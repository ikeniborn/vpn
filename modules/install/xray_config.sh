#!/bin/bash

# =============================================================================
# Xray Configuration Module
# 
# This module handles Xray configuration generation and management.
# Extracted from install_vpn.sh for modular architecture.
#
# Functions exported:
# - create_xray_config_reality()
# - create_xray_config()
# - validate_xray_config()
# - create_user_data()
# - create_connection_link()
# - setup_xray_directories()
# - setup_xray_configuration()
#
# Dependencies: lib/common.sh, lib/config.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_PATH="${PROJECT_ROOT:-$SCRIPT_DIR/../..}/lib/common.sh"
source "$COMMON_PATH" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh from $COMMON_PATH"
    exit 1
}

CONFIG_PATH="${PROJECT_ROOT:-$SCRIPT_DIR/../..}/lib/config.sh"
source "$CONFIG_PATH" 2>/dev/null || {
    echo "Error: Cannot source lib/config.sh from $CONFIG_PATH"
    exit 1
}

# =============================================================================
# DIRECTORY SETUP
# =============================================================================

# Create necessary directories for Xray
setup_xray_directories() {
    local work_dir="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Setting up Xray directories..."
    
    if [ -z "$work_dir" ]; then
        error "Missing required parameter: work_dir"
        return 1
    fi
    
    # Create directories
    mkdir -p "$work_dir/config" || {
        error "Failed to create config directory"
        return 1
    }
    
    mkdir -p "$work_dir/logs" || {
        error "Failed to create logs directory"
        return 1
    }
    
    mkdir -p "$work_dir/users" || {
        error "Failed to create users directory"
        return 1
    }
    
    # Set appropriate permissions
    chmod 755 "$work_dir/config" "$work_dir/logs" "$work_dir/users"
    
    [ "$debug" = true ] && log "Xray directories created successfully"
    return 0
}

# =============================================================================
# CONFIGURATION GENERATION
# =============================================================================

