#!/bin/bash

# ===================================================================
# YouTube Traffic Monitoring Script for Server 1
# ===================================================================
# This script:
# - Monitors incoming traffic from Server 2
# - Identifies YouTube-related traffic
# - Logs statistics and connection details
# - Provides real-time and cumulative monitoring
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SERVER2_IP=""
LOG_FILE="/var/log/youtube-traffic-monitor.log"
DURATION=0
INTERFACE="eth0"
VERBOSE=false
YOUTUBE_DOMAINS_FILE="/tmp/youtube_domains.txt"

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

This script monitors YouTube traffic coming from Server 2 to Server 1.

Required Options:
  --server2-ip IP         IP address of Server 2

Optional Options:
  --interface IFACE       Network interface to monitor (default: eth0)
  --duration SECONDS      How long to monitor traffic (0 = indefinitely, default)
  --log-file FILE         Path to log file (default: /var/log/youtube-traffic-monitor.log)
  --verbose               Enable verbose output
  --help                  Display this help message

Example:
  $(basename "$0") --server2-ip 192.168.1.100 --duration 300

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
    if [ -z "$SERVER2_IP" ]; then
        error "Server 2 IP address is required. Use --server2-ip option."
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
    
    for cmd in tcpdump grep awk cut tr host; do
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

# Function to reverse DNS lookup an IP address
reverse_dns_lookup() {
    local ip="$1"
    local hostname
    
    hostname=$(host "$ip" 2>/dev/null | awk '/domain name pointer/ {print $NF}' | sed 's/\.$//')
    
    if [ -n "$hostname" ]; then
        echo "$hostname"
    else
        echo "$ip"
    fi
}

# Monitor YouTube traffic
monitor_traffic() {
    info "Starting YouTube traffic monitoring from Server 2 ($SERVER2_IP)..."
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
    local youtube_bytes=0
    local total_packets=0
    local total_bytes=0
    
    start_time=$(date +%s)
    
    # Run tcpdump and process output
    if [ "$DURATION" -gt 0 ]; then
        # Run for specified duration
        timeout "$DURATION" tcpdump -i "$INTERFACE" -nn "host $SERVER2_IP" 2>/dev/null | while read -r line; do
            process_packet "$line"
        done
    else
        # Run indefinitely
        tcpdump -i "$INTERFACE" -nn "host $SERVER2_IP" 2>/dev/null | while read -r line; do
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
    local is_youtube=false
    
    # Parse packet info
    if [[ "$line" =~ IP[^:]*:\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)\ \>\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+):.*length\ ([0-9]+) ]]; then
        src_ip="${BASH_REMATCH[1]}"
        src_port="${BASH_REMATCH[2]}"
        dst_ip="${BASH_REMATCH[3]}"
        dst_port="${BASH_REMATCH[4]}"
        packet_size="${BASH_REMATCH[5]}"
        
        # Check if packet is from Server 2
        if [ "$src_ip" == "$SERVER2_IP" ]; then
            total_packets=$((total_packets + 1))
            total_bytes=$((total_bytes + packet_size))
            
            # Check if this is port 80 or 443 traffic (HTTP/HTTPS)
            if [ "$dst_port" == "80" ] || [ "$dst_port" == "443" ]; then
                # Get the reverse DNS of the destination IP
                dst_hostname=$(reverse_dns_lookup "$dst_ip")
                
                # Check if this is YouTube traffic
                while IFS= read -r youtube_domain; do
                    if [[ "$dst_hostname" == *"$youtube_domain"* ]] || [[ "$dst_hostname" == *"googlevideo"* ]]; then
                        is_youtube=true
                        youtube_packets=$((youtube_packets + 1))
                        youtube_bytes=$((youtube_bytes + packet_size))
                        break
                    fi
                done < "$YOUTUBE_DOMAINS_FILE"
                
                # Log YouTube traffic
                if [ "$is_youtube" = true ]; then
                    current_time=$(date +%s)
                    elapsed_time=$((current_time - start_time))
                    
                    log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] YouTube traffic: $src_ip:$src_port -> $dst_ip:$dst_port ($dst_hostname) Size: $packet_size bytes"
                    echo "$log_entry" >> "$LOG_FILE"
                    
                    if [ "$VERBOSE" = true ]; then
                        echo -e "${BLUE}[YOUTUBE]${NC} $log_entry"
                    fi
                    
                    # Print summary statistics every 50 YouTube packets
                    if [ $((youtube_packets % 50)) -eq 0 ]; then
                        echo "----------------------------------------"
                        echo "Traffic Summary (after $elapsed_time seconds):"
                        echo "YouTube Packets: $youtube_packets"
                        echo "YouTube Data: $(numfmt --to=iec-i --suffix=B $youtube_bytes)"
                        echo "Total Packets from Server 2: $total_packets"
                        echo "Total Data from Server 2: $(numfmt --to=iec-i --suffix=B $total_bytes)"
                        echo "YouTube Traffic Percentage: $((youtube_bytes * 100 / total_bytes))%"
                        echo "----------------------------------------"
                    fi
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
    
    info "Starting YouTube traffic monitoring on Server 1"
    info "Monitoring traffic from Server 2 IP: $SERVER2_IP"
    info "Log file: $LOG_FILE"
    
    # Register cleanup on exit
    trap 'info "Monitoring stopped. Summary saved to $LOG_FILE"; exit 0' INT TERM
    
    # Start monitoring
    monitor_traffic
    
    info "Monitoring completed. Check $LOG_FILE for details."
}

main "$@"