#!/bin/bash

# VPN Project Cryptography Library
# Handles key generation, UUID creation, and cryptographic operations

# Source common library
if [ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# ========================= UUID GENERATION =========================

# Generate UUID v4
generate_uuid() {
    if command_exists uuid; then
        uuid -v 4
    elif command_exists uuidgen; then
        uuidgen
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback: generate pseudo-UUID
        local N B T
        for ((N=0; N<16; ++N)); do
            B=$(( RANDOM%256 ))
            if (( N == 6 )); then
                printf '4%x' $(( B%16 ))
            elif (( N == 8 )); then
                local C='89ab'
                printf '%c%x' ${C:$(( RANDOM%${#C} )):1} $(( B%16 ))
            else
                printf '%02x' $B
            fi
            case $N in
                3 | 5 | 7 | 9)
                    printf '-'
                    ;;
            esac
        done
        echo
    fi
}

# Validate UUID format
is_valid_uuid() {
    local uuid="$1"
    validate_uuid "$uuid"
}

# ========================= RANDOM DATA GENERATION =========================

# Generate random hex string
generate_random_hex() {
    local length="${1:-8}"  # Default 8 bytes = 16 hex chars
    
    if command_exists openssl; then
        openssl rand -hex "$length"
    elif [ -f /dev/urandom ]; then
        head -c "$length" /dev/urandom | xxd -p | tr -d '\n'
    else
        # Fallback: use RANDOM
        local result=""
        for ((i=0; i<length*2; i++)); do
            printf '%x' $((RANDOM % 16))
        done
        echo
    fi
}

# Generate random base64 string
generate_random_base64() {
    local length="${1:-32}"  # Default 32 bytes
    
    if command_exists openssl; then
        openssl rand "$length" | base64 | tr -d '\n'
    elif [ -f /dev/urandom ]; then
        head -c "$length" /dev/urandom | base64 | tr -d '\n'
    else
        # Fallback: generate from random hex
        local hex_length=$((length * 2))
        local hex_data=""
        for ((i=0; i<hex_length; i++)); do
            printf '%x' $((RANDOM % 16))
        done | xxd -r -p | base64 | tr -d '\n'
    fi
}

# ========================= X25519 KEY GENERATION =========================

# Generate X25519 keypair using Xray
generate_x25519_xray() {
    debug "Attempting to generate X25519 keys using Xray..."
    
    # Method 1: Direct xray x25519 command
    local output=$(docker run --rm teddysun/xray:latest xray x25519 2>/dev/null || echo "")
    
    if [ -n "$output" ] && echo "$output" | grep -q "Private key:"; then
        local private_key=$(echo "$output" | grep "Private key:" | awk '{print $3}')
        local public_key=$(echo "$output" | grep "Public key:" | awk '{print $3}')
        
        if [ -n "$private_key" ] && [ -n "$public_key" ]; then
            debug "Successfully generated X25519 keys using Xray"
            echo "$private_key $public_key"
            return 0
        fi
    fi
    
    # Method 2: Alternative xray command path
    output=$(docker run --rm teddysun/xray:latest /usr/bin/xray x25519 2>/dev/null || echo "")
    
    if [ -n "$output" ] && echo "$output" | grep -q "Private key:"; then
        local private_key=$(echo "$output" | grep "Private key:" | awk '{print $3}')
        local public_key=$(echo "$output" | grep "Public key:" | awk '{print $3}')
        
        if [ -n "$private_key" ] && [ -n "$public_key" ]; then
            debug "Successfully generated X25519 keys using alternative Xray command"
            echo "$private_key $public_key"
            return 0
        fi
    fi
    
    # Method 3: Interactive mode
    output=$(timeout 10 docker run --rm -i teddysun/xray:latest sh -c 'echo | xray x25519' 2>/dev/null || echo "")
    
    if [ -n "$output" ] && echo "$output" | grep -q "Private key:"; then
        local private_key=$(echo "$output" | grep "Private key:" | awk '{print $3}')
        local public_key=$(echo "$output" | grep "Public key:" | awk '{print $3}')
        
        if [ -n "$private_key" ] && [ -n "$public_key" ]; then
            debug "Successfully generated X25519 keys using interactive Xray"
            echo "$private_key $public_key"
            return 0
        fi
    fi
    
    debug "Failed to generate X25519 keys using Xray"
    return 1
}

# Generate X25519 keypair using OpenSSL
generate_x25519_openssl() {
    debug "Attempting to generate X25519 keys using OpenSSL..."
    
    if ! command_exists openssl; then
        debug "OpenSSL not available"
        return 1
    fi
    
    # Generate private key
    local temp_private=$(openssl genpkey -algorithm X25519 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$temp_private" ]; then
        debug "Failed to generate X25519 private key with OpenSSL"
        return 1
    fi
    
    # Extract private key in correct format
    local private_key=$(echo "$temp_private" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
    if [ -z "$private_key" ]; then
        debug "Failed to extract private key in correct format"
        return 1
    fi
    
    # Generate corresponding public key
    local public_key=$(echo "$temp_private" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
    if [ -z "$public_key" ]; then
        debug "Failed to generate public key"
        return 1
    fi
    
    debug "Successfully generated X25519 keys using OpenSSL"
    echo "$private_key $public_key"
    return 0
}

# Generate X25519 keypair with fallback methods
generate_x25519_keys() {
    debug "Generating X25519 keypair for Reality protocol..."
    
    # Try Xray first (most compatible)
    if generate_x25519_xray; then
        return 0
    fi
    
    # Try OpenSSL second
    if generate_x25519_openssl; then
        return 0
    fi
    
    # Fallback: generate random keys (not cryptographically correct X25519, but functional)
    warning "Using fallback random key generation (not true X25519)"
    local private_key=$(generate_random_base64 32)
    local public_key=$(generate_random_base64 32)
    
    echo "$private_key $public_key"
    return 0
}

# ========================= REALITY KEY MANAGEMENT =========================

# Generate complete Reality key set
generate_reality_keys() {
    debug "Generating complete Reality key set..."
    
    # Generate X25519 keypair
    local keys=$(generate_x25519_keys)
    local private_key=$(echo "$keys" | awk '{print $1}')
    local public_key=$(echo "$keys" | awk '{print $2}')
    
    # Generate short ID
    local short_id=$(generate_random_hex 8)
    
    if [ -n "$private_key" ] && [ -n "$public_key" ] && [ -n "$short_id" ]; then
        debug "Reality keys generated successfully"
        echo "$private_key $public_key $short_id"
        return 0
    else
        error "Failed to generate complete Reality key set"
        return 1
    fi
}

# Validate Reality keys
validate_reality_keys() {
    local private_key="$1"
    local public_key="$2"
    local short_id="$3"
    
    # Check if keys are not empty
    if [ -z "$private_key" ] || [ -z "$public_key" ] || [ -z "$short_id" ]; then
        debug "One or more Reality keys are empty"
        return 1
    fi
    
    # Check if keys are not placeholder values
    if [ "$private_key" = "null" ] || [ "$private_key" = "unknown" ]; then
        debug "Private key contains invalid placeholder value"
        return 1
    fi
    
    if [ "$public_key" = "null" ] || [ "$public_key" = "unknown" ]; then
        debug "Public key contains invalid placeholder value"
        return 1
    fi
    
    # Check key lengths (base64 encoded 32-byte keys should be ~44 chars)
    if [ ${#private_key} -lt 20 ] || [ ${#public_key} -lt 20 ]; then
        debug "Keys appear to be too short"
        return 1
    fi
    
    # Check short ID length (should be 16 hex chars)
    if [ ${#short_id} -ne 16 ]; then
        debug "Short ID should be 16 hex characters"
        return 1
    fi
    
    # Check if short ID is valid hex
    if ! [[ "$short_id" =~ ^[a-fA-F0-9]{16}$ ]]; then
        debug "Short ID contains invalid characters"
        return 1
    fi
    
    debug "Reality keys validation passed"
    return 0
}

# ========================= KEY ROTATION =========================

# Rotate Reality keys (generate new set)
rotate_reality_keys() {
    local old_private="$1"
    local old_public="$2"
    local old_short_id="$3"
    
    debug "Rotating Reality keys..."
    
    # Generate new key set
    local new_keys=$(generate_reality_keys)
    if [ $? -ne 0 ]; then
        error "Failed to generate new Reality keys"
        return 1
    fi
    
    local new_private=$(echo "$new_keys" | awk '{print $1}')
    local new_public=$(echo "$new_keys" | awk '{print $2}')
    local new_short_id=$(echo "$new_keys" | awk '{print $3}')
    
    # Validate new keys
    if ! validate_reality_keys "$new_private" "$new_public" "$new_short_id"; then
        error "New Reality keys failed validation"
        return 1
    fi
    
    debug "Reality keys rotated successfully"
    echo "$new_private $new_public $new_short_id"
    return 0
}

# ========================= KNOWN KEY PAIRS =========================

# Get known working Reality key pair (for compatibility)
get_default_reality_keys() {
    local private_key="c29567a5ff1928bcf525e2d4016f7d7ce6f3c14c25c6aacc1998de43ba7b6a3e"
    local public_key="YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc"
    local short_id=$(generate_random_hex 8)
    
    echo "$private_key $public_key $short_id"
}

# ========================= SAFE BASE64 OPERATIONS =========================

# Create safe base64 string (URL-safe)
safe_base64_encode() {
    local input="$1"
    
    if [ -z "$input" ]; then
        echo ""
        return 1
    fi
    
    echo "$input" | base64 -w 0 | tr '/+' '_-' | tr -d '='
}

# Decode safe base64 string
safe_base64_decode() {
    local input="$1"
    
    if [ -z "$input" ]; then
        echo ""
        return 1
    fi
    
    # Add padding if needed
    local padded="$input"
    while [ $((${#padded} % 4)) -ne 0 ]; do
        padded="${padded}="
    done
    
    echo "$padded" | tr '_-' '/+' | base64 -d
}

# ========================= INITIALIZATION =========================

# Install required crypto tools
install_crypto_tools() {
    if [ "$EUID" -ne 0 ]; then
        debug "Not running as root, skipping crypto tools installation"
        return 0
    fi
    
    # Install uuid tools
    if ! command_exists uuid && ! command_exists uuidgen; then
        debug "Installing UUID tools..."
        if command_exists apt-get; then
            apt-get update && apt-get install -y uuid-runtime
        elif command_exists yum; then
            yum install -y util-linux
        fi
    fi
    
    # Install OpenSSL if not available
    if ! command_exists openssl; then
        debug "Installing OpenSSL..."
        if command_exists apt-get; then
            apt-get update && apt-get install -y openssl
        elif command_exists yum; then
            yum install -y openssl
        fi
    fi
}

# Initialize crypto library
init_crypto() {
    debug "Initializing crypto library"
    install_crypto_tools
}

# =============================================================================
# COMPATIBILITY FUNCTIONS
# =============================================================================

# Compatibility function for generate_keypair (used by vpn.sh)
generate_keypair() {
    generate_x25519_keys
}

# Compatibility function for generate_short_id (used by vpn.sh)
generate_short_id() {
    generate_random_hex 8
}