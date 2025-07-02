#!/bin/bash
#
# VPN Server Deployment Script
# This script automates the deployment of VPN server on a fresh Linux system
#
# Usage: ./deploy.sh [options]
# Options:
#   --protocol <protocol>  VPN protocol (vless, outline, wireguard) [default: vless]
#   --port <port>         VPN server port [default: 443]
#   --domain <domain>     Domain name for VPN server (optional)
#   --email <email>       Email for Let's Encrypt certificates (optional)
#   --skip-firewall       Skip firewall configuration
#   --skip-docker         Skip Docker installation
#   --build-from-source   Build from source instead of using Docker images
#   --help                Show this help message

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROTOCOL="vless"
PORT="443"
DOMAIN=""
EMAIL=""
SKIP_FIREWALL=false
SKIP_DOCKER=false
BUILD_FROM_SOURCE=false
INSTALL_PATH="/opt/vpn"
CONFIG_PATH="/etc/vpn-cli"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS. This script requires a Linux distribution with /etc/os-release"
        exit 1
    fi
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check CPU architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
        print_warning "Unsupported architecture: $ARCH. This may cause issues."
    fi
    
    # Check available memory
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$MEM_TOTAL" -lt 512 ]; then
        print_error "Insufficient memory. At least 512MB RAM required, found ${MEM_TOTAL}MB"
        exit 1
    fi
    
    # Check available disk space
    DISK_AVAILABLE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$DISK_AVAILABLE" -lt 2 ]; then
        print_error "Insufficient disk space. At least 2GB required, found ${DISK_AVAILABLE}GB"
        exit 1
    fi
    
    print_success "System requirements met"
}

# Function to install base dependencies
install_base_dependencies() {
    print_status "Installing base dependencies..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                curl \
                wget \
                git \
                sudo \
                ca-certificates \
                gnupg \
                lsb-release \
                ufw \
                jq \
                htop \
                net-tools \
                dnsutils
            ;;
        fedora|rhel|centos)
            dnf install -y \
                curl \
                wget \
                git \
                sudo \
                ca-certificates \
                gnupg \
                firewalld \
                jq \
                htop \
                net-tools \
                bind-utils
            ;;
        arch)
            pacman -Syu --noconfirm \
                curl \
                wget \
                git \
                sudo \
                ca-certificates \
                gnupg \
                ufw \
                jq \
                htop \
                net-tools \
                bind-tools
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    print_success "Base dependencies installed"
}

# Function to install Docker
install_docker() {
    if [ "$SKIP_DOCKER" = true ]; then
        print_warning "Skipping Docker installation"
        return
    fi
    
    print_status "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed"
        return
    fi
    
    # Install Docker
    curl -fsSL https://get.docker.com | sh
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Install Docker Compose
    print_status "Installing Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker and Docker Compose installed"
}

# Function to install Rust (for building from source)
install_rust() {
    print_status "Installing Rust toolchain..."
    
    # Check if Rust is already installed
    if command -v rustc &> /dev/null; then
        print_success "Rust is already installed"
        return
    fi
    
    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    
    # Install build dependencies
    case "$OS" in
        ubuntu|debian)
            apt-get install -y \
                build-essential \
                pkg-config \
                libssl-dev \
                protobuf-compiler
            ;;
        fedora|rhel|centos)
            dnf install -y \
                gcc \
                make \
                pkgconfig \
                openssl-devel \
                protobuf-compiler
            ;;
        arch)
            pacman -S --noconfirm \
                base-devel \
                pkg-config \
                openssl \
                protobuf
            ;;
    esac
    
    print_success "Rust toolchain installed"
}

# Function to configure firewall
configure_firewall() {
    if [ "$SKIP_FIREWALL" = true ]; then
        print_warning "Skipping firewall configuration"
        return
    fi
    
    print_status "Configuring firewall..."
    
    case "$OS" in
        ubuntu|debian|arch)
            # Enable UFW
            ufw --force enable
            
            # Allow SSH
            ufw allow 22/tcp
            
            # Allow VPN port
            ufw allow ${PORT}/tcp
            ufw allow ${PORT}/udp
            
            # Allow HTTP/HTTPS if domain is specified
            if [ -n "$DOMAIN" ]; then
                ufw allow 80/tcp
                ufw allow 443/tcp
            fi
            
            # Allow Docker subnet
            ufw allow from 172.16.0.0/12
            
            ufw reload
            ;;
        fedora|rhel|centos)
            # Enable firewalld
            systemctl start firewalld
            systemctl enable firewalld
            
            # Allow services
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-port=${PORT}/tcp
            firewall-cmd --permanent --add-port=${PORT}/udp
            
            if [ -n "$DOMAIN" ]; then
                firewall-cmd --permanent --add-service=http
                firewall-cmd --permanent --add-service=https
            fi
            
            # Allow Docker subnet
            firewall-cmd --permanent --add-source=172.16.0.0/12
            
            firewall-cmd --reload
            ;;
    esac
    
    print_success "Firewall configured"
}

