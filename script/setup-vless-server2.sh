#!/bin/bash

# ===================================================================
# VLESS-Reality Server 2 Setup Script (Routing Through Server 1)
# ===================================================================
# This script:
# - Configures Server 2 to route traffic through Server 1 using VLESS+Reality
# - Installs and configures Outline VPN on Server 2
# - Sets up necessary routing and forwarding
# - Creates systemd service for persistent tunnel
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
SERVER1_ADDRESS=""
SERVER1_PORT="443"
SERVER1_UUID=""
SERVER1_SNI="www.microsoft.com"
SERVER1_FINGERPRINT="chrome"
SERVER1_SHORTID=""
SERVER1_PUBKEY=""
OUTLINE_PORT="7777"
V2RAY_DIR="/opt/v2ray"
LOCAL_IP=$(hostname -I | awk '{print $1}')

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

This script configures Server 2 to route traffic through Server 1 using VLESS+Reality protocol
and installs Outline VPN server.

Required Options:
  --server1-address ADDR    Server 1 hostname or IP address
  --server1-uuid UUID       Server 1 account UUID for tunneling
  
Optional Options:
  --server1-port PORT       Server 1 port (default: 443)
  --server1-sni DOMAIN      Server 1 SNI (default: www.microsoft.com)
  --server1-fingerprint FP  Server 1 TLS fingerprint (default: chrome)
  --server1-shortid ID      Server 1 Reality short ID (if required)
  --server1-pubkey KEY      Server 1 Reality public key
  --outline-port PORT       Port for Outline VPN (default: 7777)
  --help                    Display this help message

Example:
  $(basename "$0") --server1-address 123.45.67.89 --server1-uuid abcd-1234-...

EOF
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
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
            --outline-port)
                OUTLINE_PORT="$2"
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

    # If Reality public key is not provided, warn the user
    if [ -z "$SERVER1_PUBKEY" ]; then
        warn "Server 1 Reality public key not provided. This may be required for connection."
    fi

    info "Configuration:"
    info "- Server 1 address: $SERVER1_ADDRESS"
    info "- Server 1 port: $SERVER1_PORT"
    info "- Server 1 SNI: $SERVER1_SNI"
    info "- Server 1 fingerprint: $SERVER1_FINGERPRINT"
    info "- Outline VPN port: $OUTLINE_PORT"
    info "- This server's local IP: $LOCAL_IP"
}

# Update system packages
update_system() {
    info "Updating system packages..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget jq ufw socat iptables-persistent \
        ca-certificates gnupg docker.io docker-compose
}

# Configure IP forwarding
configure_forwarding() {
    info "Configuring IP forwarding..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Make sure IP forwarding is enabled on boot
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Apply sysctl changes
    sysctl -p
    
    info "IP forwarding has been enabled"
}

# Install and configure v2ray client for tunneling
install_v2ray_client() {
    info "Installing v2ray client for tunneling to Server 1..."
    
    # Create necessary directories
    mkdir -p "$V2RAY_DIR"
    mkdir -p "$V2RAY_DIR/logs"
    mkdir -p /var/log/v2ray
    chmod 777 /var/log/v2ray  # More permissive for container access
    
    # Create v2ray client config using the generator script
    info "Creating v2ray configuration..."
    
    if [ -f "./script/generate-v2ray-config.sh" ]; then
        info "Using configuration generator script..."
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
        
        info "Configuration generated successfully."
    else
        error "Configuration generator script not found. Cannot proceed."
    fi
    
    chmod 644 "$V2RAY_DIR/config.json"
    
    # Validate the configuration
    info "Validating final configuration..."
    if command -v jq &>/dev/null; then
        if jq empty "$V2RAY_DIR/config.json" 2>/dev/null; then
            info "Configuration file is valid JSON."
        else
            error "Configuration is not valid JSON. Cannot proceed."
        fi
    else
        warn "jq not installed. Skipping validation."
    fi
    
    # Pull v2ray Docker image
    info "Pulling v2ray Docker image..."
    docker pull v2fly/v2fly-core:latest
    
    # Remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^v2ray-client$"; then
        info "Removing existing v2ray-client container..."
        docker rm -f v2ray-client || warn "Failed to remove existing container, it might be in use"
    fi
    
    # Try to inspect the network first - this is safer than grepping the list
    info "Setting up Docker network..."
    if docker network inspect v2ray-network &>/dev/null; then
        info "Docker network v2ray-network already exists, using existing network."
    else
        # Create the network and suppress error if it already exists
        info "Creating Docker network..."
        docker network create v2ray-network 2>/dev/null || true
        info "Network setup completed."
    fi
    
    # Run v2ray container with default entrypoint (no explicit command)
    info "Starting v2ray client container with default entrypoint..."
    docker run -d \
        --name v2ray-client \
        --restart always \
        --network host \
        --cap-add NET_ADMIN \
        -v "$V2RAY_DIR/config.json:/etc/v2ray/config.json" \
        -v "/var/log/v2ray:/var/log/v2ray" \
        -e "V2RAY_VMESS_AEAD_FORCED=false" \
        v2fly/v2fly-core:latest run -config /etc/v2ray/config.json
        
    # Verify container is running with extended waiting and diagnostics
    info "Verifying container startup (waiting 5 seconds)..."
    sleep 5
    if [ -z "$(docker ps -q --filter name=^v2ray-client$)" ]; then
        warn "Container failed to start or crashed. Detailed diagnostics:"
        echo "--- Container Logs ---"
        docker logs v2ray-client 2>&1 || echo "No logs available"
        echo "--- Container Status ---"
        docker ps -a | grep v2ray-client || echo "Container not found"
        echo "--- Configuration File ---"
        cat "$V2RAY_DIR/config.json" | grep -v "id\|publicKey" # Hide sensitive info
        
        error "Container failed to start. Cannot proceed with setup."
    else
        info "Container started successfully."
    fi
    
    info "v2ray client installed and running"
}

