# Security Documentation

This document outlines the security architecture, best practices, threat models, and security procedures for the secure VPN service.

## Table of Contents

- [Security Architecture](#security-architecture)
  - [Network Segmentation](#network-segmentation)
  - [Encryption Protocols](#encryption-protocols)
  - [Authentication](#authentication)
  - [Traffic Obfuscation](#traffic-obfuscation)
  - [System Hardening](#system-hardening)
- [Security Best Practices](#security-best-practices)
  - [Server Configuration](#server-configuration)
  - [Key Management](#key-management)
  - [Access Control](#access-control)
  - [Update Management](#update-management)
  - [Monitoring and Logging](#monitoring-and-logging)
- [Threat Model](#threat-model)
  - [Potential Threats](#potential-threats)
  - [Attack Vectors](#attack-vectors)
  - [Risk Assessment](#risk-assessment)
  - [Mitigations](#mitigations)
- [Security Audit Procedures](#security-audit-procedures)
  - [Regular Audits](#regular-audits)
  - [Penetration Testing](#penetration-testing)
  - [Compliance Verification](#compliance-verification)
  - [Audit Logging](#audit-logging)
- [Key Rotation Procedures](#key-rotation-procedures)
  - [Certificate Rotation](#certificate-rotation)
  - [VPN Key Rotation](#vpn-key-rotation)
  - [Access Credential Rotation](#access-credential-rotation)
  - [Rotation Schedule](#rotation-schedule)

## Security Architecture

### Network Segmentation

The VPN system uses Docker networks to implement strict network segmentation:

1. **Frontend Network (`vpn_frontend`)**
   - Only network exposed to the internet
   - Contains Traefik (reverse proxy) and the cover website
   - Provides TLS termination and request routing

2. **VPN Services Network (`vpn_services`)**
   - Internal network, not directly accessible from the internet
   - Contains V2Ray and OutlineVPN services
   - Communicates only through the reverse proxy

3. **Management Network (`vpn_management`)**
   - Protected internal network for administrative interfaces
   - Contains management dashboard, Prometheus, Grafana, and Alertmanager
   - Restricted access with additional authentication

4. **Backup Network (`vpn_backup`)**
   - Isolated network for backup operations
   - Restricted access to sensitive data and configurations

This segmentation ensures that a compromise in one network doesn't automatically lead to full system compromise.

### Encryption Protocols

The VPN service employs multiple layers of encryption:

1. **Transport Layer Security (TLS)**
   - All external connections use TLS 1.3
   - Certificates automatically managed by Let's Encrypt
   - Modern cipher suites only (TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256)
   - Perfect Forward Secrecy (PFS) enforced
   - HSTS enabled with long max-age

2. **VPN Protocol Encryption**
   - V2Ray (VMess): AES-128-GCM or ChaCha20-Poly1305
   - OutlineVPN (Shadowsocks): ChaCha20-IETF-Poly1305 
   - Both protocols include perfect forward secrecy
   - Secure key exchange mechanisms

3. **Data at Rest**
   - Configuration files with sensitive data use restricted permissions
   - Backup files encrypted with AES-256-GCM
   - Docker volumes with proper permission settings

### Authentication

The VPN system implements multiple authentication mechanisms:

1. **VPN Client Authentication**
   - V2Ray: UUID-based authentication
   - OutlineVPN: Password authentication with strong encryption
   - Optional OTP (One-Time Password) integration

2. **Administrative Interface Authentication**
   - HTTP Basic Authentication with bcrypt-hashed passwords
   - Rate limiting to prevent brute force attacks
   - IP-based access restrictions (optional)
   - Audit logging of all authentication attempts

3. **System Authentication**
   - SSH access protected by port knocking
   - Key-based authentication recommended, passwords disabled
   - Fail2ban to prevent brute force attacks
   - Restricted sudo access for administrative tasks

### Traffic Obfuscation

To evade deep packet inspection (DPI) and censorship systems, the VPN implements:

1. **Protocol Obfuscation**
   - V2Ray WebSocket traffic masquerading as HTTPS
   - TLS fingerprint randomization
   - HTTP header normalization
   - Timing obfuscation for packet delivery

2. **Traffic Camouflage**
   - Legitimate-looking HTTP headers
   - Random padding of packets
   - Variable packet sizes
   - Traffic pattern normalization

3. **Cover Traffic**
   - Public-facing legitimate website
   - VPN traffic hidden within normal HTTPS requests
   - Proper SNI routing through Traefik

### System Hardening

The system includes multiple hardening measures:

1. **Host System Hardening**
   - Minimal package installation
   - Regular security updates
   - AppArmor profiles
   - Restrictive firewall rules
   - Kernel hardening parameters

2. **Container Security**
   - Read-only containers where possible
   - Non-root container execution
   - Docker user namespace remapping
   - Resource limits to prevent DoS
   - No privileged containers

3. **Firewall Configuration**
   - Default deny policy
   - Only necessary ports exposed (80, 443)
   - SSH protected via port knocking
   - Rate limiting on exposed ports
   - Invalid packet filtering
   - Anti-spoofing measures

## Security Best Practices

### Server Configuration

1. **Physical Security**
   - Choose reputable hosting providers with good physical security
   - Prefer providers with SOC 2 compliance
   - Consider geographic location for legal protection
   - Implement full disk encryption where supported

2. **Operating System**
   - Use a minimal server installation
   - Remove unnecessary services and packages
   - Enable automatic security updates
   - Configure proper log rotation
   - Install and configure rkhunter and other intrusion detection tools

3. **SSH Configuration**
   - Disable password authentication
   - Use ED25519 keys only
   - Configure AllowUsers and DenyUsers
   - Change default port (optional, in addition to port knocking)
   - Enable strict mode and disable root login

4. **Kernel Hardening**
   - Enable and configure sysctl security parameters
   - Use the included security-hardened kernel settings
   - Enable necessary modules only
   - Regular kernel updates

### Key Management

1. **Private Key Storage**
   - Store private keys with restricted permissions (0600)
   - Use separate keys for different services
   - Consider hardware security modules for critical keys
   - Never store unencrypted private keys in repositories

2. **Certificate Management**
   - Automatic certificate renewal via Let's Encrypt
   - Monitor certificate expiration
   - Use appropriate key sizes (RSA 4096 or ECC P-256)
   - Implement OCSP stapling

3. **VPN Key Security**
   - Generate strong random UUIDs for V2Ray
   - Use high-entropy passwords for Shadowsocks
   - Rotate keys regularly (see [Key Rotation Procedures](#key-rotation-procedures))
   - Separate user credentials from service credentials

4. **Password Policies**
   - Minimum 16 characters for all administrative passwords
   - Use password manager to generate and store passwords
   - Implement password-less authentication where possible
   - Regular password rotation

### Access Control

1. **Principle of Least Privilege**
   - Grant minimum necessary access to users
   - Use separate accounts for different functions
   - Implement role-based access control (RBAC)
   - Regularly audit access rights

2. **Administrative Access**
   - Limit admin access to trusted IPs where possible
   - Use separate accounts for daily operations vs. administration
   - Implement multi-factor authentication for admin interfaces
   - Log all administrative actions

3. **VPN User Management**
   - Document user onboarding and offboarding procedures
   - Implement time-limited access where appropriate
   - Regular access review and cleanup of unused accounts
   - Enforce traffic limits and monitoring

4. **Docker Security**
   - Use Docker content trust for image verification
   - Scan container images for vulnerabilities
   - Use fixed versions rather than "latest" tags
   - Implement proper resource constraints

### Update Management

1. **System Updates**
   - Configure unattended-upgrades for security patches
   - Weekly review of available updates
   - Maintain change log of all updates
   - Test updates in staging when possible

2. **Application Updates**
   - Regular updates of VPN software components
   - Check for security advisories for all components
   - Subscribe to security mailing lists
   - Document update procedures

3. **Dependency Management**
   - Regular audit of dependencies
   - Check for known vulnerabilities
   - Update dependencies promptly when security issues arise
   - Pin dependency versions

4. **Update Testing**
   - Test major updates in a staging environment
   - Create backup before significant updates
   - Document rollback procedures
   - Maintain previous working configuration

### Monitoring and Logging

1. **Security Monitoring**
   - Set up alerts for suspicious activity
   - Monitor authentication failures
   - Track unusual traffic patterns
   - Log and alert on configuration changes

2. **Log Management**
   - Centralized logging with Prometheus and Grafana
   - Secure log storage with proper retention
   - Log rotation to prevent disk filling
   - Monitoring of log integrity

3. **Alerting Configuration**
   - Set up immediate alerts for critical security events
   - Configure gradual alerting for threshold breaches
   - Document alert response procedures
   - Regular review of alert configurations

4. **Metrics Collection**
   - Monitor system health and performance
   - Track resource utilization
   - Monitor network traffic patterns
   - Set up anomaly detection

## Threat Model

### Potential Threats

1. **State-Level Adversaries**
   - National security agencies with advanced capabilities
   - Deep packet inspection (DPI) at network boundaries
   - Legal demands for user information
   - Traffic correlation attacks

2. **Network Eavesdroppers**
   - ISP-level traffic monitoring
   - Man-in-the-middle attacks
   - Traffic analysis and metadata collection
   - DNS poisoning and hijacking

3. **Malicious Actors**
   - Targeted attacks against VPN infrastructure
   - Credential theft attempts
   - Denial-of-service attacks
   - Exploitation of software vulnerabilities

4. **Insider Threats**
   - Administrators with elevated privileges
   - Users attempting to abuse service
   - Data exfiltration attempts
   - Configuration sabotage

### Attack Vectors

1. **Infrastructure Attacks**
   - Exploitation of unpatched vulnerabilities
   - Docker escape vulnerabilities
   - Misconfigured permissions or network rules
   - Supply chain compromises

2. **Authentication Attacks**
   - Brute force attacks on passwords
   - Social engineering of credentials
   - Session hijacking
   - Cookie theft or fixation

3. **Traffic Analysis**
   - Timing correlation attacks
   - Volume analysis
   - Protocol fingerprinting
   - Statistical pattern recognition

4. **Legal and Coercion Attacks**
   - Warrant canaries
   - Legal demands for user data
   - Equipment seizure
   - Gag orders preventing disclosure

### Risk Assessment

| Threat | Likelihood | Impact | Risk Level | Mitigations |
|--------|------------|--------|------------|-------------|
| State surveillance | High | High | Critical | Traffic obfuscation, no-logging policy, jurisdictional consideration |
| Credential theft | Medium | High | High | Strong authentication, rate limiting, 2FA where possible |
| DoS attacks | Medium | Medium | Medium | Rate limiting, firewall rules, CDN protection |
| Vulnerability exploitation | Medium | High | High | Regular updates, security audits, restricted access |
| Traffic analysis | High | Medium | High | Traffic padding, timing obfuscation, cover traffic |
| Legal coercion | Medium | High | High | Minimal data retention, transparency reporting |

### Mitigations

1. **Against State Surveillance**
   - Traffic obfuscation to evade DPI
   - Multi-hop routing options
   - No-logging policy to minimize data retention
   - Jurisdictional diversity where possible

2. **Against Network Attacks**
   - TLS for all communications
   - Perfect forward secrecy for key exchange
   - DNS over HTTPS/TLS
   - Connection security indicators

3. **Against Infrastructure Attacks**
   - Regular security patching
   - Minimal attack surface
   - Network segmentation
   - Host-based intrusion detection

4. **Against Authentication Attacks**
   - Strong password policies
   - Rate limiting on authentication attempts
   - IP-based restrictions where appropriate
   - Regular credential rotation

## Security Audit Procedures

### Regular Audits

Perform these security audits at regular intervals:

1. **Weekly Automated Checks**
   - Run the security-checks.sh script
   - Review and address findings
   - Document all issues and resolutions
   - Command: `sudo ./security-checks.sh`

2. **Monthly Manual Audit**
   - Review all user accounts and access
   - Check for unauthorized changes
   - Verify backup integrity
   - Update security patches

3. **Quarterly Full Audit**
   - Complete system review
   - Update threat model if needed
   - Test intrusion detection capabilities
   - Review and update security documentation

4. **Annual External Audit** (recommended)
   - Consider engaging external security professionals
   - Conduct penetration testing
   - Review architecture for vulnerabilities
   - Address all findings

### Penetration Testing

Guidelines for penetration testing:

1. **Scope Definition**
   - Clearly define testing boundaries
   - Document authorized test methods
   - Establish communication channels during testing
   - Define success criteria

2. **Testing Areas**
   - Network infrastructure security
   - VPN service security
   - Authentication mechanisms
   - Encryption implementation
   - Traffic obfuscation effectiveness

3. **Testing Process**
   - Create testing schedule during low-usage periods
   - Notify stakeholders before testing
   - Document all findings with evidence
   - Create remediation plan for issues

4. **Post-Testing**
   - Address all critical findings immediately
   - Schedule fixes for other vulnerabilities
   - Verify fixes with follow-up testing
   - Update documentation with lessons learned

### Compliance Verification

Ensure compliance with relevant standards:

1. **Data Protection**
   - Review GDPR compliance (if applicable)
   - Verify privacy policy accuracy
   - Check data minimization practices
   - Confirm appropriate consent mechanisms

2. **Industry Standards**
   - Review against OpenVPN security best practices
   - Check compliance with IETFs security standards
   - Verify implementation of Perfect Forward Secrecy
   - Confirm appropriate cipher selections

3. **Documentation Verification**
   - Update security documentation
   - Review and update incident response procedures
   - Verify that practices match documentation
   - Train administrators on security procedures

4. **Operational Security**
   - Verify backup procedures and test restores
   - Check certificate validity and renewal processes
   - Review access control mechanisms
   - Test monitoring and alerting systems

### Audit Logging

Configure comprehensive audit logging:

1. **Log Sources**
   - Authentication attempts (successful and failed)
   - Administrative actions
   - Configuration changes
   - Service starts/stops
   - Unusual traffic patterns

2. **Log Protection**
   - Ensure logs are write-only for normal users
   - Implement log rotation with compression
   - Consider forwarding logs to secure storage
   - Protect logs from unauthorized access

3. **Log Analysis**
   - Regular review of security logs
   - Look for patterns of suspicious activity
   - Correlate events across different services
   - Document findings and actions taken

4. **Log Retention**
   - Determine appropriate retention periods
   - Balance security needs with privacy concerns
   - Implement secure deletion after retention period
   - Document retention policy

## Key Rotation Procedures

### Certificate Rotation

1. **Let's Encrypt Certificates**
   - Automatically renewed by Traefik
   - Monitor for renewal failures
   - Manual renewal if necessary:
     ```bash
     docker-compose exec traefik rm /acme/acme.json
     docker-compose restart traefik
     ```

2. **Internal Certificates**
   - Rotate internal certificates annually
   - Generate new certificates:
     ```bash
     openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
       -keyout internal-key.pem -out internal-cert.pem
     ```
   - Update services with new certificates

3. **Certificate Verification**
   - Verify certificate validity:
     ```bash
     openssl x509 -in certificate.pem -text -noout
     ```
   - Check certificate expiration:
     ```bash
     openssl x509 -in certificate.pem -noout -enddate
     ```

4. **Certificate Revocation**
   - Document procedures for emergency revocation
   - Test revocation process annually
   - Maintain backup access methods

### VPN Key Rotation

1. **V2Ray Keys**
   - Rotate user UUIDs quarterly
   - Generate new UUIDs:
     ```bash
     cat /proc/sys/kernel/random/uuid
     ```
   - Update V2Ray configuration with new UUIDs
   - Distribute new configuration to users

2. **OutlineVPN Keys**
   - Rotate user passwords quarterly
   - Generate secure passwords:
     ```bash
     openssl rand -base64 24
     ```
   - Update OutlineVPN user configuration
   - Distribute new credentials securely

3. **Pre-Shared Keys**
   - Rotate any pre-shared keys quarterly
   - Document distribution procedures
   - Verify key updates with monitoring

4. **Emergency Key Rotation**
   - Procedures for immediate key rotation if compromise suspected
   - Backup authentication methods
   - Communication plans for users

### Access Credential Rotation

1. **Admin Passwords**
   - Rotate administrative passwords quarterly
   - Generate strong passwords:
     ```bash
     openssl rand -base64 24
     ```
   - Update .env file with new credentials
   - Restart affected services:
     ```bash
     docker-compose up -d
     ```

2. **API Keys and Tokens**
   - Rotate monitoring tokens quarterly
   - Update Telegram bot tokens and chat IDs
   - Verify continued operation after rotation

3. **SSH Keys**
   - Rotate SSH keys annually
   - Generate new ED25519 keys:
     ```bash
     ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519
     ```
   - Update authorized_keys with new public key
   - Remove old keys after transition period

4. **Secure Distribution**
   - Use encrypted channels for credential distribution
   - Verify receipt and activation
   - Document all credential changes

### Rotation Schedule

| Item | Rotation Frequency | Procedure Document | Responsible Role |
|------|---------------------|---------------------|-----------------|
| TLS Certificates | Automatic (90 days) | [Certificate Rotation](#certificate-rotation) | System (Automated) |
| V2Ray UUIDs | Quarterly | [VPN Key Rotation](#vpn-key-rotation) | Administrator |
| Shadowsocks Passwords | Quarterly | [VPN Key Rotation](#vpn-key-rotation) | Administrator |
| Admin Credentials | Quarterly | [Access Credential Rotation](#access-credential-rotation) | Security Officer |
| SSH Keys | Annually | [Access Credential Rotation](#access-credential-rotation) | Administrator |
| API Tokens | Quarterly | [Access Credential Rotation](#access-credential-rotation) | Administrator |
| Emergency Rotation | As needed | All procedures | Security Officer |

Key rotation should be executed according to this schedule. Document each rotation event, including:
- Date and time of rotation
- Items rotated
- Verification of successful implementation
- Any issues encountered and their resolution