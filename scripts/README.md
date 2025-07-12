# VPN Manager Scripts

This directory contains utility scripts organized by category:

## Directory Structure

- **install/** - Installation and setup scripts
  - `install.sh` - Main installation script for VPN Manager

- **maintenance/** - System maintenance and troubleshooting scripts
  - `fix-remote-installation.sh` - Fixes permission issues on remote servers
  - `diagnose-tui.sh` - Diagnoses TUI issues and checks system configuration
  - `init-database.py` - Initializes the VPN Manager database

- **dev/** - Development helper scripts
  - (Currently empty - for future development tools)

## Usage

All scripts should be run from the project root directory:

```bash
# Installation
bash scripts/install/install.sh

# Maintenance
bash scripts/maintenance/diagnose-tui.sh
python scripts/maintenance/init-database.py

# Fix remote server issues
bash scripts/maintenance/fix-remote-installation.sh
```