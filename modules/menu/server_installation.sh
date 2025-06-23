#!/bin/bash

# =============================================================================
# Server Installation Handler Module
# 
# This module handles VPN server installation process.
# Follows modular architecture and optimization principles.
#
# Functions exported:
# - run_server_installation()
# - select_vpn_protocol()
# - get_port_config_interactive()
# - get_user_config_interactive()
# - setup_docker_xray()
# - setup_outline_server()
# - setup_firewall()
#
# Dependencies: lib/common.sh, modules/install/*
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
# LAZY MODULE LOADING (Optimization)
# =============================================================================

# Module loading cache
declare -A LOADED_MODULES

# Load module with lazy loading optimization
load_module_lazy() {
    local module="$1"
    local module_path="${PROJECT_ROOT:-$MODULE_DIR/../..}/modules/$module"
    
    [ -z "${LOADED_MODULES[$module]}" ] && {
        source "$module_path" || {
            error "Failed to load module: $module"
            return 1
        }
        LOADED_MODULES[$module]=1
        log "Lazy loaded module: $module"
    }
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Cleanup Outline firewall rules safely
cleanup_outline_firewall_rules() {
    if ! command -v ufw >/dev/null 2>&1; then
        log "UFW not available, skipping firewall cleanup"
        return 0
    fi
    
    log "Cleaning up Outline firewall rules..."
    
    # Get current firewall status
    local ufw_status
    ufw_status=$(ufw status numbered 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$ufw_status" ]; then
        # Look for rules containing port 9000 (default Outline management port)
        echo "$ufw_status" | grep -E "\[[0-9]+\].*9000" | sed 's/\[\([0-9]*\).*/\1/' | sort -rn | while read -r num; do
            if [ -n "$num" ] && [[ "$num" =~ ^[0-9]+$ ]]; then
                log "Removing firewall rule #$num (port 9000)"
                ufw --force delete "$num" 2>/dev/null || log "Failed to remove rule #$num"
            fi
        done
        
        # Look for rules containing custom management ports (if OUTLINE_API_PORT is set and not 9000)
        if [ -n "$OUTLINE_API_PORT" ] && [ "$OUTLINE_API_PORT" != "9000" ]; then
            echo "$ufw_status" | grep -E "\[[0-9]+\].*$OUTLINE_API_PORT" | sed 's/\[\([0-9]*\).*/\1/' | sort -rn | while read -r num; do
                if [ -n "$num" ] && [[ "$num" =~ ^[0-9]+$ ]]; then
                    log "Removing firewall rule #$num (custom management port $OUTLINE_API_PORT)"
                    ufw --force delete "$num" 2>/dev/null || log "Failed to remove rule #$num"
                fi
            done
        fi
        
        # Look for rules with "Outline" in description
        echo "$ufw_status" | grep -i "outline" | sed 's/\[\([0-9]*\).*/\1/' | sort -rn | while read -r num; do
            if [ -n "$num" ] && [[ "$num" =~ ^[0-9]+$ ]]; then
                log "Removing firewall rule #$num (Outline)"
                ufw --force delete "$num" 2>/dev/null || log "Failed to remove rule #$num"
            fi
        done
        
        log "Outline firewall cleanup completed"
    else
        log "Could not get firewall status, skipping cleanup"
    fi
    
    return 0
}

# =============================================================================
# MAIN INSTALLATION FUNCTION 
# =============================================================================

# Main server installation function with optimizations
run_server_installation() {
    local start_time=$(date +%s.%N)
    
    # Ensure we're in a valid working directory
    if ! pwd >/dev/null 2>&1; then
        cd "${PROJECT_ROOT:-/home/ikeniborn/Documents/Project/vpn}" || {
            cd /tmp
            warning "Working directory issue detected, switched to /tmp"
        }
    fi
    
    log "Starting VPN server installation process..."
    
    # Check system requirements
    echo -e "${BLUE}=== VPN Server Installation ===${NC}\n"
    
    # Step 1: Install dependencies
    echo -e "${YELLOW}Step 1: Installing system dependencies...${NC}"
    log "Starting system dependencies installation..."
    
    # Lazy load prerequisites module
    load_module_lazy "install/prerequisites.sh" || return 1
    
    if ! install_system_dependencies true; then
        error "Failed to install system dependencies"
        error "Check above logs for specific package installation errors"
        return 1
    fi
    log "System dependencies installed successfully"
    
    # Step 1.5: Verify dependencies
    echo -e "${YELLOW}Step 1.5: Verifying dependencies...${NC}"
    log "Verifying all required dependencies are available..."
    if ! verify_dependencies true; then
        error "Dependency verification failed"
        error "Some required tools are missing. Please check the installation logs above."
        return 1
    fi
    log "All dependencies verified successfully"
    
    # Step 2: Protocol selection
    echo -e "\n${YELLOW}Step 2: Select VPN Protocol${NC}"
    log "Starting protocol selection process..."
    if ! select_vpn_protocol; then
        error "Protocol selection failed"
        error "User failed to select a valid protocol or process was interrupted"
        return 1
    fi
    log "Protocol selection completed: $PROTOCOL"
    
    # Step 3: Check existing installations
    echo -e "\n${YELLOW}Step 3: Checking for existing installations...${NC}"
    log "Checking for existing $PROTOCOL installations..."
    if ! check_existing_vpn_installation "$PROTOCOL"; then
        error "Installation check failed"
        error "Failed to check for existing installations or user cancelled"
        return 1
    fi
    log "Installation check completed"
    
    # Step 4: Configure protocol-specific settings
    echo -e "\n${YELLOW}Step 4: Configuring $PROTOCOL settings...${NC}"
    case "$PROTOCOL" in
        "vless-reality")
            # Configure VLESS+Reality
            configure_vless_reality || return 1
            ;;
        "outline")
            # Configure Outline VPN
            configure_outline_vpn || return 1
            ;;
        *)
            error "Unsupported protocol: $PROTOCOL"
            return 1
            ;;
    esac
    
    # Step 5: Setup firewall
    echo -e "\n${YELLOW}Step 5: Configuring firewall...${NC}"
    log "Starting firewall configuration..."
    if ! setup_firewall; then
        error "Firewall setup failed"
        error "Failed to configure UFW firewall rules"
        return 1
    fi
    log "Firewall configuration completed successfully"
    
    # Step 6: Show results
    echo -e "\n${YELLOW}Step 6: Installation complete!${NC}"
    log "Showing installation results..."
    show_installation_results
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    log "VPN server installation completed successfully in ${duration}s"
    return 0
}

