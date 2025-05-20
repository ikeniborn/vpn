#!/bin/bash
#
# monitoring.sh - Health and performance monitoring for the integrated VPN solution
# This script checks the health of both Shadowsocks and VLESS+Reality components
# and provides performance metrics and alerts.

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
LOG_DIR="${BASE_DIR}/logs"
METRICS_DIR="${BASE_DIR}/metrics"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Thresholds for alerts
CPU_THRESHOLD=80  # CPU usage percentage
MEM_THRESHOLD=80  # Memory usage percentage
DISK_THRESHOLD=80 # Disk usage percentage
CONN_THRESHOLD=500 # Connection count

# Email for alerts
# Default value that will be overridden by environment variable or command line argument
ALERT_EMAIL="${VPN_ADMIN_EMAIL:-admin@yourdomain.com}"

# Allow overriding via command line
for arg in "$@"; do
  case $arg in
    --email=*)
      ALERT_EMAIL="${arg#*=}"
      shift
      ;;
  esac
done

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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $message" >> "${LOG_DIR}/monitoring.log"
}

# Check if Docker and services are running
check_services() {
  log_message "INFO" "Checking Docker services..."
  
  # Check Docker service
  if ! systemctl is-active --quiet docker; then
    log_message "ERROR" "Docker service is not running"
    send_alert "Docker Service Down" "Docker service is not running on $(hostname)"
    return 1
  fi
  
  # Check Outline Server container
  if ! docker ps | grep -q "outline-server"; then
    log_message "ERROR" "Outline Server container is not running"
    send_alert "Outline Server Down" "Outline Server container is not running on $(hostname)"
    return 1
  fi
  
  # Check v2ray container
  if ! docker ps | grep -q "v2ray"; then
    log_message "ERROR" "v2ray container is not running"
    send_alert "v2ray Server Down" "v2ray container is not running on $(hostname)"
    return 1
  fi
  
  log_message "INFO" "All services are running"
  return 0
}

# Check system resources
check_resources() {
  log_message "INFO" "Checking system resources..."
  
  # Create metrics directory if it doesn't exist
  mkdir -p "${METRICS_DIR}"
  
  # CPU usage
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
  echo "CPU Usage: ${cpu_usage}%" >> "${METRICS_DIR}/system_metrics.log"
  
  if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
    log_message "WARNING" "High CPU usage: ${cpu_usage}%"
    send_alert "High CPU Usage" "CPU usage is at ${cpu_usage}%, which exceeds the threshold of ${CPU_THRESHOLD}%."
  fi
  
  # Memory usage
  local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
  echo "Memory Usage: ${mem_usage}%" >> "${METRICS_DIR}/system_metrics.log"
  
  if (( $(echo "$mem_usage > $MEM_THRESHOLD" | bc -l) )); then
    log_message "WARNING" "High memory usage: ${mem_usage}%"
    send_alert "High Memory Usage" "Memory usage is at ${mem_usage}%, which exceeds the threshold of ${MEM_THRESHOLD}%."
  fi
  
  # Disk usage
  local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  echo "Disk Usage: ${disk_usage}%" >> "${METRICS_DIR}/system_metrics.log"
  
  if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
    log_message "WARNING" "High disk usage: ${disk_usage}%"
    send_alert "High Disk Usage" "Disk usage is at ${disk_usage}%, which exceeds the threshold of ${DISK_THRESHOLD}%."
  fi
  
  # Log container resource usage
  echo "Container Resource Usage ($(date)):" >> "${METRICS_DIR}/container_metrics.log"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" >> "${METRICS_DIR}/container_metrics.log"
}

# Check network connections
check_connections() {
  log_message "INFO" "Checking network connections..."
  
  # Get connection count for Outline Server
  local outline_conns=$(docker exec outline-server sh -c "netstat -an | grep -c ESTABLISHED" 2>/dev/null || echo "0")
  echo "Outline Server Connections: ${outline_conns}" >> "${METRICS_DIR}/network_metrics.log"
  
  # Get connection count for v2ray
  local v2ray_conns=$(docker exec v2ray sh -c "netstat -an | grep -c ESTABLISHED" 2>/dev/null || echo "0")
  echo "v2ray Connections: ${v2ray_conns}" >> "${METRICS_DIR}/network_metrics.log"
  
  # Total connections
  local total_conns=$((outline_conns + v2ray_conns))
  
  if [ "$total_conns" -gt "$CONN_THRESHOLD" ]; then
    log_message "WARNING" "High connection count: ${total_conns}"
    send_alert "High Connection Count" "Total connection count is ${total_conns}, which exceeds the threshold of ${CONN_THRESHOLD}."
  fi
  
  # Log connection statistics
  echo "Connection Statistics ($(date)):" >> "${METRICS_DIR}/connection_stats.log"
  echo "Total active connections: ${total_conns}" >> "${METRICS_DIR}/connection_stats.log"
  echo "Outline Server connections: ${outline_conns}" >> "${METRICS_DIR}/connection_stats.log"
  echo "v2ray connections: ${v2ray_conns}" >> "${METRICS_DIR}/connection_stats.log"
}

