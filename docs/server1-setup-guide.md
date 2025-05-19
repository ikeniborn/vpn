# Server 1 Setup Guide - VLESS+Reality Tunnel Entry Point

## Overview

This guide provides step-by-step instructions for setting up Server 1 as the tunnel entry point in the VLESS+Reality tunnel architecture. Server 1 is the internet-facing server that will accept incoming connections from Server 2 and forward traffic to the internet.

## Prerequisites

- A server with a public IP address and direct internet access
- Ubuntu/Debian-based Linux distribution (recommended)
- Root or sudo privileges
- VLESS+Reality already installed on the server (via `setup-vless-reality-server.sh`)
- Basic understanding of networking concepts

## System Requirements

- **CPU**: 1+ cores
- **RAM**: 1GB+ recommended
- **Storage**: 10GB+ free space
- **Network**: Unrestricted outbound connections
- **Operating System**: Ubuntu 20.04+ or Debian 10+

## Installation Steps

### 1. Prepare the Server

Ensure your server is up-to-date and has the necessary packages installed:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget ufw iptables-persistent
```

### 2. Check for Existing VLESS+Reality Installation

Before proceeding, make sure VLESS+Reality is already installed on this server. The setup script will verify this requirement automatically.

### 3. Run the Setup Script

The `setup-vless-server1.sh` script configures Server 1 to accept tunneled connections from Server 2. You can run it with default settings or customize it with command-line options.

```bash
# Basic usage with auto-detection
sudo ./script/setup-vless-server1.sh

# Advanced usage with custom parameters
sudo ./script/setup-vless-server1.sh --v2ray-port 443 --server2-name "tunnel-server"
```

### 4. Available Options

The script accepts the following command-line options:

- `--hostname HOST`: Server hostname or IP (auto-detected if not specified)
- `--v2ray-port PORT`: Port for v2ray VLESS protocol (default: 443)
- `--server2-name NAME`: Name for the Server 2 account (default: server2)
- `--help`: Display help message

### 5. What the Script Does

The setup script performs the following actions:

1. **Validates Prerequisites**:
   - Checks if the script is running with root privileges
   - Verifies that VLESS+Reality is already installed

2. **Creates a Special User Account**:
   - Generates a dedicated UUID for Server 2
   - Adds a new user to the VLESS server using the `manage-vless-users.sh` script
   - Exports configuration details for use on Server 2

3. **Configures IP Forwarding**:
   - Enables IP forwarding on the system
   - Makes the configuration persistent across reboots

4. **Updates Firewall Rules**:
   - Configures NAT masquerading for traffic from Server 2
   - Sets up appropriate UFW or iptables rules depending on your configuration

### 6. Server 2 Connection Details

After running the script, you'll receive important connection details for Server 2:

```
============================================================
Server 2 Connection Details (Save these for Server 2 setup):
============================================================
Server 1 Address: [your server IP/hostname]
Port:            443
UUID:            [generated UUID]
Account Name:    server2
============================================================
```

**IMPORTANT**: Save these details as they will be required when setting up Server 2.

The script also saves these details to a file named `server2_config.txt` in the current directory.

## Verifying the Setup

### 1. Check IP Forwarding

Verify that IP forwarding is enabled:

```bash
cat /proc/sys/net/ipv4/ip_forward
```

The output should be `1`.

### 2. Check Firewall Rules

Verify that the masquerading rules have been added:

```bash
# If using UFW
sudo grep -A 10 "*nat" /etc/ufw/before.rules | grep MASQUERADE

# If using direct iptables
sudo iptables -t nat -L POSTROUTING -v
```

You should see a rule for masquerading traffic.

### 3. Run the Test Script

Use the included test script to verify that Server 1 is properly configured:

```bash
sudo ./script/test-tunnel-connection.sh --server-type server1
```

## Troubleshooting

### Common Issues

1. **Cannot Add Server 2 User**:
   - Make sure `manage-vless-users.sh` is in the current path or properly installed
   - Verify that VLESS+Reality is correctly installed and running

2. **IP Forwarding Not Working**:
   - Check if the system has multiple network interfaces
   - Verify that the correct internet-facing interface is being used for masquerading

3. **Firewall Blocking Connections**:
   - Check UFW status with `sudo ufw status`
   - Ensure port 443 (or your configured port) is open for incoming connections

### Logs and Diagnostics

- Check v2ray logs: `docker logs v2ray`
- Check system logs: `journalctl -xe`
- Check iptables rules: `sudo iptables -L -v -n -t nat`

## Security Considerations

- Server 1 is internet-facing and should be hardened appropriately
- Consider using SSH key authentication and disabling password login
- Keep your system and v2ray up to date
- Regularly monitor logs and traffic for unusual activity
- Consider implementing rate limiting and intrusion detection

## Next Steps

After successfully setting up Server 1, proceed to the [Server 2 Setup Guide](server2-setup-guide.md) to configure the second server that will route traffic through this server.

## Reference

For more details about the architecture, see [VLESS+Reality Tunnel Architecture](vless-reality-tunnel-architecture.md).