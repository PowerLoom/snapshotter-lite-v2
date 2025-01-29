#!/bin/bash
# 1. Create a new file named monitoring.sh and add the following content:
# 2. Edit with your values for BURNER_WALLET_ADDRESS, SLOT_IDS, WARNING_THRESHOLD(depends on your best submissions), CRITICAL_THRESHOLD, and DISCORD_WEBHOOK_URL.
# 3. Make the Script Executable: chmod +x /path/to/folder/monitoring.sh
# 4. Set Up a Cron Job: crontab -e
# 5. Add the following line to the crontab file to run the script every hour (adjust the schedule as needed): ```0 * * * * /path/to/folder/monitoring.sh```
# 6. Save and exit the crontab editor.
# 7. Verify the Cron Job: crontab -l

# Define variables
BURNER_WALLET_ADDRESS="0xwalletaddressNOTPRIVATEKEY"
SLOT_IDS=("SLOTID1" "SLOTID2")
DATA_MARKET_ADDRESS1="0xC53ad4C6A8A978fC4A91F08A21DcE847f5Bc0E27" # uniswap data market adddress

# Define thresholds
WARNING_THRESHOLD=130 # Depends upon best submissions(144)
CRITICAL_THRESHOLD=110 # Depends upon least needed submissions(100)

# Discord Webhook URL
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/GenerateYourOwn"

# API endpoint for snapshotter stats
API_URL="https://snapshotter-dashboard-api.powerloom.network/snapshotterStats"

# Function to fetch and process data for a given slot ID
check_availability() {
    local slot_id=$1
    local payload=$(cat <<EOF
{
  "slot_id": $slot_id,
  "data_market_address": "$DATA_MARKET_ADDRESS1",
  "snapshotter_address": "$BURNER_WALLET_ADDRESS"
}
EOF
    )

    local response=$(curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d "$payload")
    local availability=$(echo "$response" | jq -r '.info.response.currentDay | ((.totalSubmissions + .remainingEpochs) * 100 / .snapshotDailyQuota)')

    # # Print availability
    echo "Availability for slot $slot_id: $availability%"

    # Send notification to Discord
    send_discord_alert() {
        local message=$1
        curl -X POST -H "Content-Type: application/json" -d "{\"content\": \"$message\"}" "$DISCORD_WEBHOOK_URL"
    }

    # Check availability and send alerts
    if (( $(echo "$availability < $CRITICAL_THRESHOLD" | bc -l) )); then
        send_discord_alert "**CRITICAL**: Powerloom snapshotter $slot_id Node availability is below $CRITICAL_THRESHOLD% (currently $availability%)"
    elif (( $(echo "$availability < $WARNING_THRESHOLD" | bc -l) )); then
        send_discord_alert "**WARNING**: Powerloom snapshotter $slot_id Node availability is below $WARNING_THRESHOLD% (currently $availability%)"
    else
        send_discord_alert "All good: Availability for slot $slot_id is $availability%"
    fi
}

# Check availability for all slot IDs
for slot_id in "${SLOT_IDS[@]}"; do
    check_availability $slot_id
done
