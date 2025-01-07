#!/bin/bash

# Always run bootstrap
echo "🚀 Running bootstrap..."

# Clone or update config repo
if [ -d "/app/config/.git" ]; then
    echo "📦 Updating existing config repo..."
    cd /app/config
    git fetch
    git reset --hard origin/$SNAPSHOT_CONFIG_REPO_BRANCH
    cd ..
else
    echo "📦 Cloning fresh config repo..."
    git clone $SNAPSHOT_CONFIG_REPO "/app/config"
    cd /app/config
    git checkout $SNAPSHOT_CONFIG_REPO_BRANCH
    cd ..
fi

# Clone or update compute repo
if [ -d "/app/computes/.git" ]; then
    echo "📦 Updating existing compute repo..."
    cd /app/computes
    git fetch
    git reset --hard origin/$SNAPSHOTTER_COMPUTE_REPO_BRANCH
    cd ..
else
    echo "📦 Cloning fresh compute repo..."
    git clone $SNAPSHOTTER_COMPUTE_REPO "/app/computes"
    cd /app/computes
    git checkout $SNAPSHOTTER_COMPUTE_REPO_BRANCH
    cd ..
fi

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

echo 'starting processes...';
pm2 start pm2.config.js

pm2 logs --lines 1000