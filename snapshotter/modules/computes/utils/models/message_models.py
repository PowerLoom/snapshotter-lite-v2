from typing import Dict
from typing import List
from unittest.mock import Base

from pydantic import BaseModel


class EpochBaseSnapshot(BaseModel):
    begin: int
    end: int


class SnapshotBase(BaseModel):
    contract: str
    chainHeightRange: EpochBaseSnapshot
    timestamp: int


class UniswapPairTotalReservesSnapshot(SnapshotBase):
    token0Reserves: Dict[
        str,
        float,
    ]  # block number to corresponding total reserves
    token1Reserves: Dict[
        str,
        float,
    ]  # block number to corresponding total reserves
    token0ReservesUSD: Dict[str, float]
    token1ReservesUSD: Dict[str, float]
    token0Prices: Dict[str, float]
    token1Prices: Dict[str, float]


class logsTradeModel(BaseModel):
    logs: List
    trades: Dict[str, float]


class UniswapTradeEvents(BaseModel):
    Swap: logsTradeModel
    Mint: logsTradeModel
    Burn: logsTradeModel
    Trades: Dict[str, float]


class UniswapTradesSnapshot(SnapshotBase):
    totalTrade: float  # in USD
    totalFee: float  # in USD
    token0TradeVolume: float  # in token native decimals supply
    token1TradeVolume: float  # in token native decimals supply
    token0TradeVolumeUSD: float
    token1TradeVolumeUSD: float
    events: UniswapTradeEvents


class MonitoredPairsSnapshot(BaseModel):
    pairs: List[str] = []
