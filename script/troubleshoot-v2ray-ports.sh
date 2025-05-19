#!/bin/bash

# ===================================================================
# V2Ray Ports Troubleshooting Script
# ===================================================================
# This script:
# - Performs deep diagnostics on port binding issues
# - Checks for port conflicts
# - Verifies configuration for proper inbound settings
# - Attempts to fix common issues with v2ray port binding
# ===================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
DOCKER_CONTAINER="v2ray-client"
V2RAY_DIR="/opt/v2ray"
SOCKS_PORT=1080
HTTP_PORT=8080
TPROXY_PORT=1081

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Check if ports are already in use
check_port_usage() {
    info "Checking if ports are already in use by other processes..."
    
    local port_issues=false
    
    # Check SOCKS port
    if ss -tulpn | grep -q ":$SOCKS_PORT "; then
        local process=$(ss -tulpn | grep ":$SOCKS_PORT " | awk '{print $7}' | cut -d ":" -f 2)
        warn "SOCKS port $SOCKS_PORT is already in use by process $process"
        port_issues=true
    else
        info "SOCKS port $SOCKS_PORT is available"
    fi
    
    # Check HTTP port
    if ss -tulpn | grep -q ":$HTTP_PORT "; then
        local process=$(ss -tulpn | grep ":$HTTP_PORT " | awk '{print $7}' | cut -d ":" -f 2)
        warn "HTTP port $HTTP_PORT is already in use by process $process"
        port_issues=true
    else
        info "HTTP port $HTTP_PORT is available"
    fi
    
    # Check transparent proxy port
    if ss -tulpn | grep -q ":$TPROXY_PORT "; then
        local process=$(ss -tulpn | grep ":$TPROXY_PORT " | awk '{print $7}' | cut -d ":" -f 2)
        warn "Transparent proxy port $TPROXY_PORT is already in use by process $process"
        port_issues=true
    else
        info "Transparent proxy port $TPROXY_PORT is available"
    fi
    
    if [ "$port_issues" = true ]; then
        warn "Port conflicts detected. This may prevent v2ray from binding correctly."
    else
        info "No port conflicts detected."
    fi
}

# Check firewall rules that might block ports
check_firewall() {
    info "Checking firewall rules..."
    
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        info "UFW is active. Checking rules..."
        
        # Check if ports are allowed
        local socks_allowed=$(ufw status | grep -E "$SOCKS_PORT(/tcp|/udp)")
        local http_allowed=$(ufw status | grep -E "$HTTP_PORT(/tcp|/udp)")
        local tproxy_allowed=$(ufw status | grep -E "$TPROXY_PORT(/tcp|/udp)")
        
        if [ -z "$socks_allowed" ]; then
            warn "SOCKS port $SOCKS_PORT may be blocked by UFW"
        fi
        
        if [ -z "$http_allowed" ]; then
            warn "HTTP port $HTTP_PORT may be blocked by UFW"
        fi
        
        if [ -z "$tproxy_allowed" ]; then
            warn "Transparent proxy port $TPROXY_PORT may be blocked by UFW"
        fi
        
        info "Consider running: ufw allow $SOCKS_PORT/tcp && ufw allow $HTTP_PORT/tcp && ufw allow $TPROXY_PORT/tcp"
    else
        info "UFW not active or not installed."
    fi
    
    # Check iptables directly
    info "Checking iptables rules..."
    if iptables -L INPUT -n | grep -q "DROP" || iptables -L INPUT -n | grep -q "REJECT"; then
        warn "iptables INPUT chain has DROP or REJECT rules that might block ports"
    fi
}

