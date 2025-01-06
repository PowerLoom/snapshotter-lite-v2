#!/bin/bash

# Run configuration
./configure-environment.sh "$@"
if [ $? -ne 0 ]; then
    echo "❌ Configuration failed"
    exit 1
fi

# Run deployment with the correct env file
./deploy-services.sh --env-file ".env-${POWERLOOM_CHAIN}-${NAMESPACE}"
if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo "✅ Build and deployment complete"


