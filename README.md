# 🚀 Xray VPN Server Automation Suite

A comprehensive Docker-based VPN server solution featuring automated installation and management of Xray-core with VLESS+Reality protocol, providing enterprise-level security with user-friendly administration.

## 📋 Features

### Core Capabilities
- **🔐 VLESS+Reality Protocol**: State-of-the-art anti-detection technology with TLS 1.3 masquerading
- **🐳 Docker Containerization**: Isolated, portable deployment using teddysun/xray image
- **🎯 Smart Configuration**: Automated port selection, SNI validation, and key generation
- **👥 Multi-User Support**: Individual user management with unique authentication
- **📊 Comprehensive Monitoring**: Traffic statistics, connection logs, and performance metrics
- **🔄 Zero-Downtime Updates**: Key rotation and configuration changes without service interruption

### Management Features
- **Interactive CLI**: Beautiful menu-driven interface with emoji support
- **QR Code Generation**: Instant client configuration via QR codes
- **Automatic Backups**: Configuration snapshots before critical operations
- **Resource Monitoring**: Docker stats, network usage, and user activity tracking
- **Advanced Logging**: Configurable log levels with user activity analysis

## 🚦 Quick Start

### Prerequisites
- Ubuntu/Debian Linux server
- Root or sudo access
- Docker and Docker Compose installed (auto-installed if missing)
- Open ports: SSH (22) and one VPN port (auto-selected or manual)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/vpn.git
cd vpn

# Make scripts executable
chmod +x install_vpn.sh manage_users.sh install_client.sh

# Run installation
sudo ./install_vpn.sh
```

### Usage

After installation, manage your VPN server using:

```bash
sudo v2ray-manage
```

Or directly:

```bash
sudo ./manage_users.sh
```

## 📚 Menu Options

### User Management
1. **📋 List Users** - Display all configured users with their UUIDs
2. **➕ Add User** - Create new user with unique credentials
3. **❌ Delete User** - Remove user and cleanup configurations
4. **✏️ Edit User** - Modify existing user settings
5. **👤 Show User Data** - Display connection details with QR code

### Server Control
6. **📊 Server Status** - System health and container status
7. **🔄 Restart Server** - Apply configuration changes
8. **🔐 Key Rotation** - Rotate Reality encryption keys

### Monitoring & Analytics
9. **📊 Usage Statistics** - Traffic analysis and performance metrics
10. **📝 Configure Logging** - Setup Xray logging levels
11. **📋 View User Logs** - Analyze connection logs and activity

### Maintenance
12. **🗑️ Uninstall Server** - Complete removal with cleanup

## 🔧 Configuration

### Installation Options

#### Port Selection
- **Random Port**: Automatically finds free port (10000-65000)
- **Manual Port**: Specify custom port with validation
- **Standard Port**: Use default 10443

#### SNI Domain Options
- addons.mozilla.org (Recommended)
- www.lovelive-anime.jp
- www.swift.org
- Custom domain with validation
- Automatic best domain selection

### File Structure
```
/opt/v2ray/
├── config/
│   ├── config.json          # Main Xray configuration
│   ├── private_key.txt      # Reality private key
│   ├── public_key.txt       # Reality public key
│   ├── short_id.txt         # Reality short ID
│   ├── port.txt             # Server port
│   ├── sni.txt              # SNI domain
│   └── protocol.txt         # Protocol type
├── users/
│   ├── <username>.json      # User configuration
│   ├── <username>.link      # Connection link
│   └── <username>.png       # QR code
├── logs/
│   ├── access.log           # Access logs
│   └── error.log            # Error logs
└── docker-compose.yml       # Container configuration
```

## 🔐 Security Features

- **X25519 Cryptography**: Military-grade key generation
- **XTLS Vision Flow**: Enhanced performance with minimal overhead
- **Unique Short IDs**: Per-user authentication tokens
- **UFW Firewall**: Automatic firewall configuration
- **Reality Protocol**: Advanced anti-detection with authentic TLS handshakes

## 📱 Client Setup

### Option 1: Web UI Client (Linux Desktop/Server)

For Linux desktop/server users, we provide a client installation script with web-based management interface:

```bash
# Install v2rayA client with Web UI
sudo ./install_client.sh
```

Features:
- 🌐 Web-based UI at http://localhost:2017
- 🔧 Easy connection management
- 📊 Traffic statistics and monitoring
- 🚀 Automatic startup on system boot
- 🛡️ Built-in routing rules and proxy settings
- 📦 Docker-based deployment for easy updates

### Option 2: Mobile Applications

#### Android
- **v2RayTun** - [Google Play](https://play.google.com/store/apps/details?id=com.v2raytun.android)

#### iOS
- **Shadowrocket** - [App Store](https://apps.apple.com/app/shadowrocket/id932747118)
- **v2RayTun** - [App Store](https://apps.apple.com/app/v2raytun/id6476628951)

## 🛠️ Troubleshooting

### Common Issues

#### Port Already in Use
The installer automatically detects occupied ports. If issues persist:
```bash
sudo netstat -tulnp | grep :YOUR_PORT
sudo ufw status
```

#### Container Won't Start
Check Docker logs:
```bash
docker logs xray
docker-compose logs -f
```

#### Connection Issues
1. Verify firewall rules: `sudo ufw status`
2. Check container status: `docker ps`
3. Review logs: `tail -f /opt/v2ray/logs/access.log`

### Maintenance Commands

```bash
# View container stats
docker stats xray

# Clean up Docker resources
docker system prune -f

# Check system resources
htop
df -h
free -h
```

## 🔄 Recent Updates

- Fixed logs directory mounting issue in Docker
- Added automatic port preservation across restarts
- Improved SNI domain validation and testing
- Enhanced user management with better error handling
- Added comprehensive logging system with configurable levels
- Added client installation script with Web UI for Linux desktop/server users
- Unified client installation into single script with v2rayA web interface

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

This tool is for educational and personal use only. Users are responsible for complying with local laws and regulations regarding VPN usage.

## 🙏 Acknowledgments

- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) - The core proxy software
- [teddysun/xray](https://hub.docker.com/r/teddysun/xray) - Docker image maintainer
- Community contributors and testers

---

**Note**: Always ensure your server is properly secured and regularly updated. Use strong passwords and keep your private keys safe.