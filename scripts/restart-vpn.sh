#!/bin/bash

# Stop and remove existing containers
echo "Stopping and removing existing containers..."
docker stop shadowbox v2ray watchtower || true
docker rm shadowbox v2ray watchtower || true

# Remove existing network
echo "Removing existing vpn-network..."
docker network rm vpn-network || true

# Run the setup script
echo "Running setup script with new network configuration..."
bash /home/ubuntu/vpn/scripts/setup.sh

# Check network and container status
echo -e "\nVerifying network setup:"
echo "-------------------------"
echo "Docker networks:"
docker network ls | grep vpn
echo -e "\nContainer connectivity:"
docker network inspect vpn-network | grep -A 5 "Containers"

echo -e "\nContainers status:"
docker ps | grep -E 'shadowbox|v2ray'

echo -e "\nDone! VPN services restarted with internal networking."