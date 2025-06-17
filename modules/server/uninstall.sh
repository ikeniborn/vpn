#!/bin/bash
#
# Server Uninstall Module
# Handles complete VPN server removal with safety checks
# Extracted from manage_users.sh as part of Phase 4 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/docker.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_server_uninstall() {
    debug "Initializing server uninstall module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    debug "Server uninstall module initialized successfully"
}

# Display uninstall warning
display_uninstall_warning() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}    ⚠️  ${RED}WARNING: VPN SERVER REMOVAL${NC}      ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}❗ This operation will permanently delete:${NC}"
    echo -e "    ${YELLOW}•${NC} VPN server and all its settings"
    echo -e "    ${YELLOW}•${NC} All users and their data"
    echo -e "    ${YELLOW}•${NC} All configuration files"
    echo -e "    ${YELLOW}•${NC} Docker containers and images"
    echo -e "    ${YELLOW}•${NC} Log files and backups"
    echo -e "    ${YELLOW}•${NC} Management scripts and links"
    echo ""
    echo -e "${RED}⚠️  All data will be lost permanently!${NC}"
    echo ""
}

# Get confirmation from user
get_uninstall_confirmation() {
    debug "Getting uninstall confirmation from user"
    
    local confirmation final_confirmation
    
    read -p "$(echo -e ${YELLOW}Are you sure you want to continue? [yes/no]:${NC} )" confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Uninstall operation cancelled"
        return 1
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm complete removal: " final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        log "Uninstall operation cancelled"
        return 1
    fi
    
    debug "User confirmation received"
    return 0
}

# Stop and remove Docker containers
remove_docker_containers() {
    debug "Removing Docker containers"
    
    log "Stopping Docker containers..."
    
    if [ -d "$WORK_DIR" ]; then
        cd "$WORK_DIR" || {
            warning "Cannot access work directory: $WORK_DIR"
            return 1
        }
        
        # Stop containers gracefully
        if docker-compose down 2>/dev/null; then
            log "✓ Docker containers stopped"
            debug "Docker containers stopped successfully"
        else
            warning "Failed to stop containers gracefully"
            
            # Try to stop individual containers
            local containers
            containers=$(docker ps -q --filter "name=xray" 2>/dev/null || echo "")
            
            if [ -n "$containers" ]; then
                log "Attempting to stop individual containers..."
                echo "$containers" | xargs -r docker stop 2>/dev/null || true
                echo "$containers" | xargs -r docker rm 2>/dev/null || true
            fi
        fi
    else
        warning "Work directory not found: $WORK_DIR"
    fi
    
    debug "Docker container removal completed"
    return 0
}

# Remove Docker images
remove_docker_images() {
    debug "Removing Docker images"
    
    log "Removing Docker images..."
    
    # Remove Xray image
    if docker rmi teddysun/xray:latest 2>/dev/null; then
        log "✓ Xray Docker image removed"
        debug "Xray image removal successful"
    else
        warning "Failed to remove Xray Docker image (may not exist)"
    fi
    
    # Clean up unused Docker resources
    if docker system prune -f 2>/dev/null; then
        log "✓ Docker system cleaned up"
        debug "Docker system cleanup successful"
    else
        warning "Failed to clean up Docker system"
    fi
    
    debug "Docker image removal completed"
    return 0
}

# Remove working directory and all data
remove_working_directory() {
    debug "Removing working directory and all data"
    
    if [ ! -d "$WORK_DIR" ]; then
        warning "Working directory not found: $WORK_DIR"
        return 0
    fi
    
    log "Removing working directory: $WORK_DIR"
    
    # Create a final backup before deletion (optional safety measure)
    local backup_dir="/tmp/vpn_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$CONFIG_FILE" ]; then
        log "Creating final backup before deletion..."
        mkdir -p "$backup_dir"
        
        # Backup essential files
        cp "$CONFIG_FILE" "$backup_dir/" 2>/dev/null || true
        cp -r "$USERS_DIR" "$backup_dir/" 2>/dev/null || true
        cp -r "$WORK_DIR/config" "$backup_dir/" 2>/dev/null || true
        
        log "Final backup created in: $backup_dir"
        log "(Backup will be automatically removed in 24 hours)"
        
        # Schedule backup cleanup
        echo "rm -rf '$backup_dir'" | at now + 1 day 2>/dev/null || true
    fi
    
    # Remove the working directory
    if rm -rf "$WORK_DIR" 2>/dev/null; then
        log "✓ Working directory removed: $WORK_DIR"
        debug "Working directory removal successful"
    else
        error "Failed to remove working directory: $WORK_DIR"
    fi
    
    debug "Working directory removal completed"
    return 0
}

