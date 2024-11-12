source .env

echo "setting up codebase..."

rm -rf snapshotter-lite-local-collector
git clone https://github.com/PowerLoom/snapshotter-lite-local-collector.git
cd ./snapshotter-lite-local-collector
git checkout main
cd ..

if [ -z "$SNAPSHOT_CONFIG_REPO" ]; then
    echo "SNAPSHOT_CONFIG_REPO not found, please set this in your .env!";
    exit 1;
fi

if [ -z "$SNAPSHOTTER_COMPUTE_REPO" ]; then
    echo "SNAPSHOTTER_COMPUTE_REPO not found, please set this in your .env!";
    exit 1;
fi

echo "Found SNAPSHOT_CONFIG_REPO ${SNAPSHOT_CONFIG_REPO}";
echo "Found SNAPSHOTTER_COMPUTE_REPO ${SNAPSHOTTER_COMPUTE_REPO}";

rm -rf config;
git clone $SNAPSHOT_CONFIG_REPO config;
cd config;
if [ "$SNAPSHOT_CONFIG_REPO_BRANCH" ]; then
    echo "Found SNAPSHOT_CONFIG_REPO_BRANCH ${SNAPSHOT_CONFIG_REPO_BRANCH}";
    git checkout $SNAPSHOT_CONFIG_REPO_BRANCH;
fi
cd ../;

rm -rf computes;
git clone $SNAPSHOTTER_COMPUTE_REPO computes;
cd computes;
if [ "$SNAPSHOTTER_COMPUTE_REPO_BRANCH" ]; then
    echo "Found SNAPSHOTTER_COMPUTE_REPO_BRANCH ${SNAPSHOTTER_COMPUTE_REPO_BRANCH}";
    git checkout $SNAPSHOTTER_COMPUTE_REPO_BRANCH;
fi
cd ../;


echo "bootstrapping complete!"
