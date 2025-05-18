# VPN Administration Guide

This guide provides comprehensive instructions for administering the secure VPN service, including user management, maintenance tasks, monitoring, backup procedures, troubleshooting, and security incident response.

## Table of Contents

- [User Management](#user-management)
  - [Adding New Users](#adding-new-users)
  - [Modifying User Accounts](#modifying-user-accounts)
  - [Revoking User Access](#revoking-user-access)
  - [Managing User Bandwidth](#managing-user-bandwidth)
- [Maintenance Tasks](#maintenance-tasks)
  - [Scheduled Maintenance](#scheduled-maintenance)
  - [System Updates](#system-updates)
  - [Certificate Renewal](#certificate-renewal)
  - [Service Restart Procedures](#service-restart-procedures)
- [Monitoring System](#monitoring-system)
  - [Accessing Dashboards](#accessing-dashboards)
  - [Interpreting Metrics](#interpreting-metrics)
  - [Alert Configuration](#alert-configuration)
  - [Custom Dashboard Setup](#custom-dashboard-setup)
- [Backup and Restore](#backup-and-restore)
  - [Backup Configuration](#backup-configuration)
  - [Manual Backup Procedure](#manual-backup-procedure)
  - [Restore from Backup](#restore-from-backup)
  - [Testing Backups](#testing-backups)
- [Troubleshooting](#troubleshooting)
  - [Common VPN Issues](#common-vpn-issues)
  - [Monitoring Issues](#monitoring-issues)
  - [Service Failures](#service-failures)
  - [Networking Problems](#networking-problems)
- [Security Incident Response](#security-incident-response)
  - [Detecting Incidents](#detecting-incidents)
  - [Containment Procedures](#containment-procedures)
  - [Recovery Steps](#recovery-steps)
  - [Post-Incident Analysis](#post-incident-analysis)

## User Management

### Adding New Users

The VPN system supports two VPN protocols: V2Ray (VMess) and OutlineVPN (Shadowsocks). Each requires a different user creation process.

#### V2Ray Users

1. **Access the management dashboard**:
   - Navigate to `https://management.example.com`
   - Log in with administrator credentials

2. **Create V2Ray user**:
   - Navigate to "User Management" → "V2Ray Users"
   - Click "Add New User"
   - Complete the form with:
     - Username (alphanumeric, no spaces)
     - Email (optional, for notifications)
     - Traffic limit (in GB, 0 for unlimited)
     - Expiration date (optional)
   - Click "Create User"

3. **User credentials**:
   - The system will generate a UUID for the user
   - Copy the configuration details or share the QR code with the user

4. **Manual configuration (alternative)**:
   - Edit the V2Ray configuration file directly:
   ```bash
   docker-compose exec -it v2ray sh
   nano /etc/v2ray/config.json
   ```
   - Add a new client in the `inbounds[0].settings.clients` array:
   ```json
   {
     "id": "generate-new-uuid-here",
     "alterId": 0,
     "security": "auto",
     "level": 0
   }
   ```
   - Generate a UUID using: `cat /proc/sys/kernel/random/uuid`
   - Save the file and restart V2Ray: `docker-compose restart v2ray`

#### OutlineVPN (Shadowsocks) Users

1. **Access the management dashboard**:
   - Navigate to "User Management" → "Outline Users"
   - Click "Add New User"
   - Complete the form with:
     - Username
     - Password (or use auto-generated)
     - Traffic limit (in GB)
     - Encryption method (default: chacha20-ietf-poly1305)

2. **Alternative method (manual configuration)**:
   - Edit the Outline configuration file:
   ```bash
   docker-compose exec -it outline sh
   nano /etc/shadowsocks-libev/config.json
   ```
   - Add a new user to the `users` object:
   ```json
   "users": {
     "username": {
       "password": "strong-password",
       "method": "chacha20-ietf-poly1305",
       "enable": true,
       "traffic_limit": 107374182400
     }
   }
   ```
   - Save the file and restart Outline: `docker-compose restart outline`

3. **Share connection details**:
   - Provide the user with the server address, port, password, encryption method, and plugin settings
   - Alternatively, generate a QR code or Outline connection link from the management dashboard

### Modifying User Accounts

1. **Access user management**:
   - Navigate to the respective user management section in the dashboard
   - Find the user you want to modify

2. **Edit user properties**:
   - Click "Edit" next to the user
   - Modify allowed parameters (traffic limits, expiration date)
   - Click "Save Changes"

3. **Manual modifications**:
   - Edit the respective configuration file for V2Ray or Outline
   - Modify the user's configuration
   - Restart the affected service

### Revoking User Access

1. **Immediate access revocation**:
   - Navigate to user management
   - Select the user(s) to revoke
   - Click "Revoke Access"
   - Confirm the action

2. **Alternative method (V2Ray)**:
   - Edit `/etc/v2ray/config.json`
   - Remove the client's entry from the `clients` array
   - Restart V2Ray: `docker-compose restart v2ray`

3. **Alternative method (Outline)**:
   - Edit `/etc/shadowsocks-libev/config.json`
   - Set the user's `enable` property to `false` or remove the user entry
   - Restart Outline: `docker-compose restart outline`

### Managing User Bandwidth

1. **View bandwidth usage**:
   - Navigate to "User Management" → "Bandwidth Reports"
   - Filter by date range, username, or protocol

2. **Set bandwidth limits**:
   - Edit a user's profile
   - Update the traffic limit value (in GB)
   - Save changes

3. **Bandwidth alerts**:
   - Configure threshold alerts in "System" → "Alerts"
   - Set percentage thresholds (e.g., 80%, 90%, 100%)
   - Configure notification methods

## Maintenance Tasks

### Scheduled Maintenance

The system includes a maintenance script that performs routine tasks to keep the VPN service running optimally.

1. **View maintenance schedule**:
   ```bash
   crontab -l | grep maintenance
   ```

2. **Adjust maintenance schedule**:
   ```bash
   crontab -e
   ```
   - Default schedule (weekly maintenance at 3 AM Sunday):
   ```
   0 3 * * 0 /opt/vpn-service/maintenance.sh > /var/log/vpn-maintenance.log 2>&1
   ```

3. **Run maintenance manually**:
   ```bash
   sudo ./maintenance.sh
   ```

4. **What the maintenance script does**:
   - Updates container images
   - Rotates logs
   - Checks for security updates
   - Performs system cleanup
   - Verifies service integrity

### System Updates

1. **Update container images**:
   ```bash
   docker-compose pull
   docker-compose up -d
   ```

2. **Update host system**:
   ```bash
   sudo apt update
   sudo apt upgrade -y
   sudo reboot  # If kernel updates require a restart
   ```

3. **Update VPN service scripts**:
   ```bash
   git pull  # If installed from a git repository
   chmod +x *.sh  # Ensure scripts are executable
   ```

### Certificate Renewal

Let's Encrypt certificates are automatically renewed by Traefik, but you can manually trigger renewal if needed:

1. **Check certificate status**:
   ```bash
   docker-compose exec traefik cat /acme/acme.json | grep "Certificates"
   ```

2. **Force certificate renewal**:
   ```bash
   # Remove the acme.json file
   docker-compose exec traefik rm /acme/acme.json
   # Restart Traefik
   docker-compose restart traefik
   ```

3. **Verify renewal**:
   ```bash
   # Check the Traefik logs
   docker-compose logs traefik | grep "certificate"
   ```

### Service Restart Procedures

1. **Restart all services**:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

2. **Restart specific service**:
   ```bash
   docker-compose restart [service_name]
   ```
   - Example: `docker-compose restart v2ray`

3. **Proper shutdown procedure**:
   ```bash
   # Graceful shutdown
   docker-compose down
   
   # If planning to restart the host
   sudo shutdown -r now
   
   # If shutting down completely
   sudo shutdown -h now
   ```

## Monitoring System

### Accessing Dashboards

1. **Grafana Dashboard**:
   - URL: `https://grafana.example.com`
   - Default credentials: username and password from `.env` file
   - Main dashboard: "VPN Overview"

2. **Prometheus**:
   - URL: `https://monitoring.example.com`
   - Used for direct query and debugging

3. **Alertmanager**:
   - URL: `https://alerts.example.com`
   - View and manage active alerts

### Interpreting Metrics

The VPN monitoring system tracks several key metrics:

1. **System metrics**:
   - CPU, memory, disk, and network usage
   - Container health and uptime

2. **VPN-specific metrics**:
   - Number of active connections
   - Bandwidth usage per protocol
   - Connection success/failure rate
   - Geographic distribution of connections

3. **Security metrics**:
   - Authentication failures
   - Unusual traffic patterns
   - Firewall block events

4. **Key dashboard panels**:
   - **Active Connections**: Shows current number of VPN clients
   - **Bandwidth Usage**: Network throughput over time
   - **Connection Success Rate**: Percentage of successful connections
   - **System Load**: Server resource utilization
   - **Service Health**: Status of all Docker containers

### Alert Configuration

1. **View existing alerts**:
   - Navigate to Alertmanager: `https://alerts.example.com`
   - Or check Prometheus rules: `https://monitoring.example.com/rules`

2. **Configure Telegram alerts**:
   - Ensure Telegram settings are in `.env`:
     ```
     TELEGRAM_BOT_TOKEN=your_bot_token
     TELEGRAM_CHAT_ID=your_chat_id
     ```
   - Restart Alertmanager: `docker-compose restart alertmanager`

3. **Add/modify alert rules**:
   - Edit `/monitoring/rules/alerts.yml`
   - Follow the Prometheus alerting rule format
   - Restart Prometheus: `docker-compose restart monitoring`

4. **Test alert delivery**:
   ```bash
   curl -H "Content-Type: application/json" -d '[{"labels":{"alertname":"TestAlert","severity":"info"},"annotations":{"summary":"This is a test alert"}}]' http://localhost:9093/api/v1/alerts
   ```

### Custom Dashboard Setup

1. **Create new dashboard**:
   - In Grafana, click "+ Create" → "Dashboard"
   - Add panels as needed
   - Use PromQL queries to visualize data

2. **Example PromQL queries**:
   - VPN connections: `sum(v2ray_connection_active)`
   - Bandwidth: `rate(v2ray_traffic_uplink[5m])`
   - Failed logins: `increase(vpn_auth_failure_total[24h])`

3. **Save and share**:
   - Save dashboard with a descriptive name
   - Set permissions (public or private)
   - Share the dashboard URL with administrators

## Backup and Restore

### Backup Configuration

The VPN service includes an automated backup system that takes regular snapshots of critical data.

1. **Backup configuration**:
   - Review settings in `.env` file:
     ```properties
     BACKUP_CRON=0 2 * * *  # Every day at 2 AM
     BACKUP_RETENTION_DAYS=7
     BACKUP_ENCRYPTION_PASSWORD=changeThisPassword
     ```

2. **Backup contents**:
   - Traefik certificates and configuration
   - VPN service configurations
   - User data and access credentials
   - Monitoring dashboards and rules

3. **Backup storage**:
   - Backups are stored in the `backup_data` volume
   - Path inside container: `/archive`
   - Encrypted with the password from `.env`

### Manual Backup Procedure

1. **Trigger manual backup**:
   ```bash
   docker-compose exec backup /bin/sh -c "/usr/local/bin/create-backup.sh"
   ```

2. **Verify backup creation**:
   ```bash
   docker-compose exec backup ls -la /archive
   ```

3. **External backup storage** (recommended):
   - Create a script to copy backups to external storage:
   ```bash
   #!/bin/bash
   # Copy latest backup to external storage
   LATEST_BACKUP=$(docker-compose exec backup find /archive -type f -name "vpn-backup-*.tar.gz.enc" -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2)
   docker cp vpn_backup:$LATEST_BACKUP /path/to/external/storage/
   ```

### Restore from Backup

1. **List available backups**:
   ```bash
   docker-compose exec backup ls -la /archive
   ```

2. **Stop services before restore**:
   ```bash
   docker-compose down
   ```

3. **Restore from backup**:
   ```bash
   # Extract backup file
   docker run --rm -v vpn_backup_data:/archive -v /tmp:/restore offen/docker-volume-backup:latest \
     sh -c "decrypt-backup.sh /archive/vpn-backup-YYYY-MM-DD_HH-MM-SS.tar.gz.enc /tmp/backup.tar.gz $BACKUP_ENCRYPTION_PASSWORD && \
     tar -xzf /tmp/backup.tar.gz -C /tmp/restore"
   
   # Copy restored files to volumes
   docker run --rm -v /tmp/restore:/restore -v vpn_traefik_data:/traefik_data \
     -v vpn_outline_data:/outline_data -v vpn_v2ray_data:/v2ray_data \
     -v vpn_management_data:/management_data -v vpn_monitoring_data:/monitoring_data \
     alpine:latest sh -c "cp -rf /restore/traefik_data/* /traefik_data/ && \
     cp -rf /restore/outline_data/* /outline_data/ && \
     cp -rf /restore/v2ray_data/* /v2ray_data/ && \
     cp -rf /restore/management_data/* /management_data/ && \
     cp -rf /restore/monitoring_data/* /monitoring_data/"
   
   # Start services
   docker-compose up -d
   ```

### Testing Backups

It's critical to regularly test your backup and restore procedures to ensure they work when needed.

1. **Schedule regular backup tests**:
   - Quarterly or after significant configuration changes
   - Document the testing process and results

2. **Test recovery procedure**:
   - Set up a separate test environment (different server)
   - Restore the backup to this environment
   - Verify all services work as expected

3. **Validate restored data**:
   - Check user accounts and configurations
   - Verify monitoring dashboards
   - Test VPN connectivity with sample accounts

## Troubleshooting

### Common VPN Issues

1. **Users cannot connect**:
   - Check if the service is running: `docker-compose ps`
   - Verify firewall rules: `sudo ufw status`
   - Check service logs: `docker-compose logs v2ray` or `docker-compose logs outline`
   - Test connectivity from the server: `curl -I https://v2ray.example.com`

2. **Slow connection speeds**:
   - Check server load: `htop`
   - Check bandwidth usage: `vnstat -l`
   - Verify network saturation: `iftop`
   - Consider upgrading server resources or optimizing configurations

3. **Authentication failures**:
   - Check user credentials in configuration files
   - Verify TLS certificates are valid
   - Check for IP blocking rules

4. **Traffic obfuscation issues**:
   - Review obfuscation settings
   - Check if DPI is detected and blocked
   - Try alternative obfuscation methods

### Monitoring Issues

1. **Missing metrics**:
   - Check Prometheus configuration: `docker-compose exec monitoring cat /etc/prometheus/prometheus.yml`
   - Verify target services are running
   - Check for scrape errors in Prometheus logs: `docker-compose logs monitoring`

2. **Alert system not working**:
   - Check Alertmanager configuration
   - Verify Telegram bot token and chat ID
   - Test alert routing manually

3. **Grafana dashboard issues**:
   - Check Grafana logs: `docker-compose logs grafana`
   - Verify data source connectivity
   - Rebuild dashboards if necessary

### Service Failures

1. **Container won't start**:
   - Check logs: `docker-compose logs [service_name]`
   - Verify volume permissions
   - Check for port conflicts: `netstat -tuln`
   - Inspect container status: `docker inspect [container_id]`

2. **Certificate issues**:
   - Check Traefik logs: `docker-compose logs traefik`
   - Verify DNS settings
   - Check rate limits with Let's Encrypt
   - Manually request certificates if needed

3. **Database corruption**:
   - Stop affected services
   - Restore from backup
   - Check disk health: `smartctl -a /dev/sda`

### Networking Problems

1. **DNS resolution issues**:
   - Check DNS settings: `cat /etc/resolv.conf`
   - Test DNS resolution: `dig v2ray.example.com`
   - Verify domain records: `dig +trace v2ray.example.com`

2. **Connectivity problems**:
   - Check network interfaces: `ip addr`
   - Verify routing table: `ip route`
   - Test internal Docker networks: `docker network inspect vpn_frontend`

3. **Firewall issues**:
   - Review UFW rules: `sudo ufw status numbered`
   - Check iptables directly: `sudo iptables -L -n -v`
   - Temporarily disable firewall to test: `sudo ufw disable` (Remember to enable after testing)

## Security Incident Response

### Detecting Incidents

Monitor these indicators for potential security incidents:

1. **Unusual authentication patterns**:
   - Multiple failed login attempts
   - Logins from unexpected locations
   - Authentication attempts outside normal hours

2. **Unusual traffic patterns**:
   - Sudden traffic spikes
   - Connections to suspicious IP addresses
   - Unexpected protocols or ports

3. **System anomalies**:
   - Unexpected service restarts
   - Modified configuration files
   - Unusual system resource usage

4. **Monitoring alerts**:
   - Configure alerts for potential security incidents
   - Monitor fail2ban logs: `tail -f /var/log/fail2ban.log`
   - Check system logs: `journalctl -xe`

### Containment Procedures

If a security incident is detected:

1. **Immediate containment**:
   - Isolate affected systems:
     ```bash
     # Disconnect from internet (emergencies only)
     sudo ufw default deny outgoing
     sudo ufw default deny incoming
     sudo ufw enable
     ```
   
   - Block suspicious IPs:
     ```bash
     sudo ufw insert 1 deny from [suspicious_ip] to any
     ```
   
   - Disable compromised accounts:
     - Remove user from VPN configurations
     - Restart affected VPN services

2. **Evidence preservation**:
   - Capture volatile data:
     ```bash
     # Running processes
     ps aux > /tmp/running_processes.txt
     
     # Network connections
     netstat -antup > /tmp/network_connections.txt
     
     # Open files
     lsof > /tmp/open_files.txt
     ```
   
   - Preserve logs:
     ```bash
     # Copy all logs
     mkdir -p /tmp/incident_logs
     cp -r /var/log/* /tmp/incident_logs/
     docker-compose logs > /tmp/incident_logs/docker-compose.log
     ```

3. **Communication**:
   - Notify security team
   - Document incident timeline
   - Consider regulatory notification requirements

### Recovery Steps

After containing the incident:

1. **System restoration**:
   - Restore from known good backup if necessary
   - Reset admin credentials
   - Regenerate VPN cryptographic material
   - Update all software to latest versions

2. **Security hardening**:
   - Run security checks: `sudo ./security-checks.sh`
   - Update firewall rules
   - Implement additional security controls

3. **Service restoration**:
   - Gradually restore connectivity
   - Verify system integrity
   - Test VPN functionality

### Post-Incident Analysis

After recovering from the incident:

1. **Root cause analysis**:
   - Determine entry point
   - Identify vulnerabilities exploited
   - Document attack timeline

2. **Improvements**:
   - Update security controls
   - Enhance monitoring
   - Revise incident response procedures

3. **Documentation**:
   - Create incident report
   - Update response playbooks
   - Share lessons learned (internal only)