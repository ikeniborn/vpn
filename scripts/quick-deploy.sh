#!/bin/bash
#
# Quick VPN Deployment Script - One-liner installer
# This script provides the fastest way to deploy VPN server
#
# Usage: curl -sSL https://your-domain.com/quick-deploy.sh | bash
# Or: wget -qO- https://your-domain.com/quick-deploy.sh | bash

set -euo pipefail

# Configuration
GITHUB_REPO="https://github.com/your-org/vpn"
DEPLOY_SCRIPT_URL="${GITHUB_REPO}/raw/main/scripts/deploy.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===== Quick VPN Server Deployment =====${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Trying with sudo..."
    exec sudo "$0" "$@"
fi

# Download and run the full deployment script
echo -e "${BLUE}[*]${NC} Downloading deployment script..."
curl -sSL "$DEPLOY_SCRIPT_URL" -o /tmp/vpn-deploy.sh
chmod +x /tmp/vpn-deploy.sh

echo -e "${BLUE}[*]${NC} Starting deployment..."
/tmp/vpn-deploy.sh "$@"

# Cleanup
rm -f /tmp/vpn-deploy.sh

echo -e "${GREEN}[✓]${NC} Deployment complete!"