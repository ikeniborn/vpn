# Outline Server Fix Instructions

These instructions will help you resolve the current issue with your Outline Server not starting properly. Follow these steps to fix the problem.

## Problem Description

Your Outline Server container is failing to start properly due to a missing configuration file. The error message `Need to specify hostname in shadowbox_server_config.json` indicates that the container needs a configuration file that specifies the server's hostname/IP address.

## Fix Steps

### 1. Run the Fix Script

Execute the following commands as root or with sudo privileges:

```bash
# Navigate to your project directory (if needed)
cd /path/to/vpn/directory

# Make the fix script executable (if not already)
chmod +x scripts/fix-outline.sh

# Run the fix script
sudo ./scripts/fix-outline.sh
```

This script will:
- Detect your server's IP address
- Create the missing shadowbox_server_config.json file
- Restart the Docker containers

### 2. Verify the Fix

After running the script, check if the containers are running properly:

```bash
# Check container status
docker ps

# Check if the Outline Server port is listening
netstat -tuln | grep 8388

# Check container logs
docker logs outline-server
```

You should see:
1. The outline-server container in a running state
2. Port 8388 listed as LISTENING
3. No errors about missing configuration files in the logs

### 3. If Issues Persist

If problems continue after running the fix script:

1. Check network connectivity from the container:
   ```bash
   docker exec outline-server ping -c 4 8.8.8.8
   ```

2. Verify Docker's network settings:
   ```bash
   docker network inspect bridge
   ```

3. Check if IP forwarding is enabled:
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   ```
   It should output "1".

4. Review the troubleshooting documentation for additional steps:
   ```
   docs/troubleshooting-outline-server.md
   ```

## Future Deployments

The main setup.sh script has been updated to automatically create this configuration file during installation. Future deployments should not encounter this issue.

## Note for ARM-based Systems

If you're running on an ARM64 or ARMv7 system, ensure you're using the correct Docker images:
- ken1029/shadowbox:latest for the Outline Server
- ken1029/watchtower:arm64 (for ARM64) or ken1029/watchtower:arm32 (for ARMv7)
- v2fly/v2fly-core:latest for v2ray