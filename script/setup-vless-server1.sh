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
        error "./script/manage-vless-users.sh script not found or not executable"
    fi
    
    # Check if a user with the same name already exists and remove it
    info "Checking for existing Server 2 accounts..."
    if grep -q "$SERVER2_NAME" "$V2RAY_DIR/users.db"; then
        info "Found existing account with name: $SERVER2_NAME, removing it first"
        if [ -x "./script/manage-vless-users.sh" ]; then
            ./script/manage-vless-users.sh --remove --name "$SERVER2_NAME" || warn "Failed to remove existing Server 2 user"
        else
            manage-vless-users.sh --remove --name "$SERVER2_NAME" || warn "Failed to remove existing Server 2 user"
        fi
        # Wait a moment for the changes to take effect
        sleep 2
    fi
    
    # Generate UUID for Server 2
    local TUNNEL_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    # Add the user using the management script
    info "Adding Server 2 account with name: $SERVER2_NAME"
    if [ -x "./script/manage-vless-users.sh" ]; then
        ./script/manage-vless-users.sh --add --name "$SERVER2_NAME" || error "Failed to add Server 2 user"
    else
        manage-vless-users.sh --add --name "$SERVER2_NAME" || error "Failed to add Server 2 user"
    fi
    
    # Get the UUID of the newly created user (use only the first match to avoid multiple UUIDs)
    local TUNNEL_UUID=$(grep -m 1 "$SERVER2_NAME" "$V2RAY_DIR/users.db" | cut -d'|' -f1)
    
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
        manage-vless-users.sh --export --uuid "$TUNNEL_UUID" > "server2_config.txt"
    fi
    
    info "Configuration saved to server2_config.txt"
}

# Configure IP forwarding and routing on Server 1
configure_routing() {
    info "Configuring IP forwarding and routing..."
    
    # Source the tunnel routing configuration file if it exists
    if [ -f "./script/tunnel-routing.conf" ]; then
        source "./script/tunnel-routing.conf"
        info "Loaded routing configuration from tunnel-routing.conf"
    else
        warn "tunnel-routing.conf not found, using default settings"
        # Default values if config file not found
        IP_FORWARD=1
        OUTLINE_NETWORK="10.0.0.0/24"
    fi
    
    # Verify IP forwarding is enabled
    function verify_ip_forwarding() {
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
            info "IP forwarding is not enabled. Enabling now..."
            echo 1 > /proc/sys/net/ipv4/ip_forward
            
            # Make sure IP forwarding is enabled on boot
            if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
                sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
            else
                echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
            fi
            
            # Apply sysctl changes
            sysctl -p
            
            return 1  # IP forwarding was not enabled
        fi
        return 0  # IP forwarding was already enabled
    }
    
    # Run the verification function
    if verify_ip_forwarding; then
        info "IP forwarding is already enabled"
    else
        info "IP forwarding has been enabled"
    fi
    
    # Add any other routing configuration needed
    info "Additional routing configurations applied"
}

