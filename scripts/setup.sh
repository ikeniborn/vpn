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
API_PORT="8989"  # Default API port different from Outline port
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
  --api-port PORT         Port for Outline API management (default: 8989)
  --v2ray-port PORT       Port for v2ray VLESS protocol (default: 443)
  --dest-site SITE        Destination site to mimic (default: www.microsoft.com:443)
  --fingerprint TYPE      TLS fingerprint to simulate (default: chrome)
  --help                  Display this help message

Example:
  $(basename "$0") --outline-port 8388 --api-port 8989 --v2ray-port 443
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
            --api-port)
                API_PORT="$2"
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
    info "- Outline API port: $API_PORT"
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
            # Use the official watchtower image which supports multiple architectures through Docker's manifest support
            WATCHTOWER_IMAGE="containrrr/watchtower:latest"
            V2RAY_IMAGE="v2fly/v2fly-core:latest"
            DOCKER_PLATFORM="linux/arm64"
            info "ARM64 architecture detected, using ARM64-compatible images"
            ;;
        armv7l)
            # Use the well-tested ARMv7 images from the ericqmore project
            SB_IMAGE="ken1029/shadowbox:latest"
            # Use the official watchtower image which supports multiple architectures
            WATCHTOWER_IMAGE="containrrr/watchtower:latest"
            V2RAY_IMAGE="v2fly/v2fly-core:latest"
            DOCKER_PLATFORM="linux/arm/v7"
            info "ARMv7 architecture detected, using ARMv7-compatible images"
            ;;
        x86_64|amd64)
            # For x86 architecture, use standard images
            SB_IMAGE="shadowsocks/shadowsocks-libev:latest"
            WATCHTOWER_IMAGE="containrrr/watchtower:latest"
            V2RAY_IMAGE="v2fly/v2fly-core:latest"
            DOCKER_PLATFORM="linux/amd64"
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
    info "- Platform: ${DOCKER_PLATFORM}"
    
    # Export variables for docker-compose
    export SB_IMAGE
    export WATCHTOWER_IMAGE
    export V2RAY_IMAGE
    export DOCKER_PLATFORM
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
    else
        info "Docker is already installed: $(docker --version)"
    fi
    
    # Always configure Docker daemon settings regardless of whether Docker was just installed
    # Create or update daemon.json to disable user namespace remapping
    info "Configuring Docker daemon to disable user namespace remapping..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "userns-remap": "",
  "storage-driver": "overlay2",
  "userland-proxy": false
}
EOF
    # Restart Docker with the new settings
    systemctl restart docker
    systemctl enable docker
    
    # Verify the settings were applied
    info "Verifying Docker daemon configuration..."
    sleep 5  # Wait for Docker to fully restart
    if docker info 2>/dev/null | grep -q "userns-remap: true"; then
        warn "Docker user namespace remapping is still enabled despite configuration!"
        warn "This might cause container layer mapping issues."
    else
        info "Docker user namespace remapping is disabled correctly."
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
    mkdir -p "${OUTLINE_DIR}/persisted-state/prometheus"
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

    # Create shadowbox_server_config.json file, which is required by ken1029/shadowbox image
    info "Creating shadowbox_server_config.json file..."
    
    # Try multiple methods to get the server's IP address
    # Using hostname -I as the primary method and avoiding potentially blocked external services
    local server_ip=""
    
    # Method 1: Try hostname command (most reliable for local network)
    server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    
    # Method 2: Try ip route command as fallback
    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
        server_ip=$(ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null)
        info "Using IP from ip route command: ${server_ip}"
    fi
    
    # Method 3: Only try external services as last resort and only if we have connectivity
    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
        # Check if we have internet connectivity before attempting external service
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null ||
                       curl -4 -s --connect-timeout 5 icanhazip.com 2>/dev/null)
            info "Using IP from external service: ${server_ip}"
        fi
    fi
    
    # Final fallback if all methods fail
    if [ -z "$server_ip" ]; then
        warn "Could not determine server IP address. Using localhost as fallback."
        server_ip="127.0.0.1"
    fi
    
    info "Using server IP address for configuration: ${server_ip}"
    mkdir -p "${OUTLINE_DIR}/data"
    
    # Generate a random API prefix for security
    local api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)
    
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
    
    # Create persisted-state directory specifically for Outline SB_STATE_DIR environment variable
    mkdir -p "${OUTLINE_DIR}/persisted-state/prometheus"
    mkdir -p "${OUTLINE_DIR}/persisted-state/shadowbox"
    
    # Copy the prometheus config.yml file to persisted-state
    if [ -f "$(dirname "$0")/prometheus_config.yml" ]; then
        cp "$(dirname "$0")/prometheus_config.yml" "${OUTLINE_DIR}/persisted-state/prometheus/config.yml"
        chmod 644 "${OUTLINE_DIR}/persisted-state/prometheus/config.yml"
        info "Prometheus configuration file copied successfully"
    else
        warn "Prometheus config file not found, creating default configuration"
        cat > "${OUTLINE_DIR}/persisted-state/prometheus/config.yml" <<EOF
