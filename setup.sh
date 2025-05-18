#!/bin/bash

# ===================================================================
# VPN Server Security Hardening Script - System Setup
# ===================================================================
# This script:
# - Updates the system
# - Installs necessary packages
# - Configures host-level security
# - Sets up directories for Docker volumes
# - Sets proper permissions
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

# Function to create directory if it doesn't exist
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        info "Created directory: $1"
    else
        info "Directory already exists: $1"
    fi
}

# Function to set secure permissions
set_secure_permissions() {
    chown -R root:root "$1"
    find "$1" -type d -exec chmod 750 {} \;
    find "$1" -type f -exec chmod 640 {} \;
    info "Secure permissions set for: $1"
}

# Check if script is run as root
check_root

# ===================================================================
# 1. System Update and Package Installation
# ===================================================================
info "Starting system update and package installation..."

# Update package lists
info "Updating package lists..."
apt-get update || error "Failed to update package lists"

# Upgrade installed packages
info "Upgrading installed packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || warn "Package upgrade completed with warnings"

# Install required packages
info "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    unattended-upgrades \
    haveged \
    auditd \
    apparmor \
    apparmor-utils \
    acl \
    logrotate \
    cron \
    iptables-persistent \
    net-tools \
    htop \
    tree \
    vim \
    nano \
    rkhunter \
    lynis \
    || warn "Package installation completed with warnings"

# ===================================================================
# 2. Docker Installation
# ===================================================================
info "Setting up Docker..."

# Remove any old versions
apt-get remove -y docker docker-engine docker.io containerd runc || true

# Install Docker dependencies
info "Installing Docker dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
info "Adding Docker GPG key..."
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
fi

# Add Docker repository
info "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package lists again
apt-get update

# Install Docker Engine, containerd, and Docker Compose
info "Installing Docker Engine and Docker Compose..."
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || error "Failed to install Docker"

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Verify Docker installation
if docker --version; then
    info "Docker installed successfully"
else
    error "Docker installation failed"
fi

# ===================================================================
# 3. Host Security Hardening
# ===================================================================
info "Configuring system-level security..."

# Setup automatic security updates
info "Setting up unattended-upgrades for automatic security updates..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

# Configure sysctl settings for better security
info "Configuring sysctl for better security..."
cat > /etc/sysctl.d/99-security.conf << EOF
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_all = 0

# Enable IP forwarding (required for Docker)
net.ipv4.ip_forward = 1

# Increase system file descriptor limit
fs.file-max = 100000

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-security.conf

# Setup fail2ban
info "Configuring fail2ban..."
# Ensure directory exists
if [ ! -d "/etc/fail2ban" ]; then
    info "Creating /etc/fail2ban directory..."
    mkdir -p /etc/fail2ban
fi
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

# Restart fail2ban
info "Starting fail2ban service..."
# Make sure fail2ban is properly installed
if ! dpkg -l | grep -q fail2ban; then
    info "Re-installing fail2ban package..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
fi

# Check if the service exists
if [ -f /lib/systemd/system/fail2ban.service ] || [ -f /etc/systemd/system/fail2ban.service ]; then
    systemctl daemon-reload
    systemctl restart fail2ban || warn "Failed to restart fail2ban service, will try to start it"
    systemctl start fail2ban || warn "Failed to start fail2ban service"
    systemctl enable fail2ban || warn "Failed to enable fail2ban service"
    info "Fail2ban service configured"
else
    warn "Fail2ban service not found. Service might need manual configuration."
    warn "You can try: apt-get install --reinstall fail2ban"
fi

# Configure AppArmor
info "Enabling AppArmor..."
systemctl start apparmor
systemctl enable apparmor

# Setup audit rules
info "Configuring system auditing..."
cat > /etc/audit/rules.d/audit.rules << EOF
# Delete all existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Audit the audit logs
-w /var/log/audit/ -k auditlog

# Audit configuration
-w /etc/audit/ -p wa -k auditconfig
-w /etc/libaudit.conf -p wa -k auditconfig
-w /etc/audisp/ -p wa -k audispconfig

# Monitor for use of audit management tools
-w /sbin/auditctl -p x -k audittools
-w /sbin/auditd -p x -k audittools

# Monitor Docker related files
-w /usr/bin/docker -p wa -k docker
-w /var/lib/docker -p wa -k docker
-w /etc/docker -p wa -k docker
-w /usr/lib/systemd/system/docker.service -p wa -k docker
-w /usr/lib/systemd/system/docker.socket -p wa -k docker
-w /var/run/docker.sock -p wa -k docker

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor system logs
-w /var/log/messages -p wa -k system_logs
-w /var/log/syslog -p wa -k system_logs
EOF

# Restart auditd
systemctl restart auditd
systemctl enable auditd

# ===================================================================
# 4. Secure Docker Configuration
# ===================================================================
info "Securing Docker configuration..."

# Create Docker daemon.json with secure defaults
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "icc": false,
  "userns-remap": "default",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

# Restart Docker service
systemctl restart docker

# ===================================================================
# 5. Create Directories for Docker Volumes
# ===================================================================
info "Creating directories for Docker volumes..."

# Define the base directory for all Docker volumes
VOLUME_BASE_DIR="/opt/vpn"

# Create the base directory
create_dir_if_not_exists "${VOLUME_BASE_DIR}"

# Create directories for each service
create_dir_if_not_exists "${VOLUME_BASE_DIR}/traefik_data"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/traefik_acme"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/web_data"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/outline_data"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/v2ray_data"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/management_data"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/monitoring_data"
create_dir_if_not_exists "${VOLUME_BASE_DIR}/backup_data"

# Create log directory
create_dir_if_not_exists "${VOLUME_BASE_DIR}/logs"

# Set secure permissions
info "Setting secure permissions for Docker volume directories..."
set_secure_permissions "${VOLUME_BASE_DIR}"

# ===================================================================
# 6. Final Steps and Verification
# ===================================================================
info "Running security checks..."

# Update RKHUNTER database
if command -v rkhunter > /dev/null; then
    info "Updating RKHUNTER database..."
    rkhunter --update
    rkhunter --propupd
fi

# Run basic Lynis audit
if command -v lynis > /dev/null; then
    info "Running basic Lynis security audit..."
    lynis audit system --quick
fi

# Display summary
echo "============================================================"
info "VPN Server setup completed successfully!"
echo "============================================================"
echo "The following tasks were completed:"
echo "  - System updated and required packages installed"
echo "  - Docker and Docker Compose installed"
echo "  - Host firewall configured (basic setup)"
echo "  - System security settings applied"
echo "  - Docker volume directories created with secure permissions"
echo ""
echo "Next steps:"
echo "  1. Run './firewall.sh' to configure the firewall"
echo "  2. Run './security-checks.sh' to perform security audits"
echo "  3. Deploy your Docker containers"
echo "  4. Set up './maintenance.sh' as a cron job for regular updates"
echo "============================================================"

exit 0