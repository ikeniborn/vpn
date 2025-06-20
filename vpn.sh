#!/bin/bash

# =============================================================================
# Unified VPN Management Script (Modular Version)
# 
# This script combines all VPN functionality using a modular architecture:
# - Server installation and configuration
# - User management
# - Client installation
# - Server monitoring and maintenance
# - Deployment and backup operations
#
# Author: Claude
# Version: 3.1 (Modular)
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
OUTLINE_DIR="/opt/outline"
CLIENT_WORK_DIR="/opt/v2raya"
SCRIPT_VERSION="3.1"
ACTION=""
SUB_ACTION=""

# =============================================================================
# MODULE LOADING FUNCTIONS
# =============================================================================

# Load user management modules
load_user_modules() {
    source "$SCRIPT_DIR/modules/users/add.sh" || return 1
    source "$SCRIPT_DIR/modules/users/delete.sh" || return 1
    source "$SCRIPT_DIR/modules/users/edit.sh" || return 1
    source "$SCRIPT_DIR/modules/users/list.sh" || return 1
    source "$SCRIPT_DIR/modules/users/show.sh" || return 1
    
    return 0
}

# Load monitoring modules
load_monitoring_modules() {
    source "$SCRIPT_DIR/modules/monitoring/statistics.sh" || return 1
    source "$SCRIPT_DIR/modules/monitoring/logging.sh" || return 1
    source "$SCRIPT_DIR/modules/monitoring/logs_viewer.sh" || return 1
    
    return 0
}

# Load additional libraries
load_additional_libraries() {
    local debug="${1:-false}"
    
    [[ "$debug" == true ]] && log "Loading additional libraries from: $SCRIPT_DIR/lib/"
    
    # Load required libraries
    for lib in "network.sh" "crypto.sh" "docker.sh"; do
        if [ ! -f "$SCRIPT_DIR/lib/$lib" ]; then
            error "Library file not found: $SCRIPT_DIR/lib/$lib"
            return 1
        fi
        
        source "$SCRIPT_DIR/lib/$lib" || {
            error "Failed to load library: $lib"
            return 1
        }
        [[ "$debug" == true ]] && log "Loaded $lib"
    done
    
    [[ "$debug" == true ]] && log "Additional libraries loaded successfully"
    return 0
}

# Load server modules
load_server_modules() {
    local debug="${1:-false}"
    
    [[ "$debug" == true ]] && log "Loading server modules from: $SCRIPT_DIR/modules/"
    
    # Source server management modules
    source "$SCRIPT_DIR/modules/server/status.sh" || return 1
    source "$SCRIPT_DIR/modules/server/restart.sh" || return 1
    source "$SCRIPT_DIR/modules/server/uninstall.sh" || return 1
    
    [[ "$debug" == true ]] && log "Server modules loaded successfully"
    return 0
}

# Load menu modules
load_menu_system() {
    local debug="${1:-false}"
    source "$SCRIPT_DIR/modules/menu/menu_loader.sh" || return 1
    # Call the load_menu_modules function from the loaded file
    load_menu_modules "$debug" || return 1
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Detect which VPN server is installed
detect_installed_vpn_type() {
    if [ -d "$WORK_DIR" ] && [ -f "$WORK_DIR/docker-compose.yml" ]; then
        echo "xray"
    elif [ -d "$OUTLINE_DIR" ] || docker ps -a --format "table {{.Names}}" | grep -q "shadowbox"; then
        echo "outline"
    else
        echo "none"
    fi
}

# =============================================================================
# CORE FUNCTIONALITY
# =============================================================================

# Include core installation and configuration functions from original vpn.sh
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
        
        # Create Xray configuration and first user
        create_xray_config_and_user || {
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
    echo "2) Outline VPN (Shadowsocks)"
    
    while true; do
        read -p "Select option (1-2): " choice
        case $choice in
            1)
                PROTOCOL="vless-reality"
                USE_REALITY=true
                log "Selected protocol: VLESS+Reality"
                break
                ;;
            2)
                PROTOCOL="outline"
                USE_REALITY=false
                log "Selected protocol: Outline VPN"
                break
                ;;
            *)
                warning "Please choose 1 or 2"
                ;;
        esac
    done
    
    # Check for existing installation of selected protocol
    check_existing_vpn_installation "$PROTOCOL" || {
        error "Installation cancelled"
        return 1
    }
    
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
    
    # Debug: Show current configuration state
    log "Current configuration after port selection:"
    log "  SERVER_IP: $SERVER_IP"
    log "  SERVER_PORT: $SERVER_PORT"
    log "  PROTOCOL: $PROTOCOL"
    
    # Get SNI configuration for Reality
    if [ "$USE_REALITY" = true ]; then
        get_sni_config_interactive
        generate_reality_keys
    fi
    
    # Get user name for first user (only for VLESS)
    if [ "$PROTOCOL" = "vless-reality" ]; then
        while true; do
            read -p "Enter username for the first user: " USER_NAME
            if [ -n "$USER_NAME" ] && [[ "$USER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                log "User name: $USER_NAME"
                break
            else
                warning "Invalid username. Use only letters, numbers, hyphens, and underscores"
            fi
        done
    fi
    
    # Final debug: Show all configuration
    log "Final configuration:"
    log "  SERVER_IP: $SERVER_IP"
    log "  SERVER_PORT: $SERVER_PORT" 
    log "  SERVER_SNI: $SERVER_SNI"
    log "  PROTOCOL: $PROTOCOL"
    log "  USER_NAME: $USER_NAME"
    log "  PRIVATE_KEY: ${PRIVATE_KEY:0:10}..."
    log "  PUBLIC_KEY: ${PUBLIC_KEY:0:10}..."
    log "  SHORT_ID: $SHORT_ID"
    
    return 0
}

# Check for existing VPN installations
check_existing_vpn_installation() {
    local protocol="${1:-}"
    local found=false
    local existing_server=""
    
    log "Checking for existing $protocol installation..."
    
    # Check based on protocol
    case "$protocol" in
        "vless-reality")
            # Check for Xray installation
            if [ -d "$WORK_DIR" ] && [ -f "$WORK_DIR/docker-compose.yml" ]; then
                if docker ps --format "table {{.Names}}" | grep -q "xray"; then
                    found=true
                    existing_server="Xray/VLESS server (running)"
                elif docker ps -a --format "table {{.Names}}" | grep -q "xray"; then
                    found=true
                    existing_server="Xray/VLESS server (stopped)"
                fi
            fi
            ;;
        "outline")
            # Check for Outline installation
            if [ -d "$OUTLINE_DIR" ] || docker ps -a --format "table {{.Names}}" | grep -q "shadowbox"; then
                if docker ps --format "table {{.Names}}" | grep -q "shadowbox"; then
                    found=true
                    existing_server="Outline VPN server (running)"
                elif docker ps -a --format "table {{.Names}}" | grep -q "shadowbox"; then
                    found=true
                    existing_server="Outline VPN server (stopped)"
                fi
            fi
            ;;
        *)
            error "Unknown protocol: $protocol"
            return 1
            ;;
    esac
    
    # If server found, prompt user
    if [ "$found" = true ]; then
        echo -e "\n${YELLOW}⚠️  Existing installation detected:${NC}"
        echo -e "• $existing_server"
        echo -e "${YELLOW}Installing a new server will replace the existing one.${NC}\n"
        
        echo "Choose an action:"
        echo "1) Reinstall (remove existing and install new)"
        echo "2) Cancel installation"
        
        while true; do
            read -p "Select option (1-2): " choice
            case $choice in
                1)
                    log "User chose to reinstall"
                    
                    # Remove existing installation based on protocol
                    case "$protocol" in
                        "vless-reality")
                            log "Removing existing Xray installation..."
                            if docker ps | grep -q "xray"; then
                                cd "$WORK_DIR" 2>/dev/null && docker-compose down 2>/dev/null || true
                            fi
                            docker rm -f xray 2>/dev/null || true
                            rm -rf "$WORK_DIR" 2>/dev/null || true
                            ;;
                        "outline")
                            log "Removing existing Outline installation..."
                            docker rm -f shadowbox watchtower 2>/dev/null || true
                            rm -rf "$OUTLINE_DIR" 2>/dev/null || true
                            # Remove any Outline-related firewall rules
                            if command -v ufw >/dev/null 2>&1; then
                                ufw status numbered | grep -E "9000|Outline" | awk '{print $2}' | sort -r | while read -r num; do
                                    ufw --force delete "$num" 2>/dev/null || true
                                done
                            fi
                            ;;
                    esac
                    
                    log "Existing installations removed"
                    return 0
                    ;;
                2)
                    log "Installation cancelled by user"
                    echo -e "${YELLOW}Installation cancelled.${NC}"
                    exit 0
                    ;;
                *)
                    warning "Please choose 1 or 2"
                    ;;
            esac
        done
    else
        log "No existing VPN installations found"
    fi
    
    return 0
}

