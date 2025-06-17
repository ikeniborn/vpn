#!/bin/bash

# VPN Watchdog Script
# Monitors and restarts VPN containers if they fail

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
WORK_DIR="/opt/v2ray"
OUTLINE_DIR="/opt/outline"
LOG_FILE="/var/log/vpn-watchdog.log"
CHECK_INTERVAL=60  # seconds
MAX_RESTART_ATTEMPTS=3
RESTART_COOLDOWN=300  # 5 minutes cooldown after max attempts

# Auto-detect working directory if default doesn't exist
if [ ! -d "$WORK_DIR" ]; then
    for dir in "/opt/v2ray" "/home/*/v2ray" "/root/v2ray" "$(pwd)"; do
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            WORK_DIR="$dir"
            break
        fi
    done
fi

if [ ! -d "$OUTLINE_DIR" ]; then
    for dir in "/opt/outline" "/home/*/outline" "/root/outline"; do
        if [ -d "$dir" ] && ([ -f "$dir/docker-compose.yml" ] || docker ps | grep -q shadowbox); then
            OUTLINE_DIR="$dir"
            break
        fi
    done
fi

# Ensure log directory exists
mkdir -p $(dirname "$LOG_FILE")

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check container health
check_container() {
    local container_name=$1
    local container_exists=$(docker ps -a --format "{{.Names}}" | grep -E "^${container_name}$" || echo "")
    
    if [ -z "$container_exists" ]; then
        return 1  # Container doesn't exist
    fi
    
    local container_status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "")
    local container_health=$(docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
    
    if [ "$container_status" != "running" ]; then
        log "Container $container_name is not running (status: $container_status)"
        return 1
    fi
    
    if [ "$container_health" != "none" ] && [ "$container_health" != "healthy" ]; then
        log "Container $container_name is unhealthy (health: $container_health)"
        return 1
    fi
    
    return 0
}

# Restart container with docker-compose
restart_xray_container() {
    log "Attempting to restart Xray container..."
    cd "$WORK_DIR" || return 1
    
    # Stop container
    docker-compose down || true
    sleep 5
    
    # Clean up any stale processes
    docker rm -f xray 2>/dev/null || true
    
    # Start container
    if docker-compose up -d; then
        log "Xray container restarted successfully"
        return 0
    else
        log "Failed to restart Xray container"
        return 1
    fi
}

# Restart Outline containers
restart_outline_containers() {
    log "Attempting to restart Outline containers..."
    
    # Check if containers exist first
    if ! docker ps -a --format "{{.Names}}" | grep -q "^shadowbox$"; then
        log "Shadowbox container doesn't exist, skipping restart"
        return 0
    fi
    
    # Restart shadowbox
    docker stop shadowbox 2>/dev/null || true
    sleep 2
    docker start shadowbox 2>/dev/null || {
        log "Failed to start shadowbox container, attempting recreation"
        # Try to restart using docker-compose if available
        if [ -f "$OUTLINE_DIR/docker-compose.yml" ]; then
            cd "$OUTLINE_DIR" && docker-compose restart shadowbox 2>/dev/null || true
        fi
    }
    
    # Restart watchtower if it exists
    if docker ps -a --format "{{.Names}}" | grep -q "^watchtower$"; then
        docker restart watchtower 2>/dev/null || log "Watchtower restart failed"
    fi
    
    return 0
}

# Check system resources
check_system_resources() {
    local memory_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
    local disk_usage=$(df -h / | tail -1 | awk '{print int($5)}')
    
    if [ "$memory_usage" -gt 90 ]; then
        log "WARNING: High memory usage: ${memory_usage}%"
    fi
    
    if [ "$disk_usage" -gt 90 ]; then
        log "WARNING: High disk usage: ${disk_usage}%"
    fi
}

# Clean up old logs and docker resources
cleanup_resources() {
    log "Performing resource cleanup..."
    
    # Rotate logs
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        log "Log file rotated"
    fi
    
    # Clean up Docker resources
    docker system prune -f --volumes 2>/dev/null || true
}

