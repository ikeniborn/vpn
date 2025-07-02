#!/bin/bash
#
# VPN Installation Test Script
# Tests the installation process in a Docker container
#
# Usage: ./test-install.sh [ubuntu|debian|fedora|arch]

set -euo pipefail

# Default OS to test
TEST_OS="${1:-ubuntu}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing VPN installation on ${TEST_OS}...${NC}"

# Docker images for different distributions
declare -A OS_IMAGES=(
    ["ubuntu"]="ubuntu:22.04"
    ["debian"]="debian:11"
    ["fedora"]="fedora:39"
    ["arch"]="archlinux:latest"
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

# Copy installation script to test directory
cp "$(dirname "$0")/install.sh" "$TEST_DIR/"

# Create Dockerfile
cat > "$TEST_DIR/Dockerfile" <<EOF
FROM $DOCKER_IMAGE

# Install sudo
RUN if command -v apt-get &> /dev/null; then \
        apt-get update && apt-get install -y sudo; \
    elif command -v dnf &> /dev/null; then \
        dnf install -y sudo; \
    elif command -v pacman &> /dev/null; then \
        pacman -Syu --noconfirm sudo; \
    fi

# Create test user
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser

# Copy installation script
COPY install.sh /home/testuser/install.sh
RUN chown testuser:testuser /home/testuser/install.sh && \
    chmod +x /home/testuser/install.sh

# Switch to test user
USER testuser
WORKDIR /home/testuser

# Set environment
ENV USER=testuser
ENV HOME=/home/testuser

# Run installation
CMD ["/bin/bash", "-c", "./install.sh --no-menu --skip-docker"]
EOF

# Build test container
echo -e "${BLUE}Building test container...${NC}"
docker build -t vpn-install-test:$TEST_OS "$TEST_DIR"

# Run test container
echo -e "${BLUE}Running installation test...${NC}"
if docker run --rm vpn-install-test:$TEST_OS; then
    echo -e "${GREEN}✓ Installation test passed for $TEST_OS${NC}"
else
    echo -e "${RED}✗ Installation test failed for $TEST_OS${NC}"
    exit 1
fi

# Cleanup
echo -e "${BLUE}Cleaning up...${NC}"
docker rmi vpn-install-test:$TEST_OS
rm -rf "$TEST_DIR"

echo -e "${GREEN}Test completed successfully!${NC}"