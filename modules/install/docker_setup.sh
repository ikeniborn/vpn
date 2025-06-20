#!/bin/bash

# =============================================================================
# Docker Setup Module
# 
# This module handles Docker container setup and management for VPN server.
# Extracted from install_vpn.sh for modular architecture.
#
# Functions exported:
# - calculate_resource_limits()
# - create_docker_compose()
# - create_backup_docker_compose()
# - start_docker_container()
# - verify_container_status()
# - diagnose_container_issues()
#
# Dependencies: lib/common.sh, lib/docker.sh
# =============================================================================

# Source required libraries if not already sourced
if [ -z "$COMMON_SOURCED" ]; then
    MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    COMMON_PATH="${PROJECT_ROOT:-$MODULE_DIR/../..}/lib/common.sh"
    source "$COMMON_PATH" 2>/dev/null || {
        echo "Error: Cannot source lib/common.sh from $COMMON_PATH"
        return 1 2>/dev/null || exit 1
    }
fi

if [ -z "$DOCKER_LIB_SOURCED" ]; then
    MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DOCKER_PATH="${PROJECT_ROOT:-$MODULE_DIR/../..}/lib/docker.sh"
    source "$DOCKER_PATH" 2>/dev/null || {
        echo "Error: Cannot source lib/docker.sh from $DOCKER_PATH"
        return 1 2>/dev/null || exit 1
    }
fi

# =============================================================================
# RESOURCE CALCULATION
# =============================================================================

# Calculate optimal resource limits based on system specifications
calculate_resource_limits() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Calculating resource limits..."
    
    # Check if required functions are available
    if ! command -v get_cpu_cores >/dev/null 2>&1; then
        error "Function get_cpu_cores not found. Docker library may not be loaded."
        return 1
    fi
    
    if ! command -v get_available_memory >/dev/null 2>&1; then
        error "Function get_available_memory not found. Docker library may not be loaded."
        return 1
    fi
    
    # Get system resources
    local cpu_cores=$(get_cpu_cores)
    local available_mem=$(get_available_memory)
    
    [ "$debug" = true ] && {
        log "Detected CPU cores: $cpu_cores"
        log "Available memory: ${available_mem} MB"
    }
    
    # Check if main calculation functions are available
    for func in calculate_cpu_limits calculate_memory_limits; do
        if ! command -v "$func" >/dev/null 2>&1; then
            error "Function $func not found. Docker library may not be loaded."
            return 1
        fi
    done
    
    # Calculate CPU limits
    local cpu_limits=$(calculate_cpu_limits)
    MAX_CPU=$(echo "$cpu_limits" | cut -d' ' -f1)
    RESERVE_CPU=$(echo "$cpu_limits" | cut -d' ' -f2)
    
    # Calculate memory limits
    local mem_limits=$(calculate_memory_limits)
    MAX_MEM=$(echo "$mem_limits" | cut -d' ' -f1)
    RESERVE_MEM=$(echo "$mem_limits" | cut -d' ' -f2)
    
    # Calculate backup limits (more conservative)
    BACKUP_CPU=$(echo "scale=1; $MAX_CPU * 0.5" | bc 2>/dev/null || echo "0.5")
    BACKUP_MEM=$(echo "scale=0; $MAX_MEM * 0.5 / 1" | bc 2>/dev/null || echo "256")m
    
    [ "$debug" = true ] && {
        log "Primary limits: CPU $MAX_CPU/$RESERVE_CPU, Memory $MAX_MEM/$RESERVE_MEM"
        log "Backup limits: CPU $BACKUP_CPU, Memory $BACKUP_MEM"
    }
    
    # Set fallback values if calculations failed
    MAX_CPU="${MAX_CPU:-1.0}"
    RESERVE_CPU="${RESERVE_CPU:-0.5}"
    MAX_MEM="${MAX_MEM:-512m}"
    RESERVE_MEM="${RESERVE_MEM:-256m}"
    BACKUP_CPU="${BACKUP_CPU:-0.5}"
    BACKUP_MEM="${BACKUP_MEM:-256m}"
    
    # Export variables for use in docker-compose
    export MAX_CPU RESERVE_CPU MAX_MEM RESERVE_MEM BACKUP_CPU BACKUP_MEM
    
    [ "$debug" = true ] && log "Resource limits calculated and exported successfully"
    
    return 0
}

