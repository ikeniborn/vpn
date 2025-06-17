#!/bin/bash
#
# Server Restart Module
# Handles VPN server restart operations with validation and checks
# Extracted from manage_users.sh as part of Phase 4 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/docker.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_server_restart() {
    debug "Initializing server restart module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    command -v docker >/dev/null 2>&1 || {
        error "Docker is not installed or not accessible"
    }
    
    command -v docker-compose >/dev/null 2>&1 || {
        error "Docker Compose is not installed or not accessible"
    }
    
    debug "Server restart module initialized successfully"
}

# Validate server configuration before restart
validate_configuration() {
    debug "Validating server configuration before restart"
    
    # Check if config file exists and is valid JSON
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        error "Configuration file contains invalid JSON: $CONFIG_FILE"
    fi
    
    # Validate essential configuration elements
    local port protocol clients
    
    port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
    protocol=$(jq -r '.inbounds[0].protocol' "$CONFIG_FILE" 2>/dev/null)
    clients=$(jq -r '.inbounds[0].settings.clients' "$CONFIG_FILE" 2>/dev/null)
    
    if [ -z "$port" ] || [ "$port" = "null" ]; then
        error "Invalid port configuration in $CONFIG_FILE"
    fi
    
    if [ -z "$protocol" ] || [ "$protocol" = "null" ]; then
        error "Invalid protocol configuration in $CONFIG_FILE"
    fi
    
    if [ -z "$clients" ] || [ "$clients" = "null" ]; then
        warning "No clients configured in $CONFIG_FILE"
    fi
    
    # Validate port range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        error "Port $port is outside valid range (1-65535)"
    fi
    
    debug "Configuration validation passed"
    return 0
}

# Prepare logs directory and files
prepare_logs() {
    debug "Preparing logs directory and files"
    
    # Create logs directory if it doesn't exist
    mkdir -p "$WORK_DIR/logs"
    
    # Create log files if they don't exist
    touch "$WORK_DIR/logs/access.log" "$WORK_DIR/logs/error.log"
    
    # Set proper permissions
    chmod 644 "$WORK_DIR/logs/access.log" "$WORK_DIR/logs/error.log"
    
    debug "Logs prepared successfully"
}

# Validate and fix port configuration
validate_port_configuration() {
    debug "Validating port configuration consistency"
    
    # Check if saved port file exists
    if [ -f "$WORK_DIR/config/port.txt" ]; then
        local saved_port current_port
        
        saved_port=$(cat "$WORK_DIR/config/port.txt" 2>/dev/null)
        current_port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
        
        if [ -n "$saved_port" ] && [ -n "$current_port" ] && [ "$saved_port" != "$current_port" ]; then
            warning "Port mismatch detected! Saved: $saved_port, Current: $current_port"
            log "Restoring saved port configuration: $saved_port"
            
            # Restore the correct port in configuration
            if jq ".inbounds[0].port = $saved_port" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
                mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                log "Port configuration restored successfully"
            else
                rm -f "$CONFIG_FILE.tmp"
                error "Failed to restore port configuration"
            fi
        fi
    else
        # Create port file from current configuration
        local current_port
        current_port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
        
        if [ -n "$current_port" ] && [ "$current_port" != "null" ]; then
            echo "$current_port" > "$WORK_DIR/config/port.txt"
            debug "Port file created with current port: $current_port"
        fi
    fi
}

# Fix docker-compose configuration if needed
fix_docker_compose_config() {
    debug "Checking docker-compose configuration"
    
    local compose_file="$WORK_DIR/docker-compose.yml"
    
    if [ -f "$compose_file" ]; then
        # Check for old log path configuration
        if grep -q "./logs:/var/log/xray" "$compose_file"; then
            log "Updating docker-compose.yml with correct log paths..."
            
            # Update log path
            sed -i 's|./logs:/var/log/xray|./logs:/opt/v2ray/logs|g' "$compose_file"
            
            debug "Docker-compose configuration updated"
            return 2  # Signal that container needs to be recreated
        fi
    else
        warning "Docker-compose file not found: $compose_file"
    fi
    
    return 0
}

# Stop server gracefully
stop_server() {
    debug "Stopping VPN server gracefully"
    
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    log "Stopping VPN server..."
    
    if docker-compose down 2>/dev/null; then
        debug "Server stopped successfully"
        return 0
    else
        warning "Failed to stop server gracefully"
        return 1
    fi
}

# Start server
start_server() {
    debug "Starting VPN server"
    
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    log "Starting VPN server..."
    
    if docker-compose up -d 2>/dev/null; then
        debug "Server started successfully"
        return 0
    else
        error "Failed to start server"
        return 1
    fi
}

# Restart server (standard restart)
restart_server_standard() {
    debug "Performing standard server restart"
    
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    log "Restarting VPN server..."
    
    if docker-compose restart 2>/dev/null; then
        debug "Server restarted successfully"
        return 0
    else
        error "Failed to restart server"
        return 1
    fi
}

# Recreate server (full recreation)
recreate_server() {
    debug "Recreating VPN server completely"
    
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    log "Recreating VPN server..."
    
    # Stop and remove containers
    if ! docker-compose down 2>/dev/null; then
        warning "Failed to stop containers gracefully"
    fi
    
    # Start containers fresh
    if docker-compose up -d 2>/dev/null; then
        log "VPN server recreated successfully"
        debug "Server recreation completed"
        return 0
    else
        error "Failed to recreate server"
        return 1
    fi
}

# Verify server is running after restart
verify_server_status() {
    debug "Verifying server status after restart"
    
    cd "$WORK_DIR" || {
        warning "Cannot verify status - work directory not accessible"
        return 1
    }
    
    # Wait a moment for container to fully start
    sleep 3
    
    # Check if container is running
    if docker-compose ps 2>/dev/null | grep -q "Up"; then
        log "✅ Server is running"
        debug "Server status verification passed"
        return 0
    else
        warning "❌ Server may not be running properly"
        debug "Server status verification failed"
        return 1
    fi
}

# Check for port conflicts
check_port_conflicts() {
    local port="$1"
    
    debug "Checking for port conflicts: $port"
    
    if [ -z "$port" ] || [ "$port" = "null" ]; then
        debug "No valid port provided for conflict check"
        return 0
    fi
    
    # Check if port is already in use by another process
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":$port.*LISTEN"; then
            local process_info
            process_info=$(netstat -tulnp 2>/dev/null | grep ":$port.*LISTEN" | head -1)
            
            # Check if it's our Docker container
            if echo "$process_info" | grep -q "docker"; then
                debug "Port $port is used by our Docker container"
                return 0
            else
                warning "Port $port is in use by another process:"
                echo "$process_info"
                return 1
            fi
        fi
    fi
    
    debug "No port conflicts detected"
    return 0
}

# Main restart function with full validation
restart_server() {
    log "🔄 Restarting VPN server..."
    echo ""
    
    # Initialize module
    init_server_restart
    
    # Validate configuration before restart
    if ! validate_configuration; then
        error "Configuration validation failed. Restart aborted."
    fi
    
    # Prepare logs
    prepare_logs
    
    # Validate port configuration
    validate_port_configuration
    
    # Check docker-compose configuration
    local needs_recreation=false
    fix_docker_compose_config
    local compose_result=$?
    
    if [ $compose_result -eq 2 ]; then
        needs_recreation=true
        log "Docker-compose configuration updated - container recreation required"
    fi
    
    # Get current port for conflict checking
    local current_port
    current_port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
    
    # Check for port conflicts
    if ! check_port_conflicts "$current_port"; then
        warning "Port conflicts detected, but proceeding with restart"
    fi
    
    # Perform restart based on requirements
    if [ "$needs_recreation" = true ]; then
        if recreate_server; then
            log "✅ VPN server recreated with updated configuration!"
        else
            error "Failed to recreate VPN server"
        fi
    else
        if restart_server_standard; then
            log "✅ VPN server restarted successfully!"
        else
            error "Failed to restart VPN server"
        fi
    fi
    
    # Verify server is running
    verify_server_status
    
    echo ""
    log "Server restart operation completed"
}

# Restart with force recreation
force_restart() {
    log "🔄 Force restarting VPN server (full recreation)..."
    echo ""
    
    # Initialize module
    init_server_restart
    
    # Validate configuration
    if ! validate_configuration; then
        error "Configuration validation failed. Force restart aborted."
    fi
    
    # Prepare logs
    prepare_logs
    
    # Validate port configuration
    validate_port_configuration
    
    # Force recreation
    if recreate_server; then
        log "✅ VPN server force restarted successfully!"
    else
        error "Failed to force restart VPN server"
    fi
    
    # Verify server is running
    verify_server_status
    
    echo ""
    log "Force restart operation completed"
}

# Graceful restart with user confirmation
graceful_restart() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        🔄 ${GREEN}Server Restart${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get current status
    get_server_info >/dev/null 2>&1
    
    echo -e "  ${GREEN}Current Configuration:${NC}"
    echo -e "    📍 IP: ${YELLOW}$SERVER_IP${NC}"
    echo -e "    🔌 Port: ${YELLOW}$SERVER_PORT${NC}"
    echo -e "    🔒 Protocol: ${YELLOW}$PROTOCOL${NC}"
    
    local users_count
    users_count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    echo -e "    👥 Users: ${YELLOW}$users_count${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  This will briefly disconnect all active VPN connections${NC}"
    echo ""
    
    local confirmation
    read -p "Continue with server restart? [yes/no]: " confirmation
    
    if [ "$confirmation" = "yes" ]; then
        restart_server
    else
        log "Server restart cancelled by user"
    fi
}

# Quick restart (minimal validation)
quick_restart() {
    debug "Performing quick server restart"
    
    # Initialize module
    init_server_restart
    
    cd "$WORK_DIR" || error "Failed to change to work directory: $WORK_DIR"
    
    if docker-compose restart >/dev/null 2>&1; then
        log "✅ Server restarted quickly"
    else
        error "Quick restart failed"
    fi
}

# Export functions for use by other modules
export -f init_server_restart
export -f validate_configuration
export -f prepare_logs
export -f validate_port_configuration
export -f fix_docker_compose_config
export -f stop_server
export -f start_server
export -f restart_server_standard
export -f recreate_server
export -f verify_server_status
export -f check_port_conflicts
export -f restart_server
export -f force_restart
export -f graceful_restart
export -f quick_restart