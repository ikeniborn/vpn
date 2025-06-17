#!/bin/bash

# VPN Deployment Script
# For manual deployment or CI/CD pipeline

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

# Configuration
DEPLOY_DIR="${DEPLOY_DIR:-/opt/v2ray}"
BACKUP_DIR="${BACKUP_DIR:-/opt/v2ray-backup}"
SERVICE_NAME="vpn-watchdog"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
fi

# Show usage
show_usage() {
    echo -e "${BLUE}VPN Deployment Script${NC}"
    echo ""
    echo "Usage: $0 [options] <action>"
    echo ""
    echo "Actions:"
    echo "  install     - Fresh installation"
    echo "  update      - Update existing installation"
    echo "  backup      - Create backup of current installation"
    echo "  restore     - Restore from backup"
    echo "  status      - Show service status"
    echo "  restart     - Restart services"
    echo "  logs        - Show service logs"
    echo ""
    echo "Options:"
    echo "  --dir=PATH      - Set deployment directory (default: /opt/v2ray)"
    echo "  --backup=PATH   - Set backup directory (default: /opt/v2ray-backup)"
    echo "  --no-watchdog   - Skip watchdog installation"
    echo "  --help          - Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  DEPLOY_DIR      - Deployment directory"
    echo "  BACKUP_DIR      - Backup directory"
}

# Parse arguments
NO_WATCHDOG=false
ACTION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir=*)
            DEPLOY_DIR="${1#*=}"
            shift
            ;;
        --backup=*)
            BACKUP_DIR="${1#*=}"
            shift
            ;;
        --no-watchdog)
            NO_WATCHDOG=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        install|update|backup|restore|status|restart|logs)
            ACTION="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [ -z "$ACTION" ]; then
    show_usage
    exit 1
fi

# Ensure required tools are available
check_dependencies() {
    local missing_deps=()
    
    for cmd in docker docker-compose systemctl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
    fi
}

# Create backup
create_backup() {
    log "Creating backup..."
    
    if [ ! -d "$DEPLOY_DIR" ]; then
        warning "No existing installation found to backup"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup configuration and data
    if [ -d "$DEPLOY_DIR" ]; then
        cp -r "$DEPLOY_DIR" "$BACKUP_DIR/v2ray-$(date +%Y%m%d-%H%M%S)"
        log "Configuration backed up to $BACKUP_DIR"
    fi
    
    # Backup systemd service
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        cp "/etc/systemd/system/${SERVICE_NAME}.service" "$BACKUP_DIR/"
        log "Systemd service backed up"
    fi
    
    # Export container images
    for container in xray shadowbox watchtower; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            local image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null || echo "")
            if [ -n "$image" ]; then
                docker save "$image" > "$BACKUP_DIR/${container}-image.tar" 2>/dev/null || true
                log "Container image $image backed up"
            fi
        fi
    done
}

# Install fresh
install_fresh() {
    log "Starting fresh installation..."
    
    check_dependencies
    
    # Create deployment directory
    mkdir -p "$DEPLOY_DIR"
    
    # Copy all project files to deployment directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    for file in install_vpn.sh manage_users.sh install_client.sh watchdog.sh vpn-watchdog.service; do
        if [ -f "$script_dir/$file" ]; then
            cp "$script_dir/$file" "$DEPLOY_DIR/"
            chmod +x "$DEPLOY_DIR/$file" 2>/dev/null || true
            log "Copied $file to deployment directory"
        fi
    done
    
    # Run installation
    cd "$DEPLOY_DIR"
    if [ -f "install_vpn.sh" ]; then
        bash install_vpn.sh
        log "VPN installation completed"
    else
        error "install_vpn.sh not found in deployment directory"
    fi
    
    # Install watchdog if not disabled
    if [ "$NO_WATCHDOG" = false ]; then
        install_watchdog
    fi
    
    log "Fresh installation completed"
}

# Update existing installation
update_installation() {
    log "Updating existing installation..."
    
    check_dependencies
    
    if [ ! -d "$DEPLOY_DIR" ]; then
        error "No existing installation found. Use 'install' action instead."
    fi
    
    # Create backup before update
    create_backup
    
    # Stop services
    docker-compose -f "$DEPLOY_DIR/docker-compose.yml" down 2>/dev/null || true
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    
    # Update files
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    for file in manage_users.sh watchdog.sh vpn-watchdog.service; do
        if [ -f "$script_dir/$file" ]; then
            cp "$script_dir/$file" "$DEPLOY_DIR/"
            chmod +x "$DEPLOY_DIR/$file" 2>/dev/null || true
            log "Updated $file"
        fi
    done
    
    # Update watchdog service
    if [ "$NO_WATCHDOG" = false ] && [ -f "$DEPLOY_DIR/vpn-watchdog.service" ]; then
        cp "$DEPLOY_DIR/vpn-watchdog.service" /etc/systemd/system/
        systemctl daemon-reload
        log "Watchdog service updated"
    fi
    
    # Restart services
    cd "$DEPLOY_DIR"
    docker-compose up -d 2>/dev/null || true
    
    if [ "$NO_WATCHDOG" = false ]; then
        systemctl start "${SERVICE_NAME}.service" 2>/dev/null || true
    fi
    
    log "Update completed"
}

