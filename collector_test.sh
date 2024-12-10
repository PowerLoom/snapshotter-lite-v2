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
echo "Port: ${LOCAL_COLLECTOR_PORT}"

# Test if container is running
if ! docker ps | grep -q "snapshotter-lite-local-collector"; then
    echo "Local collector container is not running!"
    exit 1
fi

# Array of hosts to try
hosts=("localhost" "127.0.0.1" "0.0.0.0")
success=false

# Check if nc is available, otherwise use curl
if command -v nc &> /dev/null; then
    test_command="nc -zv"
else
    test_command="curl -s --connect-timeout 5"
fi

for host in "${hosts[@]}"; do
    echo -n "🔍 Testing ${host}:${LOCAL_COLLECTOR_PORT}... "
    if $test_command "${host}:${LOCAL_COLLECTOR_PORT}" 2>&1; then
        echo "✅ Connected!"
        success=true
        break
    else
        echo "❌ Failed"
    fi
done

if [ "$success" = true ]; then
    echo "🎉 Successfully connected to collector endpoint!"
    exit 0
else
    echo "💥 Failed to connect to collector endpoint on all addresses!"
    exit 1
fi
