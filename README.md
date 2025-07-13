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
- **🔧 CLI Interface**: Comprehensive command-line tools with Typer
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
- **Performance Optimization**: Caching, batch operations, and memory profiling
- **Comprehensive Testing**: 13 test markers, quality gates, and benchmarks

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
# Clone the repository
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# Run the installation script (either command works)
bash scripts/install.sh
# or
bash scripts/install/install.sh
```

The installation script will:
- ✅ Install system dependencies (Ubuntu/Debian/RHEL/macOS)
- ✅ Create isolated Python environment
- ✅ Install VPN Manager with all dependencies
- ✅ Configure shell integration
- ✅ Run initial system checks

### Manual Installation

```bash
# Install Python 3.10+ and pip
sudo apt update
sudo apt install python3.10 python3-pip python3-venv

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install VPN Manager
pip install -e ".[dev,test,docs]"

# Verify installation
vpn --version
vpn doctor
```

### Docker Installation

```bash
# Using Docker Compose
docker-compose -f docker/docker-compose.yml up -d

# Or build from Dockerfile
docker build -f docker/Dockerfile -t vpn-manager .
docker run -it vpn-manager vpn --help
```

## 🚀 Quick Start

### 1. Initialize Configuration

```bash
# Create default configuration
vpn config init

# Or use YAML configuration
vpn yaml init --template production
```

### 2. Create Your First User

```bash
# Interactive mode
vpn users create --interactive

# Direct creation
vpn users create alice --protocol vless --email alice@example.com
```

### 3. Install VPN Server

```bash
# Install VLESS server
vpn server install --protocol vless --port 8443 --name main-server

# Install with advanced options
vpn server install --protocol shadowsocks \
  --port 8388 \
  --name shadow-server \
  --cipher chacha20-ietf-poly1305
```

### 4. Launch Terminal UI

```bash
# Start the interactive TUI
vpn tui

# Or with specific theme
vpn tui --theme dark
```

## 🏗️ Project Structure

```
vpn/
├── config/                 # Configuration files
│   └── mkdocs.yml         # Documentation configuration
├── docker/                # Docker-related files
│   ├── Dockerfile         # Container image definition
│   ├── docker-compose.yml # Production compose file
│   └── docker-compose.dev.yml # Development compose file
├── docs/                  # Documentation
│   ├── api/              # API reference
│   ├── guides/           # User and admin guides
│   └── architecture/     # System design docs
├── scripts/              # Utility scripts
│   ├── install.sh        # Installation script
│   └── dev-setup.sh      # Development setup
├── tests/                # Test suite
│   ├── unit/            # Unit tests
│   ├── integration/     # Integration tests
│   └── performance/     # Performance benchmarks
├── vpn/                  # Main package
│   ├── cli/             # CLI implementation
│   ├── core/            # Core functionality
│   ├── protocols/       # VPN protocols
│   ├── services/        # Business logic
│   ├── tui/             # Terminal UI
│   └── utils/           # Utilities
├── .config/             # Project configuration
│   ├── git/            # Git configuration
│   └── qa/             # Quality assurance configs
├── .env.example        # Environment variables template
├── .pre-commit-config.yaml # Pre-commit hooks configuration
├── CHANGELOG.md         # Version history
├── CLAUDE.md           # AI assistant instructions
├── LICENSE             # MIT license
├── Makefile           # Development commands
├── pyproject.toml     # Project configuration
├── README.md          # This file
├── requirements.txt   # Python dependencies
└── TASK.md           # Development roadmap
```

## 💻 Usage Examples

### CLI Commands

```bash
# User management
vpn users list --format table
vpn users create bob --protocol shadowsocks --batch
vpn users delete alice --confirm
vpn users stats --real-time

# Server management
vpn server list --status active
vpn server logs main-server --follow --tail 100
vpn server health --all
vpn server update main-server --restart

# Configuration management
vpn config show --section server
vpn config set server.domain vpn.example.com
vpn config validate --env
vpn config overlay apply production

# YAML operations
vpn yaml validate config.yaml
vpn yaml template render server.j2
vpn yaml preset list --category server
vpn yaml migrate --from toml --to yaml

# Monitoring and performance
vpn monitor traffic --real-time
vpn monitor users --active --format json
vpn performance benchmark --duration 60
vpn performance profile memory
```

### Terminal UI Navigation

Launch with `vpn tui`:

- **F1**: Help / Keyboard shortcuts
- **F2**: Dashboard
- **F3**: Users management
- **F4**: Server management
- **F5**: Traffic monitoring
- **F10**: Context menu
- **Ctrl+Q**: Quit
- **Tab**: Navigate between panels
- **Enter**: Select/Edit
- **Space**: Toggle selection

### Advanced Configuration

```bash
# Environment management
export VPN_CONFIG_PATH=/etc/vpn-manager
export VPN_LOG_LEVEL=DEBUG
export VPN_THEME=cyberpunk

