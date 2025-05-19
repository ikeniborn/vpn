#!/bin/bash

# This script directly fixes the v2ray config to remove common JSON errors
# Usage: ./fix-v2ray-config.sh [config_file]

CONFIG_FILE="${1:-/opt/v2ray/config.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file $CONFIG_FILE not found!"
    exit 1
fi

echo "Creating backup of original configuration..."
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak-$(date +%s)"

echo "Fixing v2ray configuration at $CONFIG_FILE..."

# Fix common JSON issues directly
echo "Applying direct fixes to JSON format..."

# Remove trailing commas in sniffing section specifically (known issue)
sed -i 's/"enabled": true,/"enabled": true/' "$CONFIG_FILE"
sed -i 's/,"destOverride"/"destOverride"/' "$CONFIG_FILE"

# Fix other common issues
sed -i 's/,\s*}/}/g' "$CONFIG_FILE" # Remove trailing commas before closing braces
sed -i 's/,\s*\]/]/g' "$CONFIG_FILE" # Remove trailing commas before closing brackets

# Try to validate the JSON with jq if available
if command -v jq &>/dev/null; then
    echo "Validating fixed JSON..."
    if jq . "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "JSON is now valid!"
    else
        echo "WARNING: JSON may still have issues."
        echo "Error details:"
        jq . "$CONFIG_FILE" 2>&1 | head -n 10
    fi
else
    echo "jq not available - skipping validation"
fi

echo "Fix complete. Original backup is at ${CONFIG_FILE}.bak-*"