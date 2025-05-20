#!/bin/bash
#
# daily-maintenance.sh - Daily maintenance tasks for the integrated VPN solution
# This script performs routine daily maintenance tasks like log rotation, 
# disk space checks, and basic service health verification.

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
LOG_DIR="${BASE_DIR}/logs"
METRICS_DIR="${BASE_DIR}/metrics"
SCRIPT_DIR="${BASE_DIR}/scripts"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Thresholds
DISK_THRESHOLD=90  # Disk usage percentage warning threshold
LOG_SIZE_THRESHOLD=10485760  # 10MB - Log file size threshold for rotation

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

# Rotate logs
rotate_logs() {
  log_message "INFO" "Rotating logs..."
  
  # Function to rotate a log file if it's larger than threshold
  rotate_log_file() {
    local file_path="$1"
    
    if [ -f "$file_path" ] && [ $(stat -c%s "$file_path" 2>/dev/null || echo "0") -gt "$LOG_SIZE_THRESHOLD" ]; then
      local timestamp=$(date '+%Y%m%d')
      local base_filename=$(basename "$file_path")
      local dir_name=$(dirname "$file_path")
      
      # Create archive directory
      mkdir -p "${dir_name}/archive"
      
      # Compress the log file
      gzip -c "$file_path" > "${dir_name}/archive/${base_filename}-${timestamp}.gz"
      
      # Clear the original file
      : > "$file_path"
      
      log_message "INFO" "Rotated log file: $file_path"
    fi
  }
  
  # Rotate various log files
  rotate_log_file "${LOG_DIR}/monitoring.log"
  rotate_log_file "${LOG_DIR}/maintenance.log"
  rotate_log_file "${LOG_DIR}/backup.log"
  rotate_log_file "${LOG_DIR}/restore.log"
  rotate_log_file "${LOG_DIR}/alerts.log"
  
  # Rotate Docker container logs
  if [ -d "${LOG_DIR}/outline" ]; then
    find "${LOG_DIR}/outline" -type f -name "*.log" | while read -r logfile; do
      rotate_log_file "$logfile"
    done
  fi
  
  if [ -d "${LOG_DIR}/v2ray" ]; then
    find "${LOG_DIR}/v2ray" -type f -name "*.log" | while read -r logfile; do
      rotate_log_file "$logfile"
    done
  fi
  
  # Delete log archives older than 30 days
  find "${LOG_DIR}" -path "*/archive/*" -type f -mtime +30 -delete
  
  log_message "INFO" "Log rotation completed"
}

