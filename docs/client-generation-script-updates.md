# Updates for Client Generation Script

The following modifications are needed for the `generate-vless-client.sh` script to support VLESS-Reality protocol.

## 1. Update URI Generation Function

Replace the current `generate_v2ray_uri()` function with:

```bash
function generate_v2ray_uri() {
  local uuid="$1"
  local name="$2"
  local server="$3"
  local port="$4"
  
  # Check if Reality is configured
  if [ "$REALITY_CONFIG" = true ]; then
    # Format: vless://UUID@server:port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=server.com&fp=fingerprint&pbk=publicKey&sid=shortId#name
    echo "vless://${uuid}@${server}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#${name}"
  else
    # For backward compatibility with WebSocket+TLS
    # URL encode the path (replace / with %2F)
    local encoded_path="${V2RAY_WS_PATH//\//\%2F}"
    
    # Format: vless://UUID@server:port?encryption=none&security=tls&type=ws&host=server&path=%2Fws#alias
    echo "vless://${uuid}@${server}:${port}?encryption=none&security=tls&type=ws&host=${server}&path=${encoded_path}#${name}"
  fi
}
```

## 2. Add Reality Configuration Detection

Add this new function to extract Reality-specific configuration:

```bash
function extract_config_values() {
  # Extract values from v2ray config
  if [ ! -f "$V2RAY_CONFIG" ]; then
    log_error "Config file not found: $V2RAY_CONFIG"
    exit 1
  fi
  
  # Extract port from config
  local port
  port=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG")
  if [ "$port" != "null" ] && [ -n "$port" ]; then
    V2RAY_PORT=$port
  fi
  
  # Check if using Reality protocol
  if jq -e '.inbounds[0].streamSettings.security == "reality"' "$V2RAY_CONFIG" > /dev/null; then
    REALITY_CONFIG=true
    
    # Extract Reality settings
    SERVER_NAME=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$V2RAY_CONFIG")
    DEST_SITE=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$V2RAY_CONFIG")
    FINGERPRINT=$(jq -r '.inbounds[0].streamSettings.realitySettings.fingerprint' "$V2RAY_CONFIG")
    SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$V2RAY_CONFIG")
    PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$V2RAY_CONFIG")
    
    # Compute public key from private key
    if command -v xray &> /dev/null; then
      PUBLIC_KEY=$(echo "$PRIVATE_KEY" | xray x25519 -i | grep "Public key:" | cut -d' ' -f3)
    elif docker ps -a --format '{{.Names}}' | grep -q "^v2ray$"; then
      PUBLIC_KEY=$(docker exec v2ray xray x25519 -i "$PRIVATE_KEY" | grep "Public key:" | cut -d' ' -f3)
    else
      PUBLIC_KEY=$(docker run --rm "${V2RAY_IMAGE:-v2fly/v2fly-core:latest}" xray x25519 -i "$PRIVATE_KEY" | grep "Public key:" | cut -d' ' -f3)
    fi
  else
    REALITY_CONFIG=false
    
    # For backward compatibility, extract WebSocket path
    local ws_path
    ws_path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$V2RAY_CONFIG" 2>/dev/null)
    if [ "$ws_path" != "null" ] && [ -n "$ws_path" ]; then
      V2RAY_WS_PATH=$ws_path
    fi
  fi
}
```

## 3. Update Display Output Function

Create a new function to display connection information:

```bash
function display_connection_info() {
  local uuid="$1"
  local name="$2"
  local server="$3"
  local port="$4"
  local uri="$5"
  
  echo ""
  echo "=============== VLESS Client Connection Details ==============="
  echo ""
  echo "Client Name: $name"
  echo "Server:      $server"
  echo "Port:        $port"
  echo "UUID:        $uuid"
  echo "Protocol:    VLESS"
  
  if [ "$REALITY_CONFIG" = true ]; then
    echo "Security:    Reality"
    echo "Flow:        xtls-rprx-vision"
    echo "SNI:         $SERVER_NAME"
    echo "Fingerprint: $FINGERPRINT"
    echo "Short ID:    $SHORT_ID"
    echo "Public Key:  $PUBLIC_KEY"
  else
    # For backward compatibility
    echo "Security:    TLS"
    echo "Network:     WebSocket"
    echo "Path:        $V2RAY_WS_PATH"
    echo "TLS Host:    $server"
  fi
  
  echo ""
  echo "Connection string for manual configuration:"
  echo "$uri"
  echo ""
}
```

