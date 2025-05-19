# Outline VPN Installation and Configuration Guide

## Overview

This document provides detailed instructions for installing and configuring Outline VPN on Server 2 within the VLESS+Reality tunnel architecture. In this setup, all Outline VPN traffic will be routed through the VLESS+Reality tunnel to Server 1, providing an additional layer of security and potential circumvention capabilities.

## Prerequisites

- Server 2 configured according to the [Server 2 Setup Guide](server2-setup-guide.md)
- VLESS+Reality tunnel to Server 1 already established and working
- Docker and Docker Compose installed
- Root or sudo privileges
- Ports 7777/tcp (VPN) and 41084/tcp (management API) available

## System Requirements

- **CPU**: 2+ cores recommended for VPN service
- **RAM**: 2GB+ recommended
- **Storage**: 10GB+ free space (for Docker containers and logs)
- **Network**: Ability to accept client connections
- **Operating System**: Ubuntu 20.04+ or Debian 10+

## Installation Methods

There are two methods to install and configure Outline VPN for use with the tunnel:

1. **Automatic installation** using the `setup-vless-server2.sh` script (recommended)
2. **Manual installation** followed by tunnel integration using `route-outline-through-tunnel.sh`

## Automatic Installation (Recommended)

If you're setting up Server 2 from scratch, use the `setup-vless-server2.sh` script which automatically installs and configures Outline VPN to work with the tunnel.

```bash
sudo ./script/setup-vless-server2.sh --server1-address 123.45.67.89 --server1-uuid abcd-1234-efgh-5678
```

For more details on this approach, see the [Server 2 Setup Guide](server2-setup-guide.md).

## Manual Installation

If you prefer to install Outline VPN manually or need to integrate an existing installation with the tunnel, follow these steps:

### 1. Install Docker and Docker Compose

```bash
# Update system packages
sudo apt update
sudo apt upgrade -y

# Install Docker prerequisites
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker and Docker Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose
```

### 2. Create Directory for Outline

```bash
sudo mkdir -p /opt/outline
cd /opt/outline
```

### 3. Download and Install Outline Server

```bash
# Download the Outline server install script
sudo curl -sSL https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh > install_server.sh
sudo chmod +x install_server.sh

# Install Outline with API port and keys directory parameters
sudo ./install_server.sh --api-port=41084 --keys-port=7777
```

### 4. Configure Outline to Use the Tunnel

After installing Outline VPN, you need to configure it to route traffic through the VLESS+Reality tunnel. The easiest way to do this is to use the `route-outline-through-tunnel.sh` script:

```bash
sudo ./script/route-outline-through-tunnel.sh --outline-dir /opt/outline
```

This script will:
- Create a configuration file with proxy settings for the tunnel
- Update the Outline Docker Compose file to use these settings
- Configure routing rules to direct Outline traffic through the tunnel
- Restart Outline with the new configuration

### 5. Options for the Route-Outline Script

The script accepts the following command-line options:

- `--outline-dir DIR`: Directory where Outline is installed (default: /opt/outline)
- `--proxy HOST:PORT`: HTTP proxy address for the tunnel (default: 127.0.0.1:8080)
- `--outline-port PORT`: Port for Outline VPN (default: 7777)
- `--help`: Display help message

## Setting Up Outline Manager

After installing the Outline server, you need to set up the Outline Manager to create and manage access keys for your users:

### 1. Download Outline Manager

