#!/bin/bash

# =============================================================================
# Automatic Dependency Management Module
# 
# This module provides intelligent dependency installation and management.
# Supports multiple package managers and handles version compatibility.
#
# Functions exported:
# - detect_package_manager()
# - install_dependencies()
# - check_and_install_docker()
# - install_optional_tools()
# - update_system_packages()
# - configure_package_repositories()
#
# Dependencies: lib/common.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Package lists by category
ESSENTIAL_PACKAGES=(
    "curl"
    "wget"
    "tar"
    "gzip"
    "ca-certificates"
    "gnupg"
    "lsb-release"
)

NETWORK_PACKAGES=(
    "iptables"
    "net-tools"
    "dnsutils"
    "iputils-ping"
    "traceroute"
)

BUILD_PACKAGES=(
    "build-essential"
    "git"
    "make"
    "gcc"
)

OPTIONAL_PACKAGES=(
    "jq"
    "htop"
    "vim"
    "qrencode"
    "vnstat"
    "socat"
    "netcat"
)

# Package name mappings for different distributions
declare -A PACKAGE_MAPPINGS=(
    # Debian/Ubuntu -> RHEL/CentOS/Fedora
    ["dnsutils"]="bind-utils"
    ["netcat"]="nmap-ncat"
    ["build-essential"]="@development-tools"
    ["iputils-ping"]="iputils"
    ["net-tools"]="net-tools"
    ["ca-certificates"]="ca-certificates"
)

# Docker installation scripts by distribution
declare -A DOCKER_INSTALL_SCRIPTS=(
    ["ubuntu"]="https://get.docker.com"
    ["debian"]="https://get.docker.com"
    ["centos"]="https://get.docker.com"
    ["rhel"]="https://get.docker.com"
    ["fedora"]="https://get.docker.com"
)

# =============================================================================
# PACKAGE MANAGER DETECTION
# =============================================================================

# Detect system package manager
detect_package_manager() {
    local package_manager=""
    local os_type=""
    
    # Detect OS type
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_type="${ID:-unknown}"
    fi
    
    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        package_manager="apt"
    elif command -v yum >/dev/null 2>&1; then
        package_manager="yum"
    elif command -v dnf >/dev/null 2>&1; then
        package_manager="dnf"
    elif command -v zypper >/dev/null 2>&1; then
        package_manager="zypper"
    elif command -v pacman >/dev/null 2>&1; then
        package_manager="pacman"
    elif command -v apk >/dev/null 2>&1; then
        package_manager="apk"
    else
        error "No supported package manager found"
        return 1
    fi
    
    echo "$package_manager:$os_type"
    return 0
}

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================

