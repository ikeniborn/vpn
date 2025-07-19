#!/bin/bash

# VPN Management System - Stub Script
# This script helps users when there are PATH conflicts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Clear screen
clear

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       VPN Management System - Notice         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}⚠️  The VPN command location has changed!${NC}"
echo
echo -e "${BLUE}Information:${NC}"
echo "  • The old vpn binary was replaced during installation"
echo "  • The new VPN Management System is now available"
echo "  • This stub script is helping you transition"
echo
echo -e "${GREEN}How to run VPN Management System:${NC}"
echo
echo -e "  ${YELLOW}1. Run with full path:${NC}"
echo "     /usr/local/bin/vpn"
echo
echo -e "  ${YELLOW}2. Run with sudo (recommended):${NC}"
echo "     sudo vpn"
echo
echo -e "  ${YELLOW}3. Update your shell hash:${NC}"
echo "     hash -d vpn"
echo "     vpn"
echo
echo -e "${BLUE}Available commands:${NC}"
echo "  • vpn                    - Interactive menu"
echo "  • sudo vpn               - Full access menu"
echo "  • vpn install <protocol> - Install VPN server"
echo "  • vpn status             - Check server status"
echo "  • vpn --help             - Show all commands"
echo
echo -e "${GREEN}Documentation:${NC} /opt/vpn/docs/"
echo -e "${GREEN}Configuration:${NC} /opt/vpn/configs/"
echo
echo -n "Press Enter to run VPN Management System with sudo..."
read -r

# Run the actual VPN command with sudo
exec sudo /usr/local/bin/vpn "$@"