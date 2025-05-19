# VLESS-Reality New Server Installation Guide

This document provides comprehensive instructions for installing and configuring VLESS-Reality on a new server, including firewall configuration and security settings.

## Prerequisites

- A fresh Linux server (Ubuntu/Debian recommended)
- Root or sudo access
- Basic command line knowledge
- Open ports (primarily 443/TCP and UDP)

## 1. Preparation

### 1.1 System Update

First, ensure your system is up-to-date:

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

### 1.2 Install Dependencies

Install required dependencies:

```bash
sudo apt-get install -y curl wget jq socat qrencode ufw
```

### 1.3 Install Docker

If Docker is not already installed:

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
```

## 2. Firewall Configuration

### 2.1 Configure Basic Firewall

Run the firewall configuration script:

```bash
# Download the firewall script
wget -O firewall.sh https://raw.githubusercontent.com/username/vpn/main/script/firewall.sh

# Make it executable
chmod +x firewall.sh

# Run with default settings (v2ray port 443, with port knocking for SSH)
sudo ./firewall.sh

# Or customize with options:
# sudo ./firewall.sh --v2ray-port 12345 --disable-port-knocking
```

This script:
- Configures UFW with secure defaults
- Sets up port knocking for SSH (optional)
- Opens required ports for v2ray VLESS
- Configures IP forwarding
- Prevents common network attacks
- Ensures Docker compatibility

### 2.2 Verify Firewall Configuration

```bash
sudo ufw status verbose
```

## 3. VLESS-Reality Installation

### 3.1 Download Installation Script

```bash
wget -O outline-v2ray-reality-install.sh https://raw.githubusercontent.com/username/vpn/main/script/outline-v2ray-reality-install.sh
chmod +x outline-v2ray-reality-install.sh
```

### 3.2 Run Installation

Basic installation with default settings:

```bash
sudo ./outline-v2ray-reality-install.sh
```

Advanced installation with custom parameters:

```bash
sudo ./outline-v2ray-reality-install.sh \
  --hostname your-server-ip \
  --v2ray-port 443 \
  --dest-site www.microsoft.com:443 \
  --fingerprint chrome
```

Parameters explained:
- `--hostname`: Server IP or domain (auto-detected if not specified)
- `--v2ray-port`: Port for VLESS connections (default: 443)
- `--dest-site`: Website to mimic for traffic obfuscation (default: www.microsoft.com:443)
- `--fingerprint`: TLS fingerprint to simulate (default: chrome)

The installation:
- Generates Reality keypair (X25519) for authentication
- Configures v2ray with VLESS and Reality protocol
- Sets up destination site mimicking
- Creates Docker containers for the service

### 3.3 Verify Installation

Check that containers are running:

```bash
docker ps
```

Verify v2ray is listening on the configured port:

```bash
ss -tuln | grep <configured-port>
```

## 4. User Management

### 4.1 Download User Management Script

```bash
wget -O manage-vless-users.sh https://raw.githubusercontent.com/username/vpn/main/script/manage-vless-users.sh
chmod +x manage-vless-users.sh
```

### 4.2 Manage Users

List existing users:

```bash
./manage-vless-users.sh --list
```

Add a new user:

```bash
./manage-vless-users.sh --add --name "user1-phone"
```

Remove a user:

```bash
./manage-vless-users.sh --remove --uuid "user-uuid-here"
```

Export user configuration:

```bash
./manage-vless-users.sh --export --uuid "user-uuid-here"
```

## 5. Client Configuration

### 5.1 Download Client Generation Script

```bash
wget -O generate-vless-reality-client.sh https://raw.githubusercontent.com/username/vpn/main/script/generate-vless-reality-client.sh
chmod +x generate-vless-reality-client.sh
```

### 5.2 Generate Client Configuration

```bash
./generate-vless-reality-client.sh --name "client-device"
```

This will:
- Generate a unique UUID for the client
- Add the client to v2ray config
- Display connection details and QR code

### 5.3 Compatible Clients

- v2rayN (Windows)
- v2rayNG (Android)
- Qv2ray (Cross-platform)
- V2Box (iOS)
- FoXray (macOS)

## 6. Security Verification

Run the security check script to verify your installation:

```bash
wget -O security-checks.sh https://raw.githubusercontent.com/username/vpn/main/script/security-checks.sh
chmod +x security-checks.sh
sudo ./security-checks.sh
```

This will:
- Perform comprehensive security audits
- Check for misconfigurations
- Verify Docker security settings
- Validate VLESS-Reality configurations
- Generate a security report

## 7. Troubleshooting

### 7.1 Common Issues

**Cannot connect to server:**
- Verify firewall allows the configured port
- Check if the v2ray container is running
- Ensure client configuration matches server settings

**Docker container won't start:**
- Check Docker logs: `docker logs v2ray`
- Verify config.json syntax: `jq . /opt/v2ray/config.json`
- Check for port conflicts: `ss -tuln`

**Permission issues:**
- Run the permission fixer: `./outline-v2ray-reality-install.sh --fix-permissions`

**Client connection issues:**
- Try a different TLS fingerprint
- Ensure the destination site is accessible from client location
- Check public/private key match

## 8. Maintenance

### 8.1 Backup Configuration

Periodically backup your configuration:

```bash
sudo cp -r /opt/v2ray /opt/v2ray.backup-$(date +%Y%m%d)
sudo cp -r /opt/outline /opt/outline.backup-$(date +%Y%m%d)
```

### 8.2 Monitor Logs

View v2ray logs:

```bash
docker logs v2ray
```

### 8.3 System Updates

Keep your system updated:

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

## 9. Advanced Configuration

### 9.1 Destination Site Selection

For better censorship resistance, consider these destination sites:
- microsoft.com:443 (default, good reputation)
- cloudflare.com:443 (highly available globally)
- amazon.com:443 (common in most countries)
- akamai.net:443 (CDN provider)

Choose sites that:
- Have high reputation
- Exhibit stable behavior
- Have good global connectivity
- Are unlikely to be blocked in your target region

### 9.2 TLS Fingerprints

Available fingerprint options:
- `chrome`: Chrome browser (best compatibility)
- `firefox`: Firefox browser
- `safari`: Safari browser
- `ios`: iOS devices
- `android`: Android devices
- `edge`: Microsoft Edge browser
- `360`: 360 Secure Browser
- `qq`: QQ Browser
- `random`: Randomize fingerprint

### 9.3 Reality Settings

You can modify Reality settings in `/opt/v2ray/config.json`:
- Change destination sites
- Update shortIDs
- Adjust fingerprints

After any changes, restart the v2ray container:

```bash
docker restart v2ray
```

## 10. Final Notes

- VLESS-Reality does not require traditional SSL certificates
- The Reality protocol uses X25519 keypairs for security
- Traffic is hidden by mimicking real websites (using dest parameter)
- TLS fingerprinting makes detection even more difficult
- Regular security audits are recommended using the security-checks.sh script