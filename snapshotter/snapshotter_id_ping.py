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
    protocol_abi = read_json_file(settings.protocol_state_old.abi)
    print('abi file ', settings.protocol_state_old.abi)
    print('Contract address: ', settings.protocol_state_old.address)

    w3_old = Web3(Web3.HTTPProvider(settings.prost_chain_rpc.full_nodes[0].url))
    w3 = Web3(Web3.HTTPProvider(settings.powerloom_chain_rpc.full_nodes[0].url))
    
    try:
        block_number = w3_old.eth.get_block_number()
        print(f"✅ Successfully fetched the latest block number {block_number}. Your ISP is supported!")
    except Exception as e:
        print("❌ Failed to fetch the latest block number. Your ISP/VPS region is not supported ⛔️")
        sys.exit(1)

    protocol_state_contract_old = w3_old.eth.contract(address=settings.protocol_state_old.address, abi=protocol_abi)
    protocol_state_contract = w3.eth.contract(address=settings.protocol_state.address, abi=protocol_abi)

    current_epoch_old = protocol_state_contract_old.functions.currentEpoch(settings.old_data_market).call()
    latest_epoch_id_old = current_epoch_old[2]
    print('Latest epoch ID detected on old chain: ', latest_epoch_id_old)

    snapshotter_address = w3_old.eth.account.from_key(settings.signer_private_key).address
    print('Extracted snapshotter address from private key: ', snapshotter_address)

    if latest_epoch_id_old < settings.switch_rpc_at_epoch_id:
        print('Using old chain')

        # Query allowed snapshotters
        allowed_snapshotters = protocol_state_contract_old.functions.allSnapshotters(
            Web3.to_checksum_address(snapshotter_address)
        ).call()

        # Check slot ID mapping
        slot_id_mapping_query = protocol_state_contract_old.functions.slotSnapshotterMapping(
            settings.slot_id
        ).call()

    else:
        print('Using new chain')
        # Query allowed snapshotters
        allowed_snapshotters = protocol_state_contract.functions.allSnapshotters(
            Web3.to_checksum_address(snapshotter_address)
        ).call()

        # Check slot ID mapping
        slot_id_mapping_query = protocol_state_contract.functions.slotSnapshotterMapping(
            settings.slot_id
        ).call()

    if allowed_snapshotters is True or allowed_snapshotters:
        print('✅ Snapshotter identity found in allowed snapshotters...')
    else:
        print('❌ Snapshotter identity check failed on protocol smart contract')
        sys.exit(1)

    try:
        slot_id_snapshotter_addr = Web3.to_checksum_address(slot_id_mapping_query)
        if slot_id_snapshotter_addr == Web3.to_checksum_address(snapshotter_address):
            print('Snapshotter identity found in slot ID mapping...')
        else:
            print('Snapshotter identity not found in slot ID mapping...')
            sys.exit(1)
    except Exception as e:
        print('Error in slot ID mapping query: ', e)
        sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())
