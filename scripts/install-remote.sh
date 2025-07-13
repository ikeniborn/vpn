#!/bin/bash
# VPN Remote Server Installation Script
# This script downloads and installs the latest VPN release on remote servers

set -euo pipefail

# Configuration
REPO_OWNER="${REPO_OWNER:-your-org}"
REPO_NAME="${REPO_NAME:-vpn}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/vpn}"
VERSION="${VERSION:-latest}"
FORCE_INSTALL="${FORCE_INSTALL:-false}"
QUIET="${QUIET:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Detect system architecture
detect_arch() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            echo "x86_64-unknown-linux-gnu"
            ;;
        aarch64|arm64)
            echo "aarch64-unknown-linux-gnu"
            ;;
        armv7l|armhf)
            echo "armv7-unknown-linux-gnueabihf"
            ;;
        *)
            error "Unsupported architecture: $arch"
            ;;
    esac
}

# Get latest release version from GitHub API
get_latest_version() {
    local api_url="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget is available. Please install one of them."
    fi
}

# Download and verify binary
download_binary() {
    local version="$1"
    local target="$2"
    local download_dir="$3"
    
    local base_url="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download"
    local binary_name="vpn-${target}.tar.gz"
    local checksum_name="vpn-${target}.tar.gz.sha256"
    
    log "Downloading VPN binary for $target..."
    
    if command -v curl >/dev/null 2>&1; then
        curl -L "$base_url/$version/$binary_name" -o "$download_dir/$binary_name"
        curl -L "$base_url/$version/$checksum_name" -o "$download_dir/$checksum_name"
    elif command -v wget >/dev/null 2>&1; then
        wget "$base_url/$version/$binary_name" -O "$download_dir/$binary_name"
        wget "$base_url/$version/$checksum_name" -O "$download_dir/$checksum_name"
    else
        error "Neither curl nor wget is available"
    fi
    
    # Verify checksum
    log "Verifying binary checksum..."
    cd "$download_dir"
    if ! sha256sum -c "$checksum_name"; then
        error "Checksum verification failed"
    fi
    
    # Extract binary
    tar -xzf "$binary_name"
    log "Binary downloaded and verified successfully"
}

# Install binary
install_binary() {
    local download_dir="$1"
    
    log "Installing VPN binary to $INSTALL_DIR..."
    
    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Copy binary
    cp "$download_dir/vpn" "$INSTALL_DIR/vpn"
    chmod +x "$INSTALL_DIR/vpn"
    
    # Create symlink for global access if not already in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        ln -sf "$INSTALL_DIR/vpn" /usr/local/bin/vpn 2>/dev/null || true
    fi
    
    log "Binary installed successfully"
}

# Setup configuration directory
setup_config() {
    log "Setting up configuration directory at $CONFIG_DIR..."
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/users"
    mkdir -p "$CONFIG_DIR/servers"
    mkdir -p "$CONFIG_DIR/templates"
    
    # Create default configuration if it doesn't exist
    if [[ ! -f "$CONFIG_DIR/config.toml" ]]; then
        cat > "$CONFIG_DIR/config.toml" << 'EOF'
# VPN Manager Configuration
[general]
install_path = "/opt/vpn"
log_level = "info"
log_path = "/var/log/vpn"

[docker]
# Docker configuration will be auto-detected
network_name = "vpn-network"

[server]
default_protocol = "vless"
default_port = 8443

[monitoring]
enabled = true
metrics_port = 9090
EOF
        log "Created default configuration file"
    fi
    
    # Set proper permissions
    chown -R root:root "$CONFIG_DIR"
    chmod -R 755 "$CONFIG_DIR"
    chmod 644 "$CONFIG_DIR/config.toml"
}

# Install Docker if not present
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker is already installed"
        return
    fi
    
    log "Installing Docker..."
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        error "Cannot detect operating system"
    fi
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|fedora)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            systemctl start docker
            systemctl enable docker
            ;;
        *)
            error "Unsupported operating system: $OS"
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log "Docker installed successfully"
}

# Create systemd service
create_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/vpn-manager.service << EOF
[Unit]
Description=VPN Manager Service
After=docker.service
Requires=docker.service

[Service]
Type=forking
ExecStart=$INSTALL_DIR/vpn server start
ExecStop=$INSTALL_DIR/vpn server stop
ExecReload=$INSTALL_DIR/vpn server restart
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vpn-manager
    
    log "Systemd service created and enabled"
}

