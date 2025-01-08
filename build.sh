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
    echo "🔌 ⭕ No collector flag passed, skipping collector test"
    COLLECTOR_PROFILE_STRING=""
else
    ./collector_test.sh --env-file ".env-${FULL_NAMESPACE}"
    test_result=$?
    if [ $test_result -eq 101 ]; then
        echo "🔌 ⭕ Local collector not found or unreachable - will spawn a new local collector instance"
        COLLECTOR_PROFILE_STRING="--profile local-collector"

    elif [ $test_result -eq 100 ]; then
        echo "🔌 ✅ Local collector found - using existing collector instance"
        COLLECTOR_PROFILE_STRING=""
    else
        echo "❌ Collector test failed with exit code $?, exiting..."
        exit 1
    fi
fi

# Create lowercase versions of namespace variables
PROJECT_NAME="snapshotter-lite-v2-${SLOT_ID}-${FULL_NAMESPACE}"
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
FULL_NAMESPACE_LOWER=$(echo "$FULL_NAMESPACE" | tr '[:upper:]' '[:lower:]')

# Export the lowercase version for docker-compose
export FULL_NAMESPACE_LOWER

# Run deployment with the correct env file
./deploy-services.sh --env-file ".env-${FULL_NAMESPACE}" \
    --project-name "$PROJECT_NAME_LOWER" \
    --collector-profile "$COLLECTOR_PROFILE_STRING" \
    --image-tag "$IMAGE_TAG"
