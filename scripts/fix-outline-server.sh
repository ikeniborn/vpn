#!/bin/bash

# Fix script for Outline Server (shadowbox) configuration issues
# This script:
# 1. Fixes the TypeError: path must be a string or Buffer error 
# 2. Changes management port and API port for Outline

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default ports - these can be overridden by command line arguments
DEFAULT_API_PORT=8989
DEFAULT_KEYS_PORT=8388

# Parse command line arguments
API_PORT=$DEFAULT_API_PORT
KEYS_PORT=$DEFAULT_KEYS_PORT

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --api-port)
            API_PORT="$2"
            shift
            ;;
        --keys-port)
            KEYS_PORT="$2"
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [--api-port PORT] [--keys-port PORT]"
            exit 1
            ;;
    esac
    shift
done

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
info "API Port: $API_PORT"
info "Keys Port: $KEYS_PORT"

# Define paths for both regular Outline installation and Docker-based setup
OUTLINE_DIR="/opt/outline"
DOCKER_OUTLINE_DIR="/opt/vpn/outline-server"

# Check which installation method is being used
if [ -d "$OUTLINE_DIR" ]; then
    # Standard Outline installation
    STATE_DIR="$OUTLINE_DIR/persisted-state"
    info "Found standard Outline installation at $OUTLINE_DIR"
elif [ -d "$DOCKER_OUTLINE_DIR" ]; then
    # Docker-based setup
    STATE_DIR="$DOCKER_OUTLINE_DIR/persisted-state"
    DATA_DIR="$DOCKER_OUTLINE_DIR/data"
    info "Found Docker-based Outline installation at $DOCKER_OUTLINE_DIR"
else
    # Create default directory structure if not found
    info "No existing Outline installation found. Creating default directories."
    OUTLINE_DIR="/opt/outline"
    STATE_DIR="$OUTLINE_DIR/persisted-state"
    mkdir -p "$STATE_DIR"
fi

# Generate a random API prefix for security
api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)

# Create necessary directories
mkdir -p "$STATE_DIR"

# Create the shadowbox_server_config.json file in the persisted-state directory
info "Creating shadowbox_server_config.json in $STATE_DIR..."

cat > "$STATE_DIR/shadowbox_server_config.json" <<EOF
{
  "hostname": "${SERVER_IP}",
  "apiPort": ${API_PORT},
  "apiPrefix": "${api_prefix}",
  "portForNewAccessKeys": ${KEYS_PORT},
  "accessKeyDataLimit": {},
  "defaultDataLimit": null,
  "unrestrictedAccessKeyDataLimit": {}
}
EOF

chmod 600 "$STATE_DIR/shadowbox_server_config.json"

# If Docker setup, also create the file in the data directory
if [ -d "$DOCKER_OUTLINE_DIR" ]; then
    mkdir -p "$DATA_DIR"
    cp "$STATE_DIR/shadowbox_server_config.json" "$DATA_DIR/shadowbox_server_config.json"
    chmod 600 "$DATA_DIR/shadowbox_server_config.json"
    info "Also copied configuration to $DATA_DIR/shadowbox_server_config.json"
fi

info "Configuration files created successfully!"

# Update Docker environment variables if using Docker
if [ -d "$DOCKER_OUTLINE_DIR" ] && [ -f "/opt/vpn/docker-compose.yml" ]; then
    info "Updating Docker environment variables..."
    
    # Backup the original docker-compose.yml file
    cp "/opt/vpn/docker-compose.yml" "/opt/vpn/docker-compose.yml.bak"
    
    # Update the API port in the docker-compose.yml file
    sed -i "s/SB_API_PORT=.*/SB_API_PORT=${API_PORT}/" "/opt/vpn/docker-compose.yml"
    
    info "Docker environment variables updated"
fi

# Restart the Outline server
info "Restarting Outline server..."

if [ -d "$DOCKER_OUTLINE_DIR" ]; then
    # Docker-based setup
    if command -v docker-compose &> /dev/null && [ -f "/opt/vpn/docker-compose.yml" ]; then
        cd /opt/vpn && docker-compose down
        cd /opt/vpn && docker-compose up -d
    else
        docker restart outline-server 2>/dev/null || true
    fi
else
    # Standard installation
    systemctl restart shadowbox 2>/dev/null || true
fi

info "Outline server has been restarted with new configuration"
info "Management API port: $API_PORT"
info "Access keys port: $KEYS_PORT"
info ""
info "If you're using Outline Manager, you'll need to reconnect using the new API details"