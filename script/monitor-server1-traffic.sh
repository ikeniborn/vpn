#!/bin/bash

# ===================================================================
# Server 1 Traffic Monitoring Script
# ===================================================================
# This script:
# - Monitors incoming connections from Server 2
# - Tracks traffic routing from Server 2 to the internet
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
SERVER2_IP=""
INTERVAL=5
DURATION=60
MONITOR_MODE="basic"  # Options: basic, detailed, continuous
OUTPUT_FILE=""
V2RAY_PORT="443"

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

This script monitors incoming traffic from Server 2 and tracks routing to the internet.

Options:
  --server2-ip IP        IP address of Server 2 (required)
  --interval SEC         Sampling interval in seconds (default: 5)
  --duration SEC         Total monitoring duration in seconds (default: 60)
  --mode MODE            Monitoring mode: basic, detailed, continuous (default: basic)
  --v2ray-port PORT      V2Ray port (default: 443)
  --output FILE          Save output to file
  --help                 Display this help message

Example:
  $(basename "$0") --server2-ip 192.168.1.2 --mode detailed

EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --server2-ip)
                SERVER2_IP="$2"
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
            --v2ray-port)
                V2RAY_PORT="$2"
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
    if [ -z "$SERVER2_IP" ]; then
        error "Server 2 IP address is required. Use --server2-ip option."
    fi

    # Validate monitoring mode
    if [[ "$MONITOR_MODE" != "basic" && "$MONITOR_MODE" != "detailed" && "$MONITOR_MODE" != "continuous" ]]; then
        error "Invalid monitoring mode: $MONITOR_MODE. Must be 'basic', 'detailed', or 'continuous'."
    fi

    info "Configuration:"
    info "- Server 2 IP: $SERVER2_IP"
    info "- Interval: $INTERVAL seconds"
    info "- Duration: $DURATION seconds"
    info "- Mode: $MONITOR_MODE"
    info "- V2Ray port: $V2RAY_PORT"
    if [ -n "$OUTPUT_FILE" ]; then
        info "- Output file: $OUTPUT_FILE"
    fi
}

# Check for required tools
check_dependencies() {
    info "Checking for required tools..."
    
    local missing_tools=()
    
    for tool in tcpdump iptables netstat ss jq grep awk sort uniq; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        warn "Missing required tools: ${missing_tools[*]}"
        info "Installing missing tools..."
        
        apt-get update
        apt-get install -y net-tools iproute2 iptables tcpdump jq
        
        # Check again after install
        for tool in "${missing_tools[@]}"; do
            if ! command -v $tool &> /dev/null; then
                error "Failed to install $tool. Please install it manually."
            fi
        done
    fi
    
    info "All required tools are available."
}

# Check if v2ray/reality is properly configured
check_v2ray_config() {
    info "Checking v2ray configuration..."
    
    # Check if the port is listening
    if ! ss -tulpn | grep -q ":$V2RAY_PORT "; then
        error "V2Ray is not listening on port $V2RAY_PORT."
    fi
    
    info "V2Ray is listening on port $V2RAY_PORT."
    
    # Check for docker container if used
    if command -v docker &> /dev/null; then
        if docker ps | grep -q "v2fly/v2fly-core"; then
            info "V2Ray is running in Docker container."
            
            # Get container ID
            local container_id=$(docker ps | grep "v2fly/v2fly-core" | awk '{print $1}')
            info "Container ID: $container_id"
        fi
    fi
}

# Check iptables for forwarding rules
check_forwarding_rules() {
    info "Checking IP forwarding and routing rules..."
    
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
    
    # Check for masquerade rules
    if iptables -t nat -L POSTROUTING | grep -q "MASQUERADE"; then
        info "✅ MASQUERADE rule is configured in POSTROUTING chain."
    else
        warn "❌ MASQUERADE rule is missing. Server 2 traffic may not be routed correctly."
    fi
    
    # Find active interfaces
    local interfaces=$(ip -4 route show default | awk '{print $5}' | head -n1)
    info "Default outgoing interface: $interfaces"
}

# Monitor connections from Server 2
monitor_connections() {
    header "=== MONITORING CONNECTIONS FROM SERVER 2 ($SERVER2_IP) ==="
    
    if [ "$MONITOR_MODE" == "continuous" ]; then
        info "Starting continuous monitoring. Press Ctrl+C to stop."
        while true; do
            check_current_connections
            sleep $INTERVAL
        done
    else
        info "Monitoring for $DURATION seconds with $INTERVAL second intervals..."
        local end_time=$(($(date +%s) + DURATION))
        
        while [ $(date +%s) -lt $end_time ]; do
            check_current_connections
            sleep $INTERVAL
        done
    fi
}

