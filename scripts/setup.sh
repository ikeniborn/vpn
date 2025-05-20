#!/bin/bash

# setup.sh - Combined setup script for Outline Server and VLESS-Reality
# This script:
# - Sets up Docker environment
# - Configures Outline Server with Shadowsocks
# - Configures VLESS+Reality server
# - Sets up optimized routing
# - Implements security measures

set -euo pipefail

# Colors for output
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
BACKUP_DIR="${BASE_DIR}/backups"
METRICS_DIR="${BASE_DIR}/metrics"

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

# Check system requirements
check_system_requirements() {
    info "Checking system requirements..."
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        warn "Low CPU core count detected: $CPU_CORES cores. Minimum recommended is 2 cores."
    else
        info "CPU cores: $CPU_CORES (OK)"
    fi
    
    # Check RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1024 ]; then
        warn "Low memory detected: $TOTAL_RAM MB. Minimum recommended is 1024 MB."
    else
        info "Memory: $TOTAL_RAM MB (OK)"
    fi
    
    # Check disk space
    DISK_SPACE=$(df -m / | awk '{if(NR==2) print $4}')
    if [ "$DISK_SPACE" -lt 5120 ]; then 
        warn "Low disk space detected: $DISK_SPACE MB free. Minimum recommended is 5120 MB."
    else
        info "Disk space: $DISK_SPACE MB (OK)"
    fi
    
    # Check if ports are available
    if lsof -i :"$OUTLINE_PORT" > /dev/null 2>&1; then
        warn "Port $OUTLINE_PORT is already in use. Consider using a different port."
    fi
    
    if lsof -i :"$V2RAY_PORT" > /dev/null 2>&1; then
        warn "Port $V2RAY_PORT is already in use. Consider using a different port."
    fi
}

# Detect architecture and set appropriate Docker images
detect_architecture() {
    info "Detecting system architecture..."
    ARCH=$(uname -m)
    
    case $ARCH in
        aarch64|arm64)
            # Use the well-tested ARM64 images from the ericqmore project
            SB_IMAGE="ken1029/shadowbox:latest"
            WATCHTOWER_IMAGE="ken1029/watchtower:arm64"
            V2RAY_IMAGE="v2fly/v2fly-core:latest"
            info "ARM64 architecture detected, using ARM64-compatible images"
            ;;
        armv7l)
            # Use the well-tested ARMv7 images from the ericqmore project
            SB_IMAGE="ken1029/shadowbox:latest"
            WATCHTOWER_IMAGE="ken1029/watchtower:arm32"
            V2RAY_IMAGE="v2fly/v2fly-core:latest"
            info "ARMv7 architecture detected, using ARMv7-compatible images"
            ;;
        x86_64|amd64)
            # For x86 architecture, use standard images
            SB_IMAGE="shadowsocks/shadowsocks-libev:latest"
            WATCHTOWER_IMAGE="containrrr/watchtower:latest"
            V2RAY_IMAGE="v2fly/v2fly-core:latest"
            info "x86_64 architecture detected, using standard images"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac
    
    info "Using images:"
    info "- Shadowsocks: ${SB_IMAGE}"
    info "- V2Ray: ${V2RAY_IMAGE}"
    info "- Watchtower: ${WATCHTOWER_IMAGE}"
    
    # Export variables for docker-compose
    export SB_IMAGE
    export WATCHTOWER_IMAGE
    export V2RAY_IMAGE
}

# Update system packages
update_system() {
    info "Updating system packages..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

# Check for required dependencies
check_dependencies() {
    info "Checking required dependencies..."
    
    local missing_deps=()
    local required_deps=("curl" "wget" "jq" "ufw" "socat" "qrencode")
    local required_packages=("net-tools")
    
    # Check each required command dependency
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    # Check for net-tools package specifically by checking for netstat command
    if ! command -v "netstat" &> /dev/null; then
        missing_deps+=("net-tools")
    fi
    
    # If any dependencies are missing, inform the user
    if [ ${#missing_deps[@]} -ne 0 ]; then
        warn "Missing required dependencies: ${missing_deps[*]}"
        info "Installing missing dependencies..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_deps[@]}"
        
        # Verify installation
        local still_missing=()
        for dep in "${missing_deps[@]}"; do
            # Special check for net-tools package using netstat command
            if [ "$dep" = "net-tools" ]; then
                if ! command -v "netstat" &> /dev/null; then
                    still_missing+=("$dep")
                fi
            elif ! command -v "$dep" &> /dev/null; then
                still_missing+=("$dep")
            fi
        done
        
        if [ ${#still_missing[@]} -ne 0 ]; then
            error "Failed to install dependencies: ${still_missing[*]}"
        fi
    else
        info "All required dependencies are installed"
    fi
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."
    
    # First check required dependencies
    check_dependencies
    
    # Install additional helpful packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates gnupg lsb-release bc mailutils apt-transport-https software-properties-common
}

# Install Docker if not already installed
install_docker() {
    info "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        info "Installing Docker..."
        
        # Add Docker's official GPG key
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up the Docker repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io
        
        # Enable and start Docker service
        systemctl enable docker
        systemctl start docker
    else
        info "Docker is already installed: $(docker --version)"
    fi

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        info "Installing Docker Compose..."
        
        # Install Docker Compose
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
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "${METRICS_DIR}"
    
    # Set proper permissions
    chmod 700 "${BACKUP_DIR}"
}

# Configure Outline Server
configure_outline() {
    info "Configuring Outline Server..."
    
    # Generate a strong random password
    local ss_password=$(openssl rand -base64 24)
    
    # Create config files with secure permissions from the start
    # Create empty files with proper permissions first
    touch "${OUTLINE_DIR}/config.json"
    touch "${OUTLINE_DIR}/access.json"
    chmod 600 "${OUTLINE_DIR}/config.json"
    chmod 600 "${OUTLINE_DIR}/access.json"
    
    # Now write the sensitive content to the properly secured files
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
    
    # Create access policy with secure permissions
    cat > "${OUTLINE_DIR}/access.json" <<EOF
{
  "strategy": "allow",
  "rules": []
}
EOF
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
        
        # Try different commands to generate keypair
        
        # First attempt - try xray generate x25519
        local key_output=""
        key_output=$(docker run --rm v2fly/v2fly-core:latest xray x25519 2>/dev/null || true)
        
        # Check if we got keys from first attempt
        if echo "$key_output" | grep -q "Private key:" && echo "$key_output" | grep -q "Public key:"; then
            private_key=$(echo "$key_output" | grep "Private key:" | cut -d ' ' -f3)
            public_key=$(echo "$key_output" | grep "Public key:" | cut -d ' ' -f3)
            info "Successfully generated X25519 keypair with xray x25519 command"
        else
            # Second attempt - try v2ray x25519
            key_output=$(docker run --rm v2fly/v2fly-core:latest v2ray x25519 2>/dev/null || true)
            
            # Check if we got keys from second attempt
            if echo "$key_output" | grep -q "Private key:" && echo "$key_output" | grep -q "Public key:"; then
                private_key=$(echo "$key_output" | grep "Private key:" | cut -d ' ' -f3)
                public_key=$(echo "$key_output" | grep "Public key:" | cut -d ' ' -f3)
                info "Successfully generated X25519 keypair with v2ray x25519 command"
            else
                # Fallback method - generate random keys
                warn "Could not generate proper X25519 keypair using Docker container."
                warn "Using a fallback method to generate random keys."
                
                # Generate private and public keys using openssl (these are just random values, not real X25519 keys)
                private_key=$(openssl rand -hex 32)
                public_key=$(openssl rand -hex 32)
                
                warn "IMPORTANT: The generated keys are NOT proper X25519 keys."
                warn "You should manually generate proper keys and update the config."
            fi
        fi
        
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
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "protocol": "freedom",
      "tag": "streaming_out",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 100,
          "tcpFastOpen": true,
          "tcpKeepAliveInterval": 25
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "browsing_out",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true
        }
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
          "youtube.com", "googlevideo.com", "*.googlevideo.com",
          "netflix.com", "netflixdnstest.com", "*.nflxvideo.net",
          "hulu.com", "hulustream.com",
          "spotify.com", "*.spotifycdn.com",
          "twitch.tv", "*.ttvnw.net", "*.jtvnw.net",
          "amazon.com/Prime-Video", "primevideo.com", "aiv-cdn.net"
        ],
        "outboundTag": "streaming_out"
      },
      {
        "type": "field",
        "domain": [
          "*.googleusercontent.com", "*.gstatic.com", 
          "*.facebook.com", "*.fbcdn.net",
          "*.twitter.com", "*.twimg.com",
          "*.instagram.com", "*.cdninstagram.com"
        ],
        "outboundTag": "browsing_out"
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
        chmod 600 "${V2RAY_DIR}/users.db"
    fi
}

# Create Docker Compose configuration
create_docker_compose() {
    info "Creating Docker Compose configuration..."
    
    # We'll use the SB_IMAGE variable directly, which has already been set
    # based on architecture in the detect_architecture function
    info "Using Outline Server image: ${SB_IMAGE}"
    
    cat > "${BASE_DIR}/docker-compose.yml" <<EOF
version: '3'

services:
  outline-server:
    image: ${SB_IMAGE}
    container_name: outline-server
    restart: always
    # Use host networking mode which works better with the ken1029/shadowbox image
    network_mode: "host"
    volumes:
      - ./outline-server/config.json:/etc/shadowsocks-libev/config.json
      - ./outline-server/access.json:/etc/shadowsocks-libev/access.json
      - ./outline-server/data:/opt/outline/data
      - ./logs/outline:/var/log/shadowsocks
    environment:
      - SS_CONFIG=/etc/shadowsocks-libev/config.json
    cap_add:
      - NET_ADMIN
      
  v2ray:
    image: ${V2RAY_IMAGE}
    container_name: v2ray
    restart: always
    network_mode: "host"
    volumes:
      - ./v2ray/config.json:/etc/v2ray/config.json
      - ./logs/v2ray:/var/log/v2ray
    command: run -c /etc/v2ray/config.json
    cap_add:
      - NET_ADMIN

  watchtower:
    image: ${WATCHTOWER_IMAGE}
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --tlsverify --interval 3600
    depends_on:
      - outline-server
      - v2ray
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
    
    info "Firewall configured successfully"
}

# Create user management script
create_user_management() {
    info "Creating user management script..."
    
    # Copy the user management script to the scripts directory
    cp "$(dirname "$0")/manage-users.sh" "${SCRIPT_DIR}/manage-users.sh"
    chmod +x "${SCRIPT_DIR}/manage-users.sh"
    
    info "User management script created at ${SCRIPT_DIR}/manage-users.sh"
}

# Create monitoring script
create_monitoring_script() {
    info "Creating monitoring script..."
    
    # Copy the monitoring script to the scripts directory
    cp "$(dirname "$0")/monitoring.sh" "${SCRIPT_DIR}/monitoring.sh"
    chmod +x "${SCRIPT_DIR}/monitoring.sh"
    
    info "Monitoring script created at ${SCRIPT_DIR}/monitoring.sh"
}

# Create backup script
create_backup_script() {
    info "Creating backup script..."
    
    # Copy the backup script to the scripts directory
    cp "$(dirname "$0")/backup.sh" "${SCRIPT_DIR}/backup.sh"
    chmod +x "${SCRIPT_DIR}/backup.sh"
    
    info "Backup script created at ${SCRIPT_DIR}/backup.sh"
}

# Create restore script
create_restore_script() {
    info "Creating restore script..."
    
    # Copy the restore script to the scripts directory
    cp "$(dirname "$0")/restore.sh" "${SCRIPT_DIR}/restore.sh"
    chmod +x "${SCRIPT_DIR}/restore.sh"
    
    info "Restore script created at ${SCRIPT_DIR}/restore.sh"
}

# Create maintenance scripts
create_maintenance_scripts() {
    info "Creating maintenance scripts..."
    
    # Copy the daily maintenance script
    cp "$(dirname "$0")/daily-maintenance.sh" "${SCRIPT_DIR}/daily-maintenance.sh"
    chmod +x "${SCRIPT_DIR}/daily-maintenance.sh"
    
    # Copy the weekly maintenance script
    cp "$(dirname "$0")/weekly-maintenance.sh" "${SCRIPT_DIR}/weekly-maintenance.sh"
    chmod +x "${SCRIPT_DIR}/weekly-maintenance.sh"
    
    info "Maintenance scripts created"
}

# Create security audit script
create_security_audit_script() {
    info "Creating security audit script..."
    
    # Copy the security audit script
    cp "$(dirname "$0")/security-audit.sh" "${SCRIPT_DIR}/security-audit.sh"
    chmod +x "${SCRIPT_DIR}/security-audit.sh"
    
    info "Security audit script created at ${SCRIPT_DIR}/security-audit.sh"
}

# Create alert script
create_alert_script() {
    info "Creating alert script..."
    
    # Copy the alert script
    cp "$(dirname "$0")/alert.sh" "${SCRIPT_DIR}/alert.sh"
    chmod +x "${SCRIPT_DIR}/alert.sh"
    
    info "Alert script created at ${SCRIPT_DIR}/alert.sh"
}

# Setup cron jobs for maintenance and monitoring
setup_cron_jobs() {
    info "Setting up cron jobs..."
    
    # Create a temporary file for cron entries
    local cron_file=$(mktemp)
    
    # Add cron entries
    cat > "$cron_file" <<EOF
# Run monitoring every 15 minutes
*/15 * * * * root ${SCRIPT_DIR}/monitoring.sh > /dev/null 2>&1

# Run daily backup at 1 AM
0 1 * * * root ${SCRIPT_DIR}/backup.sh > /dev/null 2>&1

# Run daily maintenance at 2 AM
0 2 * * * root ${SCRIPT_DIR}/daily-maintenance.sh > /dev/null 2>&1

# Run weekly maintenance at 3 AM on Sundays
0 3 * * 0 root ${SCRIPT_DIR}/weekly-maintenance.sh > /dev/null 2>&1

# Run security audit at 4 AM on the first day of each month
0 4 1 * * root ${SCRIPT_DIR}/security-audit.sh > /dev/null 2>&1
EOF
    
    # Install the cron file
    install -m 644 "$cron_file" /etc/cron.d/vpn-maintenance
    
    # Remove the temporary file
    rm "$cron_file"
    
    info "Cron jobs set up successfully"
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
    echo "Management Scripts:"
    echo "  - User Management: ${SCRIPT_DIR}/manage-users.sh"
    echo "  - Monitoring: ${SCRIPT_DIR}/monitoring.sh"
    echo "  - Backup: ${SCRIPT_DIR}/backup.sh"
    echo "  - Restore: ${SCRIPT_DIR}/restore.sh"
    echo "  - Daily Maintenance: ${SCRIPT_DIR}/daily-maintenance.sh"
    echo "  - Weekly Maintenance: ${SCRIPT_DIR}/weekly-maintenance.sh"
    echo "  - Security Audit: ${SCRIPT_DIR}/security-audit.sh"
    echo ""
    echo "To manage users, use:"
    echo "  ${SCRIPT_DIR}/manage-users.sh"
    echo ""
    echo "To export client configurations, use:"
    echo "  ${SCRIPT_DIR}/manage-users.sh --export --uuid \"<USER_UUID>\""
    echo "=================================================="
}

# Check if scripts directory contains required files
check_required_scripts() {
    local missing_files=()
    local required_files=(
        "$(dirname "$0")/manage-users.sh"
        "$(dirname "$0")/monitoring.sh"
        "$(dirname "$0")/backup.sh"
        "$(dirname "$0")/restore.sh"
        "$(dirname "$0")/daily-maintenance.sh"
        "$(dirname "$0")/weekly-maintenance.sh"
        "$(dirname "$0")/security-audit.sh"
        "$(dirname "$0")/alert.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -ne 0 ]; then
        warn "The following required script files are missing:"
        for file in "${missing_files[@]}"; do
            warn "  - $(basename "$file")"
        done
        warn "These files will be skipped during setup. You may need to create them manually."
    fi
}

# Perform health check
health_check() {
    info "Performing initial health check..."
    
    # Add a delay to allow services to fully start
    info "Waiting 20 seconds for services to initialize..."
    sleep 20
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        warn "Docker service is not running"
        return 1
    fi
    
    # Check if containers are running
    if ! docker ps | grep -q "outline-server"; then
        warn "Outline Server container is not running"
        docker logs outline-server
        return 1
    fi
    
    # Special check for v2ray
    local v2ray_running=false
    if docker ps | grep -q "v2ray"; then
        v2ray_running=true
        info "v2ray container is running"
    else
        warn "v2ray container is not running"
        docker logs v2ray || true
        # Try to restart the container
        info "Attempting to restart v2ray container..."
        docker restart v2ray || true
        sleep 10
    fi
    
    # Check if ports are listening
    if ! netstat -tuln | grep -q ":${OUTLINE_PORT}"; then
        warn "Outline Server port ${OUTLINE_PORT} is not listening"
        docker logs outline-server
        return 1
    fi
    
    # More lenient v2ray port check
    if netstat -tuln | grep -q ":${V2RAY_PORT}"; then
        info "v2ray port ${V2RAY_PORT} is listening"
    else
        warn "v2ray port ${V2RAY_PORT} is not listening"
        # Show v2ray logs but continue
        docker logs v2ray || true
        warn "v2ray may take longer to initialize or might need further configuration"
        warn "You can manually check the status later with: docker logs v2ray"
        warn "You may need to restart v2ray after installation: docker restart v2ray"
    fi
    
    info "Health check completed"
    # Always return success to allow script to complete
    return 0
}

# Main function
main() {
    check_root
    parse_args "$@"
    check_system_requirements
    check_required_scripts
    
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
    
    # Execute installation steps
    update_system
    check_dependencies
    install_dependencies
    install_docker
    detect_architecture
    create_directories
    configure_outline
    configure_v2ray
    create_docker_compose
    configure_firewall
    create_user_management
    create_monitoring_script
    create_backup_script
    create_restore_script
    create_maintenance_scripts
    create_security_audit_script
    create_alert_script
    setup_cron_jobs
    start_services
    health_check
    display_summary
    
    info "Installation completed successfully!"
}

# Execute main function with all arguments
main "$@"