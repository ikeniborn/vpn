#!/bin/bash
#
# User Show Module
# Handles displaying detailed user information and QR codes
# Extracted from manage_users.sh as part of Phase 3 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/crypto.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_user_show() {
    debug "Initializing user show module"
    
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
    debug "User show module initialized successfully"
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

# Get or create user configuration file
ensure_user_config() {
    local user_name="$1"
    
    debug "Ensuring user configuration exists: $user_name"
    
    local config_file="$USERS_DIR/$user_name.json"
    
    # If config file doesn't exist, create it
    if [ ! -f "$config_file" ]; then
        warning "User configuration file not found. Creating new file."
        
        # Get user UUID from main config
        local user_uuid
        user_uuid=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | .id" "$CONFIG_FILE" 2>/dev/null)
        
        if [ -z "$user_uuid" ] || [ "$user_uuid" = "null" ]; then
            error "Failed to get UUID for user: $user_name"
        fi
        
        # Create configuration file
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
  "short_id": "$SHORT_ID",
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
    else
        # Update server IP if it has changed
        local current_server_ip
        current_server_ip=$(curl -s https://api.ipify.org)
        
        local config_server_ip
        config_server_ip=$(jq -r '.server' "$config_file" 2>/dev/null)
        
        if [ "$current_server_ip" != "$config_server_ip" ]; then
            debug "Updating server IP in user config: $current_server_ip"
            jq ".server = \"$current_server_ip\"" "$config_file" > "$config_file.tmp"
            mv "$config_file.tmp" "$config_file"
        fi
    fi
}

# Generate or update connection link
ensure_connection_link() {
    local user_name="$1"
    
    debug "Ensuring connection link exists: $user_name"
    
    # Get user data from config file
    local config_file="$USERS_DIR/$user_name.json"
    local user_uuid
    local user_port
    local user_sni
    local user_public_key
    local user_short_id
    
    user_uuid=$(jq -r '.uuid' "$config_file" 2>/dev/null)
    user_port=$(jq -r '.port' "$config_file" 2>/dev/null)
    user_sni=$(jq -r '.sni' "$config_file" 2>/dev/null)
    user_public_key=$(jq -r '.public_key' "$config_file" 2>/dev/null)
    user_short_id=$(jq -r '.short_id // ""' "$config_file" 2>/dev/null)
    
    # Use current server IP
    local current_server_ip
    current_server_ip=$(curl -s https://api.ipify.org)
    
    # Generate connection link
    local connection_link=""
    
    if [ "$USE_REALITY" = true ]; then
        # Validate Reality parameters
        if [ -z "$user_public_key" ] || [ "$user_public_key" = "null" ] || [ "$user_public_key" = "unknown" ]; then
            warning "Public key Reality unavailable. Using current key..."
            user_public_key="$PUBLIC_KEY"
        fi
        
        if [ -z "$user_short_id" ] || [ "$user_short_id" = "null" ]; then
            warning "Short ID Reality unavailable. Using current ID."
            user_short_id="$SHORT_ID"
        fi
        
        # Create Reality link with XTLS Vision support
        connection_link="vless://$user_uuid@$current_server_ip:$user_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$user_sni&fp=chrome&pbk=$user_public_key&sid=$user_short_id&type=tcp&headerType=none#$user_name"
        
        debug "Created Reality connection link"
    else
        # Create standard VLESS link
        connection_link="vless://$user_uuid@$current_server_ip:$user_port?encryption=none&security=none&type=tcp#$user_name"
        debug "Created standard VLESS connection link"
    fi
    
    # Save connection link
    local link_file="$USERS_DIR/$user_name.link"
    echo "$connection_link" > "$link_file"
    debug "Connection link saved to: $link_file"
    
    echo "$connection_link"
}

# Generate or update QR code
ensure_qr_code() {
    local user_name="$1"
    local connection_link="$2"
    
    debug "Ensuring QR code exists: $user_name"
    
    local qr_file="$USERS_DIR/$user_name.png"
    
    # Generate QR code image
    if qrencode -t PNG -o "$qr_file" "$connection_link" 2>/dev/null; then
        debug "QR code image generated: $qr_file"
    else
        warning "Failed to generate QR code image"
    fi
}

# Display user information header
display_user_header() {
    local user_name="$1"
    
    echo ""
    echo -e "${GREEN}=== User Information: $user_name ===${NC}"
    echo ""
}

# Display user configuration details
display_user_details() {
    local user_name="$1"
    
    debug "Displaying user details: $user_name"
    
    local config_file="$USERS_DIR/$user_name.json"
    
    # Read user configuration
    local user_uuid user_port user_server user_sni user_protocol
    
    user_uuid=$(jq -r '.uuid' "$config_file" 2>/dev/null || echo "Unknown")
    user_port=$(jq -r '.port' "$config_file" 2>/dev/null || echo "Unknown")
    user_server=$(jq -r '.server' "$config_file" 2>/dev/null || echo "Unknown")
    user_sni=$(jq -r '.sni' "$config_file" 2>/dev/null || echo "Unknown")
    user_protocol=$(jq -r '.protocol' "$config_file" 2>/dev/null || echo "Unknown")
    
    # Display details
    echo -e "  ${GREEN}👤 User Name:${NC} ${YELLOW}$user_name${NC}"
    echo -e "  ${GREEN}🆔 UUID:${NC} ${WHITE}$user_uuid${NC}"
    echo -e "  ${GREEN}🌐 Server IP:${NC} ${YELLOW}$user_server${NC}"
    echo -e "  ${GREEN}🔌 Port:${NC} ${YELLOW}$user_port${NC}"
    echo -e "  ${GREEN}🔒 Protocol:${NC} ${YELLOW}$user_protocol${NC}"
    echo -e "  ${GREEN}🌐 SNI:${NC} ${YELLOW}$user_sni${NC}"
    
    # Display Reality-specific information
    if [ "$USE_REALITY" = true ]; then
        local user_short_id
        user_short_id=$(jq -r '.short_id // "Not set"' "$config_file" 2>/dev/null)
        echo -e "  ${GREEN}🔐 Reality:${NC} ${GREEN}✓ Enabled${NC}"
        echo -e "  ${GREEN}🔑 Short ID:${NC} ${YELLOW}$user_short_id${NC}"
    else
        echo -e "  ${GREEN}🔐 Reality:${NC} ${RED}✗ Disabled${NC}"
    fi
    
    echo ""
}

# Display file status
display_file_status() {
    local user_name="$1"
    
    debug "Displaying file status: $user_name"
    
    echo -e "  ${GREEN}📁 File Status:${NC}"
    
    # Check configuration file
    if [ -f "$USERS_DIR/$user_name.json" ]; then
        echo -e "    ${GREEN}✅ Configuration:${NC} $USERS_DIR/$user_name.json"
    else
        echo -e "    ${RED}❌ Configuration:${NC} Missing"
    fi
    
    # Check connection link file
    if [ -f "$USERS_DIR/$user_name.link" ]; then
        echo -e "    ${GREEN}✅ Connection Link:${NC} $USERS_DIR/$user_name.link"
    else
        echo -e "    ${RED}❌ Connection Link:${NC} Missing"
    fi
    
    # Check QR code file
    if [ -f "$USERS_DIR/$user_name.png" ]; then
        echo -e "    ${GREEN}✅ QR Code Image:${NC} $USERS_DIR/$user_name.png"
    else
        echo -e "    ${RED}❌ QR Code Image:${NC} Missing"
    fi
    
    echo ""
}

# Display connection link
display_connection_link() {
    local connection_link="$1"
    
    debug "Displaying connection link"
    
    echo -e "  ${GREEN}🔗 Connection Link:${NC}"
    echo ""
    echo "$connection_link"
    echo ""
}

# Display QR code in terminal
display_qr_code() {
    local connection_link="$1"
    
    debug "Displaying QR code in terminal"
    
    echo -e "  ${GREEN}📱 QR Code:${NC}"
    echo ""
    
    if qrencode -t ANSIUTF8 "$connection_link" 2>/dev/null; then
        debug "QR code displayed successfully"
    else
        warning "Failed to display QR code in terminal"
        echo -e "    ${RED}❌ Unable to display QR code${NC}"
    fi
    
    echo ""
}

# Show client information (if available)
show_client_info() {
    debug "Showing client information"
    
    echo -e "${GREEN}=== Client Setup Information ===${NC}"
    echo ""
    echo -e "  ${GREEN}📱 Client Configuration:${NC}"
    echo -e "    1. Copy the connection link above"
    echo -e "    2. Import it into your VPN client (v2rayN, v2rayA, etc.)"
    echo -e "    3. Or scan the QR code with your mobile client"
    echo ""
    echo -e "  ${GREEN}🔧 Recommended Clients:${NC}"
    echo -e "    • ${YELLOW}Windows/Linux:${NC} v2rayN, v2rayA"
    echo -e "    • ${YELLOW}Android:${NC} v2rayNG"
    echo -e "    • ${YELLOW}iOS:${NC} Shadowrocket, Quantumult X"
    echo -e "    • ${YELLOW}macOS:${NC} V2rayU, ClashX"
    echo ""
    echo -e "  ${GREEN}⚠️  Important Notes:${NC}"
    echo -e "    • Keep your connection details secure"
    echo -e "    • Don't share your personal connection link"
    echo -e "    • Contact admin if connection fails"
    echo ""
}

# Main function to show user information
show_user() {
    log "Displaying user information..."
    
    # Initialize module
    init_user_show
    
    # Get server configuration
    get_server_info
    
    # Source and show user list for selection
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
    
    # Get user name to show
    local user_name=""
    read -p "Enter user name to display information: " user_name
    
    # Validate user exists
    validate_user_exists "$user_name"
    
    # Ensure user configuration is up to date
    ensure_user_config "$user_name"
    
    # Generate/update connection link
    local connection_link
    connection_link=$(ensure_connection_link "$user_name")
    
    # Generate/update QR code
    ensure_qr_code "$user_name" "$connection_link"
    
    # Display user information
    display_user_header "$user_name"
    display_user_details "$user_name"
    display_file_status "$user_name"
    display_connection_link "$connection_link"
    display_qr_code "$connection_link"
    show_client_info
    
    log "User information display completed for: $user_name"
}

# Show user by name (for scripting)
show_user_by_name() {
    local user_name="$1"
    
    if [ -z "$user_name" ]; then
        error "User name required for show_user_by_name function"
    fi
    
    debug "Showing user by name: $user_name"
    
    # Initialize module
    init_user_show
    
    # Get server configuration
    get_server_info
    
    # Validate user exists
    validate_user_exists "$user_name"
    
    # Ensure user configuration is up to date
    ensure_user_config "$user_name"
    
    # Generate/update connection link
    local connection_link
    connection_link=$(ensure_connection_link "$user_name")
    
    # Generate/update QR code
    ensure_qr_code "$user_name" "$connection_link"
    
    # Display user information
    display_user_header "$user_name"
    display_user_details "$user_name"
    display_file_status "$user_name"
    display_connection_link "$connection_link"
    display_qr_code "$connection_link"
    show_client_info
}

# Show all users (summary)
show_all_users() {
    log "Displaying all users information..."
    
    # Initialize module
    init_user_show
    
    # Get server configuration
    get_server_info
    
    # Get all user names
    local user_names
    mapfile -t user_names < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE" 2>/dev/null)
    
    if [ ${#user_names[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No users found${NC}"
        return 0
    fi
    
    # Show each user
    for user_name in "${user_names[@]}"; do
        show_user_by_name "$user_name"
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
    done
    
    log "All users information displayed"
}

# Export functions for use by other modules
export -f init_user_show
export -f validate_user_exists
export -f ensure_user_config
export -f ensure_connection_link
export -f ensure_qr_code
export -f display_user_header
export -f display_user_details
export -f display_file_status
export -f display_connection_link
export -f display_qr_code
export -f show_client_info
export -f show_user
export -f show_user_by_name
export -f show_all_users