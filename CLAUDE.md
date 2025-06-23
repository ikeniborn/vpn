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

### Development & Testing

```bash
# Run all tests
cd /path/to/vpn/project
./test/run_all_tests.sh

# Run individual test suites
./test/test_libraries.sh        # Test core libraries
./test/test_user_modules.sh     # Test user management modules
./test/test_server_modules.sh   # Test server management modules
./test/test_monitoring_modules.sh # Test monitoring modules
./test/test_install_modules.sh  # Test installation modules
./test/test_performance.sh      # Test performance optimizations

# Syntax validation
bash -n vpn.sh
for module in lib/*.sh modules/*/*.sh; do bash -n "$module"; done

# Optional: Advanced linting with shellcheck
shellcheck vpn.sh lib/*.sh modules/*/*.sh

# Validate Docker configuration
cd /opt/v2ray && docker-compose config
```

### Unified Management Script

All VPN functionality is available through a single script:

```bash
# Launch interactive menu
sudo ./vpn.sh

# Or use specific commands
sudo ./vpn.sh install      # Install VPN server
sudo ./vpn.sh status       # Check server status
sudo ./vpn.sh users        # Manage users
sudo ./vpn.sh restart      # Restart server
sudo ./vpn.sh uninstall    # Uninstall server
sudo ./vpn.sh debug        # Show debug info & loaded modules
sudo ./vpn.sh benchmark    # Run performance benchmarks
```

### Docker Operations

**For Xray VPN:**
```bash
# Navigate to working directory
cd /opt/v2ray

# Container management
docker-compose down
docker-compose up -d
docker-compose restart
docker-compose ps
docker-compose logs -f
docker stats xray

# View logs
docker logs --tail 50 xray
tail -f /opt/v2ray/logs/access.log
tail -f /opt/v2ray/logs/error.log
```

**For Outline VPN:**
```bash
# View container status
docker ps | grep -E "shadowbox|watchtower"

# View logs
docker logs shadowbox
docker logs watchtower

# Access management configuration
cat /opt/outline/management/config.json
cat /opt/outline/access.txt
```

## Architecture

### Repository Structure
```
vpn/
├── vpn.sh                   # Unified management script (single entry point)
├── lib/                     # Core Libraries
│   ├── common.sh           # Common functions and utilities
│   ├── config.sh           # Configuration management
│   ├── docker.sh           # Docker operations
│   ├── network.sh          # Network utilities
│   ├── crypto.sh           # Cryptographic functions
│   ├── ui.sh               # User interface components
│   └── performance.sh      # Performance optimization
├── modules/                 # Feature Modules
│   ├── install/            # Installation modules
│   ├── menu/               # Menu system
│   ├── users/              # User management
│   ├── server/             # Server management
│   ├── monitoring/         # Monitoring & analytics
│   └── system/             # System utilities
├── test/                   # Test suite
└── config/                 # Configuration templates
```

### Server Directory Structure

**Xray Server:**
```
/opt/v2ray/
├── config/
│   ├── config.json          # Main Xray configuration
│   ├── private_key.txt      # Reality private key
│   ├── public_key.txt       # Reality public key
│   └── sni.txt             # SNI domain
├── users/
│   ├── user1.json          # User configuration
│   ├── user1.link          # Connection link
│   └── user1.png           # QR code
├── logs/
│   ├── access.log          # Access logs
│   └── error.log           # Error logs
└── docker-compose.yml      # Container configuration
```

**Outline Server:**
```
/opt/outline/
├── persisted-state/
│   └── shadowbox_server_config.json
├── management/
│   └── config.json
├── access.txt
└── api_port.txt
```

## Module System

The project uses a modular architecture with lazy loading for optimal performance:

- **Core Libraries** (`lib/`): Essential utilities loaded on demand
- **Feature Modules** (`modules/`): Specialized functionality loaded when needed
- **Lazy Loading**: Modules are cached and loaded only once per session
- **Performance Optimization**: < 2 second startup time, < 50MB memory usage

Key modules include:
- `modules/install/`: Installation workflows for different VPN protocols
- `modules/users/`: Complete user lifecycle management
- `modules/server/`: Server operations (restart, status, uninstall)
- `modules/monitoring/`: Statistics, logging, and health checks
- `modules/system/`: System utilities like watchdog and diagnostics

## Development Workflow

1. **Before Changes**: Run tests to ensure clean state
   ```bash
   ./test/run_all_tests.sh
   ```

2. **Make Changes**: Follow modular architecture patterns

3. **Validate Syntax**: Check modified files
   ```bash
   bash -n path/to/modified/file.sh
   ```

4. **Run Relevant Tests**: Test affected modules
   ```bash
   ./test/test_libraries.sh     # If modified lib/
   ./test/test_user_modules.sh  # If modified user modules
   ```

5. **Full Test Suite**: Before committing
   ```bash
   ./test/run_all_tests.sh
   ```

6. **Performance Check**: Ensure no regressions
   ```bash
   ./test/test_performance.sh
   sudo ./vpn.sh benchmark
   ```

## Key Features & Capabilities

### System Diagnostics
- Comprehensive health checks and automatic issue detection
- Network configuration validation and auto-repair
- Port accessibility testing and firewall rule management
- Detailed diagnostic reports for troubleshooting

### User Management
- Multi-user support with unique UUID and short ID per user
- QR code generation for easy mobile setup
- Connection link generation for all platforms
- User activity tracking and statistics

### Performance Optimization
- Lazy module loading reduces startup time to < 2 seconds
- Docker operation caching with 5-second TTL
- Configuration caching with 30-second TTL
- Parallel processing for container health checks

### Security Features
- Reality protocol with TLS 1.3 masquerading
- Automatic key rotation with zero downtime
- UFW firewall integration
- Container isolation with Docker security boundaries

### Monitoring & Analytics
- Real-time container resource monitoring
- Network traffic statistics with vnstat integration
- Configurable logging levels (none, error, warning, info, debug)
- User activity analysis and connection tracking