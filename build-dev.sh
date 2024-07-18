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


if [ -z "$OVERRIDE_DEFAULTS" ]; then
    echo "reset to default values...";
    export PROST_RPC_URL="https://rpc-prost1h-proxy.powerloom.io"
    export PROTOCOL_STATE_CONTRACT="0x10c5E2ee14006B3860d4FdF6B173A30553ea6333"
    export PROST_CHAIN_ID="11165"
    export SEQUENCER_ID="QmdJbNsbHpFseUPKC9vLt4vMsfdxA4dyHPzsAWuzYz3Yxx"
    export RELAYER_RENDEZVOUS_POINT="Relayer_POP_test_simulation_phase_1"
    export CLIENT_RENDEZVOUS_POINT="POP_Client_simulation_test_alpha"
fi



source .env

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

echo "Found SOURCE RPC URL ${SOURCE_RPC_URL}";

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

if [ "$RELAYER_HOST" ]; then
    echo "Found RELAYER_HOST ${RELAYER_HOST}";
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

if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051;
    echo "LOCAL_COLLECTOR_PORT not found in .env, setting to default value ${LOCAL_COLLECTOR_PORT}";
else
    echo "Found LOCAL_COLLECTOR_PORT ${LOCAL_COLLECTOR_PORT}";
fi

if [ -z "$CORE_API_PORT" ]; then
    export CORE_API_PORT=8002;
    echo "CORE_API_PORT not found in .env, setting to default value ${CORE_API_PORT}";
else
    echo "Found CORE_API_PORT ${CORE_API_PORT}";
fi

# setting up git submodules
git submodule update --init --recursive
# check if snapshotter-lite-local-collector exists
if [ -d "./snapshotter-lite-local-collector" ]; then
    echo "snapshotter-lite-local-collector exists, do you want to delete and clone a fresh one? (y/n)";
    read response;
    if [ "$response" == "y" ]; then
        rm -rf ./snapshotter-lite-local-collector
        git clone https://github.com/PowerLoom/snapshotter-lite-local-collector/ snapshotter-lite-local-collector --single-branch --branch main
    fi
fi
cd ./snapshotter-lite-local-collector/ && chmod +x build-docker.sh && ./build-docker.sh;
cd ../;

docker build -t snapshotter-lite-v2 .

echo "building...";

if ! [ -x "$(command -v docker-compose)" ]; then
    echo 'docker compose not found, trying to see if compose exists within docker';
    if [ "$IPFS_URL" == "/dns/ipfs/tcp/5001" ]; then
        docker compose -f docker-compose-dev.yaml --profile ipfs up -V --abort-on-container-exit
    else
        docker compose -f docker-compose-dev.yaml up --no-deps -V --abort-on-container-exit
    fi
else
    if [ "$IPFS_URL" == "/dns/ipfs/tcp/5001" ]; then
        docker-compose -f docker-compose-dev.yaml --profile ipfs up -V --abort-on-container-exit
    else
        docker-compose -f docker-compose-dev.yaml up --no-deps -V --abort-on-container-exit
    fi
fi