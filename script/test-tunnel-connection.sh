#!/bin/bash

# ===================================================================
# VLESS-Reality Tunnel Test Script
# ===================================================================
# This script:
# - Tests connectivity between Server 1 and Server 2
# - Verifies that traffic is routing through the tunnel
# - Checks Outline VPN connectivity
# - Diagnoses common tunnel issues
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SERVER_TYPE=""
SERVER1_ADDRESS=""
V2RAY_DIR="/opt/v2ray"
OUTLINE_PORT="7777"

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

success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script tests the tunnel connection between Server 1 and Server 2.

Required Options:
  --server-type TYPE       Specify "server1" or "server2"

For Server 2 testing:
  --server1-address ADDR   Server 1 hostname or IP address

Optional Options:
  --outline-port PORT      Port for Outline VPN (default: 7777)
  --help                   Display this help message

Example:
  $(basename "$0") --server-type server1
  $(basename "$0") --server-type server2 --server1-address 123.45.67.89

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
    if [ -z "$SERVER_TYPE" ]; then
        error "Server type is required. Use --server-type option."
        display_usage
        exit 1
    fi

    if [ "$SERVER_TYPE" != "server1" ] && [ "$SERVER_TYPE" != "server2" ]; then
        error "Server type must be 'server1' or 'server2'."
        display_usage
        exit 1
    fi

    if [ "$SERVER_TYPE" == "server2" ] && [ -z "$SERVER1_ADDRESS" ]; then
        error "Server 1 address is required for Server 2 testing. Use --server1-address option."
        display_usage
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check if Docker is running
check_docker() {
    info "Checking Docker status..."
    if ! command_exists docker; then
        error "Docker is not installed."
        return 1
    fi

    if ! docker info &> /dev/null; then
        error "Docker is not running or you don't have permission to use it."
        return 1
    fi

    success "Docker is running properly."
    return 0
}

# Function to check if v2ray is running
check_v2ray() {
    local container_name="v2ray"
    
    if [ "$SERVER_TYPE" == "server2" ]; then
        container_name="v2ray-client"
    fi
    
    info "Checking $container_name container status..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
        error "$container_name container is not running."
        
        # Check if container exists but is not running
        if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            warn "$container_name container exists but is not running."
            echo "You can start it with: docker start $container_name"
        else
            warn "$container_name container does not exist."
            if [ "$SERVER_TYPE" == "server1" ]; then
                echo "Run setup-vless-server1.sh to configure Server 1."
            else
                echo "Run setup-vless-server2.sh to configure Server 2."
            fi
        fi
        
        return 1
    fi
    
    success "$container_name container is running."
    
    # Check logs for errors
    info "Checking $container_name logs for errors..."
    if docker logs "$container_name" 2>&1 | grep -i "error\|fatal\|panic" > /dev/null; then
        warn "Found potential errors in $container_name logs:"
        docker logs "$container_name" 2>&1 | grep -i "error\|fatal\|panic" | head -n 5
        echo "Check full logs with: docker logs $container_name"
    else
        success "No obvious errors found in $container_name logs."
    fi
    
    return 0
}

# Function to test IP forwarding
test_ip_forwarding() {
    info "Testing IP forwarding configuration..."
    
    local ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$ip_forward" != "1" ]; then
        error "IP forwarding is not enabled. Should be 1, but is $ip_forward."
        echo "Enable with: echo 1 > /proc/sys/net/ipv4/ip_forward"
        echo "And make it permanent by adding net.ipv4.ip_forward=1 to /etc/sysctl.conf"
        return 1
    fi
    
    success "IP forwarding is enabled."
    return 0
}

# Function to test network connectivity
test_connectivity() {
    if [ "$SERVER_TYPE" == "server1" ]; then
        info "Server 1: Testing external connectivity..."
        
        # Test outbound internet connectivity
        if ! curl -s --connect-timeout 5 https://ifconfig.me > /dev/null; then
            error "Cannot connect to the internet. Check network configuration."
            return 1
        fi
        
        success "Server 1 has internet connectivity."
        
        # Display external IP
        local external_ip=$(curl -s --connect-timeout 5 https://ifconfig.me)
        info "Server 1 external IP: $external_ip"
        
        return 0
    else
        # Server 2 tests
        info "Server 2: Testing tunnel connectivity to Server 1..."
        
        # Test connection to Server 1
        if ! ping -c 3 "$SERVER1_ADDRESS" > /dev/null; then
            error "Cannot ping Server 1 at $SERVER1_ADDRESS. Check network configuration."
            return 1
        fi
        
        success "Server 2 can reach Server 1."
        
        # Test the proxy connection 
        info "Testing proxy connection through tunnel..."
        if ! command_exists curl; then
            warn "curl not installed. Cannot test proxy connection."
            return 1
        fi
        
        # Test HTTP proxy
        local proxy_ip=$(curl -s --connect-timeout 10 -x http://127.0.0.1:8080 https://ifconfig.me 2>/dev/null)
        local direct_ip=$(curl -s --connect-timeout 10 https://ifconfig.me 2>/dev/null)
        
        if [ -z "$proxy_ip" ]; then
            error "Proxy connection through tunnel failed. Check v2ray-client configuration."
            return 1
        fi
        
        if [ "$proxy_ip" == "$direct_ip" ]; then
            warn "Proxy connection working but IP is the same as direct connection."
            warn "This suggests traffic might not be properly tunneling through Server 1."
            warn "Direct: $direct_ip, Proxy: $proxy_ip"
        else
            success "Proxy connection through tunnel is working!"
            info "Direct IP: $direct_ip, Tunneled IP: $proxy_ip"
        fi
        
        return 0
    fi
}

# Function to test Outline VPN (Server 2 only)
test_outline() {
    if [ "$SERVER_TYPE" != "server2" ]; then
        return 0
    fi
    
    info "Testing Outline VPN server..."
    
    # Check if Outline containers are running
    if ! docker ps --format '{{.Names}}' | grep -q "shadowbox"; then
        error "Outline server container (shadowbox) is not running."
        return 1
    fi
    
    success "Outline server container (shadowbox) is running."
    
    # Check if Outline API is responding
    if ! curl -sk https://localhost:41084/server > /dev/null; then
        warn "Outline API is not responding on port 41084."
    else
        success "Outline API is responding."
    fi
    
    # Check if Outline port is open
    local open_ports_count
    open_ports_count=$(ss -tulpn | grep ":$OUTLINE_PORT" | wc -l)
    
    if [ "$open_ports_count" -eq 0 ]; then
        warn "Outline VPN port $OUTLINE_PORT does not appear to be open. (Found $open_ports_count listening)"
    else
        success "Outline VPN port $OUTLINE_PORT is open. (Found $open_ports_count listening)"
    fi
    
    # Test if Outline is routing through the tunnel
    info "Testing if Outline traffic routes through the tunnel (requires active connection)..."
    
    local active_conns
    active_conns=$(ss -anp | grep ":$OUTLINE_PORT" | grep -Ev 'LISTEN|UNCONN' | wc -l)
    
    if [ "$active_conns" -gt 0 ]; then
        success "Outline has active connections (found $active_conns). Traffic should be routing through the tunnel."
    else
        warn "No active Outline connections detected (established TCP or active UDP). Cannot verify routing."
        warn "Connect a client and ensure traffic is flowing to test fully."
    fi
    
    return 0
}

# Function to check firewall rules
check_firewall() {
    info "Checking firewall configuration..."
    
    if command_exists ufw; then
        # Check UFW status
        if ! ufw status | grep -q "Status: active"; then
            warn "UFW is installed but not active."
        else
            success "UFW is active."
            
            # Check specific rules
            if [ "$SERVER_TYPE" == "server1" ]; then
                if ! ufw status | grep -q "443"; then
                    warn "UFW: No rule found for v2ray port (443)."
                fi
            else
                if ! ufw status | grep -q "$OUTLINE_PORT"; then
                    warn "UFW: No rule found for Outline VPN port ($OUTLINE_PORT)."
                fi
                
                if ! ufw status | grep -q "41084"; then
                    warn "UFW: No rule found for Outline API port (41084)."
                fi
            fi
        fi
    else
        # Check iptables
        if ! command_exists iptables; then
            warn "Neither UFW nor iptables-save found. Cannot check firewall rules."
            return 1
        fi
        
        # Check for masquerading rules (NAT)
        if ! iptables -t nat -L POSTROUTING | grep -q "MASQUERADE"; then
            warn "No masquerading rules found in iptables. Traffic forwarding may not work."
        else
            success "iptables masquerading rules found."
        fi
        
        if [ "$SERVER_TYPE" == "server2" ]; then
            # Check for redirection to v2ray (transparent proxy)
            if ! iptables -t nat -L | grep -q "REDIRECT.*1081"; then
                warn "No redirection rules to v2ray transparent proxy found."
                warn "Traffic may not be routed through the tunnel."
            else
                success "iptables redirection rules to v2ray found."
            fi
        fi
    fi
    
    return 0
}

# Function to display system information
show_system_info() {
    info "Collecting system information..."
    
    echo "---------- System Information ----------"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
    echo "IP Addresses: $(hostname -I)"
    
    echo "---------- Memory Usage ----------"
    free -h
    
    echo "---------- Disk Usage ----------"
    df -h | grep -v "tmpfs\|udev"
    
    echo "---------- Docker Containers ----------"
    docker ps
    
    echo "---------- Network Connections ----------"
    ss -tulpn | grep -E ":($OUTLINE_PORT|41084|443|1080|8080|1081)"
}

# Main function
main() {
    parse_args "$@"
    
    echo "====================================================================="
    if [ "$SERVER_TYPE" == "server1" ]; then
        echo "Testing VLESS-Reality Server 1 (Tunnel Entry Point)"
    else
        echo "Testing VLESS-Reality Server 2 (Traffic Source / Outline VPN)"
        echo "Server 1 Address: $SERVER1_ADDRESS"
    fi
    echo "====================================================================="
    
    # Run tests
    check_docker
    check_v2ray
    test_ip_forwarding
    test_connectivity
    check_firewall
    
    if [ "$SERVER_TYPE" == "server2" ]; then
        test_outline
    fi
    
    # Show system information
    show_system_info
    
    echo "====================================================================="
    echo "Tunnel testing completed. See above for results and recommendations."
    echo "====================================================================="
}

main "$@"