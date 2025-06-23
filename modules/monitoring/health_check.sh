#!/bin/bash

# =============================================================================
# Health Check Endpoints Module
# 
# This module provides health check endpoints for monitoring VPN services.
# Implements comprehensive health monitoring for external monitoring systems.
#
# Functions exported:
# - start_health_server()
# - stop_health_server()
# - get_health_status()
# - create_health_endpoint()
# - configure_health_monitoring()
#
# Dependencies: lib/common.sh, lib/docker.sh, modules/system/diagnostics.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

source "$PROJECT_ROOT/lib/docker.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/docker.sh"
    exit 1
}

# =============================================================================
# CONFIGURATION
# =============================================================================

HEALTH_CHECK_PORT="${HEALTH_CHECK_PORT:-8888}"
HEALTH_CHECK_HOST="${HEALTH_CHECK_HOST:-127.0.0.1}"
HEALTH_CHECK_PIDFILE="/var/run/vpn-health-check.pid"
HEALTH_CHECK_LOG="/var/log/vpn-health-check.log"

# =============================================================================
# HEALTH STATUS COLLECTION
# =============================================================================

# Get comprehensive health status
get_health_status() {
    local format="${1:-json}"
    local detailed="${2:-false}"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local status="healthy"
    local checks=()
    local issues=()
    
    # Check VPN container status
    local container_status="unknown"
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "xray"; then
        if docker ps --format "{{.Names}}\t{{.Status}}" | grep "xray" | grep -q "Up"; then
            container_status="running"
        else
            container_status="stopped"
            status="unhealthy"
            issues+=("VPN container is not running")
        fi
    elif docker ps --format "{{.Names}}" 2>/dev/null | grep -q "shadowbox"; then
        if docker ps --format "{{.Names}}\t{{.Status}}" | grep "shadowbox" | grep -q "Up"; then
            container_status="running"
        else
            container_status="stopped"
            status="unhealthy"
            issues+=("VPN container is not running")
        fi
    else
        container_status="not_found"
        status="unhealthy"
        issues+=("No VPN container found")
    fi
    
    checks+=("container:$container_status")
    
    # Check system resources
    local memory_usage=$(free | awk '/^Mem:/{printf "%.1f", $3/$2 * 100}')
    local disk_usage=$(df / | awk 'NR==2{printf "%.1f", $3/$2 * 100}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    checks+=("memory:${memory_usage}%")
    checks+=("disk:${disk_usage}%")
    checks+=("load:${load_avg}")
    
    # Check if resources are within acceptable limits
    if (( $(echo "$memory_usage > 90" | bc -l) )); then
        status="degraded"
        issues+=("High memory usage: ${memory_usage}%")
    fi
    
    if (( $(echo "$disk_usage > 85" | bc -l) )); then
        status="degraded"
        issues+=("High disk usage: ${disk_usage}%")
    fi
    
    # Check network connectivity
    local network_status="unknown"
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        network_status="ok"
    else
        network_status="failed"
        status="unhealthy"
        issues+=("Network connectivity failed")
    fi
    
    checks+=("network:$network_status")
    
    # Check Docker daemon
    local docker_status="unknown"
    if docker info >/dev/null 2>&1; then
        docker_status="ok"
    else
        docker_status="failed"
        status="unhealthy"
        issues+=("Docker daemon not accessible")
    fi
    
    checks+=("docker:$docker_status")
    
    # Check port accessibility (if VPN is configured)
    local port_status="unknown"
    if [ -f "/opt/v2ray/config/config.json" ]; then
        local vpn_port=$(jq -r '.inbounds[0].port' /opt/v2ray/config/config.json 2>/dev/null)
        if [ -n "$vpn_port" ] && [ "$vpn_port" != "null" ]; then
            if netstat -tuln 2>/dev/null | grep -q ":$vpn_port "; then
                port_status="listening"
            else
                port_status="not_listening"
                status="unhealthy"
                issues+=("VPN port $vpn_port not listening")
            fi
        fi
    fi
    
    checks+=("port:$port_status")
    
    # Format output
    case "$format" in
        "json")
            local checks_json=$(printf '%s\n' "${checks[@]}" | jq -R . | jq -s .)
            local issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)
            
            cat <<EOF
{
  "status": "$status",
  "timestamp": "$timestamp",
  "checks": $checks_json,
  "issues": $issues_json,
  "summary": {
    "container": "$container_status",
    "memory_usage": "$memory_usage%",
    "disk_usage": "$disk_usage%",
    "load_average": "$load_avg",
    "network": "$network_status",
    "docker": "$docker_status",
    "port": "$port_status"
  }
}
EOF
            ;;
        "prometheus")
            # Prometheus metrics format
            cat <<EOF
