#!/bin/bash
#
# security-audit.sh - Security audit for the integrated VPN solution
# This script performs security checks and verification of the VPN setup

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
LOG_DIR="${BASE_DIR}/logs"
SCRIPT_DIR="${BASE_DIR}/scripts"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables for tracking findings
CRITICAL_FINDINGS=0
WARNING_FINDINGS=0
INFO_FINDINGS=0
FAILED_CHECKS=0
PASSED_CHECKS=0

# Output file for full report
REPORT_FILE="${LOG_DIR}/security_audit_$(date +%Y%m%d).log"

# Email to send reports to
ADMIN_EMAIL="admin@example.com"

# Function to display and log messages
log_message() {
  local level="$1"
  local message="$2"
  local color="${NC}"
  
  case "$level" in
    "INFO")
      color="${GREEN}"
      ((INFO_FINDINGS++))
      ;;
    "WARNING")
      color="${YELLOW}"
      ((WARNING_FINDINGS++))
      ;;
    "CRITICAL")
      color="${RED}"
      ((CRITICAL_FINDINGS++))
      ;;
    "PASS")
      color="${GREEN}"
      ((PASSED_CHECKS++))
      ;;
    "FAIL")
      color="${RED}"
      ((FAILED_CHECKS++))
      ;;
  esac
  
  echo -e "${color}[${level}]${NC} $message"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $message" >> "${REPORT_FILE}"
}

# Display usage information
display_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Perform security audit on the VPN solution.

Options:
  --report-only         Only generate report without sending alerts
  --email EMAIL         Email to send report to (default: ${ADMIN_EMAIL})
  --help                Display this help message

Example:
  $(basename "$0") --email admin@yoursite.com
EOF
}

# Parse command line arguments
REPORT_ONLY=false
parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --report-only)
        REPORT_ONLY=true
        ;;
      --email)
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
          log_message "WARNING" "--email requires an email address"
          exit 1
        fi
        ADMIN_EMAIL="$2"
        shift
        ;;
      --help)
        display_usage
        exit 0
        ;;
      *)
        log_message "WARNING" "Unknown parameter: $1"
        ;;
    esac
    shift
  done
}

# Check firewall configuration
check_firewall() {
  log_message "INFO" "Checking firewall configuration..."
  
  # Check if UFW is installed and enabled
  if ! command -v ufw &> /dev/null; then
    log_message "CRITICAL" "UFW firewall is not installed"
    return 1
  fi
  
  if [ "$(ufw status | grep -c "Status: active")" -eq 0 ]; then
    log_message "CRITICAL" "UFW firewall is not active"
    return 1
  else
    log_message "PASS" "UFW firewall is active"
  fi
  
  # Check if SSH port is limited
  if ufw status | grep -q "22.*ALLOW.*Anywhere"; then
    log_message "WARNING" "SSH port 22 is open to all IPs"
  else
    log_message "PASS" "SSH port is properly restricted"
  fi
  
  # Check if only necessary ports are open
  local open_ports=$(ufw status | grep -v "^Status" | grep -v "(v6)" | grep ALLOW | wc -l)
  local expected_ports=5  # 22/tcp, 8388/tcp, 8388/udp, 443/tcp, 443/udp
  
  if [ "$open_ports" -gt "$expected_ports" ]; then
    log_message "WARNING" "More ports are open than expected: $open_ports (expected: $expected_ports)"
    
    # List open ports
    log_message "INFO" "Open ports:"
    ufw status | grep ALLOW | grep -v "(v6)" >> "${REPORT_FILE}"
  else
    log_message "PASS" "Only necessary ports are open"
  fi
  
  # Check if IP forwarding is enabled
  if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    log_message "CRITICAL" "IP forwarding is not enabled in sysctl.conf"
    return 1
  else
    log_message "PASS" "IP forwarding is properly configured"
  fi
  
  # Check actual forwarding status
  if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    log_message "CRITICAL" "IP forwarding is not active in the kernel"
    return 1
  fi
  
  return 0
}

