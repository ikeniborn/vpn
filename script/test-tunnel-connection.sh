#!/bin/bash

# ===================================================================
# Tunnel Connection Testing Script
# ===================================================================
# This script:
# - Tests connectivity between Server 1 and Server 2
# - Verifies proper routing and tunnel configuration
# - Performs diagnostics to identify common issues
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
SERVER_TYPE="server2"  # Options: server1, server2
SERVER1_ADDRESS=""
CONFIG_DIR="/opt/v2ray"
DOCKER_CONTAINER="v2ray-client"
DETAILED=false

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    return 1
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script tests the connectivity between Server 1 and Server 2 for the VLESS+Reality tunnel.

Options:
  --server-type TYPE      Server type to test: server1 or server2 (default: server2)
  --server1-address ADDR  Address of Server 1 (required for server2 testing)
  --config-dir DIR        Directory with v2ray config (default: /opt/v2ray)
  --container NAME        Name of the v2ray Docker container (default: v2ray-client)
  --detailed              Show detailed diagnostic information
  --help                  Display this help message

Example:
  $(basename "$0") --server-type server2 --server1-address 123.45.67.89 --detailed

EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --server-type)
                SERVER_TYPE="$2"
                shift
                ;;
            --server1-address)
                SERVER1_ADDRESS="$2"
                shift
                ;;
            --config-dir)
                CONFIG_DIR="$2"
                shift
                ;;
            --container)
                DOCKER_CONTAINER="$2"
                shift
                ;;
            --detailed)
                DETAILED=true
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

    # Validate server type
    if [[ "$SERVER_TYPE" != "server1" && "$SERVER_TYPE" != "server2" ]]; then
        error "Invalid server type: $SERVER_TYPE. Must be 'server1' or 'server2'."
        exit 1
    fi

    # For server2, we need the address of server1
    if [[ "$SERVER_TYPE" == "server2" && -z "$SERVER1_ADDRESS" ]]; then
        error "Server 1 address is required when testing from Server 2."
        echo "Use --server1-address to specify the address of Server 1."
        exit 1
    fi

    info "Configuration:"
    info "- Server type: $SERVER_TYPE"
    if [[ "$SERVER_TYPE" == "server2" ]]; then
        info "- Server 1 address: $SERVER1_ADDRESS"
    fi
    info "- Config directory: $CONFIG_DIR"
    info "- Docker container: $DOCKER_CONTAINER"
}

# Verify IP forwarding is enabled
verify_ip_forwarding() {
    info "Checking if IP forwarding is enabled..."
    
    local ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
    
    if [ "$ip_forward" -eq 1 ]; then
        info "✅ IP forwarding is enabled."
        return 0
    else
        error "❌ IP forwarding is not enabled (value: $ip_forward)."
        info "  To enable IP forwarding, run:"
        info "  echo 1 > /proc/sys/net/ipv4/ip_forward"
        info "  sysctl -w net.ipv4.ip_forward=1"
        return 1
    fi
}

# Check Docker container status
check_container_status() {
    info "Checking Docker container status..."
    
    if ! command -v docker &>/dev/null; then
        error "❌ Docker is not installed."
        return 1
    fi
    
    if [ -z "$(docker ps -q -f name=^$DOCKER_CONTAINER$)" ]; then
        error "❌ Docker container '$DOCKER_CONTAINER' is not running."
        
        if [ -n "$(docker ps -a -q -f name=^$DOCKER_CONTAINER$)" ]; then
            info "  Container exists but is not running. Check logs:"
            docker logs "$DOCKER_CONTAINER" | tail -n 10
        else
            info "  Container does not exist."
        fi
        
        return 1
    else
        info "✅ Docker container '$DOCKER_CONTAINER' is running."
        return 0
    fi
}

# Check v2ray configuration
check_v2ray_config() {
    info "Checking v2ray configuration..."
    
    local config_file="$CONFIG_DIR/config.json"
    
    if [ ! -f "$config_file" ]; then
        error "❌ Configuration file not found: $config_file"
        return 1
    fi
    
    info "✅ Configuration file exists: $config_file"
    
    # Validate JSON if jq is available
    if command -v jq &>/dev/null; then
        if jq empty "$config_file" 2>/dev/null; then
            info "✅ Configuration file is valid JSON."
        else
            error "❌ Configuration file is not valid JSON."
            return 1
        fi
    fi
    
    return 0
}

