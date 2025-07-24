# VPN Management System - Installation Guide

## Quick Start

```bash
# Extract the archive
tar -xzf vpn-release.tar.gz
cd vpn-release

# Install the system
sudo ./install.sh

# Verify installation
vpn --version
```

## Installation Notes

- Extract the archive to a temporary directory (e.g., ~/vpn-install)
- Run `./install.sh` to install the VPN system
- Run `./uninstall.sh` to remove the VPN system
- The db directory will be created at /opt/vpn/db during installation
- Templates directory contains Docker Compose configurations and service configs
- Docker files are in the docker/ directory within the release
- Installation requires root privileges

## Post-Installation

After installation, the VPN system will be available at:
- Binaries: /usr/local/bin/vpn*
- Configuration: /opt/vpn/configs/
- Logs: /opt/vpn/logs/
- Documentation: /opt/vpn/docs/

To start using the VPN system:
```bash
# View help
vpn --help

# Start interactive menu
sudo vpn menu

# Check service status
systemctl status vpn-manager
```

## Uninstallation

To remove the VPN system:
```bash
# With backup
sudo /opt/vpn/scripts/archive-uninstall.sh

# Without backup (force)
sudo /opt/vpn/scripts/archive-uninstall.sh --force
```
