#!/bin/bash

# ===================================================================
# VLESS-Reality Server 1 Setup Script (Tunnel Entry Point)
# ===================================================================
# This script:
# - Configures the first server to accept incoming connections from Server 2
# - Creates a special user account with permissions for tunneling
# - Sets up necessary routing for forwarded traffic
# - Works with the existing VLESS+Reality infrastructure
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
HOSTNAME=""
V2RAY_PORT="443"
SERVER2_NAME="server2"
V2RAY_DIR="/opt/v2ray"

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

This script configures the first VLESS-Reality server to accept tunneled connections from Server 2.

Options:
  --hostname HOST       Server hostname or IP (auto-detected if not specified)
  --v2ray-port PORT     Port for v2ray VLESS protocol (default: 443)
  --server2-name NAME   Name for the Server 2 account (default: server2)
  --help                Display this help message

Example:
  $(basename "$0") --v2ray-port 443 --server2-name "tunnel-server"

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
            --server2-name)
                SERVER2_NAME="$2"
                shift
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

    # If hostname not provided, try to detect it
    if [ -z "$HOSTNAME" ]; then
        HOSTNAME=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
        info "Auto-detected server address: $HOSTNAME"
    fi

    info "Configuration:"
    info "- Server 1 address: $HOSTNAME"
    info "- v2ray port: $V2RAY_PORT"
    info "- Server 2 account name: $SERVER2_NAME"
}

# Check if VLESS-Reality is already installed
check_vless_reality() {
    info "Checking for existing VLESS-Reality installation..."
    if [ ! -f "$V2RAY_DIR/config.json" ]; then
        error "VLESS-Reality configuration not found in $V2RAY_DIR. Please run setup-vless-reality-server.sh first."
    else
        info "VLESS-Reality installation found."
    fi
}

# Create a special user account for the second server
create_tunnel_user() {
    info "Creating a special user account for Server 2..."
    
    # Check if manage-vless-users.sh exists and is executable
    if [ ! -x "$(command -v manage-vless-users.sh)" ] && [ ! -x "./script/manage-vless-users.sh" ]; then
        error "manage-vless-users.sh script not found or not executable"
    fi
    
    # Generate UUID for Server 2
    local TUNNEL_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    # Add the user using the management script
    info "Adding Server 2 account with name: $SERVER2_NAME"
    if [ -x "./script/manage-vless-users.sh" ]; then
        ./script/manage-vless-users.sh --add --name "$SERVER2_NAME" || error "Failed to add Server 2 user"
    else
        /script/manage-vless-users.sh --add --name "$SERVER2_NAME" || error "Failed to add Server 2 user"
    fi
    
    # Get the UUID of the newly created user
    local TUNNEL_UUID=$(grep "$SERVER2_NAME" "$V2RAY_DIR/users.db" | cut -d'|' -f1)
    
    if [ -z "$TUNNEL_UUID" ]; then
        error "Failed to retrieve UUID for Server 2 user"
    fi
    
    info "Server 2 account created with UUID: $TUNNEL_UUID"
    
    # Display the configuration for Server 2
    echo ""
    echo "============================================================"
    echo "Server 2 Connection Details (Save these for Server 2 setup):"
    echo "============================================================"
    echo "Server 1 Address: $HOSTNAME"
    echo "Port:            $V2RAY_PORT"
    echo "UUID:            $TUNNEL_UUID"
    echo "Account Name:    $SERVER2_NAME"
    echo "============================================================"
    echo ""
    
    # Export the configuration for easy setup on Server 2
    info "Exporting configuration for Server 2..."
    if [ -x "./script/manage-vless-users.sh" ]; then
        ./script/manage-vless-users.sh --export --uuid "$TUNNEL_UUID" > "server2_config.txt"
    else
        script/manage-vless-users.sh --export --uuid "$TUNNEL_UUID" > "server2_config.txt"
    fi
    
    info "Configuration saved to server2_config.txt"
}

# Configure IP forwarding and routing on Server 1
configure_routing() {
    info "Configuring IP forwarding and routing..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Make sure IP forwarding is enabled on boot
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Apply sysctl changes
    sysctl -p
    
    info "IP forwarding has been enabled"
}

# Update firewall to allow tunneled traffic
update_firewall() {
    info "Updating firewall rules for tunneled traffic..."
    
    # Check if UFW is active
    if ufw status | grep -q "Status: active"; then
        # Get the internet-facing interface
        local INTERNET_FACING_IFACE="$(ip -4 route show default | awk '{print $5}' | head -n1)"
        
        if [ -z "$INTERNET_FACING_IFACE" ]; then
            warn "Could not determine internet-facing interface. Masquerading may not work correctly."
        else
            info "Using interface: $INTERNET_FACING_IFACE for outbound traffic"
        fi
        
        # Add masquerading rule to UFW's before.rules if not already present
        if ! grep -q "POSTROUTING -o $INTERNET_FACING_IFACE -j MASQUERADE" /etc/ufw/before.rules; then
            # Create a backup of the original before.rules
            cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
            
            # Check if NAT table exists in before.rules
            if grep -q "*nat" /etc/ufw/before.rules; then
                # Insert masquerading rule before COMMIT line in *nat section
                sed -i "/*nat/,/COMMIT/ s/COMMIT/# Forward traffic from Server 2 through Server 1\n-A POSTROUTING -o $INTERNET_FACING_IFACE -j MASQUERADE\n\nCOMMIT/" /etc/ufw/before.rules
            else
                # Add NAT table with masquerading rule before the final COMMIT
                sed -i "$ i\\
*nat\\
:PREROUTING ACCEPT [0:0]\\
:POSTROUTING ACCEPT [0:0]\\
\\
# Forward traffic from Server 2 through Server 1\\
-A POSTROUTING -o $INTERNET_FACING_IFACE -j MASQUERADE\\
\\
COMMIT" /etc/ufw/before.rules
            fi
            
            info "Added masquerading rules to UFW"
            
            # Reload UFW
            ufw reload
        else
            info "Masquerading rules already exist in UFW configuration"
        fi
    else
        warn "UFW is not active. Using direct iptables rules instead."
        
        # Get the internet-facing interface
        local INTERNET_FACING_IFACE="$(ip -4 route show default | awk '{print $5}' | head -n1)"
        
        if [ -z "$INTERNET_FACING_IFACE" ]; then
            warn "Could not determine internet-facing interface. Masquerading may not work correctly."
        else
            info "Using interface: $INTERNET_FACING_IFACE for outbound traffic"
        fi
        
        # Add masquerading rule
        iptables -t nat -A POSTROUTING -o "$INTERNET_FACING_IFACE" -j MASQUERADE
        
        # Save iptables rules
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 || warn "Failed to save iptables rules"
        else
            warn "iptables-save not found. Rules will not persist after reboot."
            warn "Consider installing iptables-persistent: apt-get install iptables-persistent"
        fi
    fi
}

# Main function
main() {
    check_root
    parse_args "$@"
    check_vless_reality
    create_tunnel_user
    configure_routing
    update_firewall
    
    info "====================================================================="
    info "Server 1 (Tunnel Entry Point) has been configured successfully!"
    info "Server 2 will be able to connect and route traffic through this server."
    info "Please use the generated configuration details when setting up Server 2."
    info "====================================================================="
}

main "$@"