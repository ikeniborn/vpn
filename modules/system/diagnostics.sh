#!/bin/bash

# =============================================================================
# System Diagnostics Module
# 
# This module provides comprehensive diagnostics and health checks for VPN server.
# Includes configuration validation, network testing, and system analysis.
#
# Functions exported:
# - run_full_diagnostics()
# - check_system_requirements()
# - validate_vpn_configuration()
# - test_network_connectivity()
# - check_port_accessibility()
# - diagnose_vpn_issues()
# - generate_diagnostic_report()
#
# Dependencies: lib/common.sh, lib/config.sh, lib/network.sh, lib/docker.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

source "$PROJECT_ROOT/lib/config.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/config.sh"
    exit 1
}

source "$PROJECT_ROOT/lib/network.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/network.sh"
    exit 1
}

source "$PROJECT_ROOT/lib/docker.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/docker.sh"
    exit 1
}

# =============================================================================
# SYSTEM REQUIREMENTS CHECK
# =============================================================================

# Check system requirements for VPN operation
check_system_requirements() {
    local debug=${1:-false}
    local issues_found=false
    
    [ "$debug" = true ] && log "Checking system requirements..."
    
    echo "=== System Requirements Check ==="
    echo ""
    
    # Check OS
    echo -n "✓ Operating System: "
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Unknown"
        issues_found=true
    fi
    
    # Check architecture
    echo -n "✓ Architecture: "
    local arch=$(uname -m)
    echo "$arch"
    if [[ ! "$arch" =~ ^(x86_64|aarch64|armv7l)$ ]]; then
        echo "  ⚠️  Warning: Unsupported architecture"
        issues_found=true
    fi
    
    # Check memory
    echo -n "✓ Memory: "
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local available_mem=$(free -m | awk '/^Mem:/{print $7}')
    echo "${available_mem}MB available of ${total_mem}MB total"
    if [ "$available_mem" -lt 512 ]; then
        echo "  ⚠️  Warning: Low memory (recommended: 512MB+)"
        issues_found=true
    fi
    
    # Check disk space
    echo -n "✓ Disk Space: "
    local disk_free=$(df -BM /opt 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/M//')
    if [ -n "$disk_free" ]; then
        echo "${disk_free}MB free in /opt"
        if [ "$disk_free" -lt 1024 ]; then
            echo "  ⚠️  Warning: Low disk space (recommended: 1GB+)"
            issues_found=true
        fi
    else
        echo "Unable to check"
    fi
    
    # Check kernel modules
    echo -n "✓ TUN/TAP support: "
    if [ -c /dev/net/tun ]; then
        echo "Available"
    else
        echo "Not available"
        echo "  ⚠️  Warning: TUN/TAP may be required for some VPN features"
        issues_found=true
    fi
    
    # Check IP forwarding
    echo -n "✓ IP Forwarding: "
    local ip_forward=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
    if [ "$ip_forward" = "1" ]; then
        echo "Enabled"
    else
        echo "Disabled"
        echo "  ⚠️  Warning: IP forwarding is required for VPN routing"
        issues_found=true
    fi
    
    echo ""
    
    if [ "$issues_found" = true ]; then
        return 1
    else
        return 0
    fi
}

# =============================================================================
# DOCKER DIAGNOSTICS
# =============================================================================

# Check Docker installation and configuration
check_docker_health() {
    local debug=${1:-false}
    local issues_found=false
    
    [ "$debug" = true ] && log "Checking Docker health..."
    
    echo "=== Docker Diagnostics ==="
    echo ""
    
    # Check Docker installation
    echo -n "✓ Docker: "
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | sed 's/,$//')
        echo "Installed (version $docker_version)"
    else
        echo "Not installed"
        issues_found=true
        return 1
    fi
    
    # Check Docker daemon
    echo -n "✓ Docker Daemon: "
    if docker info >/dev/null 2>&1; then
        echo "Running"
    else
        echo "Not running"
        issues_found=true
        return 1
    fi
    
    # Check Docker Compose
    echo -n "✓ Docker Compose: "
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version=$(docker-compose --version 2>/dev/null | awk '{print $3}' | sed 's/,$//')
        echo "Installed (version $compose_version)"
    else
        echo "Not installed (optional)"
    fi
    
    # Check Docker containers
    echo ""
    echo "Docker Containers:"
    local containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "xray|shadowbox|watchtower|v2raya" || true)
    if [ -n "$containers" ]; then
        echo "$containers" | while read -r line; do
            echo "  • $line"
        done
    else
        echo "  No VPN containers found"
    fi
    
    # Check Docker networks
    echo ""
    echo "Docker Networks:"
    local networks=$(docker network ls --format "table {{.Name}}\t{{.Driver}}" | grep -v "DRIVER" | grep -E "bridge|host" || true)
    if [ -n "$networks" ]; then
        echo "$networks" | while read -r line; do
            echo "  • $line"
        done
    fi
    
    echo ""
    
    if [ "$issues_found" = true ]; then
        return 1
    else
        return 0
    fi
}

