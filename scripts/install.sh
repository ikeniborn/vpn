#!/bin/bash

# VPN Manager - One-line installation script
# Usage: curl -fsSL https://get.vpn-manager.io | bash

set -e

# Configuration
REPO_URL="https://github.com/vpn-manager/vpn-python"
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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root"
        exit 1
    fi
}

# Check if sudo is available
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        error "sudo is required but not installed"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            OS=$ID
            VERSION=$VERSION_ID
        else
            error "Cannot detect Linux distribution"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        VERSION=$(sw_vers -productVersion)
    else
        error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
    log "Detected OS: $OS $VERSION"
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check Python version
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        if [[ $(echo "$PYTHON_VERSION >= $PYTHON_MIN_VERSION" | bc -l) -eq 1 ]]; then
            success "Python $PYTHON_VERSION is installed"
        else
            error "Python $PYTHON_MIN_VERSION or higher is required (found $PYTHON_VERSION)"
            exit 1
        fi
    else
        error "Python 3 is not installed"
        exit 1
    fi
    
    # Check pip
    if ! command -v pip3 &> /dev/null; then
        error "pip3 is not installed"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed. Installing Docker..."
        install_docker
    else
        success "Docker is installed"
    fi
    
    # Check available memory
    if [[ "$OS" == "linux-gnu" ]] || [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        MEMORY_MB=$((MEMORY_KB / 1024))
        if [[ $MEMORY_MB -lt 512 ]]; then
            warn "Low memory detected: ${MEMORY_MB}MB (minimum 512MB recommended)"
        fi
    fi
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        curl -fsSL https://get.docker.com | sudo bash
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
        success "Docker installed successfully"
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
        curl -fsSL https://get.docker.com | sudo bash
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
        success "Docker installed successfully"
    elif [[ "$OS" == "macos" ]]; then
        warn "Please install Docker Desktop for macOS from https://docker.com/products/docker-desktop"
        exit 1
    else
        error "Automatic Docker installation not supported for $OS"
        exit 1
    fi
}

# Install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        sudo apt-get update
        sudo apt-get install -y \
            python3-pip \
            python3-venv \
            python3-dev \
            build-essential \
            curl \
            wget \
            git \
            iptables \
            iproute2 \
            net-tools \
            ca-certificates \
            gnupg \
            lsb-release
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
        sudo yum update -y
        sudo yum install -y \
            python3-pip \
            python3-devel \
            gcc \
            gcc-c++ \
            make \
            curl \
            wget \
            git \
            iptables \
            iproute \
            net-tools \
            ca-certificates
    elif [[ "$OS" == "macos" ]]; then
        if ! command -v brew &> /dev/null; then
            warn "Homebrew is not installed. Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install python3 git
    fi
    
    success "System dependencies installed"
}

# Create system user
create_system_user() {
    log "Creating system user..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        sudo useradd --system --shell /bin/bash --home-dir "$INSTALL_DIR" --create-home "$SERVICE_USER"
        sudo usermod -aG docker "$SERVICE_USER"
        success "Created system user: $SERVICE_USER"
    else
        log "System user $SERVICE_USER already exists"
    fi
}

# Create directories
create_directories() {
    log "Creating directories..."
    
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$CONFIG_DIR"
    sudo mkdir -p "$LOG_DIR"
    
    sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR"
    sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
    
    success "Directories created"
}

# Install VPN Manager
install_vpn_manager() {
    log "Installing VPN Manager..."
    
    # Install via pip
    sudo -u "$SERVICE_USER" pip3 install --user vpn-manager
    
    # Create symlink for global access
    sudo ln -sf "/home/$SERVICE_USER/.local/bin/vpn" /usr/local/bin/vpn
    
    success "VPN Manager installed"
}

