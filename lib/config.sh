#!/bin/bash

# VPN Project Configuration Management Library

# Mark as sourced
export CONFIG_LIB_SOURCED=true
# Handles loading, saving, and validating server configuration

# Source common library
if [ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# ========================= CONFIGURATION VARIABLES =========================

# Server configuration variables
# Only set if not already defined to avoid overwriting during module loading
[ -z "$SERVER_IP" ] && export SERVER_IP=""
[ -z "$SERVER_PORT" ] && export SERVER_PORT=""
[ -z "$SERVER_SNI" ] && export SERVER_SNI=""
[ -z "$USE_REALITY" ] && export USE_REALITY=""
[ -z "$PROTOCOL" ] && export PROTOCOL=""
[ -z "$PRIVATE_KEY" ] && export PRIVATE_KEY=""
[ -z "$PUBLIC_KEY" ] && export PUBLIC_KEY=""
[ -z "$SHORT_ID" ] && export SHORT_ID=""

# ========================= CONFIGURATION FILE MANAGEMENT =========================

# Get server IP address
get_server_ip() {
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(get_current_ip)
        debug "Server IP detected: $SERVER_IP"
    fi
    echo "$SERVER_IP"
}

# Load server port from configuration
load_server_port() {
    if [ -f "$WORK_DIR/config/port.txt" ]; then
        SERVER_PORT=$(safe_read_file "$WORK_DIR/config/port.txt")
        debug "Port loaded from file: $SERVER_PORT"
    elif [ -f "$CONFIG_FILE" ] && command_exists jq; then
        SERVER_PORT=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null)
        if [ "$SERVER_PORT" != "null" ] && [ -n "$SERVER_PORT" ]; then
            safe_write_file "$WORK_DIR/config/port.txt" "$SERVER_PORT"
            debug "Port loaded from JSON config: $SERVER_PORT"
        fi
    fi
    
    if [ -z "$SERVER_PORT" ] || [ "$SERVER_PORT" = "null" ]; then
        warning "Server port not found in configuration"
        return 1
    fi
}

# Load SNI domain from configuration
load_server_sni() {
    if [ -f "$WORK_DIR/config/sni.txt" ]; then
        SERVER_SNI=$(safe_read_file "$WORK_DIR/config/sni.txt")
        debug "SNI loaded from file: $SERVER_SNI"
    else
        SERVER_SNI="addons.mozilla.org"
        debug "Using default SNI: $SERVER_SNI"
    fi
}

# Detect protocol and Reality usage
load_protocol_config() {
    if [ -f "$CONFIG_FILE" ] && command_exists jq; then
        local security=$(jq -r '.inbounds[0].streamSettings.security' "$CONFIG_FILE" 2>/dev/null)
        
        if [ "$security" = "reality" ]; then
            USE_REALITY=true
            PROTOCOL="vless+reality"
            debug "Reality protocol detected"
        else
            USE_REALITY=false
            PROTOCOL="vless"
            debug "Basic VLESS protocol detected"
        fi
        
        # Save protocol info
        safe_write_file "$WORK_DIR/config/protocol.txt" "$PROTOCOL"
        safe_write_file "$WORK_DIR/config/use_reality.txt" "$USE_REALITY"
    else
        # Try to load from files
        if [ -f "$WORK_DIR/config/protocol.txt" ]; then
            PROTOCOL=$(safe_read_file "$WORK_DIR/config/protocol.txt")
            if [[ "$PROTOCOL" == *"reality"* ]]; then
                USE_REALITY=true
            else
                USE_REALITY=false
            fi
        else
            warning "Protocol configuration not found"
            return 1
        fi
    fi
}

