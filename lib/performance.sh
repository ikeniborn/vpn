#!/bin/bash

# =============================================================================
# Performance Optimization Library
# 
# This library implements optimization techniques from OPTIMIZATION.md
# including caching, parallel processing, and resource monitoring.
#
# Functions exported:
# - get_container_status_cached()
# - check_all_containers()
# - time_function()
# - monitor_resources()
# - benchmark_modules()
# - setup_log_rotation()
#
# Dependencies: lib/common.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_PATH="${SCRIPT_DIR}/common.sh"
source "$COMMON_PATH" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh from $COMMON_PATH"
    exit 1
}

# =============================================================================
# DOCKER OPERATIONS CACHING
# =============================================================================

# Cache container states for 5 seconds
CACHE_TTL=5
declare -A CONTAINER_CACHE
declare -A CACHE_TIME

# Get container status with caching
get_container_status_cached() {
    local container="$1"
    local now=$(date +%s)
    
    if [ -z "${CACHE_TIME[$container]}" ] || 
       [ $((now - CACHE_TIME[$container])) -gt $CACHE_TTL ]; then
        CONTAINER_CACHE[$container]=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
        CACHE_TIME[$container]=$now
    fi
    echo "${CONTAINER_CACHE[$container]}"
}

# Clear cache for specific container
clear_container_cache() {
    local container="$1"
    unset CONTAINER_CACHE[$container]
    unset CACHE_TIME[$container]
}

# Clear all container caches
clear_all_caches() {
    CONTAINER_CACHE=()
    CACHE_TIME=()
}

# =============================================================================
# PARALLEL PROCESSING
# =============================================================================

# Check multiple containers concurrently
check_all_containers() {
    local containers=("xray" "v2raya" "shadowbox" "watchtower")
    local results=()
    
    # Start background jobs
    for container in "${containers[@]}"; do
        (
            status=$(get_container_status_cached "$container")
            echo "$container:$status"
        ) &
    done
    
    # Wait for all jobs to complete
    wait
}

