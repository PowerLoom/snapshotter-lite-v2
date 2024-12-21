#!/bin/bash

DOCKER_NETWORK_PRUNE=false
SETUP_COMPLETE=true
DATA_MARKET_CONTRACT_NUMBER=""
SKIP_CREDENTIAL_UPDATE=false
NO_COLLECTOR=false
# Parse command line argument
# this is used to prune the docker network if the user passes --docker-network-prune
while [[ $# -gt 0 ]]; do
    case $1 in
        --docker-network-prune)
            DOCKER_NETWORK_PRUNE=true
            shift
            ;;
        --data-market-contract-number)
            DATA_MARKET_CONTRACT_NUMBER=$2
            shift 2
            ;;
        --skip-credential-update)
            SKIP_CREDENTIAL_UPDATE=true
            shift
            ;;
        --no-collector)
            NO_COLLECTOR=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

handle_error() {
    local exit_code=$?
    # Only handle exit codes below 100 as errors
    if [ $exit_code -lt 100 ]; then
        echo "Error on line $1: Command exited with status $exit_code"
        # Cleanup code here
        exit $exit_code
    fi
    return $exit_code
}

# Add trap for error handling
trap 'handle_error $LINENO' ERR

# Add cleanup function
cleanup() {
    # Remove backup files
    find . -name "*.backup" -type f -delete
    # also check if the namespace is set and if the .env-${NAMESPACE} file exists
    if [ -n "$NAMESPACE" ] && [ -f ".env-${NAMESPACE}" ] && [ "$SETUP_COMPLETE" = false ]; then
        rm -rf ".env-${NAMESPACE}"
        echo "Aborted setup. Deleted .env-${NAMESPACE} file."
    fi
    # Other cleanup tasks
}

trap cleanup EXIT

# Add docker daemon check
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not running"
    exit 1
fi
# if the data market number is passed as an argument with the data-market-contract-number flag, use it
# Replace the interactive data market selection with automated selection if argument is provided
if [ -n "$DATA_MARKET_CONTRACT_NUMBER" ]; then
    DATA_MARKET_CONTRACT_CHOICE="$DATA_MARKET_CONTRACT_NUMBER"
else
    # ask user to select a data market contract
    echo "🔍 Select a data market contract: ";
    echo "1. Aave V3";
    echo "2. Uniswap V2";
    read DATA_MARKET_CONTRACT_CHOICE;
fi

if [ "$DATA_MARKET_CONTRACT_CHOICE" = "1" ]; then
    echo "Aave V3 selected"
    DATA_MARKET_CONTRACT="0xc390a15BcEB89C2d4910b2d3C696BfD21B190F07"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_aavev3_lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_aavev3_lite"
    NAMESPACE="AAVEV3"
elif [ "$DATA_MARKET_CONTRACT_CHOICE" = "2" ]; then
    echo "Uniswap V2 selected"
    DATA_MARKET_CONTRACT="0x8023BD7A9e8386B10336E88294985e3Fbc6CF23F"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_uniswapv2-lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_uniswapv2_lite_v2"
    NAMESPACE="UNISWAPV2"
fi

# set default protocol values
export PROTOCOL_STATE_CONTRACT="0xF68342970beF978697e1104223b2E1B6a1D7764d"
export PROST_RPC_URL="https://rpc-prost1m.powerloom.io"
export PROST_CHAIN_ID=11169

# check if .env exists
if [ ! -f ".env-${NAMESPACE}" ]; then
    echo "🟡 .env-${NAMESPACE} file not found, please follow the instructions below to create one!";
    echo "creating .env-${NAMESPACE} file...";
    cp env.example ".env-${NAMESPACE}";
    SETUP_COMPLETE=false

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

    sed -i".backup" "s#<data-market-contract>#$DATA_MARKET_CONTRACT#" ".env-$NAMESPACE"
    sed -i".backup" "s#<protocol-state-contract>#$PROTOCOL_STATE_CONTRACT#" ".env-$NAMESPACE"
    sed -i".backup" "s#<snapshot-config-repo-branch>#$SNAPSHOT_CONFIG_REPO_BRANCH#" ".env-$NAMESPACE"
    sed -i".backup" "s#<snapshotter-compute-repo-branch>#$SNAPSHOTTER_COMPUTE_REPO_BRANCH#" ".env-$NAMESPACE"
    sed -i".backup" "s#<namespace>#$NAMESPACE#" ".env-$NAMESPACE"
    sed -i".backup" "s#<source-rpc-url>#$SOURCE_RPC_URL#" ".env-$NAMESPACE"
    sed -i".backup" "s#<signer-account-address>#$SIGNER_ACCOUNT_ADDRESS#" ".env-$NAMESPACE"
    sed -i".backup" "s#<signer-account-private-key>#$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-$NAMESPACE"
    sed -i".backup" "s#<slot-id>#$SLOT_ID#" ".env-$NAMESPACE"
    sed -i".backup" "s#<telegram-chat-id>#$TELEGRAM_CHAT_ID#" ".env-$NAMESPACE"
    sed -i".backup" "s#<prost-rpc-url>#$PROST_RPC_URL#" ".env-$NAMESPACE"
    sed -i".backup" "s#<prost-chain-id>#$PROST_CHAIN_ID#" ".env-$NAMESPACE"

    echo "🟢 .env-${NAMESPACE} file created successfully."


