#!/bin/bash

# Load variables from .env file
source .env

curl -X 'POST' \
    'https://snapshotter-v2-reg-api.powerloom.io/stats' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
    "address": "'"$SIGNER_ACCOUNT_ADDRESS"'",
    "slotId": '"$SLOT_ID"',
    "token": "cc9405f83db24d3b82f11997c5bbf90f"
}'