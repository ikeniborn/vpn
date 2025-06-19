#!/bin/bash

# =============================================================================
# Main Menu Module
# 
# This module handles the main interactive menu display and navigation.
# Extracted from vpn.sh for modular architecture.
#
# Functions exported:
# - show_main_menu()
# - handle_menu_choice()
# - run_interactive_menu()
#
# Dependencies: lib/common.sh, lib/ui.sh
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
# MAIN MENU DISPLAY
# =============================================================================

show_main_menu() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          VPN Management System v${SCRIPT_VERSION:-3.0}                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Server Management:${NC}"
    echo "  1)  📦 Install VPN Server"
    echo "  2)  📊 Server Status"
    echo "  3)  🔄 Restart Server"
    echo "  4)  🗑️  Uninstall Server"
    echo ""
    echo -e "${YELLOW}User Management:${NC}"
    echo "  5)  👥 User Management"
    echo ""
    echo -e "${YELLOW}Client Management:${NC}"
    echo "  6)  💻 Client Management"
    echo "  7)  📥 Install Client (Quick)"
    echo ""
    echo -e "${YELLOW}Monitoring & Maintenance:${NC}"
    echo "  8)  📈 Traffic Statistics"
    echo "  9)  📋 View Logs"
    echo "  10) 🔐 Rotate Keys"
    echo ""
    echo -e "${YELLOW}Advanced:${NC}"
    echo "  11) 🛡️  Watchdog Service"
    echo ""
    echo -e "${YELLOW}Help & Info:${NC}"
    echo "  12) ❓ Show Help"
    echo "  13) ℹ️  Show Version"
    echo ""
    echo -e "${RED}  0)  🚪 Exit${NC}"
    echo ""
}

# =============================================================================
# MENU CHOICE HANDLING
# =============================================================================

handle_menu_choice() {
    local choice="$1"
    
    case "$choice" in
        1)
            handle_server_install
            ;;
        2)
            handle_server_status
            ;;
        3)
            handle_server_restart
            ;;
        4)
            handle_server_uninstall
            ;;
        5)
            handle_user_management
            ;;
        6)
            handle_client_management
            ;;
        7)
            SUB_ACTION="install"
            handle_client_management
            ;;
        8)
            handle_statistics
            ;;
        9)
            handle_logs
            ;;
        10)
            handle_key_rotation
            ;;
        11)
            handle_watchdog_menu
            ;;
        12)
            show_usage
            ;;
        13)
            show_version
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            warning "Invalid option. Please choose 0-13."
            ;;
    esac
}

# =============================================================================
# SUBMENU HANDLERS
# =============================================================================


handle_watchdog_menu() {
    echo -e "${BLUE}Watchdog Service:${NC}"
    echo "1) Install Service"
    echo "2) Start Service"
    echo "3) Stop Service"
    echo "4) Restart Service"
    echo "5) Service Status"
    echo "6) Remove Service"
    echo "0) Back"
    read -p "Select option: " watchdog_choice
    case "$watchdog_choice" in
        1) SUB_ACTION="install"; handle_watchdog ;;
        2) SUB_ACTION="start"; handle_watchdog ;;
        3) SUB_ACTION="stop"; handle_watchdog ;;
        4) SUB_ACTION="restart"; handle_watchdog ;;
        5) SUB_ACTION="status"; handle_watchdog ;;
        6) SUB_ACTION="remove"; handle_watchdog ;;
        0) return ;;
        *) warning "Invalid option" ;;
    esac
}

# =============================================================================
# INTERACTIVE MENU LOOP
# =============================================================================

run_interactive_menu() {
    # Set interactive mode flag
    export INTERACTIVE_MODE=1
    
    # Trap to ensure we always exit with 0
    trap 'exit 0' INT TERM EXIT
    
    while true; do
        show_main_menu
        read -p "Select option (0-13): " choice
        
        # Handle errors gracefully
        handle_menu_choice "$choice" || {
            # If error occurred, show message and continue
            echo ""
            read -p "Press Enter to continue..."
            continue
        }
        
        if [ "$choice" = "0" ]; then
            exit 0
        fi
        
        if [ "$choice" != "12" ] && [ "$choice" != "13" ]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f show_main_menu
export -f handle_menu_choice
export -f handle_watchdog_menu
export -f run_interactive_menu