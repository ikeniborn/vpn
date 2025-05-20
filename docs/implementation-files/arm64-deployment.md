# ARM64 Deployment Guide for Outline Server

This document provides specialized instructions for deploying the Outline Server component of the integrated VPN solution on ARM64 and ARMv7 architectures.

## Overview

The integrated VPN solution can be deployed on ARM-based systems, including:
- ARM64 (aarch64) platforms like AWS Graviton, Oracle Cloud ARM, or Raspberry Pi 4 (64-bit OS)
- ARMv7 platforms like Raspberry Pi 3/4 (32-bit OS)

This enables cost-effective deployment on a wide range of hardware, from inexpensive single-board computers to ARM-based cloud instances, which often cost less than x86 equivalents.

## ARM64 Docker Images

When deploying on ARM architecture, you must use specialized Docker images:

### For ARM64 (64-bit)

```yaml
# Outline Server image
SB_IMAGE=ken1029/shadowbox:latest

# Watchtower image
WATCHTOWER_IMAGE=ken1029/watchtower:arm64
```

### For ARMv7 (32-bit)

```yaml
# Outline Server image
SB_IMAGE=ken1029/shadowbox:latest

# Watchtower image
WATCHTOWER_IMAGE=ken1029/watchtower:arm32
```

## Installation Methods

### One-Line Installation

For simple deployment on ARM64:

```bash
export SB_IMAGE=ken1029/shadowbox:latest
curl -sSL https://raw.githubusercontent.com/ericqmore/outline-vpn-arm/main/arm64/install_server.sh | bash
```

For ARMv7 (e.g., Raspberry Pi 3/4 with 32-bit OS):

```bash
export SB_IMAGE=ken1029/shadowbox:latest
curl -sSL https://raw.githubusercontent.com/ericqmore/outline-vpn-arm/main/armv7/install_server.sh | bash
```

### Manual Installation

For more control over the installation process:

1. Clone the repository:
   ```bash
   git clone https://github.com/ericqmore/outline-vpn-arm.git
   cd outline-vpn-arm
   ```

2. Run the appropriate installation script:
   - For ARM64:
     ```bash
     ./INSTALL-ARM64
     ```
   - For ARMv7:
     ```bash
     ./INSTALL-ARMv7
     ```

## Docker Compose Configuration for ARM64

Update the Docker Compose configuration to support ARM64:

```yaml
version: '3'

services:
  outline-server:
    image: ken1029/shadowbox:latest  # ARM64-compatible image
    container_name: outline-server
    restart: always
    volumes:
      - ./outline-server/config.json:/etc/shadowsocks-libev/config.json
      - ./outline-server/access.json:/etc/shadowsocks-libev/access.json
      - ./outline-server/data:/opt/outline/data
      - ./logs/outline:/var/log/shadowsocks
    ports:
      - "${OUTLINE_PORT}:${OUTLINE_PORT}/tcp"
      - "${OUTLINE_PORT}:${OUTLINE_PORT}/udp"
    networks:
      vpn-network:
        ipv4_address: 172.16.238.2
    environment:
      - SS_CONFIG=/etc/shadowsocks-libev/config.json
    cap_add:
      - NET_ADMIN
      
  v2ray:
    image: v2fly/v2fly-core:latest  # v2fly supports multi-arch including ARM64
    container_name: v2ray
    restart: always
    volumes:
      - ./v2ray/config.json:/etc/v2ray/config.json
      - ./logs/v2ray:/var/log/v2ray
    ports:
      - "${V2RAY_PORT}:${V2RAY_PORT}/tcp"
      - "${V2RAY_PORT}:${V2RAY_PORT}/udp"
    networks:
      vpn-network:
        ipv4_address: 172.16.238.3
    depends_on:
      - outline-server
    cap_add:
      - NET_ADMIN

  watchtower:
    image: ken1029/watchtower:arm64  # ARM64-specific watchtower image
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --tlsverify --interval 3600
    depends_on:
      - outline-server
      - v2ray

networks:
  vpn-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.238.0/24
```

