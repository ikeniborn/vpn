#!/bin/bash
#
# VPN CLI Installation Script
# Installs dependencies, clones repository, builds project, and installs VPN CLI tool
#
# Usage: ./install.sh [options]
# Options:
#   --no-menu          Don't launch the menu after installation
#   --skip-docker      Skip Docker installation
#   --verbose          Enable verbose output
#   --help             Show this help message

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
LAUNCH_MENU=true
SKIP_DOCKER=false
VERBOSE=false
REPO_URL="https://github.com/your-org/vpn.git"
REPO_DIR="$HOME/vpn-rust"

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

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check CPU architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|aarch64|armv7l)
            print_success "Architecture: $ARCH"
            ;;
        *)
            print_warning "Unsupported architecture: $ARCH. This may cause issues."
            ;;
    esac
    
    # Check available memory for building
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$MEM_TOTAL" -lt 1024 ]; then
        print_warning "Low memory detected: ${MEM_TOTAL}MB. At least 1GB recommended for building."
    else
        print_success "Memory: ${MEM_TOTAL}MB"
    fi
    
    # Check available disk space
    DISK_AVAILABLE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$DISK_AVAILABLE" -lt 2 ]; then
        print_error "Insufficient disk space. At least 2GB required, found ${DISK_AVAILABLE}GB"
        exit 1
    else
        print_success "Disk space: ${DISK_AVAILABLE}GB available"
    fi
}

# Function to install OS dependencies
install_os_dependencies() {
    print_status "Installing OS dependencies..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                curl \
                wget \
                git \
                build-essential \
                pkg-config \
                libssl-dev \
                protobuf-compiler \
                ca-certificates \
                gnupg \
                software-properties-common
            ;;
        fedora|rhel|centos)
            dnf install -y \
                curl \
                wget \
                git \
                gcc \
                gcc-c++ \
                make \
                pkgconfig \
                openssl-devel \
                protobuf-compiler \
                ca-certificates \
                gnupg
            ;;
        arch)
            pacman -Syu --noconfirm \
                curl \
                wget \
                git \
                base-devel \
                pkg-config \
                openssl \
                protobuf \
                ca-certificates \
                gnupg
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    print_success "OS dependencies installed"
}

# Function to install Rust
install_rust() {
    print_status "Installing Rust toolchain..."
    
    # Check if Rust is already installed
    if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
        RUST_VERSION=$(rustc --version | cut -d' ' -f2)
        print_success "Rust is already installed (version $RUST_VERSION)"
        
        # Check minimum version (1.70.0)
        MIN_VERSION="1.70.0"
        if [ "$(printf '%s\n' "$MIN_VERSION" "$RUST_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
            print_warning "Rust version $RUST_VERSION is older than minimum required $MIN_VERSION"
            print_status "Updating Rust..."
            rustup update stable
        fi
        return
    fi
    
    # Install Rust
    print_status "Downloading and installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    
    # Source cargo env
    source "$HOME/.cargo/env"
    
    print_success "Rust toolchain installed"
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
        
        # Start Docker if not running
        if ! docker info &> /dev/null; then
            print_status "Starting Docker service..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
        return
    fi
    
    # Install Docker
    print_status "Downloading and installing Docker..."
    curl -fsSL https://get.docker.com | sh
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    if [ "$EUID" -ne 0 ]; then
        sudo usermod -aG docker $USER
        print_warning "You've been added to the docker group. Please log out and back in for this to take effect."
    fi
    
    # Install Docker Compose
    print_status "Installing Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker and Docker Compose installed"
}

# Function to clone repository
clone_repository() {
    print_status "Cloning VPN repository..."
    
    if [ -d "$REPO_DIR" ]; then
        print_status "Repository exists, updating..."
        cd "$REPO_DIR"
        git pull origin main || git pull origin master
    else
        print_status "Cloning repository..."
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
    fi
    
    print_success "Repository ready at $REPO_DIR"
}

# Function to build the project
build_project() {
    print_status "Building VPN project (this may take a while)..."
    
    # Ensure we're in the repo directory
    cd "$REPO_DIR"
    
    # Clean previous builds
    if [ "$VERBOSE" = true ]; then
        cargo clean
    fi
    
    # Build in release mode
    if [ "$VERBOSE" = true ]; then
        cargo build --release --workspace
    else
        print_status "Building project... (this may take 5-10 minutes)"
        cargo build --release --workspace 2>&1 | while read -r line; do
            if [[ "$line" =~ "Compiling" ]]; then
                echo -ne "\r${BLUE}[*]${NC} Building... $(echo "$line" | awk '{print $2}')"
            fi
        done
        echo -e "\r${BLUE}[*]${NC} Building... Completed!                    "
    fi
    
    print_success "Project built successfully"
}

# Function to install the CLI
install_cli() {
    print_status "Installing VPN CLI..."
    
    cd "$REPO_DIR"
    
    # Install using cargo
    if [ "$VERBOSE" = true ]; then
        cargo install --path crates/vpn-cli --force
    else
        cargo install --path crates/vpn-cli --force --quiet
    fi
    
    # Verify installation
    if command -v vpn &> /dev/null; then
        VPN_VERSION=$(vpn --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
        print_success "VPN CLI installed successfully (version $VPN_VERSION)"
    else
        print_error "VPN CLI installation failed"
        exit 1
    fi
}

# Function to create default configuration
create_default_config() {
    print_status "Creating default configuration..."
    
    CONFIG_DIR="$HOME/.config/vpn-cli"
    mkdir -p "$CONFIG_DIR"
    
    if [ ! -f "$CONFIG_DIR/config.toml" ]; then
        cat > "$CONFIG_DIR/config.toml" <<'EOF'
# VPN CLI Configuration

[general]
install_path = "/opt/vpn"
log_level = "info"
auto_backup = true
backup_retention_days = 7

[server]
default_protocol = "vless"
default_port_range = [10000, 65000]
enable_firewall = true
auto_start = true
update_check_interval = 86400

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
        print_success "Configuration file created at $CONFIG_DIR/config.toml"
    else
        print_success "Configuration file already exists"
    fi
}

# Function to setup shell completion
setup_completion() {
    print_status "Setting up shell completion..."
    
    # Detect shell
    SHELL_NAME=$(basename "$SHELL")
    
    case "$SHELL_NAME" in
        bash)
            if [ -d "$HOME/.local/share" ]; then
                mkdir -p "$HOME/.local/share/bash-completion/completions"
                vpn completions bash > "$HOME/.local/share/bash-completion/completions/vpn" 2>/dev/null || true
                print_success "Bash completion installed"
            fi
            ;;
        zsh)
            if [ -d "$HOME/.zsh" ]; then
                mkdir -p "$HOME/.zsh/completions"
                vpn completions zsh > "$HOME/.zsh/completions/_vpn" 2>/dev/null || true
                print_success "Zsh completion installed"
            fi
            ;;
        fish)
            if [ -d "$HOME/.config/fish" ]; then
                mkdir -p "$HOME/.config/fish/completions"
                vpn completions fish > "$HOME/.config/fish/completions/vpn.fish" 2>/dev/null || true
                print_success "Fish completion installed"
            fi
            ;;
        *)
            print_warning "Shell completion not set up for $SHELL_NAME"
            ;;
    esac
}