# Create systemd service for v2ray-client
create_v2ray_service() {
    info "Creating systemd service for v2ray tunnel..."
    
    cat > /etc/systemd/system/v2ray-tunnel.service << EOF
[Unit]
Description=v2ray Tunnel to Server 1
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start v2ray-client
ExecStop=/usr/bin/docker stop v2ray-client
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable v2ray-tunnel.service
    
    info "v2ray tunnel service created and enabled"
}

# Configure iptables to route traffic through the tunnel
configure_routing() {
    info "Configuring routing for traffic through the tunnel..."
    
    # Source the tunnel routing configuration file if it exists
    if [ -f "./script/tunnel-routing.conf" ]; then
        source "./script/tunnel-routing.conf"
        info "Loaded routing configuration from tunnel-routing.conf"
    else
        warn "tunnel-routing.conf not found, using default settings"
        # Default value if config file not found
        ROUTE_OUTLINE_THROUGH_TUNNEL=true
    fi
    
    # Get the internet-facing interface
    INTERNET_IFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
    if [ -z "$INTERNET_IFACE" ]; then
        warn "Could not determine internet-facing interface. Using fallback method."
        INTERNET_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
        if [ -z "$INTERNET_IFACE" ]; then
            error "Failed to determine outgoing network interface. Manual configuration needed."
        fi
    fi
    info "Using network interface: $INTERNET_IFACE for traffic forwarding"
    
    # Create iptables rules script
    cat > /usr/local/bin/setup-tunnel-routing.sh << EOF
#!/bin/bash

# Verify IP forwarding is enabled
function verify_ip_forwarding() {
    if [ \$(cat /proc/sys/net/ipv4/ip_forward) -ne 1 ]; then
        echo "IP forwarding is not enabled. Enabling now..."
        echo 1 > /proc/sys/net/ipv4/ip_forward
        sysctl -w net.ipv4.ip_forward=1
    fi
}

# Verify IP forwarding
verify_ip_forwarding

# Clear existing rules for our chains only (not all rules)
iptables -t nat -F V2RAY 2>/dev/null || true
iptables -t mangle -F V2RAY 2>/dev/null || true
iptables -t mangle -F V2RAY_MARK 2>/dev/null || true

# Remove our chains if they exist (to avoid errors on creation)
iptables -t nat -D PREROUTING -p tcp -j V2RAY 2>/dev/null || true
iptables -t nat -X V2RAY 2>/dev/null || true
iptables -t mangle -X V2RAY 2>/dev/null || true
iptables -t mangle -X V2RAY_MARK 2>/dev/null || true

# Create new chain for tunnel
iptables -t nat -N V2RAY
iptables -t mangle -N V2RAY
iptables -t mangle -N V2RAY_MARK

# Don't route Outline VPN management traffic through the tunnel
iptables -t nat -A V2RAY -d ${SERVER1_ADDRESS} -j RETURN
iptables -t nat -A V2RAY -d ${LOCAL_IP} -j RETURN

# Don't route local and private traffic through the tunnel
iptables -t nat -A V2RAY -d 0.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 169.254.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t nat -A V2RAY -d 240.0.0.0/4 -j RETURN

# Route all other traffic through v2ray tunnel
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 11081
iptables -t nat -A PREROUTING -p tcp -j V2RAY

# Route traffic from Outline VPN through the tunnel (if enabled)
if [ "${ROUTE_OUTLINE_THROUGH_TUNNEL}" = "true" ]; then
    echo "Routing Outline VPN traffic (10.0.0.0/24) through tunnel"
    
    # Use proper outgoing interface for masquerading
    iptables -t nat -A POSTROUTING -o ${INTERNET_IFACE} -s 10.0.0.0/24 -j MASQUERADE
    
    # Add explicit rules for routing Outline traffic through the tunnel
    iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp -j V2RAY
    iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p udp -j REDIRECT --to-ports 11081
else
    echo "Direct routing for Outline VPN traffic (not through tunnel)"
    iptables -t nat -A POSTROUTING -o ${INTERNET_IFACE} -s 10.0.0.0/24 -j MASQUERADE
fi
EOF
    
    chmod +x /usr/local/bin/setup-tunnel-routing.sh
    
    # Execute the script now
    /usr/local/bin/setup-tunnel-routing.sh
    
    # Create systemd service to run the script after reboot
    cat > /etc/systemd/system/tunnel-routing.service << EOF
[Unit]
Description=Configure Tunnel Routing Rules
After=network.target v2ray-tunnel.service
Requires=v2ray-tunnel.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-tunnel-routing.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable tunnel-routing.service
    
    info "Routing configuration has been set up"
}

