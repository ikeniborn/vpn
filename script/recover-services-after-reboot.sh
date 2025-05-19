#!/bin/bash

# ===================================================================
# Server Recovery Script After Reboot
# ===================================================================
# This script:
# - Recovers all services after a server reboot
# - Restores SSH, HTTPS, and Outline VPN connectivity
# - Works on both Server 1 and Server 2
# - Identifies which server it's running on and takes appropriate actions
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables
V2RAY_DIR="/opt/v2ray"
DOCKER_CONTAINER_SERVER1="v2ray"
DOCKER_CONTAINER_SERVER2="v2ray-client"
SERVER1_CONFIG_PRESENT=false
SERVER2_CONFIG_PRESENT=false
SERVER_TYPE=""

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

# Detect which server we're running on
detect_server_type() {
    info "Detecting server type..."
    
    # Check for Docker container names
    if docker ps -a --format '{{.Names}}' | grep -q "^$DOCKER_CONTAINER_SERVER1$"; then
        info "Found $DOCKER_CONTAINER_SERVER1 container - likely Server 1"
        SERVER_TYPE="server1"
    elif docker ps -a --format '{{.Names}}' | grep -q "^$DOCKER_CONTAINER_SERVER2$"; then
        info "Found $DOCKER_CONTAINER_SERVER2 container - likely Server 2"
        SERVER_TYPE="server2"
    fi
    
    # Check configuration files
    if [ -f "$V2RAY_DIR/config.json" ]; then
        # Using jq for proper JSON parsing
        if command -v jq &>/dev/null; then
            # Look for Reality settings as server
            if jq -e '.inbounds[0].streamSettings.realitySettings' "$V2RAY_DIR/config.json" &>/dev/null; then
                info "Found Reality server configuration - confirming Server 1"
                SERVER_TYPE="server1"
                SERVER1_CONFIG_PRESENT=true
            # Look for Reality settings as client
            elif jq -e '.outbounds[].streamSettings.realitySettings' "$V2RAY_DIR/config.json" &>/dev/null; then
                info "Found Reality client configuration - confirming Server 2"
                SERVER_TYPE="server2"
                SERVER2_CONFIG_PRESENT=true
            fi
        else
            # Fallback detection without jq
            if grep -q "realitySettings" "$V2RAY_DIR/config.json" && grep -q "\"inbounds\"" "$V2RAY_DIR/config.json"; then
                info "Found Reality settings in inbounds - likely Server 1"
                SERVER_TYPE="server1"
                SERVER1_CONFIG_PRESENT=true
            elif grep -q "realitySettings" "$V2RAY_DIR/config.json" && grep -q "\"outbounds\"" "$V2RAY_DIR/config.json"; then
                info "Found Reality settings in outbounds - likely Server 2"
                SERVER_TYPE="server2"
                SERVER2_CONFIG_PRESENT=true
            fi
        fi
    fi
    
    if [ -z "$SERVER_TYPE" ]; then
        warn "Could not definitively determine server type. Will try to recover both configurations."
        SERVER_TYPE="unknown"
    else
        info "Detected server type: $SERVER_TYPE"
    fi
}

# Ensure Docker is running
ensure_docker_running() {
    info "Ensuring Docker is running..."
    
    if ! systemctl is-active --quiet docker; then
        info "Docker is not running. Starting Docker..."
        systemctl start docker
        
        # Wait for Docker to fully start
        local max_attempts=10
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if systemctl is-active --quiet docker; then
                info "Docker started successfully"
                break
            fi
            info "Waiting for Docker to start... (attempt $attempt/$max_attempts)"
            sleep 3
            attempt=$((attempt + 1))
        done
        
        if ! systemctl is-active --quiet docker; then
            error "Failed to start Docker after $max_attempts attempts"
        fi
    else
        info "Docker is already running"
    fi
}

# Fix container port binding for Server 2
fix_server2_port_binding() {
    info "Fixing port binding for Server 2..."
    
    if [ -f "./script/fix-port-binding.sh" ]; then
        chmod +x ./script/fix-port-binding.sh
        ./script/fix-port-binding.sh
    elif [ -f "/usr/local/bin/fix-port-binding.sh" ]; then
        /usr/local/bin/fix-port-binding.sh
    else
        warn "fix-port-binding.sh not found. Creating container manually..."
        
        # Make sure v2ray image is available
        docker pull v2fly/v2fly-core:latest
        
        # Stop and remove existing container if it exists
        docker stop "$DOCKER_CONTAINER_SERVER2" 2>/dev/null || true
        docker rm "$DOCKER_CONTAINER_SERVER2" 2>/dev/null || true
        
        # Create a new container with host networking
        docker run -d \
            --name "$DOCKER_CONTAINER_SERVER2" \
            --restart always \
            --network host \
            --cap-add NET_ADMIN --cap-add NET_BROADCAST --cap-add NET_RAW \
            -v "$V2RAY_DIR/config.json:/etc/v2ray/config.json" \
            -v "/var/log/v2ray:/var/log/v2ray" \
            v2fly/v2fly-core:latest run -config /etc/v2ray/config.json
    fi
}

