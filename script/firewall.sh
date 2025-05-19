#!/bin/bash

# ===================================================================
# Outline VPN with v2ray VLESS - Firewall Configuration
# ===================================================================
# This script:
# - Configures UFW with secure defaults
# - Sets up port knocking for SSH (optional)
# - Opens required ports for v2ray VLESS and Outline VPN
# - Configures IP forwarding for VPN traffic
# - Prevents common network attacks
# - Ensures Docker compatibility
# ===================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Display colored text
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
V2RAY_PORT="443"
ENABLE_PORT_KNOCKING="yes"
CONFIGURE_SSH="yes"
INTERNET_FACING_IFACE="$(ip -4 route show default | awk '{print $5}' | head -n1)"

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

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --v2ray-port)
                V2RAY_PORT="$2"
                shift
                ;;
            --disable-port-knocking)
                ENABLE_PORT_KNOCKING="no"
                ;;
            --disable-ssh-config)
                CONFIGURE_SSH="no"
                ;;
            --iface)
                INTERNET_FACING_IFACE="$2"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --v2ray-port PORT       Set v2ray port (default: 443)"
                echo "  --disable-port-knocking Disable port knocking for SSH"
                echo "  --disable-ssh-config    Don't configure SSH in firewall"
                echo "  --iface INTERFACE       Specify internet-facing interface"
                echo "  --help                  Show this help message"
                exit 0
                ;;
            *)
                warn "Unknown parameter: $1"
                ;;
        esac
        shift
    done

    if [ -z "$INTERNET_FACING_IFACE" ]; then
        error "Could not determine internet-facing interface. Please specify with --iface."
    fi
    
    info "Using interface: $INTERNET_FACING_IFACE"
    info "v2ray port: $V2RAY_PORT"
}

# Check if script is run as root
check_root
parse_args "$@"

# ===================================================================
# 1. Reset and Configure UFW Defaults
# ===================================================================
info "Configuring UFW (Uncomplicated Firewall)..."

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    info "UFW not found. Installing UFW..."
    apt-get update || error "Failed to update package lists"
    DEBIAN_FRONTEND=noninteractive apt-get install -y ufw || error "Failed to install UFW"
fi

# Reset UFW to default state
info "Resetting UFW to default state..."
ufw --force reset

# Set default policies
info "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

# ===================================================================
# 2. Configure IP Forwarding (Required for VPN)
# ===================================================================
info "Configuring IP forwarding for VPN traffic..."

# Enable IP forwarding in sysctl
if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
    sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# Apply sysctl changes
sysctl -p

# Configure UFW to allow forwarded packets
info "Configuring UFW to allow forwarded packets..."
if ! grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

# ===================================================================
# 3. Configure Port Knocking for SSH (Optional)
# ===================================================================
if [ "$ENABLE_PORT_KNOCKING" = "yes" ]; then
    info "Setting up port knocking for SSH..."

    # Check if knockd is installed
    if ! command -v knockd &> /dev/null; then
        info "knockd not found. Installing knockd..."
        apt-get update || error "Failed to update package lists"
        DEBIAN_FRONTEND=noninteractive apt-get install -y knockd || error "Failed to install knockd"
    else
        info "knockd is already installed"
    fi

    # Configure knockd
    cat > /etc/knockd.conf << EOF
[options]
    logfile = /var/log/knockd.log

[openSSH]
    sequence    = 7000,8000,9000
    seq_timeout = 15
    command     = ufw allow from %IP% to any port 22
    tcpflags    = syn
    cmd_timeout = 30

[closeSSH]
    sequence    = 9000,8000,7000
    seq_timeout = 15
    command     = ufw delete allow from %IP% to any port 22
    tcpflags    = syn
    cmd_timeout = 30
EOF

    # Enable knockd service
    systemctl enable knockd
    systemctl start knockd

    info "Port knocking configured. To access SSH: knock server 7000 8000 9000"
    info "To close SSH access: knock server 9000 8000 7000"
else
    info "Port knocking for SSH is disabled"
fi

