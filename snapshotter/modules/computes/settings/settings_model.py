from typing import List
from typing import Dict
from typing import Any
from pydantic import BaseModel
from pydantic import Field


class UniswapContractAbis(BaseModel):
    factory: str = Field(...)
    router: str = Field(...)
    pair_contract: str = Field(...)
    erc20: str = Field(...)
    trade_events: str = Field(...)


class ContractAddresses(BaseModel):
    iuniswap_v2_factory: str = Field(...)
    iuniswap_v2_router: str = Field(...)
    MAKER: str = Field(...)
    USDT: str = Field(...)
    DAI: str = Field(...)
    USDC: str = Field(...)
    WETH: str = Field(...)
    WETH_USDT: str = Field(...)
    FRAX: str = Field(...)
    SYN: str = Field(...)
    FEI: str = Field(...)
    agEUR: str = Field(...)
    DAI_WETH_PAIR: str = Field(...)
    USDC_WETH_PAIR: str = Field(...)
    USDT_WETH_PAIR: str = Field(...)


class Settings(BaseModel):
    uniswap_contract_abis: UniswapContractAbis
    contract_addresses: ContractAddresses
    uniswap_v2_whitelist: List[str]
    initial_pairs: List[str]
    metadata_cache: Dict[str, Any]
    static_pairs: bool
