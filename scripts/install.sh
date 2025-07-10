#!/bin/bash

# VPN Manager - One-line installation script
# Usage: curl -fsSL https://get.vpn-manager.io | bash

set -e

# Configuration
REPO_URL="https://github.com/ikeniborn/vpn"
INSTALL_DIR="$HOME/.vpn"
VENV_DIR="$HOME/.vpn-venv"
CONFIG_DIR="$HOME/.config/vpn-manager"
DATA_DIR="$HOME/.local/share/vpn-manager"
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

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        error "Cannot detect OS. This script supports Ubuntu and Debian."
        exit 1
    fi
}

# Install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Detect OS
    detect_os
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! command -v sudo &> /dev/null; then
        error "This script requires sudo privileges to install system dependencies"
        exit 1
    fi
    
    # Set sudo command
    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        SUDO="sudo"
    fi
    
    case $OS in
        ubuntu|debian)
            log "Detected $OS $VER"
            
            # Update package list
            $SUDO apt-get update -qq
            
            # Essential packages
            local packages=(
                "python3-pip"
                "python3-venv"
                "python3-dev"
                "python3-setuptools"
                "build-essential"
                "git"
                "curl"
                "wget"
                "tar"
                "gcc"
                "make"
                # For cryptography
                "libssl-dev"
                "libffi-dev"
                # For python-ldap
                "libldap2-dev"
                "libsasl2-dev"
                # For psycopg2
                "libpq-dev"
                # For lxml
                "libxml2-dev"
                "libxslt1-dev"
                # Network tools
                "net-tools"
                "iptables"
            )
            
            log "Installing required packages..."
            $SUDO apt-get install -y "${packages[@]}"
            
            # Install pipx if not present
            if ! command -v pipx &> /dev/null; then
                log "Installing pipx..."
                $SUDO apt-get install -y pipx
            fi
            
            success "System dependencies installed"
            ;;
        *)
            error "Unsupported OS: $OS"
            error "This script supports Ubuntu and Debian"
            exit 1
            ;;
    esac
}

# Check system dependencies
check_dependencies() {
    log "Checking system dependencies..."
    
    local missing_deps=()
    
    # Check for required commands
    local required_cmds=("git" "curl" "tar" "make" "gcc")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for required libraries
    local required_libs=(
        "/usr/include/openssl/ssl.h"
        "/usr/include/ldap.h"
    )
    
    for lib in "${required_libs[@]}"; do
        if [[ ! -f "$lib" ]]; then
            missing_deps+=("$(basename $lib)")
        fi
    done
    
    # Check for Docker (optional but recommended)
    if ! command -v docker &> /dev/null; then
        warn "Docker not found. Docker is required for VPN server functionality"
        warn "Install Docker with: curl -fsSL https://get.docker.com | bash"
    else
        success "Docker found"
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        warn "Missing dependencies detected: ${missing_deps[*]}"
        
        # Ask to install dependencies
        while true; do
            read -p "Would you like to install missing dependencies? (y/N): " -r REPLY
            # Convert to lowercase for case-insensitive comparison
            REPLY=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
            
            # Validate input
            if [[ "$REPLY" =~ ^(y|yes|n|no)$ ]] || [[ -z "$REPLY" ]]; then
                break
            else
                echo "Invalid input. Please enter Y/yes or N/no (or press Enter for default N)"
            fi
        done
        
        # Check for yes (default is no for this prompt)
        if [[ "$REPLY" =~ ^(y|yes)$ ]]; then
            install_system_deps
        else
            error "Please install missing dependencies manually"
            exit 1
        fi
    else
        success "All required dependencies found"
    fi
}

