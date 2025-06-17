#!/bin/bash

# =============================================================================
# Prerequisites Installation Module
# 
# This module handles system checks and dependency installation for VPN server.
# Extracted from install_vpn.sh for modular architecture.
#
# Functions exported:
# - check_root_privileges()
# - install_system_dependencies()
# - verify_dependencies()
# - detect_system_info()
#
# Dependencies: lib/common.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

# =============================================================================
# SYSTEM CHECKS
# =============================================================================

# Check if script is running with root privileges
check_root_privileges() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Checking root privileges..."
    
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script with superuser privileges (sudo)"
        return 1
    fi
    
    [ "$debug" = true ] && log "Root privileges verified"
    return 0
}

# Detect system information
detect_system_info() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Detecting system information..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        export SYSTEM_OS="$ID"
        export SYSTEM_VERSION="$VERSION_ID"
        export SYSTEM_NAME="$PRETTY_NAME"
    else
        export SYSTEM_OS="unknown"
        export SYSTEM_VERSION="unknown"
        export SYSTEM_NAME="Unknown System"
    fi
    
    # Detect architecture
    export SYSTEM_ARCH=$(uname -m)
    case "$SYSTEM_ARCH" in
        x86_64)
            export DOCKER_ARCH="amd64"
            ;;
        aarch64|arm64)
            export DOCKER_ARCH="arm64"
            ;;
        armv7l)
            export DOCKER_ARCH="arm/v7"
            ;;
        armv6l)
            export DOCKER_ARCH="arm/v6"
            ;;
        *)
            warning "Unsupported architecture: $SYSTEM_ARCH, defaulting to amd64"
            export DOCKER_ARCH="amd64"
            ;;
    esac
    
    # Detect available memory
    export SYSTEM_MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    export SYSTEM_MEMORY_MB=$((SYSTEM_MEMORY_KB / 1024))
    export SYSTEM_MEMORY_GB=$((SYSTEM_MEMORY_MB / 1024))
    
    # Detect CPU cores
    export SYSTEM_CPU_CORES=$(nproc)
    
    [ "$debug" = true ] && {
        log "System OS: $SYSTEM_NAME"
        log "Architecture: $SYSTEM_ARCH (Docker: $DOCKER_ARCH)"
        log "Memory: ${SYSTEM_MEMORY_GB}GB (${SYSTEM_MEMORY_MB}MB)"
        log "CPU Cores: $SYSTEM_CPU_CORES"
    }
    
    return 0
}

# =============================================================================
# DEPENDENCY INSTALLATION
# =============================================================================

# Install Docker if not present
install_docker() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Checking Docker installation..."
    
    if command -v docker >/dev/null 2>&1; then
        [ "$debug" = true ] && log "Docker is already installed"
        return 0
    fi
    
    log "Docker not found. Installing Docker..."
    
    # Update package list
    apt update || {
        error "Failed to update package list"
        return 1
    }
    
    # Install prerequisites for Docker installation
    apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || {
        error "Failed to install Docker prerequisites"
        return 1
    }
    
    # Download and run Docker installation script
    curl -fsSL https://get.docker.com -o get-docker.sh || {
        error "Failed to download Docker installation script"
        return 1
    }
    
    sh get-docker.sh || {
        error "Failed to install Docker"
        rm -f get-docker.sh
        return 1
    }
    
    # Clean up installation script
    rm -f get-docker.sh
    
    # Enable and start Docker service
    systemctl enable docker || {
        warning "Failed to enable Docker service"
    }
    
    systemctl start docker || {
        error "Failed to start Docker service"
        return 1
    }
    
    # Verify Docker installation
    if ! docker --version >/dev/null 2>&1; then
        error "Docker installation verification failed"
        return 1
    fi
    
    log "Docker installed successfully"
    return 0
}

# Install Docker Compose if not present
install_docker_compose() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Checking Docker Compose installation..."
    
    if command -v docker-compose >/dev/null 2>&1; then
        [ "$debug" = true ] && log "Docker Compose is already installed"
        return 0
    fi
    
    log "Docker Compose not found. Installing Docker Compose..."
    
    # Determine latest version or use fallback
    local compose_version="v2.20.3"
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    # Download Docker Compose
    curl -L "$compose_url" -o /usr/local/bin/docker-compose || {
        error "Failed to download Docker Compose"
        return 1
    }
    
    # Make executable
    chmod +x /usr/local/bin/docker-compose || {
        error "Failed to make Docker Compose executable"
        return 1
    }
    
    # Create symlink for compatibility
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || {
        warning "Failed to create Docker Compose symlink"
    }
    
    # Verify installation
    if ! docker-compose --version >/dev/null 2>&1; then
        error "Docker Compose installation verification failed"
        return 1
    fi
    
    log "Docker Compose installed successfully"
    return 0
}

# Install system packages
install_system_packages() {
    local debug=${1:-false}
    local packages=(
        "ufw"           # Firewall
        "uuid"          # UUID generation
        "dnsutils"      # DNS utilities (dig)
        "openssl"       # SSL/TLS tools
        "curl"          # HTTP client
        "wget"          # File downloader
        "jq"            # JSON processor
        "qrencode"      # QR code generator
    )
    
    [ "$debug" = true ] && log "Installing system packages..."
    
    # Update package list
    apt update || {
        error "Failed to update package list"
        return 1
    }
    
    # Install packages one by one with error handling
    local failed_packages=()
    for package in "${packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            [ "$debug" = true ] && log "Installing $package..."
            
            if apt install -y "$package"; then
                [ "$debug" = true ] && log "$package installed successfully"
            else
                warning "Failed to install $package"
                failed_packages+=("$package")
            fi
        else
            [ "$debug" = true ] && log "$package is already installed"
        fi
    done
    
    # Report failed installations
    if [ ${#failed_packages[@]} -gt 0 ]; then
        warning "Some packages failed to install: ${failed_packages[*]}"
        warning "This may affect functionality"
    fi
    
    return 0
}

# =============================================================================
# MAIN INSTALLATION FUNCTION
# =============================================================================

# Install all system dependencies
install_system_dependencies() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Starting system dependencies installation..."
    
    # Install system packages first
    install_system_packages "$debug" || {
        error "Failed to install system packages"
        return 1
    }
    
    # Install Docker
    install_docker "$debug" || {
        error "Failed to install Docker"
        return 1
    }
    
    # Install Docker Compose
    install_docker_compose "$debug" || {
        error "Failed to install Docker Compose"
        return 1
    }
    
    [ "$debug" = true ] && log "All system dependencies installed successfully"
    return 0
}

# =============================================================================
# VERIFICATION FUNCTIONS
# =============================================================================

# Verify all dependencies are properly installed
verify_dependencies() {
    local debug=${1:-false}
    local required_commands=(
        "docker"
        "docker-compose"
        "ufw"
        "uuid"
        "dig"
        "openssl"
        "curl"
        "qrencode"
    )
    
    [ "$debug" = true ] && log "Verifying dependencies..."
    
    local missing_commands=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    # Verify Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is installed but not running properly"
        return 1
    fi
    
    [ "$debug" = true ] && log "All dependencies verified successfully"
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f check_root_privileges
export -f detect_system_info
export -f install_system_dependencies
export -f verify_dependencies
export -f install_docker
export -f install_docker_compose
export -f install_system_packages

# Debug mode check
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being run directly, enable debug mode
    check_root_privileges true
    detect_system_info true
    install_system_dependencies true
    verify_dependencies true
fi