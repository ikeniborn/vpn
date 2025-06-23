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
    
    # Install UFW if not present
    if ! command -v ufw >/dev/null 2>&1; then
        log "Installing UFW firewall..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y ufw || {
                error "Failed to install UFW"
                return 1
            }
        elif command -v yum >/dev/null 2>&1; then
            yum install -y ufw || {
                error "Failed to install UFW"
                return 1
            }
        else
            error "Package manager not supported for UFW installation"
            return 1
        fi
        log "UFW installed successfully"
    fi
    
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
        if ufw allow "$server_port/tcp" comment "Xray VLESS+Reality VPN"; then
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
        if ufw allow "$api_port/tcp" comment "Outline VPN Management API"; then
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
        if ufw allow "$access_key_port/tcp" comment "Outline VPN Client Access"; then
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
        if ufw allow "$access_key_port/udp" comment "Outline VPN Client Access"; then
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
# VPN TRAFFIC ROUTING AND IP FORWARDING
# =============================================================================

# Enable IP forwarding for VPN traffic routing
enable_ip_forwarding() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Enabling IP forwarding for VPN traffic..."
    
    # Check current IP forwarding status
    local current_forwarding=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
    
    if [ "$current_forwarding" = "1" ]; then
        [ "$debug" = true ] && log "IP forwarding already enabled"
    else
        # Enable IP forwarding temporarily
        if echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null; then
            [ "$debug" = true ] && log "IP forwarding enabled temporarily"
        else
            error "Failed to enable IP forwarding temporarily"
            return 1
        fi
    fi
    
    # Make IP forwarding permanent
    local sysctl_conf="/etc/sysctl.conf"
    if grep -q "^net.ipv4.ip_forward=1" "$sysctl_conf" 2>/dev/null; then
        [ "$debug" = true ] && log "IP forwarding already configured in sysctl.conf"
    else
        # Add or update IP forwarding setting
        if grep -q "^#net.ipv4.ip_forward=1" "$sysctl_conf" 2>/dev/null; then
            # Uncomment existing line
            sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' "$sysctl_conf"
            [ "$debug" = true ] && log "Uncommented IP forwarding in sysctl.conf"
        elif grep -q "^net.ipv4.ip_forward=" "$sysctl_conf" 2>/dev/null; then
            # Update existing line
            sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' "$sysctl_conf"
            [ "$debug" = true ] && log "Updated IP forwarding in sysctl.conf"
        else
            # Add new line
            echo "net.ipv4.ip_forward=1" >> "$sysctl_conf"
            [ "$debug" = true ] && log "Added IP forwarding to sysctl.conf"
        fi
    fi
    
    # Apply sysctl changes
    if sysctl -p >/dev/null 2>&1; then
        [ "$debug" = true ] && log "Sysctl changes applied successfully"
    else
        warning "Failed to apply sysctl changes, but IP forwarding is enabled"
    fi
    
    log "✓ IP forwarding enabled for VPN traffic routing"
    return 0
}

# Setup VPN traffic routing and masquerading
setup_vpn_routing() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Setting up VPN traffic routing..."
    
    # Get primary network interface
    local primary_interface=$(ip route | grep '^default' | grep -o 'dev [^ ]*' | head -1 | cut -d' ' -f2)
    if [ -z "$primary_interface" ]; then
        primary_interface="eth0"  # Fallback
        warning "Could not detect primary interface, using $primary_interface"
    fi
    [ "$debug" = true ] && log "Primary network interface: $primary_interface"
    
    # Setup iptables rules for VPN traffic masquerading
    [ "$debug" = true ] && log "Adding iptables masquerading rules..."
    
    # Configure UFW for VPN NAT/MASQUERADE
    local ufw_before_rules="/etc/ufw/before.rules"
    local ufw_backup="/etc/ufw/before.rules.vpn.backup"
    
    # Backup UFW before.rules if not already backed up
    if [ -f "$ufw_before_rules" ] && [ ! -f "$ufw_backup" ]; then
        cp "$ufw_before_rules" "$ufw_backup" 2>/dev/null || {
            warning "Failed to backup UFW before.rules"
        }
        [ "$debug" = true ] && log "Backed up UFW before.rules"
    fi
    
    # Add VPN NAT rules to UFW before.rules
    if [ -f "$ufw_before_rules" ]; then
        # Check if VPN NAT section already exists
        if ! grep -q "# START VPN NAT RULES" "$ufw_before_rules" 2>/dev/null; then
            [ "$debug" = true ] && log "Adding VPN NAT rules to UFW before.rules..."
            
            # Add NAT table rules before the filter rules
            cat >> "$ufw_before_rules" << EOF

