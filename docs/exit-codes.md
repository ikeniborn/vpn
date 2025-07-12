# Exit Codes Reference

VPN Manager uses standardized exit codes to indicate the result of CLI operations. This enables proper error handling in scripts and automation.

## Overview

Exit codes follow Unix conventions with custom extensions for VPN-specific operations:

- **0**: Success
- **1-32**: General system errors
- **33-224**: Application-specific errors
- **130**: Operation cancelled (Ctrl+C)
- **141**: Broken pipe
- **143**: SIGTERM received

## Exit Code Categories

### Success (0)
| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Operation completed successfully |

### General Errors (1-16)
| Code | Name | Description |
|------|------|-------------|
| 1 | GENERAL_ERROR | General error occurred |
| 2 | MISUSE_OF_SHELL_BUILTINS | Misuse of shell builtins |

### Permission and Access Errors (17-32)
| Code | Name | Description |
|------|------|-------------|
| 13 | PERMISSION_DENIED | Permission denied |
| 14 | FILE_NOT_FOUND | File not found |
| 15 | DIRECTORY_NOT_FOUND | Directory not found |
| 16 | ACCESS_DENIED | Access denied |

### Configuration Errors (33-48)
| Code | Name | Description |
|------|------|-------------|
| 33 | CONFIG_ERROR | Configuration error |
| 34 | CONFIG_FILE_NOT_FOUND | Configuration file not found |
| 35 | CONFIG_INVALID | Invalid configuration |
| 36 | CONFIG_PERMISSION_DENIED | Configuration permission denied |

### Database Errors (49-64)
| Code | Name | Description |
|------|------|-------------|
| 49 | DATABASE_ERROR | Database error |
| 50 | DATABASE_CONNECTION_FAILED | Database connection failed |
| 51 | DATABASE_SCHEMA_ERROR | Database schema error |
| 52 | DATABASE_CORRUPTION | Database corruption |

### Network Errors (65-80)
| Code | Name | Description |
|------|------|-------------|
| 65 | NETWORK_ERROR | Network error |
| 66 | CONNECTION_TIMEOUT | Connection timeout |
| 67 | CONNECTION_REFUSED | Connection refused |
| 68 | DNS_ERROR | DNS error |

### Docker Errors (81-96)
| Code | Name | Description |
|------|------|-------------|
| 81 | DOCKER_ERROR | Docker error |
| 82 | DOCKER_NOT_FOUND | Docker not found |
| 83 | DOCKER_CONNECTION_FAILED | Docker connection failed |
| 84 | DOCKER_PERMISSION_DENIED | Docker permission denied |
| 85 | CONTAINER_NOT_FOUND | Container not found |
| 86 | CONTAINER_ALREADY_EXISTS | Container already exists |
| 87 | CONTAINER_START_FAILED | Container start failed |
| 88 | CONTAINER_STOP_FAILED | Container stop failed |

### User Management Errors (97-112)
| Code | Name | Description |
|------|------|-------------|
| 97 | USER_ERROR | User management error |
| 98 | USER_NOT_FOUND | User not found |
| 99 | USER_ALREADY_EXISTS | User already exists |
| 100 | USER_CREATION_FAILED | User creation failed |
| 101 | USER_DELETION_FAILED | User deletion failed |
| 102 | USER_UPDATE_FAILED | User update failed |

### Server Management Errors (113-128)
| Code | Name | Description |
|------|------|-------------|
| 113 | SERVER_ERROR | Server management error |
| 114 | SERVER_NOT_FOUND | Server not found |
| 115 | SERVER_ALREADY_EXISTS | Server already exists |
| 116 | SERVER_START_FAILED | Server start failed |
| 117 | SERVER_STOP_FAILED | Server stop failed |
| 118 | SERVER_RESTART_FAILED | Server restart failed |
| 119 | SERVER_CONFIG_ERROR | Server configuration error |

### Protocol Errors (129-144)
| Code | Name | Description |
|------|------|-------------|
| 129 | PROTOCOL_ERROR | Protocol error |
| 130 | PROTOCOL_NOT_SUPPORTED | Protocol not supported |
| 131 | PROTOCOL_CONFIG_ERROR | Protocol configuration error |
| 132 | VLESS_ERROR | VLESS protocol error |
| 133 | SHADOWSOCKS_ERROR | Shadowsocks protocol error |
| 134 | WIREGUARD_ERROR | WireGuard protocol error |

### Security Errors (145-160)
| Code | Name | Description |
|------|------|-------------|
| 145 | SECURITY_ERROR | Security error |
| 146 | AUTHENTICATION_FAILED | Authentication failed |
| 147 | AUTHORIZATION_FAILED | Authorization failed |
| 148 | CERTIFICATE_ERROR | Certificate error |
| 149 | KEY_ERROR | Key error |

### Validation Errors (161-176)
| Code | Name | Description |
|------|------|-------------|
| 161 | VALIDATION_ERROR | Validation error |
| 162 | INVALID_INPUT | Invalid input |
| 163 | INVALID_FORMAT | Invalid format |
| 164 | INVALID_RANGE | Invalid range |
| 165 | REQUIRED_FIELD_MISSING | Required field missing |

### System Errors (177-192)
| Code | Name | Description |
|------|------|-------------|
| 177 | SYSTEM_ERROR | System error |
| 178 | INSUFFICIENT_RESOURCES | Insufficient resources |
| 179 | DISK_FULL | Disk full |
| 180 | MEMORY_ERROR | Memory error |

### Operation Errors (193-208)
| Code | Name | Description |
|------|------|-------------|
| 193 | OPERATION_FAILED | Operation failed |
| 194 | OPERATION_CANCELLED | Operation cancelled |
| 195 | OPERATION_TIMEOUT | Operation timeout |
| 196 | OPERATION_NOT_SUPPORTED | Operation not supported |

### Import/Export Errors (209-224)
| Code | Name | Description |
|------|------|-------------|
| 209 | IMPORT_ERROR | Import error |
| 210 | EXPORT_ERROR | Export error |
| 211 | BACKUP_ERROR | Backup error |
| 212 | RESTORE_ERROR | Restore error |

## Usage in Scripts

### Basic Exit Code Checking

```bash
#!/bin/bash

# Run VPN command and check exit code
vpn users create john --protocol vless

if [ $? -eq 0 ]; then
    echo "User created successfully"
else
    echo "Failed to create user"
    exit 1
fi
```

### Specific Error Handling

```bash
#!/bin/bash

vpn users create john --protocol vless
exit_code=$?

case $exit_code in
    0)
        echo "Success: User created"
        ;;
    98)
        echo "Error: User not found"
        ;;
    99)
        echo "Error: User already exists"
        ;;
    100)
        echo "Error: User creation failed"
        ;;
    130)
        echo "Operation cancelled by user"
        ;;
    *)
        echo "Unknown error (exit code: $exit_code)"
        ;;
esac
```

### Automation Scripts

```bash
#!/bin/bash

# Automated server deployment with error handling
deploy_server() {
    local server_name=$1
    local protocol=$2
    
    echo "Deploying server: $server_name"
    
    # Create server
    vpn server create "$server_name" --protocol "$protocol" --auto-start
    case $? in
        0)
            echo "✓ Server created successfully"
            ;;
        115)
            echo "⚠ Server already exists, skipping"
            return 0
            ;;
        116)
            echo "✗ Server start failed"
            return 1
            ;;
        *)
            echo "✗ Unknown error during server creation"
            return 1
            ;;
    esac
    
    # Verify server is running
    vpn server status "$server_name" --format plain | grep -q "running"
    if [ $? -eq 0 ]; then
        echo "✓ Server is running"
        return 0
    else
        echo "✗ Server is not running"
        return 1
    fi
}

# Deploy multiple servers
for server in prod-vless prod-shadowsocks test-wireguard; do
    protocol=$(echo $server | cut -d'-' -f2)
    
    if deploy_server "$server" "$protocol"; then
        echo "Server $server deployed successfully"
    else
        echo "Failed to deploy server $server"
        exit 1
    fi
done
```

### Python Scripts

```python
#!/usr/bin/env python3

import subprocess
import sys

def run_vpn_command(command):
    """Run VPN command and return exit code."""
    try:
        result = subprocess.run(
            ["vpn"] + command.split(),
            capture_output=True,
            text=True,
            check=False
        )
        return result.returncode, result.stdout, result.stderr
    except FileNotFoundError:
        print("Error: vpn command not found")
        sys.exit(1)

def main():
    # Create user with error handling
    exit_code, stdout, stderr = run_vpn_command("users create alice --protocol vless")
    
    if exit_code == 0:
        print("✓ User created successfully")
    elif exit_code == 99:
        print("⚠ User already exists")
    elif exit_code == 100:
        print("✗ User creation failed")
        print(f"Error: {stderr}")
        sys.exit(1)
    elif exit_code == 130:
        print("Operation cancelled by user")
        sys.exit(130)
    else:
        print(f"✗ Unknown error (exit code: {exit_code})")
        print(f"Error: {stderr}")
        sys.exit(exit_code)

if __name__ == "__main__":
    main()
```

## Best Practices

### 1. Always Check Exit Codes

```bash
# Good
vpn users create john --protocol vless
if [ $? -ne 0 ]; then
    echo "Failed to create user"
    exit 1
fi

# Better
if ! vpn users create john --protocol vless; then
    echo "Failed to create user"
    exit 1
fi
```

### 2. Handle Specific Error Cases

```bash
# Handle specific errors differently
vpn server start production
exit_code=$?

case $exit_code in
    0)
        echo "Server started"
        ;;
    114)
        echo "Server not found - creating it first"
        vpn server create production --protocol vless
        ;;
    116)
        echo "Server start failed - checking logs"
        vpn server logs production --tail 50
        exit 1
        ;;
esac
```

### 3. Use Proper Exit Codes in Your Scripts

```bash
#!/bin/bash

# Exit with appropriate codes
if [ ! -f "config.yaml" ]; then
    echo "Configuration file not found"
    exit 14  # FILE_NOT_FOUND
fi

if [ ! -r "config.yaml" ]; then
    echo "Cannot read configuration file"
    exit 13  # PERMISSION_DENIED
fi
```

### 4. Provide Meaningful Error Messages

```bash
#!/bin/bash

check_vpn_status() {
    vpn doctor --quiet
    case $? in
        0)
            echo "✓ VPN system is healthy"
            ;;
        177)
            echo "✗ System error detected"
            echo "Run 'vpn doctor' for detailed diagnostics"
            exit 177
            ;;
        *)
            echo "✗ Unknown system issue"
            echo "Run 'vpn doctor' for detailed diagnostics"
            exit 1
            ;;
    esac
}
```

## Viewing Exit Codes

Use the built-in command to view all exit codes:

```bash
# Show complete exit code reference
vpn exit-codes

# Get exit code for last command
echo $?

# In scripts, capture exit code
vpn users list
EXIT_CODE=$?
echo "Command exited with code: $EXIT_CODE"
```

## Integration with Monitoring

### Nagios/Icinga Checks

```bash
#!/bin/bash
# VPN health check for monitoring systems

vpn doctor --quiet
exit_code=$?

case $exit_code in
    0)
        echo "OK - VPN system healthy"
        exit 0  # OK
        ;;
    *)
        echo "CRITICAL - VPN system has issues (exit code: $exit_code)"
        exit 2  # CRITICAL
        ;;
esac
```

### Systemd Service Monitoring

```ini
[Unit]
Description=VPN Health Check
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vpn doctor --quiet
# Use exit codes to determine service status
# 0 = success, anything else = failure

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

### Common Exit Codes and Solutions

| Exit Code | Likely Cause | Solution |
|-----------|--------------|----------|
| 13 | Permission denied | Run with sudo or check file permissions |
| 14 | File not found | Check file path, ensure file exists |
| 33 | Config error | Validate configuration file syntax |
| 49 | Database error | Check database connectivity and permissions |
| 81 | Docker error | Ensure Docker is running and accessible |
| 98 | User not found | Use `vpn users list` to see available users |
| 114 | Server not found | Use `vpn server list` to see available servers |
| 130 | User cancelled | Normal when user presses Ctrl+C |

### Debug Mode

Enable debug mode to get more detailed error information:

```bash
vpn --debug users create john --protocol vless
```

### Verbose Output

Use verbose mode to see detailed operation information:

```bash
vpn --verbose server start production
```

This comprehensive exit code system ensures that VPN Manager CLI commands provide clear, actionable feedback for both interactive use and automation scenarios.