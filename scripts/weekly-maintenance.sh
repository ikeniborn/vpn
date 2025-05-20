#!/bin/bash
#
# weekly-maintenance.sh - Weekly maintenance tasks for the integrated VPN solution
# This script performs weekly maintenance including Docker image updates, system updates,
# and performance optimization.

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
LOG_DIR="${BASE_DIR}/logs"
SCRIPT_DIR="${BASE_DIR}/scripts"
METRICS_DIR="${BASE_DIR}/metrics"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Flag to track if restart is needed after updates
RESTART_NEEDED=false
# Flag to skip system updates
SKIP_SYSTEM_UPDATES=false
# Flag to skip performance optimization
SKIP_PERF_OPTIMIZATION=false
# Flag for dry run
DRY_RUN=false

# Function to display and log messages
log_message() {
  local level="$1"
  local message="$2"
  local color="${NC}"
  
  case "$level" in
    "INFO")
      color="${GREEN}"
      ;;
    "WARNING")
      color="${YELLOW}"
      ;;
    "ERROR")
      color="${RED}"
      ;;
  esac
  
  echo -e "${color}[${level}]${NC} $message"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $message" >> "${LOG_DIR}/maintenance.log"
}

# Display usage information
display_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Perform weekly maintenance tasks for the VPN solution.

Options:
  --skip-system-updates   Skip system package updates
  --skip-optimization     Skip performance optimization
  --dry-run               Show what would be done without making changes
  --help                  Display this help message

Example:
  $(basename "$0") --skip-system-updates
EOF
}

# Parse command line arguments
parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --skip-system-updates)
        SKIP_SYSTEM_UPDATES=true
        ;;
      --skip-optimization)
        SKIP_PERF_OPTIMIZATION=true
        ;;
      --dry-run)
        DRY_RUN=true
        log_message "INFO" "Performing a dry run. No changes will be made."
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

# Check required dependencies
check_dependencies() {
  log_message "INFO" "Checking dependencies..."
  
  local missing_deps=()
  
  # Check for required tools
  if ! command -v docker &> /dev/null; then
    missing_deps+=("docker")
  fi
  
  if ! command -v docker-compose &> /dev/null; then
    missing_deps+=("docker-compose")
  fi
  
  if ! command -v apt-get &> /dev/null && ! SKIP_SYSTEM_UPDATES; then
    log_message "WARNING" "apt-get not found. System updates will be skipped."
    SKIP_SYSTEM_UPDATES=true
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_message "ERROR" "Missing dependencies: ${missing_deps[*]}. Please install them and try again."
    exit 1
  fi
}

# Update Docker images
update_docker_images() {
  log_message "INFO" "Updating Docker images..."
  
  if [ "$DRY_RUN" = "true" ]; then
    log_message "INFO" "Dry run: Would pull latest Docker images"
    return
  fi
  
  # Create a backup before updating
  log_message "INFO" "Creating backup before updating..."
  if [ -f "${SCRIPT_DIR}/backup.sh" ]; then
    "${SCRIPT_DIR}/backup.sh" --retention 30 || log_message "WARNING" "Backup before update failed"
  else
    log_message "WARNING" "backup.sh not found. Skipping backup before update."
  fi
  
  # Go to the base directory
  cd "${BASE_DIR}" || { log_message "ERROR" "Failed to change to ${BASE_DIR}"; exit 1; }
  
  # Pull the latest images
  if ! docker-compose pull; then
    log_message "ERROR" "Failed to pull Docker images"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Docker Update Failed" "Failed to pull latest Docker images."
    fi
    
    return 1
  fi
  
  # Check if any images were updated
  if docker-compose pull | grep -q "Image is up to date"; then
    log_message "INFO" "All Docker images are up to date"
  else
    log_message "INFO" "Docker images updated successfully"
    RESTART_NEEDED=true
  fi
}

