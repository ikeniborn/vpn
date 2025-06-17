#!/bin/bash
#
# Logging Configuration Module
# Handles Xray logging configuration and management
# Extracted from manage_users.sh as part of Phase 5 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_logging() {
    debug "Initializing logging module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    # Ensure logs directory exists
    mkdir -p "$WORK_DIR/logs"
    
    debug "Logging module initialized successfully"
}

# Check current logging configuration
check_logging_config() {
    debug "Checking current logging configuration"
    
    if jq -e '.log' "$CONFIG_FILE" >/dev/null 2>&1; then
        debug "Logging configuration found in config file"
        return 0
    else
        debug "No logging configuration found"
        return 1
    fi
}

# Get current logging settings
get_current_logging_settings() {
    debug "Getting current logging settings"
    
    if check_logging_config; then
        local access_log error_log log_level
        
        access_log=$(jq -r '.log.access // "not configured"' "$CONFIG_FILE" 2>/dev/null)
        error_log=$(jq -r '.log.error // "not configured"' "$CONFIG_FILE" 2>/dev/null)
        log_level=$(jq -r '.log.loglevel // "warning"' "$CONFIG_FILE" 2>/dev/null)
        
        echo "access_log:$access_log"
        echo "error_log:$error_log"
        echo "log_level:$log_level"
    else
        echo "access_log:not configured"
        echo "error_log:not configured"
        echo "log_level:not configured"
    fi
}

# Display current logging settings
display_current_logging() {
    debug "Displaying current logging settings"
    
    echo -e "  ${GREEN}📊 Current Logging Configuration:${NC}"
    
    if check_logging_config; then
        local settings
        settings=$(get_current_logging_settings)
        
        local access_log error_log log_level
        access_log=$(echo "$settings" | grep "access_log:" | cut -d: -f2-)
        error_log=$(echo "$settings" | grep "error_log:" | cut -d: -f2-)
        log_level=$(echo "$settings" | grep "log_level:" | cut -d: -f2-)
        
        echo -e "    📝 Access Log: ${YELLOW}$access_log${NC}"
        echo -e "    🚨 Error Log: ${YELLOW}$error_log${NC}"
        echo -e "    📊 Log Level: ${YELLOW}$log_level${NC}"
        
        # Check if log files exist
        if [ -f "$access_log" ]; then
            local file_size
            file_size=$(du -h "$access_log" 2>/dev/null | cut -f1)
            echo -e "    📄 Access Log Size: ${YELLOW}$file_size${NC}"
        fi
        
        if [ -f "$error_log" ]; then
            local file_size
            file_size=$(du -h "$error_log" 2>/dev/null | cut -f1)
            echo -e "    📄 Error Log Size: ${YELLOW}$file_size${NC}"
        fi
    else
        echo -e "    ${RED}❌ Logging not configured${NC}"
    fi
    
    echo ""
}

# Select log level interactively
select_log_level() {
    debug "Selecting log level interactively"
    
    echo -e "  ${GREEN}📊 Select Log Level:${NC}"
    echo "    1. none - No logging (not recommended)"
    echo "    2. error - Only errors"
    echo "    3. warning - Warnings and errors (recommended)"
    echo "    4. info - Informational messages"
    echo "    5. debug - Detailed logs (for troubleshooting only)"
    echo ""
    
    local log_level_choice
    read -p "  Choose log level [1-5, default: 3]: " log_level_choice
    
    case ${log_level_choice:-3} in
        1) echo "none" ;;
        2) echo "error" ;;
        3) echo "warning" ;;
        4) echo "info" ;;
        5) echo "debug" ;;
        *) echo "warning" ;;
    esac
}

# Configure log paths
configure_log_paths() {
    debug "Configuring log paths"
    
    local access_log_path="$WORK_DIR/logs/access.log"
    local error_log_path="$WORK_DIR/logs/error.log"
    
    # Ensure logs directory exists
    mkdir -p "$WORK_DIR/logs"
    
    # Create log files if they don't exist
    touch "$access_log_path" "$error_log_path"
    chmod 644 "$access_log_path" "$error_log_path"
    
    debug "Log paths configured: access=$access_log_path, error=$error_log_path"
    echo "$access_log_path:$error_log_path"
}

