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

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Create configuration file
cat > "$OUTPUT_FILE" << EOL
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
            "address": "${SERVER1_ADDRESS}",
            "port": ${SERVER1_PORT},
            "users": [
              {
                "id": "${SERVER1_UUID}",
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
EOL

# Add required reality settings
echo "          \"serverName\": \"${SERVER1_SNI}\"," >> "$OUTPUT_FILE"
echo "          \"fingerprint\": \"${SERVER1_FINGERPRINT}\"" >> "$OUTPUT_FILE"

# Add optional reality settings if provided
if [ -n "$SERVER1_PUBKEY" ]; then
    echo "          ,\"publicKey\": \"${SERVER1_PUBKEY}\"" >> "$OUTPUT_FILE"
fi

if [ -n "$SERVER1_SHORTID" ]; then
    echo "          ,\"shortId\": \"${SERVER1_SHORTID}\"" >> "$OUTPUT_FILE"
fi

# Complete the configuration file
cat >> "$OUTPUT_FILE" << EOL
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

echo "Configuration file generated successfully."

# Validate the JSON if jq is available
if command -v jq &>/dev/null; then
    echo "Validating configuration..."
    if jq . "$OUTPUT_FILE" > /dev/null; then
        echo "Validation successful."
    else
        echo "WARNING: Generated configuration failed validation!"
    fi
fi