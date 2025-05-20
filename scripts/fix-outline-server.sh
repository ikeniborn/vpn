#!/bin/bash

# fix-outline-server.sh - Comprehensive fix script for Outline Server on ARM architectures
# This script addresses common issues including the "TypeError: path must be a string or Buffer" error
# and ensures proper configuration of the Outline VPN server

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
LOGS_DIR="${BASE_DIR}/logs/outline"

# Default values
OUTLINE_PORT="8388"
API_PORT="8989"

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
echo "======================================================"
info "Outline VPN Server Fix Script"
info "Addressing configuration issues and errors on ARM systems"
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

# Look for the Outline server container
if ! docker ps -a | grep -q outline-server; then
    warn "Outline server container not found."
    read -p "Would you like to check for containers with a different name? [y/N] " check_other
    if [[ "$check_other" =~ ^[Yy]$ ]]; then
        docker ps -a
        read -p "Please enter the container ID or name of the Outline server: " container_name
        if [ -z "$container_name" ]; then
            error "No container specified. Exiting."
        fi
    else
        error "Outline server container not found. Please ensure it has been installed."
    fi
else
    container_name="outline-server"
fi

# Get current configuration
info "Retrieving current configuration..."

# Get current ports
if [ "$container_name" = "outline-server" ]; then
    # Try to get port mapping from docker inspect
    API_PORT=$(docker inspect --format='{{range .Config.Env}}{{if eq (index (split . "=") 0) "SB_API_PORT"}}{{index (split . "=") 1}}{{end}}{{end}}' outline-server 2>/dev/null || echo "8989")
    OUTLINE_PORT=$(docker inspect --format='{{range $key, $value := .NetworkSettings.Ports}}{{if contains "tcp" $key}}{{$key}}{{end}}{{end}}' outline-server 2>/dev/null | sed 's/\/tcp//' || echo "8388")
    
    # If the values are empty, try alternative methods
    if [ -z "$API_PORT" ]; then
        API_PORT=$(docker exec -i outline-server env 2>/dev/null | grep SB_API_PORT | cut -d= -f2 || echo "8989")
    fi
    if [ -z "$OUTLINE_PORT" ]; then
        OUTLINE_PORT=$(docker exec -i outline-server env 2>/dev/null | grep SB_PORT | cut -d= -f2 || echo "8388")
        # If still empty, check shadowbox config
        if [ -z "$OUTLINE_PORT" ] && docker exec -i outline-server cat /opt/outline/persisted-state/shadowbox_server_config.json &>/dev/null; then
            OUTLINE_PORT=$(docker exec -i outline-server cat /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null | grep -o '"portForNewAccessKeys":[0-9]*' | cut -d: -f2 || echo "8388")
        fi
    fi
fi

info "Detected API port: ${API_PORT}"
info "Detected Outline port: ${OUTLINE_PORT}"

# Create necessary directories
info "Creating required directories..."
mkdir -p "${OUTLINE_DIR}/data"
mkdir -p "${OUTLINE_DIR}/persisted-state"
mkdir -p "${LOGS_DIR}"

# Ensure permissions are correct
chmod 700 "${OUTLINE_DIR}/data"
chmod 700 "${OUTLINE_DIR}/persisted-state"
chmod 700 "${LOGS_DIR}"

# Get server IP address for configuration
info "Detecting server IP address..."
server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
    server_ip=$(ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null)
    info "Using IP from ip route command: ${server_ip}"
fi
if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null ||
                    curl -4 -s --connect-timeout 5 icanhazip.com 2>/dev/null)
        info "Using IP from external service: ${server_ip}"
    fi
fi
if [ -z "$server_ip" ]; then
    warn "Could not determine server IP address. Using localhost as fallback."
    server_ip="127.0.0.1"
fi

info "Using server IP address: ${server_ip}"

# Check for existing API prefix or generate a new one
api_prefix=""
if docker exec -i outline-server cat /opt/outline/persisted-state/shadowbox_server_config.json &>/dev/null; then
    api_prefix=$(docker exec -i outline-server cat /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null | grep -o '"apiPrefix":"[^"]*"' | cut -d'"' -f4 || echo "")
fi
if [ -z "$api_prefix" ]; then
    api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)
    info "Generated new API prefix: ${api_prefix}"
else
    info "Using existing API prefix: ${api_prefix}"
