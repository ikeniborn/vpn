# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Real-time progress feedback for proxy server installation
- Docker image pull progress reporting
- Container startup status updates with elapsed time
- Service-by-service health check reporting
- Enhanced logging configuration for installation visibility
- Local Docker image building instead of remote pulls

### Changed
- Improved docker-compose operations to show real-time progress
- Enhanced error messages with more helpful context
- Updated health check waiting to show container states
- All VPN protocols now use local Docker builds instead of pulling from registries
- Proxy server installation uses docker-compose build instead of pull

### Fixed
- Installation appearing frozen during Docker image downloads
- Lack of feedback during container startup phase
- Removed dependency on external Docker registries for all protocols

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