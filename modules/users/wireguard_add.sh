#!/bin/bash
#################################################
# WireGuard User Addition Module
# 
# This module handles adding new users to the
# WireGuard VPN server with config and QR code
# generation
#
# Exported Functions:
#   - add_wireguard_user
#   - generate_wireguard_client_config
#   - generate_wireguard_qr_code
#################################################

set -euo pipefail

# Source required libraries
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/config.sh"
source "$(dirname "$0")/../../lib/crypto.sh"
source "$(dirname "$0")/../../lib/ui.sh"

# WireGuard constants
readonly WIREGUARD_DIR="/opt/wireguard"
readonly WIREGUARD_CONFIG_DIR="${WIREGUARD_DIR}/config"
readonly WIREGUARD_USERS_DIR="${WIREGUARD_DIR}/users"
readonly WIREGUARD_KEYS_DIR="${WIREGUARD_DIR}/keys"
readonly WIREGUARD_IMAGE="linuxserver/wireguard:latest"

get_next_client_ip() {
    local last_ip=1
    local server_config="${WIREGUARD_CONFIG_DIR}/wg0.conf"
    
    # Find the highest IP address already assigned
    if [[ -f "${server_config}" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ AllowedIPs[[:space:]]*=[[:space:]]*10\.66\.66\.([0-9]+)/32 ]]; then
                local ip="${BASH_REMATCH[1]}"
                if [[ $ip -gt $last_ip ]]; then
                    last_ip=$ip
                fi
            fi
        done < "${server_config}"
    fi
    
    # Return next available IP
    echo "$((last_ip + 1))"
}

generate_wireguard_client_keys() {
    local username="${1}"
    local client_dir="${WIREGUARD_USERS_DIR}/${username}"
    
    # Create user directory
    mkdir -p "${client_dir}"
    
    # Generate client private key
    local private_key=$(docker run --rm ${WIREGUARD_IMAGE} wg genkey)
    echo "${private_key}" > "${client_dir}/private_key"
    
    # Generate client public key
    local public_key=$(echo "${private_key}" | docker run --rm -i ${WIREGUARD_IMAGE} wg pubkey)
    echo "${public_key}" > "${client_dir}/public_key"
    
    # Generate preshared key for additional security
    local preshared_key=$(docker run --rm ${WIREGUARD_IMAGE} wg genpsk)
    echo "${preshared_key}" > "${client_dir}/preshared_key"
    
    # Set secure permissions
    chmod 600 "${client_dir}"/private_key
    chmod 600 "${client_dir}"/preshared_key
    chmod 644 "${client_dir}"/public_key
}

