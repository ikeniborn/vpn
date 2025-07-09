#!/bin/bash

# VPN Manager - One-line installation script
# Usage: curl -fsSL https://get.vpn-manager.io | bash

set -e

# Configuration
REPO_URL="https://github.com/ikeniborn/vpn-manager"
INSTALL_DIR="/opt/vpn-manager"
CONFIG_DIR="/etc/vpn-manager"
LOG_DIR="/var/log/vpn-manager"
SERVICE_USER="vpn-manager"
PYTHON_MIN_VERSION="3.10"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check Python version
check_python() {
    log "Checking Python version..."
    
    # Try python3 first
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        error "Python not found. Please install Python ${PYTHON_MIN_VERSION} or higher"
        exit 1
    fi
    
    # Check version
    PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    
    if [[ $(echo "$PYTHON_VERSION >= $PYTHON_MIN_VERSION" | bc) -eq 0 ]]; then
        error "Python $PYTHON_VERSION is too old. Required: $PYTHON_MIN_VERSION or higher"
        exit 1
    fi
    
    success "Python $PYTHON_VERSION found"
}

# Check system dependencies
check_dependencies() {
    log "Checking system dependencies..."
    
    local missing_deps=()
    
    # Check for required commands
    local required_cmds=("git" "curl" "tar")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for Docker (optional but recommended)
    if ! command -v docker &> /dev/null; then
        warn "Docker not found. Docker is required for VPN server functionality"
    else
        success "Docker found"
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        error "Please install them using your package manager"
        exit 1
    fi
    
    success "All required dependencies found"
}

# Install Python package
install_python_package() {
    log "Installing VPN Manager..."
    
    # Install using pip
    if [[ "$1" == "dev" ]]; then
        log "Installing in development mode..."
        cd "$INSTALL_DIR"
        $PYTHON_CMD -m pip install -e ".[dev]" --user
    else
        log "Installing from PyPI..."
        $PYTHON_CMD -m pip install vpn-manager --user
    fi
    
    # Add user's pip bin to PATH if needed
    local pip_bin="$HOME/.local/bin"
    if [[ ":$PATH:" != *":$pip_bin:"* ]]; then
        log "Adding $pip_bin to PATH..."
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        export PATH="$pip_bin:$PATH"
    fi
    
    success "VPN Manager installed successfully"
}

# Setup configuration
setup_config() {
    log "Setting up configuration..."
    
    # Create config directory
    mkdir -p "$HOME/.config/vpn-manager"
    
    # Initialize configuration
    vpn config init
    
    success "Configuration initialized"
}

# Run post-installation checks
post_install_checks() {
    log "Running post-installation checks..."
    
    # Run doctor command
    vpn doctor
    
    success "Post-installation checks complete"
}

# Show completion message
show_completion() {
    echo
    echo "========================================"
    echo "   VPN Manager Installation Complete!"
    echo "========================================"
    echo
    echo "Installation summary:"
    echo "  ✓ Python package installed"
    echo "  ✓ Configuration initialized"
    echo "  ✓ System checks passed"
    echo
    echo "Quick start commands:"
    echo "  • vpn --help        - Show available commands"
    echo "  • vpn doctor        - Run system diagnostics"
    echo "  • vpn tui           - Launch terminal UI"
    echo "  • vpn users create  - Create a new user"
    echo
    echo "Configuration file: ~/.config/vpn-manager/config.toml"
    echo
    echo "For more information, visit:"
    echo "https://github.com/ikeniborn/vpn-manager"
    echo
}

# Main installation process
main() {
    echo "========================================"
    echo "     VPN Manager Installer"
    echo "========================================"
    echo
    
    # Parse arguments
    local install_mode="release"
    if [[ "$1" == "--dev" ]]; then
        install_mode="dev"
        log "Development mode installation"
    fi
    
    # Check system
    check_python
    check_dependencies
    
    # Install package
    if [[ "$install_mode" == "dev" ]]; then
        # Clone repository for development
        log "Cloning repository..."
        if [[ -d "$INSTALL_DIR" ]]; then
            warn "Directory $INSTALL_DIR already exists"
            read -p "Remove and continue? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$INSTALL_DIR"
            else
                error "Installation cancelled"
                exit 1
            fi
        fi
        
        git clone "$REPO_URL" "$INSTALL_DIR"
        install_python_package "dev"
    else
        install_python_package
    fi
    
    # Setup and verify
    setup_config
    post_install_checks
    
    # Show completion
    show_completion
}

# Run main function
main "$@"