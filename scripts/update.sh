#!/bin/bash
#
# VPN CLI Update Script
# Updates repository, rebuilds project, and reinstalls VPN CLI tool
#
# Usage: ./update.sh [options]
# Options:
#   --no-menu          Don't launch the menu after update
#   --clean            Clean build (cargo clean before building)
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
CLEAN_BUILD=false
VERBOSE=false
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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if repository exists
    if [ ! -d "$REPO_DIR" ]; then
        print_error "VPN repository not found at $REPO_DIR"
        print_error "Please run install.sh first"
        exit 1
    fi
    
    # Check if Rust is installed
    if ! command -v rustc &> /dev/null || ! command -v cargo &> /dev/null; then
        print_error "Rust toolchain not found"
        print_error "Please run install.sh first"
        exit 1
    fi
    
    # Check if vpn CLI is installed
    if ! command -v vpn &> /dev/null; then
        print_warning "VPN CLI not found in PATH, but continuing with update..."
    fi
    
    print_success "Prerequisites checked"
}

# Function to update repository
update_repository() {
    print_status "Updating VPN repository..."
    
    cd "$REPO_DIR"
    
    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        print_error "Not a git repository: $REPO_DIR"
        exit 1
    fi
    
    # Save current branch
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "master")
    
    # Stash any local changes
    if ! git diff-index --quiet HEAD --; then
        print_warning "Local changes detected, stashing..."
        git stash push -m "Auto-stash before update $(date)"
    fi
    
    # Fetch latest changes
    print_status "Fetching latest changes..."
    git fetch origin
    
    # Pull latest changes
    if git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
        print_status "Pulling latest changes from origin/$CURRENT_BRANCH..."
        git pull origin "$CURRENT_BRANCH"
    else
        print_warning "Branch origin/$CURRENT_BRANCH not found, trying master..."
        git pull origin master || git pull origin main
    fi
    
    print_success "Repository updated"
}

