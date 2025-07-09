# Migration from Rust Version

This guide helps you migrate from the Rust-based VPN Manager to the new Python implementation while preserving your data and configurations.

## Overview

The Python version maintains compatibility with the Rust version's data structures and configurations, allowing for seamless migration. The migration process preserves:

- User accounts and credentials
- Server configurations
- Traffic statistics
- Access logs
- Custom settings

## Prerequisites

Before starting the migration:

1. **Backup your existing data**:
   ```bash
   # Backup Rust version data
   sudo cp -r /etc/vpn /etc/vpn-backup
   sudo cp -r /var/lib/vpn /var/lib/vpn-backup
   ```

2. **Install Python version** alongside Rust version:
   ```bash
   pip install vpn-manager
   ```

3. **Stop Rust services**:
   ```bash
   sudo systemctl stop vpn-server
   sudo systemctl stop vpn-proxy
   ```

## Migration Methods

### Method 1: Automated Migration (Recommended)

The Python version includes an automated migration tool:

```bash
# Run migration wizard
vpn migrate from-rust

# Or specify paths explicitly
vpn migrate from-rust \
    --rust-config /etc/vpn/config.toml \
    --rust-data /var/lib/vpn \
    --backup-first
```

The migration tool will:
1. Detect existing Rust installation
2. Parse configuration files
3. Convert user data
4. Migrate server configurations
5. Preserve traffic statistics
6. Create Python-compatible database

### Method 2: Manual Migration

For custom setups or troubleshooting:

#### Step 1: Export Data from Rust Version

If you still have the Rust version running:

```bash
# Export users (if Rust CLI is available)
vpn users list --format json > rust-users.json
vpn config show --format toml > rust-config.toml
```

#### Step 2: Prepare Python Environment

```bash
# Initialize Python version
vpn config init

# Set basic configuration
vpn config set server.install_path /opt/vpn-python
```

#### Step 3: Convert Configuration

Create a configuration mapping script:

```python
# migrate_config.py
import toml
import json
from pathlib import Path

def migrate_config():
    # Read Rust config
    rust_config = toml.load("/etc/vpn/config.toml")
    
    # Convert to Python format
    python_config = {
        "database": {
            "url": "sqlite:///vpn.db"
        },
        "server": {
            "host": rust_config.get("server", {}).get("host", "0.0.0.0"),
            "install_path": "/opt/vpn-python",
            "data_path": "/var/lib/vpn-python"
        },
        "logging": {
            "level": rust_config.get("logging", {}).get("level", "info"),
            "file": "/var/log/vpn-python/vpn.log"
        }
    }
    
    # Save Python config
    with open("config.toml", "w") as f:
        toml.dump(python_config, f)

if __name__ == "__main__":
    migrate_config()
```

Run the conversion:
```bash
python migrate_config.py
vpn config import config.toml
```

## Data Structure Mapping

### User Data Migration

The Rust version stores users in individual JSON files. The Python version uses a SQLite database but can import the same structure:

```bash
# Convert Rust user files to Python format
vpn migrate users \
    --from-directory /var/lib/vpn/users \
    --format rust-json
```

#### Manual User Migration

If you need to migrate specific users:

```python
# migrate_users.py
import json
import asyncio
from pathlib import Path
from vpn.services.user_manager import UserManager
from vpn.core.models import User, ProtocolConfig, ProtocolType

async def migrate_users():
    manager = UserManager()
    rust_users_dir = Path("/var/lib/vpn/users")
    
    for user_file in rust_users_dir.glob("*/config.json"):
        with open(user_file) as f:
            rust_user = json.load(f)
        
        # Convert protocol
        protocol_map = {
            "vless": ProtocolType.VLESS,
            "shadowsocks": ProtocolType.SHADOWSOCKS,
            "wireguard": ProtocolType.WIREGUARD
        }
        
        protocol_type = protocol_map.get(
            rust_user["protocol"]["type"].lower(),
            ProtocolType.VLESS
        )
        
        # Create Python user
        try:
            user = await manager.create(
                username=rust_user["username"],
                protocol=protocol_type,
                email=rust_user.get("email"),
                # Preserve other fields
            )
            print(f"Migrated user: {user.username}")
        except Exception as e:
            print(f"Error migrating {rust_user['username']}: {e}")

# Run migration
asyncio.run(migrate_users())
```

