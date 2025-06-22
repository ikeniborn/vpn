#!/bin/bash

# Security Hardening Module
# Implements advanced security features for VPN server

# Get module directory
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/common.sh" || exit 1
source "$PROJECT_ROOT/lib/config.sh" || exit 1
source "$PROJECT_ROOT/lib/network.sh" || exit 1

# Security configuration
SECURITY_CONFIG="/opt/v2ray/config/security.json"
SECURITY_LOG="/opt/v2ray/logs/security.log"
FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"

# Initialize security module
init_security_hardening() {
    # Create security configuration
    if [ ! -f "$SECURITY_CONFIG" ]; then
        cat > "$SECURITY_CONFIG" << EOF
{
    "enabled": true,
    "features": {
        "fail2ban": false,
        "port_knocking": false,
        "geo_blocking": false,
        "rate_limiting": true,
        "connection_limits": true,
        "intrusion_detection": false
    },
    "settings": {
        "max_connections_per_user": 3,
        "max_connections_per_ip": 5,
        "rate_limit_requests": 100,
        "rate_limit_window": 60,
        "blocked_countries": [],
        "allowed_countries": [],
        "port_knock_sequence": []
    }
}
EOF
        chmod 600 "$SECURITY_CONFIG"
    fi
    
    # Create security log
    touch "$SECURITY_LOG"
    chmod 640 "$SECURITY_LOG"
}

# Enable/disable security features
configure_security_feature() {
    local feature="$1"
    local enabled="$2"
    
    [ -z "$feature" ] || [ -z "$enabled" ] && {
        error "Feature and enabled status required"
        return 1
    }
    
    # Update configuration
    local config=$(cat "$SECURITY_CONFIG")
    config=$(echo "$config" | jq --arg feature "$feature" --arg enabled "$enabled" \
        '.features[$feature] = ($enabled == "true")')
    echo "$config" | jq '.' > "$SECURITY_CONFIG"
    
    # Apply feature-specific configuration
    case "$feature" in
        fail2ban)
            if [ "$enabled" = "true" ]; then
                setup_fail2ban
            else
                disable_fail2ban
            fi
            ;;
        port_knocking)
            if [ "$enabled" = "true" ]; then
                setup_port_knocking
            else
                disable_port_knocking
            fi
            ;;
        geo_blocking)
            if [ "$enabled" = "true" ]; then
                setup_geo_blocking
            else
                disable_geo_blocking
            fi
            ;;
        rate_limiting)
            if [ "$enabled" = "true" ]; then
                setup_rate_limiting
            else
                disable_rate_limiting
            fi
            ;;
        connection_limits)
            if [ "$enabled" = "true" ]; then
                setup_connection_limits
            else
                disable_connection_limits
            fi
            ;;
        intrusion_detection)
            if [ "$enabled" = "true" ]; then
                setup_intrusion_detection
            else
                disable_intrusion_detection
            fi
            ;;
    esac
    
    log_security_event "Feature $feature ${enabled}"
    success "Security feature $feature ${enabled}"
}

# Setup Fail2ban for VPN
setup_fail2ban() {
    info "Setting up Fail2ban for VPN protection..."
    
    # Install fail2ban if not present
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        apt-get update && apt-get install -y fail2ban || {
            error "Failed to install fail2ban"
            return 1
        }
    fi
    
    # Create VPN jail configuration
    cat > /etc/fail2ban/jail.d/xray-vpn.conf << EOF
[xray-auth]
enabled = true
port = $(get_vpn_port)
filter = xray-auth
logpath = /opt/v2ray/logs/access.log
maxretry = 5
findtime = 3600
bantime = 86400
banaction = iptables-multiport

[xray-dos]
enabled = true
port = $(get_vpn_port)
filter = xray-dos
logpath = /opt/v2ray/logs/access.log
maxretry = 100
findtime = 60
bantime = 3600
banaction = iptables-multiport
EOF
    
    # Create filter for authentication failures
    cat > /etc/fail2ban/filter.d/xray-auth.conf << 'EOF'
[Definition]
failregex = .*rejected.*from <HOST>.*
            .*authentication failed.*<HOST>.*
            .*invalid user.*from <HOST>.*
ignoreregex =
EOF
    
    # Create filter for DoS attempts
    cat > /etc/fail2ban/filter.d/xray-dos.conf << 'EOF'
[Definition]
failregex = .*<HOST>.*
ignoreregex = .*accepted.*
EOF
    
    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    success "Fail2ban configured for VPN protection"
}

