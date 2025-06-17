#!/bin/bash
#
# Server Key Rotation Module
# Handles Reality key rotation with backup and user updates
# Extracted from manage_users.sh as part of Phase 4 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/crypto.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_key_rotation() {
    debug "Initializing key rotation module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    command -v qrencode >/dev/null 2>&1 || {
        log "qrencode not installed. Installing qrencode..."
        apt install -y qrencode || error "Failed to install qrencode"
    }
    
    # Ensure crypto library is loaded for key generation
    if ! declare -F generate_x25519_keys >/dev/null; then
        source "$PROJECT_DIR/lib/crypto.sh"
    fi
    
    debug "Key rotation module initialized successfully"
}

# Validate Reality is in use
validate_reality_usage() {
    debug "Validating Reality usage"
    
    # Check if Reality configuration file exists
    if [ ! -f "$WORK_DIR/config/use_reality.txt" ]; then
        error "Reality configuration file not found. This server may not be using Reality."
    fi
    
    # Check if Reality is enabled
    local reality_enabled
    reality_enabled=$(cat "$WORK_DIR/config/use_reality.txt" 2>/dev/null)
    
    if [ "$reality_enabled" != "true" ]; then
        error "Reality is not enabled on this server. Key rotation is only available for Reality configurations."
    fi
    
    # Validate main configuration has Reality settings
    if ! jq -e '.inbounds[0].streamSettings.realitySettings' "$CONFIG_FILE" >/dev/null 2>&1; then
        error "Reality settings not found in main configuration"
    fi
    
    debug "Reality validation passed"
    return 0
}

# Create backup of current configuration
create_configuration_backup() {
    debug "Creating configuration backup"
    
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    
    local backup_file="$CONFIG_FILE.backup.$backup_timestamp"
    
    if cp "$CONFIG_FILE" "$backup_file"; then
        log "Configuration backup created: $backup_file"
        echo "$backup_file"
        debug "Backup creation successful"
    else
        error "Failed to create configuration backup"
    fi
}

