#!/bin/bash

# ===================================================================
# Setup Tunnel Routing Rules
# ===================================================================
# This script:
# - Creates the necessary iptables rules for the VLESS tunnel
# - Sets up transparent routing for Outline VPN traffic
# - Ensures proper routing between Server 2 and Server 1
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Setup v2ray iptables rules
setup_v2ray_chain() {
    info "Setting up V2RAY iptables chain..."
    
    # Create V2RAY chain if it doesn't exist
    if ! iptables -t nat -L V2RAY &>/dev/null; then
        info "Creating V2RAY chain..."
        iptables -t nat -N V2RAY
    else
        info "V2RAY chain already exists, flushing it..."
        iptables -t nat -F V2RAY
    fi
    
    # Add rules to V2RAY chain for transparent proxy
    info "Adding rules to V2RAY chain..."
    iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-port 11081
    
    # Add rule for Outline VPN subnet
    info "Adding rule for Outline VPN subnet..."
    iptables -t nat -A PREROUTING -p tcp -s 10.0.0.0/24 -j V2RAY
    
    # Check if V2RAY chain is referenced in PREROUTING
    if ! iptables -t nat -L PREROUTING | grep -q V2RAY; then
        info "Adding V2RAY chain to PREROUTING..."
        iptables -t nat -A PREROUTING -p tcp -j V2RAY
    fi
    
    # Add MASQUERADE rule to POSTROUTING
    if ! iptables -t nat -L POSTROUTING | grep -q MASQUERADE; then
        info "Adding MASQUERADE rule to POSTROUTING..."
        # Get the correct outgoing interface
        local outgoing_iface=$(ip -4 route show default | awk '{print $5}' | head -n1)
        iptables -t nat -A POSTROUTING -j MASQUERADE -o "$outgoing_iface"
    fi
    
    info "iptables rules setup completed successfully."
}

# Main function
main() {
    check_root
    setup_v2ray_chain
    
    # Save iptables rules
    info "Saving iptables rules..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    # Install save/restore mechanism for persistence
    if [ -d "/etc/network/if-pre-up.d" ]; then
        info "Setting up iptables persistence via if-pre-up.d..."
        echo '#!/bin/sh' > /etc/network/if-pre-up.d/iptablesload
        echo 'iptables-restore < /etc/iptables/rules.v4' >> /etc/network/if-pre-up.d/iptablesload
        chmod +x /etc/network/if-pre-up.d/iptablesload
    fi
    
    # Create a routing configuration
    info "Creating tunnel routing configuration..."
    cat > /opt/v2ray/tunnel-routing.conf <<EOF
# Tunnel Routing Configuration
ROUTE_OUTLINE_THROUGH_TUNNEL=true
EOF
    
    info "Copying script to system location..."
    cp "$0" /usr/local/bin/setup-tunnel-routing.sh
    chmod +x /usr/local/bin/setup-tunnel-routing.sh
    
    info "====================================================================="
    info "Tunnel routing setup complete!"
    info "====================================================================="
}

main "$@"