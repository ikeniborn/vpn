#!/bin/bash

# VPN Project Docker Operations Library
# Handles Docker installation, container management, and resource optimization

# Mark as sourced
export DOCKER_LIB_SOURCED=true

# Source common library
if [ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# ========================= SYSTEM RESOURCE DETECTION =========================

# Get number of available CPU cores
get_cpu_cores() {
    nproc 2>/dev/null || echo "1"
}

# Get available memory in MB
get_available_memory() {
    local mem_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [ -n "$mem_kb" ]; then
        echo $((mem_kb / 1024))
    else
        # Fallback to total memory
        local mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
        echo $((mem_total / 1024))
    fi
}

# Calculate optimal CPU limits based on available cores
calculate_cpu_limits() {
    local cpu_cores=$(get_cpu_cores)
    local max_cpu=""
    local reserve_cpu=""
    
    if [ "$cpu_cores" -eq 1 ]; then
        # Single core system - use smaller limits
        max_cpu="0.8"
        reserve_cpu="0.2"
    elif [ "$cpu_cores" -eq 2 ]; then
        # Dual core system
        max_cpu="1.5"
        reserve_cpu="0.5"
    else
        # Multi-core system
        max_cpu="2"
        reserve_cpu="0.5"
    fi
    
    echo "$max_cpu $reserve_cpu"
}

# Calculate optimal memory limits based on available memory
calculate_memory_limits() {
    local available_mem=$(get_available_memory)
    local max_mem=""
    local reserve_mem=""
    
    if [ "$available_mem" -lt 1024 ]; then
        # Less than 1GB - very conservative
        max_mem="512m"
        reserve_mem="256m"
    elif [ "$available_mem" -lt 2048 ]; then
        # Less than 2GB - conservative
        max_mem="1g"
        reserve_mem="512m"
    else
        # 2GB or more - standard limits
        max_mem="2g"
        reserve_mem="512m"
    fi
    
    echo "$max_mem $reserve_mem"
}

# ========================= DOCKER INSTALLATION =========================

# Check if Docker is installed
check_docker_installed() {
    command_exists docker
}

# Check if Docker Compose is installed
check_docker_compose_installed() {
    command_exists docker-compose || command_exists docker compose
}

# Install Docker if not present
install_docker() {
    if check_docker_installed; then
        debug "Docker already installed"
        return 0
    fi
    
    log "Installing Docker..."
    
    # Download and run Docker installation script
    if curl -fsSL https://get.docker.com -o get-docker.sh; then
        if sh get-docker.sh; then
            systemctl enable docker
            systemctl start docker
            log "Docker installed successfully"
            rm -f get-docker.sh
            return 0
        else
            error "Failed to install Docker"
            return 1
        fi
    else
        error "Failed to download Docker installation script"
        return 1
    fi
}

# Install Docker Compose if not present
install_docker_compose() {
    if check_docker_compose_installed; then
        debug "Docker Compose already installed"
        return 0
    fi
    
    log "Installing Docker Compose..."
    
    local compose_version="v2.20.3"
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    if curl -L "$compose_url" -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        log "Docker Compose installed successfully"
        return 0
    else
        error "Failed to install Docker Compose"
        return 1
    fi
}

# ========================= CONTAINER MANAGEMENT =========================

# Check if container exists
container_exists() {
    local container_name="$1"
    docker ps -a --format "{{.Names}}" | grep -E "^${container_name}$" >/dev/null 2>&1
}

# Check if container is running
container_running() {
    local container_name="$1"
    docker ps --format "{{.Names}}" | grep -E "^${container_name}$" >/dev/null 2>&1
}

# Get container status
get_container_status() {
    local container_name="$1"
    if container_exists "$container_name"; then
        docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null
    else
        echo "not found"
    fi
}

# Get container health status
get_container_health() {
    local container_name="$1"
    if container_exists "$container_name"; then
        docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none"
    else
        echo "not found"
    fi
}

# ========================= DOCKER COMPOSE MANAGEMENT =========================

# Generate Docker Compose configuration with appropriate resource limits
generate_docker_compose() {
    local server_port="$1"
    local compose_file="$2"
    
    if [ -z "$server_port" ] || [ -z "$compose_file" ]; then
        error "Server port and compose file path required"
        return 1
    fi
    
    # Calculate optimal resource limits
    local cpu_limits=($(calculate_cpu_limits))
    local memory_limits=($(calculate_memory_limits))
    
    local max_cpu="${cpu_limits[0]}"
    local reserve_cpu="${cpu_limits[1]}"
    local max_memory="${memory_limits[0]}"
    local reserve_memory="${memory_limits[1]}"
    
    debug "Calculated limits - CPU: $max_cpu/$reserve_cpu, Memory: $max_memory/$reserve_memory"
    
    cat > "$compose_file" <<EOF
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
    environment:
      - TZ=Europe/Moscow
    command: ["xray", "run", "-c", "/etc/xray/config.json"]
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "$server_port"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '$max_cpu'
          memory: $max_memory
        reservations:
          cpus: '$reserve_cpu'
          memory: $reserve_memory
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "Docker Compose configuration generated with optimal resource limits"
    debug "Max CPU: $max_cpu, Reserved CPU: $reserve_cpu"
    debug "Max Memory: $max_memory, Reserved Memory: $reserve_memory"
}

# Generate backup Docker Compose configuration (minimal resources)
generate_backup_docker_compose() {
    local server_port="$1"
    local compose_file="$2"
    
    if [ -z "$server_port" ] || [ -z "$compose_file" ]; then
        error "Server port and compose file path required"
        return 1
    fi
    
    # Use very conservative limits for backup
    local cpu_cores=$(get_cpu_cores)
    local backup_cpu="0.5"
    local backup_memory="512m"
    
    if [ "$cpu_cores" -eq 1 ]; then
        backup_cpu="0.8"
        backup_memory="256m"
    fi
    
    cat > "$compose_file" <<EOF
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
    environment:
      - TZ=Europe/Moscow
    entrypoint: ["/usr/bin/xray"]
    command: ["run", "-c", "/etc/xray/config.json"]
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "$server_port"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '$backup_cpu'
          memory: $backup_memory
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "Backup Docker Compose configuration generated with minimal resource limits"
}

# Start containers using Docker Compose
start_containers() {
    local work_dir="$1"
    
    if [ ! -f "$work_dir/docker-compose.yml" ]; then
        error "Docker Compose file not found: $work_dir/docker-compose.yml"
        return 1
    fi
    
    cd "$work_dir" || return 1
    
    log "Starting Docker containers..."
    if docker-compose up -d; then
        log "Containers started successfully"
        return 0
    else
        warning "Primary configuration failed, trying backup configuration..."
        
        # Try backup configuration
        if [ -f "docker-compose.backup.yml" ]; then
            cp "docker-compose.backup.yml" "docker-compose.yml"
            if docker-compose up -d; then
                log "Containers started with backup configuration"
                return 0
            fi
        fi
        
        error "Failed to start containers with both configurations"
        return 1
    fi
}

# Stop containers using Docker Compose
stop_containers() {
    local work_dir="$1"
    
    if [ ! -f "$work_dir/docker-compose.yml" ]; then
        warning "Docker Compose file not found: $work_dir/docker-compose.yml"
        return 1
    fi
    
    cd "$work_dir" || return 1
    docker-compose down
}

# Restart containers using Docker Compose
restart_containers() {
    local work_dir="$1"
    
    log "Restarting Docker containers..."
    stop_containers "$work_dir"
    sleep 2
    start_containers "$work_dir"
}

# ========================= HEALTH CHECKS =========================

# Check if netcat is available for health checks
ensure_netcat() {
    if ! command_exists nc && ! command_exists netcat; then
        log "Installing netcat for health checks..."
        if command_exists apt-get; then
            apt-get update && apt-get install -y netcat-openbsd
        elif command_exists yum; then
            yum install -y nc
        else
            warning "Could not install netcat - health checks may fail"
        fi
    fi
}

# ========================= SYSTEM DIAGNOSTICS =========================

# Show system resources
show_system_resources() {
    echo "=== System Resources ==="
    echo "CPU Cores: $(get_cpu_cores)"
    echo "Available Memory: $(get_available_memory) MB"
    echo "Recommended CPU limits: $(calculate_cpu_limits)"
    echo "Recommended Memory limits: $(calculate_memory_limits)"
    echo "======================="
}

# Initialize Docker library
init_docker() {
    debug "Initializing Docker library"
    ensure_netcat
}