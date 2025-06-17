# 🚀 VPN Management System

A modern, modular VPN server solution featuring automated installation and management of Xray-core with VLESS+Reality protocol, providing enterprise-level security through a unified command-line interface.

## ✨ Key Features

- **🎯 Single Script Interface**: All functionality through `vpn.sh`
- **📦 Modular Architecture**: Clean, maintainable code structure
- **🔐 VLESS+Reality Protocol**: State-of-the-art anti-detection technology
- **🐳 Docker-Based**: Containerized deployment for consistency
- **👥 Multi-User Support**: Individual user management with unique authentication
- **📊 Comprehensive Monitoring**: Traffic statistics, logs, and health checks
- **🛡️ Auto-Recovery**: Built-in watchdog service for container monitoring
- **🎨 Interactive Menu**: User-friendly interface with numbered options

## 🚀 Quick Start

### Prerequisites

- Ubuntu/Debian Linux server
- Root or sudo access
- Port 22 (SSH) and one VPN port open

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/vpn.git
cd vpn

# Make the script executable
chmod +x vpn.sh

# Launch interactive menu
sudo ./vpn.sh

# Or install directly
sudo ./vpn.sh install
```

## 📖 Usage

### Interactive Mode (Recommended)

```bash
sudo ./vpn.sh
```

This launches a user-friendly menu with all available options.

### Command Line Mode

```bash
# Server Management
sudo ./vpn.sh install              # Install VPN server
sudo ./vpn.sh status               # Show server status
sudo ./vpn.sh restart              # Restart server
sudo ./vpn.sh uninstall            # Uninstall server

# User Management
sudo ./vpn.sh users                # Interactive user menu
sudo ./vpn.sh user add john        # Add user 'john'
sudo ./vpn.sh user list            # List all users
sudo ./vpn.sh user show john       # Show connection details
sudo ./vpn.sh user delete john     # Delete user

# Monitoring
sudo ./vpn.sh stats                # Show traffic statistics
sudo ./vpn.sh logs                 # View server logs
sudo ./vpn.sh rotate-keys          # Rotate encryption keys

# Watchdog Service
sudo ./vpn.sh watchdog install     # Install watchdog
sudo ./vpn.sh watchdog start       # Start monitoring
sudo ./vpn.sh watchdog status      # Check status
```

## 🏗️ Architecture

### Project Structure

```
vpn/
├── vpn.sh                  # Main executable script
├── lib/                    # Core libraries
│   ├── common.sh          # Shared utilities
│   ├── config.sh          # Configuration management
│   ├── docker.sh          # Docker operations
│   ├── network.sh         # Network utilities
│   ├── crypto.sh          # Cryptographic functions
│   └── ui.sh              # User interface components
├── modules/               # Feature modules
│   ├── install/           # Installation modules
│   ├── users/             # User management
│   ├── server/            # Server management
│   ├── monitoring/        # Monitoring & analytics
│   └── system/            # System utilities (watchdog)
├── config/                # Configuration templates
├── test/                  # Test suite
└── docs/                  # Documentation
```

### Key Technologies

- **Xray-core**: Latest VLESS+Reality implementation
- **Docker**: Container orchestration
- **XTLS Vision**: Enhanced performance protocol
- **X25519**: Military-grade encryption

## 🔧 Configuration

### Server Installation Options

- **Port Selection**: Random (10000-65000), manual, or standard (10443)
- **SNI Domains**: Pre-validated domains or custom
- **Protocol**: VLESS+Reality (recommended) or VLESS Basic

### Client Setup

#### Desktop/Server (Linux)
```bash
sudo ./vpn.sh client install
```
Access web UI at http://localhost:2017

#### Mobile Applications
- **Android**: v2RayTun (Google Play)
- **iOS**: Shadowrocket, v2RayTun (App Store)

## 🛡️ Security Features

- **Reality Protocol**: Advanced TLS masquerading
- **Unique Authentication**: Per-user UUID and short ID
- **Automatic Key Rotation**: Zero-downtime security updates
- **UFW Integration**: Automatic firewall configuration
- **Container Isolation**: Docker security boundaries

## 🔍 Troubleshooting

### Common Issues

**Container Won't Start**
```bash
sudo ./vpn.sh logs
docker logs xray
```

**Port Conflicts**
```bash
sudo netstat -tulnp | grep :YOUR_PORT
```

**Connection Issues**
1. Check firewall: `sudo ufw status`
2. Verify container: `docker ps`
3. Review logs: `sudo ./vpn.sh logs`

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License.

## ⚠️ Disclaimer

This tool is for educational and personal use only. Users are responsible for complying with local laws and regulations.

---

**Version**: 3.0 | **Architecture**: Modular | **Status**: Production Ready