# Install Python package
install_python_package() {
    log "Installing VPN Manager..."
    
    # Always create and use virtual environment
    log "Creating virtual environment at $VENV_DIR..."
    
    # Remove old virtual environment if exists
    if [[ -d "$VENV_DIR" ]]; then
        log "Removing old virtual environment..."
        rm -rf "$VENV_DIR"
    fi
    
    # Create new virtual environment
    $PYTHON_CMD -m venv "$VENV_DIR"
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip
    log "Upgrading pip..."
    python -m pip install --upgrade pip setuptools wheel
    
    # Install package
    if [[ "$1" == "dev" ]]; then
        log "Installing in development mode..."
        cd "$INSTALL_DIR"
        python -m pip install -e ".[dev,test,docs]"
    elif [[ "$1" == "local" ]]; then
        log "Installing from local repository..."
        python -m pip install .
    else
        log "Installing from PyPI..."
        python -m pip install vpn-manager
    fi
    
    # Setup PATH and shell integration
    setup_shell_integration
    
    success "VPN Manager installed successfully"
}

# Setup shell integration
setup_shell_integration() {
    log "Setting up shell integration..."
    
    local shell_config=""
    
    # Detect shell
    if [[ -n "$BASH_VERSION" ]]; then
        shell_config="$HOME/.bashrc"
    elif [[ -n "$ZSH_VERSION" ]]; then
        shell_config="$HOME/.zshrc"
    else
        shell_config="$HOME/.profile"
    fi
    
    # Create shell integration script
    local vpn_init_script="$HOME/.vpn-init.sh"
    cat > "$vpn_init_script" << 'EOF'
# VPN Manager Shell Integration
export VPN_HOME="$HOME/.vpn"
export VPN_VENV="$HOME/.vpn-venv"

# Auto-activate VPN virtual environment if it exists
if [ -d "$VPN_VENV" ]; then
    export PATH="$VPN_VENV/bin:$PATH"
    export VIRTUAL_ENV="$VPN_VENV"
fi

# VPN Manager aliases
alias vpn-activate='source $VPN_VENV/bin/activate'
alias vpn-update='cd $VPN_HOME && git pull && source $VPN_VENV/bin/activate && pip install -U .'
EOF
    
    # Add to shell config if not already present
    if ! grep -q "vpn-init.sh" "$shell_config" 2>/dev/null; then
        echo "" >> "$shell_config"
        echo "# VPN Manager" >> "$shell_config"
        echo "[ -f ~/.vpn-init.sh ] && source ~/.vpn-init.sh" >> "$shell_config"
    fi
    
    # Also add to .profile for login shells
    if [[ "$shell_config" != "$HOME/.profile" ]] && ! grep -q "vpn-init.sh" "$HOME/.profile" 2>/dev/null; then
        echo "" >> "$HOME/.profile"
        echo "# VPN Manager" >> "$HOME/.profile"
        echo "[ -f ~/.vpn-init.sh ] && source ~/.vpn-init.sh" >> "$HOME/.profile"
    fi
    
    # Source the init script now
    source "$vpn_init_script"
    
    success "Shell integration configured"
}

# Setup configuration
setup_config() {
    log "Setting up configuration..."
    
    # Create config directories
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$DATA_DIR/logs"
    
    # Create default config file if not exists
    if [[ ! -f "$CONFIG_DIR/config.toml" ]]; then
        log "Creating default configuration file..."
        cat > "$CONFIG_DIR/config.toml" << 'EOF'
# VPN Manager Configuration
[app]
debug = false
log_level = "INFO"

[server]
default_protocol = "vless"
enable_firewall = true
auto_start_servers = true

[tui]
theme = "dark"
refresh_rate = 1
EOF
        success "Configuration file created"
    else
        log "Configuration file already exists"
    fi
    
    success "Configuration directories initialized"
}