# Check listening ports
check_listening_ports() {
    info "Checking listening ports..."
    
    if [[ "$SERVER_TYPE" == "server2" ]]; then
        # Check for HTTP, SOCKS, and dokodemo-door ports
        # Using grep with extended regex to check for either 0.0.0.0:port or 127.0.0.1:port
        if ss -tulpn | grep -E "((0.0.0.0|127.0.0.1):18080) "; then
            info "✅ HTTP proxy port 18080 is listening."
        else
            warn "⚠️ HTTP proxy port 18080 is not listening."
            info "  Checking Docker container logs (last 15 lines for $DOCKER_CONTAINER):"
            docker logs "$DOCKER_CONTAINER" --tail 15
            info "  Checking V2Ray error log on host (/var/log/v2ray/error.log) (last 15 lines):"
            if [ -f "/var/log/v2ray/error.log" ]; then tail -n 15 "/var/log/v2ray/error.log"; else warn "  /var/log/v2ray/error.log not found on host."; fi
        fi
        
        if ss -tulpn | grep -E "((0.0.0.0|127.0.0.1):11080) "; then
            info "✅ SOCKS proxy port 11080 is listening."
        else
            warn "⚠️ SOCKS proxy port 11080 is not listening."
            info "  Checking Docker container logs (last 15 lines for $DOCKER_CONTAINER):"
            docker logs "$DOCKER_CONTAINER" --tail 15
            info "  Checking V2Ray error log on host (/var/log/v2ray/error.log) (last 15 lines):"
            if [ -f "/var/log/v2ray/error.log" ]; then tail -n 15 "/var/log/v2ray/error.log"; else warn "  /var/log/v2ray/error.log not found on host."; fi
        fi
        
        if ss -tulpn | grep -E "((0.0.0.0|127.0.0.1):11081) "; then
            info "✅ Transparent proxy port 11081 is listening."
        else
            error "❌ Transparent proxy port 11081 is not listening." # Keep as error for this critical port
            info "  This port is critical for transparent routing."
            info "  Checking Docker container logs (last 15 lines for $DOCKER_CONTAINER):"
            docker logs "$DOCKER_CONTAINER" --tail 15
            info "  Checking V2Ray error log on host (/var/log/v2ray/error.log) (last 15 lines):"
            if [ -f "/var/log/v2ray/error.log" ]; then tail -n 15 "/var/log/v2ray/error.log"; else warn "  /var/log/v2ray/error.log not found on host."; fi
            
            # Provide a suggestion for restarting
            info "  Try restarting the v2ray container:"
            info "  docker restart $DOCKER_CONTAINER"
            return 1
        fi
    else
        # Check VLESS port for Server 1
        if ss -tulpn | grep -q ":443 "; then
            info "✅ VLESS port 443 is listening."
        else
            warn "⚠️ VLESS port 443 is not listening."
        fi
    fi
    
    return 0
}

# Check iptables rules
check_iptables_rules() {
    info "Checking iptables rules..."
    
    if [[ "$SERVER_TYPE" == "server1" ]]; then
        # Check for masquerade rule
        if iptables -t nat -L POSTROUTING | grep -q 'MASQUERADE'; then
            info "✅ POSTROUTING masquerade rule is configured."
            
            # Check for Outline subnet rule
            if iptables -t nat -L POSTROUTING | grep -q '10.0.0.0/24'; then
                info "✅ POSTROUTING rule for Outline VPN subnet is configured."
            else
                warn "⚠️ POSTROUTING rule for Outline VPN subnet is missing."
            fi
        else
            error "❌ POSTROUTING masquerade rule is missing."
            return 1
        fi
    else
        # Check for V2RAY chain
        if iptables -t nat -L | grep -q 'V2RAY'; then
            info "✅ V2RAY chain exists in nat table."
            
            # Check for PREROUTING rule
            if iptables -t nat -L PREROUTING | grep -q 'V2RAY'; then
                info "✅ PREROUTING rule references V2RAY chain."
            else
                error "❌ PREROUTING rule does not reference V2RAY chain."
                return 1
            fi
            
            # Check for Outline subnet rules
            if iptables -t nat -L PREROUTING | grep -q '10.0.0.0/24'; then
                info "✅ PREROUTING rule for Outline VPN subnet exists."
            else
                warn "⚠️ PREROUTING rule for Outline VPN subnet is missing."
            fi
            
            # Check for masquerade rule with correct interface
            if iptables -t nat -L POSTROUTING | grep -q 'MASQUERADE.*o lo'; then
                warn "⚠️ Masquerade rule uses loopback interface (lo) instead of outgoing interface."
            fi
        else
            error "❌ V2RAY chain not found in nat table."
            return 1
        fi
    fi
    
    return 0
}

