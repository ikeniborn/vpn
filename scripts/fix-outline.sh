#!/bin/bash

# fix-outline.sh - Main script to fix Outline VPN errors
# This script serves as a launcher for the more specialized fixing scripts:
# - fix-outline-error.sh: Specifically targets the "TypeError: path must be a string or Buffer" error
# - fix-outline-server.sh: Comprehensive fix for all common Outline Server issues

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root or with sudo privileges"
fi

# Get the script directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Display banner
echo "======================================================"
info "Outline VPN Server Fix Menu"
info "Choose an option to fix your Outline VPN installation"
echo "======================================================"
echo ""
echo "1) Quick Fix for 'TypeError: path must be a string or Buffer'"
echo "   - Targets specifically this common error on ARM systems"
echo "   - Fastest solution if you know what's wrong"
echo ""
echo "2) Comprehensive Server Fix (Recommended)"
echo "   - Full repair of Outline Server configuration"
echo "   - Fixes multiple issues including path errors, configuration problems"
echo "   - Provides detailed diagnostics and management information"
echo ""
echo "3) Exit"
echo ""

# Get user choice
read -p "Enter your choice (1-3): " CHOICE

case $CHOICE in
    1)
        info "Running quick error fix script..."
        if [ -f "${SCRIPT_DIR}/fix-outline-error.sh" ]; then
            chmod +x "${SCRIPT_DIR}/fix-outline-error.sh"
            "${SCRIPT_DIR}/fix-outline-error.sh"
        else
            error "Error fix script (${SCRIPT_DIR}/fix-outline-error.sh) not found!"
        fi
        ;;
    2)
        info "Running comprehensive server fix script..."
        if [ -f "${SCRIPT_DIR}/fix-outline-server.sh" ]; then
            chmod +x "${SCRIPT_DIR}/fix-outline-server.sh"
            "${SCRIPT_DIR}/fix-outline-server.sh"
        else
            error "Server fix script (${SCRIPT_DIR}/fix-outline-server.sh) not found!"
        fi
        ;;
    3)
        info "Exiting..."
        exit 0
        ;;
    *)
        error "Invalid choice. Please run script again and select option 1, 2, or 3."
        ;;
esac

exit 0