# Basic Prometheus configuration for Outline server
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'outline'
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'outline-node-metrics'
    static_configs:
      - targets: ['127.0.0.1:9091']

  - job_name: 'outline-ss-server'
    static_configs:
      - targets: ['127.0.0.1:9092']
EOF
        chmod 644 "${OUTLINE_DIR}/persisted-state/prometheus/config.yml"
    fi
    
    # Create additional files required by the main.js at line 163
    # These files are likely accessed right after Prometheus initialization
    # Create files with valid content structures
    # metrics.json - empty JSON object
    echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/metrics.json"
    
    # servers.json - empty JSON object
    echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/servers.json"
    
    # access_keys.json - empty JSON array
    echo "[]" > "${OUTLINE_DIR}/persisted-state/shadowbox/access_keys.json"
    
    # server.yml with basic structure
    cat > "${OUTLINE_DIR}/persisted-state/shadowbox/server.yml" <<EOF
# Outline Server configuration
apiPort: ${API_PORT}
portForNewAccessKeys: ${OUTLINE_PORT}
hostname: ${server_ip}
EOF
    
    # metrics_state with minimal valid content
    echo "{\"lastUpdated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${OUTLINE_DIR}/persisted-state/metrics_state"
    
    # Set proper permissions
    chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/server.yml"
    chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/metrics.json"
    chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/servers.json"
    chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/access_keys.json"
    chmod 644 "${OUTLINE_DIR}/persisted-state/metrics_state"
    
    # Create a copy of the config in the persisted-state directory
    cp "${OUTLINE_DIR}/data/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
    chmod 600 "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
    
    # Export the server IP for later use in docker-compose
    export SERVER_IP="${server_ip}"
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
    
    # Create a custom docker-compose.yml file with simplified configuration
    cat > "${BASE_DIR}/docker-compose.yml" <<EOF
version: '3.8'

services:
  outline-server:
    image: ${SB_IMAGE}
    container_name: outline-server
    restart: always
    # Force root user to avoid ID mapping issues
    user: "0:0"
    # Explicit security options to handle ID mapping issues
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
      - no-new-privileges:false
    privileged: true
    platform: ${DOCKER_PLATFORM}
    # Additional comments kept for documentation purposes
    volumes:
      - ./outline-server/config.json:/etc/shadowsocks-libev/config.json:Z
      - ./outline-server/access.json:/etc/shadowsocks-libev/access.json:Z
      - ./outline-server/data:/opt/outline/data:Z
      - ./outline-server/persisted-state:/opt/outline/persisted-state:Z
      # Add explicit volume mounts for all subdirectories to ensure they're accessible
      - ./outline-server/persisted-state/prometheus:/opt/outline/persisted-state/prometheus:Z
      - ./outline-server/persisted-state/shadowbox:/opt/outline/persisted-state/shadowbox:Z
      # Add a direct mount for the root directory structure to fix the TypeError issue
      - ./outline-server/tmp_root:/root:Z
      - ./logs/outline:/var/log/shadowsocks:Z
    ports:
      - "${OUTLINE_PORT}:${OUTLINE_PORT}/tcp"
      - "${OUTLINE_PORT}:${OUTLINE_PORT}/udp"
    environment:
      - SS_CONFIG=/etc/shadowsocks-libev/config.json
      - SB_PUBLIC_IP=${SERVER_IP:-localhost}
      - SB_API_PORT=${API_PORT}
      # Explicitly define all necessary environment variables
      - SB_STATE_DIR=/opt/outline/persisted-state
      - SB_METRICS_URL=https://prod.metrics.getoutline.org
      - PROMETHEUS_CONFIG_PATH=/opt/outline/persisted-state/prometheus/config.yml
      # Explicitly disable metrics reporting if causing issues
      - SB_METRICS_URL_MANUAL_MODE=disable
      # Add path to metrics file to prevent "path must be a string" error
      - METRICS_PATH=/opt/outline/persisted-state/metrics_state
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
      
  v2ray:
    image: ${V2RAY_IMAGE}
    container_name: v2ray
    restart: always
    # Force root user to avoid ID mapping issues
    user: "0:0"
    # Explicit security options to handle ID mapping issues
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
      - no-new-privileges:false
    privileged: true
    platform: ${DOCKER_PLATFORM}
    ports:
      - "${V2RAY_PORT}:${V2RAY_PORT}/tcp"
      - "${V2RAY_PORT}:${V2RAY_PORT}/udp"
    volumes:
      - ./v2ray/config.json:/etc/v2ray/config.json:Z
      - ./logs/v2ray:/var/log/v2ray:Z
    command: run -c /etc/v2ray/config.json
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    depends_on:
      - outline-server

  watchtower:
    image: ${WATCHTOWER_IMAGE}
    container_name: watchtower
    restart: always
    # Force root user to avoid ID mapping issues
    user: "0:0"
    # Explicit security options to handle ID mapping issues
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
      - no-new-privileges:false
    privileged: true
    # No platform specification for watchtower to allow Docker to automatically select the correct platform
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: --cleanup --tlsverify --interval 3600
    depends_on:
      - outline-server
      - v2ray

networks:
  default:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.16.238.0/24
    driver_opts:
      com.docker.network.bridge.name: vpn-network
      com.docker.network.bridge.enable_icc: "true"
      com.docker.network.bridge.enable_ip_masquerade: "true"
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
    
    # Allow Outline API port if different from Outline port
    if [ "${API_PORT}" != "${OUTLINE_PORT}" ]; then
        ufw allow ${API_PORT}/tcp
        ufw allow ${API_PORT}/udp
    fi
    
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

    # Export SERVER_IP for Docker Compose environment variable substitution
    # Try multiple methods to get a reliable server IP address
    SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null ||
                ip route get 1.1.1.1 | awk '{print $7}' 2>/dev/null ||
                echo "localhost")
    export SERVER_IP
    
    info "Using server IP for Docker Compose: ${SERVER_IP}"
    
    # First, ensure any old containers are properly removed
    info "Cleaning up any old containers..."
    docker-compose down --remove-orphans 2>/dev/null || true
    docker rm -f outline-server v2ray watchtower 2>/dev/null || true
    
    # Check Docker system
    info "Verifying Docker system status..."
    docker system info >/dev/null || {
        warn "Docker system issue detected. Attempting to restart Docker service..."
        systemctl restart docker
        sleep 10
    }
    
    # Start services with retry mechanism
    local max_attempts=3
    local attempt=1
    local success=false
    
    while [ $attempt -le $max_attempts ] && [ "$success" = "false" ]; do
        info "Starting VPN services (attempt $attempt of $max_attempts)..."
        
        # Create any missing directories and files with valid content before starting
        mkdir -p "${OUTLINE_DIR}/persisted-state/prometheus"
        mkdir -p "${OUTLINE_DIR}/persisted-state/shadowbox"
        
        # Fill with valid content
        echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/metrics.json"
        echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/servers.json"
        echo "[]" > "${OUTLINE_DIR}/persisted-state/shadowbox/access_keys.json"
        
        cat > "${OUTLINE_DIR}/persisted-state/shadowbox/server.yml" <<EOF
