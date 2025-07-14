#!/bin/bash

# VPN Installation Script
# Supports both source build and pre-built release installation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
VPN_BINARY_NAME="vpn-manager"
INSTALL_PREFIX="/usr/local"
BACKUP_DIR="/tmp/vpn-backup-$(date +%Y%m%d-%H%M%S)"
INSTALL_MODE=""
RELEASE_ARCHIVE=""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root directly. It will ask for sudo when needed."
        exit 1
    fi
}

# Function to detect installation mode
detect_installation_mode() {
    # Check if we're running from extracted release
    if [[ -f "$SCRIPT_DIR/VERSION" ]] && [[ -d "$SCRIPT_DIR/bin" ]]; then
        INSTALL_MODE="release"
        log_info "Detected pre-built release installation"
        return
    fi
    
    # Check if we're in a release directory with archive
    if [[ -f "$SCRIPT_DIR/release/vpn-release.tar.gz" ]]; then
        INSTALL_MODE="release-archive"
        RELEASE_ARCHIVE="$SCRIPT_DIR/release/vpn-release.tar.gz"
        log_info "Detected release archive installation"
        return
    fi
    
    # Check if we're in source directory
    if [[ -f "$SCRIPT_DIR/Cargo.toml" ]]; then
        INSTALL_MODE="source"
        log_info "Detected source installation"
        return
    fi
    
    log_error "Could not determine installation mode. Make sure you're running from:"
    echo "  - VPN source directory (contains Cargo.toml)"
    echo "  - Release directory (contains release/vpn-release.tar.gz)"
    echo "  - Extracted release (contains VERSION and bin/ directory)"
    exit 1
}

# Function to check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    if [[ "$INSTALL_MODE" == "source" ]]; then
        # Check if Rust is installed
        if ! command -v rustc &> /dev/null; then
            log_error "Rust is not installed. Please install Rust first:"
            echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            exit 1
        fi
        
        # Check if Cargo is installed
        if ! command -v cargo &> /dev/null; then
            log_error "Cargo is not installed. Please install Rust toolchain."
            exit 1
        fi
    fi
    
    # Check for required system tools
    local required_tools=("tar" "sudo")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "System requirements check passed"
}

# Function to detect and backup existing VPN installations
detect_existing_installations() {
    log_info "Detecting existing VPN installations..."
    
    local found_installations=()
    
    # Check common locations for VPN binaries
    local search_paths=(
        "/usr/local/bin/vpn"
        "/usr/local/bin/vpn-manager"
        "/usr/local/bin/vpn-cli"
        "/usr/local/bin/vpn-api"
        "/usr/local/bin/vpn-proxy"
        "/usr/local/bin/vpn-identity"
        "/usr/bin/vpn"
        "/usr/bin/vpn-manager"
        "$HOME/.local/bin/vpn"
        "$HOME/.local/bin/vpn-manager"
        "$HOME/.vpn-venv/bin/vpn"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            found_installations+=("$path")
            log_warning "Found existing installation: $path"
            
            # Check what type of installation it is
            if file "$path" 2>/dev/null | grep -q "Python"; then
                log_warning "  -> Python-based installation detected"
            elif file "$path" 2>/dev/null | grep -q "ELF"; then
                log_warning "  -> Binary (possibly Rust) installation detected"
            else
                log_warning "  -> Unknown installation type"
            fi
        fi
    done
    
    # Check for Python virtual environments
    if [[ -d "$HOME/.vpn-venv" ]]; then
        log_warning "Found Python VPN virtual environment: $HOME/.vpn-venv"
        found_installations+=("$HOME/.vpn-venv")
    fi
    
    # Check for systemd services
    if systemctl list-unit-files 2>/dev/null | grep -q "vpn"; then
        log_warning "Found VPN-related systemd services"
        systemctl list-unit-files 2>/dev/null | grep vpn || true
    fi
    
    # Check for Docker containers
    if command -v docker &> /dev/null && docker ps -a 2>/dev/null | grep -q "vpn"; then
        log_warning "Found VPN-related Docker containers"
        docker ps -a | grep vpn || true
    fi
    
    if [[ ${#found_installations[@]} -gt 0 ]]; then
        echo
        log_warning "Found ${#found_installations[@]} existing VPN installation(s)."
        echo "The following will be backed up and removed:"
        printf '%s\n' "${found_installations[@]}"
        echo
        read -p "Do you want to continue? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user."
            exit 0
        fi
        
        # Create backup directory
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
        
        return 0
    else
        log_success "No conflicting VPN installations found"
        return 1
    fi
}

# Function to remove existing installations
remove_existing_installations() {
    log_info "Removing existing VPN installations..."
    
    # Stop systemd services if they exist
    local vpn_services=("vpn-manager" "vpn-api" "vpn-proxy" "vpn-identity" "vpn")
    for service in "${vpn_services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            log_info "Stopping service: $service"
            sudo systemctl stop "$service" || true
            sudo systemctl disable "$service" || true
        fi
    done
    
    # Remove VPN binaries from common locations
    local binary_names=("vpn" "vpn-manager" "vpn-cli" "vpn-api" "vpn-proxy" "vpn-identity")
    local binary_dirs=("/usr/local/bin" "/usr/bin" "/bin" "$HOME/.local/bin")
    
    for dir in "${binary_dirs[@]}"; do
        for binary in "${binary_names[@]}"; do
            local path="$dir/$binary"
            if [[ -f "$path" ]]; then
                log_info "Backing up and removing: $path"
                if [[ "$dir" == "$HOME/.local/bin" ]]; then
                    cp "$path" "$BACKUP_DIR/$(basename "$path")-user-local" 2>/dev/null || true
                    rm -f "$path"
                else
                    sudo cp "$path" "$BACKUP_DIR/$(basename "$path")-system" 2>/dev/null || true
                    sudo rm -f "$path"
                fi
            fi
        done
    done
    
    # Remove Python virtual environment
    if [[ -d "$HOME/.vpn-venv" ]]; then
        log_info "Backing up and removing Python VPN environment: $HOME/.vpn-venv"
        # Just backup the requirements if exists
        if [[ -f "$HOME/.vpn-venv/requirements.txt" ]]; then
            cp "$HOME/.vpn-venv/requirements.txt" "$BACKUP_DIR/vpn-venv-requirements.txt" 2>/dev/null || true
        fi
        rm -rf "$HOME/.vpn-venv"
    fi
    
    # Remove systemd service files
    for service in "${vpn_services[@]}"; do
        if [[ -f "/etc/systemd/system/$service.service" ]]; then
            log_info "Backing up and removing systemd service: $service"
            sudo cp "/etc/systemd/system/$service.service" "$BACKUP_DIR/$service.service" 2>/dev/null || true
            sudo rm -f "/etc/systemd/system/$service.service"
        fi
    done
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Remove VPN from PATH (common shell configs)
    local shell_configs=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.profile"
        "$HOME/.bash_profile"
    )
    
    for config in "${shell_configs[@]}"; do
        if [[ -f "$config" ]] && grep -q "vpn" "$config"; then
            log_info "Checking shell config: $config"
            # Create backup
            cp "$config" "$BACKUP_DIR/$(basename "$config")" 2>/dev/null || true
            # Remove VPN-related PATH entries (be conservative)
            sed -i.bak '/\.vpn-venv/d' "$config" 2>/dev/null || true
        fi
    done
    
    log_success "Existing installations removed and backed up to: $BACKUP_DIR"
}

# Function to extract release archive
extract_release_archive() {
    log_info "Extracting release archive..."
    
    # Create /opt/vpn directory
    log_info "Creating /opt/vpn directory..."
    sudo mkdir -p /opt/vpn
    
    # Copy archive to /opt/vpn
    log_info "Copying archive to /opt/vpn..."
    sudo cp "$RELEASE_ARCHIVE" /opt/vpn/
    
    # Extract archive in /opt/vpn
    cd /opt/vpn
    log_info "Extracting archive in /opt/vpn..."
    if ! sudo tar -xzf "$(basename "$RELEASE_ARCHIVE")"; then
        log_error "Failed to extract release archive"
        exit 1
    fi
    
    # Find the extracted directory
    local release_dir=$(find . -maxdepth 1 -type d -name "vpn-release" | head -1)
    if [[ -z "$release_dir" ]]; then
        log_error "Could not find extracted release directory"
        exit 1
    fi
    
    # Update script directory to extracted location
    SCRIPT_DIR="/opt/vpn/$release_dir"
    cd "$SCRIPT_DIR"
    
    # Remove the archive copy
    sudo rm -f "/opt/vpn/$(basename "$RELEASE_ARCHIVE")"
    
    log_success "Release archive extracted successfully to /opt/vpn"
}

# Function to build from source
build_from_source() {
    log_info "Building VPN from source..."
    
    cd "$PROJECT_ROOT"
    
    # Clean previous builds
    log_info "Cleaning previous builds..."
    cargo clean
    
    # Update dependencies
    log_info "Updating dependencies..."
    cargo update
    
    # Build in release mode
    log_info "Building in release mode (this may take a while)..."
    
    # Set up DATABASE_URL for sqlx macros (required for vpn-identity)
    export DATABASE_URL="sqlite::memory:"
    log_info "Setting up environment for sqlx macros..."
    
    if ! DATABASE_URL="sqlite::memory:" cargo build --release --locked; then
        log_error "Failed to build VPN"
        exit 1
    fi
    
    log_success "VPN built successfully"
}

# Function to install binaries
install_binaries() {
    log_info "Installing VPN binaries..."
    
    local source_dir=""
    if [[ "$INSTALL_MODE" == "source" ]]; then
        source_dir="$PROJECT_ROOT/target/release"
    else
        source_dir="$SCRIPT_DIR/bin"
    fi
    
    # Check if source directory exists
    if [[ ! -d "$source_dir" ]]; then
        log_error "Binary directory not found: $source_dir"
        log_error "The release archive appears to be missing compiled binaries."
        log_error "Please ensure you're using a complete release archive with pre-built binaries."
        exit 1
    fi
    
    # Check if directory is empty
    if [[ -z "$(ls -A "$source_dir" 2>/dev/null)" ]]; then
        log_error "Binary directory is empty: $source_dir"
        log_error "The release archive does not contain any compiled binaries."
        log_error "Please build the project first or use a complete release archive."
        exit 1
    fi
    
    # List of binaries to install (install vpn first as others may depend on it)
    local binaries=("vpn" "vpn-manager" "vpn-cli" "vpn-api" "vpn-proxy" "vpn-identity")
    local installed_count=0
    
    log_info "Looking for binaries in: $source_dir"
    log_info "Available files:"
    ls -la "$source_dir" 2>/dev/null || true
    
    for binary in "${binaries[@]}"; do
        if [[ -e "$source_dir/$binary" ]]; then
            log_info "Installing $binary..."
            # Check if it's a symlink
            if [[ -L "$source_dir/$binary" ]]; then
                # Copy the symlink preserving its nature
                sudo cp -P "$source_dir/$binary" "$INSTALL_PREFIX/bin/$binary"
            else
                # Regular file
                sudo cp "$source_dir/$binary" "$INSTALL_PREFIX/bin/$binary"
                sudo chmod +x "$INSTALL_PREFIX/bin/$binary"
            fi
            ((installed_count++))
        else
            log_warning "Binary $binary not found in $source_dir"
        fi
    done
    
    if [[ $installed_count -eq 0 ]]; then
        log_error "No binaries were installed"
        log_error "Expected binaries: ${binaries[*]}"
        log_error "Please ensure the release archive contains compiled binaries in the 'bin' directory."
        exit 1
    fi
    
    # Create symlink for main vpn command
    if [[ -f "$INSTALL_PREFIX/bin/vpn-manager" ]]; then
        log_info "Creating vpn symlink..."
        sudo ln -sf "$INSTALL_PREFIX/bin/vpn-manager" "$INSTALL_PREFIX/bin/vpn"
    fi
    
    log_success "Installed $installed_count binaries"
}

# Function to install configuration files
install_configs() {
    log_info "Installing configuration files..."
    
    local config_dir="/etc/vpn"
    sudo mkdir -p "$config_dir"
    
    if [[ -d "$SCRIPT_DIR/configs" ]]; then
        log_info "Copying configuration files to $config_dir..."
        sudo cp -r "$SCRIPT_DIR/configs"/* "$config_dir/" 2>/dev/null || true
        
        # Set proper permissions
        sudo chmod 644 "$config_dir"/*.toml 2>/dev/null || true
        sudo chmod 644 "$config_dir"/*.yaml 2>/dev/null || true
        sudo chmod 644 "$config_dir"/*.yml 2>/dev/null || true
    fi
    
    log_success "Configuration files installed"
}

# Function to install systemd services
install_systemd_services() {
    log_info "Installing systemd services..."
    
    if [[ -d "$SCRIPT_DIR/systemd" ]]; then
        local service_count=0
        for service_file in "$SCRIPT_DIR/systemd"/*.service; do
            if [[ -f "$service_file" ]]; then
                local service_name=$(basename "$service_file")
                log_info "Installing $service_name..."
                sudo cp "$service_file" "/etc/systemd/system/"
                ((service_count++))
            fi
        done
        
        if [[ $service_count -gt 0 ]]; then
            sudo systemctl daemon-reload
            log_success "Installed $service_count systemd services"
        fi
    fi
}

# Function to install Docker files
install_docker_files() {
    log_info "Installing Docker files..."
    sudo mkdir -p /opt/vpn/docker
    
    # Copy Docker files from release docker directory
    if [[ -d "$SCRIPT_DIR/docker" ]]; then
        log_info "Copying Docker files from release..."
        sudo cp -r "$SCRIPT_DIR/docker"/* /opt/vpn/docker/ 2>/dev/null || true
    fi
    
    # Also check templates for any Docker files (for backward compatibility)
    if [[ -d "$SCRIPT_DIR/templates" ]]; then
        # Copy Dockerfiles
        find "$SCRIPT_DIR/templates" -name "Dockerfile*" -exec sudo cp {} /opt/vpn/docker/ \; 2>/dev/null || true
        # Copy docker-compose files
        find "$SCRIPT_DIR/templates" -name "docker-compose*.yml" -exec sudo cp {} /opt/vpn/docker/ \; 2>/dev/null || true
    fi
    
    log_success "Docker files installed to /opt/vpn/docker"
}

# Function to install templates
install_templates() {
    if [[ -d "$SCRIPT_DIR/templates" ]]; then
        log_info "Templates found. Creating /opt/vpn/templates directory..."
        sudo mkdir -p /opt/vpn/templates
        sudo cp -r "$SCRIPT_DIR/templates"/* /opt/vpn/templates/ 2>/dev/null || true
        log_success "Templates installed to /opt/vpn/templates"
    fi
}

# Function to create required directories
create_directories() {
    log_info "Creating required directories..."
    sudo mkdir -p /opt/vpn/db
    sudo chmod 755 /opt/vpn/db
    log_success "Created /opt/vpn/db directory"
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check if VPN is in PATH
    if ! command -v vpn &> /dev/null; then
        log_error "VPN command not found in PATH after installation"
        exit 1
    fi
    
    # Check version
    local version_output
    if version_output=$(vpn --version 2>&1); then
        log_success "VPN version: $version_output"
    else
        log_warning "Could not get VPN version"
    fi
    
    # Check installed binaries
    local binaries=("vpn" "vpn-manager" "vpn-cli" "vpn-api" "vpn-proxy" "vpn-identity")
    log_info "Installed binaries:"
    for binary in "${binaries[@]}"; do
        if command -v "$binary" &> /dev/null; then
            echo "  ✓ $binary"
        fi
    done
    
    log_success "Installation verification completed"
}

# Function to create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    local uninstall_script="/opt/vpn/uninstall.sh"
    sudo mkdir -p /opt/vpn
    
    sudo tee "$uninstall_script" > /dev/null << 'EOF'
#!/bin/bash

# VPN Uninstallation Script

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "Uninstalling VPN..."

# Stop and disable services
services=("vpn-manager" "vpn-api" "vpn-proxy" "vpn-identity")
for service in "${services[@]}"; do
    if systemctl is-active "$service" &>/dev/null; then
        log_info "Stopping $service..."
        sudo systemctl stop "$service"
        sudo systemctl disable "$service"
    fi
done

# Remove binaries
binaries=("vpn" "vpn-manager" "vpn-cli" "vpn-api" "vpn-proxy" "vpn-identity")
for binary in "${binaries[@]}"; do
    if [[ -f "/usr/local/bin/$binary" ]]; then
        log_info "Removing /usr/local/bin/$binary"
        sudo rm -f "/usr/local/bin/$binary"
    fi
done

# Remove systemd services
for service in "${services[@]}"; do
    if [[ -f "/etc/systemd/system/$service.service" ]]; then
        log_info "Removing systemd service: $service"
        sudo rm -f "/etc/systemd/system/$service.service"
    fi
done

# Remove configuration directory
if [[ -d "/etc/vpn" ]]; then
    log_info "Removing configuration directory: /etc/vpn"
    sudo rm -rf "/etc/vpn"
fi

# Remove Docker files
if [[ -d "/opt/vpn/docker" ]]; then
    log_info "Removing Docker files: /opt/vpn/docker"
    sudo rm -rf "/opt/vpn/docker"
fi

# Remove templates
if [[ -d "/opt/vpn/templates" ]]; then
    log_info "Removing templates: /opt/vpn/templates"
    sudo rm -rf "/opt/vpn/templates"
fi

# Remove database directory
if [[ -d "/opt/vpn/db" ]]; then
    log_info "Removing database directory: /opt/vpn/db"
    read -p "Remove database files? This will delete all VPN data! [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo rm -rf "/opt/vpn/db"
    else
        log_info "Keeping database directory"
    fi
fi

# Remove opt directory if empty
if [[ -d "/opt/vpn" ]]; then
    if [[ -z "$(ls -A /opt/vpn)" ]]; then
        sudo rmdir "/opt/vpn"
    fi
fi

# Reload systemd
sudo systemctl daemon-reload

log_success "VPN uninstalled successfully"
log_info "Backups may be preserved in /tmp/vpn-backup-* directories"
EOF

    sudo chmod +x "$uninstall_script"
    log_success "Uninstall script created: $uninstall_script"
}

# Function to display post-installation instructions
show_post_install_info() {
    echo
    log_success "=== VPN Installation Complete ==="
    echo
    echo "Installation Summary:"
    echo "  • Installation mode: $INSTALL_MODE"
    echo "  • Binaries installed to: $INSTALL_PREFIX/bin/"
    echo "  • Configuration files: /etc/vpn/"
    echo "  • Docker files: /opt/vpn/docker/"
    echo "  • Templates: /opt/vpn/templates/"
    echo "  • Database directory: /opt/vpn/db/"
    echo "  • Uninstall script: /opt/vpn/uninstall.sh"
    if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
        echo "  • Backups created in: $BACKUP_DIR"
    fi
    echo
    echo "Usage:"
    echo "  vpn --help              # Show help"
    echo "  vpn --version           # Show version"
    echo "  sudo vpn-manager        # Start VPN manager"
    echo "  vpn-cli                 # Use CLI interface"
    echo
    echo "Systemd Services (if installed):"
    echo "  sudo systemctl start vpn-manager    # Start VPN manager service"
    echo "  sudo systemctl enable vpn-manager   # Enable auto-start"
    echo "  sudo systemctl status vpn-manager   # Check service status"
    echo
    echo "Docker Setup (if using Docker):"
    echo "  cd /opt/vpn/docker"
    echo "  # Main VPN container:"
    echo "  docker build -f Dockerfile -t vpn:latest ."
    echo "  # Or use docker-compose:"
    echo "  docker-compose -f docker-compose.hub.yml up -d"
    echo "  # Templates with additional configs:"
    echo "  cd /opt/vpn/templates/docker-compose"
    echo "  docker-compose -f production.yml up -d"
    echo
    echo "Uninstallation:"
    echo "  sudo /opt/vpn/uninstall.sh"
    echo
}

# Main installation function
main() {
    echo "=== VPN Installation Script ==="
    echo
    
    check_privileges
    detect_installation_mode
    check_requirements
    
    if detect_existing_installations; then
        remove_existing_installations
    fi
    
    # Handle different installation modes
    case "$INSTALL_MODE" in
        "source")
            build_from_source
            ;;
        "release-archive")
            extract_release_archive
            ;;
        "release")
            # Already extracted, nothing to do
            ;;
    esac
    
    install_binaries
    install_configs
    install_systemd_services
    install_docker_files
    install_templates
    create_directories
    verify_installation
    create_uninstall_script
    show_post_install_info
    
    # Note: We don't cleanup /opt/vpn since that's where we installed the files
    
    log_success "VPN installation completed successfully!"
}

# Handle script interruption
trap 'log_error "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"