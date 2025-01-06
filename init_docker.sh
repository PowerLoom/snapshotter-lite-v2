#!/bin/bash

# Run bootstrap if directories are empty
if [ -z "$(ls -A /app/computes)" ] || [ -z "$(ls -A /app/config)" ]; then
    echo "🚀 Running bootstrap..."
    
    # Clone config repo
    git clone $SNAPSHOT_CONFIG_REPO "/app/config"
    cd /app/config
    if [ "$SNAPSHOT_CONFIG_REPO_BRANCH" ]; then
        git checkout $SNAPSHOT_CONFIG_REPO_BRANCH
    fi
    cd ..

    # Clone compute repo
    git clone $SNAPSHOTTER_COMPUTE_REPO "/app/computes"
    cd /app/computes
    if [ "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" ]; then
        git checkout $SNAPSHOTTER_COMPUTE_REPO_BRANCH
    fi
    cd ..

    if [ $? -ne 0 ]; then
        echo "❌ Bootstrap failed"
        exit 1
    fi
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