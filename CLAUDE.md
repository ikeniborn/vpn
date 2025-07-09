# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Python-based VPN management system that provides comprehensive tools for managing Xray (VLESS+Reality), Shadowsocks, WireGuard servers, and HTTP/SOCKS5 proxy servers. It features a rich Terminal User Interface (TUI) built with Textual and comprehensive CLI tools using Typer. This is a complete rewrite of the original Rust implementation, focusing on usability, cross-platform support, and extensive protocol coverage.

### Key Infrastructure Components

- **VPN Protocols**: VLESS+Reality, Shadowsocks, WireGuard with native Python implementations
- **Proxy Server**: Python-based HTTP/HTTPS and SOCKS5 proxy with authentication
- **TUI Interface**: Rich terminal interface built with Textual framework
- **CLI Tools**: Comprehensive command-line interface using Typer
- **Docker Integration**: Full container lifecycle management with async operations
- **Database**: SQLAlchemy with async support for SQLite/PostgreSQL
- **Configuration**: TOML-based configuration with Pydantic validation
- **Security**: Secure key generation and certificate management

## Build and Development Commands

### Core Development Commands

```bash
# Install development dependencies
pip install -e ".[dev]"

# Setup pre-commit hooks
pre-commit install

# Run all tests
make test
pytest

# Run tests with coverage
make test-cov
pytest --cov=vpn --cov-report=html

# Run specific test file
pytest tests/test_user_manager.py

# Format code
make format
black .
isort .

# Type checking
make type-check
mypy vpn/

# Linting
make lint
ruff check vpn/

# Run all quality checks
make check

# Clean temporary files
make clean

# Build documentation
make docs
mkdocs serve
```

### CLI Usage Examples

```bash
# Check system status
python -m vpn doctor

# Version information
python -m vpn --version

# User management
python -m vpn users list
python -m vpn users create alice --protocol vless
python -m vpn users show alice --connection-info

# Server management
python -m vpn server list
python -m vpn server install --protocol vless --port 8443
python -m vpn server start main-server

# Configuration
python -m vpn config show
python -m vpn config set server.domain vpn.example.com

# TUI interface
python -m vpn tui

# Proxy services
python -m vpn proxy start --type http --port 8888
python -m vpn proxy test --url https://google.com

# Monitoring
python -m vpn monitor stats
python -m vpn monitor traffic --real-time
```

### Docker Commands

```bash
# Build Docker image
docker build -t vpn-manager .

# Run with Docker Compose
docker-compose up -d

# Development environment
docker-compose -f docker-compose.dev.yml up -d

# Check container logs
docker-compose logs -f vpn-manager
```

## Architecture and Code Structure

### Package Layout

The project uses a modular Python package structure:

```
Core Package (Foundation Layer):
├── vpn/core/          # Core models, config, database, exceptions
├── vpn/utils/         # Utility functions (logging, crypto, diagnostics)
└── vpn/protocols/     # Protocol implementations (VLESS, Shadowsocks, WireGuard)

Service Layer (Business Logic):
├── vpn/services/      # Business logic services
│   ├── user_manager.py     # User lifecycle and management
│   ├── server_manager.py   # Server installation and configuration
│   ├── proxy_server.py     # HTTP/SOCKS5 proxy implementation
│   ├── docker_manager.py   # Docker container operations
│   └── network_manager.py  # Network and firewall management

Application Layer:
├── vpn/cli/           # CLI interface and commands
│   ├── app.py         # Main CLI application
│   ├── commands/      # Command implementations
│   └── formatters/    # Output formatters (JSON, YAML, table)

User Interface Layer:
└── vpn/tui/           # Terminal User Interface
    ├── app.py         # Main TUI application
    ├── screens/       # TUI screens
    ├── widgets/       # Custom widgets
    └── dialogs/       # Dialog components

Supporting Components:
├── vpn/templates/     # Jinja2 configuration templates
├── tests/            # Comprehensive test suite
└── scripts/          # Installation and utility scripts
```

