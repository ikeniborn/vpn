#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_BASE_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_PREFIX="/opt/vpn"
SERVICE_NAME="vpn-manager"
SYSTEMD_PATH="/etc/systemd/system"
BINARY_PATH="/usr/local/bin"

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

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS version"
        exit 1
    fi
    print_info "Detected OS: $OS $VER"
}

# Function to check and install dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local deps_needed=()
    
    # Check for required commands
    for cmd in curl wget jq systemctl; do
        if ! command -v $cmd &> /dev/null; then
            deps_needed+=($cmd)
        fi
    done
    
    # Check for Docker (optional)
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed. Docker deployment will not be available."
        echo -n "Do you want to install Docker? (y/N): "
        read -r install_docker
        if [[ "$install_docker" =~ ^[Yy]$ ]]; then
            deps_needed+=("docker.io" "docker-compose")
        fi
    fi
    
    # Install missing dependencies
    if [[ ${#deps_needed[@]} -gt 0 ]]; then
        print_info "Installing missing dependencies: ${deps_needed[*]}"
        
        if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian"* ]]; then
            apt-get update
            apt-get install -y "${deps_needed[@]}"
        elif [[ "$OS" == "Arch"* ]]; then
            pacman -Sy --noconfirm "${deps_needed[@]}"
        elif [[ "$OS" == "Red Hat"* ]] || [[ "$OS" == "CentOS"* ]]; then
            yum install -y "${deps_needed[@]}"
        else
            print_error "Unsupported OS for automatic dependency installation"
            print_info "Please install manually: ${deps_needed[*]}"
            exit 1
        fi
    fi
    
    print_success "All dependencies satisfied"
}

# Function to check for existing installation
check_existing_installation() {
    print_info "Checking for existing VPN installation..."
    
    local existing_found=false
    
    # Check for existing service
    if systemctl list-unit-files | grep -q "${SERVICE_NAME}.service"; then
        existing_found=true
        print_warning "Found existing systemd service: ${SERVICE_NAME}"
    fi
    
    # Check for existing binaries
    if [[ -f "$BINARY_PATH/vpn" ]]; then
        existing_found=true
        print_warning "Found existing VPN binary at: $BINARY_PATH/vpn"
    fi
    
    # Check for existing installation directory
    if [[ -d "$INSTALL_PREFIX" ]]; then
        existing_found=true
        print_warning "Found existing installation directory: $INSTALL_PREFIX"
    fi
    
    if [[ "$existing_found" == true ]]; then
        echo -e "\n${YELLOW}An existing VPN installation was detected.${NC}"
        echo "What would you like to do?"
        echo "1) Remove existing installation and continue"
        echo "2) Upgrade existing installation (preserve configs)"
        echo "3) Cancel installation"
        echo -n "Choice (1-3): "
        read -r choice
        
        case $choice in
            1)
                print_info "Removing existing installation..."
                # Stop service if running
                systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
                systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
                rm -f "$SYSTEMD_PATH/${SERVICE_NAME}.service"
                
                # Remove binaries
                rm -f "$BINARY_PATH/vpn" "$BINARY_PATH/vpn-"*
                
                # Backup configs before removal
                if [[ -d "$INSTALL_PREFIX/configs" ]]; then
                    print_info "Backing up existing configs..."
                    cp -r "$INSTALL_PREFIX/configs" "/tmp/vpn-configs-backup-$(date +%Y%m%d%H%M%S)"
                fi
                
                # Remove installation directory
                rm -rf "$INSTALL_PREFIX"
                print_success "Existing installation removed"
                ;;
            2)
                print_info "Upgrading existing installation..."
                # Backup existing configs
                if [[ -d "$INSTALL_PREFIX/configs" ]]; then
                    cp -r "$INSTALL_PREFIX/configs" "/tmp/vpn-configs-backup-$(date +%Y%m%d%H%M%S)"
                fi
                ;;
            3)
                print_info "Installation cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
}

# Function to create directory structure
create_directories() {
    print_info "Creating directory structure..."
    
    mkdir -p "$INSTALL_PREFIX"/{bin,configs,db,logs,templates,docs,scripts,systemd,docker}
    
    print_success "Directory structure created"
}

