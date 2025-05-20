#!/bin/bash
#
# Script to manage users for both Outline Server and VLESS-Reality

set -euo pipefail

# Default values
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
OUTLINE_CONFIG="${OUTLINE_DIR}/config.json"
V2RAY_CONFIG="${V2RAY_DIR}/config.json"
V2RAY_USERS_DB="${V2RAY_DIR}/users.db"
OPERATION=""
UUID=""
NAME=""
PASSWORD=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

function log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function log_info() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

function display_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Manage users for integrated Outline (Shadowsocks) and VLESS-Reality VPN.

Operations:
  --list                List all configured users
  --add --name NAME     Add a new user with the specified name
  --remove --uuid UUID  Remove a user with the specified UUID
  --export --uuid UUID  Export client configuration for a specific user

Options:
  --password PASS      Set specific password for Shadowsocks (with --add)
  --help               Display this help message
EOF
}

function check_dependencies() {
  local missing_deps=()
  
  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi
  
  if ! command -v qrencode &> /dev/null; then
    missing_deps+=("qrencode")
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${missing_deps[*]}"
    echo "Please install them using:"
    echo "sudo apt-get install ${missing_deps[*]}"
    exit 1
  fi
}

function list_users() {
  echo "=== VLESS-Reality and Outline Server Users ==="
  echo ""
  echo "UUID                                  Name                         Added"
  echo "------------------------------------------------------------------------------"
  
  # List v2ray users
  if [ -f "$V2RAY_CONFIG" ] && [ -f "$V2RAY_USERS_DB" ]; then
    jq -r '.inbounds[0].settings.clients[] | .id' "$V2RAY_CONFIG" | while read -r uuid; do
      name=$(jq -r --arg uuid "$uuid" '.inbounds[0].settings.clients[] | select(.id == $uuid) | .email // "<unnamed>"' "$V2RAY_CONFIG")
      added=$(grep "$uuid" "$V2RAY_USERS_DB" | cut -d'|' -f3 || echo "unknown")
      printf "%-36s  %-28s  %s\n" "$uuid" "$name" "$added"
    done
  else
    log_error "v2ray configuration or users database not found"
  fi
}

function add_user() {
  local name="$1"
  local password="$2"
  local uuid
  
  # Generate UUID for new user
  uuid=$(cat /proc/sys/kernel/random/uuid)
  
  # Generate random password if not provided
  if [ -z "$password" ]; then
    password=$(openssl rand -base64 16)
  fi

  log_info "Adding user to v2ray (VLESS-Reality)..."
  
  # Create a backup of the original v2ray config
  cp "$V2RAY_CONFIG" "${V2RAY_CONFIG}.bak"
  
  # Add the new client to the v2ray config
  local temp_config
  temp_config=$(mktemp)
  
  # Check if using Reality (flow field needed)
  if jq -e '.inbounds[0].streamSettings.security == "reality"' "$V2RAY_CONFIG" > /dev/null; then
    jq --arg uuid "$uuid" --arg name "$name" '.inbounds[0].settings.clients += [{"id": $uuid, "flow": "xtls-rprx-vision", "level": 0, "email": $name}]' "$V2RAY_CONFIG" > "$temp_config"
  else
    jq --arg uuid "$uuid" --arg name "$name" '.inbounds[0].settings.clients += [{"id": $uuid, "level": 0, "email": $name}]' "$V2RAY_CONFIG" > "$temp_config"
  fi
  
  # Check if jq command was successful
  if [ $? -ne 0 ]; then
    log_error "Failed to modify the v2ray config file"
    rm -f "$temp_config"
    exit 1
  fi
  
  # Replace the original config with the modified one
  mv "$temp_config" "$V2RAY_CONFIG"
  
  # Set appropriate permissions
  chmod 644 "$V2RAY_CONFIG"
  
  # Add to v2ray users database
  echo "$uuid|$name|$(date '+%Y-%m-%d %H:%M:%S')" >> "$V2RAY_USERS_DB"
  
  log_info "Adding user to Outline Server (Shadowsocks)..."
  
  # Create user-specific config in outline data directory
  mkdir -p "${OUTLINE_DIR}/data/$name"
  
  # Create user's shadowsocks config
  cat > "${OUTLINE_DIR}/data/$name/config.json" <<EOF
{
  "server": "0.0.0.0",
  "server_port": $(jq -r '.server_port' "${OUTLINE_CONFIG}"),
  "password": "$password",
  "method": "$(jq -r '.method' "${OUTLINE_CONFIG}")",
  "plugin": "$(jq -r '.plugin // "obfs-server"' "${OUTLINE_CONFIG}")",
  "plugin_opts": "$(jq -r '.plugin_opts // "obfs=http"' "${OUTLINE_CONFIG}")",
  "remarks": "$name",
  "timeout": 300
}
EOF
  
  log_success "User '$name' added successfully"
  echo "UUID (for v2ray): $uuid"
  echo "Password (for Shadowsocks): $password"
  echo
  echo "To export client configurations, run:"
  echo "  ./manage-users.sh --export --uuid \"$uuid\""
  
  # Restart containers to apply changes
  restart_services
}

