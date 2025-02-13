import asyncio
import json
import importlib
from collections import defaultdict
from typing import Union

from eth_utils.address import to_checksum_address
from httpx import AsyncClient
from httpx import AsyncHTTPTransport
from httpx import Limits
from httpx import Timeout
from web3 import Web3
import time

from snapshotter.settings.config import projects_config
from snapshotter.settings.config import settings
from snapshotter.settings.config import preloaders
from snapshotter.utils.data_utils import get_snapshot_submision_window
from snapshotter.utils.data_utils import get_source_chain_epoch_size
from snapshotter.utils.data_utils import get_source_chain_id
from snapshotter.utils.default_logger import logger
from snapshotter.utils.file_utils import read_json_file
from snapshotter.utils.models.data_models import DailyTaskCompletedEvent
from snapshotter.utils.models.data_models import DayStartedEvent
from snapshotter.utils.models.data_models import EpochReleasedEvent
from snapshotter.utils.models.data_models import PreloaderResult
from snapshotter.utils.models.data_models import SnapshotFinalizedEvent
from snapshotter.utils.models.data_models import SnapshotterIssue
from snapshotter.utils.models.data_models import SnapshotterReportState
from snapshotter.utils.models.data_models import SnapshottersUpdatedEvent
from snapshotter.utils.models.message_models import EpochBase
from snapshotter.utils.models.message_models import SnapshotProcessMessage
from snapshotter.utils.models.message_models import TelegramSnapshotterReportMessage
from snapshotter.utils.rpc import RpcHelper
from snapshotter.utils.snapshot_worker import SnapshotAsyncWorker
from snapshotter.utils.callback_helpers import send_failure_notifications_async
from snapshotter.utils.callback_helpers import send_telegram_notification_async