# Outline Server configuration
apiPort: ${API_PORT}
portForNewAccessKeys: ${OUTLINE_PORT}
hostname: ${SERVER_IP}
EOF
        
        echo "{\"lastUpdated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${OUTLINE_DIR}/persisted-state/metrics_state"
        
        # Ensure permissions are correct
        find "${OUTLINE_DIR}/persisted-state" -type d -exec chmod 755 {} \;
        find "${OUTLINE_DIR}/persisted-state" -type f -exec chmod 644 {} \;
        
        if docker-compose up -d; then
            # Give services a moment to start
            sleep 10
            
            # Check if services are running
            if docker-compose ps | grep -q "Up"; then
                info "VPN services started successfully on attempt $attempt"
                success=true
            else
                warn "Services not running after docker-compose up. Checking container logs..."
                docker-compose logs
                
                # Check for specific user namespace errors
                if docker-compose logs 2>&1 | grep -q "cannot be mapped to a host ID"; then
                    warn "User namespace mapping error detected. Applying fix..."
                    
                    # Apply additional fix - pull images first with explicit disabling of user namespaces
                    docker pull --security-opt=no-new-privileges:false --security-opt=apparmor:unconfined ${SB_IMAGE}
                    docker pull --security-opt=no-new-privileges:false --security-opt=apparmor:unconfined ${V2RAY_IMAGE}
                    # Pull watchtower without platform constraint to let Docker auto-select the correct architecture
                    docker pull --security-opt=no-new-privileges:false --security-opt=apparmor:unconfined ${WATCHTOWER_IMAGE}
                    
                    # Remove failed containers
                    docker-compose down --remove-orphans
                    sleep 5
                # Check for Outline Server hostname configuration errors
                elif docker-compose logs outline-server 2>&1 | grep -q "Need to specify hostname in shadowbox_server_config.json"; then
                    warn "Outline Server hostname configuration error detected. Applying fix..."
                    
                    # Apply fix for Outline Server - ensure hostname is properly set
                    # Using same improved IP detection logic as configure_outline function
                    local server_ip=""
                    
                    # Method 1: Try hostname command (most reliable for local network)
                    server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
                    
                    # Method 2: Try ip route command as fallback
                    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
                        server_ip=$(ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null)
                        info "Using IP from ip route command: ${server_ip}"
                    fi
                    
                    # Method 3: Only try external services as very last resort
                    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
                        # Check if we have internet connectivity before attempting external service
                        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
                            server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null ||
                                      curl -4 -s --connect-timeout 5 icanhazip.com 2>/dev/null)
                            info "Using IP from external service: ${server_ip}"
                        fi
                    fi
                    
                    # Final fallback if all methods fail
                    if [ -z "$server_ip" ]; then
                        warn "Could not determine server IP address. Using localhost as fallback."
                        server_ip="127.0.0.1"
                    fi
                    
                    info "Using server IP address: $server_ip for Outline Server"
                    
                    # Create or update the shadowbox_server_config.json file
                    mkdir -p "${OUTLINE_DIR}/data"
                    # Generate a random API prefix for security
                    local api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)
                    
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
                    
                    # Create persisted-state directory specifically for Outline SB_STATE_DIR environment variable
                    mkdir -p "${OUTLINE_DIR}/persisted-state"
                    
                    # Create a copy of the config in the persisted-state directory
                    cp "${OUTLINE_DIR}/data/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
                    chmod 600 "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
                    
                    # Export updated server IP for docker-compose
                    export SERVER_IP="${server_ip}"
                    
                    # Remove failed containers
                    docker-compose down --remove-orphans
                    sleep 5
                fi
            fi
        else
            warn "docker-compose up command failed"
        fi
        
        if [ "$success" = "false" ]; then
            warn "Attempt $attempt failed. Waiting before retry..."
            sleep 10
            attempt=$((attempt + 1))
        fi
    done
    
    # Final check after all attempts
    if [ "$success" = "false" ]; then
        error "Failed to start VPN services after $max_attempts attempts. Please check Docker configuration."
    fi
    
    info "Container status:"
    docker ps
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