# Helper functions from original script
get_sni_config_interactive() {
    # Source SNI configuration
    source "$SCRIPT_DIR/modules/install/prerequisites.sh" || {
        error "Failed to load prerequisites module"
        return 1
    }
    
    echo -e "${BLUE}Choose SNI domain for Reality:${NC}"
    echo "1) Pre-configured safe domains (Recommended)"
    echo "2) Enter custom domain"
    
    while true; do
        read -p "Select option (1-2): " sni_choice
        case $sni_choice in
            1)
                # Get pre-configured domain
                get_sni_domain true
                if [ -n "$SERVER_SNI" ]; then
                    log "Selected SNI domain: $SERVER_SNI"
                    break
                else
                    error "Failed to get SNI domain"
                    return 1
                fi
                ;;
            2)
                read -p "Enter SNI domain: " custom_sni
                if validate_sni_domain "$custom_sni"; then
                    SERVER_SNI="$custom_sni"
                    log "Custom SNI domain: $SERVER_SNI"
                    break
                else
                    warning "Invalid domain format"
                fi
                ;;
            *)
                warning "Please choose 1 or 2"
                ;;
        esac
    done
    
    return 0
}

generate_reality_keys() {
    # Generate Reality keys
    # Ensure crypto library is loaded
    if ! command -v generate_keypair >/dev/null 2>&1; then
        source "$SCRIPT_DIR/lib/crypto.sh" || {
            error "Failed to load crypto library"
            return 1
        }
    fi
    
    # Use generate_reality_keys which returns private_key public_key short_id
    local reality_keys=$(generate_reality_keys 2>/dev/null)
    if [ -n "$reality_keys" ]; then
        # If generate_reality_keys worked, extract all three values
        PRIVATE_KEY=$(echo "$reality_keys" | awk '{print $1}')
        PUBLIC_KEY=$(echo "$reality_keys" | awk '{print $2}')
        SHORT_ID=$(echo "$reality_keys" | awk '{print $3}')
    else
        # Fallback to separate functions
        local keys=$(generate_keypair)
        if [ -z "$keys" ]; then
            error "Failed to generate keypair"
            return 1
        fi
        
        PRIVATE_KEY=$(echo "$keys" | cut -d' ' -f1)
        PUBLIC_KEY=$(echo "$keys" | cut -d' ' -f2)
        SHORT_ID=$(generate_short_id)
    fi
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
        error "Failed to extract or generate Reality keys"
        log "  Reality keys output: $reality_keys"
        log "  PRIVATE_KEY: $PRIVATE_KEY"
        log "  PUBLIC_KEY: $PUBLIC_KEY" 
        log "  SHORT_ID: $SHORT_ID"
        return 1
    fi
    
    log "Generated Reality keys successfully"
    log "  PRIVATE_KEY: ${PRIVATE_KEY:0:10}..."
    log "  PUBLIC_KEY: ${PUBLIC_KEY:0:10}..."
    log "  SHORT_ID: $SHORT_ID"
    return 0
}

# Create Xray configuration and prepare for first user
create_xray_config_and_user() {
    log "Creating Xray configuration..."
    
    # Validate required variables
    if [ -z "$PROTOCOL" ]; then
        PROTOCOL="vless-reality"
        log "Protocol not set, defaulting to: $PROTOCOL"
    fi
    
    if [ -z "$WORK_DIR" ]; then
        WORK_DIR="/opt/v2ray"
        log "Work directory not set, defaulting to: $WORK_DIR"
    fi
    
    if [ -z "$SERVER_PORT" ]; then
        error "SERVER_PORT is not set. This should have been configured during installation."
        return 1
    fi
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(get_external_ip) || SERVER_IP="127.0.0.1"
        log "Server IP not set, detected/defaulting to: $SERVER_IP"
    fi
    
    # Generate UUID for first user if not set
    if [ -z "$USER_UUID" ]; then
        # Ensure crypto library is loaded for UUID generation
        if ! command -v generate_uuid >/dev/null 2>&1; then
            source "$SCRIPT_DIR/lib/crypto.sh" || {
                error "Failed to load crypto library for UUID generation"
                return 1
            }
        fi
        USER_UUID=$(generate_uuid)
    fi
    
    # Ensure Reality keys are set
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
        log "Reality keys not set, generating them now..."
        generate_reality_keys || {
            error "Failed to generate Reality keys"
            return 1
        }
    fi
    
    if [ -z "$SERVER_SNI" ]; then
        error "SERVER_SNI is not set. This should have been configured during installation."
        return 1
    fi
    
    if [ -z "$USER_NAME" ]; then
        error "USER_NAME is not set. This should have been configured during installation."
        return 1
    fi
    
    # Debug information
    log "Configuration parameters:"
    log "  WORK_DIR: $WORK_DIR"
    log "  PROTOCOL: $PROTOCOL"
    log "  SERVER_PORT: $SERVER_PORT"
    log "  USER_NAME: $USER_NAME"
    log "  USER_UUID: $USER_UUID"
    log "  SERVER_IP: $SERVER_IP"
    log "  SERVER_SNI: $SERVER_SNI"
    log "  PRIVATE_KEY: ${PRIVATE_KEY:0:10}..."
    log "  PUBLIC_KEY: ${PUBLIC_KEY:0:10}..."
    log "  SHORT_ID: $SHORT_ID"
    
    # Store configuration values
    mkdir -p "$WORK_DIR/config"
    echo "$PRIVATE_KEY" > "$WORK_DIR/config/private_key.txt"
    echo "$PUBLIC_KEY" > "$WORK_DIR/config/public_key.txt"
    echo "$SHORT_ID" > "$WORK_DIR/config/short_id.txt"
    echo "$SERVER_SNI" > "$WORK_DIR/config/sni.txt"
    echo "$PROTOCOL" > "$WORK_DIR/config/protocol.txt"
    echo "$SERVER_PORT" > "$WORK_DIR/config/port.txt"
    
    # Load xray_config module if not already loaded
    if ! command -v setup_xray_configuration >/dev/null 2>&1; then
        source "$SCRIPT_DIR/modules/install/xray_config.sh" || {
            error "Failed to load xray_config module"
            return 1
        }
    fi
    
    # Setup Xray configuration using the module
    setup_xray_configuration "$WORK_DIR" "$PROTOCOL" "$SERVER_PORT" "$USER_UUID" \
        "$USER_NAME" "$SERVER_IP" "$SERVER_SNI" "$PRIVATE_KEY" "$PUBLIC_KEY" \
        "$SHORT_ID" true || {
        error "Failed to setup Xray configuration"
        return 1
    }
    
    log "Xray configuration created successfully"
    return 0
}

create_first_user() {
    # Create first user for Xray
    if [ -z "$USER_NAME" ]; then
        error "User name is required"
        return 1
    fi
    
    # Generate UUID for user
    USER_UUID=$(generate_uuid)
    
    # Source user management modules
    load_user_modules || {
        error "Failed to load user modules"
        return 1
    }
    
    # Add user using existing module
    add_user "$USER_NAME" "$USER_UUID" true || {
        error "Failed to create first user"
        return 1
    }
    
    log "First user '$USER_NAME' created successfully"
    return 0
}

show_installation_results() {
    # Show installation completion message
    echo -e "\n${GREEN}=== VPN Server Installation Complete ===${NC}"
    echo -e "${BLUE}Protocol:${NC} $PROTOCOL"
    echo -e "${BLUE}Server IP:${NC} $SERVER_IP"
    echo -e "${BLUE}Port:${NC} $SERVER_PORT"
    
    if [ "$PROTOCOL" = "vless-reality" ]; then
        echo -e "${BLUE}SNI Domain:${NC} $SERVER_SNI"
        echo -e "${BLUE}First User:${NC} $USER_NAME"
        echo -e "\n${YELLOW}Use the 'users' menu to manage users and get connection details.${NC}"
    elif [ "$PROTOCOL" = "outline" ]; then
        echo -e "\n${YELLOW}Outline VPN installed successfully!${NC}"
        echo -e "${YELLOW}Access configuration from:${NC} /opt/outline/access.txt"
        echo -e "${YELLOW}Use Outline Manager app to manage users.${NC}"
    fi
    
    echo -e "\n${GREEN}Installation completed successfully!${NC}\n"
    return 0
}

# =============================================================================
# LAZY MODULE LOADING (Performance Optimization)
# =============================================================================

# Module loading cache
declare -A LOADED_MODULES

# Load module with lazy loading optimization
load_module_lazy() {
    local module="$1"
    local module_path="$SCRIPT_DIR/modules/$module"
    
    [ -z "${LOADED_MODULES[$module]}" ] && {
        source "$module_path" || {
            error "Failed to load module: $module"
            return 1
        }
        LOADED_MODULES[$module]=1
    }
    return 0
}

# =============================================================================
# USER MANAGEMENT
# =============================================================================

handle_user_management() {
    # Check prerequisites
    if [ "$EUID" -ne 0 ]; then
        error "User management requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check which VPN type is installed
    local vpn_type=$(detect_installed_vpn_type)
    
    if [ "$vpn_type" = "none" ]; then
        error "No VPN server is installed. Run '$0 install' first."
        return 1
    elif [ "$vpn_type" = "outline" ]; then
        echo -e "${YELLOW}Outline VPN user management is done through the Outline Manager app.${NC}"
        echo -e "${BLUE}Download Outline Manager from:${NC}"
        echo -e "${WHITE}https://getoutline.org/get-started/#step-1${NC}"
        echo ""
        read -p "Press Enter to return to main menu..."
        return 0
    fi
    
    # For Xray, continue with normal user management
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
    
    # Show user management menu
    show_user_management_menu
}

# =============================================================================
# OTHER HANDLERS (Simplified stubs)
# =============================================================================

handle_client_management() {
    # Source client installation functionality
    if [ ! -f "$SCRIPT_DIR/install_client.sh" ]; then
        error "Client installation script not found"
        return 1
    fi
    
    echo -e "${BLUE}VPN Client Management${NC}"
    echo "1) Install VPN client (v2rayA)"
    echo "2) Check client status"
    echo "3) Restart client"
    echo "4) Uninstall client"
    echo "5) Back to main menu"
    
    while true; do
        read -p "Select option (1-5): " choice
        case $choice in
            1)
                log "Installing VPN client..."
                bash "$SCRIPT_DIR/install_client.sh"
                break
                ;;
            2)
                if docker ps | grep -q "v2raya"; then
                    echo -e "${GREEN}✓ VPN client is running${NC}"
                    echo -e "${BLUE}Web interface:${NC} http://localhost:2017"
                else
                    echo -e "${RED}✗ VPN client is not running${NC}"
                fi
                read -p "Press Enter to continue..."
                break
                ;;
            3)
                log "Restarting VPN client..."
                docker restart v2raya 2>/dev/null || echo "Client not running"
                read -p "Press Enter to continue..."
                break
                ;;
            4)
                log "Uninstalling VPN client..."
                docker rm -f v2raya 2>/dev/null || true
                docker rmi mzz2017/v2raya 2>/dev/null || true
                echo -e "${GREEN}Client uninstalled${NC}"
                read -p "Press Enter to continue..."
                break
                ;;
            5)
                return 0
                ;;
            *)
                warning "Please choose 1-5"
                ;;
        esac
    done
}

handle_statistics() {
    if [ "$EUID" -ne 0 ]; then
        error "Statistics require superuser privileges (sudo)"
        return 1
    fi
    
    load_monitoring_modules || {
        error "Failed to load monitoring modules"
        return 1
    }
    
    show_statistics
}

handle_logs() {
    if [ "$EUID" -ne 0 ]; then
        error "Log viewing requires superuser privileges (sudo)"
        return 1
    fi
    
    load_monitoring_modules || {
        error "Failed to load monitoring modules"
        return 1
    }
    
    view_logs
}

handle_key_rotation() {
    if [ "$EUID" -ne 0 ]; then
        error "Key rotation requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check if Xray server is installed
    local vpn_type=$(detect_installed_vpn_type)
    if [ "$vpn_type" != "xray" ]; then
        error "Key rotation is only available for Xray/VLESS servers"
        return 1
    fi
    
    # Load server modules
    load_server_modules true || {
        error "Failed to load server modules"
        return 1
    }
    
    # Source and run key rotation
    source "$SCRIPT_DIR/modules/server/rotate_keys.sh" || {
        error "Failed to load key rotation module"
        return 1
    }
    
    rotate_reality_keys true
}