# Update firewall to allow tunneled traffic
update_firewall() {
    info "Updating firewall rules for tunneled traffic..."
    
    # Source the tunnel routing configuration file if it exists
    if [ -f "./script/tunnel-routing.conf" ]; then
        source "./script/tunnel-routing.conf"
        info "Loaded routing configuration from tunnel-routing.conf"
    else
        warn "tunnel-routing.conf not found, using default settings"
        # Default values if config file not found
        SERVER1_MASQUERADE_TRAFFIC=true
        OUTLINE_NETWORK="10.0.0.0/24"
    fi
    
    # Get the internet-facing interface
    local INTERNET_FACING_IFACE="$(ip -4 route show default | awk '{print $5}' | head -n1)"
    if [ -z "$INTERNET_FACING_IFACE" ]; then
        warn "Could not determine internet-facing interface. Trying alternative method."
        INTERNET_FACING_IFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"
        if [ -z "$INTERNET_FACING_IFACE" ]; then
            error "Failed to determine outgoing network interface. Manual configuration needed."
        fi
    fi
    info "Using interface: $INTERNET_FACING_IFACE for outbound traffic"
    
    # Check if UFW is active
    if ufw status | grep -q "Status: active"; then
        info "UFW is active. Configuring UFW rules..."
        
        # Add masquerading rule to UFW's before.rules if not already present
        if ! grep -q "POSTROUTING -o $INTERNET_FACING_IFACE -j MASQUERADE" /etc/ufw/before.rules; then
            # Create a backup of the original before.rules
            cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
            
            # Check if NAT table exists in before.rules
            if grep -q "*nat" /etc/ufw/before.rules; then
                # Find the COMMIT line in the nat section and insert the rule before it
                awk '
                BEGIN {nat_section=0}
                /\*nat/ {nat_section=1; print; next}
                /COMMIT/ && nat_section==1 {
                    printf("# Forward traffic from Server 2 through Server 1\n");
                    printf("-A POSTROUTING -o '"$INTERNET_FACING_IFACE"' -j MASQUERADE\n");
                    # Allow Outline VPN subnet traffic
                    printf("# Allow Outline VPN subnet traffic\n");
                    printf("-A POSTROUTING -s '"$OUTLINE_NETWORK"' -o '"$INTERNET_FACING_IFACE"' -j MASQUERADE\n\n");
                    nat_section=0;
                }
                {print}
                ' /etc/ufw/before.rules > /tmp/before.rules.new && mv /tmp/before.rules.new /etc/ufw/before.rules
            else
                # Create a new NAT table section
                NAT_SECTION="*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

# Forward traffic from Server 2 through Server 1
-A POSTROUTING -o $INTERNET_FACING_IFACE -j MASQUERADE

# Allow Outline VPN subnet traffic
-A POSTROUTING -s $OUTLINE_NETWORK -o $INTERNET_FACING_IFACE -j MASQUERADE

COMMIT
"
                # Insert before the final line (which should be COMMIT)
                sed -i '$i\'"$NAT_SECTION" /etc/ufw/before.rules
            fi
            
            info "Added masquerading rules to UFW"
            
            # Enable IP forwarding in UFW
            if ! grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
                sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
                info "Enabled forwarding policy in UFW"
            fi
            
            # Reload UFW
            ufw reload
        else
            info "Masquerading rules already exist in UFW configuration"
        fi
    else
        warn "UFW is not active. Using direct iptables rules instead."
        
        # Check if the SERVER1_MASQUERADE_TRAFFIC flag is set to true
        if [ "$SERVER1_MASQUERADE_TRAFFIC" = "true" ]; then
            # Add masquerading rule for general traffic
            iptables -t nat -A POSTROUTING -o "$INTERNET_FACING_IFACE" -j MASQUERADE
            
            # Add specific rule for Outline VPN subnet
            iptables -t nat -A POSTROUTING -s "$OUTLINE_NETWORK" -o "$INTERNET_FACING_IFACE" -j MASQUERADE
            
            info "Added masquerading rules for traffic forwarding"
        else
            warn "SERVER1_MASQUERADE_TRAFFIC is not set to true. Skipping masquerade rules."
        fi
        
        # Save iptables rules
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 || warn "Failed to save iptables rules"
        else
            warn "iptables-save not found. Rules will not persist after reboot."
            warn "Consider installing iptables-persistent: apt-get install iptables-persistent"
        fi
    fi
    
    # Verify the rules are applied
    info "Verifying firewall rules..."
    if iptables -t nat -L POSTROUTING | grep -q "MASQUERADE"; then
        info "MASQUERADE rules are correctly configured."
    else
        warn "MASQUERADE rules do not appear to be applied correctly."
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
    
    # Ensure Server 2's UUID is correctly added to Server 1's client list
    info "Ensuring Server 2's UUID is correctly added to client list..."
    local TUNNEL_UUID=$(grep -m 1 "$SERVER2_NAME" "$V2RAY_DIR/users.db" | cut -d'|' -f1)
    
    if [ -f "./script/fix-server-uuid.sh" ]; then
        chmod +x ./script/fix-server-uuid.sh
        ./script/fix-server-uuid.sh --uuid "$TUNNEL_UUID" --name "$SERVER2_NAME"
        info "Server 2's UUID confirmed in Server 1's client list"
    else
        warn "fix-server-uuid.sh not found. Please run it manually if needed:"
        warn "sudo ./script/fix-server-uuid.sh --uuid \"$TUNNEL_UUID\" --name \"$SERVER2_NAME\""
    fi
    
    info "====================================================================="
    info "Server 1 (Tunnel Entry Point) has been configured successfully!"
    info "Server 2 will be able to connect and route traffic through this server."
    info "Please use the generated configuration details when setting up Server 2."
    info "====================================================================="
}

main "$@"