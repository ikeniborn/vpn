#!/bin/bash

# =============================================================================
# VPN User Management Script (Modular Version)
# 
# This script provides comprehensive user management for VPN server.
# It has been refactored to use modular architecture.
#
# Author: Claude
# Version: 2.0 (Modular)
# =============================================================================

set -e

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

source "$SCRIPT_DIR/lib/config.sh" || {
    error "Cannot source lib/config.sh"
}

source "$SCRIPT_DIR/lib/ui.sh" || {
    error "Cannot source lib/ui.sh"
}

# Source user management modules
source "$SCRIPT_DIR/modules/users/add.sh" || {
    error "Cannot source modules/users/add.sh"
}

source "$SCRIPT_DIR/modules/users/delete.sh" || {
    error "Cannot source modules/users/delete.sh"
}

source "$SCRIPT_DIR/modules/users/edit.sh" || {
    error "Cannot source modules/users/edit.sh"
}

source "$SCRIPT_DIR/modules/users/list.sh" || {
    error "Cannot source modules/users/list.sh"
}

source "$SCRIPT_DIR/modules/users/show.sh" || {
    error "Cannot source modules/users/show.sh"
}

# Source server management modules
source "$SCRIPT_DIR/modules/server/status.sh" || {
    error "Cannot source modules/server/status.sh"
}

source "$SCRIPT_DIR/modules/server/restart.sh" || {
    error "Cannot source modules/server/restart.sh"
}

source "$SCRIPT_DIR/modules/server/rotate_keys.sh" || {
    error "Cannot source modules/server/rotate_keys.sh"
}

source "$SCRIPT_DIR/modules/server/uninstall.sh" || {
    error "Cannot source modules/server/uninstall.sh"
}

# Source monitoring modules
source "$SCRIPT_DIR/modules/monitoring/statistics.sh" || {
    error "Cannot source modules/monitoring/statistics.sh"
}

source "$SCRIPT_DIR/modules/monitoring/logging.sh" || {
    error "Cannot source modules/monitoring/logging.sh"
}

source "$SCRIPT_DIR/modules/monitoring/logs_viewer.sh" || {
    error "Cannot source modules/monitoring/logs_viewer.sh"
}

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

WORK_DIR="/opt/v2ray"

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

# Check prerequisites and install missing tools
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script with superuser privileges (sudo)"
    fi
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Check and install required tools
    local tools=("uuid" "qrencode" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "Installing missing tools: ${missing_tools[*]}"
        apt update
        apt install -y "${missing_tools[@]}" || {
            error "Failed to install required tools: ${missing_tools[*]}"
        }
    fi
    
    # Check if VPN server is installed
    if [ ! -d "$WORK_DIR" ]; then
        error "VPN server is not installed. Please run install_vpn.sh first."
    fi
    
    log "Prerequisites check completed"
}

# =============================================================================
# MENU SYSTEM
# =============================================================================

# Show main menu
show_main_menu() {
    clear
    echo -e "${GREEN}=== VPN User Management (Modular Version) ===${NC}"
    echo -e "${BLUE}Version: 2.0${NC}"
    echo -e "${BLUE}Working Directory: $WORK_DIR${NC}\n"
    
    echo -e "${YELLOW}User Management:${NC}"
    echo "1)  📋 List Users"
    echo "2)  ➕ Add User"
    echo "3)  🗑️  Delete User"
    echo "4)  ✏️  Edit User"
    echo "5)  👤 Show User Data"
    echo
    echo -e "${YELLOW}Server Management:${NC}"
    echo "6)  📊 Server Status"
    echo "7)  🔄 Restart Server"
    echo "8)  🔐 Key Rotation"
    echo "9)  🗑️  Uninstall Server"
    echo
    echo -e "${YELLOW}Monitoring:${NC}"
    echo "10) 📈 Usage Statistics"
    echo "11) 🔧 Configure Logging"
    echo "12) 📋 View User Logs"
    echo
    echo -e "${YELLOW}System:${NC}"
    echo "0)  🚪 Exit"
    echo
}

# Handle menu selection
handle_menu_selection() {
    local choice="$1"
    
    case $choice in
        1)
            list_users_interactive
            ;;
        2)
            add_user_interactive
            ;;
        3)
            delete_user_interactive
            ;;
        4)
            edit_user_interactive
            ;;
        5)
            show_user_interactive
            ;;
        6)
            show_server_status_interactive
            ;;
        7)
            restart_server_interactive
            ;;
        8)
            rotate_keys_interactive
            ;;
        9)
            uninstall_server_interactive
            ;;
        10)
            show_statistics_interactive
            ;;
        11)
            configure_logging_interactive
            ;;
        12)
            view_logs_interactive
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            warning "Invalid option. Please choose 0-12."
            press_enter
            ;;
    esac
}

# =============================================================================
# INTERACTIVE WRAPPERS
# =============================================================================

