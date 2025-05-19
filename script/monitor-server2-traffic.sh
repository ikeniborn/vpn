#!/bin/bash

# ===================================================================
# Server 2 Traffic Monitoring Script
# ===================================================================
# This script:
# - Monitors traffic from Outline VPN clients
# - Checks tunnel connection to Server 1
# - Verifies proper routing of traffic through Server 1
# - Provides detailed statistics and diagnostics
# ===================================================================

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
SERVER1_ADDRESS=""
INTERVAL=5
DURATION=60
MONITOR_MODE="basic"  # Options: basic, detailed, continuous
OUTPUT_FILE=""
OUTLINE_NETWORK="10.0.0.0/24"
DOCKER_CONTAINER="v2ray-client"

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

header() {
    echo -e "${BLUE}$1${NC}"
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script monitors traffic from Outline VPN clients and checks tunnel routing to Server 1.

Options:
  --server1-address ADDR  Address of Server 1 (required)
  --interval SEC          Sampling interval in seconds (default: 5)
  --duration SEC          Total monitoring duration in seconds (default: 60)
  --mode MODE             Monitoring mode: basic, detailed, continuous (default: basic)
  --outline-network CIDR  Outline VPN network CIDR (default: 10.0.0.0/24)
  --container NAME        Docker container name for v2ray client (default: v2ray-client)
  --output FILE           Save output to file
  --help                  Display this help message

Example:
  $(basename "$0") --server1-address 123.45.67.89 --mode detailed

EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --server1-address)
                SERVER1_ADDRESS="$2"
                shift
                ;;
            --interval)
                INTERVAL="$2"
                shift
                ;;
            --duration)
                DURATION="$2"
                shift
                ;;
            --mode)
                MONITOR_MODE="$2"
                shift
                ;;
            --outline-network)
                OUTLINE_NETWORK="$2"
                shift
                ;;
            --container)
                DOCKER_CONTAINER="$2"
                shift
                ;;
            --output)
                OUTPUT_FILE="$2"
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

    # Validate required parameters
    if [ -z "$SERVER1_ADDRESS" ]; then
        error "Server 1 address is required. Use --server1-address option."
    fi

    # Validate monitoring mode
    if [[ "$MONITOR_MODE" != "basic" && "$MONITOR_MODE" != "detailed" && "$MONITOR_MODE" != "continuous" ]]; then
        error "Invalid monitoring mode: $MONITOR_MODE. Must be 'basic', 'detailed', or 'continuous'."
    fi

    info "Configuration:"
    info "- Server 1 address: $SERVER1_ADDRESS"
    info "- Interval: $INTERVAL seconds"
    info "- Duration: $DURATION seconds"
    info "- Mode: $MONITOR_MODE"
    info "- Outline network: $OUTLINE_NETWORK"
    info "- Docker container: $DOCKER_CONTAINER"
    if [ -n "$OUTPUT_FILE" ]; then
        info "- Output file: $OUTPUT_FILE"
    fi
}

# Check for required tools
check_dependencies() {
    info "Checking for required tools..."
    
    local missing_tools=()
    
    for tool in tcpdump iptables netstat ss jq grep awk sort uniq docker; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        warn "Missing required tools: ${missing_tools[*]}"
        info "Installing missing tools..."
        
        apt-get update
        apt-get install -y net-tools iproute2 iptables tcpdump jq docker.io
        
        # Check again after install
        for tool in "${missing_tools[@]}"; do
            if ! command -v $tool &> /dev/null; then
                error "Failed to install $tool. Please install it manually."
            fi
        done
    fi
    
    info "All required tools are available."
}

