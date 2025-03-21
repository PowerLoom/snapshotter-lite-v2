#!/bin/bash


echo 'Snapshotter node: populating setting from environment values...';

if [ -z "$SOURCE_RPC_URL" ]; then
    echo "RPC URL not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SIGNER_ACCOUNT_ADDRESS" ]; then
    echo "SIGNER_ACCOUNT_ADDRESS not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$PROST_RPC_URL" ]; then
    echo "PROST_RPC_URL not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$POWERLOOM_RPC_URL" ]; then
    echo "POWERLOOM_RPC_URL not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SLOT_ID" ]; then
    echo "SLOT_ID not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$PROTOCOL_STATE_CONTRACT" ]; then
    echo "PROTOCOL_STATE_CONTRACT not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$PROTOCOL_STATE_CONTRACT_OLD" ]; then
    echo "PROTOCOL_STATE_CONTRACT_OLD not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SIGNER_ACCOUNT_PRIVATE_KEY" ]; then
    echo "SIGNER_ACCOUNT_PRIVATE_KEY not found, please set this in your .env!";
    exit 1;
fi


echo "Found SOURCE RPC URL ${SOURCE_RPC_URL}";

echo "Found SIGNER ACCOUNT ADDRESS ${SIGNER_ACCOUNT_ADDRESS}";

if [ "$IPFS_URL" ]; then
    echo "Found IPFS_URL ${IPFS_URL}";
fi


if [ "$SLACK_REPORTING_URL" ]; then
    echo "Found SLACK_REPORTING_URL ${SLACK_REPORTING_URL}";
fi

if [ "$DATA_MARKET_CONTRACT" ]; then
    echo "Found DATA_MARKET_CONTRACT ${DATA_MARKET_CONTRACT}";
fi

if [ "$POWERLOOM_REPORTING_URL" ]; then
    echo "Found POWERLOOM_REPORTING_URL ${POWERLOOM_REPORTING_URL}";
fi

if [ "$TELEGRAM_REPORTING_URL" ]; then
    echo "Found TELEGRAM_REPORTING_URL ${TELEGRAM_REPORTING_URL}";
fi

if [ "$TELEGRAM_CHAT_ID" ]; then
    echo "Found TELEGRAM_CHAT_ID ${TELEGRAM_CHAT_ID}";
fi

if [ "$WEB3_STORAGE_TOKEN" ]; then
    echo "Found WEB3_STORAGE_TOKEN ${WEB3_STORAGE_TOKEN}";
fi

if [ "$FULL_NAMESPACE" ]; then
    echo "Found FULL_NAMESPACE ${FULL_NAMESPACE}";
else
    echo "FULL_NAMESPACE not found, please set this in your .env!";
    exit 1;
fi

cp config/projects.example.json config/projects.json
cp config/settings.example.json config/settings.json


export namespace="${FULL_NAMESPACE:-namespace_hash}"
export ipfs_url="${IPFS_URL:-}"
export ipfs_api_key="${IPFS_API_KEY:-}"
export ipfs_api_secret="${IPFS_API_SECRET:-}"
export web3_storage_token="${WEB3_STORAGE_TOKEN:-}"
export local_collector_port="${LOCAL_COLLECTOR_PORT:-50051}"
export slack_reporting_url="${SLACK_REPORTING_URL:-}"
export powerloom_reporting_url="${POWERLOOM_REPORTING_URL:-}"
export telegram_reporting_url="${TELEGRAM_REPORTING_URL:-}"
export telegram_chat_id="${TELEGRAM_CHAT_ID:-}"


# If IPFS_URL is empty, clear IPFS API key and secret
if [ -z "$IPFS_URL" ]; then
    ipfs_api_key=""
    ipfs_api_secret=""
fi

echo "Using FULL_NAMESPACE: ${namespace}"
echo "Using Prost RPC URL: ${PROST_RPC_URL}"
echo "Using Powerloom RPC URL: ${POWERLOOM_RPC_URL}"
echo "Using IPFS URL: ${ipfs_url}"
echo "Using IPFS API KEY: ${ipfs_api_key}"
echo "Using protocol state contract: ${PROTOCOL_STATE_CONTRACT}"
echo "Using protocol state contract old: ${PROTOCOL_STATE_CONTRACT_OLD}"
echo "Using data market contract: ${DATA_MARKET_CONTRACT}"
echo "Using slack reporting url: ${slack_reporting_url}"
echo "Using powerloom reporting url: ${powerloom_reporting_url}"
echo "Using web3 storage token: ${web3_storage_token}"
echo "Using telegram reporting url: ${telegram_reporting_url}"
echo "Using telegram chat id: ${telegram_chat_id}"

sed -i'.backup' "s#relevant-namespace#$namespace#" config/settings.json

sed -i'.backup' "s#account-address#$SIGNER_ACCOUNT_ADDRESS#" config/settings.json
sed -i'.backup' "s#slot-id#$SLOT_ID#" config/settings.json

sed -i'.backup' "s#https://rpc-url#$SOURCE_RPC_URL#" config/settings.json

sed -i'.backup' "s#https://prost-rpc-url#$PROST_RPC_URL#" config/settings.json
sed -i'.backup' "s#https://powerloom-rpc-url#$POWERLOOM_RPC_URL#" config/settings.json

sed -i'.backup' "s#web3-storage-token#$web3_storage_token#" config/settings.json
sed -i'.backup' "s#ipfs-writer-url#$ipfs_url#" config/settings.json
sed -i'.backup' "s#ipfs-writer-key#$ipfs_api_key#" config/settings.json
sed -i'.backup' "s#ipfs-writer-secret#$ipfs_api_secret#" config/settings.json

sed -i'.backup' "s#ipfs-reader-url#$ipfs_url#" config/settings.json
sed -i'.backup' "s#ipfs-reader-key#$ipfs_api_key#" config/settings.json
sed -i'.backup' "s#ipfs-reader-secret#$ipfs_api_secret#" config/settings.json

sed -i'.backup' "s#protocol-state-contract#$PROTOCOL_STATE_CONTRACT#" config/settings.json
sed -i'.backup' "s#old-protocol-state#$PROTOCOL_STATE_CONTRACT_OLD#" config/settings.json
sed -i'.backup' "s#data-market-contract#$DATA_MARKET_CONTRACT#" config/settings.json
sed -i'.backup' "s#old-datamarket-contract#$OLD_DATA_MARKET_CONTRACT#" config/settings.json
sed -i'.backup' "s#https://slack-reporting-url#$slack_reporting_url#" config/settings.json

sed -i'.backup' "s#https://powerloom-reporting-url#$powerloom_reporting_url#" config/settings.json

sed -i'.backup' "s#signer-account-private-key#$SIGNER_ACCOUNT_PRIVATE_KEY#" config/settings.json

sed -i'.backup' "s#local-collector-port#$local_collector_port#" config/settings.json

sed -i'.backup' "s#https://telegram-reporting-url#$telegram_reporting_url#" config/settings.json
sed -i'.backup' "s#telegram-chat-id#$telegram_chat_id#" config/settings.json

echo 'settings has been populated!'