# Remove management script links
remove_management_links() {
    debug "Removing management script links"
    
    log "Removing management script links..."
    
    # Remove main management script link
    if [ -f "/usr/local/bin/v2ray-manage" ]; then
        if rm -f "/usr/local/bin/v2ray-manage" 2>/dev/null; then
            log "✓ Management script link removed"
            debug "Management script link removal successful"
        else
            warning "Failed to remove management script link"
        fi
    else
        debug "Management script link not found"
    fi
    
    # Remove any other script links that might exist
    local script_links=(
        "/usr/local/bin/vpn-manage"
        "/usr/local/bin/xray-manage"
        "/usr/bin/v2ray-manage"
    )
    
    for link in "${script_links[@]}"; do
        if [ -f "$link" ]; then
            rm -f "$link" 2>/dev/null || true
            debug "Removed additional script link: $link"
        fi
    done
    
    debug "Management links removal completed"
    return 0
}

# Close firewall ports
close_firewall_ports() {
    debug "Closing firewall ports"
    
    if ! command -v ufw >/dev/null 2>&1; then
        debug "UFW not available, skipping firewall cleanup"
        return 0
    fi
    
    log "Closing firewall ports..."
    
    # Get current port from configuration if still available
    local current_port=""
    if [ -f "$CONFIG_FILE" ]; then
        current_port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi
    
    # Close current port if found
    if [ -n "$current_port" ] && [ "$current_port" != "null" ]; then
        if ufw delete allow "$current_port/tcp" 2>/dev/null; then
            log "✓ Closed port $current_port in firewall"
            debug "Current port closed successfully"
        else
            warning "Failed to close port $current_port"
        fi
    fi
    
    # Close common VPN ports as safety measure
    local common_ports=("10443" "443" "8443" "9443")
    
    for port in "${common_ports[@]}"; do
        if ufw delete allow "$port/tcp" 2>/dev/null; then
            log "✓ Closed common port $port in firewall"
            debug "Common port $port closed"
        fi
    done
    
    # Show current firewall status
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log "Firewall remains active with updated rules"
    fi
    
    debug "Firewall ports closure completed"
    return 0
}

