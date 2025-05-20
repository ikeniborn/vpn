# VPN Monitoring and Maintenance

This document outlines the monitoring, health checks, and maintenance procedures for the integrated Shadowsocks/Outline Server and VLESS+Reality VPN solution.

## System Monitoring

### Monitoring Script

```bash
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

# Email for alerts (change to your email)
ALERT_EMAIL="admin@example.com"

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
    return 1
  fi
  
  # Check Outline Server container
  if ! docker ps | grep -q "outline-server"; then
    log_message "ERROR" "Outline Server container is not running"
    return 1
  fi
  
  # Check v2ray container
  if ! docker ps | grep -q "v2ray"; then
    log_message "ERROR" "v2ray container is not running"
    return 1
  }
  
  log_message "INFO" "All services are running"
  return 0
}

# Check system resources
check_resources() {
  log_message "INFO" "Checking system resources..."
  
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
}

# Check network connections
check_connections() {
  log_message "INFO" "Checking network connections..."
  
  # Get connection count for Outline Server
  local outline_conns=$(docker exec outline-server ss -tn | grep -c "ESTAB")
  echo "Outline Server Connections: ${outline_conns}" >> "${METRICS_DIR}/network_metrics.log"
  
  # Get connection count for v2ray
  local v2ray_conns=$(docker exec v2ray ss -tn | grep -c "ESTAB")
  echo "v2ray Connections: ${v2ray_conns}" >> "${METRICS_DIR}/network_metrics.log"
  
  # Total connections
  local total_conns=$((outline_conns + v2ray_conns))
  
  if [ "$total_conns" -gt "$CONN_THRESHOLD" ]; then
    log_message "WARNING" "High connection count: ${total_conns}"
    send_alert "High Connection Count" "Total connection count is ${total_conns}, which exceeds the threshold of ${CONN_THRESHOLD}."
  fi
}

# Check logs for errors
check_logs() {
  log_message "INFO" "Checking service logs for errors..."
  
  # Check Outline Server logs
  local outline_errors=$(grep -c "ERROR" "${LOG_DIR}/outline/shadowsocks.log" 2>/dev/null || echo "0")
  echo "Outline Server Errors: ${outline_errors}" >> "${METRICS_DIR}/error_metrics.log"
  
  # Check v2ray logs
  local v2ray_errors=$(grep -c "error" "${LOG_DIR}/v2ray/error.log" 2>/dev/null || echo "0")
  echo "v2ray Errors: ${v2ray_errors}" >> "${METRICS_DIR}/error_metrics.log"
  
  if [ "$outline_errors" -gt 0 ] || [ "$v2ray_errors" -gt 0 ]; then
    log_message "WARNING" "Errors found in service logs"
    send_alert "Service Log Errors" "Found ${outline_errors} errors in Outline Server logs and ${v2ray_errors} errors in v2ray logs."
  fi
}

# Perform health check
health_check() {
  # Check if outbound connections are working
  log_message "INFO" "Performing health check..."
  
  # Test Internet connectivity
  if ! ping -c 1 8.8.8.8 &>/dev/null; then
    log_message "ERROR" "Internet connectivity test failed"
    return 1
  fi
  
  # Test DNS resolution
  if ! nslookup google.com &>/dev/null; then
    log_message "WARNING" "DNS resolution test failed"
  fi
  
  # Check if ports are listening
  if ! netstat -tuln | grep -q ":8388"; then
    log_message "ERROR" "Outline Server port not listening"
    return 1
  fi
  
  if ! netstat -tuln | grep -q ":443"; then
    log_message "ERROR" "v2ray port not listening"
    return 1
  }
  
  log_message "INFO" "Health check passed"
  return 0
}

# Send alert (customize this function based on your alert mechanism)
send_alert() {
  local subject="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  log_message "WARNING" "Sending alert: $subject"
  
  # Using mail command (make sure mailutils is installed)
  echo -e "${message}\n\nTimestamp: ${timestamp}\nServer: $(hostname)" | mail -s "VPN Alert: ${subject}" "$ALERT_EMAIL"
  
  # Alternatively, you could use a webhook, SMS service, etc.
}

# Rotate logs
rotate_logs() {
  log_message "INFO" "Rotating logs..."
  
  # Create timestamp for backup
  local timestamp=$(date '+%Y%m%d-%H%M%S')
  
  # Rotate system metrics log if it exists and is larger than 1MB
  if [ -f "${METRICS_DIR}/system_metrics.log" ] && [ $(stat -c%s "${METRICS_DIR}/system_metrics.log") -gt 1048576 ]; then
    mv "${METRICS_DIR}/system_metrics.log" "${METRICS_DIR}/system_metrics-${timestamp}.log"
    log_message "INFO" "Rotated system metrics log"
  fi
  
  # Rotate network metrics log if it exists and is larger than 1MB
  if [ -f "${METRICS_DIR}/network_metrics.log" ] && [ $(stat -c%s "${METRICS_DIR}/network_metrics.log") -gt 1048576 ]; then
    mv "${METRICS_DIR}/network_metrics.log" "${METRICS_DIR}/network_metrics-${timestamp}.log"
    log_message "INFO" "Rotated network metrics log"
  fi
  
  # Rotate error metrics log if it exists and is larger than 1MB
  if [ -f "${METRICS_DIR}/error_metrics.log" ] && [ $(stat -c%s "${METRICS_DIR}/error_metrics.log") -gt 1048576 ]; then
    mv "${METRICS_DIR}/error_metrics.log" "${METRICS_DIR}/error_metrics-${timestamp}.log"
    log_message "INFO" "Rotated error metrics log"
  fi
  
  # Clean up old logs (older than 30 days)
  find "${METRICS_DIR}" -name "*.log" -type f -mtime +30 -delete
  log_message "INFO" "Cleaned up old logs"
}

# Main function
main() {
  # Create metrics directory if it doesn't exist
  mkdir -p "${METRICS_DIR}"
  
  # Start timestamp
  log_message "INFO" "Starting monitoring at $(date)"
  
  # Run checks
  check_services
  check_resources
  check_connections
  check_logs
  health_check
  rotate_logs
  
  # End timestamp
  log_message "INFO" "Monitoring completed at $(date)"
}

# Run main function
main
```

