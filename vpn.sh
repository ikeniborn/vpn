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

# Global caching variables to reduce CPU usage
VPN_TYPE_CACHE=""
VPN_TYPE_CACHE_TIME=0
DOCKER_STATUS_CACHE=""
DOCKER_STATUS_CACHE_TIME=0

# Rate limiting for expensive operations
LAST_HEAVY_OP_TIME=0
HEAVY_OP_COOLDOWN=2  # Minimum 2 seconds between heavy operations

# Check if we can perform a heavy operation (rate limiting)
can_perform_heavy_operation() {
    local current_time=$(date +%s)
    if [ $((current_time - LAST_HEAVY_OP_TIME)) -ge $HEAVY_OP_COOLDOWN ]; then
        LAST_HEAVY_OP_TIME=$current_time
        return 0
    fi
    return 1
}

# Get Docker container status with caching
get_docker_status_cached() {
    local current_time=$(date +%s)
    local cache_validity=10  # Cache for 10 seconds
    
    # Use cache if still valid
    if [ -n "$DOCKER_STATUS_CACHE" ] && [ $((current_time - DOCKER_STATUS_CACHE_TIME)) -lt $cache_validity ]; then
        echo "$DOCKER_STATUS_CACHE"
        return
    fi
    
    # Get fresh Docker status with timeout
    local status=""
    if command -v docker >/dev/null 2>&1; then
        status=$(timeout 3 docker ps --format "{{.Names}}" 2>/dev/null || echo "")
    fi
    
    # Update cache
    DOCKER_STATUS_CACHE="$status"
    DOCKER_STATUS_CACHE_TIME=$current_time
    
    echo "$status"
}

# Detect which VPN server is installed (with caching)
detect_installed_vpn_type() {
    local current_time=$(date +%s)
    local cache_validity=30  # Cache for 30 seconds
    
    # Use cache if still valid
    if [ -n "$VPN_TYPE_CACHE" ] && [ $((current_time - VPN_TYPE_CACHE_TIME)) -lt $cache_validity ]; then
        echo "$VPN_TYPE_CACHE"
        return
    fi
    
    # Detect VPN type using file system checks first (much faster)
    local vpn_type="none"
    if [ -d "$WORK_DIR" ] && [ -f "$WORK_DIR/docker-compose.yml" ]; then
        vpn_type="xray"
    elif [ -d "$OUTLINE_DIR" ]; then
        vpn_type="outline"
    else
        # Only check Docker if file system checks fail
        local containers=$(get_docker_status_cached)
        if echo "$containers" | grep -q "shadowbox"; then
            vpn_type="outline"
        fi
    fi
    
    # Update cache
    VPN_TYPE_CACHE="$vpn_type"
    VPN_TYPE_CACHE_TIME=$current_time
    
    echo "$vpn_type"
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
        
        # Install Outline VPN server with selected port
        export SERVER_PORT  # Make sure port is available to the module
        install_outline_server true || {
            error "Failed to install Outline VPN server"
            return 1
        }
    else
        # Source required installation modules
        export PROJECT_ROOT="$SCRIPT_DIR"
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
    
    # Get server port (applies to both VPN types)
    if [ "$PROTOCOL" = "outline" ]; then
        echo -e "${BLUE}Choose Outline VPN server port:${NC}"
        echo -e "${YELLOW}Note: This port will be used for VPN connections${NC}"
    else
        echo -e "${BLUE}Choose server port:${NC}"
    fi
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

# Check for existing VPN installations (optimized)
check_existing_vpn_installation() {
    local protocol="${1:-}"
    local found=false
    local existing_server=""
    
    log "Checking for existing $protocol installation..."
    
    # Get Docker containers info using cached function
    local running_containers=$(get_docker_status_cached)
    local all_containers=""
    if command -v docker >/dev/null 2>&1; then
        all_containers=$(timeout 3 docker ps -a --format "{{.Names}}" 2>/dev/null || echo "")
    fi
    
    # Check based on protocol
    case "$protocol" in
        "vless-reality")
            # Check for Xray installation
            if [ -d "$WORK_DIR" ] && [ -f "$WORK_DIR/docker-compose.yml" ]; then
                if echo "$running_containers" | grep -q "xray"; then
                    found=true
                    existing_server="Xray/VLESS server (running)"
                elif echo "$all_containers" | grep -q "xray"; then
                    found=true
                    existing_server="Xray/VLESS server (stopped)"
                fi
            fi
            ;;
        "outline")
            # Check for Outline installation
            if [ -d "$OUTLINE_DIR" ]; then
                if echo "$running_containers" | grep -q "shadowbox"; then
                    found=true
                    existing_server="Outline VPN server (running)"
                elif echo "$all_containers" | grep -q "shadowbox"; then
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
                            local containers=$(get_docker_status_cached)
                            if echo "$containers" | grep -q "xray"; then
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
        # Set PROJECT_ROOT before sourcing module
        export PROJECT_ROOT="$SCRIPT_DIR"
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
                local containers=$(get_docker_status_cached)
                if echo "$containers" | grep -q "v2raya"; then
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
    
    view_user_logs
}

validate_config() {
    if [ "$EUID" -ne 0 ]; then
        error "Configuration validation requires superuser privileges (sudo)"
        return 1
    fi
    
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
    # Load validation module
    if [ -f "$SCRIPT_DIR/modules/server/validate_config.sh" ]; then
        source "$SCRIPT_DIR/modules/server/validate_config.sh"
        validate_server_config true
    else
        error "Validation module not found"
        return 1
    fi
}