# Check disk space
check_disk_space() {
  log_message "INFO" "Checking disk space..."
  
  # Check disk usage for the root directory
  local root_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  
  # Check disk usage for the VPN directory if it's on a separate partition
  local vpn_usage=$(df -h "$BASE_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
  
  # Log the disk usage
  log_message "INFO" "Root directory disk usage: ${root_usage}%"
  log_message "INFO" "VPN directory disk usage: ${vpn_usage}%"
  
  # Check if disk usage exceeds threshold
  if [ "$root_usage" -gt "$DISK_THRESHOLD" ]; then
    log_message "WARNING" "Root directory disk usage is high: ${root_usage}%"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Disk Space Warning" "Root directory disk usage is at ${root_usage}%, which exceeds the threshold of ${DISK_THRESHOLD}%."
    fi
  fi
  
  if [ "$vpn_usage" -gt "$DISK_THRESHOLD" ]; then
    log_message "WARNING" "VPN directory disk usage is high: ${vpn_usage}%"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Disk Space Warning" "VPN directory disk usage is at ${vpn_usage}%, which exceeds the threshold of ${DISK_THRESHOLD}%."
    fi
  fi
  
  # Clean old metrics files
  if [ -d "${METRICS_DIR}" ]; then
    log_message "INFO" "Cleaning old metrics files..."
    find "${METRICS_DIR}" -type f -name "*.log" -mtime +7 -delete
  fi
}

# Verify service health
verify_service_health() {
  log_message "INFO" "Verifying service health..."
  
  # Check Docker service
  if ! systemctl is-active --quiet docker; then
    log_message "ERROR" "Docker service is not running"
    
    # Try to restart Docker
    log_message "INFO" "Attempting to restart Docker service..."
    if ! systemctl restart docker; then
      log_message "ERROR" "Failed to restart Docker service"
      
      # Send alert using alert.sh if it exists
      if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
        "${SCRIPT_DIR}/alert.sh" "Docker Service Down" "Docker service is not running and could not be restarted."
      fi
    else
      log_message "INFO" "Docker service restarted successfully"
    fi
  fi
  
  # Wait for Docker to start (if it was restarted)
  sleep 5
  
  # Check if containers are running
  if ! docker ps | grep -q "outline-server"; then
    log_message "WARNING" "Outline Server container is not running"
    
    # Try to restart the container
    log_message "INFO" "Attempting to restart Outline Server container..."
    if ! docker start outline-server; then
      log_message "ERROR" "Failed to restart Outline Server container"
      
      # Send alert using alert.sh if it exists
      if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
        "${SCRIPT_DIR}/alert.sh" "Container Down" "Outline Server container is not running and could not be restarted."
      fi
    else
      log_message "INFO" "Outline Server container restarted successfully"
    fi
  fi
  
  if ! docker ps | grep -q "v2ray"; then
    log_message "WARNING" "v2ray container is not running"
    
    # Try to restart the container
    log_message "INFO" "Attempting to restart v2ray container..."
    if ! docker start v2ray; then
      log_message "ERROR" "Failed to restart v2ray container"
      
      # Send alert using alert.sh if it exists
      if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
        "${SCRIPT_DIR}/alert.sh" "Container Down" "v2ray container is not running and could not be restarted."
      fi
    else
      log_message "INFO" "v2ray container restarted successfully"
    fi
  fi
  
  # Check if ports are listening
  local outline_port=$(jq -r '.server_port' "${OUTLINE_DIR}/config.json" 2>/dev/null || echo "8388")
  local v2ray_port=$(jq -r '.inbounds[0].port' "${V2RAY_DIR}/config.json" 2>/dev/null || echo "443")
  
  if ! netstat -tuln | grep -q ":${outline_port}"; then
    log_message "WARNING" "Outline Server port ${outline_port} is not listening"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Port Not Listening" "Outline Server port ${outline_port} is not listening despite container being active."
    fi
  fi
  
  if ! netstat -tuln | grep -q ":${v2ray_port}"; then
    log_message "WARNING" "v2ray port ${v2ray_port} is not listening"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Port Not Listening" "v2ray port ${v2ray_port} is not listening despite container being active."
    fi
  fi
}

# Check for service errors
check_service_errors() {
  log_message "INFO" "Checking for service errors..."
  
  # Check for errors in container logs since midnight
  local today_date=$(date '+%Y-%m-%d')
  local midnight_timestamp=$(date -d "${today_date} 00:00:00" '+%s')
  
  # Function to check for errors in a container
  check_container_errors() {
    local container_name="$1"
    local error_count=0
    
    # Get logs since midnight
    local container_logs=$(docker logs --since "@${midnight_timestamp}" "$container_name" 2>&1)
    
    # Check for error patterns
    error_count=$(echo "$container_logs" | grep -c -i "error\|fail\|exception\|fatal" || echo "0")
    
    if [ "$error_count" -gt 0 ]; then
      log_message "WARNING" "Found $error_count errors in $container_name logs since midnight"
      
      # Extract the most recent errors
      local recent_errors=$(echo "$container_logs" | grep -i "error\|fail\|exception\|fatal" | tail -5)
      log_message "INFO" "Recent errors from $container_name:"
      echo "$recent_errors" >> "${LOG_DIR}/maintenance.log"
      
      # Send alert using alert.sh if it exists
      if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
        "${SCRIPT_DIR}/alert.sh" "Service Errors" "Found $error_count errors in $container_name logs since midnight."
      fi
    else
      log_message "INFO" "No errors found in $container_name logs since midnight"
    fi
  }
  
  # Check both containers
  check_container_errors "outline-server"
  check_container_errors "v2ray"
}

# Create daily backup
create_daily_backup() {
  log_message "INFO" "Creating daily backup..."
  
  # Check if backup.sh exists
  if [ ! -f "${SCRIPT_DIR}/backup.sh" ]; then
    log_message "ERROR" "backup.sh script not found"
    return 1
  fi
  
  # Execute backup script with retention set to 7 days
  if ! "${SCRIPT_DIR}/backup.sh" --retention 7; then
    log_message "ERROR" "Daily backup failed"
    
    # Send alert using alert.sh if it exists
    if [ -f "${SCRIPT_DIR}/alert.sh" ]; then
      "${SCRIPT_DIR}/alert.sh" "Backup Failed" "Daily backup operation failed."
    fi
  else
    log_message "INFO" "Daily backup completed successfully"
  fi
}

# Main function
main() {
  # Ensure log directory exists
  mkdir -p "${LOG_DIR}"
  
  # Start timestamp
  log_message "INFO" "Starting daily maintenance at $(date)"
  
  # Run maintenance tasks
  rotate_logs
  check_disk_space
  verify_service_health
  check_service_errors
  create_daily_backup
  
  # End timestamp
  log_message "INFO" "Daily maintenance completed at $(date)"
}

# Run main function
main