# Check logs for errors
check_logs() {
  log_message "INFO" "Checking service logs for errors..."
  
  # Check Outline Server logs
  local outline_errors=$(grep -c "ERROR\|FATAL\|CRITICAL" "${LOG_DIR}/outline/shadowsocks.log" 2>/dev/null || echo "0")
  echo "Outline Server Errors: ${outline_errors}" >> "${METRICS_DIR}/error_metrics.log"
  
  # Check v2ray logs
  local v2ray_errors=$(grep -c "error\|fatal\|critical" "${LOG_DIR}/v2ray/error.log" 2>/dev/null || echo "0")
  echo "v2ray Errors: ${v2ray_errors}" >> "${METRICS_DIR}/error_metrics.log"
  
  if [ "$outline_errors" -gt 0 ] || [ "$v2ray_errors" -gt 0 ]; then
    log_message "WARNING" "Errors found in service logs"
    send_alert "Service Log Errors" "Found ${outline_errors} errors in Outline Server logs and ${v2ray_errors} errors in v2ray logs."
  fi
  
  # Extract recent errors for review
  if [ "$outline_errors" -gt 0 ]; then
    log_message "INFO" "Recent Outline Server errors:"
    grep -n "ERROR\|FATAL\|CRITICAL" "${LOG_DIR}/outline/shadowsocks.log" 2>/dev/null | tail -5
  fi
  
  if [ "$v2ray_errors" -gt 0 ]; then
    log_message "INFO" "Recent v2ray errors:"
    grep -n "error\|fatal\|critical" "${LOG_DIR}/v2ray/error.log" 2>/dev/null | tail -5
  fi
}

# Perform health check
health_check() {
  # Check if outbound connections are working
  log_message "INFO" "Performing health check..."
  
  # Test Internet connectivity
  if ! ping -c 1 8.8.8.8 &>/dev/null; then
    log_message "ERROR" "Internet connectivity test failed"
    send_alert "Internet Connectivity Issue" "Server cannot reach the internet. Ping to 8.8.8.8 failed."
    return 1
  fi
  
  # Test DNS resolution
  if ! nslookup google.com &>/dev/null; then
    log_message "WARNING" "DNS resolution test failed"
    send_alert "DNS Resolution Issue" "Server cannot resolve domain names. nslookup to google.com failed."
  fi
  
  # Get Outline Server port
  local outline_port=$(jq -r '.server_port' "${OUTLINE_DIR}/config.json" 2>/dev/null || echo "8388")
  
  # Get v2ray port
  local v2ray_port=$(jq -r '.inbounds[0].port' "${V2RAY_DIR}/config.json" 2>/dev/null || echo "443")
  
  # Check if ports are listening
  if ! netstat -tuln | grep -q ":${outline_port}"; then
    log_message "ERROR" "Outline Server port ${outline_port} not listening"
    send_alert "Port Not Listening" "Outline Server port ${outline_port} is not listening."
    return 1
  fi
  
  if ! netstat -tuln | grep -q ":${v2ray_port}"; then
    log_message "ERROR" "v2ray port ${v2ray_port} not listening"
    send_alert "Port Not Listening" "v2ray port ${v2ray_port} is not listening."
    return 1
  fi
  
  # Test connectivity to external sites via curl with timeout
  local test_urls=(
    "https://www.google.com"
    "https://www.cloudflare.com"
    "https://www.microsoft.com"
  )
  
  local conn_failures=0
  for url in "${test_urls[@]}"; do
    if ! curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$url" | grep -q "^[23]"; then
      log_message "WARNING" "Connection test to $url failed"
      ((conn_failures++))
    fi
  done
  
  if [ "$conn_failures" -gt 1 ]; then
    log_message "ERROR" "Multiple external connectivity tests failed"
    send_alert "External Connectivity Issue" "${conn_failures} out of ${#test_urls[@]} external connectivity tests failed."
    return 1
  fi
  
  log_message "INFO" "Health check passed"
  return 0
}