# Update system packages
update_system_packages() {
  if [ "$SKIP_SYSTEM_UPDATES" = "true" ]; then
    log_message "INFO" "Skipping system package updates as requested."
    return
  fi
  
  log_message "INFO" "Updating system packages..."
  
  if [ "$DRY_RUN" = "true" ]; then
    log_message "INFO" "Dry run: Would update system packages"
    return
  fi
  
  # Update package lists
  if ! apt-get update; then
    log_message "ERROR" "Failed to update package lists"
    return 1
  fi
  
  # Get list of upgradable packages
  local upgradable_packages=$(apt-get --just-print upgrade | grep -c ^Inst || echo "0")
  
  if [ "$upgradable_packages" -eq 0 ]; then
    log_message "INFO" "All system packages are up to date"
    return
  fi
  
  log_message "INFO" "Found ${upgradable_packages} upgradable packages"
  
  # Upgrade packages
  if ! DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
    log_message "ERROR" "Failed to upgrade system packages"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "System Update Failed" "Failed to upgrade system packages."
    fi
    
    return 1
  fi
  
  log_message "INFO" "System packages updated successfully"
}

# Run security audit
run_security_audit() {
  log_message "INFO" "Running security audit..."
  
  if [ "$DRY_RUN" = "true" ]; then
    log_message "INFO" "Dry run: Would run security audit"
    return
  fi
  
  # Check if security-audit.sh exists
  if [ ! -f "${SCRIPT_DIR}/security-audit.sh" ]; then
    log_message "WARNING" "security-audit.sh not found. Skipping security audit."
    return
  fi
  
  # Run security audit script
  if ! "${SCRIPT_DIR}/security-audit.sh"; then
    log_message "WARNING" "Security audit reported issues"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Security Audit Issues" "Weekly security audit reported issues. Check logs for details."
    fi
  else
    log_message "INFO" "Security audit completed successfully"
  fi
}

# Check for certificate expiry (if applicable)
check_certificates() {
  log_message "INFO" "Checking certificates..."
  
  # Check if v2ray Reality key is older than 90 days
  local keypair_file="${V2RAY_DIR}/reality_keypair.txt"
  if [ -f "$keypair_file" ]; then
    local key_age=$(( ($(date +%s) - $(stat -c %Y "$keypair_file")) / (60*60*24) ))
    
    if [ "$key_age" -gt 90 ]; then
      log_message "WARNING" "Reality keypair is ${key_age} days old (older than 90 days). Consider rotating."
      
      # Send alert using alert.sh if it exists
      if [ -f "${SCRIPT_DIR}/alert.sh" ] && [ "$DRY_RUN" != "true" ]; then
        "${SCRIPT_DIR}/alert.sh" "Key Rotation Needed" "Reality keypair is ${key_age} days old. Consider rotating for security."
      fi
    else
      log_message "INFO" "Reality keypair is ${key_age} days old (within 90-day period)"
    fi
  fi
}

# Optimize performance
optimize_performance() {
  if [ "$SKIP_PERF_OPTIMIZATION" = "true" ]; then
    log_message "INFO" "Skipping performance optimization as requested."
    return
  fi
  
  log_message "INFO" "Optimizing system performance..."
  
  if [ "$DRY_RUN" = "true" ]; then
    log_message "INFO" "Dry run: Would optimize system performance"
    return
  fi
  
  # Clean Docker resources
  log_message "INFO" "Cleaning Docker resources..."
  
  # Remove unused Docker containers, networks, and images
  if ! docker system prune -f > /dev/null; then
    log_message "WARNING" "Error during Docker cleanup"
  fi
  
  # Check and clean Docker volumes
  local unused_volumes=$(docker volume ls -qf dangling=true | wc -l)
  if [ "$unused_volumes" -gt 0 ]; then
    log_message "INFO" "Removing $unused_volumes unused Docker volumes"
    docker volume prune -f > /dev/null
  fi
  
  # Optimize kernel parameters if needed
  log_message "INFO" "Checking kernel parameters..."
  
  # Check TCP Fast Open
  if ! grep -q "net.ipv4.tcp_fastopen" /etc/sysctl.conf; then
    log_message "INFO" "Enabling TCP Fast Open for better performance"
    echo "net.ipv4.tcp_fastopen=3" | tee -a /etc/sysctl.conf > /dev/null
    RESTART_NEEDED=true
  fi
  
  # Check BBR congestion control
  if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    log_message "INFO" "Enabling BBR congestion control for better network performance"
    {
      echo "net.core.default_qdisc=fq"
      echo "net.ipv4.tcp_congestion_control=bbr"
    } | tee -a /etc/sysctl.conf > /dev/null
    RESTART_NEEDED=true
  fi
  
  # Apply sysctl changes if any were made
  sysctl -p > /dev/null
  
  # Clean up logs and metrics
  if [ -d "${METRICS_DIR}" ]; then
    log_message "INFO" "Cleaning old metrics data..."
    find "${METRICS_DIR}" -type f -name "*.log-*" -mtime +30 -delete
  fi
  
  # Create weekly performance report
  log_message "INFO" "Creating weekly performance report..."
  {
    echo "=== Weekly Performance Report ==="
    echo "Date: $(date '+%Y-%m-%d')"
    echo ""
    echo "=== System Load Averages ==="
    uptime
    echo ""
    echo "=== Memory Usage ==="
    free -h
    echo ""
    echo "=== Disk Usage ==="
    df -h /
    echo ""
    echo "=== Docker Container Stats ==="
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
    echo ""
    echo "=== Connection Statistics ==="
    netstat -ant | grep -E "8388|443" | awk '{print $6}' | sort | uniq -c
  } > "${METRICS_DIR}/weekly-performance-$(date '+%Y%m%d').txt"
}