# Check file permissions
check_file_permissions() {
  log_message "INFO" "Checking file permissions..."
  
  # Array of critical files that should have restricted permissions
  local critical_files=(
    "${V2RAY_DIR}/reality_keypair.txt:600"
    "${V2RAY_DIR}/users.db:600"
    "${OUTLINE_DIR}/config.json:600"
    "${OUTLINE_DIR}/access.json:600"
  )
  
  # Check each critical file
  for entry in "${critical_files[@]}"; do
    # Split the entry into file path and expected permissions
    local file_path=${entry%:*}
    local expected_perm=${entry#*:}
    
    if [ -f "$file_path" ]; then
      # Get actual permissions (in octal)
      local actual_perm=$(stat -c "%a" "$file_path")
      
      if [ "$actual_perm" -gt "$expected_perm" ]; then
        log_message "CRITICAL" "File $file_path has insecure permissions: $actual_perm (expected: $expected_perm)"
      else
        log_message "PASS" "File $file_path has proper permissions: $actual_perm"
      fi
    else
      log_message "WARNING" "File $file_path not found, skipping permission check"
    fi
  done
  
  # Check directory permissions
  local critical_dirs=(
    "${BASE_DIR}:755"
    "${V2RAY_DIR}:755"
    "${OUTLINE_DIR}:755"
    "${BASE_DIR}/backups:700"
  )
  
  for entry in "${critical_dirs[@]}"; do
    # Split the entry into directory path and expected permissions
    local dir_path=${entry%:*}
    local expected_perm=${entry#*:}
    
    if [ -d "$dir_path" ]; then
      # Get actual permissions (in octal)
      local actual_perm=$(stat -c "%a" "$dir_path")
      
      if [ "$actual_perm" -gt "$expected_perm" ]; then
        log_message "WARNING" "Directory $dir_path has loose permissions: $actual_perm (expected: $expected_perm)"
      else
        log_message "PASS" "Directory $dir_path has proper permissions: $actual_perm"
      fi
    else
      log_message "WARNING" "Directory $dir_path not found, skipping permission check"
    fi
  done
}

# Check for security updates
check_security_updates() {
  log_message "INFO" "Checking for security updates..."
  
  # Check if apt-get is available
  if ! command -v apt-get &> /dev/null; then
    log_message "WARNING" "apt-get not found, skipping security updates check"
    return
  fi
  
  # Update package index
  if ! apt-get update -qq; then
    log_message "WARNING" "Failed to update package index"
    return
  fi
  
  # Check for security updates
  local security_updates=$(apt-get --just-print upgrade | grep -c "security" || echo "0")
  
  if [ "$security_updates" -gt 0 ]; then
    log_message "CRITICAL" "There are $security_updates pending security updates"
    
    # List security updates
    log_message "INFO" "Security updates available:"
    apt-get --just-print upgrade | grep security >> "${REPORT_FILE}"
  else
    log_message "PASS" "No pending security updates found"
  fi
}

# Check Docker security
check_docker_security() {
  log_message "INFO" "Checking Docker security configuration..."
  
  # Check if Docker is running
  if ! command -v docker &> /dev/null; then
    log_message "WARNING" "Docker not found, skipping Docker security check"
    return
  fi
  
  # Check container privileges
  local privileged_containers=$(docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}}:{{.HostConfig.Privileged}}' {} | grep true | wc -l)
  
  if [ "$privileged_containers" -gt 0 ]; then
    log_message "CRITICAL" "There are $privileged_containers containers running with privileged mode"
    
    # List privileged containers
    docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}}:{{.HostConfig.Privileged}}' {} | grep true >> "${REPORT_FILE}"
  else
    log_message "PASS" "No containers running with privileged mode"
  fi
  
  # Check container capabilities
  local containers_with_extra_caps=0
  for container in $(docker ps --format "{{.Names}}"); do
    local caps=$(docker inspect --format '{{range .HostConfig.CapAdd}}{{.}} {{end}}' "$container" | grep -v "^$")
    
    if [ -n "$caps" ] && [ "$caps" != "NET_ADMIN" ]; then
      ((containers_with_extra_caps++))
      log_message "WARNING" "Container $container has extra capabilities: $caps"
    fi
  done
  
  if [ "$containers_with_extra_caps" -eq 0 ]; then
    log_message "PASS" "No containers with unexpected capabilities found"
  fi
  
  # Check container network mode
  local containers_with_host_network=$(docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}}:{{.HostConfig.NetworkMode}}' {} | grep -c "host")
  
  if [ "$containers_with_host_network" -gt 0 ]; then
    log_message "WARNING" "There are $containers_with_host_network containers using host network mode"
    
    # List containers using host network
    docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}}:{{.HostConfig.NetworkMode}}' {} | grep "host" >> "${REPORT_FILE}"
  else
    log_message "PASS" "No containers using host network mode"
  fi
}

