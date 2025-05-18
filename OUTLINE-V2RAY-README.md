# Outline VPN with v2ray VLESS Masking

This package provides an enhanced installation of Outline VPN that uses v2ray with VLESS protocol for traffic masking and improved censorship resistance. It removes all monitoring and management components for better privacy and security.

## Features

- **Enhanced Privacy**: No management API or monitoring components
- **Traffic Obfuscation**: Uses v2ray VLESS protocol with WebSocket over TLS
- **Reduced Attack Surface**: Minimal component installation
- **Improved Censorship Resistance**: Traffic looks like normal HTTPS
- **Simple Installation**: One-script setup process

## Prerequisites

- A server running Linux (x86_64 or aarch64 architecture)
- Root access or sudo privileges
- Open ports (default 443 for v2ray)
- Docker (installed automatically if missing)

## Installation

### Basic Installation

The simplest way to install is to run:

```bash
./outline-v2ray-install.sh
```

This will:
1. Install Docker if not already present
2. Set up Outline VPN (Shadowsocks)
3. Configure v2ray with VLESS protocol
4. Generate certificates and connection details

### Advanced Installation Options

You can customize the installation with these parameters:

```bash
./outline-v2ray-install.sh --hostname example.com --v2ray-port 443 --keys-port 8388
```

Parameters:
- `--hostname`: Server hostname or IP address
- `--v2ray-port`: Port for v2ray VLESS protocol (default: 443)
- `--keys-port`: Port for Shadowsocks (random if not specified)

### Environment Variables

You can further customize the installation using environment variables:

```bash
SS_METHOD=aes-256-gcm V2RAY_WS_PATH=/custom/path ./outline-v2ray-install.sh
```

Available variables:
- `SB_IMAGE`: The Shadowsocks Docker image (default: shadowsocks/shadowsocks-libev:latest)
- `CONTAINER_NAME`: Docker instance name for Shadowsocks (default: shadowbox)
- `SHADOWBOX_DIR`: Directory for Outline VPN state (default: /opt/outline)
- `V2RAY_CONTAINER_NAME`: Docker instance name for v2ray (default: v2ray)
- `V2RAY_DIR`: Directory for v2ray state (default: /opt/v2ray)
- `V2RAY_UUID`: UUID for VLESS authentication (auto-generated if not provided)
- `V2RAY_WS_PATH`: WebSocket path (default: /ws)
- `SS_METHOD`: Shadowsocks encryption method (default: chacha20-ietf-poly1305)
- `SS_PASSWORD`: Shadowsocks password (auto-generated if not provided)

## Client Configuration

After installation, the script will output the connection details needed for client configuration:

```
Server:   your-server-ip
Port:     443
UUID:     your-generated-uuid
Protocol: VLESS
TLS:      YES
Network:  WebSocket
Path:     /ws
TLS Host: your-server-ip
```

### Compatible Clients

You can use these connection details with clients like:
- v2rayN (Windows)
- v2rayNG (Android)
- Qv2ray (Cross-platform)
- V2Box (iOS)
- FoXray (macOS)

## Architecture

```
Client ←→ v2ray VLESS/TLS/WebSocket ←→ Shadowsocks ←→ Internet
```

The traffic flow is:
1. Client connects to v2ray using VLESS protocol with TLS and WebSocket
2. v2ray forwards traffic to Shadowsocks service via Docker network
3. Shadowsocks handles the actual VPN functionality

The containers communicate through a dedicated Docker network called `outline-network`. This approach is compatible with systems that have user namespaces enabled.

## Security Considerations

- TLS certificates are self-signed by default
- All components run in Docker containers
- Components communicate via a secure Docker network
- No management API is exposed
- Ports other than v2ray port (default 443) are not exposed externally
- Compatible with systems that have Docker user namespaces enabled

## Security Hardening

This package includes two security hardening scripts to help secure your VPN server:

### Firewall Configuration (firewall.sh)

The `firewall.sh` script configures a secure firewall with specific rules for Outline VPN with v2ray:

```bash
# Basic usage
sudo ./firewall.sh

# Advanced usage with options
sudo ./firewall.sh --v2ray-port 8443 --disable-port-knocking --iface eth0
```

Options:
- `--v2ray-port PORT`: Set v2ray port (default: 443)
- `--disable-port-knocking`: Disable port knocking for SSH access
- `--disable-ssh-config`: Don't configure SSH in firewall
- `--iface INTERFACE`: Specify internet-facing interface

This script:
- Configures UFW with secure defaults
- Sets up port knocking for SSH (optional)
- Opens required ports for v2ray VLESS and Outline VPN
- Configures IP forwarding for VPN traffic
- Prevents common network attacks
- Ensures Docker compatibility

### Security Auditing (security-checks.sh)

The `security-checks.sh` script performs comprehensive security audits:

```bash
# Run security checks
sudo ./security-checks.sh

# Run with custom paths (if you installed to non-default locations)
sudo OUTLINE_DIR=/custom/path/outline V2RAY_DIR=/custom/path/v2ray ./security-checks.sh
```

This script:
- Performs comprehensive security audits on the system
- Checks for common misconfigurations
- Verifies Docker security settings
- Validates Outline VPN and v2ray configurations
- Checks for proper TLS implementation
- Generates a detailed security report

The report will be saved to a file (path shown at the end of the script execution) and includes recommendations for fixing any identified issues.

### Recommended Security Practices

For maximum security:
1. Run the firewall script immediately after installation
2. Run the security audit tool regularly to check for vulnerabilities
3. Fix any issues identified in the security report
4. Consider setting up automatic security updates
5. Regularly check and rotate TLS certificates

## Troubleshooting

If you encounter issues:
1. Check the firewall settings on your server
2. Verify Docker is running properly
3. Check the logs with `docker logs v2ray` or `docker logs shadowbox`
4. Ensure the ports are correctly configured and opened
5. Verify Docker network with `docker network inspect outline-network`
6. On systems with user namespaces enabled, the script uses explicit port mapping instead of host networking

## Uninstallation

To remove the installation:

```bash
docker rm -f v2ray shadowbox
rm -rf /opt/outline /opt/v2ray
```

## Differences from Standard Outline VPN

This installation differs from the standard Outline VPN in several ways:
- No Watchtower container for auto-updates
- No management API or web interface
- Added v2ray with VLESS protocol as front-facing service
- Configured for maximum privacy and censorship resistance
- Includes dedicated security hardening scripts (firewall.sh and security-checks.sh)