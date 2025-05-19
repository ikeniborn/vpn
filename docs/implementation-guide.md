# VLESS-Reality Implementation Guide

This document provides step-by-step instructions for implementing VLESS-Reality protocol in place of the current WebSocket+TLS setup, along with testing guidelines and troubleshooting tips.

## Implementation Steps

### 1. Backup Current Configuration

Always create backups before making changes:

```bash
# Back up the v2ray configuration directory
cp -r /opt/v2ray /opt/v2ray.bak

# Back up the outline configuration directory
cp -r /opt/outline /opt/outline.bak

# Back up the actual config files
cp /opt/v2ray/config.json /opt/v2ray/config.json.bak
```

### 2. Update Scripts

Modify the scripts according to the detailed changes in our documentation:

1. Update `outline-v2ray-install.sh` with Reality protocol support
2. Create the new `manage-vless-users.sh` script
3. Update `generate-vless-client.sh` with Reality support
4. Ensure all scripts have proper permissions:

```bash
chmod +x outline-v2ray-install.sh generate-vless-client.sh manage-vless-users.sh
```

### 3. Test Installation on a Fresh System

To test without disrupting your existing setup:

```bash
# Clone the repository to a temporary location
git clone <your-repo-url> /tmp/vless-reality-test

# Run the installation with default parameters (uses microsoft.com as default target)
cd /tmp/vless-reality-test
./outline-v2ray-install.sh

# Or run with custom parameters
./outline-v2ray-install.sh --dest-site www.cloudflare.com:443 --fingerprint firefox
```

### 4. Test User Management

After installation, test the user management features:

```bash
# List users (should show just the default user)
./manage-vless-users.sh --list

# Add a new user
./manage-vless-users.sh --add --name "test-user"

# Export configuration for the user
./manage-vless-users.sh --export --uuid "user-uuid-here"

# Remove the test user
./manage-vless-users.sh --remove --uuid "user-uuid-here"
```

### 5. Test Client Configuration

Generate a client configuration and test it with a compatible client:

```bash
# Generate configuration for a client
./generate-vless-client.sh --name "test-client"
```

### 6. Implement in Production

Once testing is complete, implement in your production environment:

```bash
# Stop existing containers
docker stop v2ray shadowbox

# Update scripts
# (copy from test environment or update in place)

# Run the installation script
./outline-v2ray-install.sh --dest-site www.microsoft.com:443 --fingerprint chrome

# Migrate existing users if needed
# (manual process - extract UUIDs from old config and add them)
```

## Key Differences: WebSocket+TLS vs Reality

Understanding these differences will help with troubleshooting:

| Feature | WebSocket+TLS | Reality |
|---------|---------------|---------|
| Transport | WebSocket over TLS | TCP |
| Certificates | Requires TLS certificates | No certificates needed |
| Detection resistance | Medium (DPI can detect WebSocket) | High (mimics actual TLS traffic) |
| Connection parameters | Simpler (fewer parameters) | More complex (fingerprint, shortID, etc.) |
| Client compatibility | Wider range of clients | Newer clients with Reality support |
| Performance | Overhead from WebSocket | More efficient |
| URI format | Different | Includes more parameters |

## Important Considerations

### Destination Site Selection

Choose destination sites carefully:
- Use high-reputation, stable sites (Microsoft, Cloudflare, etc.)
- Pick sites with good global connectivity
- Avoid sites likely to be blocked in target regions
- Consider having fallback destinations

### TLS Fingerprints

Available fingerprint options:
- `chrome`: Chrome browser (best compatibility)
- `firefox`: Firefox browser
- `safari`: Safari browser
- `ios`: iOS devices
- `android`: Android devices
- `edge`: Microsoft Edge browser
- `360`: 360 Secure Browser
- `qq`: QQ Browser
- `random`: Randomize fingerprint

### Network Considerations

1. **Firewall Settings**: Reality uses TCP port (default 443), ensure this is open
2. **Allowed Domains**: Some networks block certain domains, choose your destination site accordingly
3. **Port Restrictions**: Some networks only allow certain ports, default 443 has best compatibility

## Troubleshooting

### Client Connection Issues

1. **Verify configuration parameters**: Check all parameters in the URI string
2. **Verify fingerprint**: Try different fingerprints if connection fails
3. **Check the destination site**: Ensure the destination site is accessible from the client
4. **Port access**: Verify the port is open and accessible

### Server Configuration Issues

1. **Docker issues**: Check Docker logs with `docker logs v2ray`
2. **Configuration syntax**: Verify JSON syntax with `jq . /opt/v2ray/config.json`
3. **Permissions**: Run `./outline-v2ray-install.sh --fix-permissions`

### Reality-Specific Issues

1. **Public/Private Key Mismatch**: Regenerate the keypair if needed
2. **SNI Issues**: Ensure the SNI matches the domain in the destination site
3. **Fingerprint Compatibility**: Try different fingerprints if handshake fails

## Migration Guide for Existing Users

To migrate existing users from WebSocket+TLS to Reality:

1. Extract current user UUIDs from the existing config:
   ```
   jq '.inbounds[0].settings.clients[] | .id' /opt/v2ray/config.json
   ```

2. After setting up the new Reality protocol, add each user with:
   ```
   ./manage-vless-users.sh --add --name "migrated-user-name"
   ```

3. Update each user's configuration manually or through a script

4. Set up a transition period where both old and new systems run in parallel (on different ports)

## Testing Matrix

| Test Case | Expected Result |
|-----------|-----------------|
| Install with default parameters | Installation successful, default user created |
| Install with custom destination | Installation successful with custom parameters |
| Add new user | User successfully added, appears in config |
| Remove user | User successfully removed from config |
| Export config | Configuration successfully exported |
| Connect with client | Client connects successfully |
| Firewall test | Traffic passes through firewall without detection |
| Restart test | Service restores properly after server restart |

## Next Steps

After implementation:

1. Monitor usage and performance
2. Gather feedback from users on connection stability
3. Consider implementing site rotation for better censorship resistance
4. Update client guides for users