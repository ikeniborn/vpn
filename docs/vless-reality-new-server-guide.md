# VLESS-Reality New Server Guide

This guide walks you through setting up a new server with VLESS-Reality protocol for secure and undetectable VPN connectivity.

## Prerequisites

- A VPS/server with a public IP address
- Root access or sudo privileges
- Basic Linux command-line knowledge

## Features of VLESS-Reality

- **No Certificates Required**: Unlike traditional TLS setups, Reality protocol doesn't need SSL certificates
- **Advanced Fingerprinting Evasion**: Mimics legitimate TLS traffic to common sites
- **Improved Performance**: Direct TCP connections with efficient flow control
- **Resistance to Active Probing**: Emulates real browser TLS fingerprints and behaviors

## Quick Installation

For a standard installation with default settings:

```bash
# Clone this repository
git clone https://github.com/yourusername/vpn.git
cd vpn

# Make scripts executable
chmod +x script/*.sh

# Run the setup script with defaults
sudo ./script/setup-vless-reality-server.sh
```

## Advanced Installation

You can customize your installation with these options:

```bash
sudo ./script/setup-vless-reality-server.sh \
  --v2ray-port 443 \
  --dest-site www.cloudflare.com:443 \
  --fingerprint firefox
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--hostname` | Server hostname/IP (auto-detected if not specified) | Auto-detected |
| `--v2ray-port` | Port for VLESS protocol | 443 |
| `--dest-site` | Destination site to mimic | www.microsoft.com:443 |
| `--fingerprint` | TLS fingerprint to simulate | chrome |
| `--no-port-knocking` | Disable port knocking for SSH | Enabled by default |
| `--no-firewall` | Skip firewall configuration | Enabled by default |

## Post-Installation

After installation completes, the script will display:

1. Default user UUID
2. Server details
3. Connection parameters

Save this information securely. You can export a complete client configuration with:

```bash
./script/manage-vless-users.sh --export --uuid YOUR_UUID_HERE
```

## Managing Users

### List All Users

```bash
./script/manage-vless-users.sh --list
```

### Add a New User

```bash
./script/manage-vless-users.sh --add --name "user-phone"
```

### Remove a User

```bash
./script/manage-vless-users.sh --remove --uuid "user-uuid"
```

### Export User Configuration

This will generate both a URI for client import and a QR code (if qrencode is installed):

```bash
./script/manage-vless-users.sh --export --uuid "user-uuid"
```

## Client Setup

### Compatible Clients

- v2rayN (Windows)
- v2rayNG (Android)
- Qv2ray (Cross-platform)
- V2Box (iOS)
- FoXray (macOS)
- Shadowrocket (iOS)

### Client Configuration

Use the exported URI from the `--export` command to configure your client. The URI contains all necessary parameters:

```
vless://UUID@server:port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=server.com&fp=fingerprint&pbk=publicKey&sid=shortId#alias
```

## Security Verification

Run security checks on your server to verify proper configuration:

```bash
sudo ./script/security-checks-reality.sh
```

## Troubleshooting

### Connection Issues

1. Verify firewall allows traffic on your configured port
2. Check Docker container is running: `docker ps | grep v2ray`
3. Verify client configuration matches server settings
4. Try changing the fingerprint type if connections fail

### Configuration Problems

If you make manual changes to the configuration:

1. Backup the current config: `cp /opt/v2ray/config.json /opt/v2ray/config.json.bak`
2. Edit the config: `nano /opt/v2ray/config.json`
3. Restart the container: `docker restart v2ray`

## Maintenance

### Updating V2Ray

```bash
docker pull v2fly/v2fly-core:latest
docker restart v2ray
```

### Backup

Backup your v2ray directory regularly:

```bash
tar -czvf v2ray-backup.tar.gz /opt/v2ray