# Parallel user operations
parallel_user_operation() {
    local operation="$1"
    shift
    local users=("$@")
    local pids=()
    
    for user in "${users[@]}"; do
        "$operation" "$user" &
        pids+=($!)
    done
    
    # Wait for all operations to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# =============================================================================
# PERFORMANCE MONITORING
# =============================================================================

# Add timing to critical functions
time_function() {
    local func="$1"
    shift
    local start=$(date +%s.%N)
    "$func" "$@"
    local exit_code=$?
    local end=$(date +%s.%N)
    local duration=$(echo "$end - $start" | bc 2>/dev/null || echo "N/A")
    log "Function $func took: ${duration}s"
    return $exit_code
}

# Monitor script resource usage
monitor_resources() {
    local pid=${1:-$$}
    echo "=== Resource Usage for PID $pid ==="
    
    # Memory usage
    if [ -f "/proc/$pid/status" ]; then
        echo "Memory Usage:"
        grep -E "VmRSS|VmSize|VmHWM|VmPeak" "/proc/$pid/status" 2>/dev/null
    fi
    
    # CPU and process info
    echo -e "\nProcess Info:"
    ps -o pid,ppid,vsz,rss,pcpu,pmem,comm -p "$pid" 2>/dev/null
    
    # File descriptors
    echo -e "\nFile Descriptors:"
    if [ -d "/proc/$pid/fd" ]; then
        echo "Open FDs: $(ls /proc/$pid/fd 2>/dev/null | wc -l)"
    fi
}

# =============================================================================
# BENCHMARKING
# =============================================================================

# Benchmark module loading
benchmark_modules() {
    local module_dir="${PROJECT_ROOT:-$(dirname "$0")}"
    echo "=== Module Loading Benchmarks ==="
    
    for module in "$module_dir"/lib/*.sh "$module_dir"/modules/*/*.sh; do
        if [ -f "$module" ]; then
            echo -n "Loading $(basename "$module"): "
            time (source "$module" >/dev/null 2>&1)
        fi
    done
}

# Test command execution time
test_command_performance() {
    local script="${1:-./vpn.sh}"
    echo "=== Command Performance Tests ==="
    
    # Test common commands
    local commands=(
        "status"
        "user list"
        "help"
        "version"
    )
    
    for cmd in "${commands[@]}"; do
        echo -n "Testing '$cmd': "
        time ($script $cmd >/dev/null 2>&1)
    done
}

# Load testing
load_test() {
    local iterations=${1:-10}
    local script="${2:-./vpn.sh}"
    echo "=== Load Test ($iterations concurrent operations) ==="
    
    local start_time=$(date +%s.%N)
    
    for i in $(seq 1 "$iterations"); do
        ($script status >/dev/null 2>&1) &
    done
    
    wait
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    echo "Load test completed in ${duration}s"
}

# =============================================================================
# RESOURCE OPTIMIZATION
# =============================================================================

# Setup log rotation
setup_log_rotation() {
    local log_file="${1:-/var/log/vpn-watchdog.log}"
    local config_file="/etc/logrotate.d/vpn-logs"
    
    log "Setting up log rotation for $log_file"
    
    cat > "$config_file" <<EOF
$log_file {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # Reload systemd service if needed
        systemctl reload-or-restart vpn-watchdog 2>/dev/null || true
    endscript
}
EOF
    
    # Test logrotate configuration
    if logrotate -d "$config_file" >/dev/null 2>&1; then
        log "Log rotation configured successfully"
        return 0
    else
        error "Failed to configure log rotation"
        return 1
    fi
}

# =============================================================================
# STRING OPERATIONS OPTIMIZATION
# =============================================================================

# Optimized string operations (avoid repeated concatenation)
join_strings() {
    local delimiter="$1"
    shift
    local items=("$@")
    
    # Use printf instead of string concatenation
    local first=1
    for item in "${items[@]}"; do
        if [ $first -eq 1 ]; then
            printf "%s" "$item"
            first=0
        else
            printf "%s%s" "$delimiter" "$item"
        fi
    done
    printf "\n"
}

# Optimized file operations
read_multiple_files() {
    local files=("$@")
    local values=()
    
    # Batch file reads using read builtin
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local value
            read value < "$file"
            values+=("$value")
        else
            values+=("")
        fi
    done
    
    printf "%s\n" "${values[@]}"
}

# =============================================================================
# NETWORK OPTIMIZATION
# =============================================================================

# Set Docker client optimizations
optimize_docker_client() {
    export DOCKER_CLIENT_TIMEOUT=120
    export COMPOSE_HTTP_TIMEOUT=120
    export DOCKER_BUILDKIT=1
    
    log "Docker client optimizations applied"
}

# =============================================================================
# CONFIGURATION CACHING
# =============================================================================

# Configuration cache
declare -A CONFIG_CACHE
declare -A CONFIG_CACHE_TIME
CONFIG_CACHE_TTL=30

# Get configuration with caching
get_config_cached() {
    local config_file="$1"
    local key="$2"
    local cache_key="${config_file}:${key}"
    local now=$(date +%s)
    
    if [ -z "${CONFIG_CACHE_TIME[$cache_key]}" ] || 
       [ $((now - CONFIG_CACHE_TIME[$cache_key])) -gt $CONFIG_CACHE_TTL ]; then
        
        if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
            # Handle complex jq queries (with pipes, etc.)
            if [[ "$key" =~ \| ]]; then
                CONFIG_CACHE[$cache_key]=$(jq -r "$key // empty" "$config_file" 2>/dev/null)
            else
                CONFIG_CACHE[$cache_key]=$(jq -r ".$key // empty" "$config_file" 2>/dev/null)
            fi
        else
            CONFIG_CACHE[$cache_key]=""
        fi
        CONFIG_CACHE_TIME[$cache_key]=$now
    fi
    
    echo "${CONFIG_CACHE[$cache_key]}"
}

# =============================================================================
# MEMORY OPTIMIZATION
# =============================================================================

# Clean up unused variables and functions
cleanup_resources() {
    # Clear caches if they get too large
    if [ ${#CONTAINER_CACHE[@]} -gt 50 ]; then
        log "Clearing container cache (too large)"
        clear_all_caches
    fi
    
    if [ ${#CONFIG_CACHE[@]} -gt 100 ]; then
        log "Clearing configuration cache (too large)"
        CONFIG_CACHE=()
        CONFIG_CACHE_TIME=()
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export functions for use by other modules
export -f get_container_status_cached
export -f clear_container_cache
export -f clear_all_caches
export -f check_all_containers
export -f parallel_user_operation
export -f time_function
export -f monitor_resources
export -f benchmark_modules
export -f test_command_performance
export -f load_test
export -f setup_log_rotation
export -f join_strings
export -f read_multiple_files
export -f optimize_docker_client
export -f get_config_cached
export -f cleanup_resources

# Mark library as loaded
PERFORMANCE_LIB_SOURCED=1

# Initialize optimizations
optimize_docker_client

log "Performance optimization library loaded"