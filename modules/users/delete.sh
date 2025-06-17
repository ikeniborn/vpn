#!/bin/bash
#
# User Deletion Module
# Handles removing users from the VPN server
# Extracted from manage_users.sh as part of Phase 3 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_user_delete() {
    debug "Initializing user deletion module"
    
    # Verify jq is available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    debug "User deletion module initialized successfully"
}

# Validate that user exists
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

# Remove user from server configuration
remove_user_from_config() {
    local user_name="$1"
    
    debug "Removing user from server configuration: $user_name"
    
    # Remove user from clients array
    if jq "del(.inbounds[0].settings.clients[] | select(.email == \"$user_name\"))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        debug "User removed from configuration successfully"
    else
        rm -f "$CONFIG_FILE.tmp"
        error "Failed to remove user from configuration"
    fi
}

# Clean up user files
cleanup_user_files() {
    local user_name="$1"
    
    debug "Cleaning up user files: $user_name"
    
    local files_removed=0
    
    # Remove user configuration file
    if [ -f "$USERS_DIR/$user_name.json" ]; then
        rm -f "$USERS_DIR/$user_name.json"
        files_removed=$((files_removed + 1))
        debug "Removed user config: $user_name.json"
    fi
    
    # Remove connection link file
    if [ -f "$USERS_DIR/$user_name.link" ]; then
        rm -f "$USERS_DIR/$user_name.link"
        files_removed=$((files_removed + 1))
        debug "Removed connection link: $user_name.link"
    fi
    
    # Remove QR code file
    if [ -f "$USERS_DIR/$user_name.png" ]; then
        rm -f "$USERS_DIR/$user_name.png"
        files_removed=$((files_removed + 1))
        debug "Removed QR code: $user_name.png"
    fi
    
    if [ $files_removed -gt 0 ]; then
        debug "Cleaned up $files_removed user files"
    else
        warning "No user files found to clean up"
    fi
}

# Get user UUID before deletion (for logging purposes)
get_user_uuid() {
    local user_name="$1"
    
    debug "Getting UUID for user: $user_name"
    
    local user_uuid
    user_uuid=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$user_name\") | .id" "$CONFIG_FILE" 2>/dev/null)
    
    if [ -n "$user_uuid" ] && [ "$user_uuid" != "null" ]; then
        debug "Found UUID for user $user_name: $user_uuid"
        echo "$user_uuid"
    else
        debug "No UUID found for user: $user_name"
        echo ""
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

# Display confirmation prompt
confirm_user_deletion() {
    local user_name="$1"
    local user_uuid="$2"
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}    ⚠️  ${RED}WARNING: USER DELETION${NC}           ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}❗ This operation will permanently delete:${NC}"
    echo -e "    ${YELLOW}•${NC} User: ${YELLOW}$user_name${NC}"
    if [ -n "$user_uuid" ]; then
        echo -e "    ${YELLOW}•${NC} UUID: ${YELLOW}$user_uuid${NC}"
    fi
    echo -e "    ${YELLOW}•${NC} All user configuration files"
    echo -e "    ${YELLOW}•${NC} Connection links and QR codes"
    echo ""
    echo -e "${RED}⚠️  This action cannot be undone!${NC}"
    echo ""
    
    local confirmation
    read -p "$(echo -e ${YELLOW}Are you sure you want to delete this user? [yes/no]:${NC} )" confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "User deletion cancelled"
        return 1
    fi
    
    return 0
}

# Main function to delete a user
delete_user() {
    log "Deleting user from VPN server..."
    
    # Initialize module
    init_user_delete
    
    # Source the list module to show users
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
    
    # Get user name to delete
    local user_name=""
    read -p "Enter user name to delete: " user_name
    
    # Validate user exists
    validate_user_exists "$user_name"
    
    # Get user UUID for confirmation
    local user_uuid
    user_uuid=$(get_user_uuid "$user_name")
    
    # Confirm deletion
    if ! confirm_user_deletion "$user_name" "$user_uuid"; then
        return 0
    fi
    
    # Perform deletion
    log "Removing user '$user_name'..."
    
    # Remove from configuration
    remove_user_from_config "$user_name"
    
    # Clean up files
    cleanup_user_files "$user_name"
    
    # Restart server
    restart_vpn_server
    
    # Display success message
    echo ""
    log "User '$user_name' successfully deleted!"
    if [ -n "$user_uuid" ]; then
        log "Deleted UUID: $user_uuid"
    fi
    log "All associated files have been removed"
    
    # Show updated user count
    local remaining_users
    remaining_users=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    log "Remaining users: $remaining_users"
}

# Batch delete multiple users (advanced function)
batch_delete_users() {
    log "Batch user deletion mode..."
    
    # Initialize module
    init_user_delete
    
    # Show current users
    if [ -f "$PROJECT_DIR/modules/users/list.sh" ]; then
        source "$PROJECT_DIR/modules/users/list.sh"
        list_users
    fi
    
    echo ""
    echo "Enter user names to delete (separated by spaces):"
    read -p "Users: " -a user_names
    
    if [ ${#user_names[@]} -eq 0 ]; then
        warning "No users specified"
        return 0
    fi
    
    # Validate all users exist
    for user_name in "${user_names[@]}"; do
        if ! jq -e ".inbounds[0].settings.clients[] | select(.email == \"$user_name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
            error "User '$user_name' not found"
        fi
    done
    
    # Show deletion summary
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}    ⚠️  ${RED}BATCH USER DELETION${NC}              ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}❗ This will delete ${#user_names[@]} users:${NC}"
    for user_name in "${user_names[@]}"; do
        echo -e "    ${YELLOW}•${NC} $user_name"
    done
    echo ""
    
    local confirmation
    read -p "$(echo -e ${YELLOW}Confirm batch deletion? [yes/no]:${NC} )" confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Batch deletion cancelled"
        return 0
    fi
    
    # Delete each user
    for user_name in "${user_names[@]}"; do
        log "Deleting user: $user_name"
        remove_user_from_config "$user_name"
        cleanup_user_files "$user_name"
    done
    
    # Single restart after all deletions
    restart_vpn_server
    
    log "Batch deletion completed. Deleted ${#user_names[@]} users"
}

# Export functions for use by other modules
export -f init_user_delete
export -f validate_user_exists
export -f remove_user_from_config
export -f cleanup_user_files
export -f get_user_uuid
export -f restart_vpn_server
export -f confirm_user_deletion
export -f delete_user
export -f batch_delete_users