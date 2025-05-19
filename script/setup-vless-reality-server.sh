#!/bin/bash

# ===================================================================
# VLESS-Reality Server Setup Script
# ===================================================================
# This script:
# - Updates system packages
# - Installs dependencies
# - Configures firewall
# - Sets up VLESS-Reality protocol
# - Configures v2ray with proper settings
# - Creates default user
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
HOSTNAME=""
V2RAY_PORT="443"
DEST_SITE="www.microsoft.com:443"
FINGERPRINT="chrome"
USE_PORT_KNOCKING="yes"
SCRIPTS_DIR="$(pwd)"
SETUP_FIREWALL="yes"

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script performs a complete setup of VLESS-Reality on a new server.

Options:
  --hostname HOST       Server hostname or IP (auto-detected if not specified)
  --v2ray-port PORT     Port for v2ray VLESS protocol (default: 443)
  --dest-site SITE      Destination site to mimic (default: www.microsoft.com:443)
  --fingerprint TYPE    TLS fingerprint to simulate (default: chrome)
  --no-port-knocking    Disable port knocking for SSH
  --no-firewall         Skip firewall configuration
  --help                Display this help message

Example:
  $(basename "$0") --v2ray-port 443 --dest-site www.cloudflare.com:443 --fingerprint firefox

EOF
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --hostname)
                HOSTNAME="$2"
                shift
                ;;
            --v2ray-port)
                V2RAY_PORT="$2"
                shift
                ;;
            --dest-site)
                DEST_SITE="$2"
                shift
                ;;
            --fingerprint)
                FINGERPRINT="$2"
                shift
                ;;
            --no-port-knocking)
                USE_PORT_KNOCKING="no"
                ;;
            --no-firewall)
                SETUP_FIREWALL="no"
                ;;
            --help)
                display_usage
                exit 0
                ;;
            *)
                warn "Unknown parameter: $1"
                ;;
        esac
        shift
    done

    info "Configuration:"
    info "- v2ray port: $V2RAY_PORT"
    info "- Destination site: $DEST_SITE"
    info "- TLS fingerprint: $FINGERPRINT"
    info "- Port knocking: $USE_PORT_KNOCKING"
}

# Update system packages
update_system() {
    info "Updating system packages..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget jq ufw socat qrencode net-tools \
        ca-certificates gnupg
}

# Install Docker if not already installed
install_docker() {
    info "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        info "Installing Docker..."
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    else
        info "Docker is already installed: $(docker --version)"
    fi
}

# Configure firewall
configure_firewall() {
    if [ "$SETUP_FIREWALL" = "no" ]; then
        info "Skipping firewall configuration as requested"
        return
    fi

    info "Configuring firewall..."
    
    # Download firewall script if it doesn't exist
    if [ ! -f "${SCRIPTS_DIR}/firewall.sh" ]; then
        info "Downloading firewall script..."
        wget -O "${SCRIPTS_DIR}/firewall.sh" https://raw.githubusercontent.com/username/vpn/main/script/firewall.sh
        chmod +x "${SCRIPTS_DIR}/firewall.sh"
    fi
    
    # Configure arguments
    local FIREWALL_ARGS=()
    FIREWALL_ARGS+=("--v2ray-port" "$V2RAY_PORT")
    
    if [ "$USE_PORT_KNOCKING" = "no" ]; then
        FIREWALL_ARGS+=("--disable-port-knocking")
    fi
    
    # Run firewall script
    info "Running firewall configuration script..."
    "${SCRIPTS_DIR}/firewall.sh" "${FIREWALL_ARGS[@]}"
}

