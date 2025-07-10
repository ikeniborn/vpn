# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Python-based VPN management system providing comprehensive tools for managing VLESS+Reality, Shadowsocks, WireGuard VPN servers, and HTTP/SOCKS5 proxy servers. Features a rich Terminal User Interface (TUI) built with Textual and CLI tools using Typer.

## Development Commands

### Essential Development Workflow

```bash
# Initial setup
pip install -e ".[dev,test,docs]"
pre-commit install

# Run single test
pytest tests/test_user_manager.py::TestUserManager::test_create_user -v

# Run tests matching pattern  
pytest -k "test_create" -v

# Quick checks before commit
make check  # Runs lint + type-check + test

# Auto-fix code issues
make fix    # Runs black + ruff --fix
```

### Build and Quality Commands

```bash
# Testing
make test          # Run all tests
make test-cov      # Generate coverage report

# Code quality
make format        # Format with black
make lint          # Check with ruff
make type-check    # Type check with mypy

# Clean build artifacts
make clean

# Documentation
make docs          # Build docs
make docs-serve    # Serve docs locally
```

### Running the Application

```bash
# CLI mode
python -m vpn --help
python -m vpn users list
python -m vpn server install --protocol vless --port 8443

# TUI mode
python -m vpn tui

# Development/debug mode
python -m vpn --debug users create test-user --protocol vless
```

## High-Level Architecture

### Core Architecture Principles

The codebase follows a **layered architecture** with clear separation of concerns:

```
User Input → CLI/TUI Layer → Service Layer → Core Layer → External Systems
```

### Critical Architectural Components

#### 1. **Async Service Layer Pattern**
All services inherit from `BaseService` and use async/await throughout:

```python
# vpn/services/base.py defines the pattern
# All services (UserManager, ServerManager, etc.) follow this async pattern
# Services are stateless and can be instantiated per-request
```

#### 2. **Protocol Factory System**
VPN protocols are implemented via factory pattern:

```python
# vpn/protocols/base.py - Abstract protocol interface
# Each protocol (VLESS, Shadowsocks, WireGuard) implements this interface
# Protocol selection happens at runtime based on user input
```

#### 3. **Configuration Hierarchy**
Configuration follows a clear precedence order:

```
1. Environment variables (VPN_*)
2. User config file (~/.config/vpn-manager/config.toml)  
3. System config (/etc/vpn-manager/config.toml)
4. Default values (vpn/core/config.py)
```

#### 4. **Docker Integration Architecture**
Docker operations are abstracted through DockerManager:

- All VPN servers run as Docker containers
- Container lifecycle is managed asynchronously
- Health checks run in background tasks
- Resource limits enforced via Docker API

#### 5. **TUI Component Architecture**
The TUI uses Textual's reactive programming model:

```python
# Screens (vpn/tui/screens/) - Full page views
# Widgets (vpn/tui/widgets/) - Reusable components  
# Dialogs (vpn/tui/dialogs/) - Modal interactions
# Context menus implemented via ContextMenuMixin
```

### Key Design Decisions

1. **SQLite for Local State**: User data and server configs stored locally in SQLite
2. **Template-Based Configs**: Jinja2 templates generate VPN server configurations
3. **Type Safety First**: Pydantic models validate all data at boundaries
4. **Factory Pattern for Extensibility**: New protocols can be added without changing core code
5. **Async Throughout**: Even synchronous operations wrapped in async for consistency

### Critical File Relationships

#### User Creation Flow
1. `vpn/cli/commands/users.py` → CLI entry point
2. `vpn/services/user_manager.py` → Business logic
3. `vpn/protocols/{protocol}.py` → Protocol-specific config generation
4. `vpn/services/docker_manager.py` → Container deployment
5. `vpn/templates/{protocol}/` → Configuration templates

#### TUI Navigation Flow
1. `vpn/tui/app.py` → Main app and screen routing
2. `vpn/tui/screens/dashboard.py` → Default landing screen
3. `vpn/tui/widgets/navigation.py` → Menu system
4. Context menus triggered by right-click or F10 in any widget

### Performance Considerations

- **Connection Pooling**: Docker client reused across operations
- **Lazy Loading**: TUI screens load data on-demand
- **Async I/O**: All file/network operations are async
- **Caching**: User/server lists cached with TTL

## Testing Strategy

### Test Organization

```
tests/
├── test_models.py          # Pydantic model validation
├── test_*_manager.py       # Service layer tests
├── test_protocols.py       # Protocol implementations
├── test_cli_*.py          # CLI command tests
├── test_tui_*.py          # TUI component tests
└── test_docker_*.py       # Docker integration tests
```

### Running Specific Test Categories

```bash
# Unit tests only
pytest -m "not integration and not tui"

# TUI tests (require special setup)
pytest tests/test_tui_*.py

# Integration tests (require Docker)
pytest -m integration --docker
```

## Common Development Patterns

### Adding New VPN Protocol

1. Create `vpn/protocols/new_protocol.py` implementing `BaseProtocol`
2. Add protocol to `ProtocolType` enum in `vpn/core/models.py`
3. Register in protocol factory (`vpn/protocols/__init__.py`)
4. Add templates in `vpn/templates/new_protocol/`
5. Add tests in `tests/test_protocols.py`

### Adding New CLI Command

1. Create command function in appropriate file under `vpn/cli/commands/`
2. Use Typer decorators for arguments and options
3. Call appropriate service layer methods
4. Format output using `vpn/cli/formatters/`
5. Add tests in `tests/test_cli_*.py`

### Extending TUI

1. New screens go in `vpn/tui/screens/`
2. Register screen in `VPNManagerApp.SCREENS` dict
3. Add navigation menu item in `Navigation` widget
4. For context menus, use `ContextMenuMixin`
5. Test with `AppTest` from Textual

## Environment Variables

Key environment variables that affect behavior:

- `VPN_DEBUG=1` - Enable debug logging
- `VPN_CONFIG_PATH` - Override config file location
- `VPN_INSTALL_PATH` - VPN installation directory
- `VPN_LOG_LEVEL` - Set logging level
- `VPN_NO_COLOR=1` - Disable colored output

## Dependencies and Tooling

The project uses Poetry for dependency management but provides pip-compatible installation. Key tool versions:

- Python 3.10+ (3.11 recommended)
- Docker 20.10+ (required for VPN servers)
- Make (optional, for convenience commands)

## Error Handling Philosophy

- User-facing errors provide actionable messages
- Internal errors logged with full context
- Async exceptions properly propagated
- Docker errors wrapped with helpful context
- Network errors include retry suggestions