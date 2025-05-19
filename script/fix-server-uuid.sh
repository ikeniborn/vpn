#!/bin/bash

# ===================================================================
# Fix Server 2 Authentication to Server 1
# ===================================================================
# This script:
# - Adds a specific UUID to Server 1's client list to allow
#   Server 2 to authenticate successfully
# - Outputs the correct Reality public key and short ID from Server 1
#   that Server 2 should be using
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
V2RAY_DIR="/opt/v2ray"
SERVER2_UUID="9daf9658-2b84-4d23-9d07-cfac80499241"
SERVER2_NAME="server2-fixed"

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --uuid)
                SERVER2_UUID="$2"
                shift
                ;;
            --name)
                SERVER2_NAME="$2"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "This script adds a specific UUID to Server 1's client list to fix"
                echo "the 'context canceled' error when Server 2 connects."
                echo ""
                echo "Options:"
                echo "  --uuid UUID        UUID used by Server 2 (default: 9daf9658-2b84-4d23-9d07-cfac80499241)"
                echo "  --name NAME        Name for the Server 2 account (default: server2-fixed)"
                echo ""
                exit 0
                ;;
            *)
                warn "Unknown parameter: $1"
                ;;
        esac
        shift
    done

    # Verify UUID format
    if [[ ! "$SERVER2_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error "Invalid UUID format: $SERVER2_UUID"
    fi

    info "Using Server 2 UUID: $SERVER2_UUID"
    info "Using Server 2 name: $SERVER2_NAME"
}

# Add Server 2's UUID to Server 1's client list
add_server2_uuid() {
    info "Adding Server 2's UUID to Server 1's client list..."

    # Create a backup of the original config
    if [ -f "$V2RAY_DIR/config.json" ]; then
        cp "$V2RAY_DIR/config.json" "${V2RAY_DIR}/config.json.bak.$(date +%s)"
    else
        error "V2Ray configuration not found at $V2RAY_DIR/config.json"
    fi

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        info "Installing jq for JSON parsing..."
        apt-get update && apt-get install -y jq
    fi

    # Check if the UUID already exists in the client list
    local uuid_exists=$(jq --arg uuid "$SERVER2_UUID" '.inbounds[0].settings.clients[] | select(.id == $uuid) | .id' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
    
    if [ -n "$uuid_exists" ]; then
        info "UUID $SERVER2_UUID already exists in the client list"
    else
        info "Adding UUID $SERVER2_UUID to the client list..."
        local temp_config=$(mktemp)
        
        # Check if using Reality (flow field needed)
        if jq -e '.inbounds[0].streamSettings.security == "reality"' "$V2RAY_DIR/config.json" > /dev/null; then
            jq --arg uuid "$SERVER2_UUID" --arg name "$SERVER2_NAME" '.inbounds[0].settings.clients += [{"id": $uuid, "flow": "xtls-rprx-vision", "level": 0, "email": $name}]' "$V2RAY_DIR/config.json" > "$temp_config"
        else
            jq --arg uuid "$SERVER2_UUID" --arg name "$SERVER2_NAME" '.inbounds[0].settings.clients += [{"id": $uuid, "level": 0, "email": $name}]' "$V2RAY_DIR/config.json" > "$temp_config"
        fi
        
        # Check if jq command was successful
        if [ $? -ne 0 ]; then
            error "Failed to modify the config file"
            rm -f "$temp_config"
            exit 1
        fi
        
        # Replace the original config with the modified one
        mv "$temp_config" "$V2RAY_DIR/config.json"
        chmod 644 "$V2RAY_DIR/config.json"
        
        # Add to users database
        echo "$SERVER2_UUID|$SERVER2_NAME|$(date '+%Y-%m-%d %H:%M:%S')" >> "$V2RAY_DIR/users.db"
        
        info "UUID $SERVER2_UUID added to the client list"
    fi
}

# Restart v2ray to apply changes
restart_v2ray() {
    info "Restarting v2ray to apply changes..."
    
    if docker ps -a --format '{{.Names}}' | grep -q "^v2ray$"; then
        docker restart v2ray >/dev/null 2>&1 && info "v2ray container restarted successfully" || {
            warn "Failed to restart v2ray container"
            warn "Trying to start container if it's not running..."
            docker start v2ray >/dev/null 2>&1 || warn "Failed to start v2ray container"
        }
    else
        warn "v2ray container not found. Manually restart v2ray to apply changes."
    fi
}

# Get Reality parameters for Server 2
get_reality_params() {
    info "Getting Reality parameters that Server 2 should use..."
    
    local public_key=""
    local short_id=""
    
    # Try to get Reality public key and short ID from config
    if jq -e '.inbounds[0].streamSettings.realitySettings' "$V2RAY_DIR/config.json" > /dev/null; then
        public_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
        short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$V2RAY_DIR/config.json" 2>/dev/null || echo "")
    fi
    
    # If public key not found in config, try reality_keypair.txt file
    if [ -z "$public_key" ] && [ -f "$V2RAY_DIR/reality_keypair.txt" ]; then
        public_key=$(grep "Public key:" "$V2RAY_DIR/reality_keypair.txt" | awk '{print $3}' 2>/dev/null || echo "")
    fi
    
    echo "======================================================================="
    echo "Server 2 Configuration Parameters:"
    echo "======================================================================="
    echo "UUID: $SERVER2_UUID"
    
    if [ -n "$public_key" ]; then
        echo "Public Key: $public_key"
    else
        echo "Public Key: UNKNOWN - check $V2RAY_DIR/reality_keypair.txt manually"
    fi
    
    if [ -n "$short_id" ]; then
        echo "Short ID: $short_id"
    else
        echo "Short ID: UNKNOWN - check V2Ray configuration manually"
    fi
    echo "======================================================================="
    
    # Show mismatches with the values Server 2 is currently using
    local server2_public_key="699722a9514be470d107e9c0e60a03843b68c2be3c70f6496604e20f91d2b029"
    local server2_short_id="c78c1589e547b244"
    
    if [ -n "$public_key" ] && [ "$public_key" != "$server2_public_key" ]; then
        warn "MISMATCH: Server 2 is using different public key:"
        warn "  Server 2 using:       $server2_public_key"
        warn "  Server 1's actual key: $public_key"
        echo ""
        echo "  You need to update Server 2's configuration to use Server 1's public key."
        echo "  Edit Server 2's configuration in /opt/v2ray/config.json or run:"
        echo "  ./script/setup-vless-server2.sh with --server1-pubkey \"$public_key\""
    fi
    
    if [ -n "$short_id" ] && [ "$short_id" != "$server2_short_id" ]; then
        warn "MISMATCH: Server 2 is using different short ID:"
        warn "  Server 2 using:        $server2_short_id"
        warn "  Server 1's actual ID:  $short_id"
        echo ""
        echo "  You need to update Server 2's configuration to use Server 1's short ID."
        echo "  Edit Server 2's configuration in /opt/v2ray/config.json or run:"
        echo "  ./script/setup-vless-server2.sh with --server1-shortid \"$short_id\""
    fi
}

# Main function
main() {
    check_root
    parse_args "$@"
    add_server2_uuid
    restart_v2ray
    get_reality_params
    
    info "====================================================================="
    info "Server 2's UUID has been added to Server 1's configuration."
    info "Please check if Server 2 also needs to use the correct Reality"
    info "parameters (public key, short ID) from Server 1 as shown above."
    info "====================================================================="
}

main "$@"