class ProcessorDistributor:
    _anchor_rpc_helper: RpcHelper
    _reporting_httpx_client: AsyncClient
    _telegram_httpx_client: AsyncClient

    def __init__(self):
        """
        Initialize the ProcessorDistributor object.

        Args:
            name (str): The name of the ProcessorDistributor.
            **kwargs: Additional keyword arguments.

        Attributes:
            _rpc_helper: The RPC helper object.
            _source_chain_id: The source chain ID.
            _projects_list: The list of projects.
            _initialized (bool): Flag indicating if the ProcessorDistributor has been initialized.
            _upcoming_project_changes (defaultdict): Dictionary of upcoming project changes.
            _project_type_config_mapping (dict): Dictionary mapping project types to their configurations.
        """
        self._rpc_helper = None
        self._source_chain_id = None
        self._projects_list = None
        self._initialized = False
        self._upcoming_project_changes = defaultdict(list)
        self._project_type_config_mapping = dict()
        self._preloader_compute_mapping = dict()
        self._all_preload_tasks = set()
        for project_config in projects_config:
            self._project_type_config_mapping[project_config.project_type] = project_config
            for preload_task in project_config.preload_tasks:
                self._all_preload_tasks.add(preload_task)

        self._snapshotter_enabled = True
        self._snapshotter_active = True
        self.snapshot_worker = SnapshotAsyncWorker()

        self.last_notification_time = 0
        self.notification_cooldown = 300

    async def _init_rpc_helper(self):
        """
        Initializes the RpcHelper instance if it is not already initialized.
        """
        if not self._rpc_helper:
            self._rpc_helper = RpcHelper()
            self._anchor_rpc_helper = RpcHelper(rpc_settings=settings.anchor_chain_rpc)

    async def _init_httpx_client(self):
        """
        Initializes the HTTPX clients with the specified settings.
        """
        
        transport_limits = Limits(
            max_connections=100,
            max_keepalive_connections=50,
            keepalive_expiry=None,
        )

        self._reporting_httpx_client = AsyncClient(
            base_url=settings.reporting.service_url,
            timeout=Timeout(timeout=5.0),
            follow_redirects=False,
            transport=AsyncHTTPTransport(limits=transport_limits),
        )
        self._telegram_httpx_client = AsyncClient(
            base_url=settings.reporting.telegram_url,
            timeout=Timeout(timeout=5.0),
            follow_redirects=False,
            transport=AsyncHTTPTransport(limits=transport_limits),
        )

    async def _init_preloader_compute_mapping(self):
        """
        Initializes the preloader compute mapping by importing the preloader module and class and
        adding it to the mapping dictionary.
        """
        if self._preloader_compute_mapping:
            return

        for preloader in preloaders:
            if preloader.task_type in self._all_preload_tasks:
                preloader_module = importlib.import_module(preloader.module)
                self._logger.debug('Imported preloader module: {}', preloader_module)
                preloader_class = getattr(preloader_module, preloader.class_name)
                self._preloader_compute_mapping[preloader.task_type] = preloader_class
                self._logger.debug(
                    'Imported preloader class {} against preloader module {} for task type {}',
                    preloader_class,
                    preloader_module,
                    preloader.task_type,
                )

    async def init(self):
        """
        Initializes the worker by initializing the RPC helper, loading project metadata.
        """
        if not self._initialized:

            self._logger = logger.bind(
                module='ProcessDistributor',
            )
            self._anchor_rpc_helper = RpcHelper(
                rpc_settings=settings.anchor_chain_rpc,
            )
            protocol_abi = read_json_file(settings.protocol_state.abi, self._logger)
            self._protocol_state_contract = self._anchor_rpc_helper.get_current_node()['web3_client'].eth.contract(
                address=to_checksum_address(
                    settings.protocol_state.address,
                ),
                abi=protocol_abi,
            )
            try:
                source_block_time = self._protocol_state_contract.functions.SOURCE_CHAIN_BLOCK_TIME(Web3.to_checksum_address(settings.data_market)).call()
            except Exception as e:
                self._logger.error(
                    'Exception in querying protocol state for source chain block time: {}',
                    e,
                )
            else:
                self._source_chain_block_time = source_block_time / 10 ** 4
                self._logger.debug('Set source chain block time to {}', self._source_chain_block_time)

            try:
                epoch_size = self._protocol_state_contract.functions.EPOCH_SIZE(Web3.to_checksum_address(settings.data_market)).call()
            except Exception as e:
                self._logger.error(
                    'Exception in querying protocol state for epoch size: {}',
                    e,
                )
            else:
                self._epoch_size = epoch_size

            try:
                self._current_day = self._protocol_state_contract.functions.dayCounter(Web3.to_checksum_address(settings.data_market)).call()

                task_completion_status = self._protocol_state_contract.functions.checkSlotTaskStatusForDay(
                    Web3.to_checksum_address(settings.data_market),
                    settings.slot_id,
                    self._current_day,
                ).call()
                if task_completion_status:
                    self._snapshotter_active = False
                else:
                    self._snapshotter_active = True
            except Exception as e:
                self._logger.error(
                    'Exception in querying protocol state for user task status for day {}',
                    e,
                )
                self._snapshotter_active = False
            self._logger.info('Snapshotter active: {}', self._snapshotter_active)

            await self._init_httpx_client()
            await self._init_rpc_helper()
            await self._load_projects_metadata()
            await self._init_preloader_compute_mapping()
            await self.snapshot_worker.init_worker()

            self._initialized = True

    async def _load_projects_metadata(self):
        """
        Loads the metadata for the projects, including the source chain ID, the list of projects, and the submission window
        for snapshots. It also updates the project type configuration mapping with the relevant projects.
        """
        if not self._projects_list:
            with open(settings.protocol_state.abi, 'r') as f:
                abi_dict = json.load(f)
            protocol_state_contract = self._anchor_rpc_helper.get_current_node()['web3_client'].eth.contract(
                address=Web3.to_checksum_address(
                    settings.protocol_state.address,
                ),
                abi=abi_dict,
            )
            self._source_chain_epoch_size = await get_source_chain_epoch_size(
                rpc_helper=self._anchor_rpc_helper,
                state_contract_obj=protocol_state_contract,
                data_market=Web3.to_checksum_address(settings.data_market),
            )

            self._source_chain_id = await get_source_chain_id(
                rpc_helper=self._anchor_rpc_helper,
                state_contract_obj=protocol_state_contract,
                data_market=Web3.to_checksum_address(settings.data_market),
            )

            submission_window = await get_snapshot_submision_window(
                rpc_helper=self._anchor_rpc_helper,
                state_contract_obj=protocol_state_contract,
                data_market=Web3.to_checksum_address(settings.data_market),
            )
            self._submission_window = submission_window

    async def _epoch_release_processor(self, message: EpochReleasedEvent):
        """
        This method is called when an epoch is released. It starts the snapshotting process for the epoch.

        Args:
            message (EpochBase): The message containing the epoch information.
        """

        epoch = EpochBase(
            begin=message.begin,
            end=message.end,
            epochId=message.epochId,
            day=self._current_day,
        )

        preloader_tasks = {}
        preloader_results_dict = {}
        failed_preloaders = set()

        # Use the pre-computed set of all preload tasks
        for preloader_task in self._all_preload_tasks:
            preloader_class = self._preloader_compute_mapping[preloader_task]
            preloader_obj = preloader_class()
            preloader_compute_kwargs = dict(
                epoch=epoch,
                rpc_helper=self._rpc_helper,
            )
            self._logger.debug(
                'Starting preloader obj {} for epoch {}',
                preloader_task,
                epoch.epochId,
            )
            preloader_tasks[preloader_task] = asyncio.create_task(
                preloader_obj.compute(**preloader_compute_kwargs)
            )

        await asyncio.gather(
            *preloader_tasks.values(),
            return_exceptions=True,
        )

        for preloader_task, task in preloader_tasks.items():
            try:
                result = task.result()
                if isinstance(result, PreloaderResult):
                    preloader_results_dict[preloader_task] = result.result
                else:
                    raise ValueError(
                        f"Unexpected result from preloader {preloader_task}: {result}"
                    )
            except Exception as e:
                self._logger.error(
                    'Exception in preloader {} for epoch {}: {}',
                    preloader_task,
                    epoch.epochId,
                    e,
                )
                failed_preloaders.add(preloader_task)

        # Distribute results to each project based on its requirements
        for project_type, project_config in self._project_type_config_mapping.items():
            # Check if all required preloaders for this project succeeded
            project_required_preloaders = set(project_config.preload_tasks)
            project_failed_preloaders = failed_preloaders.intersection(project_required_preloaders)
            if not project_failed_preloaders:
                project_preloader_results = {
                    task: preloader_results_dict[task]
                    for task in project_required_preloaders
                    if task in preloader_results_dict
                }
                
                asyncio.ensure_future(
                    self._distribute_callbacks_snapshotting(
                        project_type, epoch, project_preloader_results,
                    )
                )
            else:
                self._logger.warning(
                    'Skipping project type {} for epoch {} due to failed preloader tasks: {}',
                    project_type,
                    epoch.epochId,
                    project_failed_preloaders
                )

                # Update counters for each skipped project
                self.snapshot_worker.status.totalMissedSubmissions += 1
                self.snapshot_worker.status.consecutiveMissedSubmissions += 1

                await self._send_failure_notifications(
                    error=Exception(f'Failed preloaders for {project_type}: {project_failed_preloaders}'),
                    epoch_id=epoch.epochId,
                    project_id=project_type
                )

        if failed_preloaders:
            self._logger.warning(
                'Some preloader tasks failed for epoch {}: {}',
                epoch.epochId,
                failed_preloaders
            )

    async def _distribute_callbacks_snapshotting(self, project_type: str, epoch: EpochBase, preloader_results: dict):
        """
        Distributes callbacks for snapshotting to the appropriate snapshotters based on the project type and epoch.

        Args:
            project_type (str): The type of project.
            epoch (EpochBase): The epoch to snapshot.

        Returns:
            None
        """

        process_unit = SnapshotProcessMessage(
            begin=epoch.begin,
            end=epoch.end,
            epochId=epoch.epochId,
            day=epoch.day,
        )

        asyncio.ensure_future(
            self.snapshot_worker.process_task(process_unit, project_type, preloader_results),
        )

    async def process_event(
        self, type_: str, event: Union[
            EpochReleasedEvent,
            SnapshotFinalizedEvent,
            SnapshottersUpdatedEvent,
            DayStartedEvent,
            DailyTaskCompletedEvent,
        ],
    ):
        """
        Process an event based on its type.

        Args:
            type_ (str): The type of the event.
            event (Union[EpochReleasedEvent, SnapshotFinalizedEvent, SnapshottersUpdatedEvent,
            DayStartedEvent, DailyTaskCompletedEvent]): The event object.

        Returns:
            None
        """
        if type_ == 'EpochReleased':

            return await self._epoch_release_processor(event)

        elif type_ == 'DayStartedEvent':
            self._logger.info('Day started event received, setting active status to True')
            self._snapshotter_active = True
            self._current_day += 1

        elif type_ == 'DailyTaskCompletedEvent':
            self._logger.info('Daily task completed event received, setting active status to False')
            self._snapshotter_active = False

        else:
            self._logger.error(
                (
                    'Unknown message type {} received'
                ),
                type_,
            )

    async def _send_failure_notifications(
        self,
        error: Exception,
        epoch_id: str,
        project_id: str,
    ):
        if (int(time.time()) - self.last_notification_time) >= self.notification_cooldown and \
            (settings.reporting.telegram_url and settings.reporting.telegram_chat_id):

            if not self._telegram_httpx_client:
                self._logger.error('Telegram client not initialized')
                return

            try:
                notification_message = SnapshotterIssue(
                    instanceID=settings.instance_id,
                    issueType=SnapshotterReportState.MISSED_SNAPSHOT.value,
                    projectID=project_id,
                    epochId=str(epoch_id),
                    timeOfReporting=str(time.time()),
                    extra=json.dumps({'issueDetails': f'Error : {error}'}),
                )

                telegram_message = TelegramSnapshotterReportMessage(
                    chatId=settings.reporting.telegram_chat_id,
                    slotId=settings.slot_id,
                    issue=notification_message,
                    status=self.snapshot_worker.status,
                )

                await send_telegram_notification_async(
                    client=self._telegram_httpx_client,
                    message=telegram_message,
                )
                self.last_notification_time = int(time.time())

            except Exception as e:
                self._logger.error('Error sending Telegram notification: {}', e)