# Send alert (customize this function based on your alert mechanism)
send_alert() {
  local subject="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local server_info=$(hostname -f || hostname)
  local ip_info=$(hostname -I | awk '{print $1}')
  
  log_message "WARNING" "Sending alert: $subject"
  
  # Log the alert to the alerts log file
  mkdir -p "${LOG_DIR}"
  echo "[${timestamp}] ALERT: ${subject}" >> "${LOG_DIR}/alerts.log"
  echo "  Message: ${message}" >> "${LOG_DIR}/alerts.log"
  echo "  Server: ${server_info} (${ip_info})" >> "${LOG_DIR}/alerts.log"
  
  # Send alert email if mailutils is installed
  if command -v mail &> /dev/null; then
    echo -e "${message}\n\nTimestamp: ${timestamp}\nServer: ${server_info} (${ip_info})" | mail -s "VPN Alert: ${subject}" "$ALERT_EMAIL"
  else
    log_message "WARNING" "mail command not found. Install mailutils to enable email alerts."
  fi
  
  # Call the alert.sh script if it exists
  if [ -f "${BASE_DIR}/scripts/alert.sh" ]; then
    "${BASE_DIR}/scripts/alert.sh" "$subject" "$message" || true
  fi
}

# Rotate logs
rotate_logs() {
  log_message "INFO" "Rotating logs..."
  
  # Create timestamp for backup
  local timestamp=$(date '+%Y%m%d-%H%M%S')
  
  # Function to rotate a log file if it's larger than 1MB
  rotate_log_file() {
    local file_path="$1"
    local max_size="${2:-1048576}"  # Default to 1MB
    
    if [ -f "$file_path" ] && [ $(stat -c%s "$file_path" 2>/dev/null || echo "0") -gt "$max_size" ]; then
      # Create directory for rotated logs
      local rotated_dir="${METRICS_DIR}/rotated"
      mkdir -p "$rotated_dir"
      
      # Get base filename
      local base_filename=$(basename "$file_path")
      
      # Move and compress the log file
      gzip -c "$file_path" > "${rotated_dir}/${base_filename}-${timestamp}.gz"
      
      # Clear the original file
      : > "$file_path"
      
      log_message "INFO" "Rotated log file: $file_path"
    fi
  }
  
  # Rotate various log files
  rotate_log_file "${METRICS_DIR}/system_metrics.log"
  rotate_log_file "${METRICS_DIR}/network_metrics.log"
  rotate_log_file "${METRICS_DIR}/error_metrics.log"
  rotate_log_file "${METRICS_DIR}/container_metrics.log"
  rotate_log_file "${METRICS_DIR}/connection_stats.log"
  rotate_log_file "${LOG_DIR}/monitoring.log" 5242880  # 5MB for main monitoring log
  
  # Clean up old logs (older than 30 days)
  find "${METRICS_DIR}/rotated" -name "*.gz" -type f -mtime +30 -delete
  log_message "INFO" "Cleaned up logs older than 30 days"
}

# Check Docker container stats
check_container_stats() {
  log_message "INFO" "Checking container statistics..."
  
  # Get container stats
  local outline_stats=$(docker stats outline-server --no-stream --format "{{.CPUPerc}}|{{.MemPerc}}" 2>/dev/null || echo "0%|0%")
  local v2ray_stats=$(docker stats v2ray --no-stream --format "{{.CPUPerc}}|{{.MemPerc}}" 2>/dev/null || echo "0%|0%")
  
  # Parse stats
  local outline_cpu=$(echo "$outline_stats" | cut -d'|' -f1 | tr -d '%')
  local outline_mem=$(echo "$outline_stats" | cut -d'|' -f2 | tr -d '%')
  local v2ray_cpu=$(echo "$v2ray_stats" | cut -d'|' -f1 | tr -d '%')
  local v2ray_mem=$(echo "$v2ray_stats" | cut -d'|' -f2 | tr -d '%')
  
  # Log stats
  echo "Outline Server: CPU ${outline_cpu}%, Memory ${outline_mem}%" >> "${METRICS_DIR}/container_metrics.log"
  echo "v2ray: CPU ${v2ray_cpu}%, Memory ${v2ray_mem}%" >> "${METRICS_DIR}/container_metrics.log"
  
  # Check if any container is using excessive resources
  if (( $(echo "$outline_cpu > 90" | bc -l 2>/dev/null || echo "0") )); then
    log_message "WARNING" "Outline Server high CPU usage: ${outline_cpu}%"
    send_alert "Container High CPU" "Outline Server CPU usage is at ${outline_cpu}%"
  fi
  
  if (( $(echo "$outline_mem > 90" | bc -l 2>/dev/null || echo "0") )); then
    log_message "WARNING" "Outline Server high memory usage: ${outline_mem}%"
    send_alert "Container High Memory" "Outline Server memory usage is at ${outline_mem}%"
  fi
  
  if (( $(echo "$v2ray_cpu > 90" | bc -l 2>/dev/null || echo "0") )); then
    log_message "WARNING" "v2ray high CPU usage: ${v2ray_cpu}%"
    send_alert "Container High CPU" "v2ray CPU usage is at ${v2ray_cpu}%"
  fi
  
  if (( $(echo "$v2ray_mem > 90" | bc -l 2>/dev/null || echo "0") )); then
    log_message "WARNING" "v2ray high memory usage: ${v2ray_mem}%"
    send_alert "Container High Memory" "v2ray memory usage is at ${v2ray_mem}%"
  fi
}

