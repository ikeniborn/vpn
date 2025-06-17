#!/bin/bash

# =============================================================================
# VPN Server Uninstall Script
# 
# This script completely removes the VPN server and all associated data.
# It provides a clean uninstallation with optional backup.
#
# Author: Claude
# Version: 2.0 (Modular)
# =============================================================================

set -e

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || {
    # Fallback color definitions if lib/common.sh is not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
    
    log() { echo -e "${GREEN}✓${NC} $1"; }
    error() { echo -e "${RED}✗ [ERROR]${NC} $1"; exit 1; }
    warning() { echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"; }
}

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

WORK_DIR="/opt/v2ray"
BACKUP_DIR="/tmp/vpn_backup_$(date +%Y%m%d_%H%M%S)"
CREATE_BACKUP=false

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

# Create backup of VPN data
create_backup() {
    log "Creating backup..."
    
    mkdir -p "$BACKUP_DIR" || {
        error "Failed to create backup directory: $BACKUP_DIR"
    }
    
    if [ -d "$WORK_DIR" ]; then
        # Copy configuration and user data
        cp -r "$WORK_DIR" "$BACKUP_DIR/" 2>/dev/null || {
            warning "Failed to backup some files"
        }
        
        # Export current firewall rules
        if command -v ufw >/dev/null 2>&1; then
            ufw status verbose > "$BACKUP_DIR/firewall_rules.txt" 2>/dev/null || true
        fi
        
        # Save Docker information
        if command -v docker >/dev/null 2>&1; then
            docker ps -a > "$BACKUP_DIR/docker_containers.txt" 2>/dev/null || true
            docker images > "$BACKUP_DIR/docker_images.txt" 2>/dev/null || true
        fi
        
        log "Backup created at: $BACKUP_DIR"
    else
        warning "VPN directory not found, skipping data backup"
    fi
}

# =============================================================================
# UNINSTALL FUNCTIONS
# =============================================================================

# Stop and remove Docker containers
remove_containers() {
    log "Stopping and removing Docker containers..."
    
    if command -v docker >/dev/null 2>&1; then
        # Stop and remove containers
        local containers=("xray" "v2raya" "watchtower" "shadowbox")
        
        for container in "${containers[@]}"; do
            if docker ps -a --format "table {{.Names}}" | grep -q "^$container$"; then
                log "Removing container: $container"
                docker stop "$container" 2>/dev/null || true
                docker rm "$container" 2>/dev/null || true
            fi
        done
        
        # Remove Docker Compose services
        if [ -f "$WORK_DIR/docker-compose.yml" ]; then
            cd "$WORK_DIR"
            docker-compose down 2>/dev/null || true
        fi
        
        # Remove Docker images (optional)
        echo -e "${YELLOW}Do you want to remove VPN Docker images? [y/N]${NC}"
        read -p "Remove images: " remove_images
        if [[ "$remove_images" =~ ^[Yy]$ ]]; then
            local images=("teddysun/xray" "mzz2017/v2raya" "containrrr/watchtower" "quay.io/outline/shadowbox")
            for image in "${images[@]}"; do
                if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$image"; then
                    log "Removing image: $image"
                    docker rmi "$image" 2>/dev/null || true
                fi
            done
        fi
    else
        warning "Docker not found, skipping container removal"
    fi
}

# Remove firewall rules
remove_firewall_rules() {
    log "Removing firewall rules..."
    
    if command -v ufw >/dev/null 2>&1; then
        # Get VPN port from config if available
        local vpn_port=""
        if [ -f "$WORK_DIR/config/config.json" ]; then
            vpn_port=$(grep -o '"port":[[:space:]]*[0-9]*' "$WORK_DIR/config/config.json" | grep -o '[0-9]*' | head -1)
        fi
        
        # Remove VPN port rules
        if [ -n "$vpn_port" ]; then
            log "Removing firewall rule for port $vpn_port"
            ufw delete allow "$vpn_port/tcp" 2>/dev/null || true
            ufw delete allow "$vpn_port/udp" 2>/dev/null || true
        fi
        
        # Remove common VPN ports
        local common_ports=("10443" "8080" "8388" "443")
        for port in "${common_ports[@]}"; do
            if ufw status | grep -q "$port"; then
                log "Removing firewall rule for port $port"
                ufw delete allow "$port/tcp" 2>/dev/null || true
                ufw delete allow "$port/udp" 2>/dev/null || true
            fi
        done
        
        log "Firewall rules removed"
    else
        warning "UFW not found, skipping firewall rule removal"
    fi
}

# Remove files and directories
remove_files() {
    log "Removing VPN files and directories..."
    
    # Remove main VPN directory
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR" || {
            error "Failed to remove VPN directory: $WORK_DIR"
        }
        log "Removed VPN directory: $WORK_DIR"
    fi
    
    # Remove management script symlink
    if [ -L "/usr/local/bin/v2ray-manage" ]; then
        rm -f "/usr/local/bin/v2ray-manage" || {
            warning "Failed to remove management script symlink"
        }
        log "Removed management script symlink"
    fi
    
    # Remove systemd services if they exist
    local services=("v2ray" "v2raya" "vpn-watchdog")
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log "Disabling and removing service: $service"
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            rm -f "/etc/systemd/system/$service.service" 2>/dev/null || true
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true
    
    log "Files and directories removed"
}