# Verify the v2ray configuration
verify_config() {
    info "Verifying v2ray configuration..."
    
    if [ ! -f "$V2RAY_DIR/config.json" ]; then
        error "Configuration file not found: $V2RAY_DIR/config.json"
        return 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &>/dev/null; then
        warn "jq not installed. Installing..."
        apt-get update && apt-get install -y jq
    fi
    
    # Check if the inbounds are correctly defined
    local socks_inbound=$(jq '.inbounds[] | select(.protocol == "socks")' "$V2RAY_DIR/config.json")
    local http_inbound=$(jq '.inbounds[] | select(.protocol == "http")' "$V2RAY_DIR/config.json")
    local dokodemo_inbound=$(jq '.inbounds[] | select(.protocol == "dokodemo-door")' "$V2RAY_DIR/config.json")
    
    if [ -z "$socks_inbound" ]; then
        warn "SOCKS inbound not found in configuration"
    else
        local socks_listen=$(jq -r '.inbounds[] | select(.protocol == "socks") | .listen' "$V2RAY_DIR/config.json")
        local socks_port=$(jq -r '.inbounds[] | select(.protocol == "socks") | .port' "$V2RAY_DIR/config.json")
        
        if [ "$socks_listen" = "127.0.0.1" ]; then
            warn "SOCKS inbound is configured to listen only on localhost (127.0.0.1)"
        fi
        
        info "SOCKS inbound configured: listen=$socks_listen, port=$socks_port"
    fi
    
    if [ -z "$http_inbound" ]; then
        warn "HTTP inbound not found in configuration"
    else
        local http_listen=$(jq -r '.inbounds[] | select(.protocol == "http") | .listen' "$V2RAY_DIR/config.json")
        local http_port=$(jq -r '.inbounds[] | select(.protocol == "http") | .port' "$V2RAY_DIR/config.json")
        
        if [ "$http_listen" = "127.0.0.1" ]; then
            warn "HTTP inbound is configured to listen only on localhost (127.0.0.1)"
        fi
        
        info "HTTP inbound configured: listen=$http_listen, port=$http_port"
    fi
    
    if [ -z "$dokodemo_inbound" ]; then
        warn "Dokodemo-door (transparent proxy) inbound not found in configuration"
    else
        local dokodemo_listen=$(jq -r '.inbounds[] | select(.protocol == "dokodemo-door") | .listen' "$V2RAY_DIR/config.json")
        local dokodemo_port=$(jq -r '.inbounds[] | select(.protocol == "dokodemo-door") | .port' "$V2RAY_DIR/config.json")
        
        if [ "$dokodemo_listen" = "127.0.0.1" ]; then
            warn "Dokodemo-door inbound is configured to listen only on localhost (127.0.0.1)"
        fi
        
        # Check if dokodemo-door has tproxy enabled
        local tproxy_enabled=$(jq -r '.inbounds[] | select(.protocol == "dokodemo-door") | .streamSettings.sockopt.tproxy' "$V2RAY_DIR/config.json")
        
        if [ "$tproxy_enabled" != "tproxy" ]; then
            warn "Dokodemo-door inbound does not have tproxy enabled"
        fi
        
        info "Dokodemo-door inbound configured: listen=$dokodemo_listen, port=$dokodemo_port, tproxy=$tproxy_enabled"
    fi
    
    # Verify outbound configuration
    local outbounds=$(jq '.outbounds[] | .protocol' "$V2RAY_DIR/config.json")
    
    if [ -z "$outbounds" ]; then
        warn "No outbounds found in configuration"
    else
        info "Outbounds configured: $outbounds"
    fi
}

# Check Docker container status
check_container() {
    info "Checking Docker container status..."
    
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed"
        return 1
    fi
    
    if [ -z "$(docker ps -q -f "name=^${DOCKER_CONTAINER}$")" ]; then
        warn "Container $DOCKER_CONTAINER is not running"
        
        # Check if container exists
        if [ -n "$(docker ps -a -q -f "name=^${DOCKER_CONTAINER}$")" ]; then
            info "Container exists but is not running. Checking logs:"
            docker logs "$DOCKER_CONTAINER" | tail -20
        else
            info "Container does not exist"
        fi
        
        return 1
    else
        info "Container $DOCKER_CONTAINER is running"
        
        # Check container logs
        info "Container logs:"
        docker logs "$DOCKER_CONTAINER" | tail -20
        
        # Check container network settings
        info "Container network settings:"
        docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$DOCKER_CONTAINER"
        
        return 0
    fi
}