## 4. Add Global Variables 

Add these at the top of the script, after the existing variables:

```bash
# Default values
V2RAY_DIR="${V2RAY_DIR:-/opt/v2ray}"
V2RAY_CONFIG="${V2RAY_DIR}/config.json"
V2RAY_PORT=443
V2RAY_WS_PATH="/ws"
CLIENT_NAME=""
DISPLAY_QR=true

# Reality config defaults
REALITY_CONFIG=false
SERVER_NAME=""
DEST_SITE=""
FINGERPRINT=""
SHORT_ID=""
PRIVATE_KEY=""
PUBLIC_KEY=""
```

## 5. Update Main Function

Modify the main function to use the new Reality-aware functions:

```bash
function main() {
  parse_flags "$@"
  check_dependencies
  extract_config_values
  
  # Generate UUID for new client
  local uuid
  uuid=$(generate_uuid)
  
  # Get server hostname
  local server
  server=$(get_server_hostname)
  
  # Add client to config
  add_client_to_config "$uuid" "$CLIENT_NAME"
  
  # Restart v2ray to apply changes
  restart_v2ray
  
  # Generate v2ray URI
  local uri
  uri=$(generate_v2ray_uri "$uuid" "$CLIENT_NAME" "$server" "$V2RAY_PORT")
  
  # Display connection information
  display_connection_info "$uuid" "$CLIENT_NAME" "$server" "$V2RAY_PORT" "$uri"
  
  # Generate and display QR code
  echo "Scan this QR code with your v2ray client app:"
  echo ""
  generate_qr_code "$uri"
  
  echo ""
  echo "================================================================"
  echo "Compatible clients:"
  echo "- v2rayN (Windows)"
  echo "- v2rayNG (Android)"
  echo "- Qv2ray (Cross-platform)"
  echo "- V2Box (iOS)"
  echo "- FoXray (macOS)"
  echo "================================================================"
}
```

## 6. Update Server Hostname Detection

Modify the `get_server_hostname()` function to handle Reality configuration:

```bash
function get_server_hostname() {
  # Try to get the hostname from the config file
  local hostname
  
  if [ "$REALITY_CONFIG" = true ]; then
    # For Reality, use the server's IP address
    if hostname=$(hostname -I | awk '{print $1}'); then
      echo "$hostname"
      return 0
    fi
  else
    # First, try to extract from v2ray config for WebSocket+TLS
    if hostname=$(jq -r '.inbounds[0].streamSettings.wsSettings.headers.Host' "$V2RAY_CONFIG" 2>/dev/null) && 
       [ "$hostname" != "null" ] && [ -n "$hostname" ]; then
      echo "$hostname"
      return 0
    fi
  fi
  
  # If the above methods fail, try to guess using public IP services
  local -a urls=(
    'https://icanhazip.com/'
    'https://ipinfo.io/ip'
    'https://domains.google.com/checkip'
  )
  
  for url in "${urls[@]}"; do
    if hostname=$(curl -s "$url"); then
      echo "$hostname"
      return 0
    fi
  done
  
  log_error "Failed to determine server hostname"
  exit 1
}
```

## Complete Updated Script

These changes should be integrated with the existing script logic. After implementation, the script will:

1. Detect if Reality protocol is used instead of WebSocket+TLS
2. Extract all necessary Reality parameters from the configuration
3. Generate the correct URI format for Reality protocol
4. Display relevant connection information to the user
5. Generate a QR code that works with Reality-compatible clients

Remember to test the script thoroughly after implementation to ensure it works with both new Reality configurations and maintains backward compatibility with the old WebSocket+TLS setup if needed.