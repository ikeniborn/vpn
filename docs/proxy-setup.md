# Proxy Server Setup Guide

This guide explains how to connect to the VPN proxy servers after installation.

## Overview

The VPN Manager provides two types of proxy servers:
- **HTTP/HTTPS Proxy** (Squid) - Port 8080
- **SOCKS5 Proxy** (Dante) - Port 1080

## Server Information

After starting the proxy servers, you'll have:
- HTTP Proxy: `http://<server-ip>:8080`
- SOCKS5 Proxy: `socks5://<server-ip>:1080`

## Client Configuration

### Windows

#### HTTP Proxy Setup
1. Open **Settings** → **Network & Internet** → **Proxy**
2. Under "Manual proxy setup", enable "Use a proxy server"
3. Enter:
   - Address: `<server-ip>`
   - Port: `8080`
4. Click **Save**

#### SOCKS5 Proxy Setup (Firefox)
1. Open Firefox → **Settings** → **General** → **Network Settings**
2. Select "Manual proxy configuration"
3. Enter:
   - SOCKS Host: `<server-ip>`
   - Port: `1080`
   - Select "SOCKS v5"
4. Click **OK**

### macOS

#### System-wide HTTP Proxy
1. Open **System Preferences** → **Network**
2. Select your network connection → **Advanced** → **Proxies**
3. Check "Web Proxy (HTTP)"
4. Enter:
   - Server: `<server-ip>`
   - Port: `8080`
5. Click **OK** → **Apply**

#### SOCKS5 Proxy
1. Same as above, but check "SOCKS Proxy"
2. Enter:
   - Server: `<server-ip>`
   - Port: `1080`

### Linux

#### Using Environment Variables
```bash
# HTTP Proxy
export http_proxy="http://<server-ip>:8080"
export https_proxy="http://<server-ip>:8080"

# SOCKS5 Proxy
export all_proxy="socks5://<server-ip>:1080"
```

#### GNOME Desktop
1. Open **Settings** → **Network** → **Network Proxy**
2. Select "Manual"
3. Enter proxy details:
   - HTTP Proxy: `<server-ip>` port `8080`
   - SOCKS Host: `<server-ip>` port `1080`

### Browser-Specific Configuration

#### Google Chrome
Chrome uses system proxy settings on Windows and macOS. On Linux:
```bash
google-chrome --proxy-server="http://<server-ip>:8080"
# or for SOCKS5
google-chrome --proxy-server="socks5://<server-ip>:1080"
```

#### Firefox
1. Open **Settings** → **General** → **Network Settings**
2. Configure as described in Windows section above

#### curl
```bash
# HTTP proxy
curl -x http://<server-ip>:8080 https://example.com

# SOCKS5 proxy
curl -x socks5://<server-ip>:1080 https://example.com
```

## Authentication

If authentication is enabled on the proxy server:

### With Credentials
- HTTP: `http://username:password@<server-ip>:8080`
- SOCKS5: `socks5://username:password@<server-ip>:1080`

### Browser Authentication
When accessing through a browser, you'll be prompted for:
- Username: Your VPN username
- Password: Your VPN password/key

## Testing Your Connection

### HTTP Proxy Test
```bash
# Check your IP through the proxy
curl -x http://<server-ip>:8080 https://api.ipify.org

# Verbose connection test
curl -v -x http://<server-ip>:8080 https://example.com
```

### SOCKS5 Proxy Test
```bash
# Using curl
curl -x socks5://<server-ip>:1080 https://api.ipify.org

# Using netcat
nc -X 5 -x <server-ip>:1080 example.com 80
```

## Mobile Devices

### Android
1. Go to **Settings** → **Wi-Fi**
2. Long press your network → **Modify network**
3. Check "Show advanced options"
4. Set Proxy to "Manual"
5. Enter proxy details

### iOS
1. Go to **Settings** → **Wi-Fi**
2. Tap the (i) next to your network
3. Scroll down to "HTTP Proxy"
4. Select "Manual"
5. Enter server and port details

## Application-Specific Proxy

### Git
```bash
# HTTP proxy
git config --global http.proxy http://<server-ip>:8080
git config --global https.proxy http://<server-ip>:8080

# SOCKS5 proxy
git config --global http.proxy socks5://<server-ip>:1080
```

### npm
```bash
# HTTP proxy
npm config set proxy http://<server-ip>:8080
npm config set https-proxy http://<server-ip>:8080

# Remove proxy
npm config delete proxy
npm config delete https-proxy
```

### Docker
```bash
# Create or edit ~/.docker/config.json
{
  "proxies": {
    "default": {
      "httpProxy": "http://<server-ip>:8080",
      "httpsProxy": "http://<server-ip>:8080"
    }
  }
}
```

## Proxy Auto-Configuration (PAC)

For advanced users, create a PAC file:

```javascript
function FindProxyForURL(url, host) {
    // Direct connection for local addresses
    if (isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "127.0.0.0", "255.0.0.0")) {
        return "DIRECT";
    }
    
    // Use proxy for everything else
    return "PROXY <server-ip>:8080; SOCKS5 <server-ip>:1080";
}
```

## Security Considerations

1. **Always use HTTPS** when transmitting sensitive data through HTTP proxies
2. **SOCKS5 is preferred** for better protocol support and security
3. **Enable authentication** to prevent unauthorized access
4. **Use VPN** in addition to proxy for maximum privacy

## Performance Optimization

### Squid Cache Settings
The HTTP proxy includes caching to improve performance. Clear cache if needed:
```bash
sudo docker exec vpn-squid-proxy squid -k shutdown
sudo docker exec vpn-squid-proxy rm -rf /var/spool/squid/*
sudo docker restart vpn-squid-proxy
```

### Connection Limits
Default limits:
- HTTP Proxy: Unlimited connections
- SOCKS5 Proxy: 10 workers (configurable)

## Next Steps

- [Troubleshooting Guide](./proxy-troubleshooting.md)
- [User Management](./user-management.md)
- [Advanced Configuration](./advanced-proxy-config.md)