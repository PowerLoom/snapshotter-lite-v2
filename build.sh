#!/bin/bash

# Run configuration
./configure-environment.sh "$@"
if [ $? -ne 0 ]; then
    echo "❌ Configuration failed"
    exit 1
fi

# Run bootstrap
echo "🚀 bootstrapping..."
if ! ./bootstrap.sh; then
    echo "❌ bootstrapping failed, exiting..."
    exit 1
fi
echo "✅ bootstrap complete"

# Source the environment file
source ".env-${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}"

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
    ./collector_test.sh
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

# Run deployment with the correct env file
./deploy-services.sh --env-file ".env-${POWERLOOM_CHAIN}-${NAMESPACE}-${SOURCE_CHAIN}" \
    --project-name "snapshotter-lite-v2-${SLOT_ID}-${NAMESPACE,,}" \
    --collector-profile "$COLLECTOR_PROFILE_STRING" \
    --image-tag "$IMAGE_TAG"
if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo "✅ Build and deployment complete"


