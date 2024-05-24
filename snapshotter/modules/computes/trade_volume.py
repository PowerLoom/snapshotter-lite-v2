import time

from ipfs_client.main import AsyncIPFSClient
from snapshotter.settings.config import settings
from snapshotter.utils.callback_helpers import GenericProcessor
from snapshotter.utils.default_logger import logger
from snapshotter.utils.models.message_models import SnapshotProcessMessage
from snapshotter.utils.rpc import RpcHelper

from .settings.config import settings as module_settings
from .utils.core import get_pair_trade_volume
from .utils.models.message_models import EpochBaseSnapshot
from .utils.models.message_models import UniswapTradesSnapshot


class TradeVolumeProcessor(GenericProcessor):

    def __init__(self) -> None:
        self._logger = logger.bind(module='TradeVolumeProcessor')

    async def _compute_single(
        self,
        data_source_contract_address: str,
        min_chain_height: int,
        max_chain_height: int,
        rpc_helper: RpcHelper,
        eth_price_dict: dict,
    ):
        result = await get_pair_trade_volume(
            data_source_contract_address=data_source_contract_address,
            min_chain_height=min_chain_height,
            max_chain_height=max_chain_height,
            rpc_helper=rpc_helper,
            eth_price_dict=eth_price_dict,
        )
        self._logger.debug(f'trade volume {data_source_contract_address}, computation end time {time.time()}')

        # Set effective trade volume at top level
        total_trades_in_usd = result['Trades'][
            'totalTradesUSD'
        ]
        total_fee_in_usd = result['Trades']['totalFeeUSD']
        total_token0_vol = result['Trades'][
            'token0TradeVolume'
        ]
        total_token1_vol = result['Trades'][
            'token1TradeVolume'
        ]
        total_token0_vol_usd = result['Trades'][
            'token0TradeVolumeUSD'
        ]
        total_token1_vol_usd = result['Trades'][
            'token1TradeVolumeUSD'
        ]

        max_block_timestamp = result.get('timestamp')
        result.pop('timestamp', None)
        trade_volume_snapshot = UniswapTradesSnapshot(
            contract=data_source_contract_address,
            chainHeightRange=EpochBaseSnapshot(begin=min_chain_height, end=max_chain_height),
            timestamp=max_block_timestamp,
            totalTrade=float(f'{total_trades_in_usd: .6f}'),
            totalFee=float(f'{total_fee_in_usd: .6f}'),
            token0TradeVolume=float(f'{total_token0_vol: .6f}'),
            token1TradeVolume=float(f'{total_token1_vol: .6f}'),
            token0TradeVolumeUSD=float(f'{total_token0_vol_usd: .6f}'),
            token1TradeVolumeUSD=float(f'{total_token1_vol_usd: .6f}'),
            events=result,
        )

        return trade_volume_snapshot

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

        self._logger.debug(f'trade volume, computation init time {time.time()}')

        pair_idx = self._gen_pair_idx_to_compute(msg_obj)
        data_source_contract_address = monitored_pairs[pair_idx]

        snapshot = await self._compute_single(
            data_source_contract_address=data_source_contract_address,
            min_chain_height=min_chain_height,
            max_chain_height=max_chain_height,
            rpc_helper=rpc_helper,
            eth_price_dict=eth_price_dict,
        )

        self._logger.debug(f'trade volume, computation end time {time.time()}')

        return [(data_source_contract_address, snapshot)]
