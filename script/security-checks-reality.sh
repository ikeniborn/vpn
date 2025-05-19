#!/bin/bash

# ===================================================================
# Outline VPN with v2ray VLESS-Reality - Security Checks
# ===================================================================
# This script:
# - Performs comprehensive security audits on the system
# - Checks for common misconfigurations
# - Verifies Docker security settings
# - Validates Outline VPN and v2ray Reality configurations
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
REPORT_FILE="/tmp/outline-v2ray-reality-security-report-$(date +%Y%m%d-%H%M%S).txt"
VERBOSE=false  # Set to true for verbose output

# Default paths for Outline and v2ray
OUTLINE_DIR="${OUTLINE_DIR:-/opt/outline}"
V2RAY_DIR="${V2RAY_DIR:-/opt/v2ray}"

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
echo "OUTLINE VPN WITH V2RAY VLESS-REALITY SECURITY AUDIT REPORT" > "$REPORT_FILE"
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
# 4. IP Forwarding Checks (Required for VPN)
# ===================================================================
section "IP Forwarding for VPN"

# Check IP forwarding
info "Checking IP forwarding settings..."
if sysctl -n net.ipv4.ip_forward | grep -q "1"; then
    success "IP forwarding is enabled (required for VPN)"
else
    fail "IP forwarding is not enabled, VPN will not work properly"
fi

# Check UFW forward policy
if [ -f /etc/default/ufw ]; then
    if grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
        success "UFW is configured to allow forwarded packets"
    else
        fail "UFW may block forwarded packets, VPN will not work properly"
    fi
else
    warn "UFW default configuration file not found"
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
    
    # Check Docker daemon configuration
    if [ -f /etc/docker/daemon.json ]; then
        echo "Docker daemon configuration:" >> "$REPORT_FILE"
        cat /etc/docker/daemon.json >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
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
    fi
else
    warn "Docker is not installed"
fi

# ===================================================================
# 6. v2ray VLESS-Reality Configuration Checks
# ===================================================================
section "v2ray VLESS-Reality Configuration"

# Check v2ray directory
info "Checking v2ray directories..."
if [ -d "$V2RAY_DIR" ]; then
    success "v2ray directory exists at $V2RAY_DIR"
    
    # Check directory permissions
    V2RAY_PERMS=$(stat -c "%a" "$V2RAY_DIR")
    if [[ "$V2RAY_PERMS" == "770" || "$V2RAY_PERMS" == "700" ]]; then
        success "v2ray directory has secure permissions: $V2RAY_PERMS"
    else
        warn "v2ray directory has potentially insecure permissions: $V2RAY_PERMS (should be 770 or 700)"
    fi
    
    # Check for v2ray config
    if [ -f "$V2RAY_DIR/config.json" ]; then
        success "v2ray configuration file found"
        
        # Check if config file is readable only by owner and group
        CONFIG_PERMS=$(stat -c "%a" "$V2RAY_DIR/config.json")
        if [[ "$CONFIG_PERMS" == "640" || "$CONFIG_PERMS" == "600" || "$CONFIG_PERMS" == "440" || "$CONFIG_PERMS" == "400" ]]; then
            success "v2ray configuration file has secure permissions: $CONFIG_PERMS"
        else
            warn "v2ray configuration file has potentially insecure permissions: $CONFIG_PERMS (should be 600 or 640)"
        fi
        
        # Check if VLESS protocol is being used
        if grep -q "\"protocol\": \"vless\"" "$V2RAY_DIR/config.json"; then
            success "v2ray is correctly configured with VLESS protocol"
        else
            fail "v2ray is not configured with VLESS protocol"
        fi
        
        # Check if Reality is enabled
        if grep -q "\"security\": \"reality\"" "$V2RAY_DIR/config.json"; then
            success "v2ray Reality security is correctly enabled"
            
            # Check Reality parameters
            if grep -q "\"privateKey\"" "$V2RAY_DIR/config.json" && grep -q "\"shortIds\"" "$V2RAY_DIR/config.json"; then
                success "v2ray Reality is correctly configured with keys and shortIds"
            else
                fail "v2ray Reality configuration is incomplete or incorrect"
            fi
            
            # Check destination site configuration
            DEST_SITE=$(grep -o "\"dest\": \"[^\"]*\"" "$V2RAY_DIR/config.json" | cut -d'"' -f4)
            if [ -n "$DEST_SITE" ]; then
                success "Reality is configured to mimic: $DEST_SITE"
            else
                fail "Reality destination site is not properly configured"
            fi
            
            # Check fingerprint configuration
            FINGERPRINT=$(grep -o "\"fingerprint\": \"[^\"]*\"" "$V2RAY_DIR/config.json" | cut -d'"' -f4)
            if [ -n "$FINGERPRINT" ]; then
                success "Reality is using fingerprint: $FINGERPRINT"
            else
                fail "Reality fingerprint is not properly configured"
            fi
        else
            fail "v2ray is not configured with Reality security"
        fi
        
        # Verify network is set to TCP (not WebSocket)
        if grep -q "\"network\": \"tcp\"" "$V2RAY_DIR/config.json"; then
            success "v2ray is correctly configured with TCP transport (required for Reality)"
        else
            fail "v2ray is not configured with TCP transport, which is required for Reality"
        fi
    else
        fail "v2ray configuration file not found"
    fi
    
    # Check for Reality keypair file
    if [ -f "$V2RAY_DIR/reality_keypair.txt" ]; then
        success "Reality keypair file exists"
        
        # Check permissions
        KEYPAIR_PERMS=$(stat -c "%a" "$V2RAY_DIR/reality_keypair.txt")
        if [[ "$KEYPAIR_PERMS" == "600" || "$KEYPAIR_PERMS" == "400" ]]; then
            success "Reality keypair file has secure permissions: $KEYPAIR_PERMS"
        else
            fail "Reality keypair file has insecure permissions: $KEYPAIR_PERMS (should be 600)"
        fi
    else
        warn "Reality keypair file not found"
    fi
    
    # Check for logs directory
    if [ -d "$V2RAY_DIR/logs" ]; then
        success "v2ray logs directory exists"
    else
        warn "v2ray logs directory not found"
    fi
else
    fail "v2ray directory not found at $V2RAY_DIR"
fi

# Check Outline directory
info "Checking Outline VPN directories..."
if [ -d "$OUTLINE_DIR" ]; then
    success "Outline VPN directory exists at $OUTLINE_DIR"
    
    # Check directory permissions
    OUTLINE_PERMS=$(stat -c "%a" "$OUTLINE_DIR")
    if [[ "$OUTLINE_PERMS" == "770" || "$OUTLINE_PERMS" == "700" ]]; then
        success "Outline directory has secure permissions: $OUTLINE_PERMS"
    else
        warn "Outline directory has potentially insecure permissions: $OUTLINE_PERMS (should be 770 or 700)"
    fi
else
    warn "Outline VPN directory not found at $OUTLINE_DIR"
fi

# Check Docker containers
info "Checking Outline and v2ray containers..."
if command -v docker >/dev/null; then
    # Check if outline container is running
    if docker ps --format "{{.Names}}" | grep -q "^shadowbox$"; then
        success "Outline VPN container (shadowbox) is running"
    else
        fail "Outline VPN container (shadowbox) is not running"
    fi
    
    # Check if v2ray container is running
    if docker ps --format "{{.Names}}" | grep -q "^v2ray$"; then
        success "v2ray container is running"
    else
        fail "v2ray container is not running"
    fi
    
    # Check Docker network
    if docker network ls | grep -q "outline-network"; then
        success "Docker outline-network exists"
    else
        warn "Docker outline-network not found"
    fi
else
    fail "Docker is not installed, cannot check containers"
fi

# Check v2ray port
info "Checking if v2ray port is accessible..."
DEFAULT_V2RAY_PORT=443
if [ -f "$V2RAY_DIR/config.json" ]; then
    # Extract actual port from config if possible
    CONFIGURED_PORT=$(grep -o "\"port\": [0-9]*" "$V2RAY_DIR/config.json" | awk '{print $2}')
    if [ -n "$CONFIGURED_PORT" ]; then
        DEFAULT_V2RAY_PORT=$CONFIGURED_PORT
    fi
fi

# Check if port is open
if command -v ss >/dev/null; then
    if ss -tuln | grep -q ":$DEFAULT_V2RAY_PORT "; then
        success "v2ray port $DEFAULT_V2RAY_PORT is open"
    else
        fail "v2ray port $DEFAULT_V2RAY_PORT is not open"
    fi
elif command -v netstat >/dev/null; then
    if netstat -tuln | grep -q ":$DEFAULT_V2RAY_PORT "; then
        success "v2ray port $DEFAULT_V2RAY_PORT is open"
    else
        fail "v2ray port $DEFAULT_V2RAY_PORT is not open"
    fi
else
    warn "Cannot check if v2ray port is open (no ss or netstat found)"
fi

# ===================================================================
# 7. Security Recommendations
# ===================================================================
section "Security Recommendations"

# Add recommendations based on findings
echo "Based on the security audit, here are recommended actions:" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Add v2ray Reality-specific recommendations
if [ -f "$V2RAY_DIR/config.json" ]; then
    if ! grep -q "\"security\": \"reality\"" "$V2RAY_DIR/config.json"; then
        echo "1. Enable Reality protocol for v2ray" >> "$REPORT_FILE"
        echo "   - Edit $V2RAY_DIR/config.json to change security to 'reality'" >> "$REPORT_FILE"
        echo "   - Run the installation script with Reality parameters" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # Check Reality keypair file permissions
    if [ -f "$V2RAY_DIR/reality_keypair.txt" ]; then
        KEYPAIR_PERMS=$(stat -c "%a" "$V2RAY_DIR/reality_keypair.txt")
        if [[ "$KEYPAIR_PERMS" != "600" && "$KEYPAIR_PERMS" != "400" ]]; then
            echo "2. Fix Reality keypair file permissions" >> "$REPORT_FILE"
            echo "   - Run: chmod 600 $V2RAY_DIR/reality_keypair.txt" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    fi
fi

# Check firewall rules for v2ray port
if command -v ufw >/dev/null; then
    if ! ufw status | grep -q "$DEFAULT_V2RAY_PORT/tcp"; then
        echo "3. Ensure firewall allows v2ray port $DEFAULT_V2RAY_PORT" >> "$REPORT_FILE"
        echo "   - Run: ufw allow $DEFAULT_V2RAY_PORT/tcp" >> "$REPORT_FILE"
        echo "   - Run: ufw allow $DEFAULT_V2RAY_PORT/udp" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
fi

# IP forwarding recommendation
if ! sysctl -n net.ipv4.ip_forward | grep -q "1"; then
    echo "4. Enable IP forwarding (required for VPN)" >> "$REPORT_FILE"
    echo "   - Run: echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf" >> "$REPORT_FILE"
    echo "   - Run: sysctl -p" >> "$REPORT_FILE"
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
echo "  - IP forwarding configuration verified"
echo "  - Docker security configuration checked"
echo "  - v2ray VLESS-Reality configuration verified"
echo ""
echo "Review the report at $REPORT_FILE for detailed information and recommendations."
echo "============================================================"

# Open the report file with less if running in interactive terminal
if [ -t 1 ]; then
    less "$REPORT_FILE"
fi

exit 0