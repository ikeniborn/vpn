#!/bin/bash
#
# Traffic Statistics Module
# Handles VPN server traffic and usage statistics
# Extracted from manage_users.sh as part of Phase 5 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_statistics() {
    debug "Initializing statistics module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    debug "Statistics module initialized successfully"
}

# Get Docker container statistics
get_docker_stats() {
    debug "Getting Docker container statistics"
    
    echo -e "  ${GREEN}🐳 Docker Container Statistics:${NC}"
    
    # Check if VPN containers are running
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -q "xray\|v2ray"; then
        # Get real-time container stats
        local container_stats
        container_stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | grep -E "xray|v2ray")
        
        if [ -n "$container_stats" ]; then
            echo "$container_stats" | while IFS=$'\t' read -r name cpu mem netio blockio; do
                echo -e "    📦 Container: ${YELLOW}$name${NC}"
                echo -e "    🖥️  CPU Usage: ${YELLOW}$cpu${NC}"
                echo -e "    🧠 Memory: ${YELLOW}$mem${NC}"
                echo -e "    🌐 Network I/O: ${YELLOW}$netio${NC}"
                echo -e "    💾 Block I/O: ${YELLOW}$blockio${NC}"
            done
        else
            echo -e "    ${YELLOW}⚠️  Unable to get container statistics${NC}"
        fi
    else
        echo -e "    ${RED}❌ VPN container not running${NC}"
    fi
    
    echo ""
}

# Get network interface statistics
get_network_stats() {
    debug "Getting network interface statistics"
    
    echo -e "  ${GREEN}🌐 Network Interface Statistics:${NC}"
    
    # Determine primary network interface
    local interface
    interface=$(ip route show default 2>/dev/null | awk '/default/ { print $5 }' | head -1)
    
    if [ -z "$interface" ]; then
        interface="eth0"
        debug "Using fallback interface: $interface"
    else
        debug "Primary interface detected: $interface"
    fi
    
    # Check if vnstat is available
    if command -v vnstat >/dev/null 2>&1; then
        get_vnstat_statistics "$interface"
    else
        get_basic_network_statistics "$interface"
        offer_vnstat_installation
    fi
    
    echo ""
}

# Get vnstat statistics
get_vnstat_statistics() {
    local interface="$1"
    
    debug "Getting vnstat statistics for interface: $interface"
    
    echo -e "    📊 Interface: ${YELLOW}$interface${NC}"
    
    # Try to get JSON output for detailed stats
    if vnstat -i "$interface" --json 2>/dev/null | jq empty 2>/dev/null; then
        local json_stats
        json_stats=$(vnstat -i "$interface" --json 2>/dev/null)
        
        # Extract today's statistics
        local today_rx today_tx
        today_rx=$(echo "$json_stats" | jq -r '.interfaces[0].stats.day[] | select(.date == (now | strftime("%Y-%m-%d"))) | .rx.bytes' 2>/dev/null || echo "0")
        today_tx=$(echo "$json_stats" | jq -r '.interfaces[0].stats.day[] | select(.date == (now | strftime("%Y-%m-%d"))) | .tx.bytes' 2>/dev/null || echo "0")
        
        if [ "$today_rx" != "0" ] && [ "$today_tx" != "0" ]; then
            # Convert bytes to human readable format
            local rx_human tx_human
            rx_human=$(format_bytes "$today_rx")
            tx_human=$(format_bytes "$today_tx")
            
            echo -e "    📈 Today: RX ${YELLOW}$rx_human${NC}, TX ${YELLOW}$tx_human${NC}"
        else
            # Fallback to text output
            local today_line
            today_line=$(vnstat -i "$interface" 2>/dev/null | grep -E "today|сегодня" | head -1)
            if [ -n "$today_line" ]; then
                echo -e "    📈 $today_line"
            else
                echo -e "    ${YELLOW}⚠️  No data available for today${NC}"
            fi
        fi
        
        # Monthly statistics
        echo -e "    📊 Monthly Statistics:"
        vnstat -i "$interface" -m 2>/dev/null | tail -3 | head -1 | sed 's/^/      /'
        
    else
        # Fallback to simple vnstat output
        echo -e "    📈 Today:"
        vnstat -i "$interface" 2>/dev/null | grep -E "today|сегодня" | head -1 | sed 's/^/      /' || echo -e "      ${YELLOW}No data available${NC}"
        
        echo -e "    📊 This Month:"
        vnstat -i "$interface" -m 2>/dev/null | tail -3 | head -1 | sed 's/^/      /' || echo -e "      ${YELLOW}No data available${NC}"
    fi
}