# Create Xray configuration for VLESS+Reality protocol
create_xray_config_reality() {
    local config_file="$1"
    local server_port="$2"
    local user_uuid="$3"
    local user_name="$4"
    local server_sni="$5"
    local private_key="$6"
    local short_id="$7"
    local debug=${8:-false}
    
    [ "$debug" = true ] && log "Creating VLESS+Reality configuration..."
    
    # Validate required parameters
    if [ -z "$config_file" ] || [ -z "$server_port" ] || [ -z "$user_uuid" ] || \
       [ -z "$user_name" ] || [ -z "$server_sni" ] || [ -z "$private_key" ] || \
       [ -z "$short_id" ]; then
        error "Missing required parameters for Reality configuration"
        return 1
    fi
    
    # Create Reality configuration
    cat > "$config_file" <<EOL
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "stats": {},
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "policy": {
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "port": $server_port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$user_uuid",
            "flow": "xtls-rprx-vision",
            "email": "$user_name"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$server_sni:443",
          "xver": 0,
          "serverNames": [
            "$server_sni"
          ],
          "privateKey": "$private_key",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 60000,
          "shortIds": [
            "$short_id"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic", "fakedns"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOL
    
    if [ ! -f "$config_file" ]; then
        error "Failed to create Reality configuration file"
        return 1
    fi
    
    [ "$debug" = true ] && log "VLESS+Reality configuration created successfully"
    return 0
}


# Create Xray configuration based on protocol type
create_xray_config() {
    local work_dir="$1"
    local protocol="$2"
    local server_port="$3"
    local user_uuid="$4"
    local user_name="$5"
    local server_sni="$6"
    local private_key="$7"
    local public_key="$8"
    local short_id="$9"
    local debug=${10:-false}
    
    [ "$debug" = true ] && log "Creating Xray configuration..."
    [ "$debug" = true ] && log "Protocol: $protocol"
    
    if [ -z "$work_dir" ] || [ -z "$protocol" ]; then
        error "Missing required parameters: work_dir and protocol"
        return 1
    fi
    
    local config_file="$work_dir/config/config.json"
    
    # Ensure config directory exists
    mkdir -p "$work_dir/config" || {
        error "Failed to create config directory"
        return 1
    }
    
    # Create configuration based on protocol
    case "$protocol" in
        "vless-reality")
            create_xray_config_reality "$config_file" "$server_port" "$user_uuid" \
                "$user_name" "$server_sni" "$private_key" "$short_id" "$debug"
            ;;
        *)
            error "Unsupported protocol: $protocol"
            return 1
            ;;
    esac
    
    return $?
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Validate Xray configuration file
validate_xray_config() {
    local config_file="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Validating Xray configuration..."
    
    if [ -z "$config_file" ]; then
        error "Missing required parameter: config_file"
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if file is valid JSON
    if ! command -v jq >/dev/null 2>&1; then
        warning "jq not available, skipping JSON validation"
        return 0
    fi
    
    if ! jq empty "$config_file" 2>/dev/null; then
        error "Configuration file is not valid JSON"
        return 1
    fi
    
    # Validate required fields
    local required_fields=("inbounds" "outbounds")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$config_file" >/dev/null 2>&1; then
            error "Missing required field in configuration: $field"
            return 1
        fi
    done
    
    [ "$debug" = true ] && log "Configuration validation passed"
    return 0
}

# =============================================================================
# USER DATA MANAGEMENT
# =============================================================================

# Create user data file
create_user_data() {
    local work_dir="$1"
    local user_name="$2"
    local user_uuid="$3"
    local server_port="$4"
    local server_ip="$5"
    local protocol="$6"
    local server_sni="$7"
    local private_key="$8"
    local public_key="$9"
    local short_id="${10}"
    local debug=${11:-false}
    
    [ "$debug" = true ] && log "Creating user data file..."
    
    if [ -z "$work_dir" ] || [ -z "$user_name" ] || [ -z "$user_uuid" ]; then
        error "Missing required parameters for user data"
        return 1
    fi
    
    local user_file="$work_dir/users/$user_name.json"
    
    # Ensure users directory exists
    mkdir -p "$work_dir/users" || {
        error "Failed to create users directory"
        return 1
    }
    
    # Create user data for VLESS+Reality
    cat > "$user_file" <<EOL
{
  "name": "$user_name",
  "uuid": "$user_uuid",
  "port": $server_port,
  "server": "$server_ip",
  "sni": "$server_sni",
  "private_key": "$private_key",
  "public_key": "$public_key",
  "short_id": "$short_id",
  "protocol": "$protocol"
}
EOL
    
    if [ ! -f "$user_file" ]; then
        error "Failed to create user data file"
        return 1
    fi
    
    [ "$debug" = true ] && log "User data file created: $user_file"
    return 0
}

# Create connection link for user
create_connection_link() {
    local work_dir="$1"
    local user_name="$2"
    local user_uuid="$3"
    local server_ip="$4"
    local server_port="$5"
    local protocol="$6"
    local server_sni="$7"
    local public_key="$8"
    local short_id="$9"
    local debug=${10:-false}
    
    [ "$debug" = true ] && log "Creating connection link..."
    
    if [ -z "$work_dir" ] || [ -z "$user_name" ] || [ -z "$user_uuid" ] || \
       [ -z "$server_ip" ] || [ -z "$server_port" ]; then
        error "Missing required parameters for connection link"
        return 1
    fi
    
    local link_file="$work_dir/users/$user_name.link"
    local connection_link=""
    
    # Create connection link for VLESS+Reality
    connection_link="vless://$user_uuid@$server_ip:$server_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$server_sni&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#$user_name"
    
    # Save connection link
    echo "$connection_link" > "$link_file"
    
    if [ ! -f "$link_file" ]; then
        error "Failed to create connection link file"
        return 1
    fi
    
    [ "$debug" = true ] && log "Connection link created: $link_file"
    
    # Generate QR code if qrencode is available
    if command -v qrencode >/dev/null 2>&1; then
        local qr_file="$work_dir/users/$user_name.png"
        qrencode -o "$qr_file" "$connection_link" 2>/dev/null || {
            warning "Failed to generate QR code"
        }
        [ "$debug" = true ] && [ -f "$qr_file" ] && log "QR code generated: $qr_file"
    fi
    
    return 0
}

# =============================================================================
# COMPREHENSIVE SETUP FUNCTION
# =============================================================================

# Setup complete Xray configuration environment
setup_xray_configuration() {
    local work_dir="$1"
    local protocol="$2"
    local server_port="$3"
    local user_uuid="$4"
    local user_name="$5"
    local server_ip="$6"
    local server_sni="$7"
    local private_key="$8"
    local public_key="$9"
    local short_id="${10}"
    local debug=${11:-false}
    
    [ "$debug" = true ] && log "Setting up Xray configuration environment..."
    
    # Setup directories
    setup_xray_directories "$work_dir" "$debug" || {
        error "Failed to setup Xray directories"
        return 1
    }
    
    # Create Xray configuration
    create_xray_config "$work_dir" "$protocol" "$server_port" "$user_uuid" \
        "$user_name" "$server_sni" "$private_key" "$public_key" "$short_id" "$debug" || {
        error "Failed to create Xray configuration"
        return 1
    }
    
    # Validate configuration
    validate_xray_config "$work_dir/config/config.json" "$debug" || {
        error "Configuration validation failed"
        return 1
    }
    
    # Create user data
    create_user_data "$work_dir" "$user_name" "$user_uuid" "$server_port" \
        "$server_ip" "$protocol" "$server_sni" "$private_key" "$public_key" \
        "$short_id" "$debug" || {
        error "Failed to create user data"
        return 1
    }
    
    # Create connection link
    create_connection_link "$work_dir" "$user_name" "$user_uuid" "$server_ip" \
        "$server_port" "$protocol" "$server_sni" "$public_key" "$short_id" \
        "$debug" || {
        error "Failed to create connection link"
        return 1
    }
    
    [ "$debug" = true ] && log "Xray configuration environment setup completed"
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f setup_xray_directories
export -f create_xray_config_reality
export -f create_xray_config
export -f validate_xray_config
export -f create_user_data
export -f create_connection_link
export -f setup_xray_configuration

# Debug mode check
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being run directly, show usage
    echo "Usage: $0 <work_dir> <protocol> <server_port> <user_uuid> <user_name> <server_ip> [server_sni] [private_key] [public_key] [short_id]"
    echo "Protocol: vless-reality"
    exit 1
fi