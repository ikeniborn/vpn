#!/bin/bash

# VPN Project Outline VPN Installation Module
# Handles Outline VPN server installation and configuration
# Based on https://github.com/EricQmore/outline-vpn-arm

# Source required libraries
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/../../lib/docker.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../../lib/docker.sh"
else
    echo "Error: docker.sh not found" >&2
    exit 1
fi

if [ -f "$(dirname "${BASH_SOURCE[0]}")/firewall.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/firewall.sh"
else
    echo "Error: firewall.sh not found" >&2
    exit 1
fi

# ========================= OUTLINE SETUP =========================

# Detect system architecture
get_system_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get appropriate watchtower image for architecture
get_watchtower_image() {
    local arch=$(get_system_architecture)
    case $arch in
        arm64)
            echo "ken1029/watchtower:arm64"
            ;;
        armv7)
            echo "ken1029/watchtower:arm32"
            ;;
        *)
            echo "containrrr/watchtower:latest"
            ;;
    esac
}

# Generate random port
get_random_port() {
    local num=0
    until (( 1024 <= num && num < 65536)); do
        num=$(( $RANDOM + ($RANDOM % 2) * 32768 ))
    done
    echo $num
}

# Generate URL-safe base64
safe_base64() {
    local url_safe="$(base64 -w 0 - | tr '/+' '_-')"
    echo -n "${url_safe%%=*}"  # Strip trailing = chars
}

# Setup Outline VPN directories
setup_outline_directories() {
    local base_dir="${1:-$OUTLINE_DIR}"
    local debug="${2:-false}"
    
    [ "$debug" = true ] && log "Setting up Outline directories in $base_dir..."
    
    # Create base directory with correct permissions
    mkdir -p --mode=770 "$base_dir"
    chmod u+s "$base_dir"
    
    # Create persistent state directory
    local state_dir="$base_dir/persisted-state"
    mkdir -p --mode=770 "$state_dir"
    chmod g+s "$state_dir"
    
    [ "$debug" = true ] && log "Outline directories created successfully"
    return 0
}

# Generate Outline configuration
generate_outline_config() {
    local state_dir="${1:-$OUTLINE_DIR/persisted-state}"
    local api_port="${2:-$OUTLINE_API_PORT}"
    local keys_port="${3:-$SERVER_PORT}"
    local debug="${4:-false}"
    
    [ "$debug" = true ] && log "Generating Outline configuration..."
    
    # Generate API secret key (16 bytes = 128 bits)
    local api_prefix=$(head -c 16 /dev/urandom | safe_base64)
    export SB_API_PREFIX="$api_prefix"
    
    # Write server config if keys port is specified
    if [[ $keys_port != 0 ]]; then
        echo "{\"portForNewAccessKeys\":$keys_port}" > "$state_dir/shadowbox_server_config.json"
    fi
    
    # Save configuration
    echo "$api_prefix" > "$OUTLINE_DIR/api_prefix.txt"
    echo "$api_port" > "$OUTLINE_DIR/api_port.txt"
    
    [ "$debug" = true ] && log "Outline configuration generated"
    return 0
}

