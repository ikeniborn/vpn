# VPN Client Setup Instructions

This guide provides step-by-step instructions for connecting to our secure VPN services using either V2Ray or OutlineVPN (Shadowsocks). These configurations include advanced traffic masking capabilities to help evade deep packet inspection (DPI) and bypass censorship.

## Table of Contents

- [VPN Client Setup Instructions](#vpn-client-setup-instructions)
  - [Table of Contents](#table-of-contents)
  - [V2Ray Client Setup](#v2ray-client-setup)
    - [Windows](#windows)
    - [macOS](#macos)
    - [Android](#android)
    - [iOS](#ios)
  - [OutlineVPN (Shadowsocks) Client Setup](#outlinevpn-shadowsocks-client-setup)
    - [Windows](#windows-1)
    - [macOS](#macos-1)
    - [Android](#android-1)
    - [iOS](#ios-1)
  - [Security Best Practices](#security-best-practices)
  - [Troubleshooting](#troubleshooting)
    - [Common Issues and Solutions](#common-issues-and-solutions)
    - [Additional Help](#additional-help)

## V2Ray Client Setup

### <a name="v2ray-windows"></a>Windows

1. **Download the V2Ray client**:
   - Download V2RayN from the official GitHub repository: [https://github.com/2dust/v2rayN/releases](https://github.com/2dust/v2rayN/releases)
   - Download the latest `v2rayN-Core.zip` file

2. **Installation**:
   - Extract the ZIP file to a location on your computer
   - Run `v2rayN.exe`
   - The application will appear in your system tray

3. **Configuration**:
   - Right-click the V2RayN icon in the system tray
   - Select "Import Config from Clipboard"
   - Paste the following configuration (replace with your actual server details):

```json
{
  "v": "2",
  "ps": "Your-Server-Name",
  "add": "v2ray.example.com",
  "port": "443",
  "id": "6ba85179-5016-4930-9a9c-4c2f236c4aa0",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "v2ray.example.com",
  "path": "/api/v3/streaming/data",
  "tls": "tls",
  "sni": "v2ray.example.com"
}
```

4. **Connect to the VPN**:
   - Right-click the V2RayN icon
   - Select "Enable V2Ray Routing"
   - Choose the server you just added

### <a name="v2ray-macos"></a>macOS

1. **Download the V2Ray client**:
   - Download V2RayX from [https://github.com/Cenmrev/V2RayX/releases](https://github.com/Cenmrev/V2RayX/releases)
   - Alternatively, use V2rayU: [https://github.com/yanue/V2rayU/releases](https://github.com/yanue/V2rayU/releases)

2. **Installation**:
   - Open the DMG file and drag the application to your Applications folder
   - When launching for the first time, you may need to go to System Preferences → Security & Privacy to allow the app to run

3. **Configuration**:
   - Open V2RayX/V2RayU
   - Click on "Configure"
   - Add a new server with the following settings:
     - Address: `v2ray.example.com`
     - Port: `443`
     - User ID: `6ba85179-5016-4930-9a9c-4c2f236c4aa0`
     - AlterId: `0`
     - Security: `auto`
     - Network: `ws`
     - Path: `/api/v3/streaming/data`
     - TLS: `Enabled`
     - Host: `v2ray.example.com`

4. **Connect to the VPN**:
   - Click on "Server" → Select your server
   - Click on "V2Ray" → "Start V2Ray"

### <a name="v2ray-android"></a>Android

1. **Download the V2Ray client**:
   - Install V2RayNG from Google Play Store or from GitHub: [https://github.com/2dust/v2rayNG/releases](https://github.com/2dust/v2rayNG/releases)

2. **Configuration**:
   - Open V2RayNG
   - Tap on the "+" button in the bottom right
   - Select "Import Config from Clipboard"
   - Paste the same configuration JSON used in the Windows instructions
   - Alternatively, select "Manual Settings" and enter:
     - Remarks: `Your-Server-Name`
     - Address: `v2ray.example.com`
     - Port: `443`
     - User ID: `6ba85179-5016-4930-9a9c-4c2f236c4aa0`
     - AlterId: `0`
     - Security: `auto`
     - Network: `ws`
     - Path: `/api/v3/streaming/data`
     - TLS: `Enabled`
     - Host: `v2ray.example.com`

3. **Connect to the VPN**:
   - Tap on the server you just added
   - Tap on the "V" button at the bottom to connect

### <a name="v2ray-ios"></a>iOS

1. **Download the V2Ray client**:
   - Install Shadowrocket from the App Store (paid app)

2. **Configuration**:
   - Open Shadowrocket
   - Tap on the "+" button in the top right
   - Type: select "VMess"
   - Fill in the details:
     - Server: `v2ray.example.com`
     - Port: `443`
     - UUID: `6ba85179-5016-4930-9a9c-4c2f236c4aa0`
     - Alter ID: `0`
     - Transport: `ws`
     - Path: `/api/v3/streaming/data`
     - TLS: `Enabled`
     - Host: `v2ray.example.com`
   - Tap "Done" to save

3. **Connect to the VPN**:
   - Toggle the switch next to the server configuration to connect

## OutlineVPN (Shadowsocks) Client Setup

### <a name="outline-windows"></a>Windows

1. **Download the OutlineVPN client**:
   - Download from the official website: [https://getoutline.org/get-started/#step-3](https://getoutline.org/get-started/#step-3)
   - Alternatively, download the Shadowsocks Windows client: [https://github.com/shadowsocks/shadowsocks-windows/releases](https://github.com/shadowsocks/shadowsocks-windows/releases)

2. **Installation**:
   - Run the installer and follow the prompts

3. **Configuration**:
   - For Outline client: Use the access key provided by your administrator
   - For Shadowsocks client:
     - Right-click the Shadowsocks icon in the system tray
     - Select "Servers" → "Edit Servers"
     - Click "Add"
     - Server IP: `outline.example.com`
     - Server Port: `8388`
     - Password: `changeThisPassword` (use the actual password)
     - Encryption: `chacha20-ietf-poly1305`
     - Plugin: `obfs-local`
     - Plugin Options: `obfs=http;obfs-host=www.example.com`

4. **Connect to the VPN**:
   - Right-click the Shadowsocks icon in the system tray
   - Select "Enable System Proxy"

### <a name="outline-macos"></a>macOS

1. **Download the OutlineVPN client**:
   - Download from the official website: [https://getoutline.org/get-started/#step-3](https://getoutline.org/get-started/#step-3)
   - Alternatively, download ShadowsocksX-NG: [https://github.com/shadowsocks/ShadowsocksX-NG/releases](https://github.com/shadowsocks/ShadowsocksX-NG/releases)

2. **Installation**:
   - Open the DMG file and drag the application to your Applications folder

3. **Configuration**:
   - For Outline client: Use the access key provided by your administrator
   - For ShadowsocksX-NG:
     - Click on the Shadowsocks icon in the menu bar
     - Select "Server" → "Server Preferences"
     - Click "+"
     - Address: `outline.example.com`
     - Port: `8388`
     - Password: `changeThisPassword` (use the actual password)
     - Encryption: `chacha20-ietf-poly1305`
     - Plugin: `obfs-local`
     - Plugin Options: `obfs=http;obfs-host=www.example.com`

4. **Connect to the VPN**:
   - Click on the Shadowsocks icon in the menu bar
   - Select "Turn Shadowsocks On"

### <a name="outline-android"></a>Android

1. **Download the OutlineVPN client**:
   - Install from Google Play Store: [https://play.google.com/store/apps/details?id=org.outline.android.client](https://play.google.com/store/apps/details?id=org.outline.android.client)
   - Alternatively, install Shadowsocks for Android: [https://play.google.com/store/apps/details?id=com.github.shadowsocks](https://play.google.com/store/apps/details?id=com.github.shadowsocks)

2. **Configuration**:
   - For Outline client: Use the access key provided by your administrator
   - For Shadowsocks client:
     - Tap on the "+" button
     - Scan QR code or manually enter:
       - Profile Name: `Your-Server-Name`
       - Server: `outline.example.com`
       - Port: `8388`
       - Password: `changeThisPassword` (use the actual password)
       - Encryption Method: `chacha20-ietf-poly1305`
       - Plugin: `obfs-local`
       - Plugin Configuration: `obfs=http;obfs-host=www.example.com`

3. **Connect to the VPN**:
   - Tap on the server profile
   - Tap the connect button

### <a name="outline-ios"></a>iOS

1. **Download the OutlineVPN client**:
   - Install from the App Store: [https://apps.apple.com/us/app/outline-app/id1356177741](https://apps.apple.com/us/app/outline-app/id1356177741)
   - Alternatively, install Shadowrocket (paid app)

2. **Configuration**:
   - For Outline client: Use the access key provided by your administrator
   - For Shadowrocket:
     - Tap on the "+" button
     - Type: select "Shadowsocks"
     - Fill in the details:
       - Host: `outline.example.com`
       - Port: `8388`
       - Password: `changeThisPassword` (use the actual password)
       - Encryption: `chacha20-ietf-poly1305`
       - Plugin: `obfs`
       - Plugin Options: `obfs=http;obfs-host=www.example.com`

3. **Connect to the VPN**:
   - Tap the connect button or toggle the switch

## Security Best Practices

1. **Keep your clients updated**:
   - Always use the latest version of the VPN client software to ensure you have the most recent security patches.

2. **Use strong passwords**:
   - Ensure you're using a strong, unique password for your VPN connection.

3. **Enable kill switch**:
   - If your VPN client has a "kill switch" feature, enable it to prevent data leakage if the VPN connection drops.

4. **Use Secure DNS**:
   - Configure your client to use secure DNS servers (e.g., 1.1.1.1 or 9.9.9.9) to prevent DNS leaks.

5. **Check for leaks**:
   - Periodically visit [ipleak.net](https://ipleak.net) while connected to verify there are no IP, DNS, or WebRTC leaks.

6. **Use the recommended traffic obfuscation settings**:
   - The configurations provided include optimized traffic obfuscation settings to evade DPI. Do not change these settings without consulting your administrator.

7. **Be aware of your environment**:
   - Be mindful when using the VPN in public or untrusted networks.

8. **Additional security**:
   - Consider using Tor Browser in conjunction with the VPN for enhanced anonymity when needed.

## Troubleshooting

### Common Issues and Solutions

1. **Cannot Connect to Server**:
   - Verify your internet connection is working
   - Check that your server address and port are correct
   - Try alternative connection methods (e.g., switch from WebSocket to gRPC in V2Ray)

2. **Slow Connection Speeds**:
   - Try switching to a different server if available
   - Change to a less secure but faster encryption method if speed is more important than maximum security
   - Check if your ISP is throttling VPN connections

3. **Connection Drops Frequently**:
   - Adjust timeouts in the client configuration
   - Try different protocols (WebSocket or gRPC for V2Ray)
   - If using mobile, check if your device is aggressively managing background processes

4. **Blocked by DPI/Firewall**:
   - Try switching to the alternative port (443 is recommended as it's generally not blocked)
   - Enable or adjust obfuscation settings
   - Use the fallback connection options included in the configurations

5. **TLS Certificate Errors**:
   - Ensure your system time is correctly set
   - Check if your client has the latest CA certificates
   - Verify the server hostname matches the TLS certificate

### Additional Help

If you continue to experience issues connecting to the VPN, please contact your system administrator with the following information:

- Your client software and version
- Operating system and version
- Error messages (screenshots if possible)
- Connection logs (with sensitive information redacted)
- Network environment (home, work, public Wi-Fi)

For urgent assistance, contact: `support@example.com`