#!/bin/bash

# =============================================================================
# Unified VPN Management Script
# 
# This script combines all VPN functionality:
# - Server installation and configuration
# - User management
# - Client installation
# - Server monitoring and maintenance
# - Deployment and backup operations
#
# Author: Claude
# Version: 3.0 (Unified)
# =============================================================================

# Removed 'set -e' to ensure we always exit with 0
# Error handling is done gracefully within functions

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "Error: Cannot source lib/common.sh"
    exit 0
}

# Override error function to not exit with non-zero code
error() {
    echo -e "${RED}✗ [ERROR]${NC} $1" >&2
    # In interactive mode, return to menu instead of exiting
    if [ -n "$INTERACTIVE_MODE" ]; then
        return 1
    else
        exit 0
    fi
}

source "$SCRIPT_DIR/lib/config.sh" || {
    error "Cannot source lib/config.sh"
    exit 0
}

source "$SCRIPT_DIR/lib/ui.sh" || {
    error "Cannot source lib/ui.sh"
    exit 0
}

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

WORK_DIR="/opt/v2ray"
CLIENT_WORK_DIR="/opt/v2raya"
SCRIPT_VERSION="3.0"
ACTION=""
SUB_ACTION=""

# =============================================================================
# HELP AND USAGE
# =============================================================================

show_usage() {
    echo -e "${GREEN}=== Unified VPN Management Script v${SCRIPT_VERSION} ===${NC}"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo -e "${YELLOW}Interactive Mode:${NC}"
    echo "  (no command)         Launch interactive menu"
    echo "  menu                 Launch interactive menu"
    echo ""
    echo -e "${YELLOW}Server Commands:${NC}"
    echo "  install              Install VPN server"
    echo "  uninstall            Uninstall VPN server"
    echo "  status               Show server status"
    echo "  restart              Restart VPN server"
    echo ""
    echo -e "${YELLOW}User Management:${NC}"
    echo "  users                Interactive user management menu"
    echo "  user add <name>      Add a new user"
    echo "  user delete <name>   Delete a user"
    echo "  user list            List all users"
    echo "  user show <name>     Show user connection details"
    echo ""
    echo -e "${YELLOW}Client Commands:${NC}"
    echo "  client install       Install VPN client"
    echo "  client status        Show client status"
    echo "  client uninstall     Uninstall VPN client"
    echo ""
    echo -e "${YELLOW}Monitoring Commands:${NC}"
    echo "  stats                Show traffic statistics"
    echo "  logs                 View server logs"
    echo "  rotate-keys          Rotate Reality encryption keys"
    echo ""
    echo -e "${YELLOW}Deployment Commands:${NC}"
    echo "  deploy install       Deploy fresh installation"
    echo "  deploy update        Update existing installation"
    echo "  deploy backup        Create backup"
    echo "  deploy restore       Restore from backup"
    echo ""
    echo -e "${YELLOW}System Commands:${NC}"
    echo "  watchdog start       Start watchdog service"
    echo "  watchdog stop        Stop watchdog service"
    echo "  watchdog status      Show watchdog status"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --help, -h           Show this help message"
    echo "  --version, -v        Show version information"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0                            # Launch interactive menu"
    echo "  $0 install                    # Install VPN server"
    echo "  $0 user add john              # Add user 'john'"
    echo "  $0 client install             # Install VPN client"
    echo "  $0 stats                      # Show traffic statistics"
    echo ""
}

show_version() {
    echo -e "${GREEN}Unified VPN Management Script${NC}"
    echo -e "Version: ${BLUE}${SCRIPT_VERSION}${NC}"
    echo -e "Architecture: ${BLUE}Modular${NC}"
    echo -e "Location: ${BLUE}${SCRIPT_DIR}${NC}"
}

# =============================================================================
# MODULE LOADING
# =============================================================================