### Server Configuration Migration

Server configurations are mapped as follows:

| Rust Config | Python Config | Notes |
|-------------|---------------|-------|
| `server.protocol` | `protocol.type` | Direct mapping |
| `server.port` | `port` | Same value |
| `server.domain` | `domain` | Same value |
| `server.keys.private_key` | `extra_config.reality.private_key` | For VLESS |
| `server.docker.image` | `docker_config.image` | Docker settings |

### Traffic Statistics Migration

Traffic data is preserved during migration:

```bash
# Migrate traffic statistics
vpn migrate traffic \
    --from-directory /var/lib/vpn/traffic \
    --preserve-history
```

## Configuration Differences

### File Locations

| Component | Rust Location | Python Location |
|-----------|---------------|-----------------|
| Config | `/etc/vpn/config.toml` | `~/.config/vpn-manager/config.toml` |
| Data | `/var/lib/vpn/` | `/var/lib/vpn-manager/` |
| Logs | `/var/log/vpn/` | `/var/log/vpn-manager/` |
| Users | `/var/lib/vpn/users/` | Database in data directory |

### Command Changes

| Rust Command | Python Command | Notes |
|--------------|----------------|-------|
| `vpn user create` | `vpn users create` | Plural form |
| `vpn server start` | `vpn server start` | Same syntax |
| `vpn install` | `vpn server install` | More specific |
| `vpn status` | `vpn monitor stats` | Reorganized |

### Configuration Format

The Python version uses the same TOML format but with some structural changes:

=== "Rust Config"
    ```toml
    [server]
    protocol = "vless"
    port = 8443
    domain = "vpn.example.com"
    
    [server.keys]
    private_key = "..."
    public_key = "..."
    
    [docker]
    image = "teddysun/xray:latest"
    ```

=== "Python Config"
    ```toml
    [server]
    host = "0.0.0.0"
    install_path = "/opt/vpn"
    
    [protocol]
    type = "vless"
    
    [docker]
    image = "teddysun/xray:latest"
    
    [database]
    url = "sqlite:///vpn.db"
    ```

## Step-by-Step Migration

### Complete Migration Process

1. **Preparation**:
   ```bash
   # Stop Rust services
   sudo systemctl stop vpn-server
   sudo systemctl disable vpn-server
   
   # Backup data
   sudo tar -czf vpn-rust-backup.tar.gz /etc/vpn /var/lib/vpn /var/log/vpn
   ```

2. **Install Python Version**:
   ```bash
   pip install vpn-manager
   vpn doctor --check all
   ```

3. **Run Migration**:
   ```bash
   vpn migrate from-rust --interactive
   ```
   
   Follow the prompts to:
   - Locate Rust installation
   - Choose migration options
   - Verify data integrity
   - Test migrated configuration

4. **Verify Migration**:
   ```bash
   # Check users
   vpn users list
   
   # Check servers
   vpn server list
   
   # Test connectivity
   vpn doctor --check connectivity
   ```

5. **Start Python Services**:
   ```bash
   # Start migrated servers
   vpn server start --all
   
   # Test a connection
   vpn proxy start --type http --port 8888
   vpn proxy test --type http --port 8888
   ```

6. **Update Systemd Services** (optional):
   ```bash
   # Remove Rust service
   sudo systemctl disable vpn-server
   sudo rm /etc/systemd/system/vpn-server.service
   
   # Install Python service
   vpn install --systemd
   sudo systemctl enable vpn-manager
   sudo systemctl start vpn-manager
   ```

## Validation and Testing

### Data Integrity Checks

After migration, verify data integrity:

```bash
# Compare user counts
echo "Rust users: $(find /var/lib/vpn/users -name config.json | wc -l)"
echo "Python users: $(vpn users list --format json | jq length)"

# Check traffic data
vpn users stats --detailed

# Verify server configurations
vpn server list --show-config
```

### Functionality Testing

Test all critical functionality:

```bash
# Test user creation
vpn users create test-migration --protocol vless
vpn users show test-migration --connection-info

# Test server operations
vpn server status --all
vpn server logs main-server --tail 10

# Test proxy services
vpn proxy start --type http --port 8888
vpn proxy test --type http --port 8888
vpn proxy stop http-proxy-8888

# Clean up test user
vpn users delete test-migration --force
```

## Troubleshooting Migration Issues

### Common Issues

#### 1. Permission Errors
```bash
# Fix file permissions
sudo chown -R $USER:$USER ~/.config/vpn-manager/
sudo chown -R vpn-manager:vpn-manager /var/lib/vpn-manager/
```

#### 2. Database Migration Errors
```bash
# Reset database and re-migrate
rm ~/.config/vpn-manager/vpn.db
vpn migrate from-rust --reset-database
```

#### 3. Docker Container Issues
```bash
# Clean up old containers
docker container prune
docker image prune

# Restart Docker
sudo systemctl restart docker
vpn server restart --all
```

#### 4. Configuration Conflicts
```bash
# Reset configuration
vpn config reset --force
vpn migrate from-rust --config-only
```

### Migration Logs

Check migration logs for detailed information:

```bash
# View migration logs
vpn logs --component migration --level debug

# Check for specific errors
vpn logs --component migration --level error --since 1h
```

## Rollback Procedure

If you need to rollback to the Rust version:

1. **Stop Python services**:
   ```bash
   vpn server stop --all
   vpn proxy stop --all
   ```

2. **Restore Rust backup**:
   ```bash
   sudo tar -xzf vpn-rust-backup.tar.gz -C /
   ```

3. **Restart Rust services**:
   ```bash
   sudo systemctl start vpn-server
   sudo systemctl enable vpn-server
   ```

## Post-Migration Steps

### 1. Update Client Configurations

Client configurations remain compatible, but you may want to update:

```bash
# Generate new connection strings with Python version
vpn users show alice --connection-info
```

### 2. Update Monitoring

Set up monitoring for the Python version:

```bash
# Configure system monitoring
vpn monitor stats --refresh 30 > /var/log/vpn-stats.log &

# Set up log rotation
sudo tee /etc/logrotate.d/vpn-manager <<EOF
/var/log/vpn-manager/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 vpn-manager vpn-manager
}
EOF
```

### 3. Update Backup Scripts

Update your backup scripts for the new structure:

```bash
#!/bin/bash
# backup-vpn-python.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/vpn-manager"

# Export users and config
vpn users export --format json --include-keys > "$BACKUP_DIR/users_$DATE.json"
vpn config export > "$BACKUP_DIR/config_$DATE.toml"

# Backup database
cp ~/.config/vpn-manager/vpn.db "$BACKUP_DIR/database_$DATE.db"

# Backup logs
tar -czf "$BACKUP_DIR/logs_$DATE.tar.gz" /var/log/vpn-manager/
```

## Migration Checklist

- [ ] Backup existing Rust installation
- [ ] Install Python version
- [ ] Run migration tool
- [ ] Verify user data migration
- [ ] Test server configurations
- [ ] Validate traffic statistics
- [ ] Test client connections
- [ ] Update monitoring scripts
- [ ] Update backup procedures
- [ ] Update documentation
- [ ] Train team on new CLI commands
- [ ] Schedule Rust version removal

## Getting Help

If you encounter issues during migration:

1. Check the [Troubleshooting Guide](../admin-guide/troubleshooting.md)
2. Run `vpn doctor --verbose` for diagnostics
3. Check migration logs: `vpn logs --component migration`
4. Join our [Discord Community](https://discord.gg/vpn-manager)
5. Create an issue on [GitHub](https://github.com/vpn-manager/vpn-python/issues) with:
   - Migration command used
   - Error messages
   - System information (`vpn version --detailed`)
   - Relevant log excerpts

The migration process is designed to be safe and reversible. Don't hesitate to reach out for help if needed!