# Check VPN configurations
check_vpn_configs() {
  log_message "INFO" "Checking VPN configurations..."
  
  # Check Outline Server config
  if [ -f "${OUTLINE_DIR}/config.json" ]; then
    # Check encryption method
    local ss_method=$(jq -r '.method' "${OUTLINE_DIR}/config.json" 2>/dev/null || echo "unknown")
    
    if [ "$ss_method" != "chacha20-ietf-poly1305" ] && [ "$ss_method" != "aes-256-gcm" ]; then
      log_message "CRITICAL" "Outline Server is using weak encryption method: $ss_method"
    else
      log_message "PASS" "Outline Server is using strong encryption: $ss_method"
    fi
    
    # Check if obfuscation is enabled
    if ! jq -e '.plugin' "${OUTLINE_DIR}/config.json" &> /dev/null; then
      log_message "WARNING" "Outline Server is not using obfuscation plugin"
    else
      log_message "PASS" "Outline Server has obfuscation enabled"
    fi
  else
    log_message "WARNING" "Outline Server config not found, skipping checks"
  fi
  
  # Check v2ray config
  if [ -f "${V2RAY_DIR}/config.json" ]; then
    # Check if Reality is enabled
    if ! jq -e '.inbounds[0].streamSettings.security == "reality"' "${V2RAY_DIR}/config.json" &> /dev/null; then
      log_message "CRITICAL" "v2ray is not using Reality protocol"
    else
      log_message "PASS" "v2ray is using Reality protocol for enhanced security"
    fi
    
    # Check if default UUID has been changed
    local default_uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "${V2RAY_DIR}/config.json" 2>/dev/null || echo "unknown")
    local default_email=$(jq -r '.inbounds[0].settings.clients[0].email' "${V2RAY_DIR}/config.json" 2>/dev/null || echo "unknown")
    
    if [ "$default_email" = "default-user" ]; then
      log_message "WARNING" "Default user has not been renamed in v2ray config"
    else
      log_message "PASS" "Default user has been renamed in v2ray config"
    fi
    
    # Check if sniffing is enabled
    if ! jq -e '.inbounds[0].sniffing.enabled' "${V2RAY_DIR}/config.json" &> /dev/null; then
      log_message "WARNING" "Traffic sniffing is not enabled in v2ray config"
    else
      log_message "PASS" "Traffic sniffing is enabled in v2ray config"
    fi
    
    # Check if Reality keypair exists
    if [ ! -f "${V2RAY_DIR}/reality_keypair.txt" ]; then
      log_message "WARNING" "Reality keypair file not found"
    else
      # Check keypair file age
      local key_age=$(( ($(date +%s) - $(stat -c %Y "${V2RAY_DIR}/reality_keypair.txt")) / (60*60*24) ))
      
      if [ "$key_age" -gt 180 ]; then
        log_message "WARNING" "Reality keypair is $key_age days old (recommended rotation: 180 days)"
      else
        log_message "PASS" "Reality keypair age is within recommended limits: $key_age days"
      fi
    fi
  else
    log_message "WARNING" "v2ray config not found, skipping checks"
  fi
}

# Check for unusual login attempts
check_login_attempts() {
  log_message "INFO" "Checking for unusual login attempts..."
  
  # Check auth.log for failed SSH attempts in the last week
  local failed_attempts=$(grep "Failed password" /var/log/auth.log 2>/dev/null | grep -c "sshd" || echo "0")
  
  if [ "$failed_attempts" -gt 20 ]; then
    log_message "WARNING" "High number of failed SSH login attempts: $failed_attempts"
    
    # Extract top IPs
    log_message "INFO" "Top IPs with failed login attempts:"
    grep "Failed password" /var/log/auth.log 2>/dev/null | grep "sshd" | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head -5 >> "${REPORT_FILE}"
  else
    log_message "PASS" "Normal number of failed SSH login attempts: $failed_attempts"
  fi
  
  # Check for successful logins
  local successful_logins=$(grep "Accepted " /var/log/auth.log 2>/dev/null | grep -c "sshd" || echo "0")
  
  log_message "INFO" "Successful SSH logins in the last week: $successful_logins"
  
  # If there are successful logins, list them
  if [ "$successful_logins" -gt 0 ]; then
    log_message "INFO" "Recent successful SSH logins:"
    grep "Accepted " /var/log/auth.log 2>/dev/null | grep "sshd" | tail -5 >> "${REPORT_FILE}"
  fi
}