# Check if tunnel to Server 1 is active
check_tunnel_status() {
    info "Checking tunnel connection to Server 1..."
    
    # Check Docker container status
    if ! docker ps | grep -q "$DOCKER_CONTAINER"; then
        error "V2Ray client container '$DOCKER_CONTAINER' is not running."
    fi
    
    info "✅ V2Ray client container is running."
    
    # Check for listening proxy ports
    if ! ss -tulpn | grep -q ":18080 "; then
        warn "❌ HTTP proxy port 18080 is not listening."
    else
        info "✅ HTTP proxy port 18080 is listening."
    fi
    
    if ! ss -tulpn | grep -q ":11080 "; then
        warn "❌ SOCKS proxy port 11080 is not listening."
    else
        info "✅ SOCKS proxy port 11080 is listening."
    fi
    
    if ! ss -tulpn | grep -q ":11081 "; then
        error "❌ Transparent proxy port 11081 is not listening. Tunnel will not work!"
    else
        info "✅ Transparent proxy port 11081 is listening."
    fi
    
    # Test connection to Server 1
    info "Testing connectivity to Server 1 ($SERVER1_ADDRESS)..."
    if ! ping -c 1 -W 2 "$SERVER1_ADDRESS" &>/dev/null; then
        warn "⚠️ Cannot ping Server 1. This may be normal if ICMP is blocked."
    else
        info "✅ Server 1 is reachable via ping."
    fi
    
    # Test HTTP proxy connection
    info "Testing HTTP proxy tunnel to Server 1..."
    local proxy_result=$(curl -s -m 10 -x "http://127.0.0.1:18080" https://ifconfig.me 2>&1 || echo "Failed")
    
    if [[ "$proxy_result" != "Failed" && "$proxy_result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        info "✅ HTTP proxy tunnel is working. External IP: $proxy_result"
        
        # Compare with direct connection
        local direct_result=$(curl -s -m 5 https://ifconfig.me 2>/dev/null || echo "Failed")
        if [[ "$direct_result" != "Failed" && "$proxy_result" != "$direct_result" ]]; then
            info "✅ Tunnel routing confirmed! Traffic is going through Server 1."
            info "  - Direct IP: $direct_result"
            info "  - Tunneled IP: $proxy_result"
        else
            warn "⚠️ Tunnel might not be working correctly. IP addresses are the same or direct check failed."
        fi
    else
        warn "❌ HTTP proxy tunnel test failed: $proxy_result"
        
        # Check container logs for errors
        docker logs "$DOCKER_CONTAINER" --tail 20 | grep -i "error\|warn\|fail"
    fi
}

# Check iptables rules for routing
check_routing_rules() {
    info "Checking routing rules..."
    
    # Check IP forwarding
    local ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$ip_forward" -eq 1 ]; then
        info "✅ IP forwarding is enabled."
    else
        warn "❌ IP forwarding is not enabled. This will break routing."
        info "Run the following to enable:"
        info "echo 1 > /proc/sys/net/ipv4/ip_forward"
        info "sysctl -w net.ipv4.ip_forward=1"
    fi
    
    # Check for V2RAY chain
    if iptables -t nat -L | grep -q "V2RAY"; then
        info "✅ V2RAY chain exists in nat table."
        
        # Check for proper routing rules
        if iptables -t nat -L | grep -q "REDIRECT.*11081"; then
            info "✅ REDIRECT rules to port 11081 are configured."
        else
            warn "❌ REDIRECT rules to port 11081 are missing."
        fi
        
        # Check for Outline network rules
        if iptables -t nat -L | grep -q "$OUTLINE_NETWORK"; then
            info "✅ Rules for Outline VPN network exist."
        else
            warn "❌ Rules for Outline VPN network are missing."
        fi
    else
        warn "❌ V2RAY chain is missing from nat table."
    fi
    
    # Check for masquerading rules
    if iptables -t nat -L POSTROUTING | grep -q "MASQUERADE"; then
        info "✅ MASQUERADE rule is configured in POSTROUTING chain."
    else
        warn "❌ MASQUERADE rule is missing. Outline clients may not be able to access the internet."
    fi
}

# Monitor Outline client traffic
monitor_outline_traffic() {
    header "=== MONITORING OUTLINE VPN CLIENT TRAFFIC ==="
    
    # Get the Outline network interface
    local outline_interface="tun0"
    if ip a | grep -q "tun"; then
        outline_interface=$(ip a | grep "tun" | cut -d: -f2 | head -n1 | tr -d ' ')
        info "Detected Outline interface: $outline_interface"
    else
        warn "Could not detect Outline interface, assuming tun0."
    fi
    
    if [ "$MONITOR_MODE" == "continuous" ]; then
        info "Starting continuous monitoring. Press Ctrl+C to stop."
        while true; do
            check_outline_connections
            sleep $INTERVAL
        done
    else
        info "Monitoring for $DURATION seconds with $INTERVAL second intervals..."
        local end_time=$(($(date +%s) + DURATION))
        
        while [ $(date +%s) -lt $end_time ]; do
            check_outline_connections
            sleep $INTERVAL
        done
    fi
}

# Check current Outline client connections
check_outline_connections() {
    echo -e "\n${CYAN}[$(date +"%Y-%m-%d %H:%M:%S")]${NC} Checking Outline client traffic..."
    
    # Count active Outline clients by IP
    local outline_clients=$(netstat -an | grep -E "($OUTLINE_NETWORK|tun0)" | grep -v "127.0.0.1" | awk '{print $5}' | sort | uniq -c | sort -nr)
    
    if [ -z "$outline_clients" ]; then
        echo "  No active Outline VPN clients detected."
    else
        echo "Active Outline VPN clients:"
        echo "$outline_clients" | while read count ip; do
            echo "  $ip: $count connections"
        done
    fi
    
    # Check if traffic is being forwarded through the tunnel
    local forwarded_count=$(iptables -L FORWARD -v | grep -E "$OUTLINE_NETWORK" | awk '{print $1}')
    echo "Forwarded packets from Outline network: ${forwarded_count:-0}"
    
    # Check for traffic destinations (in detailed mode)
    if [ "$MONITOR_MODE" == "detailed" ] || [ "$MONITOR_MODE" == "continuous" ]; then
        # Check if we already have a monitoring rule
        if ! iptables -L | grep -q "OUTLINE-MONITOR"; then
            # Add temporary monitoring rules
            iptables -N OUTLINE-MONITOR 2>/dev/null || true
            iptables -I FORWARD -s "$OUTLINE_NETWORK" -j OUTLINE-MONITOR
        fi
        
        # Show packet counts
        echo "  Outline client traffic: $(iptables -L OUTLINE-MONITOR -v | grep -m 1 "OUTLINE-MONITOR" | awk '{print $1}') packets"
        
        if [ "$MONITOR_MODE" == "detailed" ]; then
            # Show brief tcpdump output for Outline traffic
            echo "Recent traffic from Outline clients (last 5 packets):"
            timeout 2 tcpdump -nn -c 5 -i any src net "$OUTLINE_NETWORK" 2>/dev/null || echo "  No packets captured in the last 2 seconds."
            
            # Check if traffic is actually going through the tunnel
            echo "Verifying tunnel routing for Outline traffic:"
            local tunnel_count=$(ss -tn | grep -E "127.0.0.1:1108[01]" | wc -l)
            echo "  Connections to local proxy ports: $tunnel_count"
        fi
    fi
}

# Check tunnel performance
check_tunnel_performance() {
    if [ "$MONITOR_MODE" == "detailed" ] || [ "$MONITOR_MODE" == "continuous" ]; then
        header "=== TUNNEL PERFORMANCE CHECK ==="
        
        # Test tunnel performance with a speed test
        info "Testing tunnel download speed (small file)..."
        local start_time=$(date +%s.%N)
        curl -s -m 10 -x "http://127.0.0.1:18080" -o /dev/null https://speed.cloudflare.com/cdn-cgi/trace
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        
        echo "  Small file download time: ${duration} seconds"
        
        # Get a sample of packet round-trip time to Server 1
        info "Testing packet round-trip time to Server 1..."
        local rtt=$(ping -c 3 -W 2 "$SERVER1_ADDRESS" 2>/dev/null | grep "rtt" | cut -d '/' -f 5)
        if [ -n "$rtt" ]; then
            echo "  Average RTT to Server 1: ${rtt} ms"
        else
            echo "  Could not measure RTT to Server 1 (ICMP may be blocked)"
        fi
    fi
}

# Generate a summary report
generate_summary() {
    header "=== ROUTING SUMMARY ==="
    
    # Check tunnel status
    if curl -s -m 5 -x "http://127.0.0.1:18080" https://ifconfig.me &>/dev/null; then
        echo -e "${GREEN}✅ Tunnel to Server 1 is ACTIVE${NC}"
    else
        echo -e "${RED}❌ Tunnel to Server 1 is NOT WORKING${NC}"
    fi
    
    # Check Outline routing
    local outline_rules=$(iptables -t nat -L | grep -E "$OUTLINE_NETWORK" | wc -l)
    if [ "$outline_rules" -gt 0 ]; then
        echo -e "${GREEN}✅ Outline VPN routing is CONFIGURED${NC}"
    else
        echo -e "${YELLOW}⚠️ Outline VPN routing rules are MISSING${NC}"
    fi
    
    # Count forwarded traffic
    if iptables -L | grep -q "OUTLINE-MONITOR"; then
        local outline_traffic=$(iptables -L OUTLINE-MONITOR -v | grep -m 1 "OUTLINE-MONITOR" | awk '{print $1}')
        echo "Total Outline traffic: ${outline_traffic:-0} packets"
        
        # Cleanup monitoring rules
        iptables -D FORWARD -s "$OUTLINE_NETWORK" -j OUTLINE-MONITOR 2>/dev/null || true
        iptables -F OUTLINE-MONITOR 2>/dev/null || true
        iptables -X OUTLINE-MONITOR 2>/dev/null || true
        echo "Cleaned up monitoring iptables rules."
    fi
    
    # Check for any connection errors in the logs
    echo "Connection Errors (last 10):"
    docker logs "$DOCKER_CONTAINER" 2>&1 | grep -i "error\|warn\|fail" | tail -10 || echo "  No errors found."
    
    # Suggestions for improvement
    echo -e "\n${BLUE}Troubleshooting Suggestions:${NC}"
    echo "1. If tunnel is not working, check '/var/log/v2ray/error.log' for errors"
    echo "2. Verify V2Ray configuration with 'docker exec $DOCKER_CONTAINER v2ray test -config /etc/v2ray/config.json'"
    echo "3. Ensure Server 1 has the correct client UUID for this server"
    echo "4. Run '/usr/local/bin/fix-port-binding.sh' if tunnel ports are not listening"
    echo "5. Check 'docker logs $DOCKER_CONTAINER' for container-specific errors"
}

# Main function
main() {
    parse_args "$@"
    check_dependencies
    
    # Redirect output to file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        exec > >(tee -a "$OUTPUT_FILE") 2>&1
    fi
    
    # Check tunnel and routing
    check_tunnel_status
    check_routing_rules
    
    # Monitor VPN traffic
    monitor_outline_traffic
    
    # Check tunnel performance in detailed mode
    check_tunnel_performance
    
    # Generate summary
    generate_summary
    
    info "Monitoring completed."
    if [ -n "$OUTPUT_FILE" ]; then
        info "Results saved to $OUTPUT_FILE"
    fi
}

main "$@"