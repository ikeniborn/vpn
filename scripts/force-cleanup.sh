#!/bin/bash
# Script to forcefully remove stuck Docker containers and reset the Docker environment
# Use when the normal setup script fails to remove existing containers

echo "=== Starting Aggressive Docker Cleanup ==="
echo "This script will forcefully remove stuck containers and reset Docker networking"

# 1. Try standard removal first (with stronger force)
echo "Step 1: Attempting standard container removal..."
docker stop shadowbox v2ray watchtower 2>/dev/null || true
docker rm -f shadowbox v2ray watchtower 2>/dev/null || true

# 2. Check if containers still exist
if docker ps -a | grep -q "shadowbox"; then
    echo "Container still exists after normal removal. Trying stronger measures..."
    
    # 3. Use Docker API to directly remove the container
    echo "Step 2: Using Docker API method to remove container..."
    
    # Get container ID
    CONTAINER_ID=$(docker ps -a | grep shadowbox | awk '{print $1}')
    if [ -n "$CONTAINER_ID" ]; then
        echo "Found shadowbox container ID: $CONTAINER_ID"
        
        # Kill the container process more aggressively
        docker kill -s 9 $CONTAINER_ID 2>/dev/null || true
        sleep 2
        
        # Try removal again
        docker rm -f $CONTAINER_ID 2>/dev/null || true
    fi
fi

# 4. Remove Docker networks that might be causing issues
echo "Step 3: Cleaning up Docker networks..."
docker network rm vpn-network 2>/dev/null || true

# 5. Check for and remove any dangling/leftover container resources
echo "Step 4: Removing dangling Docker resources..."
docker system prune -f

# 6. Restart Docker daemon as last resort
echo "Step 5: Checking if Docker daemon restart is needed..."
if docker ps -a | grep -q "shadowbox"; then
    echo "Container still exists. Recommending Docker daemon restart."
    echo "Do you want to restart the Docker daemon? This will stop all running containers. [y/N]"
    read response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Restarting Docker daemon..."
        sudo systemctl restart docker
        sleep 5
        echo "Docker daemon restarted."
    else
        echo "Skipping Docker daemon restart."
    fi
fi

# 7. Final check
if docker ps -a | grep -q "shadowbox"; then
    echo "WARNING: shadowbox container still exists after cleanup attempts."
    echo "You may need to reboot your system to fully clear the Docker state."
else
    echo "Success! All problematic containers have been removed."
fi

echo "=== Cleanup Complete ==="
echo "You can now run the setup script again:"
echo "    ./scripts/setup.sh"