# =============================================================================
# PROTOCOL CONFIGURATION FUNCTIONS
# =============================================================================

# Configure VLESS+Reality protocol
configure_vless_reality() {
    # SNI configuration
    log "Starting SNI domain configuration..."
    if ! get_sni_config_interactive; then
        error "SNI configuration failed"
        error "Failed to configure SNI domain or user cancelled"
        return 1
    fi
    log "SNI configuration completed: $SERVER_SNI"
    
    # Port configuration
    log "Starting port configuration..."
    if ! get_port_config_interactive; then
        error "Port configuration failed"
        error "Failed to configure server port or user cancelled"
        return 1
    fi
    log "Port configuration completed: $SERVER_PORT"
    
    # User name configuration
    log "Starting user configuration..."
    if ! get_user_config_interactive; then
        error "User configuration failed"
        error "Failed to configure first user or user cancelled"
        return 1
    fi
    log "User configuration completed: $USER_NAME"
    
    # IP address configuration
    log "Starting IP address configuration..."
    # Ensure network library is loaded
    if ! command -v select_server_ip >/dev/null 2>&1; then
        local lib_path="${PROJECT_ROOT:-$MODULE_DIR/../..}/lib/network.sh"
        source "$lib_path" || {
            error "Failed to load network library from $lib_path"
            return 1
        }
    fi
    
    if ! select_server_ip; then
        error "IP address configuration failed"
        error "Failed to configure server IP address"
        return 1
    fi
    log "IP address configuration completed: $SERVER_IP"
    
    # Reality keys generation
    echo -e "\n${YELLOW}Generating Reality encryption keys...${NC}"
    log "Starting Reality key generation..."
    
    # Ensure crypto functions are available
    if ! command -v generate_reality_keys >/dev/null 2>&1; then
        source "$PROJECT_ROOT/lib/crypto.sh" || {
            error "Failed to load crypto library"
            return 1
        }
    fi
    
    # Generate Reality keys using crypto library
    log "Calling generate_reality_keys function..."
    local reality_keys=$(generate_reality_keys)
    local gen_result=$?
    
    log "Generation result: $gen_result"
    log "Raw keys output: '$reality_keys'"
    
    if [ $gen_result -eq 0 ] && [ -n "$reality_keys" ]; then
        # Extract all three values
        PRIVATE_KEY=$(echo "$reality_keys" | awk '{print $1}')
        PUBLIC_KEY=$(echo "$reality_keys" | awk '{print $2}')
        SHORT_ID=$(echo "$reality_keys" | awk '{print $3}')
        
        log "Extracted values:"
        log "  PRIVATE_KEY: '${PRIVATE_KEY:0:10}...'"
        log "  PUBLIC_KEY: '${PUBLIC_KEY:0:10}...'"
        log "  SHORT_ID: '$SHORT_ID'"
    else
        error "Failed to generate Reality keys (exit code: $gen_result)"
        return 1
    fi
    
    # Verify all keys were generated
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
        error "Failed to extract Reality keys"
        error "PRIVATE_KEY empty: $([ -z "$PRIVATE_KEY" ] && echo "yes" || echo "no")"
        error "PUBLIC_KEY empty: $([ -z "$PUBLIC_KEY" ] && echo "yes" || echo "no")"
        error "SHORT_ID empty: $([ -z "$SHORT_ID" ] && echo "yes" || echo "no")"
        error "Raw keys output: '$reality_keys'"
        return 1
    fi
    
    log "Reality keys generated successfully: Private key ${PRIVATE_KEY:0:10}..., Public key ${PUBLIC_KEY:0:10}..., Short ID: $SHORT_ID"
    
    # Export all configuration variables for use in other functions
    export PROTOCOL
    export WORK_DIR
    export SERVER_PORT
    export SERVER_SNI
    export USER_NAME
    export USER_UUID
    export SERVER_IP
    export PRIVATE_KEY
    export PUBLIC_KEY
    export SHORT_ID
    
    # Final configuration display
    show_final_configuration
    
    # Create Xray configuration
    echo -e "\n${YELLOW}Setting up Xray server...${NC}"
    log "Starting Xray configuration creation..."
    if ! create_xray_config_and_user; then
        error "Xray configuration creation failed"
        error "Failed to create Xray config files, check parameters above"
        return 1
    fi
    log "Xray configuration created successfully"
    
    # Setup Docker containers
    echo -e "\n${YELLOW}Setting up Docker containers...${NC}"
    log "Starting Docker environment setup..."
    if ! setup_docker_xray; then
        error "Docker setup failed"
        error "Failed to setup Docker containers, check Docker status"
        return 1
    fi
    log "Docker environment setup completed"
    
    return 0
}

