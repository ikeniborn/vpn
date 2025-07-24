# Production Security Hardening Guide

This guide provides a comprehensive security hardening checklist for deploying the VPN system in production environments.

## Table of Contents

1. [Container Security](#container-security)
2. [Network Security](#network-security)
3. [Data Security](#data-security)
4. [Access Control](#access-control)
5. [Monitoring & Auditing](#monitoring--auditing)
6. [Deployment Checklist](#deployment-checklist)

## Container Security

### Base Image Security

- [ ] Use minimal base images (Alpine Linux preferred)
- [ ] Scan all images for vulnerabilities before deployment
- [ ] Pin image versions - never use `latest` tag in production
- [ ] Regularly update base images with security patches
- [ ] Verify image signatures and checksums

### Container Runtime Security

- [ ] Run containers as non-root users
- [ ] Drop all unnecessary capabilities
- [ ] Enable read-only root filesystem where possible
- [ ] Use security options: `no-new-privileges:true`
- [ ] Implement resource limits (CPU, memory, file descriptors)
- [ ] Mount temporary filesystems with `noexec,nosuid` options

### Example Configuration

```yaml
services:
  vpn-server:
    user: "1000:1000"
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE
    tmpfs:
      - /tmp:noexec,nosuid,size=100M
```

## Network Security

### Network Isolation

- [ ] Use encrypted overlay networks for inter-service communication
- [ ] Implement network segmentation (separate networks for different tiers)
- [ ] Disable inter-container communication where not needed
- [ ] Use internal networks for services that don't need external access
- [ ] Implement egress filtering

### TLS Configuration

- [ ] Enable TLS 1.2 minimum for all communications
- [ ] Use strong cipher suites only
- [ ] Implement certificate pinning where applicable
- [ ] Regular certificate rotation (every 90 days)
- [ ] Enable HSTS with preload

### Firewall Rules

```bash
# Example iptables rules for VPN server
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -j DROP
```

## Data Security

### Secrets Management

- [ ] Use Docker secrets for sensitive data
- [ ] Never store secrets in environment variables
- [ ] Rotate all secrets regularly (at least every 90 days)
- [ ] Implement secret versioning
- [ ] Audit secret access

### Data Encryption

- [ ] Encrypt data at rest (database, volumes)
- [ ] Encrypt data in transit (TLS/SSL)
- [ ] Use strong encryption algorithms (AES-256)
- [ ] Implement key rotation policies
- [ ] Secure key storage (HSM or KMS)

### Database Security

- [ ] Enable SSL/TLS for database connections
- [ ] Use strong authentication (SCRAM-SHA-256)
- [ ] Implement connection limits
- [ ] Enable query logging for audit
- [ ] Regular security updates

## Access Control

### Authentication

- [ ] Implement multi-factor authentication (MFA)
- [ ] Use strong password policies
- [ ] Implement account lockout policies
- [ ] Regular password rotation
- [ ] Centralized authentication (LDAP/OAuth2)

### Authorization

- [ ] Implement Role-Based Access Control (RBAC)
- [ ] Principle of least privilege
- [ ] Regular access reviews
- [ ] Audit trail for all access
- [ ] Time-based access controls

### SSH Hardening

```bash
# /etc/ssh/sshd_config
Protocol 2
Port 22
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers vpnadmin
```

## Monitoring & Auditing

### Security Monitoring

- [ ] Implement centralized logging
- [ ] Real-time security alerting
- [ ] Anomaly detection
- [ ] Failed authentication monitoring
- [ ] Resource usage monitoring

### Audit Requirements

- [ ] Log all administrative actions
- [ ] Log all authentication attempts
- [ ] Log all configuration changes
- [ ] Log all data access
- [ ] Retain logs for compliance period

### Security Metrics

```yaml
# Prometheus alerts for security monitoring
groups:
  - name: security
    rules:
      - alert: TooManyFailedLogins
        expr: rate(auth_failed_total[5m]) > 10
        annotations:
          summary: "High rate of failed authentication attempts"
      
      - alert: UnauthorizedAccess
        expr: unauthorized_access_total > 0
        annotations:
          summary: "Unauthorized access attempt detected"
```

## Deployment Checklist

### Pre-Deployment

- [ ] Security assessment completed
- [ ] Vulnerability scan passed
- [ ] Security configurations reviewed
- [ ] Secrets properly configured
- [ ] Backup and recovery tested

### Deployment

- [ ] Use secure deployment pipeline
- [ ] Implement blue-green deployment
- [ ] Enable health checks
- [ ] Configure auto-rollback
- [ ] Document deployment process

### Post-Deployment

- [ ] Verify security configurations
- [ ] Test security controls
- [ ] Monitor for anomalies
- [ ] Update security documentation
- [ ] Schedule security review

## Security Configuration Files

### 1. Docker Compose Security Override

Create `docker-compose.security.yml`:

```yaml
version: '3.8'

x-security-defaults: &security-defaults
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  read_only: true

services:
  vpn-server:
    <<: *security-defaults
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE
```

### 2. Environment Variables

Create `.env.production`:

```bash
# Security settings
ENABLE_AUDIT_LOG=true
ENABLE_SECURITY_HEADERS=true
ENABLE_RATE_LIMITING=true
SSL_PROTOCOLS="TLSv1.2 TLSv1.3"
```

### 3. Deploy Script

```bash
#!/bin/bash
# secure-deploy.sh

set -euo pipefail

# Verify security configurations
docker-compose -f docker-compose.yml \
  -f docker-compose.security.yml \
  -f environments/production.yml \
  config --quiet

# Deploy with security overrides
docker stack deploy \
  --compose-file docker-compose.yml \
  --compose-file docker-compose.security.yml \
  --compose-file environments/production.yml \
  --with-registry-auth \
  vpn-stack
```

## Compliance Considerations

### GDPR Compliance

- [ ] Data minimization implemented
- [ ] Right to erasure supported
- [ ] Data portability available
- [ ] Privacy by design
- [ ] Data protection impact assessment

### SOC 2 Requirements

- [ ] Access controls documented
- [ ] Change management process
- [ ] Incident response plan
- [ ] Business continuity plan
- [ ] Regular security training

## Incident Response

### Security Incident Checklist

1. **Detection**
   - [ ] Identify the incident
   - [ ] Assess severity
   - [ ] Activate response team

2. **Containment**
   - [ ] Isolate affected systems
   - [ ] Preserve evidence
   - [ ] Prevent spread

3. **Eradication**
   - [ ] Remove threat
   - [ ] Patch vulnerabilities
   - [ ] Update security controls

4. **Recovery**
   - [ ] Restore services
   - [ ] Verify integrity
   - [ ] Monitor for recurrence

5. **Lessons Learned**
   - [ ] Document incident
   - [ ] Update procedures
   - [ ] Implement improvements

## Security Resources

- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

## Regular Security Tasks

### Daily
- Review security alerts
- Check failed authentication logs
- Monitor resource usage

### Weekly
- Review access logs
- Update security patches
- Test backup recovery

### Monthly
- Security assessment
- Access review
- Update documentation

### Quarterly
- Penetration testing
- Security training
- Compliance audit