# Install watchdog service
install_watchdog() {
    if [ ! -f "$DEPLOY_DIR/watchdog.sh" ] || [ ! -f "$DEPLOY_DIR/vpn-watchdog.service" ]; then
        warning "Watchdog files not found, skipping watchdog installation"
        return 0
    fi
    
    log "Installing watchdog service..."
    
    # Copy watchdog script
    cp "$DEPLOY_DIR/watchdog.sh" /usr/local/bin/vpn-watchdog.sh
    chmod +x /usr/local/bin/vpn-watchdog.sh
    
    # Install systemd service
    cp "$DEPLOY_DIR/vpn-watchdog.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
    systemctl start "${SERVICE_NAME}.service"
    
    log "Watchdog service installed and started"
}

# Restore from backup
restore_from_backup() {
    log "Restoring from backup..."
    
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Backup directory not found: $BACKUP_DIR"
    fi
    
    # Find latest backup
    local latest_backup=$(ls -t "$BACKUP_DIR"/v2ray-* 2>/dev/null | head -n1)
    
    if [ -z "$latest_backup" ]; then
        error "No backup found in $BACKUP_DIR"
    fi
    
    log "Restoring from: $latest_backup"
    
    # Stop services
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    docker-compose -f "$DEPLOY_DIR/docker-compose.yml" down 2>/dev/null || true
    
    # Restore files
    rm -rf "$DEPLOY_DIR"
    cp -r "$latest_backup" "$DEPLOY_DIR"
    
    # Restore systemd service
    if [ -f "$BACKUP_DIR/${SERVICE_NAME}.service" ]; then
        cp "$BACKUP_DIR/${SERVICE_NAME}.service" /etc/systemd/system/
        systemctl daemon-reload
    fi
    
    # Start services
    cd "$DEPLOY_DIR"
    docker-compose up -d 2>/dev/null || true
    systemctl start "${SERVICE_NAME}.service" 2>/dev/null || true
    
    log "Restore completed"
}

# Show status
show_status() {
    echo -e "${BLUE}VPN Services Status${NC}"
    echo ""
    
    # Docker containers
    echo -e "${GREEN}Docker Containers:${NC}"
    if command -v docker >/dev/null 2>&1; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(xray|shadowbox|watchtower)" || echo "  No VPN containers running"
    else
        echo "  Docker not available"
    fi
    
    echo ""
    
    # Systemd service
    echo -e "${GREEN}Watchdog Service:${NC}"
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "  Status: ${GREEN}● Active${NC}"
        echo "  Enabled: $(systemctl is-enabled ${SERVICE_NAME}.service 2>/dev/null || echo 'unknown')"
    else
        echo -e "  Status: ${RED}● Inactive${NC}"
    fi
    
    echo ""
    
    # System resources
    echo -e "${GREEN}System Resources:${NC}"
    echo "  Memory: $(free -h | grep '^Mem:' | awk '{print $3 "/" $2}')"
    echo "  Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"
}

# Restart services
restart_services() {
    log "Restarting VPN services..."
    
    # Restart containers
    if [ -f "$DEPLOY_DIR/docker-compose.yml" ]; then
        cd "$DEPLOY_DIR"
        docker-compose restart
        log "Docker containers restarted"
    fi
    
    # Restart watchdog
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        systemctl restart "${SERVICE_NAME}.service"
        log "Watchdog service restarted"
    fi
}

# Show logs
show_logs() {
    echo -e "${BLUE}VPN Service Logs${NC}"
    echo ""
    
    # Docker logs
    echo -e "${GREEN}Docker Container Logs:${NC}"
    for container in xray shadowbox watchtower; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            echo -e "${YELLOW}--- $container ---${NC}"
            docker logs --tail 10 "$container" 2>/dev/null || echo "  No logs available"
        fi
    done
    
    echo ""
    
    # Watchdog logs
    echo -e "${GREEN}Watchdog Logs:${NC}"
    if [ -f "/var/log/vpn-watchdog.log" ]; then
        tail -20 /var/log/vpn-watchdog.log
    else
        echo "  No watchdog logs found"
    fi
}

# Main execution
case $ACTION in
    install)
        install_fresh
        ;;
    update)
        update_installation
        ;;
    backup)
        create_backup
        ;;
    restore)
        restore_from_backup
        ;;
    status)
        show_status
        ;;
    restart)
        restart_services
        ;;
    logs)
        show_logs
        ;;
    *)
        error "Unknown action: $ACTION"
        ;;
esac

log "Action '$ACTION' completed successfully"