# START VPN NAT RULES
# NAT table rules for VPN traffic routing
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic from VPN networks through primary interface
-A POSTROUTING -s 10.0.0.0/8 -o $primary_interface -j MASQUERADE
-A POSTROUTING -s 192.168.0.0/16 -o $primary_interface -j MASQUERADE  
-A POSTROUTING -s 172.16.0.0/12 -o $primary_interface -j MASQUERADE

# Don't delete the 'COMMIT' line or these rules won't be processed
COMMIT
# END VPN NAT RULES

EOF
            [ "$debug" = true ] && log "Added VPN NAT rules to UFW configuration"
        else
            [ "$debug" = true ] && log "VPN NAT rules already exist in UFW configuration"
        fi
    else
        warning "UFW before.rules file not found, cannot add VPN NAT rules"
    fi
    
    # Configure UFW for VLESS+Reality optimization
    [ "$debug" = true ] && log "Configuring UFW for VLESS+Reality..."
    
    # Enable UFW routing for VPN traffic
    local ufw_sysctl="/etc/ufw/sysctl.conf"
    if [ -f "$ufw_sysctl" ]; then
        # Enable IP forwarding in UFW sysctl
        if ! grep -q "^net/ipv4/ip_forward=1" "$ufw_sysctl" 2>/dev/null; then
            echo "net/ipv4/ip_forward=1" >> "$ufw_sysctl"
            [ "$debug" = true ] && log "Enabled IP forwarding in UFW sysctl"
        fi
        
        # Enable IPv6 forwarding for future compatibility
        if ! grep -q "^net/ipv6/conf/all/forwarding=1" "$ufw_sysctl" 2>/dev/null; then
            echo "net/ipv6/conf/all/forwarding=1" >> "$ufw_sysctl"
            [ "$debug" = true ] && log "Enabled IPv6 forwarding in UFW sysctl"
        fi
    fi
    
    # Ensure FORWARD policy allows VPN traffic
    [ "$debug" = true ] && log "Configuring FORWARD policy..."
    
    # Change UFW forward policy to ACCEPT
    local ufw_defaults="/etc/default/ufw"
    if [ -f "$ufw_defaults" ]; then
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' "$ufw_defaults"; then
            sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$ufw_defaults"
            [ "$debug" = true ] && log "Changed UFW forward policy to ACCEPT"
            
            # Reload UFW to apply changes
            if ufw reload >/dev/null 2>&1; then
                [ "$debug" = true ] && log "UFW reloaded with new forward policy"
            else
                warning "Failed to reload UFW"
            fi
        else
            [ "$debug" = true ] && log "UFW forward policy already set to ACCEPT"
        fi
    fi
    
    # Add FORWARD rules to UFW before.rules for VPN traffic
    if [ -f "$ufw_before_rules" ]; then
        # Check if VPN FORWARD section already exists
        if ! grep -q "# START VPN FORWARD RULES" "$ufw_before_rules" 2>/dev/null; then
            [ "$debug" = true ] && log "Adding VPN FORWARD rules to UFW before.rules..."
            
            # Add FORWARD rules after the filter table start
            sed -i '/^# allow all on loopback/i\
# START VPN FORWARD RULES\
# Allow forwarding for VPN traffic\
-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\
-A ufw-before-forward -j ACCEPT\
# END VPN FORWARD RULES\
' "$ufw_before_rules"
            
            [ "$debug" = true ] && log "Added VPN FORWARD rules to UFW configuration"
        else
            [ "$debug" = true ] && log "VPN FORWARD rules already exist in UFW configuration"
        fi
    fi
    
    log "✓ VPN traffic routing configured"
    return 0
}