load_server_modules() {
    # Load installation modules
    source "$SCRIPT_DIR/modules/install/prerequisites.sh" || return 1
    source "$SCRIPT_DIR/modules/install/docker_setup.sh" || return 1
    source "$SCRIPT_DIR/modules/install/xray_config.sh" || return 1
    source "$SCRIPT_DIR/modules/install/firewall.sh" || return 1
    
    # Load server management modules
    source "$SCRIPT_DIR/modules/server/status.sh" || return 1
    source "$SCRIPT_DIR/modules/server/restart.sh" || return 1
    source "$SCRIPT_DIR/modules/server/rotate_keys.sh" || return 1
    source "$SCRIPT_DIR/modules/server/uninstall.sh" || return 1
    
    return 0
}

load_user_modules() {
    source "$SCRIPT_DIR/modules/users/add.sh" || return 1
    source "$SCRIPT_DIR/modules/users/delete.sh" || return 1
    source "$SCRIPT_DIR/modules/users/edit.sh" || return 1
    source "$SCRIPT_DIR/modules/users/list.sh" || return 1
    source "$SCRIPT_DIR/modules/users/show.sh" || return 1
    
    return 0
}

load_monitoring_modules() {
    source "$SCRIPT_DIR/modules/monitoring/statistics.sh" || return 1
    source "$SCRIPT_DIR/modules/monitoring/logging.sh" || return 1
    source "$SCRIPT_DIR/modules/monitoring/logs_viewer.sh" || return 1
    
    return 0
}

load_additional_libraries() {
    source "$SCRIPT_DIR/lib/network.sh" || return 1
    source "$SCRIPT_DIR/lib/crypto.sh" || return 1
    source "$SCRIPT_DIR/lib/docker.sh" || return 1
    
    return 0
}

# =============================================================================
# SERVER INSTALLATION (from install_vpn.sh)
# =============================================================================

handle_server_install() {
    log "Starting VPN server installation..."
    
    # Check prerequisites
    check_root_privileges true || {
        error "Root privileges required"
        return 1
    }
    detect_system_info true
    
    # Load required modules
    load_additional_libraries || error "Failed to load additional libraries"
    load_server_modules || error "Failed to load server modules"
    
    # Source the original installation logic
    source "$SCRIPT_DIR/install_vpn.sh" || error "Failed to load install_vpn.sh"
    
    # Run main installation
    main
}

# =============================================================================
# USER MANAGEMENT (from manage_users.sh)
# =============================================================================

handle_user_management() {
    # Check prerequisites
    if [ "$EUID" -ne 0 ]; then
        error "User management requires superuser privileges (sudo)"
    fi
    
    # Check if server is installed
    if [ ! -d "$WORK_DIR" ]; then
        error "VPN server is not installed. Run '$0 install' first."
    fi
    
    # Load required modules
    load_user_modules || error "Failed to load user modules"
    load_monitoring_modules || error "Failed to load monitoring modules"
    load_server_modules || error "Failed to load server modules"
    
    case "$SUB_ACTION" in
        "add")
            if [ -z "$2" ]; then
                error "Username required. Usage: $0 user add <username>"
            fi
            add_user "$2"
            ;;
        "delete")
            if [ -z "$2" ]; then
                error "Username required. Usage: $0 user delete <username>"
            fi
            delete_user "$2"
            ;;
        "list")
            list_users
            ;;
        "show")
            if [ -z "$2" ]; then
                error "Username required. Usage: $0 user show <username>"
            fi
            show_user "$2"
            ;;
        *)
            # Interactive mode
            source "$SCRIPT_DIR/manage_users.sh" || error "Failed to load manage_users.sh"
            main
            ;;
    esac
}

# =============================================================================
# CLIENT INSTALLATION (from install_client.sh)
# =============================================================================

handle_client_management() {
    case "$SUB_ACTION" in
        "install")
            log "Starting VPN client installation..."
            source "$SCRIPT_DIR/install_client.sh" || error "Failed to load install_client.sh"
            install_client
            ;;
        "status")
            source "$SCRIPT_DIR/install_client.sh" || error "Failed to load install_client.sh"
            show_client_status
            ;;
        "uninstall")
            source "$SCRIPT_DIR/install_client.sh" || error "Failed to load install_client.sh"
            uninstall_client
            ;;
        *)
            # Interactive mode
            source "$SCRIPT_DIR/install_client.sh" || error "Failed to load install_client.sh"
            main
            ;;
    esac
}

