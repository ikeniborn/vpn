# Decision Log

This file records architectural and implementation decisions using a list format.
2025-05-18 18:14:47 - Memory Bank initialization.

## Decision

* Use Docker containerization for service isolation and deployment
* Implement multiple VPN protocols (V2Ray and OutlineVPN/Shadowsocks) for versatility
* Use Traefik as reverse proxy for routing and TLS termination
* Implement network segmentation with isolated Docker networks
* Add a cover website to make the VPN service less conspicuous
* Implement a comprehensive monitoring solution with Prometheus, Alertmanager, and Grafana
* Set up automated encrypted backups for disaster recovery

## Rationale 

* Docker provides isolation, portability, and simplified deployment
* Multiple VPN protocols offer redundancy and options to bypass network restrictions
* Traefik provides modern, container-aware reverse proxy capabilities with automatic TLS
* Network segmentation enhances security by limiting attack surface
* A cover website helps avoid detection by censors
* Monitoring ensures system health and performance visibility
* Automated backups protect against data loss and facilitate disaster recovery

## Implementation Details

* Docker Compose for orchestration with defined networks and volumes
* V2Ray with WebSocket transport for better censorship evasion
* OutlineVPN/Shadowsocks for simpler client setup
* Traefik with Let's Encrypt for automatic certificate management
* Four isolated Docker networks (frontend, vpn_services, management, backup)
* Prometheus, Alertmanager with Telegram notifications, and Grafana dashboards
* Encrypted backups with retention policy and failure notifications

## Script Resilience Enhancement - 2025-05-18 21:46:42

**Decision**: Added automatic installation checks for required packages (UFW, knockd, iptables) in the firewall.sh script.

**Rationale**: The script was failing with "ufw: command not found" error when run without first executing setup.sh. By adding dependency checks, the script now verifies if required tools are installed and installs them if missing, making the script more self-contained and resilient.

**Implementation Details**:
* Added check for UFW installation before attempting to use it
* Added check for knockd installation before configuration
* Added check for iptables installation before Docker compatibility setup
* Used apt-get with DEBIAN_FRONTEND=noninteractive to prevent prompts