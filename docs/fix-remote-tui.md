# Fixing VPN Manager TUI on Remote Server

## Problem
The TUI interface shows empty panels with no data, indicating issues with:
- Database initialization
- Docker connectivity
- Service initialization

## Quick Fix Steps

### 1. Run the Fix Script
```bash
# First, apply the installation fixes
bash scripts/fix-remote-installation.sh

# Reload your shell
source ~/.bashrc
```

### 2. Initialize the Database
```bash
# Run database initialization
python scripts/init-database.py

# Or if that doesn't work:
cd ~/vpn
source ~/.vpn-venv/bin/activate
python scripts/init-database.py
```

### 3. Check Docker Access
```bash
# Verify Docker is accessible
docker ps

# If not, add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 4. Run Diagnostics
```bash
# Run the diagnostic script
bash scripts/diagnose-tui.sh
```

### 5. Test TUI with Debug Mode
```bash
# Run TUI with debug logging
VPN_LOG_LEVEL=DEBUG vpn tui

# Or with specific paths
VPN_INSTALL_PATH="$HOME/.local/share/vpn-manager" \
VPN_CONFIG_PATH="$HOME/.config/vpn-manager" \
VPN_DATA_PATH="$HOME/.local/share/vpn-manager" \
vpn tui
```

## Manual Fixes

### If Database Still Not Working
```bash
# Create database manually
mkdir -p ~/.local/share/vpn-manager
cd ~/vpn
python -c "
import asyncio
from vpn.core.database import init_database
asyncio.run(init_database())
"
```

### If Docker Not Accessible
```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# Should show something like:
# srw-rw---- 1 root docker 0 Jan 1 00:00 /var/run/docker.sock

# Fix permissions
sudo chmod 666 /var/run/docker.sock
# OR better:
sudo usermod -aG docker $USER
# Then logout and login again
```

### Environment Variables
Add to your `~/.bashrc`:
```bash
export VPN_INSTALL_PATH="$HOME/.local/share/vpn-manager"
export VPN_CONFIG_PATH="$HOME/.config/vpn-manager"
export VPN_DATA_PATH="$HOME/.local/share/vpn-manager"
export VPN_LOG_LEVEL="INFO"
```

## Checking Logs

```bash
# View TUI logs
tail -f ~/.local/share/vpn-manager/logs/vpn.log

# View all logs
ls -la ~/.local/share/vpn-manager/logs/
```

## Common Issues

### 1. "Permission denied: '/opt/vpn'"
- Already fixed by setting VPN_INSTALL_PATH
- The fix script handles this automatically

### 2. Empty TUI panels
- Database not initialized
- Docker not accessible
- Run the init-database.py script

### 3. "sudo vpn: command not found"
- Fixed by the wrapper script in /usr/local/bin/vpn
- Run fix-remote-installation.sh

## Verification

After fixes, verify everything works:
```bash
# Check vpn command
vpn --version
sudo vpn --version

# Check database
ls -la ~/.local/share/vpn-manager/db/vpn.db

# Check Docker
docker ps

# Run TUI
vpn tui
```

The TUI should now show:
- User statistics in the top cards
- Server status in the main panel
- Recent activity in the bottom panel