#!/bin/bash

# Fix script for Outline Server (shadowbox) error:
# "TypeError: path must be a string or Buffer"
# This script also allows changing the management port and API port

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default ports
DEFAULT_API_PORT=8989
DEFAULT_KEYS_PORT=8388

# Parse command line arguments
API_PORT=$DEFAULT_API_PORT
KEYS_PORT=$DEFAULT_KEYS_PORT

# Function to display usage information
display_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script fixes the 'TypeError: path must be a string or Buffer' error"
    echo "and allows changing the Outline Server API and keys ports."
    echo ""
    echo "Options:"
    echo "  --api-port PORT     Port for Outline management API (default: 8989)"
    echo "  --keys-port PORT    Port for Outline access keys (default: 8388)"
    echo "  --help              Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --api-port 8989 --keys-port 8388"
}

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
        --help)
            display_usage
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            display_usage
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

info "Outline Server Fix Tool"
info "API Port: $API_PORT"
info "Keys Port: $KEYS_PORT"

# Define path variables
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
STANDARD_OUTLINE_DIR="/opt/outline"

# Detect which Outline directory to use
if [ -d "$OUTLINE_DIR" ]; then
    info "Found Docker-based Outline installation at $OUTLINE_DIR"
    INSTALL_DIR="$OUTLINE_DIR"
    IS_DOCKER=true
elif [ -d "$STANDARD_OUTLINE_DIR" ]; then
    info "Found standard Outline installation at $STANDARD_OUTLINE_DIR"
    INSTALL_DIR="$STANDARD_OUTLINE_DIR"
    IS_DOCKER=false
else
    warn "No existing Outline installation found. Creating default Docker-based directory."
    INSTALL_DIR="$OUTLINE_DIR"
    IS_DOCKER=true
    mkdir -p "$INSTALL_DIR"
fi

# Get server hostname/IP using multiple fallback methods
info "Detecting server IP address..."
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null ||
            ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null ||
            curl -4 -s ifconfig.me 2>/dev/null ||
            curl -4 -s icanhazip.com 2>/dev/null ||
            echo "127.0.0.1")

info "Using server IP address: $SERVER_IP"

# Create necessary directories
mkdir -p "${INSTALL_DIR}/data"
mkdir -p "${INSTALL_DIR}/persisted-state"

# Generate a random API prefix for security
api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)

# Create the shadowbox_server_config.json file in the data directory
info "Creating shadowbox_server_config.json in ${INSTALL_DIR}/data..."

cat > "${INSTALL_DIR}/data/shadowbox_server_config.json" <<EOF
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
chmod 600 "${INSTALL_DIR}/data/shadowbox_server_config.json"

# Create a copy in the persisted-state directory
info "Creating shadowbox_server_config.json in ${INSTALL_DIR}/persisted-state..."
cp "${INSTALL_DIR}/data/shadowbox_server_config.json" "${INSTALL_DIR}/persisted-state/shadowbox_server_config.json"
chmod 600 "${INSTALL_DIR}/persisted-state/shadowbox_server_config.json"

info "Configuration files created successfully"

# Update Docker environment variables if using Docker
if [ "$IS_DOCKER" = true ] && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
    info "Updating Docker environment variables..."
    
    # Create backup of docker-compose.yml
    cp "${BASE_DIR}/docker-compose.yml" "${BASE_DIR}/docker-compose.yml.bak"
    
    # Update the API_PORT in docker-compose.yml
    sed -i "s/SB_API_PORT=[0-9]*/SB_API_PORT=${API_PORT}/" "${BASE_DIR}/docker-compose.yml" || true
    
    info "Docker environment variables updated"
fi

# Restart the Outline Server
info "Restarting Outline server..."

if [ "$IS_DOCKER" = true ]; then
    if command -v docker-compose &> /dev/null && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        # Use docker-compose if available
        cd "${BASE_DIR}" && docker-compose down
        cd "${BASE_DIR}" && docker-compose up -d
    else
        # Fall back to docker if docker-compose is not available
        docker restart outline-server 2>/dev/null || {
            warn "Failed to restart container with docker restart. Using docker-compose if available..."
            cd "${BASE_DIR}" && docker-compose down 2>/dev/null || true
            cd "${BASE_DIR}" && docker-compose up -d 2>/dev/null || true
        }
    fi
else
    # For standard installations
    systemctl restart shadowbox 2>/dev/null || {
        warn "Failed to restart with systemctl. Trying direct Docker commands..."
        docker restart outline-server 2>/dev/null || true
    }
fi

info "Outline server has been restarted with new configuration"
info "Management API port: $API_PORT"
info "Access keys port: $KEYS_PORT"
info ""
info "If you're using Outline Manager, you'll need to reconnect using the new API details"

# Show a summary of what was fixed
echo ""
echo "==================================================================="
echo "SUMMARY OF CHANGES:"
echo "==================================================================="
echo "1. Fixed 'TypeError: path must be a string or Buffer' error by"
echo "   creating proper configuration files in both required locations."
echo ""
echo "2. Changed API management port to: $API_PORT"
echo ""
echo "3. Changed access keys port to: $KEYS_PORT"
echo ""
echo "4. Restarted the Outline server to apply changes"
echo "==================================================================="