# Clean up Docker system
cleanup_docker() {
    log "Cleaning up Docker system..."
    
    if command -v docker >/dev/null 2>&1; then
        # Remove unused networks
        docker network prune -f 2>/dev/null || true
        
        # Remove unused volumes
        docker volume prune -f 2>/dev/null || true
        
        # Remove unused images (only dangling)
        docker image prune -f 2>/dev/null || true
        
        log "Docker system cleaned up"
    fi
}

# =============================================================================
# VERIFICATION FUNCTIONS
# =============================================================================

# Verify uninstallation
verify_uninstall() {
    log "Verifying uninstallation..."
    
    local issues=()
    
    # Check if directory still exists
    if [ -d "$WORK_DIR" ]; then
        issues+=("VPN directory still exists: $WORK_DIR")
    fi
    
    # Check for running containers
    if command -v docker >/dev/null 2>&1; then
        local running_containers=$(docker ps --format "{{.Names}}" | grep -E "(xray|v2raya|shadowbox)" || true)
        if [ -n "$running_containers" ]; then
            issues+=("VPN containers still running: $running_containers")
        fi
    fi
    
    # Check for management script
    if [ -L "/usr/local/bin/v2ray-manage" ]; then
        issues+=("Management script symlink still exists")
    fi
    
    # Report issues
    if [ ${#issues[@]} -gt 0 ]; then
        warning "Uninstallation verification found issues:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        return 1
    else
        log "Uninstallation verification passed"
        return 0
    fi
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Show uninstallation summary
show_summary() {
    echo -e "\n${GREEN}=== Uninstallation Summary ===${NC}"
    echo "The following will be removed:"
    echo "• VPN server containers and configurations"
    echo "• User data and connection files"
    echo "• Firewall rules for VPN ports"
    echo "• Management scripts and services"
    
    if [ "$CREATE_BACKUP" = true ]; then
        echo -e "\n${BLUE}Backup will be created at: $BACKUP_DIR${NC}"
    fi
    
    echo -e "\n${RED}WARNING: This action cannot be undone!${NC}"
}

# Confirm uninstallation
confirm_uninstall() {
    echo -e "\n${YELLOW}Are you sure you want to completely uninstall the VPN server? [y/N]${NC}"
    read -p "Confirm uninstall: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Uninstallation cancelled"
        exit 0
    fi
    
    echo -e "\n${YELLOW}Type 'YES' to confirm complete removal:${NC}"
    read -p "Final confirmation: " final_confirm
    
    if [ "$final_confirm" != "YES" ]; then
        log "Uninstallation cancelled"
        exit 0
    fi
}

# Main uninstallation process
main() {
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script with superuser privileges (sudo)"
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup)
                CREATE_BACKUP=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--backup] [--help]"
                echo "  --backup    Create backup before uninstalling"
                echo "  --help      Show this help message"
                exit 0
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Welcome message
    echo -e "${GREEN}=== VPN Server Uninstall Script ===${NC}"
    echo -e "${BLUE}Version: 2.0${NC}\n"
    
    # Show summary
    show_summary
    
    # Confirm uninstallation
    confirm_uninstall
    
    # Create backup if requested
    if [ "$CREATE_BACKUP" = true ]; then
        create_backup
    fi
    
    # Perform uninstallation
    log "Starting VPN server uninstallation..."
    
    remove_containers
    remove_firewall_rules
    remove_files
    cleanup_docker
    
    # Verify uninstallation
    if verify_uninstall; then
        echo -e "\n${GREEN}=== Uninstallation Completed Successfully ===${NC}"
        if [ "$CREATE_BACKUP" = true ]; then
            echo -e "${BLUE}Backup saved at: $BACKUP_DIR${NC}"
        fi
        echo -e "${GREEN}VPN server has been completely removed from the system.${NC}"
    else
        echo -e "\n${YELLOW}=== Uninstallation Completed with Issues ===${NC}"
        echo -e "${YELLOW}Please review the issues above and clean up manually if needed.${NC}"
        exit 1
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi