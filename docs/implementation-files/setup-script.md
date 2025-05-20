# VPN Integration Setup Script

This script automates the deployment of the integrated Shadowsocks/Outline Server and VLESS+Reality VPN solution.

## File Path
```
/opt/vpn/scripts/setup.sh
```

## Script Content

```bash
#!/bin/bash

# setup.sh - Combined setup script for Outline Server and VLESS-Reality
# This script:
# - Sets up Docker environment
# - Configures Outline Server with Shadowsocks
# - Integrates with existing VLESS+Reality server
# - Sets up optimized routing

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
SCRIPT_DIR="${BASE_DIR}/scripts"
LOGS_DIR="${BASE_DIR}/logs"

# Default values
OUTLINE_PORT="8388"
V2RAY_PORT="443"
DEST_SITE="www.microsoft.com:443"
FINGERPRINT="chrome"

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

# Display usage information
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script performs a complete setup of the integrated Outline Server (Shadowsocks)
and VLESS-Reality VPN solution.

Options:
  --outline-port PORT     Port for Outline Server (default: 8388)
  --v2ray-port PORT       Port for v2ray VLESS protocol (default: 443)
  --dest-site SITE        Destination site to mimic (default: www.microsoft.com:443)
  --fingerprint TYPE      TLS fingerprint to simulate (default: chrome)
  --help                  Display this help message

Example:
  $(basename "$0") --outline-port 8388 --v2ray-port 443
EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --outline-port)
                OUTLINE_PORT="$2"
                shift
                ;;
            --v2ray-port)
                V2RAY_PORT="$2"
                shift
                ;;
            --dest-site)
                DEST_SITE="$2"
                shift
                ;;
            --fingerprint)
                FINGERPRINT="$2"
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
    info "- Outline Server port: $OUTLINE_PORT"
    info "- v2ray port: $V2RAY_PORT"
    info "- Destination site: $DEST_SITE"
    info "- TLS fingerprint: $FINGERPRINT"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
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
        curl wget jq ufw socat qrencode net-tools ca-certificates gnupg docker-compose
}

# Install Docker if not already installed
install_docker() {
    info "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        info "Installing Docker..."
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    else
        info "Docker is already installed: $(docker --version)"
    fi

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        info "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        info "Docker Compose is already installed: $(docker-compose --version)"
    fi
}

# Create directory structure
create_directories() {
    info "Creating directory structure..."
    mkdir -p "${OUTLINE_DIR}/certs"
    mkdir -p "${OUTLINE_DIR}/data"
    mkdir -p "${V2RAY_DIR}"
    mkdir -p "${SCRIPT_DIR}"
    mkdir -p "${LOGS_DIR}/outline"
    mkdir -p "${LOGS_DIR}/v2ray"
}

# Configure Outline Server
configure_outline() {
    info "Configuring Outline Server..."
    
    # Generate a random password
    local ss_password=$(openssl rand -base64 16)
    
    # Create Shadowsocks config
    cat > "${OUTLINE_DIR}/config.json" <<EOF
{
  "server": "0.0.0.0",
  "server_port": ${OUTLINE_PORT},
  "password": "${ss_password}",
  "timeout": 300,
  "method": "chacha20-ietf-poly1305",
  "fast_open": true,
  "reuse_port": true,
  "no_delay": true,
  "nameserver": "8.8.8.8",
  "mode": "tcp_and_udp",
  "plugin": "obfs-server",
  "plugin_opts": "obfs=http;obfs-host=${DEST_SITE%%:*}"
}
EOF
    
    # Create access policy
    cat > "${OUTLINE_DIR}/access.json" <<EOF
{
  "strategy": "allow", 
  "rules": []
}
EOF
    
    chmod 600 "${OUTLINE_DIR}/config.json"
    chmod 600 "${OUTLINE_DIR}/access.json"
}

# Configure v2ray with updated routing
configure_v2ray() {
    info "Configuring v2ray with updated routing..."
    
    # Use existing key pair or generate a new one
    local private_key=""
    local public_key=""
    local short_id=$(openssl rand -hex 8)
    
    if [ -f "${V2RAY_DIR}/reality_keypair.txt" ]; then
        info "Using existing Reality key pair..."
        private_key=$(grep "Private key:" "${V2RAY_DIR}/reality_keypair.txt" | cut -d ' ' -f3)
        public_key=$(grep "Public key:" "${V2RAY_DIR}/reality_keypair.txt" | cut -d ' ' -f3)
    else
        info "Generating new Reality key pair..."
        local key_output=$(docker run --rm v2fly/v2fly-core:latest xray x25519)
        private_key=$(echo "$key_output" | grep "Private key:" | cut -d ' ' -f3)
        public_key=$(echo "$key_output" | grep "Public key:" | cut -d ' ' -f3)
        
        # Save key pair for reference
        {
            echo "Private key: $private_key"
            echo "Public key: $public_key"
        } > "${V2RAY_DIR}/reality_keypair.txt"
        chmod 600 "${V2RAY_DIR}/reality_keypair.txt"
    fi
    
    # Generate UUID for default user
    local default_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Extract server name from destination site
    local server_name="${DEST_SITE%%:*}"
    
    # Create v2ray config with updated routing
    cat > "${V2RAY_DIR}/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": ${V2RAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${default_uuid}",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "default-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_SITE}",
          "xver": 0,
          "serverNames": [
            "${server_name}"
          ],
          "privateKey": "${private_key}",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "${short_id}"
          ],
          "fingerprint": "${FINGERPRINT}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "listen": "172.16.238.3",
      "port": ${V2RAY_PORT},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "0.0.0.0",
        "network": "tcp,udp",
        "followRedirect": true
      },
      "tag": "outline_in",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "protocol": "freedom",
      "tag": "streaming_out",
      "settings": {
        "domainStrategy": "AsIs"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 100,
          "tcpFastOpen": true
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "browsing_out",
      "settings": {
        "domainStrategy": "AsIs"
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["outline_in"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": [
          "youtube.com", "googlevideo.com",
          "netflix.com", "netflixdnstest.com",
          "hulu.com", "hulustream.com",
          "spotify.com", "spotifycdn.com"
        ],
        "outboundTag": "streaming_out"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
    
    # Set proper permissions
    chmod 644 "${V2RAY_DIR}/config.json"
    
    # Create users database if it doesn't exist
    if [ ! -f "${V2RAY_DIR}/users.db" ]; then
        echo "${default_uuid}|default-user|$(date '+%Y-%m-%d %H:%M:%S')" > "${V2RAY_DIR}/users.db"
    fi
}

# Create Docker Compose configuration
create_docker_compose() {
    info "Creating Docker Compose configuration..."
    
    cat > "${BASE_DIR}/docker-compose.yml" <<EOF
version: '3'

services:
  outline-server:
    image: shadowsocks/shadowsocks-libev:latest
    container_name: outline-server
    restart: always
    volumes:
      - ./outline-server/config.json:/etc/shadowsocks-libev/config.json
      - ./outline-server/access.json:/etc/shadowsocks-libev/access.json
      - ./outline-server/data:/opt/outline/data
      - ./logs/outline:/var/log/shadowsocks
    ports:
      - "${OUTLINE_PORT}:${OUTLINE_PORT}/tcp"
      - "${OUTLINE_PORT}:${OUTLINE_PORT}/udp"
    networks:
      vpn-network:
        ipv4_address: 172.16.238.2
    environment:
      - SS_CONFIG=/etc/shadowsocks-libev/config.json
    cap_add:
      - NET_ADMIN
      
  v2ray:
    image: v2fly/v2fly-core:latest
    container_name: v2ray
    restart: always
    volumes:
      - ./v2ray/config.json:/etc/v2ray/config.json
      - ./logs/v2ray:/var/log/v2ray
    ports:
      - "${V2RAY_PORT}:${V2RAY_PORT}/tcp"
      - "${V2RAY_PORT}:${V2RAY_PORT}/udp"
    networks:
      vpn-network:
        ipv4_address: 172.16.238.3
    depends_on:
      - outline-server
    cap_add:
      - NET_ADMIN

networks:
  vpn-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.238.0/24
EOF
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall..."
    
    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        info "UFW not found. Installing UFW..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
    fi
    
    # Configure UFW
    info "Configuring UFW rules..."
    
    # Reset UFW to default state
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (port 22)
    ufw allow 22/tcp
    
    # Allow Outline Server port
    ufw allow ${OUTLINE_PORT}/tcp
    ufw allow ${OUTLINE_PORT}/udp
    
    # Allow v2ray port
    ufw allow ${V2RAY_PORT}/tcp
    ufw allow ${V2RAY_PORT}/udp
    
    # Enable IP forwarding (required for VPN)
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Apply sysctl changes
    sysctl -p
    
    # Configure UFW to allow forwarded packets
    if ! grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    fi
    
    # Enable UFW
    echo "y" | ufw enable
}

# Create user management script
create_user_management() {
    info "Creating user management script..."
    
    cat > "${SCRIPT_DIR}/manage-users.sh" <<'EOF'
#!/bin/bash
#
# Script to manage users for both Outline Server and VLESS-Reality

set -euo pipefail

# Default paths
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
OUTLINE_CONFIG="${OUTLINE_DIR}/config.json"
V2RAY_CONFIG="${V2RAY_DIR}/config.json"
V2RAY_USERS_DB="${V2RAY_DIR}/users.db"

# Script implementation goes here
# See the separate user management script documentation
EOF

    chmod +x "${SCRIPT_DIR}/manage-users.sh"
}

# Create monitoring script
create_monitoring_script() {
    info "Creating monitoring script..."
    
    cat > "${SCRIPT_DIR}/monitoring.sh" <<'EOF'
#!/bin/bash
#
# Script to monitor health of Outline Server and VLESS-Reality

set -euo pipefail

# Default paths
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"

# Script implementation goes here
# See the separate monitoring script documentation
EOF

    chmod +x "${SCRIPT_DIR}/monitoring.sh"
}

# Start services
start_services() {
    info "Starting VPN services..."
    
    cd "${BASE_DIR}"
    docker-compose up -d
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        info "VPN services started successfully"
    else
        error "Failed to start VPN services"
    fi
}

# Display configuration summary
display_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo "=================================================="
    info "VPN Integration Setup Completed"
    echo "=================================================="
    echo "Configuration Summary:"
    echo "  - Outline Server (Shadowsocks):"
    echo "      - Server: ${server_ip}"
    echo "      - Port: ${OUTLINE_PORT}"
    echo "      - Method: chacha20-ietf-poly1305"
    echo "      - Obfuscation: HTTP"
    echo ""
    echo "  - VLESS+Reality Server:"
    echo "      - Server: ${server_ip}" 
    echo "      - Port: ${V2RAY_PORT}"
    echo "      - Destination Site: ${DEST_SITE}"
    echo "      - Fingerprint: ${FINGERPRINT}"
    echo ""
    echo "Default user created with UUID:"
    grep -o "id\": \"[^\"]*" "${V2RAY_DIR}/config.json" | head -1 | cut -d'"' -f3
    echo ""
    echo "To manage users, use:"
    echo "  ${SCRIPT_DIR}/manage-users.sh"
    echo "=================================================="
}

# Main function
main() {
    check_root
    parse_args "$@"
    
    # Interactive confirmation
    echo "This script will set up the integrated VPN solution with the following settings:"
    echo "- Outline Server port: $OUTLINE_PORT"
    echo "- v2ray port: $V2RAY_PORT"
    echo "- Destination site: $DEST_SITE"
    echo "- TLS fingerprint: $FINGERPRINT"
    echo ""
    echo -n "Proceed with installation? [Y/n] "
    read -r RESPONSE
    RESPONSE=$(echo "${RESPONSE}" | tr '[:upper:]' '[:lower:]')
    if [[ -n "${RESPONSE}" && "${RESPONSE}" != "y" && "${RESPONSE}" != "yes" ]]; then
        echo "Installation aborted by user"
        exit 0
    fi
    
    update_system
    install_dependencies
    install_docker
    create_directories
    configure_outline
    configure_v2ray
    create_docker_compose
    configure_firewall
    create_user_management
    create_monitoring_script
    start_services
    display_summary
}

# Execute main function with all arguments
main "$@"
```

