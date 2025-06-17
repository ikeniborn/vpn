#!/bin/bash
#
# User Addition Module
# Handles adding new users to the VPN server
# Extracted from manage_users.sh as part of Phase 3 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh" 
source "$PROJECT_DIR/lib/crypto.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_user_add() {
    debug "Initializing user addition module"
    
    # Verify required tools are available
    command -v uuid >/dev/null 2>&1 || {
        log "uuid not installed. Installing uuid..."
        apt install -y uuid || error "Failed to install uuid"
    }
    
    command -v qrencode >/dev/null 2>&1 || {
        log "qrencode not installed. Installing qrencode..."
        apt install -y qrencode || error "Failed to install qrencode"
    }
    
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    # Ensure users directory exists
    mkdir -p "$USERS_DIR"
    debug "User addition module initialized successfully"
}

# Validate user input for new user creation
validate_user_input() {
    local user_name="$1"
    local user_uuid="$2"
    
    debug "Validating user input: name='$user_name', uuid='$user_uuid'"
    
    # Check if user name is provided
    if [ -z "$user_name" ]; then
        error "User name cannot be empty"
    fi
    
    # Check if user name contains invalid characters
    if [[ ! "$user_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "User name can only contain letters, numbers, underscores, and hyphens"
    fi
    
    # Check if user already exists
    if jq -e ".inbounds[0].settings.clients[] | select(.email == \"$user_name\")" "$CONFIG_FILE" > /dev/null 2>&1; then
        error "User with name '$user_name' already exists"
    fi
    
    # Validate UUID format if provided
    if [ -n "$user_uuid" ]; then
        if [[ ! "$user_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
            error "Invalid UUID format: $user_uuid"
        fi
    fi
    
    debug "User input validation passed"
    return 0
}

# Generate connection link for the user
generate_connection_link() {
    local user_name="$1"
    local user_uuid="$2"
    local user_short_id="$3"
    
    debug "Generating connection link for user: $user_name"
    
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
        
        # Use user-specific short ID if available
        local used_short_id="${user_short_id:-$SHORT_ID}"
        
        # Create Reality link with XTLS Vision support
        connection_link="vless://$user_uuid@$SERVER_IP:$SERVER_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$used_short_id&type=tcp&headerType=none#$user_name"
        
        debug "Created Reality link: $connection_link"
    else
        # Create standard VLESS link
        connection_link="vless://$user_uuid@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$user_name"
        debug "Created standard VLESS link: $connection_link"
    fi
    
    echo "$connection_link"
}

# Create user configuration file
create_user_config() {
    local user_name="$1"
    local user_uuid="$2"
    local user_short_id="$3"
    
    debug "Creating configuration file for user: $user_name"
    
    local config_file="$USERS_DIR/$user_name.json"
    
    if [ "$USE_REALITY" = true ]; then
        cat > "$config_file" <<EOL
{
  "name": "$user_name",
  "uuid": "$user_uuid",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "short_id": "$user_short_id",
  "protocol": "$PROTOCOL"
}
EOL
    else
        cat > "$config_file" <<EOL
{
  "name": "$user_name",
  "uuid": "$user_uuid",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "protocol": "$PROTOCOL"
}
EOL
    fi
    
    debug "User configuration file created: $config_file"
}

# Generate QR code for the user
generate_user_qr_code() {
    local user_name="$1"
    local connection_link="$2"
    
    debug "Generating QR code for user: $user_name"
    
    local qr_file="$USERS_DIR/$user_name.png"
    local link_file="$USERS_DIR/$user_name.link"
    
    # Save connection link to file
    echo "$connection_link" > "$link_file"
    debug "Connection link saved to: $link_file"
    
    # Generate QR code image
    if qrencode -t PNG -o "$qr_file" "$connection_link" 2>/dev/null; then
        debug "QR code image generated: $qr_file"
    else
        warning "Failed to generate QR code image"
    fi
    
    # Display QR code in terminal
    if qrencode -t ANSIUTF8 "$connection_link" 2>/dev/null; then
        debug "QR code displayed in terminal"
    else
        warning "Failed to display QR code in terminal"
    fi
}

# Add user to server configuration
add_user_to_config() {
    local user_name="$1"
    local user_uuid="$2"
    local user_short_id="$3"
    
    debug "Adding user to server configuration: $user_name"
    
    # Add user to clients array
    if [ "$USE_REALITY" = true ]; then
        # For Reality use xtls-rprx-vision flow
        jq ".inbounds[0].settings.clients += [{\"id\": \"$user_uuid\", \"flow\": \"xtls-rprx-vision\", \"email\": \"$user_name\"}]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        
        # Add new shortId to shortIds array if not present
        if [ -n "$user_short_id" ]; then
            jq ".inbounds[0].streamSettings.realitySettings.shortIds |= (. + [\"$user_short_id\"] | unique)" "$CONFIG_FILE.tmp" > "$CONFIG_FILE"
            debug "Added unique short ID to configuration: $user_short_id"
        else
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        fi
        rm -f "$CONFIG_FILE.tmp"
    else
        # For standard VLESS use empty flow
        jq ".inbounds[0].settings.clients += [{\"id\": \"$user_uuid\", \"flow\": \"\", \"email\": \"$user_name\"}]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    debug "User added to server configuration successfully"
}

# Restart VPN server to apply changes
restart_vpn_server() {
    debug "Restarting VPN server to apply changes"
    
    # Ensure logs directory exists
    mkdir -p "$WORK_DIR/logs"
    
    # Create log files if they don't exist
    touch "$WORK_DIR/logs/access.log" "$WORK_DIR/logs/error.log"
    chmod 644 "$WORK_DIR/logs/access.log" "$WORK_DIR/logs/error.log"
    
    # Change to work directory and restart
    cd "$WORK_DIR" || error "Failed to change to work directory: $WORK_DIR"
    
    if docker-compose restart >/dev/null 2>&1; then
        log "VPN server restarted successfully"
        debug "Docker compose restart completed"
    else
        error "Failed to restart VPN server"
    fi
}

# Main function to add a new user
add_user() {
    log "Adding new user to VPN server..."
    
    # Initialize module
    init_user_add
    
    # Get server configuration
    get_server_info
    
    # Request user details
    local user_name=""
    local user_uuid=""
    local user_short_id=""
    
    # Get user name
    echo ""
    read -p "Enter new user name: " user_name
    
    # Generate UUID
    user_uuid=$(uuid -v 4)
    read -p "Enter UUID for user [$user_uuid]: " input_uuid
    user_uuid=${input_uuid:-$user_uuid}
    
    # Validate input
    validate_user_input "$user_name" "$user_uuid"
    
    # Generate unique short ID for Reality users
    if [ "$USE_REALITY" = true ]; then
        user_short_id=$(openssl rand -hex 8)
        log "Generated unique Short ID for user: $user_short_id"
    fi
    
    # Add user to configuration
    add_user_to_config "$user_name" "$user_uuid" "$user_short_id"
    
    # Create user configuration file
    create_user_config "$user_name" "$user_uuid" "$user_short_id"
    
    # Generate connection link
    local connection_link
    connection_link=$(generate_connection_link "$user_name" "$user_uuid" "$user_short_id")
    
    # Generate QR code
    generate_user_qr_code "$user_name" "$connection_link"
    
    # Restart server
    restart_vpn_server
    
    # Display success information
    echo ""
    log "User '$user_name' successfully added!"
    log "UUID: $user_uuid"
    log "Connection link saved to: $USERS_DIR/$user_name.link"
    log "QR code saved to: $USERS_DIR/$user_name.png"
    
    echo ""
    echo "Connection link:"
    echo "$connection_link"
    echo ""
    echo "QR code:"
    
    # Show client information if function is available
    if command -v show_client_info >/dev/null 2>&1; then
        show_client_info
    fi
}

# Export functions for use by other modules
export -f init_user_add
export -f validate_user_input
export -f generate_connection_link
export -f create_user_config
export -f generate_user_qr_code
export -f add_user_to_config
export -f restart_vpn_server
export -f add_user