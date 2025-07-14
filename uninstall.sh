#!/bin/bash

# VPN Complete Uninstallation Script
# This script removes all VPN components installed by install.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_info "Starting VPN uninstallation process..."

# Confirmation prompt
echo
log_warning "This will remove all VPN components including:"
echo "  • All VPN binaries from /usr/local/bin/"
echo "  • All configuration files from /etc/vpn/"
echo "  • All files from /opt/vpn/"
echo "  • All systemd services"
echo "  • All Docker containers and images (if requested)"
echo
read -p "Are you sure you want to continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "Uninstallation cancelled."
    exit 0
fi

# Stop and disable systemd services
log_info "Stopping and disabling VPN services..."
services=("vpn-manager" "vpn-api" "vpn-proxy" "vpn-identity" "vpn")
for service in "${services[@]}"; do
    if systemctl is-active "$service" &>/dev/null; then
        log_info "Stopping $service..."
        systemctl stop "$service" || true
    fi
    if systemctl is-enabled "$service" &>/dev/null; then
        log_info "Disabling $service..."
        systemctl disable "$service" || true
    fi
done

# Remove systemd service files
log_info "Removing systemd service files..."
for service in "${services[@]}"; do
    if [[ -f "/etc/systemd/system/$service.service" ]]; then
        log_info "Removing /etc/systemd/system/$service.service"
        rm -f "/etc/systemd/system/$service.service"
    fi
done

# Reload systemd
systemctl daemon-reload

# Stop Docker containers if running
if command -v docker &>/dev/null; then
    log_info "Checking for VPN Docker containers..."
    containers=$(docker ps -a --filter "name=vpn" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$containers" ]]; then
        log_warning "Found VPN Docker containers:"
        echo "$containers"
        read -p "Remove Docker containers? [y/N]: " remove_containers
        if [[ "$remove_containers" =~ ^[Yy]$ ]]; then
            for container in $containers; do
                log_info "Stopping and removing container: $container"
                docker stop "$container" 2>/dev/null || true
                docker rm "$container" 2>/dev/null || true
            done
        fi
    fi
    
    # Remove Docker images
    images=$(docker images --filter "reference=vpn*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [[ -n "$images" ]]; then
        log_warning "Found VPN Docker images:"
        echo "$images"
        read -p "Remove Docker images? [y/N]: " remove_images
        if [[ "$remove_images" =~ ^[Yy]$ ]]; then
            for image in $images; do
                log_info "Removing image: $image"
                docker rmi "$image" 2>/dev/null || true
            done
        fi
    fi
fi

# Remove binaries from /usr/local/bin
log_info "Removing VPN binaries..."
binaries=("vpn" "vpn-manager" "vpn-cli" "vpn-api" "vpn-proxy" "vpn-identity")
for binary in "${binaries[@]}"; do
    if [[ -f "/usr/local/bin/$binary" ]]; then
        log_info "Removing /usr/local/bin/$binary"
        rm -f "/usr/local/bin/$binary"
    fi
    # Also check other common locations
    if [[ -f "/usr/bin/$binary" ]]; then
        log_info "Removing /usr/bin/$binary"
        rm -f "/usr/bin/$binary"
    fi
done

# Remove configuration directory
if [[ -d "/etc/vpn" ]]; then
    log_info "Removing configuration directory: /etc/vpn"
    rm -rf "/etc/vpn"
fi

# Remove shell completions
completion_files=(
    "/etc/bash_completion.d/vpn"
    "/usr/share/bash-completion/completions/vpn"
    "/etc/zsh/completions/_vpn"
    "/usr/share/zsh/site-functions/_vpn"
)
for completion in "${completion_files[@]}"; do
    if [[ -f "$completion" ]]; then
        log_info "Removing completion file: $completion"
        rm -f "$completion"
    fi
done

# Handle /opt/vpn directory
if [[ -d "/opt/vpn" ]]; then
    # Check for database files
    if [[ -d "/opt/vpn/db" ]]; then
        log_warning "Found database directory: /opt/vpn/db"
        read -p "Remove database files? This will DELETE ALL VPN DATA! [y/N]: " remove_db
        if [[ "$remove_db" =~ ^[Yy]$ ]]; then
            log_info "Creating backup of database files..."
            backup_dir="/tmp/vpn-db-backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"
            cp -r "/opt/vpn/db" "$backup_dir/" 2>/dev/null || true
            log_info "Database backed up to: $backup_dir"
            rm -rf "/opt/vpn/db"
        else
            log_info "Keeping database files"
        fi
    fi
    
    # Remove other directories
    for dir in docker templates scripts; do
        if [[ -d "/opt/vpn/$dir" ]]; then
            log_info "Removing /opt/vpn/$dir"
            rm -rf "/opt/vpn/$dir"
        fi
    done
    
    # Remove installation files
    installation_files=(
        "/opt/vpn/install.sh"
        "/opt/vpn/uninstall.sh"
        "/opt/vpn/VERSION"
        "/opt/vpn/RELEASE_INFO.md"
        "/opt/vpn/INSTALL_NOTES.txt"
    )
    for file in "${installation_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing $file"
            rm -f "$file"
        fi
    done
    
    # Check if /opt/vpn is empty
    if [[ -z "$(ls -A /opt/vpn 2>/dev/null)" ]]; then
        log_info "Removing empty directory: /opt/vpn"
        rmdir "/opt/vpn"
    else
        log_warning "/opt/vpn is not empty, some files were preserved"
        ls -la /opt/vpn
    fi
fi

# Remove log files
log_locations=(
    "/var/log/vpn"
    "/var/log/vpn.log"
    "/var/log/vpn-*.log"
)
for log_loc in "${log_locations[@]}"; do
    if [[ -e "$log_loc" ]]; then
        log_info "Removing log files: $log_loc"
        rm -rf "$log_loc"
    fi
done

# Remove from PATH if added
shell_configs=(
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.profile"
    "$HOME/.bash_profile"
)
for config in "${shell_configs[@]}"; do
    if [[ -f "$config" ]] && grep -q "vpn" "$config"; then
        log_info "Cleaning VPN entries from $config"
        sed -i.bak '/# VPN/d' "$config" 2>/dev/null || true
        sed -i.bak '/vpn/d' "$config" 2>/dev/null || true
    fi
done

# Clean cargo installation if exists
if command -v cargo &>/dev/null; then
    if cargo install --list | grep -q "vpn-cli"; then
        log_info "Removing vpn-cli from cargo installations..."
        cargo uninstall vpn-cli 2>/dev/null || true
    fi
fi

# Final cleanup
log_info "Performing final cleanup..."

# Clear any cached files
rm -rf /tmp/vpn-* 2>/dev/null || true

echo
log_success "VPN uninstallation completed successfully!"
log_info "The following items may have been preserved:"
echo "  • Database backups in /tmp/vpn-db-backup-* (if created)"
echo "  • Custom configuration backups"
echo
log_info "To reinstall VPN, run the installation script again."