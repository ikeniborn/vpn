# VPN Server Security Best Practices Guide

**Version**: 1.0  
**Date**: 2025-07-01  
**Classification**: Internal Use  
**Audience**: Security Teams, System Administrators, DevOps Engineers

## Table of Contents

1. [Security Overview](#security-overview)
2. [Installation Security](#installation-security)
3. [Network Security](#network-security)
4. [Access Control](#access-control)
5. [Certificate Management](#certificate-management)
6. [Monitoring & Logging](#monitoring--logging)
7. [Incident Response](#incident-response)
8. [Compliance & Auditing](#compliance--auditing)
9. [Hardening Checklist](#hardening-checklist)

## Security Overview

### Security Architecture

The VPN server implements a multi-layered security approach:

```text
┌─────────────────────────────────────────────────────────┐
│                  Internet / WAN                         │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                  Firewall                               │
│  • DDoS Protection    • Rate Limiting                   │
│  • IP Filtering      • Port Security                    │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                 Load Balancer (Traefik)                 │
│  • SSL/TLS Termination  • Header Security               │
│  • Auto HTTPS          • Access Logging                 │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                VPN Server (Xray)                        │
│  • VLESS+Reality      • Traffic Obfuscation             │
│  • Certificate Auth   • Zero-Knowledge Auth             │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│               Internal Network                           │
│  • User Authentication  • Privilege Management          │
│  • Audit Logging       • Resource Isolation             │
└─────────────────────────────────────────────────────────┘
```

### Security Principles

1. **Defense in Depth**: Multiple security layers
2. **Least Privilege**: Minimal access rights
3. **Zero Trust**: Verify everything, trust nothing
4. **Fail Secure**: Default to secure state on failures
5. **Auditability**: Complete logging and monitoring

## Installation Security

### Secure Installation Procedure

#### 1. System Preparation

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install security updates
sudo unattended-upgrades

# Configure automatic security updates
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
```

#### 2. User Account Security

```bash
# Create dedicated VPN user (non-root)
sudo useradd -r -s /bin/false vpn-server
sudo usermod -aG docker vpn-server

# Configure sudo access (if needed)
echo 'vpn-server ALL=(ALL) NOPASSWD: /usr/local/bin/vpn' >> /etc/sudoers.d/vpn-server

# Disable password authentication
sudo passwd -l vpn-server
```

#### 3. File System Security

```bash
# Set proper file permissions
sudo chown -R vpn-server:vpn-server /etc/vpn
sudo chmod 700 /etc/vpn
sudo chmod 600 /etc/vpn/config.toml
sudo chmod 600 /etc/vpn/certs/*

# Secure log directory
sudo chown vpn-server:adm /var/log/vpn
sudo chmod 750 /var/log/vpn
```

#### 4. Container Security

```bash
# Use security-focused installation
sudo vpn install \
  --protocol vless \
  --port 8443 \
  --security-hardened \
  --enable-firewall \
  --non-root-containers

# Verify security configuration
vpn security verify-installation
```

### Security Configuration

#### Core Security Settings

```toml
# /etc/vpn/config.toml
[security]
# Enable security features
enable_privilege_bracketing = true
enable_audit_logging = true
enable_rate_limiting = true
enable_intrusion_detection = true

# Authentication settings
max_auth_failures = 3
auth_failure_ban_time = "1h"
require_cert_validation = true
enable_2fa = true

# Network security
allowed_client_subnets = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
blocked_countries = ["CN", "RU", "KP"]  # Optional: country blocking
max_connections_per_ip = 3

# Certificate security
cert_rotation_interval = "90d"
require_cert_pinning = true
enable_cert_transparency = true
```

## Network Security

### Firewall Configuration

#### UFW (Uncomplicated Firewall) Setup

```bash
# Reset firewall
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (change port from default 22)
sudo ufw allow 2222/tcp

# Allow VPN port
sudo ufw allow 8443/tcp

# Allow monitoring (restrict to management network)
sudo ufw allow from 192.168.1.0/24 to any port 9090
sudo ufw allow from 192.168.1.0/24 to any port 3000

# Enable firewall
sudo ufw enable

# Verify configuration
sudo ufw status verbose
```

#### Advanced iptables Rules

```bash
# Drop invalid packets
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# Rate limiting for VPN connections
iptables -A INPUT -p tcp --dport 8443 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j DROP

# DDoS protection
iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# Block common attack patterns
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4
```

### Network Segmentation

#### Docker Network Security

```yaml
# docker-compose.yml - Security-focused network configuration
version: '3.8'

networks:
  vpn-frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.1.0/24
  vpn-backend:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.20.2.0/24
  monitoring:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.20.3.0/24

services:
  traefik:
    networks:
      - vpn-frontend
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE

  xray:
    networks:
      - vpn-frontend
      - vpn-backend
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
```

### SSL/TLS Security

#### Certificate Configuration

```bash
# Generate secure certificates
vpn security generate-certs \
  --algorithm ecdsa \
  --key-size 384 \
  --hash sha384 \
  --domain your-domain.com \
  --validity 90

# Configure TLS settings
vpn config set tls.min_version 1.3
vpn config set tls.cipher_suites "TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256"
vpn config set tls.enable_hsts true
vpn config set tls.hsts_max_age 31536000
```

## Access Control

### User Authentication

#### Multi-Factor Authentication

```bash
# Enable 2FA for admin users
vpn users enable-2fa admin --method totp

# Configure backup codes
vpn users generate-backup-codes admin

# Require 2FA for all new users
vpn config set auth.require_2fa true
vpn config set auth.2fa_grace_period "7d"
```

#### Role-Based Access Control

```bash
# Define user roles
vpn roles create admin --permissions all
vpn roles create operator --permissions "users:read,status:read,logs:read"
vpn roles create viewer --permissions "status:read"

# Assign roles to users
vpn users assign-role admin --role admin
vpn users assign-role operator1 --role operator
vpn users assign-role support1 --role viewer
```

### Privilege Management

#### Sudo Configuration

```bash
# /etc/sudoers.d/vpn-secure
Defaults:vpn-admin timestamp_timeout=5
Defaults:vpn-admin passwd_timeout=1
Defaults:vpn-admin passwd_tries=3
Defaults:vpn-admin logfile=/var/log/sudo-vpn.log

# Specific command permissions
vpn-admin ALL=(ALL) /usr/local/bin/vpn users create *
vpn-admin ALL=(ALL) /usr/local/bin/vpn users remove *
vpn-admin ALL=(ALL) /usr/local/bin/vpn restart
vpn-admin ALL=(ALL) /usr/local/bin/vpn backup create *

# Operator permissions (limited)
vpn-operator ALL=(ALL) NOPASSWD: /usr/local/bin/vpn status
vpn-operator ALL=(ALL) NOPASSWD: /usr/local/bin/vpn users list
vpn-operator ALL=(ALL) NOPASSWD: /usr/local/bin/vpn logs --tail *
```

#### Session Management

```bash
# Configure session timeouts
vpn config set security.session_timeout "30m"
vpn config set security.idle_timeout "15m"
vpn config set security.max_concurrent_sessions 3

# Enable session monitoring
vpn config set security.log_sessions true
vpn config set security.detect_concurrent_logins true
```

## Certificate Management

### Certificate Lifecycle

#### 1. Certificate Generation

```bash
# Generate CA certificate
vpn security ca-init \
  --common-name "VPN Root CA" \
  --country US \
  --organization "Your Organization" \
  --validity 10y

# Generate server certificates
vpn security cert-generate \
  --type server \
  --common-name "vpn.example.com" \
  --san "*.vpn.example.com,vpn.example.com" \
  --validity 90d

# Generate client certificates
vpn security cert-generate \
  --type client \
  --common-name "user@example.com" \
  --validity 30d
```

#### 2. Certificate Rotation

```bash
# Automated certificate rotation
vpn config set certs.auto_rotation true
vpn config set certs.rotation_threshold "30d"
vpn config set certs.rotation_schedule "0 2 * * 0"  # Weekly at 2 AM

# Manual certificate rotation
vpn security rotate-certs --type server --graceful
vpn security rotate-certs --type client --user username
```

#### 3. Certificate Revocation

```bash
# Revoke compromised certificate
vpn security revoke-cert --serial 123456789 --reason "key-compromise"

# Update CRL
vpn security update-crl

# Verify revocation
vpn security verify-cert --serial 123456789
```

### Certificate Pinning

```bash
# Enable certificate pinning
vpn config set security.cert_pinning true
vpn config set security.pin_backup_certs true

# Configure pinned certificates
vpn security pin-cert --cert /etc/vpn/certs/server.crt
vpn security pin-cert --cert /etc/vpn/certs/backup.crt
```

## Monitoring & Logging

### Security Logging

#### Log Configuration

```toml
# /etc/vpn/config.toml
[logging]
level = "info"
security_level = "debug"
audit_level = "info"

[logging.destinations]
syslog = true
file = "/var/log/vpn/security.log"
remote_syslog = "siem.example.com:514"

[logging.filters]
include_sensitive_data = false
log_client_ips = true  # Consider privacy implications
log_user_agents = true
log_connection_metadata = true
```

#### Security Events to Monitor

1. **Authentication Events**
   - Login attempts (successful/failed)
   - Certificate validation failures
   - 2FA attempts
   - Session creation/destruction

2. **Access Control Events**
   - Privilege escalation attempts
   - Unauthorized command execution
   - File access violations
   - Network access violations

3. **System Events**
   - Configuration changes
   - Certificate operations
   - Service restarts
   - Container operations

#### Log Analysis

```bash
# Real-time security monitoring
vpn security monitor --real-time

# Analyze authentication patterns
vpn logs security --filter "auth" --last 24h | \
  grep -E "(failed|success)" | \
  awk '{print $1, $2, $3, $6}' | \
  sort | uniq -c | sort -nr

# Check for brute force attacks
vpn security detect-bruteforce --threshold 10 --window 1h

# Generate security report
vpn security report --type comprehensive --period 7d
```

### Intrusion Detection

#### IDS Configuration

```bash
# Enable built-in IDS
vpn config set security.ids.enabled true
vpn config set security.ids.sensitivity "medium"

# Configure detection rules
vpn security ids-rules \
  --add "failed_auth_threshold=5" \
  --add "suspicious_user_agent_patterns=bot,scanner,crawler" \
  --add "connection_rate_limit=100/minute" \
  --add "data_transfer_threshold=10GB/hour"

# Set up automated responses
vpn config set security.ids.auto_block true
vpn config set security.ids.block_duration "1h"
vpn config set security.ids.notification_email "security@example.com"
```

#### External SIEM Integration

```bash
# Configure SIEM forwarding
vpn config set logging.siem.enabled true
vpn config set logging.siem.endpoint "https://siem.example.com/api/logs"
vpn config set logging.siem.api_key "your-siem-api-key"
vpn config set logging.siem.format "cef"  # Common Event Format
```

## Incident Response

### Incident Classification

#### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| **Critical** | Service down, security breach | 15 minutes | RCE, data breach, service outage |
| **High** | Degraded service, auth issues | 1 hour | Auth bypass, cert compromise |
| **Medium** | Performance issues, warnings | 4 hours | High resource usage, failed backups |
| **Low** | Minor issues, maintenance | 24 hours | Log rotation, user lockouts |

### Response Procedures

#### 1. Detection & Analysis

```bash
# Quick security assessment
vpn security scan --active-threats

# Check system integrity
vpn security verify-integrity --full

# Analyze recent activity
vpn logs security --last 1h --format json | \
  jq '.[] | select(.level == "ERROR" or .level == "WARN")'

# Check for indicators of compromise
vpn security ioc-scan --indicators /etc/vpn/threat-intel.txt
```

#### 2. Containment

```bash
# Immediate threat containment
vpn security quarantine --ip 192.168.1.100
vpn security disable-user suspicious-user
vpn security isolate-container vpn-server

# Enable enhanced monitoring
vpn config set security.enhanced_logging true
vpn config set security.log_all_connections true

# Create forensic snapshot
vpn security snapshot-create --type forensic --preserve-evidence
```

#### 3. Eradication

```bash
# Remove threats
vpn security threat-removal --auto-confirm=false

# Update security rules
vpn security update-rules --source threat-intel

# Patch vulnerabilities
vpn security patch-scan --apply-critical

# Regenerate compromised credentials
vpn security regenerate-keys --force
```

#### 4. Recovery

```bash
# Restore from clean backup
vpn backup restore /backup/pre-incident-backup.tar.gz --verify

# Gradual service restoration
vpn start --mode safe
vpn security verify-clean
vpn start --mode normal

# Monitor for 24 hours
vpn security monitor --enhanced --duration 24h
```

### Communication Plan

#### Internal Communication

```bash
# Incident declaration
vpn incident declare --severity critical --description "Security breach detected"

# Status updates
vpn incident update --id INC-001 --status "investigating" --message "Analyzing scope"

# Resolution
vpn incident resolve --id INC-001 --resolution "Threat contained and removed"
```

#### External Communication

```bash
# User notification (if needed)
vpn users notify --message "Temporary service disruption for security maintenance"

# Regulatory notification (if required)
vpn compliance notify-breach --regulator GDPR --timeline 72h
```

## Compliance & Auditing

### Compliance Frameworks

#### SOC 2 Type II

```bash
# Configure SOC 2 compliance
vpn compliance enable-soc2

# Generate compliance report
vpn compliance report --framework soc2 --period 12m

# Audit trail export
vpn audit export --format csv --period 12m --include-all
```

#### GDPR Compliance

```bash
# Enable GDPR features
vpn config set compliance.gdpr.enabled true
vpn config set compliance.gdpr.data_retention "24m"
vpn config set compliance.gdpr.right_to_erasure true

# Data processing record
vpn gdpr data-processing-record --export /tmp/dpr.pdf

# Personal data audit
vpn gdpr personal-data-audit --user-id user@example.com
```

### Audit Configuration

#### Audit Events

```toml
# /etc/vpn/audit.toml
[audit]
enabled = true
storage_path = "/var/log/vpn/audit"
retention_period = "7y"
encryption = true

[audit.events]
authentication = true
authorization = true
configuration_changes = true
user_management = true
certificate_operations = true
security_events = true
data_access = true

[audit.integrity]
signing_enabled = true
hash_algorithm = "sha384"
sign_interval = "1h"
```

#### Audit Reports

```bash
# Generate compliance audit
vpn audit report \
  --type compliance \
  --framework "SOC2,GDPR,ISO27001" \
  --period 12m \
  --output /tmp/compliance-audit.pdf

# Security audit
vpn audit report \
  --type security \
  --include-failed-attempts \
  --include-privilege-escalations \
  --period 30d

# Access audit
vpn audit report \
  --type access \
  --user all \
  --include-permissions \
  --period 90d
```

## Hardening Checklist

### System Hardening

#### Operating System

- [ ] **System Updates**
  - [ ] Latest OS patches installed
  - [ ] Automatic security updates enabled
  - [ ] Package manager signatures verified

- [ ] **Account Security**
  - [ ] Default accounts disabled/removed
  - [ ] Strong password policy enforced
  - [ ] SSH key-based authentication only
  - [ ] Root login disabled

- [ ] **Network Hardening**
  - [ ] Unnecessary services disabled
  - [ ] Firewall configured and enabled
  - [ ] Network time synchronization configured
  - [ ] DNS security (DNS over HTTPS/TLS)

- [ ] **File System Security**
  - [ ] File permissions properly set
  - [ ] Sensitive files encrypted
  - [ ] Mount points secured (noexec, nosuid)
  - [ ] Log file permissions restricted

#### Container Security

- [ ] **Image Security**
  - [ ] Images from trusted registries only
  - [ ] Image vulnerability scanning
  - [ ] Minimal base images used
  - [ ] Regular image updates

- [ ] **Runtime Security**
  - [ ] Non-root containers
  - [ ] Read-only root file systems
  - [ ] Capability dropping
  - [ ] Security profiles (AppArmor/SELinux)

- [ ] **Network Security**
  - [ ] Network segmentation
  - [ ] Encrypted communication
  - [ ] Resource limits set
  - [ ] Health checks configured

### Application Hardening

#### VPN Server

- [ ] **Authentication**
  - [ ] Strong authentication enabled
  - [ ] Certificate-based authentication
  - [ ] Multi-factor authentication
  - [ ] Account lockout policies

- [ ] **Encryption**
  - [ ] Strong cipher suites only
  - [ ] Perfect forward secrecy
  - [ ] Certificate pinning
  - [ ] Regular key rotation

- [ ] **Access Control**
  - [ ] Principle of least privilege
  - [ ] Role-based access control
  - [ ] Regular access reviews
  - [ ] Privileged access monitoring

- [ ] **Monitoring**
  - [ ] Comprehensive logging
  - [ ] Real-time monitoring
  - [ ] Intrusion detection
  - [ ] Incident response plan

### Security Testing

#### Regular Security Tests

```bash
# Weekly automated tests
#!/bin/bash
# /etc/cron.weekly/vpn-security-test

# Vulnerability scanning
vpn security scan --type vulnerability --report /var/log/vpn/vuln-scan.log

# Configuration audit
vpn security audit-config --report /var/log/vpn/config-audit.log

# Certificate validation
vpn security verify-certs --report /var/log/vpn/cert-check.log

# Network security test
vpn security network-test --report /var/log/vpn/network-test.log

# Send summary report
vpn security summary-report --email security@example.com
```

#### Penetration Testing

```bash
# External penetration testing (quarterly)
vpn security pen-test-prep --scope external --duration 1w

# Internal penetration testing (bi-annually)
vpn security pen-test-prep --scope internal --duration 2w

# Post-test remediation tracking
vpn security pen-test-followup --findings /tmp/pentest-findings.json
```

---

## Security Contacts

**Security Team**: security@example.com  
**Incident Response**: +1-XXX-XXX-XXXX  
**CISO**: ciso@example.com  
**Legal/Compliance**: legal@example.com

---

**Document Classification**: Internal Use  
**Last Updated**: 2025-07-01  
**Next Review**: 2025-10-01  
**Document Owner**: Security Team