# =============================================================================
# HEALTHCHECK SCRIPT CREATION
# =============================================================================

# Create healthcheck script for VLESS+Reality protocol
create_healthcheck_script() {
    local work_dir="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Creating healthcheck script..."
    
    if [ -z "$work_dir" ]; then
        error "Missing required parameter: work_dir"
        return 1
    fi
    
    # Create healthcheck script
    cat > "$work_dir/healthcheck.sh" <<'EOL'
#!/bin/bash
# Health check script for VLESS+Reality
# Enhanced version with better timing and diagnostics

PORT=${1:-37276}
HOST=${2:-127.0.0.1}

# Function to check if Xray process is ready
check_xray_ready() {
    # Check if error log shows successful startup
    if [ -f "/var/log/xray/error.log" ]; then
        if grep -q "started" /var/log/xray/error.log 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Wait for Xray to be ready (up to 10 seconds)
ready_count=0
while [ $ready_count -lt 10 ]; do
    if check_xray_ready; then
        break
    fi
    sleep 1
    ready_count=$((ready_count + 1))
done

# Check port accessibility with retries
port_check_attempts=0
while [ $port_check_attempts -lt 3 ]; do
    if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
        break
    fi
    sleep 1
    port_check_attempts=$((port_check_attempts + 1))
done

if [ $port_check_attempts -eq 3 ]; then
    echo "Port $PORT is not accessible after retries"
    exit 1
fi

# Check TLS handshake with Reality SNI if available
if command -v openssl >/dev/null 2>&1 && [ $ready_count -lt 10 ]; then
    # Get SNI from config if available
    if [ -f "/etc/xray/config.json" ] && command -v jq >/dev/null 2>&1; then
        SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // "addons.mozilla.org"' /etc/xray/config.json 2>/dev/null)
    else
        SNI="addons.mozilla.org"
    fi
    
    # Test TLS connection with Reality SNI (shorter timeout for health check)
    if echo "" | timeout 3 openssl s_client -connect "$HOST:$PORT" -servername "$SNI" -verify_return_error >/dev/null 2>&1; then
        echo "VLESS+Reality service healthy"
        exit 0
    fi
fi

# Fallback: basic TCP connectivity test
if timeout 2 sh -c "</dev/tcp/$HOST/$PORT" >/dev/null 2>&1; then
    echo "VLESS service accessible (TCP check)"
    exit 0
fi

echo "VLESS+Reality service not ready"
exit 1
EOL
    
    # Make script executable
    chmod +x "$work_dir/healthcheck.sh"
    
    if [ ! -f "$work_dir/healthcheck.sh" ]; then
        error "Failed to create healthcheck script"
        return 1
    fi
    
    [ "$debug" = true ] && log "Healthcheck script created successfully"
    return 0
}

# =============================================================================
# DOCKER COMPOSE CREATION
# =============================================================================

# Create main docker-compose.yml with adaptive resource limits and improved health check
create_docker_compose() {
    local work_dir="$1"
    local server_port="$2"
    local debug=${3:-false}
    
    [ "$debug" = true ] && log "Creating docker-compose.yml..."
    
    if [ -z "$work_dir" ] || [ -z "$server_port" ]; then
        error "Missing required parameters: work_dir and server_port"
        return 1
    fi
    
    # Ensure resource limits are calculated
    if [ -z "$MAX_CPU" ]; then
        calculate_resource_limits "$debug"
    fi
    
    # Create healthcheck script for VLESS+Reality
    create_healthcheck_script "$work_dir" "$debug"
    
    # Create docker-compose.yml with improved health check
    cat > "$work_dir/docker-compose.yml" <<EOL
version: '3'
services:
  xray:
    image: teddysun/xray:latest
    container_name: xray
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
      - ./healthcheck.sh:/usr/local/bin/healthcheck.sh:ro
    environment:
      - TZ=Europe/Moscow
    command: ["xray", "run", "-c", "/etc/xray/config.json"]
    healthcheck:
      test: ["CMD", "/bin/bash", "/usr/local/bin/healthcheck.sh", "$server_port"]
      interval: 20s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '$MAX_CPU'
          memory: $MAX_MEM
        reservations:
          cpus: '$RESERVE_CPU'
          memory: $RESERVE_MEM
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOL
    
    if [ ! -f "$work_dir/docker-compose.yml" ]; then
        error "Failed to create docker-compose.yml"
        return 1
    fi
    
    [ "$debug" = true ] && log "docker-compose.yml created successfully"
    return 0
}

# Create backup docker-compose.yml with minimal resource limits
create_backup_docker_compose() {
    local work_dir="$1"
    local server_port="$2"
    local debug=${3:-false}
    
    [ "$debug" = true ] && log "Creating backup docker-compose.yml..."
    
    if [ -z "$work_dir" ] || [ -z "$server_port" ]; then
        error "Missing required parameters: work_dir and server_port"
        return 1
    fi
    
    # Ensure resource limits are calculated
    if [ -z "$BACKUP_CPU" ]; then
        calculate_resource_limits "$debug"
    fi
    
    # Create backup docker-compose.yml with improved health check
    cat > "$work_dir/docker-compose.backup.yml" <<EOL
version: '3'
services:
  xray:
    image: teddysun/xray:latest
    container_name: xray
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
      - ./healthcheck.sh:/usr/local/bin/healthcheck.sh:ro
    environment:
      - TZ=Europe/Moscow
    entrypoint: ["/usr/bin/xray"]
    command: ["run", "-c", "/etc/xray/config.json"]
    healthcheck:
      test: ["CMD", "/bin/bash", "/usr/local/bin/healthcheck.sh", "$server_port"]
      interval: 20s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '$BACKUP_CPU'
          memory: $BACKUP_MEM
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOL
    
    if [ ! -f "$work_dir/docker-compose.backup.yml" ]; then
        error "Failed to create backup docker-compose.yml"
        return 1
    fi
    
    [ "$debug" = true ] && log "backup docker-compose.yml created successfully"
    return 0
}

# =============================================================================
# CONTAINER MANAGEMENT
# =============================================================================

# Start Docker container with fallback to backup configuration
start_docker_container() {
    local work_dir="$1"
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Starting Docker container..."
    
    if [ -z "$work_dir" ]; then
        error "Missing required parameter: work_dir"
        return 1
    fi
    
    # Change to work directory
    cd "$work_dir" || {
        error "Failed to change to work directory: $work_dir"
        return 1
    }
    
    # Verify configuration exists
    if [ ! -f "config/config.json" ]; then
        error "Configuration file not found: config/config.json"
        return 1
    fi
    
    [ "$debug" = true ] && log "Starting Docker container with primary configuration..."
    
    # Try to start with primary configuration
    if docker-compose up -d; then
        [ "$debug" = true ] && log "Container started successfully with primary configuration"
        return 0
    fi
    
    # Primary configuration failed, try backup
    warning "Primary configuration failed, trying backup configuration..."
    
    # Stop any running containers
    docker-compose down 2>/dev/null || true
    
    # Switch to backup configuration
    if [ -f "docker-compose.backup.yml" ]; then
        cp "docker-compose.backup.yml" "docker-compose.yml"
        
        [ "$debug" = true ] && log "Switched to backup configuration"
        
        # Try to start with backup configuration
        if docker-compose up -d; then
            log "Container started successfully with backup configuration"
            return 0
        else
            error "Failed to start Docker container even with backup configuration"
            return 1
        fi
    else
        error "Backup configuration not found"
        return 1
    fi
}

# Verify container status and health with improved waiting logic
verify_container_status() {
    local container_name=${1:-"xray"}
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Verifying container status..."
    
    # Wait for container to initialize
    sleep 5
    
    # Check if container is running
    if docker ps | grep -q "$container_name"; then
        [ "$debug" = true ] && log "Container $container_name is running"
        
        # Check container health if health check is enabled
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)
        if [ -n "$health_status" ]; then
            [ "$debug" = true ] && log "Container health status: $health_status"
            
            # Improved waiting logic with longer timeout for start_period
            local retries=0
            local max_retries=45  # Increased to accommodate 60s start_period + buffer
            
            while [ "$health_status" = "starting" ] && [ $retries -lt $max_retries ]; do
                sleep 2
                health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)
                retries=$((retries + 1))
                
                # Show progress every 10 retries
                if [ $((retries % 10)) -eq 0 ]; then
                    log "Waiting for health check... ($((retries * 2))s elapsed)"
                fi
            done
            
            if [ "$health_status" = "healthy" ]; then
                log "Container $container_name is healthy and ready"
                return 0
            elif [ "$health_status" = "unhealthy" ]; then
                warning "Container $container_name is unhealthy"
                # Show recent logs for debugging
                log "Recent container logs:"
                docker logs --tail 10 "$container_name" 2>/dev/null || true
                return 1
            elif [ "$health_status" = "starting" ]; then
                warning "Container $container_name health check is still starting (may need more time)"
                log "Container is running but health check hasn't completed yet"
                return 0  # Consider this acceptable - container is running
            fi
        fi
        
        log "Container $container_name is running successfully"
        return 0
    else
        error "Container $container_name is not running"
        return 1
    fi
}

