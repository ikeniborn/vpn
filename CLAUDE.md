# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a multi-protocol VPN server implementation supporting both **Xray** (VLESS+Reality) and **Outline VPN** (Shadowsocks). The system consists of:

- `vpn.sh` - Unified management script with interactive menu
- Modular architecture in `lib/` and `modules/` directories
- Support for ARM architectures (ARM64/ARMv7) including Raspberry Pi

The VPN servers run in Docker containers, providing enterprise-level security with advanced features like automatic port selection, SNI quality monitoring, key rotation, traffic statistics, and automatic updates.

## Key Technologies

- **Xray-core**: Latest XTLS/Xray-core implementation (migrated from V2Ray)
- **Outline VPN**: Shadowsocks-based protocol with web management interface
- **VLESS+Reality Protocol**: State-of-the-art protocol with TLS 1.3 masquerading
- **XTLS Vision Flow**: Enhanced performance with minimal processing overhead
- **Docker**: Containerized deployment with automatic updates via Watchtower
- **X25519 Cryptography**: Military-grade key generation
- **ARM Support**: Full compatibility with ARM64 and ARMv7 architectures

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

**VPN Protocol Selection:**
1. **VLESS+Reality** (Recommended for maximum security)
   - Enhanced anti-detection technology
   - Port Selection: Random (10000-65000), manual, or standard (10443)
   - SNI Domain Options: Pre-validated domains or custom
   
2. **Outline VPN** (Shadowsocks-based)
   - Easy client setup and management
   - Web-based management interface
   - Automatic updates via Watchtower
   - ARM architecture support

### Main Menu Options

The unified VPN management interface (`sudo ./vpn.sh`) provides:

**Server Management:**
1. **📦 Install VPN Server** - Complete server installation with protocol selection
2. **📊 Server Status** - Real-time status, container health, and system metrics
3. **🔄 Restart Server** - Safe restart with configuration validation
4. **🗑️ Uninstall Server** - Complete removal with cleanup

**User Management:**
5. **👥 User Management** - Complete user lifecycle management
   - List Users - Display all configured users with connection status
   - Add User - Create new user with unique shortID and QR codes
   - Delete User - Remove user and cleanup configurations
   - Edit User - Modify user settings and regenerate credentials
   - Show User Data - Display connection details, QR codes, and links

**Advanced Operations:**
6. **🛡️ Watchdog Service** - Container monitoring and auto-restart service
7. **🔧 Fix Reality Issues** - Repair Reality key configuration problems
8. **✅ Validate Configuration** - Comprehensive configuration validation
9. **🔍 System Diagnostics** - Complete system health check and auto-fix
10. **🧹 Clean Up Unused Ports** - Remove old firewall rules for unused VPN ports

**Help & Information:**
11. **❓ Show Help** - Display usage information and commands
12. **ℹ️ Show Version** - Show script version and system information

### Advanced Features

#### System Diagnostics (New)
- **Comprehensive Health Checks**: System requirements, Docker status, VPN configuration
- **Network Connectivity Tests**: Internet access, DNS resolution, routing analysis
- **Port Accessibility Validation**: Firewall rules, listening processes, external access
- **Automatic Issue Detection**: Common VPN problems with suggested solutions
- **Network Configuration Fixes**: Automatic repair of masquerading rules and routing
- **Diagnostic Reports**: Detailed system analysis for troubleshooting

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

#### Network Configuration Management
- **Automatic VPN Routing Setup**: IP forwarding, masquerading rules, FORWARD policies
- **Firewall Integration**: UFW configuration with VPN port management
- **Network Issue Detection**: Missing NAT rules, incorrect policies, port conflicts
- **One-Click Network Fixes**: Automatic repair of common routing problems

### Docker Operations

**For Xray VPN:**
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

**For Outline VPN:**
```bash
# View container status
docker ps | grep -E "shadowbox|watchtower"

# View Outline logs
docker logs shadowbox

# View Watchtower logs
docker logs watchtower

# Access management configuration
cat /opt/outline/management/config.json

# View access file
cat /opt/outline/access.txt
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
├── vpn.sh                   # Unified management script (single entry point)
├── lib/                     # Core Libraries (Phase 1-2)
│   ├── common.sh           # Common functions and utilities
│   ├── config.sh           # Configuration management
│   ├── docker.sh           # Docker operations and resource management
│   ├── network.sh          # Network utilities and port management
│   ├── crypto.sh           # Cryptographic functions and key generation
│   ├── ui.sh               # User interface components
│   └── performance.sh      # Performance optimization library
├── modules/                 # Feature Modules (Phase 3-5)
│   ├── install/            # Installation Modules
│   │   ├── prerequisites.sh # System dependency installation
│   │   ├── docker_setup.sh  # Docker environment setup
│   │   ├── firewall.sh      # UFW firewall configuration
│   │   ├── outline_setup.sh # Outline VPN installation
│   │   └── xray_config.sh   # Xray configuration generation
│   ├── menu/               # Menu System Modules
│   │   ├── main_menu.sh    # Main interactive menu
│   │   ├── menu_loader.sh  # Menu module loader
│   │   ├── server_handlers.sh # Server operation handlers
│   │   ├── server_installation.sh # Installation workflow
│   │   └── user_menu.sh    # User management menu
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
│   ├── monitoring/         # Monitoring Modules
│   │   ├── statistics.sh   # Traffic statistics and vnstat integration
│   │   ├── logging.sh      # Xray logging configuration
│   │   └── logs_viewer.sh  # Log viewing and analysis
│   └── system/             # System Modules
│       └── watchdog.sh     # Container health monitoring
├── test/                   # Test Suite
│   ├── test_libraries.sh   # Core libraries testing
│   ├── test_user_modules.sh # User management testing
│   ├── test_server_modules.sh # Server management testing
│   ├── test_monitoring_modules.sh # Monitoring testing
│   ├── test_install_modules.sh # Installation testing
│   └── test_performance.sh # Performance optimization testing
├── config/                 # Configuration Templates
│   └── vpn-watchdog.service # Systemd service template
├── docs/                   # Documentation
│   ├── DEPLOYMENT.md       # Deployment guide (removed)
│   ├── DEVELOPER.md        # Developer documentation
│   └── OPTIMIZATION.md     # Performance optimization plan
├── CLAUDE.md               # Project documentation
├── PLANNING.md             # Architecture and refactoring plan
├── TASK.md                 # Task tracking and progress
└── README.md               # Project overview
```

