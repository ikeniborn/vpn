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
    
    # Load performance optimization library
    if [ -z "$PERFORMANCE_LIB_SOURCED" ]; then
        source "$PROJECT_ROOT/lib/performance.sh" || {
            warning "Performance optimizations not available"
        }
    fi
    
    # Lazy load server installation module
    load_module_lazy "menu/server_installation.sh" || {
        error "Failed to load server installation module"
        return 1
    }
    
    # Load additional libraries only when needed
    load_additional_libraries true || {
        error "Failed to load additional libraries"
        return 1
    }
    
    # Load prerequisites module for system detection
    load_module_lazy "install/prerequisites.sh" || {
        error "Failed to load prerequisites module"
        return 1
    }
    
    # Now check system prerequisites
    detect_system_info true
    
    # Run installation using optimized modules with timing
    time_function run_server_installation
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
    
    # Load performance library for caching
    if [ -z "$PERFORMANCE_LIB_SOURCED" ]; then
        source "$PROJECT_ROOT/lib/performance.sh" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}=== VPN Server Status ===${NC}"
    echo ""
    
    local servers_found=false
    
    # Check Xray server with optimized file operations
    if [ -d "/opt/v2ray" ] && [ -f "/opt/v2ray/docker-compose.yml" ]; then
        servers_found=true
        echo -e "${YELLOW}Xray/VLESS Server:${NC}"
        
        # Use cached container status if available
        local xray_status
        if command -v get_container_status_cached >/dev/null 2>&1; then
            xray_status=$(get_container_status_cached "xray")
        else
            xray_status=$(docker inspect -f '{{.State.Status}}' xray 2>/dev/null || echo "not_found")
        fi
        
        if [ "$xray_status" = "running" ]; then
            echo -e "  Status: ${GREEN}✓ Running${NC}"
            
            # Optimized file reads
            local config_files=("/opt/v2ray/config/port.txt" "/opt/v2ray/config/protocol.txt")
            local config_values
            if command -v read_multiple_files >/dev/null 2>&1; then
                readarray -t config_values < <(read_multiple_files "${config_files[@]}")
                local port=${config_values[0]:-"Unknown"}
                local protocol=${config_values[1]:-"VLESS+Reality"}
            else
                local port=$(cat /opt/v2ray/config/port.txt 2>/dev/null || echo "Unknown")
                local protocol=$(cat /opt/v2ray/config/protocol.txt 2>/dev/null || echo "VLESS+Reality")
            fi
            
            echo -e "  Port: ${BLUE}$port${NC}"
            echo -e "  Protocol: ${BLUE}$protocol${NC}"
            
            # Count users with caching
            if [ -f "/opt/v2ray/config/config.json" ]; then
                local user_count
                if command -v get_config_cached >/dev/null 2>&1; then
                    user_count=$(get_config_cached "/opt/v2ray/config/config.json" ".inbounds[0].settings.clients | length")
                else
                    user_count=$(jq -r '.inbounds[0].settings.clients | length' /opt/v2ray/config/config.json 2>/dev/null || echo "0")
                fi
                echo -e "  Users: ${BLUE}$user_count${NC}"
            fi
        else
            echo -e "  Status: ${RED}✗ Stopped${NC}"
        fi
        echo ""
    fi
    
    # Check Outline server with optimized status check
    if [ -d "/opt/outline" ] || docker ps -a --format "table {{.Names}}" 2>/dev/null | grep -q "shadowbox"; then
        servers_found=true
        echo -e "${YELLOW}Outline VPN Server:${NC}"
        
        # Use cached container status
        local outline_status
        if command -v get_container_status_cached >/dev/null 2>&1; then
            outline_status=$(get_container_status_cached "shadowbox")
        else
            outline_status=$(docker inspect -f '{{.State.Status}}' shadowbox 2>/dev/null || echo "not_found")
        fi
        
        if [ "$outline_status" = "running" ]; then
            echo -e "  Status: ${GREEN}✓ Running${NC}"
            
            # Get API port and access key port
            local api_port=$(cat /opt/outline/api_port.txt 2>/dev/null || echo "9000")
            local access_port=$(cat /opt/outline/configured_port.txt 2>/dev/null || echo "Unknown")
            
            echo -e "  API Port: ${BLUE}$api_port${NC}"
            echo -e "  Access Port: ${BLUE}$access_port${NC}"
            
            # Get API URL from saved file or access.txt
            local api_url=""
            if [ -f "/opt/outline/api_url.txt" ]; then
                api_url=$(cat /opt/outline/api_url.txt 2>/dev/null)
            elif [ -f "/opt/outline/access.txt" ]; then
                api_url=$(grep "apiUrl:" /opt/outline/access.txt 2>/dev/null | cut -d':' -f2-)
            fi
            
            if [ -n "$api_url" ]; then
                echo -e "  API URL: ${BLUE}$api_url${NC}"
            fi
            
            # Check Watchtower status
            local watchtower_status
            if command -v get_container_status_cached >/dev/null 2>&1; then
                watchtower_status=$(get_container_status_cached "watchtower")
            else
                watchtower_status=$(docker inspect -f '{{.State.Status}}' watchtower 2>/dev/null || echo "not_found")
            fi
            
            if [ "$watchtower_status" = "running" ]; then
                echo -e "  Auto-Update: ${GREEN}✓ Active (Watchtower)${NC}"
            else
                echo -e "  Auto-Update: ${YELLOW}⚠ Inactive${NC}"
            fi
        elif [ "$outline_status" = "not_found" ]; then
            echo -e "  Status: ${RED}✗ Not Found${NC}"
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
    
    # Load uninstall module
    load_module_lazy "server/uninstall.sh" || {
        error "Failed to load uninstall module"
        return 1
    }
    
    # Call appropriate uninstall function
    case "$vpn_type" in
        "xray")
            uninstall_vpn
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