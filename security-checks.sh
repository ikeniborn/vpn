#!/bin/bash

# ===================================================================
# VPN Server Security Hardening Script - Security Checks
# ===================================================================
# This script:
# - Performs comprehensive security audits on the system
# - Checks for common misconfigurations
# - Verifies Docker security settings
# - Validates file permissions
# - Generates a security report
# ===================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Display colored text
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Output file for report
REPORT_FILE="/tmp/security-report-$(date +%Y%m%d-%H%M%S).txt"
VERBOSE=false  # Set to true for verbose output

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$REPORT_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$REPORT_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$REPORT_FILE"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    echo "[PASS] $1" >> "$REPORT_FILE"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo "[FAIL] $1" >> "$REPORT_FILE"
}

section() {
    echo -e "\n${BLUE}[SECTION]${NC} $1"
    echo -e "\n-----------------------------------------" >> "$REPORT_FILE"
    echo "[SECTION] $1" >> "$REPORT_FILE"
    echo -e "-----------------------------------------" >> "$REPORT_FILE"
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Check if script is run as root
check_root

# Initialize report file
echo "VPN SERVER SECURITY AUDIT REPORT" > "$REPORT_FILE"
echo "Generated on: $(date)" >> "$REPORT_FILE"
echo "Hostname: $(hostname)" >> "$REPORT_FILE"
echo "=======================================" >> "$REPORT_FILE"

# ===================================================================
# 1. System Information Gathering
# ===================================================================
section "System Information"

info "Gathering system information..."

# OS information
echo "OS Details:" >> "$REPORT_FILE"
lsb_release -a 2>/dev/null >> "$REPORT_FILE" || echo "lsb_release not available" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Kernel information
echo "Kernel Information:" >> "$REPORT_FILE"
uname -a >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check for available updates
echo "Available Updates:" >> "$REPORT_FILE"
apt-get update -qq > /dev/null
apt-get --just-print upgrade | grep -c "Inst " >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check uptime
echo "System Uptime:" >> "$REPORT_FILE"
uptime >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# ===================================================================
# 2. User and Authentication Checks
# ===================================================================
section "User and Authentication Security"

# Check for users with empty passwords
info "Checking for users with empty passwords..."
EMPTY_PASS=$(grep -E "^[^:]+::.*:.*:.*:.*:" /etc/shadow | cut -d: -f1)
if [ -n "$EMPTY_PASS" ]; then
    fail "Users with empty passwords: $EMPTY_PASS"
else
    success "No users with empty passwords found"
fi

# Check for users with UID 0 (besides root)
info "Checking for users with UID 0..."
UID0_USERS=$(awk -F: '($3 == 0 && $1 != "root") {print $1}' /etc/passwd)
if [ -n "$UID0_USERS" ]; then
    fail "Users with UID 0 besides root: $UID0_USERS"
else
    success "No unauthorized users with UID 0"
fi

# Check SSH configuration
info "Checking SSH configuration..."
if [ -f /etc/ssh/sshd_config ]; then
    # Check SSH PermitRootLogin
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        fail "SSH allows root login directly"
    else
        success "SSH root login is properly restricted"
    fi

    # Check SSH PasswordAuthentication
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
        warn "SSH allows password authentication, consider using key-based authentication only"
    else
        success "SSH password authentication is disabled"
    fi

    # Check SSH Protocol version
    if grep -q "^Protocol 1" /etc/ssh/sshd_config; then
        fail "SSH is using the insecure Protocol version 1"
    else
        success "SSH is using Protocol version 2"
    fi
else
    warn "SSH server configuration file not found"
fi

# ===================================================================
# 3. Firewall and Network Security Checks
# ===================================================================
section "Firewall and Network Security"

# Check if firewall is enabled
info "Checking firewall status..."
if command -v ufw >/dev/null; then
    if ufw status | grep -q "Status: active"; then
        success "UFW firewall is active"
        echo "UFW Rules:" >> "$REPORT_FILE"
        ufw status >> "$REPORT_FILE"
    else
        fail "UFW firewall is installed but not active"
    fi
elif command -v iptables >/dev/null; then
    IPTABLES_RULES=$(iptables -L -n | grep -v "Chain" | grep -v "target" | grep -c .)
    if [ "$IPTABLES_RULES" -gt 0 ]; then
        success "iptables has $IPTABLES_RULES rules configured"
    else
        fail "No active iptables rules found"
    fi
else
    fail "No firewall (UFW or iptables) found"
fi

# Check for listening ports
info "Checking for open network ports..."
echo "Open Ports:" >> "$REPORT_FILE"
if command -v ss >/dev/null; then
    ss -tuln >> "$REPORT_FILE"
elif command -v netstat >/dev/null; then
    netstat -tuln >> "$REPORT_FILE"
else
    echo "Neither ss nor netstat commands available" >> "$REPORT_FILE"
fi
echo "" >> "$REPORT_FILE"

# Check for unnecessary services
info "Checking for running services..."
echo "Running Services:" >> "$REPORT_FILE"
systemctl list-units --type=service --state=running | grep ".service" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# ===================================================================
# 4. File System Security Checks
# ===================================================================
section "File System Security"

# Check world-writable files
info "Checking for world-writable files..."
WW_FILES=$(find / -path /proc -prune -o -path /sys -prune -o -type f -perm -0002 -print 2>/dev/null | wc -l)
if [ "$WW_FILES" -gt 0 ]; then
    warn "Found $WW_FILES world-writable files"
    if [ "$VERBOSE" = true ]; then
        echo "World-writable files:" >> "$REPORT_FILE"
        find / -path /proc -prune -o -path /sys -prune -o -type f -perm -0002 -print 2>/dev/null | head -n 20 >> "$REPORT_FILE"
        echo "(showing first 20 results)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
else
    success "No world-writable files found"
fi

# Check world-writable directories
info "Checking for world-writable directories without sticky bit..."
WW_DIRS=$(find / -path /proc -prune -o -path /sys -prune -o -type d -perm -0002 ! -perm -1000 -print 2>/dev/null | wc -l)
if [ "$WW_DIRS" -gt 0 ]; then
    warn "Found $WW_DIRS world-writable directories without sticky bit"
    if [ "$VERBOSE" = true ]; then
        echo "World-writable directories without sticky bit:" >> "$REPORT_FILE"
        find / -path /proc -prune -o -path /sys -prune -o -type d -perm -0002 ! -perm -1000 -print 2>/dev/null | head -n 20 >> "$REPORT_FILE"
        echo "(showing first 20 results)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
else
    success "No world-writable directories without sticky bit found"
fi

# Check SUID/SGID files
info "Checking for SUID/SGID files..."
SUID_FILES=$(find / -path /proc -prune -o -path /sys -prune -o \( -perm -4000 -o -perm -2000 \) -print 2>/dev/null | wc -l)
echo "Found $SUID_FILES SUID/SGID files (some may be legitimate)" >> "$REPORT_FILE"
if [ "$VERBOSE" = true ]; then
    echo "SUID/SGID files:" >> "$REPORT_FILE"
    find / -path /proc -prune -o -path /sys -prune -o \( -perm -4000 -o -perm -2000 \) -print 2>/dev/null >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ===================================================================
# 5. Docker Security Checks
# ===================================================================
section "Docker Security"

# Check if Docker is installed
info "Checking Docker installation and configuration..."
if command -v docker >/dev/null; then
    success "Docker is installed: $(docker --version)"
    
    # Check Docker service status
    if systemctl is-active --quiet docker; then
        success "Docker service is running"
    else
        fail "Docker service is not running"
    fi
    
    # Check Docker configuration
    if [ -f /etc/docker/daemon.json ]; then
        echo "Docker daemon configuration:" >> "$REPORT_FILE"
        cat /etc/docker/daemon.json >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Check for security-related settings
        if grep -q "\"userns-remap\"" /etc/docker/daemon.json; then
            success "Docker uses user namespace remapping"
        else
            warn "Docker is not using user namespace remapping"
        fi
        
        if grep -q "\"no-new-privileges\"" /etc/docker/daemon.json; then
            success "Docker has no-new-privileges enabled"
        else
            warn "Docker does not have no-new-privileges globally enabled"
        fi
        
        if grep -q "\"icc\": false" /etc/docker/daemon.json; then
            success "Docker inter-container communication is disabled"
        else
            warn "Docker inter-container communication is enabled"
        fi
    else
        warn "Docker daemon configuration file not found"
    fi
    
    # Check running containers
    info "Checking running Docker containers..."
    RUNNING_CONTAINERS=$(docker ps -q | wc -l)
    echo "Number of running containers: $RUNNING_CONTAINERS" >> "$REPORT_FILE"
    
    if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
        echo "Running containers:" >> "$REPORT_FILE"
        docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Check container security options
        info "Checking container security configurations..."
        PRIVILEGED_CONTAINERS=$(docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}} {{.HostConfig.Privileged}}' {} | grep "true" | wc -l)
        if [ "$PRIVILEGED_CONTAINERS" -gt 0 ]; then
            fail "Found $PRIVILEGED_CONTAINERS privileged containers"
            docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}} {{.HostConfig.Privileged}}' {} | grep "true" >> "$REPORT_FILE"
        else
            success "No privileged containers found"
        fi
        
        # Check containers with host network
        HOST_NETWORK_CONTAINERS=$(docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}} {{.HostConfig.NetworkMode}}' {} | grep "host" | wc -l)
        if [ "$HOST_NETWORK_CONTAINERS" -gt 0 ]; then
            warn "Found $HOST_NETWORK_CONTAINERS containers using host network"
            docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}} {{.HostConfig.NetworkMode}}' {} | grep "host" >> "$REPORT_FILE"
        else
            success "No containers using host network found"
        fi
    fi
    
    # Check unused images (potential security risk)
    UNUSED_IMAGES=$(docker images -f "dangling=true" -q | wc -l)
    if [ "$UNUSED_IMAGES" -gt 0 ]; then
        warn "Found $UNUSED_IMAGES unused (dangling) images"
    else
        success "No unused images found"
    fi
    