# Install packages using appropriate package manager
install_packages() {
    local package_manager="$1"
    shift
    local packages=("$@")
    local failed_packages=()
    
    log "Installing packages using $package_manager..."
    
    # Update package index first
    case "$package_manager" in
        "apt")
            log "Updating package index..."
            apt-get update -qq || warning "Failed to update package index"
            
            for package in "${packages[@]}"; do
                if ! dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
                    log "Installing $package..."
                    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package"; then
                        log "Installed $package"
                    else
                        failed_packages+=("$package")
                        warning "Failed to install $package"
                    fi
                else
                    log "$package is already installed"
                fi
            done
            ;;
            
        "yum"|"dnf")
            for package in "${packages[@]}"; do
                # Map package names if needed
                local mapped_package="${PACKAGE_MAPPINGS[$package]:-$package}"
                
                if ! rpm -q "$mapped_package" >/dev/null 2>&1; then
                    log "Installing $mapped_package..."
                    if $package_manager install -y "$mapped_package" >/dev/null 2>&1; then
                        log "Installed $mapped_package"
                    else
                        failed_packages+=("$mapped_package")
                        warning "Failed to install $mapped_package"
                    fi
                else
                    log "$mapped_package is already installed"
                fi
            done
            ;;
            
        "apk")
            log "Updating package index..."
            apk update >/dev/null 2>&1
            
            for package in "${packages[@]}"; do
                if ! apk info -e "$package" >/dev/null 2>&1; then
                    log "Installing $package..."
                    if apk add --no-cache "$package" >/dev/null 2>&1; then
                        log "Installed $package"
                    else
                        failed_packages+=("$package")
                        warning "Failed to install $package"
                    fi
                else
                    log "$package is already installed"
                fi
            done
            ;;
            
        "pacman")
            log "Updating package database..."
            pacman -Sy --noconfirm >/dev/null 2>&1
            
            for package in "${packages[@]}"; do
                if ! pacman -Q "$package" >/dev/null 2>&1; then
                    log "Installing $package..."
                    if pacman -S --noconfirm "$package" >/dev/null 2>&1; then
                        log "Installed $package"
                    else
                        failed_packages+=("$package")
                        warning "Failed to install $package"
                    fi
                else
                    log "$package is already installed"
                fi
            done
            ;;
            
        "zypper")
            for package in "${packages[@]}"; do
                if ! rpm -q "$package" >/dev/null 2>&1; then
                    log "Installing $package..."
                    if zypper install -y "$package" >/dev/null 2>&1; then
                        log "Installed $package"
                    else
                        failed_packages+=("$package")
                        warning "Failed to install $package"
                    fi
                else
                    log "$package is already installed"
                fi
            done
            ;;
            
        *)
            error "Unsupported package manager: $package_manager"
            return 1
            ;;
    esac
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        error "Failed to install packages: ${failed_packages[*]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# DEPENDENCY INSTALLATION
# =============================================================================

# Install all required dependencies
install_dependencies() {
    local skip_optional=${1:-false}
    local verbose=${2:-true}
    
    [ "$verbose" = true ] && log "Starting dependency installation..."
    
    # Detect package manager
    local pm_info=$(detect_package_manager)
    local package_manager=$(echo "$pm_info" | cut -d: -f1)
    local os_type=$(echo "$pm_info" | cut -d: -f2)
    
    [ "$verbose" = true ] && log "Detected: $os_type with $package_manager"
    
    # Install essential packages
    log "Installing essential packages..."
    if ! install_packages "$package_manager" "${ESSENTIAL_PACKAGES[@]}"; then
        error "Failed to install essential packages"
        return 1
    fi
    
    # Install network packages
    log "Installing network packages..."
    if ! install_packages "$package_manager" "${NETWORK_PACKAGES[@]}"; then
        warning "Some network packages failed to install"
    fi
    
    # Install optional packages if not skipped
    if [ "$skip_optional" != true ]; then
        log "Installing optional packages..."
        install_packages "$package_manager" "${OPTIONAL_PACKAGES[@]}" || true
    fi
    
    log "Dependency installation completed"
    return 0
}

# =============================================================================
# DOCKER INSTALLATION
# =============================================================================

