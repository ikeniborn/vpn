# VPN Server Operations Guide

**Version**: 1.0  
**Date**: 2025-07-01  
**For**: VPN Server Administrators and DevOps Teams

## Table of Contents

1. [Installation & Setup](#installation--setup)
2. [Daily Operations](#daily-operations)
3. [Troubleshooting](#troubleshooting)
4. [Monitoring & Alerting](#monitoring--alerting)
5. [Backup & Recovery](#backup--recovery)
6. [Performance Tuning](#performance-tuning)
7. [Security Operations](#security-operations)
8. [Emergency Procedures](#emergency-procedures)

## Installation & Setup

### System Requirements

**Minimum Requirements:**
- OS: Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- RAM: 2GB minimum, 4GB recommended
- CPU: 2 cores minimum, 4 cores recommended
- Storage: 20GB minimum, 50GB recommended
- Network: 100Mbps uplink minimum

**Dependencies:**
- Docker 20.10+
- Docker Compose 2.0+
- Rust 1.70+ (for building from source)

### Quick Installation

```bash
# Install from pre-built binary
curl -sSL https://install.vpn-server.example.com | bash

# Or build from source
git clone https://github.com/vpn-project/vpn-server.git
cd vpn-server
cargo build --release
sudo cp target/release/vpn /usr/local/bin/
```

### Initial Configuration

```bash
# Initialize VPN server
sudo vpn install --protocol vless --port 8443 --sni www.google.com

# Verify installation
vpn status --detailed

# Create first user
sudo vpn users create admin
```

## Daily Operations

### Health Checks

Run these commands daily to ensure system health:

```bash
# Overall system status
vpn status

# Check all containers
vpn status --detailed

# Monitor resource usage
vpn monitor stats

# Check logs for errors
vpn logs --errors --tail 100
```

### User Management

```bash
# List all users
vpn users list

# Create new user
sudo vpn users create username

# Get user connection info
vpn users show username

# Disable user temporarily
sudo vpn users disable username

# Remove user permanently
sudo vpn users remove username --confirm
```

### Container Management

```bash
# List all containers
vpn compose ps

# Restart specific service
sudo vpn compose restart vpn-server

# View service logs
vpn compose logs vpn-server

# Scale monitoring services
sudo vpn compose scale prometheus=2
```

## Troubleshooting

### Common Issues & Solutions

#### 1. Container Won't Start

**Symptoms:**
- Container status shows "Exited" or "Dead"
- Service unavailable errors

**Diagnosis:**
```bash
# Check container status
vpn status --detailed

# Check container logs
vpn logs vpn-server --tail 50

# Check Docker daemon
sudo systemctl status docker

# Check port availability
vpn network check --port 8443
```

**Solutions:**
```bash
# Restart container
sudo vpn restart

# Check port conflicts
sudo netstat -tulpn | grep 8443

# Free up memory if needed
sudo docker system prune -f

# Restart Docker daemon if needed
sudo systemctl restart docker
```

#### 2. High Memory Usage

**Symptoms:**
- Memory usage > 80%
- Container OOM kills
- Slow performance

**Diagnosis:**
```bash
# Check memory usage
vpn monitor stats --memory

# Check Docker memory usage
docker stats

# Check system memory
free -h

# Check for memory leaks
vpn doctor --memory-check
```

**Solutions:**
```bash
# Clean up unused containers
sudo docker system prune -f

# Restart services to free memory
sudo vpn restart

# Adjust container memory limits
vpn config set container.memory_limit 512m

# Enable swap if needed (not recommended for production)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

#### 3. Network Connectivity Issues

**Symptoms:**
- Users can't connect
- Slow connection speeds
- Timeouts

**Diagnosis:**
```bash
# Check network status
vpn network status

# Test connectivity
vpn network test --external

# Check firewall rules
sudo ufw status verbose

# Check port accessibility
vpn network check --port 8443 --external
```

**Solutions:**
```bash
# Fix firewall rules
sudo vpn security fix-firewall

# Restart networking
sudo vpn compose restart traefik

# Check DNS resolution
nslookup your-domain.com

# Test with different protocols
vpn config set server.protocol trojan
sudo vpn restart
```

#### 4. Certificate Issues

**Symptoms:**
- SSL/TLS errors
- Certificate expired warnings
- Connection refused with SSL

**Diagnosis:**
```bash
# Check certificate status
vpn security cert-status

# Check certificate expiry
openssl x509 -in /etc/vpn/certs/server.crt -noout -dates

# Check certificate chain
vpn security verify-certs
```

**Solutions:**
```bash
# Renew certificates
sudo vpn security renew-certs

# Generate new certificates
sudo vpn security generate-certs --domain your-domain.com

# Restart with new certificates
sudo vpn restart
```

### Log Analysis

#### Important Log Locations

```bash
# Application logs
/var/log/vpn/
├── access.log      # Connection logs
├── error.log       # Error messages
├── audit.log       # Security events
└── performance.log # Performance metrics

# Container logs
docker logs vpn-server
docker logs vpn-traefik
docker logs vpn-prometheus

# System logs
journalctl -u vpn-server
```

#### Log Analysis Commands

```bash
# Find error patterns
vpn logs --grep "ERROR|FATAL" --last 24h

# Monitor real-time logs
vpn logs --follow

# Analyze connection patterns
grep "connection" /var/log/vpn/access.log | tail -100

# Check for security events
sudo vpn security audit-logs --last 7d
```

## Monitoring & Alerting

### Key Metrics to Monitor

1. **System Health**
   - CPU usage < 80%
   - Memory usage < 80%
   - Disk usage < 85%
   - Load average < number of cores

2. **Network Performance**
   - Connection latency < 100ms
   - Throughput > 80% of capacity
   - Packet loss < 1%
   - Active connections count

3. **Application Metrics**
   - Container restart count
   - Failed authentication attempts
   - Certificate expiry dates
   - API response times

### Setting Up Monitoring

```bash
# Enable built-in monitoring
sudo vpn compose scale prometheus=1 grafana=1

# Access monitoring dashboards
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000

# Configure alerting
vpn config set monitoring.alerts.email "admin@example.com"
vpn config set monitoring.alerts.slack_webhook "https://hooks.slack.com/..."
```

### Alert Thresholds

```yaml
# /etc/vpn/monitoring.yml
alerts:
  cpu_threshold: 80
  memory_threshold: 80
  disk_threshold: 85
  response_time_threshold: 500  # ms
  failed_auth_threshold: 10     # per minute
  cert_expiry_warning: 30       # days
```

## Backup & Recovery

### What to Backup

1. **Configuration Files**
   - `/etc/vpn/config.toml`
   - `/etc/vpn/users/*/config.json`
   - `/etc/vpn/certs/`

2. **Data Directories**
   - `/var/lib/vpn/data/`
   - `/var/log/vpn/`

3. **Docker Volumes**
   - Container persistent data
   - Database files

### Backup Procedures

#### Daily Automated Backup

```bash
# Create backup script
sudo vpn backup create-script --schedule daily --retention 30

# Manual backup
sudo vpn backup create --destination /backup/vpn-$(date +%Y%m%d)

# Verify backup
vpn backup verify /backup/vpn-20250701
```

#### Backup Script Example

```bash
#!/bin/bash
# /usr/local/bin/vpn-backup.sh

BACKUP_DIR="/backup/vpn"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/vpn-backup-$DATE"

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Backup configuration
cp -r /etc/vpn "$BACKUP_PATH/"

# Backup user data
cp -r /var/lib/vpn "$BACKUP_PATH/"

# Backup logs (last 7 days)
find /var/log/vpn -name "*.log" -mtime -7 -exec cp {} "$BACKUP_PATH/" \;

# Create archive
tar -czf "$BACKUP_PATH.tar.gz" -C "$BACKUP_DIR" "vpn-backup-$DATE"
rm -rf "$BACKUP_PATH"

# Clean old backups (keep 30 days)
find "$BACKUP_DIR" -name "vpn-backup-*.tar.gz" -mtime +30 -delete

echo "Backup completed: $BACKUP_PATH.tar.gz"
```

### Recovery Procedures

#### Complete System Recovery

```bash
# Stop services
sudo vpn stop

# Restore from backup
sudo vpn backup restore /backup/vpn-20250701.tar.gz

# Verify configuration
vpn config validate

# Start services
sudo vpn start

# Verify operation
vpn status --detailed
```

#### Partial Recovery

```bash
# Restore only user data
sudo vpn users restore /backup/vpn-20250701.tar.gz --users-only

# Restore only configuration
sudo vpn config restore /backup/vpn-20250701.tar.gz --config-only

# Restore specific user
sudo vpn users restore-user username /backup/vpn-20250701.tar.gz
```

## Performance Tuning

### System-Level Optimizations

```bash
# Optimize network settings
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 12582912 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 12582912 16777216' >> /etc/sysctl.conf
sysctl -p

# Optimize file descriptor limits
echo '* soft nofile 65536' >> /etc/security/limits.conf
echo '* hard nofile 65536' >> /etc/security/limits.conf

# Disable swap for better performance
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### Application-Level Optimizations

```bash
# Optimize Docker settings
vpn config set docker.pool_size 20
vpn config set docker.cache_ttl 60

# Optimize container resource limits
vpn config set container.cpu_limit 2.0
vpn config set container.memory_limit 1g

# Enable performance monitoring
vpn config set monitoring.performance true

# Apply optimizations
sudo vpn restart
```

### Performance Testing

```bash
# Run performance benchmark
vpn benchmark --duration 60s --connections 100

# Monitor during peak usage
vpn monitor performance --real-time

# Generate performance report
vpn performance report --last 30d
```

## Security Operations

### Security Checklist

#### Daily Security Tasks

- [ ] Review authentication logs
- [ ] Check for failed login attempts
- [ ] Verify certificate status
- [ ] Review firewall logs
- [ ] Check for security updates

```bash
# Daily security audit
sudo vpn security audit --daily

# Check for suspicious activity
sudo vpn security scan --threats

# Review access logs
vpn logs --security --last 24h
```

#### Weekly Security Tasks

- [ ] Update system packages
- [ ] Rotate log files
- [ ] Review user access
- [ ] Check backup integrity
- [ ] Scan for vulnerabilities

```bash
# Weekly security maintenance
sudo vpn security maintenance --weekly

# Update system
sudo apt update && sudo apt upgrade -y

# Rotate secrets
sudo vpn security rotate-secrets --age 7d
```

### Incident Response

#### Security Incident Procedure

1. **Detection & Assessment**
   ```bash
   # Check for active threats
   sudo vpn security scan --active-threats
   
   # Review recent logs
   vpn logs --security --last 1h
   
   # Check system integrity
   sudo vpn security verify-integrity
   ```

2. **Containment**
   ```bash
   # Block suspicious IPs
   sudo vpn security block-ip 192.168.1.100
   
   # Disable compromised users
   sudo vpn users disable suspicious-user
   
   # Enable enhanced logging
   vpn config set security.enhanced_logging true
   ```

3. **Eradication**
   ```bash
   # Remove threats
   sudo vpn security clean-threats
   
   # Update security rules
   sudo vpn security update-rules
   
   # Regenerate certificates if needed
   sudo vpn security regenerate-certs
   ```

4. **Recovery**
   ```bash
   # Restore from clean backup if needed
   sudo vpn backup restore /backup/known-good-backup.tar.gz
   
   # Restart services
   sudo vpn restart
   
   # Verify security posture
   sudo vpn security verify-all
   ```

## Emergency Procedures

### Emergency Contacts

```
Primary On-Call: +1-XXX-XXX-XXXX
Secondary On-Call: +1-XXX-XXX-XXXX
Security Team: security@example.com
Management: management@example.com
```

### Emergency Shutdown

```bash
# Immediate shutdown
sudo vpn emergency-stop

# Graceful shutdown with user notification
sudo vpn shutdown --graceful --notify-users

# Network isolation
sudo vpn network isolate
```

### Emergency Recovery

```bash
# Boot from recovery mode
sudo vpn recovery-mode start

# Minimal service start
sudo vpn start --minimal

# Emergency user access
sudo vpn emergency-access create --duration 1h
```

### Communication Templates

#### Service Disruption Notice

```
Subject: VPN Service Disruption - [TIMESTAMP]

Dear Users,

We are currently experiencing technical difficulties with our VPN service.

Incident Details:
- Start Time: [TIMESTAMP]
- Affected Services: [SERVICES]
- Estimated Resolution: [ETA]

Current Status:
[STATUS UPDATE]

We apologize for the inconvenience and are working to restore service as quickly as possible.

Updates will be provided every 30 minutes.

VPN Operations Team
```

#### Service Restoration Notice

```
Subject: VPN Service Restored - [TIMESTAMP]

Dear Users,

VPN service has been fully restored as of [TIMESTAMP].

Incident Summary:
- Duration: [DURATION]
- Root Cause: [CAUSE]
- Resolution: [RESOLUTION]

Preventive Measures:
[MEASURES TAKEN]

Thank you for your patience.

VPN Operations Team
```

## Maintenance Windows

### Planned Maintenance

```bash
# Schedule maintenance window
vpn maintenance schedule --start "2025-07-02 02:00" --duration 2h

# Notify users in advance
vpn users notify-maintenance --advance 24h

# Prepare maintenance checklist
vpn maintenance checklist --window-id MW-001
```

### Maintenance Checklist

#### Pre-Maintenance (T-24h)
- [ ] Notify users of upcoming maintenance
- [ ] Create full system backup
- [ ] Verify backup integrity
- [ ] Prepare rollback plan
- [ ] Test procedures in staging

#### Pre-Maintenance (T-1h)
- [ ] Send final user notification
- [ ] Verify team readiness
- [ ] Prepare monitoring tools
- [ ] Stage backup files
- [ ] Document baseline metrics

#### During Maintenance
- [ ] Stop services gracefully
- [ ] Perform updates/changes
- [ ] Test functionality
- [ ] Monitor system health
- [ ] Document any issues

#### Post-Maintenance
- [ ] Start services
- [ ] Verify full functionality
- [ ] Monitor for 1 hour
- [ ] Update documentation
- [ ] Send completion notice

---

## Support & Resources

### Getting Help

- **Documentation**: https://docs.vpn-project.example.com
- **Community Forum**: https://forum.vpn-project.example.com
- **Issue Tracker**: https://github.com/vpn-project/issues
- **Email Support**: support@example.com

### CLI Quick Reference

```bash
# Most common commands
vpn status                    # System status
vpn users list               # List users
sudo vpn users create USER   # Create user
vpn logs --tail 50          # Recent logs
sudo vpn restart            # Restart services
vpn backup create           # Create backup
vpn security audit          # Security check
vpn performance report      # Performance report
```

### Version Information

Run `vpn --version` to get current version information and build details.

---

**Last Updated**: 2025-07-01  
**Document Version**: 1.0  
**Next Review Date**: 2025-08-01