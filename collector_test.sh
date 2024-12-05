#!/bin/bash

# Source environment variables
if [ -z "$NAMESPACE" ]; then
    echo "NAMESPACE not found, please run build.sh first to set up environment"
    exit 1
fi

source ".env-${NAMESPACE}"

# Set default values if not found in env
if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051
fi

echo "⏳ Testing connection to local collector..."
echo "Host: host.docker.internal"
echo "Port: ${LOCAL_COLLECTOR_PORT}"

# Test if container is running
if ! docker ps | grep -q "snapshotter-lite-local-collector"; then
    echo "Local collector container is not running!"
    exit 1
fi

# Test connection using nc (netcat)
docker run --rm \
    alpine:latest \
    timeout 5 nc -zv host.docker.internal "${LOCAL_COLLECTOR_PORT}" 2>&1

if [ $? -eq 0 ]; then
    echo "Successfully connected to collector endpoint!"
    exit 0
else
    echo "Failed to connect to collector endpoint!"
    exit 1
fi