# Diagnose container issues
diagnose_container_issues() {
    local container_name=${1:-"xray"}
    local debug=${2:-false}
    
    [ "$debug" = true ] && log "Diagnosing container issues..."
    
    # Show container logs
    log "Container logs (last 20 lines):"
    docker-compose logs --tail 20 2>/dev/null || docker logs --tail 20 "$container_name" 2>/dev/null
    
    # Test Xray binary
    log "Testing Xray binary:"
    if docker run --rm teddysun/xray:latest xray version 2>/dev/null; then
        log "Xray binary is working correctly"
    else
        warning "Xray binary test failed"
    fi
    
    # Check system resources
    log "System resource usage:"
    docker stats --no-stream 2>/dev/null || log "Docker stats not available"
    
    # Check for port conflicts
    local work_dir="$(pwd)"
    if [ -f "$work_dir/config/config.json" ]; then
        local port=$(grep -o '"port":[[:space:]]*[0-9]*' "$work_dir/config/config.json" | grep -o '[0-9]*' | head -1)
        if [ -n "$port" ]; then
            log "Checking port $port availability:"
            if netstat -tulnp 2>/dev/null | grep ":$port "; then
                warning "Port $port is already in use"
            else
                log "Port $port is available"
            fi
        fi
    fi
    
    return 0
}