else
    # .env exists, ask if user wants to update any of the environment variables
    echo "🟢 .env-${NAMESPACE} file found." 
    if [ "$SKIP_CREDENTIAL_UPDATE" = "true" ]; then
        echo "🔔 Skipping credential update prompts due to --skip-credential-update flag"
    else
        echo "🫸 ▶︎  Would you like to update any of the environment variables (SIGNER_ACCOUNT, SLOT_ID, SOURCE_RPC_URL)? (y/n): ";
        read UPDATE_ENV_VARS
        if [ "$UPDATE_ENV_VARS" = "y" ]; then
            echo "Enter new SIGNER_ACCOUNT_ADDRESS (press enter to skip): "
            read SIGNER_ACCOUNT_ADDRESS;
            if [ ! -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
                echo "Enter new SIGNER_ACCOUNT_PRIVATE_KEY: "
                read SIGNER_ACCOUNT_PRIVATE_KEY;
                sed -i".backup" "s#^SIGNER_ACCOUNT_ADDRESS=.*#SIGNER_ACCOUNT_ADDRESS=$SIGNER_ACCOUNT_ADDRESS#" ".env-$NAMESPACE"
                sed -i".backup" "s#^SIGNER_ACCOUNT_PRIVATE_KEY=.*#SIGNER_ACCOUNT_PRIVATE_KEY=$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-$NAMESPACE"
            fi

            echo "Enter new SLOT_ID (NFT_ID) (press enter to skip): "
            read SLOT_ID
            if [ ! -z "$SLOT_ID" ]; then
                sed -i".backup" "s#^SLOT_ID=.*#SLOT_ID=$SLOT_ID#" ".env-$NAMESPACE"
            fi

            echo "Enter new SOURCE_RPC_URL (press enter to skip): "
            read SOURCE_RPC_URL
            if [ ! -z "$SOURCE_RPC_URL" ]; then
                sed -i".backup" "s#^SOURCE_RPC_URL=.*#SOURCE_RPC_URL=$SOURCE_RPC_URL#" ".env-$NAMESPACE"
            fi
        fi
    fi
fi

export NAMESPACE

echo "🚀 bootstrapping..."
if ! ./bootstrap.sh; then
    echo "❌ bootstrapping failed, exiting..."
    exit 1
fi
echo "✅ bootstrap complete"

bootstrapped_env_file=.env-${NAMESPACE}
source ${bootstrapped_env_file}

export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE}"
# Use 172.18.0.0/16 as the base, which is within Docker's default pool
if [ -z "$SUBNET_THIRD_OCTET" ]; then
    SUBNET_THIRD_OCTET=1
    echo "🔔 SUBNET_THIRD_OCTET not found in .env, setting to default value ${SUBNET_THIRD_OCTET}"
fi

# Check if network with same name already exists
NETWORK_EXISTS=$(docker network ls --format '{{.Name}}' | grep -x "$DOCKER_NETWORK_NAME" || echo "")

# Check if subnet is already in use in Docker networks
SUBNET_IN_USE=$(docker network ls --format '{{.Name}}' | while read network; do
    if [ "$network" != "$DOCKER_NETWORK_NAME" ] && docker network inspect "$network" | grep -q "172.18.${SUBNET_THIRD_OCTET}"; then
        echo "yes"
        break
    fi
done || echo "no")

