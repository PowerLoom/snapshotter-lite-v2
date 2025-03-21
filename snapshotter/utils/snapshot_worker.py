import importlib
from typing import Optional

from ipfs_client.main import AsyncIPFSClient
from ipfs_client.main import AsyncIPFSClientSingleton

from snapshotter.settings.config import projects_config
from snapshotter.settings.config import settings
from snapshotter.utils.data_utils import get_snapshot_submision_window
from snapshotter.utils.generic_worker import GenericAsyncWorker
from snapshotter.utils.models.message_models import SnapshotProcessMessage


class SnapshotAsyncWorker(GenericAsyncWorker):
    _ipfs_singleton: AsyncIPFSClientSingleton
    _ipfs_writer_client: AsyncIPFSClient
    _ipfs_reader_client: AsyncIPFSClient

    def __init__(self):
        """
        Initializes a SnapshotAsyncWorker object.

        Args:
            name (str): The name of the worker.
            **kwargs: Additional keyword arguments to be passed to the AsyncWorker constructor.
        """
        self._project_calculation_mapping = {}
        super().__init__()
        self._task_types = []
        for project_config in projects_config:
            task_type = project_config.project_type
            self._task_types.append(task_type)
        self._submission_window = 0

    def _gen_project_id(self, task_type: str, data_source: Optional[str] = None, primary_data_source: Optional[str] = None):
        """
        Generates a project ID based on the given task type, data source, and primary data source.

        Args:
            task_type (str): The type of task.
            data_source (Optional[str], optional): The data source. Defaults to None.
            primary_data_source (Optional[str], optional): The primary data source. Defaults to None.

        Returns:
            str: The generated project ID.
        """
        if not data_source:
            # For generic use cases that don't have a data source like block details
            project_id = f'{task_type}:{settings.namespace}'
        else:
            if primary_data_source:
                project_id = f'{task_type}:{primary_data_source.lower()}_{data_source.lower()}:{settings.namespace}'
            else:
                project_id = f'{task_type}:{data_source.lower()}:{settings.namespace}'
        return project_id

    async def _process(self, msg_obj: SnapshotProcessMessage, task_type: str, preloader_results: dict):
        """
        Processes the given SnapshotProcessMessage object in bulk mode.

        Args:
            msg_obj (SnapshotProcessMessage): The message object to process.
            task_type (str): The type of task to perform.

        Raises:
            Exception: If an error occurs while processing the message.

        Returns:
            None
        """
        try:
            task_processor = self._project_calculation_mapping[task_type]
            
            snapshots = await task_processor.compute(
                msg_obj=msg_obj,
                rpc_helper=self._rpc_helper,
                anchor_rpc_helper=self._anchor_rpc_helper,
                ipfs_reader=self._ipfs_reader_client,
                protocol_state_contract=self.protocol_state_contract,
                preloader_results=preloader_results,
            )

            if not snapshots:
                self.logger.debug(
                    'No snapshot data for: {}, skipping...', msg_obj,
                )

        except Exception as e:
            self.logger.opt(exception=True).error(
                'Exception processing callback for epoch: {}, Error: {},'
                'sending failure notifications', msg_obj, e,
            )

            self.status.totalMissedSubmissions += 1
            self.status.consecutiveMissedSubmissions += 1

            await self._send_failure_notifications(
                error=e,
                epoch_id=str(msg_obj.epochId),
                project_id=self._gen_project_id(
                    task_type=task_type,
                ),
            )
        else:

            if not snapshots:
                self.logger.debug(
                    'No snapshot data for: {}, skipping...', msg_obj,
                )
                return

            for project_data_source, snapshot in snapshots:
                data_sources = project_data_source.split('_')
                if len(data_sources) == 1:
                    data_source = data_sources[0]
                    primary_data_source = None
                else:
                    primary_data_source, data_source = data_sources

                project_id = self._gen_project_id(
                    task_type=task_type, data_source=data_source, primary_data_source=primary_data_source,
                )
                await self._commit_payload(
                    task_type=task_type,
                    _ipfs_writer_client=self._ipfs_writer_client,
                    project_id=project_id,
                    epoch=msg_obj,
                    snapshot=snapshot,
                    storage_flag=settings.web3storage.upload_snapshots,
                )

    async def process_task(self, msg_obj: SnapshotProcessMessage, task_type: str, preloader_results: dict):
        """
        Process a SnapshotProcessMessage object for a given task type.

        Args:
            msg_obj (SnapshotProcessMessage): The message object to process.
            task_type (str): The type of task to perform.

        Returns:
            None
        """
        self.logger.debug(
            'Processing callback: {}', msg_obj,
        )
        if task_type not in self._project_calculation_mapping:
            self.logger.error(
                (
                    'No project calculation mapping found for task type'
                    f' {task_type}. Skipping...'
                ),
            )
            return

        if not self._submission_window:
            self._submission_window = await get_snapshot_submision_window(
                rpc_helper=self._old_anchor_rpc_helper,
                state_contract_obj=self.protocol_state_old_contract,
                data_market=settings.old_data_market,
            )

        self.logger.debug(
            'Got epoch to process for {}: {}',
            task_type, msg_obj,
        )

        await self._process(
            msg_obj=msg_obj,
            task_type=task_type,
            preloader_results=preloader_results,
        )

    async def _init_project_calculation_mapping(self):
        """
        Initializes the project calculation mapping by generating a dictionary that maps project types to their corresponding
        calculation classes.

        Raises:
            Exception: If a duplicate project type is found in the projects configuration.
        """
        if self._project_calculation_mapping != {}:
            return
        # Generate project function mapping
        self._project_calculation_mapping = dict()
        for project_config in projects_config:
            key = project_config.project_type
            if key in self._project_calculation_mapping:
                raise Exception('Duplicate project type found')
            module = importlib.import_module(project_config.processor.module)
            class_ = getattr(module, project_config.processor.class_name)
            self._project_calculation_mapping[key] = class_()

    async def _init_ipfs_client(self):
        """
        Initializes the IPFS client by creating a singleton instance of AsyncIPFSClientSingleton
        and initializing its sessions. The write and read clients are then assigned to instance variables.
        """
        self._ipfs_reader_client = None
        self._ipfs_writer_client = None
        if not settings.ipfs.url:
            return
        self._ipfs_singleton = AsyncIPFSClientSingleton(settings.ipfs)
        await self._ipfs_singleton.init_sessions()
        self._ipfs_writer_client = self._ipfs_singleton._ipfs_write_client
        self._ipfs_reader_client = self._ipfs_singleton._ipfs_read_client

    async def init_worker(self):
        """
        Initializes the worker by initializing project calculation mapping, IPFS client, and other necessary components.
        """
        if not self.initialized:
            await self._init_project_calculation_mapping()
            await self._init_ipfs_client()
            await self.init()