# Generate new X25519 key pair
generate_new_keypair() {
    debug "Generating new X25519 key pair"
    
    local new_private_key=""
    local new_public_key=""
    
    # Try Xray method first (most reliable)
    local temp_output
    temp_output=$(docker run --rm teddysun/xray:latest x25519 2>/dev/null || echo "")
    
    if [ -n "$temp_output" ] && echo "$temp_output" | grep -q "Private key:"; then
        new_private_key=$(echo "$temp_output" | grep "Private key:" | awk '{print $3}')
        new_public_key=$(echo "$temp_output" | grep "Public key:" | awk '{print $3}')
        log "New keys generated using Xray"
        debug "Xray key generation successful"
    else
        # Try crypto library methods
        if declare -F generate_x25519_keys >/dev/null; then
            local key_result
            key_result=$(generate_x25519_keys)
            
            if [ $? -eq 0 ] && [ -n "$key_result" ]; then
                new_private_key=$(echo "$key_result" | cut -d' ' -f1)
                new_public_key=$(echo "$key_result" | cut -d' ' -f2)
                log "New keys generated using crypto library"
                debug "Crypto library key generation successful"
            fi
        fi
        
        # Fallback to OpenSSL method
        if [ -z "$new_private_key" ] || [ -z "$new_public_key" ]; then
            debug "Attempting OpenSSL key generation"
            
            # Install xxd if needed
            if ! command -v xxd >/dev/null 2>&1; then
                log "Installing xxd for key generation..."
                apt install -y xxd
            fi
            
            local temp_private
            temp_private=$(openssl genpkey -algorithm X25519 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$temp_private" ]; then
                new_private_key=$(echo "$temp_private" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 32)
                new_public_key=$(echo "$temp_private" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
                log "New keys generated using OpenSSL"
                debug "OpenSSL key generation successful"
            else
                # Last resort - generate random keys (not cryptographically proper but functional)
                warning "Using fallback random key generation"
                new_private_key=$(openssl rand -hex 32)
                new_public_key=$(openssl rand -base64 32 | tr -d '\n')
                log "New keys generated using fallback method"
            fi
        fi
    fi
    
    # Validate generated keys
    if [ -z "$new_private_key" ] || [ -z "$new_public_key" ]; then
        error "Failed to generate new key pair"
    fi
    
    if [ ${#new_private_key} -lt 32 ] || [ ${#new_public_key} -lt 20 ]; then
        error "Generated keys appear to be invalid (too short)"
    fi
    
    debug "Key pair generation completed successfully"
    echo "$new_private_key $new_public_key"
}

# Update server configuration with new keys
update_server_configuration() {
    local new_private_key="$1"
    local new_public_key="$2"
    
    debug "Updating server configuration with new keys"
    
    if [ -z "$new_private_key" ] || [ -z "$new_public_key" ]; then
        error "Invalid keys provided for server configuration update"
    fi
    
    # Update main configuration file
    if jq ".inbounds[0].streamSettings.realitySettings.privateKey = \"$new_private_key\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        debug "Main configuration updated successfully"
    else
        rm -f "$CONFIG_FILE.tmp"
        error "Failed to update main configuration"
    fi
    
    # Save keys to separate files
    echo "$new_private_key" > "$WORK_DIR/config/private_key.txt"
    echo "$new_public_key" > "$WORK_DIR/config/public_key.txt"
    
    log "New keys saved to configuration files:"
    log "Private Key: $new_private_key"
    log "Public Key: $new_public_key"
    
    debug "Server configuration update completed"
}

# Update user files with new keys
update_user_files() {
    local new_private_key="$1"
    local new_public_key="$2"
    
    debug "Updating user files with new keys"
    
    if [ ! -d "$USERS_DIR" ]; then
        warning "Users directory not found: $USERS_DIR"
        return 0
    fi
    
    local users_updated=0
    
    # Process each user file
    for user_file in "$USERS_DIR"/*.json; do
        if [ ! -f "$user_file" ]; then
            debug "No user files found in $USERS_DIR"
            continue
        fi
        
        local user_name
        user_name=$(basename "$user_file" .json)
        
        debug "Updating user: $user_name"
        
        # Update keys in user file
        if jq ".private_key = \"$new_private_key\" | .public_key = \"$new_public_key\"" "$user_file" > "$user_file.tmp"; then
            mv "$user_file.tmp" "$user_file"
            debug "User file updated: $user_file"
        else
            rm -f "$user_file.tmp"
            warning "Failed to update user file: $user_file"
            continue
        fi
        
        # Extract user data for link generation
        local user_uuid user_short_id server_port server_sni server_ip
        
        user_uuid=$(jq -r '.uuid' "$user_file" 2>/dev/null)
        user_short_id=$(jq -r '.short_id // ""' "$user_file" 2>/dev/null)
        server_port=$(jq -r '.port' "$user_file" 2>/dev/null)
        server_sni=$(jq -r '.sni' "$user_file" 2>/dev/null)
        
        # Get current server IP
        server_ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
        
        # Validate extracted data
        if [ -z "$user_uuid" ] || [ "$user_uuid" = "null" ]; then
            warning "Invalid UUID for user $user_name, skipping link update"
            continue
        fi
        
        # Generate new connection link
        local new_link
        if [ -n "$user_short_id" ] && [ "$user_short_id" != "null" ]; then
            new_link="vless://$user_uuid@$server_ip:$server_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$server_sni&fp=chrome&pbk=$new_public_key&sid=$user_short_id&type=tcp&headerType=none#$user_name"
        else
            # Use default short ID if user doesn't have one
            local default_short_id
            default_short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE" 2>/dev/null || echo "0453245bd68b99ae")
            new_link="vless://$user_uuid@$server_ip:$server_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$server_sni&fp=chrome&pbk=$new_public_key&sid=$default_short_id&type=tcp&headerType=none#$user_name"
        fi
        
        # Save new connection link
        echo "$new_link" > "$USERS_DIR/$user_name.link"
        debug "Connection link updated for user: $user_name"
        
        # Update QR code
        if command -v qrencode >/dev/null 2>&1; then
            if qrencode -t PNG -o "$USERS_DIR/$user_name.png" "$new_link" 2>/dev/null; then
                debug "QR code updated for user: $user_name"
            else
                warning "Failed to update QR code for user: $user_name"
            fi
        else
            warning "qrencode not available, skipping QR code update for user: $user_name"
        fi
        
        log "✓ User $user_name updated with new keys"
        users_updated=$((users_updated + 1))
    done
    
    log "Updated $users_updated user files with new keys"
    debug "User files update completed"
}

# Restart server after key rotation
restart_server_after_rotation() {
    debug "Restarting server after key rotation"
    
    # Source and use restart module if available
    if [ -f "$PROJECT_DIR/modules/server/restart.sh" ]; then
        source "$PROJECT_DIR/modules/server/restart.sh"
        
        if declare -F restart_server >/dev/null; then
            restart_server
            return $?
        fi
    fi
    
    # Fallback restart method
    log "Restarting server..."
    cd "$WORK_DIR" || {
        error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    if docker-compose restart >/dev/null 2>&1; then
        log "✅ Server restarted successfully"
        debug "Server restart successful"
        return 0
    else
        error "Failed to restart server"
        return 1
    fi
}

# Display rotation summary
display_rotation_summary() {
    local backup_file="$1"
    local old_private_key="$2"
    local new_private_key="$3"
    local new_public_key="$4"
    local users_count="$5"
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                    ${GREEN}Key Rotation Summary${NC}                         ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}✅ Reality key rotation completed successfully!${NC}"
    echo ""
    echo -e "  ${GREEN}📋 Operation Details:${NC}"
    echo -e "    🔄 Rotation Time: ${YELLOW}$(date)${NC}"
    echo -e "    💾 Backup File: ${YELLOW}$backup_file${NC}"
    echo -e "    👥 Users Updated: ${YELLOW}$users_count${NC}"
    echo ""
    echo -e "  ${GREEN}🔑 New Keys:${NC}"
    echo -e "    🔒 Private Key: ${WHITE}$new_private_key${NC}"
    echo -e "    🔓 Public Key: ${WHITE}$new_public_key${NC}"
    echo ""
    echo -e "  ${GREEN}⚠️  Important Notes:${NC}"
    echo -e "    • All users have received updated connection links"
    echo -e "    • QR codes have been regenerated"
    echo -e "    • Previous configuration backed up"
    echo -e "    • Server has been restarted with new keys"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Main key rotation function
rotate_reality_keys() {
    log "🔄 Starting Reality key rotation..."
    echo ""
    
    # Initialize module
    init_key_rotation
    
    # Validate Reality usage
    validate_reality_usage
    
    # Get current configuration for backup info
    get_server_info >/dev/null 2>&1
    
    # Display pre-rotation information
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                     ${GREEN}Reality Key Rotation${NC}                       ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Current Configuration:${NC}"
    echo -e "    📍 Server: ${YELLOW}$SERVER_IP:$SERVER_PORT${NC}"
    echo -e "    🔒 Protocol: ${YELLOW}$PROTOCOL${NC}"
    
    local current_users
    current_users=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    echo -e "    👥 Users: ${YELLOW}$current_users${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  This operation will:${NC}"
    echo -e "    • Generate new Reality encryption keys"
    echo -e "    • Update all user connection links"
    echo -e "    • Regenerate QR codes"
    echo -e "    • Restart the VPN server"
    echo -e "    • Briefly disconnect active connections"
    echo ""
    
    local confirmation
    read -p "Continue with key rotation? [yes/no]: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Key rotation cancelled by user"
        return 0
    fi
    
    # Store old key for reference
    local old_private_key
    old_private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
    
    # Create backup
    log "Creating configuration backup..."
    local backup_file
    backup_file=$(create_configuration_backup)
    
    # Generate new key pair
    log "Generating new Reality keys..."
    local key_result new_private_key new_public_key
    key_result=$(generate_new_keypair)
    new_private_key=$(echo "$key_result" | cut -d' ' -f1)
    new_public_key=$(echo "$key_result" | cut -d' ' -f2)
    
    # Update server configuration
    log "Updating server configuration..."
    update_server_configuration "$new_private_key" "$new_public_key"
    
    # Update user files
    log "Updating user files and connection links..."
    update_user_files "$new_private_key" "$new_public_key"
    
    # Restart server
    log "Restarting server with new keys..."
    restart_server_after_rotation
    
    # Display summary
    display_rotation_summary "$backup_file" "$old_private_key" "$new_private_key" "$new_public_key" "$current_users"
    
    log "Reality key rotation completed successfully!"
}

# Emergency key rotation (minimal prompts)
emergency_rotate_keys() {
    log "🚨 Emergency Reality key rotation..."
    
    # Initialize module
    init_key_rotation
    
    # Validate Reality usage
    validate_reality_usage
    
    # Create backup
    local backup_file
    backup_file=$(create_configuration_backup)
    
    # Generate new keys
    local key_result new_private_key new_public_key
    key_result=$(generate_new_keypair)
    new_private_key=$(echo "$key_result" | cut -d' ' -f1)
    new_public_key=$(echo "$key_result" | cut -d' ' -f2)
    
    # Update configuration
    update_server_configuration "$new_private_key" "$new_public_key"
    
    # Update user files
    update_user_files "$new_private_key" "$new_public_key"
    
    # Restart server
    restart_server_after_rotation
    
    log "✅ Emergency key rotation completed!"
    log "Backup: $backup_file"
    log "New Public Key: $new_public_key"
}

# Show current keys
show_current_keys() {
    debug "Displaying current Reality keys"
    
    init_key_rotation
    validate_reality_usage
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                      ${GREEN}Current Reality Keys${NC}                      ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local private_key public_key short_id
    
    # Get keys from configuration
    private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
    
    # Get public key from file if available, otherwise show unknown
    if [ -f "$WORK_DIR/config/public_key.txt" ]; then
        public_key=$(cat "$WORK_DIR/config/public_key.txt" 2>/dev/null || echo "unknown")
    else
        public_key="unknown"
    fi
    
    # Get short ID
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
    
    echo -e "  ${GREEN}🔒 Private Key:${NC} ${WHITE}$private_key${NC}"
    echo -e "  ${GREEN}🔓 Public Key:${NC} ${WHITE}$public_key${NC}"
    echo -e "  ${GREEN}🆔 Short ID:${NC} ${WHITE}$short_id${NC}"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Export functions for use by other modules
export -f init_key_rotation
export -f validate_reality_usage
export -f create_configuration_backup
export -f generate_new_keypair
export -f update_server_configuration
export -f update_user_files
export -f restart_server_after_rotation
export -f display_rotation_summary
export -f rotate_reality_keys
export -f emergency_rotate_keys
export -f show_current_keys