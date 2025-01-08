#!/bin/bash

# Initial variable declarations
DOCKER_NETWORK_PRUNE=false
SETUP_COMPLETE=true
DATA_MARKET_CONTRACT_NUMBER=""
SKIP_CREDENTIAL_UPDATE=false
NO_COLLECTOR=false

# Parse command line arguments
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

# Error handling and cleanup functions
handle_error() {
    local exit_code=$?
    if [ $exit_code -lt 100 ]; then
        echo "Error on line $1: Command exited with status $exit_code"
        exit $exit_code
    fi
    return $exit_code
}

cleanup() {
    find . -name "*.backup" -type f -delete
    if [ -n "$NAMESPACE" ] && [ -f ".env-${FULL_NAMESPACE}" ] && [ "$SETUP_COMPLETE" = false ]; then
        rm -rf ".env-${FULL_NAMESPACE}"
        echo "Aborted setup. Deleted .env-${FULL_NAMESPACE} file."
    fi
}

trap 'handle_error $LINENO' ERR
trap cleanup EXIT

# Docker daemon check
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not running"
    exit 1
fi

# Data market selection
if [ -n "$DATA_MARKET_CONTRACT_NUMBER" ]; then
    DATA_MARKET_CONTRACT_CHOICE="$DATA_MARKET_CONTRACT_NUMBER"
else
    echo "🔍 Select a data market contract: "
    echo "1. Aave V3"
    echo "2. Uniswap V2 (default)"
    read DATA_MARKET_CONTRACT_CHOICE
    
    # Set default to Uniswap V2 if empty or invalid input
    if [ -z "$DATA_MARKET_CONTRACT_CHOICE" ] || ! [[ "$DATA_MARKET_CONTRACT_CHOICE" =~ ^[12]$ ]]; then
        DATA_MARKET_CONTRACT_CHOICE="2"
        echo "Using default: Uniswap V2"
    fi
fi

if [ "$DATA_MARKET_CONTRACT_CHOICE" = "1" ]; then
    echo "Aave V3 selected"
    DATA_MARKET_CONTRACT="0xdE95f6d0D1A7B8411fCbfc60d5c2C5Df69d667a9"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_aavev3_lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_aavev3_lite"
    NAMESPACE="AAVEV3"
elif [ "$DATA_MARKET_CONTRACT_CHOICE" = "2" ]; then
    echo "Uniswap V2 selected"
    DATA_MARKET_CONTRACT="0xC53ad4C6A8A978fC4A91F08A21DcE847f5Bc0E27"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_uniswapv2-lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_uniswapv2_lite_v2"
    NAMESPACE="UNISWAPV2"
fi

# Set protocol values
export PROTOCOL_STATE_CONTRACT="0x670E0Cf8c8dF15B326D5E2Db4982172Ff8504909"
export PROST_RPC_URL="https://rpc.powerloom.network"
export PROST_CHAIN_ID=7865
export POWERLOOM_CHAIN=pre-mainnet
export SOURCE_CHAIN=ETH
export FULL_NAMESPACE="${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"

# Environment file management
if [ ! -f ".env-${FULL_NAMESPACE}" ]; then
    echo "🟡 .env-${FULL_NAMESPACE} file not found, creating one..."
    cp env.example ".env-${FULL_NAMESPACE}"
    SETUP_COMPLETE=false

    # Prompt for required values
    read -p "Enter SOURCE_RPC_URL: " SOURCE_RPC_URL
    read -p "Enter SIGNER_ACCOUNT_ADDRESS: " SIGNER_ACCOUNT_ADDRESS
    read -s -p "Enter SIGNER_ACCOUNT_PRIVATE_KEY: " SIGNER_ACCOUNT_PRIVATE_KEY
    echo
    read -p "Enter Your SLOT_ID (NFT_ID): " SLOT_ID
    export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${SLOT_ID}-${FULL_NAMESPACE}"
    
    read -p "Enter Your TELEGRAM_CHAT_ID (Optional, leave blank to skip.): " TELEGRAM_CHAT_ID

    # Update env file
    sed -i".backup" "s#<data-market-contract>#$DATA_MARKET_CONTRACT#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<protocol-state-contract>#$PROTOCOL_STATE_CONTRACT#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<snapshot-config-repo-branch>#$SNAPSHOT_CONFIG_REPO_BRANCH#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<snapshotter-compute-repo-branch>#$SNAPSHOTTER_COMPUTE_REPO_BRANCH#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<powerloom-chain>#$POWERLOOM_CHAIN#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<source-chain>#$SOURCE_CHAIN#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<namespace>#${NAMESPACE}#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<full-namespace>#${FULL_NAMESPACE}#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<source-rpc-url>#$SOURCE_RPC_URL#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<signer-account-address>#$SIGNER_ACCOUNT_ADDRESS#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<signer-account-private-key>#$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<slot-id>#$SLOT_ID#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<telegram-chat-id>#$TELEGRAM_CHAT_ID#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<prost-rpc-url>#$PROST_RPC_URL#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<prost-chain-id>#$PROST_CHAIN_ID#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<docker-network-name>#$DOCKER_NETWORK_NAME#" ".env-${FULL_NAMESPACE}"
    echo "🟢 .env-${FULL_NAMESPACE} file created successfully."
