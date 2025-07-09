# Docker Deployment Guide

This guide explains how to deploy VPN servers using Docker with the Python-based VPN Manager.

## Prerequisites

- Docker 20.10 or later
- Docker Compose v2 (optional)
- Python 3.10+ with VPN Manager installed

## Quick Start

### 1. Install VPN Manager

```bash
# Install from PyPI
pip install vpn-manager

# Or install from source
git clone https://github.com/ikeniborn/vpn-manager.git
cd vpn-manager
pip install -e .
```

### 2. Deploy VPN Server

```bash
# Install VLESS server
vpn server install --protocol vless --port 8443 --name vless-server

# Install Shadowsocks server
vpn server install --protocol shadowsocks --port 8388 --name ss-server

# Install WireGuard server
vpn server install --protocol wireguard --port 51820 --name wg-server
```

### 3. Manage Servers

```bash
# List all servers
vpn server list

# Start/stop servers
vpn server start vless-server
vpn server stop vless-server

# View logs
vpn server logs vless-server --follow

# Check status
vpn server status vless-server --detailed
```

## Docker Compose Deployment

### Using Built-in Compose

```bash
# Deploy full stack with monitoring
vpn compose up --with-monitoring

# Deploy only VPN services
vpn compose up

# Scale services
vpn compose scale vless=3

# View compose status
vpn compose status
```

### Manual Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  vless-server:
    image: teddysun/xray:latest
    container_name: vless-server
    restart: unless-stopped
    ports:
      - "8443:8443"
    volumes:
      - ./config/vless:/etc/xray
      - ./logs/vless:/var/log/xray
    environment:
      - TZ=UTC
    networks:
      - vpn-network

  shadowsocks-server:
    image: shadowsocks/shadowsocks-libev:latest
    container_name: shadowsocks-server
    restart: unless-stopped
    ports:
      - "8388:8388"
      - "8388:8388/udp"
    volumes:
      - ./config/shadowsocks:/etc/shadowsocks
    environment:
      - METHOD=chacha20-ietf-poly1305
      - PASSWORD=${SS_PASSWORD}
    networks:
      - vpn-network

  proxy-server:
    image: vpn-manager/proxy:latest
    container_name: proxy-server
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "1080:1080"
    volumes:
      - ./config/proxy:/etc/proxy
      - ./data/proxy:/var/lib/proxy
    environment:
      - PROXY_AUTH=true
      - PROXY_TYPE=both
    networks:
      - vpn-network

networks:
  vpn-network:
    driver: bridge
```

## Container Management

### Health Monitoring

VPN Manager automatically monitors container health:

```bash
# View health status
vpn monitor health

# Set up health alerts
vpn monitor alerts add --container vless-server --cpu 80 --memory 90

# View container metrics
vpn monitor stats --container vless-server
```

### Resource Limits

Set resource constraints for containers:

```bash
# During installation
vpn server install --protocol vless \
  --memory-limit 512m \
  --cpu-limit 1.0

# Update existing server
vpn server update vless-server \
  --memory-limit 1g \
  --cpu-limit 2.0
```

### Networking

Configure network settings:

```bash
# Use custom network
vpn server install --protocol vless \
  --network vpn-bridge \
  --ip 172.20.0.10

# Configure port mapping
vpn server install --protocol shadowsocks \
  --port 8388:8388 \
  --port 8388:8388/udp
```

## Multi-Architecture Support

VPN Manager supports multiple architectures:

- `linux/amd64` - Standard x86_64
- `linux/arm64` - ARM 64-bit (Raspberry Pi 4, Apple Silicon)
- `linux/arm/v7` - ARM 32-bit (Raspberry Pi 3)

The appropriate image is automatically selected based on your platform.

## Production Deployment

### Security Considerations

1. **Use Secrets Management**:
   ```bash
   # Create secrets
   vpn secrets create vless-uuid
   vpn secrets create ss-password
   
   # Use in deployment
   vpn server install --protocol vless \
     --secret vless-uuid:uuid
   ```

2. **Enable TLS**:
   ```bash
   vpn server install --protocol vless \
     --tls-cert /path/to/cert.pem \
     --tls-key /path/to/key.pem
   ```

3. **Firewall Rules**:
   ```bash
   # Automatically configured, but can be customized
   vpn network firewall add --port 8443 --protocol tcp
   ```

### Backup and Restore

```bash
# Backup server configuration
vpn server backup vless-server --output backup.tar.gz

# Restore from backup
vpn server restore vless-server --input backup.tar.gz

# Backup all servers
vpn backup create --all --output vpn-backup.tar.gz
```

### Monitoring Stack

Deploy with Prometheus and Grafana:

```bash
# Deploy monitoring stack
vpn compose up --monitoring-stack

# Access dashboards
# Grafana: http://localhost:3000
# Prometheus: http://localhost:9090
```

## Troubleshooting

### Common Issues

1. **Port Already in Use**:
   ```bash
   # Check port usage
   vpn network check-port 8443
   
   # Use alternative port
   vpn server install --protocol vless --port 8444
   ```

2. **Container Won't Start**:
   ```bash
   # Check logs
   vpn server logs vless-server --tail 100
   
   # Inspect container
   docker inspect vless-server
   
   # Reset server
   vpn server reset vless-server
   ```

3. **Performance Issues**:
   ```bash
   # Check resource usage
   vpn monitor stats --all
   
   # Optimize containers
   vpn optimize --aggressive
   ```

### Debug Mode

Enable debug logging:

```bash
# Run with debug output
vpn --debug server install --protocol vless

# Enable debug for specific server
vpn server update vless-server --debug-logs
```

## Advanced Topics

### Custom Images

Use custom Docker images:

```bash
vpn server install --protocol custom \
  --image myregistry/myvpn:latest \
  --port 8443 \
  --config /path/to/config.json
```

### Cluster Deployment

Deploy across multiple hosts:

```bash
# Initialize swarm mode
vpn cluster init

# Join nodes
vpn cluster join --token <token> --manager <manager-ip>

# Deploy services
vpn cluster deploy --replicas 3
```

## Next Steps

- Review [Security Guide](SECURITY.md) for hardening
- Set up [Monitoring](OPERATIONS.md#monitoring) for production
- Configure [Automated Backups](OPERATIONS.md#backup)