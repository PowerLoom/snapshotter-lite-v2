#!/bin/bash

# Initial variable declarations
DOCKER_NETWORK_PRUNE=false
SETUP_COMPLETE=true
DATA_MARKET_CONTRACT_NUMBER=""
SKIP_CREDENTIAL_UPDATE=false
NO_COLLECTOR=false
OVERRIDE_DEFAULTS_SCRIPT_FLAG=false

# --- Define Top-Level Fixed Defaults ---
DEFAULT_POWERLOOM_CHAIN="mainnet"
DEFAULT_SOURCE_CHAIN="ETH"
DEFAULT_NAMESPACE="UNISWAPV2"
DEFAULT_POWERLOOM_RPC_URL="https://rpc-v2.powerloom.network"
DEFAULT_PROTOCOL_STATE_CONTRACT="0x000AA7d3a6a2556496f363B59e56D9aA1881548F"
DEFAULT_SNAPSHOT_CONFIG_REPO_BRANCH="eth_uniswapv2-lite_v2"
DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_uniswapv2_lite_v2"
DEFAULT_CONNECTION_REFRESH_INTERVAL_SEC=60
DEFAULT_TELEGRAM_NOTIFICATION_COOLDOWN=300

# --- Initialize Working Configuration Variables from Fixed Defaults ---
POWERLOOM_CHAIN="$DEFAULT_POWERLOOM_CHAIN"
SOURCE_CHAIN="$DEFAULT_SOURCE_CHAIN"
NAMESPACE="$DEFAULT_NAMESPACE"
POWERLOOM_RPC_URL="$DEFAULT_POWERLOOM_RPC_URL"
PROTOCOL_STATE_CONTRACT="$DEFAULT_PROTOCOL_STATE_CONTRACT"
SNAPSHOT_CONFIG_REPO_BRANCH="$DEFAULT_SNAPSHOT_CONFIG_REPO_BRANCH"
SNAPSHOTTER_COMPUTE_REPO_BRANCH="$DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH"
CONNECTION_REFRESH_INTERVAL_SEC="$DEFAULT_CONNECTION_REFRESH_INTERVAL_SEC"
TELEGRAM_NOTIFICATION_COOLDOWN="$DEFAULT_TELEGRAM_NOTIFICATION_COOLDOWN"
DATA_MARKET_CONTRACT=""

# --- .env File Detection and Selection ---
ENV_FILE_PATH=""
FILE_CONTAINS_OVERRIDES="false"
EXISTING_ENV_FILES=( $(find . -maxdepth 1 -name ".env-*" -type f) )
NUM_EXISTING_ENV_FILES=${#EXISTING_ENV_FILES[@]}
SELECTED_ENV_FILE=""
FILE_WAS_NEWLY_CREATED=false

if [ "$NUM_EXISTING_ENV_FILES" -eq 1 ]; then
    SELECTED_ENV_FILE="${EXISTING_ENV_FILES[0]}"
    echo "ℹ️ Auto-selected existing environment file: $SELECTED_ENV_FILE"
elif [ "$NUM_EXISTING_ENV_FILES" -gt 1 ]; then
    echo "Found multiple .env-* files. Please choose which one to use:"
    for i in "${!EXISTING_ENV_FILES[@]}"; do
        echo "$((i+1))) ${EXISTING_ENV_FILES[$i]}"
    done
    read -p "Enter number (1-$NUM_EXISTING_ENV_FILES): " FILE_CHOICE
    if [[ "$FILE_CHOICE" =~ ^[0-9]+$ ]] && [ "$FILE_CHOICE" -ge 1 ] && [ "$FILE_CHOICE" -le "$NUM_EXISTING_ENV_FILES" ]; then
        SELECTED_ENV_FILE="${EXISTING_ENV_FILES[$((FILE_CHOICE-1))]}"
        echo "ℹ️ You selected: $SELECTED_ENV_FILE"
    else
        echo "❌ Invalid selection. Exiting."
        exit 1
    fi
fi

if [ -n "$SELECTED_ENV_FILE" ]; then
    ENV_FILE_PATH="$SELECTED_ENV_FILE"
    echo "🟢 Using environment file: $ENV_FILE_PATH"
    source "$ENV_FILE_PATH"
    FILE_CONTAINS_OVERRIDES=$(grep "^OVERRIDE_DEFAULTS=" "$ENV_FILE_PATH" | cut -d'=' -f2 || echo "false")
fi

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
        --override)
            OVERRIDE_DEFAULTS_SCRIPT_FLAG=true
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