# Check and install Docker
check_and_install_docker() {
    local force_install=${1:-false}
    local verbose=${2:-true}
    
    [ "$verbose" = true ] && log "Checking Docker installation..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1 && [ "$force_install" != true ]; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,$//')
        [ "$verbose" = true ] && log "Docker is already installed (version $docker_version)"
        
        # Check if Docker daemon is running
        if docker info >/dev/null 2>&1; then
            [ "$verbose" = true ] && log "Docker daemon is running"
            return 0
        else
            warning "Docker daemon is not running"
            
            # Try to start Docker
            if systemctl start docker 2>/dev/null; then
                log "Started Docker daemon"
                
                # Enable Docker to start on boot
                systemctl enable docker 2>/dev/null || true
                return 0
            else
                error "Failed to start Docker daemon"
                return 1
            fi
        fi
    fi
    
    # Install Docker
    [ "$verbose" = true ] && log "Installing Docker..."
    
    # Detect package manager and OS
    local pm_info=$(detect_package_manager)
    local package_manager=$(echo "$pm_info" | cut -d: -f1)
    local os_type=$(echo "$pm_info" | cut -d: -f2)
    
    # Method 1: Use official Docker installation script
    if [ -n "${DOCKER_INSTALL_SCRIPTS[$os_type]}" ]; then
        log "Using official Docker installation script..."
        
        local temp_script=$(mktemp)
        if curl -fsSL "${DOCKER_INSTALL_SCRIPTS[$os_type]}" -o "$temp_script"; then
            if bash "$temp_script"; then
                rm -f "$temp_script"
                log "Docker installed successfully"
                
                # Add current user to docker group
                if [ -n "$SUDO_USER" ]; then
                    usermod -aG docker "$SUDO_USER" 2>/dev/null || true
                fi
                
                # Start and enable Docker
                systemctl start docker 2>/dev/null || true
                systemctl enable docker 2>/dev/null || true
                
                return 0
            else
                rm -f "$temp_script"
                error "Docker installation script failed"
            fi
        else
            rm -f "$temp_script"
            error "Failed to download Docker installation script"
        fi
    fi
    
    # Method 2: Install from distribution repositories
    log "Installing Docker from distribution repositories..."
    
    case "$package_manager" in
        "apt")
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$os_type/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add repository
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os_type \
              $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        "yum"|"dnf")
            # Install dependencies
            $package_manager install -y yum-utils
            
            # Add repository
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker
            $package_manager install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        *)
            error "Unsupported package manager for Docker installation: $package_manager"
            return 1
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker 2>/dev/null || true
    systemctl enable docker 2>/dev/null || true
    
    # Verify installation
    if docker --version >/dev/null 2>&1; then
        log "Docker installed successfully"
        return 0
    else
        error "Docker installation failed"
        return 1
    fi
}

# =============================================================================
# OPTIONAL TOOLS
# =============================================================================

# Install optional tools
install_optional_tools() {
    local tools=("$@")
    local verbose=true
    
    [ "$verbose" = true ] && log "Installing optional tools..."
    
    # Detect package manager
    local pm_info=$(detect_package_manager)
    local package_manager=$(echo "$pm_info" | cut -d: -f1)
    
    # Install Docker Compose if requested
    if [[ " ${tools[@]} " =~ " docker-compose " ]]; then
        if ! command -v docker-compose >/dev/null 2>&1; then
            log "Installing Docker Compose..."
            
            local compose_version="v2.24.0"
            local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
            
            if curl -L "$compose_url" -o /usr/local/bin/docker-compose; then
                chmod +x /usr/local/bin/docker-compose
                log "Docker Compose installed"
            else
                warning "Failed to install Docker Compose"
            fi
        else
            log "Docker Compose is already installed"
        fi
    fi
    
    # Install other tools
    local other_tools=()
    for tool in "${tools[@]}"; do
        if [ "$tool" != "docker-compose" ]; then
            other_tools+=("$tool")
        fi
    done
    
    if [ ${#other_tools[@]} -gt 0 ]; then
        install_packages "$package_manager" "${other_tools[@]}"
    fi
    
    return 0
}

# =============================================================================
# SYSTEM UPDATES
# =============================================================================

# Update system packages
update_system_packages() {
    local upgrade=${1:-false}
    local verbose=${2:-true}
    
    [ "$verbose" = true ] && log "Updating system packages..."
    
    # Detect package manager
    local pm_info=$(detect_package_manager)
    local package_manager=$(echo "$pm_info" | cut -d: -f1)
    
    case "$package_manager" in
        "apt")
            apt-get update -qq
            if [ "$upgrade" = true ]; then
                DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
            fi
            ;;
            
        "yum")
            yum check-update -q || true
            if [ "$upgrade" = true ]; then
                yum upgrade -y -q
            fi
            ;;
            
        "dnf")
            dnf check-update -q || true
            if [ "$upgrade" = true ]; then
                dnf upgrade -y -q
            fi
            ;;
            
        "apk")
            apk update
            if [ "$upgrade" = true ]; then
                apk upgrade
            fi
            ;;
            
        "pacman")
            pacman -Sy --noconfirm
            if [ "$upgrade" = true ]; then
                pacman -Su --noconfirm
            fi
            ;;
            
        "zypper")
            zypper refresh -q
            if [ "$upgrade" = true ]; then
                zypper update -y
            fi
            ;;
            
        *)
            warning "Package update not implemented for: $package_manager"
            ;;
    esac
    
    [ "$verbose" = true ] && log "System packages updated"
    return 0
}

