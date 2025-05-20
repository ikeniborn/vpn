# Docker Compose Configuration

This file defines the container configuration for the integrated Shadowsocks (Outline Server) and VLESS+Reality VPN solution.

## File Path
```
/opt/vpn/docker-compose.yml
```

## Configuration

```yaml
version: '3'

services:
  outline-server:
    # Use architecture-specific image
    # For x86_64: shadowsocks/shadowsocks-libev:latest
    # For ARM64/ARMv7: ken1029/shadowbox:latest
    image: ${SB_IMAGE:-shadowsocks/shadowsocks-libev:latest}
    container_name: outline-server
    restart: always
    volumes:
      - ./outline-server/config.json:/etc/shadowsocks-libev/config.json
      - ./outline-server/access.json:/etc/shadowsocks-libev/access.json
      - ./outline-server/data:/opt/outline/data
      - ./logs/outline:/var/log/shadowsocks
    ports:
      - "8388:8388/tcp"
      - "8388:8388/udp"
    networks:
      vpn-network:
        ipv4_address: 172.16.238.2
    environment:
      - SS_CONFIG=/etc/shadowsocks-libev/config.json
    cap_add:
      - NET_ADMIN
    command: >
      /bin/sh -c "ss-server -c /etc/shadowsocks-libev/config.json -v"
      
  v2ray:
    image: v2fly/v2fly-core:latest
    container_name: v2ray
    restart: always
    volumes:
      - ./v2ray/config.json:/etc/v2ray/config.json
      - ./logs/v2ray:/var/log/v2ray
    ports:
      - "443:443/tcp"
      - "443:443/udp"
    networks:
      vpn-network:
        ipv4_address: 172.16.238.3
    depends_on:
      - outline-server
    cap_add:
      - NET_ADMIN

  # Watchtower container for automatic updates
  watchtower:
    # Use architecture-specific image
    # For x86_64: containrrr/watchtower:latest
    # For ARM64: ken1029/watchtower:arm64
    # For ARMv7: ken1029/watchtower:arm32
    image: ${WATCHTOWER_IMAGE:-containrrr/watchtower:latest}
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --tlsverify --interval 3600

networks:
  vpn-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.238.0/24
```

## Description

This Docker Compose configuration sets up:

1. **outline-server** container:
   - Based on shadowsocks/shadowsocks-libev image
   - Exposes port 8388 for TCP and UDP traffic
   - Mounts configuration files and data directories
   - Has NET_ADMIN capability for network management
   - Assigned static IP 172.16.238.2 on internal network

2. **v2ray** container:
   - Based on v2fly/v2fly-core image
   - Exposes port 443 for TCP and UDP traffic
   - Mounts configuration files and logging directory
   - Depends on outline-server to ensure proper startup order
   - Assigned static IP 172.16.238.3 on internal network

3. **vpn-network**:
   - Custom bridge network for container communication
   - Subnet 172.16.238.0/24 for internal addressing
   - Isolated from other Docker networks

## Deployment

Create the docker-compose.yml file in the `/opt/vpn/` directory and launch the containers:

```bash
cd /opt/vpn
docker-compose up -d
```

To check the status of the containers:

```bash
docker-compose ps
```

To view the logs:

```bash
docker-compose logs -f
```

## Detecting Architecture in Deployment Scripts

Add this to your deployment scripts to automatically select the correct images:

```bash
# Detect architecture and set appropriate images
ARCH=$(uname -m)
case $ARCH in
    aarch64|arm64)
        export SB_IMAGE="ken1029/shadowbox:latest"
        export WATCHTOWER_IMAGE="ken1029/watchtower:arm64"
        echo "ARM64 architecture detected, using ARM64-compatible images"
        ;;
    armv7l)
        export SB_IMAGE="ken1029/shadowbox:latest"
        export WATCHTOWER_IMAGE="ken1029/watchtower:arm32"
        echo "ARMv7 architecture detected, using ARMv7-compatible images"
        ;;
    x86_64|amd64)
        export SB_IMAGE="shadowsocks/shadowsocks-libev:latest"
        export WATCHTOWER_IMAGE="containrrr/watchtower:latest"
        echo "x86_64 architecture detected, using standard images"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac