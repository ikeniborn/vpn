#!/bin/bash

# ===================================================================
# Restart V2Ray with New Configuration
# ===================================================================
# This script:
# - Regenerates the v2ray configuration
# - Restarts the v2ray container
# - Reapplies the routing rules
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
V2RAY_DIR="/opt/v2ray"
DOCKER_CONTAINER="v2ray-client"
SERVER1_ADDRESS=""
SERVER1_PORT="443" 
SERVER1_UUID=""
SERVER1_SNI="www.microsoft.com"
SERVER1_FINGERPRINT="chrome"
SERVER1_PUBKEY=""
SERVER1_SHORTID=""

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

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script regenerates the v2ray configuration and restarts the container.

Required Options:
  --server1-address ADDR    Server 1 hostname or IP address
  --server1-uuid UUID       Server 1 account UUID for tunneling
  
Optional Options:
  --server1-port PORT       Server 1 port (default: 443)
  --server1-sni DOMAIN      Server 1 SNI (default: www.microsoft.com)
  --server1-fingerprint FP  Server 1 TLS fingerprint (default: chrome)
  --server1-shortid ID      Server 1 Reality short ID (if required)
  --server1-pubkey KEY      Server 1 Reality public key
  --container NAME          Docker container name (default: v2ray-client)
  --config-dir DIR          v2ray config directory (default: /opt/v2ray)
  --help                    Display this help message

Example:
  $(basename "$0") --server1-address 123.45.67.89 --server1-uuid abcd-1234-...

EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --server1-address)
                SERVER1_ADDRESS="$2"
                shift
                ;;
            --server1-port)
                SERVER1_PORT="$2"
                shift
                ;;
            --server1-uuid)
                SERVER1_UUID="$2"
                shift
                ;;
            --server1-sni)
                SERVER1_SNI="$2"
                shift
                ;;
            --server1-fingerprint)
                SERVER1_FINGERPRINT="$2"
                shift
                ;;
            --server1-shortid)
                SERVER1_SHORTID="$2"
                shift
                ;;
            --server1-pubkey)
                SERVER1_PUBKEY="$2"
                shift
                ;;
            --container)
                DOCKER_CONTAINER="$2"
                shift
                ;;
            --config-dir)
                V2RAY_DIR="$2"
                shift
                ;;
            --help)
                display_usage
                exit 0
                ;;
            *)
                warn "Unknown parameter: $1"
                ;;
        esac
        shift
    done

    # Check required parameters
    if [ -z "$SERVER1_ADDRESS" ]; then
        error "Server 1 address is required. Use --server1-address option."
    fi

    if [ -z "$SERVER1_UUID" ]; then
        error "Server 1 UUID is required. Use --server1-uuid option."
    fi

    info "Configuration:"
    info "- Server 1 address: $SERVER1_ADDRESS"
    info "- Server 1 port: $SERVER1_PORT"
    info "- Server 1 SNI: $SERVER1_SNI"
    info "- Server 1 fingerprint: $SERVER1_FINGERPRINT"
    info "- v2ray configuration directory: $V2RAY_DIR"
    info "- Docker container: $DOCKER_CONTAINER"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Regenerate v2ray configuration
regenerate_config() {
    info "Regenerating v2ray configuration..."
    
    if [ ! -f "./script/generate-v2ray-config.sh" ]; then
        error "Configuration generator script not found. Cannot proceed."
    fi
    
    chmod +x ./script/generate-v2ray-config.sh
    
    # Generate the configuration with proper validation
    if ! ./script/generate-v2ray-config.sh \
        "$SERVER1_ADDRESS" \
        "$SERVER1_PORT" \
        "$SERVER1_UUID" \
        "$SERVER1_SNI" \
        "$SERVER1_FINGERPRINT" \
        "$SERVER1_PUBKEY" \
        "$SERVER1_SHORTID" \
        "$V2RAY_DIR/config.json"; then
        
        error "Failed to generate valid configuration. Check script output."
    fi
    
    info "Configuration regenerated successfully."
    chmod 644 "$V2RAY_DIR/config.json"
}

# Restart v2ray container
restart_container() {
    info "Restarting v2ray container..."
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^$DOCKER_CONTAINER$"; then
        error "Container $DOCKER_CONTAINER does not exist. Cannot restart."
    fi
    
    # Stop the container if it's running
    if docker ps --format '{{.Names}}' | grep -q "^$DOCKER_CONTAINER$"; then
        info "Stopping container..."
        docker stop "$DOCKER_CONTAINER"
    fi
    
    # Start the container
    info "Starting container..."
    docker start "$DOCKER_CONTAINER"
    
    # Verify container is running
    sleep 3
    if [ -z "$(docker ps -q --filter name=^$DOCKER_CONTAINER$)" ]; then
        error "Container failed to start. Check logs: docker logs $DOCKER_CONTAINER"
    fi
    
    info "Container restarted successfully."
}

# Reapply routing rules
reapply_routing() {
    info "Reapplying routing rules..."
    
    if [ -f "/usr/local/bin/setup-tunnel-routing.sh" ]; then
        /usr/local/bin/setup-tunnel-routing.sh
        info "Routing rules reapplied."
    else
        warn "setup-tunnel-routing.sh not found. Routing rules not reapplied."
    fi
}

# Main function
main() {
    check_root
    parse_args "$@"
    regenerate_config
    restart_container
    reapply_routing
    
    info "====================================================================="
    info "v2ray has been restarted with the new configuration."
    info "Run './script/test-tunnel-connection.sh --server-type server2 --server1-address $SERVER1_ADDRESS' to verify the connection."
    info "====================================================================="
}

main "$@"