### Key Design Patterns

1. **Async/Await**: All I/O operations use asyncio for performance
2. **Pydantic Models**: Type-safe data validation and serialization
3. **Dependency Injection**: Service layer with clear dependencies
4. **Factory Pattern**: Protocol implementations use factory pattern
5. **Observer Pattern**: TUI widgets use reactive programming

### Error Handling

Each module defines specific exception types inheriting from base exceptions:

```python
# Core exceptions in vpn/core/exceptions.py
class VPNError(Exception): ...
class ConfigurationError(VPNError): ...
class NetworkError(VPNError): ...

# Service-specific exceptions
class UserManagerError(VPNError): ...
class ServerManagerError(VPNError): ...
```

### Configuration Management

- **TOML format**: Human-readable configuration files
- **Pydantic validation**: Type-safe configuration parsing
- **Environment variables**: Override configuration with env vars
- **Hierarchical config**: Default → system → user → environment

## Testing Strategy

### Test Structure
- **Unit Tests**: Testing individual components in isolation
- **Integration Tests**: Testing component interactions
- **TUI Tests**: Testing terminal interface with Textual testing framework
- **Performance Tests**: Benchmarking against requirements
- **Docker Tests**: Testing container operations

### Running Tests

```bash
# All tests
pytest

# Specific categories
pytest -m "unit"
pytest -m "integration"
pytest -m "tui"
pytest -m "performance"

# With coverage
pytest --cov=vpn --cov-report=html --cov-report=term

# Parallel execution
pytest -n auto

# Verbose output
pytest -v
```

### Test Configuration

Tests use:
- **pytest**: Test framework with fixtures
- **pytest-asyncio**: Async test support
- **pytest-mock**: Mocking framework
- **pytest-cov**: Coverage reporting
- **pytest-xdist**: Parallel test execution

## Performance Characteristics

Current performance benchmarks:
- **Startup time**: ~50ms for CLI, ~200ms for TUI
- **Memory usage**: ~25MB baseline, ~50MB with TUI
- **User operations**: ~30ms per user creation
- **Docker operations**: ~100ms average response time
- **Database operations**: ~5ms for typical queries

## Common Development Tasks

### Adding a New CLI Command
1. Create command in `vpn/cli/commands/`
2. Register in `vpn/cli/app.py`
3. Add tests in `tests/test_cli_*.py`
4. Update documentation

### Adding a New TUI Screen
1. Create screen in `vpn/tui/screens/`
2. Register in `vpn/tui/app.py`
3. Add navigation logic
4. Add TUI tests

### Adding a New Protocol
1. Implement in `vpn/protocols/`
2. Register in protocol factory
3. Add configuration templates
4. Add comprehensive tests

### Adding a New Service
1. Create service in `vpn/services/`
2. Define service interface
3. Add dependency injection
4. Add service tests

## Key Dependencies

### Core Dependencies
- **textual**: Terminal UI framework
- **typer**: CLI framework
- **pydantic**: Data validation
- **sqlalchemy**: Database ORM
- **asyncio**: Async operations
- **docker**: Container management

### Development Dependencies
- **pytest**: Testing framework
- **black**: Code formatting
- **isort**: Import sorting
- **mypy**: Type checking
- **ruff**: Fast linting
- **pre-commit**: Git hooks

## Documentation Structure

Comprehensive documentation is organized in the `docs/` directory:
- **docs/getting-started/**: Installation and quick start guides
- **docs/user-guide/**: End-user documentation
- **docs/admin-guide/**: System administration guides
- **docs/api/**: API reference documentation
- **docs/development/**: Developer guides
- **docs/migration/**: Migration guides from other versions

## Project Status

**Current Status**: Production Ready
- All core functionality implemented and tested
- Comprehensive TUI with context menus and real-time monitoring
- Complete CLI interface with multiple output formats
- Full Docker integration and orchestration
- Extensive test coverage and documentation
- Python 3.10+ support with async-first architecture