# Product Context

This file provides a high-level overview of the project and the expected product that will be created. Initially it is based upon projectBrief.md (if provided) and all other available project-related information in the working directory. This file is intended to be updated as the project evolves, and should be used to inform all other modes of the project's goals and context.
2025-05-19 11:04:14 - Initial Memory Bank creation.
2025-05-20 10:05:37 - Updated to reflect the integrated Shadowsocks/Outline Server + VLESS+Reality solution.

## Project Goal

* Provide a comprehensive deployment solution for an integrated VPN architecture combining Shadowsocks (via Outline Server) and VLESS protocol with Reality encryption
* Enable secure, undetectable VPN connectivity that can bypass deep packet inspection through multi-layer encryption and traffic obfuscation
* Simplify the deployment and management of complex VPN servers with easy-to-use scripts
* Support deployment on various hardware architectures including x86_64, ARM64, and ARMv7

## Key Features

* **Dual-Layer Architecture**:
  * First layer: Shadowsocks/Outline Server with ChaCha20-IETF-Poly1305 encryption
  * Second layer: VLESS protocol with Reality encryption
* **Traffic Obfuscation**: Multiple layers of obfuscation to evade detection
  * Shadowsocks with HTTP obfuscation plugin
  * Reality protocol mimicking legitimate TLS traffic to approved destinations
* **User Management**: Unified user management across both systems
* **Security Hardening**: Built-in firewall and security checks
* **Docker-based**: Containerized deployment with proper isolation
* **Multi-Architecture Support**: Deployable on x86_64, ARM64, and ARMv7 platforms
* **Advanced Routing**: Content-based traffic routing for optimization
* **Performance Optimizations**: Specialized settings for streaming, browsing, and other traffic types
* **Monitoring & Maintenance**: Automated health checks and maintenance procedures

## Overall Architecture

* **Core Components**:
  * Docker-orchestrated containers for Shadowsocks/Outline Server and VLESS+Reality
  * Isolated Docker network for inter-container communication
  * Configuration files stored in dedicated directories
  * User database for managing access credentials
  
* **Scripts**:
  * setup.sh: All-in-one setup script for the integrated solution
  * manage-users.sh: Unified user management across both systems
  * monitoring.sh: Health checks and performance monitoring
  * backup and maintenance scripts for system upkeep
  
* **Security Model**:
  * Multi-layer encryption (Shadowsocks + Reality)
  * Traffic obfuscation at multiple levels
  * Secure Docker networking isolation
  * Firewall configured with secure defaults

2025-05-20 10:05:37 - Updated to reflect the integrated Shadowsocks/Outline Server + VLESS+Reality solution instead of the VLESS+Reality only approach described initially.