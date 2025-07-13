#!/bin/bash

# VPN Rust Installation Script
# This script builds the VPN server from Rust source code and removes conflicts with other implementations

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
VPN_BINARY_NAME="vpn"
INSTALL_PREFIX="/usr/local"
BACKUP_DIR="/tmp/vpn-backup-$(date +%Y%m%d-%H%M%S)"

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

# Function to check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
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
    
    # Check if git is installed (for version info)
    if ! command -v git &> /dev/null; then
        log_warning "Git is not installed. Version information may be limited."
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        log_error "Not in a Rust project directory. Please run this script from the VPN project root."
        exit 1
    fi
    
    log_success "System requirements check passed"
}

# Function to detect and backup existing VPN installations
detect_existing_installations() {
    log_info "Detecting existing VPN installations..."
    
    local found_installations=()
    
    # Check common locations for VPN binaries
    local search_paths=(
        "/usr/local/bin/vpn"
        "/usr/bin/vpn"
        "/bin/vpn"
        "$HOME/.local/bin/vpn"
        "$HOME/.vpn-venv/bin/vpn"
    )
    
    # Check PATH for vpn command
    if command -v vpn &> /dev/null; then
        local vpn_path=$(which vpn)
        found_installations+=("$vpn_path")
        log_warning "Found VPN installation: $vpn_path"
        
        # Check what type of installation it is
        if file "$vpn_path" | grep -q "Python"; then
            log_warning "  -> Python-based installation detected"
        elif file "$vpn_path" | grep -q "ELF"; then
            log_warning "  -> Binary (possibly Rust) installation detected"
        else
            log_warning "  -> Unknown installation type"
        fi
    fi
    
    # Check for Python virtual environments
    if [[ -d "$HOME/.vpn-venv" ]]; then
        log_warning "Found Python VPN virtual environment: $HOME/.vpn-venv"
        found_installations+=("$HOME/.vpn-venv")
    fi
    
    # Check for systemd services
    if systemctl list-unit-files | grep -q "vpn"; then
        log_warning "Found VPN-related systemd services"
        systemctl list-unit-files | grep vpn || true
    fi
    
    if [[ ${#found_installations[@]} -gt 0 ]]; then
        echo
        log_warning "Found ${#found_installations[@]} existing VPN installation(s)."
        echo "The script will create backups before removing them."
        echo
        read -p "Do you want to continue and remove existing installations? [y/N]: " confirm
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
    
    # Remove VPN binaries from common locations
    local binary_paths=(
        "/usr/local/bin/vpn"
        "/usr/bin/vpn"
        "/bin/vpn"
    )
    
    for path in "${binary_paths[@]}"; do
        if [[ -f "$path" ]]; then
            log_info "Backing up and removing: $path"
            sudo cp "$path" "$BACKUP_DIR/$(basename "$path")-$(dirname "$path" | tr '/' '-')" 2>/dev/null || true
            sudo rm -f "$path"
        fi
    done
    
    # Remove user-local installations
    if [[ -f "$HOME/.local/bin/vpn" ]]; then
        log_info "Backing up and removing: $HOME/.local/bin/vpn"
        cp "$HOME/.local/bin/vpn" "$BACKUP_DIR/vpn-user-local" 2>/dev/null || true
        rm -f "$HOME/.local/bin/vpn"
    fi
    
    # Remove Python virtual environment
    if [[ -d "$HOME/.vpn-venv" ]]; then
        log_info "Backing up and removing Python VPN environment: $HOME/.vpn-venv"
        cp -r "$HOME/.vpn-venv" "$BACKUP_DIR/vpn-venv" 2>/dev/null || true
        rm -rf "$HOME/.vpn-venv"
    fi
    
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

# Function to build the Rust VPN
build_rust_vpn() {
    log_info "Building Rust VPN from source..."
    
    cd "$PROJECT_ROOT"
    
    # Clean previous builds
    log_info "Cleaning previous builds..."
    cargo clean
    
    # Update dependencies
    log_info "Updating dependencies..."
    cargo update
    
    # Build in release mode
    log_info "Building in release mode (this may take a while)..."
    if ! cargo build --release; then
        log_error "Failed to build Rust VPN"
        exit 1
    fi
    
    # Verify the binary was created
    if [[ ! -f "$PROJECT_ROOT/target/release/$VPN_BINARY_NAME" ]]; then
        log_error "Build completed but binary not found at: $PROJECT_ROOT/target/release/$VPN_BINARY_NAME"
        exit 1
    fi
    
    log_success "Rust VPN built successfully"
}

# Function to install the Rust VPN
install_rust_vpn() {
    log_info "Installing Rust VPN..."
    
    local source_binary="$PROJECT_ROOT/target/release/$VPN_BINARY_NAME"
    local target_binary="$INSTALL_PREFIX/bin/$VPN_BINARY_NAME"
    
    # Install the binary
    log_info "Installing binary to: $target_binary"
    sudo cp "$source_binary" "$target_binary"
    sudo chmod +x "$target_binary"
    
    # Verify installation
    if [[ ! -f "$target_binary" ]]; then
        log_error "Installation failed: binary not found at $target_binary"
        exit 1
    fi
    
    # Test the installation
    log_info "Testing installation..."
    if ! "$target_binary" --version &> /dev/null; then
        log_error "Installation test failed: binary is not executable or has issues"
        exit 1
    fi
    
    log_success "Rust VPN installed successfully to: $target_binary"
}

# Function to setup shell completions (optional)
setup_shell_completions() {
    log_info "Setting up shell completions..."
    
    # Check if the binary supports completion generation
    if "$INSTALL_PREFIX/bin/$VPN_BINARY_NAME" --help 2>&1 | grep -q "completion\|complete"; then
        # Try to generate completions (if supported)
        local completion_dir="/etc/bash_completion.d"
        if [[ -d "$completion_dir" ]]; then
            log_info "Installing bash completions..."
            # This would need to be implemented in the Rust binary
            # sudo "$INSTALL_PREFIX/bin/$VPN_BINARY_NAME" completion bash > "$completion_dir/vpn"
        fi
    fi
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
        log_error "Failed to get VPN version"
        exit 1
    fi
    
    # Check if it's the Rust version
    local vpn_path=$(which vpn)
    if file "$vpn_path" | grep -q "ELF"; then
        log_success "Rust VPN binary confirmed at: $vpn_path"
    else
        log_warning "Installed binary may not be the Rust version"
    fi
    
    log_success "Installation verification completed"
}

# Function to create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    local uninstall_script="$PROJECT_ROOT/uninstall.sh"
    
    cat > "$uninstall_script" << 'EOF'
#!/bin/bash

# VPN Rust Uninstallation Script

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

log_info "Uninstalling Rust VPN..."

# Remove binary
if [[ -f "/usr/local/bin/vpn" ]]; then
    log_info "Removing /usr/local/bin/vpn"
    sudo rm -f "/usr/local/bin/vpn"
fi

# Remove completions
if [[ -f "/etc/bash_completion.d/vpn" ]]; then
    log_info "Removing shell completions"
    sudo rm -f "/etc/bash_completion.d/vpn"
fi

log_success "Rust VPN uninstalled successfully"
log_info "Backups are preserved in /tmp/vpn-backup-* directories"
EOF

    chmod +x "$uninstall_script"
    log_success "Uninstall script created: $uninstall_script"
}

# Function to display post-installation instructions
show_post_install_info() {
    echo
    log_success "=== VPN Rust Installation Complete ==="
    echo
    echo "Installation Summary:"
    echo "  • Rust VPN binary installed to: $INSTALL_PREFIX/bin/$VPN_BINARY_NAME"
    echo "  • Version: $(vpn --version 2>/dev/null || echo 'Unknown')"
    echo "  • Backups created in: $BACKUP_DIR"
    echo
    echo "Usage:"
    echo "  vpn --help          # Show help"
    echo "  vpn --version       # Show version"
    echo "  sudo vpn menu       # Start interactive menu (requires sudo)"
    echo
    echo "Next Steps:"
    echo "  1. Restart your terminal or run: source ~/.bashrc"
    echo "  2. Run 'vpn --version' to verify installation"
    echo "  3. Run 'sudo vpn menu' to start the VPN management interface"
    echo
    echo "Uninstallation:"
    echo "  • Run: $PROJECT_ROOT/uninstall.sh"
    echo
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "Backup Information:"
        echo "  • Previous installations backed up to: $BACKUP_DIR"
        echo "  • To restore previous installation, check the backup directory"
        echo
    fi
}

# Main installation function
main() {
    echo "=== VPN Rust Installation Script ==="
    echo "This script will:"
    echo "  1. Check system requirements"
    echo "  2. Detect and remove existing VPN installations"
    echo "  3. Build VPN from Rust source code"
    echo "  4. Install the new Rust VPN binary"
    echo "  5. Verify the installation"
    echo
    
    check_privileges
    check_requirements
    
    if detect_existing_installations; then
        remove_existing_installations
    fi
    
    build_rust_vpn
    install_rust_vpn
    setup_shell_completions
    verify_installation
    create_uninstall_script
    show_post_install_info
    
    log_success "VPN Rust installation completed successfully!"
}

# Handle script interruption
trap 'log_error "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"