# Get basic network statistics from /proc/net/dev
get_basic_network_statistics() {
    local interface="$1"
    
    debug "Getting basic network statistics for interface: $interface"
    
    echo -e "    📊 Interface: ${YELLOW}$interface${NC}"
    
    # Read from /proc/net/dev
    if [ -f "/proc/net/dev" ]; then
        local net_line
        net_line=$(grep -E "$interface|eth0|ens|enp" /proc/net/dev 2>/dev/null | head -1)
        
        if [ -n "$net_line" ]; then
            # Extract RX and TX bytes (fields 2 and 10)
            local rx_bytes tx_bytes
            rx_bytes=$(echo "$net_line" | awk '{print $2}')
            tx_bytes=$(echo "$net_line" | awk '{print $10}')
            
            # Format bytes to human readable
            local rx_human tx_human
            rx_human=$(format_bytes "$rx_bytes")
            tx_human=$(format_bytes "$tx_bytes")
            
            echo -e "    📈 Total: RX ${YELLOW}$rx_human${NC}, TX ${YELLOW}$tx_human${NC}"
            echo -e "    ${YELLOW}⚠️  Since boot time - install vnstat for detailed statistics${NC}"
        else
            echo -e "    ${RED}❌ Unable to read network statistics for $interface${NC}"
        fi
    else
        echo -e "    ${RED}❌ /proc/net/dev not available${NC}"
    fi
}

# Offer vnstat installation
offer_vnstat_installation() {
    debug "Offering vnstat installation"
    
    echo ""
    echo -e "  ${YELLOW}💡 vnstat not installed${NC}"
    read -p "  Install vnstat for detailed traffic statistics? (y/n): " install_vnstat
    
    if [ "$install_vnstat" = "y" ] || [ "$install_vnstat" = "Y" ]; then
        install_vnstat_package
    fi
}

# Install vnstat package
install_vnstat_package() {
    debug "Installing vnstat package"
    
    log "Installing vnstat..."
    
    if apt install -y vnstat 2>/dev/null; then
        log "vnstat successfully installed!"
        
        # Initialize vnstat database
        local interface
        interface=$(ip route show default 2>/dev/null | awk '/default/ { print $5 }' | head -1)
        
        if [ -n "$interface" ]; then
            log "Initializing vnstat database for $interface..."
            
            # Try to add interface (for older versions)
            vnstat -i "$interface" --add >/dev/null 2>&1 || {
                debug "Interface auto-initialization (modern vnstat)"
            }
            
            # Start and enable vnstat service
            if command -v systemctl >/dev/null 2>&1; then
                systemctl enable vnstat >/dev/null 2>&1
                systemctl start vnstat >/dev/null 2>&1
                
                # Wait for initialization
                sleep 2
                log "vnstat configured for interface $interface"
            fi
        else
            warning "Could not determine network interface for vnstat"
        fi
    else
        error "Failed to install vnstat"
    fi
}

# Format bytes to human readable format
format_bytes() {
    local bytes="$1"
    
    if [ -z "$bytes" ] || [ "$bytes" = "0" ]; then
        echo "0 B"
        return
    fi
    
    # Use awk for cross-platform compatibility
    awk -v bytes="$bytes" '
    BEGIN {
        units[0] = "B"
        units[1] = "KB" 
        units[2] = "MB"
        units[3] = "GB"
        units[4] = "TB"
        
        for (i = 4; i >= 0; i--) {
            if (bytes >= 1024^i) {
                printf "%.1f %s", bytes / (1024^i), units[i]
                exit
            }
        }
        printf "%.0f B", bytes
    }'
}

# Get connection statistics
get_connection_stats() {
    debug "Getting connection statistics"
    
    echo -e "  ${GREEN}🔗 Connection Statistics:${NC}"
    
    # Get VPN port from configuration
    local vpn_port
    if [ -f "$CONFIG_FILE" ]; then
        vpn_port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    if [ -n "$vpn_port" ] && [ "$vpn_port" != "null" ]; then
        echo -e "    🔌 VPN Port: ${YELLOW}$vpn_port${NC}"
        
        # Count active connections
        local connections=0
        if command -v netstat >/dev/null 2>&1; then
            connections=$(netstat -an 2>/dev/null | grep ":$vpn_port " | wc -l)
        elif command -v ss >/dev/null 2>&1; then
            connections=$(ss -an 2>/dev/null | grep ":$vpn_port " | wc -l)
        fi
        
        echo -e "    📊 Active Connections: ${YELLOW}$connections${NC}"
        
        # Show sample connections
        if [ "$connections" -gt 0 ]; then
            echo -e "    🌐 Sample Connections:"
            if command -v netstat >/dev/null 2>&1; then
                netstat -an 2>/dev/null | grep ":$vpn_port " | head -3 | while read -r line; do
                    echo -e "      $line"
                done
            elif command -v ss >/dev/null 2>&1; then
                ss -an 2>/dev/null | grep ":$vpn_port " | head -3 | while read -r line; do
                    echo -e "      $line"
                done
            fi
        fi
    else
        echo -e "    ${RED}❌ Unable to determine VPN port${NC}"
    fi
    
    echo ""
}

# Get user connection statistics from logs
get_user_connection_stats() {
    debug "Getting user connection statistics"
    
    echo -e "  ${GREEN}👥 User Connection Statistics:${NC}"
    
    local access_log="$WORK_DIR/logs/access.log"
    
    if [ -f "$access_log" ] && [ -s "$access_log" ]; then
        echo -e "    📊 Top Users by Connections:"
        
        # Extract user emails from logs and count connections
        grep -o 'email:.*' "$access_log" 2>/dev/null | \
        awk -F: '{print $2}' | \
        sort | uniq -c | sort -nr | head -5 | \
        while read -r count email; do
            echo -e "      ${YELLOW}$email${NC}: $count connections"
        done
        
        # Recent activity
        echo -e "    🕒 Recent Activity:"
        tail -5 "$access_log" 2>/dev/null | while read -r line; do
            echo -e "      $(echo "$line" | cut -c1-80)..."
        done
    else
        echo -e "    ${YELLOW}⚠️  No access logs available${NC}"
        echo -e "    💡 Configure Xray logging to track user connections"
    fi
    
    echo ""
}