# Disable Fail2ban
disable_fail2ban() {
    info "Disabling Fail2ban..."
    
    # Remove VPN-specific configurations
    rm -f /etc/fail2ban/jail.d/xray-vpn.conf
    rm -f /etc/fail2ban/filter.d/xray-auth.conf
    rm -f /etc/fail2ban/filter.d/xray-dos.conf
    
    # Reload fail2ban if running
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        systemctl reload fail2ban
    fi
    
    success "Fail2ban disabled for VPN"
}

# Setup port knocking
setup_port_knocking() {
    info "Setting up port knocking..."
    
    # Install knockd if not present
    if ! command -v knockd >/dev/null 2>&1; then
        apt-get update && apt-get install -y knockd || {
            error "Failed to install knockd"
            return 1
        }
    fi
    
    # Generate random knock sequence
    local knock1=$((RANDOM % 10000 + 10000))
    local knock2=$((RANDOM % 10000 + 20000))
    local knock3=$((RANDOM % 10000 + 30000))
    
    # Update security config with knock sequence
    local config=$(cat "$SECURITY_CONFIG")
    config=$(echo "$config" | jq --arg k1 "$knock1" --arg k2 "$knock2" --arg k3 "$knock3" \
        '.settings.port_knock_sequence = [$k1, $k2, $k3]')
    echo "$config" | jq '.' > "$SECURITY_CONFIG"
    
    # Configure knockd
    cat > /etc/knockd.conf << EOF
[options]
    UseSyslog

[openVPN]
    sequence    = $knock1,$knock2,$knock3
    seq_timeout = 5
    command     = /sbin/iptables -A INPUT -s %IP% -p tcp --dport $(get_vpn_port) -j ACCEPT
    tcpflags    = syn

[closeVPN]
    sequence    = $knock3,$knock2,$knock1
    seq_timeout = 5
    command     = /sbin/iptables -D INPUT -s %IP% -p tcp --dport $(get_vpn_port) -j ACCEPT
    tcpflags    = syn
EOF
    
    # Update default settings
    sed -i 's/START_KNOCKD=0/START_KNOCKD=1/' /etc/default/knockd 2>/dev/null
    
    # Close VPN port by default
    iptables -D INPUT -p tcp --dport $(get_vpn_port) -j ACCEPT 2>/dev/null
    
    # Start knockd
    systemctl restart knockd
    systemctl enable knockd
    
    success "Port knocking configured. Sequence: $knock1, $knock2, $knock3"
}

# Disable port knocking
disable_port_knocking() {
    info "Disabling port knocking..."
    
    # Open VPN port
    local vpn_port=$(get_vpn_port)
    iptables -A INPUT -p tcp --dport "$vpn_port" -j ACCEPT 2>/dev/null
    
    # Stop knockd
    systemctl stop knockd
    systemctl disable knockd
    
    # Update config
    sed -i 's/START_KNOCKD=1/START_KNOCKD=0/' /etc/default/knockd 2>/dev/null
    
    success "Port knocking disabled"
}

# Setup geo-blocking
setup_geo_blocking() {
    info "Setting up geo-blocking..."
    
    # Install required packages
    if ! command -v ipset >/dev/null 2>&1; then
        apt-get update && apt-get install -y ipset || {
            error "Failed to install ipset"
            return 1
        }
    fi
    
    # Create ipsets for countries
    ipset create geoblock_allowed hash:net 2>/dev/null || ipset flush geoblock_allowed
    ipset create geoblock_blocked hash:net 2>/dev/null || ipset flush geoblock_blocked
    
    # Load country configuration
    local config=$(cat "$SECURITY_CONFIG")
    local blocked_countries=$(echo "$config" | jq -r '.settings.blocked_countries[]' 2>/dev/null)
    local allowed_countries=$(echo "$config" | jq -r '.settings.allowed_countries[]' 2>/dev/null)
    
    # Download and apply country IP blocks
    for country in $blocked_countries; do
        info "Blocking IPs from $country..."
        wget -q -O - "https://www.ipdeny.com/ipblocks/data/countries/${country,,}.zone" | \
            while read -r ip; do
                ipset add geoblock_blocked "$ip" 2>/dev/null
            done
    done
    
    # Apply iptables rules
    iptables -I INPUT -m set --match-set geoblock_blocked src -j DROP 2>/dev/null
    
    # Save ipset rules
    ipset save > /etc/ipset.rules
    
    success "Geo-blocking configured"
}

# Disable geo-blocking
disable_geo_blocking() {
    info "Disabling geo-blocking..."
    
    # Remove iptables rules
    iptables -D INPUT -m set --match-set geoblock_blocked src -j DROP 2>/dev/null
    iptables -D INPUT -m set --match-set geoblock_allowed dst -j ACCEPT 2>/dev/null
    
    # Destroy ipsets
    ipset destroy geoblock_allowed 2>/dev/null
    ipset destroy geoblock_blocked 2>/dev/null
    
    success "Geo-blocking disabled"
}

# Setup rate limiting
setup_rate_limiting() {
    info "Setting up rate limiting..."
    
    local config=$(cat "$SECURITY_CONFIG")
    local rate_limit=$(echo "$config" | jq -r '.settings.rate_limit_requests // 100')
    local window=$(echo "$config" | jq -r '.settings.rate_limit_window // 60')
    
    # Calculate rate
    local rate=$((rate_limit / window))
    [ "$rate" -lt 1 ] && rate=1
    
    # Apply rate limiting rules
    local vpn_port=$(get_vpn_port)
    
    # Connection rate limiting
    iptables -I INPUT -p tcp --dport "$vpn_port" -m state --state NEW -m recent --set
    iptables -I INPUT -p tcp --dport "$vpn_port" -m state --state NEW -m recent \
        --update --seconds "$window" --hitcount "$rate_limit" -j DROP
    
    # Save rules
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    fi
    
    success "Rate limiting configured: $rate_limit requests per $window seconds"
}

# Disable rate limiting
disable_rate_limiting() {
    info "Disabling rate limiting..."
    
    local vpn_port=$(get_vpn_port)
    
    # Remove rate limiting rules
    while iptables -D INPUT -p tcp --dport "$vpn_port" -m state --state NEW -m recent --set 2>/dev/null; do :; done
    while iptables -D INPUT -p tcp --dport "$vpn_port" -m state --state NEW -m recent \
        --update --seconds 60 --hitcount 100 -j DROP 2>/dev/null; do :; done
    
    success "Rate limiting disabled"
}

# Setup connection limits
setup_connection_limits() {
    info "Setting up connection limits..."
    
    local config=$(cat "$SECURITY_CONFIG")
    local max_per_user=$(echo "$config" | jq -r '.settings.max_connections_per_user // 3')
    local max_per_ip=$(echo "$config" | jq -r '.settings.max_connections_per_ip // 5')
    
    # Apply connection limit rules
    local vpn_port=$(get_vpn_port)
    
    # Limit connections per IP
    iptables -I INPUT -p tcp --dport "$vpn_port" -m connlimit \
        --connlimit-above "$max_per_ip" --connlimit-mask 32 -j REJECT
    
    # Create connection tracking script
    cat > /opt/v2ray/scripts/connection_limits.sh << EOF
#!/bin/bash
# Monitor and enforce per-user connection limits

MAX_PER_USER=$max_per_user

# Check each user's connections
for user_file in /opt/v2ray/users/*.json; do
    [ -f "\$user_file" ] || continue
    username=\$(basename "\$user_file" .json)
    uuid=\$(jq -r '.clients[0].id' "\$user_file" 2>/dev/null)
    
    [ -z "\$uuid" ] && continue
    
    # Count active connections for this user
    conn_count=\$(docker logs xray 2>&1 | grep -c "\$uuid.*accepted" | tail -1000)
    
    if [ "\$conn_count" -gt "\$MAX_PER_USER" ]; then
        echo "\$(date): User \$username exceeded connection limit (\$conn_count > \$MAX_PER_USER)" >> $SECURITY_LOG
        # Could implement connection dropping here
    fi
done
EOF
    chmod +x /opt/v2ray/scripts/connection_limits.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "connection_limits.sh"; 
     echo "*/5 * * * * /opt/v2ray/scripts/connection_limits.sh") | crontab -
    
    success "Connection limits configured: $max_per_ip per IP, $max_per_user per user"
}

# Disable connection limits
disable_connection_limits() {
    info "Disabling connection limits..."
    
    local vpn_port=$(get_vpn_port)
    
    # Remove iptables rules
    while iptables -D INPUT -p tcp --dport "$vpn_port" -m connlimit \
        --connlimit-above 5 --connlimit-mask 32 -j REJECT 2>/dev/null; do :; done
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "connection_limits.sh" | crontab -
    rm -f /opt/v2ray/scripts/connection_limits.sh
    
    success "Connection limits disabled"
}

# Setup intrusion detection
setup_intrusion_detection() {
    info "Setting up intrusion detection..."
    
    # Create detection script
    cat > /opt/v2ray/scripts/intrusion_detection.sh << 'EOF'
#!/bin/bash
# VPN Intrusion Detection System

SECURITY_LOG="/opt/v2ray/logs/security.log"
ALERT_THRESHOLD=10

# Patterns to detect
declare -A PATTERNS=(
    ["port_scan"]="SYN.*FIN"
    ["brute_force"]="authentication failed.*([0-9]+) times"
    ["protocol_violation"]="invalid.*protocol"
    ["suspicious_payload"]="(shell|cmd|exec|system)"
)

# Check logs for suspicious patterns
check_logs() {
    local log_file="$1"
    local time_window="${2:-300}"  # 5 minutes
    
    # Get recent log entries
    local recent_logs=$(tail -n 1000 "$log_file" 2>/dev/null | \
        awk -v d="$(date -d "$time_window seconds ago" +%s)" \
        '$0 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
            gsub(/[T:]/, " ", $1);
            if (mktime($1) > d) print
        }')
    
    # Check each pattern
    for pattern_name in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$pattern_name]}"
        local count=$(echo "$recent_logs" | grep -cE "$pattern")
        
        if [ "$count" -gt "$ALERT_THRESHOLD" ]; then
            echo "$(date): ALERT - $pattern_name detected ($count occurrences)" >> "$SECURITY_LOG"
            # Could trigger additional actions here
        fi
    done
}

# Monitor container logs
check_logs "/opt/v2ray/logs/access.log" 300
check_logs "/opt/v2ray/logs/error.log" 300

# Check for unusual network activity
netstat -an | awk '$6 == "ESTABLISHED" {print $5}' | cut -d: -f1 | \
    sort | uniq -c | sort -rn | head -10 | \
    while read count ip; do
        if [ "$count" -gt 20 ]; then
            echo "$(date): WARNING - High connection count from $ip ($count connections)" >> "$SECURITY_LOG"
        fi
    done
EOF
    chmod +x /opt/v2ray/scripts/intrusion_detection.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "intrusion_detection.sh"; 
     echo "*/5 * * * * /opt/v2ray/scripts/intrusion_detection.sh") | crontab -
    
    success "Intrusion detection configured"
}

# Disable intrusion detection
disable_intrusion_detection() {
    info "Disabling intrusion detection..."
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "intrusion_detection.sh" | crontab -
    rm -f /opt/v2ray/scripts/intrusion_detection.sh
    
    success "Intrusion detection disabled"
}

