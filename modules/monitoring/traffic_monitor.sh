#!/bin/bash
#
# Real-time Traffic Monitoring Module
# Provides comprehensive real-time traffic diagnostics for VPN connections
# Author: Claude
# Version: 1.0

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"
source "$PROJECT_DIR/lib/network.sh"

# Global variables for monitoring
MONITOR_ACTIVE=false
MONITOR_PID=""
MONITOR_INTERVAL=2  # seconds
TRAFFIC_LOG_FILE="/tmp/vpn_traffic_monitor.log"

# Initialize traffic monitoring module
init_traffic_monitor() {
    log "Initializing traffic monitoring module..."
    
    # Check required tools
    local required_tools=("ss" "iftop" "vnstat" "netstat")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # Install missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "Installing required monitoring tools: ${missing_tools[*]}"
        
        # Update package list
        apt-get update -qq >/dev/null 2>&1
        
        # Install tools based on what's missing
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "ss")
                    apt-get install -y iproute2 >/dev/null 2>&1 || warning "Failed to install iproute2"
                    ;;
                "iftop")
                    apt-get install -y iftop >/dev/null 2>&1 || warning "Failed to install iftop"
                    ;;
                "vnstat")
                    apt-get install -y vnstat >/dev/null 2>&1 || warning "Failed to install vnstat"
                    ;;
                "netstat")
                    apt-get install -y net-tools >/dev/null 2>&1 || warning "Failed to install net-tools"
                    ;;
            esac
        done
    fi
    
    # Initialize vnstat if needed
    if command -v vnstat >/dev/null 2>&1; then
        local primary_interface=$(get_primary_interface)
        if [ -n "$primary_interface" ]; then
            vnstat -i "$primary_interface" --create >/dev/null 2>&1 || true
        fi
    fi
    
    log "Traffic monitoring module initialized"
}

# Get primary network interface
get_primary_interface() {
    ip route | grep '^default' | head -1 | awk '{print $5}' || echo "eth0"
}

# Get VPN server port
get_vpn_port() {
    if [ -f "/opt/v2ray/config/config.json" ]; then
        jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null || echo ""
    fi
}

# Monitor active connections in real-time
monitor_active_connections() {
    local duration="${1:-60}"
    local vpn_port
    vpn_port=$(get_vpn_port)
    
    if [ -z "$vpn_port" ]; then
        error "Could not determine VPN port"
        return 1
    fi
    
    log "🔍 Monitoring active connections on port $vpn_port for ${duration}s"
    echo -e "${BLUE}Press Ctrl+C to stop monitoring${NC}"
    echo ""
    
    # Monitor connections
    local end_time=$(($(date +%s) + duration))
    local last_connection_count=0
    
    while [ $(date +%s) -lt $end_time ]; do
        clear
        echo -e "${GREEN}=== Real-time VPN Connection Monitor ===${NC}"
        echo -e "${BLUE}Monitoring port: $vpn_port${NC}"
        echo -e "${BLUE}Time remaining: $((end_time - $(date +%s)))s${NC}"
        echo ""
        
        # Current connections
        local connections
        connections=$(ss -tn 2>/dev/null | grep ":$vpn_port" | grep ESTAB || echo "")
        local connection_count
        connection_count=$(echo "$connections" | grep -c . || echo "0")
        
        echo -e "${YELLOW}Active Connections: $connection_count${NC}"
        echo ""
        
        if [ "$connection_count" -gt 0 ]; then
            echo -e "${GREEN}Connected Clients:${NC}"
            echo "$connections" | while IFS= read -r line; do
                if [ -n "$line" ]; then
                    local client_ip
                    client_ip=$(echo "$line" | awk '{print $5}' | cut -d':' -f1)
                    local client_port
                    client_port=$(echo "$line" | awk '{print $5}' | cut -d':' -f2)
                    echo "  📱 Client: $client_ip:$client_port"
                fi
            done
            echo ""
        fi
        
        # Connection change detection
        if [ "$connection_count" -ne "$last_connection_count" ]; then
            if [ "$connection_count" -gt "$last_connection_count" ]; then
                echo -e "${GREEN}🔗 New connection detected! (+$((connection_count - last_connection_count)))${NC}"
            else
                echo -e "${RED}🔌 Connection disconnected (-$((last_connection_count - connection_count)))${NC}"
            fi
            echo ""
        fi
        last_connection_count=$connection_count
        
        # Traffic statistics
        show_interface_traffic_summary
        
        sleep $MONITOR_INTERVAL
    done
}