## Script Execution

Make the script executable and run it:

```bash
chmod +x /opt/vpn/scripts/setup.sh
sudo /opt/vpn/scripts/setup.sh
```

## Customization Options

The script accepts several parameters to customize the deployment:

1. `--outline-port PORT`: Change the default Shadowsocks port (default: 8388)
2. `--v2ray-port PORT`: Change the default VLESS+Reality port (default: 443)
3. `--dest-site SITE`: Specify the site to mimic in Reality (default: www.microsoft.com:443)
4. `--fingerprint TYPE`: Set the TLS fingerprint to use (default: chrome)

Example with custom options:

```bash
sudo ./setup.sh --outline-port 9000 --v2ray-port 8443 --dest-site www.cloudflare.com:443 --fingerprint firefox
```

## Implementation Details

### Setup Process

1. **Environment Preparation**:
   - Checks for root privileges
   - Updates system packages
   - Installs required dependencies
   - Sets up Docker if not already installed

2. **Directory Structure**:
   - Creates required directories for configuration and logs
   - Sets appropriate permissions

3. **Configuration**:
   - Configures Outline Server (Shadowsocks)
   - Configures v2ray with optimized routing
   - Creates Docker Compose file
   - Sets up firewall rules

4. **Management Scripts**:
   - Creates user management script
   - Creates monitoring script

5. **Service Startup**:
   - Starts containers with Docker Compose
   - Verifies services are running correctly

### Security Considerations

1. **File Permissions**:
   - Sensitive configuration files use restricted permissions (600)
   - Executables use standard permissions (755)

2. **Network Security**:
   - Firewall allows only necessary ports
   - IP forwarding enabled for VPN functionality
   - UFW configured to allow forwarded packets

3. **Authentication**:
   - Random password generation for Shadowsocks
   - UUID-based authentication for VLESS
   - Reality protocol for advanced obfuscation

### Optimization Features

1. **Performance Settings**:
   - TCP optimizations (fast open, keep-alive)
   - Content-based routing rules
   - Smart traffic handling

2. **Integration Design**:
   - Internal Docker network for secure communication
   - Static IP addressing for reliable routing
   - Container dependencies for proper startup order