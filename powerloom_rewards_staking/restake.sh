#!/bin/bash
# Define paths explicitly
VENV_PATH="/home/nemin/pop/venv/bin/activate"
PYTHON_SCRIPT="/home/nemin/pop/powerloom_rewards_staking/claimrestake.py"
LOG_FILE="/home/nemin/pop/powerloom_rewards_staking/restake.txt"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1281377399082061824/hyZ1BMZ3mSlX1y0uGIvV5QzYYa-RCuiS59LO6dN3YdCZXO1-dWdrvPOD3nBkMOCauqzY"

# Activate the virtual environment
source "$VENV_PATH"

# Run python script and capture output and exit code
output=$(python3 "$PYTHON_SCRIPT" 2>&1) #2>&1 to catch stderr
exit_code=$?

# Function to send notification to Discord
send_discord_alert() {
    local message=$1
    escaped_message=$(echo "$message" | jq -Rsa .)  # Escape special characters properly
    curl -s -o /dev/null -X POST -H "Content-Type: application/json" -d "{\"content\": $escaped_message}" "$DISCORD_WEBHOOK_URL"
}

# Check for errors and send alerts
if [[ $exit_code -ne 0 ]]; then
    send_discord_alert "**CRITICAL**: $output"
elif [[ "$output" == *"SUCCESS:"* ]]; then
    send_discord_alert "$output"
else
    send_discord_alert "Unknown python script status: $output"
fi

# Append output to log file for debugging
echo -e "\n$(date) - Exit Code: $exit_code\n$output\n" >> "$LOG_FILE"