final_cleanup_handler() {
    find . -name "*.backup" -type f -delete
    if [ "$CLEANUP_ENV_FILE_ON_ABORT" = true ] && [ -n "$TARGET_ENV_FILE_FOR_CLEANUP" ] && [ -f "$TARGET_ENV_FILE_FOR_CLEANUP" ] && [ "$SETUP_COMPLETE" = false ]; then
        rm -f "$TARGET_ENV_FILE_FOR_CLEANUP"
        echo "Aborted setup. Deleted partially created $TARGET_ENV_FILE_FOR_CLEANUP file."
    elif [ "$SETUP_COMPLETE" = false ] && [ -n "$ENV_FILE_PATH" ]; then
        echo "Setup incomplete or aborted. Please review $ENV_FILE_PATH as it might be in an inconsistent state."
    elif [ "$SETUP_COMPLETE" = false ]; then
        echo "Setup incomplete or aborted."
    fi
}

trap 'handle_error $LINENO; final_cleanup_handler' ERR
trap final_cleanup_handler EXIT

# Docker daemon check
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not running"
    exit 1
fi

# Helper function to update a variable in a file or append it if it doesn't exist
update_or_append_var() {
    local var_name="$1"
    local var_value="$2"
    local target_file="$3"

    if grep -q "^${var_name}=" "$target_file"; then
        local sed_safe_var_value=$(echo "$var_value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/#/\\#/g')
        sed -i".backup" "s#^${var_name}=.*#${var_name}=${sed_safe_var_value}#" "$target_file"
    else
        if [ -s "$target_file" ] && [ "$(tail -c 1 "$target_file" | wc -l)" -eq 0 ]; then
            echo "" >> "$target_file"
        fi
        echo "${var_name}=${var_value}" >> "$target_file"
    fi
}

CLEANUP_ENV_FILE_ON_ABORT=false
TARGET_ENV_FILE_FOR_CLEANUP=""


if [ "$OVERRIDE_DEFAULTS_SCRIPT_FLAG" = "true" ]; then
    SETUP_COMPLETE=false
    echo "🔧 Custom configuration mode enabled via --override flag."
    
    echo "Select POWERLOOM_CHAIN:"
    echo "1. mainnet (default)"
    echo "2. devnet"
    echo "3. staging"
    read -p "Enter choice (1-3) [default: 1]: " POWERLOOM_CHAIN_CHOICE_INPUT
    POWERLOOM_CHAIN_CHOICE=${POWERLOOM_CHAIN_CHOICE_INPUT:-1} 

    while ! [[ "$POWERLOOM_CHAIN_CHOICE" =~ ^[1-3]$ ]]; do
        read -p "Invalid input. Enter choice (1-3): " POWERLOOM_CHAIN_CHOICE
    done

    case $POWERLOOM_CHAIN_CHOICE in
        1) export POWERLOOM_CHAIN="mainnet" ;;
        2) export POWERLOOM_CHAIN="devnet" ;;
        3) export POWERLOOM_CHAIN="staging" ;;
    esac
    echo "Selected POWERLOOM_CHAIN: $POWERLOOM_CHAIN"

    read -p "Enter NAMESPACE (e.g., UNISWAPV2, AAVEV3, or custom name) [default: $DEFAULT_NAMESPACE]: " NAMESPACE_INPUT
    export NAMESPACE=${NAMESPACE_INPUT:-$DEFAULT_NAMESPACE}
    echo "Selected NAMESPACE: $NAMESPACE"

    read -p "Enter SOURCE_CHAIN (e.g., ETH) [default: $DEFAULT_SOURCE_CHAIN]: " SOURCE_CHAIN_INPUT
    export SOURCE_CHAIN=${SOURCE_CHAIN_INPUT:-$DEFAULT_SOURCE_CHAIN}
    echo "Selected SOURCE_CHAIN: $SOURCE_CHAIN"

    read -p "Enter POWERLOOM_RPC_URL [default: $DEFAULT_POWERLOOM_RPC_URL]: " POWERLOOM_RPC_URL_INPUT
    export POWERLOOM_RPC_URL=${POWERLOOM_RPC_URL_INPUT:-$DEFAULT_POWERLOOM_RPC_URL}

    read -p "Enter PROTOCOL_STATE_CONTRACT [default: $DEFAULT_PROTOCOL_STATE_CONTRACT]: " PROTOCOL_STATE_CONTRACT_INPUT
    export PROTOCOL_STATE_CONTRACT=${PROTOCOL_STATE_CONTRACT_INPUT:-$DEFAULT_PROTOCOL_STATE_CONTRACT}

    read -p "Enter DATA_MARKET_CONTRACT: " DATA_MARKET_CONTRACT_INPUT
    while [ -z "$DATA_MARKET_CONTRACT_INPUT" ]; do
        read -p "DATA_MARKET_CONTRACT cannot be empty. Enter DATA_MARKET_CONTRACT: " DATA_MARKET_CONTRACT_INPUT
    done
    export DATA_MARKET_CONTRACT="$DATA_MARKET_CONTRACT_INPUT"

    read -p "Would you like to specify custom snapshot configuration and compute repository branches? (y/n) [default: n]: " OVERRIDE_BRANCHES_CHOICE
    OVERRIDE_BRANCHES_CHOICE=${OVERRIDE_BRANCHES_CHOICE:-n}

    if [[ "$OVERRIDE_BRANCHES_CHOICE" =~ ^[Yy]$ ]]; then
        read -p "Enter SNAPSHOT_CONFIG_REPO_BRANCH [default: $DEFAULT_SNAPSHOT_CONFIG_REPO_BRANCH]: " SNAPSHOT_CONFIG_REPO_BRANCH_INPUT
        export SNAPSHOT_CONFIG_REPO_BRANCH=${SNAPSHOT_CONFIG_REPO_BRANCH_INPUT:-$DEFAULT_SNAPSHOT_CONFIG_REPO_BRANCH}
        read -p "Enter SNAPSHOTTER_COMPUTE_REPO_BRANCH [default: $DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH]: " SNAPSHOTTER_COMPUTE_REPO_BRANCH_INPUT
        export SNAPSHOTTER_COMPUTE_REPO_BRANCH=${SNAPSHOTTER_COMPUTE_REPO_BRANCH_INPUT:-$DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH}
    else
        export SNAPSHOT_CONFIG_REPO_BRANCH="$DEFAULT_SNAPSHOT_CONFIG_REPO_BRANCH"
        export SNAPSHOTTER_COMPUTE_REPO_BRANCH="$DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH"
    fi
    echo "Selected SNAPSHOT_CONFIG_REPO_BRANCH: $SNAPSHOT_CONFIG_REPO_BRANCH"
    echo "Selected SNAPSHOTTER_COMPUTE_REPO_BRANCH: $SNAPSHOTTER_COMPUTE_REPO_BRANCH"

    export FULL_NAMESPACE="${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"
    TARGET_ENV_FILE_FOR_OVERRIDES=".env-${FULL_NAMESPACE}"

    if [ -n "$ENV_FILE_PATH" ] && [ "$ENV_FILE_PATH" != "$TARGET_ENV_FILE_FOR_OVERRIDES" ]; then
        echo "ℹ️ Configuration values resulted in a new target .env file: $TARGET_ENV_FILE_FOR_OVERRIDES"
        echo "Previously selected file was: $ENV_FILE_PATH (if any)."
    elif [ -z "$ENV_FILE_PATH" ]; then
         echo "ℹ️ Creating new configuration based on overrides: $TARGET_ENV_FILE_FOR_OVERRIDES"
    fi
    ENV_FILE_PATH="$TARGET_ENV_FILE_FOR_OVERRIDES"

    if [ ! -f "$ENV_FILE_PATH" ]; then
        echo "🟡 $ENV_FILE_PATH file not found, creating one based on overrides..."
        cp env.example "$ENV_FILE_PATH"
        CLEANUP_ENV_FILE_ON_ABORT=true
        TARGET_ENV_FILE_FOR_CLEANUP="$ENV_FILE_PATH"
        read -p "Enter SOURCE_RPC_URL: " SOURCE_RPC_URL_VAL
        update_or_append_var "SOURCE_RPC_URL" "$SOURCE_RPC_URL_VAL" "$ENV_FILE_PATH"
        read -p "Enter SIGNER_ACCOUNT_ADDRESS: " SIGNER_ACCOUNT_ADDRESS_VAL
        update_or_append_var "SIGNER_ACCOUNT_ADDRESS" "$SIGNER_ACCOUNT_ADDRESS_VAL" "$ENV_FILE_PATH"
        read -s -p "Enter SIGNER_ACCOUNT_PRIVATE_KEY: " SIGNER_ACCOUNT_PRIVATE_KEY_VAL; echo
        update_or_append_var "SIGNER_ACCOUNT_PRIVATE_KEY" "$SIGNER_ACCOUNT_PRIVATE_KEY_VAL" "$ENV_FILE_PATH"
        read -p "Enter Your SLOT_ID (NFT_ID): " SLOT_ID_VAL
        update_or_append_var "SLOT_ID" "$SLOT_ID_VAL" "$ENV_FILE_PATH"
        read -p "Enter Your TELEGRAM_CHAT_ID (Optional, leave blank to skip.): " TELEGRAM_CHAT_ID_VAL
        update_or_append_var "TELEGRAM_CHAT_ID" "$TELEGRAM_CHAT_ID_VAL" "$ENV_FILE_PATH"
        FILE_WAS_NEWLY_CREATED=true # Set flag as file was just created and prompted for initial values
    else
        echo "🟢 $ENV_FILE_PATH found. Will update it with override values."
    fi
 
    export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${FULL_NAMESPACE}"
  
    update_or_append_var "POWERLOOM_CHAIN" "$POWERLOOM_CHAIN" "$ENV_FILE_PATH"
    update_or_append_var "NAMESPACE" "$NAMESPACE" "$ENV_FILE_PATH"
    update_or_append_var "SOURCE_CHAIN" "$SOURCE_CHAIN" "$ENV_FILE_PATH"
    update_or_append_var "POWERLOOM_RPC_URL" "$POWERLOOM_RPC_URL" "$ENV_FILE_PATH"
    update_or_append_var "PROTOCOL_STATE_CONTRACT" "$PROTOCOL_STATE_CONTRACT" "$ENV_FILE_PATH"
    update_or_append_var "DATA_MARKET_CONTRACT" "$DATA_MARKET_CONTRACT" "$ENV_FILE_PATH"
    update_or_append_var "SNAPSHOT_CONFIG_REPO_BRANCH" "$SNAPSHOT_CONFIG_REPO_BRANCH" "$ENV_FILE_PATH"
    update_or_append_var "SNAPSHOTTER_COMPUTE_REPO_BRANCH" "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" "$ENV_FILE_PATH"
    update_or_append_var "FULL_NAMESPACE" "$FULL_NAMESPACE" "$ENV_FILE_PATH"
    update_or_append_var "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME" "$ENV_FILE_PATH"
    update_or_append_var "CONNECTION_REFRESH_INTERVAL_SEC" "$CONNECTION_REFRESH_INTERVAL_SEC" "$ENV_FILE_PATH"
    update_or_append_var "TELEGRAM_NOTIFICATION_COOLDOWN" "$TELEGRAM_NOTIFICATION_COOLDOWN" "$ENV_FILE_PATH"
  
    update_or_append_var "OVERRIDE_DEFAULTS" "true" "$ENV_FILE_PATH"
    echo "✅ $ENV_FILE_PATH configured with overrides."

