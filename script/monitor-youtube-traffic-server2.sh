#!/bin/bash

# ===================================================================
# YouTube Traffic Monitoring Script for Server 2
# ===================================================================
# This script:
# - Monitors outgoing traffic from Outline VPN clients to Server 1
# - Identifies YouTube-related traffic based on DNS queries and IPs
# - Logs statistics and connection details
# - Verifies tunnel functionality for YouTube traffic
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SERVER1_IP=""
OUTLINE_PORT="7777"
LOG_FILE="/var/log/youtube-traffic-outline-monitor.log"
DURATION=0
INTERFACE="eth0"
VERBOSE=false
YOUTUBE_DOMAINS_FILE="/tmp/youtube_domains.txt"
OUTLINE_NETWORK="10.0.0.0/24"

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

This script monitors YouTube traffic from Outline VPN clients to Server 1.

Required Options:
  --server1-ip IP         IP address of Server 1

Optional Options:
  --outline-port PORT     Outline VPN port (default: 7777)
  --outline-network NET   Outline VPN client network (default: 10.0.0.0/24)
  --interface IFACE       Network interface to monitor (default: eth0)
  --duration SECONDS      How long to monitor traffic (0 = indefinitely, default)
  --log-file FILE         Path to log file (default: /var/log/youtube-traffic-outline-monitor.log)
  --verbose               Enable verbose output
  --help                  Display this help message

Example:
  $(basename "$0") --server1-ip 123.45.67.89 --duration 300

EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --server1-ip)
                SERVER1_IP="$2"
                shift
                ;;
            --outline-port)
                OUTLINE_PORT="$2"
                shift
                ;;
            --outline-network)
                OUTLINE_NETWORK="$2"
                shift
                ;;
            --interface)
                INTERFACE="$2"
                shift
                ;;
            --duration)
                DURATION="$2"
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift
                ;;
            --verbose)
                VERBOSE=true
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
    if [ -z "$SERVER1_IP" ]; then
        error "Server 1 IP address is required. Use --server1-ip option."
    fi
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Check for required dependencies
check_dependencies() {
    info "Checking required dependencies..."
    
    local missing_deps=()
    
    for cmd in tcpdump grep awk cut tr host sed; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}. Please install them and try again."
    fi
    
    info "All required dependencies are installed."
}

# Create a file with common YouTube domains
create_youtube_domains_file() {
    info "Creating YouTube domains reference file..."
    
    cat > "$YOUTUBE_DOMAINS_FILE" << EOF
youtube.com
www.youtube.com
m.youtube.com
youtu.be
youtubei.googleapis.com
yt3.ggpht.com
yt3.googleusercontent.com
i.ytimg.com
i9.ytimg.com
s.ytimg.com
r1---sn-*.googlevideo.com
r2---sn-*.googlevideo.com
r3---sn-*.googlevideo.com
r4---sn-*.googlevideo.com
r5---sn-*.googlevideo.com
r6---sn-*.googlevideo.com
r7---sn-*.googlevideo.com
r8---sn-*.googlevideo.com
r9---sn-*.googlevideo.com
r10---sn-*.googlevideo.com
r11---sn-*.googlevideo.com
r12---sn-*.googlevideo.com
r13---sn-*.googlevideo.com
r14---sn-*.googlevideo.com
r15---sn-*.googlevideo.com
r16---sn-*.googlevideo.com
r17---sn-*.googlevideo.com
r18---sn-*.googlevideo.com
r19---sn-*.googlevideo.com
r20---sn-*.googlevideo.com
yt.be
youtube-ui.l.google.com
youtube-nocookie.com
youtube-thumbnail.l.google.com
EOF
    
    info "YouTube domains file created at $YOUTUBE_DOMAINS_FILE"
}

# Check Outline VPN container status
check_outline_status() {
    info "Checking Outline VPN container status..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "shadowbox"; then
        warn "Outline VPN container (shadowbox) is not running."
        warn "YouTube traffic monitoring may not work properly."
        return 1
    fi
    
    info "Outline VPN container is running."
    
    # Check if Outline port is listening
    if ! ss -tulpn | grep -q ":$OUTLINE_PORT"; then
        warn "Outline VPN port $OUTLINE_PORT is not listening."
        warn "YouTube traffic monitoring may not work properly."
        return 1
    fi
    
    info "Outline VPN port $OUTLINE_PORT is listening."
    return 0
}