# Security audit with detailed results
run_security_audit() {
    echo -e "${BLUE}🔒 Running comprehensive security audit...${NC}"
    echo ""
    
    local audit_results="{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"checks\": {}}"
    local issues_found=()
    local recommendations=()
    
    # Check SSH configuration
    echo -e "${YELLOW}1. SSH Security Configuration${NC}"
    local ssh_checks=0
    local ssh_config=""
    local ssh_issues=()
    
    # Find SSH config file
    for config_path in "/etc/ssh/sshd_config" "/etc/sshd_config" "/etc/openssh/sshd_config"; do
        if [ -f "$config_path" ]; then
            ssh_config="$config_path"
            break
        fi
    done
    
    if [ -n "$ssh_config" ]; then
        echo "   📂 Config file: $ssh_config"
        
        # Check PermitRootLogin
        if grep -q "^PermitRootLogin no" "$ssh_config" 2>/dev/null; then
            echo -e "   ${GREEN}✓${NC} Root login disabled"
            ((ssh_checks++))
        else
            echo -e "   ${RED}✗${NC} Root login not disabled"
            ssh_issues+=("Root login should be disabled")
        fi
        
        # Check PasswordAuthentication  
        if grep -q "^PasswordAuthentication no" "$ssh_config" 2>/dev/null; then
            echo -e "   ${GREEN}✓${NC} Password authentication disabled"
            ((ssh_checks++))
        else
            echo -e "   ${RED}✗${NC} Password authentication enabled"
            ssh_issues+=("Password authentication should be disabled")
        fi
        
        # Check PubkeyAuthentication
        if grep -q "^PubkeyAuthentication yes" "$ssh_config" 2>/dev/null; then
            echo -e "   ${GREEN}✓${NC} Public key authentication enabled"
            ((ssh_checks++))
        else
            echo -e "   ${RED}✗${NC} Public key authentication not enabled"
            ssh_issues+=("Public key authentication should be enabled")
        fi
        
        if [ "$ssh_checks" -eq 3 ]; then
            echo -e "   ${GREEN}Result: SSH is properly secured${NC}"
            audit_results=$(echo "$audit_results" | jq '.checks.ssh = "secure"')
        else
            echo -e "   ${YELLOW}Result: SSH needs hardening (${ssh_checks}/3 checks passed)${NC}"
            audit_results=$(echo "$audit_results" | jq '.checks.ssh = "needs_hardening"')
            issues_found+=("SSH: ${ssh_issues[*]}")
            recommendations+=("Run: sudo nano $ssh_config and apply SSH hardening")
        fi
    else
        echo -e "   ${GRAY}SSH service not installed${NC}"
        audit_results=$(echo "$audit_results" | jq '.checks.ssh = "not_installed"')
    fi
    echo ""
    
    # Check firewall status
    echo -e "${YELLOW}2. Firewall Configuration${NC}"
    if ufw status | grep -q "Status: active"; then
        echo -e "   ${GREEN}✓${NC} UFW firewall is active"
        local rules_count=$(ufw status | grep -c "ALLOW")
        echo "   📊 Active rules: $rules_count"
        audit_results=$(echo "$audit_results" | jq '.checks.firewall = "active"')
    else
        echo -e "   ${RED}✗${NC} UFW firewall is inactive"
        audit_results=$(echo "$audit_results" | jq '.checks.firewall = "inactive"')
        issues_found+=("Firewall: UFW is not active")
        recommendations+=("Run: sudo ufw enable")
    fi
    echo ""
    
    # Check for unnecessary services
    echo -e "${YELLOW}3. System Services${NC}"
    local unnecessary_services=0
    local unsafe_services=()
    
    for service in telnet rsh rlogin finger; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            ((unnecessary_services++))
            unsafe_services+=("$service")
            echo -e "   ${RED}✗${NC} Unsafe service enabled: $service"
        fi
    done
    
    if [ "$unnecessary_services" -eq 0 ]; then
        echo -e "   ${GREEN}✓${NC} No unsafe services found"
        audit_results=$(echo "$audit_results" | jq '.checks.unnecessary_services = "none"')
    else
        echo -e "   ${YELLOW}Result: $unnecessary_services unsafe services found${NC}"
        audit_results=$(echo "$audit_results" | jq --arg count "$unnecessary_services" '.checks.unnecessary_services = $count')
        issues_found+=("Services: ${unsafe_services[*]} should be disabled")
        recommendations+=("Run: sudo systemctl disable ${unsafe_services[*]}")
    fi
    echo ""
    
    # Check kernel parameters
    echo -e "${YELLOW}4. Kernel Security Parameters${NC}"
    local kernel_checks=0
    local kernel_issues=()
    
    # Check IP forwarding protection
    if sysctl net.ipv4.conf.all.rp_filter 2>/dev/null | grep -q "= 1"; then
        echo -e "   ${GREEN}✓${NC} IP spoofing protection enabled"
        ((kernel_checks++))
    else
        echo -e "   ${RED}✗${NC} IP spoofing protection disabled"
        kernel_issues+=("rp_filter should be set to 1")
    fi
    
    # Check source routing
    if sysctl net.ipv4.conf.all.accept_source_route 2>/dev/null | grep -q "= 0"; then
        echo -e "   ${GREEN}✓${NC} Source routing disabled"
        ((kernel_checks++))
    else
        echo -e "   ${RED}✗${NC} Source routing enabled"
        kernel_issues+=("accept_source_route should be set to 0")
    fi
    
    # Check SYN cookies
    if sysctl net.ipv4.tcp_syncookies 2>/dev/null | grep -q "= 1"; then
        echo -e "   ${GREEN}✓${NC} SYN flood protection enabled"
        ((kernel_checks++))
    else
        echo -e "   ${RED}✗${NC} SYN flood protection disabled"
        kernel_issues+=("tcp_syncookies should be set to 1")
    fi
    
    if [ "$kernel_checks" -eq 3 ]; then
        echo -e "   ${GREEN}Result: Kernel parameters are secure${NC}"
        audit_results=$(echo "$audit_results" | jq '.checks.kernel = "secure"')
    else
        echo -e "   ${YELLOW}Result: Kernel needs hardening (${kernel_checks}/3 checks passed)${NC}"
        audit_results=$(echo "$audit_results" | jq '.checks.kernel = "needs_tuning"')
        issues_found+=("Kernel: ${kernel_issues[*]}")
        recommendations+=("Run security hardening to apply kernel parameters")
    fi
    echo ""
    
    # Check file permissions
    echo -e "${YELLOW}5. Critical File Permissions${NC}"
    local perm_issues=0
    local perm_problems=()
    
    # Check VPN private key
    if [ -f /opt/v2ray/config/private_key.txt ]; then
        local key_perms=$(stat -c %a /opt/v2ray/config/private_key.txt)
        if [ "$key_perms" = "600" ]; then
            echo -e "   ${GREEN}✓${NC} VPN private key permissions correct (600)"
        else
            echo -e "   ${RED}✗${NC} VPN private key permissions incorrect ($key_perms, should be 600)"
            ((perm_issues++))
            perm_problems+=("private_key.txt has permissions $key_perms")
        fi
    fi
    
    # Check security config
    if [ -f "$SECURITY_CONFIG" ]; then
        local sec_perms=$(stat -c %a "$SECURITY_CONFIG")
        if [ "$sec_perms" = "600" ]; then
            echo -e "   ${GREEN}✓${NC} Security config permissions correct (600)"
        else
            echo -e "   ${RED}✗${NC} Security config permissions incorrect ($sec_perms, should be 600)"
            ((perm_issues++))
            perm_problems+=("security.json has permissions $sec_perms")
        fi
    fi
    
    if [ "$perm_issues" -eq 0 ]; then
        echo -e "   ${GREEN}Result: File permissions are correct${NC}"
        audit_results=$(echo "$audit_results" | jq '.checks.file_permissions = "correct"')
    else
        echo -e "   ${RED}Result: $perm_issues permission issues found${NC}"
        audit_results=$(echo "$audit_results" | jq --arg count "$perm_issues" '.checks.file_permissions = $count')
        issues_found+=("Permissions: ${perm_problems[*]}")
        recommendations+=("Run: chmod 600 /opt/v2ray/config/*.txt /opt/v2ray/config/*.json")
    fi
    echo ""
    
    # Save audit results
    ensure_dir "/opt/v2ray/security"
    echo "$audit_results" | jq '.' > "/opt/v2ray/security/audit_$(date +%Y%m%d_%H%M%S).json"
    
    # Calculate and display security score
    local score=$(calculate_security_score "$audit_results")
    echo -e "${BOLD}=== SECURITY AUDIT SUMMARY ===${NC}"
    echo -e "${BOLD}Security Score: $(get_security_score_color "$score")${NC}"
    echo ""
    
    # Display issues and recommendations
    if [ ${#issues_found[@]} -gt 0 ]; then
        echo -e "${BOLD}🚨 Issues Found:${NC}"
        for issue in "${issues_found[@]}"; do
            echo -e "   ${RED}•${NC} $issue"
        done
        echo ""
        
        echo -e "${BOLD}💡 Recommendations:${NC}"
        for rec in "${recommendations[@]}"; do
            echo -e "   ${YELLOW}•${NC} $rec"
        done
        echo ""
        echo -e "${BLUE}💡 Quick Fix: Use option 2 'Apply Security Hardening' to fix most issues automatically${NC}"
    else
        echo -e "${GREEN}✅ No security issues found! Your system is well secured.${NC}"
    fi
}

# Calculate security score
calculate_security_score() {
    local audit_results="$1"
    local score=100
    
    # Deduct points for issues
    local ssh_status="$(echo "$audit_results" | jq -r '.checks.ssh')"
    [ "$ssh_status" != "secure" ] && [ "$ssh_status" != "not_installed" ] && ((score-=20))
    [ "$(echo "$audit_results" | jq -r '.checks.firewall')" != "active" ] && ((score-=25))
    [ "$(echo "$audit_results" | jq -r '.checks.unnecessary_services')" != "none" ] && ((score-=15))
    [ "$(echo "$audit_results" | jq -r '.checks.kernel')" != "secure" ] && ((score-=15))
    [ "$(echo "$audit_results" | jq -r '.checks.file_permissions')" != "correct" ] && ((score-=15))
    
    [ "$score" -lt 0 ] && score=0
    echo "$score"
}

# Get security score color
get_security_score_color() {
    local score="$1"
    
    if [ "$score" -ge 90 ]; then
        echo -e "${GREEN}Excellent ($score/100)${NC}"
    elif [ "$score" -ge 70 ]; then
        echo -e "${YELLOW}Good ($score/100)${NC}"
    elif [ "$score" -ge 50 ]; then
        echo -e "${YELLOW}Fair ($score/100)${NC}"
    else
        echo -e "${RED}Poor ($score/100)${NC}"
    fi
}

# Apply security best practices
apply_security_hardening() {
    info "Applying security hardening..."
    
    # Kernel hardening
    cat >> /etc/sysctl.d/99-vpn-security.conf << EOF
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Enable TCP/IP SYN cookies
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    
    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-vpn-security.conf
    
    # Set secure file permissions
    chmod 600 /opt/v2ray/config/*.txt 2>/dev/null
    chmod 600 /opt/v2ray/config/*.json 2>/dev/null
    chmod 700 /opt/v2ray/scripts 2>/dev/null
    chmod 640 /opt/v2ray/logs/*.log 2>/dev/null
    
    # Create security monitoring alerts
    cat > /opt/v2ray/scripts/security_alerts.sh << 'EOF'
#!/bin/bash
# Security Alert Monitoring

ALERT_EMAIL="${SECURITY_ALERT_EMAIL:-root@localhost}"
SECURITY_LOG="/opt/v2ray/logs/security.log"

# Check for recent alerts
recent_alerts=$(grep "ALERT" "$SECURITY_LOG" 2>/dev/null | tail -10)

if [ -n "$recent_alerts" ]; then
    # Send alert (configure mail server for actual email)
    echo "$recent_alerts" | mail -s "VPN Security Alert" "$ALERT_EMAIL" 2>/dev/null || \
        echo "$recent_alerts" >> /var/log/vpn_security_alerts.log
fi
EOF
    chmod +x /opt/v2ray/scripts/security_alerts.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "security_alerts.sh"; 
     echo "*/15 * * * * /opt/v2ray/scripts/security_alerts.sh") | crontab -
    
    success "Security hardening applied"
}

# Log security events
log_security_event() {
    local event="$1"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $event" >> "$SECURITY_LOG"
}

# Get VPN port helper
get_vpn_port() {
    grep -oP '"port":\s*\K\d+' /opt/v2ray/config/config.json 2>/dev/null || echo "10443"
}

# Initialize on module load
init_security_hardening

# Export functions
export -f init_security_hardening
export -f configure_security_feature
export -f setup_fail2ban
export -f disable_fail2ban
export -f setup_port_knocking
export -f disable_port_knocking
export -f setup_geo_blocking
export -f disable_geo_blocking
export -f setup_rate_limiting
export -f disable_rate_limiting
export -f setup_connection_limits
export -f disable_connection_limits
export -f setup_intrusion_detection
export -f disable_intrusion_detection
export -f run_security_audit
export -f apply_security_hardening
export -f log_security_event