# Installation Guide

This guide covers different methods to install VPN Manager on your system.

## System Requirements

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

## Installation Methods

### 1. PyPI Installation (Recommended)

Install the latest stable version from PyPI:

```bash
pip install vpn-manager
```

For development dependencies:

```bash
pip install "vpn-manager[dev]"
```

### 2. From Source

Clone and install from the GitHub repository:

```bash
git clone https://github.com/vpn-manager/vpn-python.git
cd vpn-python
pip install -e .
```

For development:

```bash
git clone https://github.com/vpn-manager/vpn-python.git
cd vpn-python
pip install -e ".[dev]"
```

### 3. Docker Installation

Run VPN Manager in a Docker container:

```bash
docker run -d \
  --name vpn-manager \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v vpn-data:/app/data \
  -p 8443:8443 \
  vpnmanager/vpn-manager:latest
```

### 4. One-Line Installation Script

For quick installation on Linux/macOS:

```bash
curl -fsSL https://get.vpn-manager.io | bash
```

Or with wget:

```bash
wget -qO- https://get.vpn-manager.io | bash
```

## Package Manager Installation

### Ubuntu/Debian

```bash
# Add repository
curl -fsSL https://packages.vpn-manager.io/gpg | sudo apt-key add -
echo "deb https://packages.vpn-manager.io/apt stable main" | sudo tee /etc/apt/sources.list.d/vpn-manager.list

# Install
sudo apt update
sudo apt install vpn-manager
```

### CentOS/RHEL/Fedora

```bash
# Add repository
sudo tee /etc/yum.repos.d/vpn-manager.repo <<EOF
[vpn-manager]
name=VPN Manager Repository
baseurl=https://packages.vpn-manager.io/rpm
enabled=1
gpgcheck=1
gpgkey=https://packages.vpn-manager.io/gpg
EOF

# Install
sudo yum install vpn-manager
```

### macOS (Homebrew)

```bash
brew tap vpn-manager/tap
brew install vpn-manager
```

### Windows (Chocolatey)

```powershell
choco install vpn-manager
```

### Snap Package

```bash
sudo snap install vpn-manager --classic
```

## Post-Installation Setup

### 1. Verify Installation

Check that VPN Manager is installed correctly:

```bash
vpn --version
vpn --help
```

### 2. Initialize Configuration

Create initial configuration:

```bash
vpn config init
```

This creates configuration files in:
- Linux/macOS: `~/.config/vpn-manager/`
- Windows: `%APPDATA%/vpn-manager/`

### 3. Docker Setup

Ensure Docker is running and accessible:

```bash
vpn doctor --check docker
```

If Docker is not installed, install it:

=== "Ubuntu/Debian"
    ```bash
    curl -fsSL https://get.docker.com | bash
    sudo usermod -aG docker $USER
    newgrp docker
    ```

=== "CentOS/RHEL"
    ```bash
    sudo yum install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    ```

=== "macOS"
    ```bash
    brew install --cask docker
    # Start Docker Desktop application
    ```

=== "Windows"
    Download and install Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop)

### 4. Firewall Configuration

Allow necessary ports through the firewall:

```bash
# Allow VPN ports (adjust as needed)
sudo ufw allow 8443/tcp
sudo ufw allow 8443/udp
sudo ufw allow 1080/tcp  # SOCKS5 proxy
sudo ufw allow 8888/tcp  # HTTP proxy
```

## Development Installation

For development and testing:

```bash
# Clone repository
git clone https://github.com/vpn-manager/vpn-python.git
cd vpn-python

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install in development mode
pip install -e ".[dev]"

# Install pre-commit hooks
pre-commit install

# Run tests
pytest
```

## Virtual Environment (Recommended)

Using a virtual environment is recommended to avoid conflicts:

```bash
# Create virtual environment
python -m venv vpn-manager-env

# Activate virtual environment
source vpn-manager-env/bin/activate  # Linux/macOS
# or
vpn-manager-env\Scripts\activate  # Windows

# Install VPN Manager
pip install vpn-manager

# When done, deactivate
deactivate
```

## Troubleshooting

### Common Issues

#### Permission Denied Errors

If you encounter permission errors:

```bash
# On Linux/macOS, add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Or run with sudo (not recommended for regular use)
sudo vpn <command>
```

#### Python Version Issues

Ensure you're using Python 3.10+:

```bash
python --version
# If using older Python, install Python 3.11
sudo apt install python3.11 python3.11-pip  # Ubuntu/Debian
```

#### Docker Not Found

If Docker is not found:

```bash
# Check if Docker is installed
docker --version

# Check if Docker daemon is running
sudo systemctl status docker

# Start Docker if not running
sudo systemctl start docker
```

#### Network Issues

If you encounter network connectivity issues:

```bash
# Check internet connectivity
ping google.com

# Check DNS resolution
nslookup pypi.org

# Use alternative index if needed
pip install --index-url https://pypi.python.org/simple/ vpn-manager
```

### Getting Help

If you encounter issues:

1. Check the [Troubleshooting Guide](../admin-guide/troubleshooting.md)
2. Run diagnostics: `vpn doctor`
3. Check logs: `vpn logs --level debug`
4. Search [GitHub Issues](https://github.com/vpn-manager/vpn-python/issues)
5. Create a new issue with logs and system information

## Next Steps

After installation:

1. [Quick Start Guide](quickstart.md) - Set up your first VPN server
2. [Configuration Guide](configuration.md) - Customize VPN Manager settings
3. [CLI Commands](../user-guide/cli-commands.md) - Learn the command-line interface
4. [TUI Interface](../user-guide/tui-interface.md) - Use the terminal interface

## Uninstallation

To remove VPN Manager:

```bash
# Stop all services
vpn server stop --all
vpn proxy stop --all

# Remove package
pip uninstall vpn-manager

# Remove configuration (optional)
rm -rf ~/.config/vpn-manager/  # Linux/macOS
# or
rmdir /S %APPDATA%\vpn-manager  # Windows

# Remove Docker containers (optional)
docker container prune
docker image prune
```