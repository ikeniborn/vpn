#!/bin/bash

# Fix script for remote server VPN Manager installation issues
# This script addresses permission errors and sudo command not found issues

set -e

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

# Check if running as user (not root)
if [[ $EUID -eq 0 ]]; then
   error "This script should be run as a regular user, not root!"
   exit 1
fi

log "Fixing VPN Manager installation issues..."

# 1. Fix environment variable for install path
log "Setting up environment variables..."

# Add to user's shell init file
if [[ -f ~/.vpn-init.sh ]]; then
    # Check if VPN_INSTALL_PATH already exists
    if ! grep -q "VPN_INSTALL_PATH" ~/.vpn-init.sh; then
        echo 'export VPN_INSTALL_PATH="$HOME/.local/share/vpn-manager"' >> ~/.vpn-init.sh
        success "Added VPN_INSTALL_PATH to ~/.vpn-init.sh"
    else
        log "VPN_INSTALL_PATH already configured"
    fi
else
    warn "~/.vpn-init.sh not found. Creating it..."
    cat > ~/.vpn-init.sh << 'EOF'
# VPN Manager Shell Integration
export VPN_HOME="$HOME/.vpn"
export VPN_VENV="$HOME/.vpn-venv"
export VPN_INSTALL_PATH="$HOME/.local/share/vpn-manager"

# Auto-activate VPN virtual environment if it exists
if [ -d "$VPN_VENV" ]; then
    export PATH="$VPN_VENV/bin:$PATH"
    export VIRTUAL_ENV="$VPN_VENV"
fi

# VPN Manager aliases
alias vpn-activate='source $VPN_VENV/bin/activate'
alias vpn-update='cd $VPN_HOME && git pull && source $VPN_VENV/bin/activate && pip install -U .'
EOF
    success "Created ~/.vpn-init.sh"
fi

# 2. Create necessary directories with user permissions
log "Creating user directories..."
mkdir -p "$HOME/.local/share/vpn-manager"
mkdir -p "$HOME/.config/vpn-manager"
mkdir -p "$HOME/.local/share/vpn-manager/logs"
success "User directories created"

# 3. Fix sudo command not found issue
log "Creating wrapper script for sudo access..."

# Create a wrapper script that can be called with sudo
sudo mkdir -p /usr/local/bin

# Create wrapper script content
cat > /tmp/vpn-wrapper << 'EOF'
#!/bin/bash
# VPN Manager wrapper script for sudo access

# Source user's vpn environment
if [ -f "$SUDO_USER_HOME/.vpn-init.sh" ]; then
    export HOME="$SUDO_USER_HOME"
    source "$SUDO_USER_HOME/.vpn-init.sh"
elif [ -f "$HOME/.vpn-init.sh" ]; then
    source "$HOME/.vpn-init.sh"
fi

# Set default paths if not set
export VPN_INSTALL_PATH="${VPN_INSTALL_PATH:-$HOME/.local/share/vpn-manager}"
export VPN_CONFIG_PATH="${VPN_CONFIG_PATH:-$HOME/.config/vpn-manager}"
export VPN_DATA_PATH="${VPN_DATA_PATH:-$HOME/.local/share/vpn-manager}"

# Execute vpn command from virtual environment
if [ -f "$HOME/.vpn-venv/bin/vpn" ]; then
    exec "$HOME/.vpn-venv/bin/vpn" "$@"
else
    echo "Error: VPN Manager not found in virtual environment"
    echo "Please run the installation script first: bash scripts/install.sh"
    exit 1
fi
EOF

# Install wrapper script
sudo cp /tmp/vpn-wrapper /usr/local/bin/vpn
sudo chmod 755 /usr/local/bin/vpn
rm /tmp/vpn-wrapper
success "Wrapper script installed to /usr/local/bin/vpn"

# 4. Source the environment for current session
log "Loading environment for current session..."
source ~/.vpn-init.sh

# 5. Test the installation
log "Testing VPN Manager..."

# Test without sudo
if vpn --version &>/dev/null; then
    version=$(vpn --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    success "VPN Manager $version is accessible without sudo"
else
    warn "VPN Manager not accessible without sudo - you may need to reload your shell"
fi

# Test with sudo
if sudo vpn --version &>/dev/null; then
    version=$(sudo vpn --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    success "VPN Manager $version is accessible with sudo"
else
    error "VPN Manager still not accessible with sudo"
fi

echo
echo "========================================"
echo "   VPN Manager Fix Applied!"
echo "========================================"
echo
echo "Next steps:"
echo "1. Reload your shell: source ~/.bashrc"
echo "2. Test the vpn command: vpn --version"
echo "3. Test with sudo: sudo vpn --version"
echo
echo "If you still have issues, check that:"
echo "- Virtual environment exists at ~/.vpn-venv"
echo "- VPN Manager is installed in the virtual environment"
echo "- Run the installation script if needed: bash scripts/install.sh"
echo