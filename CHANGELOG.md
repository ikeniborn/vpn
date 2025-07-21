# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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