# Configure VPN Manager
configure_vpn_manager() {
    log "Configuring VPN Manager..."
    
    # Initialize configuration
    sudo -u "$SERVICE_USER" vpn config init --config-dir "$CONFIG_DIR"
    
    # Set permissions
    sudo chmod 640 "$CONFIG_DIR/config.toml"
    sudo chmod 700 "$CONFIG_DIR"
    
    success "VPN Manager configured"
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    
    sudo tee /etc/systemd/system/vpn-manager.service > /dev/null <<EOF
[Unit]
Description=VPN Manager Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/vpn server start --all
ExecStop=/usr/local/bin/vpn server stop --all
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=VPN_CONFIG_DIR=$CONFIG_DIR
Environment=VPN_LOG_DIR=$LOG_DIR
Environment=VPN_LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable vpn-manager
    
    success "Systemd service created"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw allow 8443/tcp comment "VPN Manager VLESS"
        sudo ufw allow 8443/udp comment "VPN Manager VLESS"
        sudo ufw allow 8444/tcp comment "VPN Manager Shadowsocks"
        sudo ufw allow 1080/tcp comment "VPN Manager SOCKS5"
        sudo ufw allow 8888/tcp comment "VPN Manager HTTP Proxy"
        sudo ufw allow 51820/udp comment "VPN Manager WireGuard"
        success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-port=8443/tcp
        sudo firewall-cmd --permanent --add-port=8443/udp
        sudo firewall-cmd --permanent --add-port=8444/tcp
        sudo firewall-cmd --permanent --add-port=1080/tcp
        sudo firewall-cmd --permanent --add-port=8888/tcp
        sudo firewall-cmd --permanent --add-port=51820/udp
        sudo firewall-cmd --reload
        success "Firewall configured"
    else
        warn "No supported firewall detected. Please configure firewall manually."
    fi
}

# Run post-install checks
post_install_checks() {
    log "Running post-install checks..."
    
    # Check installation
    if vpn --version &> /dev/null; then
        success "VPN Manager CLI is working"
    else
        error "VPN Manager CLI is not working"
        exit 1
    fi
    
    # Check Docker access
    if sudo -u "$SERVICE_USER" docker ps &> /dev/null; then
        success "Docker access is working"
    else
        warn "Docker access may not be working. You may need to log out and back in."
    fi
    
    # Run diagnostics
    sudo -u "$SERVICE_USER" vpn doctor
}

# Print installation summary
print_summary() {
    echo
    echo "======================================"
    echo "VPN Manager Installation Complete!"
    echo "======================================"
    echo
    echo "Installation Directory: $INSTALL_DIR"
    echo "Configuration Directory: $CONFIG_DIR"
    echo "Log Directory: $LOG_DIR"
    echo "System User: $SERVICE_USER"
    echo
    echo "Commands:"
    echo "  vpn --help                    Show help"
    echo "  vpn doctor                    Run diagnostics"
    echo "  vpn tui                       Launch terminal interface"
    echo "  vpn users create <name>       Create VPN user"
    echo "  vpn server install            Install VPN server"
    echo
    echo "Service Management:"
    echo "  sudo systemctl start vpn-manager     Start service"
    echo "  sudo systemctl stop vpn-manager      Stop service"
    echo "  sudo systemctl status vpn-manager    Check status"
    echo "  sudo journalctl -u vpn-manager -f    View logs"
    echo
    echo "Next Steps:"
    echo "1. Create your first user: vpn users create myuser --protocol vless"
    echo "2. Install a VPN server: vpn server install --protocol vless --port 8443"
    echo "3. Start the service: sudo systemctl start vpn-manager"
    echo "4. Access the TUI: vpn tui"
    echo
    echo "Documentation: https://docs.vpn-manager.io"
    echo "Support: https://github.com/vpn-manager/vpn-python/issues"
    echo
}

# Handle cleanup on exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        error "Installation failed. Cleaning up..."
        # Add cleanup logic here if needed
    fi
}

# Main installation function
main() {
    trap cleanup EXIT
    
    echo "VPN Manager Installation Script"
    echo "==============================="
    echo
    
    check_root
    check_sudo
    detect_os
    check_requirements
    install_system_deps
    create_system_user
    create_directories
    install_vpn_manager
    configure_vpn_manager
    create_systemd_service
    configure_firewall
    post_install_checks
    print_summary
    
    success "Installation completed successfully!"
}

# Run main function
main "$@"