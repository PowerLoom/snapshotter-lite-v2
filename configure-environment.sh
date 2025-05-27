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
DATA_MARKET_CONTRACT="" # Will be set by override prompt or market selection

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
    if [ "$CLEANUP_ENV_FILE_ON_ABORT" = true ] && [ -n "$FULL_NAMESPACE" ] && [ -f ".env-${FULL_NAMESPACE}" ] && [ "$SETUP_COMPLETE" = false ]; then
        rm -f ".env-${FULL_NAMESPACE}"
        echo "Aborted setup. Deleted partially created .env-${FULL_NAMESPACE} file."
    elif [ "$SETUP_COMPLETE" = false ]; then
        echo "Setup incomplete or aborted. Please review .env-${FULL_NAMESPACE} as it might be in an inconsistent state."
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
        # Ensure newline before appending if file not empty and doesn't end with newline
        if [ -s "$target_file" ] && [ "$(tail -c 1 "$target_file" | wc -l)" -eq 0 ]; then
            echo "" >> "$target_file"
        fi
        echo "${var_name}=${var_value}" >> "$target_file"
    fi
}

if [ "$OVERRIDE_DEFAULTS_SCRIPT_FLAG" = "true" ]; then
    SETUP_COMPLETE=false
    echo "🔧 Custom configuration mode enabled via --override flag."
    
    echo "Select POWERLOOM_CHAIN:"
    echo "1. mainnet (default)"
    echo "2. devnet"
    echo "3. staging"
    read -p "Enter choice (1-3) [default: 1]: " POWERLOOM_CHAIN_CHOICE_INPUT
    POWERLOOM_CHAIN_CHOICE=${POWERLOOM_CHAIN_CHOICE_INPUT:-1} # Default to 1 if empty

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
    export NAMESPACE=${NAMESPACE_INPUT:-$DEFAULT_NAMESPACE} # Default to initial working NAMESPACE (from DEFAULT_NAMESPACE)
    echo "Selected NAMESPACE: $NAMESPACE"

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
        echo "Selected SNAPSHOT_CONFIG_REPO_BRANCH: $SNAPSHOT_CONFIG_REPO_BRANCH"

        read -p "Enter SNAPSHOTTER_COMPUTE_REPO_BRANCH [default: $DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH]: " SNAPSHOTTER_COMPUTE_REPO_BRANCH_INPUT
        export SNAPSHOTTER_COMPUTE_REPO_BRANCH=${SNAPSHOTTER_COMPUTE_REPO_BRANCH_INPUT:-$DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH}
        echo "Selected SNAPSHOTTER_COMPUTE_REPO_BRANCH: $SNAPSHOTTER_COMPUTE_REPO_BRANCH"
    else
        export SNAPSHOT_CONFIG_REPO_BRANCH="$DEFAULT_SNAPSHOT_CONFIG_REPO_BRANCH"
        export SNAPSHOTTER_COMPUTE_REPO_BRANCH="$DEFAULT_SNAPSHOTTER_COMPUTE_REPO_BRANCH"
        echo "Using default SNAPSHOT_CONFIG_REPO_BRANCH: $SNAPSHOT_CONFIG_REPO_BRANCH"
        echo "Using default SNAPSHOTTER_COMPUTE_REPO_BRANCH: $SNAPSHOTTER_COMPUTE_REPO_BRANCH"
    fi
else
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
    # Set other defaults for non-override mode
    export POWERLOOM_CHAIN="$DEFAULT_POWERLOOM_CHAIN"
    export POWERLOOM_RPC_URL="$DEFAULT_POWERLOOM_RPC_URL"
    export PROTOCOL_STATE_CONTRACT="$DEFAULT_PROTOCOL_STATE_CONTRACT"
fi

# Ensure all critical configuration variables are exported before constructing FULL_NAMESPACE or interacting with .env file
export POWERLOOM_CHAIN
export NAMESPACE
export SOURCE_CHAIN
export DATA_MARKET_CONTRACT
export PROTOCOL_STATE_CONTRACT
export SNAPSHOT_CONFIG_REPO_BRANCH
export SNAPSHOTTER_COMPUTE_REPO_BRANCH
export POWERLOOM_RPC_URL
export CONNECTION_REFRESH_INTERVAL_SEC # Already exported, but good to be explicit
export TELEGRAM_NOTIFICATION_COOLDOWN  # Already exported

export FULL_NAMESPACE="${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"
ENV_FILE_PATH=".env-${FULL_NAMESPACE}"

CLEANUP_ENV_FILE_ON_ABORT=false # Flag to indicate if current ENV_FILE_PATH should be deleted on abort