# Run post-installation checks
post_install_checks() {
    log "Running post-installation checks..."
    
    # Check if vpn command is available
    if command -v vpn &> /dev/null; then
        # Try to get version
        if vpn --version &> /dev/null; then
            local version=$(vpn --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            success "VPN Manager $version installed successfully"
        else
            warn "VPN command found but version check failed"
        fi
        
        # Check directories
        if [[ -d "$CONFIG_DIR" ]] && [[ -d "$DATA_DIR" ]]; then
            success "Configuration directories created"
        fi
        
        # Check Python environment
        if [[ -n "$VIRTUAL_ENV" ]]; then
            success "Virtual environment activated"
        fi
    else
        warn "vpn command not found in PATH"
        warn "Run 'source ~/.bashrc' to reload shell configuration"
    fi
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
    echo "  ✓ Virtual environment created at $VENV_DIR"
    echo "  ✓ Shell integration configured"
    
    if command -v vpn &> /dev/null; then
        echo "  ✓ VPN command available in current shell"
        
        # Try to get version
        if vpn --version &> /dev/null; then
            local version=$(vpn --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            echo "  ✓ Version: $version"
        fi
    fi
    
    echo
    echo -e "${GREEN}IMPORTANT: Reload your shell to activate VPN Manager${NC}"
    echo
    echo "Run one of these commands:"
    echo -e "  ${BLUE}exec \$SHELL${NC}              # Restart current shell"
    echo -e "  ${BLUE}source ~/.bashrc${NC}         # Or reload configuration"
    echo
    echo "After reloading, you can use:"
    echo -e "  ${BLUE}vpn --help${NC}               # Show available commands"
    echo -e "  ${BLUE}vpn doctor${NC}               # Run system diagnostics"
    echo -e "  ${BLUE}vpn tui${NC}                  # Launch terminal interface"
    echo
    echo "Useful aliases:"
    echo -e "  ${BLUE}vpn-activate${NC}             # Manually activate virtual environment"
    echo -e "  ${BLUE}vpn-update${NC}               # Update VPN Manager from git"
    echo
    echo "Repository: https://github.com/ikeniborn/vpn"
    echo
    
    # Ask to reload shell
    while true; do
        read -p "Reload shell now? (Y/n): " -r REPLY
        # Convert to lowercase for case-insensitive comparison
        REPLY=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
        
        # Validate input
        if [[ "$REPLY" =~ ^(y|yes|n|no)$ ]] || [[ -z "$REPLY" ]]; then
            break
        else
            echo "Invalid input. Please enter Y/yes or N/no (or press Enter for default Y)"
        fi
    done
    
    # Default to yes if empty, otherwise check for no
    if [[ -z "$REPLY" ]] || [[ "$REPLY" =~ ^(y|yes)$ ]]; then
        exec $SHELL
    fi
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
    
    # Determine installation source
    if [[ -f "pyproject.toml" ]] && grep -q "name = \"vpn-manager\"" pyproject.toml 2>/dev/null; then
        # Installing from cloned repository
        log "Installing from current directory"
        INSTALL_DIR="$(pwd)"
        
        if [[ "$install_mode" == "dev" ]]; then
            install_python_package "dev"
        else
            install_python_package "local"
        fi
    else
        # Clone repository first
        log "Cloning repository to $INSTALL_DIR..."
        
        # Ensure install directory is clean
        if [[ -d "$INSTALL_DIR" ]]; then
            warn "Directory $INSTALL_DIR already exists"
            while true; do
                read -p "Remove and continue? (y/N): " -r REPLY
                # Convert to lowercase for case-insensitive comparison
                REPLY=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
                
                # Validate input
                if [[ "$REPLY" =~ ^(y|yes|n|no)$ ]] || [[ -z "$REPLY" ]]; then
                    break
                else
                    echo "Invalid input. Please enter Y/yes or N/no (or press Enter for default N)"
                fi
            done
            
            # Check for yes (default is no for this prompt)
            if [[ "$REPLY" =~ ^(y|yes)$ ]]; then
                rm -rf "$INSTALL_DIR"
            else
                error "Installation cancelled"
                exit 1
            fi
        fi
        
        # Clone repository
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        
        if [[ "$install_mode" == "dev" ]]; then
            install_python_package "dev"
        else
            install_python_package "local"
        fi
    fi
    
    # Setup and verify
    setup_config
    post_install_checks
    
    # Show completion
    show_completion
}

# Run main function
main "$@"