# Install and configure v2ray with VLESS-Reality
install_vless_reality() {
    info "Installing VLESS-Reality..."
    
    # Download installation script if it doesn't exist
    if [ ! -f "${SCRIPTS_DIR}/outline-v2ray-reality-install.sh" ]; then
        info "Downloading installation script..."
        wget -O "${SCRIPTS_DIR}/outline-v2ray-reality-install.sh" https://raw.githubusercontent.com/username/vpn/main/script/outline-v2ray-reality-install.sh
        chmod +x "${SCRIPTS_DIR}/outline-v2ray-reality-install.sh"
    fi
    
    # Configure arguments
    local INSTALL_ARGS=()
    
    if [ -n "$HOSTNAME" ]; then
        INSTALL_ARGS+=("--hostname" "$HOSTNAME")
    fi
    
    INSTALL_ARGS+=("--v2ray-port" "$V2RAY_PORT")
    INSTALL_ARGS+=("--dest-site" "$DEST_SITE")
    INSTALL_ARGS+=("--fingerprint" "$FINGERPRINT")
    
    # Run installation script
    info "Running VLESS-Reality installation script..."
    "${SCRIPTS_DIR}/outline-v2ray-reality-install.sh" "${INSTALL_ARGS[@]}"
}

# Setup user management scripts
setup_user_management() {
    info "Setting up user management scripts..."
    
    # Download user management script
    if [ ! -f "${SCRIPTS_DIR}/manage-vless-users.sh" ]; then
        info "Downloading user management script..."
        wget -O "${SCRIPTS_DIR}/manage-vless-users.sh" https://raw.githubusercontent.com/username/vpn/main/script/manage-vless-users.sh
        chmod +x "${SCRIPTS_DIR}/manage-vless-users.sh"
    fi
    
    # Download client generation script
    if [ ! -f "${SCRIPTS_DIR}/generate-vless-reality-client.sh" ]; then
        info "Downloading client generation script..."
        wget -O "${SCRIPTS_DIR}/generate-vless-reality-client.sh" https://raw.githubusercontent.com/username/vpn/main/script/generate-vless-reality-client.sh
        chmod +x "${SCRIPTS_DIR}/generate-vless-reality-client.sh"
    fi
}

# Download security checks script
setup_security_checks() {
    info "Setting up security checks script..."
    
    if [ ! -f "${SCRIPTS_DIR}/security-checks-reality.sh" ]; then
        info "Downloading security checks script..."
        wget -O "${SCRIPTS_DIR}/security-checks-reality.sh" https://raw.githubusercontent.com/username/vpn/main/script/security-checks-reality.sh
        chmod +x "${SCRIPTS_DIR}/security-checks-reality.sh"
    fi
}

# Run security verification
verify_security() {
    info "Verifying security settings..."
    
    if [ -f "${SCRIPTS_DIR}/security-checks-reality.sh" ]; then
        info "Running security checks..."
        "${SCRIPTS_DIR}/security-checks-reality.sh"
    else
        warn "Security checks script not found. Skipping verification."
    fi
}

# Main function
main() {
    check_root
    parse_args "$@"
    
    # Interactive confirmation
    echo "This script will set up VLESS-Reality with the following settings:"
    echo "- v2ray port: $V2RAY_PORT"
    echo "- Destination site: $DEST_SITE"
    echo "- TLS fingerprint: $FINGERPRINT"
    echo "- Port knocking for SSH: $USE_PORT_KNOCKING"
    echo "- Firewall setup: $SETUP_FIREWALL"
    echo ""
    echo -n "Proceed with installation? [Y/n] "
    read -r RESPONSE
    RESPONSE=$(echo "${RESPONSE}" | tr '[:upper:]' '[:lower:]')
    if [[ ! -z "${RESPONSE}" && "${RESPONSE}" != "y" && "${RESPONSE}" != "yes" ]]; then
        echo "Installation aborted by user"
        exit 0
    fi
    
    update_system
    install_dependencies
    install_docker
    configure_firewall
    install_vless_reality
    setup_user_management
    setup_security_checks
    
    # Verification is optional
    if [ -t 1 ]; then  # Only if running in an interactive terminal
        echo -n "Would you like to run a security verification? [Y/n] "
        read -r RESPONSE
        RESPONSE=$(echo "${RESPONSE}" | tr '[:upper:]' '[:lower:]')
        if [[ -z "${RESPONSE}" || "${RESPONSE}" == "y" || "${RESPONSE}" == "yes" ]]; then
            verify_security
        fi
    fi
    
    info "===================================================================="
    info "VLESS-Reality server setup completed successfully!"
    info "You can now create additional users with:"
    info "  ./manage-vless-users.sh --add --name \"user-name\""
    info "===================================================================="
}

main "$@"