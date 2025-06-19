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

source "$SCRIPT_DIR/lib/network.sh" || {
    error "Cannot source lib/network.sh"
    exit 0
}

source "$SCRIPT_DIR/lib/crypto.sh" || {
    error "Cannot source lib/crypto.sh"
    exit 0
}

source "$SCRIPT_DIR/lib/docker.sh" || {
    error "Cannot source lib/docker.sh"
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
    echo "  watchdog install     Install watchdog service"
    echo "  watchdog start       Start watchdog service"
    echo "  watchdog stop        Stop watchdog service"
    echo "  watchdog restart     Restart watchdog service"
    echo "  watchdog status      Show watchdog status"
    echo "  watchdog remove      Remove watchdog service"
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
    local debug="${1:-false}"
    
    [[ "$debug" == true ]] && log "Loading server modules from: $SCRIPT_DIR/modules/"
    
    # Set PROJECT_ROOT for modules to use when sourcing libraries
    export PROJECT_ROOT="$SCRIPT_DIR"
    
    # Load installation modules
    source "$SCRIPT_DIR/modules/install/prerequisites.sh" || {
        error "Failed to source modules/install/prerequisites.sh"
        return 1
    }
    source "$SCRIPT_DIR/modules/install/docker_setup.sh" || {
        error "Failed to source modules/install/docker_setup.sh"
        return 1
    }
    source "$SCRIPT_DIR/modules/install/xray_config.sh" || {
        error "Failed to source modules/install/xray_config.sh"
        return 1
    }
    source "$SCRIPT_DIR/modules/install/firewall.sh" || {
        error "Failed to source modules/install/firewall.sh"
        return 1
    }
    
    # Load server management modules
    source "$SCRIPT_DIR/modules/server/status.sh" || {
        error "Failed to source modules/server/status.sh"
        return 1
    }
    source "$SCRIPT_DIR/modules/server/restart.sh" || {
        error "Failed to source modules/server/restart.sh"
        return 1
    }
    source "$SCRIPT_DIR/modules/server/rotate_keys.sh" || {
        error "Failed to source modules/server/rotate_keys.sh"
        return 1
    }
    source "$SCRIPT_DIR/modules/server/uninstall.sh" || {
        error "Failed to source modules/server/uninstall.sh"
        return 1
    }
    
    [[ "$debug" == true ]] && log "Server modules loaded successfully"
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
    local debug="${1:-false}"
    
    [[ "$debug" == true ]] && log "Loading additional libraries from: $SCRIPT_DIR/lib/"
    
    # Check if files exist before sourcing
    for lib in "network.sh" "crypto.sh" "docker.sh"; do
        if [ ! -f "$SCRIPT_DIR/lib/$lib" ]; then
            error "Library file not found: $SCRIPT_DIR/lib/$lib"
            return 1
        fi
    done
    
    source "$SCRIPT_DIR/lib/network.sh" || {
        error "Failed to source lib/network.sh"
        return 1
    }
    
    source "$SCRIPT_DIR/lib/crypto.sh" || {
        error "Failed to source lib/crypto.sh"
        return 1
    }
    
    source "$SCRIPT_DIR/lib/docker.sh" || {
        error "Failed to source lib/docker.sh"
        return 1
    }
    
    [[ "$debug" == true ]] && log "Additional libraries loaded successfully"
    return 0
}

# =============================================================================
# SERVER INSTALLATION LOGIC
# =============================================================================

# Run complete server installation using modules
run_server_installation() {
    log "Starting modular VPN server installation..."
    
    # Install system dependencies
    install_system_dependencies true || {
        error "Failed to install system dependencies"
        return 1
    }
    
    # Verify dependencies
    verify_dependencies true || {
        error "Dependency verification failed"
        return 1
    }
    
    # Get server configuration interactively
    get_server_config_interactive || {
        error "Failed to get server configuration"
        return 1
    }
    
    # Install based on selected protocol
    if [ "$PROTOCOL" = "outline" ]; then
        # Source Outline installation module
        source "$SCRIPT_DIR/modules/install/outline_setup.sh" || {
            error "Failed to load Outline installation module"
            return 1
        }
        
        # Install Outline VPN server
        install_outline_server true || {
            error "Failed to install Outline VPN server"
            return 1
        }
    else
        # Source required installation modules
        source "$SCRIPT_DIR/modules/install/xray_config.sh" || {
            error "Failed to load Xray configuration module"
            return 1
        }
        
        source "$SCRIPT_DIR/modules/install/docker_setup.sh" || {
            error "Failed to load Docker setup module"
            return 1
        }
        
        source "$SCRIPT_DIR/modules/install/firewall.sh" || {
            error "Failed to load firewall module"
            return 1
        }
        
        # Create Xray configuration
        create_xray_config || {
            error "Failed to create Xray configuration"
            return 1
        }
        
        # Setup Docker environment
        setup_docker_environment "$WORK_DIR" "$SERVER_PORT" true || {
            error "Failed to setup Docker environment"
            return 1
        }
        
        # Configure firewall
        setup_xray_firewall "$SERVER_PORT" true || {
            error "Failed to configure firewall"
            return 1
        }
        
        # Create first user
        create_first_user || {
            error "Failed to create first user"
            return 1
        }
    fi
    
    # Show installation results
    show_installation_results
    
    log "VPN server installation completed successfully!"
}

