source .env

echo "setting up codebase..."

rm -rf snapshotter-lite-local-collector
git clone https://github.com/PowerLoom/snapshotter-lite-local-collector.git
cd ./snapshotter-lite-local-collector
git checkout feat/trusted-relayers
cd ..

echo "bootstrapping complete!"
