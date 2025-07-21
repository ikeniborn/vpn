#!/bin/bash
# Test VPN status display

echo "Testing VPN status display..."
echo ""
echo "Expected behavior:"
echo "1. Menu header should show status of ALL protocols"
echo "2. Installed protocols should show as green ● or red ○"
echo "3. Not installed protocols should show as dimmed ○ (not installed)"
echo "4. Server Management -> Show Status should display correct container info"
echo ""

echo "Current Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "vless|shadowsocks|wireguard|proxy"
echo ""

echo "Testing menu display..."
echo "Press Enter to continue..."
read

# Run the menu
/home/ikeniborn/Documents/Project/vpn/target/release/vpn menu