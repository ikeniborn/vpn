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
    
    # Reality connection string components
    local REALITY_PARAMS=""
    if [ -n "$SERVER1_PUBKEY" ]; then
        REALITY_PARAMS="&pbk=${SERVER1_PUBKEY}"
    fi
    
    if [ -n "$SERVER1_SHORTID" ]; then
        REALITY_PARAMS="${REALITY_PARAMS}&sid=${SERVER1_SHORTID}"
    fi
    
    # Create v2ray client config
    cat > "$V2RAY_DIR/config.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "tag": "socks-inbound",
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "tag": "http-inbound",
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {
        "auth": "noauth"
      }
    },
    {
      "tag": "transparent-inbound",
      "port": 1081,
      "listen": "0.0.0.0",
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "tunnel-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER1_ADDRESS}",
            "port": ${SERVER1_PORT},
            "users": [
              {
                "id": "${SERVER1_UUID}",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "${SERVER1_SNI}",
          "fingerprint": "${SERVER1_FINGERPRINT}"${REALITY_PARAMS:+,}
          ${SERVER1_PUBKEY:+"publicKey": "${SERVER1_PUBKEY}"}${SERVER1_SHORTID:+,}
          ${SERVER1_SHORTID:+"shortId": "${SERVER1_SHORTID}"}
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["127.0.0.1/32"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["socks-inbound", "http-inbound", "transparent-inbound"],
        "outboundTag": "tunnel-out"
      }
    ]
  }
}
EOF
    
    chmod 644 "$V2RAY_DIR/config.json"
    
    # Pull v2ray Docker image
    info "Pulling v2ray Docker image..."
    docker pull v2fly/v2fly-core:latest
    
    # Remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^v2ray-client$"; then
        info "Removing existing v2ray-client container..."
        docker rm -f v2ray-client
    fi
    
    # Handle Docker network creation
    info "Setting up Docker network..."
    if docker network inspect v2ray-network &>/dev/null; then
        info "Docker network v2ray-network already exists, using existing network."
    else
        info "Creating Docker network..."
        docker network create v2ray-network
    fi
    
    # Run v2ray container
    info "Starting v2ray client container..."
    docker run -d \
        --name v2ray-client \
        --restart always \
        --network host \
        --cap-add NET_ADMIN \
        -v "$V2RAY_DIR/config.json:/etc/v2ray/config.json" \
        -v "$V2RAY_DIR/logs:/var/log/v2ray" \
        v2fly/v2fly-core:latest
    
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
    
    # Create iptables rules script
    cat > /usr/local/bin/setup-tunnel-routing.sh << EOF
#!/bin/bash

# Clear existing rules
iptables -t nat -F
iptables -t mangle -F

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
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 1081
iptables -t nat -A PREROUTING -p tcp -j V2RAY

# Route traffic from Outline VPN through the tunnel
iptables -t nat -A POSTROUTING -o lo -s 10.0.0.0/24 -j MASQUERADE
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
HTTP_PROXY=http://127.0.0.1:8080
HTTPS_PROXY=http://127.0.0.1:8080
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

# Test the tunnel connection
test_tunnel() {
    info "Testing tunnel connection to Server 1..."
    
    # Wait a few seconds for the tunnel to establish
    sleep 5
    
    # Test the connection using curl through the proxy
    if curl -s --connect-timeout 10 -x http://127.0.0.1:8080 https://ifconfig.me > /dev/null; then
        info "Tunnel is working correctly. Traffic is being routed through Server 1."
    else
        warn "Tunnel test failed. Please check the configuration and Server 1 connectivity."
        warn "You may need to manually verify the connection and correct any issues."
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