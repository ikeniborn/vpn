#!/bin/bash

# ===================================================================
# Fix or Create V2Ray Container with Proper Port Binding
# ===================================================================
# This script:
# - Creates v2ray container if it doesn't exist
# - Fixes port binding issues with v2ray Docker container
# - Ensures the container has proper network configuration
# - Creates or restarts the container with host networking mode
# - Generates configuration if needed
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables
DOCKER_CONTAINER="v2ray-client"
V2RAY_DIR="/opt/v2ray"
CONFIG_FILE="/etc/v2ray/config.json"
CONTAINER_EXISTS=false
SERVER1_ADDRESS=""
SERVER1_UUID=""

# Check for parameters
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --server1-address)
            SERVER1_ADDRESS="$2"
            shift
            ;;
        --server1-uuid)
            SERVER1_UUID="$2"
            shift
            ;;
        *)
            warn "Unknown parameter: $1"
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

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Check container status
check_container() {
    info "Checking container status..."
    
    # Use more reliable method to check if container exists
    if [ -z "$(docker ps -a -q -f "name=^${DOCKER_CONTAINER}$")" ]; then
        info "Container $DOCKER_CONTAINER does not exist - will create it"
        CONTAINER_EXISTS=false
    else
        info "Container exists, checking configuration..."
        CONTAINER_EXISTS=true
        
        # Check container status
        if [ -z "$(docker ps -q -f "name=^${DOCKER_CONTAINER}$")" ]; then
            info "Container exists but is not running"
        else
            info "Container is running"
        fi
        
        # Force remove existing container regardless of errors from previous attempts
        info "Removing existing container to avoid conflicts..."
        docker rm -f "$DOCKER_CONTAINER" || true
        sleep 2
    fi
}

# Backup original configuration
backup_config() {
    info "Backing up current configuration..."
    
    if [ -f "$V2RAY_DIR/config.json" ]; then
        cp "$V2RAY_DIR/config.json" "$V2RAY_DIR/config.json.bak.$(date +%s)"
        info "Configuration backed up"
    else
        warn "No configuration file found at $V2RAY_DIR/config.json"
    fi
}

# Create config directory if needed
create_config_dir() {
    info "Creating config directory if needed..."
    mkdir -p "$V2RAY_DIR"
}

# Generate configuration if needed
generate_config() {
    if [ ! -f "$V2RAY_DIR/config.json" ]; then
        info "No configuration file found, need to generate one"
        
        if [ -z "$SERVER1_ADDRESS" ] || [ -z "$SERVER1_UUID" ]; then
            error "Missing required parameters to generate config. Please provide --server1-address and --server1-uuid"
        fi
        
        if [ -f "./script/generate-v2ray-config.sh" ]; then
            info "Using configuration generator script..."
            chmod +x ./script/generate-v2ray-config.sh
            
            # Generate the configuration with proper validation
            if ! ./script/generate-v2ray-config.sh \
                "$SERVER1_ADDRESS" \
                "443" \
                "$SERVER1_UUID" \
                "www.microsoft.com" \
                "chrome" \
                "" \
                "" \
                "$V2RAY_DIR/config.json"; then
                
                error "Failed to generate valid configuration. Check script output."
            fi
            
            info "Configuration generated successfully."
        else
            error "Configuration generator script not found and no existing config. Cannot proceed."
        fi
    fi
}

# Fix configuration file
fix_config() {
    info "Checking configuration file..."
    
    if [ ! -f "$V2RAY_DIR/config.json" ]; then
        error "Configuration file not found at $V2RAY_DIR/config.json after generation attempt"
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        info "Installing jq for JSON parsing..."
        apt-get update && apt-get install -y jq
    fi
    
    # Check if config has inbounds with 127.0.0.1 as listen address
    local has_localhost=$(jq '.inbounds | map(select(.listen == "127.0.0.1")) | length' "$V2RAY_DIR/config.json")
    
    if [ "$has_localhost" -gt 0 ]; then
        info "Fixing localhost binding in configuration..."
        # Replace 127.0.0.1 with 0.0.0.0 in all inbounds
        jq '.inbounds = (.inbounds | map(if .listen == "127.0.0.1" then .listen = "0.0.0.0" else . end))' \
            "$V2RAY_DIR/config.json" > "$V2RAY_DIR/config.json.fixed"
        
        # Check if the new config is valid
        if jq empty "$V2RAY_DIR/config.json.fixed" 2>/dev/null; then
            mv "$V2RAY_DIR/config.json.fixed" "$V2RAY_DIR/config.json"
            chmod 644 "$V2RAY_DIR/config.json"
            info "Configuration fixed to bind to all interfaces"
        else
            error "Failed to create valid configuration. Check the JSON manually."
        fi
    else
        info "Configuration already set to listen on all interfaces"
    fi
}