if [ "$SUBNET_IN_USE" = "yes" ] && [ -z "$NETWORK_EXISTS" ]; then
    echo "🟡 Warning: Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 appears to be already in use by another network."
    echo "This may be from an old snapshotter node, or you may already have a snapshotter running."
    if [ "$DOCKER_NETWORK_PRUNE" = "true" ]; then
        echo "🫸 ▶︎  Would you like to prune unused Docker networks? (y/n): "
        read PRUNE_NETWORKS
        if [ "$PRUNE_NETWORKS" = "y" ]; then
            docker network prune -f
            # Re-check if the subnet is still in use
            SUBNET_IN_USE=$(docker network ls --format '{{.Name}}' | while read network; do
                    if [ "$network" != "$DOCKER_NETWORK_NAME" ] && docker network inspect "$network" | grep -q "172.18.${SUBNET_THIRD_OCTET}"; then
                            echo "yes"
                            break
                    fi
                done || echo "no")
        else
            echo "🟡 Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 allowed to remain in use."
        fi
    fi

    # Only continue with subnet change prompts if still in use after potential pruning
    if [ "$SUBNET_IN_USE" = "yes" ]; then
        echo "⏳ Searching for an available subnet other than 172.18.${SUBNET_THIRD_OCTET}.0/24..."
        # First try to find an available subnet
        FOUND_AVAILABLE_SUBNET=false
        AVAILABLE_SUBNET_OCTET=""
        
        for i in $(seq 1 255); do
            echo "Checking subnet 172.18.${i}.0/24..."
            SUBNET_IN_USE="no"
            while read network; do
                if [ "$network" != "$DOCKER_NETWORK_NAME" ]; then
                    if docker network inspect "$network" 2>/dev/null | grep -q "172.18.${i}"; then
                        SUBNET_IN_USE="yes"
                        break
                    fi
                fi
            done < <(docker network ls --format '{{.Name}}')
            
            echo "Subnet 172.18.${i}.0/24 in use: $SUBNET_IN_USE"
            
            if [ "$SUBNET_IN_USE" = "no" ]; then
                FOUND_AVAILABLE_SUBNET=true
                AVAILABLE_SUBNET_OCTET=$i
                break
            fi
        done

        if [ "$FOUND_AVAILABLE_SUBNET" = "true" ]; then
            echo "🟢 Found available subnet: 172.18.${AVAILABLE_SUBNET_OCTET}.0/24"
            # select subnet by default unless the command line argument is passed
            if [ "$DOCKER_NETWORK_PRUNE" = "true" ]; then
                echo "🫸 ▶︎ Would you like to use this subnet? (y/n): "
                read USE_FOUND_SUBNET
            else
                echo "🟠 Proceeding with subnet 172.18.${AVAILABLE_SUBNET_OCTET}.0/24"
                USE_FOUND_SUBNET="y"
            fi
            if [ "$USE_FOUND_SUBNET" = "y" ]; then
                SUBNET_THIRD_OCTET=$AVAILABLE_SUBNET_OCTET
                SUBNET_IN_USE="no"
            else
                echo "❌ Failed to assign subnet."
                echo "🚧 Please check your docker networks and/or prune any unused networks."
                exit 1
            fi
        else
            echo "❌ No available subnets found between 172.18.1.0/24 and 172.18.255.0/24"
            echo "🚧 Please check your docker networks and/or prune any unused networks."
            exit 1
        fi
    fi

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
        echo "✅ ufw allow rule added for local collector port ${LOCAL_COLLECTOR_PORT} to allow connections from ${DOCKER_NETWORK_SUBNET}.\n"
    else
        echo "❌ ufw firewall allow rule could not be added for local collector port ${LOCAL_COLLECTOR_PORT}. \
            Please attempt to add it manually with the following command with sudo privileges: \
            sudo ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT. \
            Then run ./build.sh again."
        # exit script if ufw rule not added
        exit 1
    fi
else
    echo "🟡 ufw command not found, skipping firewall rule addition for local collector port ${LOCAL_COLLECTOR_PORT}. \
If you are on a Linux VPS, please ensure that the port is open for connections from ${DOCKER_NETWORK_SUBNET} manually to ${LOCAL_COLLECTOR_PORT}."
fi

echo "testing before build...";

if [ -z "$SOURCE_RPC_URL" ]; then
    echo "❌ RPC URL not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
    echo "❌ SIGNER_ACCOUNT_ADDRESS not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then
    echo "❌ SIGNER_ACCOUNT_PRIVATE_KEY not found, please set this in your .env!";
    exit 1;
fi

