#!/bin/bash

# Run configuration
source ./configure-environment.sh "$@"
if [ $? -ne 0 ]; then
    echo "❌ Configuration failed"
    exit 1
fi


# Source the environment file
source ".env-${FULL_NAMESPACE}"

# Set image tag based on git branch
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$GIT_BRANCH" = "dockerify" ]; then
    export IMAGE_TAG="dockerify"
else
    export IMAGE_TAG="latest"
fi
echo "🏗️ Building image with tag ${IMAGE_TAG}"

# Run collector test
if [ "$NO_COLLECTOR" = "true" ]; then
    echo "🤔 Skipping collector check (--no-collector flag)"
    COLLECTOR_PROFILE_STRING=""
else
    ./collector_test.sh --env-file ".env-${FULL_NAMESPACE}"
    test_result=$?
    if [ $test_result -eq 101 ]; then
        echo "ℹ️  Starting new collector instance"
        COLLECTOR_PROFILE_STRING="--profile local-collector"
    elif [ $test_result -eq 100 ]; then
        echo "✅ Using existing collector instance"
        COLLECTOR_PROFILE_STRING=""
    else
        echo "❌ Collector check failed (exit code: $test_result)"
        exit 1
    fi
fi

# Create lowercase versions of namespace variables
PROJECT_NAME="snapshotter-lite-v2-${SLOT_ID}-${FULL_NAMESPACE}"
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
FULL_NAMESPACE_LOWER=$(echo "$FULL_NAMESPACE" | tr '[:upper:]' '[:lower:]')
export CRON_RESTART=${CRON_RESTART:-false}

# Export the lowercase version for docker-compose
export FULL_NAMESPACE_LOWER

# Check if running in Windows Subsystem for Linux (WSL)
check_wsl() {
    if grep -qi microsoft /proc/version; then
        echo "🐧🪆 Running in WSL environment"
        return 0  # true in shell
    fi
    return 1  # false in shell
}

# Configure Docker Compose profiles based on WSL environment
if check_wsl; then
    # WSL environment - disable autoheal
    COMPOSE_PROFILES="--profile local-collector"
    export AUTOHEAL_LABEL=""
else
    # Non-WSL environment - enable autoheal
    COMPOSE_PROFILES="--profile local-collector --profile autoheal"
    export AUTOHEAL_LABEL="autoheal=true"
fi

# Modify the deploy-services call to use the profiles
./deploy-services.sh --env-file ".env-${FULL_NAMESPACE}" \
    --project-name "$PROJECT_NAME_LOWER" \
    --collector-profile "$COMPOSE_PROFILES" \
    --image-tag "$IMAGE_TAG"
