# 🚀 Xray VPN Server Automation Suite

A comprehensive Docker-based VPN server solution featuring automated installation and management of Xray-core with VLESS+Reality protocol, providing enterprise-level security with user-friendly administration.

## 🎯 Unified Management Script

**NEW**: All VPN functionality is now available through a single unified script: `vpn.sh`

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

# Make the unified script executable
chmod +x vpn.sh

# Run installation
sudo ./vpn.sh install
```

### Usage

The unified `vpn.sh` script provides all VPN management functionality:

```bash
# Show all available commands
./vpn.sh --help

# Server management
sudo ./vpn.sh install              # Install VPN server
sudo ./vpn.sh status               # Show server status
sudo ./vpn.sh restart              # Restart server
sudo ./vpn.sh uninstall            # Uninstall server

# User management
sudo ./vpn.sh users                # Interactive user menu
sudo ./vpn.sh user add john        # Add user 'john'
sudo ./vpn.sh user list            # List all users
sudo ./vpn.sh user show john       # Show connection details
sudo ./vpn.sh user delete john     # Delete user

# Client management
sudo ./vpn.sh client install       # Install VPN client
sudo ./vpn.sh client status        # Show client status
sudo ./vpn.sh client uninstall     # Uninstall client

# Monitoring
sudo ./vpn.sh stats                # Show traffic statistics
sudo ./vpn.sh logs                 # View server logs
sudo ./vpn.sh rotate-keys          # Rotate encryption keys
```

For backward compatibility, the original commands still work:
- `sudo v2ray-manage` → redirects to user management

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
12. **🛡️ Watchdog Management** - Monitor and manage container health service

### Maintenance
13. **🗑️ Uninstall Server** - Complete removal with cleanup

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

## 📁 Project Structure

### Modular Architecture (Version 2.0)

This project has been completely refactored into a modular architecture for improved maintainability, testability, and code reuse. The system is organized into libraries, feature modules, and installation modules.

```
vpn/
├── lib/                     # Core Libraries (Shared Utilities)
│   ├── common.sh           # Shared utilities and functions
│   ├── config.sh           # Configuration management
│   ├── docker.sh           # Docker operations and resource management
│   ├── network.sh          # Network utilities and port management
│   ├── crypto.sh           # Cryptographic functions (X25519, UUID, etc.)
│   └── ui.sh               # User interface components and menus
├── modules/                 # Feature Modules (Business Logic)
│   ├── install/            # Installation Modules
│   │   ├── prerequisites.sh # System checks and dependency installation
│   │   ├── docker_setup.sh  # Docker environment setup
│   │   ├── xray_config.sh   # Xray configuration generation
│   │   └── firewall.sh      # Firewall configuration
│   ├── users/              # User Management Modules
│   │   ├── add.sh          # User creation
│   │   ├── delete.sh       # User removal
│   │   ├── edit.sh         # User modification
│   │   ├── list.sh         # User listing
│   │   └── show.sh         # User information display
│   ├── server/             # Server Management Modules
│   │   ├── status.sh       # Health monitoring
│   │   ├── restart.sh      # Service control
│   │   ├── rotate_keys.sh  # Security management
│   │   └── uninstall.sh    # System cleanup
│   └── monitoring/         # Monitoring & Analytics Modules
│       ├── statistics.sh   # Traffic analysis
│       ├── logging.sh      # Log configuration
│       └── logs_viewer.sh  # Log analysis
├── test/                   # Comprehensive Test Suite
│   ├── test_libraries.sh   # Library testing
│   ├── test_user_modules.sh # User module testing
│   ├── test_server_modules.sh # Server module testing
│   ├── test_monitoring_modules.sh # Monitoring testing
│   └── test_install_modules.sh # Installation module testing
├── vpn.sh                  # Unified management script (NEW)
├── install_vpn.sh          # Main installation script (legacy, use vpn.sh install)
├── manage_users.sh         # User management interface (legacy, use vpn.sh users)
├── install_client.sh       # Client setup script (legacy, use vpn.sh client)
├── uninstall.sh           # Standalone uninstaller (legacy, use vpn.sh uninstall)
├── deploy.sh              # Deployment script (legacy, use vpn.sh deploy)
├── watchdog.sh            # Container monitoring service
├── vpn-watchdog.service   # Systemd service definition
├── LEGACY_SCRIPTS.md      # Migration guide for legacy scripts
├── CLAUDE.md              # Claude Code instructions
├── PLANNING.md            # Architecture planning documentation
├── TASK.md                # Project tasks and progress tracking
└── README.md              # This documentation
```

### Modular Benefits

#### Code Organization
- **Single Responsibility**: Each module focuses on one specific task
- **Reusability**: Functions can be shared across different scripts
- **Maintainability**: Easy to locate and modify specific functionality
- **Testability**: Individual modules can be tested in isolation

#### Architecture Improvements
- **Line Count Reduction**: 
  - install_vpn.sh: 1,403 → 407 lines (71% reduction)
  - manage_users.sh: 1,463 → 447 lines (69% reduction)
  - install_client.sh: 1,065 → 521 lines (51% reduction)
- **Code Duplication**: Reduced from ~15% to <2%
- **Function Exports**: All modules export functions for cross-module use
- **Error Handling**: Comprehensive debug logging and graceful error recovery

#### Development Workflow
```bash
# Run tests for specific modules
./test/test_libraries.sh
./test/test_install_modules.sh
./test/test_user_modules.sh

# Test all modules
find test/ -name "test_*.sh" -exec {} \;

# Syntax checking
shellcheck lib/*.sh modules/*/*.sh *.sh
```

#### Module Usage Example
```bash
# Source required libraries
source "lib/common.sh"
source "lib/docker.sh"

# Use functions from modules
source "modules/install/prerequisites.sh"
install_system_dependencies true

# All modules support debug mode
source "modules/users/add.sh"
add_user "username" true  # true enables debug logging
```

### Server File Structure
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
# Install or manage v2rayA client
sudo ./install_client.sh
```

Features:
- 🌐 Web-based UI at http://localhost:2017
- 🔧 Easy connection management
- 📊 Traffic statistics and monitoring
- 🚀 Automatic startup on system boot
- 🛡️ Built-in routing rules and proxy settings
- 📦 Docker-based deployment for easy updates
- 🔌 Proxy ports: SOCKS5 (20170), HTTP (20171), Mixed (20172)
- 🗑️ Complete uninstall option with full cleanup
- 🎯 Smart menu system that detects installation status

**Management**: After installation, use `sudo v2raya-client` for management options.

**Important**: After connecting to VPN server in v2rayA, configure your browser to use the proxy:
- SOCKS5 proxy: `127.0.0.1:20170`
- HTTP proxy: `127.0.0.1:20171`

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

#### Client Has No Internet After Connecting
This is expected behavior. v2rayA uses proxy mode, not VPN mode:
1. Configure your browser to use proxy:
   - Firefox: Settings → Network → Manual proxy → SOCKS5: `127.0.0.1:20170`
   - Chrome: Use Proxy SwitchyOmega extension or launch with `--proxy-server="socks5://127.0.0.1:20170"`
2. For system-wide proxy (Linux):
   ```bash
   export http_proxy="http://127.0.0.1:20171"
   export https_proxy="http://127.0.0.1:20171"
   ```

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

### Latest Update: Unified Management Script 🎉
- **Single Command Interface**: All functionality now available through `vpn.sh`
- **Simplified Usage**: Consistent command structure for all operations  
- **Backward Compatibility**: Legacy scripts remain functional during transition
- **Modular Architecture**: Fully leverages the modular system introduced in v2.0
- **Comprehensive Help**: Built-in help system with examples

### Stability and Reliability Improvements ⚡
- **Enhanced Container Stability**: Added comprehensive health checks for all Docker containers
- **Smart Restart Policy**: Changed from `always` to `unless-stopped` for better control
- **Resource Management**: Added CPU and memory limits to prevent system overload
- **VPN Watchdog Service**: 24/7 monitoring with automatic container recovery
- **Advanced Logging**: Implemented log rotation and centralized logging system

### Deployment and CI/CD 🚀
- **Automated Deployment**: Added `deploy.sh` script for CI/CD pipelines
- **GitHub Actions**: Ready-to-use CI/CD configuration for automated deployments
- **Backup & Restore**: Automated backup creation before updates
- **Multi-Environment**: Support for staging and production deployments
- **Auto-Discovery**: Smart path detection for flexible deployment locations

### Monitoring and Management 📊
- **Watchdog Dashboard**: New menu option for monitoring service health
- **Real-time Logs**: Live log monitoring and filtering capabilities
- **System Resources**: CPU, memory, and disk usage monitoring
- **Container Health**: Docker health check integration with restart logic
- **Service Management**: Start/stop/restart watchdog service through UI

### Previous Updates
- Fixed logs directory mounting issue in Docker
- Added automatic port preservation across restarts
- Improved SNI domain validation and testing
- Enhanced user management with better error handling
- Added comprehensive logging system with configurable levels
- Added client installation script with Web UI for Linux desktop/server users
- Unified client installation into single script with v2rayA web interface
- **Fixed client internet connectivity issue**: Changed network mode from host to bridge, added proxy ports configuration
- **Enhanced client stability**: Disabled transparent proxy mode, added proper capabilities for network management
- **Added client uninstall feature**: Complete removal of v2rayA client with cleanup of all components
- **Improved user experience**: Added intelligent main menu that detects installation status
- **Fixed Docker Compose warning**: Removed obsolete version attribute for compatibility with modern Docker

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