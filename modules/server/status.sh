#!/bin/bash
#
# Server Status Module
# Handles displaying VPN server status and health checks
# Extracted from manage_users.sh as part of Phase 4 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/docker.sh"
source "$PROJECT_DIR/lib/network.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_server_status() {
    debug "Initializing server status module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    debug "Server status module initialized successfully"
}

# Check Docker container status
check_container_status() {
    debug "Checking Docker container status"
    
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    echo -e "  ${GREEN}🐳 Docker Container:${NC}"
    
    if docker-compose ps 2>/dev/null; then
        debug "Docker compose status retrieved successfully"
    else
        warning "Failed to get Docker compose status"
        echo -e "    ${RED}❌ Unable to get container status${NC}"
        return 1
    fi
    
    echo ""
    return 0
}

# Check port accessibility
check_port_status() {
    local port="$1"
    
    debug "Checking port status: $port"
    
    echo -e "  ${GREEN}🔌 Port Status:${NC}"
    
    if [ -z "$port" ] || [ "$port" = "null" ]; then
        echo -e "    ${RED}❌ Invalid port configuration${NC}"
        return 1
    fi
    
    # Check with multiple tools for better compatibility
    local port_open=false
    
    # Try netstat first
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":$port"; then
            port_open=true
            debug "Port check successful with netstat"
        fi
    # Try ss as alternative
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -q ":$port"; then
            port_open=true
            debug "Port check successful with ss"
        fi
    # Try lsof as fallback
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i ":$port" -P -n 2>/dev/null | grep -q "LISTEN"; then
            port_open=true
            debug "Port check successful with lsof"
        fi
    fi
    
    if [ "$port_open" = true ]; then
        echo -e "    ✅ Port ${YELLOW}$port${NC} is open and listening"
        
        # Additional connectivity check
        if check_port_external_access "$port"; then
            echo -e "    ✅ Port ${YELLOW}$port${NC} is externally accessible"
        else
            echo -e "    ⚠️  Port ${YELLOW}$port${NC} may not be externally accessible"
        fi
    else
        echo -e "    ❌ Port ${YELLOW}$port${NC} is closed or not listening!"
        
        # Try to determine the cause
        if ! docker-compose ps 2>/dev/null | grep -q "Up"; then
            echo -e "    💡 Container may be stopped"
        elif ! command -v netstat >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
            echo -e "    💡 Install netstat, ss, or lsof to check port status"
        fi
    fi
    
    echo ""
    return 0
}

# Check external port accessibility
check_port_external_access() {
    local port="$1"
    
    debug "Checking external access for port: $port"
    
    # Get server IP
    local server_ip
    server_ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null)
    
    if [ -z "$server_ip" ]; then
        debug "Failed to get server IP for external check"
        return 1
    fi
    
    # Try to connect to the port from outside (basic check)
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -z "$server_ip" "$port" 2>/dev/null; then
            debug "External port access confirmed with netcat"
            return 0
        fi
    fi
    
    debug "External port access check failed or unavailable"
    return 1
}

# Display server information
display_server_info() {
    debug "Displaying server information"
    
    # Get server configuration
    get_server_info
    
    echo -e "  ${GREEN}🌐 Server Information:${NC}"
    echo -e "    📍 IP Address: ${YELLOW}$SERVER_IP${NC}"
    echo -e "    🔌 Port: ${YELLOW}$SERVER_PORT${NC}"
    echo -e "    🔒 Protocol: ${YELLOW}$PROTOCOL${NC}"
    echo -e "    🌐 SNI: ${YELLOW}$SERVER_SNI${NC}"
    
    # Display Reality-specific information
    if [ "$USE_REALITY" = true ]; then
        echo -e "    🔐 Reality: ${GREEN}✓ Active${NC}"
        
        # Show key information if available
        if [ -n "$PUBLIC_KEY" ] && [ "$PUBLIC_KEY" != "null" ] && [ "$PUBLIC_KEY" != "unknown" ]; then
            echo -e "    🔑 Public Key: ${WHITE}${PUBLIC_KEY:0:20}...${NC}"
        fi
        
        if [ -n "$SHORT_ID" ] && [ "$SHORT_ID" != "null" ]; then
            echo -e "    🆔 Short ID: ${WHITE}$SHORT_ID${NC}"
        fi
    else
        echo -e "    🔐 Reality: ${RED}✗ Not used${NC}"
    fi
    
    # SNI validation
    if [ "$SERVER_SNI" = "null" ] || [ -z "$SERVER_SNI" ]; then
        echo -e "    ⚠️  SNI not configured"
    fi
    
    echo ""
}