# Restart services if needed
restart_services() {  
  if [ "$RESTART_NEEDED" != "true" ]; then
    log_message "INFO" "No restart needed"
    return
  fi
  
  if [ "$DRY_RUN" = "true" ]; then
    log_message "INFO" "Dry run: Would restart services"
    return
  }
  
  log_message "INFO" "Restarting VPN services..."
  
  # Go to the base directory
  cd "${BASE_DIR}" || { log_message "ERROR" "Failed to change to ${BASE_DIR}"; exit 1; }
  
  # Restart containers
  if ! docker-compose down; then
    log_message "ERROR" "Failed to stop containers"
    return 1
  fi
  
  if ! docker-compose up -d; then
    log_message "ERROR" "Failed to start containers"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Service Restart Failed" "Failed to restart VPN services after weekly maintenance."
    fi
    
    return 1
  fi
  
  log_message "INFO" "VPN services restarted successfully"
  
  # Verify services after restart
  sleep 5
  
  if ! docker ps | grep -q "outline-server"; then
    log_message "ERROR" "Outline Server container failed to start"
    return 1
  fi
  
  if ! docker ps | grep -q "v2ray"; then
    log_message "ERROR" "v2ray container failed to start"
    return 1
  fi
  
  log_message "INFO" "Service verification after restart: OK"
}

# Create weekly backup
create_weekly_backup() {
  log_message "INFO" "Creating weekly backup..."
  
  if [ "$DRY_RUN" = "true" ]; then
    log_message "INFO" "Dry run: Would create weekly backup"
    return
  }
  
  # Check if backup.sh exists
  if [ ! -f "${SCRIPT_DIR}/backup.sh" ]; then
    log_message "ERROR" "backup.sh script not found"
    return 1
  fi
  
  # Execute backup script with retention set to 90 days and encryption
  if ! "${SCRIPT_DIR}/backup.sh" --retention 90 --encrypt; then
    log_message "ERROR" "Weekly backup failed"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Backup Failed" "Weekly backup operation failed."
    fi
  else
    log_message "INFO" "Weekly backup completed successfully"
  fi
}

# Main function
main() {
  # Ensure log directory exists
  mkdir -p "${LOG_DIR}"
  mkdir -p "${METRICS_DIR}"
  
  # Start timestamp
  log_message "INFO" "Starting weekly maintenance at $(date)"
  
  # Parse command line arguments
  parse_args "$@"
  
  # Check dependencies
  check_dependencies
  
  # Run maintenance tasks
  update_docker_images
  update_system_packages
  run_security_audit
  check_certificates
  optimize_performance
  restart_services
  create_weekly_backup
  
  # End timestamp
  log_message "INFO" "Weekly maintenance completed at $(date)"
}

# Run main function
main "$@"