#!/bin/bash
#
# User Edit Module
# Handles editing existing users in the VPN server
# Extracted from manage_users.sh as part of Phase 3 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/crypto.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_user_edit() {
    debug "Initializing user edit module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    command -v qrencode >/dev/null 2>&1 || {
        log "qrencode not installed. Installing qrencode..."
        apt install -y qrencode || error "Failed to install qrencode"
    }
    
    # Ensure users directory exists
    mkdir -p "$USERS_DIR"
    debug "User edit module initialized successfully"
}

# Validate user exists
validate_user_exists() {
    local user_name="$1"
    
    debug "Validating user exists: $user_name"
    
    if [ -z "$user_name" ]; then
        error "User name cannot be empty"
    fi
    
    # Check if user exists in configuration
    if ! jq -e ".inbounds[0].settings.clients[] | select(.email == \"$user_name\")" "$CONFIG_FILE" > /dev/null 2>&1; then
        error "User with name '$user_name' not found"
    fi
    
    debug "User validation passed: $user_name"
    return 0
}

# Validate new user data
validate_new_user_data() {
    local old_name="$1"
    local new_name="$2"
    local new_uuid="$3"
    
    debug "Validating new user data: old='$old_name', new='$new_name', uuid='$new_uuid'"
    
    # Check if new name contains invalid characters
    if [[ ! "$new_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "User name can only contain letters, numbers, underscores, and hyphens"
    fi
    
    # Check if new name is already taken (by someone else)
    if [ "$new_name" != "$old_name" ]; then
        if jq -e ".inbounds[0].settings.clients[] | select(.email == \"$new_name\")" "$CONFIG_FILE" > /dev/null 2>&1; then
            error "User with name '$new_name' already exists"
        fi
    fi
    
    # Validate UUID format
    if [[ ! "$new_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error "Invalid UUID format: $new_uuid"
    fi
    
    debug "New user data validation passed"
    return 0
}

# Get current user information
get_current_user_info() {
    local user_name="$1"
    
    debug "Getting current user information: $user_name"
    
    # Get current UUID
    local current_uuid
    current_uuid=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | .id" "$CONFIG_FILE" 2>/dev/null)
    
    if [ -z "$current_uuid" ] || [ "$current_uuid" = "null" ]; then
        error "Failed to get current UUID for user: $user_name"
    fi
    
    debug "Current user UUID: $current_uuid"
    echo "$current_uuid"
}

# Update user in configuration
update_user_in_config() {
    local old_name="$1"
    local new_name="$2"
    local new_uuid="$3"
    
    debug "Updating user in configuration: $old_name -> $new_name"
    
    # Remove old user entry
    if ! jq "del(.inbounds[0].settings.clients[] | select(.email == \"$old_name\"))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
        rm -f "$CONFIG_FILE.tmp"
        error "Failed to remove old user from configuration"
    fi
    
    # Add updated user entry
    if [ "$USE_REALITY" = true ]; then
        # For Reality use xtls-rprx-vision flow
        if ! jq ".inbounds[0].settings.clients += [{\"id\": \"$new_uuid\", \"flow\": \"xtls-rprx-vision\", \"email\": \"$new_name\"}]" "$CONFIG_FILE.tmp" > "$CONFIG_FILE"; then
            rm -f "$CONFIG_FILE.tmp"
            error "Failed to add updated user to configuration"
        fi
    else
        # For standard VLESS use empty flow
        if ! jq ".inbounds[0].settings.clients += [{\"id\": \"$new_uuid\", \"flow\": \"\", \"email\": \"$new_name\"}]" "$CONFIG_FILE.tmp" > "$CONFIG_FILE"; then
            rm -f "$CONFIG_FILE.tmp"
            error "Failed to add updated user to configuration"
        fi
    fi
    
    rm -f "$CONFIG_FILE.tmp"
    debug "User updated in configuration successfully"
}

# Generate connection link for updated user
generate_updated_connection_link() {
    local user_name="$1"
    local user_uuid="$2"
    
    debug "Generating updated connection link for user: $user_name"
    
    local connection_link=""
    
    if [ "$USE_REALITY" = true ]; then
        # Validate Reality parameters
        if [ -z "$PUBLIC_KEY" ] || [ "$PUBLIC_KEY" = "null" ] || [ "$PUBLIC_KEY" = "unknown" ]; then
            warning "Public key Reality unavailable. Using fixed key..."
            PUBLIC_KEY="YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc"
        fi
        
        if [ -z "$SHORT_ID" ] || [ "$SHORT_ID" = "null" ]; then
            warning "Short ID Reality unavailable. Using fixed ID."
            SHORT_ID="0453245bd68b99ae"
        fi
        
        # Create Reality link with XTLS Vision support
        connection_link="vless://$user_uuid@$SERVER_IP:$SERVER_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#$user_name"
        
        debug "Created updated Reality link: $connection_link"
    else
        # Create standard VLESS link
        connection_link="vless://$user_uuid@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$user_name"
        debug "Created updated standard VLESS link: $connection_link"
    fi
    
    echo "$connection_link"
}

# Update user configuration files
update_user_files() {
    local old_name="$1"
    local new_name="$2"
    local new_uuid="$3"
    local connection_link="$4"
    
    debug "Updating user files: $old_name -> $new_name"
    
    # Remove old files
    rm -f "$USERS_DIR/$old_name.json" "$USERS_DIR/$old_name.link" "$USERS_DIR/$old_name.png"
    debug "Removed old user files"
    
    # Create new configuration file
    local config_file="$USERS_DIR/$new_name.json"
    
    if [ "$USE_REALITY" = true ]; then
        cat > "$config_file" <<EOL
{
  "name": "$new_name",
  "uuid": "$new_uuid",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "short_id": "$SHORT_ID",
  "protocol": "$PROTOCOL"
}
EOL
    else
        cat > "$config_file" <<EOL
{
  "name": "$new_name",
  "uuid": "$new_uuid",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "protocol": "$PROTOCOL"
}
EOL
    fi
    
    debug "Created new user configuration file: $config_file"
    
    # Save connection link
    local link_file="$USERS_DIR/$new_name.link"
    echo "$connection_link" > "$link_file"
    debug "Connection link saved to: $link_file"
    
    # Generate QR code image
    local qr_file="$USERS_DIR/$new_name.png"
    if qrencode -t PNG -o "$qr_file" "$connection_link" 2>/dev/null; then
        debug "QR code image generated: $qr_file"
    else
        warning "Failed to generate QR code image"
    fi
}

# Restart VPN server to apply changes
restart_vpn_server() {
    debug "Restarting VPN server to apply changes"
    
    # Change to work directory and restart
    cd "$WORK_DIR" || error "Failed to change to work directory: $WORK_DIR"
    
    if docker-compose restart >/dev/null 2>&1; then
        log "VPN server restarted successfully"
        debug "Docker compose restart completed"
    else
        error "Failed to restart VPN server"
    fi
}

# Display user edit summary
display_edit_summary() {
    local old_name="$1"
    local new_name="$2"
    local old_uuid="$3"
    local new_uuid="$4"
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}          ${GREEN}User Edit Summary${NC}                ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Old Information:${NC}"
    echo -e "    Name: ${YELLOW}$old_name${NC}"
    echo -e "    UUID: ${YELLOW}$old_uuid${NC}"
    echo ""
    echo -e "  ${GREEN}New Information:${NC}"
    echo -e "    Name: ${YELLOW}$new_name${NC}"
    echo -e "    UUID: ${YELLOW}$new_uuid${NC}"
    echo ""
    
    local confirmation
    read -p "$(echo -e ${YELLOW}Confirm these changes? [yes/no]:${NC} )" confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "User edit cancelled"
        return 1
    fi
    
    return 0
}

# Main function to edit a user
edit_user() {
    log "Editing user in VPN server..."
    
    # Initialize module
    init_user_edit
    
    # Get server configuration
    get_server_info
    
    # Source and show user list
    if [ -f "$PROJECT_DIR/modules/users/list.sh" ]; then
        source "$PROJECT_DIR/modules/users/list.sh"
        list_users
    else
        # Fallback: simple user list
        echo ""
        log "Current users:"
        jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE" 2>/dev/null | while read -r user; do
            echo "  • $user"
        done
        echo ""
    fi
    
    # Get user to edit
    local user_name=""
    read -p "Enter user name to edit: " user_name
    
    # Validate user exists
    validate_user_exists "$user_name"
    
    # Get current user information
    local current_uuid
    current_uuid=$(get_current_user_info "$user_name")
    
    # Get new user information
    local new_name=""
    local new_uuid=""
    
    echo ""
    read -p "Enter new user name [$user_name]: " new_name
    new_name=${new_name:-$user_name}
    
    read -p "Enter new UUID [$current_uuid]: " new_uuid
    new_uuid=${new_uuid:-$current_uuid}
    
    # Validate new data
    validate_new_user_data "$user_name" "$new_name" "$new_uuid"
    
    # Display summary and confirm
    if ! display_edit_summary "$user_name" "$new_name" "$current_uuid" "$new_uuid"; then
        return 0
    fi
    
    # Perform update
    log "Updating user '$user_name'..."
    
    # Update configuration
    update_user_in_config "$user_name" "$new_name" "$new_uuid"
    
    # Generate new connection link
    local connection_link
    connection_link=$(generate_updated_connection_link "$new_name" "$new_uuid")
    
    # Update files
    update_user_files "$user_name" "$new_name" "$new_uuid" "$connection_link"
    
    # Restart server
    restart_vpn_server
    
    # Display success information
    echo ""
    log "User successfully updated!"
    log "New name: $new_name"
    log "New UUID: $new_uuid"
    log "Connection link saved to: $USERS_DIR/$new_name.link"
    log "QR code saved to: $USERS_DIR/$new_name.png"
    
    echo ""
    echo "Updated connection link:"
    echo "$connection_link"
    echo ""
    echo "QR code:"
    
    # Display QR code in terminal
    if qrencode -t ANSIUTF8 "$connection_link" 2>/dev/null; then
        debug "QR code displayed in terminal"
    else
        warning "Failed to display QR code in terminal"
    fi
    
    # Show client information if function is available
    if command -v show_client_info >/dev/null 2>&1; then
        show_client_info
    fi
}

# Batch edit function for multiple users (advanced feature)
batch_edit_users() {
    log "Batch user edit mode..."
    
    # Initialize module
    init_user_edit
    
    echo ""
    echo "Available operations:"
    echo "1. Regenerate UUIDs for all users"
    echo "2. Update server IP for all users"
    echo "3. Regenerate all QR codes"
    
    local operation
    read -p "Select operation (1-3): " operation
    
    case $operation in
        1)
            regenerate_all_uuids
            ;;
        2)
            update_all_server_ip
            ;;
        3)
            regenerate_all_qr_codes
            ;;
        *)
            error "Invalid operation selected"
            ;;
    esac
}

