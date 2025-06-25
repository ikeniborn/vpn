#!/bin/bash

# =============================================================================
# User Management Menu Module
# 
# This module handles user management menu display and operations.
# Extracted from vpn.sh for modular architecture.
#
# Functions exported:
# - show_user_management_menu()
#
# Dependencies: lib/common.sh, modules/users/*
# =============================================================================

# Source required libraries if not already sourced
if [ -z "$COMMON_SOURCED" ]; then
    MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    COMMON_PATH="${PROJECT_ROOT:-$MODULE_DIR/../..}/lib/common.sh"
    source "$COMMON_PATH" 2>/dev/null || {
        echo "Error: Cannot source lib/common.sh from $COMMON_PATH"
        return 1 2>/dev/null || exit 1
    }
fi

# =============================================================================
# USER MANAGEMENT MENU
# =============================================================================

show_user_management_menu() {
    while true; do
        clear
        echo -e "${GREEN}=== User Management ===${NC}"
        echo ""
        echo "1) 📋 List Users"
        echo "2) ➕ Add User"
        echo "3) 🗑️  Delete User"
        echo "4) ✏️  Edit User"
        echo "5) 👤 Show User Data"
        echo "6) 🌐 Manage SNI Domains"
        echo ""
        echo -e "${RED}0) 🔙 Back to Main Menu${NC}"
        echo ""
        
        read -p "Select option (0-6): " choice
        
        # Add delay to prevent CPU spinning
        sleep 0.1
        case $choice in
            1) 
                list_users
                read -p "Press Enter to continue..." 
                ;;
            2) 
                read -p "Enter username: " username
                if [ -n "$username" ]; then
                    add_user "$username"
                else
                    warning "Username cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                echo "Current users:"
                list_users
                echo ""
                read -p "Enter user number or username to delete: " user_input
                if [ -n "$user_input" ]; then
                    # Try to get user by number first
                    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
                        username=$(get_user_by_number "$user_input")
                        if [ $? -eq 0 ] && [ -n "$username" ]; then
                            delete_user "$username"
                        else
                            warning "Invalid user number: $user_input"
                        fi
                    else
                        # Treat as username
                        delete_user "$user_input"
                    fi
                else
                    warning "User input cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo "Current users:"
                list_users
                echo ""
                read -p "Enter user number or username to edit: " user_input
                if [ -n "$user_input" ]; then
                    # Try to get user by number first
                    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
                        username=$(get_user_by_number "$user_input")
                        if [ $? -eq 0 ] && [ -n "$username" ]; then
                            edit_user "$username"
                        else
                            warning "Invalid user number: $user_input"
                        fi
                    else
                        # Treat as username
                        edit_user "$user_input"
                    fi
                else
                    warning "User input cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                echo "Current users:"
                list_users
                echo ""
                read -p "Enter user number or username to show: " user_input
                if [ -n "$user_input" ]; then
                    # Try to get user by number first
                    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
                        username=$(get_user_by_number "$user_input")
                        if [ $? -eq 0 ] && [ -n "$username" ]; then
                            show_user_by_name "$username"
                        else
                            warning "Invalid user number: $user_input"
                        fi
                    else
                        # Treat as username
                        show_user_by_name "$user_input"
                    fi
                else
                    warning "User input cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            6)
                echo "Current users:"
                list_users
                echo ""
                read -p "Enter user number or username to manage SNI domains: " user_input
                if [ -n "$user_input" ]; then
                    # Try to get user by number first
                    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
                        username=$(get_user_by_number "$user_input")
                        if [ $? -eq 0 ] && [ -n "$username" ]; then
                            # Load multi-SNI module if not loaded
                            if ! type manage_user_sni_interactive &>/dev/null; then
                                source "$PROJECT_ROOT/modules/users/multi_sni.sh" || {
                                    error "Failed to load multi-SNI module"
                                    read -p "Press Enter to continue..."
                                    continue
                                }
                            fi
                            manage_user_sni_interactive "$username"
                        else
                            warning "Invalid user number: $user_input"
                        fi
                    else
                        # Treat as username
                        # Load multi-SNI module if not loaded
                        if ! type manage_user_sni_interactive &>/dev/null; then
                            source "$PROJECT_ROOT/modules/users/multi_sni.sh" || {
                                error "Failed to load multi-SNI module"
                                read -p "Press Enter to continue..."
                                continue
                            }
                        fi
                        manage_user_sni_interactive "$user_input"
                    fi
                else
                    warning "User input cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                warning "Invalid option. Please choose 0-6."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f show_user_management_menu