# Function to configure sysctl for better performance
configure_sysctl() {
    print_status "Configuring system parameters..."
    
    cat > /etc/sysctl.d/99-vpn-performance.conf <<EOF
# VPN Server Performance Tuning

# Network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384

# Enable IP forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Security
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Connection tracking
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
EOF

    sysctl -p /etc/sysctl.d/99-vpn-performance.conf
    
    print_success "System parameters configured"
}

# Function to deploy VPN using Docker
deploy_with_docker() {
    print_status "Deploying VPN server with Docker..."
    
    # Create directories
    mkdir -p "$INSTALL_PATH"
    mkdir -p "$CONFIG_PATH"
    
    # Create configuration file
    create_config_file
    
    # Download docker-compose.yml
    print_status "Downloading Docker Compose configuration..."
    curl -L https://raw.githubusercontent.com/your-org/vpn/main/docker-compose.hub.yml \
        -o "$INSTALL_PATH/docker-compose.yml"
    
    # Set environment variables
    cat > "$INSTALL_PATH/.env" <<EOF
VPN_PROTOCOL=${PROTOCOL}
VPN_PORT=${PORT}
VPN_DOMAIN=${DOMAIN:-localhost}
VPN_EMAIL=${EMAIL}
VPN_SNI=${DOMAIN:-www.google.com}
INSTALL_PATH=${INSTALL_PATH}
CONFIG_PATH=${CONFIG_PATH}
EOF
    
    # Start services
    cd "$INSTALL_PATH"
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to start..."
    sleep 10
    
    print_success "VPN server deployed with Docker"
}

# Function to build and deploy from source
deploy_from_source() {
    print_status "Building VPN server from source..."
    
    # Install Rust if not already installed
    install_rust
    
    # Clone repository
    cd /tmp
    git clone https://github.com/your-org/vpn.git
    cd vpn
    
    # Build the project
    print_status "Building project (this may take a while)..."
    cargo build --release --workspace
    
    # Install the binary
    cp target/release/vpn /usr/local/bin/
    chmod +x /usr/local/bin/vpn
    
    # Create directories
    mkdir -p "$INSTALL_PATH"
    mkdir -p "$CONFIG_PATH"
    
    # Create configuration file
    create_config_file
    
    # Create systemd service
    create_systemd_service
    
    # Start the service
    systemctl daemon-reload
    systemctl start vpn-server
    systemctl enable vpn-server
    
    print_success "VPN server built and deployed from source"
}

# Function to create configuration file
create_config_file() {
    print_status "Creating configuration file..."
    
    cat > "$CONFIG_PATH/config.toml" <<EOF
# VPN CLI Configuration

[general]
install_path = "${INSTALL_PATH}"
log_level = "info"
auto_backup = true
backup_retention_days = 7

[server]
default_protocol = "${PROTOCOL}"
default_port_range = [10000, 65000]
enable_firewall = true
auto_start = true
update_check_interval = 86400
host = "${DOMAIN:-$(curl -s https://api.ipify.org)}"
port = ${PORT}

[ui]
default_output_format = "table"
color_output = true
progress_bars = true
confirmation_prompts = true

[monitoring]
enable_metrics = true
metrics_retention_days = 30
notification_channels = []

[monitoring.alert_thresholds]
cpu_usage = 90.0
memory_usage = 90.0
disk_usage = 85.0
error_rate = 5.0

[security]
auto_key_rotation = false
key_rotation_interval_days = 90
backup_keys = true
strict_validation = true

[runtime]
preferred_runtime = "docker"
auto_detect = true
fallback_enabled = true

[runtime.docker]
socket_path = "/var/run/docker.sock"
api_version = ""
timeout_seconds = 30
max_connections = 10
enabled = true

[runtime.containerd]
socket_path = "/run/containerd/containerd.sock"
namespace = "default"
timeout_seconds = 30
max_connections = 10
snapshotter = "overlayfs"
runtime = "io.containerd.runc.v2"
enabled = false

[runtime.migration]
backup_before_migration = true
preserve_containers = true
validate_after_migration = true
migration_timeout_minutes = 30
EOF
    
    chmod 644 "$CONFIG_PATH/config.toml"
    print_success "Configuration file created"
}

# Function to create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."
    
    cat > /etc/systemd/system/vpn-server.service <<EOF
[Unit]
Description=VPN Server
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/vpn server start --daemon
ExecReload=/usr/local/bin/vpn server reload
ExecStop=/usr/local/bin/vpn server stop
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vpn-server
User=root
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Systemd service created"
}

