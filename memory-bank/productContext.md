# Product Context

This file provides a high-level overview of the project and the expected product that will be created. Initially it is based upon projectBrief.md (if provided) and all other available project-related information in the working directory. This file is intended to be updated as the project evolves, and should be used to inform all other modes of the project's goals and context.
2025-05-18 18:14:05 - Initial creation based on project repository information.

## Project Goal

* Create a comprehensive, secure, and resilient VPN solution with enhanced privacy features, traffic obfuscation, and robust monitoring.
* Provide secure, private access to the internet through multiple tunneling protocols
* Evade detection and censorship through traffic obfuscation techniques
* Implement multiple VPN protocols (V2Ray and OutlineVPN/Shadowsocks) for versatility

## Key Features

* **Multiple VPN Protocols**: V2Ray (VMess) and OutlineVPN (Shadowsocks) for versatile connectivity options
* **Traffic Obfuscation**: Advanced traffic masking to evade deep packet inspection (DPI) and censorship
* **Security Hardening**: Comprehensive system hardening, including firewall rules, fail2ban, and AppArmor
* **Network Isolation**: Docker networks for security separation between components
* **Automated Monitoring**: Prometheus, Alertmanager, and Grafana for real-time monitoring and alerts
* **Management Interface**: Web-based admin dashboard for user management and system monitoring
* **Automated Backup**: Scheduled encrypted backups of configuration and data
* **TLS Encryption**: Automatic TLS certificate management via Let's Encrypt
* **Legitimate-Looking Frontend**: Cover website to make the VPN service less conspicuous

## Overall Architecture

* **Docker-based Containerization**: All services run in isolated Docker containers
* **Network Segmentation**: Multiple isolated Docker networks (frontend, vpn_services, management, backup)
* **Reverse Proxy**: Traefik for secure traffic routing and TLS termination
* **Monitoring Stack**: Prometheus, Alertmanager, and Grafana for system monitoring
* **Backup System**: Automated encrypted backups of configuration and data
* **Security**: Multiple security layers including firewall rules, network isolation, and regular security checks