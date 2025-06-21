#!/bin/bash

# =============================================================================
# Custom Installation Profiles Module
# 
# This module provides pre-configured installation profiles for different
# use cases and environments (security, performance, low-resource).
#
# Functions exported:
# - get_installation_profile()
# - apply_installation_profile()
# - list_installation_profiles()
# - create_custom_profile()
# - validate_profile()
#
# Dependencies: lib/common.sh, lib/config.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

source "$PROJECT_ROOT/lib/config.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/config.sh"
    exit 1
}

# =============================================================================
# PROFILE DEFINITIONS
# =============================================================================

# High Security Profile - Maximum security with some performance trade-offs
declare -A HIGH_SECURITY_PROFILE=(
    ["name"]="high-security"
    ["description"]="Maximum security configuration with enhanced encryption and strict access controls"
    ["vpn_protocol"]="vless-reality"
    ["port_range_start"]="20000"
    ["port_range_end"]="30000"
    ["cipher"]="chacha20-poly1305"
    ["key_rotation_days"]="7"
    ["log_level"]="warning"
    ["enable_firewall"]="true"
    ["firewall_mode"]="strict"
    ["enable_fail2ban"]="true"
    ["enable_ids"]="true"
    ["docker_security"]="enhanced"
    ["resource_limits"]="strict"
    ["max_connections"]="50"
    ["connection_timeout"]="300"
    ["enable_geoip_blocking"]="true"
    ["blocked_countries"]=""
    ["enable_rate_limiting"]="true"
    ["rate_limit_per_user"]="100/hour"
    ["enable_intrusion_detection"]="true"
    ["enable_audit_logging"]="true"
    ["tls_min_version"]="1.3"
    ["enable_perfect_forward_secrecy"]="true"
)

# Performance Optimized Profile - Maximum performance with reasonable security
declare -A PERFORMANCE_PROFILE=(
    ["name"]="performance"
    ["description"]="Optimized for maximum performance and throughput"
    ["vpn_protocol"]="vless-reality"
    ["port_range_start"]="10000"
    ["port_range_end"]="20000"
    ["cipher"]="aes-128-gcm"
    ["key_rotation_days"]="30"
    ["log_level"]="error"
    ["enable_firewall"]="true"
    ["firewall_mode"]="balanced"
    ["enable_fail2ban"]="false"
    ["enable_ids"]="false"
    ["docker_security"]="standard"
    ["resource_limits"]="relaxed"
    ["max_connections"]="500"
    ["connection_timeout"]="3600"
    ["enable_geoip_blocking"]="false"
    ["blocked_countries"]=""
    ["enable_rate_limiting"]="false"
    ["rate_limit_per_user"]=""
    ["enable_intrusion_detection"]="false"
    ["enable_audit_logging"]="false"
    ["tls_min_version"]="1.2"
    ["enable_perfect_forward_secrecy"]="true"
    ["enable_tcp_fast_open"]="true"
    ["enable_bbr"]="true"
    ["buffer_size"]="4096"
    ["enable_zero_copy"]="true"
)

# Low Resource Profile - Minimal resource usage for constrained environments
declare -A LOW_RESOURCE_PROFILE=(
    ["name"]="low-resource"
    ["description"]="Minimal resource usage for VPS or embedded systems"
    ["vpn_protocol"]="vless-reality"
    ["port_range_start"]="40000"
    ["port_range_end"]="50000"
    ["cipher"]="chacha20-poly1305"
    ["key_rotation_days"]="30"
    ["log_level"]="error"
    ["enable_firewall"]="true"
    ["firewall_mode"]="basic"
    ["enable_fail2ban"]="false"
    ["enable_ids"]="false"
    ["docker_security"]="minimal"
    ["resource_limits"]="strict"
    ["max_connections"]="25"
    ["connection_timeout"]="600"
    ["enable_geoip_blocking"]="false"
    ["blocked_countries"]=""
    ["enable_rate_limiting"]="true"
    ["rate_limit_per_user"]="50/hour"
    ["enable_intrusion_detection"]="false"
    ["enable_audit_logging"]="false"
    ["tls_min_version"]="1.2"
    ["enable_perfect_forward_secrecy"]="false"
    ["memory_limit"]="256M"
    ["cpu_limit"]="0.5"
    ["disable_unnecessary_services"]="true"
    ["enable_swap_optimization"]="true"
)

