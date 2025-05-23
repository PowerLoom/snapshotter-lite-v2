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

export DATA_MARKET_CONTRACT_NUMBER="2"
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
    DATA_MARKET_CONTRACT="0x0000000000000000000000000000000000000000"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_aavev3_lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_aavev3_lite"
    NAMESPACE="AAVEV3"
elif [ "$DATA_MARKET_CONTRACT_CHOICE" = "2" ]; then
    echo "Uniswap V2 selected"
    DATA_MARKET_CONTRACT="0x21cb57C1f2352ad215a463DD867b838749CD3b8f"
    SNAPSHOT_CONFIG_REPO_BRANCH="eth_uniswapv2-lite_v2"
    SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_uniswapv2_lite_v2"
    NAMESPACE="UNISWAPV2"
fi

# Set protocol values
export PROTOCOL_STATE_CONTRACT="0x000AA7d3a6a2556496f363B59e56D9aA1881548F"
export POWERLOOM_RPC_URL="https://rpc-v2.powerloom.network"
export POWERLOOM_CHAIN=mainnet
export SOURCE_CHAIN=ETH
export FULL_NAMESPACE="${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"
export CONNECTION_REFRESH_INTERVAL_SEC=60

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
    export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${FULL_NAMESPACE}"
    
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
    sed -i".backup" "s#<powerloom-rpc-url>#$POWERLOOM_RPC_URL#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<docker-network-name>#$DOCKER_NETWORK_NAME#" ".env-${FULL_NAMESPACE}"
    sed -i".backup" "s#<seq-conn-refresh-interval>#$CONNECTION_REFRESH_INTERVAL_SEC#" ".env-${FULL_NAMESPACE}"
    echo "🟢 .env-${FULL_NAMESPACE} file created successfully."
else
    echo "🟢 .env-${FULL_NAMESPACE} file found."

    # override DATA_MARKET_CONTRACT if DATA_MARKET_CONTRACT_NUMBER is set to 2
    if [ "$DATA_MARKET_CONTRACT_NUMBER" = "2" ]; then
        echo "🔔 Overriding DATA_MARKET_CONTRACT to use Uniswap V2 contract address"
        sed -i".backup" "s#DATA_MARKET_CONTRACT=.*#DATA_MARKET_CONTRACT=0x21cb57C1f2352ad215a463DD867b838749CD3b8f#" ".env-${FULL_NAMESPACE}"
    fi

    # Check if POWERLOOM_RPC_URL exists in the file, if not add it, otherwise update it
    if grep -q "POWERLOOM_RPC_URL=" ".env-${FULL_NAMESPACE}"; then
        sed -i".backup" "s#POWERLOOM_RPC_URL=.*#POWERLOOM_RPC_URL=$POWERLOOM_RPC_URL#" ".env-${FULL_NAMESPACE}"
    else
        # Check if the file ends with a newline, if not add one before appending
        if [ -s ".env-${FULL_NAMESPACE}" ] && [ "$(tail -c 1 ".env-${FULL_NAMESPACE}" | wc -l)" -eq 0 ]; then
            echo "" >> ".env-${FULL_NAMESPACE}"
        fi
        echo "POWERLOOM_RPC_URL=$POWERLOOM_RPC_URL" >> ".env-${FULL_NAMESPACE}"
    fi

    # check if CONNECTION_REFRESH_INTERVAL_SEC exists in the file, if not add it, otherwise update it
    if grep -q "CONNECTION_REFRESH_INTERVAL_SEC=" ".env-${FULL_NAMESPACE}"; then
        sed -i".backup" "s#CONNECTION_REFRESH_INTERVAL_SEC=.*#CONNECTION_REFRESH_INTERVAL_SEC=$CONNECTION_REFRESH_INTERVAL_SEC#" ".env-${FULL_NAMESPACE}"
    else
        echo "CONNECTION_REFRESH_INTERVAL_SEC=$CONNECTION_REFRESH_INTERVAL_SEC" >> ".env-${FULL_NAMESPACE}"
    fi

    # Check if TELEGRAM_NOTIFICATION_COOLDOWN exists in the file, if not add it, otherwise update it
    if grep -q "TELEGRAM_NOTIFICATION_COOLDOWN=" ".env-${FULL_NAMESPACE}"; then
        sed -i".backup" "s#TELEGRAM_NOTIFICATION_COOLDOWN=.*#TELEGRAM_NOTIFICATION_COOLDOWN=300#" ".env-${FULL_NAMESPACE}"
    else
        # Check if the file ends with a newline, if not add one before appending
        if [ -s ".env-${FULL_NAMESPACE}" ] && [ "$(tail -c 1 ".env-${FULL_NAMESPACE}" | wc -l)" -eq 0 ]; then
            echo "" >> ".env-${FULL_NAMESPACE}"
        fi
        echo "TELEGRAM_NOTIFICATION_COOLDOWN=300" >> ".env-${FULL_NAMESPACE}"
    fi

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

# Port configuration
if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051
    echo "🔔 LOCAL_COLLECTOR_PORT not found in .env, setting to default value ${LOCAL_COLLECTOR_PORT}"
fi


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
