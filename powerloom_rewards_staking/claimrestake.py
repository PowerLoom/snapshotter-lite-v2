import os
from dotenv import load_dotenv
from web3 import Web3
import sys
from eth_utils import keccak
from eth_abi import decode

def staking_rewards_claim_and_deposit(nodestaking_address, rpc_url, private_key):
    """Claims rewards and deposits from staking contract."""
    method_name = "Staking claim and restake"

    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        account = w3.eth.account.from_key(private_key)
        wallet_address = account.address

        if not w3.is_connected():
            raise Exception("Web3 is not connected.")

        contract = w3.eth.contract(address=nodestaking_address, abi=[
            {"inputs": [], "name": "claimRewardsAndDeposit", "outputs": [], "stateMutability": "nonpayable", "type": "function"}
        ])

        nonce = w3.eth.get_transaction_count(wallet_address)
        gas_price = w3.eth.gas_price
        gas = contract.functions.claimRewardsAndDeposit().estimate_gas({'from': wallet_address})
        transaction = contract.functions.claimRewardsAndDeposit().build_transaction({
            'gas': gas,
            'gasPrice': gas_price,
            'nonce': nonce,
            'from': wallet_address,
        })

        signed_txn = account.sign_transaction(transaction)
        tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
        tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

        if tx_receipt['status'] == 1:
            print(f"{method_name} successful! Transaction hash: {tx_hash.hex()}")
            return tx_receipt
        else:
            print(f"{method_name} failed. Transaction hash: {tx_hash.hex()}")
            print(f"Transaction receipt: {tx_receipt}")
            return None

    except Exception as e:
        print(f"An error occurred in {method_name}: {e}")
        return None

def claim_node_rewards(powerloomnode_address, rpc_url, private_key, user_address):
    """Claims rewards from powerloomnodes contract and returns transaction receipt."""
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        account = w3.eth.account.from_key(private_key)
        wallet_address = account.address

        if not w3.is_connected():
            raise Exception("Web3 is not connected.")

        contract2 = w3.eth.contract(address=powerloomnode_address, abi=[{
            "inputs": [{"internalType": "address", "name": "_user", "type": "address"}],
            "name": "claimRewards",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function"
        }])

        nonce = w3.eth.get_transaction_count(wallet_address)
        gas_price = w3.eth.gas_price
        gas = contract2.functions.claimRewards(user_address).estimate_gas({'from': wallet_address})

        transaction = contract2.functions.claimRewards(user_address).build_transaction({
            'gas': gas,
            'gasPrice': gas_price,
            'nonce': nonce,
            'from': wallet_address,
        })

        signed_txn = account.sign_transaction(transaction)
        tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
        tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

        if tx_receipt['status'] == 1:
            print(f"Powerloom Node Claim successful! Transaction hash: {tx_hash.hex()}")
            return tx_receipt
        else:
            print(f"Node claim failed. Transaction hash: {tx_hash.hex()}")
            print(f"Transaction receipt: {tx_receipt}")
            return None

    except Exception as e:
        print(f"An unexpected error occurred in node reward claim: {e}")
        return None

