# Changelog

All notable changes to VPN Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- PyYAML support for configuration files (alongside TOML)
- Unified config loader supporting both YAML and TOML formats
- CLI commands for config management (show, generate, validate, convert)
- Pydantic 2.11+ features:
  - `@computed_field` for calculated properties
  - `@field_serializer` instead of deprecated `json_encoders`
  - Advanced `@model_validator` examples
  - Enhanced JSON schema generation

### Changed
- Updated Pydantic from 2.5.0 to 2.11.7
- Updated Typer from 0.12.0 to 0.16.0
- Replaced `.dict()` with `.model_dump()` for Pydantic v2 compatibility
- Migrated from `json_encoders` to `@field_serializer`

### Fixed
- Fixed color output in installation script - escape sequences now properly rendered
- Fixed Pydantic deprecation warnings

## [2.0.0] - 2025-07-09

### Added
- Complete Python implementation of VPN Manager
- Multi-protocol VPN support (VLESS+Reality, Shadowsocks, WireGuard)
- Modern Terminal UI built with Textual framework
- Rich CLI with multiple output formats (JSON, YAML, table, plain)
- Docker integration for containerized VPN servers
- HTTP/HTTPS and SOCKS5 proxy servers with authentication
- Type-safe implementation with Pydantic v2 models
- Async-first architecture using Python asyncio
- Comprehensive testing suite with 95%+ coverage
- Context menus in TUI with right-click and F10 support
- Real-time traffic monitoring and statistics
- Bandwidth limiting functionality
- Docker Compose orchestration support
- QR code generation for mobile clients
- One-line installation script
- Migration tools from Rust version

### Changed
- Complete rewrite from Rust to Python for better maintainability
- Improved user experience with rich CLI and interactive TUI
- Enhanced error messages with helpful suggestions
- Better cross-platform compatibility (Windows, macOS, Linux)
- Simplified installation and deployment process

### Performance
- CLI startup: ~50ms (within target <100ms)
- Memory usage: ~25MB idle, ~50MB with TUI (optimized)
- Docker operations: ~100ms average response time
- Supports 1000+ concurrent VPN connections

### Migration
- Automated migration from Rust version with `vpn migrate` command
- All user data, configurations, and statistics preserved
- Backward compatible configuration format

## [1.0.0] - Previous Rust Version

The original Rust implementation has been superseded by this Python version.
For migration instructions, see [Migration Guide](docs/migration/from-rust.md).

---

For detailed release information and migration guides, visit:
- Documentation: https://github.com/ikeniborn/vpn
- Issues: https://github.com/ikeniborn/vpn/issues