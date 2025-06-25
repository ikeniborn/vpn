#!/bin/bash
#################################################
# WireGuard Installation Module for VPN Server
# 
# This module handles the installation and setup
# of WireGuard VPN server with Docker deployment
#
# Exported Functions:
#   - install_wireguard_server
#   - configure_wireguard_firewall
#   - generate_wireguard_keys
#   - create_wireguard_config
#################################################

set -euo pipefail

# Source required libraries
source "$(dirname "$0")/../../lib/common.sh"
source "$(dirname "$0")/../../lib/config.sh"
source "$(dirname "$0")/../../lib/docker.sh"
source "$(dirname "$0")/../../lib/network.sh"
source "$(dirname "$0")/../../lib/crypto.sh"
source "$(dirname "$0")/../../lib/ui.sh"

# WireGuard specific constants
readonly WIREGUARD_DIR="/opt/wireguard"
readonly WIREGUARD_CONFIG_DIR="${WIREGUARD_DIR}/config"
readonly WIREGUARD_USERS_DIR="${WIREGUARD_DIR}/users"
readonly WIREGUARD_KEYS_DIR="${WIREGUARD_DIR}/keys"
readonly WIREGUARD_PORT_FILE="${WIREGUARD_DIR}/port.txt"
readonly WIREGUARD_SUBNET="10.66.66.0/24"
readonly WIREGUARD_SERVER_IP="10.66.66.1"
readonly WIREGUARD_DNS="1.1.1.1,8.8.8.8"
readonly WIREGUARD_IMAGE="linuxserver/wireguard:latest"

generate_wireguard_keys() {
    local private_key public_key
    
    log_info "Generating WireGuard server keys..."
    
    # Create keys directory
    mkdir -p "${WIREGUARD_KEYS_DIR}"
    
    # Generate private key
    private_key=$(docker run --rm ${WIREGUARD_IMAGE} wg genkey)
    echo "${private_key}" > "${WIREGUARD_KEYS_DIR}/private_key"
    
    # Generate public key
    public_key=$(echo "${private_key}" | docker run --rm -i ${WIREGUARD_IMAGE} wg pubkey)
    echo "${public_key}" > "${WIREGUARD_KEYS_DIR}/public_key"
    
    # Set secure permissions
    chmod 600 "${WIREGUARD_KEYS_DIR}"/private_key
    chmod 644 "${WIREGUARD_KEYS_DIR}"/public_key
    
    log_success "WireGuard keys generated successfully"
}

create_wireguard_config() {
    local port="${1}"
    local private_key=$(cat "${WIREGUARD_KEYS_DIR}/private_key")
    local public_ip=$(get_public_ip)
    
    log_info "Creating WireGuard server configuration..."
    
    # Create main configuration file
    cat > "${WIREGUARD_CONFIG_DIR}/wg0.conf" << EOF
[Interface]
Address = ${WIREGUARD_SERVER_IP}/24
ListenPort = ${port}
PrivateKey = ${private_key}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth+ -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth+ -j MASQUERADE

# Clients will be added here dynamically
EOF

    # Store port for future reference
    echo "${port}" > "${WIREGUARD_PORT_FILE}"
    
    # Create docker-compose.yml
    cat > "${WIREGUARD_DIR}/docker-compose.yml" << EOF
version: '3.8'

services:
  wireguard:
    image: ${WIREGUARD_IMAGE}
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - SERVERPORT=${port}
      - SERVERURL=${public_ip}
      - PEERS=0
      - PEERDNS=${WIREGUARD_DNS}
      - INTERNAL_SUBNET=${WIREGUARD_SUBNET}
      - ALLOWEDIPS=0.0.0.0/0
      - LOG_CONFS=false
    volumes:
      - ${WIREGUARD_CONFIG_DIR}:/config
      - /lib/modules:/lib/modules:ro
    ports:
      - ${port}:${port}/udp
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
    restart: unless-stopped
    networks:
      - wireguard_net

networks:
  wireguard_net:
    driver: bridge

EOF
    
    log_success "WireGuard configuration created"
}

configure_wireguard_firewall() {
    local port="${1}"
    
    log_info "Configuring firewall for WireGuard..."
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
    
    # Configure UFW
    ufw allow ${port}/udp comment "WireGuard VPN"
    
    # Add UFW before rules for NAT
    local ufw_before_rules="/etc/ufw/before.rules"
    if ! grep -q "WireGuard NAT" "${ufw_before_rules}"; then
        # Backup original file
        cp "${ufw_before_rules}" "${ufw_before_rules}.backup"
        
        # Add NAT rules
        cat >> "${ufw_before_rules}" << EOF

# WireGuard NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${WIREGUARD_SUBNET} -o eth0 -j MASQUERADE
COMMIT
EOF
    fi
    
    # Enable UFW forwarding
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    
    # Reload UFW
    ufw reload
    
    log_success "Firewall configured for WireGuard"
}

install_wireguard_server() {
    log_header "Starting WireGuard Server Installation"
    
    # Check if already installed
    if [[ -d "${WIREGUARD_DIR}" ]] && docker ps | grep -q wireguard; then
        log_error "WireGuard server is already installed"
        return 1
    fi
    
    # Create directory structure
    log_info "Creating WireGuard directory structure..."
    mkdir -p "${WIREGUARD_CONFIG_DIR}"
    mkdir -p "${WIREGUARD_USERS_DIR}"
    mkdir -p "${WIREGUARD_KEYS_DIR}"
    
    # Generate server keys
    generate_wireguard_keys
    
    # Get available port
    local port=$(find_available_port 51820 51900)
    log_info "Selected port: ${port}"
    
    # Create configuration
    create_wireguard_config "${port}"
    
    # Configure firewall
    configure_wireguard_firewall "${port}"
    
    # Start WireGuard container
    log_info "Starting WireGuard container..."
    cd "${WIREGUARD_DIR}"
    docker-compose up -d
    
    # Wait for container to be ready
    log_info "Waiting for WireGuard to start..."
    sleep 5
    
    # Verify installation
    if docker ps | grep -q wireguard; then
        log_success "WireGuard server installed successfully!"
        
        # Display installation summary
        display_banner "WireGuard Installation Complete"
        echo "Server IP: $(get_public_ip)"
        echo "Port: ${port}"
        echo "Subnet: ${WIREGUARD_SUBNET}"
        echo "Configuration: ${WIREGUARD_CONFIG_DIR}"
        echo ""
        echo "Use the VPN management script to add users:"
        echo "sudo ./vpn.sh"
        
        # Save installation info
        save_installation_info "wireguard" "${port}"
    else
        log_error "Failed to start WireGuard container"
        docker-compose logs wireguard
        return 1
    fi
}

# Export functions
export -f install_wireguard_server
export -f configure_wireguard_firewall
export -f generate_wireguard_keys
export -f create_wireguard_config

# Support direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        install)
            install_wireguard_server
            ;;
        *)
            echo "Usage: $0 {install}"
            exit 1
            ;;
    esac
fi