# Hot-reload configuration
vpn config hot-reload start
# Make changes to config files...
# Changes are automatically applied

# Configuration overlays
vpn config overlay create high-security
vpn config overlay edit high-security
vpn config overlay apply high-security
```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
make test

# Run specific test categories
make test-unit          # Unit tests only
make test-integration   # Integration tests
make test-performance   # Performance benchmarks
make test-quality       # Quality gates

# Run with coverage
make coverage
make coverage-html      # Generate HTML report

# Run tests in parallel
make test-parallel
```

### Test Infrastructure

- **13 Test Markers**: unit, integration, slow, performance, load, docker, network, tui, quality, e2e, memory, security
- **Factory Patterns**: Comprehensive test data generation
- **Quality Gates**: Automated coverage and quality checks
- **Performance Benchmarks**: Database, Docker, and caching performance tests
- **Test Isolation**: Complete test environment management

## 🔧 Development

### Setup Development Environment

```bash
# Clone and setup
git clone https://github.com/ikeniborn/vpn.git
cd vpn
make dev-install

# Install pre-commit hooks
pre-commit install

# Verify setup
make check
```

### Development Commands

```bash
# Code quality
make format         # Auto-format code
make lint          # Run linters
make type-check    # Type checking
make check         # All checks

# Testing
make test-fast     # Quick tests
make test-watch    # Watch mode
make benchmark     # Performance tests

# Documentation
make docs          # Build docs
make docs-serve    # Live preview

# Cleanup
make clean         # Remove artifacts
```

### Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and test: `make test`
4. Commit with conventional commits: `git commit -m "feat: add amazing feature"`
5. Push and create PR: `git push origin feature/amazing-feature`

## 📊 Performance

### Optimizations Implemented

- **Async Operations**: Full asyncio support with connection pooling
- **Batch Processing**: Bulk operations for users and containers
- **Caching Layer**: Advanced caching with TTL and LRU eviction
- **Memory Profiling**: Built-in memory leak detection
- **Query Optimization**: SQLAlchemy query optimization with pagination
- **Lazy Loading**: Virtual scrolling and on-demand data loading

### Benchmarks

- **User Creation**: <30ms per user, <5s for 100 users batch
- **Container Operations**: <200ms single, <15s for 50 containers batch
- **Query Performance**: <500ms for paginated queries
- **Cache Performance**: <1ms for cache hits
- **Memory Usage**: <50MB idle, optimized with profiling tools

## 🔒 Security

### Security Features

- **Encryption**: AES-256-GCM for sensitive data
- **Key Management**: Secure key generation and storage
- **Authentication**: Multi-factor authentication support
- **Audit Logging**: Comprehensive security event logging
- **Input Validation**: Pydantic models with strict validation
- **Dependency Scanning**: Regular security updates

### Best Practices

```bash
# Enable security features
vpn config set security.encryption_enabled true
vpn config set security.audit_logging true
vpn config set security.mfa_required true

# Security monitoring
vpn monitor security --real-time
vpn audit logs --filter security
```

## 📖 Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[Installation Guide](docs/installation.md)** - Detailed installation instructions
- **[User Guide](docs/user-guide.md)** - Complete user documentation
- **[CLI Reference](docs/cli-reference.md)** - All CLI commands
- **[TUI Guide](docs/tui-guide.md)** - Terminal UI documentation
- **[API Reference](docs/api-reference.md)** - Python API documentation
- **[Architecture](docs/architecture.md)** - System design and architecture
- **[Migration Guide](docs/migration.md)** - Migrate from other VPN solutions

## 🤝 Support

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/ikeniborn/vpn/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ikeniborn/vpn/discussions)
- **Documentation**: Check the `docs/` directory
- **Debug Mode**: Run with `--debug` flag for detailed output

### Reporting Issues

When reporting issues, include:

1. System information: `vpn doctor`
2. Debug output: `vpn --debug [command]`
3. Configuration: `vpn config show --redacted`
4. Steps to reproduce

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Textual](https://textual.textualize.io/) for the terminal UI
- Powered by [Typer](https://typer.tiangolo.com/) for CLI interface
- Uses [Pydantic](https://pydantic-docs.helpmanual.io/) for data validation
- Optimized with [SQLAlchemy](https://www.sqlalchemy.org/) for database operations

---

**VPN Manager** - Modern, Fast, and Secure VPN Management System