# Show interface traffic summary
show_interface_traffic_summary() {
    local interface
    interface=$(get_primary_interface)
    
    echo -e "${YELLOW}Network Interface: $interface${NC}"
    
    # Get interface statistics
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        local rx_bytes tx_bytes
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
        
        # Convert to human readable
        local rx_human tx_human
        rx_human=$(numfmt --to=iec-i --suffix=B "$rx_bytes" 2>/dev/null || echo "${rx_bytes}B")
        tx_human=$(numfmt --to=iec-i --suffix=B "$tx_bytes" 2>/dev/null || echo "${tx_bytes}B")
        
        echo "  📥 RX: $rx_human"
        echo "  📤 TX: $tx_human"
    fi
    
    # Show vnstat if available
    if command -v vnstat >/dev/null 2>&1; then
        local vnstat_output
        vnstat_output=$(vnstat -i "$interface" --json 2>/dev/null || echo "")
        if [ -n "$vnstat_output" ]; then
            local today_rx today_tx
            today_rx=$(echo "$vnstat_output" | jq -r '.interfaces[0].traffic.day[0].rx' 2>/dev/null || echo "0")
            today_tx=$(echo "$vnstat_output" | jq -r '.interfaces[0].traffic.day[0].tx' 2>/dev/null || echo "0")
            
            if [ "$today_rx" != "null" ] && [ "$today_tx" != "null" ]; then
                local today_rx_human today_tx_human
                today_rx_human=$(numfmt --to=iec-i --suffix=B "$today_rx" 2>/dev/null || echo "${today_rx}B")
                today_tx_human=$(numfmt --to=iec-i --suffix=B "$today_tx" 2>/dev/null || echo "${today_tx}B")
                
                echo "  📊 Today: ↓$today_rx_human ↑$today_tx_human"
            fi
        fi
    fi
    echo ""
}

# Monitor user-specific traffic
monitor_user_traffic() {
    local username="$1"
    local duration="${2:-30}"
    
    if [ -z "$username" ]; then
        error "Username required for user-specific monitoring"
        return 1
    fi
    
    log "👤 Monitoring traffic for user: $username (${duration}s)"
    echo -e "${BLUE}Press Ctrl+C to stop monitoring${NC}"
    echo ""
    
    # Get user UUID from user file
    local user_file="/opt/v2ray/users/${username}.json"
    local user_uuid=""
    
    if [ -f "$user_file" ]; then
        user_uuid=$(jq -r '.uuid' "$user_file" 2>/dev/null || echo "")
    fi
    
    if [ -z "$user_uuid" ]; then
        warning "Could not find UUID for user: $username"
    fi
    
    # Monitor user activity in logs
    local access_log="/opt/v2ray/logs/access.log"
    local end_time=$(($(date +%s) + duration))
    local last_activity_count=0
    
    while [ $(date +%s) -lt $end_time ]; do
        clear
        echo -e "${GREEN}=== User Traffic Monitor ===${NC}"
        echo -e "${BLUE}User: $username${NC}"
        if [ -n "$user_uuid" ]; then
            echo -e "${BLUE}UUID: ${user_uuid:0:8}...${NC}"
        fi
        echo -e "${BLUE}Time remaining: $((end_time - $(date +%s)))s${NC}"
        echo ""
        
        # Check for user activity in logs
        if [ -f "$access_log" ]; then
            local recent_activity
            recent_activity=$(tail -100 "$access_log" 2>/dev/null | grep -i "$username" | tail -5 || echo "")
            
            if [ -n "$recent_activity" ]; then
                echo -e "${GREEN}Recent Activity:${NC}"
                echo "$recent_activity" | while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        local timestamp
                        timestamp=$(echo "$line" | awk '{print $1, $2}')
                        echo "  🕒 $timestamp"
                    fi
                done
                echo ""
                
                local activity_count
                activity_count=$(echo "$recent_activity" | grep -c . || echo "0")
                
                if [ "$activity_count" -ne "$last_activity_count" ]; then
                    echo -e "${GREEN}📈 New activity detected for $username${NC}"
                    echo ""
                fi
                last_activity_count=$activity_count
            else
                echo -e "${YELLOW}📭 No recent activity for user: $username${NC}"
                echo ""
            fi
        fi
        
        # Show general interface statistics
        show_interface_traffic_summary
        
        sleep $MONITOR_INTERVAL
    done
}

