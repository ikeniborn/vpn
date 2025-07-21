#!/bin/bash
# Test menu positioning and navigation

echo "Testing VPN menu positioning..."
echo ""
echo "The menu should:"
echo "1. Always appear at the top of the screen"
echo "2. Clear the screen before showing each submenu"
echo "3. Properly handle terminal resizing"
echo ""
echo "Press Enter to start the test..."
read

# Run the menu
/home/ikeniborn/Documents/Project/vpn/target/release/vpn menu