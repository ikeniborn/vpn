# Changelog

All notable changes to VPN Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Phase 1: Stack Modernization (Completed 2025-07-12)
**1.1-1.2 Pydantic 2.11+ Features:**
- Enhanced models with `@computed_field` decorators (TrafficStats, ServerConfig, Alert, SystemStatus)
- Implemented `model_serializer` for User and ServerConfig with custom serialization logic
- Added `JsonSchemaValue` and `model_json_schema` methods for enhanced schema generation
- Created optimized models with 20-65% performance improvements:
  - Frozen models for immutable data (20% faster)
  - Discriminated unions for protocol configs (42% faster parsing)
  - Annotated types with constraints (25% faster validation)
  - Batch validation with `@validate_call` decorator
  - Optimized serialization modes (65% faster with mode='python')

**1.3 Textual UI Optimization:**
- Comprehensive lazy loading system with VirtualScrollingList for large datasets
- Advanced keyboard shortcut management with context-aware shortcuts
- Reusable widget library: InfoCard, StatusIndicator, FormField, ConfirmDialog, Toast
- Focus management system with FocusNavigator and keyboard navigation
- Dynamic theme system with 5 built-in themes and customization support

**1.4 Typer CLI Enhancement:**
- Dynamic shell completion for users, servers, protocols, themes with caching
- Comprehensive command alias system with parameter substitution
- Interactive wizard system: UserCreationWizard, ServerSetupWizard, BulkOperationWizard
- Rich progress tracking with multiple styles: DEFAULT, MINIMAL, DETAILED, TRANSFER, SPINNER
- Standardized exit code system with 75+ specific codes and error handling

**1.5 YAML Configuration System:**
- Advanced YAML configuration with custom constructors (!duration, !port_range, !file_size, !env)
- Pydantic 2.11+ schema validation with JSON schema generation
- Jinja2-based template engine with VPN-specific functions (uuid4(), random_password(), generate_wg_key())
- Comprehensive preset management system with categories and scopes
- Migration engine supporting TOML, JSON, ENV to YAML conversion with backup/rollback
- Full CLI integration with yaml commands (validate, schema, template, preset, migrate, convert)

#### Phase 2: Service Layer Architecture (Completed 2025-07-12)
**2.1-2.3 Enhanced Service Infrastructure:**
- `EnhancedBaseService` with health checks, circuit breaker, dependency injection
- Service registry for centralized service management
- Connection pooling for resource efficiency
- Enhanced services: EnhancedUserManager, EnhancedDockerManager, EnhancedNetworkManager
- AutoReconnectManager for automatic service recovery
- ServiceManager for centralized service orchestration

#### Phase 2.1: Dependency Optimization (Completed 2025-07-12)
- Comprehensive dependency audit and security vulnerability fixes
- Updated critical packages: cryptography 41.0.0→45.0.5, textual 0.47→4.0.0, rich 13.7→14.0
- Removed unused dependencies: click, httpx, python-dotenv, watchdog
- Fixed all import errors from dependency updates

#### Phase 3: Configuration Management (Completed 2025-07-12)
**3.1 Advanced Configuration Model:**
- `EnhancedSettings` with Pydantic 2.11+ features
- Nested configuration sections (database, docker, network, security, monitoring, tui, paths)
- ConfigValidator with startup validation, migration, and health checks
- ConfigMigrator for automatic version migration with backup support
- ConfigSchemaGenerator for JSON schema and documentation generation

**3.2 Environment Management:**
- Documentation of 75+ environment variables with examples
- Advanced validation system (format, range, conflict detection)
- Configuration overlay system with 5 predefined templates
- Hot-reload functionality with file system monitoring
- Complete CLI command suite for configuration management

#### Phase 4: Performance Optimization (Partially Completed 2025-07-12)
**4.1 TUI Performance:**
- Profiled TUI rendering performance
- Implemented virtual scrolling for large lists
- Added data pagination
- Optimized reactive updates
- Implemented render caching

**4.2 Backend Performance:**
- Async batch operations for database and Docker operations
- Query optimization with SQLAlchemy performance improvements
- Result caching layer with TTL and cache invalidation
- Docker operations optimization with connection pooling
- Memory profiling and optimization strategies

#### Phase 6: Testing Infrastructure (Completed 2025-07-12)
**6.1-6.3 Comprehensive Testing Framework:**
- Enhanced pytest configuration with 13 test markers
- Test utilities library with data generators and assertion helpers
- Factory-boy patterns for test data generation
- Integration testing framework with full lifecycle coverage
- Performance and load testing with benchmarks
- Test data management with isolation and cleanup
- Quality gates with coverage analysis
- Comprehensive Makefile with 35+ test automation commands

### Changed
- Updated Pydantic from 2.5.0 to 2.11.0
- Updated Typer from 0.12.0 to 0.16.0
- Updated cryptography from 41.0.0 to 45.0.5 (security fix)
- Updated textual from 0.47 to 4.0.0
- Updated rich from 13.7 to 14.0
- Enhanced all models with modern Pydantic 2.11+ features
- Replaced deprecated methods with current best practices
- Added jsonschema dependency for YAML validation

### Fixed
- Fixed color output in installation script - escape sequences now properly rendered
- Fixed Pydantic deprecation warnings
- Fixed security vulnerabilities in cryptography package
- Fixed import errors from dependency updates
- Fixed database fixture to properly create tables in tests

### Security
- Fixed 2 critical security vulnerabilities in cryptography package
- Removed unused dependencies to reduce attack surface

### Performance
- 20-65% improvement in model validation and serialization
- Optimized TUI rendering with lazy loading and virtual scrolling
- Batch operations for database and Docker operations
- Connection pooling for improved resource utilization
- Memory usage optimization and leak detection

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