# Get server uptime statistics
get_uptime_stats() {
    debug "Getting server uptime statistics"
    
    echo -e "  ${GREEN}⏱️  Server Uptime Statistics:${NC}"
    
    # System uptime
    if [ -f "/proc/uptime" ]; then
        local uptime_seconds
        uptime_seconds=$(cut -d' ' -f1 /proc/uptime)
        local uptime_formatted
        uptime_formatted=$(format_uptime "$uptime_seconds")
        echo -e "    🖥️  System Uptime: ${YELLOW}$uptime_formatted${NC}"
    fi
    
    # Container uptime
    if command -v docker >/dev/null 2>&1; then
        local container_id
        container_id=$(docker ps --format "{{.ID}}\t{{.Names}}" 2>/dev/null | grep -E "(xray|v2ray)" | head -1 | awk '{print $1}')
        
        if [ -n "$container_id" ]; then
            local start_time
            start_time=$(docker inspect --format='{{.State.StartedAt}}' "$container_id" 2>/dev/null)
            
            if [ -n "$start_time" ]; then
                echo -e "    📦 Container Started: ${YELLOW}$start_time${NC}"
                
                # Calculate runtime using Python if available
                if command -v python3 >/dev/null 2>&1; then
                    local runtime
                    runtime=$(python3 -c "
from datetime import datetime
import sys
try:
    start_time = datetime.fromisoformat('$start_time'.replace('Z', '+00:00'))
    now = datetime.now(start_time.tzinfo)
    uptime = now - start_time
    days = uptime.days
    hours, remainder = divmod(uptime.seconds, 3600)
    minutes, _ = divmod(remainder, 60)
    print(f'{days} days, {hours} hours, {minutes} minutes')
except Exception as e:
    print('unknown')
" 2>/dev/null)
                    
                    if [ "$runtime" != "unknown" ]; then
                        echo -e "    🕰️  Container Uptime: ${YELLOW}$runtime${NC}"
                    fi
                fi
            fi
        else
            echo -e "    ${RED}❌ VPN container not found${NC}"
        fi
    fi
    
    echo ""
}

# Format uptime seconds to human readable
format_uptime() {
    local seconds="$1"
    
    if [ -z "$seconds" ]; then
        echo "unknown"
        return
    fi
    
    local days hours minutes
    days=$((seconds / 86400))
    hours=$(((seconds % 86400) / 3600))
    minutes=$(((seconds % 3600) / 60))
    
    echo "${days} days, ${hours} hours, ${minutes} minutes"
}

# Get user file statistics
get_user_file_stats() {
    debug "Getting user file statistics"
    
    echo -e "  ${GREEN}📁 User File Statistics:${NC}"
    
    if [ -d "$USERS_DIR" ]; then
        local total_users
        total_users=$(find "$USERS_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
        echo -e "    👤 Total Users: ${YELLOW}$total_users${NC}"
        
        if [ "$total_users" -gt 0 ]; then
            echo -e "    📅 Recently Created Users:"
            find "$USERS_DIR" -name "*.json" -type f -printf '%T+ %p\n' 2>/dev/null | \
            sort -r | head -3 | while read -r timestamp filepath; do
                local user_name
                user_name=$(basename "$filepath" .json)
                local date_formatted
                date_formatted=$(echo "$timestamp" | cut -d'T' -f1)
                echo -e "      ${YELLOW}$user_name${NC} (created: $date_formatted)"
            done
            
            # File integrity check
            local valid_configs=0
            local invalid_configs=0
            
            find "$USERS_DIR" -name "*.json" -type f 2>/dev/null | while read -r config_file; do
                if jq empty "$config_file" 2>/dev/null; then
                    valid_configs=$((valid_configs + 1))
                else
                    invalid_configs=$((invalid_configs + 1))
                fi
            done
            
            echo -e "    ✅ Valid Configs: ${GREEN}$valid_configs${NC}"
            if [ "$invalid_configs" -gt 0 ]; then
                echo -e "    ❌ Invalid Configs: ${RED}$invalid_configs${NC}"
            fi
        fi
    else
        echo -e "    ${RED}❌ Users directory not found${NC}"
    fi
    
    echo ""
}

# Display monitoring recommendations
display_monitoring_recommendations() {
    debug "Displaying monitoring recommendations"
    
    echo -e "  ${GREEN}💡 Monitoring Recommendations:${NC}"
    
    # Check what's already configured
    local recommendations=0
    
    # vnstat check
    if ! command -v vnstat >/dev/null 2>&1; then
        echo -e "    ${RED}✗${NC} Install vnstat for detailed traffic statistics"
        recommendations=$((recommendations + 1))
    else
        echo -e "    ${GREEN}✓${NC} vnstat is installed and available"
    fi
    
    # Xray logging check
    if ! jq -e '.log' "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "    ${RED}✗${NC} Configure Xray logging for user activity tracking"
        recommendations=$((recommendations + 1))
    else
        echo -e "    ${GREEN}✓${NC} Xray logging is configured"
    fi
    
    # Log files check
    if [ ! -f "$WORK_DIR/logs/access.log" ]; then
        echo -e "    ${RED}✗${NC} Access logs not available"
        recommendations=$((recommendations + 1))
    else
        echo -e "    ${GREEN}✓${NC} Access logs are available"
    fi
    
    # Additional recommendations
    echo -e "    ${BLUE}📊${NC} Use system monitoring tools (htop, iotop, iostat)"
    echo -e "    ${BLUE}📅${NC} Set up automated reports with cron jobs"
    echo -e "    ${BLUE}🔍${NC} Monitor logs regularly for security issues"
    echo -e "    ${BLUE}📈${NC} Track performance trends over time"
    
    if [ $recommendations -eq 0 ]; then
        echo -e "    ${GREEN}🎉 All basic monitoring is properly configured!${NC}"
    else
        echo -e "    ${YELLOW}⚠️  $recommendations items need attention${NC}"
    fi
    
    echo ""
}

# Generate statistics report
generate_statistics_report() {
    local output_file="$1"
    
    debug "Generating statistics report"
    
    if [ -z "$output_file" ]; then
        output_file="$WORK_DIR/statistics_report_$(date +%Y%m%d_%H%M%S).txt"
    fi
    
    {
        echo "VPN Server Statistics Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        # Server information
        get_server_info >/dev/null 2>&1
        echo "Server Information:"
        echo "  IP: $SERVER_IP"
        echo "  Port: $SERVER_PORT"
        echo "  Protocol: $PROTOCOL"
        echo ""
        
        # User count
        local users_count
        users_count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
        echo "Users: $users_count"
        echo ""
        
        # System resources
        echo "System Resources:"
        if command -v free >/dev/null 2>&1; then
            free -h | head -2
        fi
        echo ""
        
        if command -v df >/dev/null 2>&1; then
            echo "Disk Usage:"
            df -h "$WORK_DIR" 2>/dev/null || echo "Unable to get disk usage"
        fi
        echo ""
        
        # Network statistics
        if command -v vnstat >/dev/null 2>&1; then
            local interface
            interface=$(ip route show default | awk '/default/ { print $5 }' | head -1)
            echo "Network Statistics ($interface):"
            vnstat -i "$interface" | head -10
        fi
        echo ""
        
        # Docker statistics
        echo "Docker Status:"
        docker stats --no-stream 2>/dev/null | grep -E "xray|v2ray" || echo "No VPN containers running"
        
    } > "$output_file"
    
    if [ $? -eq 0 ]; then
        log "Statistics report generated: $output_file"
        echo "$output_file"
    else
        error "Failed to generate statistics report"
    fi
}

# Main function to show traffic statistics
show_traffic_stats() {
    log "VPN Server Traffic Statistics"
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                    ${GREEN}VPN Server Statistics${NC}                        ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Initialize module
    init_statistics
    
    # Get server configuration
    get_server_info >/dev/null 2>&1
    
    # Display various statistics
    get_docker_stats
    get_network_stats
    get_connection_stats
    get_user_connection_stats
    get_uptime_stats
    get_user_file_stats
    display_monitoring_recommendations
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log "Statistics display completed"
}

# Quick statistics (minimal output)
quick_stats() {
    debug "Generating quick statistics"
    
    # Initialize module
    init_statistics
    
    # Get basic info
    get_server_info >/dev/null 2>&1
    
    local users_count container_status connections
    users_count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    
    # Check container status
    if docker ps 2>/dev/null | grep -q "xray\|v2ray"; then
        container_status="running"
    else
        container_status="stopped"
    fi
    
    # Get connection count
    if [ -n "$SERVER_PORT" ] && [ "$SERVER_PORT" != "null" ]; then
        connections=$(netstat -an 2>/dev/null | grep ":$SERVER_PORT " | wc -l)
    else
        connections="unknown"
    fi
    
    echo "Stats: Users=$users_count | Container=$container_status | Connections=$connections | Port=$SERVER_PORT"
}

# Export functions for use by other modules
export -f init_statistics
export -f get_docker_stats
export -f get_network_stats
export -f get_vnstat_statistics
export -f get_basic_network_statistics
export -f offer_vnstat_installation
export -f install_vnstat_package
export -f format_bytes
export -f get_connection_stats
export -f get_user_connection_stats
export -f get_uptime_stats
export -f format_uptime
export -f get_user_file_stats
export -f display_monitoring_recommendations
export -f generate_statistics_report
export -f show_traffic_stats
export -f quick_stats