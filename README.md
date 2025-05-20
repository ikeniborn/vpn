# Integrated VPN Solution Deployment Scripts

This repository contains deployment scripts for an integrated Shadowsocks/Outline Server + VLESS+Reality VPN solution. These scripts automate the deployment, management, and maintenance of the VPN system.

## Overview

The integrated VPN solution combines Shadowsocks (via Outline Server) with VLESS+Reality to provide a dual-layer encryption approach:

1. **First Layer**: Shadowsocks/Outline Server with ChaCha20-IETF-Poly1305 encryption and obfuscation
2. **Second Layer**: VLESS protocol with Reality TLS simulation for advanced fingerprinting evasion

This dual-layer approach provides enhanced security, obfuscation, and resistance to deep packet inspection.

## Features

- **Multi-Architecture Support**: Deploy on x86_64, ARM64, and ARMv7 platforms
- **Docker-Based**: Container isolation and easy deployment
- **Traffic Obfuscation**: Multiple layers of obfuscation to evade detection
- **Content-Based Routing**: Optimize traffic based on content type
- **Comprehensive Management**: User management, monitoring, backups, and more
- **Security Hardening**: Built-in security checks and firewall configuration
- **Maintenance Automation**: Scheduled tasks for system health and updates

## Scripts

### Core Deployment

- **`setup.sh`**: Main deployment script that orchestrates the entire installation process
- **`manage-users.sh`**: Unified user management for both Shadowsocks and VLESS+Reality

### Monitoring and Maintenance

- **`monitoring.sh`**: System health monitoring and performance metrics
- **`daily-maintenance.sh`**: Daily maintenance tasks (log rotation, disk space checks)
- **`weekly-maintenance.sh`**: Weekly maintenance tasks (updates, security checks)
- **`security-audit.sh`**: Comprehensive security audit of the VPN system

### Backup and Recovery

- **`backup.sh`**: Configuration backup with encryption and retention policies
- **`restore.sh`**: Restore system from backups

### Notifications

- **`alert.sh`**: Send alerts via email, SMS, or webhooks when issues are detected

## Requirements

- **OS**: Modern Linux distribution (Ubuntu 20.04+ recommended)
- **Hardware**: 
  - 2+ CPU cores (4+ recommended)
  - 2+ GB RAM (4+ GB recommended)
  - 20+ GB storage (40+ GB recommended)
  - Public IP address (static recommended)
- **Software**:
  - Docker and Docker Compose
  - bash, jq, curl, socat, netstat
  - UFW (Uncomplicated Firewall)

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/username/vpn-deployment.git
   cd vpn-deployment
   ```

2. Run the setup script:
   ```
   sudo ./scripts/setup.sh
   ```

3. Follow the prompts to configure your VPN server.

## Configuration

The setup script will create configuration files in the `/opt/vpn` directory:

- `/opt/vpn/outline-server/` - Outline Server (Shadowsocks) configuration
- `/opt/vpn/v2ray/` - VLESS+Reality configuration
- `/opt/vpn/docker-compose.yml` - Docker Compose configuration

## Usage

### Managing Users

```bash
# List all users
sudo ./scripts/manage-users.sh --list

# Add a new user
sudo ./scripts/manage-users.sh --add --name "john-laptop"

# Add a user with a specific password
sudo ./scripts/manage-users.sh --add --name "john-laptop" --password "secure_password"

# Remove a user
sudo ./scripts/manage-users.sh --remove --uuid "12345678-1234-5678-1234-567812345678"

# Export client configurations
sudo ./scripts/manage-users.sh --export --uuid "12345678-1234-5678-1234-567812345678"
```

### Monitoring

```bash
# Run health check monitoring
sudo ./scripts/monitoring.sh
```

### Backup and Restore

```bash
# Create a backup
sudo ./scripts/backup.sh --retention 30

# Create an encrypted backup
sudo ./scripts/backup.sh --encrypt --key "your-secure-passphrase"

# Restore from backup
sudo ./scripts/restore.sh --file /opt/vpn/backups/vpn-backup-20250519-120000.tar.gz
```

### Maintenance

```bash
# Run daily maintenance tasks
sudo ./scripts/daily-maintenance.sh

# Run weekly maintenance tasks
sudo ./scripts/weekly-maintenance.sh

# Run security audit
sudo ./scripts/security-audit.sh
```

## Security Considerations

- The scripts implement multiple security measures, including:
  - Secure file permissions for sensitive files
  - Firewall configuration with minimal port exposure
  - Regular security audits
  - Configuration backups
  - Docker container isolation

- Regular updates are recommended to maintain security:
  - Use `weekly-maintenance.sh` to update Docker images and system packages
  - Run `security-audit.sh` periodically to check for security issues

## Customization

The scripts are designed to be modular and customizable:

- Edit the configuration files in `/opt/vpn/` to customize your deployment
- Modify the routing rules in `/opt/vpn/v2ray/config.json` to optimize traffic routing
- Adjust alert thresholds in monitoring and maintenance scripts

## Troubleshooting

If you encounter issues:

1. Check the logs in `/opt/vpn/logs/`
2. Verify all containers are running: `docker ps`
3. Check service status: `./scripts/monitoring.sh`
4. Restore from a backup if needed: `./scripts/restore.sh`

## License

[MIT License](LICENSE)

## Acknowledgements

- [Outline Server](https://github.com/Jigsaw-Code/outline-server)
- [v2fly/v2ray-core](https://github.com/v2fly/v2ray-core)
- [VLESS Protocol](https://github.com/XTLS/VLESS)
- [Reality TLS](https://github.com/XTLS/REALITY)