if [ ! -f "$ENV_FILE_PATH" ]; then
    SETUP_COMPLETE=false
    CLEANUP_ENV_FILE_ON_ABORT=true # Mark for deletion if script aborts during creation
    echo "🟡 $ENV_FILE_PATH file not found, creating one..."
    cp env.example "$ENV_FILE_PATH"

    # Populate with determined/prompted values
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
    read -s -p "Enter SIGNER_ACCOUNT_PRIVATE_KEY: " SIGNER_ACCOUNT_PRIVATE_KEY_VAL
    echo
    update_or_append_var "SIGNER_ACCOUNT_PRIVATE_KEY" "$SIGNER_ACCOUNT_PRIVATE_KEY_VAL" "$ENV_FILE_PATH"
    read -p "Enter Your SLOT_ID (NFT_ID): " SLOT_ID_VAL
    update_or_append_var "SLOT_ID" "$SLOT_ID_VAL" "$ENV_FILE_PATH"
    read -p "Enter Your TELEGRAM_CHAT_ID (Optional, leave blank to skip.): " TELEGRAM_CHAT_ID_VAL
    update_or_append_var "TELEGRAM_CHAT_ID" "$TELEGRAM_CHAT_ID_VAL" "$ENV_FILE_PATH"
    
    # Set OVERRIDE_DEFAULTS status in the new file based on how this script was run
    update_or_append_var "OVERRIDE_DEFAULTS" "$OVERRIDE_DEFAULTS_SCRIPT_FLAG" "$ENV_FILE_PATH"
    
    echo "🟢 $ENV_FILE_PATH file created successfully."
else
    echo "🟢 $ENV_FILE_PATH file found."
    # Source existing file to get its current OVERRIDE_DEFAULTS setting and other vars
    # Note: Variables exported by this script (e.g. from --override prompts) will take precedence over sourced values
    source "$ENV_FILE_PATH"

    if [ "$OVERRIDE_DEFAULTS_SCRIPT_FLAG" = "true" ]; then
        SETUP_COMPLETE=false # Re-evaluating config
        echo "🔔 --override flag passed. Updating $ENV_FILE_PATH with specified values."
        # Values are already exported from the initial override prompt section
        update_or_append_var "POWERLOOM_CHAIN" "$POWERLOOM_CHAIN" "$ENV_FILE_PATH"
        update_or_append_var "NAMESPACE" "$NAMESPACE" "$ENV_FILE_PATH"
        update_or_append_var "POWERLOOM_RPC_URL" "$POWERLOOM_RPC_URL" "$ENV_FILE_PATH"
        update_or_append_var "PROTOCOL_STATE_CONTRACT" "$PROTOCOL_STATE_CONTRACT" "$ENV_FILE_PATH"
        update_or_append_var "DATA_MARKET_CONTRACT" "$DATA_MARKET_CONTRACT" "$ENV_FILE_PATH"
        update_or_append_var "SNAPSHOT_CONFIG_REPO_BRANCH" "$SNAPSHOT_CONFIG_REPO_BRANCH" "$ENV_FILE_PATH"
        update_or_append_var "SNAPSHOTTER_COMPUTE_REPO_BRANCH" "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" "$ENV_FILE_PATH"
        update_or_append_var "FULL_NAMESPACE" "$FULL_NAMESPACE" "$ENV_FILE_PATH" # Ensure FULL_NAMESPACE in file matches
        
        export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${FULL_NAMESPACE}" # Recalculate if FULL_NAMESPACE changed
        update_or_append_var "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME" "$ENV_FILE_PATH"
        
        # Set OVERRIDE_DEFAULTS to true in the file
        update_or_append_var "OVERRIDE_DEFAULTS" "true" "$ENV_FILE_PATH"
        echo "✅ $ENV_FILE_PATH updated as per --override."
    else
        # Standard run, .env file exists, NO --override script flag
        # Ensure key default values are present if missing, and overwrite to ensure consistency with script defaults.

        if [ -n "$DATA_MARKET_CONTRACT_NUMBER" ] && [ "$DATA_MARKET_CONTRACT_NUMBER" = "2" ]; then
            CURRENT_DM_CONTRACT_IN_FILE=$(grep "^DATA_MARKET_CONTRACT=" "$ENV_FILE_PATH" | cut -d'=' -f2- || echo "")
            if [ "$CURRENT_DM_CONTRACT_IN_FILE" != "0x21cb57C1f2352ad215a463DD867b838749CD3b8f" ]; then
                echo "🔔 Ensuring DATA_MARKET_CONTRACT is Uniswap V2 in $ENV_FILE_PATH due to contract number selection."
                update_or_append_var "DATA_MARKET_CONTRACT" "0x21cb57C1f2352ad215a463DD867b838749CD3b8f" "$ENV_FILE_PATH"
            fi
            export DATA_MARKET_CONTRACT="0x21cb57C1f2352ad215a463DD867b838749CD3b8f" # Ensure current session reflects this
        fi
        
        # For the following, unconditionally update/append to match old script's behavior of enforcing its defaults.
        echo "🔔 Ensuring $ENV_FILE_PATH reflects current script defaults for RPC, Connection Interval, and Telegram Cooldown."
        update_or_append_var "POWERLOOM_RPC_URL" "$DEFAULT_POWERLOOM_RPC_URL" "$ENV_FILE_PATH"
        export POWERLOOM_RPC_URL="$DEFAULT_POWERLOOM_RPC_URL"

        update_or_append_var "CONNECTION_REFRESH_INTERVAL_SEC" "$DEFAULT_CONNECTION_REFRESH_INTERVAL_SEC" "$ENV_FILE_PATH"
        export CONNECTION_REFRESH_INTERVAL_SEC="$DEFAULT_CONNECTION_REFRESH_INTERVAL_SEC"
        
        update_or_append_var "TELEGRAM_NOTIFICATION_COOLDOWN" "$DEFAULT_TELEGRAM_NOTIFICATION_COOLDOWN" "$ENV_FILE_PATH"
        export TELEGRAM_NOTIFICATION_COOLDOWN="$DEFAULT_TELEGRAM_NOTIFICATION_COOLDOWN"

        # Ensure OVERRIDE_DEFAULTS is present and false if not explicitly set true by script flag
        if ! grep -q "^OVERRIDE_DEFAULTS=" "$ENV_FILE_PATH"; then
             update_or_append_var "OVERRIDE_DEFAULTS" "false" "$ENV_FILE_PATH"
        fi
    fi

    if [ "$SKIP_CREDENTIAL_UPDATE" = "true" ]; then
        echo "🔔 Skipping credential update prompts due to --skip-credential-update flag"
    else
        read -p "🫸 ▶︎  Would you like to update any of the environment variables? (y/n): " UPDATE_ENV_VARS
        if [ "$UPDATE_ENV_VARS" = "y" ]; then
            SETUP_COMPLETE=false
            
            read -p "Enter new SIGNER_ACCOUNT_ADDRESS (current: ${SIGNER_ACCOUNT_ADDRESS:-<not set>}, press enter to skip): " NEW_SIGNER_ACCOUNT_ADDRESS
            if [ -n "$NEW_SIGNER_ACCOUNT_ADDRESS" ]; then
                read -s -p "Enter new SIGNER_ACCOUNT_PRIVATE_KEY: " NEW_SIGNER_ACCOUNT_PRIVATE_KEY
                echo
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
if [ -z "$SOURCE_RPC_URL" ]; then echo "❌ SOURCE_RPC_URL not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then echo "❌ SIGNER_ACCOUNT_ADDRESS not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then echo "❌ SIGNER_ACCOUNT_PRIVATE_KEY not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$SLOT_ID" ]; then echo "❌ SLOT_ID not found after configuration, please set this in your $ENV_FILE_PATH!"; SETUP_COMPLETE=false; fi
if [ -z "$DATA_MARKET_CONTRACT" ]; then echo "❌ DATA_MARKET_CONTRACT not found after configuration!"; SETUP_COMPLETE=false; fi
if [ -z "$SNAPSHOT_CONFIG_REPO_BRANCH" ]; then echo "❌ SNAPSHOT_CONFIG_REPO_BRANCH not found after configuration!"; SETUP_COMPLETE=false; fi
if [ -z "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" ]; then echo "❌ SNAPSHOTTER_COMPUTE_REPO_BRANCH not found after configuration!"; SETUP_COMPLETE=false; fi