# Interactive wrapper for list users
list_users_interactive() {
    clear
    echo -e "${GREEN}=== User List ===${NC}\n"
    list_users || {
        error "Failed to list users"
    }
    press_enter
}

# Interactive wrapper for add user
add_user_interactive() {
    clear
    echo -e "${GREEN}=== Add New User ===${NC}\n"
    
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        warning "Username cannot be empty"
        press_enter
        return 1
    fi
    
    add_user "$username" || {
        error "Failed to add user: $username"
    }
    press_enter
}

# Interactive wrapper for delete user
delete_user_interactive() {
    clear
    echo -e "${GREEN}=== Delete User ===${NC}\n"
    
    # Show current users first
    echo "Current users:"
    list_users
    echo
    
    read -p "Enter username to delete: " username
    if [ -z "$username" ]; then
        warning "Username cannot be empty"
        press_enter
        return 1
    fi
    
    # Confirm deletion
    echo -e "${YELLOW}Are you sure you want to delete user '$username'? [y/N]${NC}"
    read -p "Confirm: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        delete_user "$username" || {
            error "Failed to delete user: $username"
        }
    else
        log "Deletion cancelled"
    fi
    press_enter
}

# Interactive wrapper for edit user
edit_user_interactive() {
    clear
    echo -e "${GREEN}=== Edit User ===${NC}\n"
    
    # Show current users first
    echo "Current users:"
    list_users
    echo
    
    read -p "Enter username to edit: " username
    if [ -z "$username" ]; then
        warning "Username cannot be empty"
        press_enter
        return 1
    fi
    
    edit_user "$username" || {
        error "Failed to edit user: $username"
    }
    press_enter
}

# Interactive wrapper for show user
show_user_interactive() {
    clear
    echo -e "${GREEN}=== Show User Data ===${NC}\n"
    
    # Show current users first
    echo "Current users:"
    list_users
    echo
    
    read -p "Enter username to show: " username
    if [ -z "$username" ]; then
        warning "Username cannot be empty"
        press_enter
        return 1
    fi
    
    show_user "$username" || {
        error "Failed to show user data: $username"
    }
    press_enter
}

# Interactive wrapper for server status
show_server_status_interactive() {
    clear
    echo -e "${GREEN}=== Server Status ===${NC}\n"
    show_server_status || {
        error "Failed to show server status"
    }
    press_enter
}

# Interactive wrapper for restart server
restart_server_interactive() {
    clear
    echo -e "${GREEN}=== Restart Server ===${NC}\n"
    
    echo -e "${YELLOW}Are you sure you want to restart the VPN server? [y/N]${NC}"
    read -p "Confirm: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        restart_server || {
            error "Failed to restart server"
        }
    else
        log "Restart cancelled"
    fi
    press_enter
}

# Interactive wrapper for key rotation
rotate_keys_interactive() {
    clear
    echo -e "${GREEN}=== Key Rotation ===${NC}\n"
    
    echo -e "${YELLOW}This will rotate Reality keys and update all users. Continue? [y/N]${NC}"
    read -p "Confirm: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rotate_reality_keys || {
            error "Failed to rotate keys"
        }
    else
        log "Key rotation cancelled"
    fi
    press_enter
}

# Interactive wrapper for server uninstall
uninstall_server_interactive() {
    clear
    echo -e "${GREEN}=== Uninstall Server ===${NC}\n"
    
    echo -e "${RED}WARNING: This will completely remove the VPN server and all user data!${NC}"
    echo -e "${YELLOW}Are you absolutely sure? Type 'YES' to confirm:${NC}"
    read -p "Confirm: " confirm
    if [ "$confirm" = "YES" ]; then
        uninstall_vpn_server || {
            error "Failed to uninstall server"
        }
        echo -e "${GREEN}Server uninstalled successfully. Exiting...${NC}"
        exit 0
    else
        log "Uninstall cancelled"
    fi
    press_enter
}

# Interactive wrapper for statistics
show_statistics_interactive() {
    clear
    echo -e "${GREEN}=== Usage Statistics ===${NC}\n"
    show_traffic_statistics || {
        error "Failed to show statistics"
    }
    press_enter
}

# Interactive wrapper for logging configuration
configure_logging_interactive() {
    clear
    echo -e "${GREEN}=== Configure Logging ===${NC}\n"
    configure_xray_logging || {
        error "Failed to configure logging"
    }
    press_enter
}

# Interactive wrapper for log viewer
view_logs_interactive() {
    clear
    echo -e "${GREEN}=== View User Logs ===${NC}\n"
    view_user_logs || {
        error "Failed to view logs"
    }
    press_enter
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Check prerequisites
    check_prerequisites
    
    # Main menu loop
    while true; do
        show_main_menu
        read -p "Select option (0-12): " choice
        handle_menu_selection "$choice"
    done
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi