#!/bin/bash

# Source environment variables
if [ -z "$FULL_NAMESPACE" ]; then
    echo "FULL_NAMESPACE not found, please run build.sh first to set up environment"
    exit 1  # it is fine to exit with 1 here, as setup should not proceed past this
fi

# parse --env-file argument
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --env-file) ENV_FILE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

source "$ENV_FILE"

# Set default values if not found in env
if [ -z "$LOCAL_COLLECTOR_PORT" ]; then
    export LOCAL_COLLECTOR_PORT=50051
fi

echo "⏳ Testing connection to local collector..."
echo "Port: ${LOCAL_COLLECTOR_PORT}"

# Array of hosts to try
hosts=("localhost" "127.0.0.1" "0.0.0.0")
test_ping=false
test_namespace=false

# Check if nc is available, otherwise use curl
if command -v nc &> /dev/null; then
    test_command="nc -zv -w 5"
    for host in "${hosts[@]}"; do
        echo -n "🔍 Testing ${host}:${LOCAL_COLLECTOR_PORT}... "
        if ${test_command} "${host}" "${LOCAL_COLLECTOR_PORT}" 2>&1; then
            echo "✅ Connected!"
            test_ping=true
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
            test_ping=true
            break
        else
            echo "❌ Failed"
        fi
    done
fi

# Test if container is running
if ! docker ps | grep -q "snapshotter-lite-local-collector-${SLOT_ID}-${FULL_NAMESPACE}"; then
    echo "Local collector container for namespace '${FULL_NAMESPACE}' is not running!"
else
    echo "Local collector container for namespace '${FULL_NAMESPACE}' is running!"
    test_namespace=true
fi


success=false
if [ "$test_ping" = true ] && [ "$test_namespace" = true ]; then
    success=true
fi

if [ "$success" = true ]; then
    echo "🎉 Successfully connected to collector endpoint!"
    exit 100
else
    echo "💥 No collector found or reachable in this namespace, checking for available ports..."
    # check for available PORTS in the range 50051-50059
    for port in {50051..50059}; do
        if ! nc -zv -w 5 localhost $port 2>&1; then
            echo "🔍 Port $port is available!"
            # update local collector port
            echo "🔌 ⭕ Local collector port: ${port}"
            sed -i".backup" "s/^LOCAL_COLLECTOR_PORT=.*/LOCAL_COLLECTOR_PORT=${port}/" "${ENV_FILE}"
            break
        fi
    done
    exit 101
fi