# Check tunnel to Server 1
check_tunnel_status() {
    info "Checking tunnel connectivity to Server 1..."
    
    # Check if v2ray-client container is running
    if ! docker ps --format '{{.Names}}' | grep -q "v2ray-client"; then
        warn "v2ray-client container is not running."
        warn "Tunnel to Server 1 may not be working properly."
        return 1
    fi
    
    info "v2ray-client container is running."
    
    # Check if proxy ports are listening
    if ! ss -tulpn | grep -q ":1081\|:8080"; then
        warn "v2ray proxy ports (1081/8080) are not listening."
        warn "Tunnel to Server 1 may not be working properly."
        return 1
    fi
    
    info "v2ray proxy ports are listening."
    
    # Test connection to Server 1
    if ! ping -c 1 -W 5 "$SERVER1_IP" >/dev/null 2>&1; then
        warn "Cannot ping Server 1 ($SERVER1_IP)."
        warn "This may be normal if ICMP is blocked."
    else
        info "Server 1 is reachable via ping."
    fi
    
    # Test tunnel connectivity with curl
    local tunnel_test
    tunnel_test=$(curl -s --connect-timeout 5 -x http://127.0.0.1:8080 https://ifconfig.me 2>/dev/null)
    
    if [ -z "$tunnel_test" ]; then
        warn "Tunnel test failed. Traffic may not be routed correctly."
        return 1
    else
        info "Tunnel is working. Traffic is being routed through: $tunnel_test"
    fi
    
    return 0
}

# Monitor YouTube traffic from Outline clients to Server 1
monitor_traffic() {
    info "Starting YouTube traffic monitoring for Outline clients..."
    info "Monitoring interface: $INTERFACE"
    if [ "$DURATION" -gt 0 ]; then
        info "Monitoring for $DURATION seconds"
    else
        info "Monitoring indefinitely (press Ctrl+C to stop)"
    fi
    
    # Create log file directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Initialize counters
    local start_time
    local youtube_packets=0
    local youtube_dns=0
    local youtube_bytes=0
    local total_tunnel_packets=0
    local total_tunnel_bytes=0
    local current_clients=()
    
    start_time=$(date +%s)
    
    # Capture DNS queries and traffic to Server 1
    local filter="(src net $OUTLINE_NETWORK and dst $SERVER1_IP) or (udp port 53 and src net $OUTLINE_NETWORK)"
    
    # Run tcpdump and process output
    if [ "$DURATION" -gt 0 ]; then
        # Run for specified duration
        timeout "$DURATION" tcpdump -i "$INTERFACE" -nn "$filter" 2>/dev/null | while read -r line; do
            process_packet "$line"
        done
    else
        # Run indefinitely
        tcpdump -i "$INTERFACE" -nn "$filter" 2>/dev/null | while read -r line; do
            process_packet "$line"
        done
    fi
}

# Process each packet from tcpdump
process_packet() {
    local line="$1"
    local src_ip
    local dst_ip
    local packet_size
    local current_time
    local elapsed_time
    local dns_query
    
    # Check for DNS queries for YouTube domains
    if [[ "$line" =~ IP[^:]*:\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)\ \>\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.53:.* ]]; then
        src_ip="${BASH_REMATCH[1]}"
        src_port="${BASH_REMATCH[2]}"
        dns_server="${BASH_REMATCH[3]}"
        
        # Check if this is from an Outline client
        if [[ "$src_ip" =~ ^10\.0\.0\. ]]; then
            # Try to extract the domain from the DNS query (simplified approach)
            dns_query=$(echo "$line" | grep -o "[A-Za-z0-9.-]*\.youtube\.com\|[A-Za-z0-9.-]*\.youtu\.be\|[A-Za-z0-9.-]*\.googlevideo\.com")
            
            # If we found a YouTube domain in the DNS query
            if [ -n "$dns_query" ]; then
                youtube_dns=$((youtube_dns + 1))
                
                # Log YouTube DNS query
                current_time=$(date +%s)
                elapsed_time=$((current_time - start_time))
                
                log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] Outline client $src_ip DNS query for YouTube domain: $dns_query"
                echo "$log_entry" >> "$LOG_FILE"
                
                if [ "$VERBOSE" = true ]; then
                    echo -e "${BLUE}[YOUTUBE DNS]${NC} $log_entry"
                fi
                
                # Add client to list if not already present
                if [[ ! " ${current_clients[@]} " =~ " ${src_ip} " ]]; then
                    current_clients+=("$src_ip")
                fi
            fi
        fi
    fi
    
    # Process regular traffic to Server 1
    if [[ "$line" =~ IP[^:]*:\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)\ \>\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+):.*length\ ([0-9]+) ]]; then
        src_ip="${BASH_REMATCH[1]}"
        src_port="${BASH_REMATCH[2]}"
        dst_ip="${BASH_REMATCH[3]}"
        dst_port="${BASH_REMATCH[4]}"
        packet_size="${BASH_REMATCH[5]}"
        
        # Check if this is traffic from Outline client to Server 1
        if [[ "$src_ip" =~ ^10\.0\.0\. ]] && [ "$dst_ip" == "$SERVER1_IP" ]; then
            total_tunnel_packets=$((total_tunnel_packets + 1))
            total_tunnel_bytes=$((total_tunnel_bytes + packet_size))
            
            # If this client previously made a YouTube DNS query, count as YouTube traffic
            if [[ " ${current_clients[@]} " =~ " ${src_ip} " ]]; then
                youtube_packets=$((youtube_packets + 1))
                youtube_bytes=$((youtube_bytes + packet_size))
                
                # Log YouTube traffic
                current_time=$(date +%s)
                elapsed_time=$((current_time - start_time))
                
                log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] YouTube traffic: Outline client $src_ip -> Server 1 $dst_ip:$dst_port Size: $packet_size bytes"
                echo "$log_entry" >> "$LOG_FILE"
                
                if [ "$VERBOSE" = true ]; then
                    echo -e "${BLUE}[YOUTUBE TRAFFIC]${NC} $log_entry"
                fi
                
                # Print summary statistics every 50 YouTube packets
                if [ $((youtube_packets % 50)) -eq 0 ]; then
                    echo "----------------------------------------"
                    echo "Traffic Summary (after $elapsed_time seconds):"
                    echo "YouTube DNS Queries: $youtube_dns"
                    echo "YouTube Packets: $youtube_packets"
                    echo "YouTube Data: $(numfmt --to=iec-i --suffix=B $youtube_bytes 2>/dev/null || echo "$youtube_bytes bytes")"
                    echo "Total Tunnel Packets: $total_tunnel_packets"
                    echo "Total Tunnel Data: $(numfmt --to=iec-i --suffix=B $total_tunnel_bytes 2>/dev/null || echo "$total_tunnel_bytes bytes")"
                    if [ "$total_tunnel_bytes" -gt 0 ]; then
                        echo "YouTube Traffic Percentage: $((youtube_bytes * 100 / total_tunnel_bytes))%"
                    fi
                    echo "Active YouTube Clients: ${#current_clients[@]}"
                    echo "----------------------------------------"
                fi
            fi
        fi
    fi
}

# Main function
main() {
    check_root
    parse_args "$@"
    check_dependencies
    create_youtube_domains_file
    check_outline_status
    check_tunnel_status
    
    info "Starting YouTube traffic monitoring on Server 2"
    info "Monitoring tunnel traffic to Server 1 IP: $SERVER1_IP"
    info "Monitoring Outline client network: $OUTLINE_NETWORK"
    info "Log file: $LOG_FILE"
    
    # Register cleanup on exit
    trap 'info "Monitoring stopped. Summary saved to $LOG_FILE"; exit 0' INT TERM
    
    # Start monitoring
    monitor_traffic
    
    info "Monitoring completed. Check $LOG_FILE for details."
}

main "$@"