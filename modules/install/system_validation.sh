#!/bin/bash

# =============================================================================
# Enhanced Pre-Installation System Validation Module
# 
# This module provides comprehensive system validation before VPN installation.
# Implements detailed checks for resources, dependencies, and compatibility.
#
# Functions exported:
# - validate_system_requirements()
# - check_hardware_resources()
# - validate_network_environment()
# - check_software_dependencies()
# - generate_installation_report()
# - interactive_validation_wizard()
#
# Dependencies: lib/common.sh, lib/network.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

source "$PROJECT_ROOT/lib/network.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/network.sh"
    exit 1
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Minimum requirements
MIN_CPU_CORES=1
MIN_MEMORY_MB=512
MIN_DISK_GB=5
MIN_KERNEL_VERSION="3.10"

# Recommended requirements
REC_CPU_CORES=2
REC_MEMORY_MB=1024
REC_DISK_GB=10

# Supported architectures
SUPPORTED_ARCH=("x86_64" "aarch64" "armv7l")

# Supported OS
SUPPORTED_OS=("ubuntu" "debian" "centos" "rhel" "fedora" "alpine")

# Required ports
REQUIRED_PORTS=(22)  # SSH
COMMON_VPN_PORTS=(443 8443 10443)

# =============================================================================
# HARDWARE VALIDATION
# =============================================================================