echo "Found SOURCE RPC URL ${SOURCE_RPC_URL}"

echo "Found SIGNER ACCOUNT ADDRESS ${SIGNER_ACCOUNT_ADDRESS}";

if export -p | grep -q "PROST_RPC_URL="; then
    echo "Found exported PROST_RPC_URL ${PROST_RPC_URL}";
elif [ "$PROST_RPC_URL" ]; then
    echo "PROST_RPC_URL is set but not exported: ${PROST_RPC_URL}";
fi

if export -p | grep -q "PROST_CHAIN_ID="; then
    echo "Found exported PROST_CHAIN_ID ${PROST_CHAIN_ID}";
elif [ "$PROST_CHAIN_ID" ]; then
    echo "PROST_CHAIN_ID is set but not exported: ${PROST_CHAIN_ID}";
fi

if [ "$IPFS_URL" ]; then
    echo "Found IPFS_URL ${IPFS_URL}";
fi

if export -p | grep -q "PROTOCOL_STATE_CONTRACT="; then
    echo "Found exported PROTOCOL_STATE_CONTRACT ${PROTOCOL_STATE_CONTRACT}";
elif [ "$PROTOCOL_STATE_CONTRACT" ]; then
    echo "PROTOCOL_STATE_CONTRACT is set but not exported: ${PROTOCOL_STATE_CONTRACT}";
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
    echo "🔔 CORE_API_PORT not found in .env, setting to default value ${CORE_API_PORT}";
else
    echo "Found CORE_API_PORT ${CORE_API_PORT}";
fi

# Function to check if port is in use
check_port() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -i:"$1" >/dev/null 2>&1
    else
        netstat -tuln | grep -q ":$1 "
    fi
}

# Find available port starting from CORE_API_PORT
while check_port $CORE_API_PORT; do
    echo "Port ${CORE_API_PORT} is already in use"
    CORE_API_PORT=$((CORE_API_PORT + 1))
done

echo "ℹ️ Using available port: ${CORE_API_PORT}"
export CORE_API_PORT
sed -i'.backup' "s#^CORE_API_PORT=.*#CORE_API_PORT=$CORE_API_PORT#" ".env-$NAMESPACE"

if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051;
    echo "🔔 LOCAL_COLLECTOR_PORT not found in .env, setting to default value ${LOCAL_COLLECTOR_PORT}";
else
    echo "Found LOCAL_COLLECTOR_PORT ${LOCAL_COLLECTOR_PORT}";
fi

if [ "$MAX_STREAM_POOL_SIZE" ]; then
    echo "Found MAX_STREAM_POOL_SIZE ${MAX_STREAM_POOL_SIZE}";
else
    export MAX_STREAM_POOL_SIZE=2
    echo "🔔 MAX_STREAM_POOL_SIZE not found in .env, setting to default value ${MAX_STREAM_POOL_SIZE}";
fi

if [ -z "$STREAM_HEALTH_CHECK_TIMEOUT_MS" ]; then
    export STREAM_HEALTH_CHECK_TIMEOUT_MS=5000
    echo "🔔 STREAM_HEALTH_CHECK_TIMEOUT_MS not found in .env, setting to default value ${STREAM_HEALTH_CHECK_TIMEOUT_MS}";
else
    echo "Found STREAM_HEALTH_CHECK_TIMEOUT_MS ${STREAM_HEALTH_CHECK_TIMEOUT_MS}";
fi

if [ -z "$STREAM_WRITE_TIMEOUT_MS" ]; then
    export STREAM_WRITE_TIMEOUT_MS=5000
    echo "🔔 STREAM_WRITE_TIMEOUT_MS not found in .env, setting to default value ${STREAM_WRITE_TIMEOUT_MS}";
else
    echo "Found STREAM_WRITE_TIMEOUT_MS ${STREAM_WRITE_TIMEOUT_MS}";
fi

if [ -z "$MAX_WRITE_RETRIES" ]; then
    export MAX_WRITE_RETRIES=3
    echo "🔔 MAX_WRITE_RETRIES not found in .env, setting to default value ${MAX_WRITE_RETRIES}";
else
    echo "Found MAX_WRITE_RETRIES ${MAX_WRITE_RETRIES}";
fi

if [ -z "$MAX_CONCURRENT_WRITES" ]; then
    export MAX_CONCURRENT_WRITES=4
    echo "🔔 MAX_CONCURRENT_WRITES not found in .env, setting to default value ${MAX_CONCURRENT_WRITES}";