elif [ -n "$ENV_FILE_PATH" ]; then # No --override flag, but a .env file was selected/found
    echo "🟢 Operating on selected environment file: $ENV_FILE_PATH"
    
    if [ "$FILE_CONTAINS_OVERRIDES" = "true" ]; then
        echo "🔔 $ENV_FILE_PATH has OVERRIDE_DEFAULTS=true. Preserving existing overrides."
        update_or_append_var "OVERRIDE_DEFAULTS" "true" "$ENV_FILE_PATH"
    else
        echo "🔔 $ENV_FILE_PATH has OVERRIDE_DEFAULTS=false (or not set). Applying standard script defaults/updates."
        if [ -n "$DATA_MARKET_CONTRACT_NUMBER" ] && [ "$DATA_MARKET_CONTRACT_NUMBER" = "2" ]; then
            UNISWAP_V2_DM_CONTRACT="0x21cb57C1f2352ad215a463DD867b838749CD3b8f"
            CURRENT_DM_CONTRACT_IN_FILE=$(grep "^DATA_MARKET_CONTRACT=" "$ENV_FILE_PATH" | cut -d'=' -f2- || echo "")
            if [ "$CURRENT_DM_CONTRACT_IN_FILE" != "$UNISWAP_V2_DM_CONTRACT" ]; then
                echo "🔔 Ensuring DATA_MARKET_CONTRACT is Uniswap V2 in $ENV_FILE_PATH due to contract number selection."
                update_or_append_var "DATA_MARKET_CONTRACT" "$UNISWAP_V2_DM_CONTRACT" "$ENV_FILE_PATH"
            fi
            export DATA_MARKET_CONTRACT="$UNISWAP_V2_DM_CONTRACT"
        fi
  
        echo "🔔 Ensuring $ENV_FILE_PATH reflects current script's global defaults for RPC, Connection Interval, and Telegram Cooldown."
        update_or_append_var "POWERLOOM_RPC_URL" "$DEFAULT_POWERLOOM_RPC_URL" "$ENV_FILE_PATH"
        export POWERLOOM_RPC_URL="$DEFAULT_POWERLOOM_RPC_URL"

        update_or_append_var "CONNECTION_REFRESH_INTERVAL_SEC" "$DEFAULT_CONNECTION_REFRESH_INTERVAL_SEC" "$ENV_FILE_PATH"
        export CONNECTION_REFRESH_INTERVAL_SEC="$DEFAULT_CONNECTION_REFRESH_INTERVAL_SEC"
        
        update_or_append_var "TELEGRAM_NOTIFICATION_COOLDOWN" "$DEFAULT_TELEGRAM_NOTIFICATION_COOLDOWN" "$ENV_FILE_PATH"
        export TELEGRAM_NOTIFICATION_COOLDOWN="$DEFAULT_TELEGRAM_NOTIFICATION_COOLDOWN"
        
        update_or_append_var "OVERRIDE_DEFAULTS" "false" "$ENV_FILE_PATH"
    fi

    export FULL_NAMESPACE="${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"
    update_or_append_var "FULL_NAMESPACE" "$FULL_NAMESPACE" "$ENV_FILE_PATH"
    export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${FULL_NAMESPACE}"
    update_or_append_var "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME" "$ENV_FILE_PATH"