# Function to update Rust if needed
update_rust() {
    print_status "Checking Rust version..."
    
    # Check minimum version (1.70.0)
    RUST_VERSION=$(rustc --version | cut -d' ' -f2)
    MIN_VERSION="1.70.0"
    
    if [ "$(printf '%s\n' "$MIN_VERSION" "$RUST_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
        print_warning "Rust version $RUST_VERSION is older than minimum required $MIN_VERSION"
        print_status "Updating Rust..."
        rustup update stable
        print_success "Rust updated"
    else
        print_success "Rust version $RUST_VERSION is up to date"
    fi
}

# Function to rebuild project
rebuild_project() {
    print_status "Rebuilding VPN project..."
    
    cd "$REPO_DIR"
    
    # Clean if requested
    if [ "$CLEAN_BUILD" = true ]; then
        print_status "Cleaning previous build..."
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
    
    print_success "Project rebuilt successfully"
}

# Function to rebuild Docker images
rebuild_docker_images() {
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not installed, skipping image rebuild"
        return
    fi
    
    print_status "Rebuilding Docker images..."
    
    cd "$REPO_DIR"
    
    # Check if Docker buildx is available
    if ! docker buildx version &> /dev/null; then
        print_warning "Docker Buildx not available, skipping multi-arch builds"
        return
    fi
    
    # Use existing multi-arch builder or create one
    if ! docker buildx ls | grep -q "multi-arch"; then
        print_status "Creating multi-arch builder..."
        docker buildx create --name multi-arch --driver docker-container --use
        docker buildx inspect --bootstrap
    else
        docker buildx use multi-arch
    fi
    
    # Build main VPN server image
    print_status "Rebuilding VPN server image..."
    docker buildx build \
        --platform linux/$(uname -m) \
        --file Dockerfile \
        --tag vpn-rust:latest \
        --load \
        . || print_warning "Failed to rebuild VPN server image"
    
    # Build proxy auth service if Dockerfile exists
    if [ -f "docker/proxy/Dockerfile.auth" ]; then
        print_status "Rebuilding proxy auth service image..."
        docker buildx build \
            --platform linux/$(uname -m) \
            --file docker/proxy/Dockerfile.auth \
            --tag vpn-rust-proxy-auth:latest \
            --load \
            . || print_warning "Failed to rebuild proxy auth image"
    fi
    
    # Build identity service if Dockerfile exists
    if [ -f "docker/Dockerfile.identity" ]; then
        print_status "Rebuilding identity service image..."
        docker buildx build \
            --platform linux/$(uname -m) \
            --file docker/Dockerfile.identity \
            --tag vpn-rust-identity:latest \
            --load \
            . || print_warning "Failed to rebuild identity service image"
    fi
    
    print_success "Docker images rebuilt successfully"
}

# Function to reinstall CLI
reinstall_cli() {
    print_status "Reinstalling VPN CLI..."
    
    cd "$REPO_DIR"
    
    # Get old version for comparison
    OLD_VERSION=""
    if command -v vpn &> /dev/null; then
        OLD_VERSION=$(vpn --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
    fi
    
    # Install using cargo
    if [ "$VERBOSE" = true ]; then
        cargo install --path crates/vpn-cli --force
    else
        cargo install --path crates/vpn-cli --force --quiet
    fi
    
    # Verify installation
    if command -v vpn &> /dev/null; then
        NEW_VERSION=$(vpn --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
        if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "unknown" ]; then
            print_success "VPN CLI updated from $OLD_VERSION to $NEW_VERSION"
        else
            print_success "VPN CLI installed successfully (version $NEW_VERSION)"
        fi
    else
        print_error "VPN CLI installation failed"
        exit 1
    fi
}

# Function to run doctor checks
run_doctor() {
    print_status "Running VPN system diagnostics..."
    
    echo
    vpn doctor || {
        print_warning "Some diagnostic checks failed."
        print_warning "This may be normal if VPN services are not installed."
    }
    echo
}

# Function to show completion message
show_completion_message() {
    echo
    echo "========================================"
    echo "      VPN CLI Update Complete!"
    echo "========================================"
    echo
    echo "The VPN CLI tool has been successfully updated."
    echo
    echo "What was updated:"
    echo "  ✓ Repository code"
    echo "  ✓ Project build"
    echo "  ✓ Docker images"
    echo "  ✓ VPN CLI binary"
    echo
    echo "Next steps:"
    echo "  • Use 'vpn menu' for interactive management"
    echo "  • Check 'vpn status' for current server state"
    echo "  • Run 'vpn doctor' for system diagnostics"
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
    echo "VPN CLI Update Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --no-menu          Don't launch the menu after update"
    echo "  --clean            Clean build (cargo clean before building)"
    echo "  --verbose          Enable verbose output"
    echo "  --help             Show this help message"
    echo
    echo "This script will:"
    echo "  1. Update VPN repository from Git"
    echo "  2. Update Rust toolchain if needed"
    echo "  3. Rebuild the project"
    echo "  4. Rebuild Docker images"
    echo "  5. Reinstall VPN CLI"
    echo "  6. Run system diagnostics"
    echo "  7. Launch interactive menu (optional)"
    echo
    echo "Prerequisites:"
    echo "  • VPN repository must exist at $REPO_DIR"
    echo "  • Rust toolchain must be installed"
    echo "  • Run install.sh first if this is a fresh system"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-menu)
            LAUNCH_MENU=false
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
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

# Main update process
main() {
    echo "========================================"
    echo "       VPN CLI Update Script"
    echo "========================================"
    echo
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root"
        print_warning "Run as a regular user (same user that installed VPN CLI)"
        exit 1
    fi
    
    # Pre-update checks
    check_prerequisites
    
    print_status "Repository location: $REPO_DIR"
    echo
    
    # Ensure cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    
    # Update steps
    update_repository
    update_rust
    rebuild_project
    rebuild_docker_images
    reinstall_cli
    
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