# Save UFW configuration and ensure persistence
save_ufw_configuration() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Ensuring UFW configuration persistence..."
    
    # UFW automatically saves its configuration, but we'll verify it's enabled
    if command -v ufw >/dev/null 2>&1; then
        # Check if UFW is enabled
        local ufw_status=$(ufw status 2>/dev/null | grep "Status:" | awk '{print $2}')
        
        if [ "$ufw_status" = "active" ]; then
            [ "$debug" = true ] && log "UFW is active and configuration will persist"
            
            # Reload UFW to ensure all changes are applied
            if ufw reload >/dev/null 2>&1; then
                [ "$debug" = true ] && log "UFW configuration reloaded"
            else
                warning "Failed to reload UFW configuration"
                return 1
            fi
            
            return 0
        else
            warning "UFW is not active - configuration may not persist"
            return 1
        fi
    else
        warning "UFW not found - cannot save firewall configuration"
        return 1
    fi
}

# Complete VPN network setup (IP forwarding + routing + firewall)
setup_vpn_network() {
    local server_port="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Setting up complete VPN network configuration..."
    
    if [ -z "$server_port" ]; then
        error "Missing required parameter: server_port"
        return 1
    fi
    
    # Step 1: Enable IP forwarding
    enable_ip_forwarding "$debug" || {
        error "Failed to enable IP forwarding"
        return 1
    }
    
    # Step 2: Setup VPN traffic routing
    setup_vpn_routing "$debug" || {
        error "Failed to setup VPN routing"
        return 1
    }
    
    # Step 3: Configure firewall for VPN port
    setup_xray_firewall "$server_port" "$debug" || {
        error "Failed to setup VPN firewall"
        return 1
    }
    
    # Step 4: Save UFW configuration
    save_ufw_configuration "$debug" || {
        warning "Failed to ensure UFW configuration persistence"
    }
    
    log "✓ Complete VPN network configuration completed"
    return 0
}

# Fix VPN network configuration issues
fix_vpn_network_issues() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Fixing VPN network configuration issues..."
    
    echo "🔧 Diagnosing and fixing VPN network issues..."
    echo ""
    
    local issues_fixed=0
    
    # Get primary network interface
    local primary_interface=$(ip route | grep '^default' | grep -o 'dev [^ ]*' | head -1 | cut -d' ' -f2)
    if [ -z "$primary_interface" ]; then
        primary_interface="eth0"  # Fallback
        warning "Could not detect primary interface, using $primary_interface"
    fi
    
    # Check and fix IP forwarding
    echo "Checking IP forwarding..."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then
        echo "  ❌ IP forwarding is disabled"
        if enable_ip_forwarding "$debug"; then
            echo "  ✅ IP forwarding enabled"
            issues_fixed=$((issues_fixed + 1))
        else
            echo "  ❌ Failed to enable IP forwarding"
        fi
    else
        echo "  ✅ IP forwarding is already enabled"
    fi
    
    # Check and fix VPN masquerading rules in UFW
    echo ""
    echo "Checking VPN masquerading rules in UFW..."
    local ufw_before_rules="/etc/ufw/before.rules"
    
    if [ -f "$ufw_before_rules" ]; then
        if ! grep -q "# START VPN NAT RULES" "$ufw_before_rules" 2>/dev/null; then
            echo "  ❌ VPN NAT rules missing from UFW configuration"
            echo "    Adding VPN NAT rules to UFW before.rules..."
            if setup_vpn_routing "$debug"; then
                echo "    ✅ Added VPN NAT rules to UFW configuration"
                issues_fixed=$((issues_fixed + 1))
            else
                echo "    ❌ Failed to add VPN NAT rules"
            fi
        else
            echo "  ✅ VPN NAT rules are present in UFW configuration"
        fi
    else
        echo "  ⚠️  UFW before.rules file not found"
    fi
    
    # Check and fix UFW FORWARD policy
    echo ""
    echo "Checking UFW FORWARD policy..."
    local ufw_defaults="/etc/default/ufw"
    if [ -f "$ufw_defaults" ]; then
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' "$ufw_defaults"; then
            echo "  ❌ UFW FORWARD policy is DROP"
            if sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$ufw_defaults"; then
                echo "  ✅ UFW FORWARD policy set to ACCEPT"
                issues_fixed=$((issues_fixed + 1))
                # Reload UFW to apply changes
                if ufw reload >/dev/null 2>&1; then
                    echo "  ✅ UFW reloaded with new FORWARD policy"
                else
                    echo "  ⚠️  Failed to reload UFW"
                fi
            else
                echo "  ❌ Failed to set UFW FORWARD policy"
            fi
        else
            echo "  ✅ UFW FORWARD policy is already ACCEPT"
        fi
    else
        echo "  ⚠️  UFW defaults file not found"
    fi
    
    # Check FORWARD rules in UFW before.rules
    echo ""
    echo "Checking UFW FORWARD rules for VPN traffic..."
    if [ -f "$ufw_before_rules" ]; then
        if ! grep -q "# START VPN FORWARD RULES" "$ufw_before_rules" 2>/dev/null; then
            echo "  ❌ VPN FORWARD rules missing from UFW configuration"
            if setup_vpn_routing "$debug"; then
                echo "  ✅ Added VPN FORWARD rules to UFW configuration"
                issues_fixed=$((issues_fixed + 1))
            else
                echo "  ❌ Failed to add VPN FORWARD rules"
            fi
        else
            echo "  ✅ VPN FORWARD rules are present in UFW configuration"
        fi
    fi
    
    # Reload UFW to apply all changes
    if [ $issues_fixed -gt 0 ]; then
        echo ""
        echo "Reloading UFW to apply changes..."
        if ufw reload >/dev/null 2>&1; then
            echo "  ✅ UFW reloaded successfully"
        else
            echo "  ⚠️  Failed to reload UFW"
        fi
    fi
    
    echo ""
    if [ $issues_fixed -gt 0 ]; then
        echo "🎉 Fixed $issues_fixed VPN network configuration issues"
        echo ""
        echo "VPN network should now be properly configured for traffic routing."
        echo "You may want to restart the VPN server to ensure all changes take effect."
    else
        echo "✅ No VPN network configuration issues found"
    fi
    
    return 0
}

# Optimize kernel settings for VLESS+Reality performance
optimize_kernel_settings() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Optimizing kernel settings for VLESS+Reality..."
    
    local sysctl_conf="/etc/sysctl.conf"
    local sysctl_backup="/etc/sysctl.conf.vpn.backup"
    
    # Backup original sysctl.conf if not already backed up
    if [ ! -f "$sysctl_backup" ]; then
        cp "$sysctl_conf" "$sysctl_backup" 2>/dev/null || {
            warning "Failed to backup sysctl.conf"
        }
        [ "$debug" = true ] && log "Backed up original sysctl.conf"
    fi
    
    # Kernel optimizations for high-performance VPN
    local optimizations=(
        "# VPN Performance Optimizations"
        "net.core.rmem_max = 134217728"
        "net.core.wmem_max = 134217728"
        "net.ipv4.tcp_rmem = 4096 16384 134217728"
        "net.ipv4.tcp_wmem = 4096 16384 134217728"
        "net.core.netdev_max_backlog = 5000"
        "net.ipv4.tcp_congestion_control = bbr"
        "net.ipv4.tcp_fastopen = 3"
        "net.ipv4.tcp_slow_start_after_idle = 0"
        "net.ipv4.tcp_mtu_probing = 1"
        "net.ipv4.ip_forward = 1"
        "net.ipv4.conf.all.forwarding = 1"
        "net.ipv6.conf.all.forwarding = 1"
        "net.core.default_qdisc = fq"
    )
    
    local changes_made=false
    
    for setting in "${optimizations[@]}"; do
        # Skip comments
        if [[ "$setting" =~ ^# ]]; then
            if ! grep -q "^$setting" "$sysctl_conf" 2>/dev/null; then
                echo "$setting" >> "$sysctl_conf"
                [ "$debug" = true ] && log "Added comment: $setting"
            fi
            continue
        fi
        
        local key=$(echo "$setting" | cut -d= -f1 | xargs)
        local value=$(echo "$setting" | cut -d= -f2 | xargs)
        
        # Check if setting already exists with correct value
        if grep -q "^$key = $value" "$sysctl_conf" 2>/dev/null; then
            [ "$debug" = true ] && log "Setting already optimal: $key = $value"
            continue
        fi
        
        # Update or add the setting
        if grep -q "^$key" "$sysctl_conf" 2>/dev/null; then
            # Update existing setting
            sed -i "s|^$key.*|$setting|" "$sysctl_conf"
            [ "$debug" = true ] && log "Updated: $setting"
        else
            # Add new setting
            echo "$setting" >> "$sysctl_conf"
            [ "$debug" = true ] && log "Added: $setting"
        fi
        changes_made=true
    done
    
    # Apply changes immediately
    if [ "$changes_made" = true ]; then
        if sysctl -p >/dev/null 2>&1; then
            [ "$debug" = true ] && log "Applied kernel optimizations"
        else
            warning "Failed to apply some kernel settings"
        fi
        log "✓ Kernel settings optimized for VLESS+Reality performance"
    else
        [ "$debug" = true ] && log "All kernel settings already optimal"
    fi
    
    return 0
}

# Complete VPN network optimization for VLESS+Reality
optimize_vless_reality_network() {
    local server_port="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Starting complete VLESS+Reality network optimization..."
    
    if [ -z "$server_port" ]; then
        error "Missing required parameter: server_port"
        return 1
    fi
    
    # Step 1: Basic network setup
    setup_vpn_network "$server_port" "$debug" || {
        error "Failed basic VPN network setup"
        return 1
    }
    
    # Step 2: Kernel optimizations
    optimize_kernel_settings "$debug" || {
        warning "Failed to optimize kernel settings"
    }
    
    # Step 3: Verify configuration
    [ "$debug" = true ] && log "Verifying network configuration..."
    
    # Check if port is accessible
    if verify_port_access "$server_port" "tcp" "$debug"; then
        log "✓ Port $server_port is properly configured"
    else
        warning "Port $server_port may not be accessible"
    fi
    
    # Check IP forwarding
    if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
        [ "$debug" = true ] && log "✓ IP forwarding is enabled"
    else
        warning "IP forwarding is not enabled"
    fi
    
    log "✓ VLESS+Reality network optimization completed"
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
export -f enable_ip_forwarding
export -f setup_vpn_routing
export -f save_ufw_configuration
export -f setup_vpn_network
export -f fix_vpn_network_issues
export -f optimize_kernel_settings
export -f optimize_vless_reality_network

# =============================================================================
# FIREWALL CLEANUP FUNCTIONS
# =============================================================================

# Clean up unused VPN ports from firewall with interactive confirmation
cleanup_unused_vpn_ports() {
    local current_port="$1"
    local debug=${2:-false}
    local interactive=${3:-true}
    
    [ "$debug" = true ] && log "Analyzing VPN ports in firewall..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        [ "$debug" = true ] && log "UFW not available, skipping port cleanup"
        return 0
    fi
    
    # Get all currently allowed VPN-related ports (high ports typically used by VPN)
    local allowed_ports=$(ufw status numbered 2>/dev/null | grep -E "ALLOW.*tcp" | grep -v -E "22/tcp|80/tcp|443/tcp|OpenSSH|9000/tcp" | awk '{print $2}' | cut -d'/' -f1 | awk '$1 >= 10000' | sort -n)
    
    if [ -z "$allowed_ports" ]; then
        [ "$debug" = true ] && log "No VPN ports found in firewall"
        return 0
    fi
    
    # Get currently listening ports from system
    local listening_ports=""
    
    # Method 1: Check from VPN configuration files
    if [ -f "/opt/v2ray/config/port.txt" ]; then
        local xray_port=$(cat /opt/v2ray/config/port.txt 2>/dev/null)
        [ -n "$xray_port" ] && listening_ports="$listening_ports $xray_port"
    elif [ -f "/opt/v2ray/config/config.json" ]; then
        local xray_port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null)
        [ -n "$xray_port" ] && [ "$xray_port" != "null" ] && listening_ports="$listening_ports $xray_port"
    fi
    
    if [ -f "/opt/outline/api_port.txt" ]; then
        local outline_api_port=$(cat /opt/outline/api_port.txt 2>/dev/null)
        [ -n "$outline_api_port" ] && listening_ports="$listening_ports $outline_api_port"
    fi
    
    # Method 2: Check actual listening ports on system
    if command -v netstat >/dev/null 2>&1; then
        local system_ports=$(netstat -tlnp 2>/dev/null | grep ":.*LISTEN" | awk '{print $4}' | sed 's/.*://' | awk '$1 >= 10000' | sort -n | uniq)
        listening_ports="$listening_ports $system_ports"
    elif command -v ss >/dev/null 2>&1; then
        local system_ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | sed 's/.*://' | awk '$1 >= 10000' | sort -n | uniq)
        listening_ports="$listening_ports $system_ports"
    fi
    
    # Method 3: Check Docker container ports
    if command -v docker >/dev/null 2>&1; then
        local docker_ports=$(docker ps --format "table {{.Ports}}" 2>/dev/null | grep -o '[0-9]*->' | sed 's/->//' | awk '$1 >= 10000' | sort -n | uniq)
        listening_ports="$listening_ports $docker_ports"
    fi
    
    # Add current port if provided
    [ -n "$current_port" ] && listening_ports="$listening_ports $current_port"
    
    # Remove duplicates and sort
    listening_ports=$(echo $listening_ports | tr ' ' '\n' | sort -n | uniq | tr '\n' ' ')
    
    [ "$debug" = true ] && log "Currently listening ports: $listening_ports"
    [ "$debug" = true ] && log "Allowed VPN ports in firewall: $allowed_ports"
    
    # Find unused ports
    local unused_ports=""
    for port in $allowed_ports; do
        if [ -n "$port" ] && ! echo " $listening_ports " | grep -q " $port "; then
            unused_ports="$unused_ports $port"
        fi
    done
    
    if [ -z "$unused_ports" ]; then
        log "✅ All VPN ports in firewall are currently in use"
        return 0
    fi
    
    # Show analysis
    echo ""
    log "🔍 Firewall port analysis:"
    echo ""
    echo "📋 Currently allowed VPN ports in UFW:"
    for port in $allowed_ports; do
        if echo " $listening_ports " | grep -q " $port "; then
            echo "  ✅ $port/tcp (in use)"
        else
            echo "  ❌ $port/tcp (unused)"
        fi
    done
    
    echo ""
    echo "📊 Currently listening ports: $(echo $listening_ports | tr ' ' ',')"
    echo "🗑️  Unused ports that can be removed: $(echo $unused_ports | tr ' ' ',')"
    
    if [ "$interactive" = false ]; then
        # Non-interactive mode - remove all unused ports
        local removed_count=0
        for port in $unused_ports; do
            if ufw delete allow "$port/tcp" 2>/dev/null; then
                log "Removed unused port: $port/tcp"
                removed_count=$((removed_count + 1))
            fi
        done
        [ $removed_count -gt 0 ] && log "Removed $removed_count unused VPN ports"
        return 0
    fi
    
    # Interactive mode - ask user what to remove
    echo ""
    echo "Would you like to remove unused ports from the firewall?"
    echo "1) Remove all unused ports automatically"
    echo "2) Select specific ports to remove"
    echo "3) Keep all ports (skip cleanup)"
    echo ""
    read -p "Select option (1-3): " choice
    
    case "$choice" in
        1)
            # Remove all unused ports
            local removed_count=0
            for port in $unused_ports; do
                echo "Removing port $port/tcp..."
                if ufw delete allow "$port/tcp" 2>/dev/null; then
                    log "✅ Removed: $port/tcp"
                    removed_count=$((removed_count + 1))
                else
                    warning "❌ Failed to remove: $port/tcp"
                fi
            done
            [ $removed_count -gt 0 ] && log "🧹 Cleaned up $removed_count unused VPN ports"
            ;;
        2)
            # Interactive selection
            echo ""
            echo "Select ports to remove (enter numbers separated by spaces, or 'all' for all):"
            local port_array=($unused_ports)
            local i=1
            for port in $unused_ports; do
                echo "  $i) $port/tcp"
                i=$((i + 1))
            done
            echo ""
            read -p "Enter selection: " selection
            
            if [ "$selection" = "all" ]; then
                selection=$(seq 1 ${#port_array[@]} | tr '\n' ' ')
            fi
            
            local removed_count=0
            for num in $selection; do
                if [ "$num" -ge 1 ] && [ "$num" -le ${#port_array[@]} ]; then
                    local port_index=$((num - 1))
                    local port=${port_array[$port_index]}
                    echo "Removing port $port/tcp..."
                    if ufw delete allow "$port/tcp" 2>/dev/null; then
                        log "✅ Removed: $port/tcp"
                        removed_count=$((removed_count + 1))
                    else
                        warning "❌ Failed to remove: $port/tcp"
                    fi
                fi
            done
            [ $removed_count -gt 0 ] && log "🧹 Removed $removed_count selected ports"
            ;;
        3)
            log "Skipping firewall cleanup"
            ;;
        *)
            warning "Invalid selection, skipping cleanup"
            ;;
    esac
    
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