generate_wireguard_client_config() {
    local username="${1}"
    local client_ip="${2}"
    local client_dir="${WIREGUARD_USERS_DIR}/${username}"
    
    # Read keys
    local client_private_key=$(cat "${client_dir}/private_key")
    local client_preshared_key=$(cat "${client_dir}/preshared_key")
    local server_public_key=$(cat "${WIREGUARD_KEYS_DIR}/public_key")
    local server_port=$(cat "${WIREGUARD_DIR}/port.txt")
    local server_ip=$(get_public_ip)
    
    # Create client configuration
    cat > "${client_dir}/client.conf" << EOF
[Interface]
PrivateKey = ${client_private_key}
Address = 10.66.66.${client_ip}/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${server_public_key}
PresharedKey = ${client_preshared_key}
Endpoint = ${server_ip}:${server_port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    # Save client IP for reference
    echo "10.66.66.${client_ip}" > "${client_dir}/ip_address"
    
    log_success "Client configuration generated: ${client_dir}/client.conf"
}

add_client_to_server_config() {
    local username="${1}"
    local client_ip="${2}"
    local client_dir="${WIREGUARD_USERS_DIR}/${username}"
    local server_config="${WIREGUARD_CONFIG_DIR}/wg0.conf"
    
    # Read client keys
    local client_public_key=$(cat "${client_dir}/public_key")
    local client_preshared_key=$(cat "${client_dir}/preshared_key")
    
    # Add peer to server configuration
    cat >> "${server_config}" << EOF

# Client: ${username}
[Peer]
PublicKey = ${client_public_key}
PresharedKey = ${client_preshared_key}
AllowedIPs = 10.66.66.${client_ip}/32
EOF

    log_info "Added ${username} to server configuration"
}

generate_wireguard_qr_code() {
    local username="${1}"
    local client_dir="${WIREGUARD_USERS_DIR}/${username}"
    local client_config="${client_dir}/client.conf"
    local qr_file="${client_dir}/qr_code.png"
    
    if command_exists qrencode; then
        # Generate QR code
        qrencode -t png -o "${qr_file}" -r "${client_config}"
        log_success "QR code generated: ${qr_file}"
        
        # Also generate ASCII QR code for terminal display
        local ascii_qr="${client_dir}/qr_code.txt"
        qrencode -t ansiutf8 -o "${ascii_qr}" -r "${client_config}"
    else
        log_warning "qrencode not installed. Installing..."
        apt-get update && apt-get install -y qrencode
        if command_exists qrencode; then
            generate_wireguard_qr_code "${username}"
        else
            log_error "Failed to install qrencode"
        fi
    fi
}

reload_wireguard_config() {
    log_info "Reloading WireGuard configuration..."
    
    # Copy updated config to container
    docker cp "${WIREGUARD_CONFIG_DIR}/wg0.conf" wireguard:/config/wg0.conf
    
    # Reload configuration
    docker exec wireguard wg syncconf wg0 <(wg-quick strip wg0)
    
    log_success "WireGuard configuration reloaded"
}

add_wireguard_user() {
    local username="${1:-}"
    
    # Validate input
    if [[ -z "${username}" ]]; then
        log_error "Username is required"
        echo "Usage: add_wireguard_user <username>"
        return 1
    fi
    
    # Check if user already exists
    if [[ -d "${WIREGUARD_USERS_DIR}/${username}" ]]; then
        log_error "User ${username} already exists"
        return 1
    fi
    
    log_header "Adding WireGuard User: ${username}"
    
    # Get next available IP
    local client_ip=$(get_next_client_ip)
    log_info "Assigning IP: 10.66.66.${client_ip}"
    
    # Generate client keys
    log_info "Generating client keys..."
    generate_wireguard_client_keys "${username}"
    
    # Generate client configuration
    log_info "Creating client configuration..."
    generate_wireguard_client_config "${username}" "${client_ip}"
    
    # Add client to server config
    add_client_to_server_config "${username}" "${client_ip}"
    
    # Generate QR code
    generate_wireguard_qr_code "${username}"
    
    # Reload server configuration
    reload_wireguard_config
    
    # Display results
    display_banner "User Added Successfully"
    echo "Username: ${username}"
    echo "IP Address: 10.66.66.${client_ip}"
    echo "Configuration: ${WIREGUARD_USERS_DIR}/${username}/client.conf"
    echo "QR Code: ${WIREGUARD_USERS_DIR}/${username}/qr_code.png"
    echo ""
    echo "To display QR code in terminal:"
    echo "cat ${WIREGUARD_USERS_DIR}/${username}/qr_code.txt"
    
    # Save user info
    local user_info="${WIREGUARD_USERS_DIR}/${username}/info.json"
    cat > "${user_info}" << EOF
{
    "username": "${username}",
    "ip_address": "10.66.66.${client_ip}",
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "config_file": "client.conf",
    "qr_code": "qr_code.png"
}
EOF
}

# Export functions
export -f add_wireguard_user
export -f generate_wireguard_client_config
export -f generate_wireguard_qr_code

# Support direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        add)
            shift
            add_wireguard_user "$@"
            ;;
        *)
            echo "Usage: $0 add <username>"
            exit 1
            ;;
    esac
fi