# Quick Start Guide

Get up and running with VPN Manager in minutes!

## Prerequisites

Before starting, ensure you have:

- [VPN Manager installed](installation.md)
- Docker running on your system
- Administrative privileges (for server installation)

> **Note**: If you installed VPN Manager in a virtual environment, make sure it's activated:
> ```bash
> # If using manual virtual environment
> source ~/.vpn-manager-venv/bin/activate
> 
> # If using pipx, commands are available globally
> # No activation needed
> ```

## Step 1: Verify Installation

First, verify that VPN Manager is working:

```bash
vpn --version
vpn --help
```

Run system diagnostics:

```bash
vpn doctor
```

This will check:
- Python version compatibility
- Docker availability
- Network connectivity
- Required permissions

## Step 2: Initialize Configuration

Create the initial configuration:

```bash
vpn config init
```

This creates:
- Configuration directory
- Default settings file
- Database initialization
- Log directory

## Step 3: Create Your First User

Create a user for VPN access:

```bash
vpn users create alice --protocol vless --email alice@example.com
```

You can also create users interactively:

```bash
vpn users create alice
# Follow the prompts to configure the user
```

Verify the user was created:

```bash
vpn users list
```

## Step 4: Install a VPN Server

Install your first VPN server:

### VLESS Server (Recommended)

```bash
vpn server install --protocol vless --port 8443 --name main-server
```

### Shadowsocks Server

```bash
vpn server install --protocol shadowsocks --port 8443 --name shadowsocks-server
```

### WireGuard Server

```bash
vpn server install --protocol wireguard --port 51820 --name wireguard-server
```

## Step 5: Start the Server

Start your VPN server:

```bash
vpn server start main-server
```

Check server status:

```bash
vpn server list
vpn server status main-server
```

## Step 6: Generate Connection Info

Get connection details for your user:

```bash
vpn users show alice --connection-info
```

This will display:
- Connection string (for VPN clients)
- QR code (for mobile devices)
- Configuration file content

## Step 7: Test the Connection

### Using the Built-in Proxy

Start a local proxy for testing:

```bash
vpn proxy start --type http --port 8888
```

Test the proxy:

```bash
vpn proxy test --type http --port 8888 --url https://httpbin.org/ip
```

### Using VPN Client

Copy the connection string from Step 6 and configure your VPN client:

=== "v2rayN (Windows)"
    1. Open v2rayN
    2. Click "Add server" → "Import from clipboard"
    3. Paste the connection string
    4. Connect

=== "v2rayNG (Android)"
    1. Open v2rayNG
    2. Tap "+" → "Import config from clipboard"
    3. Paste the connection string
    4. Connect

=== "ShadowRocket (iOS)"
    1. Open ShadowRocket
    2. Tap "+" → "Add Config"
    3. Paste the connection string
    4. Connect

## Step 8: Monitor Your Setup

### Command Line Monitoring

```bash
# Server status
vpn server status main-server --detailed

# Server logs
vpn server logs main-server --follow

# User statistics
vpn users stats

# System monitoring
vpn monitor stats
```

### Terminal UI

Launch the interactive terminal interface:

```bash
vpn tui
```

The TUI provides:
- Real-time dashboard
- User management
- Server monitoring
- System statistics

## Common Tasks

### Add More Users

```bash
# Create users with different protocols
vpn users create bob --protocol shadowsocks
vpn users create carol --protocol wireguard

# Batch create users
vpn users create-batch users.json
```

### Manage Multiple Servers

```bash
# Install multiple servers
vpn server install --protocol vless --port 8443 --name vless-main
vpn server install --protocol shadowsocks --port 8444 --name ss-backup
vpn server install --protocol wireguard --port 51820 --name wg-mobile

# Start all servers
vpn server start --all

# List all servers
vpn server list --format table
```

### Configure Proxy Services

```bash
# HTTP proxy with authentication
vpn proxy start --type http --port 8888 --auth

# SOCKS5 proxy without authentication
vpn proxy start --type socks5 --port 1080 --no-auth

# List running proxies
vpn proxy list
```

### Export/Import Configuration

```bash
# Export users
vpn users export users-backup.json

# Export configuration
vpn config export config-backup.toml

# Import on another system
vpn users import users-backup.json
vpn config import config-backup.toml
```

## Configuration Examples

### Basic VLESS Setup

```bash
# Create configuration for VLESS server
vpn config set server.protocol vless
vpn config set server.port 8443
vpn config set server.domain vpn.example.com
vpn config set server.reality.dest www.google.com:443
```

### Multi-User Shadowsocks

```bash
# Install Shadowsocks server with multiple users
vpn server install --protocol shadowsocks --port 8443 --name ss-multi

# Create multiple users
for user in user{1..10}; do
    vpn users create $user --protocol shadowsocks
done
```

### Production WireGuard

```bash
# Install WireGuard with production settings
vpn server install \
    --protocol wireguard \
    --port 51820 \
    --name wg-prod \
    --network 10.0.0.0/24 \
    --dns 1.1.1.1,8.8.8.8
```

## Troubleshooting

### Server Won't Start

```bash
# Check Docker status
docker ps

# Check logs
vpn server logs main-server

# Restart Docker
sudo systemctl restart docker
vpn server restart main-server
```

### Connection Issues

```bash
# Test server connectivity
vpn server test main-server

# Check firewall
sudo ufw status
sudo ufw allow 8443

# Verify port is listening
netstat -tlnp | grep 8443
```

### Permission Errors

```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Or run with elevated privileges
sudo vpn server install --protocol vless --port 8443
```

## Security Best Practices

1. **Use Strong Domains**: For VLESS+Reality, use popular domains for fronting
2. **Regular Updates**: Keep VPN Manager and Docker updated
3. **Monitor Access**: Regularly check user access logs
4. **Backup Configs**: Export configurations regularly
5. **Firewall Rules**: Only open necessary ports

```bash
# Set up basic firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 8443/tcp
sudo ufw allow 8443/udp
```

## Next Steps

Now that you have a basic setup running:

1. **[Learn CLI Commands](../user-guide/cli-commands.md)** - Master the command-line interface
2. **[Explore TUI](../user-guide/tui-interface.md)** - Use the terminal user interface
3. **[User Management](../user-guide/user-management.md)** - Advanced user operations
4. **[Server Management](../user-guide/server-management.md)** - Advanced server configuration
5. **[Admin Guide](../admin-guide/installation.md)** - Production deployment
6. **[Migration Guide](../migration/from-rust.md)** - Migrate from Rust version

## Getting Help

If you encounter issues:

- Run `vpn doctor` for diagnostics
- Check `vpn logs --level debug` for detailed logs
- Visit our [Troubleshooting Guide](../admin-guide/troubleshooting.md)
- Join our [Discord Community](https://discord.gg/vpn-manager)
- Report issues on [GitHub](https://github.com/vpn-manager/vpn-python/issues)

## Example: Complete Setup

Here's a complete example setting up a production-ready VPN server:

```bash
# 1. System check
vpn doctor

# 2. Initialize
vpn config init

# 3. Install VLESS server
vpn server install \
    --protocol vless \
    --port 8443 \
    --name production \
    --domain vpn.example.com

# 4. Create users
vpn users create admin --protocol vless --email admin@example.com
vpn users create user1 --protocol vless --email user1@example.com
vpn users create user2 --protocol vless --email user2@example.com

# 5. Start server
vpn server start production

# 6. Setup proxy
vpn proxy start --type http --port 8888 --auth

# 7. Monitor
vpn tui

# 8. Get connection info
vpn users show admin --connection-info
```

You now have a fully functional VPN server with multiple users and proxy services!