# HELP vpn_health_status Overall VPN health status (1=healthy, 0.5=degraded, 0=unhealthy)
# TYPE vpn_health_status gauge
vpn_health_status{service="vpn"} $([ "$status" = "healthy" ] && echo "1" || ([ "$status" = "degraded" ] && echo "0.5" || echo "0"))

# HELP vpn_container_status VPN container status (1=running, 0=stopped/not_found)
# TYPE vpn_container_status gauge
vpn_container_status{service="vpn"} $([ "$container_status" = "running" ] && echo "1" || echo "0")

# HELP vpn_memory_usage_percent Memory usage percentage
# TYPE vpn_memory_usage_percent gauge
vpn_memory_usage_percent{service="vpn"} $memory_usage

# HELP vpn_disk_usage_percent Disk usage percentage
# TYPE vpn_disk_usage_percent gauge
vpn_disk_usage_percent{service="vpn"} $disk_usage

# HELP vpn_load_average System load average
# TYPE vpn_load_average gauge
vpn_load_average{service="vpn"} $load_avg

# HELP vpn_network_status Network connectivity status (1=ok, 0=failed)
# TYPE vpn_network_status gauge
vpn_network_status{service="vpn"} $([ "$network_status" = "ok" ] && echo "1" || echo "0")

# HELP vpn_docker_status Docker daemon status (1=ok, 0=failed)
# TYPE vpn_docker_status gauge
vpn_docker_status{service="vpn"} $([ "$docker_status" = "ok" ] && echo "1" || echo "0")
EOF
            ;;
        "text")
            echo "VPN Health Status: $status"
            echo "Timestamp: $timestamp"
            echo "Checks:"
            for check in "${checks[@]}"; do
                echo "  - $check"
            done
            if [ ${#issues[@]} -gt 0 ]; then
                echo "Issues:"
                for issue in "${issues[@]}"; do
                    echo "  - $issue"
                done
            fi
            ;;
    esac
    
    # Return appropriate exit code
    case "$status" in
        "healthy") return 0 ;;
        "degraded") return 1 ;;
        "unhealthy") return 2 ;;
        *) return 3 ;;
    esac
}

# =============================================================================
# HTTP HEALTH SERVER
# =============================================================================

# Simple HTTP server for health checks
create_health_endpoint() {
    local port="${1:-$HEALTH_CHECK_PORT}"
    local host="${2:-$HEALTH_CHECK_HOST}"
    
    # Create a simple HTTP server using netcat or socat
    if command -v socat >/dev/null 2>&1; then
        create_health_endpoint_socat "$host" "$port"
    elif command -v nc >/dev/null 2>&1; then
        create_health_endpoint_nc "$host" "$port"
    else
        error "Neither socat nor netcat available for health endpoint"
        return 1
    fi
}