# Display user statistics
display_user_statistics() {
    debug "Displaying user statistics"
    
    echo -e "  ${GREEN}👥 Users:${NC}"
    
    local users_count
    users_count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    
    echo -e "    👤 Total Users: ${YELLOW}$users_count${NC}"
    
    # Additional user information if users exist
    if [ "$users_count" -gt 0 ]; then
        # Show user names
        local user_names
        mapfile -t user_names < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE" 2>/dev/null)
        
        if [ ${#user_names[@]} -gt 0 ]; then
            echo -e "    📋 User List:"
            for user_name in "${user_names[@]}"; do
                # Check if user files exist
                local status_icon="✅"
                if [ ! -f "$USERS_DIR/$user_name.json" ] || [ ! -f "$USERS_DIR/$user_name.link" ]; then
                    status_icon="⚠️"
                fi
                echo -e "      $status_icon $user_name"
            done
        fi
    else
        echo -e "    💭 No users configured"
    fi
    
    echo ""
}

# Check system resources
check_system_resources() {
    debug "Checking system resources"
    
    echo -e "  ${GREEN}💻 System Resources:${NC}"
    
    # CPU usage
    if command -v top >/dev/null 2>&1; then
        local cpu_usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "unknown")
        echo -e "    🖥️  CPU Usage: ${YELLOW}$cpu_usage${NC}"
    fi
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        local mem_info
        mem_info=$(free -h | grep "Mem:" | awk '{printf "Used: %s / Total: %s (%.1f%%)", $3, $2, ($3/$2)*100}' 2>/dev/null || echo "unknown")
        echo -e "    🧠 Memory: ${YELLOW}$mem_info${NC}"
    fi
    
    # Disk usage
    if command -v df >/dev/null 2>&1; then
        local disk_usage
        disk_usage=$(df -h "$WORK_DIR" 2>/dev/null | tail -1 | awk '{printf "Used: %s / Total: %s (%s)", $3, $2, $5}' || echo "unknown")
        echo -e "    💾 Disk Usage: ${YELLOW}$disk_usage${NC}"
    fi
    
    # Docker system info
    if command -v docker >/dev/null 2>&1; then
        local docker_info
        docker_info=$(docker system df 2>/dev/null | grep "Images" | awk '{printf "%s images, %s", $4, $3}' || echo "unknown")
        echo -e "    🐳 Docker: ${YELLOW}$docker_info${NC}"
    fi
    
    echo ""
}

# Check service health
check_service_health() {
    debug "Checking service health"
    
    echo -e "  ${GREEN}🏥 Health Checks:${NC}"
    
    # Container health
    local container_healthy=false
    if cd "$WORK_DIR" 2>/dev/null && docker-compose ps 2>/dev/null | grep -q "Up"; then
        container_healthy=true
        echo -e "    ✅ Container Status: ${GREEN}Healthy${NC}"
    else
        echo -e "    ❌ Container Status: ${RED}Unhealthy${NC}"
    fi
    
    # Configuration file integrity
    if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo -e "    ✅ Configuration: ${GREEN}Valid${NC}"
    else
        echo -e "    ❌ Configuration: ${RED}Invalid or missing${NC}"
    fi
    
    # User directory integrity
    if [ -d "$USERS_DIR" ]; then
        local user_files_count
        user_files_count=$(find "$USERS_DIR" -name "*.json" | wc -l 2>/dev/null || echo "0")
        echo -e "    ✅ User Files: ${GREEN}$user_files_count files found${NC}"
    else
        echo -e "    ⚠️  User Directory: ${YELLOW}Missing${NC}"
    fi
    
    # Log files
    if [ -f "$WORK_DIR/logs/access.log" ] && [ -f "$WORK_DIR/logs/error.log" ]; then
        echo -e "    ✅ Log Files: ${GREEN}Available${NC}"
    else
        echo -e "    ⚠️  Log Files: ${YELLOW}Not configured${NC}"
    fi
    
    # Network connectivity
    if curl -s --connect-timeout 5 https://api.ipify.org >/dev/null 2>&1; then
        echo -e "    ✅ Internet: ${GREEN}Connected${NC}"
    else
        echo -e "    ❌ Internet: ${RED}Connection issues${NC}"
    fi
    
    echo ""
}

# Display connection statistics
display_connection_stats() {
    debug "Displaying connection statistics"
    
    echo -e "  ${GREEN}📊 Connection Statistics:${NC}"
    
    # Active connections to VPN port
    local port
    port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
    
    if [ -n "$port" ] && [ "$port" != "null" ]; then
        local active_connections=0
        
        if command -v netstat >/dev/null 2>&1; then
            active_connections=$(netstat -an 2>/dev/null | grep ":$port" | grep "ESTABLISHED" | wc -l || echo "0")
        elif command -v ss >/dev/null 2>&1; then
            active_connections=$(ss -an 2>/dev/null | grep ":$port" | grep "ESTAB" | wc -l || echo "0")
        fi
        
        echo -e "    🔗 Active Connections: ${YELLOW}$active_connections${NC}"
        
        # Connection rate (if logs are available)
        if [ -f "$WORK_DIR/logs/access.log" ]; then
            local recent_connections
            recent_connections=$(tail -n 100 "$WORK_DIR/logs/access.log" 2>/dev/null | wc -l || echo "0")
            echo -e "    📈 Recent Log Entries: ${YELLOW}$recent_connections${NC}"
        fi
    else
        echo -e "    ❌ Unable to determine VPN port"
    fi
    
    echo ""
}

# Generate status report
generate_status_report() {
    local output_file="$1"
    
    debug "Generating status report"
    
    if [ -z "$output_file" ]; then
        output_file="$WORK_DIR/status_report_$(date +%Y%m%d_%H%M%S).txt"
    fi
    
    {
        echo "VPN Server Status Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        # Get all status information (redirect to capture output)
        get_server_info >/dev/null 2>&1
        
        echo "Server Information:"
        echo "  IP: $SERVER_IP"
        echo "  Port: $SERVER_PORT"
        echo "  Protocol: $PROTOCOL"
        echo "  SNI: $SERVER_SNI"
        echo "  Reality: $USE_REALITY"
        echo ""
        
        echo "Users: $(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")"
        echo ""
        
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
        
        echo "Docker Status:"
        cd "$WORK_DIR" 2>/dev/null && docker-compose ps 2>/dev/null || echo "Unable to get Docker status"
        
    } > "$output_file"
    
    if [ $? -eq 0 ]; then
        log "Status report generated: $output_file"
    else
        error "Failed to generate status report"
    fi
}

