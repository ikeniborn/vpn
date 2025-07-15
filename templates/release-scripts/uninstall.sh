#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
INSTALL_PREFIX="/opt/vpn"
SERVICE_NAME="vpn-manager"
SYSTEMD_PATH="/etc/systemd/system"
BINARY_PATH="/usr/local/bin"
BACKUP_DIR="/tmp/vpn-uninstall-backup-$(date +%Y%m%d%H%M%S)"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Function to confirm uninstallation
confirm_uninstall() {
    echo "╔══════════════════════════════════════════════╗"
    echo "║      VPN Management System Uninstaller       ║"
    echo "╚══════════════════════════════════════════════╝"
    echo
    print_warning "This will remove the VPN Management System from your system."
    echo
    echo "The following will be removed:"
    echo "  - VPN service and systemd units"
    echo "  - Binaries from $BINARY_PATH"
    echo "  - Installation directory: $INSTALL_PREFIX"
    echo "  - All associated data and logs"
    echo
    echo -n "Do you want to create a backup before uninstalling? (Y/n): "
    read -r create_backup
    
    if [[ ! "$create_backup" =~ ^[Nn]$ ]]; then
        BACKUP_ENABLED=true
    else
        BACKUP_ENABLED=false
    fi
    
    echo
    echo -e "${RED}This action cannot be undone!${NC}"
    echo -n "Are you sure you want to continue? (y/N): "
    read -r confirmation
    
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
}

# Function to stop and disable services
stop_services() {
    print_info "Stopping VPN services..."
    
    # Stop main service
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
        print_success "Stopped $SERVICE_NAME service"
    fi
    
    # Stop any related services
    for service in vpn-proxy vpn-identity vpn-api; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            systemctl stop "$service"
            print_success "Stopped $service service"
        fi
    done
    
    # Disable services
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
        print_success "Disabled $SERVICE_NAME service"
    fi
    
    for service in vpn-proxy vpn-identity vpn-api; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            systemctl disable "$service"
            print_success "Disabled $service service"
        fi
    done
}

# Function to create backup
create_backup() {
    if [[ "$BACKUP_ENABLED" != true ]]; then
        return
    fi
    
    print_info "Creating backup at $BACKUP_DIR..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup configuration files
    if [[ -d "$INSTALL_PREFIX/configs" ]]; then
        cp -r "$INSTALL_PREFIX/configs" "$BACKUP_DIR/"
        print_success "Backed up configuration files"
    fi
    
    # Backup database
    if [[ -d "$INSTALL_PREFIX/db" ]]; then
        cp -r "$INSTALL_PREFIX/db" "$BACKUP_DIR/"
        print_success "Backed up database"
    fi
    
    # Backup logs
    if [[ -d "$INSTALL_PREFIX/logs" ]]; then
        cp -r "$INSTALL_PREFIX/logs" "$BACKUP_DIR/"
        print_success "Backed up logs"
    fi
    
    # Create restore script
    cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
# VPN Backup Restore Script

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/opt/vpn"

echo "This will restore VPN configuration from backup."
echo "Target directory: $INSTALL_PREFIX"
echo -n "Continue? (y/N): "
read -r confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    mkdir -p "$INSTALL_PREFIX"
    cp -r "$BACKUP_DIR/configs" "$INSTALL_PREFIX/" 2>/dev/null || true
    cp -r "$BACKUP_DIR/db" "$INSTALL_PREFIX/" 2>/dev/null || true
    cp -r "$BACKUP_DIR/logs" "$INSTALL_PREFIX/" 2>/dev/null || true
    echo "Restore completed"
else
    echo "Restore cancelled"
fi
EOF
    chmod +x "$BACKUP_DIR/restore.sh"
    
    print_success "Backup created at: $BACKUP_DIR"
}

# Function to remove systemd units
remove_systemd_units() {
    print_info "Removing systemd service files..."
    
    # Remove main service file
    if [[ -f "$SYSTEMD_PATH/${SERVICE_NAME}.service" ]]; then
        rm -f "$SYSTEMD_PATH/${SERVICE_NAME}.service"
        print_success "Removed ${SERVICE_NAME}.service"
    fi
    
    # Remove any related service files
    for service in vpn-proxy vpn-identity vpn-api; do
        if [[ -f "$SYSTEMD_PATH/${service}.service" ]]; then
            rm -f "$SYSTEMD_PATH/${service}.service"
            print_success "Removed ${service}.service"
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload
}

# Function to remove binaries
remove_binaries() {
    print_info "Removing binaries..."
    
    # Remove symlinks from system path
    for binary in vpn vpn-manager vpn-cli vpn-proxy vpn-identity vpn-api; do
        if [[ -L "$BINARY_PATH/$binary" ]] || [[ -f "$BINARY_PATH/$binary" ]]; then
            rm -f "$BINARY_PATH/$binary"
            print_success "Removed $BINARY_PATH/$binary"
        fi
    done
}

# Function to remove installation directory
remove_installation_directory() {
    print_info "Removing installation directory..."
    
    if [[ -d "$INSTALL_PREFIX" ]]; then
        rm -rf "$INSTALL_PREFIX"
        print_success "Removed $INSTALL_PREFIX"
    else
        print_warning "Installation directory not found: $INSTALL_PREFIX"
    fi
}

# Function to remove Docker containers and images
remove_docker_resources() {
    if ! command -v docker &> /dev/null; then
        return
    fi
    
    print_info "Checking for Docker resources..."
    
    # Stop and remove containers
    local containers=$(docker ps -a --filter "name=vpn" --format "{{.Names}}" 2>/dev/null)
    if [[ -n "$containers" ]]; then
        print_info "Removing VPN Docker containers..."
        docker stop $containers 2>/dev/null || true
        docker rm $containers 2>/dev/null || true
        print_success "Removed Docker containers"
    fi
    
    # Remove images
    local images=$(docker images --filter "reference=vpn*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null)
    if [[ -n "$images" ]]; then
        echo -n "Remove VPN Docker images? (y/N): "
        read -r remove_images
        if [[ "$remove_images" =~ ^[Yy]$ ]]; then
            docker rmi $images 2>/dev/null || true
            print_success "Removed Docker images"
        fi
    fi
}

# Function to clean up logs and temporary files
cleanup_logs() {
    print_info "Cleaning up logs and temporary files..."
    
    # Remove logs from common locations
    rm -rf /var/log/vpn* 2>/dev/null || true
    
    # Remove any temporary files
    rm -rf /tmp/vpn* 2>/dev/null || true
    
    print_success "Cleaned up logs and temporary files"
}

# Function to display post-uninstall summary
post_uninstall_summary() {
    echo
    print_success "VPN Management System has been uninstalled!"
    echo
    
    if [[ "$BACKUP_ENABLED" == true ]]; then
        echo -e "${GREEN}Backup Information:${NC}"
        echo "  A backup has been created at: $BACKUP_DIR"
        echo "  To restore the backup, run: $BACKUP_DIR/restore.sh"
        echo
    fi
    
    echo -e "${BLUE}Cleanup Summary:${NC}"
    echo "  ✓ Services stopped and disabled"
    echo "  ✓ Systemd units removed"
    echo "  ✓ Binaries removed from $BINARY_PATH"
    echo "  ✓ Installation directory removed"
    echo "  ✓ Logs and temporary files cleaned"
    
    if command -v docker &> /dev/null; then
        echo "  ✓ Docker resources cleaned"
    fi
    
    echo
    echo -e "${YELLOW}Note:${NC} Some configuration files may remain in:"
    echo "  - /etc/vpn* (if any)"
    echo "  - User home directories"
    echo
    echo "Thank you for using VPN Management System!"
}

# Main uninstallation function
main() {
    check_root
    confirm_uninstall
    
    # Perform uninstallation steps
    stop_services
    create_backup
    remove_systemd_units
    remove_binaries
    remove_installation_directory
    remove_docker_resources
    cleanup_logs
    
    post_uninstall_summary
}

# Handle script arguments
case "${1:-}" in
    --force)
        BACKUP_ENABLED=false
        check_root
        stop_services
        remove_systemd_units
        remove_binaries
        remove_installation_directory
        remove_docker_resources
        cleanup_logs
        print_success "Forced uninstallation completed"
        ;;
    --help|-h)
        echo "VPN Management System Uninstaller"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --force    Uninstall without confirmation or backup"
        echo "  --help     Show this help message"
        echo
        ;;
    *)
        main "$@"
        ;;
esac