# Health endpoint using socat
create_health_endpoint_socat() {
    local host="$1"
    local port="$2"
    
    local response_script=$(mktemp)
    cat > "$response_script" <<'EOF'
#!/bin/bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_ROOT/modules/monitoring/health_check.sh" 2>/dev/null

read request
path=$(echo "$request" | awk '{print $2}')

case "$path" in
    "/health")
        status_json=$(get_health_status "json")
        status_code=$?
        http_code=$([ $status_code -eq 0 ] && echo "200 OK" || echo "503 Service Unavailable")
        ;;
    "/health/prometheus")
        status_json=$(get_health_status "prometheus")
        status_code=$?
        http_code=$([ $status_code -eq 0 ] && echo "200 OK" || echo "503 Service Unavailable")
        ;;
    "/health/text")
        status_json=$(get_health_status "text")
        status_code=$?
        http_code=$([ $status_code -eq 0 ] && echo "200 OK" || echo "503 Service Unavailable")
        ;;
    *)
        status_json='{"error": "Not found", "available_endpoints": ["/health", "/health/prometheus", "/health/text"]}'
        http_code="404 Not Found"
        ;;
esac

content_length=${#status_json}

cat <<RESPONSE
HTTP/1.1 $http_code
Content-Type: application/json
Content-Length: $content_length
Connection: close

$status_json
RESPONSE
EOF
    
    chmod +x "$response_script"
    
    log "Starting health check endpoint on $host:$port"
    socat TCP-LISTEN:"$port",bind="$host",reuseaddr,fork EXEC:"$response_script" &
    local server_pid=$!
    
    echo "$server_pid" > "$HEALTH_CHECK_PIDFILE"
    log "Health check server started with PID: $server_pid"
    
    return 0
}