# Balanced Profile - Good balance between security and performance
declare -A BALANCED_PROFILE=(
    ["name"]="balanced"
    ["description"]="Balanced configuration suitable for most use cases"
    ["vpn_protocol"]="vless-reality"
    ["port_range_start"]="10000"
    ["port_range_end"]="60000"
    ["cipher"]="aes-256-gcm"
    ["key_rotation_days"]="14"
    ["log_level"]="info"
    ["enable_firewall"]="true"
    ["firewall_mode"]="balanced"
    ["enable_fail2ban"]="true"
    ["enable_ids"]="false"
    ["docker_security"]="standard"
    ["resource_limits"]="balanced"
    ["max_connections"]="100"
    ["connection_timeout"]="1800"
    ["enable_geoip_blocking"]="false"
    ["blocked_countries"]=""
    ["enable_rate_limiting"]="true"
    ["rate_limit_per_user"]="200/hour"
    ["enable_intrusion_detection"]="false"
    ["enable_audit_logging"]="true"
    ["tls_min_version"]="1.2"
    ["enable_perfect_forward_secrecy"]="true"
)

# Enterprise Profile - Enterprise-grade features with compliance
declare -A ENTERPRISE_PROFILE=(
    ["name"]="enterprise"
    ["description"]="Enterprise-grade configuration with compliance and auditing"
    ["vpn_protocol"]="vless-reality"
    ["port_range_start"]="8000"
    ["port_range_end"]="9000"
    ["cipher"]="aes-256-gcm"
    ["key_rotation_days"]="7"
    ["log_level"]="info"
    ["enable_firewall"]="true"
    ["firewall_mode"]="strict"
    ["enable_fail2ban"]="true"
    ["enable_ids"]="true"
    ["docker_security"]="enhanced"
    ["resource_limits"]="dynamic"
    ["max_connections"]="1000"
    ["connection_timeout"]="28800"
    ["enable_geoip_blocking"]="true"
    ["blocked_countries"]=""
    ["enable_rate_limiting"]="true"
    ["rate_limit_per_user"]="unlimited"
    ["enable_intrusion_detection"]="true"
    ["enable_audit_logging"]="true"
    ["tls_min_version"]="1.2"
    ["enable_perfect_forward_secrecy"]="true"
    ["enable_compliance_mode"]="true"
    ["enable_data_retention"]="true"
    ["data_retention_days"]="90"
    ["enable_user_activity_monitoring"]="true"
    ["enable_bandwidth_accounting"]="true"
    ["enable_high_availability"]="true"
    ["enable_backup_automation"]="true"
)

# Stealth Profile - Maximum obfuscation and anti-detection
declare -A STEALTH_PROFILE=(
    ["name"]="stealth"
    ["description"]="Maximum obfuscation for restrictive network environments"
    ["vpn_protocol"]="vless-reality"
    ["port_range_start"]="443"
    ["port_range_end"]="443"
    ["cipher"]="chacha20-poly1305"
    ["key_rotation_days"]="3"
    ["log_level"]="none"
    ["enable_firewall"]="true"
    ["firewall_mode"]="stealth"
    ["enable_fail2ban"]="false"
    ["enable_ids"]="false"
    ["docker_security"]="standard"
    ["resource_limits"]="balanced"
    ["max_connections"]="10"
    ["connection_timeout"]="300"
    ["enable_geoip_blocking"]="false"
    ["blocked_countries"]=""
    ["enable_rate_limiting"]="false"
    ["rate_limit_per_user"]=""
    ["enable_intrusion_detection"]="false"
    ["enable_audit_logging"]="false"
    ["tls_min_version"]="1.3"
    ["enable_perfect_forward_secrecy"]="true"
    ["enable_traffic_obfuscation"]="true"
    ["enable_port_hopping"]="true"
    ["enable_protocol_masquerading"]="true"
    ["masquerade_as"]="https"
    ["enable_timing_obfuscation"]="true"
)

# Available profiles
declare -A AVAILABLE_PROFILES=(
    ["high-security"]="HIGH_SECURITY_PROFILE"
    ["performance"]="PERFORMANCE_PROFILE"
    ["low-resource"]="LOW_RESOURCE_PROFILE"
    ["balanced"]="BALANCED_PROFILE"
    ["enterprise"]="ENTERPRISE_PROFILE"
    ["stealth"]="STEALTH_PROFILE"
)

# =============================================================================
# PROFILE MANAGEMENT
# =============================================================================

# Get installation profile by name
get_installation_profile() {
    local profile_name="${1:-balanced}"
    
    # Check if profile exists
    if [ -z "${AVAILABLE_PROFILES[$profile_name]}" ]; then
        error "Unknown profile: $profile_name"
        return 1
    fi
    
    # Get profile array name
    local profile_var="${AVAILABLE_PROFILES[$profile_name]}"
    
    # Return profile data as JSON
    local json_output="{"
    local first=true
    
    # Use nameref to access the profile array
    local -n profile_ref="$profile_var"
    
    for key in "${!profile_ref[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_output+=","
        fi
        json_output+="\"$key\":\"${profile_ref[$key]}\""
    done
    
    json_output+="}"
    
    echo "$json_output"
    return 0
}

# List available installation profiles
list_installation_profiles() {
    local verbose=${1:-false}
    
    echo "Available Installation Profiles:"
    echo "==============================="
    echo ""
    
    for profile_name in "${!AVAILABLE_PROFILES[@]}"; do
        local profile_var="${AVAILABLE_PROFILES[$profile_name]}"
        local -n profile_ref="$profile_var"
        
        echo "📦 ${profile_ref[name]}"
        echo "   ${profile_ref[description]}"
        
        if [ "$verbose" = true ]; then
            echo "   Key features:"
            echo "   - Protocol: ${profile_ref[vpn_protocol]}"
            echo "   - Security: ${profile_ref[docker_security]}"
            echo "   - Max connections: ${profile_ref[max_connections]}"
            echo "   - Resource limits: ${profile_ref[resource_limits]}"
            [ "${profile_ref[enable_firewall]}" = "true" ] && echo "   - Firewall: ${profile_ref[firewall_mode]} mode"
            [ "${profile_ref[enable_rate_limiting]}" = "true" ] && echo "   - Rate limiting: ${profile_ref[rate_limit_per_user]}"
            [ "${profile_ref[enable_audit_logging]}" = "true" ] && echo "   - Audit logging enabled"
        fi
        
        echo ""
    done
    
    return 0
}

# Apply installation profile
apply_installation_profile() {
    local profile_name="${1:-balanced}"
    local override_file="${2:-}"
    
    log "Applying installation profile: $profile_name"
    
    # Get profile data
    local profile_json=$(get_installation_profile "$profile_name")
    if [ -z "$profile_json" ]; then
        error "Failed to load profile: $profile_name"
        return 1
    fi
    
    # Convert JSON to environment variables
    while IFS="=" read -r key value; do
        # Remove quotes and export
        key=$(echo "$key" | tr -d '"' | tr '[:lower:]' '[:upper:]')
        value=$(echo "$value" | tr -d '"')
        export "PROFILE_${key}=${value}"
    done < <(echo "$profile_json" | jq -r 'to_entries|map("\(.key)=\(.value)")|.[]')
    
    # Apply overrides if provided
    if [ -n "$override_file" ] && [ -f "$override_file" ]; then
        log "Applying overrides from: $override_file"
        source "$override_file"
    fi
    
    # Create configuration based on profile
    generate_profile_config "$profile_name"
    
    success "Profile $profile_name applied successfully"
    return 0
}

# Generate configuration from profile
generate_profile_config() {
    local profile_name="$1"
    local config_dir="${2:-/tmp/vpn-profile-config}"
    
    mkdir -p "$config_dir"
    
    # Generate main configuration
    cat > "$config_dir/profile.conf" <<EOF
# VPN Installation Profile Configuration
# Generated from profile: $profile_name
# Timestamp: $(date)

# Core Settings
VPN_PROTOCOL="${PROFILE_VPN_PROTOCOL:-vless-reality}"
PORT_RANGE_START="${PROFILE_PORT_RANGE_START:-10000}"
PORT_RANGE_END="${PROFILE_PORT_RANGE_END:-60000}"
CIPHER="${PROFILE_CIPHER:-aes-256-gcm}"

# Security Settings
ENABLE_FIREWALL="${PROFILE_ENABLE_FIREWALL:-true}"
FIREWALL_MODE="${PROFILE_FIREWALL_MODE:-balanced}"
KEY_ROTATION_DAYS="${PROFILE_KEY_ROTATION_DAYS:-14}"
TLS_MIN_VERSION="${PROFILE_TLS_MIN_VERSION:-1.2}"
ENABLE_PERFECT_FORWARD_SECRECY="${PROFILE_ENABLE_PERFECT_FORWARD_SECRECY:-true}"

# Performance Settings
MAX_CONNECTIONS="${PROFILE_MAX_CONNECTIONS:-100}"
CONNECTION_TIMEOUT="${PROFILE_CONNECTION_TIMEOUT:-1800}"
RESOURCE_LIMITS="${PROFILE_RESOURCE_LIMITS:-balanced}"
LOG_LEVEL="${PROFILE_LOG_LEVEL:-info}"

# Advanced Features
ENABLE_RATE_LIMITING="${PROFILE_ENABLE_RATE_LIMITING:-true}"
RATE_LIMIT_PER_USER="${PROFILE_RATE_LIMIT_PER_USER:-200/hour}"
ENABLE_AUDIT_LOGGING="${PROFILE_ENABLE_AUDIT_LOGGING:-true}"
ENABLE_FAIL2BAN="${PROFILE_ENABLE_FAIL2BAN:-false}"
ENABLE_IDS="${PROFILE_ENABLE_IDS:-false}"
EOF
    
    # Generate Docker configuration based on profile
    generate_docker_config_for_profile "$profile_name" "$config_dir"
    
    # Generate firewall rules based on profile
    generate_firewall_rules_for_profile "$profile_name" "$config_dir"
    
    # Generate resource limits configuration
    generate_resource_limits_for_profile "$profile_name" "$config_dir"
    
    log "Profile configuration generated in: $config_dir"
    return 0
}

# Generate Docker configuration for profile
generate_docker_config_for_profile() {
    local profile_name="$1"
    local config_dir="$2"
    
    local memory_limit="${PROFILE_MEMORY_LIMIT:-512M}"
    local cpu_limit="${PROFILE_CPU_LIMIT:-1.0}"
    
    # Adjust limits based on profile
    case "$profile_name" in
        "high-security")
            memory_limit="1G"
            cpu_limit="2.0"
            ;;
        "performance")
            memory_limit="2G"
            cpu_limit="4.0"
            ;;
        "low-resource")
            memory_limit="256M"
            cpu_limit="0.5"
            ;;
        "enterprise")
            memory_limit="4G"
            cpu_limit="8.0"
            ;;
    esac
    
    cat > "$config_dir/docker-limits.conf" <<EOF
# Docker Resource Limits for Profile: $profile_name

# Memory limits
MEMORY_LIMIT="$memory_limit"
MEMORY_RESERVATION="$((${memory_limit%M} / 2))M"

# CPU limits
CPU_LIMIT="$cpu_limit"
CPU_RESERVATION="$(echo "$cpu_limit / 2" | bc -l)"

# Other limits
PIDS_LIMIT="1000"
ULIMIT_NOFILE="65535:65535"
ULIMIT_NPROC="4096:4096"

# Security options
SECURITY_OPT="no-new-privileges:true"
READ_ONLY_ROOT="true"
EOF
    
    return 0
}

# Generate firewall rules for profile
generate_firewall_rules_for_profile() {
    local profile_name="$1"
    local config_dir="$2"
    
    cat > "$config_dir/firewall-rules.sh" <<'EOF'
#!/bin/bash
# Firewall rules for VPN profile
EOF
    
    # Add profile-specific rules
    case "${PROFILE_FIREWALL_MODE}" in
        "strict")
            cat >> "$config_dir/firewall-rules.sh" <<'EOF'

# Strict firewall mode
# Default DROP policy
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH (rate limited)
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow VPN ports
iptables -A INPUT -p tcp --dport ${PROFILE_PORT_RANGE_START}:${PROFILE_PORT_RANGE_END} -j ACCEPT
iptables -A INPUT -p udp --dport ${PROFILE_PORT_RANGE_START}:${PROFILE_PORT_RANGE_END} -j ACCEPT
EOF
            ;;
            
        "balanced")
            cat >> "$config_dir/firewall-rules.sh" <<'EOF'

