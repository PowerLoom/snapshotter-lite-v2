#!/bin/bash

handle_exit() {
    EXIT_CODE=$?
    # Random delay between 1-5 minutes, spread between 30 seconds
    MIN_DELAY=30
    MAX_DELAY=300
    ACTUAL_DELAY=$((MIN_DELAY + RANDOM % (MAX_DELAY - MIN_DELAY + 1)))
    
    echo "Container exited with code $EXIT_CODE. Restarting in $ACTUAL_DELAY seconds..."
    sleep $ACTUAL_DELAY
}

# Always run bootstrap
echo "🚀 Running bootstrap..."

echo "📦 Cloning fresh config repo..."
git clone $SNAPSHOT_CONFIG_REPO "/app/config"
cd /app/config
git checkout $SNAPSHOT_CONFIG_REPO_BRANCH
cd ..

echo "📦 Cloning fresh compute repo..."
git clone $SNAPSHOTTER_COMPUTE_REPO "/app/computes"
cd /app/computes
git checkout $SNAPSHOTTER_COMPUTE_REPO_BRANCH
cd ..

if [ $? -ne 0 ]; then
    echo "❌ Bootstrap failed"
    exit 1
fi

# Run autofill to setup config files
bash snapshotter_autofill.sh
if [ $? -ne 0 ]; then
    echo "❌ Config setup failed"
    exit 1
fi

# Continue with existing steps
poetry run python -m snapshotter.snapshotter_id_ping
ret_status=$?

if [ $ret_status -ne 0 ]; then
    exit 1
fi

# Set up traps for all possible exit scenarios
trap 'handle_exit' EXIT HUP INT QUIT ABRT TERM KILL

poetry run python -m snapshotter.system_event_detector
