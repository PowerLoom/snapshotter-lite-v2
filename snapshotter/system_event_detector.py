import json
import asyncio
import multiprocessing
import resource
import signal
import time
from signal import SIGINT
from signal import SIGQUIT
from signal import SIGTERM
import httpx
from eth_utils.address import to_checksum_address
from web3 import Web3
import sys
import os
import aiofiles
from snapshotter.processor_distributor import ProcessorDistributor
from snapshotter.settings.config import settings
from snapshotter.utils.callback_helpers import send_telegram_notification_async

from snapshotter.utils.default_logger import logger
from snapshotter.utils.file_utils import read_json_file
from snapshotter.utils.models.data_models import DailyTaskCompletedEvent
from snapshotter.utils.models.data_models import DayStartedEvent
from snapshotter.utils.models.data_models import EpochReleasedEvent
from snapshotter.utils.models.data_models import SnapshotterIssue
from snapshotter.utils.models.message_models import TelegramSnapshotterReportMessage
from snapshotter.utils.models.data_models import SnapshotterStatus
from snapshotter.utils.models.data_models import SnapshotterReportState
from snapshotter.utils.models.message_models import TelegramEpochProcessingReportMessage
from snapshotter.utils.rpc import get_event_sig_and_abi
from snapshotter.utils.rpc import RpcHelper
from urllib.parse import urljoin
from snapshotter.utils.models.data_models import SnapshotterPing
from pathlib import Path


