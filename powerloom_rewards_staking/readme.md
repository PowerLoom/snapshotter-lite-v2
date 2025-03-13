# Powerloom Node Staking Rewards Claim and Restake

This Python script interacts with the Powerloom blockchain to claim staking rewards and restake them using the Powerloom smart contracts. It automates the following tasks:

1. **Claiming rewards** from the staking contract.
2. **Claiming node rewards** from the Powerloom node contract.
3. **Restaking the claimed rewards** by depositing them back into the staking contract.

## Prerequisites

- Python 3.x installed
- `venv` (virtual environment) set up
- Required dependencies installed (see [Installation](#installation))
- `.env` file configured with private keys

## Installation

1. Clone this repository:
   ```sh
   git clone https://github.com/halfdoctor/snapshotter-lite-v2.git
   cd snapshotter-lite-v2/powerloom_rewards_staking
   ```
2. Create a virtual environment and activate it:
   ```sh
   python3 -m venv venv
   source venv/bin/activate  # For Linux/macOS
   venv\Scripts\activate     # For Windows
   ```
3. Install required dependencies:
   ```sh
   pip install -r requirements.txt
   ```
4. Set up the `.env` file:
   ```sh
   cp env.example .env
   ```
   Then update the `.env` file with:
   ```sh
   SENDER_PK=your_private_key_here
   ADDRESS_INPUT=your_wallet_address_here
   ```

- `ADDRESS_INPUT`: Your wallet address that you purchased the node with.
- `SENDER_PK`: The private key of the wallet address.
- `NODESTAKING_ADDRESS`: The address of the NodeStaking contract. Found on the Powerloom network.
- `POWERLOOM_NODES_ADDRESS`: The address of the PowerloomNodes contract. Found on the Powerloom network.

## Usage

Run the script with:
```sh
python claimrestake.py
```

## How It Works

### `staking_rewards_claim_and_deposit()`
- Connects to the Powerloom blockchain using Web3.
- Calls `claimRewardsAndDeposit()` on the staking contract.
- Signs and sends the transaction.
- Waits for transaction confirmation.
- If successful, prints the transaction hash.

### `node_rewards_claim()`
- Connects to the Powerloom blockchain using Web3.
- Calls `claimRewards(user_address)` on the Powerloom node contract, passing the user's address.
- Retrieves the transaction receipt to check for success.
- If successful, prints the transaction hash.

### `restake_node_rewards()`
- Connects to the Powerloom blockchain using Web3.
- Examines the logs of the `claimRewards` transaction receipt.
- Decodes the event data to extract the deposit value.
- Calls the `deposit()` function on the staking contract with the extracted value.
- Signs and sends the transaction.
- Waits for transaction confirmation.
- If successful, prints the transaction hash.

## Expected Output

If both claims and restaking succeed:
```sh
SUCCESS: Node Claim, Staking Claim, and Restaking successful!
```
If one step fails:
```sh
SUCCESS: Staking Claim and Restaking successful! Node Claim failed.
```
Or:
```sh
SUCCESS: Node Claim and Restaking successful! Staking Claim failed.
```
If both fail:
```sh
ERROR: Both steps failed.
```

## Error Handling

- Checks if Web3 is connected.
- Validates if private key is set.
- Catches transaction errors and prints warnings.
- Uses `sys.exit()` codes for success/failure detection.

## License

This project is licensed under the MIT License.

---

**Note:** Use this script at your own risk. Always verify contract interactions before executing transactions on the blockchain.