# Main function to show server status
show_status() {
    log "VPN Server Status Check..."
    
    # Initialize module
    init_server_status
    
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        📊 ${GREEN}VPN Server Status${NC}         ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check Docker container status
    check_container_status
    
    # Get server port for checks
    local server_port
    server_port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
    
    # Check port status
    check_port_status "$server_port"
    
    # Display server information
    display_server_info
    
    # Display user statistics
    display_user_statistics
    
    # Check system resources
    check_system_resources
    
    # Check service health
    check_service_health
    
    # Display connection statistics
    display_connection_stats
    
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    
    log "Status check completed"
}

# Quick status check (minimal output)
quick_status() {
    debug "Performing quick status check"
    
    # Initialize module
    init_server_status
    
    # Get basic info
    get_server_info >/dev/null 2>&1
    
    local users_count
    users_count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    
    # Check if container is running
    local container_status="stopped"
    if cd "$WORK_DIR" 2>/dev/null && docker-compose ps 2>/dev/null | grep -q "Up"; then
        container_status="running"
    fi
    
    echo "Status: $container_status | Users: $users_count | Port: $SERVER_PORT | Protocol: $PROTOCOL"
}

# Export functions for use by other modules
export -f init_server_status
export -f check_container_status
export -f check_port_status
export -f check_port_external_access
export -f display_server_info
export -f display_user_statistics
export -f check_system_resources
export -f check_service_health
export -f display_connection_stats
export -f generate_status_report
export -f show_status
export -f quick_status