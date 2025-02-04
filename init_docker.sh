#!/bin/bash

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
    echo "Snapshotter identity check failed on protocol smart contract"
    exit 1
fi

poetry run python -m snapshotter.system_event_detector