# Export NO_COLLECTOR for use in deploy-services.sh
export NO_COLLECTOR

# NOTE: Might want to just exit here if SETUP_COMPLETE is false
if [ "$SETUP_COMPLETE" = true ]; then
    echo "✅ Configuration complete. Environment file ready at $ENV_FILE_PATH"
else
    echo "❌ Configuration incomplete or encountered errors. Please review messages and $ENV_FILE_PATH."
    # Check final validation again for specific missing critical vars
    if [ -z "$SOURCE_RPC_URL" ] || \
       [ -z "$SIGNER_ACCOUNT_ADDRESS" ] || \
       [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ] || \
       [ -z "$SLOT_ID" ] || \
       [ -z "$DATA_MARKET_CONTRACT" ] || \
       [ -z "$SNAPSHOT_CONFIG_REPO_BRANCH" ] || \
       [ -z "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" ] || \
       [ -z "$POWERLOOM_CHAIN" ] || \
       [ -z "$NAMESPACE" ] || \
       [ -z "$SOURCE_CHAIN" ] || \
       [ -z "$POWERLOOM_RPC_URL" ] || \
       ( [[ "$POWERLOOM_CHAIN" == "mainnet" || "$POWERLOOM_CHAIN" == "devnet" ]] && [ -z "$PROTOCOL_STATE_CONTRACT" ] ); then
      echo "❌ Critical configuration variables are missing. Exiting."
      exit 1 # Exit with error if critical vars are still missing
    fi
    echo "Continuing with potentially incomplete configuration. Some services might not work as expected."

fi

SETUP_COMPLETE=true