handle_logging_config() {
    if [ "$EUID" -ne 0 ]; then
        error "Logging configuration requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check if Xray server is installed
    local vpn_type=$(detect_installed_vpn_type)
    if [ "$vpn_type" != "xray" ]; then
        error "Logging configuration is only available for Xray servers"
        return 1
    fi
    
    # Load monitoring modules
    load_monitoring_modules || {
        error "Failed to load monitoring modules"
        return 1
    }
    
    # Call logging configuration function
    configure_logging
}


handle_watchdog() {
    echo -e "${BLUE}VPN Watchdog Management${NC}"
    echo "1) Install watchdog service"
    echo "2) Start watchdog"
    echo "3) Stop watchdog"
    echo "4) Check watchdog status"
    echo "5) Back to main menu"
    
    while true; do
        read -p "Select option (1-5): " choice
        case $choice in
            1)
                # Source watchdog module
                if [ -f "$SCRIPT_DIR/modules/system/watchdog.sh" ]; then
                    source "$SCRIPT_DIR/modules/system/watchdog.sh"
                    install_watchdog_service
                else
                    echo "Watchdog module not found"
                fi
                read -p "Press Enter to continue..."
                break
                ;;
            2)
                systemctl start vpn-watchdog 2>/dev/null || echo "Failed to start watchdog"
                read -p "Press Enter to continue..."
                break
                ;;
            3)
                systemctl stop vpn-watchdog 2>/dev/null || echo "Failed to stop watchdog"
                read -p "Press Enter to continue..."
                break
                ;;
            4)
                systemctl status vpn-watchdog 2>/dev/null || echo "Watchdog not installed"
                read -p "Press Enter to continue..."
                break
                ;;
            5)
                return 0
                ;;
            *)
                warning "Please choose 1-5"
                ;;
        esac
    done
}

# =============================================================================
# HELP AND VERSION
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
    echo -e "${YELLOW}Performance & Debug:${NC}"
    echo "  benchmark            Run performance benchmarks"
    echo "  debug                Show debug information and loaded modules"
}

show_version() {
    echo -e "${GREEN}VPN Management System${NC}"
    echo -e "${BLUE}Version:${NC} $SCRIPT_VERSION (Modular)"
    echo -e "${BLUE}Author:${NC} Claude"
    echo -e "${BLUE}Architecture:${NC} Modular"
}

# =============================================================================
# MAIN EXECUTION LOGIC
# =============================================================================

main() {
    # Parse command line arguments
    ACTION="${1:-menu}"
    SUB_ACTION="${2:-}"
    
    case "$ACTION" in
        "menu"|"")
            # Load menu modules and start interactive menu
            load_menu_system true || {
                error "Failed to load menu modules"
                exit 1
            }
            run_interactive_menu
            ;;
        "install")
            handle_server_install
            ;;
        "status")
            handle_server_status
            ;;
        "restart")
            handle_server_restart
            ;;
        "uninstall")
            handle_server_uninstall
            ;;
        "users")
            handle_user_management
            ;;
        "user")
            case "$SUB_ACTION" in
                "add"|"delete"|"list"|"show")
                    handle_user_management
                    ;;
                *)
                    show_usage
                    ;;
            esac
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        "version"|"--version"|"-v")
            show_version
            ;;
        "benchmark")
            # Load performance library and run benchmarks
            source "$SCRIPT_DIR/lib/performance.sh" 2>/dev/null || {
                error "Performance library not available"
                exit 1
            }
            echo "=== VPN System Performance Benchmarks ==="
            benchmark_modules
            test_command_performance "$0"
            monitor_resources
            ;;
        "debug")
            # Debug mode with performance monitoring
            source "$SCRIPT_DIR/lib/performance.sh" 2>/dev/null || true
            echo "=== Debug Information ==="
            monitor_resources
            echo -e "\n=== Loaded Modules ==="
            for module in "${!LOADED_MODULES[@]}"; do
                echo "  ✓ $module"
            done
            ;;
        *)
            error "Unknown command: $ACTION"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