## Modifications to Setup Script

When using our integrated setup script on ARM64 platforms, you need to set the appropriate image variables:

```bash
# Add to setup.sh before starting containers
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    info "Detected ARM64 architecture, using ARM-compatible images"
    SB_IMAGE="ken1029/shadowbox:latest"
    WATCHTOWER_IMAGE="ken1029/watchtower:arm64"
elif [ "$(uname -m)" = "armv7l" ]; then
    info "Detected ARMv7 architecture, using ARM-compatible images"
    SB_IMAGE="ken1029/shadowbox:latest"
    WATCHTOWER_IMAGE="ken1029/watchtower:arm32"
else
    info "Using default x86_64 images"
    SB_IMAGE="${SB_IMAGE:-quay.io/outline/shadowbox:stable}"
    WATCHTOWER_IMAGE="containrrr/watchtower:latest"
fi
```

## Performance Considerations

ARM platforms typically have different performance characteristics compared to x86-based systems:

1. **CPU Performance**: ARM CPUs often have more cores but lower single-thread performance
2. **Memory Bandwidth**: Typically lower than high-end x86 servers
3. **Storage I/O**: Can be limited, especially on single-board computers with SD cards

### Recommended Minimum Specifications

| Resource | ARMv7 (32-bit) | ARM64 (64-bit) |
|----------|----------------|---------------|
| CPU      | 4+ cores       | 2+ cores      |
| RAM      | 1 GB           | 2 GB          |
| Storage  | 8 GB           | 16 GB         |
| Network  | 100 Mbps       | 1 Gbps        |

### Optimizations for ARM

1. **Reduce Memory Usage**:
   - Add memory limits to Docker containers
   - Optimize connection pooling settings

2. **CPU Efficiency**:
   - Use less computationally intensive ciphers (e.g., chacha20-ietf-poly1305)
   - Enable hardware acceleration if available

3. **Storage Optimization**:
   - Use tmpfs for frequently written files
   - Enable noatime for filesystem mounts

## Integration Specifics

When integrating Outline Server (Shadowsocks) with VLESS+Reality on ARM64:

1. **Network Performance**:
   - Set appropriate buffer sizes in both services
   - Use TCP keepalive settings that work well on limited-resource systems

2. **Process Priority**:
   - Ensure v2ray receives adequate CPU priority using nice or Docker resource limits

3. **Log Management**:
   - Implement stricter log rotation on ARM due to potential storage constraints
   - Consider log compression or remote logging

## Troubleshooting ARM-Specific Issues

### Common Problems

1. **Container fails to start with "exec format error"**:
   - You're likely using an image not compatible with your CPU architecture
   - Solution: Verify architecture with `uname -m` and use the correct image

2. **Performance degradation over time**:
   - Check for memory leaks or swap usage
   - Solution: Add `--memory-swap=-1` to prevent container swapping

3. **High CPU usage**:
   - Review encryption methods, as some are more efficient on ARM
   - Solution: Use chacha20-ietf-poly1305 instead of AES on systems without AES hardware acceleration

4. **Storage I/O bottlenecks**:
   - Especially common on Raspberry Pi with SD cards
   - Solution: Move the data directory to an external USB SSD or use a high-quality SD card

### Architecture Detection

Add to your scripts to auto-detect and handle architecture differences:

```bash
ARCH=$(uname -m)
case $ARCH in
    aarch64|arm64)
        # ARM64 specific configuration
        ;;
    armv7l)
        # ARMv7 specific configuration
        ;;
    x86_64)
        # x86_64 specific configuration
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
```

## Conclusion

Deploying on ARM64 platforms offers excellent cost-efficiency for VPN servers, especially for small to medium deployments. By using the proper images and applying the recommended optimizations, you can achieve reliable performance on a variety of ARM-based systems, from Raspberry Pi to ARM cloud instances.