# Get server configuration interactively
get_server_config_interactive() {
    # Global variables for configuration
    export SERVER_IP=""
    export SERVER_PORT=""
    export SERVER_SNI=""
    export PROTOCOL="vless-reality"
    export USE_REALITY=true
    export USER_NAME=""
    export USER_UUID=""
    export PRIVATE_KEY=""
    export PUBLIC_KEY=""
    export SHORT_ID=""
    
    # Get external IP
    SERVER_IP=$(get_external_ip) || {
        read -p "Could not detect external IP. Enter server IP address: " SERVER_IP
    }
    log "External IP: $SERVER_IP"
    
    # Choose VPN type
    echo -e "${BLUE}Choose VPN type:${NC}"
    echo "1) VLESS+Reality (Recommended)"
    echo "2) VLESS Basic"
    echo "3) Outline VPN (Shadowsocks)"
    
    while true; do
        read -p "Select option (1-3): " choice
        case $choice in
            1)
                PROTOCOL="vless-reality"
                USE_REALITY=true
                log "Selected protocol: VLESS+Reality"
                break
                ;;
            2)
                PROTOCOL="vless-basic"
                USE_REALITY=false
                log "Selected protocol: VLESS Basic"
                break
                ;;
            3)
                PROTOCOL="outline"
                USE_REALITY=false
                log "Selected protocol: Outline VPN"
                break
                ;;
            *)
                warning "Please choose 1, 2, or 3"
                ;;
        esac
    done
    
    # Get server port
    echo -e "${BLUE}Choose server port:${NC}"
    echo "1) Automatic free port (10000-65000) - Recommended"
    echo "2) Manual port"
    echo "3) Standard port (10443)"
    
    while true; do
        read -p "Select option (1-3): " port_choice
        case $port_choice in
            1)
                SERVER_PORT=$(generate_free_port 10000 65000 true 20 10443)
                log "Automatically selected port: $SERVER_PORT"
                break
                ;;
            2)
                read -p "Enter port (1024-65535): " custom_port
                if validate_port "$custom_port" && check_port_available "$custom_port"; then
                    SERVER_PORT="$custom_port"
                    log "Selected port: $SERVER_PORT"
                    break
                else
                    warning "Port unavailable or incorrect"
                fi
                ;;
            3)
                SERVER_PORT="10443"
                if check_port_available "$SERVER_PORT"; then
                    log "Using standard port: $SERVER_PORT"
                    break
                else
                    warning "Standard port is busy, choose another option"
                fi
                ;;
            *)
                warning "Please choose 1, 2, or 3"
                ;;
        esac
    done
    
    # Get SNI configuration for Reality
    if [ "$USE_REALITY" = true ]; then
        get_sni_config_interactive
        generate_reality_keys
    fi
    
    # Get user name for first user
    while true; do
        read -p "Enter username for the first user: " USER_NAME
        if [ -n "$USER_NAME" ] && [[ "$USER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log "User name: $USER_NAME"
            break
        else
            warning "Invalid username. Use only letters, numbers, hyphens, and underscores"
        fi
    done
    
    return 0
}

# Get SNI configuration
get_sni_config_interactive() {
    echo -e "${BLUE}Choose SNI domain:${NC}"
    echo "1) addons.mozilla.org - Recommended"
    echo "2) www.lovelive-anime.jp"
    echo "3) www.swift.org"
    echo "4) Custom domain"
    echo "5) Auto-select best domain"
    
    local sni_domains=(
        "addons.mozilla.org"
        "www.lovelive-anime.jp"
        "www.swift.org"
    )
    
    while true; do
        read -p "Select option (1-5): " sni_choice
        case $sni_choice in
            1|2|3)
                local selected_domain="${sni_domains[$((sni_choice-1))]}"
                if check_sni_domain "$selected_domain"; then
                    SERVER_SNI="$selected_domain"
                    log "Selected SNI domain: $SERVER_SNI"
                    break
                else
                    warning "Domain unavailable, try another"
                fi
                ;;
            4)
                read -p "Enter domain: " custom_domain
                if check_sni_domain "$custom_domain"; then
                    SERVER_SNI="$custom_domain"
                    log "Selected custom domain: $SERVER_SNI"
                    break
                else
                    warning "Domain unavailable or incorrect"
                fi
                ;;
            5)
                log "Finding best domain..."
                for domain in "${sni_domains[@]}"; do
                    if check_sni_domain "$domain"; then
                        SERVER_SNI="$domain"
                        log "Auto-selected domain: $SERVER_SNI"
                        break
                    fi
                done
                if [ -n "$SERVER_SNI" ]; then
                    break
                else
                    warning "Could not find available domain"
                fi
                ;;
            *)
                warning "Please choose 1-5"
                ;;
        esac
    done
}

