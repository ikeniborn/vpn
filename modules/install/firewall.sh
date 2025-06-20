#!/bin/bash

# =============================================================================
# Firewall Configuration Module
# 
# This module handles UFW firewall configuration for VPN server.
# Extracted from install_vpn.sh for modular architecture.
#
# Functions exported:
# - setup_basic_firewall()
# - setup_xray_firewall()
# - setup_outline_firewall()
# - backup_firewall_rules()
# - restore_firewall_rules()
# - check_firewall_status()
# - verify_port_access()
#
# Dependencies: lib/common.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_PATH="${PROJECT_ROOT:-$SCRIPT_DIR/../..}/lib/common.sh"
source "$COMMON_PATH" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh from $COMMON_PATH"
    exit 1
}

# =============================================================================
# FIREWALL STATUS AND CHECKS
# =============================================================================

# Check if UFW is installed and running
check_firewall_status() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Checking firewall status..."
    
    # Check if UFW is installed
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW is not installed"
        return 1
    fi
    
    # Check UFW status
    local ufw_status=$(ufw status 2>/dev/null | grep "Status:" | awk '{print $2}')
    
    case "$ufw_status" in
        "active")
            [ "$debug" = true ] && log "UFW is active"
            return 0
            ;;
        "inactive")
            [ "$debug" = true ] && log "UFW is inactive"
            return 2
            ;;
        *)
            [ "$debug" = true ] && log "UFW status unknown"
            return 3
            ;;
    esac
}

# Check if a specific port rule exists
check_port_rule_exists() {
    local port="$1"
    local protocol="${2:-tcp}"
    local debug=${3:-false}
    
    [ "$debug" = true ] && log "Checking if port rule exists: $port/$protocol"
    
    if [ -z "$port" ]; then
        error "Missing required parameter: port"
        return 1
    fi
    
    # Check if port rule exists in UFW
    if ufw status | grep -q "$port/$protocol\|$port\/$protocol"; then
        [ "$debug" = true ] && log "Port rule exists: $port/$protocol"
        return 0
    else
        [ "$debug" = true ] && log "Port rule does not exist: $port/$protocol"
        return 1
    fi
}

# Check if SSH rule exists
check_ssh_rule_exists() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Checking SSH rule..."
    
    if ufw status | grep -q "22/tcp\|OpenSSH\|ssh"; then
        [ "$debug" = true ] && log "SSH rule exists"
        return 0
    else
        [ "$debug" = true ] && log "SSH rule does not exist"
        return 1
    fi
}

# =============================================================================
# FIREWALL BACKUP AND RESTORE
# =============================================================================

# Backup current firewall rules
backup_firewall_rules() {
    local backup_dir="${1:-/opt/v2ray/backup}"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Backing up firewall rules..."
    
    # Create backup directory
    mkdir -p "$backup_dir" || {
        error "Failed to create backup directory: $backup_dir"
        return 1
    }
    
    # Backup UFW rules
    local backup_file="$backup_dir/ufw_rules_backup_$(date +%Y%m%d_%H%M%S).txt"
    
    if ufw status verbose > "$backup_file" 2>/dev/null; then
        [ "$debug" = true ] && log "Firewall rules backed up to: $backup_file"
        echo "$backup_file"
        return 0
    else
        error "Failed to backup firewall rules"
        return 1
    fi
}

# Restore firewall rules from backup
restore_firewall_rules() {
    local backup_file="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Restoring firewall rules..."
    
    if [ -z "$backup_file" ]; then
        error "Missing required parameter: backup_file"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    # Note: UFW doesn't have a direct restore function
    # This would require manual parsing and recreation of rules
    warning "UFW rule restoration requires manual implementation"
    log "Backup file location: $backup_file"
    
    return 0
}

# =============================================================================
# BASIC FIREWALL SETUP
# =============================================================================

# Setup basic firewall with SSH access
setup_basic_firewall() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Setting up basic firewall..."
    
    # Ensure SSH access
    if ! check_ssh_rule_exists "$debug"; then
        [ "$debug" = true ] && log "Adding SSH rule..."
        if ufw allow ssh; then
            log "SSH rule added successfully"
        else
            error "Failed to add SSH rule"
            return 1
        fi
    else
        [ "$debug" = true ] && log "SSH rule already exists"
    fi
    
    # Enable UFW if not active
    check_firewall_status "$debug"
    local status=$?
    if [ "$status" -ne 0 ]; then
        [ "$debug" = true ] && log "Enabling UFW firewall..."
        if ufw --force enable; then
            log "UFW firewall enabled"
        else
            error "Failed to enable UFW firewall"
            return 1
        fi
    fi
    
    [ "$debug" = true ] && log "Basic firewall setup completed"
    return 0
}