# Test the tunnel
test_tunnel() {
    if [[ "$SERVER_TYPE" == "server2" ]]; then
        info "Testing tunnel connectivity..."
        
        # Test HTTP proxy
        local curl_output=$(curl -s -m 15 -x "http://127.0.0.1:18080" https://ifconfig.me 2>&1 || echo "Connection failed")
        
        # If first attempt fails, try with 0.0.0.0
        if [[ "$curl_output" == *"Connection failed"* || "$curl_output" == *"timed out"* ]]; then
            info "  Initial connection failed, trying with direct server IP..."
            curl_output=$(curl -s -m 15 -x "http://${LOCAL_IP}:18080" https://ifconfig.me 2>&1 || echo "Connection failed")
        fi
        
        if [[ "$curl_output" != *"Connection failed"* && "$curl_output" != *"timed out"* ]]; then
            info "✅ Successfully connected through proxy!"
            info "  Your IP appears as: $curl_output"
            return 0
        else
            error "❌ Failed to connect through proxy."
            info "  Error output: $curl_output"
            return 1
        fi
    else
        info "Skipping tunnel test when running on Server 1."
        return 0
    fi
}

# Test route handling
test_route_handling() {
    if [[ "$SERVER_TYPE" == "server2" ]]; then
        info "Testing route handling..."
        
        # Source the tunnel routing configuration if available
        if [ -f "./script/tunnel-routing.conf" ]; then
            source "./script/tunnel-routing.conf"
            
            # Check if ROUTE_OUTLINE_THROUGH_TUNNEL is implemented
            if [ -n "${ROUTE_OUTLINE_THROUGH_TUNNEL+x}" ]; then
                info "✅ ROUTE_OUTLINE_THROUGH_TUNNEL flag found: $ROUTE_OUTLINE_THROUGH_TUNNEL"
                
                # Check outgoing interface for masquerading
                local interfaces=$(iptables -t nat -L POSTROUTING | grep 'MASQUERADE' | grep -o 'o [^ ]*' | awk '{print $2}')
                
                if [[ "$interfaces" == *"lo"* && "$interfaces" == *""* ]]; then
                    warn "⚠️ Masquerading uses loopback interface, which is incorrect."
                    
                    # Get the correct interface
                    local correct_iface=$(ip -4 route show default | awk '{print $5}' | head -n1)
                    info "  The correct interface should be: $correct_iface"
                    return 1
                fi
            else
                warn "⚠️ ROUTE_OUTLINE_THROUGH_TUNNEL flag not found in configuration."
                return 1
            fi
        else
            warn "⚠️ tunnel-routing.conf not found."
            return 1
        fi
    fi
    
    return 0
}

# Main function
main() {
    parse_args "$@"
    
    # Run tests and record results
    verify_ip_forwarding
    
    if [[ "$SERVER_TYPE" == "server2" ]]; then
        check_container_status
    fi
    
    check_v2ray_config
    check_listening_ports
    check_iptables_rules
    
    if [[ "$SERVER_TYPE" == "server2" ]]; then
        test_tunnel
        test_route_handling
    fi
    
    info "========== TUNNEL CONNECTION TEST COMPLETED =========="
}

main "$@"