# Monitor bandwidth usage in real-time
monitor_bandwidth() {
    local duration="${1:-60}"
    local interface
    interface=$(get_primary_interface)
    
    log "📊 Monitoring bandwidth usage on $interface (${duration}s)"
    echo -e "${BLUE}Press Ctrl+C to stop monitoring${NC}"
    echo ""
    
    # Store initial values
    local start_rx start_tx
    start_rx=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
    start_tx=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
    local start_time
    start_time=$(date +%s)
    
    local end_time=$((start_time + duration))
    local prev_rx=$start_rx
    local prev_tx=$start_tx
    local prev_time=$start_time
    
    while [ $(date +%s) -lt $end_time ]; do
        clear
        echo -e "${GREEN}=== Real-time Bandwidth Monitor ===${NC}"
        echo -e "${BLUE}Interface: $interface${NC}"
        echo -e "${BLUE}Time remaining: $((end_time - $(date +%s)))s${NC}"
        echo ""
        
        # Current values
        local current_rx current_tx current_time
        current_rx=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        current_tx=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
        current_time=$(date +%s)
        
        # Calculate rates
        local time_diff=$((current_time - prev_time))
        if [ $time_diff -gt 0 ]; then
            local rx_rate tx_rate
            rx_rate=$(( (current_rx - prev_rx) / time_diff ))
            tx_rate=$(( (current_tx - prev_tx) / time_diff ))
            
            # Convert to human readable
            local rx_rate_human tx_rate_human
            rx_rate_human=$(numfmt --to=iec-i --suffix=B/s "$rx_rate" 2>/dev/null || echo "${rx_rate}B/s")
            tx_rate_human=$(numfmt --to=iec-i --suffix=B/s "$tx_rate" 2>/dev/null || echo "${tx_rate}B/s")
            
            echo -e "${YELLOW}Current Speed:${NC}"
            echo "  📥 Download: $rx_rate_human"
            echo "  📤 Upload: $tx_rate_human"
            echo ""
        fi
        
        # Total since monitoring started
        local total_rx total_tx
        total_rx=$((current_rx - start_rx))
        total_tx=$((current_tx - start_tx))
        
        local total_rx_human total_tx_human
        total_rx_human=$(numfmt --to=iec-i --suffix=B "$total_rx" 2>/dev/null || echo "${total_rx}B")
        total_tx_human=$(numfmt --to=iec-i --suffix=B "$total_tx" 2>/dev/null || echo "${total_tx}B")
        
        echo -e "${YELLOW}Session Total:${NC}"
        echo "  📥 Downloaded: $total_rx_human"
        echo "  📤 Uploaded: $total_tx_human"
        echo ""
        
        # Update previous values
        prev_rx=$current_rx
        prev_tx=$current_tx
        prev_time=$current_time
        
        sleep $MONITOR_INTERVAL
    done
    
    log "Bandwidth monitoring completed"
}