# Setup firewall rules
setup_firewall() {
    log "Setting up firewall rules..."
    
    # Default VPN ports
    local ports=(8443 8080 9090)
    
    if command -v ufw >/dev/null 2>&1; then
        for port in "${ports[@]}"; do
            ufw allow "$port" >/dev/null 2>&1 || true
        done
        log "UFW firewall rules configured"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        for port in "${ports[@]}"; do
            firewall-cmd --permanent --add-port="$port/tcp" >/dev/null 2>&1 || true
        done
        firewall-cmd --reload >/dev/null 2>&1 || true
        log "Firewalld rules configured"
    elif command -v iptables >/dev/null 2>&1; then
        for port in "${ports[@]}"; do
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
        done
        # Save iptables rules (method varies by distro)
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        log "Iptables rules configured"
    else
        warn "No supported firewall found. Please manually configure firewall rules for ports: ${ports[*]}"
    fi
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    if ! command -v vpn >/dev/null 2>&1; then
        error "VPN binary not found in PATH"
    fi
    
    local version_output
    version_output=$(vpn --version 2>&1 || true)
    
    if [[ -z "$version_output" ]]; then
        error "VPN binary is not working correctly"
    fi
    
    log "Installation verified: $version_output"
}

# Cleanup temporary files
cleanup() {
    local download_dir="$1"
    if [[ -d "$download_dir" ]]; then
        rm -rf "$download_dir"
    fi
}

# Show usage information
show_usage() {
    cat << EOF
VPN Remote Server Installation Script

Usage: $0 [OPTIONS]

Options:
    -v, --version VERSION    Install specific version (default: latest)
    -d, --install-dir DIR    Installation directory (default: /usr/local/bin)
    -c, --config-dir DIR     Configuration directory (default: /etc/vpn)
    -f, --force             Force reinstallation even if already installed
    -q, --quiet             Quiet mode (suppress info messages)
    --no-docker             Skip Docker installation
    --no-service            Skip systemd service creation
    --no-firewall           Skip firewall configuration
    -h, --help              Show this help message

Environment Variables:
    REPO_OWNER              GitHub repository owner (default: your-org)
    REPO_NAME               GitHub repository name (default: vpn)
    INSTALL_DIR             Installation directory
    CONFIG_DIR              Configuration directory
    VERSION                 Version to install
    FORCE_INSTALL           Force installation (true/false)
    QUIET                   Quiet mode (true/false)

Examples:
    # Install latest version
    sudo $0

    # Install specific version
    sudo $0 --version v1.2.3

    # Install to custom directory
    sudo $0 --install-dir /opt/vpn/bin

    # Quiet installation without Docker
    sudo $0 --quiet --no-docker
EOF
}

# Main installation function
main() {
    local skip_docker=false
    local skip_service=false
    local skip_firewall=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -d|--install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -c|--config-dir)
                CONFIG_DIR="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --no-docker)
                skip_docker=true
                shift
                ;;
            --no-service)
                skip_service=true
                shift
                ;;
            --no-firewall)
                skip_firewall=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    log "Starting VPN installation..."
    
    # Check prerequisites
    check_root
    
    # Check if already installed
    if command -v vpn >/dev/null 2>&1 && [[ "$FORCE_INSTALL" != "true" ]]; then
        local current_version
        current_version=$(vpn --version 2>&1 | head -n1 || echo "unknown")
        warn "VPN is already installed: $current_version"
        warn "Use --force to reinstall"
        exit 0
    fi
    
    # Detect architecture
    local target
    target=$(detect_arch)
    log "Detected architecture: $target"
    
    # Get version to install
    if [[ "$VERSION" == "latest" ]]; then
        VERSION=$(get_latest_version)
        if [[ -z "$VERSION" ]]; then
            error "Failed to get latest version"
        fi
    fi
    log "Installing version: $VERSION"
    
    # Create temporary download directory
    local download_dir
    download_dir=$(mktemp -d)
    trap "cleanup '$download_dir'" EXIT
    
    # Download and install
    download_binary "$VERSION" "$target" "$download_dir"
    install_binary "$download_dir"
    setup_config
    
    # Optional components
    if [[ "$skip_docker" != "true" ]]; then
        install_docker
    fi
    
    if [[ "$skip_service" != "true" ]]; then
        create_service
    fi
    
    if [[ "$skip_firewall" != "true" ]]; then
        setup_firewall
    fi
    
    # Verify installation
    verify_installation
    
    log "VPN installation completed successfully!"
    log ""
    log "Next steps:"
    log "1. Configure your VPN settings in $CONFIG_DIR/config.toml"
    log "2. Start the VPN service: systemctl start vpn-manager"
    log "3. Create your first user: vpn users create <username>"
    log "4. Install VPN server: vpn server install --protocol vless"
    log ""
    log "For more information, run: vpn --help"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi