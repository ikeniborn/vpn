# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a Docker-based **Xray VPN server** implementation using the **VLESS+Reality** protocol. The system consists of:

- `install_vpn.sh` - Server installation and configuration script with smart features
- `manage_users.sh` - Advanced user management utility with comprehensive features
- `install_client.sh` - Client installation script with v2rayA Web UI for Linux desktop/server

The VPN server runs in a Docker container using Xray-core, providing enterprise-level security with advanced features like automatic port selection, SNI quality monitoring, key rotation, and traffic statistics.

## Key Technologies

- **Xray-core**: Latest XTLS/Xray-core implementation (migrated from V2Ray)
- **VLESS+Reality Protocol**: State-of-the-art protocol with TLS 1.3 masquerading
- **XTLS Vision Flow**: Enhanced performance with minimal processing overhead
- **Docker**: Containerized deployment with teddysun/xray image
- **X25519 Cryptography**: Military-grade key generation

## Commands

### Unified Management Script

All VPN functionality is now available through a single script:

```bash
# Launch interactive menu
sudo ./vpn.sh

# Or use specific commands
sudo ./vpn.sh install      # Install VPN server
sudo ./vpn.sh status       # Check server status
sudo ./vpn.sh users        # Manage users
```

The installation script provides smart configuration options:

**Port Selection:**
- Random free port (10000-65000) - Recommended
- Manual port specification with validation
- Standard port (10443)

**SNI Domain Options:**
- addons.mozilla.org (Recommended)
- www.lovelive-anime.jp
- www.swift.org
- Custom domain with validation
- Automatic best domain selection

**Protocol Selection:**
- VLESS+Reality (Enhanced security - Recommended)
- VLESS Basic (Standard protocol)

### User Management

User management is available through the unified script:

```bash
sudo ./vpn.sh users        # Interactive menu
sudo ./vpn.sh user add john    # Add user directly
sudo ./vpn.sh user list        # List all users
```

This provides a comprehensive menu-driven interface for:

1. **List Users** - Display all configured users
2. **Add User** - Create new user with unique shortID
3. **Delete User** - Remove user and cleanup configs
4. **Edit User** - Modify user settings
5. **Show User Data** - Display connection details + QR code
6. **Server Status** - System and container status
7. **Restart Server** - Apply configuration changes
8. **🔄 Key Rotation** - Rotate Reality encryption keys
9. **📊 Usage Statistics** - Traffic and performance analytics
10. **🔧 Configure Logging** - Setup Xray logging with multiple levels
11. **📋 View User Logs** - Analyze connection logs and user activity
12. **Uninstall Server** - Complete removal with cleanup

### Advanced Features

#### Key Rotation
- Automatic backup of current configuration
- Generation of new X25519 keypairs
- Updates all user configurations
- Regenerates QR codes and connection links
- Zero-downtime key updates

#### Traffic Statistics
- Docker container resource usage
- Network interface statistics with vnstat integration
- Active connection monitoring
- User activity tracking with detailed logs
- Performance recommendations
- Automatic vnstat installation and configuration

#### Advanced Logging System
- **Configurable Log Levels**: none, error, warning, info, debug
- **Separate Log Files**: access.log and error.log
- **Real-time Monitoring**: Live log streaming and filtering
- **User Activity Analysis**: Per-user connection statistics
- **Log Search & Filter**: Find specific user activities
- **Connection Statistics**: Detailed connection metrics per user

### Docker Operations

To manually manage the Docker container:

```bash
# Navigate to working directory
cd /opt/v2ray

# Stop the VPN server
docker-compose down

# Start the VPN server
docker-compose up -d

# Restart the VPN server
docker-compose restart

# View container status
docker-compose ps

# View logs
docker-compose logs -f

# Real-time container stats
docker stats xray
```

### Monitoring Commands

```bash
# View recent logs
docker logs --tail 50 xray

# Network connections
sudo netstat -tulnp | grep :YOUR_PORT

# Access logs
tail -f /opt/v2ray/logs/access.log
tail -f /opt/v2ray/logs/error.log

# Network traffic statistics (if vnstat is installed)
vnstat -i eth0
```

## Project Structure

The VPN project follows a modular architecture with the following structure:

### Repository Structure
```
/home/ikeniborn/Documents/Project/vpn/
├── lib/                     # Core Libraries (Phase 1-2)
│   ├── common.sh           # Common functions and utilities
│   ├── config.sh           # Configuration management
│   ├── docker.sh           # Docker operations and resource management
│   ├── network.sh          # Network utilities and port management
│   ├── crypto.sh           # Cryptographic functions and key generation
│   └── ui.sh               # User interface components
├── modules/                 # Feature Modules (Phase 3-5)
│   ├── users/              # User Management Modules
│   │   ├── add.sh          # User creation and validation
│   │   ├── delete.sh       # User removal and cleanup
│   │   ├── edit.sh         # User modification and updates
│   │   ├── list.sh         # User listing and display
│   │   └── show.sh         # User information and QR codes
│   ├── server/             # Server Management Modules
│   │   ├── status.sh       # Server status and health checks
│   │   ├── restart.sh      # Server restart and validation
│   │   ├── rotate_keys.sh  # Reality key rotation and backup
│   │   └── uninstall.sh    # Complete server removal
│   └── monitoring/         # Monitoring Modules
│       ├── statistics.sh   # Traffic statistics and vnstat integration
│       ├── logging.sh      # Xray logging configuration
│       └── logs_viewer.sh  # Log viewing and analysis
├── test/                   # Test Suite
│   ├── test_libraries.sh   # Core libraries testing
│   ├── test_user_modules.sh # User management testing
│   ├── test_server_modules.sh # Server management testing
│   └── test_monitoring_modules.sh # Monitoring testing
├── install_vpn.sh          # Main server installation script
├── manage_users.sh         # Main user management script
├── install_client.sh       # Client installation script
├── CLAUDE.md               # Project documentation
├── PLANNING.md             # Architecture and refactoring plan
├── TASK.md                 # Task tracking and progress
└── README.md               # Project overview
```