# =============================================================================
# SERVER MANAGEMENT
# =============================================================================

handle_server_status() {
    load_server_modules || error "Failed to load server modules"
    show_server_status
}

handle_server_restart() {
    load_server_modules || error "Failed to load server modules"
    restart_server
}

handle_server_uninstall() {
    source "$SCRIPT_DIR/uninstall.sh" || error "Failed to load uninstall.sh"
    main "$@"
}

# =============================================================================
# MONITORING COMMANDS
# =============================================================================

handle_statistics() {
    load_monitoring_modules || error "Failed to load monitoring modules"
    show_traffic_statistics
}

handle_logs() {
    load_monitoring_modules || error "Failed to load monitoring modules"
    view_user_logs
}

handle_key_rotation() {
    load_server_modules || error "Failed to load server modules"
    load_additional_libraries || error "Failed to load additional libraries"
    rotate_reality_keys
}

# =============================================================================
# DEPLOYMENT COMMANDS
# =============================================================================

handle_deployment() {
    case "$SUB_ACTION" in
        "install"|"update"|"backup"|"restore")
            source "$SCRIPT_DIR/deploy.sh" || error "Failed to load deploy.sh"
            # Pass the sub-action as the main action to deploy.sh
            bash "$SCRIPT_DIR/deploy.sh" "$SUB_ACTION"
            ;;
        *)
            error "Unknown deployment command: $SUB_ACTION"
            ;;
    esac
}

# =============================================================================
# WATCHDOG COMMANDS
# =============================================================================

handle_watchdog() {
    case "$SUB_ACTION" in
        "start")
            if [ ! -f "$SCRIPT_DIR/vpn-watchdog.service" ]; then
                error "Watchdog service file not found"
            fi
            
            # Install watchdog script
            cp "$SCRIPT_DIR/watchdog.sh" /usr/local/bin/vpn-watchdog.sh
            chmod +x /usr/local/bin/vpn-watchdog.sh
            
            # Install systemd service
            cp "$SCRIPT_DIR/vpn-watchdog.service" /etc/systemd/system/
            systemctl daemon-reload
            systemctl enable vpn-watchdog.service
            systemctl start vpn-watchdog.service
            
            log "Watchdog service started"
            ;;
        "stop")
            systemctl stop vpn-watchdog.service
            log "Watchdog service stopped"
            ;;
        "status")
            systemctl status vpn-watchdog.service
            ;;
        *)
            error "Unknown watchdog command: $SUB_ACTION"
            ;;
    esac
}

# =============================================================================
# INTERACTIVE MENU
# =============================================================================

