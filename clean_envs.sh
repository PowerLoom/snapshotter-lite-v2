#!/bin/bash

# Remove all .env-<namespace> files
namespaces=("AAVEV3" "UNISWAPV2")
for namespace in "${namespaces[@]}"; do
    if [ -f ".env-${namespace}" ]; then
        echo "Removing .env-${namespace} file. Press y to confirm."
        while read -r -t 0; do read -r; done  # Clear input buffer
        read -s -n 1 confirm
        if [ "$confirm" = "y" ]; then
            rm -rf ".env-${namespace}"
            echo "🗑️  .env-${namespace} file removed."
        else
            echo "🚫  .env-${namespace} file not removed."
        fi
    fi
done