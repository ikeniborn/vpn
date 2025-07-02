# Docker Deployment Guide

This guide explains how to deploy the VPN server using Docker and Docker Compose.

## Quick Start

### Using Docker Hub Images

```bash
# Download docker-compose file
curl -L https://raw.githubusercontent.com/yourusername/vpn-rust/main/docker-compose.hub.yml -o docker-compose.yml

# Set environment variables
export VPN_PROTOCOL=vless
export VPN_PORT=443
export VPN_SNI=www.google.com

# Deploy
docker-compose up -d
```

### Building from Source

```bash
# Clone repository
git clone https://github.com/yourusername/vpn-rust.git
cd vpn-rust

# Build multi-arch images
./scripts/docker-build.sh

# Deploy
docker-compose -f docker-compose.hub.yml up -d
```

## Available Images

| Image | Description | Size |
|-------|-------------|------|
| `vpn-rust:latest` | Main VPN server with CLI | ~50MB |
| `vpn-rust-proxy-auth:latest` | Proxy authentication service | ~20MB |
| `vpn-rust-identity:latest` | Identity management service | ~25MB |

## Architecture Support

All images support multiple architectures:
- `linux/amd64` (x86_64)
- `linux/arm64` (ARM 64-bit)

## Environment Variables

### VPN Server Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `VPN_PROTOCOL` | `vless` | VPN protocol (vless, shadowsocks, proxy-server) |
| `VPN_PORT` | `443` | VPN server port |
| `VPN_SNI` | `www.google.com` | SNI domain for Reality protocol |
| `VPN_INSTALL_PATH` | `/opt/vpn` | Installation directory |
| `VPN_CONFIG_PATH` | `/etc/vpn/config.toml` | Configuration file path |

### Proxy Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTH_PORT` | `3000` | Proxy auth service port |
| `DATABASE_PATH` | `/opt/vpn/users` | User database path |
| `LOG_LEVEL` | `info` | Log level (debug, info, warn, error) |

### Monitoring Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_USER` | `admin` | Grafana admin username |
| `GRAFANA_PASSWORD` | `admin` | Grafana admin password |

## Service Ports

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| VPN Server | 443 | UDP/TCP | Main VPN connection |
| HTTP Proxy | 8888 | TCP | HTTP/HTTPS proxy |
| HTTPS Proxy | 8443 | TCP | HTTPS proxy with auth |
| SOCKS5 Proxy | 1080 | TCP | SOCKS5 proxy |
| Traefik Dashboard | 8080 | HTTP | Proxy management UI |
| Prometheus | 9090 | HTTP | Metrics collection |
| Grafana | 3001 | HTTP | Monitoring dashboard |

## Data Persistence

The following volumes are created for data persistence:

- `vpn-data`: User configurations and keys
- `vpn-config`: Server configuration files
- `vpn-logs`: Application logs
- `traefik-certs`: SSL certificates
- `prometheus-data`: Metrics data
- `grafana-data`: Dashboard configurations

## Commands

### User Management

```bash
# Create a new user
docker exec vpn-server vpn users create alice

# List users
docker exec vpn-server vpn users list

# Generate connection link
docker exec vpn-server vpn users link alice --qr

# Show user details
docker exec vpn-server vpn users show alice
```

### Server Management

```bash
# Check server status
docker exec vpn-server vpn status

# Restart server
docker exec vpn-server vpn restart

# View logs
docker logs vpn-server

# Monitor real-time logs
docker logs -f vpn-server
```

### Proxy Management

```bash
# Check proxy status
docker exec vpn-server vpn proxy status

# Monitor connections
docker exec vpn-server vpn proxy monitor

# Test connectivity
docker exec vpn-server vpn proxy test
```

## Health Checks

All services include health checks:

```bash
# Check all service health
docker-compose ps

# Individual service health
docker exec vpn-server vpn status
curl http://localhost:3000/health  # Proxy auth
curl http://localhost:8080/ping    # Traefik
curl http://localhost:9090/-/healthy  # Prometheus
```

## Troubleshooting

### Common Issues

**Container fails to start:**
```bash
# Check logs
docker logs vpn-server

# Check permissions
docker exec vpn-server id
```

**VPN connection fails:**
```bash
# Check server status
docker exec vpn-server vpn status --detailed

# Check firewall
docker exec vpn-server vpn network-check

# Check configuration
docker exec vpn-server vpn config show
```

**Proxy authentication fails:**
```bash
# Check auth service
curl http://localhost:3000/health

# Check user database
docker exec vpn-server vpn users list

# Check auth logs
docker logs vpn-proxy-auth
```

### Debug Mode

Enable debug logging:

```bash
# Set environment variable
export LOG_LEVEL=debug

# Recreate containers
docker-compose up -d
```

### Performance Tuning

For production deployments:

```yaml
# Add to docker-compose.yml
services:
  vpn-server:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
        reservations:
          memory: 256M
          cpus: "0.5"
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

## Security Considerations

1. **Change default passwords:**
   ```bash
   export GRAFANA_PASSWORD=your-secure-password
   ```

2. **Use custom networks:**
   ```yaml
   networks:
     vpn-network:
       driver: bridge
       ipam:
         config:
           - subnet: 172.30.0.0/16
   ```

3. **Enable SSL/TLS:**
   ```bash
   # Generate certificates
   docker exec vpn-server vpn security generate
   ```

4. **Regular updates:**
   ```bash
   # Update images
   docker-compose pull
   docker-compose up -d
   ```

## Production Deployment

For production use, consider:

1. Use external databases
2. Set up log aggregation
3. Configure backup strategies
4. Implement monitoring alerts
5. Use container orchestration (Kubernetes)

See [PRODUCTION.md](PRODUCTION.md) for detailed production deployment guide.