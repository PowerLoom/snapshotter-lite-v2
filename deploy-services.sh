#!/bin/bash

# Help message
show_help() {
    echo "Usage: ./deploy-services.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --env-file FILE          Use specified environment file"
    echo "  -p, --project-name NAME      Set docker compose project name"
    echo "  -c, --collector-profile STR  Set collector profile string"
    echo "  -t, --image-tag TAG         Set docker image tag"
    echo "  -h, --help                  Show this help message"
    echo
    echo "Examples:"
    echo "  ./deploy-services.sh --env-file .env-pre-mainnet-AAVEV3-ETH"
    echo "  ./deploy-services.sh --project-name snapshotter-lite-v2-123-aavev3"
}

# Initialize variables
ENV_FILE=""
PROJECT_NAME=""
COLLECTOR_PROFILE=""
IMAGE_TAG="latest"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -c|--collector-profile)
            COLLECTOR_PROFILE="$2"
            shift 2
            ;;
        -t|--image-tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$ENV_FILE" ]; then
    echo "Error: Environment file must be specified"
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file $ENV_FILE not found"
    exit 1
fi

# Source the environment file
source "$ENV_FILE"

# Validate required variables
required_vars=("FULL_NAMESPACE" "SLOT_ID" "DOCKER_NETWORK_NAME")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

# Create required directories
mkdir -p "./logs-${FULL_NAMESPACE_LOWER}" \
        "./computes-${FULL_NAMESPACE_LOWER}" \
        "./config-${FULL_NAMESPACE_LOWER}"


# Docker pull locking mechanism
DOCKER_PULL_LOCK="/tmp/powerloom_docker_pull.lock"

handle_docker_pull() {
    while [ -f "$DOCKER_PULL_LOCK" ]; do
        echo "Another Docker pull in progress, waiting..."
        sleep 5
    done

    touch "$DOCKER_PULL_LOCK"
    trap 'rm -f $DOCKER_PULL_LOCK' EXIT

    # Determine docker compose command
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        DOCKER_COMPOSE_CMD="docker compose"
    fi

    # Build compose arguments
    COMPOSE_ARGS=(
        --env-file "$ENV_FILE"
        -p "${PROJECT_NAME:-snapshotter-lite-v2-${FULL_NAMESPACE}}"
        -f docker-compose.yaml
    )

    # Add optional profiles
    [ -n "$IPFS_URL" ] && COMPOSE_ARGS+=("--profile" "ipfs")
    [ -n "$COLLECTOR_PROFILE" ] && COMPOSE_ARGS+=($COLLECTOR_PROFILE)

    # Set image tag and ensure network exists
    export IMAGE_TAG
    export DOCKER_NETWORK_NAME

    # Execute docker compose pull
    $DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" pull

    rm -f "$DOCKER_PULL_LOCK"
}

# Main deployment
echo "🚀 Deploying with configuration from: $ENV_FILE"
handle_docker_pull

# Deploy services
$DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" up -V 