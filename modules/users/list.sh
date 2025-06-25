#!/bin/bash
#
# User List Module
# Handles displaying users from the VPN server
# Extracted from manage_users.sh as part of Phase 3 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_user_list() {
    debug "Initializing user list module"
    
    # Verify jq is available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    debug "User list module initialized successfully"
}

# Get user count
get_user_count() {
    debug "Getting user count"
    
    local count
    count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    
    # Ensure count is a valid integer
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        count="0"
    fi
    
    debug "User count: $count"
    echo "$count"
}

# Get all user names
get_user_names() {
    debug "Getting all user names"
    
    jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE" 2>/dev/null || {
        debug "No users found or error reading config"
        return 1
    }
}

# Get user information by name
get_user_info() {
    local user_name="$1"
    
    debug "Getting user info for: $user_name"
    
    if [ -z "$user_name" ]; then
        debug "Empty user name provided"
        return 1
    fi
    
    # Get user UUID and flow
    local user_data
    user_data=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | {id, flow}" "$CONFIG_FILE" 2>/dev/null)
    
    if [ -z "$user_data" ] || [ "$user_data" = "null" ]; then
        debug "No data found for user: $user_name"
        return 1
    fi
    
    echo "$user_data"
}

# Format user table header
format_table_header() {
    echo -e "${GREEN}=== User List ===${NC}"
    echo ""
    echo -e "${BLUE}$(printf '%-3s' '#') | $(printf '%-25s' 'User Name') | $(printf '%-36s' 'UUID')${NC}"
    echo -e "${BLUE}$(printf '%3s' '' | tr ' ' '-') | $(printf '%25s' '' | tr ' ' '-') | $(printf '%36s' '' | tr ' ' '-')${NC}"
}

# Format user table footer
format_table_footer() {
    echo ""
}

# Format user row
format_user_row() {
    local user_name="$1"
    local user_uuid="$2"
    
    # Truncate name if too long
    if [ ${#user_name} -gt 25 ]; then
        user_name="${user_name:0:22}..."
    fi
    
    echo -e "${YELLOW}$(printf '%-25s' "$user_name")${NC} | ${WHITE}$user_uuid${NC}"
}

# List users in table format
list_users() {
    debug "Listing users in table format"
    
    # Initialize module
    init_user_list
    
    log "User List:"
    echo ""
    
    # Get user count
    local user_count
    user_count=$(get_user_count)
    
    if [ "$user_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No users found${NC}"
        echo ""
        return 0
    fi
    
    # Display table header
    format_table_header
    
    # Get and display each user with numbering
    local counter=1
    jq -r '.inbounds[0].settings.clients[] | (.email // "No Name") + " | " + .id' "$CONFIG_FILE" 2>/dev/null | while IFS=' | ' read -r user_name user_uuid; do
        printf "${BLUE}%-3s | %-25s | %-36s${NC}\n" "$counter" "$user_name" "$user_uuid"
        counter=$((counter + 1))
    done
    
    # Display table footer
    format_table_footer
    
    # Display summary
    echo ""
    echo -e "  ${GREEN}📊 Total Users: ${YELLOW}$user_count${NC}"
    echo ""
}

# List users in simple format
list_users_simple() {
    debug "Listing users in simple format"
    
    # Initialize module
    init_user_list
    
    local user_count
    user_count=$(get_user_count)
    
    if [ "$user_count" -eq 0 ]; then
        echo "No users found"
        return 0
    fi
    
    echo "Users ($user_count):"
    get_user_names | while read -r user_name; do
        echo "  • $user_name"
    done
}

# List users with detailed information
list_users_detailed() {
    debug "Listing users with detailed information"
    
    # Initialize module
    init_user_list
    
    # Get server info for detailed display
    get_server_info
    
    log "Detailed User List:"
    echo ""
    
    local user_count
    user_count=$(get_user_count)
    
    if [ "$user_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No users found${NC}"
        echo ""
        return 0
    fi
    
    # Display each user with details
    local counter=1
    get_user_names | while read -r user_name; do
        echo -e "${GREEN}=== User #$counter: $user_name ===${NC}"
        
        # Get user UUID
        local user_uuid
        user_uuid=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | .id" "$CONFIG_FILE" 2>/dev/null)
        
        echo -e "   ${YELLOW}UUID:${NC} $user_uuid"
        echo -e "   ${YELLOW}Server:${NC} $SERVER_IP:$SERVER_PORT"
        echo -e "   ${YELLOW}Protocol:${NC} $PROTOCOL"
        echo -e "   ${YELLOW}SNI:${NC} $SERVER_SNI"
        
        # Check if user files exist
        if [ -f "$USERS_DIR/$user_name.json" ]; then
            echo -e "   ${YELLOW}Config File:${NC} ✅ Available"
        else
            echo -e "   ${YELLOW}Config File:${NC} ❌ Missing"
        fi
        
        if [ -f "$USERS_DIR/$user_name.link" ]; then
            echo -e "   ${YELLOW}Connection Link:${NC} ✅ Available"
        else
            echo -e "   ${YELLOW}Connection Link:${NC} ❌ Missing"
        fi
        
        if [ -f "$USERS_DIR/$user_name.png" ]; then
            echo -e "   ${YELLOW}QR Code:${NC} ✅ Available"
        else
            echo -e "   ${YELLOW}QR Code:${NC} ❌ Missing"
        fi
        
        echo ""
        
        counter=$((counter + 1))
    done
    
    echo -e "  ${GREEN}📊 Total Users: ${YELLOW}$user_count${NC}"
    echo ""
}

# List users with filtering
list_users_filtered() {
    local filter="$1"
    
    debug "Listing users with filter: $filter"
    
    # Initialize module
    init_user_list
    
    if [ -z "$filter" ]; then
        list_users
        return
    fi
    
    log "Filtered User List (filter: '$filter'):"
    echo ""
    
    # Filter users by name pattern
    local filtered_users
    filtered_users=$(get_user_names | grep -i "$filter" 2>/dev/null || true)
    
    if [ -z "$filtered_users" ]; then
        echo -e "${YELLOW}⚠️  No users match filter '$filter'${NC}"
        echo ""
        return 0
    fi
    
    # Display filtered results
    format_table_header
    
    echo "$filtered_users" | while read -r user_name; do
        local user_uuid
        user_uuid=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | .id" "$CONFIG_FILE" 2>/dev/null)
        format_user_row "$user_name" "$user_uuid"
    done
    
    format_table_footer
    
    local filtered_count
    filtered_count=$(echo "$filtered_users" | wc -l)
    echo ""
    echo -e "  ${GREEN}📊 Filtered Users: ${YELLOW}$filtered_count${NC}"
    echo ""
}

# Export user list to JSON
export_user_list() {
    local output_file="$1"
    
    debug "Exporting user list to: $output_file"
    
    # Initialize module
    init_user_list
    
    if [ -z "$output_file" ]; then
        output_file="$WORK_DIR/users_export_$(date +%Y%m%d_%H%M%S).json"
    fi
    
    # Get server info
    get_server_info
    
    # Create export structure
    local export_data
    export_data=$(jq -n \
        --arg server_ip "$SERVER_IP" \
        --arg server_port "$SERVER_PORT" \
        --arg protocol "$PROTOCOL" \
        --arg sni "$SERVER_SNI" \
        --arg export_date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            export_info: {
                date: $export_date,
                server: {
                    ip: $server_ip,
                    port: ($server_port | tonumber),
                    protocol: $protocol,
                    sni: $sni
                }
            },
            users: []
        }')
    
    # Add each user to export
    get_user_names | while read -r user_name; do
        local user_uuid
        user_uuid=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | .id" "$CONFIG_FILE" 2>/dev/null)
        
        export_data=$(echo "$export_data" | jq \
            --arg name "$user_name" \
            --arg uuid "$user_uuid" \
            '.users += [{name: $name, uuid: $uuid}]')
    done
    
    # Write to file
    echo "$export_data" > "$output_file"
    
    if [ $? -eq 0 ]; then
        log "User list exported to: $output_file"
    else
        error "Failed to export user list"
    fi
}

# Interactive user selection menu
select_user_interactive() {
    debug "Starting interactive user selection"
    
    # Initialize module
    init_user_list
    
    local user_count
    user_count=$(get_user_count)
    
    if [ "$user_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No users available for selection${NC}"
        return 1
    fi
    
    echo "Select a user:"
    echo ""
    
    local counter=1
    local user_array=()
    
    get_user_names | while read -r user_name; do
        echo "  $counter) $user_name"
        user_array+=("$user_name")
        counter=$((counter + 1))
    done
    
    echo ""
    read -p "Enter user number (1-$user_count): " selection
    
    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$user_count" ]; then
        error "Invalid selection: $selection"
    fi
    
    # Return selected user name
    local selected_user="${user_array[$((selection - 1))]}"
    echo "$selected_user"
}

# Get user name by number
get_user_by_number() {
    local number="$1"
    
    debug "Getting user by number: $number"
    
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        debug "Invalid number format: $number"
        return 1
    fi
    
    local user_count
    user_count=$(get_user_count)
    
    if [ "$number" -lt 1 ] || [ "$number" -gt "$user_count" ]; then
        debug "Number out of range: $number (max: $user_count)"
        return 1
    fi
    
    # Get user name by index (jq arrays are 0-based)
    local user_name
    user_name=$(jq -r ".inbounds[0].settings.clients[$((number - 1))].email" "$CONFIG_FILE" 2>/dev/null)
    
    if [ "$user_name" = "null" ] || [ -z "$user_name" ]; then
        debug "User not found at position: $number"
        return 1
    fi
    
    echo "$user_name"
}

# Export functions for use by other modules
export -f init_user_list
export -f get_user_count
export -f get_user_names
export -f get_user_info
export -f format_table_header
export -f format_table_footer
export -f format_user_row
export -f list_users
export -f list_users_simple
export -f list_users_detailed
export -f list_users_filtered
export -f export_user_list
export -f select_user_interactive
export -f get_user_by_number