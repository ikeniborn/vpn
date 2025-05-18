#!/bin/bash
#
# Fix permissions for Outline VPN with v2ray VLESS
# This script fixes permission issues that can prevent containers from accessing config files

# Set correct permissions for V2Ray config and certificates
sudo chmod 644 /opt/v2ray/config.json
sudo chmod 644 /opt/outline/persisted-state/shadowbox-selfsigned.key
sudo chmod 644 /opt/outline/persisted-state/shadowbox-selfsigned.crt

echo "Permissions fixed for V2Ray and Outline VPN files"
echo "V2Ray config: /opt/v2ray/config.json"
echo "TLS cert: /opt/outline/persisted-state/shadowbox-selfsigned.crt"
echo "TLS key: /opt/outline/persisted-state/shadowbox-selfsigned.key"

# Restart containers to apply changes
echo "Restarting containers..."
docker restart v2ray shadowbox

echo "Done! Services should now be running properly"