# Monitor connection quality
monitor_connection_quality() {
    local duration="${1:-60}"
    local vpn_port
    vpn_port=$(get_vpn_port)
    
    log "🔍 Monitoring connection quality (${duration}s)"
    echo -e "${BLUE}Press Ctrl+C to stop monitoring${NC}"
    echo ""
    
    local end_time=$(($(date +%s) + duration))
    local total_checks=0
    local successful_checks=0
    local failed_checks=0
    
    while [ $(date +%s) -lt $end_time ]; do
        clear
        echo -e "${GREEN}=== Connection Quality Monitor ===${NC}"
        echo -e "${BLUE}VPN Port: $vpn_port${NC}"
        echo -e "${BLUE}Time remaining: $((end_time - $(date +%s)))s${NC}"
        echo ""
        
        # Check port accessibility
        total_checks=$((total_checks + 1))
        
        if nc -z localhost "$vpn_port" 2>/dev/null; then
            successful_checks=$((successful_checks + 1))
            echo -e "${GREEN}✅ Port $vpn_port is accessible${NC}"
        else
            failed_checks=$((failed_checks + 1))
            echo -e "${RED}❌ Port $vpn_port is not accessible${NC}"
        fi
        
        # Calculate success rate
        local success_rate=0
        if [ $total_checks -gt 0 ]; then
            success_rate=$(( (successful_checks * 100) / total_checks ))
        fi
        
        echo ""
        echo -e "${YELLOW}Quality Statistics:${NC}"
        echo "  📊 Success Rate: ${success_rate}%"
        echo "  ✅ Successful: $successful_checks"
        echo "  ❌ Failed: $failed_checks"
        echo "  📋 Total Checks: $total_checks"
        echo ""
        
        # Container health check
        if command -v docker >/dev/null 2>&1; then
            local container_status
            container_status=$(docker ps --filter "name=xray" --format "{{.Status}}" 2>/dev/null || echo "Not running")
            echo -e "${YELLOW}Container Status:${NC}"
            echo "  🐳 Xray: $container_status"
            echo ""
        fi
        
        # Recent log errors
        if [ -f "/opt/v2ray/logs/error.log" ]; then
            local recent_errors
            recent_errors=$(tail -5 /opt/v2ray/logs/error.log 2>/dev/null | grep -c "ERROR" || echo "0")
            echo -e "${YELLOW}Recent Errors: $recent_errors${NC}"
            echo ""
        fi
        
        sleep $MONITOR_INTERVAL
    done
    
    log "Connection quality monitoring completed"
    echo ""
    echo -e "${GREEN}=== Final Quality Report ===${NC}"
    echo "  📊 Overall Success Rate: $((successful_checks * 100 / total_checks))%"
    echo "  ✅ Successful Checks: $successful_checks"
    echo "  ❌ Failed Checks: $failed_checks"
    echo "  📋 Total Checks: $total_checks"
}

# Generate traffic analysis report
generate_traffic_report() {
    local output_file="${1:-/tmp/traffic_report_$(date +%Y%m%d_%H%M%S).txt}"
    local interface
    interface=$(get_primary_interface)
    local vpn_port
    vpn_port=$(get_vpn_port)
    
    log "📋 Generating traffic analysis report..."
    
    {
        echo "VPN Traffic Analysis Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        # System Information
        echo "SYSTEM INFORMATION"
        echo "=================="
        echo "Primary Interface: $interface"
        echo "VPN Port: $vpn_port"
        echo "Server IP: $(curl -s https://api.ipify.org 2>/dev/null || echo 'unknown')"
        echo ""
        
        # Current Interface Statistics
        echo "INTERFACE STATISTICS"
        echo "==================="
        if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
            local rx_bytes tx_bytes
            rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
            tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
            
            echo "RX Bytes: $rx_bytes ($(numfmt --to=iec-i --suffix=B "$rx_bytes" 2>/dev/null || echo "${rx_bytes}B"))"
            echo "TX Bytes: $tx_bytes ($(numfmt --to=iec-i --suffix=B "$tx_bytes" 2>/dev/null || echo "${tx_bytes}B"))"
        else
            echo "Interface statistics not available"
        fi
        echo ""
        
        # vnstat Information
        if command -v vnstat >/dev/null 2>&1; then
            echo "VNSTAT TRAFFIC SUMMARY"
            echo "======================"
            vnstat -i "$interface" 2>/dev/null || echo "vnstat data not available"
            echo ""
        fi
        
        # Active Connections
        echo "ACTIVE CONNECTIONS"
        echo "=================="
        if [ -n "$vpn_port" ]; then
            local connections
            connections=$(ss -tn 2>/dev/null | grep ":$vpn_port" | grep ESTAB || echo "")
            
            if [ -n "$connections" ]; then
                echo "Connected clients on port $vpn_port:"
                echo "$connections" | while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        local client_ip
                        client_ip=$(echo "$line" | awk '{print $5}' | cut -d':' -f1)
                        echo "  - $client_ip"
                    fi
                done
            else
                echo "No active connections on port $vpn_port"
            fi
        else
            echo "VPN port not determined"
        fi
        echo ""
        
        # Docker Container Status
        if command -v docker >/dev/null 2>&1; then
            echo "CONTAINER STATUS"
            echo "================"
            docker ps --filter "name=xray" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not available"
            echo ""
        fi
        
        # Recent Log Activity
        if [ -f "/opt/v2ray/logs/access.log" ]; then
            echo "RECENT ACCESS LOG ACTIVITY"
            echo "=========================="
            echo "Last 10 connections:"
            tail -10 /opt/v2ray/logs/access.log 2>/dev/null || echo "Access log not available"
            echo ""
        fi
        
        if [ -f "/opt/v2ray/logs/error.log" ]; then
            echo "RECENT ERROR LOG ACTIVITY"
            echo "========================="
            echo "Last 5 errors:"
            tail -5 /opt/v2ray/logs/error.log 2>/dev/null || echo "Error log not available"
            echo ""
        fi
        
    } > "$output_file"
    
    if [ $? -eq 0 ]; then
        log "Traffic report generated: $output_file"
        echo "$output_file"
    else
        error "Failed to generate traffic report"
        return 1
    fi
}

# Main traffic monitoring menu
show_traffic_monitor_menu() {
    clear
    echo -e "${GREEN}=== Real-time Traffic Monitoring ===${NC}"
    echo ""
    
    # Initialize module
    init_traffic_monitor
    
    echo -e "${BLUE}Available monitoring options:${NC}"
    echo "  1. Monitor active connections (60s)"
    echo "  2. Monitor bandwidth usage (60s)"
    echo "  3. Monitor connection quality (60s)"
    echo "  4. Monitor specific user traffic"
    echo "  5. Generate traffic analysis report"
    echo "  6. Custom monitoring duration"
    echo "  7. Back to main menu"
    echo ""
    
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1)
            monitor_active_connections 60
            ;;
        2)
            monitor_bandwidth 60
            ;;
        3)
            monitor_connection_quality 60
            ;;
        4)
            # List users first
            if [ -d "/opt/v2ray/users" ]; then
                echo ""
                echo -e "${YELLOW}Available users:${NC}"
                ls -1 /opt/v2ray/users/*.json 2>/dev/null | while read -r user_file; do
                    if [ -f "$user_file" ]; then
                        local username
                        username=$(basename "$user_file" .json)
                        echo "  - $username"
                    fi
                done
                echo ""
            fi
            
            read -p "Enter username to monitor: " username
            if [ -n "$username" ]; then
                read -p "Enter duration in seconds [30]: " duration
                duration=${duration:-30}
                monitor_user_traffic "$username" "$duration"
            fi
            ;;
        5)
            local report_file
            report_file=$(generate_traffic_report)
            if [ -n "$report_file" ]; then
                echo ""
                echo -e "${GREEN}Report generated: $report_file${NC}"
                read -p "View report now? (y/n): " view_choice
                if [ "$view_choice" = "y" ] || [ "$view_choice" = "Y" ]; then
                    less "$report_file"
                fi
            fi
            ;;
        6)
            echo ""
            echo "Custom monitoring options:"
            echo "  1. Active connections"
            echo "  2. Bandwidth usage"
            echo "  3. Connection quality"
            read -p "Select monitoring type [1-3]: " monitor_type
            read -p "Enter duration in seconds: " duration
            
            case $monitor_type in
                1) monitor_active_connections "$duration" ;;
                2) monitor_bandwidth "$duration" ;;
                3) monitor_connection_quality "$duration" ;;
                *) warning "Invalid monitoring type" ;;
            esac
            ;;
        7)
            return 0
            ;;
        *)
            warning "Invalid choice: $choice"
            read -p "Press Enter to continue..." 
            show_traffic_monitor_menu
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to traffic monitoring menu..."
    show_traffic_monitor_menu
}

# Export functions for use by other modules
export -f init_traffic_monitor
export -f get_primary_interface
export -f get_vpn_port
export -f monitor_active_connections
export -f monitor_user_traffic
export -f monitor_bandwidth
export -f monitor_connection_quality
export -f generate_traffic_report
export -f show_traffic_monitor_menu