## Regular Maintenance Tasks

### Daily Maintenance

1. **Log Review**:
   - Review monitoring logs for errors or warnings
   - Check system resource usage patterns
   - Verify connection counts and patterns

2. **Backup Configuration**:
   - Create daily backup of critical configuration files

   ```bash
   #!/bin/bash
   # daily-backup.sh
   BACKUP_DIR="/opt/vpn/backups"
   DATE=$(date '+%Y%m%d')
   mkdir -p "$BACKUP_DIR/$DATE"
   
   # Backup configuration files
   cp -r /opt/vpn/outline-server/config.json "$BACKUP_DIR/$DATE/"
   cp -r /opt/vpn/v2ray/config.json "$BACKUP_DIR/$DATE/"
   cp -r /opt/vpn/v2ray/users.db "$BACKUP_DIR/$DATE/"
   
   # Compress backup
   tar -czf "$BACKUP_DIR/vpn-config-$DATE.tar.gz" -C "$BACKUP_DIR" "$DATE"
   rm -rf "$BACKUP_DIR/$DATE"
   
   # Clean up old backups (older than 7 days)
   find "$BACKUP_DIR" -name "vpn-config-*.tar.gz" -type f -mtime +7 -delete
   ```

### Weekly Maintenance

1. **Security Updates**:
   - Update Docker images to the latest versions
   - Apply system updates

   ```bash
   #!/bin/bash
   # weekly-update.sh
   
   # Update system packages
   apt-get update && apt-get upgrade -y
   
   # Update Docker images
   cd /opt/vpn
   docker-compose pull
   docker-compose up -d
   
   # Verify services are running
   sleep 5
   docker-compose ps
   ```

2. **Performance Optimization**:
   - Check and optimize routing rules
   - Review connection patterns and adjust routing as needed

3. **Configuration Review**:
   - Verify Reality settings are up-to-date
   - Check if the mimicked site (e.g., Microsoft.com) has changed its TLS configuration

### Monthly Maintenance