Download the [Outline Manager](https://getoutline.org/get-started/#step-1) for your operating system (Windows, macOS, or Linux).

### 2. Connect to Your Server

1. Launch the Outline Manager application
2. Click "Set up Outline anywhere"
3. Enter your server's management API URL:
   ```
   https://YOUR_SERVER_IP:41084/access-keys/
   ```
4. Accept the security certificate warning (self-signed certificate)

### 3. Complete the Server Setup

1. Set a name for your server
2. Optionally, set metrics sharing preferences
3. Click "Done"

### 4. Create Access Keys

1. In the Outline Manager, click "Add key"
2. Optionally, rename the key (e.g., "User 1")
3. Share the access key with your user via the "Share" button

## Client Configuration

Instruct your users to:

1. Download the [Outline Client](https://getoutline.org/get-started/#step-3) for their device
2. Add the access key you provided
3. Connect to the VPN

## Verifying the Setup

### 1. Check if Outline is Running

```bash
docker ps | grep outline
```

You should see the Outline server container running.

### 2. Check if the Port is Open

```bash
ss -tulpn | grep 7777
```

### 3. Check Routing Through the Tunnel

From a device connected to your Outline VPN:
1. Visit a website like [ifconfig.me](https://ifconfig.me) to check your IP
2. The IP should match Server 1's IP, not Server 2's IP

## Troubleshooting

### Common Issues

1. **Outline API Not Accessible**:
   - Check if the API is running: `curl -k https://localhost:41084/server`
   - Verify firewall rules allow access to port 41084
   - Check the Outline server container logs: `docker logs outline-server`

2. **Clients Cannot Connect**:
   - Verify port 7777 is open: `ss -tulpn | grep 7777`
   - Check firewall rules: `sudo ufw status` or `sudo iptables -L`
   - Check Outline server logs for connection attempts

3. **Traffic Not Routing Through Tunnel**:
   - Check that v2ray client is running: `docker ps | grep v2ray-client`
   - Test the proxy connection: `curl -x http://127.0.0.1:8080 ifconfig.me`
   - Check iptables rules: `sudo iptables -t nat -L`

4. **Performance Issues**:
   - Check Server 1's bandwidth and CPU usage
   - Look for bottlenecks in the tunnel connection
   - Consider upgrading Server 1 if it's handling multiple Server 2 instances

### Logs and Diagnostics

- Outline server logs: `docker logs outline-server`
- v2ray client logs: `docker logs v2ray-client`
- Routing rules: `iptables -t nat -L V2RAY`
- Active connections: `ss -tanp | grep 7777`

## Advanced Configuration

### Customizing Outline VPN Port

If you want to use a different port for Outline VPN:

1. Edit `/opt/outline/docker-compose.yml`
2. Change the port mapping for the `watchtower` service
3. Update firewall rules to allow the new port
4. Restart Outline: `cd /opt/outline && docker-compose down && docker-compose up -d`

### Multiple Outline Access Keys

Create multiple access keys through the Outline Manager to support different users or devices. Each key:
- Can be individually named and tracked
- Can be revoked independently
- Has its own encryption

### Data Limit Settings

From the Outline Manager, you can set data transfer limits for each access key:
1. Click on the vertical dots menu next to the key
2. Select "Set data limit"
3. Enter the desired limit in GB
4. Click "Done"

### Rate Limiting (Optional)

For better performance distribution, you might want to implement rate limiting:

```bash
# Example: Limit each connection to 5Mbps
sudo iptables -A FORWARD -p tcp --dport 7777 -m hashlimit \
  --hashlimit-above 5mb/s \
  --hashlimit-mode srcip \
  --hashlimit-name outline_limit \
  -j DROP
```

## Security Considerations

- Keep Server 2 and Outline VPN regularly updated
- Use strong, unique keys for each user
- Monitor access logs regularly for unusual activity
- Consider implementing fail2ban to prevent brute force attacks
- Disable SSH password authentication and use key-based authentication

## Backup and Recovery

### Backing Up Outline Configuration

To backup your Outline VPN configuration:

```bash
# Create backup directory
mkdir -p ~/outline-backup

# Backup configuration files
cp -r /opt/outline/access-keys ~/outline-backup/
cp /opt/outline/docker-compose.yml ~/outline-backup/
cp /opt/outline/outline-tunnel.conf ~/outline-backup/
```

### Restoring from Backup

To restore your Outline VPN configuration:

```bash
# Restore configuration files
cp -r ~/outline-backup/access-keys /opt/outline/
cp ~/outline-backup/docker-compose.yml /opt/outline/
cp ~/outline-backup/outline-tunnel.conf /opt/outline/

# Restart Outline
cd /opt/outline && docker-compose down && docker-compose up -d
```

## References

- [Official Outline Documentation](https://getoutline.org/docs/)
- [VLESS+Reality Tunnel Architecture](vless-reality-tunnel-architecture.md)
- [Server 2 Setup Guide](server2-setup-guide.md)
- [Tunnel Troubleshooting Guide](tunnel-troubleshooting.md)