else
    echo "🟢 .env-${FULL_NAMESPACE} file found."
    if [ "$SKIP_CREDENTIAL_UPDATE" = "true" ]; then
        echo "🔔 Skipping credential update prompts due to --skip-credential-update flag"
    else
        read -p "🫸 ▶︎  Would you like to update any of the environment variables? (y/n): " UPDATE_ENV_VARS
        if [ "$UPDATE_ENV_VARS" = "y" ]; then
            read -p "Enter new SIGNER_ACCOUNT_ADDRESS (press enter to skip): " SIGNER_ACCOUNT_ADDRESS
            if [ ! -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
                read -s -p "Enter new SIGNER_ACCOUNT_PRIVATE_KEY: " SIGNER_ACCOUNT_PRIVATE_KEY
                echo
                sed -i".backup" "s#^SIGNER_ACCOUNT_ADDRESS=.*#SIGNER_ACCOUNT_ADDRESS=$SIGNER_ACCOUNT_ADDRESS#" ".env-${FULL_NAMESPACE}"
                sed -i".backup" "s#^SIGNER_ACCOUNT_PRIVATE_KEY=.*#SIGNER_ACCOUNT_PRIVATE_KEY=$SIGNER_ACCOUNT_PRIVATE_KEY#" ".env-${FULL_NAMESPACE}"
            fi

            read -p "Enter new SLOT_ID (NFT_ID) (press enter to skip): " SLOT_ID
            if [ ! -z "$SLOT_ID" ]; then
                sed -i".backup" "s#^SLOT_ID=.*#SLOT_ID=$SLOT_ID#" ".env-${FULL_NAMESPACE}"
            fi

            read -p "Enter new SOURCE_RPC_URL (press enter to skip): " SOURCE_RPC_URL
            if [ ! -z "$SOURCE_RPC_URL" ]; then
                sed -i".backup" "s#^SOURCE_RPC_URL=.*#SOURCE_RPC_URL=$SOURCE_RPC_URL#" ".env-${FULL_NAMESPACE}"
            fi
            echo "Feel free to ask for help in our Discord: https://discord.gg/powerloom if you need assistance in modifying your .env-${FULL_NAMESPACE} environment variables. DO NOT SHARE YOUR PRIVATE KEYS OR ANY SENSITIVE INFORMATION."
        fi
    fi
fi

# Source the environment file
source ".env-${FULL_NAMESPACE}"

# Subnet configuration
if [ -z "$SUBNET_THIRD_OCTET" ]; then
    SUBNET_THIRD_OCTET=1
    echo "🔔 SUBNET_THIRD_OCTET not found in .env, setting to default value ${SUBNET_THIRD_OCTET}"
fi

# Check if network exists and get its subnet
NETWORK_EXISTS=$(docker network ls --format '{{.Name}}' | grep -x "$DOCKER_NETWORK_NAME" || echo "")
EXISTING_NETWORK_SUBNET=""
if [ -n "$NETWORK_EXISTS" ]; then
    EXISTING_NETWORK_SUBNET=$(docker network inspect "$DOCKER_NETWORK_NAME" | grep -o '"Subnet": "[^"]*"' | cut -d'"' -f4)
fi

# Check if subnet is in use
SUBNET_IN_USE=$(docker network ls -q | xargs -I {} docker network inspect {} 2>/dev/null | grep -q "172.18.${SUBNET_THIRD_OCTET}" && echo "yes" || echo "no")

if [ "$SUBNET_IN_USE" = "yes" ] || \
   ([ -n "$NETWORK_EXISTS" ] && [ "$EXISTING_NETWORK_SUBNET" != "172.18.${SUBNET_THIRD_OCTET}.0/24" ]) || \
   [ -z "$NETWORK_EXISTS" ]; then
    echo "🟡 Warning: Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 appears to be already in use."
    if [ "$DOCKER_NETWORK_PRUNE" = "true" ]; then
        read -p "🫸 ▶︎  Would you like to prune unused Docker networks? (y/n): " PRUNE_NETWORKS
        if [ "$PRUNE_NETWORKS" = "y" ]; then
            docker network prune -f
            SUBNET_IN_USE=$(docker network ls -q | xargs -I {} docker network inspect {} 2>/dev/null | grep -q "172.18.${SUBNET_THIRD_OCTET}" && echo "yes" || echo "no")
        fi
    fi

    if [ "$SUBNET_IN_USE" = "yes" ]; then
        echo "🟡 Subnet 172.18.${SUBNET_THIRD_OCTET}.0/24 is already in use."
        echo "⏳ Searching for an available subnet..."
        FOUND_AVAILABLE_SUBNET=false
        
        for i in $(seq 1 255); do
            echo "Checking subnet 172.18.${i}.0/24..."
            SUBNET_IN_USE=$(docker network ls -q | xargs -I {} docker network inspect {} 2>/dev/null | grep -q "172.18.${i}" && echo "yes" || echo "no")
            
            if [ "$SUBNET_IN_USE" = "no" ]; then
                FOUND_AVAILABLE_SUBNET=true
                SUBNET_THIRD_OCTET=$i
                break
            fi
        done

        if [ "$FOUND_AVAILABLE_SUBNET" = "false" ]; then
            echo "❌ No available subnets found between 172.18.1.0/24 and 172.18.255.0/24"
            echo "🚧 Please check your docker networks and/or prune any unused networks."
            exit 1
        fi
    fi
fi

export DOCKER_NETWORK_SUBNET="172.18.${SUBNET_THIRD_OCTET}.0/24"

echo "Selected DOCKER_NETWORK_NAME: ${DOCKER_NETWORK_NAME}"
echo "Selected DOCKER_NETWORK_SUBNET: ${DOCKER_NETWORK_SUBNET}"

# Port configuration
if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051
    echo "🔔 LOCAL_COLLECTOR_PORT not found in .env, setting to default value ${LOCAL_COLLECTOR_PORT}"
fi

# UFW firewall configuration
if [ -x "$(command -v ufw)" ]; then
    ufw delete allow $LOCAL_COLLECTOR_PORT >> /dev/null
    ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT
    if [ $? -eq 0 ]; then
        echo "✅ ufw allow rule added for local collector port ${LOCAL_COLLECTOR_PORT} to allow connections from ${DOCKER_NETWORK_SUBNET}."
    else
        echo "❌ ufw firewall allow rule could not be added for local collector port ${LOCAL_COLLECTOR_PORT}."
        echo "Please attempt to add it manually with: sudo ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT"
        exit 1
    fi
else
    echo "🟡 ufw command not found, skipping firewall rule addition for local collector port ${LOCAL_COLLECTOR_PORT}."
    echo "If you are on a Linux VPS, please ensure that the port is open for connections from ${DOCKER_NETWORK_SUBNET} manually to ${LOCAL_COLLECTOR_PORT}."
fi

# Core API port configuration
if [ -z "$CORE_API_PORT" ]; then
    export CORE_API_PORT=8002
    echo "🔔 CORE_API_PORT not found in .env, setting to default value ${CORE_API_PORT}"
fi

# Check if port is in use
check_port() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -i:"$1" >/dev/null 2>&1
    else
        netstat -tuln | grep -q ":$1 "
    fi
}

while check_port $CORE_API_PORT; do
    echo "Port ${CORE_API_PORT} is already in use"
    CORE_API_PORT=$((CORE_API_PORT + 1))
done

echo "ℹ️ Using available port: ${CORE_API_PORT}"
sed -i'.backup' "s#^CORE_API_PORT=.*#CORE_API_PORT=$CORE_API_PORT#" ".env-${FULL_NAMESPACE}"

# Set default values for optional environment variables
if [ -z "$MAX_STREAM_POOL_SIZE" ]; then
    export MAX_STREAM_POOL_SIZE=2
    echo "🔔 MAX_STREAM_POOL_SIZE not found in .env, setting to default value ${MAX_STREAM_POOL_SIZE}"
fi

if [ -z "$STREAM_HEALTH_CHECK_TIMEOUT_MS" ]; then
    export STREAM_HEALTH_CHECK_TIMEOUT_MS=5000
    echo "🔔 STREAM_HEALTH_CHECK_TIMEOUT_MS not found in .env, setting to default value ${STREAM_HEALTH_CHECK_TIMEOUT_MS}"
fi

if [ -z "$STREAM_WRITE_TIMEOUT_MS" ]; then
    export STREAM_WRITE_TIMEOUT_MS=5000
    echo "🔔 STREAM_WRITE_TIMEOUT_MS not found in .env, setting to default value ${STREAM_WRITE_TIMEOUT_MS}"
fi

if [ -z "$MAX_WRITE_RETRIES" ]; then
    export MAX_WRITE_RETRIES=3
    echo "🔔 MAX_WRITE_RETRIES not found in .env, setting to default value ${MAX_WRITE_RETRIES}"
fi

if [ -z "$MAX_CONCURRENT_WRITES" ]; then
    export MAX_CONCURRENT_WRITES=4
    echo "🔔 MAX_CONCURRENT_WRITES not found in .env, setting to default value ${MAX_CONCURRENT_WRITES}"
fi

# Environment validation
if [ -z "$SOURCE_RPC_URL" ]; then
    echo "❌ RPC URL not found, please set this in your .env!"
    exit 1
fi

if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
    echo "❌ SIGNER_ACCOUNT_ADDRESS not found, please set this in your .env!"
    exit 1
fi

if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then
    echo "❌ SIGNER_ACCOUNT_PRIVATE_KEY not found, please set this in your .env!"
    exit 1
fi

# Export NO_COLLECTOR for use in deploy-services.sh
export NO_COLLECTOR

SETUP_COMPLETE=true
echo "✅ Configuration complete. Environment file ready at .env-${FULL_NAMESPACE}" 