# Create or recreate the container with proper networking
recreate_container() {
    info "Creating/recreating v2ray container with proper networking..."
    
    # First make sure v2ray image is available
    info "Pulling v2ray Docker image if not present..."
    docker pull v2fly/v2fly-core:latest
    
    # Make sure the log directory exists
    mkdir -p /var/log/v2ray
    chmod 777 /var/log/v2ray
    
    # Stop and remove existing container if it exists
    if [ "$CONTAINER_EXISTS" = true ]; then
        info "Removing existing container..."
        docker stop "$DOCKER_CONTAINER" || true
        docker rm "$DOCKER_CONTAINER" || true
    fi
    
    # Create a new container with host networking
    info "Creating new container with host networking..."
    docker run -d \
        --name "$DOCKER_CONTAINER" \
        --restart always \
        --network host \
        --cap-add NET_ADMIN \
        -v "$V2RAY_DIR/config.json:/etc/v2ray/config.json" \
        -v "/var/log/v2ray:/var/log/v2ray" \
        v2fly/v2fly-core:latest /usr/bin/v2ray -config "$CONFIG_FILE"
    
    # Verify container is running with more reliable method
    sleep 5
    if [ -n "$(docker ps -q -f "name=^${DOCKER_CONTAINER}$")" ]; then
        info "Container started successfully"
        
        # Show logs for debugging
        info "Recent container logs:"
        docker logs "$DOCKER_CONTAINER" --tail 5
    else
        warn "Container might have failed to start. Checking logs:"
        docker logs "$DOCKER_CONTAINER" --tail 10 || true
        
        # Check again after logs - container might be running even if initial check failed
        if [ -n "$(docker ps -q -f "name=^${DOCKER_CONTAINER}$")" ]; then
            info "Container is actually running despite previous check failure"
        else
            error "Container definitely not running. Check logs and try again."
        fi
    fi
}

# Verify ports are listening
verify_ports() {
    info "Verifying ports are listening..."
    
    # Allow a moment for ports to start listening
    sleep 2
    
    # Check HTTP proxy port
    if ss -tulpn | grep -q ":18080 "; then
        info "✅ HTTP proxy port 18080 is now listening"
    else
        warn "⚠️ HTTP proxy port 18080 is still not listening"
        info "Checking container logs for clues..."
        docker logs "$DOCKER_CONTAINER" | grep -i "18080\|http\|error\|fail" | tail -10
        
        # Try binding explicitly to 0.0.0.0 in the container
        info "Trying to bind ports explicitly inside the container..."
        docker exec "$DOCKER_CONTAINER" sh -c 'echo "127.0.0.1 localhost" > /etc/hosts'
        docker restart "$DOCKER_CONTAINER"
        sleep 3
    fi
    
    # Check SOCKS proxy port
    if ss -tulpn | grep -q ":11080 "; then
        info "✅ SOCKS proxy port 11080 is now listening"
    else
        warn "⚠️ SOCKS proxy port 11080 is still not listening"
    fi
    
    # Check transparent proxy port - wait longer for this critical port
    if ss -tulpn | grep -q ":11081 "; then
        info "✅ Transparent proxy port 11081 is now listening"
    else
        warn "⚠️ Transparent proxy port 11081 is not listening immediately"
        info "This port is critical for transparent routing"
        info "Waiting longer for port to become available (10 seconds)..."
        
        # Wait longer for the port to appear
        for i in {1..10}; do
            sleep 1
            echo -n "."
            if ss -tulpn | grep -q ":11081 "; then
                echo ""
                info "✅ Transparent proxy port 11081 is now listening after waiting"
                break
            fi
            
            # Last iteration - still not listening
            if [ "$i" -eq 10 ] && ! ss -tulpn | grep -q ":11081 "; then
                echo ""
                warn "⚠️ Transparent proxy port 11081 is still not listening after extended wait"
                info "Checking logs for clues:"
                docker logs "$DOCKER_CONTAINER" | grep -i "11081\|dokodemo\|error\|fail" | tail -10
                info "Container will continue running - test connectivity anyway"
            fi
        done
    fi
}

# Reapply routing rules
reapply_routing() {
    info "Reapplying iptables routing rules..."
    
    if [ -f "/usr/local/bin/setup-tunnel-routing.sh" ]; then
        /usr/local/bin/setup-tunnel-routing.sh
        info "Routing rules reapplied"
    else
        warn "setup-tunnel-routing.sh not found. Routing rules not reapplied."
    fi
}

# Run a full connectivity test
test_connectivity() {
    info "Testing connectivity..."
    
    # Try simple curl through the proxy
    local curl_output=$(curl -s -m 15 -x "http://127.0.0.1:18080" https://ifconfig.me 2>&1 || echo "Connection failed")
    
    if [[ "$curl_output" != *"Connection failed"* && "$curl_output" != *"timed out"* ]]; then
        info "✅ Successfully connected through proxy!"
        info "  Your IP appears as: $curl_output"
    else
        warn "⚠️ Connection through proxy failed"
        info "  Error output: $curl_output"
        
        # Additional diagnostics
        info "Checking iptables rules..."
        iptables -t nat -L
    fi
    
    info "Full testing can be done with: ./script/test-tunnel-connection.sh"
}

# Main function
main() {
    check_root
    create_config_dir
    check_container
    generate_config
    backup_config
    fix_config
    recreate_container
    verify_ports
    reapply_routing
    test_connectivity
    
    info "====================================================================="
    info "v2ray port binding fix completed!"
    info "If issues persist, check logs with: docker logs $DOCKER_CONTAINER"
    info "====================================================================="
}

main "$@"