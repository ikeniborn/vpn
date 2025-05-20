# Decision Log

This file records architectural and implementation decisions using a list format.
2025-05-19 11:04:58 - Initial Memory Bank creation.
2025-05-20 10:08:39 - Updated to reflect architecture decisions for the integrated VPN solution.

## Decision

* Use integrated Shadowsocks/Outline Server + VLESS+Reality approach rather than VLESS+Reality only
* Create a comprehensive architecture plan for all required deployment scripts
* Implement a modular script design with clear separation of responsibilities
* Use Docker containers for both Shadowsocks/Outline Server and VLESS+Reality components

## Rationale 

* The integrated approach offers enhanced security through dual-layer encryption
* Modular script design improves maintainability and allows for future enhancements
* Docker containers provide isolation, portability and simplified deployment
* Multi-architecture support enables deployment across various hardware platforms
* Content-based routing optimizes performance for different types of traffic

## Implementation Details

* Docker-based deployment for simplified installation and management
* Comprehensive script structure:
  * Main setup script (setup.sh) for orchestration
  * User management script (manage-users.sh) for unified user administration
  * Monitoring script (monitoring.sh) for health checks
  * Backup and maintenance scripts for system upkeep
* Configuration stored in dedicated directories (/opt/vpn/*)
* User database maintained for managing credentials across both systems
* Docker Compose for container orchestration and network configuration
* Isolated Docker network (172.16.238.0/24) for container communication
* Implementation plan with estimated 16-day development timeline
* Support for multiple architectures (x86_64, ARM64, ARMv7)

2025-05-20 10:08:39 - Made architectural decisions for the integrated Shadowsocks/Outline Server + VLESS+Reality VPN solution deployment scripts.
2025-05-20 14:32:13 - Added explicit platform specification to Docker Compose configuration to resolve platform mismatch between host (linux/arm64/v8) and container images (linux/amd64).
2025-05-20 14:36:45 - Added creation of shadowbox_server_config.json to the setup.sh script to fix critical Outline Server configuration issue. Created additional troubleshooting script and documentation.
2025-05-20 17:42:00 - Enhanced container management in setup.sh to prevent "address already in use" errors by implementing robust container cleanup, port release, and network resource cleanup functions. This prevents Docker networking conflicts when restarting services.