# Function to perform post-deployment checks
perform_checks() {
    print_status "Performing post-deployment checks..."
    
    local checks_passed=true
    
    # Check if VPN command is available
    if [ "$BUILD_FROM_SOURCE" = true ]; then
        if command -v vpn &> /dev/null; then
            print_success "VPN binary is available"
        else
            print_error "VPN binary not found"
            checks_passed=false
        fi
    else
        if docker ps | grep -q vpn-server; then
            print_success "VPN container is running"
        else
            print_error "VPN container is not running"
            checks_passed=false
        fi
    fi
    
    # Check port availability
    if netstat -tuln | grep -q ":${PORT} "; then
        print_success "VPN port ${PORT} is listening"
    else
        print_warning "VPN port ${PORT} is not yet listening"
    fi
    
    # Check firewall rules
    if [ "$SKIP_FIREWALL" = false ]; then
        case "$OS" in
            ubuntu|debian|arch)
                if ufw status | grep -q "${PORT}/tcp"; then
                    print_success "Firewall rules configured"
                else
                    print_error "Firewall rules not found"
                    checks_passed=false
                fi
                ;;
            fedora|rhel|centos)
                if firewall-cmd --list-ports | grep -q "${PORT}/tcp"; then
                    print_success "Firewall rules configured"
                else
                    print_error "Firewall rules not found"
                    checks_passed=false
                fi
                ;;
        esac
    fi
    
    # Check configuration
    if [ -f "$CONFIG_PATH/config.toml" ]; then
        print_success "Configuration file exists"
    else
        print_error "Configuration file not found"
        checks_passed=false
    fi
    
    # Run VPN doctor
    if [ "$BUILD_FROM_SOURCE" = true ]; then
        print_status "Running VPN system check..."
        vpn doctor || true
    else
        print_status "Running VPN system check..."
        docker exec vpn-server vpn doctor || true
    fi
    
    if [ "$checks_passed" = true ]; then
        print_success "All checks passed!"
    else
        print_warning "Some checks failed. Please review the errors above."
    fi
}

# Function to create first user
create_first_user() {
    print_status "Creating first VPN user..."
    
    read -p "Enter username for first VPN user: " username
    
    if [ "$BUILD_FROM_SOURCE" = true ]; then
        vpn users create "$username"
        vpn users link "$username" --qr
    else
        docker exec vpn-server vpn users create "$username"
        docker exec vpn-server vpn users link "$username" --qr
    fi
    
    print_success "User '$username' created successfully"
}

# Function to show deployment summary
show_summary() {
    echo
    echo "========================================"
    echo "       VPN Server Deployment Summary"
    echo "========================================"
    echo
    echo "Protocol: $PROTOCOL"
    echo "Port: $PORT"
    echo "Install Path: $INSTALL_PATH"
    echo "Config Path: $CONFIG_PATH"
    
    if [ -n "$DOMAIN" ]; then
        echo "Domain: $DOMAIN"
    fi
    
    echo
    echo "Next steps:"
    echo "1. Create users: vpn users create <username>"
    echo "2. Get connection links: vpn users link <username> --qr"
    echo "3. Monitor status: vpn status"
    echo "4. View logs: vpn monitor logs"
    echo
    
    if [ "$BUILD_FROM_SOURCE" = false ]; then
        echo "Docker commands:"
        echo "- View logs: docker-compose -f $INSTALL_PATH/docker-compose.yml logs"
        echo "- Restart: docker-compose -f $INSTALL_PATH/docker-compose.yml restart"
        echo "- Stop: docker-compose -f $INSTALL_PATH/docker-compose.yml down"
        echo
    fi
    
    echo "Documentation: https://github.com/your-org/vpn"
    echo "========================================"
}

# Function to show help
show_help() {
    echo "VPN Server Deployment Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --protocol <protocol>  VPN protocol (vless, outline, wireguard) [default: vless]"
    echo "  --port <port>         VPN server port [default: 443]"
    echo "  --domain <domain>     Domain name for VPN server (optional)"
    echo "  --email <email>       Email for Let's Encrypt certificates (optional)"
    echo "  --skip-firewall       Skip firewall configuration"
    echo "  --skip-docker         Skip Docker installation"
    echo "  --build-from-source   Build from source instead of using Docker images"
    echo "  --help                Show this help message"
    echo
    echo "Examples:"
    echo "  # Basic deployment with Docker"
    echo "  $0"
    echo
    echo "  # Deploy with custom protocol and port"
    echo "  $0 --protocol outline --port 8388"
    echo
    echo "  # Deploy with domain and SSL"
    echo "  $0 --domain vpn.example.com --email admin@example.com"
    echo
    echo "  # Build from source"
    echo "  $0 --build-from-source"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --protocol)
            PROTOCOL="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --build-from-source)
            BUILD_FROM_SOURCE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main deployment process
main() {
    echo "========================================"
    echo "       VPN Server Deployment Script"
    echo "========================================"
    echo
    
    # Pre-deployment checks
    check_root
    detect_os
    check_requirements
    
    print_status "Detected OS: $OS $OS_VERSION"
    print_status "Architecture: $(uname -m)"
    echo
    
    # Installation steps
    install_base_dependencies
    configure_sysctl
    configure_firewall
    
    # Deploy VPN
    if [ "$BUILD_FROM_SOURCE" = true ]; then
        install_rust
        deploy_from_source
    else
        install_docker
        deploy_with_docker
    fi
    
    # Post-deployment
    perform_checks
    
    # Optional: Create first user
    echo
    read -p "Would you like to create the first VPN user now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_first_user
    fi
    
    # Show summary
    show_summary
}

# Run main function
main