# Check current connections
check_current_connections() {
    echo -e "\n${CYAN}[$(date +"%Y-%m-%d %H:%M:%S")]${NC} Checking current connections..."
    
    # Get active connections from Server 2
    echo "Active connections from Server 2:"
    if ss -tn | grep "$SERVER2_IP"; then
        # If found connections, highlight them
        ss -tn | grep "$SERVER2_IP" | awk '{print "  " $0}'
    else
        echo "  No active connections found from Server 2."
    fi
    
    # Show established connections count
    local established_count=$(ss -tn | grep "$SERVER2_IP" | grep "ESTAB" | wc -l)
    echo "Established connections from Server 2: $established_count"
    
    # Check connections to the V2Ray port specifically
    local v2ray_connections=$(ss -tn | grep "$SERVER2_IP" | grep ":$V2RAY_PORT" | wc -l)
    echo "Connections to V2Ray port ($V2RAY_PORT): $v2ray_connections"
    
    if [ "$MONITOR_MODE" == "detailed" ] || [ "$MONITOR_MODE" == "continuous" ]; then
        # Get more detailed stats with iptables
        echo "Traffic statistics from Server 2:"
        if command -v iptables-save &> /dev/null; then
            # Check if we already have a monitoring rule
            if ! iptables -L | grep -q "SERVER2-MONITOR"; then
                # Add temporary monitoring rules
                iptables -N SERVER2-MONITOR 2>/dev/null || true
                iptables -I INPUT -s "$SERVER2_IP" -j SERVER2-MONITOR
                iptables -I FORWARD -s "$SERVER2_IP" -j SERVER2-MONITOR
            fi
            
            # Show packet counts
            echo "  Incoming packets: $(iptables -L SERVER2-MONITOR -v | grep -m 1 "SERVER2-MONITOR" | awk '{print $1}')"
            echo "  Forwarded packets: $(iptables -L SERVER2-MONITOR -v -t filter | grep -m 1 "SERVER2-MONITOR" | awk '{print $1}')"
            
            # For more advanced troubleshooting
            if [ "$MONITOR_MODE" == "detailed" ]; then
                # Show actual traffic flow with tcpdump (briefly)
                echo "Recent traffic from Server 2 (last 5 packets):"
                timeout 2 tcpdump -nn -c 5 -i any host "$SERVER2_IP" 2>/dev/null || echo "  No packets captured in the last 2 seconds."
            fi
        else
            echo "  iptables-save not available for detailed statistics."
        fi
    fi
}

# Generate a summary report
generate_summary() {
    header "=== CONNECTION SUMMARY ==="
    
    # Average number of connections
    if command -v iptables-save &> /dev/null; then
        echo "Traffic Summary:"
        echo "  Total incoming packets: $(iptables -L SERVER2-MONITOR -v | grep -m 1 "SERVER2-MONITOR" | awk '{print $1}')"
        echo "  Total forwarded packets: $(iptables -L SERVER2-MONITOR -v -t filter | grep -m 1 "SERVER2-MONITOR" | awk '{print $1}')"
    fi
    
    # Check for any connection errors in the logs
    echo "Connection Errors (last 10):"
    if [ -f "/var/log/v2ray/error.log" ]; then
        grep -i "error\|warn\|fail" /var/log/v2ray/error.log | grep -i "$SERVER2_IP" | tail -10 || echo "  No errors found."
    else
        echo "  Error log not found at /var/log/v2ray/error.log"
    fi
    
    # Cleanup monitoring rules
    if iptables -L | grep -q "SERVER2-MONITOR"; then
        iptables -D INPUT -s "$SERVER2_IP" -j SERVER2-MONITOR 2>/dev/null || true
        iptables -D FORWARD -s "$SERVER2_IP" -j SERVER2-MONITOR 2>/dev/null || true
        iptables -F SERVER2-MONITOR 2>/dev/null || true
        iptables -X SERVER2-MONITOR 2>/dev/null || true
        echo "Cleaned up monitoring iptables rules."
    fi
    
    # Final status check
    local current_connections=$(ss -tn | grep "$SERVER2_IP" | wc -l)
    if [ "$current_connections" -gt 0 ]; then
        echo -e "${GREEN}✅ Server 2 is currently connected. Routing appears to be working.${NC}"
    else
        echo -e "${YELLOW}⚠️ No active connections from Server 2. Please check Server 2 configuration.${NC}"
    fi
}

# Main function
main() {
    parse_args "$@"
    check_dependencies
    check_v2ray_config
    check_forwarding_rules
    
    # Redirect output to file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        exec > >(tee -a "$OUTPUT_FILE") 2>&1
    fi
    
    # Monitor connections
    monitor_connections
    
    # Generate summary
    generate_summary
    
    info "Monitoring completed. Results saved to $OUTPUT_FILE"
}

main "$@"