else # No --override flag AND no .env file was selected/found. Create a new default one.
    echo "🔧 No .env file specified or found, and --override not used. Proceeding to create a new default configuration."

    if [ -z "$DATA_MARKET_CONTRACT_NUMBER" ]; then
        DATA_MARKET_CONTRACT_NUMBER="2" # Default to Uniswap V2 if no arg
    fi

    if [ -n "$DATA_MARKET_CONTRACT_NUMBER" ]; then
        DATA_MARKET_CONTRACT_CHOICE="$DATA_MARKET_CONTRACT_NUMBER"
    else
        echo "🔍 Select a data market contract: "
        echo "1. Aave V3"
        echo "2. Uniswap V2 (default)"
        read DATA_MARKET_CONTRACT_CHOICE
        if [ -z "$DATA_MARKET_CONTRACT_CHOICE" ] || ! [[ "$DATA_MARKET_CONTRACT_CHOICE" =~ ^[12]$ ]]; then
            DATA_MARKET_CONTRACT_CHOICE="2"
            echo "Using default: Uniswap V2"
        fi
    fi

    if [ "$DATA_MARKET_CONTRACT_CHOICE" = "1" ]; then
        echo "Aave V3 selected"
        export DATA_MARKET_CONTRACT="0x0000000000000000000000000000000000000000"
        export SNAPSHOT_CONFIG_REPO_BRANCH="eth_aavev3_lite_v2"
        export SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_aavev3_lite"
        export NAMESPACE="AAVEV3"
    elif [ "$DATA_MARKET_CONTRACT_CHOICE" = "2" ]; then
        echo "Uniswap V2 selected"
        export DATA_MARKET_CONTRACT="0x21cb57C1f2352ad215a463DD867b838749CD3b8f"
        export SNAPSHOT_CONFIG_REPO_BRANCH="eth_uniswapv2-lite_v2"
        export SNAPSHOTTER_COMPUTE_REPO_BRANCH="eth_uniswapv2_lite_v2"
        export NAMESPACE="UNISWAPV2"
    fi

    export POWERLOOM_CHAIN
    export SOURCE_CHAIN
    export POWERLOOM_RPC_URL
    export PROTOCOL_STATE_CONTRACT
    export CONNECTION_REFRESH_INTERVAL_SEC
    export TELEGRAM_NOTIFICATION_COOLDOWN

    export FULL_NAMESPACE="${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"
    ENV_FILE_PATH=".env-${FULL_NAMESPACE}"

    echo "🟡 $ENV_FILE_PATH file not found, creating one..."
    cp env.example "$ENV_FILE_PATH"
    CLEANUP_ENV_FILE_ON_ABORT=true
    TARGET_ENV_FILE_FOR_CLEANUP="$ENV_FILE_PATH"

    update_or_append_var "DATA_MARKET_CONTRACT" "$DATA_MARKET_CONTRACT" "$ENV_FILE_PATH"
    update_or_append_var "PROTOCOL_STATE_CONTRACT" "$PROTOCOL_STATE_CONTRACT" "$ENV_FILE_PATH"
    update_or_append_var "SNAPSHOT_CONFIG_REPO_BRANCH" "$SNAPSHOT_CONFIG_REPO_BRANCH" "$ENV_FILE_PATH"
    update_or_append_var "SNAPSHOTTER_COMPUTE_REPO_BRANCH" "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" "$ENV_FILE_PATH"
    update_or_append_var "POWERLOOM_CHAIN" "$POWERLOOM_CHAIN" "$ENV_FILE_PATH"
    update_or_append_var "SOURCE_CHAIN" "$SOURCE_CHAIN" "$ENV_FILE_PATH"
    update_or_append_var "NAMESPACE" "$NAMESPACE" "$ENV_FILE_PATH"
    update_or_append_var "FULL_NAMESPACE" "$FULL_NAMESPACE" "$ENV_FILE_PATH"
    update_or_append_var "POWERLOOM_RPC_URL" "$POWERLOOM_RPC_URL" "$ENV_FILE_PATH"
    
    export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${FULL_NAMESPACE}"
    update_or_append_var "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME" "$ENV_FILE_PATH"
    update_or_append_var "CONNECTION_REFRESH_INTERVAL_SEC" "$CONNECTION_REFRESH_INTERVAL_SEC" "$ENV_FILE_PATH"
    update_or_append_var "TELEGRAM_NOTIFICATION_COOLDOWN" "$TELEGRAM_NOTIFICATION_COOLDOWN" "$ENV_FILE_PATH"


    # Prompt for other required values
    read -p "Enter SOURCE_RPC_URL: " SOURCE_RPC_URL_VAL
    update_or_append_var "SOURCE_RPC_URL" "$SOURCE_RPC_URL_VAL" "$ENV_FILE_PATH"
    read -p "Enter SIGNER_ACCOUNT_ADDRESS: " SIGNER_ACCOUNT_ADDRESS_VAL
    update_or_append_var "SIGNER_ACCOUNT_ADDRESS" "$SIGNER_ACCOUNT_ADDRESS_VAL" "$ENV_FILE_PATH"
    read -s -p "Enter SIGNER_ACCOUNT_PRIVATE_KEY: " SIGNER_ACCOUNT_PRIVATE_KEY_VAL; echo
    update_or_append_var "SIGNER_ACCOUNT_PRIVATE_KEY" "$SIGNER_ACCOUNT_PRIVATE_KEY_VAL" "$ENV_FILE_PATH"
    read -p "Enter Your SLOT_ID (NFT_ID): " SLOT_ID_VAL
    update_or_append_var "SLOT_ID" "$SLOT_ID_VAL" "$ENV_FILE_PATH"
    read -p "Enter Your TELEGRAM_CHAT_ID (Optional, leave blank to skip.): " TELEGRAM_CHAT_ID_VAL
    update_or_append_var "TELEGRAM_CHAT_ID" "$TELEGRAM_CHAT_ID_VAL" "$ENV_FILE_PATH"
    FILE_WAS_NEWLY_CREATED=true # Set flag as file was just created and prompted for initial values
    
    update_or_append_var "OVERRIDE_DEFAULTS" "false" "$ENV_FILE_PATH"
    echo "🟢 $ENV_FILE_PATH file created successfully."