# =============================================================================
# VPN-SPECIFIC FIREWALL SETUP
# =============================================================================

# Setup firewall for Xray VPN
setup_xray_firewall() {
    local server_port="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Setting up Xray firewall..."
    
    if [ -z "$server_port" ]; then
        error "Missing required parameter: server_port"
        return 1
    fi
    
    # Setup basic firewall first
    setup_basic_firewall "$debug" || {
        error "Failed to setup basic firewall"
        return 1
    }
    
    # Add Xray server port
    if ! check_port_rule_exists "$server_port" "tcp" "$debug"; then
        [ "$debug" = true ] && log "Adding Xray server port: $server_port/tcp"
        if ufw allow "$server_port/tcp"; then
            log "Xray server port allowed: $server_port/tcp"
        else
            error "Failed to allow Xray server port: $server_port/tcp"
            return 1
        fi
    else
        [ "$debug" = true ] && log "Xray server port already allowed: $server_port/tcp"
    fi
    
    [ "$debug" = true ] && log "Xray firewall setup completed"
    return 0
}

# Setup firewall for Outline VPN
setup_outline_firewall() {
    local api_port="$1"
    local access_key_port="$2"
    local backup_dir="${3:-/opt/outline/backup}"
    local debug=${4:-false}
    
    [ "$debug" = true ] && log "Setting up Outline firewall..."
    
    if [ -z "$api_port" ] || [ -z "$access_key_port" ]; then
        error "Missing required parameters: api_port and access_key_port"
        return 1
    fi
    
    # Backup current rules
    backup_firewall_rules "$backup_dir" "$debug" || {
        warning "Failed to backup firewall rules"
    }
    
    # Setup basic firewall first
    setup_basic_firewall "$debug" || {
        error "Failed to setup basic firewall"
        return 1
    }
    
    # Add Outline API port
    if ! check_port_rule_exists "$api_port" "tcp" "$debug"; then
        [ "$debug" = true ] && log "Adding Outline API port: $api_port/tcp"
        if ufw allow "$api_port/tcp"; then
            log "Outline API port allowed: $api_port/tcp"
        else
            error "Failed to allow Outline API port: $api_port/tcp"
            return 1
        fi
    else
        [ "$debug" = true ] && log "Outline API port already allowed: $api_port/tcp"
    fi
    
    # Add Outline access key port (TCP)
    if ! check_port_rule_exists "$access_key_port" "tcp" "$debug"; then
        [ "$debug" = true ] && log "Adding Outline access key port: $access_key_port/tcp"
        if ufw allow "$access_key_port/tcp"; then
            log "Outline access key port (TCP) allowed: $access_key_port/tcp"
        else
            error "Failed to allow Outline access key port (TCP): $access_key_port/tcp"
            return 1
        fi
    else
        [ "$debug" = true ] && log "Outline access key port (TCP) already allowed: $access_key_port/tcp"
    fi
    
    # Add Outline access key port (UDP)
    if ! check_port_rule_exists "$access_key_port" "udp" "$debug"; then
        [ "$debug" = true ] && log "Adding Outline access key port: $access_key_port/udp"
        if ufw allow "$access_key_port/udp"; then
            log "Outline access key port (UDP) allowed: $access_key_port/udp"
        else
            error "Failed to allow Outline access key port (UDP): $access_key_port/udp"
            return 1
        fi
    else
        [ "$debug" = true ] && log "Outline access key port (UDP) already allowed: $access_key_port/udp"
    fi
    
    [ "$debug" = true ] && log "Outline firewall setup completed"
    return 0
}

# =============================================================================
# PORT VERIFICATION
# =============================================================================

# Verify that a port is accessible from outside
verify_port_access() {
    local port="$1"
    local protocol="${2:-tcp}"
    local debug=${3:-false}
    
    [ "$debug" = true ] && log "Verifying port access: $port/$protocol"
    
    if [ -z "$port" ]; then
        error "Missing required parameter: port"
        return 1
    fi
    
    # Check if port is in UFW rules
    if ! check_port_rule_exists "$port" "$protocol" "$debug"; then
        warning "Port $port/$protocol is not allowed in firewall"
        return 1
    fi
    
    # Check if port is actually listening
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$port "; then
            [ "$debug" = true ] && log "Port $port is listening"
        else
            warning "Port $port is not listening"
            return 2
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port "; then
            [ "$debug" = true ] && log "Port $port is listening"
        else
            warning "Port $port is not listening"
            return 2
        fi
    else
        [ "$debug" = true ] && log "Cannot verify if port is listening (netstat/ss not available)"
    fi
    
    [ "$debug" = true ] && log "Port access verification completed"
    return 0
}

