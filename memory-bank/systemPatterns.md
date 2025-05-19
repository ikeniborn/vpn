# System Patterns

This file documents recurring patterns and standards used in the project.
2025-05-19 11:05:17 - Initial Memory Bank creation.
2025-05-19 11:22:16 - Added patterns for the two-server tunnel configuration.

## Coding Patterns

* **Bash Script Structure**: All scripts follow a consistent pattern:
  * Set strict error handling with `set -euo pipefail`
  * Define color variables for output formatting
  * Implement functions for error handling, logging, and parameter parsing
  * Parse command line arguments with proper validation
  * Define main function that coordinates the execution sequence
  * Use functions for specific tasks to maintain modularity

* **Configuration Management**:
  * Primary configuration stored in JSON format in /opt/v2ray/config.json
  * User database maintained in pipe-delimited format in /opt/v2ray/users.db
  * Scripts use `jq` for JSON manipulation
  * Backups created before modifying configuration files
  * Shared configurations in .conf files for cross-script consistency

* **Error Handling**:
  * All scripts use color-coded error output for visibility
  * Critical errors prompt immediate exit with descriptive messages
  * Input validation performed before operations

## Architectural Patterns

* **Containerized Services**:
  * Docker used for v2ray deployment
  * Container configured with appropriate network settings
  * Volume mounts for persistent configuration

* **Security Patterns**:
  * Defense in depth with multiple security layers
  * Port knocking for SSH access (optional)
  * Firewall rules to restrict access
  * Reality protocol for traffic obfuscation
  * Public/private key cryptography for secure communications

* **Script Interconnection**:
  * Main setup script orchestrates the deployment
  * Specialized scripts for specific functions (user management, security checks)
  * Scripts designed to be run individually or called by other scripts

* **Multi-Server Architecture**:
  * Two-server tunnel configuration with distinct roles
  * Server 1: Tunnel entry point with direct internet access
  * Server 2: Routes traffic through Server 1, hosts Outline VPN
  * Transparent forwarding of traffic between servers
  * IP forwarding and masquerading for proper routing

* **Tunnel Design Patterns**:
  * VLESS+Reality protocol for secure tunnel connection
  * Docker containers for v2ray components on both servers
  * Multiple proxy methods (SOCKS, HTTP, transparent) for flexibility
  * Systemd services for reliable operation and automatic startup
  * Specialized routing rules for traffic segregation

## Testing Patterns

* **Security Verification**:
  * Security checks script (security-checks-reality.sh) verifies proper configuration
  * Tests for common misconfigurations and vulnerabilities
  * User export functionality to verify client configurations

* **Connectivity Testing**:
  * Tunnel connectivity testing with end-to-end verification
  * IP address comparison to verify traffic routing
  * Docker container status monitoring
  * Firewall rule verification