# Generate Outline SSL certificates
generate_outline_certificates() {
    local state_dir="${1:-$OUTLINE_DIR/persisted-state}"
    local hostname="${2:-$SERVER_IP}"
    local debug="${3:-false}"
    
    [ "$debug" = true ] && log "Generating Outline SSL certificates..."
    
    # Certificate paths
    local cert_name="${state_dir}/shadowbox-selfsigned"
    export SB_CERTIFICATE_FILE="${cert_name}.crt"
    export SB_PRIVATE_KEY_FILE="${cert_name}.key"
    
    # Generate self-signed certificate
    declare -a openssl_flags=(
        -x509 -nodes -days 36500 -newkey rsa:2048
        -subj "/CN=${hostname}"
        -keyout "${SB_PRIVATE_KEY_FILE}"
        -out "${SB_CERTIFICATE_FILE}"
    )
    
    if ! openssl req "${openssl_flags[@]}" >/dev/null 2>&1; then
        error "Failed to generate SSL certificate"
        return 1
    fi
    
    # Generate certificate fingerprint
    local cert_fingerprint=$(openssl x509 -in "${SB_CERTIFICATE_FILE}" -noout -sha256 -fingerprint)
    local cert_hex=$(echo ${cert_fingerprint#*=} | tr --delete :)
    echo "certSha256:$cert_hex" >> "$OUTLINE_DIR/access.txt"
    
    [ "$debug" = true ] && log "Outline SSL certificates generated"
    return 0
}

# Start Outline container
start_outline_container() {
    local state_dir="${1:-$OUTLINE_DIR/persisted-state}"
    local api_port="${2:-$OUTLINE_API_PORT}"
    local hostname="${3:-$SERVER_IP}"
    local debug="${4:-false}"
    
    [ "$debug" = true ] && log "Starting Outline container..."
    
    # Docker run flags
    declare -a docker_flags=(
        --name shadowbox
        --restart=always
        --net=host
        -v "${state_dir}:${state_dir}"
        -e "SB_STATE_DIR=${state_dir}"
        -e "SB_PUBLIC_IP=${hostname}"
        -e "SB_API_PORT=${api_port}"
        -e "SB_API_PREFIX=${SB_API_PREFIX}"
        -e "SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}"
        -e "SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}"
        -e "SB_DEFAULT_SERVER_NAME=${SB_DEFAULT_SERVER_NAME:-Outline Server}"
    )
    
    # Check if container already exists
    if docker ps -a | grep -q shadowbox; then
        log "Removing existing shadowbox container..."
        docker rm -f shadowbox > /dev/null 2>&1
    fi
    
    # Start container
    local image="quay.io/outline/shadowbox:stable"
    if ! docker run -d "${docker_flags[@]}" "$image" > /dev/null 2>&1; then
        error "Failed to start Outline container"
        return 1
    fi
    
    [ "$debug" = true ] && log "Outline container started"
    return 0
}

# Start Watchtower for automatic updates
start_watchtower() {
    local debug="${1:-false}"
    
    [ "$debug" = true ] && log "Starting Watchtower..."
    
    # Get appropriate image for architecture
    local watchtower_image=$(get_watchtower_image)
    local refresh_seconds="${WATCHTOWER_REFRESH_SECONDS:-3600}"
    
    # Check if watchtower already exists
    if docker ps -a | grep -q watchtower; then
        log "Removing existing watchtower container..."
        docker rm -f watchtower > /dev/null 2>&1
    fi
    
    # Start watchtower
    declare -a watchtower_flags=(
        --name watchtower
        --restart=always
        -v /var/run/docker.sock:/var/run/docker.sock
    )
    
    if ! docker run -d "${watchtower_flags[@]}" "$watchtower_image" \
        --cleanup --tlsverify --interval "$refresh_seconds" > /dev/null 2>&1; then
        warning "Failed to start Watchtower (non-critical)"
    else
        [ "$debug" = true ] && log "Watchtower started"
    fi
    
    return 0
}

# Wait for Outline API to be ready
wait_for_outline_api() {
    local api_url="${1}"
    local debug="${2:-false}"
    
    [ "$debug" = true ] && log "Waiting for Outline API to be ready..."
    
    local retries=0
    until curl --insecure -s "${api_url}/access-keys" >/dev/null 2>&1; do
        sleep 1
        retries=$((retries + 1))
        if [ $retries -gt 60 ]; then
            error "Outline API did not become ready within timeout"
            return 1
        fi
    done
    
    [ "$debug" = true ] && log "Outline API is ready"
    return 0
}

# Create first access key and display results
create_first_access_key() {
    local api_url="${1}"
    local debug="${2:-false}"
    
    [ "$debug" = true ] && log "Creating first access key..."
    
    # Create first user
    curl --insecure -X POST -s "${api_url}/access-keys" >/dev/null 2>&1
    
    return 0
}

# Check firewall status
check_outline_firewall() {
    local api_url="${1}"
    local public_api_url="${2}"
    local api_port="${3}"
    local debug="${4:-false}"
    
    [ "$debug" = true ] && log "Checking firewall status..."
    
    # Get access key port from first user
    local access_key_port=$(curl --insecure -s "${api_url}/access-keys" | \
        docker exec -i shadowbox node -e '
            const fs = require("fs");
            const accessKeys = JSON.parse(fs.readFileSync(0, {encoding: "utf-8"}));
            console.log(accessKeys["accessKeys"][0]["port"]);
        ' 2>/dev/null || echo "")
    
    local firewall_status=""
    if ! curl --max-time 5 --cacert "${SB_CERTIFICATE_FILE}" -s "${public_api_url}/access-keys" >/dev/null 2>&1; then
        firewall_status="BLOCKED
You won't be able to access it externally, despite your server being correctly
set up, because there's a firewall (in this machine, your router or cloud
provider) that is preventing incoming connections to ports ${api_port} and ${access_key_port}."
    else
        firewall_status="If you have connection problems, it may be that your router or cloud provider
blocks inbound connections, even though your machine seems to allow them."
    fi
    
    if [ -n "$access_key_port" ]; then
        firewall_status="${firewall_status}

Make sure to open the following ports on your firewall, router or cloud provider:
- Management port ${api_port}, for TCP
- Access key port ${access_key_port}, for TCP and UDP"
    fi
    
    echo "$firewall_status"
    return 0
}

# Display installation results
display_outline_results() {
    local access_file="${1}"
    local public_api_url="${2}"
    local firewall_status="${3}"
    
    # Get certificate fingerprint
    local cert_sha256=$(grep "certSha256" "$access_file" | sed "s/certSha256://")
    
    # Display results
    cat <<EOF

${GREEN}CONGRATULATIONS! Your Outline server is up and running.${NC}

To manage your Outline server, please copy the following line (including curly
brackets) into Step 2 of the Outline Manager interface:

$(echo -e "${GREEN}{\"apiUrl\":\"${public_api_url}\",\"certSha256\":\"${cert_sha256}\"}${NC}")

${firewall_status}

${YELLOW}Download Outline Manager:${NC}
${WHITE}https://getoutline.org/get-started/#step-1${NC}
EOF
    
    # Save management info
    ensure_dir "$OUTLINE_DIR/management"
    echo "{\"apiUrl\":\"${public_api_url}\",\"certSha256\":\"${cert_sha256}\"}" > "$OUTLINE_DIR/management/config.json"
}

# Install Outline VPN server
install_outline_server() {
    local debug="${1:-false}"
    
    log "Starting Outline VPN server installation..."
    
    # Check architecture compatibility
    local arch=$(get_system_architecture)
    if [ "$arch" = "unknown" ]; then
        warning "Unknown architecture: $(uname -m). Installation may fail."
    fi
    
    # Setup directories
    setup_outline_directories "$OUTLINE_DIR" "$debug" || {
        error "Failed to setup Outline directories"
        return 1
    }
    
    # Set API port
    local api_port="${OUTLINE_API_PORT}"
    if [[ $api_port == 0 ]]; then
        api_port=$(get_random_port)
    fi
    
    # Clear and initialize access file
    local access_file="$OUTLINE_DIR/access.txt"
    [[ -f $access_file ]] && cp "$access_file" "${access_file}.bak"
    > "$access_file"
    
    # Generate configuration
    generate_outline_config "$OUTLINE_DIR/persisted-state" "$api_port" "$SERVER_PORT" "$debug" || {
        error "Failed to generate Outline configuration"
        return 1
    }
    
    # Generate certificates
    generate_outline_certificates "$OUTLINE_DIR/persisted-state" "$SERVER_IP" "$debug" || {
        error "Failed to generate certificates"
        return 1
    }
    
    # Start Outline container
    start_outline_container "$OUTLINE_DIR/persisted-state" "$api_port" "$SERVER_IP" "$debug" || {
        error "Failed to start Outline container"
        return 1
    }
    
    # Start Watchtower for auto-updates
    start_watchtower "$debug"
    
    # Configure URLs
    local public_api_url="https://${SERVER_IP}:${api_port}/${SB_API_PREFIX}"
    local local_api_url="https://localhost:${api_port}/${SB_API_PREFIX}"
    
    # Add API URL to config
    echo "apiUrl:${public_api_url}" >> "$access_file"
    
    # Wait for API to be ready
    wait_for_outline_api "$local_api_url" "$debug" || {
        error "Outline API failed to start"
        return 1
    }
    
    # Create first access key
    create_first_access_key "$local_api_url" "$debug"
    
    # Configure firewall
    setup_outline_firewall "$api_port" "$SERVER_PORT" "$OUTLINE_DIR/backup" "$debug" || {
        error "Failed to configure firewall"
        return 1
    }
    
    # Check firewall status
    local firewall_status=$(check_outline_firewall "$local_api_url" "$public_api_url" "$api_port" "$debug")
    
    # Display results
    display_outline_results "$access_file" "$public_api_url" "$firewall_status"
    
    log "Outline VPN server installation completed successfully!"
    return 0
}

# Export functions
export -f setup_outline_directories
export -f generate_outline_config
export -f generate_outline_certificates
export -f start_outline_container
export -f start_watchtower
export -f wait_for_outline_api
export -f create_first_access_key
export -f check_outline_firewall
export -f display_outline_results
export -f install_outline_server
export -f get_system_architecture
export -f get_watchtower_image
export -f get_random_port
export -f safe_base64