fi

# Create shadowbox_server_config.json with proper paths and data
info "Creating shadowbox_server_config.json in data and persisted-state directories..."
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

# Create a copy in the persisted-state directory
cp "${OUTLINE_DIR}/data/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
chmod 600 "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"

# Create access.txt files if they don't exist
if [ ! -f "${OUTLINE_DIR}/data/access.txt" ]; then
    touch "${OUTLINE_DIR}/data/access.txt"
    chmod 600 "${OUTLINE_DIR}/data/access.txt"
    info "Created empty access.txt in data directory"
fi

if [ ! -f "${OUTLINE_DIR}/persisted-state/access.txt" ]; then
    cp "${OUTLINE_DIR}/data/access.txt" "${OUTLINE_DIR}/persisted-state/access.txt" 2>/dev/null || touch "${OUTLINE_DIR}/persisted-state/access.txt"
    chmod 600 "${OUTLINE_DIR}/persisted-state/access.txt"
    info "Created access.txt in persisted-state directory"
fi

# Stop container(s) for applying fixes
info "Stopping container(s) to apply fixes..."

# Check if v2ray is running and needs to be stopped
v2ray_was_running=false
if docker ps | grep -q v2ray; then
    v2ray_was_running=true
    info "Stopping v2ray container temporarily..."
    docker stop v2ray || true
fi

# Stop the Outline server
docker stop "$container_name" || true

# Fix for possible Docker user namespace issues
info "Checking for Docker user namespace issues..."
userns_remap=$(docker info 2>/dev/null | grep -q "userns-remap: true" && echo "true" || echo "false")
if [ "$userns_remap" = "true" ]; then
    warn "Docker user namespace remapping is enabled. This may cause container layer mapping issues."
    
    # Attempt to disable it temporarily in Docker daemon.json
    if [ -f "/etc/docker/daemon.json" ]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
        info "Backed up /etc/docker/daemon.json to /etc/docker/daemon.json.bak"
        
        # Update daemon.json to disable user namespace remapping
        if grep -q "userns-remap" /etc/docker/daemon.json; then
            sed -i 's/"userns-remap": "[^"]*"/"userns-remap": ""/' /etc/docker/daemon.json
        else
            # If userns-remap isn't in the file, add it
            if [ -s "/etc/docker/daemon.json" ]; then
                # File exists and is not empty
                sed -i '1s/^{\s*/{\n  "userns-remap": "",/' /etc/docker/daemon.json
            else
                # File doesn't exist or is empty
                echo '{\n  "userns-remap": ""\n}' > /etc/docker/daemon.json
            fi
        fi
        
        # Restart Docker with the new settings
        info "Restarting Docker daemon with updated settings..."
        systemctl restart docker
        sleep 5
    fi
fi

# Modify Docker container permissions if needed
info "Creating a Docker command to restart with proper permissions..."

# Extract existing environment variables
env_vars=$(docker inspect --format='{{range .Config.Env}}--env {{.}} {{end}}' "$container_name" 2>/dev/null || echo "")
if [ -z "$env_vars" ]; then
    env_vars="--env SB_PUBLIC_IP=${server_ip} --env SB_API_PORT=${API_PORT} --env SB_STATE_DIR=/opt/outline/persisted-state"
fi

# Update SB_STATE_DIR if missing
if ! echo "$env_vars" | grep -q "SB_STATE_DIR"; then
    env_vars="$env_vars --env SB_STATE_DIR=/opt/outline/persisted-state"
fi

# Ensure SB_PUBLIC_IP is set
if ! echo "$env_vars" | grep -q "SB_PUBLIC_IP"; then
    env_vars="$env_vars --env SB_PUBLIC_IP=${server_ip}"
fi

# Start the container with the corrected configuration
info "Starting Outline server with fixed configuration..."
docker start "$container_name" || docker start $(docker ps -a --filter "name=${container_name}" --format "{{.ID}}")

info "Waiting for container to initialize (15 seconds)..."
sleep 15

