# Xray VPN Server with VLESS+Reality

## 📋 Overview

This project provides a professional-grade VPN solution using **Xray-core** with **VLESS+Reality** protocol. Built with Docker for easy deployment and management, it offers enterprise-level security with advanced features like automatic port selection, SNI quality monitoring, key rotation, and traffic statistics.

## ✨ Key Features

### 🔒 **Advanced Security**
- **VLESS+Reality Protocol**: State-of-the-art protocol with TLS 1.3 masquerading
- **XTLS Vision Flow**: Enhanced performance with minimal processing overhead
- **Automatic Key Rotation**: Built-in security key rotation functionality
- **Unique Short IDs**: Each user gets a unique identification for better security

### 🚀 **Smart Installation**
- **SNI Domain Validation**: Automatic checking of domain availability and TLS 1.3 support
- **Intelligent Port Selection**: Random port assignment with conflict detection
- **One-click Setup**: Fully automated installation process
- **Docker-based**: Containerized deployment for better isolation

### 📊 **Monitoring & Statistics**
- **Traffic Analytics**: Comprehensive usage statistics and monitoring
- **Connection Tracking**: Real-time connection monitoring
- **Performance Metrics**: Docker container and system resource usage
- **User Activity**: Individual user connection history

### 👥 **User Management**
- **Multi-user Support**: Add unlimited users with unique configurations
- **QR Code Generation**: Automatic QR codes for mobile device setup
- **Bulk Operations**: Easy user management with batch operations
- **Configuration Export**: Individual user configuration files

## 🔧 Technical Specifications

### **Supported Protocols**
- **VLESS+Reality** (Recommended): Enhanced security with TLS 1.3 masquerading
- **VLESS Basic**: Standard VLESS protocol for basic scenarios

### **Core Technologies**
- **Xray-core**: Latest XTLS/Xray-core implementation
- **Docker**: Containerized deployment with teddysun/xray image
- **Reality Protocol**: Advanced anti-detection technology
- **X25519 Cryptography**: Military-grade key generation

## 📦 Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 10+, CentOS 8+)
- **Privileges**: Root access required
- **Resources**: Minimum 512MB RAM, 1GB disk space
- **Network**: Internet connectivity and open firewall port

**Auto-installed Dependencies:**
- Docker & Docker Compose
- UFW Firewall
- OpenSSL, jq, qrencode, uuid-runtime

## 🚀 Quick Installation

### 1. Download Installation Script
```bash
wget -O install_vpn.sh https://raw.githubusercontent.com/your-repo/install_vpn.sh
chmod +x install_vpn.sh
```

### 2. Run Installation
```bash
sudo ./install_vpn.sh
```

### 3. Configuration Options

**Port Selection:**
- **Option 1**: Random free port (10000-65000) - Recommended
- **Option 2**: Manual port specification with validation
- **Option 3**: Standard port (10443)

**SNI Domain Options:**
- **Option 1**: addons.mozilla.org (Recommended)
- **Option 2**: www.lovelive-anime.jp
- **Option 3**: www.swift.org
- **Option 4**: Custom domain with validation
- **Option 5**: Automatic best domain selection

**Protocol Selection:**
- **VLESS+Reality**: Enhanced security (Recommended)
- **VLESS Basic**: Standard protocol

## 🛠️ User Management

### Access Management Interface
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
| 10 | Uninstall Server | Complete removal with cleanup |

### 🔄 Advanced Features

#### **Key Rotation**
- Automatic backup of current configuration
- Generation of new X25519 keypairs
- Updates all user configurations
- Regenerates QR codes and connection links
- Zero-downtime key updates

#### **Traffic Statistics**
- Docker container resource usage
- Network interface statistics
- Active connection monitoring
- User activity tracking
- Performance recommendations

## 📱 Client Setup

### **Recommended Clients**

| Platform | Client | Download |
|----------|--------|----------|
| **Android** | v2rayNG | [Google Play](https://play.google.com/store/apps/details?id=com.v2ray.ang) |
| **iOS** | Shadowrocket | [App Store](https://apps.apple.com/app/shadowrocket/id932747118) |
| **Windows** | v2rayN | [GitHub](https://github.com/2dust/v2rayN) |
| **macOS** | V2RayXS | [GitHub](https://github.com/tzmax/V2RayXS) |
| **Linux** | Qv2ray | [GitHub](https://github.com/Qv2ray/Qv2ray) |

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

## 📊 Monitoring & Analytics

### **Built-in Statistics**
- **Container Metrics**: CPU, Memory, Network I/O
- **Connection Stats**: Active connections, bandwidth usage
- **User Analytics**: Connection history, traffic patterns
- **System Health**: Uptime, resource utilization

### **Log Files**
- **Access Logs**: `/opt/v2ray/logs/access.log`
- **Error Logs**: `/opt/v2ray/logs/error.log`
- **Container Logs**: `docker logs xray`

### **Performance Monitoring**
```bash
# Real-time container stats
docker stats xray

# View recent logs
docker logs --tail 50 xray

# Network connections
sudo netstat -tulnp | grep :YOUR_PORT
```

## 🔧 Advanced Configuration

### **Directory Structure**
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

### **Manual Docker Operations**
```bash
# Navigate to working directory
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

# Check log files
tail -f /opt/v2ray/logs/access.log
tail -f /opt/v2ray/logs/error.log
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

### **v2.0.0** - Latest Release
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

**⚡ Ready to deploy enterprise-grade VPN infrastructure with cutting-edge technology!**