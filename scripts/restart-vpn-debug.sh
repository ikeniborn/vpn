#!/bin/bash
# Enhanced restart script with debugging information

set -e

echo "=== VPN Restart with Debugging ==="
echo "Starting time: $(date)"
echo

# Function to display container status
show_container_status() {
    echo "=== Container Status ==="
    docker ps -a | grep -E 'shadowbox|v2ray|watchtower' || echo "No matching containers found"
    echo
}

# Function to display network information
show_network_info() {
    echo "=== Network Information ==="
    docker network ls | grep -E 'vpn|bridge' || echo "No matching networks found"
    
    if docker network ls | grep -q "vpn-network"; then
        echo
        echo "vpn-network details:"
        docker network inspect vpn-network | grep -A 20 "Containers"
    fi
    echo
}

# Display initial state
echo "Current state before restart:"
show_container_status
show_network_info

# Stop and remove existing containers
echo "Stopping and removing existing containers..."
docker stop shadowbox v2ray watchtower 2>/dev/null || true
docker rm shadowbox v2ray watchtower 2>/dev/null || true

# Remove existing network
echo "Removing existing vpn-network..."
docker network rm vpn-network 2>/dev/null || true

# Run the setup script
echo "Running setup script with improved network configuration..."
bash /home/ubuntu/vpn/scripts/setup.sh

# Display final state
echo
echo "Final state after setup:"
show_container_status
show_network_info

# Check logs for any issues
echo "=== Container Logs ==="
echo "shadowbox logs (truncated):"
docker logs shadowbox 2>&1 | tail -n 10
echo
echo "v2ray logs (truncated):"
docker logs v2ray 2>&1 | tail -n 10
echo

echo "=== Testing Connectivity ==="
echo "Checking connectivity to v2ray port 443..."
curl -k -s --connect-timeout 5 -o /dev/null -w "%{http_code} %{time_connect}s\n" https://localhost:443 || echo "Connection failed"

echo "Checking connectivity to Outline API..."
# Get API port from shadowbox environment variables
API_PORT=$(docker inspect --format='{{range .Config.Env}}{{if eq (index (split . "=") 0) "SB_API_PORT"}}{{index (split . "=") 1}}{{end}}{{end}}' shadowbox)
curl -k -s --connect-timeout 5 -o /dev/null -w "%{http_code} %{time_connect}s\n" https://localhost:$API_PORT/ || echo "Connection failed"

echo
echo "Restart and setup completed at $(date)"
echo "=== End of VPN Restart ==="