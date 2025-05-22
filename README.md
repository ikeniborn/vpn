# Universal VPN Server: Xray & Outline

## 📋 Overview

This project provides a comprehensive VPN solution with **dual VPN support**: **Xray-core (VLESS+Reality)** for advanced circumvention and **Outline VPN (Shadowsocks)** for easy management. Built with Docker for seamless deployment, it offers enterprise-level security with intelligent port selection, optimized domain validation, key rotation, and comprehensive traffic analytics.

### 🔀 **Choose Your VPN Solution**

**🔐 Xray VPN (VLESS+Reality)** - *Advanced Circumvention*
- State-of-the-art protocol with TLS 1.3 masquerading
- Perfect for bypassing sophisticated censorship
- Advanced anti-detection technology
- Command-line management interface

**🎯 Outline VPN (Shadowsocks)** - *Simplified Management*  
- User-friendly Outline Manager GUI application
- Easy client distribution and management
- Cross-platform compatibility
- Ideal for team/organization deployments

## ✨ Key Features

### 🔀 **Dual VPN Support**
- **Universal Installation**: Single script supports both Xray and Outline VPN
- **VPN Type Selection**: Choose your preferred VPN solution during installation
- **Optimized Port Generation**: Intelligent port allocation with conflict avoidance
- **Unified Management**: Consistent configuration and monitoring across both platforms

### 🔒 **Advanced Security (Xray)**
- **VLESS+Reality Protocol**: State-of-the-art protocol with TLS 1.3 masquerading
- **XTLS Vision Flow**: Enhanced performance with minimal processing overhead
- **Automatic Key Rotation**: Built-in security key rotation functionality
- **Unique Short IDs**: Each user gets a unique identification for better security

### 🎯 **Simplified Management (Outline)**
- **GUI-based Management**: User-friendly Outline Manager application
- **Multi-architecture Support**: Works on x86-64, ARM64, and ARMv7 systems
- **Automatic Updates**: Built-in Watchtower for container updates
- **Team Collaboration**: Easy access key sharing and management

### 🚀 **Smart Installation**
- **Improved SNI Validation**: Enhanced domain checking with faster timeouts
- **Intelligent Port Selection**: Optimized random port assignment with conflict detection
- **One-click Setup**: Fully automated installation process for both VPN types
- **Docker-based**: Containerized deployment for better isolation

### 📊 **Monitoring & Statistics**
- **Traffic Analytics**: Comprehensive usage statistics with vnstat integration
- **Connection Tracking**: Real-time connection monitoring with detailed logs
- **Performance Metrics**: Docker container and system resource usage
- **User Activity**: Individual user connection history and per-user analytics
- **Advanced Logging**: Configurable Xray logging with multiple levels
- **Log Analysis**: Built-in log viewer with filtering and search capabilities

### 👥 **User Management**
- **Multi-user Support**: Add unlimited users with unique configurations
- **QR Code Generation**: Automatic QR codes for mobile device setup
- **Bulk Operations**: Easy user management with batch operations
- **Configuration Export**: Individual user configuration files

## 🔧 Technical Specifications

### **Supported VPN Solutions**

**🔐 Xray VPN Protocols:**
- **VLESS+Reality** (Recommended): Enhanced security with TLS 1.3 masquerading
- **VLESS Basic**: Standard VLESS protocol for basic scenarios

**🎯 Outline VPN Protocols:**
- **Shadowsocks**: Industry-standard protocol with AEAD encryption
- **Multi-platform Support**: Native clients for all major platforms

### **Core Technologies**

**Xray VPN Stack:**
- **Xray-core**: Latest XTLS/Xray-core implementation
- **Reality Protocol**: Advanced anti-detection technology  
- **X25519 Cryptography**: Military-grade key generation
- **Docker**: teddysun/xray container image

