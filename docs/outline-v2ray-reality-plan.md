# Implementation Plan for VLESS-Reality Protocol

This document outlines the implementation plan for updating the current VPN solution to use VLESS-Reality protocol instead of WebSocket+TLS.

## 1. Key Changes Required

1. **Protocol Changes**
   - Replace WebSocket transport with TCP
   - Replace TLS security with Reality protocol
   - Update client URI format

2. **Configuration Changes**
   - Add Reality keypair generation instead of certificates
   - Configure destination sites for mimicking
   - Set up TLS fingerprinting

3. **User Management**
   - Implement bash scripts for user management
   - Create tracking for users, creation dates, etc.
   - Support export features for client configurations

## 2. File Modifications

### 2.1. outline-v2ray-install.sh

1. **Add new command line parameters**
   - `--dest-site`: The destination site to mimic (default: www.microsoft.com:443)
   - `--fingerprint`: TLS fingerprint to simulate (default: chrome)

2. **Add Reality keypair generation**
   - Replace certificate generation with X25519 keypair generation
   - Generate and store short IDs for authentication

3. **Update V2Ray configuration**
   - Change network from WebSocket to TCP
   - Replace TLS settings with Reality settings
   - Set up destination site mimicking

### 2.2. generate-vless-client.sh

1. **Update URI generation**
   - Update for Reality protocol format
   - Include new parameters (fingerprint, shortId, publicKey)

2. **Modify output display**
   - Show Reality-specific parameters
   - Update QR code generation

### 2.3. New Script: manage-vless-users.sh

Create a new script for user management with features:

1. **List users**
   - Show UUIDs, names, creation dates

2. **Add users**
   - Generate UUIDs
   - Update V2Ray config 
   - Track creation dates

3. **Remove users**
   - Remove from V2Ray config
   - Update user database

4. **Export configurations**
   - Generate client configurations for specific users
   - Output in multiple formats

## 3. Implementation Steps

1. Backup current configuration
2. Update installation script
3. Test new installation on test server
4. Create user management scripts
5. Update documentation
6. Implement client configuration support

## 4. Configuration Details

### 4.1. Reality Protocol Configuration

```json
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [
        {"id": "UUID", "flow": "xtls-rprx-vision", "level": 0}
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "generated_private_key",
        "shortIds": ["shortid1"],
        "fingerprint": "chrome"
      }
    }
  }]
}
```

### 4.2. Client Connection String Format

```
vless://UUID@server:port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=server.com&fp=fingerprint&pbk=publicKey&sid=shortId#name
```

## 5. User Management Database

A simple text-based database will be used to track users:
- Format: `UUID|Name|DateCreated`
- Stored at `/opt/v2ray/users.db`
- Updated when users are added or removed