else
    warn "Docker is not installed"
fi

# ===================================================================
# 6. System Configuration Checks
# ===================================================================
section "System Configuration Security"

# Check password policies
info "Checking password policies..."
if [ -f /etc/pam.d/common-password ]; then
    if grep -q "pam_pwquality.so" /etc/pam.d/common-password || grep -q "pam_cracklib.so" /etc/pam.d/common-password; then
        success "Password quality checks are enabled"
    else
        warn "No password quality checks found"
    fi
else
    warn "PAM password configuration not found"
fi

# Check account lockout policies
if [ -f /etc/pam.d/common-auth ]; then
    if grep -q "pam_tally2.so" /etc/pam.d/common-auth || grep -q "pam_faillock.so" /etc/pam.d/common-auth; then
        success "Account lockout policies are configured"
    else
        warn "No account lockout policies found"
    fi
else
    warn "PAM auth configuration not found"
fi

# Check if core dumps are disabled
if sysctl -n fs.suid_dumpable | grep -q "0"; then
    success "Core dumps are properly restricted"
else
    warn "Core dumps may not be properly restricted"
fi

# Check for automatic security updates
info "Checking automatic updates configuration..."
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    if grep -q "APT::Periodic::Update-Package-Lists \"1\"" /etc/apt/apt.conf.d/20auto-upgrades &&
       grep -q "APT::Periodic::Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades; then
        success "Automatic security updates are enabled"
    else
        warn "Automatic security updates may not be properly configured"
    fi
else
    warn "Automatic updates configuration not found"
fi

# Check if AppArmor is enabled
info "Checking AppArmor status..."
if command -v apparmor_status >/dev/null; then
    if apparmor_status | grep -q "apparmor module is loaded"; then
        success "AppArmor is enabled"
        
        # Get number of enforced profiles
        ENFORCED_PROFILES=$(apparmor_status | grep -o "[0-9]* profiles are in enforce mode" | awk '{print $1}')
        echo "AppArmor has $ENFORCED_PROFILES profiles in enforce mode" >> "$REPORT_FILE"
    else
        warn "AppArmor is not enabled"
    fi
else
    warn "AppArmor is not installed"
fi

# Check if audit daemon is running
info "Checking audit daemon status..."
if systemctl is-active --quiet auditd; then
    success "Audit daemon (auditd) is running"
else
    warn "Audit daemon (auditd) is not running"
fi

# ===================================================================
# 7. VPN-specific Security Checks
# ===================================================================
section "VPN Security Checks"

# Check IP forwarding (required for VPN)
info "Checking IP forwarding for VPN..."
if sysctl -n net.ipv4.ip_forward | grep -q "1"; then
    success "IP forwarding is enabled (required for VPN)"
else
    fail "IP forwarding is not enabled, VPN will not work properly"
fi

# Check UFW forward policy
if grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
    success "UFW is configured to allow forwarded packets"
else
    fail "UFW may block forwarded packets, VPN will not work properly"
fi

# Check Docker volume directories
info "Checking Docker volume directories..."
VOLUME_BASE_DIR="/opt/vpn"
if [ -d "$VOLUME_BASE_DIR" ]; then
    success "VPN volume base directory exists"
    
    # Check directory permissions
    INSECURE_DIRS=$(find "$VOLUME_BASE_DIR" -type d -perm -o=w | wc -l)
    if [ "$INSECURE_DIRS" -gt 0 ]; then
        fail "Found $INSECURE_DIRS world-writable directories in VPN data"
    else
        success "VPN data directories have secure permissions"
    fi
else
    warn "VPN volume base directory not found at $VOLUME_BASE_DIR"
fi

# ===================================================================
# 8. Generate Final Report
# ===================================================================
section "Security Recommendations"

# Add recommendations based on findings
echo "Based on the security audit, here are recommended actions:" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ "$WW_FILES" -gt 0 ] || [ "$WW_DIRS" -gt 0 ]; then
    echo "1. Fix world-writable files and directories" >> "$REPORT_FILE"
    echo "   - Run: find / -type f -perm -0002 -exec chmod o-w {} \;" >> "$REPORT_FILE"
    echo "   - Run: find / -type d -perm -0002 ! -perm -1000 -exec chmod o-w {} \;" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

if ! grep -q "userns-remap" /etc/docker/daemon.json 2>/dev/null; then
    echo "2. Enable user namespace remapping in Docker" >> "$REPORT_FILE"
    echo "   - Edit /etc/docker/daemon.json to add: \"userns-remap\": \"default\"" >> "$REPORT_FILE"
    echo "   - Restart Docker: systemctl restart docker" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Display final summary
echo "============================================================"
info "Security check completed. Report saved to: $REPORT_FILE"
echo "============================================================"
echo "Security check summary:"
echo "  - System information gathered"
echo "  - User and authentication settings checked"
echo "  - Firewall and network security analyzed"
echo "  - File system permissions verified"
echo "  - Docker security configuration checked"
echo "  - System security settings evaluated"
echo "  - VPN-specific security checks performed"
echo ""
echo "Review the report at $REPORT_FILE for detailed information and recommendations."
echo "============================================================"

# Open the report file with less if running in interactive terminal
if [ -t 1 ]; then
    less "$REPORT_FILE"
fi

exit 0