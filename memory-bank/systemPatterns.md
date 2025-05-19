# System Patterns

This file documents recurring patterns and standards used in the project.
2025-05-19 11:05:17 - Initial Memory Bank creation.

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

## Testing Patterns

* **Security Verification**:
  * Security checks script (security-checks-reality.sh) verifies proper configuration
  * Tests for common misconfigurations and vulnerabilities
  * User export functionality to verify client configurations