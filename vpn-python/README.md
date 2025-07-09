# VPN Manager - Python Implementation

Modern VPN Management System with Terminal User Interface (TUI).

## Features

- 🚀 **Multiple VPN Protocols**: VLESS+Reality, Shadowsocks, WireGuard, HTTP/SOCKS5 Proxy
- 🎨 **Rich TUI**: Interactive terminal interface built with Textual
- 🔧 **CLI Interface**: Comprehensive command-line interface with Click/Typer
- 🐳 **Docker Integration**: Full container lifecycle management
- 📊 **Real-time Monitoring**: Traffic statistics and system metrics
- 🔐 **Security First**: Secure key generation and management
- 🌐 **Multi-platform**: Linux, macOS, and Windows support

## Quick Start

### Installation

```bash
# Install from PyPI (when available)
pip install vpn-manager

# Or install from source
git clone https://github.com/ikeniborn/vpn-python
cd vpn-python
pip install -e ".[dev]"
```

### Basic Usage

```bash
# Launch interactive TUI
vpn menu

# CLI commands
vpn users create alice
vpn server install --protocol vless --port 8443
vpn proxy start
vpn monitor traffic --real-time
```

## Development

### Setup Development Environment

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install development dependencies
pip install -e ".[dev]"

# Setup pre-commit hooks
pre-commit install

# Run tests
pytest

# Run type checking
mypy vpn

# Run linter
ruff check .

# Format code
black .
```

### Project Structure

```
vpn-python/
├── vpn/                    # Main package
│   ├── cli/               # CLI commands
│   ├── core/              # Core functionality
│   ├── services/          # Business logic
│   ├── tui/               # Terminal UI
│   ├── templates/         # Configuration templates
│   └── utils/             # Utilities
├── tests/                 # Test suite
├── docs/                  # Documentation
└── pyproject.toml         # Project configuration
```

## Documentation

Full documentation is available at [https://vpn-manager.readthedocs.io](https://vpn-manager.readthedocs.io)

## License

MIT License - see LICENSE file for details.