fi


if [ -z "$ENV_FILE_PATH" ]; then
    echo "❌ Critical error: ENV_FILE_PATH is not set. Exiting."
    exit 1
fi

if [ "$SKIP_CREDENTIAL_UPDATE" = "true" ]; then
    echo "🔔 Skipping credential update prompts due to --skip-credential-update flag"
elif [ "$FILE_WAS_NEWLY_CREATED" = "true" ]; then
    echo "ℹ️ Skipping update prompt as $ENV_FILE_PATH was just created and configured."
else
    if [ -f "$ENV_FILE_PATH" ]; then
        source "$ENV_FILE_PATH"
    fi

    read -p "🫸 ▶︎  Would you like to update any of the environment variables in $ENV_FILE_PATH? (y/n): " UPDATE_ENV_VARS
    if [ "$UPDATE_ENV_VARS" = "y" ]; then
        SETUP_COMPLETE=false
        
        read -p "Enter new SIGNER_ACCOUNT_ADDRESS (current: ${SIGNER_ACCOUNT_ADDRESS:-<not set>}, press enter to skip): " NEW_SIGNER_ACCOUNT_ADDRESS
        if [ -n "$NEW_SIGNER_ACCOUNT_ADDRESS" ]; then
            read -s -p "Enter new SIGNER_ACCOUNT_PRIVATE_KEY: " NEW_SIGNER_ACCOUNT_PRIVATE_KEY; echo
            update_or_append_var "SIGNER_ACCOUNT_ADDRESS" "$NEW_SIGNER_ACCOUNT_ADDRESS" "$ENV_FILE_PATH"
            update_or_append_var "SIGNER_ACCOUNT_PRIVATE_KEY" "$NEW_SIGNER_ACCOUNT_PRIVATE_KEY" "$ENV_FILE_PATH"
            export SIGNER_ACCOUNT_ADDRESS="$NEW_SIGNER_ACCOUNT_ADDRESS"
            export SIGNER_ACCOUNT_PRIVATE_KEY="$NEW_SIGNER_ACCOUNT_PRIVATE_KEY"
        fi

        read -p "Enter new SLOT_ID (NFT_ID) (current: ${SLOT_ID:-<not set>}, press enter to skip): " NEW_SLOT_ID
        if [ -n "$NEW_SLOT_ID" ]; then
            update_or_append_var "SLOT_ID" "$NEW_SLOT_ID" "$ENV_FILE_PATH"
            export SLOT_ID="$NEW_SLOT_ID"
        fi

        read -p "Enter new SOURCE_RPC_URL (current: ${SOURCE_RPC_URL:-<not set>}, press enter to skip): " NEW_SOURCE_RPC_URL
        if [ -n "$NEW_SOURCE_RPC_URL" ]; then
            update_or_append_var "SOURCE_RPC_URL" "$NEW_SOURCE_RPC_URL" "$ENV_FILE_PATH"
            export SOURCE_RPC_URL="$NEW_SOURCE_RPC_URL"
        fi
        echo "Feel free to ask for help in our Discord: https://discord.gg/powerloom if you need assistance. DO NOT SHARE YOUR PRIVATE KEYS."
    fi
