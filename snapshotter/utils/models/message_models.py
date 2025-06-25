from typing import Dict
from typing import List
from typing import Optional
from typing import Union

from pydantic import BaseModel
from pydantic import Field

from snapshotter.utils.models.data_models import SnapshotterIssue
from snapshotter.utils.models.data_models import SnapshotterStatus


class TxLogsModel(BaseModel):
    logIndex: str
    blockNumber: str
    blockHash: str
    transactionHash: str
    transactionIndex: str
    address: str
    data: str
    topics: List[str]


class EthTransactionReceipt(BaseModel):
    transactionHash: str
    transactionIndex: str
    blockHash: str
    blockNumber: str
    from_field: str = Field(..., alias='from')
    to: Optional[str]
    cumulativeGasUsed: str
    gasUsed: str
    effectiveGasPrice: str
    logs: List[TxLogsModel]
    contractAddress: Optional[str] = None
    logsBloom: str
    status: str
    type: Optional[str]
    root: Optional[str]


class EpochBase(BaseModel):
    epochId: int
    begin: int
    end: int
    day: int


class SnapshotProcessMessage(EpochBase):
    genesis: Optional[bool] = False


class SnapshotFinalizedMessage(BaseModel):
    epochId: int
    projectId: str
    snapshotCid: str
    timestamp: int


class SnapshotSubmittedMessage(BaseModel):
    snapshotCid: str
    epochId: int
    projectId: str
    timestamp: int


class SnapshotSubmittedMessageLite(BaseModel):
    snapshotCid: str
    projectId: str


class ProjectTypeProcessingCompleteMessage(BaseModel):
    epochId: int
    projectType: str
    snapshotsSubmitted: List[SnapshotSubmittedMessageLite]


class ProcessHubCommand(BaseModel):
    command: str
    pid: Optional[int] = None
    proc_str_id: Optional[str] = None
    init_kwargs: Optional[Dict] = dict()


# Legacy Telegram message models (kept for backward compatibility)
class TelegramMessage(BaseModel):
    chatId: str
    slotId: int


class TelegramEpochProcessingReportMessage(TelegramMessage):
    issue: SnapshotterIssue


class TelegramSnapshotterReportMessage(TelegramMessage):
    issue: SnapshotterIssue
    status: SnapshotterStatus


class ZapierWebhookMessage(BaseModel):
    instanceID: str
    issueType: str
    projectID: str
    epochId: Union[int, str]
    timeOfReporting: str
    slotId: int
    status: Optional[SnapshotterStatus] = None
    issue: str
    chatId: Optional[str] = None
    service: str = "telegram"


class WebhookReportMessage(BaseModel):
    """Generic webhook message that can be used for various reporting services"""
    instanceID: str
    issueType: str
    projectID: str
    epochId: Union[int, str]
    timeOfReporting: str
    slotId: int
    status: Optional[SnapshotterStatus] = None
    issue: str
    chatId: Optional[str] = None
    service: str