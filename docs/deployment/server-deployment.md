# Server Deployment Guide

This guide walks through deploying VPN Manager on a fresh Ubuntu/Debian server.

## Prerequisites

- Fresh Ubuntu 20.04+ or Debian 11+ server
- Root or sudo access
- At least 2GB RAM
- 10GB free disk space
- Internet connectivity

## Step 1: Initial Server Setup

### Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### Create Non-Root User (if needed)

```bash
# Create user
sudo adduser vpnadmin

# Add to sudo group
sudo usermod -aG sudo vpnadmin

# Switch to new user
su - vpnadmin
```

### Configure Firewall

```bash
# Install UFW if not present
sudo apt install -y ufw

# Allow SSH (adjust port if needed)
sudo ufw allow 22/tcp

# Allow VPN ports
sudo ufw allow 8443/tcp  # VLESS
sudo ufw allow 8443/udp  # VLESS
sudo ufw allow 1080/tcp  # SOCKS5
sudo ufw allow 8888/tcp  # HTTP Proxy
sudo ufw allow 51820/udp # WireGuard

# Enable firewall
sudo ufw --force enable
```

## Step 2: Install VPN Manager

### Clone and Install

```bash
# Clone repository
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# Run installation script
# This will install all system dependencies and set up Python environment
bash scripts/install.sh
```

The script will:
1. Install all required system packages
2. Set up Python virtual environment
3. Install VPN Manager and dependencies
4. Configure PATH
5. Run initial diagnostics

### Activate Environment

After installation, activate the environment:

```bash
# If using virtual environment created by script
source ~/.vpn-manager-venv/bin/activate

# Or reload shell to get PATH updates
source ~/.bashrc
```

## Step 3: Install Docker

VPN Manager requires Docker for running VPN servers:

```bash
# Install Docker
curl -fsSL https://get.docker.com | bash

# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login again or run
newgrp docker

# Verify Docker
docker --version
docker run hello-world
```

## Step 4: Configure VPN Manager

### Initialize Configuration

```bash
# Create initial configuration
vpn config init

# Edit configuration if needed
nano ~/.config/vpn-manager/config.toml
```

### Set Up Database

```bash
# Initialize database
vpn doctor --fix
```

## Step 5: Deploy Your First VPN Server

### Create VLESS Server

```bash
# Install VLESS server on port 8443
vpn server install --protocol vless --port 8443 --name my-vless

# Verify server is running
vpn server list
vpn server status my-vless
```

### Create First User

```bash
# Create a user
vpn users create john-doe --protocol vless

# Get connection details
vpn users show john-doe
```

## Step 6: System Service Setup (Optional)

### Create Systemd Service

Create `/etc/systemd/system/vpn-manager.service`:

```ini
[Unit]
Description=VPN Manager Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=forking
User=vpnadmin
Group=vpnadmin
Environment="PATH=/home/vpnadmin/.vpn-manager-venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/home/vpnadmin/.vpn-manager-venv/bin/vpn server start --all
ExecStop=/home/vpnadmin/.vpn-manager-venv/bin/vpn server stop --all
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable vpn-manager

# Start service
sudo systemctl start vpn-manager

# Check status
sudo systemctl status vpn-manager
```

## Step 7: Monitoring and Maintenance

### Set Up Logging

```bash
# View logs
vpn logs --tail 100

# Enable debug logging
vpn config set log_level DEBUG
```

### Monitor Resources

```bash
# Check server health
vpn doctor

# Monitor Docker containers
docker ps
docker stats

# Check system resources
htop
df -h
```

### Backup Configuration

```bash
# Backup user data and configs
tar -czf vpn-backup-$(date +%Y%m%d).tar.gz \
    ~/.config/vpn-manager \
    ~/.local/share/vpn-manager

# Copy to remote location
scp vpn-backup-*.tar.gz user@backup-server:/backups/
```

## Step 8: Security Hardening

### SSH Hardening

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Recommended settings:
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes
# Port 2222  # Change default port

# Restart SSH
sudo systemctl restart sshd
```

### Fail2Ban Setup

```bash
# Install fail2ban
sudo apt install -y fail2ban

# Create jail for VPN Manager
sudo nano /etc/fail2ban/jail.local
```

Add to jail.local:

```ini
[vpn-manager]
enabled = true
port = 8443,1080,8888
filter = vpn-manager
logpath = /home/vpnadmin/.local/share/vpn-manager/logs/*.log
maxretry = 5
bantime = 3600
```

### Regular Updates

```bash
# System updates
sudo apt update && sudo apt upgrade -y

# Update VPN Manager
cd ~/vpn-manager
git pull
bash scripts/install.sh
```

## Troubleshooting

### Common Issues

#### Permission Denied

```bash
# Fix Docker permissions
sudo usermod -aG docker $USER
newgrp docker
```

#### Port Already in Use

```bash
# Find process using port
sudo netstat -tulpn | grep :8443
sudo lsof -i :8443

# Kill process if needed
sudo kill -9 <PID>
```

#### Virtual Environment Issues

```bash
# Recreate virtual environment
rm -rf ~/.vpn-manager-venv
cd ~/vpn-manager
bash scripts/install.sh
```

### Getting Help

```bash
# Run diagnostics
vpn doctor

# Check logs
vpn logs --level error

# Get system info
vpn doctor --system-info
```

## Production Checklist

Before going live:

- [ ] Firewall configured and enabled
- [ ] SSH hardened
- [ ] Fail2ban configured
- [ ] Regular backup scheduled
- [ ] Monitoring set up
- [ ] SSL certificates configured (if using web UI)
- [ ] Resource limits set for Docker
- [ ] Log rotation configured
- [ ] Update notifications enabled

## Next Steps

- [User Management Guide](../user-guide/user-management.md)
- [Server Configuration](../admin-guide/server-config.md)
- [Monitoring Guide](../admin-guide/monitoring.md)
- [Backup and Recovery](../admin-guide/backup.md)