# ===================================================================
# 4. Configure Basic Rules - Allow Essential Services
# ===================================================================
info "Configuring essential service rules..."

# Allow v2ray VLESS port (both TCP and UDP)
info "Opening v2ray VLESS port: $V2RAY_PORT (TCP/UDP)..."
ufw allow "$V2RAY_PORT"/tcp # v2ray VLESS TCP
ufw allow "$V2RAY_PORT"/udp # v2ray VLESS UDP

# If v2ray port is not 443, optionally allow regular HTTPS too
if [ "$V2RAY_PORT" != "443" ]; then
    info "Opening HTTPS port (443) for regular web traffic..."
    ufw allow 443/tcp # HTTPS
fi

# Optionally open HTTP for redirect to HTTPS
info "Opening HTTP port (80) for Let's Encrypt and redirects..."
ufw allow 80/tcp # HTTP for Let's Encrypt

# Configure SSH access
if [ "$CONFIGURE_SSH" = "yes" ]; then
    if [ "$ENABLE_PORT_KNOCKING" = "no" ]; then
        # If not using port knocking, use rate limiting for SSH
        info "Configuring SSH access with rate limiting..."
        ufw limit 22/tcp # SSH with rate limiting
    else
        # If using port knocking, no need to open SSH port by default
        info "SSH will be controlled via port knocking..."
    fi
else
    info "SSH configuration skipped as requested"
fi

# ===================================================================
# 5. Advanced Firewall Hardening
# ===================================================================
info "Applying advanced firewall rules..."

# Create directory for custom firewall scripts
mkdir -p /etc/ufw/applications.d

# Create a before.rules file to drop invalid packets and prevent common attacks
cat > /etc/ufw/before.rules << EOF
# Don't delete these required lines, otherwise there will be errors
*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-not-local - [0:0]

# Drop all traffic to loopback not coming from loopback interface
-A ufw-before-input -i lo -j ACCEPT
-A ufw-before-input -d 127.0.0.0/8 ! -i lo -j REJECT

# Drop INVALID packets (logs these in loglevel medium and higher)
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

# Allow established connections
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow ping
-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT

# Allow DHCP client to work
-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT

# Block all incoming ICMP traffic except ping
-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT
-A ufw-before-input -p icmp -j DROP

# Block port scanning
-A ufw-before-input -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j ACCEPT
-A ufw-before-input -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j DROP

# Drop bogus TCP packets
-A ufw-before-input -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
-A ufw-before-input -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
-A ufw-before-input -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
-A ufw-before-input -p tcp --tcp-flags FIN,ACK FIN -j DROP
-A ufw-before-input -p tcp --tcp-flags ACK,URG URG -j DROP
-A ufw-before-input -p tcp --tcp-flags ACK,FIN FIN -j DROP
-A ufw-before-input -p tcp --tcp-flags ACK,PSH PSH -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP

# Reject packets with RFC1918 source addresses trying to use public interfaces
-A ufw-before-input -s 10.0.0.0/8 -j DROP
-A ufw-before-input -s 172.16.0.0/12 -j DROP
-A ufw-before-input -s 192.168.0.0/16 -j DROP
-A ufw-before-input -s 169.254.0.0/16 -j DROP

# Allow mDNS for service discovery (comment if not needed)
-A ufw-before-input -p udp -d 224.0.0.251 --dport 5353 -j ACCEPT

# don't delete the 'COMMIT' line or these rules won't be processed
COMMIT

# NAT table rules for VPN forwarding
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic through internet-facing interface
-A POSTROUTING -s 10.0.0.0/8 -o ${INTERNET_FACING_IFACE} -j MASQUERADE
-A POSTROUTING -s 172.16.0.0/12 -o ${INTERNET_FACING_IFACE} -j MASQUERADE
-A POSTROUTING -s 192.168.0.0/16 -o ${INTERNET_FACING_IFACE} -j MASQUERADE

# don't delete the 'COMMIT' line or these rules won't be processed
COMMIT
EOF