# Try a simple test container
create_test_container() {
    info "Creating a simple test container to verify v2ray functionality..."
    
    # Create a minimal test configuration
    local test_config_dir="/tmp/v2ray-test"
    mkdir -p "$test_config_dir"
    
    cat > "$test_config_dir/config.json" << EOF
{
  "log": {
    "loglevel": "debug"
  },
  "inbounds": [
    {
      "port": 10800,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "port": 10801,
      "listen": "0.0.0.0",
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    
    # Remove any existing test container
    docker rm -f v2ray-test 2>/dev/null || true
    
    # Create the test container
    info "Starting test container..."
    docker run -d --name v2ray-test \
        -p 10800:10800 -p 10801:10801 \
        -v "$test_config_dir/config.json:/etc/v2ray/config.json" \
        v2fly/v2fly-core:latest run -config /etc/v2ray/config.json
    
    # Wait for container to start
    sleep 3
    
    # Check if container is running
    if [ -z "$(docker ps -q -f "name=^v2ray-test$")" ]; then
        error "Test container failed to start"
        docker logs v2ray-test
        return 1
    fi
    
    # Check if ports are listening
    info "Checking if test ports are listening..."
    if ss -tulpn | grep -q ":10800 "; then
        info "✅ Test SOCKS port 10800 is listening"
    else
        warn "❌ Test SOCKS port 10800 is not listening"
    fi
    
    if ss -tulpn | grep -q ":10801 "; then
        info "✅ Test HTTP port 10801 is listening"
    else
        warn "❌ Test HTTP port 10801 is not listening"
    fi
    
    # Show container logs
    info "Test container logs:"
    docker logs v2ray-test
    
    info "You can manually test with: curl -x socks5://127.0.0.1:10800 https://ifconfig.me"
    info "or: curl -x http://127.0.0.1:10801 https://ifconfig.me"
    
    return 0
}

# Create a fixed v2ray configuration
create_fixed_config() {
    info "Creating fixed v2ray configuration..."
    
    # Backup original configuration
    if [ -f "$V2RAY_DIR/config.json" ]; then
        cp "$V2RAY_DIR/config.json" "$V2RAY_DIR/config.json.bak.$(date +%s)"
    fi
    
    # Extract necessary values from existing config
    local server_address=""
    local server_port=""
    local server_id=""
    local server_sni=""
    local server_fingerprint=""
    local server_pubkey=""
    
    if [ -f "$V2RAY_DIR/config.json" ] && command -v jq &>/dev/null; then
        server_address=$(jq -r '.outbounds[] | select(.protocol == "vless") | .settings.vnext[0].address' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
        server_port=$(jq -r '.outbounds[] | select(.protocol == "vless") | .settings.vnext[0].port' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
        server_id=$(jq -r '.outbounds[] | select(.protocol == "vless") | .settings.vnext[0].users[0].id' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
        server_sni=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.serverName' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
        server_fingerprint=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.fingerprint' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
        server_pubkey=$(jq -r '.outbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.publicKey' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
    fi
    
    if [ -z "$server_address" ] || [ -z "$server_id" ]; then
        error "Could not extract server details from existing configuration"
        return 1
    fi
    
    # Create the new configuration
    cat > "$V2RAY_DIR/config.json" << EOF
{
  "log": {
    "loglevel": "debug",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "tag": "socks-inbound",
      "port": $SOCKS_PORT,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "http-inbound",
      "port": $HTTP_PORT,
      "listen": "0.0.0.0",
      "protocol": "http",
      "settings": {
        "auth": "noauth"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "transparent-inbound",
      "port": $TPROXY_PORT,
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
            "address": "$server_address",
            "port": ${server_port:-443},
            "users": [
              {
                "id": "$server_id",
                "encryption": "none",
                "flow": ""
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "${server_sni:-www.microsoft.com}",
          "fingerprint": "${server_fingerprint:-chrome}",
          "publicKey": "$server_pubkey",
          "shortId": ""
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
    info "Fixed configuration created"
    
    return 0
}

# Main function
main() {
    info "====================================================================="
    info "V2Ray Ports Troubleshooting Script"
    info "====================================================================="
    
    check_root
    check_port_usage
    check_firewall
    verify_config
    check_container
    create_test_container
    
    info "====================================================================="
    info "RECOMMENDATIONS:"
    info "====================================================================="
    info "1. If ports are already in use, stop the conflicting services."
    info "2. If fixed test container works but main container doesn't, try:"
    info "   - sudo ./script/fix-port-binding.sh --server1-address YOUR_SERVER1_IP --server1-uuid YOUR_UUID"
    info "3. If test container does not work either, try: create_fixed_config"
    info "4. Check for tproxy kernel module: modprobe xt_TPROXY"
    info "5. For networking issues, ensure the container has NET_ADMIN capability."
    info "====================================================================="
    
    # Ask user if they want to create a fixed configuration
    read -p "Do you want to create a fixed configuration? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        create_fixed_config
        
        info "Fixed configuration created. Restart the container with:"
        info "docker restart $DOCKER_CONTAINER"
    fi
    
    info "Troubleshooting completed."
}

main "$@"