# Check if the container started successfully
if ! docker ps | grep -q "$container_name"; then
    warn "Container failed to start. Checking logs..."
    docker logs "$container_name"
    
    warn "Attempting to restart with explicit configuration..."
    
    # Get the image being used
    image_name=$(docker inspect --format='{{.Config.Image}}' "$container_name" 2>/dev/null || echo "ken1029/shadowbox:latest")
    
    # Get volume mappings
    volume_mappings=$(docker inspect --format='{{range .HostConfig.Binds}}--volume {{.}} {{end}}' "$container_name" 2>/dev/null || echo "--volume ${OUTLINE_DIR}/data:/opt/outline/data --volume ${OUTLINE_DIR}/persisted-state:/opt/outline/persisted-state")
    
    # Get port mappings
    port_mappings=$(docker inspect --format='{{range $p, $conf := .HostConfig.PortBindings}}--publish {{index $conf 0 "HostPort"}}:{{$p}} {{end}}' "$container_name" 2>/dev/null || echo "--publish ${OUTLINE_PORT}:${OUTLINE_PORT}/tcp --publish ${OUTLINE_PORT}:${OUTLINE_PORT}/udp --publish ${API_PORT}:${API_PORT}/tcp")
    
    # Remove the existing container
    docker rm -f "$container_name" || true
    
    # Create a new container with explicit settings
    docker run -d --name "$container_name" --restart always \
        --net host \
        --privileged --security-opt=no-new-privileges:false --security-opt=apparmor:unconfined \
        --user "0:0" \
        ${env_vars} \
        ${volume_mappings} \
        ${image_name}
    
    info "Waiting for container to initialize after restart (20 seconds)..."
    sleep 20
fi

# Restart v2ray if it was running
if [ "$v2ray_was_running" = true ]; then
    info "Restarting v2ray container..."
    docker start v2ray || docker start $(docker ps -a --filter "name=v2ray" --format "{{.ID}}")
    sleep 5
fi

# Check if the error is fixed
info "Checking if error is fixed..."
if docker logs "$container_name" 2>&1 | grep -q "TypeError: path must be a string or Buffer"; then
    warn "Error still exists. Additional troubleshooting may be required."
    warn "Please check docker logs with: docker logs $container_name"
else
    info "Success! The 'TypeError: path must be a string or Buffer' error appears to be fixed."
fi

# Create a management script for future use
info "Creating a management configuration..."

# Generate a summary with connection details
echo "======================================================"
info "Outline Server Fixed Configuration:"
echo "======================================================"
echo "Server IP: ${server_ip}"
echo "API Port: ${API_PORT}"
echo "Outline Port: ${OUTLINE_PORT}"
echo "API Prefix: ${api_prefix}"
echo ""
echo "To manage your Outline server, use this configuration in Outline Manager:"
echo ""

# Try to get or generate the certificate hash
cert_sha256=""
if docker exec -i "$container_name" cat /opt/outline/persisted-state/access.txt &>/dev/null; then
    cert_sha256=$(docker exec -i "$container_name" cat /opt/outline/persisted-state/access.txt 2>/dev/null | grep "certSha256:" | sed "s/certSha256://" || echo "")
fi

# If we couldn't find a cert hash from access.txt, try to get it from the certificate file
if [ -z "$cert_sha256" ] && docker exec -i "$container_name" cat /opt/outline/persisted-state/shadowbox-selfsigned.crt &>/dev/null; then
    docker exec -i "$container_name" openssl x509 -in /opt/outline/persisted-state/shadowbox-selfsigned.crt -noout -sha256 -fingerprint 2>/dev/null > /tmp/cert_fingerprint
    if [ -f "/tmp/cert_fingerprint" ]; then
        cert_fingerprint=$(cat /tmp/cert_fingerprint)
        cert_sha256=$(echo ${cert_fingerprint#*=} | tr --delete : | tr '[:upper:]' '[:lower:]')
        rm /tmp/cert_fingerprint
    fi
fi

# If we still don't have a cert hash, use a placeholder
if [ -z "$cert_sha256" ]; then
    cert_sha256="<CERTIFICATE_NOT_AVAILABLE>"
    warn "Could not determine certificate fingerprint. You may need to generate a new one."
fi

# Display the management JSON
echo -e "\033[1;32m{\"apiUrl\":\"https://${server_ip}:${API_PORT}/${api_prefix}\",\"certSha256\":\"${cert_sha256}\"}\033[0m"
echo ""
echo "======================================================"

# Final status check
info "Fix completed. Check above for any warnings or errors."
info "If the server doesn't work correctly, you may need to run this script again or check Docker logs."
echo "======================================================"