show_main_menu() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          VPN Management System v${SCRIPT_VERSION}                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Server Management:${NC}"
    echo "  1)  📦 Install VPN Server"
    echo "  2)  📊 Server Status"
    echo "  3)  🔄 Restart Server"
    echo "  4)  🗑️  Uninstall Server"
    echo ""
    echo -e "${YELLOW}User Management:${NC}"
    echo "  5)  👥 User Management Menu"
    echo "  6)  ➕ Add User (Quick)"
    echo "  7)  📋 List Users"
    echo ""
    echo -e "${YELLOW}Client Management:${NC}"
    echo "  8)  💻 Client Management Menu"
    echo "  9)  📥 Install Client"
    echo ""
    echo -e "${YELLOW}Monitoring & Maintenance:${NC}"
    echo "  10) 📈 Traffic Statistics"
    echo "  11) 📋 View Logs"
    echo "  12) 🔐 Rotate Keys"
    echo ""
    echo -e "${YELLOW}Advanced:${NC}"
    echo "  13) 🚀 Deployment Options"
    echo "  14) 🛡️  Watchdog Service"
    echo ""
    echo -e "${YELLOW}Help & Info:${NC}"
    echo "  15) ❓ Show Help"
    echo "  16) ℹ️  Show Version"
    echo ""
    echo -e "${RED}  0)  🚪 Exit${NC}"
    echo ""
}

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
            echo -e "${BLUE}Quick Add User${NC}"
            read -p "Enter username: " username
            if [ -n "$username" ]; then
                SUB_ACTION="add"
                handle_user_management "$username"
            else
                warning "Username cannot be empty"
            fi
            ;;
        7)
            SUB_ACTION="list"
            handle_user_management
            ;;
        8)
            handle_client_management
            ;;
        9)
            SUB_ACTION="install"
            handle_client_management
            ;;
        10)
            handle_statistics
            ;;
        11)
            handle_logs
            ;;
        12)
            handle_key_rotation
            ;;
        13)
            echo -e "${BLUE}Deployment Options:${NC}"
            echo "1) Install"
            echo "2) Update"
            echo "3) Backup"
            echo "4) Restore"
            echo "0) Back"
            read -p "Select option: " deploy_choice
            case "$deploy_choice" in
                1) SUB_ACTION="install"; handle_deployment ;;
                2) SUB_ACTION="update"; handle_deployment ;;
                3) SUB_ACTION="backup"; handle_deployment ;;
                4) SUB_ACTION="restore"; handle_deployment ;;
                0) return ;;
                *) warning "Invalid option" ;;
            esac
            ;;
        14)
            echo -e "${BLUE}Watchdog Service:${NC}"
            echo "1) Start"
            echo "2) Stop"
            echo "3) Status"
            echo "0) Back"
            read -p "Select option: " watchdog_choice
            case "$watchdog_choice" in
                1) SUB_ACTION="start"; handle_watchdog ;;
                2) SUB_ACTION="stop"; handle_watchdog ;;
                3) SUB_ACTION="status"; handle_watchdog ;;
                0) return ;;
                *) warning "Invalid option" ;;
            esac
            ;;
        15)
            show_usage
            ;;
        16)
            show_version
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            warning "Invalid option. Please choose 0-16."
            ;;
    esac
}

run_interactive_menu() {
    # Set interactive mode flag
    export INTERACTIVE_MODE=1
    
    # Trap to ensure we always exit with 0
    trap 'exit 0' INT TERM EXIT
    
    while true; do
        show_main_menu
        read -p "Select option (0-16): " choice
        
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
        
        if [ "$choice" != "15" ] && [ "$choice" != "16" ]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# =============================================================================
# MAIN COMMAND ROUTER
# =============================================================================

main() {
    # Trap to ensure we always exit with 0
    trap 'exit 0' INT TERM EXIT
    
    # Parse command line arguments
    case "$1" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
        ""|menu)
            # Run interactive menu when no arguments or 'menu' command
            run_interactive_menu
            ;;
        install)
            ACTION="install"
            shift
            handle_server_install "$@"
            ;;
        uninstall)
            ACTION="uninstall"
            shift
            handle_server_uninstall "$@"
            ;;
        status)
            ACTION="status"
            handle_server_status
            ;;
        restart)
            ACTION="restart"
            handle_server_restart
            ;;
        users)
            ACTION="users"
            handle_user_management
            ;;
        user)
            ACTION="user"
            SUB_ACTION="$2"
            shift 2
            handle_user_management "$@"
            ;;
        client)
            ACTION="client"
            SUB_ACTION="$2"
            shift 2
            handle_client_management "$@"
            ;;
        stats)
            ACTION="stats"
            handle_statistics
            ;;
        logs)
            ACTION="logs"
            handle_logs
            ;;
        rotate-keys)
            ACTION="rotate-keys"
            handle_key_rotation
            ;;
        deploy)
            ACTION="deploy"
            SUB_ACTION="$2"
            shift 2
            handle_deployment "$@"
            ;;
        watchdog)
            ACTION="watchdog"
            SUB_ACTION="$2"
            shift 2
            handle_watchdog "$@"
            ;;
        *)
            warning "Unknown command: $1"
            echo "Run '$0 --help' for usage information."
            exit 0
            ;;
    esac
    
    # Always exit with 0
    exit 0
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi