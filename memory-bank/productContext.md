# Product Context

This file provides a high-level overview of the project and the expected product that will be created. Initially it is based upon projectBrief.md (if provided) and all other available project-related information in the working directory. This file is intended to be updated as the project evolves, and should be used to inform all other modes of the project's goals and context.
2025-05-19 11:04:14 - Initial Memory Bank creation.

## Project Goal

* Provide a comprehensive deployment solution for setting up a VPN server using the VLESS protocol with Reality encryption
* Enable secure, undetectable VPN connectivity that can bypass deep packet inspection
* Simplify the deployment and management of VPN servers with easy-to-use scripts

## Key Features

* **VLESS Protocol**: Lightweight and efficient VPN protocol
* **Reality Encryption**: Advanced security without certificates
* **Traffic Obfuscation**: Mimics legitimate TLS traffic to approved destinations
* **User Management**: Easy-to-use scripts for managing users (add, remove, list, export)
* **Security Hardening**: Built-in firewall and security checks
* **Docker-based**: Simple containerized deployment
* **No Certificates Required**: Unlike traditional TLS setups, Reality protocol doesn't need SSL certificates
* **Advanced Fingerprinting Evasion**: Mimics legitimate TLS traffic to common sites
* **Improved Performance**: Direct TCP connections with efficient flow control
* **Resistance to Active Probing**: Emulates real browser TLS fingerprints and behaviors

## Overall Architecture

* **Core Components**:
  * Docker container running v2fly/v2fly-core for VLESS+Reality protocol
  * Configuration files stored in /opt/v2ray directory
  * User database for managing access credentials
  
* **Scripts**:
  * setup-vless-reality-server.sh: All-in-one setup script for new servers
  * manage-vless-users.sh: Add, remove, list, and export users
  * firewall.sh: Configures firewall with secure defaults
  * security-checks-reality.sh: Perform security audits on the server
  
* **Security Model**:
  * Uses Reality protocol for advanced encryption without certificates
  * Mimics legitimate TLS traffic to approved destinations
  * Port knocking for SSH access (optional)
  * Firewall configured with secure defaults