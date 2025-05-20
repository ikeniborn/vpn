#!/bin/bash

# Fix script for Outline Server (shadowbox) configuration issues
# This script creates the missing shadowbox_server_config.json file

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"

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

# Get server hostname/IP
SERVER_IP=$(hostname -I | awk '{print $1}' || curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)

if [ -z "$SERVER_IP" ]; then
    error "Could not determine server IP address"
fi

info "Using server IP address: $SERVER_IP"

# Create directory if not exists
mkdir -p "${OUTLINE_DIR}/data"

# Create the shadowbox_server_config.json file
info "Creating shadowbox_server_config.json file..."

cat > "${OUTLINE_DIR}/data/shadowbox_server_config.json" <<EOF
{
  "hostname": "${SERVER_IP}",
  "portForNewAccessKeys": 8388,
  "accessKeyDataLimit": {},
  "defaultDataLimit": null,
  "unrestrictedAccessKeyDataLimit": {}
}
EOF

chmod 600 "${OUTLINE_DIR}/data/shadowbox_server_config.json"

info "Shadowbox configuration file created successfully at ${OUTLINE_DIR}/data/shadowbox_server_config.json"
info "Now restarting the containers..."

# Change to BASE_DIR for docker-compose commands
cd "${BASE_DIR}" || error "Failed to change directory to ${BASE_DIR}"

# Stop and remove containers
docker-compose down

# Start containers again
docker-compose up -d

info "Containers restarted. Please check status with 'docker ps' after a few moments."
info "If issues persist, check logs with 'docker logs outline-server'"