fi
 
if [ ! -f "$ENV_FILE_PATH" ]; then
    echo "❌ Error: Environment file $ENV_FILE_PATH not found before final sourcing. This should not happen. Exiting."
    exit 1
fi
source "$ENV_FILE_PATH"

# Port configuration
if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051
    echo "🔔 LOCAL_COLLECTOR_PORT not found in $ENV_FILE_PATH, setting to default value ${LOCAL_COLLECTOR_PORT} and adding to file."
    update_or_append_var "LOCAL_COLLECTOR_PORT" "$LOCAL_COLLECTOR_PORT" "$ENV_FILE_PATH"
fi


# Set default values for optional environment variables
if [ -z "$MAX_STREAM_POOL_SIZE" ]; then
    export MAX_STREAM_POOL_SIZE=2
    echo "🔔 MAX_STREAM_POOL_SIZE not found in $ENV_FILE_PATH, setting to default value ${MAX_STREAM_POOL_SIZE} and adding to file."
    update_or_append_var "MAX_STREAM_POOL_SIZE" "$MAX_STREAM_POOL_SIZE" "$ENV_FILE_PATH"
fi

if [ -z "$STREAM_HEALTH_CHECK_TIMEOUT_MS" ]; then
    export STREAM_HEALTH_CHECK_TIMEOUT_MS=5000
    echo "🔔 STREAM_HEALTH_CHECK_TIMEOUT_MS not found in $ENV_FILE_PATH, setting to default value ${STREAM_HEALTH_CHECK_TIMEOUT_MS} and adding to file."
    update_or_append_var "STREAM_HEALTH_CHECK_TIMEOUT_MS" "$STREAM_HEALTH_CHECK_TIMEOUT_MS" "$ENV_FILE_PATH"
