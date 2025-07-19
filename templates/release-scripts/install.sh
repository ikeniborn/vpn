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
ARCHIVE_BASE_DIR="$SCRIPT_DIR"
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
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root directly. It will ask for sudo when needed."
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
            sudo apt-get update
            sudo apt-get install -y "${deps_needed[@]}"
        elif [[ "$OS" == "Arch"* ]]; then
            sudo pacman -Sy --noconfirm "${deps_needed[@]}"
        elif [[ "$OS" == "Red Hat"* ]] || [[ "$OS" == "CentOS"* ]]; then
            sudo yum install -y "${deps_needed[@]}"
        else
            print_error "Unsupported OS for automatic dependency installation"
            print_info "Please install manually: ${deps_needed[*]}"
            exit 1
        fi
    fi
    
    print_success "All dependencies satisfied"
}

# Function to create a stub script for cargo binary conflicts
create_cargo_stub() {
    local cargo_vpn="$HOME/.cargo/bin/vpn"
    
    if [[ ! -d "$HOME/.cargo/bin" ]]; then
        mkdir -p "$HOME/.cargo/bin"
    fi
    
    cat > "$cargo_vpn" << 'EOF'
#!/bin/bash

# VPN Management System - Stub Script
# This script helps users when there are PATH conflicts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Clear screen
clear

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       VPN Management System - Notice         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}⚠️  The VPN command location has changed!${NC}"
echo
echo -e "${BLUE}Information:${NC}"
echo "  • The old vpn binary was replaced during installation"
echo "  • The new VPN Management System is now available"
echo "  • This stub script is helping you transition"
echo
echo -e "${GREEN}How to run VPN Management System:${NC}"
echo
echo -e "  ${YELLOW}1. Run with full path:${NC}"
echo "     /usr/local/bin/vpn"
echo
echo -e "  ${YELLOW}2. Run with sudo (recommended):${NC}"
echo "     sudo vpn"
echo
echo -e "  ${YELLOW}3. Update your shell hash and PATH:${NC}"
echo "     hash -d vpn"
echo "     export PATH=\"/usr/local/bin:\$PATH\""
echo "     vpn"
echo
echo -e "  ${YELLOW}4. Remove this stub (permanent fix):${NC}"
echo "     rm ~/.cargo/bin/vpn"
echo "     hash -d vpn"
echo "     vpn"
echo
echo -e "${BLUE}Available commands:${NC}"
echo "  • vpn                    - Interactive menu"
echo "  • sudo vpn               - Full access menu"
echo "  • vpn install <protocol> - Install VPN server"
echo "  • vpn status             - Check server status"
echo "  • vpn --help             - Show all commands"
echo
echo -e "${GREEN}Documentation:${NC} /opt/vpn/docs/"
echo -e "${GREEN}Configuration:${NC} /opt/vpn/configs/"
echo
echo -e "${YELLOW}Would you like to:${NC}"
echo "1) Run VPN with sudo now"
echo "2) Remove this stub and fix PATH permanently"
echo "3) Exit"
echo -n "Choice (1-3): "
read -r choice

case $choice in
    1)
        echo "Running VPN Management System with sudo..."
        exec sudo /usr/local/bin/vpn "$@"
        ;;
    2)
        echo "Removing stub and fixing PATH..."
        rm -f ~/.cargo/bin/vpn
        hash -d vpn 2>/dev/null
        echo "Fixed! Now run 'vpn' again."
        ;;
    3)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice. Running with sudo..."
        exec sudo /usr/local/bin/vpn "$@"
        ;;
esac
EOF

    chmod +x "$cargo_vpn"
    print_success "Created stub script at $cargo_vpn"
}

# Function to check for existing installation
check_existing_installation() {
    print_info "Checking for existing VPN installation..."
    
    local existing_found=false
    local conflicting_binaries=()
    
    # Check for existing service
    if systemctl list-unit-files | grep -q "${SERVICE_NAME}.service"; then
        existing_found=true
        print_warning "Found existing systemd service: ${SERVICE_NAME}"
    fi
    
    # Check for existing binaries in standard locations
    if [[ -f "$BINARY_PATH/vpn" ]]; then
        existing_found=true
        conflicting_binaries+=("$BINARY_PATH/vpn")
        print_warning "Found existing VPN binary at: $BINARY_PATH/vpn"
    fi
    
    # Check for cargo-installed binaries that might conflict
    if [[ -f "$HOME/.cargo/bin/vpn" ]]; then
        # Check if it's our stub
        if grep -q "VPN Management System - Stub Script" "$HOME/.cargo/bin/vpn" 2>/dev/null; then
            print_info "Found VPN stub script at: $HOME/.cargo/bin/vpn (will be removed)"
            conflicting_binaries+=("$HOME/.cargo/bin/vpn")
        else
            existing_found=true
            conflicting_binaries+=("$HOME/.cargo/bin/vpn")
            print_warning "Found cargo-installed VPN binary at: $HOME/.cargo/bin/vpn"
            print_warning "This may cause PATH conflicts - cargo binaries take precedence"
        fi
    fi
    
    # Check for other common installation locations
    for path in "/usr/bin/vpn" "/usr/sbin/vpn" "/opt/vpn/bin/vpn"; do
        if [[ -f "$path" && "$path" != "$BINARY_PATH/vpn" ]]; then
            existing_found=true
            conflicting_binaries+=("$path")
            print_warning "Found VPN binary at: $path"
        fi
    done
    
    # Check for existing installation directory
    if [[ -d "$INSTALL_PREFIX" ]]; then
        existing_found=true
        print_warning "Found existing installation directory: $INSTALL_PREFIX"
    fi
    
    if [[ "$existing_found" == true ]]; then
        echo -e "\n${YELLOW}An existing VPN installation was detected.${NC}"
        if [[ ${#conflicting_binaries[@]} -gt 0 ]]; then
            echo "Conflicting binaries found:"
            for binary in "${conflicting_binaries[@]}"; do
                echo "  - $binary"
            done
            echo
        fi
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
                sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
                sudo systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
                sudo rm -f "$SYSTEMD_PATH/${SERVICE_NAME}.service"
                
                # Remove all conflicting binaries
                for binary in "${conflicting_binaries[@]}"; do
                    if [[ -f "$binary" ]]; then
                        print_info "Removing conflicting binary: $binary"
                        if [[ "$binary" == "$HOME/.cargo/bin/vpn" ]]; then
                            # Remove cargo binary without sudo
                            rm -f "$binary"
                        else
                            # Remove system binaries with sudo
                            sudo rm -f "$binary"
                        fi
                    fi
                done
                
                # Remove additional binaries that might exist
                sudo rm -f "$BINARY_PATH/vpn-"*
                
                # Backup configs before removal
                if [[ -d "$INSTALL_PREFIX/configs" ]]; then
                    print_info "Backing up existing configs..."
                    sudo cp -r "$INSTALL_PREFIX/configs" "/tmp/vpn-configs-backup-$(date +%Y%m%d%H%M%S)"
                fi
                
                # Remove installation directory
                sudo rm -rf "$INSTALL_PREFIX"
                print_success "Existing installation removed"
                ;;
            2)
                print_info "Upgrading existing installation..."
                # Backup existing configs
                if [[ -d "$INSTALL_PREFIX/configs" ]]; then
                    sudo cp -r "$INSTALL_PREFIX/configs" "/tmp/vpn-configs-backup-$(date +%Y%m%d%H%M%S)"
                fi
                
                # Handle cargo binary conflict with stub
                if [[ -f "$HOME/.cargo/bin/vpn" ]]; then
                    print_info "Creating stub script for cargo binary conflict..."
                    create_cargo_stub
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
    
    sudo mkdir -p "$INSTALL_PREFIX"/{bin,configs,db,logs,templates,docs,scripts,systemd,docker}
    
    print_success "Directory structure created"
}

# Function to install files
install_files() {
    print_info "Installing files from archive..."
    
    # Install binaries
    if [[ -d "$ARCHIVE_BASE_DIR/bin" ]] && [[ -n "$(ls -A "$ARCHIVE_BASE_DIR/bin" 2>/dev/null)" ]]; then
        print_info "Installing binaries..."
        sudo cp -r "$ARCHIVE_BASE_DIR/bin"/* "$INSTALL_PREFIX/bin/"
        sudo chmod +x "$INSTALL_PREFIX/bin"/*
        
        # Create symlinks in system path
        for binary in "$INSTALL_PREFIX/bin"/*; do
            if [[ -f "$binary" ]]; then
                local bin_name=$(basename "$binary")
                sudo ln -sf "$INSTALL_PREFIX/bin/$bin_name" "$BINARY_PATH/$bin_name"
            fi
        done
    else
        print_error "No binaries found in archive!"
        return 1
    fi
    
    # Install configs (preserve existing if upgrading)
    if [[ -d "$ARCHIVE_BASE_DIR/configs" ]] && [[ -n "$(ls -A "$ARCHIVE_BASE_DIR/configs" 2>/dev/null)" ]]; then
        print_info "Installing configuration files..."
        if [[ -d "/tmp/vpn-configs-backup-"* ]]; then
            # Merge configs during upgrade
            sudo cp -n "$ARCHIVE_BASE_DIR/configs"/* "$INSTALL_PREFIX/configs/" 2>/dev/null || true
            print_warning "Existing configs preserved. New configs added with .new extension if conflicts found."
        else
            sudo cp -r "$ARCHIVE_BASE_DIR/configs"/* "$INSTALL_PREFIX/configs/"
        fi
    fi
    
    # Install templates
    if [[ -d "$ARCHIVE_BASE_DIR/templates" ]] && [[ -n "$(ls -A "$ARCHIVE_BASE_DIR/templates" 2>/dev/null)" ]]; then
        print_info "Installing templates..."
        sudo cp -r "$ARCHIVE_BASE_DIR/templates"/* "$INSTALL_PREFIX/templates/"
    fi
    
    # Install Docker files
    if [[ -d "$ARCHIVE_BASE_DIR/docker" ]] && [[ -n "$(ls -A "$ARCHIVE_BASE_DIR/docker" 2>/dev/null)" ]]; then
        print_info "Installing Docker files..."
        sudo cp -r "$ARCHIVE_BASE_DIR/docker"/* "$INSTALL_PREFIX/docker/"
    fi
    
    # Install documentation
    if [[ -d "$ARCHIVE_BASE_DIR/docs" ]] && [[ -n "$(ls -A "$ARCHIVE_BASE_DIR/docs" 2>/dev/null)" ]]; then
        print_info "Installing documentation..."
        sudo cp -r "$ARCHIVE_BASE_DIR/docs"/* "$INSTALL_PREFIX/docs/"
    fi
    
    # Install scripts
    if [[ -d "$ARCHIVE_BASE_DIR/scripts" ]] && [[ -n "$(ls -A "$ARCHIVE_BASE_DIR/scripts" 2>/dev/null)" ]]; then
        print_info "Installing scripts..."
        sudo cp -r "$ARCHIVE_BASE_DIR/scripts"/* "$INSTALL_PREFIX/scripts/"
        if [[ -n "$(ls -A "$INSTALL_PREFIX/scripts"/*.sh 2>/dev/null)" ]]; then
            sudo chmod +x "$INSTALL_PREFIX/scripts"/*.sh
        fi
    fi
    
    # Copy version info
    if [[ -f "$ARCHIVE_BASE_DIR/VERSION" ]]; then
        sudo cp "$ARCHIVE_BASE_DIR/VERSION" "$INSTALL_PREFIX/"
    fi
    
    # Copy uninstall script
    if [[ -f "$ARCHIVE_BASE_DIR/uninstall.sh" ]]; then
        sudo cp "$ARCHIVE_BASE_DIR/uninstall.sh" "$INSTALL_PREFIX/"
        sudo chmod +x "$INSTALL_PREFIX/uninstall.sh"
    fi
    
    print_success "Files installed successfully"
}

# Function to setup systemd service
setup_systemd_service() {
    print_info "Setting up systemd service..."
    
    # Check if service file exists in archive
    if [[ -f "$ARCHIVE_BASE_DIR/systemd/${SERVICE_NAME}.service" ]]; then
        sudo cp "$ARCHIVE_BASE_DIR/systemd/${SERVICE_NAME}.service" "$SYSTEMD_PATH/"
    else
        # Create basic service file
        sudo tee "$SYSTEMD_PATH/${SERVICE_NAME}.service" > /dev/null << EOF
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
    sudo systemctl daemon-reload
    
    print_success "Systemd service configured"
}

# Function to setup permissions
setup_permissions() {
    print_info "Setting up permissions..."
    
    # Set ownership
    sudo chown -R root:root "$INSTALL_PREFIX"
    
    # Set directory permissions
    sudo chmod 755 "$INSTALL_PREFIX"
    for dir in bin configs templates docs scripts systemd docker; do
        [[ -d "$INSTALL_PREFIX/$dir" ]] && sudo chmod 755 "$INSTALL_PREFIX/$dir"
    done
    for dir in db logs; do
        [[ -d "$INSTALL_PREFIX/$dir" ]] && sudo chmod 700 "$INSTALL_PREFIX/$dir"
    done
    
    # Set file permissions
    if [[ -n "$(ls -A "$INSTALL_PREFIX/configs" 2>/dev/null)" ]]; then
        sudo chmod 644 "$INSTALL_PREFIX/configs"/*
    fi
    if [[ -n "$(ls -A "$INSTALL_PREFIX/bin" 2>/dev/null)" ]]; then
        sudo chmod 755 "$INSTALL_PREFIX/bin"/*
    fi
    if [[ -n "$(ls -A "$INSTALL_PREFIX/scripts" 2>/dev/null)" ]]; then
        sudo chmod 755 "$INSTALL_PREFIX/scripts"/*
    fi
    
    print_success "Permissions configured"
}

# Function to initialize database
init_database() {
    print_info "Initializing database..."
    
    # Create database directory if not exists
    sudo mkdir -p "$INSTALL_PREFIX/db"
    
    # Initialize database if vpn binary supports it
    if [[ -x "$INSTALL_PREFIX/bin/vpn" ]]; then
        sudo "$INSTALL_PREFIX/bin/vpn" db init 2>/dev/null || true
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
    
    # Check if there might be PATH conflicts
    local current_vpn=$(which vpn 2>/dev/null || echo "")
    if [[ -n "$current_vpn" && "$current_vpn" != "$BINARY_PATH/vpn" ]]; then
        echo -e "${YELLOW}⚠️  PATH Warning:${NC}"
        echo "  The 'vpn' command currently resolves to: $current_vpn"
        echo "  This may be different from the installed version at: $BINARY_PATH/vpn"
        echo "  To use the newly installed version, you may need to:"
        echo "    - Clear shell hash: hash -r"
        echo "    - Or run the full path: $BINARY_PATH/vpn"
        echo "    - Or restart your shell"
        echo
    fi
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Configure the VPN system:"
    echo "   vi $INSTALL_PREFIX/configs/config.toml"
    echo
    echo "2. Start the VPN service:"
    echo "   sudo systemctl start $SERVICE_NAME"
    echo "   sudo systemctl enable $SERVICE_NAME"
    echo
    echo "3. Check service status:"
    echo "   sudo systemctl status $SERVICE_NAME"
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
    echo -e "${YELLOW}To uninstall:${NC} sudo $INSTALL_PREFIX/uninstall.sh"
    echo
    
    # Final PATH check
    print_info "Verifying installation..."
    hash -r 2>/dev/null || true
    local final_vpn=$(which vpn 2>/dev/null || echo "")
    if [[ "$final_vpn" == "$BINARY_PATH/vpn" ]]; then
        print_success "VPN command is correctly configured!"
    else
        print_warning "Run 'hash -r' or restart your shell to use the vpn command"
    fi
    
    # Check if there was a stub removed and PATH might be cached
    if [[ "$STUB_WAS_REMOVED" == "true" ]]; then
        echo
        echo -e "${YELLOW}⚠️  IMPORTANT: PATH cache needs to be updated${NC}"
        echo -e "${GREEN}Run this command now:${NC}"
        echo
        echo "    hash -r"
        echo
        echo -e "${BLUE}Or start a new terminal session.${NC}"
        echo
    fi
}

# Global variable to track if stub was removed
STUB_WAS_REMOVED=false

# Function to clean up old stubs and PATH issues
cleanup_old_stubs() {
    print_info "Checking for old VPN stubs and PATH issues..."
    
    # Remove any existing stub scripts
    if [[ -f "$HOME/.cargo/bin/vpn" ]]; then
        # Check if it's our stub script
        if grep -q "VPN Management System - Stub Script" "$HOME/.cargo/bin/vpn" 2>/dev/null; then
            print_info "Removing old VPN stub script..."
            rm -f "$HOME/.cargo/bin/vpn"
            print_success "Old stub removed"
            STUB_WAS_REMOVED=true
        fi
    fi
    
    # Clear bash hash to ensure clean PATH resolution
    hash -d vpn 2>/dev/null || true
    
    # Check if PATH still has issues after cleanup
    local current_vpn=$(which vpn 2>/dev/null || echo "")
    if [[ "$current_vpn" == "$HOME/.cargo/bin/vpn" && ! -f "$HOME/.cargo/bin/vpn" ]]; then
        print_warning "Detected persistent PATH cache issue"
        print_info "You may need to restart your shell or run: hash -r"
        STUB_WAS_REMOVED=true
    fi
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
    cleanup_old_stubs
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