class EventDetectorProcess(multiprocessing.Process):
    """
    A process class for detecting and handling blockchain system events.

    This class monitors the blockchain for specific events like epoch releases,
    day starts, and daily task completions. It processes these events and
    handles system shutdown gracefully. The class maintains state about processed blocks,
    handles error conditions, and provides notification capabilities.

    Attributes:
        _shutdown_initiated (bool): Flag indicating if shutdown has been initiated
        _logger (Logger): Logger instance for this process
        _last_processed_block (int): Last blockchain block that was processed
        rpc_helper (RpcHelper): Helper for RPC interactions with anchor chain
        _source_rpc_helper (RpcHelper): Helper for RPC interactions with source chain
        contract_abi (dict): Contract ABI for interacting with smart contracts
        contract_address (str): Address of the contract being monitored
        contract (Contract): Web3 contract instance
        event_sig (dict): Event signatures being monitored
        event_abi (dict): Event ABIs for decoding events
        notification_cooldown (int): Minimum time between notifications in seconds
        failure_count (int): Counter for consecutive failures
        last_status_check_time (int): Timestamp of last status check
        _initialized (bool): Flag indicating if process has been initialized
        _last_reporting_service_ping (int): Timestamp of last reporting service ping
        _last_reporting_message_sent (int): Timestamp of last reporting message
        last_notification_time (int): Timestamp of last notification sent
    """

    def __init__(self, name, **kwargs):
        """
        Initialize the EventDetectorProcess.

        Args:
            name (str): Name of the process for logging and identification
            **kwargs: Additional keyword arguments passed to multiprocessing.Process
        """
        multiprocessing.Process.__init__(self, name=name, **kwargs)
        self._shutdown_initiated = False
        self._logger = logger.bind(
            module=name,
        )

        self._last_processed_block = None

        # Initialize reporting and notification related attributes
        self._last_reporting_service_ping = 0
        self._last_reporting_message_sent = 0
        self.notification_cooldown = 300
        self.last_notification_time = 0
        self.failure_count = 0
        self.last_status_check_time = int(time.time())
        self.latest_epoch_id = - 1
        self._switch_over_completed = False
        self._initialized = False

    async def init(self):
        """
        Initialize the event detector by setting up required components and performing initial checks.
        
        This method:
        1. Initializes RPC helpers for both anchor and source chains
        2. Sets up the processor distributor
        3. Loads contract ABI and initializes contract instance
        4. Creates HTTP clients for reporting and notifications
        5. Performs initial system checks and bootstrapping
        6. Waits for required initialization periods
        
        Raises:
            Various exceptions possible during initialization steps
        """
        self.rpc_helper = RpcHelper(rpc_settings=settings.powerloom_chain_rpc)
        self.old_rpc_helper = RpcHelper(rpc_settings=settings.prost_chain_rpc)
        self._source_rpc_helper = RpcHelper(rpc_settings=settings.rpc)

        self.processor_distributor = ProcessorDistributor()

        self._logger.info('Initializing SystemEventDetector. Awaiting local collector initialization and bootstrapping for 60 seconds...')

        # Load contract ABI from settings
        self.contract_abi = read_json_file(
            settings.protocol_state.abi,
            self._logger,
        )

        self.old_contract_abi = read_json_file(
            settings.protocol_state_old.abi,
            self._logger,
        )

        # Initialize HTTP clients for reporting and Telegram notifications
        self._reporting_httpx_client = httpx.Client(
            base_url=settings.reporting.service_url,
            limits=httpx.Limits(
                max_keepalive_connections=2,
                max_connections=2,
                keepalive_expiry=300,
            ),
        )
        self._telegram_httpx_client = httpx.Client(
            base_url=settings.reporting.telegram_url,
            limits=httpx.Limits(
                max_keepalive_connections=2,
                max_connections=2,
                keepalive_expiry=300,
            ),
        )

        # Initialize contract instance
        self.contract_address = settings.protocol_state.address
        self.contract = self.rpc_helper.get_current_node()['web3_client'].eth.contract(
            address=Web3.to_checksum_address(
                self.contract_address,
            ),
            abi=self.contract_abi,
        )

        self.old_contract_address = settings.protocol_state_old.address
        self.old_contract = self.old_rpc_helper.get_current_node()['web3_client'].eth.contract(
            address=Web3.to_checksum_address(
                self.old_contract_address,
            ),
            abi=self.old_contract_abi,
        )

        with open('last_successful_submission.txt', 'w') as f:
            f.write(str(int(time.time())))

        # Define event ABIs and signatures for monitoring
        EVENTS_ABI = {
            'EpochReleased': self.contract.events.EpochReleased._get_event_abi(),
            'DayStartedEvent': self.contract.events.DayStartedEvent._get_event_abi(),
            'DailyTaskCompletedEvent': self.contract.events.DailyTaskCompletedEvent._get_event_abi(),
        }

        EVENT_SIGS = {
            'EpochReleased': 'EpochReleased(address,uint256,uint256,uint256,uint256)',
            'DayStartedEvent': 'DayStartedEvent(address,uint256,uint256)',
            'DailyTaskCompletedEvent': 'DailyTaskCompletedEvent(address,address,uint256,uint256,uint256)',
        }

        self.event_sig, self.event_abi = get_event_sig_and_abi(
            EVENT_SIGS,
            EVENTS_ABI,
        )

        current_epoch = self.old_contract.functions.currentEpoch(settings.old_data_market).call()
        self._logger.info('Current epoch: {}', current_epoch)

        self.latest_epoch_id = min(current_epoch[2], settings.switch_rpc_at_epoch_id)

        await self.processor_distributor.init()
        # TODO: introduce setting to control simulation snapshot submission if the node has been bootstrapped earlier
        self._logger.info('Initializing SystemEventDetector. Awaiting local collector initialization and bootstrapping for 60 seconds...')
        await self._init_check_and_report()
        await asyncio.sleep(60)

    async def _get_protocol_state_contract(self, current_epoch_id: int):
        """
        Get the protocol state contract instance.

        This method returns the protocol state contract instance based on the current node.

        Args:
            current_epoch_id (int): The current epoch ID

        Returns:
            Contract: The protocol state contract instance
        """
        if current_epoch_id >= settings.switch_rpc_at_epoch_id:
            self._logger.info('Using new RPC for protocol state contract')
            return self.contract
        else:
            self._logger.info('Using old RPC for protocol state contract')
            return self.old_contract

    async def _init_check_and_report(self):
        """
        Perform initial system check and report status.
        
        This method simulates an epoch release event to verify system functionality.
        It creates a test event using the current block number and attempts to process it.
        If the simulation fails, it sends a notification and exits the process.
        
        Raises:
            SystemExit: If simulation event processing fails
            Exception: Various exceptions possible during event processing
        """
        try:
            self._logger.info('Checking and reporting snapshotter status')
            current_block_number = await self._source_rpc_helper.get_current_block_number()

            event = EpochReleasedEvent(
                begin=current_block_number - 9,
                end=current_block_number,
                epochId=0,
                timestamp=int(time.time()),
            )

            self._logger.info(
                'Processing simulation event: {}', event,
            )
            await self.processor_distributor.process_event(
                "EpochReleased", event,
            )
        except Exception as e:
            self._logger.error(
                '❌ Simulation event processing failed! Error: {}', e,
            )
            self._logger.info("Please check your config and if issue persists please reach out to the team!")
            await self._send_telegram_epoch_processing_notification(
                error=e,
            )
            sys.exit(1)

    async def get_events(self, from_block: int, to_block: int):
        """
        Retrieves and filters blockchain events for the given block range.

        This method fetches events from the blockchain and processes them based on event type.
        It filters events based on data market address and snapshotter instance settings.

        Args:
            from_block (int): Starting block number to fetch events from
            to_block (int): Ending block number to fetch events to

        Returns:
            List[Tuple[str, Any]]: List of tuples containing event name and processed event data.
                Each tuple contains:
                - Event name (str): Name of the event (EpochReleased/DayStartedEvent/DailyTaskCompletedEvent)
                - Event data (object): Processed event data object specific to the event type

        Raises:
            Various exceptions possible during RPC calls and event processing
        """
        # Determine which contract to use based on latest epoch ID
        contract = await self._get_protocol_state_contract(self.latest_epoch_id)
        
        # Get the appropriate RPC helper based on the contract
        rpc_helper = self.rpc_helper if contract == self.contract else self.old_rpc_helper
        
        # Log the contract address being used for debugging
        self._logger.info('Using contract address: {} for event detection', contract.address)
        
        # Fetch events from the blockchain
        events_log = await rpc_helper.get_events_logs(
            **{
                'contract_address': contract.address,
                'to_block': to_block,
                'from_block': from_block,
                'topics': [self.event_sig],
                'event_abi': self.event_abi,
            },
        )
        
        self._logger.info('Found {} events in blocks {} to {}', len(events_log), from_block, to_block)
        self._logger.debug('Raw events: {}', events_log)
        
        events = []
        for log in events_log:
            if log.event == 'EpochReleased':
                data_market_address = await self._get_data_market_address()
                self._logger.info(f"EpochReleased event found: {log.args.dataMarketAddress}, comparing with {data_market_address}")
                
                if log.args.dataMarketAddress.lower() == data_market_address.lower():
                    self._logger.info(f"EpochReleased event matched for our data market! Epoch ID: {log.args.epochId}")
                    event = EpochReleasedEvent(
                        begin=log.args.begin,
                        end=log.args.end,
                        epochId=log.args.epochId,
                        timestamp=log.args.timestamp,
                    )
                    self.latest_epoch_id = max(self.latest_epoch_id, log.args.epochId)
                    events.append((log.event, event))
                else:
                    self._logger.info(f"Skipping EpochReleased event for different data market: {log.args.dataMarketAddress}")

            elif log.event == 'DayStartedEvent':
                self._logger.info(f"DayStartedEvent found: Day ID {log.args.dayId}")
                event = DayStartedEvent(
                    dayId=log.args.dayId,
                    timestamp=log.args.timestamp,
                )
                events.append((log.event, event))
                
            elif log.event == 'DailyTaskCompletedEvent':
                snapshotter_address = to_checksum_address(settings.instance_id)
                self._logger.info(f"DailyTaskCompletedEvent found: Snapshotter {log.args.snapshotterAddress}, Slot {log.args.slotId}")
                
                if log.args.snapshotterAddress == snapshotter_address and log.args.slotId == settings.slot_id:
                    self._logger.info(f"DailyTaskCompletedEvent matched for our snapshotter and slot! Day ID: {log.args.dayId}")
                    event = DailyTaskCompletedEvent(
                        dayId=log.args.dayId,
                        timestamp=log.args.timestamp,
                    )
                    events.append((log.event, event))
                else:
                    self._logger.info(f"Skipping DailyTaskCompletedEvent for different snapshotter/slot")

        self._logger.info('Filtered events to process: {}', events)
        return events

    def _generic_exit_handler(self, signum, sigframe):
        """
        Generic signal handler for graceful process shutdown.

        This handler manages the cleanup process when the application receives
        termination signals. It ensures resources are properly released and
        ongoing tasks are cancelled.

        Args:
            signum (int): Signal number received
            sigframe (object): Current stack frame when signal was received

        Note:
            Handles SIGINT, SIGTERM, and SIGQUIT signals
            Ensures only one shutdown process runs at a time
            Forces exit after cleanup using os._exit()
        """
        if (
            signum in [SIGINT, SIGTERM, SIGQUIT] and
            not self._shutdown_initiated
        ):
            self._shutdown_initiated = True
            self._logger.info(f"Received signal {signal.Signals(signum).name}, initiating shutdown...")
            
            try:
                # Cancel all running tasks
                for task in asyncio.all_tasks(self.ev_loop):
                    task.cancel()
                # Clean up resources with timeout
                if hasattr(self, '_reporting_httpx_client'):
                    self._reporting_httpx_client.close()
                if hasattr(self, '_telegram_httpx_client'):
                    self._telegram_httpx_client.close()
                self.ev_loop.stop()
                
            except Exception as e:
                self._logger.error(f"Error during shutdown: {e}")
            finally:
                os._exit(0)

    async def check_last_submission(self):
        """
        Monitor and verify the health of snapshot submissions.
        
        This method checks when the last successful submission occurred and handles any issues:
        - Tracks consecutive failures and exits if too many occur
        - Reads timestamp of last successful submission
        - Sends notifications if submissions are overdue
        - Manages cooldown periods between notifications
        - Updates failure counts and status check timers
        
        The method considers a submission overdue if more than 5 minutes have passed
        since the last successful submission.

        Raises:
            SystemExit: If failure count reaches threshold (3)
            Various exceptions possible during file operations and notifications
        """
        try:
            if self.latest_epoch_id == settings.switch_rpc_at_epoch_id:
                self._logger.info("skipping last submission check until first epoch is detected on the new chain!")
                self.last_status_check_time = int(time.time())
                return

            if self.failure_count >= 3:
                self._logger.error('Too many failures, exiting...')
                sys.exit(1)

            submission_file = Path('last_successful_submission.txt')
            current_time = int(time.time())

            if current_time - self.last_status_check_time < 120:
                self._logger.info('Waiting for 2 minutes before checking last submission...')
                return
            else:
                self._logger.info('Checking last submission...., current failure count: {}', self.failure_count)

            if not submission_file.exists():
                self.failure_count += 1
                self.last_status_check_time = current_time
                return
            try:
                async with aiofiles.open(submission_file, mode='r') as f:
                    content = await f.read()
                    last_timestamp = int(content.strip())
            except (ValueError, IOError) as e:
                self._logger.error('Error reading submission file: {}', e)
                self.failure_count += 1
                self.last_status_check_time = current_time
                return

            # If more than 5 minutes have passed since last submission
            if current_time - last_timestamp > 300:
                self._logger.error(
                    'No successful submission in the last 5 minutes. Last submission: {}',
                    time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_timestamp))
                )
                self.failure_count += 1
                self.last_status_check_time = current_time

                # Only send notification if cooldown has elapsed
                if (current_time - self.last_notification_time) >= self.notification_cooldown and \
                    (settings.reporting.telegram_url and settings.reporting.telegram_chat_id):

                    try:
                        # Reuse existing client from app state
                        if not self._telegram_httpx_client:
                            self._logger.error('Telegram client not initialized')
                            return

                        notification_message = SnapshotterIssue(
                            instanceID=settings.instance_id,
                            issueType=SnapshotterReportState.UNHEALTHY_EPOCH_PROCESSING.value,
                            projectID='',
                            epochId='',
                            timeOfReporting=str(current_time),
                            extra=json.dumps({
                                'issueDetails': f'No successful submission in the last 5 minutes. Last submission: {time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(last_timestamp))}'
                            }, separators=(',', ':'))  # Minimize JSON size
                        )

                        telegram_message = TelegramEpochProcessingReportMessage(
                            chatId=settings.reporting.telegram_chat_id,
                            slotId=settings.slot_id,
                            issue=notification_message,
                        )

                        await send_telegram_notification_async(
                            client=self._telegram_httpx_client,
                            message=telegram_message,
                        )
                        self.last_notification_time = current_time

                    except Exception as e:
                        self._logger.error('Error sending Telegram notification: {}', e)

            else:
                self._logger.info(
                    'Last submission was successful within the last 5 minutes. Last submission: {}',
                    time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_timestamp))
                )
                self.failure_count = 0
        except Exception as e:
            self._logger.error('Error checking last submission: {}', e)
            self.failure_count += 1
            self.last_status_check_time = int(time.time())

        self.last_status_check_time = current_time
    
    async def _get_data_market_address(self):
        """
        Get the data market address based on the current epoch ID.

        This method returns the data market address based on the current epoch ID.
        If the current epoch ID is greater than the switch RPC at epoch ID, it returns the data market address from the new RPC.
        Otherwise, it returns the data market address from the old RPC.
        """
        if self.latest_epoch_id >= settings.switch_rpc_at_epoch_id:
            return settings.data_market
        else:
            return settings.old_data_market

    async def _get_current_block_number(self):
        """
        Get the current block number from the appropriate RPC helper based on latest epoch ID.

        This method returns the current block number from the appropriate RPC helper based on latest epoch ID.
        
        """
        if self.latest_epoch_id >= settings.switch_rpc_at_epoch_id:
            if self.latest_epoch_id == settings.switch_rpc_at_epoch_id and not self._switch_over_completed:
                self._last_processed_block = None
                self._logger.info('Initializing last processed block to {}', self._last_processed_block)
                #  send simulation again
                self._logger.info("Switching to new RPC, sending simulation again")
                await self._init_check_and_report()
                await asyncio.sleep(10)
                self._switch_over_completed = True
            return await self.rpc_helper.get_current_block_number()
        else:
            return await self.old_rpc_helper.get_current_block_number()

    async def _detect_events(self):
        """
        Main event detection loop that continuously monitors the blockchain for new events.

        This method:
        1. Initializes the detector if not already done
        2. Periodically pings reporting service to indicate active status
        3. Fetches and processes new blocks since last processed block
        4. Handles event detection and distribution to processors
        5. Manages error conditions and recovery
        6. Implements configurable polling intervals
        
        The method maintains state about the last processed block and ensures
        proper error handling and notification in case of issues.

        Raises:
            Various exceptions possible during RPC calls and event processing
        """
        if not self._initialized:
            await self.init()
            self._initialized = True

        while True:
            current_time = int(time.time())
            if current_time - self.last_status_check_time > 120:
                await self.check_last_submission()
            try:
                if settings.reporting.service_url and int(time.time()) - self._last_reporting_service_ping >= 30:
                    self._last_reporting_service_ping = int(time.time())
                    try:
                        response = self._reporting_httpx_client.post(
                            url=urljoin(settings.reporting.service_url, '/ping'),
                            json=SnapshotterPing(
                                instanceID=settings.instance_id,
                                slotId=settings.slot_id,
                                dataMarketAddress=await self._get_data_market_address(),
                                namespace=settings.namespace,
                                nodeVersion=settings.node_version,
                            ).dict(),
                        )
                        response.raise_for_status()
                    except Exception as e:
                        if settings.logs.trace_enabled:
                            self._logger.opt(exception=True).error('Error while pinging reporting service: {}', e)
                        else:
                            self._logger.error(
                                'Error while pinging reporting service: {}', e,
                            )
                    else:
                        self._logger.info('Reporting service pinged successfully')

                # Get current block from the appropriate RPC helper based on latest epoch
                current_block = await self._get_current_block_number()
                
                self._logger.info('Current block: {}, Latest epoch ID: {}', current_block, self.latest_epoch_id)

            except Exception as e:
                self._logger.opt(exception=True).error(
                    (
                        'Unable to fetch current block, ERROR: {}, '
                        'sleeping for {} seconds.'
                    ),
                    e,
                    settings.rpc.polling_interval,
                )

                if int(time.time()) - self._last_reporting_message_sent >= 600:
                    self._last_reporting_message_sent = int(time.time())
                    await self._send_telegram_epoch_processing_notification(
                        error=e,
                    )

                await asyncio.sleep(settings.rpc.polling_interval)
                continue

            if not self._last_processed_block:
                self._last_processed_block = current_block - 1

            if self._last_processed_block >= current_block:
                self._logger.info(
                    'Last processed block {} is up to date, sleeping for {} seconds...',
                    self._last_processed_block,
                    settings.rpc.polling_interval,
                )
                await asyncio.sleep(settings.rpc.polling_interval)
                continue

            if current_block - self._last_processed_block >= 10:
                self._logger.warning(
                    'Last processed block is too far behind current block, '
                    'processing current block',
                )
                self._last_processed_block = current_block - 10

            # Get events from current block to last_processed_block
            try:
                events = await self.get_events(self._last_processed_block + 1, current_block)
            except Exception as e:
                self._logger.opt(exception=True).error(
                    (
                        'Unable to fetch events from block {} to block {}, '
                        'ERROR: {}, sleeping for {} seconds.'
                    ),
                    self._last_processed_block + 1,
                    current_block,
                    e,
                    settings.rpc.polling_interval,
                )

                if int(time.time()) - self._last_reporting_message_sent >= 600:
                    self._last_reporting_message_sent = int(time.time())
                    await self._send_telegram_epoch_processing_notification(
                        error=e,
                    )

                await asyncio.sleep(settings.rpc.polling_interval)
                continue

            for event_type, event in events:
                self._logger.info(
                    'Processing event: {}', event,
                )
                asyncio.ensure_future(
                    self.processor_distributor.process_event(
                        event_type, event,
                    ),
                )

            self._last_processed_block = current_block
            self._logger.info(
                'DONE: Processed blocks till {}',
                current_block,
            )
            self._logger.info(
                'Sleeping for {} seconds...',
                settings.rpc.polling_interval,
            )
            await asyncio.sleep(settings.rpc.polling_interval)

    async def _send_telegram_epoch_processing_notification(
        self,
        error: Exception,
    ):
        """
        Send a Telegram notification about epoch processing errors.

        This method constructs and sends a detailed error notification via Telegram
        when epoch processing encounters issues. The notification includes instance
        details, error information, and current status.

        Args:
            error (Exception): The error that occurred during processing

        Raises:
            Various exceptions possible during HTTP requests
        """
        telegram_message = TelegramEpochProcessingReportMessage(
            chatId=settings.reporting.telegram_chat_id,
            slotId=settings.slot_id,
            issue=SnapshotterIssue(
                instanceID=settings.instance_id,
                issueType=SnapshotterReportState.UNHEALTHY_EPOCH_PROCESSING.value,
                projectID='',
                epochId='',
                timeOfReporting=str(time.time()),
                extra=json.dumps({'issueDetails': f'Error : {error}'}),
            ),
        )
        await send_telegram_notification_async(
            client=self._telegram_httpx_client,
            message=telegram_message,
        )
    
    def run(self):
        """
        Main entry point for the event detector process.
        
        This method:
        1. Sets up system resource limits for file descriptors
        2. Configures signal handlers for graceful shutdown
        3. Initializes and runs the event detection loop
        4. Handles fatal errors and process termination
        
        The method ensures proper cleanup on exit and maintains
        process stability during runtime.

        Raises:
            SystemExit: On fatal errors in the event loop
            Various exceptions possible during initialization and runtime
        """
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        resource.setrlimit(
            resource.RLIMIT_NOFILE,
            (settings.rlimit.file_descriptors, hard),
        )
        
        # Set up signal handlers
        signal.signal(signal.SIGTERM, self._generic_exit_handler)
        signal.signal(signal.SIGINT, self._generic_exit_handler)
        signal.signal(signal.SIGQUIT, self._generic_exit_handler)

        self.ev_loop = asyncio.get_event_loop()

        try:
            self._logger.info("Starting event detection loop")
            self.ev_loop.run_until_complete(
                self._detect_events(),
            )
        except Exception as e:
            self._logger.error(f"Fatal error in event loop: {e}")
            os._exit(1)


if __name__ == '__main__':
    event_detector = EventDetectorProcess('EventDetector')
    event_detector.run()
