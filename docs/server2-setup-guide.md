# Server 2 Setup Guide - VLESS+Reality Tunnel with Outline VPN

## Overview

This guide provides detailed instructions for setting up Server 2 in the VLESS+Reality tunnel architecture. Server 2 is configured to route traffic through Server 1 using a VLESS+Reality tunnel and hosts the Outline VPN server for client connections.

## Prerequisites

- A server with basic internet connectivity (must be able to reach Server 1)
- Server 1 already configured according to the [Server 1 Setup Guide](server1-setup-guide.md)
- Connection details from Server 1 setup (Server 1 address, port, UUID)
- Root or sudo privileges
- Ubuntu/Debian-based Linux distribution (recommended)

## System Requirements

- **CPU**: 2+ cores recommended for VPN service
- **RAM**: 2GB+ recommended
- **Storage**: 20GB+ free space (for Docker containers and logs)
- **Network**: Ability to connect to Server 1 and accept client connections
- **Operating System**: Ubuntu 20.04+ or Debian 10+

## Installation Steps

### 1. Prepare the Server

Update your system and install basic dependencies:

```bash
sudo apt update
sudo apt upgrade -y
```

### 2. Run the Setup Script

The `setup-vless-server2.sh` script configures Server 2 to route traffic through Server 1 and installs Outline VPN. You must provide the Server 1 connection details that were generated during Server 1 setup.

```bash
# Basic usage with required parameters
sudo ./script/setup-vless-server2.sh --server1-address 123.45.67.89 --server1-uuid abcd-1234-efgh-5678

# Advanced usage with additional options
sudo ./script/setup-vless-server2.sh \
  --server1-address 123.45.67.89 \
  --server1-uuid abcd-1234-efgh-5678 \
  --server1-port 443 \
  --server1-sni www.microsoft.com \
  --server1-fingerprint chrome \
  --server1-shortid abc123 \
  --server1-pubkey 8KXuPLVyNM8zoprSJ77UMiEe7UP7CDa9aHp0qZRwtQs \
  --outline-port 7777
```

### 3. Available Options

The script accepts the following command-line options:

**Required Options:**
- `--server1-address ADDR`: Server 1 hostname or IP address
- `--server1-uuid UUID`: Server 1 account UUID for tunneling

**Optional Options:**
- `--server1-port PORT`: Server 1 port (default: 443)
- `--server1-sni DOMAIN`: Server 1 SNI domain (default: www.microsoft.com)
- `--server1-fingerprint FP`: Server 1 TLS fingerprint (default: chrome)
- `--server1-shortid ID`: Server 1 Reality short ID (if required)
- `--server1-pubkey KEY`: Server 1 Reality public key
- `--outline-port PORT`: Port for Outline VPN (default: 7777)
- `--help`: Display help message

### 4. What the Script Does

The setup script performs the following actions:

1. **Validates Prerequisites**:
   - Checks if the script is running with root privileges
   - Validates required parameters

2. **Updates System and Installs Dependencies**:
   - Updates package repositories
   - Installs necessary packages including Docker

3. **Configures IP Forwarding**:
   - Enables IP forwarding on the system
   - Makes the configuration persistent across reboots

4. **Installs and Configures v2ray Client for Tunneling**:
   - Creates necessary directories
   - Configures v2ray to connect to Server 1 with VLESS+Reality
   - Sets up local SOCKS, HTTP, and transparent proxies

5. **Creates Systemd Service for Tunnel**:
   - Creates a persistent service for the tunnel
   - Ensures the tunnel starts on system boot

6. **Configures Routing Rules**:
   - Sets up iptables rules to route traffic through the tunnel
   - Creates a persistent service for routing rules

7. **Installs and Configures Outline VPN**:
   - Downloads and installs Outline VPN server
   - Configures Outline to route traffic through the tunnel
   - Sets up appropriate firewall rules

8. **Tests the Tunnel Connection**:
   - Verifies that traffic is routing through Server 1
   - Shows the IP address of traffic going through the tunnel

### 5. Verifying the Setup

After the script completes, you'll see confirmation messages and the management API URL:

```
=====================================================================
Server 2 setup completed successfully!
Outline VPN is installed and configured to route traffic through Server 1.
Outline Management API: https://192.168.1.2:41084/access-keys/
Outline VPN port: 7777
=====================================================================
IMPORTANT: Use the Outline Manager to configure access keys for your VPN users.
=====================================================================
```

### 6. Setting Up Outline Manager

1. Install the [Outline Manager](https://getoutline.org/get-started/#step-1) on your local computer
2. Connect to your server using the API URL provided at the end of the setup
3. Create access keys for your users
4. Share the access keys with your users

## Testing the Tunnel Connection

You can verify that the tunnel is working correctly using the test script:

```bash
sudo ./script/test-tunnel-connection.sh --server-type server2 --server1-address 123.45.67.89
```

The script will:
1. Verify Docker and v2ray container status
2. Test IP forwarding configuration
3. Check connectivity to Server 1
4. Verify tunnel proxy functionality
5. Check Outline VPN server status
6. Display system information and network connections

## Troubleshooting

### Common Issues

1. **Cannot Connect to Server 1**:
   - Verify that Server 1 address is correct
   - Check if Server 1 is reachable with `ping`
   - Ensure that Server 1's firewall allows connections on the configured port

2. **v2ray Client Not Working**:
   - Check Docker container logs: `docker logs v2ray-client`
   - Verify the UUID and other parameters are correct
   - Ensure Reality public key is correct if provided

3. **Outline VPN Not Working**:
   - Check Docker container logs: `docker logs outline-server`
   - Verify Outline is properly configured to use the tunnel
   - Check if the port is open: `ss -tulpn | grep 7777`

4. **Routing Issues**:
   - Check IP forwarding: `cat /proc/sys/net/ipv4/ip_forward`
   - Verify iptables rules: `iptables -t nat -L`
   - Check if the v2ray transparent proxy is running: `ss -tulpn | grep 1081`

For more detailed troubleshooting, refer to the [Tunnel Troubleshooting Guide](tunnel-troubleshooting.md).

## Using an Existing Outline Installation

If you already have Outline VPN installed and want to route it through the tunnel:

1. Set up the tunnel using `setup-vless-server2.sh` without installing Outline again
2. Use the `route-outline-through-tunnel.sh` script to configure your existing Outline installation:

```bash
sudo ./script/route-outline-through-tunnel.sh --outline-dir /opt/outline
```

## Security Considerations

- Server 2 hosts the VPN service and should be hardened appropriately
- Consider using SSH key authentication and disabling password login
- Regularly update and patch your system
- Monitor logs for unusual activity
- Implement rate limiting for VPN connections if needed

## Next Steps

1. Configure Outline VPN access keys using the Outline Manager
2. Test client connections
3. Set up regular backups and monitoring

For detailed instructions on installing and configuring Outline VPN, see the [Outline VPN Installation Guide](outline-vpn-installation.md).

## Reference

For more details about the architecture, see [VLESS+Reality Tunnel Architecture](vless-reality-tunnel-architecture.md).