else
    echo "Found MAX_CONCURRENT_WRITES ${MAX_CONCURRENT_WRITES}";
fi

#fetch current git branch name
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "ℹ️ Current branch is ${GIT_BRANCH}";

#if on main git branch, set image_tag to latest or use the branch name


if [ "$GIT_BRANCH" = "dockerify" ]; then
    export IMAGE_TAG="dockerify"
else
    export IMAGE_TAG="latest"
fi

echo "🏗️ Building image with tag ${IMAGE_TAG}";

# Run collector test to determine if we need to spawn a collector
# When collector is not found/unreachable
# exit 101
# When collector is found and working
# exit 100
# check for no collector flag being passed, in that case dont even attempt the test
if [ "$NO_COLLECTOR" = "true" ]; then
    echo "🔌 ⭕ No collector flag passed, skipping collector test"
    COLLECTOR_PROFILE_STRING=""
else
    ./collector_test.sh
    test_result=$?
    if [ $test_result -eq 101 ]; then
        echo "🔌 ⭕ Local collector not found or unreachable - will spawn a new local collector instance"
        COLLECTOR_PROFILE_STRING="--profile local-collector"
    elif [ $test_result -eq 100 ]; then
        echo "🔌 ✅ Local collector found - using existing collector instance"
        COLLECTOR_PROFILE_STRING=""
    else
        echo "❌ Collector test failed with exit code $?, exiting..."
        exit 1
    fi
fi

# Convert namespace to lowercase for docker compose
NAMESPACE_LOWER=$(echo "$NAMESPACE" | tr '[:upper:]' '[:lower:]')

# if the setup has reached here, do not delete the .env-${NAMESPACE} file
SETUP_COMPLETE=true

DOCKER_PULL_LOCK="/tmp/powerloom_docker_pull.lock"

# Function to handle Docker pulls with lock
handle_docker_pull() {
    # Wait for lock to be released if it exists
    while [ -f "$DOCKER_PULL_LOCK" ]; do
        echo "Another Docker pull is in progress, waiting..."
        sleep 5
    done

    # Create lock file and ensure it's removed on exit
    touch "$DOCKER_PULL_LOCK"
    trap 'rm -f $DOCKER_PULL_LOCK' EXIT

    # Perform Docker pull
    if ! [ -x "$(command -v docker-compose)" ]; then
        echo 'docker compose not found, trying to see if compose exists within docker'
        
        if [ -n "$IPFS_URL" ]; then
            docker compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}" -f docker-compose.yaml --profile ipfs $COLLECTOR_PROFILE_STRING pull
        else
            docker compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}" -f docker-compose.yaml $COLLECTOR_PROFILE_STRING pull
        fi
    else
        if [ -n "$IPFS_URL" ]; then
            docker-compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}" -f docker-compose.yaml --profile ipfs $COLLECTOR_PROFILE_STRING pull
        else
            docker-compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}" -f docker-compose.yaml $COLLECTOR_PROFILE_STRING pull
        fi
    fi

    # Remove lock file
    rm -f "$DOCKER_PULL_LOCK"
}

# Replace the existing Docker pull and up commands with:
handle_docker_pull

# Continue with docker-compose up
if ! [ -x "$(command -v docker-compose)" ]; then
    if [ -n "$IPFS_URL" ]; then
        docker compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            --profile ipfs \
            $COLLECTOR_PROFILE_STRING \
            pull

        docker compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            --profile ipfs \
            $COLLECTOR_PROFILE_STRING \
            up -V
    else
        docker compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            $COLLECTOR_PROFILE_STRING \
            pull

        docker compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            $COLLECTOR_PROFILE_STRING \
            up -V
    fi
else
    if [ -n "$IPFS_URL" ]; then
        docker-compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            --profile ipfs \
            $COLLECTOR_PROFILE_STRING \
            pull

        docker-compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            --profile ipfs \
            $COLLECTOR_PROFILE_STRING \
            up -V
    else
        docker-compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            $COLLECTOR_PROFILE_STRING \
            pull

        docker-compose \
            --env-file "${bootstrapped_env_file}" \
            -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE_LOWER}" \
            -f docker-compose.yaml \
            $COLLECTOR_PROFILE_STRING \
            up -V
    fi
fi

# Explicitly specify env file for cross-platform compatibility
# This is especially important on Linux where environment variables
# don't automatically pass through to Docker Compose

