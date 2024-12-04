#!/bin/bash

# ask user to select a data market contract
echo "Select a data market contract: ";
echo "1. Aave V3";
echo "2. Uniswap V2";
read DATA_MARKET_CONTRACT_CHOICE;
if [ "$DATA_MARKET_CONTRACT_CHOICE" = "1" ]; then
    echo "Aave V3 selected"
    DATA_MARKET_SUFFIX="aavev3"
    DATA_MARKET_CONTRACT="0xc390a15BcEB89C2d4910b2d3C696BfD21B190F07"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_aavev3_lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_aavev3_lite"
    NAMESPACE="AAVEV3"
elif [ "$DATA_MARKET_CONTRACT_CHOICE" = "2" ]; then
    echo "Uniswap V2 selected"
    DATA_MARKET_SUFFIX="uniswapv2"
    DATA_MARKET_CONTRACT="0x8023BD7A9e8386B10336E88294985e3Fbc6CF23F"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_uniswapv2-lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_uniswapv2_lite_v2"
    NAMESPACE="UNISWAPV2"
fi

# check if .env exists
if [ ! -f ".env-${DATA_MARKET_SUFFIX}" ]; then
    echo ".env-${DATA_MARKET_SUFFIX} file not found, please create one!";
    echo "creating .env-${DATA_MARKET_SUFFIX} file...";
    cp env.example ".env-${DATA_MARKET_SUFFIX}";

    unset SOURCE_RPC_URL
    unset SIGNER_ACCOUNT_ADDRESS
    unset SIGNER_ACCOUNT_PRIVATE_KEY
    unset SLOT_ID
    unset TELEGRAM_CHAT_ID

    # ask user for SOURCE_RPC_URL and replace it in .env
    if [ -z "$SOURCE_RPC_URL" ]; then
        echo "Enter SOURCE_RPC_URL: ";
        read SOURCE_RPC_URL;
    fi

    # ask user for SIGNER_ACCOUNT_ADDRESS and replace it in .env
    if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
        echo "Enter SIGNER_ACCOUNT_ADDRESS: ";
        read SIGNER_ACCOUNT_ADDRESS;
    fi

    # ask user for SIGNER_ACCOUNT_PRIVATE_KEY and replace it in .env
    if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then
        echo "Enter SIGNER_ACCOUNT_PRIVATE_KEY: ";
        read SIGNER_ACCOUNT_PRIVATE_KEY;
    fi

    # ask user for SLOT_ID and replace it in .env
    if [ -z "$SLOT_ID" ]; then
        echo "Enter Your SLOT_ID (NFT_ID): ";
        read SLOT_ID;
    fi

    # ask user for TELEGRAM_CHAT_ID and replace it in .env
    if [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Enter Your TELEGRAM_CHAT_ID (Optional, leave blank to skip.): ";
        read TELEGRAM_CHAT_ID;
    fi

    sed -i".backup" "s#<data-market-contract>#$DATA_MARKET_CONTRACT#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<snapshot-config-repo-branch>#$SNAPSHOT_CONFIG_REPO_BRANCH#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<snapshotter-compute-repo-branch>#$SNAPSHOTTER_COMPUTE_REPO_BRANCH#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<namespace>#$NAMESPACE#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<source-rpc-url>#$SOURCE_RPC_URL#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<signer-account-address>#$SIGNER_ACCOUNT_ADDRESS#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<signer-account-private-key>#$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<slot-id>#$SLOT_ID#" ".env-$DATA_MARKET_SUFFIX"
    sed -i".backup" "s#<telegram-chat-id>#$TELEGRAM_CHAT_ID#" ".env-$DATA_MARKET_SUFFIX"


else
    # .env exists, ask if user wants to update SIGNER_ACCOUNT_ADDRESS and SIGNER_ACCOUNT_PRIVATE_KEY
    echo ".env-${DATA_MARKET_SUFFIX} file found." 
    echo "Would you like to update SIGNER_ACCOUNT_ADDRESS and SIGNER_ACCOUNT_PRIVATE_KEY? (y/n): ";
    read UPDATE_SIGNER_INFO;
    if [ "$UPDATE_SIGNER_INFO" = "y" ]; then
        echo "Enter new SIGNER_ACCOUNT_ADDRESS: ";
        read SIGNER_ACCOUNT_ADDRESS;
        echo "Enter new SIGNER_ACCOUNT_PRIVATE_KEY: ";
        read SIGNER_ACCOUNT_PRIVATE_KEY;

        sed -i".backup" "s#^SIGNER_ACCOUNT_ADDRESS=.*#SIGNER_ACCOUNT_ADDRESS=$SIGNER_ACCOUNT_ADDRESS#" ".env-$DATA_MARKET_SUFFIX"
        sed -i".backup" "s#^SIGNER_ACCOUNT_PRIVATE_KEY=.*#SIGNER_ACCOUNT_PRIVATE_KEY=$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-$DATA_MARKET_SUFFIX"
    fi
    
    echo "Would you like to update SLOT_ID? (y/n): ";
    read UPDATE_SLOT_ID;
    if [ "$UPDATE_SLOT_ID" = "y" ]; then
        echo "Enter new SLOT_ID (NFT_ID): ";
        read SLOT_ID;
        sed -i".backup" "s#^SLOT_ID=.*#SLOT_ID=$SLOT_ID#" ".env-$DATA_MARKET_SUFFIX"
    fi

    echo "Would you like to update SOURCE_RPC_URL? (y/n): ";
    read UPDATE_RPC_URL;
    if [ "$UPDATE_RPC_URL" = "y" ]; then
        echo "Enter new SOURCE_RPC_URL: ";
        read SOURCE_RPC_URL;
        sed -i".backup" "s#^SOURCE_RPC_URL=.*#SOURCE_RPC_URL=$SOURCE_RPC_URL#" ".env-$DATA_MARKET_SUFFIX"
    fi
fi

echo "bootstrapping..."
./bootstrap.sh

source ".env-$DATA_MARKET_SUFFIX"

export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${SLOT_ID}-${DATA_MARKET_SUFFIX}"
# Use 172.18.0.0/16 as the base, which is within Docker's default pool
if [ -z "$SUBNET_THIRD_OCTET" ]; then
    SUBNET_THIRD_OCTET=1
    echo "SUBNET_THIRD_OCTET not found in .env, setting to default value ${SUBNET_THIRD_OCTET}"
fi

# Check if subnet is already in use (cross-platform)
if command -v ip >/dev/null 2>&1; then
    # Linux systems with 'ip' command
    SUBNET_IN_USE=$(ip addr show | grep -q "172.18.${SUBNET_THIRD_OCTET}" && echo "yes" || echo "no")
else
    # macOS and other systems without 'ip' command
    SUBNET_IN_USE=$(ifconfig 2>/dev/null | grep -q "172.18.${SUBNET_THIRD_OCTET}" && echo "yes" || echo "no")
fi

if [ "$SUBNET_IN_USE" = "yes" ]; then
    echo "Warning: Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 appears to be already in use."
    attempts=0
    max_attempts=5
    while [ "$SUBNET_IN_USE" = "yes" ] && [ $attempts -lt $max_attempts ]; do
        echo "Would you like to try a different subnet? (y/n): "
        read CHANGE_SUBNET
        if [ "$CHANGE_SUBNET" = "y" ]; then
            echo "Enter new subnet third octet (2-255): "
            read NEW_SUBNET_THIRD_OCTET
            SUBNET_THIRD_OCTET=$NEW_SUBNET_THIRD_OCTET
            echo "Setting SUBNET_THIRD_OCTET=${SUBNET_THIRD_OCTET}"
            # Re-check if the new subnet is in use
            if command -v ip >/dev/null 2>&1; then
                SUBNET_IN_USE=$(ip addr show | grep -q "172.18.${SUBNET_THIRD_OCTET}" && echo "yes" || echo "no")
            else
                SUBNET_IN_USE=$(ifconfig 2>/dev/null | grep -q "172.18.${SUBNET_THIRD_OCTET}" && echo "yes" || echo "no")
            fi
            attempts=$((attempts + 1))
        else
            break
        fi
    done
    if [ "$SUBNET_IN_USE" = "yes" ]; then
        echo "Failed to find an available subnet after $max_attempts attempts."
        exit 1
    fi
else 
    echo "Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 is available."
fi

export DOCKER_NETWORK_SUBNET="172.18.${SUBNET_THIRD_OCTET}.0/24"

echo "Selected DOCKER_NETWORK_NAME: ${DOCKER_NETWORK_NAME}"
echo "Selected DOCKER_NETWORK_SUBNET: ${DOCKER_NETWORK_SUBNET}"

# Check if the first argument is "test"
if [ "$1" = "test" ]; then
    echo "Running subnet calculation tests..."
    
    # Test function for subnet calculation
    test_subnet_calculation() {
        local test_slot_id=$1
        local expected_third_octet=$2

        SLOT_ID=$test_slot_id
        SUBNET_THIRD_OCTET=$((SLOT_ID % 256))
        SUBNET="172.18.${SUBNET_THIRD_OCTET}.0/24"

        if [ $SUBNET_THIRD_OCTET -eq $expected_third_octet ]; then
            echo "Test passed for SLOT_ID $test_slot_id: $SUBNET"
        else    
            echo "Test failed for SLOT_ID $test_slot_id: Expected 172.18.$expected_third_octet.0/24, got $SUBNET"
        fi
    }

    # Run test cases
    test_subnet_calculation 0 0
    test_subnet_calculation 1 1
    test_subnet_calculation 99 99
    test_subnet_calculation 100 100
    test_subnet_calculation 255 255
    test_subnet_calculation 256 0

    echo "Subnet calculation tests completed."
    exit 0
fi

# check if ufw command exists
if [ -x "$(command -v ufw)" ]; then
    # delete old blanket allow rule
    ufw delete allow $LOCAL_COLLECTOR_PORT >> /dev/null
    ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT
    if [ $? -eq 0 ]; then
        echo "ufw allow rule added for local collector port ${LOCAL_COLLECTOR_PORT} to allow connections from ${DOCKER_NETWORK_SUBNET}.\n"
    else
            echo "ufw firewall allow rule could not added for local collector port ${LOCAL_COLLECTOR_PORT} \
Please attempt to add it manually with the following command with sudo privileges: \
sudo ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT \
Then run ./build.sh again."
        # exit script if ufw rule not added
        exit 1
    fi
else
    echo "ufw command not found, skipping firewall rule addition for local collector port ${LOCAL_COLLECTOR_PORT}. \
If you are on a Linux VPS, please ensure that the port is open for connections from ${DOCKER_NETWORK_SUBNET} manually to ${LOCAL_COLLECTOR_PORT}."
fi


if [ -z "$OVERRIDE_DEFAULTS" ]; then
    echo "setting default values...";
    export PROST_RPC_URL="https://rpc-prost1m.powerloom.io"
    export PROTOCOL_STATE_CONTRACT="0xF68342970beF978697e1104223b2E1B6a1D7764d"
    export PROST_CHAIN_ID="11169"
fi



echo "testing before build...";

if [ -z "$SOURCE_RPC_URL" ]; then
    echo "RPC URL not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
    echo "SIGNER_ACCOUNT_ADDRESS not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then
    echo "SIGNER_ACCOUNT_ADDRESS not found, please set this in your .env!";
    exit 1;
fi

echo "Found SOURCE RPC URL ${SOURCE_RPC_URL}"

echo "Found SIGNER ACCOUNT ADDRESS ${SIGNER_ACCOUNT_ADDRESS}";

if [ "$PROST_RPC_URL" ]; then
    echo "Found PROST_RPC_URL ${PROST_RPC_URL}";
fi

if [ "$PROST_CHAIN_ID" ]; then
    echo "Found PROST_CHAIN_ID ${PROST_CHAIN_ID}";
fi

if [ "$IPFS_URL" ]; then
    echo "Found IPFS_URL ${IPFS_URL}";
fi

if [ "$PROTOCOL_STATE_CONTRACT" ]; then
    echo "Found PROTOCOL_STATE_CONTRACT ${PROTOCOL_STATE_CONTRACT}";
fi


if [ "$WEB3_STORAGE_TOKEN" ]; then
    echo "Found WEB3_STORAGE_TOKEN ${WEB3_STORAGE_TOKEN}";
fi

if [ "$SLACK_REPORTING_URL" ]; then
    echo "Found SLACK_REPORTING_URL ${SLACK_REPORTING_URL}";
fi

if [ "$POWERLOOM_REPORTING_URL" ]; then
    echo "Found POWERLOOM_REPORTING_URL ${POWERLOOM_REPORTING_URL}";
fi

if [ -z "$CORE_API_PORT" ]; then
    export CORE_API_PORT=8002;
    echo "CORE_API_PORT not found in .env, setting to default value ${CORE_API_PORT}";
else
    echo "Found CORE_API_PORT ${CORE_API_PORT}";
fi

if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051;
    echo "LOCAL_COLLECTOR_PORT not found in .env, setting to default value ${LOCAL_COLLECTOR_PORT}";
else
    echo "Found LOCAL_COLLECTOR_PORT ${LOCAL_COLLECTOR_PORT}";
fi

if [ "$MAX_STREAM_POOL_SIZE" ]; then
    echo "Found MAX_STREAM_POOL_SIZE ${MAX_STREAM_POOL_SIZE}";
else
    export MAX_STREAM_POOL_SIZE=2
    echo "MAX_STREAM_POOL_SIZE not found in .env, setting to default value ${MAX_STREAM_POOL_SIZE}";
fi

if [ -z "$STREAM_HEALTH_CHECK_TIMEOUT_MS" ]; then
    export STREAM_HEALTH_CHECK_TIMEOUT_MS=5000
    echo "STREAM_HEALTH_CHECK_TIMEOUT_MS not found in .env, setting to default value ${STREAM_HEALTH_CHECK_TIMEOUT_MS}";
else
    echo "Found STREAM_HEALTH_CHECK_TIMEOUT_MS ${STREAM_HEALTH_CHECK_TIMEOUT_MS}";
fi

if [ -z "$STREAM_WRITE_TIMEOUT_MS" ]; then
    export STREAM_WRITE_TIMEOUT_MS=5000
    echo "STREAM_WRITE_TIMEOUT_MS not found in .env, setting to default value ${STREAM_WRITE_TIMEOUT_MS}";
else
    echo "Found STREAM_WRITE_TIMEOUT_MS ${STREAM_WRITE_TIMEOUT_MS}";
fi

if [ -z "$MAX_WRITE_RETRIES" ]; then
    export MAX_WRITE_RETRIES=3
    echo "MAX_WRITE_RETRIES not found in .env, setting to default value ${MAX_WRITE_RETRIES}";
else
    echo "Found MAX_WRITE_RETRIES ${MAX_WRITE_RETRIES}";
fi

if [ -z "$MAX_CONCURRENT_WRITES" ]; then
    export MAX_CONCURRENT_WRITES=4
    echo "MAX_CONCURRENT_WRITES not found in .env, setting to default value ${MAX_CONCURRENT_WRITES}";
else
    echo "Found MAX_CONCURRENT_WRITES ${MAX_CONCURRENT_WRITES}";
fi
# check if ufw command exists
if [ -x "$(command -v ufw)" ]; then
    # delete old blanket allow rule
    ufw delete allow $LOCAL_COLLECTOR_PORT >> /dev/null
    ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT
    if [ $? -eq 0 ]; then
        echo "ufw allow rule added for local collector port ${LOCAL_COLLECTOR_PORT} to allow connections from ${DOCKER_NETWORK_SUBNET}.\n"
    else
            echo "ufw firewall allow rule could not added for local collector port ${LOCAL_COLLECTOR_PORT} \
Please attempt to add it manually with the following command with sudo privileges: \
sudo ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT \
Then run ./build.sh again."
        # exit script if ufw rule not added
        exit 1
    fi
else
    echo "ufw command not found, skipping firewall rule addition for local collector port ${LOCAL_COLLECTOR_PORT}. \
If you are on a Linux VPS, please ensure that the port is open for connections from ${DOCKER_NETWORK_SUBNET} manually to ${LOCAL_COLLECTOR_PORT}."
fi

#fetch current git branch name
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "Current branch is ${GIT_BRANCH}";

#if on main git branch, set image_tag to latest or use the branch name


if [ "$GIT_BRANCH" = "dockerify" ]; then
    export IMAGE_TAG="dockerify"
else
    export IMAGE_TAG="latest"
fi

echo "Building image with tag ${IMAGE_TAG}";

# Get the first command line argument
# Check if the first command line argument exists, and if not, assign it a default value
if [ -z "$1" ]; then
    ARG1="yes_collector"
else
    ARG1="no_collector"
fi

if [ "$ARG1" = "yes_collector" ]; then
    COLLECTOR_PROFILE_STRING="--profile local-collector"
else
    COLLECTOR_PROFILE_STRING=""
fi

# if ! [ -x "$(command -v docker-compose)" ]; then
#     echo 'docker compose not found, trying to see if compose exists within docker';
#     # assign docker compose file according to $ARG1

#     docker compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING pull
#     if [ -n "$IPFS_URL" ]; then
#         docker compose -f docker-compose.yaml --profile ipfs $COLLECTOR_PROFILE_STRING up -V
#     else
#         docker compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING up -V
#     fi
# else
#     docker-compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING pull
#     if [ -n "$IPFS_URL" ]; then
#         docker-compose -f docker-compose.yaml --profile ipfs $COLLECTOR_PROFILE_STRING up -V
#     else
#         docker-compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING up -V
#     fi
# fi

