#!/bin/bash

# check if .env exists
if [ ! -f .env ]; then
    echo ".env file not found, please create one!";
    echo "creating .env file...";
    cp env.example .env;

    # ask user for SOURCE_RPC_URL and replace it in .env
    if [ -z "$SOURCE_RPC_URL" ]; then
        echo "Enter SOURCE_RPC_URL: ";
        read SOURCE_RPC_URL;
        sed -i'.backup' "s#<source-rpc-url>#$SOURCE_RPC_URL#" .env
    fi

    # ask user for SIGNER_ACCOUNT_ADDRESS and replace it in .env
    if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
        echo "Enter SIGNER_ACCOUNT_ADDRESS: ";
        read SIGNER_ACCOUNT_ADDRESS;
        sed -i'.backup' "s#<signer-account-address>#$SIGNER_ACCOUNT_ADDRESS#" .env
    fi

    # ask user for SIGNER_ACCOUNT_PRIVATE_KEY and replace it in .env
    if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then
        echo "Enter SIGNER_ACCOUNT_PRIVATE_KEY: ";
        read SIGNER_ACCOUNT_PRIVATE_KEY;
        sed -i'.backup' "s#<signer-account-private-key>#$SIGNER_ACCOUNT_PRIVATE_KEY#" .env
    fi

    # ask user for SLOT_ID and replace it in .env
    if [ -z "$SLOT_ID" ]; then
        echo "Enter Your SLOT_ID (NFT_ID): ";
        read SLOT_ID;
        sed -i'.backup' "s#<slot-id>#$SLOT_ID#" .env
    fi

fi

source .env

BASE_SUBNET=$((SLOT_ID % 256))

if [ -z "$OVERRIDE_DEFAULTS" ]; then
    echo "setting default values...";
    export PROST_RPC_URL="https://rpc-prost1m.powerloom.io"
    export PROTOCOL_STATE_CONTRACT="0xE88E5f64AEB483d7057645326AdDFA24A3B312DF"
    export DATA_MARKET_CONTRACT="0x0C2E22fe7526fAeF28E7A58c84f8723dEFcE200c"
    export PROST_CHAIN_ID="11169"
    export DOCKER_NETWORK_NAME="snapshotter-lite-v2-${SLOT_ID}"
    export DOCKER_NETWORK_SUBNET="172.16.${BASE_SUBNET}.0/23"
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

if [ -z "$DOCKER_NETWORK_SUBNET" ]; then
    echo "DOCKER_NETWORK_SUBNET not found, please set this in your .env!";
    exit 1;
fi

echo "DOCKER NETWORK SUBNET: ${DOCKER_NETWORK_SUBNET}"
echo "DOCKER NETWORK NAME: ${DOCKER_NETWORK_NAME}"

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

# check if ufw command exists
if [ -x "$(command -v ufw)" ]; then
    ufw allow from $DOCKER_NETWORK_SUBNET to any port $LOCAL_COLLECTOR_PORT
    if [ $? -eq 0 ]; then
        echo "ufw allow rule added for local collector port ${LOCAL_COLLECTOR_PORT} to allow connections from ${DOCKER_NETWORK_SUBNET}.\n"
    else
            echo "firewall allow rule not added for local collector port ${LOCAL_COLLECTOR_PORT}.\n \
        Please attempt to add it manually with: sudo ufw allow ${LOCAL_COLLECTOR_PORT} \n \
        Or 
        Then run ./build.sh again.\n"
        # exit script if ufw rule not added
        exit 1
    fi
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

if ! [ -x "$(command -v docker-compose)" ]; then
    echo 'docker compose not found, trying to see if compose exists within docker';
    # assign docker compose file according to $ARG1

    docker compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING pull
    if [ -n "$IPFS_URL" ]; then
        docker compose -f docker-compose.yaml --profile ipfs $COLLECTOR_PROFILE_STRING up -V --abort-on-container-exit
    else
        docker compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING up -V --abort-on-container-exit
    fi
else
    docker-compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING pull
    if [ -n "$IPFS_URL" ]; then
        docker-compose -f docker-compose.yaml --profile ipfs $COLLECTOR_PROFILE_STRING up -V --abort-on-container-exit
    else
        docker-compose -f docker-compose.yaml $COLLECTOR_PROFILE_STRING up -V --abort-on-container-exit
    fi
fi
