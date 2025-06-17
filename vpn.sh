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
    echo "Usage: $0 <command> [options]"
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
    echo "  $0 install                    # Install VPN server interactively"
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
    check_root_privileges true || exit 1
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
# MAIN COMMAND ROUTER
# =============================================================================

main() {
    # Parse command line arguments
    case "$1" in
        --help|-h|"")
            show_usage
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
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
            error "Unknown command: $1\nRun '$0 --help' for usage information."
            ;;
    esac
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi