# Troubleshooting Outline Server Issues

This document provides solutions for common issues with the Outline Server component of the integrated VPN solution.

## Issue: "Need to specify hostname in shadowbox_server_config.json"

### Symptoms
- The Outline Server container fails to start or constantly restarts
- Error message in logs: `Need to specify hostname in shadowbox_server_config.json`
- Port 8388 is not listening despite the container being present

### Root Cause
The ken1029/shadowbox:latest image requires a configuration file at `/opt/outline/data/shadowbox_server_config.json` that specifies the server's hostname (IP address). This file is not created by default in the setup script.

### Solution
Run the fix-outline.sh script which:
1. Determines your server's public IP address
2. Creates the missing shadowbox_server_config.json file with proper permissions
3. Restarts the containers to apply changes

```bash
sudo ./scripts/fix-outline.sh
```

## Issue: Network Connectivity from Containers

### Symptoms
- Curl requests to ipinfo.io fail with "Host is unreachable"
- Containers cannot connect to the internet

### Root Cause
This can be caused by:
1. Docker network configuration issues
2. Firewall blocking outgoing connections from containers
3. Network configuration on the host preventing Docker's network access

### Solution
1. Check Docker's network configuration:
   ```bash
   docker network ls
   docker network inspect bridge
   ```

2. Verify iptables is not blocking container traffic:
   ```bash
   sudo iptables -L -v
   ```

3. Check if IP forwarding is enabled:
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   ```
   Should output "1". If not, enable it:
   ```bash
   echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
   ```

## Issue: Container Platform Mismatch

### Symptoms
- Containers fail with errors related to executable format
- ARM64-specific error messages on ARM-based systems

### Root Cause
Using Docker images that do not match your system's architecture.

### Solution
1. Verify your system architecture:
   ```bash
   uname -m
   ```

2. Make sure the correct platform-specific images are being used in docker-compose.yml:
   - For ARM64/aarch64: Use ken1029/shadowbox:latest and ken1029/watchtower:arm64
   - For ARMv7: Use ken1029/shadowbox:latest and ken1029/watchtower:arm32
   - For x86_64: Use shadowsocks/shadowsocks-libev:latest and containrrr/watchtower:latest

3. Explicitly specify the platform in docker-compose.yml:
   ```yaml
   platform: linux/arm64  # Or appropriate platform
   ```

## Verifying Correct Operation

After applying fixes, check if the Outline Server is working correctly:

1. Check container status:
   ```bash
   docker ps
   ```

2. Verify the port is listening:
   ```bash
   netstat -tuln | grep 8388
   ```

3. Check container logs for any remaining errors:
   ```bash
   docker logs outline-server
   ```

4. Test connectivity to the server using an Outline client