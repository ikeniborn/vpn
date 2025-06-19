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
    
    # Load prerequisites module for system checks and installation functions
    source "$PROJECT_ROOT/modules/install/prerequisites.sh" || {
        error "Failed to load prerequisites module"
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
    
    echo -e "${GREEN}=== VPN Server Status ===${NC}"
    echo ""
    
    local servers_found=false
    
    # Check Xray server
    if [ -d "/opt/v2ray" ] && [ -f "/opt/v2ray/docker-compose.yml" ]; then
        servers_found=true
        echo -e "${YELLOW}Xray/VLESS Server:${NC}"
        if docker ps | grep -q "xray"; then
            echo -e "  Status: ${GREEN}✓ Running${NC}"
            local port=$(cat /opt/v2ray/config/port.txt 2>/dev/null || echo "Unknown")
            local protocol=$(cat /opt/v2ray/config/protocol.txt 2>/dev/null || echo "VLESS+Reality")
            echo -e "  Port: ${BLUE}$port${NC}"
            echo -e "  Protocol: ${BLUE}$protocol${NC}"
            # Count users
            if [ -f "/opt/v2ray/config/config.json" ]; then
                local user_count=$(jq -r '.inbounds[0].settings.clients | length' /opt/v2ray/config/config.json 2>/dev/null || echo "0")
                echo -e "  Users: ${BLUE}$user_count${NC}"
            fi
        else
            echo -e "  Status: ${RED}✗ Stopped${NC}"
        fi
        echo ""
    fi
    
    # Check Outline server
    if [ -d "/opt/outline" ] || docker ps -a | grep -q "shadowbox"; then
        servers_found=true
        echo -e "${YELLOW}Outline VPN Server:${NC}"
        if docker ps | grep -q "shadowbox"; then
            echo -e "  Status: ${GREEN}✓ Running${NC}"
            if [ -f "/opt/outline/access.txt" ]; then
                local api_url=$(grep "apiUrl" /opt/outline/access.txt | cut -d'"' -f4)
                echo -e "  API URL: ${BLUE}$api_url${NC}"
            fi
        else
            echo -e "  Status: ${RED}✗ Stopped${NC}"
        fi
        echo ""
    fi
    
    if [ "$servers_found" = false ]; then
        warning "No VPN servers are installed."
        echo "Run 'Install VPN Server' from the main menu to get started."
    fi
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
    
    echo -e "${GREEN}=== Restart VPN Server ===${NC}"
    echo ""
    
    # Check what servers are installed
    local servers=()
    [ -d "/opt/v2ray" ] && [ -f "/opt/v2ray/docker-compose.yml" ] && servers+=("xray")
    ([ -d "/opt/outline" ] || docker ps -a | grep -q "shadowbox") && servers+=("outline")
    
    if [ ${#servers[@]} -eq 0 ]; then
        warning "No VPN servers are installed."
        return 1
    fi
    
    # If only one server, restart it
    if [ ${#servers[@]} -eq 1 ]; then
        local vpn_type="${servers[0]}"
    else
        # Multiple servers, ask which one
        echo "Select server to restart:"
        echo "1) Xray/VLESS Server"
        echo "2) Outline VPN Server"
        echo "3) All Servers"
        echo "0) Cancel"
        read -p "Select option: " choice
        
        case "$choice" in
            1) vpn_type="xray" ;;
            2) vpn_type="outline" ;;
            3) vpn_type="all" ;;
            0) return 0 ;;
            *) warning "Invalid option"; return 1 ;;
        esac
    fi
    
    # Load required modules
    load_server_modules || {
        error "Failed to load server modules"
        return 1
    }
    
    # Restart selected server(s)
    if [ "$vpn_type" = "all" ]; then
        for server in "${servers[@]}"; do
            echo -e "${BLUE}Restarting $server server...${NC}"
            case "$server" in
                "xray") 
                    restart_server || error "Failed to restart Xray server"
                    ;;
                "outline")
                    docker restart shadowbox 2>/dev/null && log "Outline server restarted" || error "Failed to restart Outline"
                    ;;
            esac
        done
    else
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
    fi
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
    
    echo -e "${GREEN}=== Uninstall VPN Server ===${NC}"
    echo ""
    
    # Check what servers are installed
    local servers=()
    [ -d "/opt/v2ray" ] && [ -f "/opt/v2ray/docker-compose.yml" ] && servers+=("xray")
    ([ -d "/opt/outline" ] || docker ps -a | grep -q "shadowbox") && servers+=("outline")
    
    if [ ${#servers[@]} -eq 0 ]; then
        warning "No VPN servers are installed."
        return 1
    fi
    
    # Select server to uninstall
    local vpn_type=""
    if [ ${#servers[@]} -eq 1 ]; then
        vpn_type="${servers[0]}"
        echo -e "${YELLOW}Found installed server: $vpn_type${NC}"
    else
        echo "Select server to uninstall:"
        echo "1) Xray/VLESS Server"
        echo "2) Outline VPN Server"
        echo "0) Cancel"
        read -p "Select option: " choice
        
        case "$choice" in
            1) vpn_type="xray" ;;
            2) vpn_type="outline" ;;
            0) return 0 ;;
            *) warning "Invalid option"; return 1 ;;
        esac
    fi
    
    # Confirmation prompt
    echo -e "\n${RED}⚠️  WARNING: This will completely remove the selected VPN server${NC}"
    echo -e "${RED}All user data and configurations will be permanently deleted!${NC}"
    echo -e "\nServer to remove: ${YELLOW}$vpn_type${NC}"
    read -p "Are you sure you want to continue? (yes/N): " confirm
    
    if [ "$confirm" != "yes" ]; then
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