1. **Security Audit**:
   - Run security audit on the server
   - Check for unauthorized access attempts
   - Verify firewall rules

   ```bash
   #!/bin/bash
   # monthly-security-audit.sh
   
   # Check for failed SSH login attempts
   echo "Failed SSH login attempts:"
   grep "Failed password" /var/log/auth.log | grep sshd
   
   # Check for unusual open ports
   echo "Open ports:"
   netstat -tuln
   
   # Check UFW status
   echo "Firewall status:"
   ufw status
   
   # Check Docker security
   echo "Docker container privileges:"
   docker ps --format "{{.Names}}" | xargs -I{} docker inspect --format '{{.Name}} {{.HostConfig.Privileged}}' {}
   ```

2. **Resource Planning**:
   - Review resource utilization trends
   - Plan for capacity increases if needed

3. **Backup Verification**:
   - Test restoring from backup
   - Verify backup integrity

## Health Check System

### Automated Health Checks

Set up a cron job to run health checks at regular intervals:

```bash
# Add to /etc/crontab
# Run monitoring every 15 minutes
*/15 * * * * root /opt/vpn/scripts/monitoring.sh

# Run daily backup at 1 AM
0 1 * * * root /opt/vpn/scripts/daily-backup.sh

# Run weekly updates at 2 AM on Sundays
0 2 * * 0 root /opt/vpn/scripts/weekly-update.sh

# Run monthly security audit at 3 AM on the first day of the month
0 3 1 * * root /opt/vpn/scripts/monthly-security-audit.sh
```

### Health Check Metrics

The monitoring system collects the following metrics:

1. **System Metrics**:
   - CPU usage
   - Memory usage
   - Disk usage

2. **Network Metrics**:
   - Connection counts per service
   - Bandwidth usage
   - Connection duration

3. **Error Metrics**:
   - Log error counts
   - Service restart counts
   - Failed connection attempts

4. **Performance Metrics**:
   - Connection latency
   - Throughput
   - DNS resolution time

### Alert System

Configure alerts for critical issues:

1. **Email Alerts**:
   - High resource usage
   - Service outages
   - Security events

2. **SMS Alerts** (optional):
   - Critical service failures
   - Security breaches

3. **Dashboard** (optional):
   - Real-time monitoring dashboard
   - Historical metrics visualization

## Troubleshooting Guide

### Common Issues and Solutions

1. **Container Fails to Start**

   *Problem*: Docker containers fail to start after configuration changes.
   
   *Solution*:
   ```bash
   # Check container logs
   docker logs outline-server
   docker logs v2ray
   
   # Verify configuration file syntax
   jq . /opt/vpn/outline-server/config.json
   jq . /opt/vpn/v2ray/config.json
   
   # Inspect Docker network
   docker network inspect vpn-network
   ```

2. **Connectivity Issues**

   *Problem*: Clients cannot connect to the VPN service.
   
   *Solution*:
   ```bash
   # Check if ports are open
   netstat -tuln | grep -E '8388|443'
   
   # Verify firewall settings
   ufw status
   
   # Test connectivity from another server
   curl -I --connect-timeout 5 YOUR_SERVER_IP:443
   
   # Check container status
   docker ps
   ```

3. **Performance Degradation**

   *Problem*: VPN performance is slower than expected.
   
   *Solution*:
   ```bash
   # Check system load
   uptime
   
   # Monitor network traffic
   iftop -i eth0
   
   # Check connection count
   netstat -an | grep -E '8388|443' | wc -l
   
   # Review routing rules
   jq '.routing.rules' /opt/vpn/v2ray/config.json
   ```

4. **Security Concerns**

   *Problem*: Unusual access patterns or potential security breach.
   
   *Solution*:
   ```bash
   # Check authentication logs
   grep "Failed password" /var/log/auth.log
   
   # Check unusual connections
   netstat -tn | grep -v 'ESTABLISHED\|TIME_WAIT' | grep ':443\|:8388'
   
   # Restart services with new credentials
   cd /opt/vpn
   docker-compose down
   # Update credentials in config files
   docker-compose up -d
   ```

## Recovery Procedures

### Backup Restoration

In case of system failure, restore from backup:

