# Legacy Scripts to be Removed

## Overview
After creating the unified `vpn.sh` script, the following root scripts can be considered legacy and removed:

## Scripts to Remove

### 1. **install_vpn.sh**
- **Purpose**: Server installation
- **Replaced by**: `vpn.sh install`
- **Dependencies**: Uses modules from `lib/` and `modules/install/`
- **Status**: Can be removed after testing

### 2. **manage_users.sh**
- **Purpose**: User management interface
- **Replaced by**: `vpn.sh users` or `vpn.sh user <command>`
- **Dependencies**: Uses modules from `lib/` and `modules/users/`, `modules/server/`, `modules/monitoring/`
- **Status**: Can be removed after testing

### 3. **install_client.sh**
- **Purpose**: Client installation
- **Replaced by**: `vpn.sh client <command>`
- **Dependencies**: Minimal, mostly self-contained
- **Status**: Can be removed after testing

### 4. **uninstall.sh**
- **Purpose**: Server uninstallation
- **Replaced by**: `vpn.sh uninstall`
- **Dependencies**: Minimal, uses `lib/common.sh`
- **Status**: Can be removed after testing

### 5. **deploy.sh**
- **Purpose**: Deployment and backup operations
- **Replaced by**: `vpn.sh deploy <command>`
- **Dependencies**: Self-contained
- **Status**: Can be removed after testing

### 6. **watchdog.sh**
- **Purpose**: Container monitoring service
- **Replaced by**: `vpn.sh watchdog <command>`
- **Dependencies**: None (standalone script)
- **Status**: Keep as it's referenced by systemd service

## Scripts to Keep

### 1. **vpn.sh** (NEW)
- The unified management script

### 2. **watchdog.sh**
- Required by vpn-watchdog.service systemd unit
- Can be moved to a system location during installation

### 3. **vpn-watchdog.service**
- Systemd service definition file

## Migration Commands

Users can migrate to the new unified script with these equivalent commands:

| Old Command | New Command |
|------------|-------------|
| `sudo ./install_vpn.sh` | `sudo ./vpn.sh install` |
| `sudo ./manage_users.sh` | `sudo ./vpn.sh users` |
| `sudo v2ray-manage` | `sudo ./vpn.sh users` |
| `sudo ./install_client.sh` | `sudo ./vpn.sh client install` |
| `sudo ./uninstall.sh` | `sudo ./vpn.sh uninstall` |
| `sudo ./deploy.sh install` | `sudo ./vpn.sh deploy install` |
| `sudo ./deploy.sh backup` | `sudo ./vpn.sh deploy backup` |

## Removal Plan

1. Test all functionality through `vpn.sh`
2. Update documentation (README.md, CLAUDE.md)
3. Create symlinks for backward compatibility (optional)
4. Remove legacy scripts
5. Update systemd service to use new paths

## Backward Compatibility

To maintain backward compatibility during transition:

```bash
# Create wrapper scripts
echo '#!/bin/bash' > install_vpn.sh
echo './vpn.sh install "$@"' >> install_vpn.sh
chmod +x install_vpn.sh

# Repeat for other scripts...
```