#!/bin/bash

# Run configuration
./configure-environment.sh "$@"
if [ $? -ne 0 ]; then
    echo "❌ Configuration failed"
    exit 1
fi

# Run deployment
./deploy-services.sh "$NAMESPACE"
if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo "✅ Build and deployment complete"


