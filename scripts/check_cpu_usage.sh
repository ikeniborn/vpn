#!/bin/bash

# CPU Usage Monitoring Script for VPN Management System
# Helps identify resource-intensive operations

echo "=== VPN Script CPU Usage Monitor ==="
echo "Monitoring CPU usage for vpn.sh related processes..."
echo "Press Ctrl+C to stop monitoring"
echo

# Function to get CPU usage for specific processes
get_vpn_cpu_usage() {
    local total_cpu=0
    local process_count=0
    
    # Check for vpn.sh related processes
    while read -r pid cpu cmd; do
        if [[ "$cmd" == *"vpn.sh"* ]] || [[ "$cmd" == *"docker"* && "$cmd" == *"xray"* ]]; then
            echo "  PID: $pid | CPU: $cpu% | CMD: ${cmd:0:60}..."
            total_cpu=$(echo "$total_cpu + $cpu" | bc -l 2>/dev/null || echo "$total_cpu")
            ((process_count++))
        fi
    done < <(ps aux | awk 'NR>1 {print $2, $3, substr($0, index($0, $11))}' | grep -E "(vpn\.sh|docker.*xray)")
    
    echo "  Total VPN-related CPU usage: ${total_cpu}%"
    echo "  Number of processes: $process_count"
    echo
}

# Function to monitor Docker daemon CPU usage
get_docker_cpu_usage() {
    local docker_cpu=$(ps aux | grep -E "dockerd|docker-containerd" | grep -v grep | awk '{sum+=$3} END {print (sum ? sum : 0)}')
    echo "  Docker daemon CPU usage: ${docker_cpu}%"
}

# Function to check for high-frequency command execution
check_command_frequency() {
    echo "=== Checking for high-frequency commands ==="
    
    # Monitor system calls for vpn.sh processes
    local vpn_pids=$(pgrep -f "vpn.sh" | tr '\n' ' ')
    if [ -n "$vpn_pids" ]; then
        echo "  VPN script PIDs: $vpn_pids"
        
        # Check open files (indicates Docker API calls)
        for pid in $vpn_pids; do
            local open_files=$(lsof -p "$pid" 2>/dev/null | wc -l)
            echo "  PID $pid has $open_files open files"
        done
    else
        echo "  No vpn.sh processes currently running"
    fi
    echo
}

# Function to show system-wide CPU usage
show_system_cpu() {
    echo "=== System CPU Usage ==="
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "  Overall CPU usage: ${cpu_usage}%"
    
    # Show top CPU consuming processes
    echo "  Top 5 CPU consumers:"
    ps aux --sort=-%cpu | head -6 | tail -5 | while read line; do
        echo "    $line"
    done
    echo
}

# Main monitoring loop
while true; do
    clear
    echo "=== VPN CPU Usage Monitor - $(date) ==="
    echo
    
    show_system_cpu
    get_docker_cpu_usage
    echo
    get_vpn_cpu_usage
    check_command_frequency
    
    echo "Refreshing in 3 seconds... (Ctrl+C to exit)"
    sleep 3
done