# Health endpoint using netcat
create_health_endpoint_nc() {
    local host="$1"
    local port="$2"
    
    log "Starting simple health check endpoint on $host:$port (netcat mode)"
    
    while true; do
        {
            local status_json=$(get_health_status "json")
            local status_code=$?
            local http_code=$([ $status_code -eq 0 ] && echo "200 OK" || echo "503 Service Unavailable")
            local content_length=${#status_json}
            
            cat <<RESPONSE
HTTP/1.1 $http_code
Content-Type: application/json
Content-Length: $content_length
Connection: close

$status_json
RESPONSE
        } | nc -l -p "$port" -q 1
        
        sleep 1
    done &
    
    local server_pid=$!
    echo "$server_pid" > "$HEALTH_CHECK_PIDFILE"
    log "Health check server started with PID: $server_pid (netcat mode)"
    
    return 0
}

# =============================================================================
# SERVER MANAGEMENT
# =============================================================================

# Start health check server
start_health_server() {
    local port="${1:-$HEALTH_CHECK_PORT}"
    local host="${2:-$HEALTH_CHECK_HOST}"
    local daemon="${3:-true}"
    
    # Check if server is already running
    if [ -f "$HEALTH_CHECK_PIDFILE" ]; then
        local existing_pid=$(cat "$HEALTH_CHECK_PIDFILE")
        if kill -0 "$existing_pid" 2>/dev/null; then
            warning "Health check server already running with PID: $existing_pid"
            return 0
        else
            log "Removing stale PID file"
            rm -f "$HEALTH_CHECK_PIDFILE"
        fi
    fi
    
    # Check if port is available
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        error "Port $port is already in use"
        return 1
    fi
    
    log "Starting health check server on $host:$port"
    
    if [ "$daemon" = "true" ]; then
        # Run as daemon
        nohup bash -c "
            source '$PROJECT_ROOT/modules/monitoring/health_check.sh'
            create_health_endpoint '$host' '$port'
        " > "$HEALTH_CHECK_LOG" 2>&1 &
        
        local server_pid=$!
        echo "$server_pid" > "$HEALTH_CHECK_PIDFILE"
        
        # Wait a moment and check if server started successfully
        sleep 2
        if kill -0 "$server_pid" 2>/dev/null; then
            success "Health check server started successfully (PID: $server_pid)"
            log "Health endpoints available:"
            log "  - http://$host:$port/health (JSON format)"
            log "  - http://$host:$port/health/prometheus (Prometheus format)"
            log "  - http://$host:$port/health/text (Human readable)"
            return 0
        else
            error "Health check server failed to start"
            rm -f "$HEALTH_CHECK_PIDFILE"
            return 1
        fi
    else
        # Run in foreground
        create_health_endpoint "$host" "$port"
    fi
}

# Stop health check server
stop_health_server() {
    if [ -f "$HEALTH_CHECK_PIDFILE" ]; then
        local server_pid=$(cat "$HEALTH_CHECK_PIDFILE")
        
        if kill -0 "$server_pid" 2>/dev/null; then
            log "Stopping health check server (PID: $server_pid)"
            
            # Try graceful shutdown first
            kill -TERM "$server_pid" 2>/dev/null
            sleep 2
            
            # Force kill if still running
            if kill -0 "$server_pid" 2>/dev/null; then
                log "Force killing health check server"
                kill -KILL "$server_pid" 2>/dev/null
            fi
            
            rm -f "$HEALTH_CHECK_PIDFILE"
            success "Health check server stopped"
        else
            warning "Health check server PID file exists but process not running"
            rm -f "$HEALTH_CHECK_PIDFILE"
        fi
    else
        warning "Health check server is not running (no PID file found)"
    fi
    
    return 0
}

# Get server status
get_server_status() {
    if [ -f "$HEALTH_CHECK_PIDFILE" ]; then
        local server_pid=$(cat "$HEALTH_CHECK_PIDFILE")
        
        if kill -0 "$server_pid" 2>/dev/null; then
            echo "Health check server is running (PID: $server_pid)"
            echo "Listening on: $HEALTH_CHECK_HOST:$HEALTH_CHECK_PORT"
            return 0
        else
            echo "Health check server is not running (stale PID file)"
            return 1
        fi
    else
        echo "Health check server is not running"
        return 1
    fi
}

# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

# Configure health monitoring
configure_health_monitoring() {
    local enable="${1:-true}"
    local port="${2:-$HEALTH_CHECK_PORT}"
    local host="${3:-$HEALTH_CHECK_HOST}"
    
    if [ "$enable" = "true" ]; then
        log "Configuring health monitoring..."
        
        # Create systemd service for health check server
        local service_file="/etc/systemd/system/vpn-health-check.service"
        
        cat > "$service_file" <<EOF
[Unit]
Description=VPN Health Check Server
After=network.target docker.service
Requires=docker.service

[Service]
Type=forking
ExecStart=$PROJECT_ROOT/modules/monitoring/health_check.sh start
ExecStop=$PROJECT_ROOT/modules/monitoring/health_check.sh stop
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=$HEALTH_CHECK_PIDFILE
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF
        
        # Reload systemd and enable service
        systemctl daemon-reload
        systemctl enable vpn-health-check.service
        
        success "Health monitoring service configured"
        log "Use 'systemctl start vpn-health-check' to start the service"
    else
        log "Disabling health monitoring..."
        
        # Stop and disable service
        systemctl stop vpn-health-check.service 2>/dev/null || true
        systemctl disable vpn-health-check.service 2>/dev/null || true
        
        # Remove service file
        rm -f "/etc/systemd/system/vpn-health-check.service"
        systemctl daemon-reload
        
        success "Health monitoring service disabled"
    fi
    
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f get_health_status
export -f create_health_endpoint
export -f start_health_server
export -f stop_health_server
export -f get_server_status
export -f configure_health_monitoring

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

# If script is run directly, provide CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "start")
            start_health_server "${2:-$HEALTH_CHECK_PORT}" "${3:-$HEALTH_CHECK_HOST}"
            ;;
        "stop")
            stop_health_server
            ;;
        "status")
            get_server_status
            ;;
        "health")
            get_health_status "${2:-json}"
            ;;
        "configure")
            configure_health_monitoring "${2:-true}"
            ;;
        *)
            echo "Usage: $0 {start|stop|status|health|configure}"
            echo ""
            echo "Commands:"
            echo "  start [port] [host]  - Start health check server"
            echo "  stop                 - Stop health check server"
            echo "  status              - Show server status"
            echo "  health [format]     - Get health status (json|prometheus|text)"
            echo "  configure [enable]  - Configure systemd service (true|false)"
            echo ""
            echo "Examples:"
            echo "  $0 start 8888 127.0.0.1"
            echo "  $0 health json"
            echo "  $0 configure true"
            exit 1
            ;;
    esac
fi