# Balanced firewall mode
# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow VPN ports
iptables -A INPUT -p tcp --dport ${PROFILE_PORT_RANGE_START}:${PROFILE_PORT_RANGE_END} -j ACCEPT
iptables -A INPUT -p udp --dport ${PROFILE_PORT_RANGE_START}:${PROFILE_PORT_RANGE_END} -j ACCEPT

# Drop invalid packets
iptables -A INPUT -m state --state INVALID -j DROP
EOF
            ;;
            
        "stealth")
            cat >> "$config_dir/firewall-rules.sh" <<'EOF'

# Stealth firewall mode
# Minimal rules to avoid detection
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
EOF
            ;;
    esac
    
    chmod +x "$config_dir/firewall-rules.sh"
    return 0
}

# Generate resource limits for profile
generate_resource_limits_for_profile() {
    local profile_name="$1"
    local config_dir="$2"
    
    cat > "$config_dir/resource-limits.conf" <<EOF
# Resource limits for profile: $profile_name

# Connection limits
MAX_CONNECTIONS=${PROFILE_MAX_CONNECTIONS}
CONNECTION_TIMEOUT=${PROFILE_CONNECTION_TIMEOUT}
MAX_CONNECTIONS_PER_IP=10

# Rate limiting
ENABLE_RATE_LIMITING=${PROFILE_ENABLE_RATE_LIMITING}
RATE_LIMIT_PER_USER="${PROFILE_RATE_LIMIT_PER_USER}"

# Buffer sizes (profile-specific)
EOF
    
    case "$profile_name" in
        "performance")
            cat >> "$config_dir/resource-limits.conf" <<EOF
SOCKET_BUFFER_SIZE=4194304
READ_BUFFER_SIZE=32768
WRITE_BUFFER_SIZE=32768
EOF
            ;;
        "low-resource")
            cat >> "$config_dir/resource-limits.conf" <<EOF
SOCKET_BUFFER_SIZE=262144
READ_BUFFER_SIZE=4096
WRITE_BUFFER_SIZE=4096
EOF
            ;;
        *)
            cat >> "$config_dir/resource-limits.conf" <<EOF
SOCKET_BUFFER_SIZE=1048576
READ_BUFFER_SIZE=16384
WRITE_BUFFER_SIZE=16384
EOF
            ;;
    esac
    
    return 0
}

# Create custom profile
create_custom_profile() {
    local profile_name="$1"
    local base_profile="${2:-balanced}"
    local custom_settings_file="$3"
    
    if [ -z "$profile_name" ]; then
        error "Profile name required"
        return 1
    fi
    
    # Check if profile already exists
    if [ -n "${AVAILABLE_PROFILES[$profile_name]}" ]; then
        error "Profile already exists: $profile_name"
        return 1
    fi
    
    log "Creating custom profile: $profile_name (based on $base_profile)"
    
    # Create profile directory
    local profile_dir="$HOME/.vpn-profiles"
    mkdir -p "$profile_dir"
    
    # Get base profile
    local base_profile_json=$(get_installation_profile "$base_profile")
    
    # Apply custom settings if provided
    if [ -n "$custom_settings_file" ] && [ -f "$custom_settings_file" ]; then
        # Merge custom settings with base profile
        local custom_json=$(cat "$custom_settings_file")
        local merged_json=$(echo "$base_profile_json" | jq -s '.[0] * .[1]' - <(echo "$custom_json"))
        echo "$merged_json" > "$profile_dir/${profile_name}.json"
    else
        echo "$base_profile_json" > "$profile_dir/${profile_name}.json"
    fi
    
    success "Custom profile created: $profile_name"
    log "Profile saved to: $profile_dir/${profile_name}.json"
    
    return 0
}

