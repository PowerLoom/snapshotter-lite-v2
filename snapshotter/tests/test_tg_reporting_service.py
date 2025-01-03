import asyncio
import json
import time

from httpx import AsyncClient
from httpx import AsyncHTTPTransport
from httpx import Limits
from httpx import Timeout

from snapshotter.settings.config import settings
from snapshotter.utils.callback_helpers import send_telegram_notification_async
from snapshotter.utils.default_logger import logger
from snapshotter.utils.models.data_models import SnapshotterIssue
from snapshotter.utils.models.data_models import SnapshotterReportState
from snapshotter.utils.models.data_models import SnapshotterStatus
from snapshotter.utils.models.message_models import TelegramSnapshotterReportMessage


# ensure telegram__url / telegram_chat_id are set in config/settings.json
# telegram_url endpoint needs to be active
async def test_tg_reporting_call():

    project_id = 'test_project_id'
    epoch_id = 0

    async_client = AsyncClient(
        timeout=Timeout(timeout=5.0),
        follow_redirects=False,
        transport=AsyncHTTPTransport(
            limits=Limits(
                max_connections=200,
                max_keepalive_connections=50,
                keepalive_expiry=None,
            ),
        ),
    )

    notification_message = SnapshotterIssue(
        instanceID=settings.instance_id,
        issueType=SnapshotterReportState.MISSED_SNAPSHOT.value,
        projectID=project_id,
        epochId=epoch_id,
        timeOfReporting=str(time.time()),
        extra=json.dumps({'issueDetails': f'Error : TEST ERROR MESSAGE'}),
    )

    telegram_message = TelegramSnapshotterReportMessage(
        chatId=settings.reporting.telegram_chat_id,
        slotId=settings.slot_id,
        issue=notification_message,
        status=SnapshotterStatus(
            projects=[],
            totalMissedSubmissions=1,
            consecutiveMissedSubmissions=1,
        ),
    )

    await send_telegram_notification_async(
        client=async_client, message=telegram_message,
    )

    # wait for the callback to complete
    await asyncio.sleep(5)


if __name__ == '__main__':
    try:
        asyncio.get_event_loop().run_until_complete(test_tg_reporting_call())
    except Exception as e:
        logger.opt(exception=True).error('exception: {}', e)