function remove_user() {
  local uuid="$1"
  
  # Check if user exists in v2ray
  if ! jq -e ".inbounds[0].settings.clients[] | select(.id == \"$uuid\")" "$V2RAY_CONFIG" > /dev/null; then
    log_error "User with UUID '$uuid' not found in v2ray configuration"
    exit 1
  fi
  
  # Get user name before removing
  local name
  name=$(jq -r --arg uuid "$uuid" '.inbounds[0].settings.clients[] | select(.id == $uuid) | .email // "<unnamed>"' "$V2RAY_CONFIG")
  
  # Create a backup of the original config
  cp "$V2RAY_CONFIG" "${V2RAY_CONFIG}.bak"
  
  # Remove the client from the v2ray config
  local temp_config
  temp_config=$(mktemp)
  jq --arg uuid "$uuid" '.inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != $uuid)]' "$V2RAY_CONFIG" > "$temp_config"
  
  # Check if jq command was successful
  if [ $? -ne 0 ]; then
    log_error "Failed to modify the v2ray config file"
    rm -f "$temp_config"
    exit 1
  fi
  
  # Replace the original config with the modified one
  mv "$temp_config" "$V2RAY_CONFIG"
  
  # Set appropriate permissions
  chmod 644 "$V2RAY_CONFIG"
  
  # Update v2ray users database
  grep -v "$uuid" "$V2RAY_USERS_DB" > "${V2RAY_USERS_DB}.tmp"
  mv "${V2RAY_USERS_DB}.tmp" "$V2RAY_USERS_DB"
  
  # Remove user from Outline Server
  if [ -d "${OUTLINE_DIR}/data/$name" ]; then
    rm -rf "${OUTLINE_DIR}/data/$name"
  fi
  
  log_success "User '$name' with UUID '$uuid' removed successfully"
  
  # Restart containers to apply changes
  restart_services
}

function export_user_config() {
  local uuid="$1"
  
  # Check if user exists
  if ! jq -e ".inbounds[0].settings.clients[] | select(.id == \"$uuid\")" "$V2RAY_CONFIG" > /dev/null; then
    log_error "User with UUID '$uuid' not found"
    exit 1
  fi
  
  # Get user name
  local name
  name=$(jq -r --arg uuid "$uuid" '.inbounds[0].settings.clients[] | select(.id == $uuid) | .email // "<unnamed>"' "$V2RAY_CONFIG")
  
  # Get server hostname/IP
  local server
  server=$(hostname -I | awk '{print $1}')
  
  # Export v2ray configuration
  log_info "Exporting v2ray (VLESS-Reality) configuration for: $name"
  
  # Check if using Reality
  if jq -e '.inbounds[0].streamSettings.security == "reality"' "$V2RAY_CONFIG" > /dev/null; then
    # Get Reality settings
    local dest_site=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$V2RAY_CONFIG")
    local server_name="${dest_site%%:*}"
    local port=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG")
    local public_key=""
    
    # Try to get the public key
    if jq -e '.inbounds[0].streamSettings.realitySettings.publicKey' "$V2RAY_CONFIG" > /dev/null; then
      public_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$V2RAY_CONFIG")
    else
      # If no public key in config, try to get it from the keypair file
      if [ -f "${V2RAY_DIR}/reality_keypair.txt" ]; then
        public_key=$(grep "Public key:" "${V2RAY_DIR}/reality_keypair.txt" | awk '{print $3}')
      fi
    fi
    
    local short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$V2RAY_CONFIG")
    local fingerprint=$(jq -r '.inbounds[0].streamSettings.realitySettings.fingerprint' "$V2RAY_CONFIG")
    
    # Generate v2ray URI
    local v2ray_uri="vless://${uuid}@${server}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=${fingerprint}&pbk=${public_key}&sid=${short_id}#${name}"
    
    echo "=== VLESS Reality Client Configuration for: $name ==="
    echo ""
    echo "Server:      $server"
    echo "Port:        $port"
    echo "UUID:        $uuid"
    echo "Protocol:    VLESS"
    echo "Flow:        xtls-rprx-vision"
    echo "Security:    Reality"
    echo "SNI:         $server_name"
    echo "Fingerprint: $fingerprint"
    echo "Short ID:    $short_id"
    echo "Public Key:  $public_key"
    echo ""
    echo "URI for client apps:"
    echo "$v2ray_uri"
    echo ""
    echo "QR Code for v2ray client:"
    qrencode -t UTF8 "$v2ray_uri" || echo "(qrencode not installed, no QR code available)"
  else
    log_error "Non-Reality protocol configuration not supported by this tool"
  fi

  # Export Shadowsocks configuration
  log_info "Exporting Shadowsocks configuration for: $name"
  
  # Get Shadowsocks settings
  if [ -f "${OUTLINE_DIR}/data/$name/config.json" ]; then
    local ss_port=$(jq -r '.server_port' "${OUTLINE_CONFIG}")
    local ss_password=$(jq -r '.password' "${OUTLINE_DIR}/data/$name/config.json")
    local ss_method=$(jq -r '.method' "${OUTLINE_CONFIG}")
    local ss_plugin=$(jq -r '.plugin // "obfs-server"' "${OUTLINE_CONFIG}")
    local ss_plugin_opts=$(jq -r '.plugin_opts // "obfs=http"' "${OUTLINE_CONFIG}")
    
    # Generate Shadowsocks URI
    # Make plugin part compatible with client
    local plugin_client="${ss_plugin//-server/-local}"
    local ss_uri="ss://$(echo -n "${ss_method}:${ss_password}@${server}:${ss_port}" | base64 -w 0)?plugin=${plugin_client};${ss_plugin_opts}#${name}-Shadowsocks"
    
    echo "=== Shadowsocks Client Configuration for: $name ==="
    echo ""
    echo "Server:      $server"
    echo "Port:        $ss_port"
    echo "Password:    $ss_password"
    echo "Method:      $ss_method"
    echo "Plugin:      $plugin_client"
    echo "Plugin Opts: $ss_plugin_opts"
    echo ""
    echo "URI for Shadowsocks clients:"
    echo "$ss_uri"
    echo ""
    echo "QR Code for Shadowsocks client:"
    qrencode -t UTF8 "$ss_uri" || echo "(qrencode not installed, no QR code available)"
    
    # Export Outline client configuration (simplified format)
    echo ""
    echo "=== Outline Client Configuration ==="
    cat > "/tmp/outline-${name}.json" <<EOF
{
  "server": "${server}",
  "server_port": ${ss_port},
  "method": "${ss_method}",
  "password": "${ss_password}",
  "plugin": "${plugin_client}",
  "plugin_opts": "${ss_plugin_opts}",
  "remarks": "${name}",
  "timeout": 300
}
EOF
    echo "Configuration file saved to: /tmp/outline-${name}.json"
  else
    log_error "Shadowsocks configuration for user '$name' not found"
  fi
}

function restart_services() {
  log_info "Restarting VPN services..."
  
  # Check if Docker is running
  if ! command -v docker &> /dev/null || ! docker ps &> /dev/null; then
    log_error "Docker is not running or not accessible"
    exit 1
  fi
  
  # Restart containers
  cd "$BASE_DIR"
  if [ -f "docker-compose.yml" ]; then
    docker-compose restart
  else
    # Fallback to individual container restart
    docker restart outline-server v2ray
  fi
  
  log_success "VPN services restarted"
}

function parse_flags() {
  if [ $# -eq 0 ]; then
    display_usage
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list)
        OPERATION="list"
        shift
        ;;
      --add)
        OPERATION="add"
        shift
        ;;
      --remove)
        OPERATION="remove"
        shift
        ;;
      --export)
        OPERATION="export"
        shift
        ;;
      --name)
        if [[ -z "$2" || "$2" == --* ]]; then
          log_error "Error: --name requires an argument"
          display_usage
          exit 1
        fi
        NAME="$2"
        shift 2
        ;;
      --uuid)
        if [[ -z "$2" || "$2" == --* ]]; then
          log_error "Error: --uuid requires an argument"
          display_usage
          exit 1
        fi
        UUID="$2"
        shift 2
        ;;
      --password)
        if [[ -z "$2" || "$2" == --* ]]; then
          log_error "Error: --password requires an argument"
          display_usage
          exit 1
        fi
        PASSWORD="$2"
        shift 2
        ;;
      --help)
        display_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        display_usage
        exit 1
        ;;
    esac
  done
  
  # Validate operation requirements
  case "$OPERATION" in
    "add")
      if [ -z "$NAME" ]; then
        log_error "Error: --add requires --name"
        display_usage
        exit 1
      fi
      ;;
    "remove"|"export")
      if [ -z "$UUID" ]; then
        log_error "Error: --$OPERATION requires --uuid"
        display_usage
        exit 1
      fi
      ;;
  esac
}

function main() {
  check_dependencies
  parse_flags "$@"
  
  # Execute the requested operation
  case "$OPERATION" in
    "list")
      list_users
      ;;
    "add")
      add_user "$NAME" "$PASSWORD"
      ;;
    "remove")
      remove_user "$UUID"
      ;;
    "export")
      export_user_config "$UUID"
      ;;
    *)
      display_usage
      ;;
  esac
}

main "$@"