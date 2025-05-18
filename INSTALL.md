# Installation Guide

This document provides detailed instructions for deploying the secure VPN service, including system preparation, installation steps, configuration, and validation.

## Table of Contents

- [Installation Guide](#installation-guide)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
    - [Hardware Requirements](#hardware-requirements)
    - [Software Requirements](#software-requirements)
    - [Network Requirements](#network-requirements)
  - [Pre-Installation Steps](#pre-installation-steps)
    - [DNS Configuration](#dns-configuration)
    - [System Preparation](#system-preparation)
  - [Installation Process](#installation-process)
    - [Clone Repository](#clone-repository)
    - [Configure Environment](#configure-environment)
    - [Run Setup Script](#run-setup-script)
    - [Configure Firewall](#configure-firewall)
    - [Verify System Security](#verify-system-security)
  - [Deploy VPN Services](#deploy-vpn-services)
    - [Start Docker Containers](#start-docker-containers)
    - [Verify Services](#verify-services)
  - [Post-Installation Steps](#post-installation-steps)
    - [Access Management Dashboard](#access-management-dashboard)
    - [Configure Monitoring Alerts](#configure-monitoring-alerts)
    - [Set Up Backup Schedule](#set-up-backup-schedule)
  - [Troubleshooting](#troubleshooting)
    - [Common Installation Issues](#common-installation-issues)

## Requirements

### Hardware Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| CPU | 2 cores | 4+ cores | Modern x86_64 CPU (Intel/AMD) |
| RAM | 4 GB | 8+ GB | Higher memory improves performance under load |
| Storage | 40 GB | 80+ GB | SSD strongly recommended for better performance |
| Network | 100 Mbps | 1 Gbps | Reliable connection with sufficient bandwidth |

### Software Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Operating System | Ubuntu 20.04 LTS or newer | Other Debian-based distributions may work but are not officially supported |
| Docker | 20.10 or newer | Will be installed by the setup script |
| Docker Compose | v2 or newer | Will be installed by the setup script |
| Bash | 4.0 or newer | Default on most modern Linux distributions |

### Network Requirements

| Requirement | Details |
|-------------|---------|
| Public IP Address | Static IP address recommended |
| Open Ports | 80 (HTTP), 443 (HTTPS) |
| Domain Name | Valid domain with ability to configure DNS records |
| ISP Restrictions | No VPN/proxy service blocking or port restrictions |

## Pre-Installation Steps

### DNS Configuration

Before installation, configure DNS records for your domains:

1. **Main domain for the VPN service**:
   - Create an A record pointing to your server's IP address
   - Example: `vpn.example.com → 203.0.113.1`

2. **Subdomains for services**:
   - Create A or CNAME records for each service:
     - `v2ray.example.com` (V2Ray VPN service)
     - `outline.example.com` (OutlineVPN service)
     - `management.example.com` (Admin dashboard)
     - `monitoring.example.com` (Prometheus)
     - `grafana.example.com` (Grafana dashboards)
     - `alerts.example.com` (Alertmanager)
     - `traefik.example.com` (Traefik dashboard)

3. **Allow DNS propagation**:
   - Wait for DNS changes to propagate (may take 24-48 hours)
   - Verify with: `dig +short your-domain.com`

### System Preparation

1. **Update your system**:
   ```bash
   sudo apt update
   sudo apt upgrade -y
   ```

2. **Install essential packages**:
   ```bash
   sudo apt install -y curl git wget nano
   ```

3. **Check time synchronization**:
   ```bash
   sudo timedatectl set-timezone UTC
   sudo apt install -y systemd-timesyncd
   sudo systemctl enable systemd-timesyncd
   sudo systemctl start systemd-timesyncd
   ```

4. **Check available disk space**:
   ```bash
   df -h
   ```

## Installation Process

### Clone Repository

1. **Choose an installation directory**:
   ```bash
   mkdir -p /opt/vpn-service
   cd /opt/vpn-service
   ```

2. **Clone the repository**:
   ```bash
   git clone https://github.com/ikeniborn/vpn.git .
   ```
   
   Or download and extract the archive:
   ```bash
   wget https://your-repository-url/archive/main.tar.gz
   tar -xzvf main.tar.gz
   cd vpn-main
   ```

3. **Set proper permissions**:
   ```bash
   chmod +x *.sh
   ```

### Configure Environment

1. **Create the .env file**:
   ```bash
   cp .env.example .env
   nano .env
   ```

2. **Configure the following essential variables**:
   ```properties
   # Domains
   WEB_HOST=www.example.com
   V2RAY_HOST=v2ray.example.com
   OUTLINE_HOST=outline.example.com
   MANAGEMENT_HOST=management.example.com
   MONITORING_HOST=monitoring.example.com
   GRAFANA_HOST=grafana.example.com
   ALERTMANAGER_HOST=alerts.example.com
   TRAEFIK_DASHBOARD_HOST=traefik.example.com
   
   # Credentials - CHANGE THESE TO STRONG PASSWORDS
   ADMIN_USERNAME=admin
   ADMIN_PASSWORD=changeThisPassword
   SS_PASSWORD=changeThisPassword
   
   # Let's Encrypt
   ACME_EMAIL=admin@example.com
   
   # Monitoring
   TELEGRAM_BOT_TOKEN=your_bot_token
   TELEGRAM_CHAT_ID=your_chat_id
   ```

3. **Generate secure passwords and update the .env file**:
   ```bash
   # Generate a secure password and copy to clipboard
   openssl rand -base64 32
   ```

### Run Setup Script

The setup script automates system preparation, Docker installation, security hardening, and directory creation.

1. **Make the script executable** (if not already):
   ```bash
   chmod +x setup.sh
   ```

2. **Run the setup script**:
   ```bash
   sudo ./setup.sh
   ```

3. **What the setup script does**:
   - Updates the system
   - Installs necessary packages
   - Installs Docker and Docker Compose
   - Configures system-level security settings
   - Sets up secure Docker configuration
   - Creates directories for Docker volumes
   - Runs initial security checks

### Configure Firewall

The firewall script secures your server by configuring UFW with appropriate rules.

1. **Run the firewall script**:
   ```bash
   sudo ./firewall.sh
   ```

2. **What the firewall script does**:
   - Configures UFW with secure defaults
   - Sets up port knocking for SSH
   - Allows only necessary ports (SSH, HTTP, HTTPS)
   - Configures IP forwarding for VPN traffic
   - Drops invalid packets
   - Prevents common network attacks

3. **Verify firewall configuration**:
   ```bash
   sudo ufw status verbose
   ```

### Verify System Security

1. **Run the security checks script**:
   ```bash
   sudo ./security-checks.sh
   ```

2. **Review the security report**:
   - Address any critical issues before proceeding
   - Make note of recommended improvements

## Deploy VPN Services

### Start Docker Containers

1. **Start the Docker containers**:
   ```bash
   docker-compose up -d
   ```

2. **Check container status**:
   ```bash
   docker-compose ps
   ```
   
   All containers should show as "Up" status. If any container shows an error status, check the logs:
   ```bash
   docker-compose logs [service_name]
   ```

3. **View real-time logs** (optional):
   ```bash
   docker-compose logs -f
   ```

### Verify Services

1. **Check if Traefik obtained SSL certificates**:
   ```bash
   docker-compose exec traefik cat /acme/acme.json | grep "Certificates"
   ```

2. **Check if all services are accessible via their domains**:
   - Open https://www.example.com in a browser (should show the cover website)
   - Try accessing the management interface at https://management.example.com
   - Verify Grafana at https://grafana.example.com

3. **Check if Prometheus is collecting metrics**:
   ```bash
   curl -s http://localhost:9090/-/healthy
   ```

## Post-Installation Steps

### Access Management Dashboard

1. **Log into the management dashboard**:
   - Navigate to `https://management.example.com`
   - Use the admin credentials specified in your `.env` file

2. **Create VPN user accounts**:
   - Navigate to the "Users" section
   - Click "Add User" and configure access credentials
   - See the [Administration Guide](ADMIN-GUIDE.md) for detailed user management instructions

### Configure Monitoring Alerts

1. **Access Grafana**:
   - Navigate to `https://grafana.example.com`
   - Log in with the credentials specified in your `.env` file

2. **Review the dashboards**:
   - Explore the "VPN Overview" dashboard
   - Check system metrics and VPN connection statistics

3. **Configure Telegram notifications** (if using):
   - Ensure the Telegram bot token and chat ID are correctly set in the `.env` file
   - Restart the alertmanager service:
     ```bash
     docker-compose restart alertmanager
     ```
   - Test the alert system:
     ```bash
     curl -H "Content-Type: application/json" -d '[{"labels":{"alertname":"TestAlert","severity":"info"},"annotations":{"summary":"This is a test alert"}}]' http://localhost:9093/api/v1/alerts
     ```

### Set Up Backup Schedule

1. **Review the backup configuration**:
   - Check the backup schedule in the `.env` file:
     ```properties
     BACKUP_CRON=0 2 * * *  # Default: Every day at 2 AM
     BACKUP_RETENTION_DAYS=7
     BACKUP_ENCRYPTION_PASSWORD=changeThisPassword
     ```

2. **Set up external backup storage** (recommended):
   - Configure a remote storage solution (e.g., S3, SFTP)
   - Update the backup service configuration as needed

3. **Test the backup system**:
   ```bash
   docker-compose exec backup /bin/sh -c "/usr/local/bin/create-backup.sh"
   ```

## Troubleshooting

### Common Installation Issues

1. **Docker containers fail to start**:
   - Check container logs: `docker-compose logs [service_name]`
   - Verify port availability: `netstat -tuln`
   - Check disk space: `df -h`

2. **Cannot obtain SSL certificates**:
   - Verify DNS records: `dig +short your-domain.com`
   - Check if ports 80 and 443 are open: `curl -I http://your-domain.com`
   - Review Traefik logs: `docker-compose logs traefik`

3. **Network connectivity issues**:
   - Check Docker network configuration: `docker network ls`
   - Verify firewall rules: `sudo ufw status`
   - Test internal container communication: `docker-compose exec [service1] ping [service2]`

4. **Resource constraints**:
   - Check system resources: `htop`
   - Review container resource usage: `docker stats`

For more troubleshooting information, see the [Administration Guide](ADMIN-GUIDE.md#troubleshooting).