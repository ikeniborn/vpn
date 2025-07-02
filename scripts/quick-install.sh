#!/bin/bash
#
# Quick VPN CLI Installation Script
# One-liner installer for VPN CLI tool
#
# Usage: curl -sSL https://your-domain.com/quick-install.sh | bash
# Or: wget -qO- https://your-domain.com/quick-install.sh | bash

set -euo pipefail

# Configuration
GITHUB_REPO="https://github.com/your-org/vpn"
INSTALL_SCRIPT_URL="${GITHUB_REPO}/raw/main/scripts/install.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===== VPN CLI Quick Installation =====${NC}"
echo

# Download and run the full installation script
echo -e "${BLUE}[*]${NC} Downloading installation script..."
curl -sSL "$INSTALL_SCRIPT_URL" -o /tmp/vpn-install.sh
chmod +x /tmp/vpn-install.sh

echo -e "${BLUE}[*]${NC} Starting installation..."
/tmp/vpn-install.sh "$@"

# Cleanup
rm -f /tmp/vpn-install.sh

echo -e "${GREEN}[✓]${NC} Installation complete!"