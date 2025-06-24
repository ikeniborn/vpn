#!/bin/bash
#################################################
# WireGuard User Management Menu
# 
# This module provides a menu interface for
# managing WireGuard users
#
# Exported Functions:
#   - show_wireguard_user_menu
#################################################

set -euo pipefail

# Source required libraries
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/ui.sh"

# WireGuard constants
readonly WIREGUARD_DIR="/opt/wireguard"

show_wireguard_user_menu() {
    # Check if WireGuard is installed
    if [[ ! -d "${WIREGUARD_DIR}" ]] || ! docker ps | grep -q wireguard; then
        log_error "WireGuard server is not installed or not running"
        echo "Please install WireGuard server first using the main installation menu."
        return 1
    fi
    
    while true; do
        display_banner "WireGuard User Management"
        echo "1) Add new user"
        echo "2) List all users"
        echo "3) Remove user"
        echo "4) Show user QR code"
        echo "5) Show user configuration"
        echo "6) Back to main menu"
        echo ""
        
        read -p "Select option (1-6): " choice
        
        case $choice in
            1)
                echo ""
                read -p "Enter username for new user: " username
                if [[ -n "$username" ]] && [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo ""
                    log_info "Adding WireGuard user: $username"
                    source "$(dirname "$0")/wireguard_add.sh"
                    add_wireguard_user "$username"
                else
                    log_error "Invalid username. Use only alphanumeric characters, underscore, and hyphen."
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                echo ""
                source "$(dirname "$0")/wireguard_list.sh"
                list_wireguard_users
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                read -p "Enter username to remove: " username
                if [[ -n "$username" ]]; then
                    source "$(dirname "$0")/wireguard_remove.sh"
                    remove_wireguard_user "$username"
                else
                    log_error "Username cannot be empty"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                read -p "Enter username to show QR code: " username
                if [[ -n "$username" ]]; then
                    local qr_file="${WIREGUARD_DIR}/users/${username}/qr_code.txt"
                    if [[ -f "$qr_file" ]]; then
                        echo ""
                        echo "QR Code for $username:"
                        cat "$qr_file"
                    else
                        log_error "QR code not found for user: $username"
                    fi
                else
                    log_error "Username cannot be empty"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                echo ""
                read -p "Enter username to show configuration: " username
                if [[ -n "$username" ]]; then
                    local config_file="${WIREGUARD_DIR}/users/${username}/client.conf"
                    if [[ -f "$config_file" ]]; then
                        echo ""
                        echo "Configuration for $username:"
                        echo "=========================="
                        cat "$config_file"
                    else
                        log_error "Configuration not found for user: $username"
                    fi
                else
                    log_error "Username cannot be empty"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                return 0
                ;;
            *)
                log_warning "Please choose a valid option (1-6)"
                sleep 1
                ;;
        esac
    done
}

# Export functions
export -f show_wireguard_user_menu

# Support direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_wireguard_user_menu
fi