# =============================================================================
# FIREWALL MANAGEMENT
# =============================================================================

# Remove a specific port rule
remove_port_rule() {
    local port="$1"
    local protocol="${2:-tcp}"
    local debug=${3:-false}
    
    [ "$debug" = true ] && log "Removing port rule: $port/$protocol"
    
    if [ -z "$port" ]; then
        error "Missing required parameter: port"
        return 1
    fi
    
    if check_port_rule_exists "$port" "$protocol" "$debug"; then
        if ufw delete allow "$port/$protocol"; then
            log "Port rule removed: $port/$protocol"
            return 0
        else
            error "Failed to remove port rule: $port/$protocol"
            return 1
        fi
    else
        [ "$debug" = true ] && log "Port rule does not exist: $port/$protocol"
        return 0
    fi
}

# Show current firewall status and rules
show_firewall_status() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Showing firewall status..."
    
    echo "=== UFW Firewall Status ==="
    ufw status verbose 2>/dev/null || {
        warning "Cannot retrieve UFW status"
        return 1
    }
    
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f check_firewall_status
export -f check_port_rule_exists
export -f check_ssh_rule_exists
export -f backup_firewall_rules
export -f restore_firewall_rules
export -f setup_basic_firewall
export -f setup_xray_firewall
export -f setup_outline_firewall
export -f verify_port_access
export -f remove_port_rule
export -f show_firewall_status

# =============================================================================
# FIREWALL CLEANUP FUNCTIONS
# =============================================================================

# Clean up unused VPN ports from firewall
cleanup_unused_vpn_ports() {
    local current_port="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Cleaning up unused VPN ports from firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        [ "$debug" = true ] && log "UFW not available, skipping port cleanup"
        return 0
    fi
    
    # Get list of currently allowed ports for VPN services
    local allowed_ports=$(ufw status numbered 2>/dev/null | grep -E "ALLOW.*tcp" | grep -v "22\|80\|443" | awk '{print $2}' | cut -d'/' -f1)
    
    # Get listening ports from running containers
    local listening_ports=""
    if command -v docker >/dev/null 2>&1; then
        # Check Xray container
        if docker ps | grep -q xray; then
            local xray_port=$(docker port xray 2>/dev/null | head -1 | cut -d':' -f2)
            [ -n "$xray_port" ] && listening_ports="$listening_ports $xray_port"
        fi
        
        # Check Outline/Shadowbox container  
        if docker ps | grep -q shadowbox; then
            local outline_ports=$(docker port shadowbox 2>/dev/null | cut -d':' -f2)
            [ -n "$outline_ports" ] && listening_ports="$listening_ports $outline_ports"
        fi
    fi
    
    # Add current port if provided
    [ -n "$current_port" ] && listening_ports="$listening_ports $current_port"
    
    [ "$debug" = true ] && log "Listening ports: $listening_ports"
    [ "$debug" = true ] && log "Allowed ports: $allowed_ports"
    
    # Remove unused ports
    local removed_count=0
    for port in $allowed_ports; do
        if [ -n "$port" ] && ! echo "$listening_ports" | grep -q "$port"; then
            [ "$debug" = true ] && log "Removing unused port from firewall: $port"
            if ufw delete allow "$port/tcp" 2>/dev/null; then
                log "Removed unused VPN port from firewall: $port/tcp"
                removed_count=$((removed_count + 1))
            else
                warning "Failed to remove port $port from firewall"
            fi
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        log "Cleaned up $removed_count unused VPN ports from firewall"
    else
        [ "$debug" = true ] && log "No unused VPN ports found in firewall"
    fi
    
    return 0
}

# Get all VPN-related ports from firewall
get_vpn_firewall_ports() {
    local debug=${1:-false}
    
    if ! command -v ufw >/dev/null 2>&1; then
        [ "$debug" = true ] && log "UFW not available"
        return 1
    fi
    
    # List all allowed ports excluding standard ones (SSH, HTTP, HTTPS)
    ufw status numbered 2>/dev/null | grep -E "ALLOW.*tcp" | grep -v -E "22|80|443" | awk '{print $2}' | cut -d'/' -f1
}

# Export new functions
export -f cleanup_unused_vpn_ports
export -f get_vpn_firewall_ports

# Debug mode check
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being run directly, show current status
    show_firewall_status true
fi