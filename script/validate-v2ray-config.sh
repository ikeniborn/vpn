#!/bin/bash

# This script validates and fixes the v2ray config file
# It removes trailing commas and ensures the JSON is valid

CONFIG_FILE="/opt/v2ray/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file $CONFIG_FILE not found!"
    exit 1
fi

# First, make a backup
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

echo "Validating and fixing v2ray configuration..."

# Use jq to validate and reformat the JSON
if command -v jq &>/dev/null; then
    if jq . "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null; then
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo "Configuration file validated and reformatted successfully."
    else
        echo "JSON validation failed. Attempting to fix common errors..."
        
        # Fix common JSON errors (like trailing commas)
        # 1. Replace trailing commas before closing brackets
        sed -i 's/,\s*}/}/g' "$CONFIG_FILE"
        sed -i 's/,\s*\]/]/g' "$CONFIG_FILE"
        
        # Try validating again
        if jq . "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null; then
            mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            echo "Configuration file fixed and validated successfully."
        else
            echo "Failed to fix JSON configuration automatically."
            echo "Please check the file manually:"
            echo "Original backup is at ${CONFIG_FILE}.bak"
            exit 1
        fi
    fi
else
    echo "jq is not installed. Cannot validate JSON configuration."
    exit 1
fi

echo "Configuration validation complete."