# Configure Outline VPN protocol
configure_outline_vpn() {
    # Management port configuration for Outline
    log "Starting management port configuration for Outline..."
    if ! get_outline_management_port_config; then
        error "Management port configuration failed"
        error "Failed to configure management port or user cancelled"
        return 1
    fi
    log "Management port configuration completed: $OUTLINE_API_PORT"
    
    # VPN port configuration for Outline
    log "Starting VPN port configuration for Outline..."
    if ! get_outline_port_config_interactive; then
        error "VPN port configuration failed"
        error "Failed to configure server port or user cancelled"
        return 1
    fi
    log "VPN port configuration completed: $SERVER_PORT"
    
    # IP address configuration
    log "Starting IP address configuration..."
    # Ensure network library is loaded
    if ! command -v select_server_ip >/dev/null 2>&1; then
        local lib_path="${PROJECT_ROOT:-$MODULE_DIR/../..}/lib/network.sh"
        source "$lib_path" || {
            error "Failed to load network library from $lib_path"
            return 1
        }
    fi
    
    if ! select_server_ip; then
        error "IP address configuration failed"
        error "Failed to configure server IP address"
        return 1
    fi
    log "IP address configuration completed: $SERVER_IP"
    
    echo -e "\n${YELLOW}Setting up Outline VPN server...${NC}"
    log "Starting Outline server setup..."
    if ! setup_outline_server; then
        error "Outline setup failed"
        return 1
    fi
    log "Outline server setup completed"
    return 0
}