# Restart Server 1's v2ray container
restart_server1_container() {
    info "Restarting Server 1 v2ray container..."
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^$DOCKER_CONTAINER_SERVER1$"; then
        # Try to restart the container
        if ! docker restart "$DOCKER_CONTAINER_SERVER1" 2>/dev/null; then
            warn "Failed to restart container. Removing and creating a new one..."
            
            # Remove container
            docker rm -f "$DOCKER_CONTAINER_SERVER1" 2>/dev/null || true
            
            # Create a new container
            info "Creating new v2ray container..."
            docker run -d \
                --name "$DOCKER_CONTAINER_SERVER1" \
                --restart always \
                --network host \
                -v "$V2RAY_DIR/config.json:/etc/v2ray/config.json" \
                -v "/var/log/v2ray:/var/log/v2ray" \
                v2fly/v2fly-core:latest
        fi
    else
        warn "Container $DOCKER_CONTAINER_SERVER1 does not exist. Creating a new one..."
        
        # Pull the image if not already present
        docker pull v2fly/v2fly-core:latest
        
        # Create directory structure if it doesn't exist
        mkdir -p "$V2RAY_DIR"
        mkdir -p "/var/log/v2ray"
        
        # Create a new container
        docker run -d \
            --name "$DOCKER_CONTAINER_SERVER1" \
            --restart always \
            --network host \
            -v "$V2RAY_DIR/config.json:/etc/v2ray/config.json" \
            -v "/var/log/v2ray:/var/log/v2ray" \
            v2fly/v2fly-core:latest
    fi
    
    # Check if container is running
    sleep 3
    if [ -z "$(docker ps -q -f "name=^${DOCKER_CONTAINER_SERVER1}$")" ]; then
        warn "Container failed to start. Check logs for details:"
        docker logs "$DOCKER_CONTAINER_SERVER1" 2>/dev/null || true
    else
        info "Container started successfully"
    fi
}

# Fix UUID authentication between Server 1 and Server 2
fix_server_uuid() {
    info "Fixing UUID authentication between servers..."
    
    if [ -f "./script/fix-server-uuid.sh" ]; then
        chmod +x ./script/fix-server-uuid.sh
        ./script/fix-server-uuid.sh
    elif [ -f "/usr/local/bin/fix-server-uuid.sh" ]; then
        /usr/local/bin/fix-server-uuid.sh
    else
        warn "fix-server-uuid.sh not found, skipping UUID fix"
    fi
}

# Setup iptables routing rules
setup_routing_rules() {
    info "Setting up iptables routing rules..."
    
    if [ -f "./script/setup-tunnel-routing.sh" ]; then
        chmod +x ./script/setup-tunnel-routing.sh
        ./script/setup-tunnel-routing.sh
    elif [ -f "/usr/local/bin/setup-tunnel-routing.sh" ]; then
        /usr/local/bin/setup-tunnel-routing.sh
    else
        warn "setup-tunnel-routing.sh not found. Setting up basic iptables rules..."
        
        # Create V2RAY chain if it doesn't exist
        if ! iptables -t nat -L V2RAY &>/dev/null; then
            iptables -t nat -N V2RAY
        else
            iptables -t nat -F V2RAY
        fi
        
        # Add rules to V2RAY chain for transparent proxy
        iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
        iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
        iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
        iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
        iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-port 11081
        
        # Add rule for Outline VPN subnet
        iptables -t nat -A PREROUTING -p tcp -s 10.0.0.0/24 -j V2RAY
        
        # Check if V2RAY chain is referenced in PREROUTING
        if ! iptables -t nat -L PREROUTING | grep -q V2RAY; then
            iptables -t nat -A PREROUTING -p tcp -j V2RAY
        fi
        
        # Add MASQUERADE rule to POSTROUTING
        if ! iptables -t nat -L POSTROUTING | grep -q MASQUERADE; then
            local outgoing_iface=$(ip -4 route show default | awk '{print $5}' | head -n1)
            iptables -t nat -A POSTROUTING -j MASQUERADE -o "$outgoing_iface"
        fi
        
        # Save iptables rules
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
        
        # Install save/restore mechanism for persistence
        if [ -d "/etc/network/if-pre-up.d" ]; then
            echo '#!/bin/sh' > /etc/network/if-pre-up.d/iptablesload
            echo 'iptables-restore < /etc/iptables/rules.v4' >> /etc/network/if-pre-up.d/iptablesload
            chmod +x /etc/network/if-pre-up.d/iptablesload
        fi
    fi
}

