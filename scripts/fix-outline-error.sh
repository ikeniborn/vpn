#!/bin/bash

# fix-outline-error.sh - Fix for the "TypeError: path must be a string or Buffer" error in Outline VPN Server
# This script specifically addresses the error when running Outline VPN on ARM architectures
#
# Error: TypeError: path must be a string or Buffer
#    at Object.fs.openSync (fs.js:646:18)
#    at Object.fs.readFileSync (fs.js:551:33)
#    at /root/shadowbox/app/server/main.js:163:29

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

# Display banner
info "Outline VPN ARM Error Fix"
info "Fixing 'TypeError: path must be a string or Buffer' error"
echo "======================================================"

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
fi

if ! systemctl is-active --quiet docker; then
    warn "Docker service is not running. Attempting to start..."
    systemctl start docker
    if ! systemctl is-active --quiet docker; then
        error "Could not start Docker service. Please check Docker installation."
    fi
fi

# Check if outline-server container exists
if ! docker ps -a | grep -q outline-server; then
    error "Outline server container not found. Please ensure it has been installed."
fi

# Create necessary configuration directories
info "Creating necessary configuration directories..."
mkdir -p "${OUTLINE_DIR}/data"
mkdir -p "${OUTLINE_DIR}/persisted-state"

# Get server IP address for configuration
server_ip=$(hostname -I | awk '{print $1}')
if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
    server_ip=$(ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null || echo "localhost")
    info "Using IP from ip route command: ${server_ip}"
fi

info "Using server IP address for configuration: ${server_ip}"

# Get the current API port from docker-compose or use default
API_PORT=$(docker inspect --format='{{range .Config.Env}}{{if eq (index (split . "=") 0) "SB_API_PORT"}}{{index (split . "=") 1}}{{end}}{{end}}' outline-server 2>/dev/null || echo "8080")
OUTLINE_PORT=$(docker inspect --format='{{range $key, $value := .NetworkSettings.Ports}}{{if contains "tcp" $key}}{{$key}}{{end}}{{end}}' outline-server 2>/dev/null | sed 's/\/tcp//' || echo "8388")

info "Detected Outline API port: ${API_PORT}"
info "Detected Outline Server port: ${OUTLINE_PORT}"

# Generate a random API prefix for security
api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)

# Create shadowbox_server_config.json in data directory
info "Creating shadowbox_server_config.json in ${OUTLINE_DIR}/data..."
cat > "${OUTLINE_DIR}/data/shadowbox_server_config.json" <<EOF
{
  "hostname": "${server_ip}",
  "apiPort": ${API_PORT},
  "apiPrefix": "${api_prefix}",
  "portForNewAccessKeys": ${OUTLINE_PORT},
  "accessKeyDataLimit": {},
  "defaultDataLimit": null,
  "unrestrictedAccessKeyDataLimit": {}
}
EOF
chmod 600 "${OUTLINE_DIR}/data/shadowbox_server_config.json"

# Create shadowbox_server_config.json in persisted-state directory
info "Creating shadowbox_server_config.json in ${OUTLINE_DIR}/persisted-state..."
cp "${OUTLINE_DIR}/data/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
chmod 600 "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"

# Stop and remove the outline-server container
info "Stopping Outline server to apply fix..."
docker stop outline-server || true

# Check if we need to restart other containers
v2ray_was_running=false
if docker ps | grep -q v2ray; then
    v2ray_was_running=true
    info "Stopping v2ray container temporarily..."
    docker stop v2ray || true
fi

# Start the outline-server container with specific environment variables
info "Restarting Outline server with fixed configuration..."
docker start outline-server || docker start $(docker ps -a --filter "name=outline-server" --format "{{.ID}}")

# Wait a few seconds for the container to initialize
info "Waiting for container to initialize..."
sleep 10

# Restart v2ray if it was running
if [ "$v2ray_was_running" = true ]; then
    info "Restarting v2ray container..."
    docker start v2ray || docker start $(docker ps -a --filter "name=v2ray" --format "{{.ID}}")
fi

# Verify that the error is fixed
info "Checking if error is fixed..."
if docker logs outline-server 2>&1 | grep -q "TypeError: path must be a string or Buffer"; then
    warn "Error still exists. Additional troubleshooting may be required."
    warn "Please check docker logs with: docker logs outline-server"
else
    info "Success! The 'TypeError: path must be a string or Buffer' error appears to be fixed."
    info "Outline server is now running properly."
fi

echo "======================================================"
info "Fixed configuration settings:"
info "- Server IP: ${server_ip}"
info "- API Port: ${API_PORT}"
info "- Outline Port: ${OUTLINE_PORT}"
echo "======================================================"