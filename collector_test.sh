#!/bin/bash

# Source environment variables
if [ -z "$FULL_NAMESPACE" ]; then
    echo "FULL_NAMESPACE not found, please run build.sh first to set up environment"
    exit 1  # it is fine to exit with 1 here, as setup should not proceed past this
fi

source ".env-${FULL_NAMESPACE}"

# Set default values if not found in env
if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051
fi

echo "⏳ Testing connection to local collector..."
echo "Port: ${LOCAL_COLLECTOR_PORT}"

# Test if container is running
if ! docker ps | grep -q "snapshotter-lite-local-collector-${SLOT_ID}-${FULL_NAMESPACE}"; then
    echo "Local collector container for namespace '${FULL_NAMESPACE}' is not running!"
    exit 101
fi

# Array of hosts to try
hosts=("localhost" "127.0.0.1" "0.0.0.0")
success=false

# Check if nc is available, otherwise use curl
if command -v nc &> /dev/null; then
    test_command="nc -zv -w 5"
    for host in "${hosts[@]}"; do
        echo -n "🔍 Testing ${host}:${LOCAL_COLLECTOR_PORT}... "
        if ${test_command} "${host}" "${LOCAL_COLLECTOR_PORT}" 2>&1; then
            echo "✅ Connected!"
            success=true
            break
        else
            echo "❌ Failed"
        fi
    done
else
    test_command="curl -s --connect-timeout 5"
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
fi

if [ "$success" = true ]; then
    echo "🎉 Successfully connected to collector endpoint!"
    exit 100
else
    echo "💥 Failed to connect to collector endpoint on all addresses!"
    exit 101
fi
