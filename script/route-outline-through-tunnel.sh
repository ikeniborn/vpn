#!/bin/bash

# ===================================================================
# Route Existing Outline VPN Through Tunnel
# ===================================================================
# This script:
# - Updates an existing Outline VPN installation to route through
#   the VLESS+Reality tunnel to Server 1
# - Configures all necessary routing rules
# - Should be run after setting up the tunnel on Server 2
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
OUTLINE_DIR="/opt/outline"
V2RAY_HTTP_PROXY="127.0.0.1:8080"
OUTLINE_PORT="7777"
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

This script updates an existing Outline VPN installation to route through the VLESS+Reality
tunnel to Server 1.

Options:
  --outline-dir DIR      Directory where Outline is installed (default: /opt/outline)
  --proxy HOST:PORT      HTTP proxy address for the tunnel (default: 127.0.0.1:8080)
  --outline-port PORT    Port for Outline VPN (default: 7777)
  --help                 Display this help message

Example:
  $(basename "$0") --outline-dir /opt/outline --proxy 127.0.0.1:8080

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
            --outline-dir)
                OUTLINE_DIR="$2"
                shift
                ;;
            --proxy)
                V2RAY_HTTP_PROXY="$2"
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

    info "Configuration:"
    info "- Outline directory: $OUTLINE_DIR"
    info "- HTTP proxy: $V2RAY_HTTP_PROXY"
    info "- Outline port: $OUTLINE_PORT"
    info "- Local IP: $LOCAL_IP"
}

# Check if Outline is installed
check_outline() {
    info "Checking for existing Outline installation..."
    
    if [ ! -d "$OUTLINE_DIR" ]; then
        error "Outline directory not found at $OUTLINE_DIR. Please specify the correct directory with --outline-dir."
    fi
    
    if [ ! -f "$OUTLINE_DIR/docker-compose.yml" ]; then
        error "docker-compose.yml not found in $OUTLINE_DIR. This doesn't appear to be a valid Outline installation."
    fi
    
    # Check if Outline containers are running
    if ! docker ps | grep -q "outline-server"; then
        warn "Outline server container is not running. Will attempt to configure anyway."
    else
        info "Found running Outline server."
    fi
}

# Check if the tunnel is running
check_tunnel() {
    info "Checking if the tunnel is running..."
    
    # Check if v2ray-client container is running
    if ! docker ps | grep -q "v2ray-client"; then
        error "v2ray-client container is not running. Please set up the tunnel first using setup-vless-server2.sh."
    fi
    
    # Test the proxy connection
    info "Testing proxy connection through tunnel..."
    if ! command -v curl &> /dev/null; then
        warn "curl not installed. Cannot test proxy connection."
    else
        if ! curl -s --connect-timeout 5 -x "http://$V2RAY_HTTP_PROXY" https://ifconfig.me > /dev/null; then
            error "Cannot connect through the tunnel proxy. Make sure the tunnel is working correctly."
        else
            info "Tunnel proxy is working correctly."
        fi
    fi
}

# Update Outline configuration to use the tunnel
update_outline_config() {
    info "Updating Outline configuration to use the tunnel..."
    
    # Create a configuration file for Outline to use our tunnel
    cat > "$OUTLINE_DIR/outline-tunnel.conf" << EOF
# Outline VPN Tunnel Configuration
# Routes all traffic from Outline VPN clients through Server 1

# This server's IP address
LOCAL_IP=${LOCAL_IP}

# Tunnel proxy
HTTP_PROXY=http://${V2RAY_HTTP_PROXY}
HTTPS_PROXY=http://${V2RAY_HTTP_PROXY}
NO_PROXY=${LOCAL_IP},127.0.0.1,localhost
EOF
    
    # Check if env_file is already in docker-compose.yml
    if grep -q "env_file:" "$OUTLINE_DIR/docker-compose.yml"; then
        info "env_file already exists in docker-compose.yml, updating it..."
        sed -i "/env_file:/,/^ *[a-z]/ s|- .*|- $OUTLINE_DIR/outline-tunnel.conf|" "$OUTLINE_DIR/docker-compose.yml"
    else
        info "Adding env_file to docker-compose.yml..."
        # Make a backup
        cp "$OUTLINE_DIR/docker-compose.yml" "$OUTLINE_DIR/docker-compose.yml.bak"
        
        # Add our environment file to the Outline service
        sed -i '/watchtower:/i \ \ env_file:\n\ \ \ \ - '"$OUTLINE_DIR"'/outline-tunnel.conf' "$OUTLINE_DIR/docker-compose.yml"
    fi
    
    info "Outline configuration updated to use the tunnel."
}

