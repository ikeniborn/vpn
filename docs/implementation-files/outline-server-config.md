# Outline Server (Shadowsocks) Configuration

This file defines the Shadowsocks configuration for the Outline Server component of the integrated VPN solution.

## File Path
```
/opt/vpn/outline-server/config.json
```

## Configuration

```json
{
  "server": "0.0.0.0",
  "server_port": 8388,
  "password": "your_default_password_here",
  "timeout": 300,
  "method": "chacha20-ietf-poly1305",
  "fast_open": true,
  "reuse_port": true,
  "no_delay": true,
  "nameserver": "8.8.8.8",
  "mode": "tcp_and_udp",
  "plugin": "obfs-server",
  "plugin_opts": "obfs=http;obfs-host=www.microsoft.com"
}
```

## Access Policy Configuration

```
/opt/vpn/outline-server/access.json
```

```json
{
  "strategy": "allow", 
  "rules": []
}
```

## Description

### Main Configuration Options

1. **Server Settings**:
   - `server`: Bind to all interfaces (0.0.0.0)
   - `server_port`: Default port 8388 for Shadowsocks traffic
   - `password`: Secret for encryption (should be generated randomly during setup)
   - `timeout`: Connection timeout in seconds

2. **Encryption Settings**:
   - `method`: ChaCha20-IETF-Poly1305 cipher (AEAD cipher, considered secure)
   - Uses less CPU than AES-based ciphers on devices without AES hardware acceleration

3. **Performance Optimizations**:
   - `fast_open`: TCP Fast Open for reduced connection latency
   - `reuse_port`: Enable port reuse for better multi-core performance
   - `no_delay`: Disable Nagle's algorithm for lower latency
   - `nameserver`: DNS server for domain resolution

4. **Traffic Obfuscation**:
   - `plugin`: Uses obfs-server plugin for traffic obfuscation
   - `plugin_opts`: Configures HTTP obfuscation to make traffic appear as normal HTTP
   - Uses Microsoft.com as the disguise host for evasion of DPI

5. **Access Policy**:
   - Simple allow/deny strategy for IP-based access control
   - Can be expanded with specific rules as needed

## User-Specific Configurations

For each user, a separate configuration is stored in:

```
/opt/vpn/outline-server/data/{username}/config.json
```

With user-specific password but shared settings.

## Implementation Details

1. **Installation**:
   - Requires shadowsocks-libev package with obfs plugin
   - Configuration should have strict permissions (600)
   - Directory structure must exist before container starts

2. **Security Considerations**:
   - Passwords should be at least 16 random characters
   - FileSystem permissions should be restricted
   - Don't expose the management API to the internet

3. **Performance Optimization**:
   - UDP support is enabled for better performance with some protocols
   - Both TCP and UDP traffic is handled on the same port

4. **Integration with VLESS+Reality**:
   - Traffic is forwarded internally to the v2ray container
   - Uses the internal Docker network (172.16.238.0/24)
   - Routes to the v2ray container (172.16.238.3) on port 443

## Client Configuration

Client-side configuration should match these server settings:

```json
{
  "server": "your_server_ip",
  "server_port": 8388,
  "password": "user_specific_password",
  "method": "chacha20-ietf-poly1305",
  "plugin": "obfs-local",
  "plugin_opts": "obfs=http;obfs-host=www.microsoft.com",
  "timeout": 300
}
```

This can be provided to users as a configuration file or through the Outline Client app.