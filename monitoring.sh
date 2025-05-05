#!/bin/bash
# 1. Create a new file named monitoring.sh and add the following content:
# (ensure you have the packages installed. sudo apt-get install jq bc)
# 2. Edit with your values for BURNER_WALLET_ADDRESS, SLOT_IDS, WARNING_THRESHOLD(depends on your best submissions), CRITICAL_THRESHOLD, and DISCORD_WEBHOOK_URL.
# 3. Make the Script Executable: chmod +x /path/to/folder/monitoring.sh
# 4. Set Up a Cron Job: crontab -e
# 5. Add the following line to the crontab file to run the script every hour (adjust the schedule as needed): 
# ```0 * * * * /path/to/folder/monitoring.sh```
# 6. Save and exit the crontab editor.
# 7. Verify the Cron Job: crontab -l

# Define variables
BURNER_WALLET_ADDRESS="0xwalletaddressNOTPRIVATEKEY"
SLOT_IDS=("SLOTID1" "SLOTID2")
DATA_MARKET_ADDRESS1="0x21cb57C1f2352ad215a463DD867b838749CD3b8f" # uniswap data market adddress

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

    # Check if the jq command succeeded.  This is crucial for debugging.
    local jq_output=$(echo "$response" | jq -r '.info.response.currentDay | ((.totalSubmissions + .remainingEpochs *2 ) * 100 / .snapshotDailyQuota)')

    # Check the output of jq.  If it's empty or contains an error, you'll know.
    if [[ -z "$jq_output" ]]; then
    echo "Error: jq failed to extract data. Response: $response"
    exit 1  # Or handle the error differently
    elif [[ "$jq_output" == "null" ]]; then
    echo "Error: jq returned null.  The data might not exist in the JSON. Response: $response"
    exit 1
    fi

    # jq *should* now contain the result, but it might not be a number if there's an issue with the JSON.
    # Check if it's a number to avoid issues with bc
    if [[ "$jq_output" =~ ^[0-9.]+$ ]]; then
    local availability=$(bc <<< "scale=2; $jq_output") # scale=2 for 2 decimal places

    # echo "Response: $response"
    # echo "jq Output: $jq_output" # Debugging: show the value before bc
    echo "Availability for slot $slot_id: $availability%"
    else
    echo "Error: jq output is not a number: '$jq_output'. Response: $response"
    exit 1
    fi

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
    # else
    #     send_discord_alert "All good: Availability for slot $slot_id is $availability%"
    fi
}

# Check availability for all slot IDs
for slot_id in "${SLOT_IDS[@]}"; do
    check_availability $slot_id
done