# Update logging configuration in config file
update_logging_config() {
    local access_log_path="$1"
    local error_log_path="$2"
    local log_level="$3"
    
    debug "Updating logging configuration: level=$log_level"
    
    # Create backup of config
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update configuration with jq
    local temp_config="$CONFIG_FILE.tmp"
    
    if jq ".log = {
        \"access\": \"$access_log_path\",
        \"error\": \"$error_log_path\",
        \"loglevel\": \"$log_level\"
    }" "$CONFIG_FILE" > "$temp_config"; then
        mv "$temp_config" "$CONFIG_FILE"
        debug "Configuration updated successfully"
        return 0
    else
        rm -f "$temp_config"
        error "Failed to update logging configuration"
        return 1
    fi
}

# Restart server to apply logging changes
restart_server_for_logging() {
    debug "Restarting server to apply logging changes"
    
    # Check if restart module is available
    if [ -f "$PROJECT_DIR/modules/server/restart.sh" ]; then
        source "$PROJECT_DIR/modules/server/restart.sh"
        
        if declare -F restart_server >/dev/null; then
            log "Restarting server to apply logging configuration..."
            restart_server
            return $?
        fi
    fi
    
    # Fallback restart method
    log "Restarting server to apply logging configuration..."
    
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    if docker-compose restart >/dev/null 2>&1; then
        log "✅ Server restarted successfully"
        return 0
    else
        error "Failed to restart server"
        return 1
    fi
}

# Display logging setup summary
display_logging_summary() {
    local access_log_path="$1"
    local error_log_path="$2"
    local log_level="$3"
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                    ${GREEN}Logging Configuration Summary${NC}                ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}✅ Xray logging successfully configured!${NC}"
    echo ""
    echo -e "  ${GREEN}📊 Configuration Details:${NC}"
    echo -e "    📝 Access Log: ${YELLOW}$access_log_path${NC}"
    echo -e "    🚨 Error Log: ${YELLOW}$error_log_path${NC}"
    echo -e "    📊 Log Level: ${YELLOW}$log_level${NC}"
    echo ""
    echo -e "  ${GREEN}🛠️  Useful Commands:${NC}"
    echo -e "    📖 Monitor connections: ${WHITE}tail -f $access_log_path${NC}"
    echo -e "    🚨 Monitor errors: ${WHITE}tail -f $error_log_path${NC}"
    echo -e "    🔍 Search user activity: ${WHITE}grep 'username' $access_log_path${NC}"
    echo -e "    📊 View last 20 entries: ${WHITE}tail -20 $access_log_path${NC}"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Remove logging configuration
remove_logging_config() {
    debug "Removing logging configuration"
    
    echo ""
    echo -e "${YELLOW}⚠️  This will disable all Xray logging${NC}"
    echo ""
    
    local confirmation
    read -p "Continue with logging removal? [yes/no]: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Logging removal cancelled"
        return 0
    fi
    
    # Create backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove log section from config
    local temp_config="$CONFIG_FILE.tmp"
    
    if jq 'del(.log)' "$CONFIG_FILE" > "$temp_config"; then
        mv "$temp_config" "$CONFIG_FILE"
        log "Logging configuration removed"
        
        # Restart server
        restart_server_for_logging
        
        log "✅ Logging disabled successfully"
    else
        rm -f "$temp_config"
        error "Failed to remove logging configuration"
    fi
}

# Set specific log level
set_log_level() {
    local new_log_level="$1"
    
    debug "Setting log level to: $new_log_level"
    
    if ! check_logging_config; then
        error "Logging not configured. Configure logging first."
    fi
    
    # Validate log level
    case "$new_log_level" in
        none|error|warning|info|debug)
            debug "Valid log level: $new_log_level"
            ;;
        *)
            error "Invalid log level: $new_log_level. Valid levels: none, error, warning, info, debug"
            ;;
    esac
    
    # Update only the log level
    local temp_config="$CONFIG_FILE.tmp"
    
    if jq ".log.loglevel = \"$new_log_level\"" "$CONFIG_FILE" > "$temp_config"; then
        mv "$temp_config" "$CONFIG_FILE"
        log "Log level updated to: $new_log_level"
        
        # Restart server
        restart_server_for_logging
        
        log "✅ Log level change applied"
    else
        rm -f "$temp_config"
        error "Failed to update log level"
    fi
}

# Rotate log files
rotate_logs() {
    debug "Rotating log files"
    
    local access_log="$WORK_DIR/logs/access.log"
    local error_log="$WORK_DIR/logs/error.log"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    local rotated=0
    
    # Rotate access log
    if [ -f "$access_log" ] && [ -s "$access_log" ]; then
        mv "$access_log" "$access_log.$timestamp"
        touch "$access_log"
        chmod 644 "$access_log"
        log "Access log rotated: $access_log.$timestamp"
        rotated=$((rotated + 1))
    fi
    
    # Rotate error log
    if [ -f "$error_log" ] && [ -s "$error_log" ]; then
        mv "$error_log" "$error_log.$timestamp"
        touch "$error_log"
        chmod 644 "$error_log"
        log "Error log rotated: $error_log.$timestamp"
        rotated=$((rotated + 1))
    fi
    
    if [ $rotated -gt 0 ]; then
        # Restart server to use new log files
        restart_server_for_logging
        log "✅ Log rotation completed ($rotated files rotated)"
    else
        log "No logs to rotate (files are empty or don't exist)"
    fi
}

# Setup automatic log rotation with logrotate
setup_log_rotation() {
    debug "Setting up automatic log rotation"
    
    local logrotate_config="/etc/logrotate.d/xray-vpn"
    
    cat > "$logrotate_config" <<EOL
$WORK_DIR/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # Restart Xray container to use new log files
        cd $WORK_DIR && docker-compose restart > /dev/null 2>&1 || true
    endscript
}
EOL
    
    if [ $? -eq 0 ]; then
        log "Automatic log rotation configured"
        log "Logs will be rotated daily and kept for 7 days"
        
        # Test the configuration
        if logrotate -d "$logrotate_config" >/dev/null 2>&1; then
            log "✅ Log rotation configuration validated"
        else
            warning "Log rotation configuration may have issues"
        fi
    else
        error "Failed to setup automatic log rotation"
    fi
}

# Main function to configure Xray logging
configure_xray_logging() {
    log "🔧 Configuring Xray logging for user tracking..."
    echo ""
    
    # Initialize module
    init_logging
    
    # Display current configuration
    display_current_logging
    
    # Check if logging is already configured
    if check_logging_config; then
        echo -e "  ${GREEN}📊 Logging is already configured${NC}"
        echo ""
        
        local update_choice
        read -p "  Update logging configuration? (y/n): " update_choice
        
        if [ "$update_choice" != "y" ] && [ "$update_choice" != "Y" ]; then
            log "Logging configuration unchanged"
            return 0
        fi
        
        echo ""
    fi
    
    # Configure log paths
    local log_paths access_log_path error_log_path
    log_paths=$(configure_log_paths)
    access_log_path=$(echo "$log_paths" | cut -d: -f1)
    error_log_path=$(echo "$log_paths" | cut -d: -f2)
    
    # Select log level
    local log_level
    log_level=$(select_log_level)
    
    log "Configuring logging with level: $log_level"
    
    # Update configuration
    if update_logging_config "$access_log_path" "$error_log_path" "$log_level"; then
        # Restart server
        restart_server_for_logging
        
        # Display summary
        display_logging_summary "$access_log_path" "$error_log_path" "$log_level"
        
        # Offer to setup log rotation
        echo ""
        local rotation_choice
        read -p "  Setup automatic log rotation? (y/n): " rotation_choice
        
        if [ "$rotation_choice" = "y" ] || [ "$rotation_choice" = "Y" ]; then
            setup_log_rotation
        fi
        
        log "Xray logging configuration completed successfully!"
    else
        error "Failed to configure Xray logging"
    fi
}

# Quick logging setup with defaults
quick_logging_setup() {
    debug "Setting up logging with default configuration"
    
    # Initialize module
    init_logging
    
    # Configure with default settings
    local log_paths access_log_path error_log_path
    log_paths=$(configure_log_paths)
    access_log_path=$(echo "$log_paths" | cut -d: -f1)
    error_log_path=$(echo "$log_paths" | cut -d: -f2)
    
    # Use warning level as default
    local log_level="warning"
    
    # Update configuration
    if update_logging_config "$access_log_path" "$error_log_path" "$log_level"; then
        restart_server_for_logging
        log "✅ Quick logging setup completed (level: warning)"
    else
        error "Failed to setup logging"
    fi
}

# Export functions for use by other modules
export -f init_logging
export -f check_logging_config
export -f get_current_logging_settings
export -f display_current_logging
export -f select_log_level
export -f configure_log_paths
export -f update_logging_config
export -f restart_server_for_logging
export -f display_logging_summary
export -f remove_logging_config
export -f set_log_level
export -f rotate_logs
export -f setup_log_rotation
export -f configure_xray_logging
export -f quick_logging_setup