# Show final configuration before installation
show_final_configuration() {
    echo -e "\n${GREEN}=== Final Configuration ===${NC}"
    echo -e "${BLUE}Protocol:${NC} $PROTOCOL"
    echo -e "${BLUE}Server IP:${NC} $SERVER_IP"
    echo -e "${BLUE}Server Port:${NC} $SERVER_PORT"
    
    # Show protocol-specific configuration
    if [ "$PROTOCOL" = "vless-reality" ]; then
        echo -e "${BLUE}SNI Domain:${NC} $SERVER_SNI"
        echo -e "${BLUE}First User:${NC} $USER_NAME"
        echo -e "${BLUE}Private Key:${NC} ${PRIVATE_KEY:0:10}..."
        echo -e "${BLUE}Public Key:${NC} ${PUBLIC_KEY:0:10}..."
        echo -e "${BLUE}Short ID:${NC} $SHORT_ID"
    elif [ "$PROTOCOL" = "outline" ]; then
        echo -e "${BLUE}Management Port:${NC} $OUTLINE_API_PORT"
        echo -e "${BLUE}Management URL:${NC} https://$SERVER_IP:$OUTLINE_API_PORT"
    fi
}

# =============================================================================
# INSTALLATION CHECKING FUNCTIONS
# =============================================================================

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
            local outline_dir="${OUTLINE_DIR:-/opt/outline}"
            if [ -d "$outline_dir" ] || docker ps -a --format "table {{.Names}}" | grep -q "shadowbox"; then
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
                    export REINSTALL_MODE=true
                    
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
                            echo -e "${YELLOW}Stopping Outline containers...${NC}"
                            if docker ps | grep -q "shadowbox"; then
                                docker stop shadowbox 2>/dev/null || true
                            fi
                            if docker ps | grep -q "watchtower"; then
                                docker stop watchtower 2>/dev/null || true
                            fi
                            echo -e "${YELLOW}Removing Outline containers...${NC}"
                            docker rm -f shadowbox watchtower 2>/dev/null || true
                            echo -e "${YELLOW}Removing Outline directories...${NC}"
                            rm -rf "${outline_dir}" 2>/dev/null || true
                            echo -e "${YELLOW}Cleaning up firewall rules...${NC}"
                            cleanup_outline_firewall_rules
                            ;;
                    esac
                    
                    log "Existing installations removed successfully"
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

# =============================================================================
# INTERACTIVE CONFIGURATION FUNCTIONS
# =============================================================================

# Protocol selection with enhanced logging
select_vpn_protocol() {
    echo -e "${BLUE}Available VPN Protocols:${NC}"
    echo "1) VLESS+Reality (Recommended for security)"
    echo "2) Outline VPN (Shadowsocks-based)"
    echo ""
    
    while true; do
        read -p "Select VPN protocol (1-2): " protocol_choice
        case $protocol_choice in
            1)
                PROTOCOL="vless-reality"
                WORK_DIR="/opt/v2ray"
                export PROTOCOL WORK_DIR
                log "Selected protocol: VLESS+Reality"
                echo -e "${GREEN}Selected: VLESS+Reality Protocol${NC}"
                echo -e "${BLUE}✓ Enhanced anti-detection technology${NC}"
                echo -e "${BLUE}✓ TLS 1.3 masquerading${NC}"
                echo -e "${BLUE}✓ X25519 cryptography${NC}"
                break
                ;;
            2)
                PROTOCOL="outline"
                WORK_DIR="/opt/outline"
                export PROTOCOL WORK_DIR
                log "Selected protocol: Outline VPN"
                echo -e "${GREEN}Selected: Outline VPN Protocol${NC}"
                echo -e "${BLUE}✓ Shadowsocks-based${NC}"
                echo -e "${BLUE}✓ Easy client management${NC}"
                echo -e "${BLUE}✓ Web management interface${NC}"
                break
                ;;
            *)
                warning "Please choose 1 or 2"
                ;;
        esac
    done
    
    return 0
}