**Outline VPN Stack:**
- **Shadowbox**: Official Outline server implementation
- **Watchtower**: Automatic container updates
- **TLS Certificates**: Self-signed certificates for API security
- **Docker**: quay.io/outline/shadowbox container image

## 📦 Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 10+, CentOS 8+)
- **Privileges**: Root access required
- **Resources**: Minimum 512MB RAM, 1GB disk space
- **Network**: Internet connectivity and open firewall port

**Auto-installed Dependencies:**
- Docker & Docker Compose
- UFW Firewall  
- OpenSSL, dnsutils, uuid-runtime
- qrencode (for QR code generation)

## 🚀 Quick Installation

### 1. Download Installation Script
```bash
wget -O install_vpn.sh https://raw.githubusercontent.com/your-repo/install_vpn.sh
chmod +x install_vpn.sh
```

### 2. Run Universal Installation
```bash
sudo ./install_vpn.sh
```

### 3. Choose Your VPN Type

**VPN Selection Menu:**
```
1. Xray VPN (VLESS+Reality) - рекомендуется для обхода блокировок
2. Outline VPN (Shadowsocks) - простота управления через приложение
```

## 🔐 Xray VPN Configuration

### **Port Selection:**
- **Option 1**: Random free port (10000-65000) - Recommended
- **Option 2**: Manual port specification with validation
- **Option 3**: Standard port (10443)

### **SNI Domain Options:**
- **Option 1**: addons.mozilla.org (Recommended)
- **Option 2**: www.lovelive-anime.jp
- **Option 3**: www.swift.org
- **Option 4**: Custom domain with enhanced validation
- **Option 5**: Automatic best domain selection
- **Option 6**: Skip domain validation (fast installation)

### **Protocol Selection:**
- **VLESS+Reality**: Enhanced security (Recommended)
- **VLESS Basic**: Standard protocol

## 🎯 Outline VPN Configuration

### **Hostname/IP Setup:**
- **Auto-detection**: Uses your public IP automatically
- **Custom hostname**: Specify your own domain or IP

### **Port Configuration:**
- **API Port**: For Outline Manager (8000-9999 range)
  - Random generation or manual specification
- **Access Keys Port**: For client connections (10000-15999 range)
  - Random generation or manual specification
  - Automatically avoids conflicts with API port

### **Architecture Support:**
- **x86-64**: Standard servers and VPS
- **ARM64**: ARM-based servers and Raspberry Pi 4
- **ARMv7**: Older ARM devices and Raspberry Pi 3

## 🛠️ User Management

## 🔐 Xray VPN Management

### Command Line Interface
```bash
sudo v2ray-manage
```

### 📋 Available Operations

| Option | Function | Description |
|--------|----------|-------------|
| 1 | List Users | Display all configured users |
| 2 | Add User | Create new user with unique shortID |
| 3 | Delete User | Remove user and cleanup configs |
| 4 | Edit User | Modify user settings |
| 5 | Show User Data | Display connection details + QR code |
| 6 | Server Status | System and container status |
| 7 | Restart Server | Apply configuration changes |
| 8 | **🔄 Key Rotation** | Rotate Reality encryption keys |
| 9 | **📊 Usage Statistics** | Traffic and performance analytics |
| 10 | **🔧 Configure Logging** | Setup Xray logging with multiple levels |
| 11 | **📋 View User Logs** | Analyze connection logs and user activity |
| 12 | Uninstall Server | Complete removal with cleanup |

## 🎯 Outline VPN Management

### Outline Manager Application

1. **Download Outline Manager:**
   - **Windows/macOS/Linux**: [getoutline.org](https://getoutline.org/)
   - Available for all major desktop platforms

2. **Server Setup:**
   - Copy the server configuration JSON from installation output
   - Paste into Outline Manager "Add Server" dialog
   - Server will be automatically configured and connected

3. **Access Key Management:**
   - **Create Keys**: Click "Add Key" in Outline Manager
   - **Share Keys**: Generate shareable links or QR codes
   - **Rename Keys**: Assign meaningful names to users
   - **Delete Keys**: Remove access for specific users
   - **Monitor Usage**: View data usage per key

### Server Configuration Location
```bash
# Outline server files
/opt/outline/
├── access.txt              # Server access configuration
├── persisted-state/        # Shadowbox state directory
└── backup/                 # UFW backup files
```

### 🔄 Advanced Features

#### **Key Rotation**
- Automatic backup of current configuration
- Generation of new X25519 keypairs
- Updates all user configurations
- Regenerates QR codes and connection links
- Zero-downtime key updates

#### **Traffic Statistics**
- Docker container resource usage
- Network interface statistics with vnstat integration
- Active connection monitoring
- User activity tracking with detailed logs
- Performance recommendations
- Automatic vnstat installation and configuration

#### **Advanced Logging**
- **Configurable Log Levels**: none, error, warning, info, debug
- **Separate Log Files**: access.log and error.log
- **Real-time Monitoring**: Live log streaming and filtering
- **User Activity Analysis**: Per-user connection statistics
- **Log Search & Filter**: Find specific user activities
- **Connection Statistics**: Detailed connection metrics per user

## 📱 Client Setup

## 🔐 Xray VPN Clients

### **Recommended Clients**

| Platform | Client | Download |
|----------|--------|----------|
| **Android** | v2RayTun | [Google Play](https://play.google.com/store/apps/details?id=com.v2raytun.android) |
| **iOS** | Shadowrocket | [App Store](https://apps.apple.com/app/shadowrocket/id932747118) |
| **iOS** | v2RayTun | [App Store](https://apps.apple.com/app/v2raytun/id6476628951) |

### **Connection Methods**

#### **Method 1: QR Code (Recommended)**
1. Open your V2Ray client
2. Scan QR code from terminal or `/opt/v2ray/users/USERNAME.png`
3. Save and connect

#### **Method 2: Import Link**
1. Copy link from terminal or `/opt/v2ray/users/USERNAME.link`
2. Import in client from clipboard
3. Save and connect

#### **Method 3: Manual Configuration**

**Basic Settings:**
- **Address**: Your server IP
- **Port**: Your configured port
- **UUID**: User UUID
- **Protocol**: VLESS
- **Encryption**: none
- **Flow**: xtls-rprx-vision

**Reality Settings (VLESS+Reality only):**
- **Security**: reality
- **SNI**: Your SNI domain
- **Fingerprint**: chrome
- **Public Key**: From user configuration
- **Short ID**: Unique per user

## 🎯 Outline VPN Clients

### **Official Outline Clients**

| Platform | Client | Download |
|----------|--------|----------|
| **Android** | Outline | [Google Play](https://play.google.com/store/apps/details?id=org.outline.android.client) |
| **iOS** | Outline | [App Store](https://apps.apple.com/app/outline-app/id1356177741) |
| **Windows** | Outline | [getoutline.org](https://getoutline.org/get-started/#step-3) |
| **macOS** | Outline | [getoutline.org](https://getoutline.org/get-started/#step-3) |
| **Linux** | Outline | [getoutline.org](https://getoutline.org/get-started/#step-3) |
| **ChromeOS** | Outline | [Chrome Web Store](https://chrome.google.com/webstore/detail/outline/npeedaltgbjfenbhbijllbenamckbghl) |

### **Connection Methods**

#### **Method 1: Access Key URL (Recommended)**
1. Open Outline client
2. Tap "Add Server" or "+"
3. Paste the access key URL from Outline Manager
4. Connect automatically

#### **Method 2: QR Code**
1. Generate QR code in Outline Manager
2. Scan with Outline client
3. Server added automatically

#### **Method 3: Manual Import**
1. Export access key from Outline Manager
2. Share via email, messaging apps, or file
3. Import in Outline client

## 📊 Monitoring & Analytics

### **Built-in Statistics**
- **Container Metrics**: CPU, Memory, Network I/O
- **Connection Stats**: Active connections, bandwidth usage
- **User Analytics**: Connection history, traffic patterns per user
- **System Health**: Uptime, resource utilization
- **Network Traffic**: vnstat integration for detailed bandwidth statistics
- **Connection Tracking**: Real-time monitoring with filtering capabilities

### **Comprehensive Logging System**
- **Access Logs**: `/opt/v2ray/logs/access.log` - All connection attempts and user activity
- **Error Logs**: `/opt/v2ray/logs/error.log` - System errors and debugging information
- **Container Logs**: `docker logs xray` - Docker container output
- **Log Management**: Built-in log viewer with search and filtering options
- **User Tracking**: Individual user activity analysis and statistics

### **Performance Monitoring**
```bash
# Real-time container stats
docker stats xray

# View recent logs
docker logs --tail 50 xray

# Network connections
sudo netstat -tulnp | grep :YOUR_PORT

# Access management interface for detailed monitoring
sudo v2ray-manage
# Select option 9 for statistics
# Select option 11 for log analysis

# View specific log files
tail -f /opt/v2ray/logs/access.log
tail -f /opt/v2ray/logs/error.log

# Network traffic statistics (if vnstat is installed)
vnstat -i eth0
```

## 🔧 Advanced Configuration

### **Directory Structure**

**Xray VPN Files:**
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

**Outline VPN Files:**
```
/opt/outline/
├── access.txt              # Server access configuration
├── persisted-state/        # Shadowbox persistent data
│   ├── shadowbox-selfsigned.crt  # TLS certificate
│   ├── shadowbox-selfsigned.key  # TLS private key
│   └── shadowbox_server_config.json  # Server settings
└── backup/
    └── ufw_rules_backup.txt # Firewall backup
```

### **Manual Docker Operations**

**Xray VPN:**
```bash
# Navigate to Xray directory
cd /opt/v2ray

# Start services
docker-compose up -d

# Stop services
docker-compose down

# Restart services
docker-compose restart

# View logs
docker-compose logs -f

# Check status
docker-compose ps
```

**Outline VPN:**
```bash
# Check Outline containers
docker ps | grep -E "(shadowbox|watchtower)"

# View Outline logs
docker logs shadowbox
docker logs watchtower

# Restart Outline services
docker restart shadowbox
docker restart watchtower

# Stop Outline services
docker stop shadowbox watchtower

# Start Outline services
docker start shadowbox watchtower
```

## 🔐 Security Best Practices

### **Server Security**
- ✅ Automatic UFW firewall configuration
- ✅ Non-standard port usage with randomization
- ✅ TLS 1.3 masquerading with Reality protocol
- ✅ Regular key rotation capabilities
- ✅ Minimal logging for privacy

### **Client Security**
- ✅ Unique UUIDs per user
- ✅ Individual short IDs for each client
- ✅ XTLS Vision flow for performance
- ✅ Encrypted configuration storage

### **Operational Security**
- ✅ Automated backup before key rotation
- ✅ Configuration validation before deployment
- ✅ Secure key generation using X25519
- ✅ Domain validation for SNI masquerading

## 🚀 Performance Optimization

### **XTLS Vision Benefits**
- **Reduced CPU Usage**: Minimal encryption overhead
- **Better Performance**: Direct connection mode
- **Lower Latency**: Optimized data flow
- **Enhanced Compatibility**: Works with all clients

### **Network Optimization**
- **Host Networking**: Direct network access for containers
- **TCP BBR**: Modern congestion control (if available)
- **Port Randomization**: Avoid common port blocking
- **Domain Selection**: Optimal SNI domain choice

## ❓ Troubleshooting

### **Common Issues**

#### **Connection Failed**
```bash
# Check container status
docker ps
docker logs xray

# Verify port accessibility
sudo ufw status
sudo netstat -tulnp | grep :YOUR_PORT
```

#### **Key Rotation Issues**
```bash
# Check backup files
ls -la /opt/v2ray/config/config.json.backup.*

# Restore from backup if needed
cp /opt/v2ray/config/config.json.backup.TIMESTAMP /opt/v2ray/config/config.json
docker-compose restart
```

#### **Statistics Not Working**
```bash
# Install monitoring tools
sudo apt install vnstat htop

# Configure Xray logging through management interface
sudo v2ray-manage
# Select option 10 to configure logging

# Check log files
tail -f /opt/v2ray/logs/access.log
tail -f /opt/v2ray/logs/error.log

# If logs don't exist, logging may not be configured
# Use the management interface to set up logging
```

#### **Logging Issues**
```bash
# Check if logging is configured
sudo v2ray-manage
# Select option 11 to view logs

# If logs are empty or missing:
# 1. Configure logging (option 10)
# 2. Restart server (option 7)
# 3. Check logs again (option 11)

# Manual log file creation (if needed)
sudo mkdir -p /opt/v2ray/logs
sudo touch /opt/v2ray/logs/access.log /opt/v2ray/logs/error.log
sudo chmod 644 /opt/v2ray/logs/*.log
```

### **Performance Issues**
```bash
# Check system resources
htop
df -h
free -h

# Optimize Docker
docker system prune -f
```

## 📞 Support & Documentation

### **Official Documentation**
- [Xray-core Documentation](https://xtls.github.io/)
- [Reality Protocol Guide](https://github.com/XTLS/Xray-core/discussions/3518)
- [Docker Deployment Guide](https://docs.docker.com/)

### **Community Support**
- [Xray Telegram Group](https://t.me/projectXray)
- [GitHub Issues](https://github.com/XTLS/Xray-core/issues)
- [Configuration Examples](https://github.com/XTLS/Xray-examples)

## 📄 License

This project is released under the MIT License. See LICENSE file for details.

## 🎯 Changelog

### **v3.0.0** - Latest Release (Universal VPN Support)
- 🔀 **Dual VPN Support**: Added Outline VPN alongside existing Xray VPN
- ✅ **Universal Installation Script**: Single script supports both VPN types
- ✅ **VPN Type Selection Menu**: Choose between Xray and Outline during installation
- ✅ **Optimized Port Generation**: Unified port generation with intelligent conflict avoidance
- ✅ **Enhanced SNI Validation**: Improved domain checking with faster timeouts and better reliability
- ✅ **Multi-architecture Support**: Outline VPN works on x86-64, ARM64, and ARMv7
- ✅ **Outline Manager Integration**: GUI-based management for Outline VPN
- ✅ **Automatic Updates**: Watchtower integration for Outline container updates
- ✅ **Improved Documentation**: Comprehensive guides for both VPN solutions

### **v2.1.0** - Previous Release
- ✅ **Advanced Logging System**: Configurable Xray logging with multiple levels
- ✅ **Enhanced Statistics**: vnstat integration with automatic installation
- ✅ **Log Analysis Tools**: Built-in log viewer with filtering and search
- ✅ **User Activity Tracking**: Per-user connection statistics and monitoring
- ✅ **Improved Error Handling**: Better error messages and troubleshooting
- ✅ **Real-time Monitoring**: Live log streaming and connection tracking

### **v2.0.0** - Major Update
- ✅ Migrated to Xray-core from V2Ray
- ✅ Added XTLS Vision flow support
- ✅ Implemented automatic key rotation
- ✅ Added comprehensive traffic statistics
- ✅ Smart port selection and SNI validation
- ✅ Enhanced security with unique short IDs
- ✅ Improved user management interface

### **v1.0.0** - Initial Release
- ✅ Basic V2Ray VLESS+Reality support
- ✅ Docker containerization
- ✅ User management scripts
- ✅ QR code generation

---

**⚡ Ready to deploy enterprise-grade VPN infrastructure with dual-protocol support and cutting-edge technology!**