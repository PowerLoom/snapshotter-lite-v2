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
    echo "  -d, --dev-mode              Enable dev mode"
    echo "  -h, --help                  Show this help message"
    echo
    echo "Examples:"
    echo "  ./deploy-services.sh --env-file .env-pre-mainnet-AAVEV3-ETH"
    echo "  ./deploy-services.sh --project-name snapshotter-lite-v2-123-aavev3"
    echo "  ./deploy-services.sh --dev-mode"
}

# Initialize variables
ENV_FILE=""
PROJECT_NAME=""
COLLECTOR_PROFILE=""
IMAGE_TAG="latest"
DEV_MODE="false"

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
        -d|--dev-mode)
            DEV_MODE="true"
            shift
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

# Cleanup and create required directories
echo "🧹 Cleaning up existing directories..."
rm -rf "./logs-${FULL_NAMESPACE_LOWER}"

echo "📁 Creating fresh directories..."
mkdir -p "./logs-${FULL_NAMESPACE_LOWER}"

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

    if [ "$DEV_MODE" = "true" ]; then
        # Build compose arguments
        COMPOSE_ARGS=(
            --env-file "$ENV_FILE"
            -p "${PROJECT_NAME:-snapshotter-lite-v2-${FULL_NAMESPACE}}"
            -f docker-compose-dev.yaml
        )

    else
        # Build compose arguments
        COMPOSE_ARGS=(
            --env-file "$ENV_FILE"
            -p "${PROJECT_NAME:-snapshotter-lite-v2-${FULL_NAMESPACE}}"
            -f docker-compose.yaml
        )

    fi


    # Add optional profiles
    [ -n "$IPFS_URL" ] && COMPOSE_ARGS+=("--profile" "ipfs")
    [ -n "$COLLECTOR_PROFILE" ] && COMPOSE_ARGS+=($COLLECTOR_PROFILE)

    # Set image tag and ensure network exists
    export IMAGE_TAG
    export DOCKER_NETWORK_NAME

    # check if DOCKER_NETWORK_NAME exists otherwise create it, it's a bridge network
    if ! docker network ls | grep -q "$DOCKER_NETWORK_NAME"; then
        echo "🔄 Creating docker network $DOCKER_NETWORK_NAME"
        docker network create --driver bridge "$DOCKER_NETWORK_NAME"
    fi

    if [ "$DEV_MODE" = "true" ]; then
        echo "🏗️ Building the docker image"
        ./build-docker.sh
    else
        # Execute docker compose pull
        echo "🔄 Pulling docker images"
        echo $DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" pull
        $DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" pull
    fi

    rm -f "$DOCKER_PULL_LOCK"
}

# Main deployment
echo "🚀 Deploying with configuration from: $ENV_FILE"
handle_docker_pull

# Deploy services
$DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" up -V 