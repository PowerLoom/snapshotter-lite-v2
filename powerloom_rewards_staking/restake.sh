#!/bin/bash
# Define paths and values explicitly
# Set up automation such as cronjob to run daily.
VENV_PATH="/path/to/virtualenv/bin/activate"
CLAIM_SCRIPT="/path/to/powerloom_rewards_staking/claimrestake.py"
LOG_FILE="/path/to/powerloom_rewards_staking/restake.txt"
DISCORD_WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL"

# Activate the virtual environment
source "$VENV_PATH"

# --- Run claimrestake.py ---
echo "--- Running claimrestake.py ---"
claim_output=$(python3 "$CLAIM_SCRIPT" 2>&1) # Capture stdout and stderr
claim_exit_code=$?
echo "claimrestake.py finished with exit code $claim_exit_code"

# Append claimrestake output to log file
echo -e "\n$(date) - claimrestake.py - Exit Code: $claim_exit_code\n$claim_output\n" >> "$LOG_FILE"

# Function to send notification to Discord
send_discord_alert() {
    local message=$1
    escaped_message=$(echo "$message" | jq -Rsa .)  # Escape special characters properly
    curl -s -o /dev/null -X POST -H "Content-Type: application/json" -d "{\"content\": $escaped_message}" "$DISCORD_WEBHOOK_URL"
}

# Check claimrestake.py result and send alerts
if [[ $claim_exit_code -ne 0 ]]; then
    send_discord_alert "**CRITICAL (claimrestake.py)**: $claim_output"
elif [[ "$claim_output" == *"SUCCESS:"* ]]; then
    send_discord_alert "**SUCCESS (claimrestake.py)**: $claim_output"
else
    # Send potentially less critical output if it didn't explicitly succeed or fail
    send_discord_alert "**INFO (claimrestake.py)**: $claim_output"
fi