# =============================================================================
# REPOSITORY CONFIGURATION
# =============================================================================

# Configure additional package repositories
configure_package_repositories() {
    local verbose=${1:-true}
    
    [ "$verbose" = true ] && log "Configuring package repositories..."
    
    # Detect package manager and OS
    local pm_info=$(detect_package_manager)
    local package_manager=$(echo "$pm_info" | cut -d: -f1)
    local os_type=$(echo "$pm_info" | cut -d: -f2)
    
    case "$package_manager:$os_type" in
        "apt:ubuntu"|"apt:debian")
            # Enable universe repository on Ubuntu
            if [ "$os_type" = "ubuntu" ]; then
                add-apt-repository universe -y 2>/dev/null || true
            fi
            
            # Add useful repositories
            if ! grep -q "^deb.*multiverse" /etc/apt/sources.list 2>/dev/null; then
                add-apt-repository multiverse -y 2>/dev/null || true
            fi
            ;;
            
        "yum:centos"|"yum:rhel")
            # Enable EPEL repository
            if ! rpm -q epel-release >/dev/null 2>&1; then
                yum install -y epel-release
            fi
            ;;
            
        "dnf:fedora")
            # Fedora usually has everything needed
            true
            ;;
            
        *)
            [ "$verbose" = true ] && log "No additional repositories needed for $os_type"
            ;;
    esac
    
    [ "$verbose" = true ] && log "Package repositories configured"
    return 0
}

# =============================================================================
# DEPENDENCY VERIFICATION
# =============================================================================

# Verify all dependencies are installed
verify_dependencies() {
    local verbose=${1:-true}
    local missing_deps=()
    
    [ "$verbose" = true ] && log "Verifying dependencies..."
    
    # Check essential commands
    local required_commands=(
        "curl" "wget" "tar" "gzip" "iptables" "systemctl"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    elif ! docker info >/dev/null 2>&1; then
        missing_deps+=("docker-daemon")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        [ "$verbose" = true ] && error "Missing dependencies: ${missing_deps[*]}"
        return 1
    else
        [ "$verbose" = true ] && log "All dependencies verified"
        return 0
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f detect_package_manager
export -f install_packages
export -f install_dependencies
export -f check_and_install_docker
export -f install_optional_tools
export -f update_system_packages
export -f configure_package_repositories
export -f verify_dependencies

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

# If script is run directly, provide CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "install")
            install_dependencies false true
            ;;
        "docker")
            check_and_install_docker false true
            ;;
        "update")
            update_system_packages "${2:-false}" true
            ;;
        "verify")
            verify_dependencies true
            ;;
        "optional")
            shift
            install_optional_tools "$@"
            ;;
        *)
            echo "Usage: $0 {install|docker|update|verify|optional}"
            echo ""
            echo "Commands:"
            echo "  install              - Install all required dependencies"
            echo "  docker               - Install Docker and Docker Compose"
            echo "  update [upgrade]     - Update package lists (upgrade if specified)"
            echo "  verify               - Verify all dependencies are installed"
            echo "  optional [tools...]  - Install optional tools"
            echo ""
            echo "Examples:"
            echo "  $0 install"
            echo "  $0 docker"
            echo "  $0 update true"
            echo "  $0 optional jq qrencode"
            exit 1
            ;;
    esac
fi