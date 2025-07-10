# VPN Manager - Python Implementation

[![Python Version](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Code Style](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black)
[![Type Checking](https://img.shields.io/badge/type%20checking-mypy-blue.svg)](https://mypy-lang.org/)
[![Tests](https://img.shields.io/badge/tests-pytest-orange.svg)](https://pytest.org/)

Modern VPN Management System with rich Terminal User Interface (TUI) and comprehensive CLI tools. This is a complete Python rewrite of the original Rust-based VPN Manager, offering enhanced usability, cross-platform support, and extensive protocol coverage.

## 🚀 Features

### VPN Protocols
- **VLESS+Reality**: State-of-the-art protocol with Reality obfuscation
- **Shadowsocks**: High-performance proxy with multiple cipher support
- **WireGuard**: Modern VPN protocol with native performance
- **HTTP/SOCKS5 Proxy**: Built-in proxy servers with authentication

### User Interface
- **🎨 Rich TUI**: Interactive terminal interface built with Textual
- **🔧 CLI Interface**: Comprehensive command-line tools with Click/Typer
- **📊 Real-time Monitoring**: Live traffic statistics and system metrics
- **🎯 Multi-format Output**: JSON, YAML, table, and plain text formats

### Infrastructure
- **🐳 Docker Integration**: Full container lifecycle management
- **🔐 Security First**: Secure key generation and certificate management
- **🌐 Multi-platform**: Linux, macOS, and Windows support
- **📈 Scalable**: Support for multiple servers and thousands of users

### Advanced Features
- **Batch Operations**: Mass user creation and management
- **Configuration Templates**: Jinja2-based templating system
- **Health Monitoring**: Automatic server health checks
- **Firewall Integration**: Automatic port and rule management
- **Database Support**: SQLite and PostgreSQL with async operations

## 📋 System Requirements

### Minimum Requirements
- **Python**: 3.10 or higher
- **Operating System**: Linux, macOS, or Windows
- **Memory**: 512MB RAM
- **Storage**: 100MB free disk space
- **Docker**: 20.10+ (for VPN server functionality)

### Recommended Requirements
- **Python**: 3.11 or higher
- **Memory**: 2GB RAM
- **Storage**: 1GB free disk space
- **Docker**: Latest stable version

## 🛠️ Installation

### Quick Installation

```bash
# Clone and install
git clone https://github.com/ikeniborn/vpn.git
cd vpn
bash scripts/install.sh
```

The script will:
- ✅ Install all system dependencies (Ubuntu/Debian)
- ✅ Create isolated Python environment
- ✅ Install VPN Manager
- ✅ Configure shell integration
- ✅ Prompt to reload your shell

### System Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+ (other Linux distributions may work)
- **Python**: 3.10 or higher
- **Memory**: 2GB RAM minimum
- **Docker**: Required for running VPN servers
- **Permissions**: sudo access for installing system packages

### After Installation

The installer will prompt you to reload your shell. After that:

```bash
vpn --version     # Check installation
vpn doctor        # Run diagnostics
vpn tui           # Launch terminal interface
```

## 🚀 Quick Start

### 1. Verify Installation

```bash
vpn --version
vpn --help
```

### 2. System Check

```bash
vpn doctor
```

### 3. Initialize Configuration

```bash
vpn config init
```

### 4. Create Your First User

```bash
vpn users create alice --protocol vless --email alice@example.com
```

### 5. Install VPN Server

```bash
vpn server install --protocol vless --port 8443 --name main-server
```

### 6. Start Server

```bash
vpn server start main-server
```

### 7. Get Connection Info

```bash
vpn users show alice --connection-info
```

### 8. Launch TUI

```bash
vpn tui
```

## 💻 Usage Examples

### CLI Commands

```bash
# User management
vpn users list
vpn users create bob --protocol shadowsocks
vpn users delete alice
vpn users stats

# Server management
vpn server list
vpn server status main-server --detailed
vpn server logs main-server --follow
vpn server restart main-server

# Proxy services
vpn proxy start --type http --port 8888 --auth
vpn proxy list
vpn proxy test --url https://google.com

# System monitoring
vpn monitor stats
vpn monitor traffic --real-time
vpn monitor users --active
```

### Terminal UI Features

Launch the interactive TUI with `vpn tui`:

- **Dashboard**: Real-time system overview
- **User Management**: Create, edit, and monitor users
- **Server Management**: Install, configure, and monitor servers
- **Traffic Monitoring**: Live traffic statistics and charts
- **System Settings**: Configuration management
- **Help System**: Built-in documentation and shortcuts

### Configuration Management

```bash
# View current configuration
vpn config show

# Set configuration values
vpn config set server.domain vpn.example.com
vpn config set server.port 8443
vpn config set logging.level debug

# Export/import configuration
vpn config export config-backup.toml
vpn config import config-backup.toml
```

## 🏗️ Architecture

### Project Structure

```
vpn/
├── vpn/                    # Main package
│   ├── cli/               # CLI commands and interface
│   │   ├── commands/      # Command implementations
│   │   └── formatters/    # Output formatters
│   ├── core/              # Core functionality
│   │   ├── config.py      # Configuration management
│   │   ├── database.py    # Database operations
│   │   ├── exceptions.py  # Custom exceptions
│   │   └── models.py      # Data models
│   ├── protocols/         # VPN protocol implementations
│   │   ├── vless.py       # VLESS+Reality protocol
│   │   ├── shadowsocks.py # Shadowsocks protocol
│   │   └── wireguard.py   # WireGuard protocol
│   ├── services/          # Business logic services
│   │   ├── user_manager.py    # User management
│   │   ├── server_manager.py  # Server management
│   │   ├── proxy_server.py    # Proxy services
│   │   └── docker_manager.py  # Docker operations
│   ├── tui/               # Terminal UI components
│   │   ├── screens/       # TUI screens
│   │   ├── widgets/       # Custom widgets
│   │   └── dialogs/       # Dialog boxes
│   ├── templates/         # Configuration templates
│   └── utils/             # Utility functions
├── tests/                 # Comprehensive test suite
├── docs/                  # Documentation and guides
├── scripts/               # Installation and utility scripts
├── pyproject.toml         # Project configuration
├── docker-compose.yml     # Container orchestration
└── Makefile              # Development commands
```

### Key Components

#### Protocol System
- **Base Protocol**: Abstract base class for all protocols
- **VLESS Implementation**: Complete VLESS+Reality support
- **Shadowsocks**: Multi-user Shadowsocks with Outline compatibility
- **WireGuard**: Native WireGuard with peer management

#### Service Layer
- **User Manager**: User lifecycle and authentication
- **Server Manager**: VPN server installation and management
- **Docker Manager**: Container operations and health monitoring
- **Network Manager**: Firewall and network configuration

#### Data Layer
- **SQLAlchemy ORM**: Async database operations
- **Pydantic Models**: Type-safe data validation
- **Configuration**: TOML-based configuration with validation

## 🔧 Development

### Setup Development Environment

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install development dependencies
pip install -e ".[dev]"

# Setup pre-commit hooks
pre-commit install
```

### Development Commands

```bash
# Run tests
make test

# Run tests with coverage
make test-cov

# Code formatting
make format

# Type checking
make type-check

# Linting
make lint

# Run all checks
make check

# Clean temporary files
make clean
```

### Running from Source

```bash
# Run CLI
python -m vpn --help

# Run TUI
python -m vpn tui

# Run with debugging
python -m vpn --debug users list
```

### Testing

```bash
# Run all tests
pytest

# Run specific test file
pytest tests/test_user_manager.py

# Run with coverage
pytest --cov=vpn --cov-report=html

# Run integration tests
pytest -m integration

# Run tests excluding slow tests
pytest -m "not slow"
```

## 📊 Performance

### Benchmarks

Compared to the original Rust implementation:

- **Startup Time**: ~50ms (Python) vs ~5ms (Rust)
- **Memory Usage**: ~25MB (Python) vs ~10MB (Rust)
- **User Creation**: ~30ms (Python) vs ~15ms (Rust)
- **Docker Operations**: ~100ms (Python) vs ~20ms (Rust)

### Optimizations

- **Async Operations**: All I/O operations are asynchronous
- **Connection Pooling**: Database and Docker connection reuse
- **Caching**: Redis-based caching for frequently accessed data
- **Lazy Loading**: On-demand loading of resources

## 🔒 Security

### Security Features

- **Key Generation**: Secure cryptographic key generation
- **Certificate Management**: Automatic TLS certificate handling
- **Authentication**: Multi-factor authentication support
- **Access Control**: Role-based access control (RBAC)
- **Audit Logging**: Comprehensive security event logging

### Security Best Practices

```bash
# Enable security features
vpn config set security.enable_2fa true
vpn config set security.require_strong_passwords true
vpn config set security.audit_logging true

# Generate secure keys
vpn crypto generate-keys --algorithm x25519
vpn crypto generate-cert --domain vpn.example.com

# Monitor security events
vpn monitor security --real-time
```

## 📖 Documentation

### Available Documentation

- **[Installation Guide](docs/getting-started/installation.md)** - Complete installation instructions
- **[Quick Start Guide](docs/getting-started/quickstart.md)** - Get up and running quickly
- **[CLI Commands](docs/user-guide/cli-commands.md)** - Complete CLI reference
- **[TUI Interface](docs/user-guide/tui-interface.md)** - Terminal UI guide
- **[Admin Guide](docs/admin-guide/)** - System administration
- **[API Reference](docs/api/)** - Complete API documentation
- **[Migration Guide](docs/migration/from-rust.md)** - Migrate from Rust version

### Building Documentation

```bash
# Build documentation
make docs

# Serve documentation locally
mkdocs serve
```

## 🔄 Migration from Rust Version

If you're migrating from the Rust version:

```bash
# Export data from Rust version
vpn-rust export --format json --output rust-data.json

# Import to Python version
vpn import --format json --input rust-data.json

# Verify migration
vpn users list
vpn server list
```

See the [Migration Guide](docs/migration/from-rust.md) for detailed instructions.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and checks: `make check`
5. Submit a pull request

### Code Style

- **Python**: Follow PEP 8 with Black formatting
- **Type Hints**: Use type hints throughout
- **Docstrings**: Google-style docstrings
- **Testing**: Comprehensive test coverage

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Textual](https://textual.textualize.io/) for the terminal UI
- Uses [Typer](https://typer.tiangolo.com/) for CLI interface
- Powered by [AsyncIO](https://docs.python.org/3/library/asyncio.html) for performance
- Inspired by the original Rust implementation

## 🐛 Support

### Getting Help

- **Documentation**: Check the [docs](docs/) directory
- **Issues**: [GitHub Issues](https://github.com/ikeniborn/vpn/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ikeniborn/vpn/discussions)
- **Discord**: Join our [Discord Community](https://discord.gg/vpn)

### Reporting Issues

When reporting issues, please include:

1. System information: `vpn doctor`
2. Debug logs: `vpn --debug <command>`
3. Configuration: `vpn config show`
4. Steps to reproduce the issue

### Feature Requests

We welcome feature requests! Please:

1. Check existing issues and discussions
2. Provide detailed use cases
3. Consider contributing the feature yourself

---

**Made with ❤️ by the VPN Manager Team**