# Install and configure Outline VPN
install_outline() {
    info "Installing Outline VPN server..."
    
    # Create a directory for Outline
    mkdir -p /opt/outline
    
    # Download the Outline server install script
    curl -sSL https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh > /opt/outline/install_server.sh
    chmod +x /opt/outline/install_server.sh
    
    # Install Outline with API port and keys directory parameters
    info "Running Outline installer..."
    /opt/outline/install_server.sh --api-port=41084 --keys-port="${OUTLINE_PORT}"
    
    # Create a configuration file for Outline to use our tunnel
    cat > /opt/outline/outline-tunnel.conf << EOF
# Outline VPN Tunnel Configuration
# Routes all traffic from Outline VPN clients through Server 1

# This server's IP address
LOCAL_IP=${LOCAL_IP}

# Tunnel proxy
HTTP_PROXY=http://127.0.0.1:18080
HTTPS_PROXY=http://127.0.0.1:18080
NO_PROXY=${LOCAL_IP},127.0.0.1,localhost
EOF
    
    # Modify the Outline Docker Compose file to use our environment file
    if [ -f "/opt/outline/docker-compose.yml" ]; then
        info "Updating Outline Docker Compose configuration..."
        # Make a backup
        cp /opt/outline/docker-compose.yml /opt/outline/docker-compose.yml.bak
        
        # Add our environment file to the Outline service
        sed -i '/watchtower:/i \ \ env_file:\n\ \ \ \ - /opt/outline/outline-tunnel.conf' /opt/outline/docker-compose.yml
        
        # Restart Outline to apply the changes
        cd /opt/outline && docker-compose down && docker-compose up -d
    else
        warn "Outline Docker Compose file not found. Tunnel may not be properly configured."
    fi
    
    info "Outline VPN server has been installed and configured to use the tunnel"
    info "Make sure to set up access keys using the Outline Manager"
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall..."
    
    if command -v ufw &> /dev/null; then
        # Configure UFW if installed
        info "Configuring UFW..."
        
        # Reset UFW to default
        ufw --force reset
        
        # Set default policies
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH (adjust if you use a different port)
        ufw allow 22/tcp
        
        # Allow Outline management API
        ufw allow 41084/tcp
        
        # Allow Outline VPN
        ufw allow ${OUTLINE_PORT}/tcp
        ufw allow ${OUTLINE_PORT}/udp
        
        # Enable UFW
        ufw --force enable
        
        info "UFW configured and enabled"
    else
        # Configure iptables directly if UFW not installed
        info "UFW not found. Configuring iptables directly..."
        
        # Allow SSH
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        
        # Allow Outline API
        iptables -A INPUT -p tcp --dport 41084 -j ACCEPT
        
        # Allow Outline VPN
        iptables -A INPUT -p tcp --dport ${OUTLINE_PORT} -j ACCEPT
        iptables -A INPUT -p udp --dport ${OUTLINE_PORT} -j ACCEPT
        
        # Allow established connections
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        
        # Default policies
        iptables -P INPUT DROP
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        
        # Save iptables rules
        iptables-save > /etc/iptables/rules.v4
        
        info "iptables configured and saved"
    fi
}