# Function to run doctor checks
run_doctor() {
    print_status "Running VPN system diagnostics..."
    
    echo
    vpn doctor || {
        print_warning "Some diagnostic checks failed. This is normal for a fresh installation."
        print_warning "You can install VPN server components using the interactive menu."
    }
    echo
}

# Function to show completion message
show_completion_message() {
    echo
    echo "========================================"
    echo "     VPN CLI Installation Complete!"
    echo "========================================"
    echo
    echo "The VPN CLI tool has been successfully installed."
    echo
    echo "Next steps:"
    echo "  1. Use 'vpn menu' to launch the interactive menu"
    echo "  2. Install VPN server with 'sudo vpn install'"
    echo "  3. Create users with 'sudo vpn users create <username>'"
    echo
    echo "Configuration: $HOME/.config/vpn-cli/config.toml"
    echo "Binary location: $HOME/.cargo/bin/vpn"
    echo "Source code: $REPO_DIR"
    echo
    
    if [ "$LAUNCH_MENU" = true ]; then
        echo "Launching interactive menu in 3 seconds..."
        echo "========================================"
        echo
        sleep 3
    fi
}

# Function to show help
show_help() {
    echo "VPN CLI Installation Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --no-menu          Don't launch the menu after installation"
    echo "  --skip-docker      Skip Docker installation"
    echo "  --verbose          Enable verbose output"
    echo "  --help             Show this help message"
    echo
    echo "This script will:"
    echo "  1. Install system dependencies"
    echo "  2. Install Rust toolchain"
    echo "  3. Install Docker (optional)"
    echo "  4. Clone VPN repository"
    echo "  5. Build the project"
    echo "  6. Install VPN CLI"
    echo "  7. Run system diagnostics"
    echo "  8. Launch interactive menu (optional)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-menu)
            LAUNCH_MENU=false
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --verbose)
            VERBOSE=true
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

# Main installation process
main() {
    echo "========================================"
    echo "      VPN CLI Installation Script"
    echo "========================================"
    echo
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root"
        print_warning "Run as a regular user. The script will prompt for sudo when needed."
        exit 1
    fi
    
    # Pre-installation checks
    detect_os
    check_requirements
    
    print_status "Detected OS: $OS $OS_VERSION"
    print_status "Architecture: $(uname -m)"
    echo
    
    # Installation steps
    print_status "Installing system dependencies (requires sudo)..."
    sudo -E bash -c "$(declare -f install_os_dependencies detect_os print_status print_success print_error); OS=$OS; OS_VERSION=$OS_VERSION; install_os_dependencies"
    
    # Install Rust (as regular user)
    install_rust
    
    # Ensure cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    
    # Install Docker
    install_docker
    
    # Clone repository
    clone_repository
    
    # Build and install
    build_project
    install_cli
    
    # Post-installation setup
    create_default_config
    setup_completion
    
    # Run diagnostics
    run_doctor
    
    # Show completion message
    show_completion_message
    
    # Launch menu if requested
    if [ "$LAUNCH_MENU" = true ]; then
        vpn menu
    fi
}

# Run main function
main