# Clean up systemd services (if any)
cleanup_systemd_services() {
    debug "Cleaning up systemd services"
    
    local services=(
        "v2ray"
        "xray"
        "vpn-server"
        "v2ray-server"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled"; then
            log "Disabling systemd service: $service"
            systemctl disable "$service" 2>/dev/null || true
            systemctl stop "$service" 2>/dev/null || true
        fi
        
        # Remove service files if they exist
        if [ -f "/etc/systemd/system/$service.service" ]; then
            rm -f "/etc/systemd/system/$service.service" 2>/dev/null || true
            debug "Removed service file: $service.service"
        fi
    done
    
    # Reload systemd if any changes were made
    systemctl daemon-reload 2>/dev/null || true
    
    debug "Systemd services cleanup completed"
    return 0
}

# Clean up cron jobs (if any)
cleanup_cron_jobs() {
    debug "Cleaning up cron jobs"
    
    # Remove any VPN-related cron jobs
    if command -v crontab >/dev/null 2>&1; then
        local temp_cron="/tmp/cron_backup_$$"
        
        if crontab -l > "$temp_cron" 2>/dev/null; then
            # Remove lines containing VPN-related keywords
            if grep -v -E "(v2ray|xray|vpn|reality)" "$temp_cron" > "$temp_cron.clean" 2>/dev/null; then
                if [ -s "$temp_cron.clean" ]; then
                    crontab "$temp_cron.clean" 2>/dev/null || true
                    log "✓ Cleaned up cron jobs"
                else
                    crontab -r 2>/dev/null || true
                    log "✓ Removed all cron jobs"
                fi
            fi
            
            rm -f "$temp_cron" "$temp_cron.clean" 2>/dev/null || true
        fi
    fi
    
    debug "Cron jobs cleanup completed"
    return 0
}

# Display uninstall summary
display_uninstall_summary() {
    local start_time="$1"
    local end_time="$2"
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                    ${GREEN}Uninstall Summary${NC}                          ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}✅ VPN server successfully removed!${NC}"
    echo ""
    echo -e "  ${GREEN}📋 Completed Operations:${NC}"
    echo -e "    🐳 Docker containers stopped and removed"
    echo -e "    🖼️  Docker images cleaned up"
    echo -e "    📁 Working directory deleted: $WORK_DIR"
    echo -e "    🔗 Management script links removed"
    echo -e "    🔒 Firewall ports closed"
    echo -e "    🗂️  System services cleaned up"
    echo ""
    echo -e "  ${GREEN}⏱️  Operation Duration:${NC} ${YELLOW}$((end_time - start_time)) seconds${NC}"
    echo ""
    echo -e "  ${GREEN}📝 Important Notes:${NC}"
    echo -e "    • All user data and configurations have been deleted"
    echo -e "    • Docker images have been removed"
    echo -e "    • Firewall rules have been updated"
    echo -e "    • System is clean and ready for fresh installation"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Main uninstall function
uninstall_vpn() {
    local start_time
    start_time=$(date +%s)
    
    log "🗑️  Starting VPN server uninstall..."
    
    # Initialize module
    init_server_uninstall
    
    # Display warning and get confirmation
    display_uninstall_warning
    
    if ! get_uninstall_confirmation; then
        return 0
    fi
    
    log "Starting VPN server removal..."
    echo ""
    
    # Stop and remove Docker containers
    remove_docker_containers
    
    # Remove Docker images
    remove_docker_images
    
    # Remove working directory and all data
    remove_working_directory
    
    # Remove management script links
    remove_management_links
    
    # Close firewall ports
    close_firewall_ports
    
    # Clean up systemd services
    cleanup_systemd_services
    
    # Clean up cron jobs
    cleanup_cron_jobs
    
    local end_time
    end_time=$(date +%s)
    
    # Display summary
    display_uninstall_summary "$start_time" "$end_time"
    
    log "VPN server uninstall completed successfully!"
    
    # Exit the script since the server is completely removed
    exit 0
}

# Force uninstall (minimal prompts)
force_uninstall() {
    log "🚨 Force uninstalling VPN server..."
    
    # Initialize module
    init_server_uninstall
    
    echo -e "${RED}⚠️  Force uninstall mode - minimal confirmations${NC}"
    echo ""
    
    local confirmation
    read -p "Type 'FORCE' to confirm immediate removal: " confirmation
    
    if [ "$confirmation" != "FORCE" ]; then
        log "Force uninstall cancelled"
        return 0
    fi
    
    # Perform all removal operations without additional prompts
    remove_docker_containers
    remove_docker_images
    remove_working_directory
    remove_management_links
    close_firewall_ports >/dev/null 2>&1 || true
    cleanup_systemd_services >/dev/null 2>&1 || true
    cleanup_cron_jobs >/dev/null 2>&1 || true
    
    log "✅ Force uninstall completed!"
    exit 0
}

# Partial uninstall (remove containers but keep data)
partial_uninstall() {
    log "📦 Partial uninstall - removing containers only..."
    
    # Initialize module
    init_server_uninstall
    
    echo -e "${YELLOW}⚠️  This will stop containers but preserve data${NC}"
    echo ""
    
    local confirmation
    read -p "Continue with partial uninstall? [yes/no]: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Partial uninstall cancelled"
        return 0
    fi
    
    # Remove only containers and images
    remove_docker_containers
    remove_docker_images
    
    log "✅ Partial uninstall completed!"
    log "Data preserved in: $WORK_DIR"
}

# Check what would be removed (dry run)
show_removal_preview() {
    debug "Showing removal preview"
    
    init_server_uninstall
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                     ${GREEN}Removal Preview${NC}                           ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check working directory
    if [ -d "$WORK_DIR" ]; then
        local dir_size
        dir_size=$(du -sh "$WORK_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "  ${GREEN}📁 Working Directory:${NC} $WORK_DIR (${YELLOW}$dir_size${NC})"
        
        # Show user count
        if [ -f "$CONFIG_FILE" ]; then
            local users_count
            users_count=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
            echo -e "  ${GREEN}👥 Users:${NC} ${YELLOW}$users_count configured${NC}"
        fi
    else
        echo -e "  ${RED}📁 Working Directory:${NC} Not found"
    fi
    
    # Check Docker containers
    if cd "$WORK_DIR" 2>/dev/null && docker-compose ps 2>/dev/null | grep -q .; then
        echo -e "  ${GREEN}🐳 Docker Containers:${NC} Present"
    else
        echo -e "  ${RED}🐳 Docker Containers:${NC} Not found"
    fi
    
    # Check management links
    if [ -f "/usr/local/bin/v2ray-manage" ]; then
        echo -e "  ${GREEN}🔗 Management Link:${NC} /usr/local/bin/v2ray-manage"
    else
        echo -e "  ${RED}🔗 Management Link:${NC} Not found"
    fi
    
    # Check firewall rules
    if command -v ufw >/dev/null 2>&1; then
        local vpn_rules
        vpn_rules=$(ufw status 2>/dev/null | grep -E "(10443|443)" | wc -l || echo "0")
        echo -e "  ${GREEN}🔒 Firewall Rules:${NC} ${YELLOW}$vpn_rules VPN-related rules${NC}"
    else
        echo -e "  ${RED}🔒 Firewall:${NC} UFW not available"
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Export functions for use by other modules
export -f init_server_uninstall
export -f display_uninstall_warning
export -f get_uninstall_confirmation
export -f remove_docker_containers
export -f remove_docker_images
export -f remove_working_directory
export -f remove_management_links
export -f close_firewall_ports
export -f cleanup_systemd_services
export -f cleanup_cron_jobs
export -f display_uninstall_summary
export -f uninstall_vpn
export -f force_uninstall
export -f partial_uninstall
export -f show_removal_preview