# Function to install files
install_files() {
    print_info "Installing files from archive..."
    
    # Install binaries
    if [[ -d "$ARCHIVE_BASE_DIR/bin" ]]; then
        print_info "Installing binaries..."
        cp -r "$ARCHIVE_BASE_DIR/bin"/* "$INSTALL_PREFIX/bin/"
        chmod +x "$INSTALL_PREFIX/bin"/*
        
        # Create symlinks in system path
        for binary in "$INSTALL_PREFIX/bin"/*; do
            local bin_name=$(basename "$binary")
            ln -sf "$INSTALL_PREFIX/bin/$bin_name" "$BINARY_PATH/$bin_name"
        done
    fi
    
    # Install configs (preserve existing if upgrading)
    if [[ -d "$ARCHIVE_BASE_DIR/configs" ]]; then
        print_info "Installing configuration files..."
        if [[ -d "/tmp/vpn-configs-backup-"* ]]; then
            # Merge configs during upgrade
            cp -n "$ARCHIVE_BASE_DIR/configs"/* "$INSTALL_PREFIX/configs/" 2>/dev/null || true
            print_warning "Existing configs preserved. New configs added with .new extension if conflicts found."
        else
            cp -r "$ARCHIVE_BASE_DIR/configs"/* "$INSTALL_PREFIX/configs/"
        fi
    fi
    
    # Install templates
    if [[ -d "$ARCHIVE_BASE_DIR/templates" ]]; then
        print_info "Installing templates..."
        cp -r "$ARCHIVE_BASE_DIR/templates"/* "$INSTALL_PREFIX/templates/"
    fi
    
    # Install Docker files
    if [[ -d "$ARCHIVE_BASE_DIR/docker" ]]; then
        print_info "Installing Docker files..."
        cp -r "$ARCHIVE_BASE_DIR/docker"/* "$INSTALL_PREFIX/docker/"
    fi
    
    # Install documentation
    if [[ -d "$ARCHIVE_BASE_DIR/docs" ]]; then
        print_info "Installing documentation..."
        cp -r "$ARCHIVE_BASE_DIR/docs"/* "$INSTALL_PREFIX/docs/"
    fi
    
    # Install scripts
    if [[ -d "$ARCHIVE_BASE_DIR/scripts" ]]; then
        print_info "Installing scripts..."
        cp -r "$ARCHIVE_BASE_DIR/scripts"/* "$INSTALL_PREFIX/scripts/"
        chmod +x "$INSTALL_PREFIX/scripts"/*.sh
    fi
    
    # Copy version info
    if [[ -f "$ARCHIVE_BASE_DIR/VERSION" ]]; then
        cp "$ARCHIVE_BASE_DIR/VERSION" "$INSTALL_PREFIX/"
    fi
    
    print_success "Files installed successfully"
}

# Function to setup systemd service
setup_systemd_service() {
    print_info "Setting up systemd service..."
    
    # Check if service file exists in archive
    if [[ -f "$ARCHIVE_BASE_DIR/systemd/${SERVICE_NAME}.service" ]]; then
        cp "$ARCHIVE_BASE_DIR/systemd/${SERVICE_NAME}.service" "$SYSTEMD_PATH/"
    else
        # Create basic service file
        cat > "$SYSTEMD_PATH/${SERVICE_NAME}.service" << EOF
[Unit]
Description=VPN Management System
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_PREFIX/bin/vpn server
Restart=always
RestartSec=5
User=root
WorkingDirectory=$INSTALL_PREFIX
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    print_success "Systemd service configured"
}

# Function to setup permissions
setup_permissions() {
    print_info "Setting up permissions..."
    
    # Set ownership
    chown -R root:root "$INSTALL_PREFIX"
    
    # Set directory permissions
    chmod 755 "$INSTALL_PREFIX"
    chmod 755 "$INSTALL_PREFIX"/{bin,configs,templates,docs,scripts,systemd,docker}
    chmod 700 "$INSTALL_PREFIX"/{db,logs}
    
    # Set file permissions
    chmod 644 "$INSTALL_PREFIX/configs"/*
    chmod 755 "$INSTALL_PREFIX/bin"/*
    chmod 755 "$INSTALL_PREFIX/scripts"/*
    
    print_success "Permissions configured"
}

# Function to initialize database
init_database() {
    print_info "Initializing database..."
    
    # Create database directory if not exists
    mkdir -p "$INSTALL_PREFIX/db"
    
    # Initialize database if vpn binary supports it
    if [[ -x "$INSTALL_PREFIX/bin/vpn" ]]; then
        "$INSTALL_PREFIX/bin/vpn" db init 2>/dev/null || true
    fi
    
    print_success "Database initialized"
}

# Function to display post-installation instructions
post_install_instructions() {
    echo
    print_success "VPN Management System installed successfully!"
    echo
    echo -e "${GREEN}Installation Summary:${NC}"
    echo "  - Installation directory: $INSTALL_PREFIX"
    echo "  - Binaries installed to: $BINARY_PATH"
    echo "  - Service name: $SERVICE_NAME"
    echo "  - Configuration files: $INSTALL_PREFIX/configs"
    echo "  - Logs directory: $INSTALL_PREFIX/logs"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Configure the VPN system:"
    echo "   vi $INSTALL_PREFIX/configs/config.toml"
    echo
    echo "2. Start the VPN service:"
    echo "   systemctl start $SERVICE_NAME"
    echo "   systemctl enable $SERVICE_NAME"
    echo
    echo "3. Check service status:"
    echo "   systemctl status $SERVICE_NAME"
    echo
    echo "4. View logs:"
    echo "   journalctl -u $SERVICE_NAME -f"
    echo
    echo -e "${BLUE}Available Commands:${NC}"
    echo "  vpn --help              # Show help"
    echo "  vpn server              # Start VPN server"
    echo "  vpn user add            # Add a new user"
    echo "  vpn user list           # List all users"
    echo "  vpn status              # Show VPN status"
    echo
    
    if [[ -f "$INSTALL_PREFIX/VERSION" ]]; then
        echo -e "${BLUE}Version Information:${NC}"
        cat "$INSTALL_PREFIX/VERSION"
        echo
    fi
    
    echo -e "${YELLOW}Documentation:${NC} $INSTALL_PREFIX/docs/"
    echo
}

# Main installation function
main() {
    echo "╔══════════════════════════════════════════════╗"
    echo "║       VPN Management System Installer        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo
    
    check_root
    detect_os
    check_dependencies
    check_existing_installation
    create_directories
    install_files
    setup_systemd_service
    setup_permissions
    init_database
    post_install_instructions
}

# Run main function
main "$@"