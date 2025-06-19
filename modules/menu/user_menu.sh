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
        echo "0) 🔙 Back to Main Menu"
        echo ""
        
        read -p "Select option (0-5): " choice
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
                read -p "Enter username to delete: " username
                if [ -n "$username" ]; then
                    delete_user "$username"
                else
                    warning "Username cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo "Current users:"
                list_users
                echo ""
                read -p "Enter username to edit: " username
                if [ -n "$username" ]; then
                    edit_user "$username"
                else
                    warning "Username cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                echo "Current users:"
                list_users
                echo ""
                read -p "Enter username to show: " username
                if [ -n "$username" ]; then
                    show_user "$username"
                else
                    warning "Username cannot be empty"
                fi
                read -p "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                warning "Invalid option. Please choose 0-5."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f show_user_management_menu