# Port configuration with improved logic
get_port_config_interactive() {
    echo -e "${BLUE}Port Configuration for Reality:${NC}"
    echo "1) Random port (10000-65000) - Recommended"
    echo "2) Standard port (10443)"
    echo "3) Custom port"
    echo ""
    
    while true; do
        read -p "Select port option (1-3): " port_choice
        case $port_choice in
            1)
                # Generate random port between 10000-65000
                SERVER_PORT=$((RANDOM % 55000 + 10000))
                export SERVER_PORT
                log "Generated random port: $SERVER_PORT"
                echo -e "${GREEN}Random port selected: $SERVER_PORT${NC}"
                break
                ;;
            2)
                SERVER_PORT="10443"
                export SERVER_PORT
                log "Selected standard port: $SERVER_PORT"
                echo -e "${GREEN}Standard port selected: $SERVER_PORT${NC}"
                break
                ;;
            3)
                while true; do
                    read -p "Enter custom port (1024-65535): " custom_port
                    if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1024 ] && [ "$custom_port" -le 65535 ]; then
                        SERVER_PORT="$custom_port"
                        export SERVER_PORT
                        log "Selected custom port: $SERVER_PORT"
                        echo -e "${GREEN}Custom port selected: $SERVER_PORT${NC}"
                        break
                    else
                        warning "Please enter a valid port number (1024-65535)"
                    fi
                done
                break
                ;;
            *)
                warning "Please choose 1, 2, or 3"
                ;;
        esac
    done
    
    return 0
}

# Management port configuration for Outline VPN
get_outline_management_port_config() {
    echo -e "${BLUE}Management Port Configuration for Outline VPN:${NC}"
    echo "1) Standard management port (9000) - Recommended"
    echo "2) Custom management port"
    echo ""
    
    # Load network library for port checking if not already loaded
    if ! command -v check_port_available >/dev/null 2>&1; then
        source "$PROJECT_ROOT/lib/network.sh" || {
            error "Failed to load network library"
            return 1
        }
    fi
    
    while true; do
        read -p "Select management port option (1-2): " mgmt_port_choice
        case $mgmt_port_choice in
            1)
                OUTLINE_API_PORT="9000"
                # Check if port is available
                if check_port_available "$OUTLINE_API_PORT"; then
                    export OUTLINE_API_PORT
                    log "Selected standard management port: $OUTLINE_API_PORT"
                    echo -e "${GREEN}Standard management port selected: $OUTLINE_API_PORT${NC}"
                    return 0
                else
                    warning "Port $OUTLINE_API_PORT is already in use!"
                    echo "Please choose custom port instead."
                fi
                ;;
            2)
                while true; do
                    read -p "Enter custom management port (1024-65535): " custom_mgmt_port
                    if [[ "$custom_mgmt_port" =~ ^[0-9]+$ ]] && [ "$custom_mgmt_port" -ge 1024 ] && [ "$custom_mgmt_port" -le 65535 ]; then
                        # Check if port is available
                        if check_port_available "$custom_mgmt_port"; then
                            OUTLINE_API_PORT="$custom_mgmt_port"
                            export OUTLINE_API_PORT
                            log "Selected custom management port: $OUTLINE_API_PORT"
                            echo -e "${GREEN}Custom management port selected: $OUTLINE_API_PORT${NC}"
                            return 0
                        else
                            warning "Port $custom_mgmt_port is already in use!"
                            echo "Please choose another port."
                        fi
                    else
                        warning "Please enter a valid port number (1024-65535)"
                    fi
                done
                ;;
            *)
                warning "Please choose 1 or 2"
                ;;
        esac
    done
}

