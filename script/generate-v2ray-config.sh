#!/bin/bash

# Script to generate a valid v2ray configuration file
# Usage: ./generate-v2ray-config.sh <server1_address> <server1_port> <server1_uuid> <server1_sni> <server1_fingerprint> [server1_pubkey] [server1_shortid]

# Check arguments
if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <server1_address> <server1_port> <server1_uuid> <server1_sni> <server1_fingerprint> [server1_pubkey] [server1_shortid]"
    exit 1
fi

SERVER1_ADDRESS="$1"
SERVER1_PORT="$2"
SERVER1_UUID="$3"
SERVER1_SNI="$4"
SERVER1_FINGERPRINT="$5"
SERVER1_PUBKEY="${6:-}"
SERVER1_SHORTID="${7:-}"
OUTPUT_FILE="${8:-/opt/v2ray/config.json}"

echo "Generating v2ray configuration file at $OUTPUT_FILE..."

# Verify UUID format
if [[ ! "$SERVER1_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "WARNING: UUID format appears to be invalid: $SERVER1_UUID"
    echo "Proceeding anyway, but this may cause authentication issues."
fi

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Write configuration as a single operation to avoid partial writes
cat > "$OUTPUT_FILE" << 'EOL'
{
  "log": {
    "loglevel": "debug",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "tag": "socks-inbound",
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "tag": "http-inbound",
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {
        "auth": "noauth"
      }
    },
    {
      "tag": "transparent-inbound",
      "port": 1081,
      "listen": "0.0.0.0",
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "tunnel-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "SERVER1_ADDRESS_PLACEHOLDER",
            "port": SERVER1_PORT_PLACEHOLDER,
            "users": [
              {
                "id": "SERVER1_UUID_PLACEHOLDER",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "SERVER1_SNI_PLACEHOLDER",
          "fingerprint": "SERVER1_FINGERPRINT_PLACEHOLDER"
          REALITY_PUBKEY_PLACEHOLDER
          REALITY_SHORTID_PLACEHOLDER
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["127.0.0.1/32"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["socks-inbound", "http-inbound", "transparent-inbound"],
        "outboundTag": "tunnel-out"
      }
    ]
  }
}
EOL

# Replace placeholders
sed -i "s/SERVER1_ADDRESS_PLACEHOLDER/$SERVER1_ADDRESS/g" "$OUTPUT_FILE"
sed -i "s/SERVER1_PORT_PLACEHOLDER/$SERVER1_PORT/g" "$OUTPUT_FILE"
sed -i "s/SERVER1_UUID_PLACEHOLDER/$SERVER1_UUID/g" "$OUTPUT_FILE"
sed -i "s/SERVER1_SNI_PLACEHOLDER/$SERVER1_SNI/g" "$OUTPUT_FILE"
sed -i "s/SERVER1_FINGERPRINT_PLACEHOLDER/$SERVER1_FINGERPRINT/g" "$OUTPUT_FILE"

# Handle optional Reality settings
if [ -n "$SERVER1_PUBKEY" ]; then
    sed -i "s/REALITY_PUBKEY_PLACEHOLDER/,\"publicKey\": \"$SERVER1_PUBKEY\"/g" "$OUTPUT_FILE"
else
    sed -i "s/REALITY_PUBKEY_PLACEHOLDER//g" "$OUTPUT_FILE"
fi

if [ -n "$SERVER1_SHORTID" ]; then
    sed -i "s/REALITY_SHORTID_PLACEHOLDER/,\"shortId\": \"$SERVER1_SHORTID\"/g" "$OUTPUT_FILE"
else
    sed -i "s/REALITY_SHORTID_PLACEHOLDER//g" "$OUTPUT_FILE"
fi

echo "Configuration file generated successfully."

# Validate the JSON if jq is available
if command -v jq &>/dev/null; then
    echo "Validating configuration..."
    if jq . "$OUTPUT_FILE" > /dev/null; then
        echo "Validation successful."
    else
        echo "WARNING: Generated configuration failed validation!"
        echo "Attempting to fix..."
        jq . "$OUTPUT_FILE" > "${OUTPUT_FILE}.fixed" 2>/dev/null && mv "${OUTPUT_FILE}.fixed" "$OUTPUT_FILE"
        echo "Fixed configuration saved."
    fi
fi

# Final validation
echo "Checking for critical values..."
if grep -q "SERVER1_UUID_PLACEHOLDER" "$OUTPUT_FILE"; then
    echo "ERROR: UUID not properly inserted in configuration!"
    exit 1
fi

echo "Configuration generated and validated successfully."