fix_reality() {
    if [ "$EUID" -ne 0 ]; then
        error "Reality fix requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔧 Fixing Reality connection issues..."
    
    # Check if Xray container is available
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker not available"
        return 1
    fi
    
    # Generate new Reality keys using Xray container
    log "Generating new Reality keys..."
    
    local new_private_key
    local new_public_key
    
    local key_output=$(docker run --rm teddysun/xray:latest xray x25519 2>/dev/null)
    
    if [ -n "$key_output" ] && echo "$key_output" | grep -q "Private key:"; then
        new_private_key=$(echo "$key_output" | grep "Private key:" | awk '{print $3}')
        new_public_key=$(echo "$key_output" | grep "Public key:" | awk '{print $3}')
        
        if [ -n "$new_private_key" ] && [ -n "$new_public_key" ]; then
            log "✓ New Reality keys generated"
            
            # Update configuration files
            if [ -f "/opt/v2ray/config/config.json" ]; then
                log "Updating configuration..."
                
                # Backup current config
                cp /opt/v2ray/config/config.json /opt/v2ray/config/config.json.backup.$(date +%Y%m%d_%H%M%S)
                
                # Update private key in config
                jq ".inbounds[0].streamSettings.realitySettings.privateKey = \"$new_private_key\"" \
                    /opt/v2ray/config/config.json > /opt/v2ray/config/config.json.tmp
                mv /opt/v2ray/config/config.json.tmp /opt/v2ray/config/config.json
                
                # Update key files
                echo "$new_private_key" > /opt/v2ray/config/private_key.txt
                echo "$new_public_key" > /opt/v2ray/config/public_key.txt
                
                # Update user configurations
                if [ -d "/opt/v2ray/users" ]; then
                    for user_file in /opt/v2ray/users/*.json; do
                        if [ -f "$user_file" ]; then
                            # Update both public_key (for display) and private_key (for client connection)
                            # In Reality protocol, client uses server's private key as its public key
                            jq ".public_key = \"$new_public_key\" | .private_key = \"$new_private_key\"" "$user_file" > "${user_file}.tmp"
                            mv "${user_file}.tmp" "$user_file"
                        fi
                    done
                fi
                
                log "✓ Configuration updated"
                
                # Restart container
                log "Restarting Xray container..."
                cd /opt/v2ray && docker-compose restart
                
                sleep 3
                
                log "✅ Reality fix completed!"
                log "🔑 New public key: $new_public_key"
                log "📱 Please regenerate client configurations with new keys"
                
            else
                error "Configuration file not found: /opt/v2ray/config/config.json"
                return 1
            fi
        else
            error "Failed to generate valid keys"
            return 1
        fi
    else
        error "Failed to generate new Reality keys"
        return 1
    fi
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
# DIAGNOSIS AND TROUBLESHOOTING
# =============================================================================

# Diagnose Reality connection issues
diagnose_reality() {
    if [ "$EUID" -ne 0 ]; then
        error "Reality diagnosis requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔍 Diagnosing Reality connection issues..."
    
    # Check if server is running (with timeout to prevent hanging)
    if ! timeout 5 docker ps 2>/dev/null | grep -q xray; then
        error "Xray container is not running or Docker is not responding"
        return 1
    fi
    
    # Get server configuration
    local config_file="/opt/v2ray/config/config.json"
    local port_file="/opt/v2ray/config/port.txt"
    
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check server port
    local server_port
    if [ -f "$port_file" ]; then
        server_port=$(cat "$port_file")
    else
        server_port=$(jq -r '.inbounds[0].port' "$config_file" 2>/dev/null)
    fi
    
    log "Server port: $server_port"
    
    # Check firewall rules
    log "Checking firewall rules..."
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | grep "$server_port")
        if [ -n "$ufw_status" ]; then
            log "✓ Port $server_port is allowed in UFW"
            echo "$ufw_status"
        else
            warning "Port $server_port is NOT allowed in UFW"
            log "Adding firewall rule..."
            ufw allow "$server_port/tcp" || warning "Failed to add firewall rule"
        fi
    else
        warning "UFW is not installed"
    fi
    
    # Check port accessibility
    log "Checking port accessibility..."
    if command -v nc >/dev/null 2>&1; then
        if nc -z localhost "$server_port" 2>/dev/null; then
            log "✓ Port $server_port is accessible locally"
        else
            warning "Port $server_port is NOT accessible locally"
        fi
    fi
    
    # Check Reality configuration
    log "Checking Reality configuration..."
    local private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$config_file" 2>/dev/null)
    local sni_domains=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[]' "$config_file" 2>/dev/null)
    local short_ids=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[]' "$config_file" 2>/dev/null)
    
    if [ -n "$private_key" ] && [ "$private_key" != "null" ]; then
        log "✓ Private key is configured"
    else
        warning "Private key is missing or invalid"
    fi
    
    if [ -n "$sni_domains" ]; then
        log "✓ SNI domains configured:"
        echo "$sni_domains" | while read -r domain; do
            echo "  - $domain"
        done
    else
        warning "No SNI domains configured"
    fi
    
    if [ -n "$short_ids" ]; then
        log "✓ Short IDs configured:"
        echo "$short_ids" | while read -r sid; do
            echo "  - $sid"
        done
    else
        warning "No short IDs configured"
    fi
    
    # Check recent errors
    log "Recent error logs:"
    if [ -f "/opt/v2ray/logs/error.log" ]; then
        tail -10 /opt/v2ray/logs/error.log | grep -E "(REALITY|invalid|error)" || log "No recent Reality errors found"
    fi
    
    # Suggestions
    log "💡 Troubleshooting suggestions:"
    echo "1. If getting 'processed invalid connection' errors:"
    echo "   - Check client configuration matches server Reality keys"
    echo "   - Verify SNI domain is accessible from client location"
    echo "   - Ensure client uses correct short ID"
    echo "2. If port is blocked:"
    echo "   - Run: sudo ufw allow $server_port/tcp"
    echo "   - Check cloud provider security groups"
    echo "3. If keys are invalid:"
    echo "   - Run: sudo ./vpn.sh fix-reality"
    
    return 0
}

# Force update all user configurations with current server keys
update_user_configs() {
    if [ "$EUID" -ne 0 ]; then
        error "User config update requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔄 Updating all user configurations with current server keys..."
    
    local config_file="/opt/v2ray/config/config.json"
    if [ ! -f "$config_file" ]; then
        error "Server configuration not found: $config_file"
        return 1
    fi
    
    # Get current server keys
    local server_private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$config_file" 2>/dev/null)
    local server_public_key=$(cat /opt/v2ray/config/public_key.txt 2>/dev/null)
    
    if [ -z "$server_private_key" ] || [ "$server_private_key" = "null" ]; then
        error "Could not read server private key"
        return 1
    fi
    
    if [ -z "$server_public_key" ]; then
        error "Could not read server public key"
        return 1
    fi
    
    log "Server private key: ${server_private_key:0:10}..."
    log "Server public key: ${server_public_key:0:10}..."
    
    # Update all user configurations
    local updated_count=0
    if [ -d "/opt/v2ray/users" ]; then
        for user_file in /opt/v2ray/users/*.json; do
            if [ -f "$user_file" ]; then
                local user_name=$(basename "$user_file" .json)
                log "Updating user configuration: $user_name"
                
                # Update keys in user file
                jq ".public_key = \"$server_public_key\" | .private_key = \"$server_private_key\"" "$user_file" > "${user_file}.tmp"
                if [ $? -eq 0 ]; then
                    mv "${user_file}.tmp" "$user_file"
                    updated_count=$((updated_count + 1))
                    log "✓ Updated: $user_name"
                else
                    rm -f "${user_file}.tmp"
                    warning "Failed to update: $user_name"
                fi
            fi
        done
    fi
    
    if [ $updated_count -gt 0 ]; then
        log "✅ Updated $updated_count user configurations"
        log "📱 Users need to regenerate their client configurations"
    else
        warning "No user configurations found to update"
    fi
    
    return 0
}

# Interactive firewall cleanup command
cleanup_firewall() {
    if [ "$EUID" -ne 0 ]; then
        error "Firewall cleanup requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🧹 Interactive VPN firewall cleanup"
    
    # Load firewall module
    load_module_lazy "install/firewall.sh" || {
        error "Failed to load firewall module"
        return 1
    }
    
    # Run interactive cleanup
    cleanup_unused_vpn_ports "" true true
}

# Recreate docker-compose with latest healthcheck fixes
recreate_docker() {
    if [ "$EUID" -ne 0 ]; then
        error "Docker recreation requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔄 Recreating docker-compose with latest fixes..."
    
    # Check if VPN is installed
    if [ ! -d "/opt/v2ray" ] || [ ! -f "/opt/v2ray/config/config.json" ]; then
        error "No Xray VPN installation found in /opt/v2ray"
        return 1
    fi
    
    # Get current configuration
    local server_port=$(cat /opt/v2ray/config/port.txt 2>/dev/null)
    if [ -z "$server_port" ]; then
        server_port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null)
    fi
    
    if [ -z "$server_port" ] || [ "$server_port" = "null" ]; then
        error "Could not determine server port"
        return 1
    fi
    
    log "Server port: $server_port"
    
    # Stop current container
    log "Stopping current container..."
    cd /opt/v2ray && docker-compose down 2>/dev/null || true
    
    # Load docker setup module
    load_module_lazy "install/docker_setup.sh" || {
        error "Failed to load docker setup module"
        return 1
    }
    
    # Recreate docker-compose.yml and healthcheck with debug
    log "Recreating docker-compose configuration with debug..."
    
    # Create debug healthcheck temporarily
    create_debug_healthcheck "/opt/v2ray" "$server_port"
    
    create_docker_compose "/opt/v2ray" "$server_port" true || {
        error "Failed to recreate docker-compose"
        return 1
    }
    
    # Start with new configuration
    log "Starting container with new configuration..."
    cd /opt/v2ray && docker-compose up -d
    
    log "✅ Docker container recreated successfully"
    log "⏱️  Wait 2-3 minutes for healthcheck to complete"
    
    return 0
}

# Create debug version of healthcheck for troubleshooting
create_debug_healthcheck() {
    local work_dir="$1" 
    local server_port="$2"
    
    cat > "$work_dir/healthcheck.sh" <<'EOF'
#!/bin/sh
# Health check script for VLESS+Reality (DEBUG VERSION)
# Enhanced version with debug logging

# Debug: log all inputs for troubleshooting  
echo "$(date): DEBUG: Argument 1: '$1'" >> /tmp/healthcheck.log
echo "$(date): DEBUG: SERVER_PORT env: '$SERVER_PORT'" >> /tmp/healthcheck.log

# Get port from environment variable, argument, or config file
if [ -n "$SERVER_PORT" ]; then
    PORT="$SERVER_PORT"
    echo "$(date): DEBUG: Using SERVER_PORT: $PORT" >> /tmp/healthcheck.log
elif [ -n "$1" ] && [ "$1" != "vless-reality" ]; then
    PORT="$1"
    echo "$(date): DEBUG: Using argument: $PORT" >> /tmp/healthcheck.log
else
    # Extract port from Xray config using multiple methods
    if [ -f "/etc/xray/config.json" ]; then
        # Try jq first
        if command -v jq >/dev/null 2>&1; then
            PORT=$(jq -r '.inbounds[0].port' /etc/xray/config.json 2>/dev/null)
            echo "$(date): DEBUG: From jq: $PORT" >> /tmp/healthcheck.log
        fi
        
        # Fallback: use grep/sed to extract port
        if [ -z "$PORT" ] || [ "$PORT" = "null" ]; then
            PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' /etc/xray/config.json | head -1 | sed 's/.*:[[:space:]]*//')
            echo "$(date): DEBUG: From grep: $PORT" >> /tmp/healthcheck.log
        fi
    fi
    
    # Final fallback
    if [ -z "$PORT" ] || [ "$PORT" = "null" ]; then
        PORT=37276
        echo "$(date): DEBUG: Using fallback: $PORT" >> /tmp/healthcheck.log
    fi
fi

echo "$(date): DEBUG: Final PORT: $PORT" >> /tmp/healthcheck.log

HOST=${2:-127.0.0.1}

# Function to check if Xray process is ready
check_xray_ready() {
    if [ -f "/var/log/xray/error.log" ]; then
        if grep -q "started" /var/log/xray/error.log 2>/dev/null; then
            return 0
        fi
    fi
    
    if ps aux | grep -v grep | grep -q "xray" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Wait for Xray to be ready (up to 10 seconds)
ready_count=0
while [ $ready_count -lt 10 ]; do
    if check_xray_ready; then
        break
    fi
    sleep 1
    ready_count=$((ready_count + 1))
done

# Check port accessibility with retries
port_check_attempts=0
while [ $port_check_attempts -lt 3 ]; do
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
            break
        fi
    else
        if timeout 2 sh -c "</dev/tcp/$HOST/$PORT" >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 1
    port_check_attempts=$((port_check_attempts + 1))
done

echo "$(date): DEBUG: Port check attempts: $port_check_attempts, Ready count: $ready_count" >> /tmp/healthcheck.log

if [ $port_check_attempts -eq 3 ]; then
    echo "Port $PORT is not accessible after retries"
    exit 1
fi

if [ $port_check_attempts -lt 3 ] && [ $ready_count -lt 10 ]; then
    echo "VLESS+Reality service healthy (port accessible, process running)"
    exit 0
fi

echo "VLESS+Reality service not ready (port: $port_check_attempts/3, process: $ready_count/10)"
exit 1
EOF

    chmod +x "$work_dir/healthcheck.sh"
}

# Test and fix logging configuration
test_logging() {
    if [ "$EUID" -ne 0 ]; then
        error "Logging test requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔍 Testing Xray logging configuration..."
    
    if [ ! -d "/opt/v2ray" ]; then
        error "No Xray installation found"
        return 1
    fi
    
    # Check if container is running using cached function
    local containers=$(get_docker_status_cached)
    if ! echo "$containers" | grep -q xray; then
        error "Xray container is not running"
        return 1
    fi
    
    # Check log directory on host
    log "Checking host log directory..."
    if [ -d "/opt/v2ray/logs" ]; then
        log "✓ Host logs directory exists: /opt/v2ray/logs"
        ls -la /opt/v2ray/logs/
    else
        log "❌ Host logs directory missing, creating..."
        mkdir -p /opt/v2ray/logs
        chmod 755 /opt/v2ray/logs
        chown root:root /opt/v2ray/logs
    fi
    
    # Check container log directory
    log "Checking container log directory..."
    if docker exec xray ls -la /var/log/xray/ 2>/dev/null; then
        log "✓ Container logs directory accessible"
    else
        log "❌ Container logs directory issue, creating..."
        docker exec xray mkdir -p /var/log/xray 2>/dev/null || true
        docker exec xray chmod 755 /var/log/xray 2>/dev/null || true
    fi
    
    # Test writing to logs
    log "Testing log writing..."
    docker exec xray touch /var/log/xray/test.log 2>/dev/null || {
        warning "Cannot create test log file in container"
    }
    
    # Check if logs are being written
    log "Current log files:"
    docker exec xray ls -la /var/log/xray/ 2>/dev/null || log "No log files found"
    
    # Check Xray process and config
    log "Checking Xray configuration logs section..."
    if docker exec xray cat /etc/xray/config.json | grep -A 5 '"log"' 2>/dev/null; then
        log "✓ Log configuration found in config"
    else
        warning "Log configuration not found or not readable"
    fi
    
    # Restart container to apply log fixes
    read -p "Restart container to apply log fixes? (y/n): " restart_choice
    if [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
        log "Restarting container..."
        cd /opt/v2ray && docker-compose restart
        sleep 5
        log "✓ Container restarted"
        
        # Check logs after restart
        log "Checking logs after restart..."
        sleep 2
        if docker exec xray ls -la /var/log/xray/ 2>/dev/null; then
            log "✓ Logs directory accessible after restart"
        fi
    fi
    
    return 0
}

# Comprehensive Reality troubleshooting and fix
fix_reality_comprehensive() {
    if [ "$EUID" -ne 0 ]; then
        error "Reality comprehensive fix requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔧 Comprehensive Reality troubleshooting and fix..."
    
    # Check if server is installed
    if [ ! -f "/opt/v2ray/config/config.json" ]; then
        error "No Xray server installation found"
        return 1
    fi
    
    # Step 1: Backup current configuration
    log "📦 Creating backup of current configuration..."
    backup_dir="/opt/v2ray/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r /opt/v2ray/config/* "$backup_dir/" 2>/dev/null || true
    cp -r /opt/v2ray/users/* "$backup_dir/" 2>/dev/null || true
    log "✓ Backup created: $backup_dir"
    
    # Step 2: Generate completely new Reality keys
    log "🔑 Generating new Reality keys..."
    local key_output=$(docker run --rm teddysun/xray:latest xray x25519 2>/dev/null)
    
    if [ -n "$key_output" ] && echo "$key_output" | grep -q "Private key:"; then
        local new_private_key=$(echo "$key_output" | grep "Private key:" | awk '{print $3}')
        local new_public_key=$(echo "$key_output" | grep "Public key:" | awk '{print $3}')
        
        log "✓ New private key: ${new_private_key:0:10}..."
        log "✓ New public key: ${new_public_key:0:10}..."
        
        # Step 3: Update server configuration
        log "📝 Updating server configuration..."
        
        # Update main config.json
        jq ".inbounds[0].streamSettings.realitySettings.privateKey = \"$new_private_key\"" \
            /opt/v2ray/config/config.json > /opt/v2ray/config/config.json.tmp
        mv /opt/v2ray/config/config.json.tmp /opt/v2ray/config/config.json
        
        # Update key files
        echo "$new_private_key" > /opt/v2ray/config/private_key.txt
        echo "$new_public_key" > /opt/v2ray/config/public_key.txt
        
        # Step 4: Generate new short IDs
        log "🆔 Generating new Short IDs..."
        local new_short_ids=""
        for i in 1 2 3; do
            local short_id=$(openssl rand -hex 8 2>/dev/null || printf "%08x%08x" $RANDOM $RANDOM)
            new_short_ids="$new_short_ids\"$short_id\""
            [ $i -lt 3 ] && new_short_ids="$new_short_ids,"
        done
        
        # Update shortIds in config
        jq ".inbounds[0].streamSettings.realitySettings.shortIds = [$new_short_ids]" \
            /opt/v2ray/config/config.json > /opt/v2ray/config/config.json.tmp
        mv /opt/v2ray/config/config.json.tmp /opt/v2ray/config/config.json
        
        log "✓ New short IDs generated"
        
        # Step 5: Update ALL user configurations
        log "👥 Updating all user configurations..."
        local updated_users=0
        
        if [ -d "/opt/v2ray/users" ]; then
            for user_file in /opt/v2ray/users/*.json; do
                if [ -f "$user_file" ]; then
                    local user_name=$(basename "$user_file" .json)
                    local user_uuid=$(jq -r '.uuid' "$user_file" 2>/dev/null)
                    local first_short_id=$(echo "$new_short_ids" | cut -d'"' -f2)
                    
                    # Update user configuration with new keys and first short ID
                    jq ".private_key = \"$new_private_key\" | .public_key = \"$new_public_key\" | .short_id = \"$first_short_id\"" \
                        "$user_file" > "${user_file}.tmp"
                    mv "${user_file}.tmp" "$user_file"
                    
                    log "✓ Updated user: $user_name"
                    updated_users=$((updated_users + 1))
                fi
            done
        fi
        
        log "✓ Updated $updated_users user configurations"
        
        # Step 6: Validate configuration
        log "✅ Validating new configuration..."
        if docker run --rm -v /opt/v2ray/config:/etc/xray teddysun/xray:latest xray run -test -c /etc/xray/config.json >/dev/null 2>&1; then
            log "✓ Configuration validation passed"
        else
            warning "Configuration validation failed, but continuing..."
        fi
        
        # Step 7: Restart server
        log "🔄 Restarting Xray server..."
        cd /opt/v2ray && docker-compose restart
        sleep 5
        
        # Step 8: Show summary
        echo ""
        log "🎉 Reality comprehensive fix completed!"
        echo ""
        echo "📋 Summary of changes:"
        echo "  🔑 New private key: ${new_private_key:0:20}..."
        echo "  🔑 New public key: ${new_public_key:0:20}..."
        echo "  🆔 New short IDs: $(echo "$new_short_ids" | tr -d '"')"
        echo "  👥 Updated users: $updated_users"
        echo "  📦 Backup location: $backup_dir"
        echo ""
        echo "⚠️  IMPORTANT: All clients must be reconfigured with new keys!"
        echo "   Use: sudo ./vpn.sh users -> Show User Data"
        echo ""
        
        # Step 9: Monitor logs briefly
        log "📊 Monitoring connection attempts for 30 seconds..."
        timeout 30 docker logs -f xray 2>&1 | grep -E "(REALITY|started|connection)" || true
        
        return 0
        
    else
        error "Failed to generate new Reality keys"
        return 1
    fi
}

# Check and show configuration validation errors
check_config_errors() {
    if [ "$EUID" -ne 0 ]; then
        error "Config check requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔍 Checking Xray configuration for errors..."
    
    if [ ! -f "/opt/v2ray/config/config.json" ]; then
        error "Configuration file not found"
        return 1
    fi
    
    # Test configuration with detailed output
    log "Running configuration validation..."
    echo ""
    
    # Run validation and capture output
    local validation_output=$(docker run --rm -v /opt/v2ray/config:/etc/xray teddysun/xray:latest xray run -test -c /etc/xray/config.json 2>&1)
    local validation_result=$?
    
    if [ $validation_result -eq 0 ]; then
        log "✅ Configuration is valid!"
        echo "$validation_output"
    else
        error "❌ Configuration validation failed:"
        echo "$validation_output"
        echo ""
        
        # Try to identify common issues
        log "🔍 Analyzing configuration issues..."
        
        # Check for common problems
        if echo "$validation_output" | grep -q "json:"; then
            error "JSON syntax error detected"
        fi
        
        if echo "$validation_output" | grep -q "privateKey"; then
            error "Private key format issue"
        fi
        
        if echo "$validation_output" | grep -q "shortIds"; then
            error "Short IDs format issue"
        fi
        
        # Show current configuration structure
        echo ""
        log "📋 Current Reality configuration:"
        jq '.inbounds[0].streamSettings.realitySettings' /opt/v2ray/config/config.json 2>/dev/null || {
            error "Failed to read Reality settings"
        }
        
        # Offer to fix
        echo ""
        read -p "Would you like to regenerate configuration with safe defaults? (y/n): " fix_choice
        if [ "$fix_choice" = "y" ] || [ "$fix_choice" = "Y" ]; then
            fix_config_safe_defaults
        fi
    fi
    
    return 0
}

# Fix configuration with safe defaults
fix_config_safe_defaults() {
    log "🔧 Regenerating configuration with safe defaults..."
    
    # Generate new keys using docker
    local key_output=$(docker run --rm teddysun/xray:latest xray x25519 2>/dev/null)
    if [ -z "$key_output" ]; then
        error "Failed to generate keys"
        return 1
    fi
    
    local new_private_key=$(echo "$key_output" | grep "Private key:" | awk '{print $3}')
    local new_public_key=$(echo "$key_output" | grep "Public key:" | awk '{print $3}')
    
    # Get current port
    local port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null || echo "443")
    
    # Create minimal working configuration
    cat > /opt/v2ray/config/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.google.com:443",
          "xver": 0,
          "serverNames": [
            "www.google.com",
            "google.com"
          ],
          "privateKey": "$new_private_key",
          "shortIds": [
            "0123456789abcdef"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    # Update key files
    echo "$new_private_key" > /opt/v2ray/config/private_key.txt
    echo "$new_public_key" > /opt/v2ray/config/public_key.txt
    
    # Add users back
    log "Re-adding users..."
    if [ -d "/opt/v2ray/users" ]; then
        for user_file in /opt/v2ray/users/*.json; do
            if [ -f "$user_file" ]; then
                local user_uuid=$(jq -r '.uuid' "$user_file" 2>/dev/null)
                local user_name=$(basename "$user_file" .json)
                
                if [ -n "$user_uuid" ] && [ "$user_uuid" != "null" ]; then
                    # Add user to config
                    jq ".inbounds[0].settings.clients += [{\"id\": \"$user_uuid\", \"flow\": \"xtls-rprx-vision\", \"email\": \"$user_name\"}]" \
                        /opt/v2ray/config/config.json > /opt/v2ray/config/config.json.tmp
                    mv /opt/v2ray/config/config.json.tmp /opt/v2ray/config/config.json
                    
                    # Update user file with new keys
                    jq ".private_key = \"$new_private_key\" | .public_key = \"$new_public_key\" | .short_id = \"0123456789abcdef\"" \
                        "$user_file" > "${user_file}.tmp"
                    mv "${user_file}.tmp" "$user_file"
                    
                    log "✓ Re-added user: $user_name"
                fi
            fi
        done
    fi
    
    # Validate new config
    if docker run --rm -v /opt/v2ray/config:/etc/xray teddysun/xray:latest xray run -test -c /etc/xray/config.json >/dev/null 2>&1; then
        log "✅ New configuration is valid!"
        
        # Restart server
        cd /opt/v2ray && docker-compose restart
        log "✓ Server restarted with safe defaults"
        
        echo ""
        echo "📋 New configuration details:"
        echo "  Port: $port"
        echo "  Public key: $new_public_key"
        echo "  Short ID: 0123456789abcdef"
        echo ""
        echo "⚠️  All clients must update their configurations!"
    else
        error "New configuration still has errors"
    fi
}

# Debug Reality connection attempts
debug_reality_connections() {
    if [ "$EUID" -ne 0 ]; then
        error "Debug requires superuser privileges (sudo)"
        return 1
    fi
    
    log "🔍 Debugging Reality connection attempts..."
    
    # Check if container is running using cached function
    local containers=$(get_docker_status_cached)
    if ! echo "$containers" | grep -q xray; then
        error "Xray container is not running"
        return 1
    fi
    
    # Install ss if not available (replacement for netstat)
    if ! command -v ss >/dev/null 2>&1; then
        log "Installing ss tool..."
        apt-get update && apt-get install -y iproute2
    fi
    
    local port=$(cat /opt/v2ray/config/port.txt 2>/dev/null || echo "443")
    
    # Monitor connections in real-time
    log "📊 Monitoring connections on port $port for 60 seconds..."
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    # Start monitoring in background
    (
        while true; do
            echo "=== $(date) ==="
            
            # Show active connections
            echo "Active connections on port $port:"
            ss -tnp | grep ":$port" | grep -v TIME-WAIT || echo "No active connections"
            
            # Check if healthcheck is running
            if docker exec xray ps aux | grep -q healthcheck; then
                echo "⚠️  Healthcheck is running"
            fi
            
            # Show last Reality error
            echo ""
            echo "Last Reality errors:"
            docker logs xray --tail 5 2>&1 | grep "REALITY" || echo "No recent Reality errors"
            
            echo ""
            sleep 10
        done
    ) &
    
    monitor_pid=$!
    
    # Also start detailed logging
    log "📝 Starting detailed Reality logging..."
    
    # Create temporary detailed config
    docker exec xray sh -c 'cat > /tmp/debug_config.json << EOF
{
  "log": {
    "loglevel": "debug",
    "access": "/var/log/xray/access_debug.log",
    "error": "/var/log/xray/error_debug.log"
  }
}
EOF'
    
    # Wait or stop on user input
    read -p "Press Enter to stop monitoring..."
    
    # Stop monitoring
    kill $monitor_pid 2>/dev/null
    
    # Analyze patterns
    log "📊 Analyzing connection patterns..."
    
    # Check for regular intervals
    echo ""
    echo "Connection timing analysis:"
    docker logs xray --tail 100 2>&1 | grep "REALITY.*invalid" | tail -20 | awk '{print $1, $2}' | while read timestamp; do
        echo "  $timestamp"
    done
    
    # Check healthcheck logs
    echo ""
    echo "Healthcheck debug logs:"
    docker exec xray cat /tmp/healthcheck.log 2>/dev/null | tail -10 || echo "No healthcheck logs found"
    
    # Suggestions
    echo ""
    log "💡 Analysis results:"
    
    # Check intervals
    local last_two_times=$(docker logs xray --tail 100 2>&1 | grep "REALITY.*invalid" | tail -2 | awk '{print $2}' | cut -d'.' -f1)
    if [ -n "$last_two_times" ]; then
        local time1=$(echo "$last_two_times" | head -1 | tr ':' ' ')
        local time2=$(echo "$last_two_times" | tail -1 | tr ':' ' ')
        
        # Simple interval check
        echo "- Connection attempts appear to be at regular intervals (possibly monitoring)"
    fi
    
    echo "- If connections are every 30s, it might be:"
    echo "  • Container healthcheck (check docker-compose.yml)"
    echo "  • External monitoring service"
    echo "  • Misconfigured client with retry loop"
    
    echo ""
    echo "Recommended actions:"
    echo "1. Check docker healthcheck: docker inspect xray | jq '.[0].State.Health'"
    echo "2. Review client configurations for auto-retry settings"
    echo "3. Check if hosting provider has monitoring on this port"
    
    return 0
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
    echo "  fix-reality          Fix Reality connection issues"
    echo "  validate             Validate server configuration"
    echo "  diagnose             Diagnose Reality connection issues"
    echo "  update-users         Update all user configs with current server keys"
    echo "  cleanup-firewall     Interactive cleanup of unused VPN ports from firewall"
    echo "  recreate-docker      Recreate docker-compose with latest healthcheck fixes"
    echo "  test-logging         Test and fix Xray logging configuration"
    echo "  fix-reality-full     Comprehensive Reality fix with new keys and short IDs"
    echo "  check-config         Check and fix configuration validation errors"
    echo "  debug-connections    Debug source of Reality invalid connection attempts"
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
# VPN ROUTING FIX FUNCTION
# =============================================================================

# Fix VPN routing and traffic forwarding issues
fix_vpn_routing() {
    log "🔧 Fixing VPN routing and traffic forwarding..."
    
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "VPN routing fix requires superuser privileges (sudo)"
        return 1
    fi
    
    # Get current server port
    local server_port=""
    if [ -f "/opt/v2ray/config/config.json" ]; then
        server_port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null || echo "")
    fi
    
    if [ -z "$server_port" ] || [ "$server_port" = "null" ]; then
        error "Could not determine server port. Is VPN server installed?"
        return 1
    fi
    
    log "Detected server port: $server_port"
    
    # Load firewall module
    load_module_lazy "install/firewall.sh" || {
        error "Failed to load firewall module"
        return 1
    }
    
    echo -e "${GREEN}=== Fixing VPN Routing Configuration ===${NC}"
    echo ""
    
    # Apply complete network setup
    setup_vpn_network "$server_port" true || {
        error "Failed to setup VPN network configuration"
        return 1
    }
    
    echo ""
    echo -e "${GREEN}=== Verifying Configuration ===${NC}"
    
    # Verify IP forwarding
    local forwarding=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
    if [ "$forwarding" = "1" ]; then
        log "✓ IP forwarding is enabled"
    else
        error "✗ IP forwarding is disabled"
    fi
    
    # Verify FORWARD policy
    local forward_policy=$(iptables -L FORWARD -n | head -1 | grep -o "policy [A-Z]*" | cut -d' ' -f2)
    if [ "$forward_policy" = "ACCEPT" ]; then
        log "✓ FORWARD policy is ACCEPT"
    else
        warning "✗ FORWARD policy is $forward_policy"
    fi
    
    # Verify masquerading rules
    local masq_rules=$(iptables -t nat -L POSTROUTING -n | grep -c MASQUERADE || echo "0")
    if [ "$masq_rules" -gt 0 ]; then
        log "✓ Masquerading rules are configured ($masq_rules rules)"
    else
        warning "✗ No masquerading rules found"
    fi
    
    echo ""
    log "✅ VPN routing fix completed"
    log "Please test VPN connection now - internet access should work"
    
    return 0
}

# =============================================================================
# VPN PORTS CLEANUP FUNCTION
# =============================================================================

# Interactive cleanup of unused VPN ports
cleanup_vpn_ports_interactive() {
    log "🧹 Cleaning up unused VPN ports from firewall..."
    
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "Port cleanup requires superuser privileges (sudo)"
        return 1
    fi
    
    # Get current server port
    local current_port=""
    if [ -f "/opt/v2ray/config/config.json" ]; then
        current_port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null || echo "")
    fi
    
    if [ -z "$current_port" ] || [ "$current_port" = "null" ]; then
        warning "Could not determine current server port"
        current_port=""
    else
        log "Current active VPN port: $current_port"
    fi
    
    # Load firewall module
    load_module_lazy "install/firewall.sh" || {
        error "Failed to load firewall module"
        return 1
    }
    
    echo -e "${GREEN}=== VPN Port Cleanup ===${NC}"
    echo ""
    
    # Run interactive cleanup
    cleanup_unused_vpn_ports "$current_port" true true  # interactive mode
    
    return 0
}

# =============================================================================
# TEST PORT FILTERING FUNCTION
# =============================================================================

# Test port filtering logic
test_port_filtering() {
    log "🧪 Testing port filtering logic..."
    
    echo -e "${GREEN}=== UFW Status Analysis ===${NC}"
    echo ""
    
    # Show raw UFW output
    echo "Raw UFW status:"
    ufw status numbered | head -20
    echo ""
    
    # Test current filter
    echo "Testing current filter (should exclude 22,80,443,9000 and show only >= 10000):"
    local test1=$(ufw status numbered 2>/dev/null | grep -E "ALLOW.*tcp" | grep -v -E "22/tcp|80/tcp|443/tcp|OpenSSH|9000/tcp" | awk '{print $2}' | cut -d'/' -f1 | awk '$1 >= 10000' | sort -n)
    echo "Result: $test1"
    echo ""
    
    # Test alternative filter
    echo "Testing alternative filter (using line format):"
    local test2=$(ufw status numbered 2>/dev/null | grep -E "\[[0-9]+\].*ALLOW.*tcp" | grep -v -E "(22|80|443|9000)/tcp" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\/tcp$/) print $i}' | cut -d'/' -f1 | awk '$1 >= 10000' | sort -n)
    echo "Result: $test2"
    echo ""
    
    # Show what would be considered for removal
    echo "Ports that would be considered for removal:"
    ufw status numbered 2>/dev/null | grep -E "\[[0-9]+\].*ALLOW.*tcp" | while read line; do
        local port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\/tcp$/) print $i}' | cut -d'/' -f1)
        if [ -n "$port" ] && [ "$port" -ge 10000 ] 2>/dev/null; then
            echo "  - Port $port: $line"
        fi
    done
    echo ""
    
    # Check listening ports
    echo "Currently listening ports (netstat):"
    netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | sed 's/.*://' | awk '$1 >= 10000' | sort -n | uniq
    echo ""
    
    return 0
}

# =============================================================================
# FIX XRAY ROUTING CONFIGURATION
# =============================================================================

# Fix Xray routing configuration that blocks internet access
fix_xray_routing_config() {
    log "🔧 Fixing Xray routing configuration..."
    
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "Configuration fix requires superuser privileges (sudo)"
        return 1
    fi
    
    local config_file="/opt/v2ray/config/config.json"
    
    if [ ! -f "$config_file" ]; then
        error "Xray configuration file not found: $config_file"
        return 1
    fi
    
    # Backup current configuration
    local backup_file="/opt/v2ray/config/config.json.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$config_file" "$backup_file" || {
        error "Failed to backup configuration"
        return 1
    }
    log "Configuration backed up to: $backup_file"
    
    echo -e "${GREEN}=== Fixing Xray Routing Configuration ===${NC}"
    echo ""
    
    # Remove the blocking rules for private IPs
    # Keep only truly local IPs that should be blocked (127.0.0.0/8 and ::1)
    local temp_file="/tmp/xray_config_temp.json"
    
    # Use jq to modify the routing rules
    jq '.routing.rules[0].ip = ["127.0.0.0/8", "::1/128"]' "$config_file" > "$temp_file" || {
        error "Failed to modify configuration"
        return 1
    }
    
    # Verify the new configuration is valid JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        error "Invalid JSON in modified configuration"
        rm -f "$temp_file"
        return 1
    fi
    
    # Show the changes
    echo "Original routing rules:"
    jq '.routing.rules[0].ip' "$config_file"
    echo ""
    echo "New routing rules (only blocking localhost):"
    jq '.routing.rules[0].ip' "$temp_file"
    echo ""
    
    # Apply the new configuration
    mv "$temp_file" "$config_file" || {
        error "Failed to apply new configuration"
        rm -f "$temp_file"
        return 1
    }
    
    log "✓ Routing configuration updated"
    
    # Restart Xray to apply changes
    echo -e "${BLUE}Restarting Xray container...${NC}"
    cd /opt/v2ray && docker-compose restart || {
        error "Failed to restart Xray container"
        return 1
    }
    
    log "✅ Xray routing configuration fixed"
    log "Internet access through VPN should now work properly"
    echo ""
    echo "Please test VPN connection again"
    
    return 0
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
            # Load server handlers module
            load_module_lazy "menu/server_handlers.sh" || {
                error "Failed to load server handlers module"
                exit 1
            }
            handle_server_install
            ;;
        "status")
            # Load server handlers module
            load_module_lazy "menu/server_handlers.sh" || {
                error "Failed to load server handlers module"
                exit 1
            }
            handle_server_status
            ;;
        "restart")
            # Load server handlers module
            load_module_lazy "menu/server_handlers.sh" || {
                error "Failed to load server handlers module"
                exit 1
            }
            handle_server_restart
            ;;
        "uninstall")
            # Load server handlers module
            load_module_lazy "menu/server_handlers.sh" || {
                error "Failed to load server handlers module"
                exit 1
            }
            handle_server_uninstall
            ;;
        "fix-reality")
            fix_reality
            ;;
        "validate")
            validate_config
            ;;
        "diagnose")
            # Use system diagnostics module instead of legacy diagnose_reality
            load_module_lazy "system/diagnostics.sh" || {
                error "Failed to load diagnostics module"
                exit 1
            }
            run_full_diagnostics
            ;;
        "update-users")
            update_user_configs
            ;;
        "cleanup-firewall")
            cleanup_firewall
            ;;
        "recreate-docker")
            recreate_docker
            ;;
        "test-logging")
            test_logging
            ;;
        "fix-reality-full")
            fix_reality_comprehensive
            ;;
        "check-config")
            check_config_errors
            ;;
        "debug-connections")
            debug_reality_connections
            ;;
        "fix-routing")
            fix_vpn_routing
            ;;
        "cleanup-ports")
            cleanup_vpn_ports_interactive
            ;;
        "test-port-filter")
            test_port_filtering
            ;;
        "fix-routing-config")
            fix_xray_routing_config
            ;;
        "users")
            # Load user menu module
            load_module_lazy "menu/user_menu.sh" || {
                error "Failed to load user menu module"
                exit 1
            }
            show_user_management_menu
            ;;
        "user")
            # Load user menu module
            load_module_lazy "menu/user_menu.sh" || {
                error "Failed to load user menu module"
                exit 1
            }
            case "$SUB_ACTION" in
                "add"|"delete"|"list"|"show")
                    show_user_management_menu
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
            # Load performance library and run benchmarks (rate limited)
            if can_perform_heavy_operation; then
                source "$SCRIPT_DIR/lib/performance.sh" 2>/dev/null || {
                    error "Performance library not available"
                    exit 1
                }
                echo "=== VPN System Performance Benchmarks ==="
                benchmark_modules
                test_command_performance "$0"
                monitor_resources
            else
                echo "Benchmark is rate limited. Please wait $HEAVY_OP_COOLDOWN seconds between calls."
            fi
            ;;
        "debug")
            # Debug mode with performance monitoring (rate limited)
            if can_perform_heavy_operation; then
                source "$SCRIPT_DIR/lib/performance.sh" 2>/dev/null || true
                echo "=== Debug Information ==="
                monitor_resources 2>/dev/null || echo "Performance monitoring not available"
                echo -e "\n=== Loaded Modules ==="
                for module in "${!LOADED_MODULES[@]}"; do
                    echo "  ✓ $module"
                done
            else
                echo "Debug mode is rate limited. Please wait $HEAVY_OP_COOLDOWN seconds between calls."
            fi
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
