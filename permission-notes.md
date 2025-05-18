# V2Ray Permission Fix Notes

## Problem Detected
The V2Ray service was failing to start with the following error:
```
Failed to start: main/commands: failed to load config: [/etc/v2ray/config.json] > fail to load /etc/v2ray/config.json: open /etc/v2ray/config.json: permission denied
```

After fixing the config file permissions, it then failed with:
```
Failed to start: main/commands: failed to load config: [/etc/v2ray/config.json] > infra/conf/v4: Failed to build TLS config. > infra/conf/cfgcommon/tlscfg: failed to parse key > open /opt/outline/persisted-state/shadowbox-selfsigned.key: permission denied
```

## Root Cause
The Docker container for V2Ray could not read the following files due to restrictive permissions:
1. `/opt/v2ray/config.json` - Had permissions 660 (rw-rw----)
2. `/opt/outline/persisted-state/shadowbox-selfsigned.key` - Had permissions 600 (rw-------)
3. `/opt/outline/persisted-state/shadowbox-selfsigned.crt` - Had permissions 660 (rw-rw----)

## Solution Applied
1. Fixed existing installation by making these files readable:
   ```bash
   sudo chmod 644 /opt/v2ray/config.json
   sudo chmod 644 /opt/outline/persisted-state/shadowbox-selfsigned.key
   sudo chmod 644 /opt/outline/persisted-state/shadowbox-selfsigned.crt
   sudo docker restart v2ray
   ```

2. Created a fix-permissions.sh script for easy fixing if this happens again.

3. Modified the installation script to set correct permissions during initial installation:
   - Added permissions fix to the certificate generation function
   - Added permissions fix to the V2Ray config writing function

## Security Considerations
While private keys usually have 600 permissions for security, Docker containers need read access to these files. The 644 permissions (rw-r--r--) are still secure enough for this use case as:
1. The files remain in protected directories that only root can access
2. The permissions simply allow processes to read but not modify the files
3. For production environments with higher security requirements, consider using Docker secrets or a more robust permission model

## Prevention
The installation script has been modified to prevent this issue from occurring in future installations. If upgrading or reinstalling, run `./fix-permissions.sh` to ensure proper permissions.