def restake_node_rewards(nodestaking_address, rpc_url, private_key, tx_receipt):
    """Restakes rewards from claim transaction receipt."""
    method_name2 = "Node reward restaking"

    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        account = w3.eth.account.from_key(private_key)
        wallet_address = account.address

        if not w3.is_connected():
            raise Exception("Web3 is not connected.")

        contract1 = w3.eth.contract(address=nodestaking_address, abi=[{
            "inputs": [],
            "name": "deposit",
            "outputs": [],
            "stateMutability": "payable",
            "type": "function"
        }])

        event_found = False
        log_topic = "dacbdde355ba930696a362ea6738feb9f8bd52dfb3d81947558fd3217e23e325"

        if not tx_receipt:
             return None
        tx_hash_hex = tx_receipt.transactionHash.hex() if isinstance(tx_receipt.transactionHash, bytes) else str(tx_receipt.transactionHash)
        logs_in_receipt = tx_receipt.get("logs", [])

        for idx, log in enumerate(logs_in_receipt): # Use enumerate for index
            log_address = log.get('address')
            log_topics = log.get('topics', [])
            log_topics_hex = [t.hex() if isinstance(t, bytes) else str(t) for t in log_topics]

            if log_topics and len(log_topics) > 0: # Check if topics exist and list is not empty
                topic0 = log_topics[0]
                log_topic_0_hex = topic0.hex() if isinstance(topic0, bytes) else str(topic0)

                if log_topic == log_topic_0_hex:
                    log_data = log.get("data", b"") # Default to empty bytes
                    data_hex = log_data.hex() if isinstance(log_data, bytes) else str(log_data)

                    if data_hex.startswith('0x'):
                        data_bytes = bytes.fromhex(data_hex[2:])
                    elif data_hex: # Handle non-empty data without 0x prefix
                         data_bytes = bytes.fromhex(data_hex)
                    else: # Handle empty data
                        continue 

                    try:
                        decoded_data = decode(["uint256", "uint256"], data_bytes)
                        deposit_value = decoded_data[0]
                    except Exception as decode_err:
                        continue 

                    nonce = w3.eth.get_transaction_count(wallet_address)
                    gas_price = w3.eth.gas_price
                    try:
                        gas = contract1.functions.deposit().estimate_gas({'from': wallet_address, 'value': deposit_value})
                    except Exception as estimate_err:
                        continue 

                    transaction = contract1.functions.deposit().build_transaction({
                        'gas': gas,
                        'gasPrice': gas_price,
                        'nonce': nonce,
                        'from': wallet_address,
                        'value': deposit_value,
                    })

                    signed_txn = account.sign_transaction(transaction)
                    restake_tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
                    restake_tx_hash_hex = restake_tx_hash.hex() if isinstance(restake_tx_hash, bytes) else str(restake_tx_hash)
                    restake_tx_receipt = w3.eth.wait_for_transaction_receipt(restake_tx_hash)

                    if restake_tx_receipt['status'] == 1:
                        print(f"{method_name2} successful! Transaction hash: {restake_tx_hash_hex}")
                        event_found = True 
                        return restake_tx_receipt # Return the receipt of the successful restake
                    else:
                        print(f"{method_name2} failed. Transaction hash: {restake_tx_hash_hex}")
                        print(f"Transaction receipt: {restake_tx_receipt}")
                        # If the correct event log led to a failed restake, return None.
                        return None

        if not event_found:
            print("Node Rewards Claimed event not found in logs.") 
            return None

    except Exception as e:
        print(f"An unexpected error occurred in node reward restaking: {e}")
        # Also print traceback for more details during debugging
        return None

if __name__ == "__main__":
    load_dotenv()

    rpc_url = os.getenv("POWERLOOM_RPC_URL")
    private_key = os.getenv("SENDER_PK")
    user_address = os.getenv("ADDRESS_INPUT") 
    nodestaking_address = os.getenv("NODESTAKING_ADDRESS")
    powerloomnode_address = os.getenv("POWERLOOM_NODES_ADDRESS") #

    # Basic check for essential vars for the test
    if not private_key or not rpc_url or not nodestaking_address:
        print("Error: SENDER_PK, POWERLOOM_RPC_URL, or NODESTAKING_ADDRESS not set in .env")
        sys.exit(1) #exit with error code

    result1 = None
    result2 = None
    result3 = None
    try:
        result1 = staking_rewards_claim_and_deposit(nodestaking_address, rpc_url, private_key)
    except Exception as e:
        print(f"WARNING: Staking rewards claim failed: {e}")
        result1 = None
    
    try:
        # Need user_address if uncommenting this part
        user_address = os.getenv("ADDRESS_INPUT")
        powerloomnode_address = os.getenv("POWERLOOM_NODES_ADDRESS")
        if not user_address or not powerloomnode_address:
             print("Error: ADDRESS_INPUT or POWERLOOM_NODES_ADDRESS not set for original logic.")
             sys.exit(1)
        result2 = claim_node_rewards(powerloomnode_address, rpc_url, private_key, user_address)
    except Exception as e:
        print(f"WARNING: Node rewards claim failed: {e}")
        result2 = None 
    
    if result2: #only try to restake if claim was successful
        try:
            result3 = restake_node_rewards(nodestaking_address, rpc_url, private_key, result2)
        except Exception as e:
            print(f"WARNING: Node rewards restaking failed: {e}")
            result3 = None
    else:
        result3 = None
    
    # Final success/failure evaluation
    if result1 and result2 and result3:
        print("SUCCESS: Node Claim, Staking Claim, and Restaking successful!")
        sys.exit(0)  # Exit with success code
    elif result1 and result2:
        print("SUCCESS: Node Claim and Staking Claim successful!")
        sys.exit(0)  # Exit with success code
    elif result1:
        print("SUCCESS: Staking Claim and Restaking successful! Node Claim failed.")
        sys.exit(0)  # Exit with success code
    elif result2:
        print("SUCCESS: Node Claim and Restaking successful! Staking Claim failed.")
        sys.exit(0)  # Exit with success code
    else:
        print("ERROR: Both steps failed.")
        sys.exit(1)  # Exit with error code