# Regenerate UUIDs for all users
regenerate_all_uuids() {
    log "Regenerating UUIDs for all users..."
    
    # Get all users
    local user_names
    mapfile -t user_names < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE" 2>/dev/null)
    
    if [ ${#user_names[@]} -eq 0 ]; then
        warning "No users found"
        return 0
    fi
    
    echo "This will regenerate UUIDs for ${#user_names[@]} users:"
    for user_name in "${user_names[@]}"; do
        echo "  • $user_name"
    done
    
    local confirmation
    read -p "$(echo -e ${YELLOW}Continue? [yes/no]:${NC} )" confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Operation cancelled"
        return 0
    fi
    
    # Regenerate each user
    for user_name in "${user_names[@]}"; do
        log "Regenerating UUID for: $user_name"
        local new_uuid
        new_uuid=$(uuid -v 4)
        update_user_in_config "$user_name" "$user_name" "$new_uuid"
        
        # Update files with new UUID
        local connection_link
        connection_link=$(generate_updated_connection_link "$user_name" "$new_uuid")
        update_user_files "$user_name" "$user_name" "$new_uuid" "$connection_link"
    done
    
    restart_vpn_server
    log "UUID regeneration completed for all users"
}

# Export functions for use by other modules
export -f init_user_edit
export -f validate_user_exists
export -f validate_new_user_data
export -f get_current_user_info
export -f update_user_in_config
export -f generate_updated_connection_link
export -f update_user_files
export -f restart_vpn_server
export -f display_edit_summary
export -f edit_user
export -f batch_edit_users
export -f regenerate_all_uuids