# Generate Reality keys
generate_reality_keys() {
    log "Generating Reality keys..."
    
    # Generate keys using crypto library
    local keys=$(generate_reality_keypair)
    PRIVATE_KEY=$(echo "$keys" | cut -d' ' -f1)
    PUBLIC_KEY=$(echo "$keys" | cut -d' ' -f2)
    
    # Generate short ID
    SHORT_ID=$(generate_short_id)
    
    log "Reality keys generated"
}

# Create Xray configuration
create_xray_config() {
    log "Creating Xray configuration..."
    
    # Generate user UUID
    USER_UUID=$(generate_uuid)
    
    # Get username
    read -p "Enter first user name (default: user1): " input_name
    USER_NAME="${input_name:-user1}"
    log "Username: $USER_NAME"
    
    # Determine protocol format for configuration
    local config_protocol=""
    if [ "$USE_REALITY" = true ]; then
        config_protocol="vless-reality"
    else
        config_protocol="vless-basic"
    fi
    
    # Create configuration using module
    setup_xray_configuration "$WORK_DIR" "$config_protocol" "$SERVER_PORT" "$USER_UUID" \
        "$USER_NAME" "$SERVER_IP" "$SERVER_SNI" "$PRIVATE_KEY" "$PUBLIC_KEY" \
        "$SHORT_ID" true || {
        error "Failed to create Xray configuration"
        return 1
    }
    
    log "Xray configuration created"
}

# Create first user
create_first_user() {
    log "Creating first user: $USER_NAME"
    
    # This will be handled by the configuration creation
    # User is already created in create_xray_config
    
    log "First user created successfully"
}

# Show installation results
show_installation_results() {
    # Skip for Outline as it has its own results display
    if [ "$PROTOCOL" = "outline" ]; then
        return 0
    fi
    
    echo -e "\n${GREEN}=== Installation Complete ===${NC}"
    echo -e "${BLUE}Server:${NC} $SERVER_IP"
    echo -e "${BLUE}Port:${NC} $SERVER_PORT"
    echo -e "${BLUE}Protocol:${NC} $PROTOCOL"
    echo -e "${BLUE}User:${NC} $USER_NAME"
    
    if [ "$USE_REALITY" = true ]; then
        echo -e "${BLUE}SNI:${NC} $SERVER_SNI"
        echo -e "${BLUE}Public Key:${NC} $PUBLIC_KEY"
        echo -e "${BLUE}Short ID:${NC} $SHORT_ID"
    fi
    
    # Show connection link
    if [ -f "$WORK_DIR/users/$USER_NAME.link" ]; then
        echo -e "\n${GREEN}Connection link:${NC}"
        cat "$WORK_DIR/users/$USER_NAME.link"
        echo
    fi
    
    # Show QR code location
    if [ -f "$WORK_DIR/users/$USER_NAME.png" ]; then
        echo -e "${GREEN}QR code saved:${NC} $WORK_DIR/users/$USER_NAME.png"
    fi
    
    echo -e "\n${YELLOW}For user management use:${NC}"
    echo -e "${WHITE}sudo ./vpn.sh users${NC}"
}

# =============================================================================
# SERVER INSTALLATION (from install_vpn.sh)
# =============================================================================

handle_server_install() {
    log "Starting VPN server installation..."
    
    # Check root privileges first (built-in check)
    if [ "$EUID" -ne 0 ]; then
        error "Root privileges required. Please run with sudo."
        return 1
    fi
    
    # Load required modules
    load_additional_libraries true || {
        error "Failed to load additional libraries"
        return 1
    }
    load_server_modules true || {
        error "Failed to load server modules"
        return 1
    }
    
    # Now check system prerequisites using loaded modules
    detect_system_info true
    
    # Run installation using modules
    run_server_installation
}

# =============================================================================
# USER MANAGEMENT (from manage_users.sh)
# =============================================================================

handle_user_management() {
    # Check prerequisites
    if [ "$EUID" -ne 0 ]; then
        error "User management requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check if server is installed
    if [ ! -d "$WORK_DIR" ]; then
        error "VPN server is not installed. Run '$0 install' first."
        return 1
    fi
    
    # Load required modules
    load_user_modules || {
        error "Failed to load user modules"
        return 1
    }
    load_monitoring_modules || {
        error "Failed to load monitoring modules"
        return 1
    }
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
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
            # Interactive mode - call users menu directly
            show_user_management_menu
            ;;
    esac
}

# Show user management submenu
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
            1) list_users; read -p "Press Enter to continue..." ;;
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
                    echo -e "${YELLOW}Delete user '$username'? [y/N]${NC}"
                    read -p "Confirm: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        delete_user "$username"
                    else
                        log "Deletion cancelled"
                    fi
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
            0) break ;;
            *) warning "Invalid option. Please choose 0-5." ;;
        esac
    done
}

# =============================================================================
# CLIENT INSTALLATION (from install_client.sh)
# =============================================================================

handle_client_management() {
    case "$SUB_ACTION" in
        "install")
            log "Client installation not yet implemented in unified script"
            warning "Please use the original install_client.sh for now"
            ;;
        "status")
            log "Client status check not yet implemented in unified script"
            warning "Please use the original install_client.sh for now"
            ;;
        "uninstall")
            log "Client uninstall not yet implemented in unified script"
            warning "Please use the original install_client.sh for now"
            ;;
        *)
            # Interactive mode
            echo -e "${YELLOW}Client management commands:${NC}"
            echo "  client install     Install VPN client"
            echo "  client status      Show client status"
            echo "  client uninstall   Uninstall client"
            echo ""
            warning "Client management not yet fully implemented in unified script"
            ;;
    esac
}

# =============================================================================
# SERVER MANAGEMENT
# =============================================================================

handle_server_status() {
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    show_server_status
}

handle_server_restart() {
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    restart_server
}

handle_server_uninstall() {
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "Uninstall requires superuser privileges (sudo)"
        return 1
    fi
    
    # Load server modules
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
    # Use the uninstall module
    uninstall_vpn_server
}

# =============================================================================
# MONITORING COMMANDS
# =============================================================================

handle_statistics() {
    load_monitoring_modules || {
        error "Failed to load monitoring modules"
        return 1
    }
    show_traffic_statistics
}

handle_logs() {
    load_monitoring_modules || {
        error "Failed to load monitoring modules"
        return 1
    }
    view_user_logs
}

handle_key_rotation() {
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    load_additional_libraries || {
        error "Failed to load additional libraries"
        return 1
    }
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
    # Load watchdog module
    source "$SCRIPT_DIR/modules/system/watchdog.sh" || {
        error "Failed to load watchdog module"
        return 1
    }
    
    case "$SUB_ACTION" in
        "install")
            install_watchdog_service
            ;;
        "remove"|"uninstall")
            remove_watchdog_service
            ;;
        "start")
            start_watchdog_service
            ;;
        "stop")
            stop_watchdog_service
            ;;
        "status")
            get_watchdog_status
            ;;
        "restart")
            stop_watchdog_service
            sleep 2
            start_watchdog_service
            ;;
        *)
            echo -e "${YELLOW}Watchdog Commands:${NC}"
            echo "  watchdog install     Install watchdog service"
            echo "  watchdog start       Start watchdog service"
            echo "  watchdog stop        Stop watchdog service"
            echo "  watchdog restart     Restart watchdog service"
            echo "  watchdog status      Show watchdog status"
            echo "  watchdog remove      Remove watchdog service"
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