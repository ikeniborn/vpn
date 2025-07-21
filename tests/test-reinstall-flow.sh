#!/bin/bash
# Test the new reinstallation flow

echo "Testing VPN reinstallation flow..."
echo ""
echo "The reinstallation question should now appear:"
echo "1. AFTER selecting the protocol"
echo "2. NOT before showing the protocol list"
echo ""
echo "Steps:"
echo "1. Select 'Install VPN Server' from main menu"
echo "2. Choose a protocol (e.g., VLESS+Reality)"
echo "3. THEN you should see the reinstallation warning if server is installed"
echo ""
echo "Press Enter to start the test..."
read

# Run the menu
/home/ikeniborn/Documents/Project/vpn/target/release/vpn menu