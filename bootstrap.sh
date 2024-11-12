source .env

echo "setting up codebase..."

rm -rf snapshotter-lite-local-collector
git clone https://github.com/PowerLoom/snapshotter-lite-local-collector.git
cd ./snapshotter-lite-local-collector
git checkout main
cd ..

echo "bootstrapping complete!"
