#!/bin/bash
#
# Script to manage VLESS users for Outline VPN with Reality protocol
# This script allows listing, adding, removing, and exporting users

set -euo pipefail

# Default values
V2RAY_DIR="${V2RAY_DIR:-/opt/v2ray}"
V2RAY_CONFIG="${V2RAY_DIR}/config.json"
USERS_DB="${V2RAY_DIR}/users.db"
OPERATION=""
UUID=""
NAME=""

function log_error() {
  local -r ERROR_TEXT="\033[0;31m"  # red
  local -r NO_COLOR="\033[0m"
  echo -e "${ERROR_TEXT}$1${NO_COLOR}" >&2
}

function log_success() {
  local -r SUCCESS_TEXT="\033[0;32m"  # green
  local -r NO_COLOR="\033[0m"
  echo -e "${SUCCESS_TEXT}$1${NO_COLOR}"
}

function display_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Manage VLESS users for Outline VPN with Reality protocol.

Operations:
  --list                List all configured users
  --add --name NAME     Add a new user with the specified name
  --remove --uuid UUID  Remove a user with the specified UUID
  --export --uuid UUID  Export client configuration for a specific user

Options:
  --config PATH         Path to v2ray config file (default: /opt/v2ray/config.json)
  --help                Display this help message

Examples:
  $(basename "$0") --list
  $(basename "$0") --add --name "john-phone"
  $(basename "$0") --remove --uuid "123e4567-e89b-12d3-a456-426614174000"
EOF
}

function check_dependencies() {
  local missing_deps=()
  
  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${missing_deps[*]}"
    echo "Please install them using:"
    echo "sudo apt-get install ${missing_deps[*]}"
    exit 1
  fi
}

function list_users() {
  if [ ! -f "$V2RAY_CONFIG" ]; then
    log_error "Config file not found: $V2RAY_CONFIG"
    exit 1
  fi
  
  echo "=== VLESS Users ==="
  echo ""
  echo "UUID                                  Name                         Added"
  echo "------------------------------------------------------------------------------"
  
  # Check if the users database exists
  if [ -f "$USERS_DB" ]; then
    # Join data from config and database
    jq -r '.inbounds[0].settings.clients[] | .id' "$V2RAY_CONFIG" | while read -r uuid; do
      name=$(jq -r --arg uuid "$uuid" '.inbounds[0].settings.clients[] | select(.id == $uuid) | .email // "<unnamed>"' "$V2RAY_CONFIG")
      added=$(grep "$uuid" "$USERS_DB" | cut -d'|' -f3 || echo "unknown")
      printf "%-36s  %-28s  %s\n" "$uuid" "$name" "$added"
    done
  else
    # Just use config data
    jq -r '.inbounds[0].settings.clients[] | .id + "  " + (.email // "<unnamed>") + "  unknown"' "$V2RAY_CONFIG" | awk '{printf "%-36s  %-28s  %s\n", $1, $2, $3}'
  fi
  
  echo ""
  echo "Total users: $(jq '.inbounds[0].settings.clients | length' "$V2RAY_CONFIG")"
}

function add_user() {
  local name="$1"
  local uuid
  
  # Generate UUID for new user
  uuid=$(cat /proc/sys/kernel/random/uuid)
  
  # Create a backup of the original config
  cp "$V2RAY_CONFIG" "${V2RAY_CONFIG}.bak"
  
  # Add the new client to the config
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
    log_error "Failed to modify the config file"
    rm -f "$temp_config"
    exit 1
  fi
  
  # Replace the original config with the modified one
  mv "$temp_config" "$V2RAY_CONFIG"
  
  # Set appropriate permissions
  chmod 644 "$V2RAY_CONFIG"
  
  # Add to users database
  echo "$uuid|$name|$(date '+%Y-%m-%d %H:%M:%S')" >> "$USERS_DB"
  
  # Restart v2ray to apply changes
  restart_v2ray
  
  log_success "User '$name' added successfully with UUID: $uuid"
  echo "To generate a client configuration, run:"
  echo "  ./generate-vless-client.sh --name \"$name\""
}