fi

if [ -z "$STREAM_WRITE_TIMEOUT_MS" ]; then
    export STREAM_WRITE_TIMEOUT_MS=5000
    echo "🔔 STREAM_WRITE_TIMEOUT_MS not found in $ENV_FILE_PATH, setting to default value ${STREAM_WRITE_TIMEOUT_MS} and adding to file."
    update_or_append_var "STREAM_WRITE_TIMEOUT_MS" "$STREAM_WRITE_TIMEOUT_MS" "$ENV_FILE_PATH"
fi

if [ -z "$MAX_WRITE_RETRIES" ]; then
    export MAX_WRITE_RETRIES=3
    echo "🔔 MAX_WRITE_RETRIES not found in $ENV_FILE_PATH, setting to default value ${MAX_WRITE_RETRIES} and adding to file."
    update_or_append_var "MAX_WRITE_RETRIES" "$MAX_WRITE_RETRIES" "$ENV_FILE_PATH"
fi

if [ -z "$MAX_CONCURRENT_WRITES" ]; then
    export MAX_CONCURRENT_WRITES=4
    echo "🔔 MAX_CONCURRENT_WRITES not found in $ENV_FILE_PATH, setting to default value ${MAX_CONCURRENT_WRITES} and adding to file."
    update_or_append_var "MAX_CONCURRENT_WRITES" "$MAX_CONCURRENT_WRITES" "$ENV_FILE_PATH"
