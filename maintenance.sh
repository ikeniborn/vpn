#!/bin/bash

# ===================================================================
# VPN Server Security Hardening Script - Regular Maintenance
# ===================================================================
# This script:
# - Updates the system and Docker images
# - Rotates logs
# - Performs backup verification
# - Checks system health
# - Cleans up unused Docker resources
# ===================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Display colored text
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration variables
BACKUP_DIR="/opt/vpn/backup_data"
LOG_DIR="/var/log"
DOCKER_COMPOSE_DIR="$(pwd)"  # Assumes the script is run from the project directory
MAX_LOG_DAYS=30
MAX_BACKUP_DAYS=30
DOCKER_PRUNE_DAYS=7

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Function to check disk space
check_disk_space() {
    info "Checking disk space..."
    
    # Get disk usage for root partition
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [ "$DISK_USAGE" -gt 90 ]; then
        warn "Disk usage is critical: ${DISK_USAGE}% used"
    elif [ "$DISK_USAGE" -gt 80 ]; then
        warn "Disk usage is high: ${DISK_USAGE}% used"
    else
        info "Disk usage is normal: ${DISK_USAGE}% used"
    fi
    
    # Show top disk consumers
    info "Top disk consumers in /var:"
    du -h --max-depth=2 /var | sort -hr | head -10
}

# Check if script is run as root
check_root

# ===================================================================
# 1. System Update
# ===================================================================
info "Starting system maintenance..."

# Update package lists
info "Updating package lists..."
apt-get update || warn "Failed to update package lists completely"

# Upgrade installed packages
info "Upgrading installed packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || warn "Package upgrade completed with warnings"

# Update Docker and Docker Compose if installed
if command -v docker >/dev/null; then
    info "Checking for Docker updates..."
    DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade docker-ce docker-ce-cli containerd.io -y || warn "Docker update completed with warnings"
fi

# ===================================================================
# 2. Docker Maintenance
# ===================================================================
info "Performing Docker maintenance..."

if command -v docker >/dev/null; then
    # Stop unused containers (older than 7 days)
    info "Stopping inactive containers..."
    INACTIVE_CONTAINERS=$(docker ps -a --filter "status=exited" --filter "status=created" --filter "status=dead" --filter "since=${DOCKER_PRUNE_DAYS}d" -q)
    if [ -n "$INACTIVE_CONTAINERS" ]; then
        docker rm $INACTIVE_CONTAINERS || warn "Failed to remove some inactive containers"
        info "Removed inactive containers"
    else
        info "No inactive containers to remove"
    fi
    
    # Update Docker images
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.yml" ]; then
        info "Updating Docker images defined in docker-compose.yml..."
        cd "$DOCKER_COMPOSE_DIR" && docker-compose pull || warn "Failed to pull some Docker images"
        
        info "Restarting services with new images..."
        cd "$DOCKER_COMPOSE_DIR" && docker-compose up -d || warn "Failed to restart some services"
    else
        warn "No docker-compose.yml found in $DOCKER_COMPOSE_DIR"
    fi
    
    # Prune unused Docker resources
    info "Pruning unused Docker resources..."
    docker system prune --all --force --filter "until=${DOCKER_PRUNE_DAYS}d" || warn "Docker system prune completed with warnings"
    
    # Verify running containers
    info "Verifying running containers..."
    echo "Currently running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
else
    warn "Docker is not installed"
fi

# ===================================================================
# 3. Log Rotation
# ===================================================================
info "Performing log rotation and cleanup..."

# Check if logrotate is installed
if command -v logrotate >/dev/null; then
    # Force log rotation
    info "Running logrotate..."
    logrotate -f /etc/logrotate.conf || warn "Logrotate completed with warnings"
else
    warn "logrotate is not installed"
fi

# Clean old log files
info "Cleaning old log files (older than $MAX_LOG_DAYS days)..."
find "$LOG_DIR" -name "*.log.*" -type f -mtime +$MAX_LOG_DAYS -delete
find "$LOG_DIR" -name "*.gz" -type f -mtime +$MAX_LOG_DAYS -delete

# Check if any log files are getting too large
info "Checking for large log files..."
find "$LOG_DIR" -type f -name "*.log" -size +100M | while read -r LOG_FILE; do
    warn "Large log file found: $LOG_FILE ($(du -h "$LOG_FILE" | cut -f1))"
    # Truncate large log files
    echo "Truncating log file: $LOG_FILE"
    cp /dev/null "$LOG_FILE"