# Create an after.rules file with additional logging
cat > /etc/ufw/after.rules << EOF
# Don't delete these required lines, otherwise there will be errors
*filter
:ufw-after-input - [0:0]
:ufw-after-output - [0:0]
:ufw-after-forward - [0:0]

# Log SSH attempts (adjust level as needed)
-A ufw-after-input -p tcp --dport 22 -j LOG --log-prefix "[UFW SSH]: "

# Log dropped packets (adjust level as needed)
-A ufw-after-input -j LOG --log-prefix "[UFW DROPPED]: "

# don't delete the 'COMMIT' line or these rules won't be processed
COMMIT
EOF

# ===================================================================
# 6. Configure Docker Compatibility
# ===================================================================
info "Configuring Docker compatibility rules..."

# Check if Docker is installed
if command -v docker &> /dev/null; then
    # Create Docker application profile
    cat > /etc/ufw/applications.d/docker << EOF
[Docker]
title=Docker container management
description=Docker container management ports
ports=2375/tcp|2376/tcp|2377/tcp|7946/tcp|7946/udp|4789/udp
EOF

    # Allow internal communication between Docker containers
    info "Allowing Docker internal network communication..."
    ufw allow from 172.17.0.0/16 to any # Docker default network
    ufw allow from 172.18.0.0/16 to any # Docker custom networks
    ufw allow from 10.0.0.0/8 to any # Docker custom networks
    
    # Create script to reapply iptables rules after Docker restart
    info "Creating Docker compatibility service..."
    cat > /usr/local/bin/reapply-docker-iptables-rules.sh << EOF
#!/bin/bash
# This script re-applies iptables rules after Docker service restart
iptables -I DOCKER-USER -j ACCEPT
EOF

    chmod +x /usr/local/bin/reapply-docker-iptables-rules.sh

    # Create systemd service to run the script after Docker restarts
    cat > /etc/systemd/system/docker-iptables.service << EOF
[Unit]
Description=Apply custom iptables rules for Docker
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reapply-docker-iptables-rules.sh

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service
    systemctl daemon-reload
    systemctl enable docker-iptables.service
    
    # Ensure outline-network is allowed
    info "Ensuring outline-network connectivity is allowed..."
    ufw allow in on docker0 to any
    ufw allow in on br-+ to any
else
    warn "Docker is not installed. Some firewall rules for Docker compatibility have been skipped."
fi

# ===================================================================
# 7. Enable UFW with Logging
# ===================================================================
info "Enabling UFW with logging..."

# Configure logging
ufw logging medium

# Enable UFW
info "Enabling UFW..."
ufw --force enable

# Check UFW status
ufw status verbose

# This section was merged with section 6 (Docker Compatibility)

# ===================================================================
# 8. Final Status Check
# ===================================================================
echo "============================================================"
info "Firewall configuration completed successfully!"
echo "============================================================"
echo "Configuration summary:"
echo "  - Default policy: DROP for incoming, ACCEPT for outgoing"
echo "  - v2ray VLESS port $V2RAY_PORT opened (TCP/UDP)"
echo "  - HTTP port 80 opened for Let's Encrypt and redirects"
if [ "$CONFIGURE_SSH" = "yes" ]; then
    if [ "$ENABLE_PORT_KNOCKING" = "yes" ]; then
        echo "  - SSH protected with port knocking"
        echo "  - Port knocking sequence: 7000,8000,9000"
    else
        echo "  - SSH protected with rate limiting"
    fi
fi
echo "  - IP forwarding enabled for VPN traffic"
echo "  - Invalid packets and common attacks blocked"
echo "  - Docker compatibility rules applied"
echo ""
if [ "$ENABLE_PORT_KNOCKING" = "yes" ]; then
    echo "Port knocking sequence to open SSH:"
    echo "  - knock SERVER_IP 7000 8000 9000"
    echo ""
    echo "To close SSH access after use:"
    echo "  - knock SERVER_IP 9000 8000 7000"
fi
echo "============================================================"
echo "Current UFW rules:"
ufw status numbered
echo "============================================================"

exit 0