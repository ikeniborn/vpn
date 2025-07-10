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

## Installation Method

### Recommended Installation

The easiest way to install VPN Manager is using the installation script:

```bash
# Clone and install
git clone https://github.com/ikeniborn/vpn.git
cd vpn
bash scripts/install.sh
```

The installation script will:
- Install all system dependencies (Ubuntu/Debian)
- Create an isolated Python environment
- Install VPN Manager and all dependencies
- Configure shell integration
- Prompt to reload your shell

### Manual Installation

If you prefer manual installation or the script doesn't work for your system:

```bash
# Clone repository
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -e .

# For development
pip install -e ".[dev,test,docs]"
```

### Docker Installation

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

### 6. Installation from Repository (Recommended for Server Deployment)

For production deployment on new servers:

```bash
# Clone the repository
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# Run installation script
bash scripts/install.sh
```

#### What the script does:

1. **System Dependencies** (Ubuntu/Debian):
   - python3-dev, python3-pip, python3-venv
   - build-essential, gcc, make
   - libssl-dev, libffi-dev (for cryptography)
   - libldap2-dev, libsasl2-dev (for LDAP support)
   - libpq-dev (for PostgreSQL)
   - libxml2-dev, libxslt1-dev (for XML processing)
   - Docker (optional, with installation instructions)

2. **Python Environment**:
   - Detects PEP 668 restrictions
   - Creates virtual environment automatically
   - Installs all Python dependencies
   - Configures PATH in ~/.bashrc

3. **Post-Installation**:
   - Creates configuration directories
   - Runs system diagnostics
   - Provides usage instructions

#### Installation Options:

```bash
# Standard installation (production)
bash scripts/install.sh

# Development installation (editable mode)
bash scripts/install.sh --dev

# One-line installation
git clone https://github.com/ikeniborn/vpn.git && cd vpn && bash scripts/install.sh
```

### 7. Manual Installation Steps

If you prefer to install manually or the script doesn't work for your system:

```bash
# 1. Install system dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y python3-dev python3-pip python3-venv \
    build-essential libssl-dev libffi-dev libldap2-dev \
    libsasl2-dev libpq-dev git curl wget

# 2. Clone repository
git clone https://github.com/ikeniborn/vpn.git
cd vpn

# 3. Create virtual environment
python3 -m venv venv
source venv/bin/activate

# 4. Install Python dependencies
pip install -e .

# 5. Install Docker (if not installed)
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
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

## Understanding Python Environments

### PEP 668 and Externally Managed Environments

Modern Linux distributions (Ubuntu 23.04+, Debian 12+, Fedora 38+) implement PEP 668, which prevents pip from installing packages system-wide to avoid conflicts with the system package manager.

If you see this error:
```
error: externally-managed-environment
```

You have three options:
1. **Use pipx** (recommended) - Automatically manages virtual environments
2. **Create a virtual environment** - Manual but flexible
3. **Use --break-system-packages** - Not recommended, can break your system

### Virtual Environment Best Practices

Using a virtual environment isolates VPN Manager from system packages:

```bash
# Create virtual environment
python3 -m venv ~/.vpn-manager-venv

# Activate virtual environment
source ~/.vpn-manager-venv/bin/activate  # Linux/macOS
# or
~/.vpn-manager-venv\Scripts\activate  # Windows

# Install VPN Manager
pip install vpn-manager

# Add to shell profile for persistence
echo 'alias vpn-activate="source ~/.vpn-manager-venv/bin/activate"' >> ~/.bashrc

# When done, deactivate
deactivate
```

### Using pipx

pipx is a tool that automatically installs Python applications in isolated environments:

```bash
# Install pipx
python3 -m pip install --user pipx
python3 -m pipx ensurepath

# Restart your shell or run
source ~/.bashrc

# Install VPN Manager
pipx install vpn-manager

# The 'vpn' command is now available globally
vpn --version
```

## Troubleshooting

### Common Issues

#### Externally Managed Environment Error

If you encounter the PEP 668 error:

```bash
# Option 1: Use pipx
pipx install vpn-manager

# Option 2: Create virtual environment
python3 -m venv venv
source venv/bin/activate
pip install vpn-manager

# Option 3: Use the installation script (handles this automatically)
curl -fsSL https://get.vpn-manager.io | bash
```

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