## Server Configuration

The server configuration is stored in the following locations:

### Server Directory Structure
```
/opt/v2ray/
├── config/
│   ├── config.json          # Main Xray configuration
│   ├── private_key.txt      # Reality private key
│   ├── public_key.txt       # Reality public key
│   ├── short_id.txt         # Reality short ID
│   ├── sni.txt             # SNI domain
│   └── protocol.txt        # Protocol type
├── users/
│   ├── user1.json          # User configuration
│   ├── user1.link          # Connection link
│   └── user1.png           # QR code
├── logs/
│   ├── access.log          # Access logs
│   └── error.log           # Error logs
└── docker-compose.yml      # Container configuration
```

## Architecture

- **Xray-core**: Latest XTLS/Xray-core implementation with VLESS+Reality
- **XTLS Vision Flow**: Enhanced performance with minimal encryption overhead
- **Reality Protocol**: Advanced anti-detection technology with TLS 1.3 masquerading
- **Docker Container**: Runs the teddysun/xray image with host networking
- **Unique Authentication**: Each user has a unique UUID and short ID
- **Advanced Security**: Automatic key rotation and domain validation
- **Comprehensive Monitoring**: Built-in statistics, logging, and user tracking
- **UFW Firewall**: Automatically configured to allow only SSH and the VPN port

## Troubleshooting

### Testing Framework

The project includes a comprehensive testing framework located in the `test/` directory:

```bash
# Run all tests
cd /path/to/vpn/project
./test/test_libraries.sh        # Test core libraries
./test/test_user_modules.sh     # Test user management modules
./test/test_server_modules.sh   # Test server management modules
./test/test_monitoring_modules.sh # Test monitoring modules

# Run individual module tests
bash test/test_libraries.sh
bash test/test_user_modules.sh
bash test/test_server_modules.sh
bash test/test_monitoring_modules.sh
```

Each test suite includes:
- Module loading and syntax validation
- Function export verification
- Mock environment testing
- Cross-module integration testing
- Error handling validation
- Configuration validation
- File operations testing

### Lint and Type Check Commands
The project uses shell scripts, so standard linting can be done with:
```bash
# Check shell scripts syntax
bash -n install_vpn.sh
bash -n manage_users.sh
bash -n install_client.sh

# Check all modules
for module in lib/*.sh modules/*/*.sh; do bash -n "$module"; done

# Check Docker configuration
docker-compose config

# Optional: Use shellcheck for advanced linting
shellcheck install_vpn.sh manage_users.sh install_client.sh
shellcheck lib/*.sh modules/*/*.sh
```

### Client Installation

To install the VPN client with Web UI on Linux desktop/server:

```bash
sudo ./install_client.sh
```

The client provides:
- **v2rayA Web Interface**: Access at http://localhost:2017
- **Automatic System Startup**: Runs as a system service
- **Docker Containerization**: Easy updates and maintenance
- **SOCKS5/HTTP Proxy**: Ports 20170 (SOCKS5), 20171 (HTTP), 20172 (Mixed)
- **Connection Management**: Easy import of VLESS links via web UI
- **Traffic Statistics**: Monitor usage and performance
- **Bridge Network Mode**: Stable proxy operation without routing conflicts
- **Manual Proxy Configuration**: Requires browser/app proxy settings

### Common Operations
```bash
# Check container status
docker ps
docker logs xray

# Verify port accessibility
sudo ufw status
sudo netstat -tulnp | grep :YOUR_PORT

# Check system resources
htop
df -h
free -h

# Optimize Docker
docker system prune -f

# Client-specific commands
docker logs v2raya  # Check client logs
sudo systemctl status v2raya  # Check client service status

# Configure system proxy (optional)
export http_proxy="http://127.0.0.1:20171"
export https_proxy="http://127.0.0.1:20171"
export socks_proxy="socks5://127.0.0.1:20170"
```

### Client Configuration Notes

**Important**: v2rayA operates in proxy mode, not transparent VPN mode. After connecting to a server:

1. **Browser Configuration**:
   - Firefox: Settings → Network → Manual proxy → SOCKS5: `127.0.0.1:20170`
   - Chrome: Use Proxy SwitchyOmega extension or `--proxy-server="socks5://127.0.0.1:20170"`

2. **System Proxy** (Linux):
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export http_proxy="http://127.0.0.1:20171"
   export https_proxy="http://127.0.0.1:20171"
   ```

3. **Application-specific**:
   - Many applications support SOCKS5/HTTP proxy settings
   - Configure each app to use `127.0.0.1:20170` (SOCKS5) or `127.0.0.1:20171` (HTTP)