# Port configuration for Outline VPN with conflict checking
get_outline_port_config_interactive() {
    echo -e "${BLUE}VPN Port Configuration for Outline VPN:${NC}"
    echo "1) Random port (10000-65000) - Recommended"
    echo "2) Standard port (10443)"
    echo "3) Custom port"
    echo ""
    
    # Load network library for port checking if not already loaded
    if ! command -v check_port_available >/dev/null 2>&1; then
        source "$PROJECT_ROOT/lib/network.sh" || {
            error "Failed to load network library"
            return 1
        }
    fi
    
    while true; do
        read -p "Select port option (1-3): " port_choice
        case $port_choice in
            1)
                # Generate random port and check availability
                local attempts=0
                local max_attempts=20
                while [ $attempts -lt $max_attempts ]; do
                    SERVER_PORT=$((RANDOM % 55000 + 10000))
                    if check_port_available "$SERVER_PORT"; then
                        export SERVER_PORT
                        log "Generated available random port: $SERVER_PORT"
                        echo -e "${GREEN}Random port selected: $SERVER_PORT${NC}"
                        return 0
                    fi
                    ((attempts++))
                done
                warning "Could not find available random port after $max_attempts attempts"
                echo "Please choose a custom port instead."
                ;;
            2)
                SERVER_PORT="10443"
                # Check if port is available
                if check_port_available "$SERVER_PORT"; then
                    export SERVER_PORT
                    log "Selected standard port: $SERVER_PORT"
                    echo -e "${GREEN}Standard port selected: $SERVER_PORT${NC}"
                    return 0
                else
                    warning "Port $SERVER_PORT is already in use!"
                    echo "Please choose another option."
                fi
                ;;
            3)
                while true; do
                    read -p "Enter custom port (1024-65535): " custom_port
                    if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1024 ] && [ "$custom_port" -le 65535 ]; then
                        # Check if port is available
                        if check_port_available "$custom_port"; then
                            SERVER_PORT="$custom_port"
                            export SERVER_PORT
                            log "Selected custom port: $SERVER_PORT"
                            echo -e "${GREEN}Custom port selected: $SERVER_PORT${NC}"
                            return 0
                        else
                            warning "Port $custom_port is already in use!"
                            echo "Please choose another port."
                        fi
                    else
                        warning "Please enter a valid port number (1024-65535)"
                    fi
                done
                ;;
            *)
                warning "Please choose 1, 2, or 3"
                ;;
        esac
    done
}

# User configuration
get_user_config_interactive() {
    echo -e "${BLUE}First User Configuration:${NC}"
    while true; do
        read -p "Enter username for first user: " username
        if [ -n "$username" ] && [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            USER_NAME="$username"
            log "First user configured: $USER_NAME"
            echo -e "${GREEN}User '$USER_NAME' will be created${NC}"
            break
        else
            warning "Please enter a valid username (alphanumeric, underscore, and hyphen only)"
        fi
    done
    
    return 0
}

# =============================================================================
# SETUP FUNCTIONS
# =============================================================================

# Docker setup for Xray
setup_docker_xray() {
    log "Setting up Docker environment for Xray..."
    
    # Lazy load Docker module
    load_module_lazy "install/docker_setup.sh" || return 1
    
    # Setup Docker environment
    setup_docker_environment "$WORK_DIR" "$SERVER_PORT" true || {
        error "Failed to setup Docker environment"
        return 1
    }
    
    log "Docker setup completed successfully"
    return 0
}

# Outline server setup
setup_outline_server() {
    log "Setting up Outline VPN server..."
    
    # Lazy load Outline module
    load_module_lazy "install/outline_setup.sh" || return 1
    
    # Run Outline installation
    install_outline_server true || {
        error "Failed to install Outline server"
        return 1
    }
    
    log "Outline server setup completed successfully"
    return 0
}

# Firewall setup
setup_firewall() {
    log "Configuring firewall rules..."
    
    # Lazy load firewall module
    load_module_lazy "install/firewall.sh" || return 1
    
    # Clean up unused VPN ports first (always check for cleanup)
    log "Checking for unused VPN ports in firewall..."
    cleanup_unused_vpn_ports "$SERVER_PORT" true false  # non-interactive mode
    
    # Configure network and firewall for the selected protocol
    if [ "$PROTOCOL" = "vless-reality" ]; then
        setup_vpn_network "$SERVER_PORT" true || {
            error "Failed to configure VPN network and firewall"
            return 1
        }
    elif [ "$PROTOCOL" = "outline" ]; then
        # For Outline, firewall is already configured during installation
        # Just ensure basic firewall setup is complete
        setup_basic_firewall true || {
            error "Failed to configure basic firewall"
            return 1
        }
    fi
    
    log "Firewall configuration completed successfully"
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f run_server_installation
export -f check_existing_vpn_installation
export -f select_vpn_protocol
export -f get_port_config_interactive
export -f get_outline_port_config_interactive
export -f get_outline_management_port_config
export -f get_user_config_interactive
export -f setup_docker_xray
export -f setup_outline_server
export -f setup_firewall
export -f load_module_lazy
export -f configure_vless_reality
export -f configure_outline_vpn
export -f show_final_configuration
export -f cleanup_outline_firewall_rules

# Also export IP selection function from network library
if command -v select_server_ip >/dev/null 2>&1; then
    export -f select_server_ip
fi

# Mark module as loaded
LOADED_MODULES["menu/server_installation.sh"]=1