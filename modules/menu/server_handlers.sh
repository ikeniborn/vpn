#!/bin/bash

# =============================================================================
# Server Management Handlers Module
# 
# This module handles server management operations.
# Extracted from vpn.sh for modular architecture.
#
# Functions exported:
# - handle_server_install()
# - handle_server_status()
# - handle_server_restart()
# - handle_server_uninstall()
#
# Dependencies: lib/common.sh, modules/install/*, modules/server/*
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
# SERVER INSTALLATION HANDLER
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
# SERVER STATUS HANDLER
# =============================================================================

handle_server_status() {
    # Check prerequisites
    if [ "$EUID" -ne 0 ]; then
        error "Server status check requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check which VPN type is installed
    local vpn_type=$(detect_installed_vpn_type)
    
    if [ "$vpn_type" = "none" ]; then
        warning "No VPN server is installed. Run installation first."
        return 1
    fi
    
    # Load required modules
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
    # Call appropriate status function
    case "$vpn_type" in
        "xray")
            show_server_status
            ;;
        "outline")
            echo -e "${YELLOW}Outline VPN Server Status:${NC}"
            if docker ps | grep -q "shadowbox"; then
                echo -e "${GREEN}✓ Outline server is running${NC}"
                echo ""
                echo "Management configuration:"
                if [ -f "/opt/outline/management/config.json" ]; then
                    cat /opt/outline/management/config.json | jq -r '.'
                else
                    echo "Configuration file not found"
                fi
            else
                echo -e "${RED}✗ Outline server is not running${NC}"
            fi
            ;;
    esac
}

# =============================================================================
# SERVER RESTART HANDLER
# =============================================================================

handle_server_restart() {
    # Check prerequisites
    if [ "$EUID" -ne 0 ]; then
        error "Server restart requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check which VPN type is installed
    local vpn_type=$(detect_installed_vpn_type)
    
    if [ "$vpn_type" = "none" ]; then
        warning "No VPN server is installed. Run installation first."
        return 1
    fi
    
    # Load required modules
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
    # Call appropriate restart function
    case "$vpn_type" in
        "xray")
            restart_server
            ;;
        "outline")
            echo -e "${BLUE}Restarting Outline VPN server...${NC}"
            if docker restart shadowbox 2>/dev/null; then
                log "Outline server restarted successfully"
            else
                error "Failed to restart Outline server"
                return 1
            fi
            ;;
    esac
}

# =============================================================================
# SERVER UNINSTALL HANDLER
# =============================================================================

handle_server_uninstall() {
    # Check prerequisites
    if [ "$EUID" -ne 0 ]; then
        error "Server uninstall requires superuser privileges (sudo)"
        return 1
    fi
    
    # Check which VPN type is installed
    local vpn_type=$(detect_installed_vpn_type)
    
    if [ "$vpn_type" = "none" ]; then
        warning "No VPN server is installed."
        return 1
    fi
    
    # Confirmation prompt
    echo -e "${YELLOW}⚠️  This will completely remove the VPN server and all user data.${NC}"
    read -p "Are you sure you want to continue? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Uninstall cancelled by user"
        return 0
    fi
    
    # Load required modules
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
    # Call appropriate uninstall function
    case "$vpn_type" in
        "xray")
            uninstall_server
            ;;
        "outline")
            echo -e "${BLUE}Uninstalling Outline VPN server...${NC}"
            
            # Stop and remove containers
            docker rm -f shadowbox watchtower 2>/dev/null || true
            
            # Remove configuration directory
            rm -rf /opt/outline 2>/dev/null || true
            
            # Remove firewall rules
            if command -v ufw >/dev/null 2>&1; then
                ufw status numbered | grep -E "9000|Outline" | awk '{print $2}' | sort -r | while read -r num; do
                    ufw --force delete "$num" 2>/dev/null || true
                done
            fi
            
            log "Outline VPN server uninstalled successfully"
            ;;
    esac
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f handle_server_install
export -f handle_server_status
export -f handle_server_restart
export -f handle_server_uninstall