fi


# Environment validation
SETUP_COMPLETE=true

if [ -z "$POWERLOOM_CHAIN" ]; then echo "❌ POWERLOOM_CHAIN not set!"; SETUP_COMPLETE=false; fi
if [ -z "$NAMESPACE" ]; then echo "❌ NAMESPACE not set!"; SETUP_COMPLETE=false; fi
if [ -z "$SOURCE_CHAIN" ]; then echo "❌ SOURCE_CHAIN not set!"; SETUP_COMPLETE=false; fi
if [ -z "$POWERLOOM_RPC_URL" ]; then echo "❌ POWERLOOM_RPC_URL not set for $POWERLOOM_CHAIN (or is empty)!"; SETUP_COMPLETE=false; fi
if [[ "$POWERLOOM_CHAIN" == "mainnet" || "$POWERLOOM_CHAIN" == "devnet" ]] && [ -z "$PROTOCOL_STATE_CONTRACT" ]; then
    if [ "$POWERLOOM_CHAIN" != "staging" ] || [ -n "$DEFAULT_PROTOCOL_STATE_CONTRACT_STAGING" ]; then
       echo "❌ PROTOCOL_STATE_CONTRACT not set for $POWERLOOM_CHAIN!"; SETUP_COMPLETE=false;
    fi
fi
if [ -z "$SOURCE_RPC_URL" ]; then echo "❌ SOURCE_RPC_URL not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then echo "❌ SIGNER_ACCOUNT_ADDRESS not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then echo "❌ SIGNER_ACCOUNT_PRIVATE_KEY not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$SLOT_ID" ]; then echo "❌ SLOT_ID not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$DATA_MARKET_CONTRACT" ]; then echo "❌ DATA_MARKET_CONTRACT not found after configuration!"; SETUP_COMPLETE=false; fi
if [ -z "$SNAPSHOT_CONFIG_REPO_BRANCH" ]; then echo "❌ SNAPSHOT_CONFIG_REPO_BRANCH not found after configuration!"; SETUP_COMPLETE=false; fi
if [ -z "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" ]; then echo "❌ SNAPSHOTTER_COMPUTE_REPO_BRANCH not found after configuration!"; SETUP_COMPLETE=false; fi
if [ -z "$FULL_NAMESPACE" ]; then echo "❌ FULL_NAMESPACE could not be determined!"; SETUP_COMPLETE=false; fi


# Export NO_COLLECTOR for use in deploy-services.sh
export NO_COLLECTOR

if [ "$SETUP_COMPLETE" = true ]; then
    echo "✅ Configuration complete. Environment file ready at $ENV_FILE_PATH"
else
    echo "❌ Configuration incomplete or encountered errors. Please review messages and $ENV_FILE_PATH."
    exit 1
fi
