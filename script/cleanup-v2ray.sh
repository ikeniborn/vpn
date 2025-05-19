#!/bin/bash

# ===================================================================
# V2Ray Cleanup and Final Fix Script
# ===================================================================
# This script:
# - Stops any conflicting v2ray processes
# - Opens required ports in UFW
# - Restarts the container with correct configuration
# - Verifies that ports are properly listening
# ===================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
DOCKER_CONTAINER="v2ray-client"
SOCKS_PORT=11080
HTTP_PORT=18080
TPROXY_PORT=11081

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

# Find and stop any non-container v2ray processes
cleanup_processes() {
    info "Finding any v2ray processes outside of Docker..."
    
    # Get Docker container PIDs
    DOCKER_PIDS=$(docker ps -q | xargs docker inspect --format '{{.State.Pid}}' 2>/dev/null || echo "")
    
    # Find all v2ray processes
    V2RAY_PIDS=$(pgrep -f v2ray || echo "")
    
    if [ -z "$V2RAY_PIDS" ]; then
        info "No v2ray processes found outside of Docker."
        return 0
    fi
    
    # Filter out Docker container PIDs
    for PID in $V2RAY_PIDS; do
        if ! echo "$DOCKER_PIDS" | grep -q "$PID"; then
            info "Found non-Docker v2ray process: $PID. Stopping it..."
            kill -9 $PID || warn "Failed to kill process $PID"
        fi
    done
    
    # Verify that processes are stopped
    sleep 1
    V2RAY_PIDS=$(pgrep -f v2ray || echo "")
    for PID in $V2RAY_PIDS; do
        if ! echo "$DOCKER_PIDS" | grep -q "$PID"; then
            warn "Process $PID still running. Manual intervention may be required."
        fi
    done
    
    info "Cleanup of non-Docker v2ray processes completed."
}

# Open required ports in UFW
open_firewall_ports() {
    info "Opening required ports in UFW..."
    
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "active"; then
            info "UFW is active. Adding required rules..."
            
            # Add rules for required ports
            ufw allow $SOCKS_PORT/tcp
            ufw allow $HTTP_PORT/tcp
            ufw allow $TPROXY_PORT/tcp
            ufw allow $TPROXY_PORT/udp
            
            info "UFW rules added. Reloading UFW..."
            ufw reload
        else
            info "UFW is not active."
        fi
    else
        info "UFW not installed."
    fi
    
    # Add direct iptables rules to allow incoming connections
    info "Adding direct iptables rules to ensure port access..."
    
    iptables -I INPUT -p tcp --dport $SOCKS_PORT -j ACCEPT
    iptables -I INPUT -p tcp --dport $HTTP_PORT -j ACCEPT
    iptables -I INPUT -p tcp --dport $TPROXY_PORT -j ACCEPT
    iptables -I INPUT -p udp --dport $TPROXY_PORT -j ACCEPT
    
    info "Firewall ports opened."
}

# Restart Docker container
restart_container() {
    info "Restarting Docker container..."
    
    if docker ps -a | grep -q "$DOCKER_CONTAINER"; then
        info "Stopping container $DOCKER_CONTAINER..."
        docker stop "$DOCKER_CONTAINER" || true
        
        info "Starting container $DOCKER_CONTAINER..."
        docker start "$DOCKER_CONTAINER"
        
        info "Container restarted."
    else
        warn "Container $DOCKER_CONTAINER not found."
    fi
}

