#!/bin/bash
#################################################
# WireGuard User List Module
# 
# This module handles listing all WireGuard users
# with their connection status and details
#
# Exported Functions:
#   - list_wireguard_users
#   - get_wireguard_user_status
#################################################

set -euo pipefail

# Source required libraries
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/ui.sh"

# WireGuard constants
readonly WIREGUARD_DIR="/opt/wireguard"
readonly WIREGUARD_USERS_DIR="${WIREGUARD_DIR}/users"

get_wireguard_user_status() {
    local username="${1}"
    local user_dir="${WIREGUARD_USERS_DIR}/${username}"
    
    if [[ ! -f "${user_dir}/public_key" ]]; then
        echo "Unknown"
        return
    fi
    
    local public_key=$(cat "${user_dir}/public_key")
    
    # Check if user is connected
    if docker exec wireguard wg show wg0 2>/dev/null | grep -q "${public_key}"; then
        # Get connection details
        local peer_info=$(docker exec wireguard wg show wg0 2>/dev/null | grep -A 5 "${public_key}")
        
        # Extract last handshake time
        if echo "${peer_info}" | grep -q "latest handshake:"; then
            local handshake=$(echo "${peer_info}" | grep "latest handshake:" | sed 's/.*latest handshake: //')
            
            # Check if handshake is recent (within last 3 minutes)
            if [[ "${handshake}" =~ "second" ]] || [[ "${handshake}" =~ "1 minute" ]] || [[ "${handshake}" =~ "2 minutes" ]]; then
                echo "Connected"
            else
                echo "Idle"
            fi
        else
            echo "Disconnected"
        fi
    else
        echo "Disconnected"
    fi
}

get_wireguard_user_transfer() {
    local username="${1}"
    local user_dir="${WIREGUARD_USERS_DIR}/${username}"
    
    if [[ ! -f "${user_dir}/public_key" ]]; then
        echo "0 B / 0 B"
        return
    fi
    
    local public_key=$(cat "${user_dir}/public_key")
    
    # Get transfer data from wg show
    local peer_info=$(docker exec wireguard wg show wg0 2>/dev/null | grep -A 5 "${public_key}" || true)
    
    if [[ -n "${peer_info}" ]]; then
        local transfer_line=$(echo "${peer_info}" | grep "transfer:" || true)
        if [[ -n "${transfer_line}" ]]; then
            # Extract received and sent bytes
            local received=$(echo "${transfer_line}" | awk '{print $2}')
            local sent=$(echo "${transfer_line}" | awk '{print $4}')
            echo "${received} / ${sent}"
        else
            echo "0 B / 0 B"
        fi
    else
        echo "0 B / 0 B"
    fi
}

list_wireguard_users() {
    log_header "WireGuard Users"
    
    if [[ ! -d "${WIREGUARD_USERS_DIR}" ]]; then
        log_warning "No WireGuard users directory found"
        return
    fi
    
    # Check if any users exist
    local user_count=$(find "${WIREGUARD_USERS_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l)
    
    if [[ ${user_count} -eq 0 ]]; then
        log_info "No users found"
        return
    fi
    
    # Display table header
    printf "%-20s %-20s %-15s %-30s %-10s\n" "Username" "IP Address" "Status" "Transfer (RX/TX)" "Created"
    printf "%-20s %-20s %-15s %-30s %-10s\n" "$(printf '%.0s-' {1..20})" "$(printf '%.0s-' {1..20})" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..10})"
    
    # List each user
    for user_dir in "${WIREGUARD_USERS_DIR}"/*; do
        if [[ -d "${user_dir}" ]]; then
            local username=$(basename "${user_dir}")
            local ip_file="${user_dir}/ip_address"
            local info_file="${user_dir}/info.json"
            
            # Get IP address
            local ip_address="Unknown"
            if [[ -f "${ip_file}" ]]; then
                ip_address=$(cat "${ip_file}")
            fi
            
            # Get status
            local status=$(get_wireguard_user_status "${username}")
            
            # Get transfer data
            local transfer=$(get_wireguard_user_transfer "${username}")
            
            # Get creation date
            local created="Unknown"
            if [[ -f "${info_file}" ]] && command_exists jq; then
                created=$(jq -r '.created // "Unknown"' "${info_file}" | cut -d'T' -f1)
            elif [[ -f "${info_file}" ]]; then
                created=$(grep -o '"created"[[:space:]]*:[[:space:]]*"[^"]*"' "${info_file}" | cut -d'"' -f4 | cut -d'T' -f1)
            fi
            
            # Color code status
            case "${status}" in
                "Connected")
                    status="${COLOR_GREEN}${status}${COLOR_RESET}"
                    ;;
                "Idle")
                    status="${COLOR_YELLOW}${status}${COLOR_RESET}"
                    ;;
                "Disconnected")
                    status="${COLOR_RED}${status}${COLOR_RESET}"
                    ;;
            esac
            
            printf "%-20s %-20s %-25s %-30s %-10s\n" "${username}" "${ip_address}" "${status}" "${transfer}" "${created}"
        fi
    done
    
    echo ""
    log_info "Total users: ${user_count}"
}

# Export functions
export -f list_wireguard_users
export -f get_wireguard_user_status

# Support direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    list_wireguard_users
fi