# Generate Outline Management JSON for connecting to the server
generate_outline_management_json() {
    info "Generating Outline Management JSON..."
    
    local server_ip=$(hostname -I | awk '{print $1}')
    local api_port="${API_PORT:-${OUTLINE_PORT}}"
    local sb_api_prefix=""
    
    # Check if we have a persisted config with an API prefix
    if [ -f "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json" ]; then
        # Try to get the API prefix if one exists
        sb_api_prefix=$(docker exec -i outline-server cat /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null |
            grep -o '"apiPrefix":[^,}]*' | cut -d'"' -f4 || echo "")
    fi
    
    # If container isn't running or doesn't have apiPrefix, check if we can find it in the access.txt
    if [ -z "$sb_api_prefix" ] && [ -f "${OUTLINE_DIR}/data/access.txt" ]; then
        sb_api_prefix=$(grep -o 'apiUrl:[^"]*' "${OUTLINE_DIR}/data/access.txt" |
            sed -E 's|apiUrl:https://[^:]+:[0-9]+/([^/]+).*|\1|' || echo "")
    fi
    
    # If we still don't have a prefix, use 'access'
    sb_api_prefix=${sb_api_prefix:-"access"}
    
    # Get or generate the certificate hash
    local cert_sha256=""
    if [ -f "${OUTLINE_DIR}/data/access.txt" ]; then
        cert_sha256=$(grep "certSha256:" "${OUTLINE_DIR}/data/access.txt" | sed "s/certSha256://")
    fi
    
    # If we couldn't find a cert hash, try to get it from the certificate file
    if [ -z "$cert_sha256" ] && [ -f "${OUTLINE_DIR}/persisted-state/shadowbox-selfsigned.crt" ]; then
        # Extract the SHA-256 fingerprint using openssl and format it correctly
        local cert_fingerprint=$(openssl x509 -in "${OUTLINE_DIR}/persisted-state/shadowbox-selfsigned.crt" -noout -sha256 -fingerprint 2>/dev/null)
        if [ ! -z "$cert_fingerprint" ]; then
            cert_sha256=$(echo ${cert_fingerprint#*=} | tr --delete : | tr '[:upper:]' '[:lower:]')
        fi
    fi
    
    # If we still don't have a cert hash, generate a placeholder
    if [ -z "$cert_sha256" ]; then
        warn "Could not find certificate fingerprint. Using placeholder."
        cert_sha256="<CERTIFICATE_NOT_AVAILABLE>"
    fi
    
    # Construct the JSON
    local api_url="https://${server_ip}:${api_port}/${sb_api_prefix}"
    
    echo ""
    echo "CONGRATULATIONS! Your Outline server is up and running."
    echo ""
    echo "To manage your Outline server, please copy the following line (including curly"
    echo "brackets) into Step 2 of the Outline Manager interface:"
    echo ""
    echo -e "\033[1;32m{\"apiUrl\":\"${api_url}\",\"certSha256\":\"${cert_sha256}\"}\033[0m"
    echo ""
    echo "Make sure the following ports are open in your firewall:"
    echo "- Management port ${api_port}, for TCP"
    echo "- Access keys port ${OUTLINE_PORT}, for TCP and UDP"
    echo ""
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

# Ensure Outline Server configuration is valid
ensure_outline_config() {
    info "Ensuring Outline Server configuration is valid..."
    
    # Get server hostname/IP using the improved detection logic
    local server_ip=""
    
    # Method 1: Try hostname command (most reliable for local network)
    server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    
    # Method 2: Try ip route command as fallback
    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
        server_ip=$(ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null)
        info "Using IP from ip route command: ${server_ip}"
    fi
    
    # Method 3: Only try external services as very last resort
    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
        # Check if we have internet connectivity before attempting external service
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null ||
                      curl -4 -s --connect-timeout 5 icanhazip.com 2>/dev/null)
            info "Using IP from external service: ${server_ip}"
        fi
    fi
    
    # Final fallback if all methods fail
    if [ -z "$server_ip" ]; then
        warn "Could not determine server IP address. Using localhost as fallback."
        server_ip="127.0.0.1"
    fi
    
    info "Using server IP address: $server_ip"
    
    # Create directories if they don't exist with proper permissions
    mkdir -p "${OUTLINE_DIR}/data"
    mkdir -p "${OUTLINE_DIR}/persisted-state/prometheus"
    chmod 700 "${OUTLINE_DIR}/data"
    chmod 700 "${OUTLINE_DIR}/persisted-state"
    
    # The "TypeError: path must be a string or Buffer" error occurs when
    # the server tries to read the configuration file but it's missing or invalid
    
    # Generate a random API prefix for security
    local api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)
    
    # Create the shadowbox_server_config.json file in both locations
    # to ensure it exists in both the data and persisted-state directories
    info "Creating shadowbox_server_config.json in ${OUTLINE_DIR}/data and ${OUTLINE_DIR}/persisted-state"
    
    # Create the config file with apiPort parameter correctly set
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
    
    # Copy to persisted-state directory
    cp "${OUTLINE_DIR}/data/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
    chmod 600 "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
    
    # Create an empty access.txt file if it doesn't exist (needed by some container configurations)
    if [ ! -f "${OUTLINE_DIR}/data/access.txt" ]; then
        touch "${OUTLINE_DIR}/data/access.txt"
        chmod 600 "${OUTLINE_DIR}/data/access.txt"
    fi
    
    # Create a persisted-state copy of access.txt if it doesn't exist
    if [ ! -f "${OUTLINE_DIR}/persisted-state/access.txt" ]; then
        cp "${OUTLINE_DIR}/data/access.txt" "${OUTLINE_DIR}/persisted-state/access.txt" 2>/dev/null || touch "${OUTLINE_DIR}/persisted-state/access.txt"
        chmod 600 "${OUTLINE_DIR}/persisted-state/access.txt"
    fi
    
    # Ensure all directories have proper permissions
    info "Setting proper permissions on all configuration directories"
    find "${OUTLINE_DIR}/persisted-state" -type d -exec chmod 755 {} \;
    find "${OUTLINE_DIR}/data" -type d -exec chmod 755 {} \;
    
    # Ensure the prometheus directory exists and has the config file
    if [ ! -d "${OUTLINE_DIR}/persisted-state/prometheus" ]; then
        mkdir -p "${OUTLINE_DIR}/persisted-state/prometheus"
        chmod 755 "${OUTLINE_DIR}/persisted-state/prometheus"
    fi
    
    # Create files that main.js at line 163 might be trying to access
    # These are additional files that might be needed based on the error message
    mkdir -p "${OUTLINE_DIR}/persisted-state/shadowbox"
    echo "{}" > "${OUTLINE_DIR}/persisted-state/metrics.json"
    echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/metrics_transfer"
    echo "{\"lastUpdated\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${OUTLINE_DIR}/persisted-state/metrics_state"
    echo "{\"version\":1}" > "${OUTLINE_DIR}/persisted-state/metrics_metadata"
    
    # Create metrics.json in multiple possible locations to ensure it's found
    mkdir -p "${OUTLINE_DIR}/tmp_root/shadowbox/app/server"
    echo "{\"metricsEnabled\": true, \"lastUpdated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics.json"
    echo "{\"metricsEnabled\": true, \"lastUpdated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${OUTLINE_DIR}/persisted-state/metrics.json"
    
    # Give these files liberal permissions to ensure they can be read
    chmod 666 "${OUTLINE_DIR}/persisted-state/metrics.json"
    chmod 666 "${OUTLINE_DIR}/persisted-state/shadowbox/metrics_transfer"
    chmod 666 "${OUTLINE_DIR}/persisted-state/metrics_state"
    chmod 666 "${OUTLINE_DIR}/persisted-state/metrics_metadata"
    chmod -R 777 "${OUTLINE_DIR}/tmp_root"
    
    if [ ! -f "${OUTLINE_DIR}/persisted-state/prometheus/config.yml" ]; then
        cat > "${OUTLINE_DIR}/persisted-state/prometheus/config.yml" <<EOF
# Basic Prometheus configuration for Outline server
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'outline'
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'outline-node-metrics'
    static_configs:
      - targets: ['127.0.0.1:9091']

  - job_name: 'outline-ss-server'
    static_configs:
      - targets: ['127.0.0.1:9092']
EOF
        chmod 644 "${OUTLINE_DIR}/persisted-state/prometheus/config.yml"
    fi
    
    # Export the server IP for later use in docker-compose
    export SERVER_IP="${server_ip}"
    
    info "Shadowbox configuration files created successfully"
    return 0
}

# Perform health check with additional file checks
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
    
    # Ensure Outline configuration is valid
    ensure_outline_config
    
    # Check critical files explicitly before checking containers
    info "Checking critical configuration files..."
    for file in "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/prometheus/config.yml"; do
        if [ ! -f "$file" ]; then
            warn "Missing critical file: $file - recreating it now"
            ensure_outline_config  # Run again to ensure files are created
            sleep 2
        else
            info "Found critical file: $file"
        fi
    done
    
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
    
    # Check API port if different from Outline port
    if [ "${API_PORT}" != "${OUTLINE_PORT}" ] && ! netstat -tuln | grep -q ":${API_PORT}"; then
        warn "Outline API port ${API_PORT} is not listening"
        docker logs outline-server
        warn "API management functionality may not work correctly"
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
    echo "- Outline API port: $API_PORT"
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
    # Fix any potential issues with the directory structure and configuration files
    ensure_outline_config
    
    # Create explicit directory structure matching the error path in the container
    # This is fixing the "must be a string or Buffer" error at line 163
    info "Creating specific file structures for the container..."
    mkdir -p "${OUTLINE_DIR}/tmp_root/shadowbox/app/server"
    
    # Create multiple potential files that might be accessed at line 163
    echo '{"metricsEnabled": true}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics_config.json"
    echo '{"lastUpdated": "2025-05-20T00:00:00Z"}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics_state.json"
    echo '{}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics.json"
    echo '{}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics_data.json"
    
    # Set very permissive permissions
    chmod -R 777 "${OUTLINE_DIR}/tmp_root"
    
    # Start services after ensuring configuration is correct
    start_services
    # Check for TypeError in docker logs and fix if needed
    if docker logs outline-server 2>&1 | grep -q "TypeError: path must be a string or Buffer"; then
        warn "Detected 'TypeError: path must be a string or Buffer' error. Applying fix..."
        
        # This error occurs when the configuration file path is missing or invalid
        # Creating both data and persisted-state directories and properly populating them
        mkdir -p "${OUTLINE_DIR}/data"
        mkdir -p "${OUTLINE_DIR}/persisted-state/prometheus"
        
        # Get server IP address using multiple methods for reliability
        local server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null ||
                        ip route get 1.2.3.4 | awk '{print $7}' 2>/dev/null ||
                        echo "localhost")
        
        # Generate a random API prefix for security
        local api_prefix=$(head -c 16 /dev/urandom | base64 | tr '/+' '_-' | tr -d '=' | head -c 8)
        
        # Create the config file in both locations to ensure the server can find it
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
        
        # Create an identical file in the persisted-state directory
        cp "${OUTLINE_DIR}/data/shadowbox_server_config.json" "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
        chmod 600 "${OUTLINE_DIR}/persisted-state/shadowbox_server_config.json"
        
        # Restart the container to apply the fix
        docker restart outline-server
        info "Applied fix for 'TypeError: path must be a string or Buffer'. Waiting for server to restart..."
        sleep 15
        
        # Create ALL possible files with valid content
        mkdir -p "${OUTLINE_DIR}/persisted-state/shadowbox"
        
        # metrics_metadata with basic structure
        echo "{\"version\":1}" > "${OUTLINE_DIR}/persisted-state/metrics_metadata"
        
        # metrics_state with timestamp
        echo "{\"lastUpdated\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${OUTLINE_DIR}/persisted-state/metrics_state"
        
        # Files in shadowbox directory with valid JSON structures
        echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/metrics.json"
        echo "{}" > "${OUTLINE_DIR}/persisted-state/shadowbox/servers.json"
        echo "[]" > "${OUTLINE_DIR}/persisted-state/shadowbox/access_keys.json"
        
        # server.yml with basic configuration
        cat > "${OUTLINE_DIR}/persisted-state/shadowbox/server.yml" <<EOF