# =============================================================================
# VPN CONFIGURATION VALIDATION
# =============================================================================

# Validate VPN configuration files
validate_vpn_configuration() {
    local protocol="${1:-auto}"
    local debug=${2:-false}
    local issues_found=false
    
    [ "$debug" = true ] && log "Validating VPN configuration..."
    
    echo "=== VPN Configuration Validation ==="
    echo ""
    
    # Auto-detect protocol if not specified
    if [ "$protocol" = "auto" ]; then
        if [ -f "/opt/v2ray/config/config.json" ]; then
            protocol="xray"
        elif [ -f "/opt/outline/persisted-state/shadowbox_server_config.json" ]; then
            protocol="outline"
        else
            echo "No VPN configuration found"
            return 1
        fi
    fi
    
    case "$protocol" in
        "xray"|"vless"|"vless-reality")
            echo "Protocol: VLESS+Reality (Xray)"
            echo ""
            
            # Check configuration file
            echo -n "✓ Config file: "
            if [ -f "/opt/v2ray/config/config.json" ]; then
                echo "Found"
                
                # Validate JSON
                echo -n "✓ JSON validation: "
                if jq empty /opt/v2ray/config/config.json 2>/dev/null; then
                    echo "Valid"
                else
                    echo "Invalid JSON"
                    issues_found=true
                fi
                
                # Check required fields
                echo -n "✓ Inbounds: "
                local inbound_count=$(jq '.inbounds | length' /opt/v2ray/config/config.json 2>/dev/null || echo "0")
                if [ "$inbound_count" -gt 0 ]; then
                    echo "$inbound_count configured"
                else
                    echo "None configured"
                    issues_found=true
                fi
                
                # Check port configuration
                echo -n "✓ Port: "
                local port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null)
                if [ -n "$port" ] && [ "$port" != "null" ]; then
                    echo "$port"
                    
                    # Check if port is listening
                    echo -n "✓ Port status: "
                    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                        echo "Listening"
                    else
                        echo "Not listening"
                        issues_found=true
                    fi
                else
                    echo "Not configured"
                    issues_found=true
                fi
                
                # Check Reality settings
                echo -n "✓ Reality protocol: "
                local security=$(jq -r '.inbounds[0].streamSettings.security' /opt/v2ray/config/config.json 2>/dev/null)
                if [ "$security" = "reality" ]; then
                    echo "Configured"
                    
                    # Check Reality keys
                    echo -n "✓ Private key: "
                    local priv_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' /opt/v2ray/config/config.json 2>/dev/null)
                    if [ -n "$priv_key" ] && [ "$priv_key" != "null" ] && [ ${#priv_key} -eq 44 ]; then
                        echo "Valid (44 chars)"
                    else
                        echo "Invalid or missing"
                        issues_found=true
                    fi
                    
                    # Check SNI
                    echo -n "✓ SNI domain: "
                    local sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /opt/v2ray/config/config.json 2>/dev/null)
                    if [ -n "$sni" ] && [ "$sni" != "null" ]; then
                        echo "$sni"
                    else
                        echo "Not configured"
                        issues_found=true
                    fi
                else
                    echo "Not configured"
                    issues_found=true
                fi
                
            else
                echo "Not found"
                issues_found=true
            fi
            
            # Check user configurations
            echo ""
            echo "User Configurations:"
            if [ -d "/opt/v2ray/users" ]; then
                local user_count=$(ls -1 /opt/v2ray/users/*.json 2>/dev/null | wc -l)
                echo "  • User files: $user_count"
                
                # List users
                for user_file in /opt/v2ray/users/*.json; do
                    if [ -f "$user_file" ]; then
                        local username=$(basename "$user_file" .json)
                        local uuid=$(jq -r '.uuid' "$user_file" 2>/dev/null)
                        if [ -n "$uuid" ] && [ "$uuid" != "null" ]; then
                            echo "  • $username: UUID configured"
                        else
                            echo "  • $username: Invalid configuration"
                            issues_found=true
                        fi
                    fi
                done
            else
                echo "  • No user directory found"
            fi
            ;;
            
        "outline")
            echo "Protocol: Shadowsocks (Outline)"
            echo ""
            
            # Check configuration file
            echo -n "✓ Config file: "
            if [ -f "/opt/outline/persisted-state/shadowbox_server_config.json" ]; then
                echo "Found"
                
                # Validate JSON
                echo -n "✓ JSON validation: "
                if jq empty /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null; then
                    echo "Valid"
                else
                    echo "Invalid JSON"
                    issues_found=true
                fi
                
                # Check access keys
                echo -n "✓ Access keys: "
                local key_count=$(jq '.accessKeys | length' /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null || echo "0")
                echo "$key_count configured"
                
            else
                echo "Not found"
                issues_found=true
            fi
            
            # Check API configuration
            echo -n "✓ API config: "
            if [ -f "/opt/outline/access.txt" ]; then
                echo "Found"
            else
                echo "Not found"
                issues_found=true
            fi
            ;;
            
        *)
            echo "Unknown protocol: $protocol"
            return 1
            ;;
    esac
    
    echo ""
    
    if [ "$issues_found" = true ]; then
        return 1
    else
        return 0
    fi
}

# =============================================================================
# NETWORK CONNECTIVITY TESTS
# =============================================================================

# Test network connectivity
test_network_connectivity() {
    local debug=${1:-false}
    local issues_found=false
    
    [ "$debug" = true ] && log "Testing network connectivity..."
    
    echo "=== Network Connectivity Tests ==="
    echo ""
    
    # Check internet connectivity
    echo -n "✓ Internet connectivity: "
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo "OK"
    else
        echo "Failed"
        issues_found=true
    fi
    
    # Check DNS resolution
    echo -n "✓ DNS resolution: "
    if nslookup google.com >/dev/null 2>&1 || host google.com >/dev/null 2>&1; then
        echo "OK"
    else
        echo "Failed"
        issues_found=true
    fi
    
    # Check external IP
    echo -n "✓ External IP: "
    local external_ip=$(get_external_ip 2>/dev/null)
    if [ -n "$external_ip" ]; then
        echo "$external_ip"
    else
        echo "Unable to detect"
        issues_found=true
    fi
    
    # Check primary network interface
    echo -n "✓ Primary interface: "
    local primary_interface=$(ip route | grep '^default' | grep -o 'dev [^ ]*' | head -1 | cut -d' ' -f2)
    if [ -n "$primary_interface" ]; then
        echo "$primary_interface"
        
        # Get interface IP
        echo -n "✓ Interface IP: "
        local interface_ip=$(ip -4 addr show "$primary_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -n "$interface_ip" ]; then
            echo "$interface_ip"
        else
            echo "No IPv4 address"
        fi
    else
        echo "Not detected"
        issues_found=true
    fi
    
    # Check routing table
    echo ""
    echo "Routing Table:"
    ip route | head -5 | while read -r line; do
        echo "  • $line"
    done
    
    # Check iptables rules
    echo ""
    echo "NAT Rules (for VPN):"
    if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE; then
        echo "  ✓ Masquerading rules found"
        iptables -t nat -L POSTROUTING -n 2>/dev/null | grep MASQUERADE | head -3 | while read -r line; do
            echo "    • $line"
        done
    else
        echo "  ⚠️  No masquerading rules found"
        issues_found=true
    fi
    
    echo ""
    
    if [ "$issues_found" = true ]; then
        return 1
    else
        return 0
    fi
}

# =============================================================================
# PORT ACCESSIBILITY CHECK
# =============================================================================

# Check port accessibility
check_port_accessibility() {
    local port="${1:-auto}"
    local debug=${2:-false}
    local issues_found=false
    
    [ "$debug" = true ] && log "Checking port accessibility..."
    
    echo "=== Port Accessibility Check ==="
    echo ""
    
    # Auto-detect port if not specified
    if [ "$port" = "auto" ]; then
        # Try to get port from Xray config
        if [ -f "/opt/v2ray/config/config.json" ]; then
            port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null)
        fi
        
        # Try to get port from Outline
        if [ -z "$port" ] || [ "$port" = "null" ]; then
            if [ -f "/opt/outline/access.txt" ]; then
                port=$(grep -oP 'port":\K[0-9]+' /opt/outline/access.txt 2>/dev/null | head -1)
            fi
        fi
        
        if [ -z "$port" ] || [ "$port" = "null" ]; then
            echo "Could not auto-detect VPN port"
            return 1
        fi
    fi
    
    echo "Checking port: $port"
    echo ""
    
    # Check if port is valid
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port number: $port"
        return 1
    fi
    
    # Check local binding
    echo -n "✓ Local binding: "
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "Port $port is listening"
    elif ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo "Port $port is listening"
    else
        echo "Port $port is NOT listening"
        issues_found=true
    fi
    
    # Check process using port
    echo -n "✓ Process: "
    local process=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f2 | head -1)
    if [ -z "$process" ]; then
        process=$(ss -tulnp 2>/dev/null | grep ":$port " | grep -oP 'users:\(\("\K[^"]+' | head -1)
    fi
    if [ -n "$process" ]; then
        echo "$process"
    else
        echo "Unknown"
    fi
    
    # Check firewall rules
    echo -n "✓ Firewall (UFW): "
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "$port"; then
            echo "Port $port is allowed"
        else
            echo "Port $port is NOT allowed"
            issues_found=true
        fi
    else
        echo "UFW not installed"
    fi
    
    # Check iptables
    echo -n "✓ iptables: "
    if iptables -L INPUT -n 2>/dev/null | grep -q "dpt:$port"; then
        echo "Port $port has rules"
    else
        echo "No specific rules for port $port"
    fi
    
    # Test external accessibility (optional)
    echo ""
    echo "External Accessibility:"
    echo "  To test from outside: telnet <server-ip> $port"
    echo "  Or: nc -zv <server-ip> $port"
    
    echo ""
    
    if [ "$issues_found" = true ]; then
        return 1
    else
        return 0
    fi
}

# =============================================================================
# VPN ISSUE DIAGNOSIS
# =============================================================================

# Diagnose common VPN issues
diagnose_vpn_issues() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Diagnosing VPN issues..."
    
    echo "=== VPN Issue Diagnosis ==="
    echo ""
    
    local issues=()
    local suggestions=()
    
    # Check if VPN container is running
    echo "Checking VPN containers..."
    if ! docker ps 2>/dev/null | grep -qE "xray|shadowbox"; then
        issues+=("No VPN container is running")
        suggestions+=("Run: sudo ./vpn.sh status to check server status")
        suggestions+=("Run: sudo ./vpn.sh restart to restart the server")
    fi
    
    # Check IP forwarding
    echo "Checking IP forwarding..."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then
        issues+=("IP forwarding is disabled")
        suggestions+=("Run: sudo sysctl -w net.ipv4.ip_forward=1")
        suggestions+=("Add to /etc/sysctl.conf: net.ipv4.ip_forward=1")
    fi
    
    # Check DNS
    echo "Checking DNS configuration..."
    if ! nslookup google.com >/dev/null 2>&1; then
        issues+=("DNS resolution is not working")
        suggestions+=("Check /etc/resolv.conf")
        suggestions+=("Try using public DNS: 8.8.8.8 or 1.1.1.1")
    fi
    
    # Check firewall
    echo "Checking firewall status..."
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        if ! ufw status 2>/dev/null | grep -qE "10443|10000:65000"; then
            issues+=("VPN ports might not be allowed in firewall")
            suggestions+=("Check firewall rules: sudo ufw status")
            suggestions+=("Allow VPN port if needed: sudo ufw allow <port>/tcp")
        fi
    fi
    
    # Check Docker
    echo "Checking Docker health..."
    if ! docker info >/dev/null 2>&1; then
        issues+=("Docker daemon is not running")
        suggestions+=("Start Docker: sudo systemctl start docker")
        suggestions+=("Enable Docker: sudo systemctl enable docker")
    fi
    
    # Check disk space
    echo "Checking disk space..."
    local disk_usage=$(df -h /opt 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 90 ]; then
        issues+=("Low disk space (${disk_usage}% used)")
        suggestions+=("Clean up Docker: docker system prune -f")
        suggestions+=("Check logs: find /opt -name '*.log' -size +100M")
    fi
    
    # Display results
    echo ""
    if [ ${#issues[@]} -eq 0 ]; then
        echo "✅ No obvious issues detected"
        echo ""
        echo "If you're still having problems:"
        echo "  1. Check server logs: sudo ./vpn.sh logs"
        echo "  2. Verify client configuration matches server"
        echo "  3. Test with different client/network"
        echo "  4. Check if ISP blocks VPN protocols"
    else
        echo "❌ Issues found:"
        echo ""
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
        
        echo ""
        echo "💡 Suggestions:"
        echo ""
        for suggestion in "${suggestions[@]}"; do
            echo "  • $suggestion"
        done
    fi
    
    echo ""
    return 0
}

# =============================================================================
# DIAGNOSTIC REPORT GENERATION
# =============================================================================

# Generate comprehensive diagnostic report
generate_diagnostic_report() {
    local output_file="${1:-/tmp/vpn_diagnostics_$(date +%Y%m%d_%H%M%S).txt}"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Generating diagnostic report..."
    
    {
        echo "==================================="
        echo "VPN Diagnostics Report"
        echo "==================================="
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo ""
        
        # System info
        echo "=== System Information ==="
        check_system_requirements false
        echo ""
        
        # Docker info
        echo "=== Docker Information ==="
        check_docker_health false
        echo ""
        
        # VPN configuration
        echo "=== VPN Configuration ==="
        validate_vpn_configuration auto false
        echo ""
        
        # Network tests
        echo "=== Network Tests ==="
        test_network_connectivity false
        echo ""
        
        # Port checks
        echo "=== Port Accessibility ==="
        check_port_accessibility auto false
        echo ""
        
        # Issue diagnosis
        echo "=== Issue Diagnosis ==="
        diagnose_vpn_issues false
        echo ""
        
        # Recent logs
        echo "=== Recent Logs (last 20 lines) ==="
        echo ""
        echo "Docker logs:"
        for container in xray shadowbox; do
            if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
                echo "--- $container ---"
                docker logs --tail 20 "$container" 2>&1 || echo "Failed to get logs"
                echo ""
            fi
        done
        
        # System logs
        echo "System logs:"
        if [ -f "/var/log/syslog" ]; then
            echo "--- syslog (VPN-related) ---"
            grep -i "vpn\|xray\|shadowbox\|docker" /var/log/syslog | tail -20 || true
        fi
        
        echo ""
        echo "==================================="
        echo "End of Diagnostic Report"
        echo "==================================="
        
    } > "$output_file" 2>&1
    
    echo "✅ Diagnostic report saved to: $output_file"
    echo ""
    echo "You can view it with: cat $output_file"
    echo "Or share it for troubleshooting (remove sensitive data first)"
    
    return 0
}

# =============================================================================
# MAIN DIAGNOSTIC FUNCTION
# =============================================================================

# Run full diagnostics
run_full_diagnostics() {
    local save_report=${1:-false}
    local debug=${2:-false}
    
    clear
    echo "╔═══════════════════════════════════════╗"
    echo "║      VPN System Diagnostics           ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    # Run all diagnostic checks
    local overall_status=0
    
    # System requirements
    if ! check_system_requirements "$debug"; then
        overall_status=1
    fi
    
    echo ""
    read -p "Press Enter to continue..." -r
    
    # Docker health
    if ! check_docker_health "$debug"; then
        overall_status=1
    fi
    
    echo ""
    read -p "Press Enter to continue..." -r
    
    # VPN configuration
    if ! validate_vpn_configuration auto "$debug"; then
        overall_status=1
    fi
    
    echo ""
    read -p "Press Enter to continue..." -r
    
    # Network connectivity
    if ! test_network_connectivity "$debug"; then
        overall_status=1
    fi
    
    echo ""
    read -p "Press Enter to continue..." -r
    
    # Port accessibility
    if ! check_port_accessibility auto "$debug"; then
        overall_status=1
    fi
    
    echo ""
    read -p "Press Enter to continue..." -r
    
    # Issue diagnosis
    diagnose_vpn_issues "$debug"
    
    echo ""
    echo "==================================="
    if [ "$overall_status" -eq 0 ]; then
        echo "✅ Overall Status: HEALTHY"
    else
        echo "❌ Overall Status: ISSUES DETECTED"
    fi
    echo "==================================="
    
    # Ask about report generation
    if [ "$save_report" = true ]; then
        echo ""
        generate_diagnostic_report
    else
        echo ""
        echo "Would you like to save a diagnostic report?"
        read -p "Save report? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            generate_diagnostic_report
        fi
    fi
    
    return $overall_status
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f check_system_requirements
export -f check_docker_health
export -f validate_vpn_configuration
export -f test_network_connectivity
export -f check_port_accessibility
export -f diagnose_vpn_issues
export -f generate_diagnostic_report
export -f run_full_diagnostics

# =============================================================================
# STANDALONE EXECUTION
# =============================================================================

# If script is run directly, execute diagnostics
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root or with sudo"
        exit 1
    fi
    
    # Parse arguments
    case "${1:-}" in
        "report")
            generate_diagnostic_report
            ;;
        "quick")
            # Quick checks only
            check_system_requirements
            echo ""
            check_docker_health
            ;;
        "network")
            test_network_connectivity
            ;;
        "port")
            check_port_accessibility "${2:-auto}"
            ;;
        "issues")
            diagnose_vpn_issues
            ;;
        *)
            run_full_diagnostics
            ;;
    esac
fi