```bash
#!/bin/bash
# restore-from-backup.sh
BACKUP_DIR="/opt/vpn/backups"
BACKUP_DATE="20230501"  # Specify the backup date to restore

# Stop services
cd /opt/vpn
docker-compose down

# Extract backup
tar -xzf "$BACKUP_DIR/vpn-config-$BACKUP_DATE.tar.gz" -C "$BACKUP_DIR"

# Restore configuration files
cp "$BACKUP_DIR/$BACKUP_DATE/config.json" /opt/vpn/outline-server/
cp "$BACKUP_DIR/$BACKUP_DATE/config.json" /opt/vpn/v2ray/
cp "$BACKUP_DIR/$BACKUP_DATE/users.db" /opt/vpn/v2ray/

# Start services
docker-compose up -d

# Verify services
docker-compose ps
```

### Emergency Security Response

If a security breach is detected:

1. **Isolate**:
   - Temporarily disable public access to the VPN
   
   ```bash
   ufw deny 8388/tcp
   ufw deny 8388/udp
   ufw deny 443/tcp
   ufw deny 443/udp
   ```

2. **Investigate**:
   - Review logs and identify the breach
   
   ```bash
   grep -E "ERROR|WARNING" /opt/vpn/logs/*/error.log
   last -i
   grep "Invalid user" /var/log/auth.log
   ```

3. **Remediate**:
   - Change all credentials
   - Update configurations
   - Apply security patches
   
   ```bash
   # Generate new keys for Reality
   docker run --rm v2fly/v2fly-core:latest xray x25519 > /opt/vpn/v2ray/new_keypair.txt
   
   # Update configurations with new keys
   # Then restart services
   cd /opt/vpn
   docker-compose down
   docker-compose up -d
   ```

4. **Restore**:
   - Gradually restore access with monitoring
   
   ```bash
   ufw allow 8388/tcp
   ufw allow 8388/udp
   ufw allow 443/tcp
   ufw allow 443/udp
   ```

## Performance Optimization

### Network Tuning

Optimize kernel network parameters for VPN performance:

```bash
# Add to /etc/sysctl.conf
# Increase maximum file descriptors
fs.file-max = 65535

# Optimize TCP settings
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# Apply changes
sysctl -p
```

### Connection Pooling

Configure connection pooling for improved performance:

1. **TCP keepalive settings**:
   - Modify v2ray configuration to enable TCP keepalive
   - Add to streamSettings.sockopt section:
   
   ```json
   "sockopt": {
     "tcpFastOpen": true,
     "tcpKeepAliveInterval": 25
   }
   ```

2. **DNS optimization**:
   - Implement local caching DNS for faster resolution
   
   ```bash
   apt-get install dnsmasq
   
   # Configure dnsmasq
   cat > /etc/dnsmasq.conf <<EOF
   cache-size=1000
   no-negcache
   server=8.8.8.8
   server=1.1.1.1
   EOF
   
   systemctl restart dnsmasq
   
   # Update Outline and v2ray configs to use local DNS
   sed -i 's/"nameserver": "8.8.8.8"/"nameserver": "127.0.0.1"/g' /opt/vpn/outline-server/config.json
   ```

### Resource Limitation

Implement resource limits for Docker containers:

```bash
# Update docker-compose.yml to add resource limits
version: '3'

services:
  outline-server:
    # ... existing configuration ...
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
          
  v2ray:
    # ... existing configuration ...
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '1.0'
          memory: 512M
```

## Scaling Considerations

### Horizontal Scaling

For increased capacity, consider setting up multiple VPN servers:

1. **Load Balancer Setup**:
   - Deploy HAProxy or Nginx as a load balancer
   - Distribute client connections across multiple backends

2. **Configuration Synchronization**:
   - Use a central configuration repository
   - Automatically sync configurations across servers

3. **Central User Management**:
   - Implement a central user database
   - Synchronize user additions/removals across servers

### Vertical Scaling

Optimize for higher capacity on the same server:

1. **Increase Resources**:
   - Upgrade server CPU, memory, and network capacity
   - Optimize kernel parameters for higher connection counts

2. **Efficient Protocol Selection**:
   - Use most efficient ciphers for Shadowsocks
   - Configure optimal XTLS settings for VLESS+Reality