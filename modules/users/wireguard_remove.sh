#!/bin/bash
#################################################
# WireGuard User Removal Module
# 
# This module handles removing users from the
# WireGuard VPN server
#
# Exported Functions:
#   - remove_wireguard_user
#   - cleanup_wireguard_user_config
#################################################

set -euo pipefail

# Source required libraries
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/ui.sh"

# WireGuard constants
readonly WIREGUARD_DIR="/opt/wireguard"
readonly WIREGUARD_CONFIG_DIR="${WIREGUARD_DIR}/config"
readonly WIREGUARD_USERS_DIR="${WIREGUARD_DIR}/users"

remove_user_from_server_config() {
    local username="${1}"
    local server_config="${WIREGUARD_CONFIG_DIR}/wg0.conf"
    local temp_config="${server_config}.tmp"
    
    if [[ ! -f "${server_config}" ]]; then
        log_error "Server configuration not found"
        return 1
    fi
    
    # Create a temporary file without the user's peer section
    local in_peer_section=false
    local is_target_peer=false
    
    > "${temp_config}"
    
    while IFS= read -r line; do
        # Check if we're entering a peer section
        if [[ "${line}" =~ ^[[:space:]]*\[Peer\][[:space:]]*$ ]]; then
            in_peer_section=true
            is_target_peer=false
            # Store the peer header temporarily
            peer_header="${line}"
            continue
        fi
        
        # Check if this is the target user's peer section
        if [[ "${in_peer_section}" == true ]] && [[ "${line}" =~ ^#[[:space:]]*Client:[[:space:]]*${username}[[:space:]]*$ ]]; then
            is_target_peer=true
            continue
        fi
        
        # If we're in a peer section, check for the next section or peer
        if [[ "${in_peer_section}" == true ]]; then
            if [[ "${line}" =~ ^[[:space:]]*\[.*\][[:space:]]*$ ]] || [[ "${line}" =~ ^#[[:space:]]*Client: ]]; then
                # We've reached a new section or peer
                if [[ "${is_target_peer}" == false ]]; then
                    # Write the previous peer section if it wasn't the target
                    echo "${peer_header}" >> "${temp_config}"
                fi
                in_peer_section=false
                is_target_peer=false
                
                # Process the new section/comment normally
                if [[ ! "${line}" =~ ^#[[:space:]]*Client: ]]; then
                    echo "${line}" >> "${temp_config}"
                fi
            elif [[ "${is_target_peer}" == false ]]; then
                # Write non-target peer content
                echo "${line}" >> "${temp_config}"
            fi
        else
            # Write non-peer section content
            echo "${line}" >> "${temp_config}"
        fi
    done < "${server_config}"
    
    # Handle the last peer section if needed
    if [[ "${in_peer_section}" == true ]] && [[ "${is_target_peer}" == false ]]; then
        echo "${peer_header}" >> "${temp_config}"
    fi
    
    # Replace the original configuration
    mv "${temp_config}" "${server_config}"
    
    log_info "Removed ${username} from server configuration"
}

cleanup_wireguard_user_config() {
    local username="${1}"
    local user_dir="${WIREGUARD_USERS_DIR}/${username}"
    
    if [[ -d "${user_dir}" ]]; then
        log_info "Removing user configuration directory..."
        rm -rf "${user_dir}"
        log_success "User configuration removed"
    else
        log_warning "User configuration directory not found"
    fi
}

reload_wireguard_config() {
    log_info "Reloading WireGuard configuration..."
    
    # Copy updated config to container
    docker cp "${WIREGUARD_CONFIG_DIR}/wg0.conf" wireguard:/config/wg0.conf
    
    # Reload configuration
    docker exec wireguard wg syncconf wg0 <(wg-quick strip wg0)
    
    log_success "WireGuard configuration reloaded"
}

remove_wireguard_user() {
    local username="${1:-}"
    
    # Validate input
    if [[ -z "${username}" ]]; then
        log_error "Username is required"
        echo "Usage: remove_wireguard_user <username>"
        return 1
    fi
    
    # Check if user exists
    if [[ ! -d "${WIREGUARD_USERS_DIR}/${username}" ]]; then
        log_error "User ${username} not found"
        return 1
    fi
    
    log_header "Removing WireGuard User: ${username}"
    
    # Confirm removal
    if ! confirm_action "Are you sure you want to remove user ${username}?"; then
        log_info "Operation cancelled"
        return 0
    fi
    
    # Get user's public key before removal (for logging)
    local user_public_key=""
    if [[ -f "${WIREGUARD_USERS_DIR}/${username}/public_key" ]]; then
        user_public_key=$(cat "${WIREGUARD_USERS_DIR}/${username}/public_key")
    fi
    
    # Remove user from server configuration
    remove_user_from_server_config "${username}"
    
    # Cleanup user configuration
    cleanup_wireguard_user_config "${username}"
    
    # Reload server configuration
    reload_wireguard_config
    
    # Verify removal
    if docker exec wireguard wg show wg0 2>/dev/null | grep -q "${user_public_key}"; then
        log_warning "User may still be connected. Connection will terminate on next handshake."
    fi
    
    log_success "User ${username} removed successfully"
}

# Export functions
export -f remove_wireguard_user
export -f cleanup_wireguard_user_config

# Support direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        remove)
            shift
            remove_wireguard_user "$@"
            ;;
        *)
            echo "Usage: $0 remove <username>"
            exit 1
            ;;
    esac
fi