# Check hardware resources
check_hardware_resources() {
    local verbose=${1:-true}
    local validation_passed=true
    local warnings=()
    local errors=()
    
    [ "$verbose" = true ] && echo "=== Hardware Resources Validation ==="
    
    # Check CPU
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    local cpu_info=$(cat /proc/cpuinfo 2>/dev/null | grep "model name" | head -1 | cut -d: -f2 | xargs)
    
    [ "$verbose" = true ] && echo -n "CPU Cores: $cpu_cores"
    
    if [ "$cpu_cores" -lt "$MIN_CPU_CORES" ]; then
        errors+=("CPU: Insufficient cores ($cpu_cores < $MIN_CPU_CORES minimum)")
        validation_passed=false
        [ "$verbose" = true ] && echo " ❌"
    elif [ "$cpu_cores" -lt "$REC_CPU_CORES" ]; then
        warnings+=("CPU: Below recommended cores ($cpu_cores < $REC_CPU_CORES recommended)")
        [ "$verbose" = true ] && echo " ⚠️"
    else
        [ "$verbose" = true ] && echo " ✅"
    fi
    
    [ "$verbose" = true ] && [ -n "$cpu_info" ] && echo "  Model: $cpu_info"
    
    # Check Memory
    local total_memory_mb=$(free -m | awk '/^Mem:/{print $2}')
    local available_memory_mb=$(free -m | awk '/^Mem:/{print $7}')
    
    [ "$verbose" = true ] && echo -n "Memory: ${total_memory_mb}MB total, ${available_memory_mb}MB available"
    
    if [ "$available_memory_mb" -lt "$MIN_MEMORY_MB" ]; then
        errors+=("Memory: Insufficient available memory (${available_memory_mb}MB < ${MIN_MEMORY_MB}MB minimum)")
        validation_passed=false
        [ "$verbose" = true ] && echo " ❌"
    elif [ "$available_memory_mb" -lt "$REC_MEMORY_MB" ]; then
        warnings+=("Memory: Below recommended (${available_memory_mb}MB < ${REC_MEMORY_MB}MB recommended)")
        [ "$verbose" = true ] && echo " ⚠️"
    else
        [ "$verbose" = true ] && echo " ✅"
    fi
    
    # Check Disk Space
    local root_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    local opt_disk_gb=$(df -BG /opt 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "$root_disk_gb")
    
    [ "$verbose" = true ] && echo -n "Disk Space: ${opt_disk_gb}GB free in /opt"
    
    if [ "$opt_disk_gb" -lt "$MIN_DISK_GB" ]; then
        errors+=("Disk: Insufficient space (${opt_disk_gb}GB < ${MIN_DISK_GB}GB minimum)")
        validation_passed=false
        [ "$verbose" = true ] && echo " ❌"
    elif [ "$opt_disk_gb" -lt "$REC_DISK_GB" ]; then
        warnings+=("Disk: Below recommended (${opt_disk_gb}GB < ${REC_DISK_GB}GB recommended)")
        [ "$verbose" = true ] && echo " ⚠️"
    else
        [ "$verbose" = true ] && echo " ✅"
    fi
    
    # Check Architecture
    local arch=$(uname -m)
    [ "$verbose" = true ] && echo -n "Architecture: $arch"
    
    if [[ " ${SUPPORTED_ARCH[@]} " =~ " ${arch} " ]]; then
        [ "$verbose" = true ] && echo " ✅"
    else
        errors+=("Architecture: Unsupported architecture ($arch)")
        validation_passed=false
        [ "$verbose" = true ] && echo " ❌"
    fi
    
    # Check for virtualization
    local virt_type="none"
    if [ -f /proc/cpuinfo ]; then
        if grep -q "hypervisor" /proc/cpuinfo; then
            virt_type="vm"
        fi
    fi
    
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local detected_virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        [ "$detected_virt" != "none" ] && virt_type="$detected_virt"
    fi
    
    [ "$verbose" = true ] && echo "Virtualization: $virt_type"
    
    # Special checks for containers
    if [ -f /.dockerenv ] || grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
        warnings+=("Running in container - some features may be limited")
        [ "$verbose" = true ] && echo "  ⚠️  Container environment detected"
    fi
    
    # Return results
    if [ "$verbose" = true ]; then
        echo ""
        if [ ${#errors[@]} -gt 0 ]; then
            echo "❌ Errors:"
            for error in "${errors[@]}"; do
                echo "  - $error"
            done
        fi
        
        if [ ${#warnings[@]} -gt 0 ]; then
            echo "⚠️  Warnings:"
            for warning in "${warnings[@]}"; do
                echo "  - $warning"
            done
        fi
        
        if [ "$validation_passed" = true ] && [ ${#warnings[@]} -eq 0 ]; then
            echo "✅ All hardware requirements met"
        fi
    fi
    
    return $([ "$validation_passed" = true ] && echo 0 || echo 1)
}

# =============================================================================
# SOFTWARE VALIDATION
# =============================================================================

# Check software dependencies
check_software_dependencies() {
    local verbose=${1:-true}
    local validation_passed=true
    local missing_deps=()
    local optional_missing=()
    
    [ "$verbose" = true ] && echo "=== Software Dependencies Validation ==="
    
    # Check OS
    local os_name="unknown"
    local os_version="unknown"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_name=$(echo "${ID:-unknown}" | tr '[:upper:]' '[:lower:]')
        os_version="${VERSION_ID:-unknown}"
    fi
    
    [ "$verbose" = true ] && echo -n "Operating System: $os_name $os_version"
    
    if [[ " ${SUPPORTED_OS[@]} " =~ " ${os_name} " ]]; then
        [ "$verbose" = true ] && echo " ✅"
    else
        missing_deps+=("Unsupported OS: $os_name")
        [ "$verbose" = true ] && echo " ⚠️"
    fi
    
    # Check kernel version
    local kernel_version=$(uname -r | cut -d- -f1)
    [ "$verbose" = true ] && echo -n "Kernel Version: $kernel_version"
    
    if [ "$(printf '%s\n' "$MIN_KERNEL_VERSION" "$kernel_version" | sort -V | head -n1)" = "$MIN_KERNEL_VERSION" ]; then
        [ "$verbose" = true ] && echo " ✅"
    else
        missing_deps+=("Kernel version too old: $kernel_version < $MIN_KERNEL_VERSION")
        validation_passed=false
        [ "$verbose" = true ] && echo " ❌"
    fi
    
    # Check required commands
    local required_commands=("curl" "wget" "tar" "gzip" "systemctl" "iptables")
    local optional_commands=("docker" "docker-compose" "jq" "qrencode" "git")
    
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo "Required Commands:"
    
    for cmd in "${required_commands[@]}"; do
        [ "$verbose" = true ] && echo -n "  $cmd: "
        if command -v "$cmd" >/dev/null 2>&1; then
            [ "$verbose" = true ] && echo "✅"
        else
            missing_deps+=("Command not found: $cmd")
            validation_passed=false
            [ "$verbose" = true ] && echo "❌"
        fi
    done
    
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo "Optional Commands:"
    
    for cmd in "${optional_commands[@]}"; do
        [ "$verbose" = true ] && echo -n "  $cmd: "
        if command -v "$cmd" >/dev/null 2>&1; then
            [ "$verbose" = true ] && echo "✅"
        else
            optional_missing+=("$cmd")
            [ "$verbose" = true ] && echo "⚠️  (will be installed if needed)"
        fi
    done
    
    # Check systemd
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo -n "Systemd: "
    
    if [ -d /run/systemd/system ]; then
        [ "$verbose" = true ] && echo "✅"
    else
        missing_deps+=("Systemd not running")
        [ "$verbose" = true ] && echo "⚠️  (some features may be limited)"
    fi
    
    # Check SELinux status
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
        [ "$verbose" = true ] && echo "SELinux: $selinux_status"
        
        if [ "$selinux_status" = "Enforcing" ]; then
            optional_missing+=("SELinux is enforcing - may need additional configuration")
        fi
    fi
    
    # Return results
    if [ "$verbose" = true ]; then
        echo ""
        if [ ${#missing_deps[@]} -gt 0 ]; then
            echo "❌ Missing Dependencies:"
            for dep in "${missing_deps[@]}"; do
                echo "  - $dep"
            done
        fi
        
        if [ ${#optional_missing[@]} -gt 0 ]; then
            echo "⚠️  Optional Dependencies:"
            for dep in "${optional_missing[@]}"; do
                echo "  - $dep"
            done
        fi
        
        if [ "$validation_passed" = true ] && [ ${#optional_missing[@]} -eq 0 ]; then
            echo "✅ All software dependencies met"
        fi
    fi
    
    return $([ "$validation_passed" = true ] && echo 0 || echo 1)
}

# =============================================================================
# NETWORK VALIDATION
# =============================================================================

# Validate network environment
validate_network_environment() {
    local verbose=${1:-true}
    local validation_passed=true
    local issues=()
    
    [ "$verbose" = true ] && echo "=== Network Environment Validation ==="
    
    # Check internet connectivity
    [ "$verbose" = true ] && echo -n "Internet Connectivity: "
    
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    local connected=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
            connected=true
            break
        fi
    done
    
    if [ "$connected" = true ]; then
        [ "$verbose" = true ] && echo "✅"
    else
        issues+=("No internet connectivity detected")
        validation_passed=false
        [ "$verbose" = true ] && echo "❌"
    fi
    
    # Check DNS resolution
    [ "$verbose" = true ] && echo -n "DNS Resolution: "
    
    if nslookup google.com >/dev/null 2>&1 || host google.com >/dev/null 2>&1; then
        [ "$verbose" = true ] && echo "✅"
    else
        issues+=("DNS resolution not working")
        validation_passed=false
        [ "$verbose" = true ] && echo "❌"
    fi
    
    # Check external IP
    [ "$verbose" = true ] && echo -n "External IP Detection: "
    
    local external_ip=""
    for service in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        external_ip=$(curl -s --max-time 5 "$service" 2>/dev/null)
        if [[ "$external_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
    done
    
    if [ -n "$external_ip" ]; then
        [ "$verbose" = true ] && echo "$external_ip ✅"
    else
        issues+=("Cannot detect external IP address")
        [ "$verbose" = true ] && echo "Failed ⚠️"
    fi
    
    # Check network interfaces
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo "Network Interfaces:"
    
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$")
    local active_interfaces=0
    
    for iface in $interfaces; do
        local state=$(ip link show "$iface" | grep -oP '(?<=state )\S+' || echo "UNKNOWN")
        local ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet )\S+' | cut -d'/' -f1 || echo "no-ip")
        
        [ "$verbose" = true ] && echo -n "  $iface: $state"
        [ -n "$ip_addr" ] && [ "$ip_addr" != "no-ip" ] && [ "$verbose" = true ] && echo -n " ($ip_addr)"
        
        if [ "$state" = "UP" ]; then
            active_interfaces=$((active_interfaces + 1))
            [ "$verbose" = true ] && echo " ✅"
        else
            [ "$verbose" = true ] && echo " ⚠️"
        fi
    done
    
    if [ $active_interfaces -eq 0 ]; then
        issues+=("No active network interfaces found")
        validation_passed=false
    fi
    
    # Check firewall status
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo -n "Firewall Status: "
    
    local firewall_active=false
    local firewall_type="none"
    
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        firewall_active=true
        firewall_type="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        firewall_active=true
        firewall_type="firewalld"
    elif iptables -L -n 2>/dev/null | grep -q "Chain"; then
        firewall_active=true
        firewall_type="iptables"
    fi
    
    if [ "$firewall_active" = true ]; then
        [ "$verbose" = true ] && echo "$firewall_type active ✅"
    else
        [ "$verbose" = true ] && echo "No firewall detected ⚠️"
        issues+=("No firewall detected - security risk")
    fi
    
    # Check required ports
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo "Port Availability:"
    
    for port in "${REQUIRED_PORTS[@]}"; do
        [ "$verbose" = true ] && echo -n "  Port $port (SSH): "
        
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            [ "$verbose" = true ] && echo "In use ✅"
        else
            [ "$verbose" = true ] && echo "Not listening ⚠️"
            issues+=("SSH port $port not accessible")
        fi
    done
    
    # Check common VPN ports availability
    [ "$verbose" = true ] && echo ""
    [ "$verbose" = true ] && echo "Common VPN Ports:"
    
    local available_ports=()
    for port in "${COMMON_VPN_PORTS[@]}"; do
        [ "$verbose" = true ] && echo -n "  Port $port: "
        
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            [ "$verbose" = true ] && echo "In use ❌"
        else
            [ "$verbose" = true ] && echo "Available ✅"
            available_ports+=("$port")
        fi
    done
    
    if [ ${#available_ports[@]} -eq 0 ]; then
        [ "$verbose" = true ] && echo "  Note: All common VPN ports are in use, will use random port"
    fi
    
    # Return results
    if [ "$verbose" = true ]; then
        echo ""
        if [ ${#issues[@]} -gt 0 ]; then
            echo "⚠️  Network Issues:"
            for issue in "${issues[@]}"; do
                echo "  - $issue"
            done
        fi
        
        if [ "$validation_passed" = true ] && [ ${#issues[@]} -eq 0 ]; then
            echo "✅ Network environment validated"
        fi
    fi
    
    return $([ "$validation_passed" = true ] && echo 0 || echo 1)
}

# =============================================================================
# COMPREHENSIVE VALIDATION
# =============================================================================

# Run all validation checks
validate_system_requirements() {
    local verbose=${1:-true}
    local generate_report=${2:-false}
    
    [ "$verbose" = true ] && {
        echo "======================================"
        echo "VPN Pre-Installation System Validation"
        echo "======================================"
        echo "Timestamp: $(date)"
        echo ""
    }
    
    local overall_status=0
    local validation_results=()
    
    # Hardware validation
    if check_hardware_resources "$verbose"; then
        validation_results+=("Hardware: PASSED")
    else
        validation_results+=("Hardware: FAILED")
        overall_status=1
    fi
    
    [ "$verbose" = true ] && echo ""
    
    # Software validation
    if check_software_dependencies "$verbose"; then
        validation_results+=("Software: PASSED")
    else
        validation_results+=("Software: FAILED")
        overall_status=1
    fi
    
    [ "$verbose" = true ] && echo ""
    
    # Network validation
    if validate_network_environment "$verbose"; then
        validation_results+=("Network: PASSED")
    else
        validation_results+=("Network: FAILED")
        overall_status=1
    fi
    
    # Summary
    if [ "$verbose" = true ]; then
        echo ""
        echo "======================================"
        echo "Validation Summary:"
        echo "======================================"
        
        for result in "${validation_results[@]}"; do
            if [[ "$result" =~ "PASSED" ]]; then
                echo "✅ $result"
            else
                echo "❌ $result"
            fi
        done
        
        echo ""
        if [ $overall_status -eq 0 ]; then
            echo "✅ System is ready for VPN installation"
        else
            echo "❌ System validation failed - please address the issues above"
        fi
    fi
    
    # Generate report if requested
    if [ "$generate_report" = true ]; then
        generate_installation_report
    fi
    
    return $overall_status
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

# Generate detailed installation readiness report
generate_installation_report() {
    local report_file="/tmp/vpn_installation_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "VPN Installation Readiness Report"
        echo "================================="
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo ""
        
        echo "System Information:"
        echo "------------------"
        uname -a
        echo ""
        
        echo "Hardware Resources:"
        echo "------------------"
        check_hardware_resources false
        echo ""
        
        echo "Software Dependencies:"
        echo "--------------------"
        check_software_dependencies false
        echo ""
        
        echo "Network Environment:"
        echo "-------------------"
        validate_network_environment false
        echo ""
        
        echo "Recommendations:"
        echo "---------------"
        echo "1. Ensure all required dependencies are installed"
        echo "2. Have at least ${REC_MEMORY_MB}MB RAM available"
        echo "3. Have at least ${REC_DISK_GB}GB disk space free"
        echo "4. Configure firewall to allow VPN traffic"
        echo "5. Use a static IP address if possible"
        
    } > "$report_file" 2>&1
    
    echo ""
    echo "📄 Detailed report saved to: $report_file"
    
    return 0
}

# =============================================================================
# INTERACTIVE WIZARD
# =============================================================================

# Interactive validation wizard
interactive_validation_wizard() {
    clear
    echo "╔═══════════════════════════════════════╗"
    echo "║   VPN Installation Validation Wizard   ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "This wizard will check if your system is ready for VPN installation."
    echo ""
    read -p "Press Enter to begin validation..."
    
    clear
    validate_system_requirements true false
    
    echo ""
    echo "Would you like to:"
    echo "1) Continue with installation (if validation passed)"
    echo "2) Generate detailed report"
    echo "3) Exit"
    echo ""
    
    read -p "Select option (1-3): " choice
    
    case "$choice" in
        1)
            if validate_system_requirements false false; then
                echo "✅ Proceeding with installation..."
                return 0
            else
                echo "❌ Cannot proceed - validation failed"
                return 1
            fi
            ;;
        2)
            generate_installation_report
            echo ""
            read -p "Press Enter to continue..."
            return 0
            ;;
        3)
            echo "Exiting validation wizard"
            return 0
            ;;
        *)
            echo "Invalid option"
            return 1
            ;;
    esac
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f validate_system_requirements
export -f check_hardware_resources
export -f check_software_dependencies
export -f validate_network_environment
export -f generate_installation_report
export -f interactive_validation_wizard

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

# If script is run directly, execute validation
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "hardware")
            check_hardware_resources true
            ;;
        "software")
            check_software_dependencies true
            ;;
        "network")
            validate_network_environment true
            ;;
        "report")
            validate_system_requirements true true
            ;;
        "wizard")
            interactive_validation_wizard
            ;;
        *)
            validate_system_requirements true false
            ;;
    esac
fi