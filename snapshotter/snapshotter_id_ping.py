import asyncio
import sys

from web3 import Web3

from snapshotter.settings.config import settings
from snapshotter.utils.file_utils import read_json_file


async def main():
    """
    Checks if snapshotting is allowed for the given instance ID by querying the protocol state contract.
    If snapshotting is allowed, sets the active status key in Redis to True and exits with code 0.
    If snapshotting is not allowed, sets the active status key in Redis to False and exits with code 1.
    """
    # Load protocol state ABI
    protocol_abi = read_json_file(settings.protocol_state.abi)
    print('abi file ', settings.protocol_state.abi)
    print('Contract address: ', settings.protocol_state.address)

    w3 = Web3(Web3.HTTPProvider(settings.anchor_chain_rpc.full_nodes[0].url))

    protocol_state_contract = w3.eth.contract(address=settings.protocol_state.address, abi=protocol_abi)
    # Query allowed snapshotters
    allowed_snapshotters = protocol_state_contract.functions.allSnapshotters(
        Web3.to_checksum_address(settings.instance_id)
    ).call()

    if allowed_snapshotters is True or allowed_snapshotters:
        print('Snapshotter identity found in allowed snapshotters...')
    else:
        print('Snapshotter identity not found in allowed snapshotters...')
        sys.exit(1)

    # Check slot ID mapping
    slot_id_mapping_query = protocol_state_contract.functions.slotSnapshotterMapping(
        settings.slot_id
    ).call()

    try:
        slot_id_snapshotter_addr = Web3.to_checksum_address(slot_id_mapping_query[0])
        if slot_id_snapshotter_addr == Web3.to_checksum_address(settings.instance_id):
            print('Snapshotter identity found in slot ID mapping...')
        else:
            print('Snapshotter identity not found in slot ID mapping...')
            sys.exit(1)
    except Exception as e:
        print('Error in slot ID mapping query: ', e)
        sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())