# Check system health
check_system_health() {
  log_message "INFO" "Checking system health..."
  
  # Check load average
  local load_avg=$(uptime | awk -F'[a-z]:' '{ print $2}' | awk -F',' '{print $1}' | tr -d ' ')
  local cpu_cores=$(nproc)
  local load_per_core=$(echo "$load_avg / $cpu_cores" | bc -l)
  
  if (( $(echo "$load_per_core > 2.0" | bc -l) )); then
    log_message "WARNING" "High system load average: $load_avg (per core: $load_per_core)"
  else
    log_message "PASS" "Normal system load average: $load_avg (per core: $load_per_core)"
  fi
  
  # Check memory usage
  local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
  
  if (( $(echo "$mem_usage > 90" | bc -l) )); then
    log_message "WARNING" "High memory usage: ${mem_usage}%"
  else
    log_message "PASS" "Normal memory usage: ${mem_usage}%"
  fi
  
  # Check disk usage
  local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  
  if [ "$disk_usage" -gt 90 ]; then
    log_message "WARNING" "High disk usage: ${disk_usage}%"
  else
    log_message "PASS" "Normal disk usage: ${disk_usage}%"
  fi
  
  # Check for high CPU processes
  local high_cpu_processes=$(ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -6)
  log_message "INFO" "Top CPU processes:"
  echo "$high_cpu_processes" >> "${REPORT_FILE}"
}

# Generate security audit summary
generate_summary() {
  local status="PASS"
  
  if [ "$CRITICAL_FINDINGS" -gt 0 ]; then
    status="FAIL"
  elif [ "$WARNING_FINDINGS" -gt 0 ]; then
    status="WARN"
  fi
  
  # Create summary section
  cat <<EOF >> "${REPORT_FILE}"

==============================================================
SECURITY AUDIT SUMMARY
==============================================================
Overall Status: ${status}
Date: $(date '+%Y-%m-%d %H:%M:%S')
Server: $(hostname -f || hostname)
IP Address: $(hostname -I | awk '{print $1}')

Checks Passed: ${PASSED_CHECKS}
Checks Failed: ${FAILED_CHECKS}
Critical Issues: ${CRITICAL_FINDINGS}
Warning Issues: ${WARNING_FINDINGS}
Informational Items: ${INFO_FINDINGS}
==============================================================

EOF
  
  # Display summary on console
  echo ""
  echo "==============================================================
SECURITY AUDIT SUMMARY
==============================================================
Overall Status: ${status}
Critical Issues: ${CRITICAL_FINDINGS}
Warning Issues: ${WARNING_FINDINGS}
Informational Items: ${INFO_FINDINGS}
==============================================================
Full report saved to: ${REPORT_FILE}
"
  
  return 0
}

# Send the report
send_report() {
  if [ "$REPORT_ONLY" = "true" ]; then
    log_message "INFO" "Report-only mode, not sending alerts"
    return
  fi
  
  if [ "$CRITICAL_FINDINGS" -gt 0 ] || [ "$WARNING_FINDINGS" -gt 5 ]; then
    log_message "INFO" "Sending security audit report..."
    
    # Use alert.sh if available
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      local subject="Security Audit Report: $([ $CRITICAL_FINDINGS -gt 0 ] && echo "CRITICAL" || echo "WARNING")"
      local message="Security audit completed with ${CRITICAL_FINDINGS} critical and ${WARNING_FINDINGS} warning findings. See attached report for details."
      
      "${SCRIPT_DIR}/alert.sh" "$subject" "$message" "$REPORT_FILE"
    else
      # Fallback to mail command if available
      if command -v mail &> /dev/null; then
        local subject="Security Audit Report: $([ $CRITICAL_FINDINGS -gt 0 ] && echo "CRITICAL" || echo "WARNING")"
        cat "${REPORT_FILE}" | mail -s "$subject" "$ADMIN_EMAIL"
      else
        log_message "WARNING" "No alert mechanism available. Please check the report manually."
      fi
    fi
  else
    log_message "INFO" "No significant issues found, not sending alerts"
  fi
}

# Main function
main() {
  # Ensure log directory exists
  mkdir -p "${LOG_DIR}"
  
  # Initialize report file
  echo "VPN SECURITY AUDIT REPORT" > "${REPORT_FILE}"
  echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "${REPORT_FILE}"
  echo "Server: $(hostname -f || hostname)" >> "${REPORT_FILE}"
  echo "IP Address: $(hostname -I | awk '{print $1}')" >> "${REPORT_FILE}"
  echo "==============================================================
" >> "${REPORT_FILE}"
  
  # Parse command line arguments
  parse_args "$@"
  
  log_message "INFO" "Starting security audit at $(date)"
  
  # Run security checks
  check_firewall
  check_file_permissions
  check_security_updates
  check_docker_security
  check_vpn_configs
  check_login_attempts
  check_system_health
  
  # Generate summary and send report
  generate_summary
  send_report
  
  log_message "INFO" "Security audit completed at $(date)"
  
  # Return exit code based on findings
  if [ "$CRITICAL_FINDINGS" -gt 0 ]; then
    return 1
  else
    return 0
  fi
}

# Execute main function with all arguments
main "$@"