# Initialize restart counters
declare -A restart_attempts
declare -A last_restart_time

# Main monitoring loop
main() {
    log "VPN Watchdog started (Work dir: $WORK_DIR, Outline dir: $OUTLINE_DIR)"
    
    # Initial validation
    if [ ! -d "$WORK_DIR" ] && [ ! -d "$OUTLINE_DIR" ]; then
        log "ERROR: No VPN directories found. Please check installation."
        exit 1
    fi
    
    while true; do
        # Check Xray container if it exists
        if [ -d "$WORK_DIR" ] && [ -f "$WORK_DIR/docker-compose.yml" ]; then
            if ! check_container "xray"; then
                current_time=$(date +%s)
                container_key="xray"
                
                # Initialize counters if not exists
                if [ -z "${restart_attempts[$container_key]}" ]; then
                    restart_attempts[$container_key]=0
                    last_restart_time[$container_key]=0
                fi
                
                # Check if we're in cooldown period
                time_since_last_restart=$((current_time - last_restart_time[$container_key]))
                
                if [ "${restart_attempts[$container_key]}" -ge "$MAX_RESTART_ATTEMPTS" ]; then
                    if [ "$time_since_last_restart" -lt "$RESTART_COOLDOWN" ]; then
                        log "Container xray in cooldown period. Waiting..."
                        sleep "$CHECK_INTERVAL"
                        continue
                    else
                        # Reset counter after cooldown
                        restart_attempts[$container_key]=0
                    fi
                fi
                
                # Attempt restart
                restart_attempts[$container_key]=$((restart_attempts[$container_key] + 1))
                last_restart_time[$container_key]=$current_time
                
                log "Restart attempt ${restart_attempts[$container_key]}/$MAX_RESTART_ATTEMPTS for xray"
                restart_xray_container
                
                # Wait a bit for container to stabilize
                sleep 30
            else
                # Reset counter on successful check
                restart_attempts["xray"]=0
            fi
        fi
        
        # Check Outline containers if they exist
        if [ -d "$OUTLINE_DIR" ]; then
            for container in shadowbox watchtower; do
                if ! check_container "$container"; then
                    current_time=$(date +%s)
                    
                    # Initialize counters if not exists
                    if [ -z "${restart_attempts[$container]}" ]; then
                        restart_attempts[$container]=0
                        last_restart_time[$container]=0
                    fi
                    
                    # Check if we're in cooldown period
                    time_since_last_restart=$((current_time - last_restart_time[$container]))
                    
                    if [ "${restart_attempts[$container]}" -ge "$MAX_RESTART_ATTEMPTS" ]; then
                        if [ "$time_since_last_restart" -lt "$RESTART_COOLDOWN" ]; then
                            log "Container $container in cooldown period. Waiting..."
                            continue
                        else
                            # Reset counter after cooldown
                            restart_attempts[$container]=0
                        fi
                    fi
                    
                    # Attempt restart
                    restart_attempts[$container]=$((restart_attempts[$container] + 1))
                    last_restart_time[$container]=$current_time
                    
                    log "Restart attempt ${restart_attempts[$container]}/$MAX_RESTART_ATTEMPTS for $container"
                    restart_outline_containers
                    
                    # Wait a bit for containers to stabilize
                    sleep 30
                    break  # Restart all Outline containers at once
                else
                    # Reset counter on successful check
                    restart_attempts[$container]=0
                fi
            done
        fi
        
        # Check system resources every 5 cycles
        if [ $(($(date +%s) % 300)) -lt "$CHECK_INTERVAL" ]; then
            check_system_resources
        fi
        
        # Cleanup every hour
        if [ $(($(date +%s) % 3600)) -lt "$CHECK_INTERVAL" ]; then
            cleanup_resources
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Handle signals
trap 'log "VPN Watchdog stopped"; exit 0' SIGTERM SIGINT

# Start monitoring
main