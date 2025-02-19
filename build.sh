#!/bin/bash

# Run configuration
source ./configure-environment.sh "$@"
if [ $? -ne 0 ]; then
    echo "❌ Configuration failed"
    exit 1
fi


# Source the environment file
source ".env-${FULL_NAMESPACE}"

if [ "$DEV_MODE" != "true" ]; then
    # Set image tag based on git branch
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$GIT_BRANCH" = "dockerify" ]; then
        export IMAGE_TAG="dockerify"
    elif [ "$GIT_BRANCH" = "experimental" ]; then
        export IMAGE_TAG="experimental"
    else
        export IMAGE_TAG="latest"
    fi
    if [ -z "$LOCAL_COLLECTOR_IMAGE_TAG" ]; then
        if [ "$GIT_BRANCH" = "experimental" ] || [ "$GIT_BRANCH" = "dockerify" ]; then
            # TODO: Change this to use 'experimental' once we have a proper experimental image for local collector
            export LOCAL_COLLECTOR_IMAGE_TAG="dockerify"
        else
            export LOCAL_COLLECTOR_IMAGE_TAG=${IMAGE_TAG}
        fi
        echo "🔔 LOCAL_COLLECTOR_IMAGE_TAG not found in .env, setting to default value ${LOCAL_COLLECTOR_IMAGE_TAG}"
    else
        echo "🔔 LOCAL_COLLECTOR_IMAGE_TAG found in .env, using value ${LOCAL_COLLECTOR_IMAGE_TAG}"
    fi 
    echo "🏗️ Running snapshotter-lite-v2 node Docker image with tag ${IMAGE_TAG}"
    echo "🏗️ Running snapshotter-lite-local-collector Docker image with tag ${LOCAL_COLLECTOR_IMAGE_TAG}"
fi

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

# Export the lowercase version for docker-compose
export FULL_NAMESPACE_LOWER

COMPOSE_PROFILES="${COLLECTOR_PROFILE_STRING}"

# Modify the deploy-services call to use the profiles
if [ "$DEV_MODE" == "true" ]; then
    ./deploy-services.sh --env-file ".env-${FULL_NAMESPACE}" \
        --project-name "$PROJECT_NAME_LOWER" \
        --collector-profile "$COMPOSE_PROFILES" \
        --dev-mode
else
    ./deploy-services.sh --env-file ".env-${FULL_NAMESPACE}" \
        --project-name "$PROJECT_NAME_LOWER" \
        --collector-profile "$COMPOSE_PROFILES" \
        --image-tag "$IMAGE_TAG"
fi

