# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- WireGuard connectivity check fix
  - Skip TCP connectivity verification for WireGuard protocol (UDP-only)
  - Prevents false installation failures for WireGuard VPN
- Multi-protocol user management fix
  - Fixed user creation to use protocol-specific directories
  - Users with same name can now exist across different protocols
  - Each protocol maintains its own user namespace
  - Fixed user list command to show users from all installed protocols
  - Resolves issue where WireGuard users were not displayed in list
  - Enhanced user selection in interactive menu to show protocol
  - Fixed user deletion to handle duplicate names across protocols
- Claude Code hooks system for enhanced automation
  - Prehook system for structured task analysis:
    - Task parser (task_parser.py) for analyzing user prompts
    - Unique UUID generation for each request
    - Individual JSON file logging in prompts/ directory
    - JSON schema for validating structured output with request_id
    - UserPromptSubmit hook for automatic task analysis
    - Task history tracking in JSONL format
    - Test suite for parser validation
  - Posthook system for git automation:
    - git_posthook.py for intelligent auto-commits
    - git_config.py for managing posthook settings
    - PostToolUse hooks for file modification tracking
    - Stop hook for end-of-session commits
    - Configurable commit thresholds and exclusion patterns
    - Smart commit message generation based on task context
    - Optional auto-push with branch whitelist support
  - PreToolUse and PostToolUse hooks for audit logging
- Password authentication support for proxy server users
- Secure password storage using Argon2 hashing algorithm
- PasswordHasher module in vpn-crypto crate
- Password prompt during proxy user creation in CLI menu
- Temporary password display after user creation
- Password confirmation flow during user creation
- Enhanced connection details display for proxy users
- Real-time progress feedback for proxy server installation
- Docker image pull progress reporting
- Container startup status updates with elapsed time
- Service-by-service health check reporting
- Enhanced logging configuration for installation visibility
- Local Docker image building instead of remote pulls

### Changed
- Connection link generation now uses password_hash field instead of private_key for proxy users
- Proxy authentication now supports both Argon2 hashed and plaintext passwords
- User details display now shows formatted connection URLs for proxy protocols
- Updated UserConfig structure to include password_hash field
- Improved docker-compose operations to show real-time progress
- Enhanced error messages with more helpful context
- Updated health check waiting to show container states
- All VPN protocols now use local Docker builds instead of pulling from registries
- Proxy server installation uses docker-compose build instead of pull

### Fixed
- WireGuard installation failing with "Cannot connect to VPN service" error
  - Modified installer to skip TCP connectivity check for UDP-based WireGuard
  - Installation now completes successfully for WireGuard protocol
- Proxy server not displaying in status menu after installation
- Squid container health check failing due to missing squidclient
- Container name mismatch preventing proxy status detection
- Installation appearing frozen during Docker image downloads
- Lack of feedback during container startup phase
- Removed dependency on external Docker registries for all protocols
- Squid Docker build hanging on cache initialization
- Added real-time build progress output for better visibility
- Simplified proxy auth Dockerfile to use pre-built binaries
- Fixed redundant directory nesting /opt/proxy/proxy/
- Fixed proxy status detection showing "not installed" when containers are running

## [0.2.0] - 2025-07-21

### Added
- Retry mechanism for VPN service connectivity verification during installation
- Enhanced menu status display showing all available protocols
- Clear screen and cursor positioning for better menu navigation

### Changed
- Moved reinstallation prompt to appear after protocol selection instead of before
- Updated Xray configuration to use null log paths to prevent permission errors
- Improved container name detection for accurate status reporting

### Fixed
- VLESS+Reality installation failing due to insufficient startup wait time
- Xray service failing to start due to log file permission errors
- Menu displaying at bottom of terminal instead of top
- Server status not showing running containers correctly
- Container names mismatch in lifecycle management (vless-xray vs xray)
- Incorrect reinstallation prompt for non-installed protocols
- Added protocol-specific installation check to avoid confusion

## [0.1.0] - 2025-07-13

### Added
- Initial Rust implementation of VPN management system
- Support for VLESS+Reality, Shadowsocks, WireGuard, and HTTP/SOCKS5 proxy protocols
- Comprehensive installation script with conflict detection
- Docker Compose orchestration for container management
- Interactive menu system for server and user management
- Automatic backup functionality during installation
- System requirements checking (Rust, Cargo, Git)
- Uninstall script generation

### Changed
- Migrated from Bash to Rust for improved type safety and performance
- Replaced containerd with Docker Compose for container orchestration

### Deprecated
- Containerd runtime support (use Docker Compose instead)

### Security
- Added privilege management with sudo requirement indicators
- Implemented secure key generation for VPN protocols