# Validate profile configuration
validate_profile() {
    local profile_name="$1"
    local strict=${2:-false}
    
    log "Validating profile: $profile_name"
    
    # Get profile data
    local profile_json=$(get_installation_profile "$profile_name")
    if [ -z "$profile_json" ]; then
        error "Failed to load profile: $profile_name"
        return 1
    fi
    
    local validation_errors=()
    
    # Validate required fields
    local required_fields=("name" "vpn_protocol" "port_range_start" "port_range_end")
    for field in "${required_fields[@]}"; do
        local value=$(echo "$profile_json" | jq -r ".$field")
        if [ -z "$value" ] || [ "$value" = "null" ]; then
            validation_errors+=("Missing required field: $field")
        fi
    done
    
    # Validate port ranges
    local port_start=$(echo "$profile_json" | jq -r '.port_range_start')
    local port_end=$(echo "$profile_json" | jq -r '.port_range_end')
    
    if [ -n "$port_start" ] && [ -n "$port_end" ]; then
        if [ "$port_start" -gt "$port_end" ]; then
            validation_errors+=("Invalid port range: $port_start > $port_end")
        fi
        
        if [ "$port_start" -lt 1 ] || [ "$port_end" -gt 65535 ]; then
            validation_errors+=("Port range must be between 1-65535")
        fi
    fi
    
    # Validate boolean fields
    local boolean_fields=("enable_firewall" "enable_rate_limiting" "enable_audit_logging")
    for field in "${boolean_fields[@]}"; do
        local value=$(echo "$profile_json" | jq -r ".$field")
        if [ -n "$value" ] && [ "$value" != "true" ] && [ "$value" != "false" ]; then
            validation_errors+=("Invalid boolean value for $field: $value")
        fi
    done
    
    # Show validation results
    if [ ${#validation_errors[@]} -gt 0 ]; then
        error "Profile validation failed:"
        for err in "${validation_errors[@]}"; do
            echo "  - $err"
        done
        return 1
    else
        success "Profile validation passed"
        return 0
    fi
}

# Interactive profile selection
select_installation_profile() {
    echo "Select Installation Profile:"
    echo "=========================="
    echo ""
    
    local profiles=("high-security" "performance" "low-resource" "balanced" "enterprise" "stealth" "custom")
    local descriptions=(
        "Maximum security with enhanced encryption"
        "Optimized for maximum performance"
        "Minimal resource usage for small VPS"
        "Balanced for most use cases (Recommended)"
        "Enterprise-grade with compliance features"
        "Maximum obfuscation for restrictive networks"
        "Create a custom profile"
    )
    
    for i in "${!profiles[@]}"; do
        echo "$((i+1))) ${profiles[$i]}"
        echo "   ${descriptions[$i]}"
        echo ""
    done
    
    local choice
    while true; do
        read -p "Select profile (1-${#profiles[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            local selected_profile="${profiles[$((choice-1))]}"
            
            if [ "$selected_profile" = "custom" ]; then
                read -p "Enter custom profile name: " custom_name
                read -p "Base profile (balanced): " base_profile
                base_profile="${base_profile:-balanced}"
                
                create_custom_profile "$custom_name" "$base_profile"
                selected_profile="$custom_name"
            fi
            
            echo "$selected_profile"
            return 0
        else
            warning "Invalid selection. Please choose 1-${#profiles[@]}"
        fi
    done
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f get_installation_profile
export -f list_installation_profiles
export -f apply_installation_profile
export -f create_custom_profile
export -f validate_profile
export -f select_installation_profile
export -f generate_profile_config

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

# If script is run directly, provide CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "list")
            list_installation_profiles "${2:-false}"
            ;;
        "show")
            get_installation_profile "${2:-balanced}" | jq .
            ;;
        "apply")
            apply_installation_profile "${2:-balanced}" "${3:-}"
            ;;
        "validate")
            validate_profile "${2:-balanced}" "${3:-false}"
            ;;
        "create")
            create_custom_profile "$2" "${3:-balanced}" "${4:-}"
            ;;
        "select")
            select_installation_profile
            ;;
        *)
            echo "Usage: $0 {list|show|apply|validate|create|select}"
            echo ""
            echo "Commands:"
            echo "  list [verbose]           - List available profiles"
            echo "  show <profile>          - Show profile configuration"
            echo "  apply <profile> [overrides] - Apply installation profile"
            echo "  validate <profile> [strict] - Validate profile configuration"
            echo "  create <name> [base] [config] - Create custom profile"
            echo "  select                  - Interactive profile selection"
            echo ""
            echo "Examples:"
            echo "  $0 list true"
            echo "  $0 show high-security"
            echo "  $0 apply performance"
            echo "  $0 create my-profile balanced custom.json"
            exit 1
            ;;
    esac
fi