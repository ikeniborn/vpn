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

## Nginx Container Permissions Fix - 2025-05-18 22:06:30

**Decision**: Modified tmpfs mounts in the management container to resolve permission issues.

**Rationale**: The nginx container was failing with "Permission denied" errors when trying to create cache directories and write PID file. These errors were preventing the management interface from starting properly.

**Implementation Details**:
* Added `exec,mode=1777` to `/var/cache/nginx` tmpfs mount to allow cache directory creation
* Added a new tmpfs mount for `/run` with `exec,mode=1777` to allow PID file writing
* Maintained the read-only filesystem for the rest of the container to preserve security

## V2Ray Service Command Fix - 2025-05-18 22:13:50

**Decision**: Added explicit command directive to the v2ray service in docker-compose.yml to properly run the service with its configuration file.

**Rationale**: The v2ray container was only showing its help menu instead of running the actual service. This indicated that no proper command was being passed to the container to tell it to run with the config file.

**Implementation Details**:
* Added command directive to docker-compose.yml for the v2ray service: `run -c /etc/v2ray/config.json`
* This explicitly tells v2ray to use the 'run' command with the correct configuration file path
* The v2ray container now properly initializes and runs the VPN service instead of just displaying help text

## V2Ray Configuration Update - 2025-05-18 22:16:11

**Decision**: Updated V2Ray configuration to fix deprecated "root fakedns settings" warning.

**Rationale**: V2Ray 5.30.0 was showing a warning about deprecated configuration format for the fakeDns settings. The warning message indicated that the root-level fakeDns settings are no longer the recommended approach in the latest V2Ray versions.

**Implementation Details**:
* Moved the fakeDns settings from the root level of the configuration into the dns section
* Changed the property name from "fakeDns" to "fakedns" (lowercase 'd') to match the new configuration format
* Updated the structure to use an array format for the fakedns configuration
* These changes align with V2Ray's latest configuration format while preserving the original functionality

## Docker Socket Permission Fix - 2025-05-18 22:31:10

**Decision**: Added Docker group management to setup.sh script and manually fixed current session permissions.

**Rationale**: Traefik and backup containers were failing with "permission denied while trying to connect to the Docker daemon socket" errors. These errors occurred because the user doesn't have permissions to access /var/run/docker.sock, which both containers need to mount.

**Implementation Details**:
* Added the current user to the Docker group with `sudo usermod -aG docker $USER`
* Activated the new group membership in the current session with `newgrp docker` without requiring logout
* Updated setup.sh to automatically add the user to the Docker group during installation
* Discovered additional fix was needed: explicitly setting the Docker group ID in volume mounts
* Modified docker-compose.yml to use `group:988` option in Docker socket mounts for Traefik and backup containers
* This approach provides a more reliable solution by ensuring the correct group permissions inside containers
* Restarted affected containers to apply the permission changes
* This change ensures that the containers can access the Docker socket while maintaining security