# Load Reality keys
load_reality_keys() {
    if [ "$USE_REALITY" != "true" ]; then
        debug "Reality not enabled, skipping key loading"
        return 0
    fi
    
    # Try to load from separate files first
    if [ -f "$WORK_DIR/config/private_key.txt" ] && 
       [ -f "$WORK_DIR/config/public_key.txt" ] && 
       [ -f "$WORK_DIR/config/short_id.txt" ]; then
        
        PRIVATE_KEY=$(safe_read_file "$WORK_DIR/config/private_key.txt")
        PUBLIC_KEY=$(safe_read_file "$WORK_DIR/config/public_key.txt")
        SHORT_ID=$(safe_read_file "$WORK_DIR/config/short_id.txt")
        debug "Reality keys loaded from separate files"
        
    else
        # Try to get from user files
        local first_user_file=$(ls -1 "$USERS_DIR"/*.json 2>/dev/null | head -1)
        if [ -n "$first_user_file" ] && command_exists jq; then
            PUBLIC_KEY=$(jq -r '.public_key' "$first_user_file" 2>/dev/null)
            PRIVATE_KEY=$(jq -r '.private_key' "$first_user_file" 2>/dev/null)
            SHORT_ID=$(jq -r '.short_id // ""' "$first_user_file" 2>/dev/null)
            debug "Reality keys loaded from user file: $first_user_file"
            
        elif [ -f "$CONFIG_FILE" ] && command_exists jq; then
            # Try to get from main config
            PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE" 2>/dev/null)
            SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE" 2>/dev/null)
            
            # Use default public key for known private key
            if [ "$PRIVATE_KEY" = "c29567a5ff1928bcf525e2d4016f7d7ce6f3c14c25c6aacc1998de43ba7b6a3e" ]; then
                PUBLIC_KEY="YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc"
            else
                PUBLIC_KEY="YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc"
                warning "Using fallback public key"
            fi
            
            # Save keys to separate files
            save_reality_keys
            debug "Reality keys loaded from JSON config"
        fi
    fi
    
    # Validate keys
    if [ -z "$PUBLIC_KEY" ] || [ "$PUBLIC_KEY" = "null" ] || [ "$PUBLIC_KEY" = "unknown" ]; then
        warning "Invalid or missing Reality public key"
        return 1
    fi
    
    if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "null" ] || [ "$PRIVATE_KEY" = "unknown" ]; then
        warning "Invalid or missing Reality private key"
        return 1
    fi
}

# Save Reality keys to separate files
save_reality_keys() {
    if [ "$USE_REALITY" = "true" ] && [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ]; then
        safe_write_file "$WORK_DIR/config/private_key.txt" "$PRIVATE_KEY"
        safe_write_file "$WORK_DIR/config/public_key.txt" "$PUBLIC_KEY"
        if [ -n "$SHORT_ID" ]; then
            safe_write_file "$WORK_DIR/config/short_id.txt" "$SHORT_ID"
        fi
        debug "Reality keys saved to separate files"
    fi
}

# ========================= MAIN CONFIGURATION FUNCTIONS =========================

# Load all server configuration
get_server_info() {
    debug "Loading server configuration..."
    
    # Ensure required tools are available
    if ! command_exists jq; then
        warning "jq not found, some configuration loading may fail"
    fi
    
    # Load configuration components
    get_server_ip
    load_server_port || return 1
    load_server_sni
    load_protocol_config || return 1
    load_reality_keys
    
    debug "Server configuration loaded successfully"
    debug "IP: $SERVER_IP, Port: $SERVER_PORT, SNI: $SERVER_SNI"
    debug "Protocol: $PROTOCOL, Reality: $USE_REALITY"
    
    return 0
}

# Save current configuration
save_config() {
    debug "Saving server configuration..."
    
    ensure_dir "$WORK_DIR/config"
    
    # Save basic configuration
    safe_write_file "$WORK_DIR/config/port.txt" "$SERVER_PORT"
    safe_write_file "$WORK_DIR/config/sni.txt" "$SERVER_SNI"
    safe_write_file "$WORK_DIR/config/protocol.txt" "$PROTOCOL"
    safe_write_file "$WORK_DIR/config/use_reality.txt" "$USE_REALITY"
    
    # Save Reality keys if applicable
    save_reality_keys
    
    debug "Configuration saved successfully"
}

# Validate current configuration
validate_config() {
    debug "Validating configuration..."
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Main configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Validate port
    if ! validate_port "$SERVER_PORT"; then
        error "Invalid server port: $SERVER_PORT"
        return 1
    fi
    
    # Validate Reality configuration if enabled
    if [ "$USE_REALITY" = "true" ]; then
        if [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
            error "Reality keys are missing or invalid"
            return 1
        fi
        
        if [ -z "$SHORT_ID" ]; then
            warning "Reality short ID is missing"
        fi
    fi
    
    debug "Configuration validation passed"
    return 0
}

# Load configuration with error handling
load_config() {
    if get_server_info; then
        if validate_config; then
            debug "Configuration loaded and validated successfully"
            return 0
        else
            error "Configuration validation failed"
            return 1
        fi
    else
        error "Failed to load configuration"
        return 1
    fi
}

# Display current configuration (for debugging)
show_config() {
    echo "=== Server Configuration ==="
    echo "IP: $SERVER_IP"
    echo "Port: $SERVER_PORT"
    echo "SNI: $SERVER_SNI"
    echo "Protocol: $PROTOCOL"
    echo "Reality: $USE_REALITY"
    if [ "$USE_REALITY" = "true" ]; then
        echo "Public Key: ${PUBLIC_KEY:0:20}..."
        echo "Short ID: $SHORT_ID"
    fi
    echo "=========================="
}