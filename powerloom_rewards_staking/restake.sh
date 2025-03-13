#!/bin/bash
# Define paths and values explicitly
# Set up automation such as cronjob to run daily.
VENV_PATH="/path/to/virtualenv/bin/activate"
PYTHON_SCRIPT="/path/to/powerloom_rewards_staking/claimrestake.py"
LOG_FILE="/path/to/powerloom_rewards_staking/restake.txt"
DISCORD_WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL"

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
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        send_discord_alert "**CRITICAL**: $output"
    fi
elif [[ "$output" == *"SUCCESS:"* ]]; then
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        send_discord_alert "$output"
    fi
else
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        send_discord_alert "Unknown python script status: $output"
    fi
fi

# Append output to log file for debugging
echo -e "\n$(date) - Exit Code: $exit_code\n$output\n" >> "$LOG_FILE"