# Verify ports are listening
verify_ports() {
    info "Waiting for ports to start listening (15 seconds)..."
    
    for i in {1..15}; do
        sleep 1
        echo -n "."
        
        # Check if all ports are listening
        if ss -tulpn | grep -q ":$SOCKS_PORT " && \
           ss -tulpn | grep -q ":$HTTP_PORT " && \
           ss -tulpn | grep -q ":$TPROXY_PORT "; then
            echo ""
            info "All ports are now listening!"
            return 0
        fi
    done
    
    echo ""
    warn "Not all ports are listening after waiting. Current status:"
    
    if ss -tulpn | grep -q ":$SOCKS_PORT "; then
        info "✅ SOCKS port $SOCKS_PORT is listening"
    else
        warn "❌ SOCKS port $SOCKS_PORT is not listening"
    fi
    
    if ss -tulpn | grep -q ":$HTTP_PORT "; then
        info "✅ HTTP port $HTTP_PORT is listening"
    else
        warn "❌ HTTP port $HTTP_PORT is not listening"
    fi
    
    if ss -tulpn | grep -q ":$TPROXY_PORT "; then
        info "✅ Transparent proxy port $TPROXY_PORT is listening"
    else
        warn "❌ Transparent proxy port $TPROXY_PORT is not listening"
    fi
    
    return 1
}

# Test iptables routing
test_routing() {
    info "Testing iptables routing..."
    
    # Check if V2RAY chain exists
    if ! iptables -t nat -L V2RAY &>/dev/null; then
        warn "V2RAY chain does not exist in nat table."
        
        # Check if setup-tunnel-routing.sh exists
        if [ -f "/usr/local/bin/setup-tunnel-routing.sh" ]; then
            info "Running setup-tunnel-routing.sh to recreate routing rules..."
            /usr/local/bin/setup-tunnel-routing.sh
        else
            warn "setup-tunnel-routing.sh not found. Manual intervention required."
        fi
    else
        info "V2RAY chain exists in nat table."
        
        # Check for redirect rule
        if iptables -t nat -L V2RAY | grep -q "REDIRECT"; then
            info "REDIRECT rule exists in V2RAY chain."
        else
            warn "REDIRECT rule not found in V2RAY chain."
            
            # Recreate the rules
            if [ -f "/usr/local/bin/setup-tunnel-routing.sh" ]; then
                info "Running setup-tunnel-routing.sh to recreate routing rules..."
                /usr/local/bin/setup-tunnel-routing.sh
            fi
        fi
    fi
    
    # Check if PREROUTING references V2RAY chain
    if iptables -t nat -L PREROUTING | grep -q "V2RAY"; then
        info "PREROUTING references V2RAY chain."
    else
        warn "PREROUTING does not reference V2RAY chain."
        
        # Add the rule
        info "Adding V2RAY chain to PREROUTING..."
        iptables -t nat -A PREROUTING -p tcp -j V2RAY
    fi
    
    # Check for masquerade rules for Outline network
    if iptables -t nat -L POSTROUTING | grep -q "10.0.0.0/24"; then
        info "POSTROUTING rule for Outline network exists."
    else
        warn "POSTROUTING rule for Outline network not found."
        
        # Add the rule
        info "Adding POSTROUTING rule for Outline network..."
        
        # Get default interface
        DEFAULT_IFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
        
        if [ -n "$DEFAULT_IFACE" ]; then
            iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE
            info "Added POSTROUTING rule for Outline network using interface $DEFAULT_IFACE."
        else
            warn "Could not determine default interface."
        fi
    fi
    
    info "Routing check completed."
}

# Run full connection test
test_connection() {
    info "Testing v2ray proxy connection..."
    
    # Test through HTTP proxy
    info "Testing HTTP proxy..."
    curl -s -m 10 -x "http://127.0.0.1:$HTTP_PORT" https://ifconfig.me
    
    info "Testing SOCKS proxy..."
    curl -s -m 10 --socks5 "127.0.0.1:$SOCKS_PORT" https://ifconfig.me
    
    info "Connection tests completed."
}

# Main function
main() {
    info "====================================================================="
    info "V2Ray Cleanup and Final Fix Script"
    info "====================================================================="
    
    check_root
    cleanup_processes
    open_firewall_ports
    restart_container
    verify_ports
    test_routing
    test_connection
    
    info "====================================================================="
    info "Cleanup and final fix completed!"
    info "If everything is working correctly, you should be able to run:"
    info "sudo ./script/test-tunnel-connection.sh --server-type server2 --server1-address YOUR_SERVER1_IP"
    info "====================================================================="
}

main "$@"