# =============================================================================
# COMPREHENSIVE SETUP FUNCTION
# =============================================================================

# Setup Docker environment with all configurations
setup_docker_environment() {
    local work_dir="$1"
    local server_port="$2"
    local debug=${3:-false}
    
    [ "$debug" = true ] && log "Setting up Docker environment..."
    
    if [ -z "$work_dir" ] || [ -z "$server_port" ]; then
        error "Missing required parameters: work_dir and server_port"
        return 1
    fi
    
    # Calculate resource limits
    calculate_resource_limits "$debug" || {
        error "Failed to calculate resource limits"
        return 1
    }
    
    # Create Docker Compose configurations
    create_docker_compose "$work_dir" "$server_port" "$debug" || {
        error "Failed to create docker-compose.yml"
        return 1
    }
    
    create_backup_docker_compose "$work_dir" "$server_port" "$debug" || {
        error "Failed to create backup docker-compose.yml"
        return 1
    }
    
    # Start container
    start_docker_container "$work_dir" "$debug" || {
        error "Failed to start Docker container"
        diagnose_container_issues "xray" "$debug"
        return 1
    }
    
    # Verify container status
    verify_container_status "xray" "$debug" || {
        warning "Container verification failed"
        diagnose_container_issues "xray" "$debug"
        return 1
    }
    
    [ "$debug" = true ] && log "Docker environment setup completed successfully"
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f calculate_resource_limits
export -f create_healthcheck_script
export -f create_docker_compose
export -f create_backup_docker_compose
export -f start_docker_container
export -f verify_container_status
export -f diagnose_container_issues
export -f setup_docker_environment

# Debug mode check
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being run directly, enable debug mode
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <work_dir> <server_port>"
        exit 1
    fi
    setup_docker_environment "$1" "$2" true
fi