# Test the tunnel connection with enhanced diagnostics
test_tunnel() {
    info "Testing tunnel connection to Server 1..."
    
    # Verify IP forwarding is enabled
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
        warn "IP forwarding is not enabled. This will cause routing issues."
        info "Enabling IP forwarding now..."
        echo 1 > /proc/sys/net/ipv4/ip_forward
        sysctl -w net.ipv4.ip_forward=1
    else
        info "IP forwarding is properly enabled."
    fi
    
    # Wait longer for the tunnel to establish
    info "Waiting for tunnel to initialize (10 seconds)..."
    sleep 10
    
    # Check if v2ray-client container is running
    if [ -z "$(docker ps -q --filter name=^v2ray-client$)" ]; then
        error "v2ray-client container is not running. Please check docker logs:"
        docker logs v2ray-client
        return 1
    fi
    
    # Validate v2ray configuration
    info "Validating v2ray proxy configuration..."
    if [ -f "$V2RAY_DIR/config.json" ]; then
        if ! docker exec v2ray-client v2ray test -config /etc/v2ray/config.json &>/dev/null; then
            warn "v2ray configuration test failed. This may indicate configuration issues."
        else
            info "v2ray configuration is valid."
        fi
    else
        warn "v2ray configuration file not found for validation."
    fi
    
    # Check if proxy port is listening
    if ! ss -tulpn | grep -q ":18080"; then
        warn "HTTP proxy port 18080 is not listening. Checking container logs:"
        docker logs v2ray-client
        warn "You may need to restart the container or check configuration."
    else
        info "HTTP proxy port 18080 is listening correctly."
    fi
    
    # Check if transparent proxy port is listening
    if ! ss -tulpn | grep -q ":11081"; then
        warn "Transparent proxy port 11081 is not listening. This will break routing."
        docker logs v2ray-client | grep -i "error\|fail\|warn" | tail -5
    else
        info "Transparent proxy port 11081 is listening correctly."
    fi
    
    # Test connection to Server 1
    info "Testing connectivity to Server 1 ($SERVER1_ADDRESS)..."
    if ! ping -c 3 -W 5 "$SERVER1_ADDRESS" >/dev/null 2>&1; then
        warn "Cannot ping Server 1. This may be normal if ICMP is blocked."
    else
        info "Server 1 is reachable via ping."
    fi
    
    # Test the connection using curl through the proxy
    info "Testing HTTP proxy tunnel to Server 1..."
    local proxy_output=$(curl -v --connect-timeout 15 -x http://127.0.0.1:18080 https://ifconfig.me 2>&1)
    local proxy_ip=$(echo "$proxy_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$proxy_ip" ]; then
        info "Tunnel is working correctly. Traffic is being routed through Server 1."
        info "Your traffic appears as coming from: $proxy_ip"
        
        # Verify iptables routing for Outline
        if [ "$(iptables -t nat -L PREROUTING | grep -c "V2RAY")" -gt 0 ]; then
            info "iptables PREROUTING rules for the tunnel are correctly set up."
        else
            warn "iptables PREROUTING rules for the tunnel are missing."
        fi
        
        if [ "$(iptables -t nat -L POSTROUTING | grep -c "10.0.0.0/24")" -gt 0 ]; then
            info "iptables POSTROUTING rules for Outline VPN are correctly set up."
        else
            warn "iptables POSTROUTING rules for Outline VPN are missing."
        fi
    else
        warn "Tunnel test failed. Here's the diagnostic information:"
        echo "$proxy_output" | grep -i "error\|failed\|couldn't"
        
        # Check v2ray logs for errors
        warn "Checking v2ray logs for errors:"
        docker logs v2ray-client | grep -i "error\|fail\|warn" | tail -10
        
        warn "Tunnel connection failed. Possible issues:"
        warn "1. Server 1 might not be properly configured or accessible"
        warn "2. Reality protocol settings might be incorrect (missing public key?)"
        warn "3. Firewall might be blocking the connection"
        warn "4. V2Ray configuration might have syntax errors"
        warn "Run './script/test-tunnel-connection.sh --server-type server2 --server1-address $SERVER1_ADDRESS' for detailed diagnostics"
    fi
}

# Main function
main() {
    check_root
    parse_args "$@"
    update_system
    install_dependencies
    configure_forwarding
    install_v2ray_client
    create_v2ray_service
    configure_routing
    configure_firewall
    install_outline
    test_tunnel
    
    info "====================================================================="
    info "Server 2 setup completed successfully!"
    info "Outline VPN is installed and configured to route traffic through Server 1."
    info "Outline Management API: https://${LOCAL_IP}:41084/access-keys/"
    info "Outline VPN port: ${OUTLINE_PORT}"
    info "====================================================================="
    info "IMPORTANT: Use the Outline Manager to configure access keys for your VPN users."
    info "====================================================================="
}

main "$@"