# Outline Server configuration
apiPort: ${API_PORT}
portForNewAccessKeys: ${OUTLINE_PORT}
hostname: ${server_ip}
metricsEnabled: true
metricsCollectionEnabled: true
EOF
        
        # Set proper permissions
        chmod 644 "${OUTLINE_DIR}/persisted-state/metrics_metadata"
        chmod 644 "${OUTLINE_DIR}/persisted-state/metrics_state"
        chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/server.yml"
        chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/metrics.json"
        chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/servers.json"
        chmod 644 "${OUTLINE_DIR}/persisted-state/shadowbox/access_keys.json"
        
        # Create the exact directory structure that matches the error path
        info "Creating specific directory structure for the main.js error fix..."
        mkdir -p "${OUTLINE_DIR}/tmp_root/shadowbox/app/server"
        
        # Create multiple potential files that might be accessed at line 163 of main.js
        echo '{"metricsEnabled": false}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics_config.json"
        echo '{"lastUpdated": "2025-05-20T00:00:00Z"}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics_state.json"
        echo '{}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics.json"
        echo '{}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/metrics_data.json"
        echo '{}' > "${OUTLINE_DIR}/tmp_root/shadowbox/app/server/serverconfig.json"
        
        # Set permissive permissions
        chmod -R 777 "${OUTLINE_DIR}/tmp_root"
        
        # Add a custom Docker run command with additional volume mount for the root directory
        docker run -d --name outline-server \
          --security-opt=no-new-privileges:false \
          --security-opt=apparmor:unconfined \
          -p ${OUTLINE_PORT}:${OUTLINE_PORT}/tcp \
          -p ${OUTLINE_PORT}:${OUTLINE_PORT}/udp \
          -v "${OUTLINE_DIR}/config.json:/etc/shadowsocks-libev/config.json:Z" \
          -v "${OUTLINE_DIR}/access.json:/etc/shadowsocks-libev/access.json:Z" \
          -v "${OUTLINE_DIR}/data:/opt/outline/data:Z" \
          -v "${OUTLINE_DIR}/persisted-state:/opt/outline/persisted-state:Z" \
          -v "${OUTLINE_DIR}/persisted-state/prometheus:/opt/outline/persisted-state/prometheus:Z" \
          -v "${OUTLINE_DIR}/persisted-state/shadowbox:/opt/outline/persisted-state/shadowbox:Z" \
          -v "${OUTLINE_DIR}/tmp_root:/root:Z" \
          -v "${LOGS_DIR}/outline:/var/log/shadowsocks:Z" \
          -e "SS_CONFIG=/etc/shadowsocks-libev/config.json" \
          -e "SB_PUBLIC_IP=${SERVER_IP:-localhost}" \
          -e "SB_API_PORT=${API_PORT}" \
          -e "SB_STATE_DIR=/opt/outline/persisted-state" \
          -e "SB_METRICS_URL=https://prod.metrics.getoutline.org" \
          -e "PROMETHEUS_CONFIG_PATH=/opt/outline/persisted-state/prometheus/config.yml" \
          -e "SB_METRICS_URL_MANUAL_MODE=disable" \
          -e "METRICS_PATH=/opt/outline/persisted-state/metrics_state" \
          --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
          --restart=always \
          ${SB_IMAGE}
          
        info "Started Outline server directly with Docker run to ensure proper volume mounting"
    fi
    health_check
    display_summary
    generate_outline_management_json
    
    info "Installation completed successfully!"
}

# Execute main function with all arguments
main "$@"