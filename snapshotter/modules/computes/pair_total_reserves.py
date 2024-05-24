import time

from ipfs_client.main import AsyncIPFSClient
from snapshotter.settings.config import settings
from snapshotter.utils.callback_helpers import GenericProcessor
from snapshotter.utils.default_logger import logger
from snapshotter.utils.models.message_models import SnapshotProcessMessage
from snapshotter.utils.rpc import RpcHelper

from .settings.config import settings as module_settings
from .utils.core import get_pair_reserves
from .utils.models.message_models import EpochBaseSnapshot
from .utils.models.message_models import UniswapPairTotalReservesSnapshot


class PairTotalReservesProcessor(GenericProcessor):

    def __init__(self) -> None:
        self._logger = logger.bind(module='PairTotalReservesProcessor')

    async def _compute_single(
        self,
        data_source_contract_address: str,
        min_chain_height: int,
        max_chain_height: int,
        rpc_helper: RpcHelper,
        eth_price_dict: dict,
    ):
        epoch_reserves_snapshot_map_token0 = dict()
        epoch_prices_snapshot_map_token0 = dict()
        epoch_prices_snapshot_map_token1 = dict()
        epoch_reserves_snapshot_map_token1 = dict()
        epoch_usd_reserves_snapshot_map_token0 = dict()
        epoch_usd_reserves_snapshot_map_token1 = dict()
        max_block_timestamp = int(time.time())

        pair_reserve_total = await get_pair_reserves(
            pair_address=data_source_contract_address,
            from_block=min_chain_height,
            to_block=max_chain_height,
            rpc_helper=rpc_helper,
            eth_price_dict=eth_price_dict,
        )

        for block_num in range(min_chain_height, max_chain_height + 1):
            block_pair_total_reserves = pair_reserve_total.get(block_num)

            epoch_reserves_snapshot_map_token0[
                f'block{block_num}'
            ] = block_pair_total_reserves['token0']
            epoch_reserves_snapshot_map_token1[
                f'block{block_num}'
            ] = block_pair_total_reserves['token1']
            epoch_usd_reserves_snapshot_map_token0[
                f'block{block_num}'
            ] = block_pair_total_reserves['token0USD']
            epoch_usd_reserves_snapshot_map_token1[
                f'block{block_num}'
            ] = block_pair_total_reserves['token1USD']

            epoch_prices_snapshot_map_token0[
                f'block{block_num}'
            ] = block_pair_total_reserves['token0Price']

            epoch_prices_snapshot_map_token1[
                f'block{block_num}'
            ] = block_pair_total_reserves['token1Price']

            
            if not block_pair_total_reserves.get('timestamp', None):
                self._logger.error(
                    (
                        'Could not fetch timestamp against max block'
                        ' height in epoch {} - {}to calculate pair'
                        ' reserves for contract {}. Using current time'
                        ' stamp for snapshot construction'
                    ),
                    data_source_contract_address,
                    min_chain_height,
                    max_chain_height,
                )
            else:
                max_block_timestamp = block_pair_total_reserves.get(
                    'timestamp',
                )

        pair_total_reserves_snapshot = UniswapPairTotalReservesSnapshot(
            **{
                'token0Reserves': epoch_reserves_snapshot_map_token0,
                'token1Reserves': epoch_reserves_snapshot_map_token1,
                'token0ReservesUSD': epoch_usd_reserves_snapshot_map_token0,
                'token1ReservesUSD': epoch_usd_reserves_snapshot_map_token1,
                'token0Prices': epoch_prices_snapshot_map_token0,
                'token1Prices': epoch_prices_snapshot_map_token1,
                'chainHeightRange': EpochBaseSnapshot(
                    begin=min_chain_height, end=max_chain_height,
                ),
                'timestamp': max_block_timestamp,
                'contract': data_source_contract_address,
            },
        )
        return pair_total_reserves_snapshot

    def _gen_pair_idx_to_compute(self, msg_obj: SnapshotProcessMessage):
        monitored_pairs = module_settings.initial_pairs
        current_epoch = msg_obj.epochId
        snapshotter_hash = hash(int(settings.instance_id.lower(), 16))
        current_day = msg_obj.day
        return (current_epoch + snapshotter_hash + settings.slot_id + current_day) % len(monitored_pairs)

    async def compute(
        self,
        msg_obj: SnapshotProcessMessage,
        rpc_helper: RpcHelper,
        anchor_rpc_helper: RpcHelper,
        ipfs_reader: AsyncIPFSClient,
        protocol_state_contract,
        eth_price_dict: dict,
    ):

        min_chain_height = msg_obj.begin
        max_chain_height = msg_obj.end

        monitored_pairs = module_settings.initial_pairs
        self._logger.debug(f'pair reserves computation init time {time.time()}')

        pair_idx = self._gen_pair_idx_to_compute(msg_obj)
        data_source_contract_address = monitored_pairs[pair_idx]

        snapshot = await self._compute_single(
            data_source_contract_address=data_source_contract_address,
            min_chain_height=min_chain_height,
            max_chain_height=max_chain_height,
            rpc_helper=rpc_helper,
            eth_price_dict=eth_price_dict,
        )

        self._logger.debug(f'pair reserves, computation end time {time.time()}')

        return [(data_source_contract_address, snapshot)]
