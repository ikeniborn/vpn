#!/bin/bash
#
# VPN Deployment Test Script
# Tests the deployment process in a Docker container
#
# Usage: ./test-deploy.sh [ubuntu|debian|fedora|arch]

set -euo pipefail

# Default OS to test
TEST_OS="${1:-ubuntu}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing VPN deployment on ${TEST_OS}...${NC}"

# Docker images for different distributions
declare -A OS_IMAGES=(
    ["ubuntu"]="ubuntu:22.04"
    ["debian"]="debian:11"
    ["fedora"]="fedora:39"
    ["arch"]="archlinux:latest"
    ["centos"]="centos:stream9"
)

# Get the Docker image
DOCKER_IMAGE="${OS_IMAGES[$TEST_OS]}"
if [ -z "$DOCKER_IMAGE" ]; then
    echo -e "${RED}Unknown OS: $TEST_OS${NC}"
    echo "Available options: ${!OS_IMAGES[@]}"
    exit 1
fi

# Create a temporary directory for the test
TEST_DIR=$(mktemp -d)
echo -e "${BLUE}Test directory: $TEST_DIR${NC}"

# Copy deployment script to test directory
cp "$(dirname "$0")/deploy.sh" "$TEST_DIR/"

# Create Dockerfile
cat > "$TEST_DIR/Dockerfile" <<EOF
FROM $DOCKER_IMAGE

# Install basic requirements
RUN if command -v apt-get &> /dev/null; then \
        apt-get update && apt-get install -y systemd sudo curl; \
    elif command -v dnf &> /dev/null; then \
        dnf install -y systemd sudo curl; \
    elif command -v pacman &> /dev/null; then \
        pacman -Syu --noconfirm systemd sudo curl; \
    fi

# Copy deployment script
COPY deploy.sh /root/deploy.sh
RUN chmod +x /root/deploy.sh

# Create entrypoint script
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'exec /usr/sbin/init' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

# Build test container
echo -e "${BLUE}Building test container...${NC}"
docker build -t vpn-deploy-test:$TEST_OS "$TEST_DIR"

# Run test container
echo -e "${BLUE}Starting test container...${NC}"
CONTAINER_ID=$(docker run -d --privileged \
    --name vpn-deploy-test-$TEST_OS \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
    vpn-deploy-test:$TEST_OS)

echo -e "${BLUE}Container ID: $CONTAINER_ID${NC}"

# Wait for container to be ready
sleep 5

# Run deployment script in container
echo -e "${BLUE}Running deployment script...${NC}"
docker exec -it $CONTAINER_ID /root/deploy.sh --skip-docker --build-from-source

# Check deployment result
echo -e "${BLUE}Checking deployment...${NC}"
if docker exec $CONTAINER_ID vpn --version &> /dev/null; then
    echo -e "${GREEN}✓ VPN binary installed successfully${NC}"
else
    echo -e "${RED}✗ VPN binary not found${NC}"
fi

# Run diagnostics
echo -e "${BLUE}Running diagnostics...${NC}"
docker exec $CONTAINER_ID vpn doctor || true

# Cleanup
echo -e "${BLUE}Cleaning up...${NC}"
docker stop $CONTAINER_ID
docker rm $CONTAINER_ID
docker rmi vpn-deploy-test:$TEST_OS
rm -rf "$TEST_DIR"

echo -e "${GREEN}Deployment test completed!${NC}"