# Update routing rules
update_routing() {
    info "Updating routing rules for Outline..."
    
    # Create iptables rules for Outline
    cat > /usr/local/bin/outline-tunnel-routing.sh << EOF
#!/bin/bash

# Clear any existing rules related to Outline
iptables -t nat -D POSTROUTING -o lo -s 10.0.0.0/24 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -j MASQUERADE 2>/dev/null || true

# Allow direct connections to this server
iptables -t nat -A V2RAY -d ${LOCAL_IP} -j RETURN 2>/dev/null || true

# Add masquerading rule for Outline clients
iptables -t nat -A POSTROUTING -o lo -s 10.0.0.0/24 -j MASQUERADE
EOF
    
    chmod +x /usr/local/bin/outline-tunnel-routing.sh
    
    # Run the script
    /usr/local/bin/outline-tunnel-routing.sh
    
    # Make sure it runs after reboot (check for existing service first)
    if [ ! -f "/etc/systemd/system/outline-tunnel-routing.service" ]; then
        cat > /etc/systemd/system/outline-tunnel-routing.service << EOF
[Unit]
Description=Configure Outline Tunnel Routing Rules
After=network.target docker.service v2ray-tunnel.service
Requires=v2ray-tunnel.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/outline-tunnel-routing.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable outline-tunnel-routing.service
    fi
    
    info "Routing rules updated for Outline."
}

# Restart Outline with the new configuration
restart_outline() {
    info "Restarting Outline with the new configuration..."
    
    # Change to the Outline directory and restart
    cd "$OUTLINE_DIR"
    
    # Check if docker-compose is installed
    if ! command -v docker-compose &> /dev/null; then
        if ! command -v docker &> /dev/null; then
            error "Neither docker-compose nor docker compose plugin found."
        else
            # Try using docker compose plugin
            docker compose down
            docker compose up -d
        fi
    else
        # Use traditional docker-compose
        docker-compose down
        docker-compose up -d
    fi
    
    info "Outline has been restarted with the new configuration."
}

# Test the connection
test_connection() {
    info "Testing the connection..."
    
    # Wait a few seconds for Outline to start
    sleep 5
    
    # Check if Outline is running
    if ! docker ps | grep -q "outline-server"; then
        warn "Outline server did not start properly. Check the logs with: docker logs outline-server"
    else
        info "Outline server is running."
    fi
    
    # Check if the port is open
    if ! ss -tulpn | grep -q ":$OUTLINE_PORT"; then
        warn "Outline VPN port $OUTLINE_PORT does not appear to be open."
    else
        info "Outline VPN port $OUTLINE_PORT is open."
    fi
    
    # Success message
    info "Outline is now configured to route through the tunnel!"
    info "You may need to update your Outline access keys or reconnect clients."
}

# Main function
main() {
    check_root
    parse_args "$@"
    check_outline
    check_tunnel
    update_outline_config
    update_routing
    restart_outline
    test_connection
    
    info "====================================================================="
    info "Outline VPN has been configured to route through the tunnel!"
    info "All client traffic will now go through Server 1."
    info "====================================================================="
}

main "$@"