## Server Configuration

The server configuration is stored in the following locations:

### Xray Server Directory Structure
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

### Outline Server Directory Structure
```
/opt/outline/
├── persisted-state/
│   ├── shadowbox-selfsigned.crt  # SSL certificate
│   ├── shadowbox-selfsigned.key  # SSL private key
│   └── shadowbox_server_config.json # Server configuration
├── management/
│   └── config.json          # Management API configuration
├── access.txt              # API access information
├── api_prefix.txt          # API secret prefix
└── api_port.txt            # API port number
```

## Architecture

**Common Features:**
- **Docker Containers**: All VPN servers run in Docker with host networking
- **UFW Firewall**: Automatically configured to allow only SSH and VPN ports
- **Comprehensive Monitoring**: Built-in statistics, logging, and user tracking
- **Automatic Updates**: Watchtower container for Outline, manual updates for Xray

**Xray-specific:**
- **Xray-core**: Latest XTLS/Xray-core implementation with VLESS+Reality
- **XTLS Vision Flow**: Enhanced performance with minimal encryption overhead
- **Reality Protocol**: Advanced anti-detection technology with TLS 1.3 masquerading
- **Unique Authentication**: Each user has a unique UUID and short ID
- **Advanced Security**: Automatic key rotation and domain validation

**Outline-specific:**
- **Shadowbox**: Official Outline server implementation
- **Shadowsocks Protocol**: ChaCha20-IETF-Poly1305 encryption
- **Web Management**: HTTPS API for server management
- **ARM Support**: Native support for ARM64 and ARMv7 architectures
- **Automatic Updates**: Watchtower monitors and updates containers

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

**For Xray VPN:**
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
```

**For Outline VPN:**
```bash
# Check containers
docker ps | grep -E "shadowbox|watchtower"

# View management configuration
cat /opt/outline/management/config.json

# Check Outline API
curl -k https://localhost:$(cat /opt/outline/api_port.txt)/$(cat /opt/outline/api_prefix.txt)/access-keys

# Restart Outline
docker restart shadowbox

# View firewall rules for Outline
sudo ufw status numbered | grep -E "9000|YOUR_ACCESS_KEY_PORT"
```

**Client-specific commands:**
```bash
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

## Performance Optimizations

The VPN system implements comprehensive performance optimizations based on OPTIMIZATION.md:

### Lazy Module Loading

Modules are loaded only when needed to reduce startup time:

```bash
# Module loading cache in vpn.sh
declare -A LOADED_MODULES

# Load module with lazy loading
load_module_lazy() {
    local module="$1"
    [ -z "${LOADED_MODULES[$module]}" ] && {
        source "$SCRIPT_DIR/modules/$module" || return 1
        LOADED_MODULES[$module]=1
    }
}
```

### Caching Strategy

- **Docker Operations**: 5-second TTL for container status caching
- **Configuration Data**: 30-second TTL for JSON config caching
- **Automatic Cleanup**: Caches cleared when exceeding size limits

### Performance Commands

```bash
# Run performance benchmarks
sudo ./vpn.sh benchmark

# Show debug information and loaded modules
sudo ./vpn.sh debug

# Test specific performance metrics
cd /path/to/vpn
./test/test_performance.sh
```

### Optimization Results

- **Startup Time**: < 2 seconds (from ~5 seconds)
- **Status Check**: < 0.5 seconds (from ~2 seconds)
- **Memory Usage**: < 50MB baseline (from ~100MB)
- **Concurrent Operations**: Parallel container health checks

### Best Practices

1. **Use Built-in Commands**: Prefer regex matching over external grep
2. **Batch Operations**: Read multiple files in single operation
3. **String Operations**: Use printf instead of concatenation
4. **Resource Monitoring**: Regular cleanup of caches and temporary data