function remove_user() {
  local uuid="$1"
  
  # Check if user exists
  if ! jq -e ".inbounds[0].settings.clients[] | select(.id == \"$uuid\")" "$V2RAY_CONFIG" > /dev/null; then
    log_error "User with UUID '$uuid' not found"
    exit 1
  fi
  
  # Get user name before removing
  local name
  name=$(jq -r --arg uuid "$uuid" '.inbounds[0].settings.clients[] | select(.id == $uuid) | .email // "<unnamed>"' "$V2RAY_CONFIG")
  
  # Create a backup of the original config
  cp "$V2RAY_CONFIG" "${V2RAY_CONFIG}.bak"
  
  # Remove the client from the config
  local temp_config
  temp_config=$(mktemp)
  jq --arg uuid "$uuid" '.inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != $uuid)]' "$V2RAY_CONFIG" > "$temp_config"
  
  # Check if jq command was successful
  if [ $? -ne 0 ]; then
    log_error "Failed to modify the config file"
    rm -f "$temp_config"
    exit 1
  fi
  
  # Replace the original config with the modified one
  mv "$temp_config" "$V2RAY_CONFIG"
  
  # Set appropriate permissions
  chmod 644 "$V2RAY_CONFIG"
  
  # Update users database if it exists
  if [ -f "$USERS_DB" ]; then
    grep -v "$uuid" "$USERS_DB" > "${USERS_DB}.tmp"
    mv "${USERS_DB}.tmp" "$USERS_DB"
  fi
  
  # Restart v2ray to apply changes
  restart_v2ray
  
  log_success "User '$name' with UUID '$uuid' removed successfully"
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
  
  # Get port
  local port
  port=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG")
  
  # Check if using Reality
  if jq -e '.inbounds[0].streamSettings.security == "reality"' "$V2RAY_CONFIG" > /dev/null; then
    # Get Reality settings
    local dest_site=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$V2RAY_CONFIG")
    local server_name="${dest_site%%:*}"
    local public_key
    
    # Try to get the public key
    if jq -e '.inbounds[0].streamSettings.realitySettings.publicKey' "$V2RAY_CONFIG" > /dev/null; then
      public_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$V2RAY_CONFIG")
    else
      # If no public key in config, try to get it from the keypair file
      if [ -f "${V2RAY_DIR}/reality_keypair.txt" ]; then
        public_key=$(grep "Public key:" "${V2RAY_DIR}/reality_keypair.txt" | awk '{print $3}')
      else
        # If no public key, we'll need to compute it from the private key
        local private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$V2RAY_CONFIG")
        
        # Use docker to compute the public key
        public_key=$(docker run --rm v2fly/v2fly-core:latest xray x25519 -i "$private_key" | grep "Public key:" | cut -d' ' -f3)
      fi
    fi
    
    local short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$V2RAY_CONFIG")
    local fingerprint=$(jq -r '.inbounds[0].streamSettings.realitySettings.fingerprint' "$V2RAY_CONFIG")
    
    # Generate URI
    local uri="vless://${uuid}@${server}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=${fingerprint}&pbk=${public_key}&sid=${short_id}#${name}"
    
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
    echo "$uri"
    echo ""
    echo "Save this as $name.txt or scan QR code with client app:"
    echo ""
    
    # Generate QR code if qrencode is available
    if command -v qrencode &> /dev/null; then
      qrencode -t UTF8 "$uri"
    else
      echo "(qrencode not installed, no QR code available)"
    fi
  else
    log_error "Non-Reality protocol configuration not supported by this tool"
    exit 1
  fi
}

function restart_v2ray() {
  echo "Restarting v2ray container..."
  if docker ps -a --format '{{.Names}}' | grep -q "^v2ray$"; then
    docker restart v2ray >/dev/null 2>&1 && echo "v2ray container restarted successfully" || {
      log_error "Failed to restart v2ray container"
      exit 1
    }
  else
    log_error "v2ray container not found"
    exit 1
  fi
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
      --config)
        if [[ -z "$2" || "$2" == --* ]]; then
          log_error "Error: --config requires an argument"
          display_usage
          exit 1
        fi
        V2RAY_CONFIG="$2"
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
      add_user "$NAME"
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