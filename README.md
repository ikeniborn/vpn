# VLESS-Reality VPN Solution

A comprehensive deployment solution for setting up a VPN server using the VLESS protocol with Reality encryption.

## Features

- **VLESS Protocol**: Lightweight and efficient VPN protocol
- **Reality Encryption**: Advanced security without certificates
- **Traffic Obfuscation**: Mimics legitimate TLS traffic to approved destinations
- **User Management**: Easy-to-use scripts for managing users
- **Security Hardening**: Built-in firewall and security checks
- **Docker-based**: Simple containerized deployment

## Quick Start

For a new server installation:

```bash
# Clone the repository
git clone https://github.com/username/vpn.git
cd vpn

# Make scripts executable
chmod +x script/*.sh

# Run the all-in-one setup script
sudo ./script/setup-vless-reality-server.sh
```

For advanced configuration options:

```bash
sudo ./script/setup-vless-reality-server.sh \
  --v2ray-port 443 \
  --dest-site www.cloudflare.com:443 \
  --fingerprint firefox
```

## Documentation

### Installation Guides

- [New Server Installation Guide](docs/vless-reality-new-server-guide.md): Complete guide for setting up VLESS-Reality on a new server
- [Implementation Guide](docs/implementation-guide.md): General implementation steps for VLESS-Reality
- [WebSocket+TLS vs Reality Comparison](docs/websocket-tls-vs-reality.md): In-depth technical comparison

### Technical Plans and Modifications

- [VLESS-Reality Implementation Plan](docs/outline-v2ray-reality-plan.md): Original implementation plan
- [Reality Install Script Modifications](docs/reality-install-script-modifications.md): Code changes for VLESS-Reality support

## Scripts

### Core Scripts

- [setup-vless-reality-server.sh](script/setup-vless-reality-server.sh): All-in-one setup script for new servers
- [outline-v2ray-reality-install.sh](script/outline-v2ray-reality-install.sh): Main installation script
- [firewall.sh](script/firewall.sh): Configures firewall with secure defaults

### User Management

- [manage-vless-users.sh](script/manage-vless-users.sh): Add, remove, list, and export users
- [generate-vless-reality-client.sh](script/generate-vless-reality-client.sh): Generate client configurations

### Security

- [security-checks-reality.sh](script/security-checks-reality.sh): Perform security audits on your server
- [security-checks.sh](script/security-checks.sh): Original security checks script

## User Management

### List Users

```bash
./script/manage-vless-users.sh --list
```

### Add User

```bash
./script/manage-vless-users.sh --add --name "user-phone"
```

### Remove User

```bash
./script/manage-vless-users.sh --remove --uuid "user-uuid"
```

### Export User Configuration

```bash
./script/manage-vless-users.sh --export --uuid "user-uuid"
```

## Security Verification

Run a comprehensive security check:

```bash
sudo ./script/security-checks-reality.sh
```

## Compatible Clients

- v2rayN (Windows)
- v2rayNG (Android)
- Qv2ray (Cross-platform)
- V2Box (iOS)
- FoXray (macOS)
- Shadowrocket (iOS)

## Support and Contributions

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.