# Collect service status summary
collect_status_summary() {
  log_message "INFO" "Collecting service status summary..."
  
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local status_file="${METRICS_DIR}/status_summary.log"
  
  # Ensure the directory exists
  mkdir -p "${METRICS_DIR}"
  
  # Create a new status summary
  {
    echo "========================================"
    echo "VPN Service Status Summary"
    echo "Timestamp: ${timestamp}"
    echo "Server: $(hostname -f || hostname) ($(hostname -I | awk '{print $1}'))"
    echo "========================================"
    echo ""
    
    echo "=== Service Status ==="
    echo "Docker service: $(systemctl is-active docker)"
    echo "Outline Server: $(docker ps --format '{{.Status}}' -f name=outline-server 2>/dev/null || echo "Not running")"
    echo "v2ray: $(docker ps --format '{{.Status}}' -f name=v2ray 2>/dev/null || echo "Not running")"
    echo ""
    
    echo "=== Resource Usage ==="
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
    echo "Memory Usage: $(free | grep Mem | awk '{print $3/$2 * 100.0}')%"
    echo "Disk Usage: $(df -h / | awk 'NR==2 {print $5}')"
    echo ""
    
    echo "=== Connection Statistics ==="
    local outline_conns=$(docker exec outline-server sh -c "netstat -an | grep -c ESTABLISHED" 2>/dev/null || echo "0")
    local v2ray_conns=$(docker exec v2ray sh -c "netstat -an | grep -c ESTABLISHED" 2>/dev/null || echo "0")
    echo "Total active connections: $((outline_conns + v2ray_conns))"
    echo "Outline Server connections: ${outline_conns}"
    echo "v2ray connections: ${v2ray_conns}"
    echo ""
    
    echo "=== Port Status ==="
    local outline_port=$(jq -r '.server_port' "${OUTLINE_DIR}/config.json" 2>/dev/null || echo "8388")
    local v2ray_port=$(jq -r '.inbounds[0].port' "${V2RAY_DIR}/config.json" 2>/dev/null || echo "443")
    echo "Outline Server port (${outline_port}): $(netstat -tuln | grep -q ":${outline_port}" && echo "LISTENING" || echo "NOT LISTENING")"
    echo "v2ray port (${v2ray_port}): $(netstat -tuln | grep -q ":${v2ray_port}" && echo "LISTENING" || echo "NOT LISTENING")"
    echo ""
    
    echo "=== Recent Errors ==="
    echo "Outline Server errors (last 24h): $(grep -c "ERROR\|FATAL\|CRITICAL" "${LOG_DIR}/outline/shadowsocks.log" 2>/dev/null || echo "0")"
    echo "v2ray errors (last 24h): $(grep -c "error\|fatal\|critical" "${LOG_DIR}/v2ray/error.log" 2>/dev/null || echo "0")"
    echo ""
    
    echo "=== Last 5 Alerts ==="
    tail -5 "${LOG_DIR}/alerts.log" 2>/dev/null || echo "No alerts found"
    echo ""
    
    echo "========================================"
  } > "$status_file"
  
  log_message "INFO" "Status summary saved to ${status_file}"
}

# Main function
main() {
  # Create directories if they don't exist
  mkdir -p "${LOG_DIR}"
  mkdir -p "${METRICS_DIR}"
  
  # Start timestamp
  log_message "INFO" "Starting monitoring at $(date)"
  
  # Run checks
  check_services
  check_resources
  check_container_stats
  check_connections
  check_logs
  health_check
  collect_status_summary
  rotate_logs
  
  # End timestamp
  log_message "INFO" "Monitoring completed at $(date)"
}

# Run main function
main