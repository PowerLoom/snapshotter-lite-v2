#!/bin/bash

# Help message
show_help() {
    echo "Usage: ./deploy-services.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --env-file FILE     Use specified environment file"
    echo "  -e, --env KEY=VALUE     Set individual environment variable"
    echo "  -n, --namespace NAME    Use .env-NAME file (legacy mode)"
    echo "  -h, --help             Show this help message"
    echo
    echo "Examples:"
    echo "  ./deploy-services.sh --env-file .env-AAVEV3"
    echo "  ./deploy-services.sh --env NAMESPACE=AAVEV3 --env SLOT_ID=123"
    echo "  ./deploy-services.sh --namespace AAVEV3"
}

# Initialize variables
declare -A ENV_VARS
ENV_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -e|--env)
            if [[ $2 =~ ^([^=]+)=(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                ENV_VARS[$key]="$value"
            else
                echo "Error: Invalid environment variable format. Use KEY=VALUE"
                exit 1
            fi
            shift 2
            ;;
        -n|--namespace)
            ENV_FILE=".env-$2"
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

# Validate input
if [ -n "$ENV_FILE" ] && [ ${#ENV_VARS[@]} -gt 0 ]; then
    echo "Error: Cannot use both env file and individual environment variables"
    exit 1
fi

if [ -z "$ENV_FILE" ] && [ ${#ENV_VARS[@]} -eq 0 ]; then
    echo "Error: Must provide either env file or environment variables"
    exit 1
fi

# Create temporary env file if using individual variables
if [ ${#ENV_VARS[@]} -gt 0 ]; then
    ENV_FILE=$(mktemp)
    trap 'rm -f $ENV_FILE' EXIT
    
    for key in "${!ENV_VARS[@]}"; do
        echo "$key=${ENV_VARS[$key]}" >> "$ENV_FILE"
    done
fi

# Validate env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file $ENV_FILE not found"
    exit 1
fi

# Source the environment file
source "$ENV_FILE"

# Validate required variables
required_vars=("NAMESPACE" "SLOT_ID" "DOCKER_NETWORK_NAME")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

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
        -p "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE,,}"  # ${NAMESPACE,,} converts to lowercase
        -f docker-compose.yaml
    )

    # Add optional profiles
    [ -n "$IPFS_URL" ] && COMPOSE_ARGS+=("--profile" "ipfs")
    [ -n "$COLLECTOR_PROFILE_STRING" ] && COMPOSE_ARGS+=($COLLECTOR_PROFILE_STRING)

    # Execute docker compose pull
    $DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" pull

    rm -f "$DOCKER_PULL_LOCK"
}

# Main deployment
echo "🚀 Deploying with configuration from: $ENV_FILE"
handle_docker_pull

# Deploy services
$DOCKER_COMPOSE_CMD "${COMPOSE_ARGS[@]}" up -V 