# Test connectivity
test_connectivity() {
    info "Testing connectivity..."
    
    # Test outline connectivity
    if [ "$SERVER_TYPE" = "server2" ]; then
        info "Testing tunnel connectivity from Server 2 to Server 1..."
        
        if [ -f "./script/test-tunnel-connection.sh" ]; then
            chmod +x ./script/test-tunnel-connection.sh
            ./script/test-tunnel-connection.sh
        else
            # Direct test using curl through the proxy
            local curl_output=$(curl -s -m 10 -x "http://127.0.0.1:18080" https://ifconfig.me 2>&1 || echo "Connection failed")
            
            if [[ "$curl_output" != *"Connection failed"* && "$curl_output" != *"timed out"* ]]; then
                info "✅ Successfully connected through proxy!"
                info "  Your IP appears as: $curl_output"
            else
                warn "⚠️ Connection through proxy failed"
                info "  Error output: $curl_output"
            fi
        fi
    fi
}

# Restart Outline if it's server2
restart_outline() {
    if [ "$SERVER_TYPE" = "server2" ]; then
        info "Attempting to restart Outline VPN service..."
        
        # Check if Outline is installed (using common paths)
        if [ -d "/opt/outline/persisted-state" ] || [ -f "/opt/outline/docker-compose.yml" ]; then
            info "Found Outline VPN installation. Restarting services..."
            
            # Try to restart using different methods
            if [ -f "/opt/outline/docker-compose.yml" ]; then
                cd /opt/outline
                docker-compose down
                docker-compose up -d
            else
                # Try to restart individual containers
                docker restart watchtower shadowbox 2>/dev/null || true
            fi
            
            info "Outline VPN restarted"
        else
            warn "Could not find Outline VPN installation. Manual intervention may be needed."
        fi
    fi
}

# Show summary and next steps
show_summary() {
    echo ""
    echo "====================================================================="
    info "Recovery process completed!"
    echo "====================================================================="
    
    if [ "$SERVER_TYPE" = "server1" ]; then
        info "Server 1 (VLESS+Reality entry point) services should now be restored."
        info ""
        info "If issues persist, check:"
        info "1. Docker logs: docker logs v2ray"
        info "2. iptables rules: iptables -t nat -L"
        info "3. Port listening: ss -tulpn | grep -E '443'"
        info ""
        info "You may also need to run this script on Server 2 to restore the full tunnel."
    elif [ "$SERVER_TYPE" = "server2" ]; then
        info "Server 2 (Tunnel client + Outline VPN) services should now be restored."
        info ""
        info "If issues persist, check:"
        info "1. Docker logs: docker logs v2ray-client"
        info "2. iptables rules: iptables -t nat -L"
        info "3. Port listening: ss -tulpn | grep -E '11080|18080|11081'"
        info "4. Outline VPN status: cd /opt/outline && docker-compose ps"
        info ""
        info "If Server 2 still cannot connect to Server 1, you may need to run this script on Server 1 as well."
    else
        info "Services have been restored for unknown server type."
        info ""
        info "If issues persist, please run more specific troubleshooting scripts:"
        info "1. fix-server-uuid.sh - If Server 2 cannot authenticate to Server 1"
        info "2. fix-port-binding.sh - If port binding issues occur on Server 2"
        info "3. setup-tunnel-routing.sh - If traffic routing is not working"
    fi
    
    echo "====================================================================="
}

# Main function
main() {
    check_root
    detect_server_type
    ensure_docker_running
    
    if [ "$SERVER_TYPE" = "server1" ] || [ "$SERVER_TYPE" = "unknown" ]; then
        restart_server1_container
        fix_server_uuid
        setup_routing_rules
    fi
    
    if [ "$SERVER_TYPE" = "server2" ] || [ "$SERVER_TYPE" = "unknown" ]; then
        fix_server2_port_binding
        setup_routing_rules
        restart_outline
    fi
    
    test_connectivity
    show_summary
}

main "$@"