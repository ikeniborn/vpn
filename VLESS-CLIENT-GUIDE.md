# V2Ray VLESS Client Generator Guide

This document explains how to use the `generate-vless-client.sh` script to generate new VLESS client configurations for your Outline VPN with v2ray masking.

## Prerequisites

Before using this script, ensure you have the required dependencies:

```bash
sudo apt-get update
sudo apt-get install -y jq qrencode
```

## Basic Usage

To generate a new client configuration with a QR code:

```bash
./generate-vless-client.sh --name "client-name"
```

Replace `client-name` with a descriptive name for the client (e.g., "my-phone", "work-laptop").

### Command-line Options

The script supports the following options:

- `--name NAME`: (Required) Set a name/alias for the client
- `--config PATH`: Specify a custom path to the v2ray config file (default: /opt/v2ray/config.json)
- `--no-qr`: Don't display QR code (show connection string only)
- `--help`: Display usage information

## Examples

### Generate a client for your phone

```bash
./generate-vless-client.sh --name "my-phone"
```

### Generate a client with a custom config path

```bash
./generate-vless-client.sh --name "work-laptop" --config /custom/path/config.json
```

### Generate a client without displaying the QR code

```bash
./generate-vless-client.sh --name "server-connection" --no-qr
```

## Output

When executed successfully, the script will:

1. Generate a new UUID for the client
2. Add the client to the v2ray configuration file
3. Restart the v2ray container to apply changes
4. Display connection details including:
   - Client name
   - Server hostname/IP
   - Port
   - UUID
   - Protocol information
   - Connection string (URI)
5. Display a QR code that can be scanned directly by v2ray client apps

## Troubleshooting

### Permission Denied

If you encounter permission errors, make sure the script is executable:

```bash
chmod +x generate-vless-client.sh
```

### Config File Not Found

If the script cannot find the config file, check if v2ray is installed correctly or specify the correct path:

```bash
./generate-vless-client.sh --name "client" --config /actual/path/to/config.json
```

### Container Restart Failed

If v2ray container restart fails, verify that the Docker container is running:

```bash
docker ps | grep v2ray
```

If the container is not running, you may need to start it manually:

```bash
docker start v2ray
```

## Compatible Clients

You can use the generated QR code or connection string with the following clients:

- **Windows**: v2rayN
- **Android**: v2rayNG
- **iOS**: V2Box
- **macOS**: FoXray
- **Linux/Cross-platform**: Qv2ray

## Advanced Usage

### Adding Multiple Clients

You can run the script multiple times with different name parameters to add multiple clients to your v2ray server.

### Important Notes

- The script automatically restarts the v2ray container to apply changes
- Each client gets a unique UUID for authentication
- The configuration backup is saved at `/opt/v2ray/config.json.bak` in case you need to restore it

## Security Considerations

- Keep the generated connection details secure, as they provide access to your VPN
- Each client has its own UUID, allowing you to revoke access individually if needed
- Consider regularly rotating client UUIDs for sensitive connections