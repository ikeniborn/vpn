#!/bin/bash

# ===================================================================
# VPN Server Security Hardening Script - Firewall Configuration
# ===================================================================
# This script:
# - Configures UFW with secure defaults
# - Sets up port knocking for SSH
# - Allows only necessary ports (SSH, HTTP, HTTPS)
# - Configures IP forwarding for VPN traffic
# - Drops invalid packets
# - Prevents common network attacks
# ===================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Display colored text
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

# Check if script is run as root
check_root

# ===================================================================
# 1. Reset and Configure UFW Defaults
# ===================================================================
info "Configuring UFW (Uncomplicated Firewall)..."

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
# 3. Configure Port Knocking for SSH
# ===================================================================
info "Setting up port knocking for SSH..."

# Install knockd (port knocking daemon)
apt-get install -y knockd || error "Failed to install knockd"

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

# ===================================================================
# 4. Configure Basic Rules - Allow Essential Services
# ===================================================================
info "Configuring essential service rules..."

# Allow essential services
info "Opening HTTP (80) and HTTPS (443) ports for Traefik..."
ufw allow 80/tcp comment 'HTTP for Traefik'
ufw allow 443/tcp comment 'HTTPS for Traefik'

# Optional: Allow SSH directly if you don't want to use port knocking exclusively
# Warning: Port knocking is safer, but this provides a fallback method
info "Configuring SSH access with rate limiting..."
ufw limit 22/tcp comment 'SSH with rate limiting'

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

# Forward traffic through eth0 (change eth0 to your internet-facing interface)
-A POSTROUTING -s 10.0.0.0/8 -o eth0 -j MASQUERADE
-A POSTROUTING -s 172.16.0.0/12 -o eth0 -j MASQUERADE
-A POSTROUTING -s 192.168.0.0/16 -o eth0 -j MASQUERADE

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

# Configure UFW to allow docker traffic
info "Configuring Docker compatibility rules..."
cat > /etc/ufw/applications.d/docker << EOF
[Docker]
title=Docker container management
description=Docker container management ports
ports=2375/tcp|2376/tcp|2377/tcp|7946/tcp|7946/udp|4789/udp
EOF

# ===================================================================
# 6. Enable UFW with Logging
# ===================================================================
info "Enabling UFW with logging..."

# Configure logging
ufw logging medium

# Enable UFW
info "Enabling UFW..."
ufw --force enable

# Check UFW status
ufw status verbose

# ===================================================================
# 7. Configure iptables for Docker compatibility
# ===================================================================
info "Configuring iptables for Docker compatibility..."

# Add Docker subnet to trusted networks (assuming 172.17.0.0/16 is your Docker subnet)
ufw allow from 172.17.0.0/16 to any
ufw allow from 10.0.0.0/8 to any    # VPN networks from docker-compose
ufw allow from 172.16.0.0/12 to any # Additional Docker networks

# Create script to reapply iptables rules after Docker restart
cat > /usr/local/bin/reapply-iptables-rules.sh << EOF
#!/bin/bash
# This script re-applies iptables rules after Docker service restart
iptables -I DOCKER-USER -j ACCEPT
EOF

chmod +x /usr/local/bin/reapply-iptables-rules.sh

# Create systemd service to run the script after Docker restarts
cat > /etc/systemd/system/docker-iptables.service << EOF
[Unit]
Description=Apply custom iptables rules for Docker
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reapply-iptables-rules.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl daemon-reload
systemctl enable docker-iptables.service

# ===================================================================
# 8. Final Status Check
# ===================================================================
echo "============================================================"
info "Firewall configuration completed successfully!"
echo "============================================================"
echo "Configuration summary:"
echo "  - Default policy: DROP for incoming, ACCEPT for outgoing"
echo "  - Port 80 (HTTP) and 443 (HTTPS) open for Traefik"
echo "  - SSH protected with rate limiting"
echo "  - Port knocking configured for additional SSH protection"
echo "  - IP forwarding enabled for VPN traffic"
echo "  - Invalid packets and common attacks blocked"
echo "  - Docker compatibility rules applied"
echo ""
echo "Port knocking sequence to open SSH:"
echo "  - knock SERVER_IP 7000 8000 9000"
echo ""
echo "To close SSH access after use:"
echo "  - knock SERVER_IP 9000 8000 7000"
echo "============================================================"
echo "Current UFW rules:"
ufw status numbered
echo "============================================================"

exit 0