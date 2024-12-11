#!/bin/bash

# ask user to select a data market contract
echo "🔍 Select a data market contract: ";
echo "1. Aave V3";
echo "2. Uniswap V2";
read DATA_MARKET_CONTRACT_CHOICE;
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

PROTOCOL_STATE_CONTRACT="0xF68342970beF978697e1104223b2E1B6a1D7764d"

# check if .env exists
if [ ! -f ".env-${NAMESPACE}" ]; then
    echo "🟡 .env-${NAMESPACE} file not found, please create one!";
    echo "creating .env-${NAMESPACE} file...";
    cp env.example ".env-${NAMESPACE}";

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

    sed -i'.backup' "s#<source-rpc-url>#$SOURCE_RPC_URL#" ".env-$NAMESPACE"
    sed -i'.backup' "s#<signer-account-address>#$SIGNER_ACCOUNT_ADDRESS#" ".env-$NAMESPACE"
    sed -i'.backup' "s#<signer-account-private-key>#$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-$NAMESPACE"
    sed -i'.backup' "s#<slot-id>#$SLOT_ID#" ".env-$NAMESPACE"
    sed -i'.backup' "s#<telegram-chat-id>#$TELEGRAM_CHAT_ID#" ".env-$NAMESPACE"
    sed -i".backup" "s#<data-market-contract>#$DATA_MARKET_CONTRACT#" ".env-$NAMESPACE"
    sed -i".backup" "s#<snapshot-config-repo-branch>#$SNAPSHOT_CONFIG_REPO_BRANCH#" ".env-$NAMESPACE"
    sed -i".backup" "s#<snapshotter-compute-repo-branch>#$SNAPSHOTTER_COMPUTE_REPO_BRANCH#" ".env-$NAMESPACE"
    sed -i".backup" "s#<namespace>#$NAMESPACE#" ".env-$NAMESPACE"

else
    # Add update option for existing env file
    echo "🟢 .env-${NAMESPACE} file found." 
    echo "🫸 ▶︎ Would you like to update any of the environment variables? (y/n): ";
    read UPDATE_ENV_VARS;
    if [ "$UPDATE_ENV_VARS" = "y" ]; then
        echo "🔍 Updating .env-${NAMESPACE} file...";
        rm -rf ".env-${NAMESPACE}";
        echo "creating .env-${NAMESPACE} file...";
        cp env.example ".env-${NAMESPACE}";

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

        sed -i'.backup' "s#<source-rpc-url>#$SOURCE_RPC_URL#" ".env-$NAMESPACE"
        sed -i'.backup' "s#<signer-account-address>#$SIGNER_ACCOUNT_ADDRESS#" ".env-$NAMESPACE"
        sed -i'.backup' "s#<signer-account-private-key>#$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-$NAMESPACE"
        sed -i'.backup' "s#<slot-id>#$SLOT_ID#" ".env-$NAMESPACE"
        sed -i'.backup' "s#<telegram-chat-id>#$TELEGRAM_CHAT_ID#" ".env-$NAMESPACE"
        sed -i".backup" "s#<data-market-contract>#$DATA_MARKET_CONTRACT#" ".env-$NAMESPACE"
        sed -i".backup" "s#<snapshot-config-repo-branch>#$SNAPSHOT_CONFIG_REPO_BRANCH#" ".env-$NAMESPACE"
        sed -i".backup" "s#<snapshotter-compute-repo-branch>#$SNAPSHOTTER_COMPUTE_REPO_BRANCH#" ".env-$NAMESPACE"
        sed -i".backup" "s#<namespace>#$NAMESPACE#" ".env-$NAMESPACE"
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

# Update network naming to include namespace
export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE}"

# Add improved subnet handling
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
    fi

    # Only continue with subnet change prompts if still in use after potential pruning
    if [ "$SUBNET_IN_USE" = "yes" ]; then
        echo "🟡 Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 is already in use."
        echo "⏳ Searching for an available subnet..."
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
            echo "🫸 ▶︎ Would you like to use this subnet? (y/n): "
            read USE_FOUND_SUBNET
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
else 
    echo "🟢 Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 is available or already assigned to ${DOCKER_NETWORK_NAME}."
fi

export DOCKER_NETWORK_SUBNET="172.18.${SUBNET_THIRD_OCTET}.0/24"

echo "Selected DOCKER_NETWORK_NAME: ${DOCKER_NETWORK_NAME}"
echo "Selected DOCKER_NETWORK_SUBNET: ${DOCKER_NETWORK_SUBNET}"

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
    echo "🔔 CORE_API_PORT not found in .env, setting to default value ${CORE_API_PORT}";
else
    echo "Found CORE_API_PORT ${CORE_API_PORT}";
fi

# Function to check if port is in use
check_port() {
    curl -s http://"localhost:$1"/health >/dev/null 2>&1
    return $?
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

# Add collector test
./collector_test.sh
if [ $? -eq 1 ]; then
    echo "🔌 ⭕ Local collector not found or unreachable - will spawn a new local collector instance"
    COLLECTOR_PROFILE_STRING="--profile local-collector"
else
    echo "🔌 ✅ Local collector found - using existing collector instance"
    COLLECTOR_PROFILE_STRING=""
fi

# Remove existing directory if it exists
if [ -d "./snapshotter-lite-local-collector" ]; then
    echo "Removing existing snapshotter-lite-local-collector directory..."
    rm -rf ./snapshotter-lite-local-collector
fi

# Clone the repository
git clone https://github.com/PowerLoom/snapshotter-lite-local-collector.git ./snapshotter-lite-local-collector --single-branch --branch dockerify

# Change directory, make the script executable, and run it
cd ./snapshotter-lite-local-collector/ && chmod +x build-docker.sh && ./build-docker.sh

cd ../

docker build -t snapshotter-lite-v2 .

echo "building...";

# Convert namespace to lowercase for docker compose
NAMESPACE_LOWER=$(echo "$NAMESPACE" | tr '[:upper:]' '[:lower:]')

# Update docker-compose execution
if ! [ -x "$(command -v docker-compose)" ]; then
    echo '🔍 docker compose not found, trying to see if compose exists within docker';
    if [ "$IPFS_URL" == "/dns/ipfs/tcp/5001" ]; then
        docker compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}-dev" -f docker-compose-dev.yaml --profile ipfs $COLLECTOR_PROFILE_STRING up -V
    else
        docker compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}-dev" -f docker-compose-dev.yaml $COLLECTOR_PROFILE_STRING up -V
    fi
else
    if [ "$IPFS_URL" == "/dns/ipfs/tcp/5001" ]; then
        docker-compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}-dev" -f docker-compose-dev.yaml --profile ipfs $COLLECTOR_PROFILE_STRING up -V
    else
        docker-compose --env-file "${bootstrapped_env_file}" -p "snapshotter-lite-v2-${NAMESPACE_LOWER}-dev" -f docker-compose-dev.yaml $COLLECTOR_PROFILE_STRING up -V
    fi
fi