done

# ===================================================================
# 4. Backup Verification
# ===================================================================
info "Verifying backups..."

# Check if backup directory exists
if [ -d "$BACKUP_DIR" ]; then
    # Check for recent backups
    LATEST_BACKUP=$(find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime -2 | wc -l)
    
    if [ "$LATEST_BACKUP" -gt 0 ]; then
        info "Recent backups found (less than 2 days old)"
    else
        warn "No recent backups found! Check backup system"
    fi
    
    # Clean old backups
    info "Cleaning old backups (older than $MAX_BACKUP_DAYS days)..."
    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$MAX_BACKUP_DAYS -delete
    
    # Check backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    info "Current backup size: $BACKUP_SIZE"
else
    warn "Backup directory not found: $BACKUP_DIR"
fi

# ===================================================================
# 5. Security Checks
# ===================================================================
info "Performing basic security checks..."

# Check for failed login attempts
FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log | wc -l)
if [ "$FAILED_LOGINS" -gt 10 ]; then
    warn "High number of failed login attempts: $FAILED_LOGINS"
    
    # Show top IP addresses with failed logins
    info "Top IP addresses with failed logins:"
    grep "Failed password" /var/log/auth.log | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | sort | uniq -c | sort -nr | head -5
else
    info "Normal number of failed login attempts: $FAILED_LOGINS"
fi

# Check for modified system binaries
if command -v rkhunter >/dev/null; then
    info "Running RKHunter check..."
    rkhunter --check --skip-keypress --quiet || warn "RKHunter found potential issues"
fi

# Check firewall status
if command -v ufw >/dev/null; then
    if ! ufw status | grep -q "Status: active"; then
        warn "Firewall is not active! Enabling..."
        ufw --force enable
    else
        info "Firewall is active"
    fi
fi

# Check Docker network security
if command -v docker >/dev/null; then
    # Ensure Docker subnet is allowed in firewall
    if command -v ufw >/dev/null; then
        if ! ufw status | grep -q "172.17.0.0/16"; then
            warn "Docker subnet may not be properly configured in firewall"
        fi
    fi
fi

# ===================================================================
# 6. System Health Check
# ===================================================================
info "Checking system health..."

# Check disk space
check_disk_space

# Check memory usage
info "Checking memory usage..."
free -h

# Check for high CPU processes
info "Checking for high CPU processes..."
echo "Top CPU consumers:"
ps aux --sort=-%cpu | head -6

# Check load average
LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ')
CORES=$(nproc)
if awk "BEGIN {exit !($LOAD > $CORES)}" ; then
    warn "High system load detected: $LOAD (cores: $CORES)"
else
    info "System load is normal: $LOAD (cores: $CORES)"
fi

# Check for zombie processes
ZOMBIES=$(ps aux | grep -c 'Z')
if [ "$ZOMBIES" -gt 0 ]; then
    warn "Zombie processes found: $ZOMBIES"
else
    info "No zombie processes found"
fi

# ===================================================================
# 7. Final Cleanup
# ===================================================================
info "Performing final cleanup..."

# Clean package cache
apt-get clean
apt-get autoremove -y

# Verify critical services are running
info "Verifying critical services..."
CRITICAL_SERVICES=("docker" "ufw" "fail2ban" "ssh" "cron")
for SERVICE in "${CRITICAL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$SERVICE"; then
        info "Service $SERVICE is running"
    else
        warn "Service $SERVICE is not running"
        
        # Attempt to restart the service
        systemctl restart "$SERVICE" || warn "Failed to restart $SERVICE"
    fi
done

# ===================================================================
# 8. Summary
# ===================================================================
echo "============================================================"
info "Maintenance completed successfully!"
echo "============================================================"
echo "Summary of actions:"
echo "  - System packages updated"
echo "  - Docker images updated and services restarted"
echo "  - Unused Docker resources pruned"
echo "  - Log files rotated and old logs cleaned"
echo "  - Backups verified"
echo "  - Security checks performed"
echo "  - System health checked"
echo "  - Critical services verified"
echo "============================================================"
echo "Recommended to add this script to cron for regular execution:"
echo "  0 2 * * 0 /path/to/maintenance.sh > /var/log/maintenance.log 2>&1"
echo "  (This will run the script every Sunday at 2 AM)"
echo "============================================================"

exit 0