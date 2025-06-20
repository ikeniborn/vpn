#!/bin/bash
#
# Configuration Validation Module
# Validates VPN server configuration for common issues
# Created to fix Reality connection errors

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/crypto.sh"

# Validate Reality key pair consistency
validate_reality_keys() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Validating Reality key pair..."
    
    if [ ! -f "/opt/v2ray/config/private_key.txt" ] || [ ! -f "/opt/v2ray/config/public_key.txt" ]; then
        warning "Reality key files missing"
        return 1
    fi
    
    local private_key=$(cat /opt/v2ray/config/private_key.txt 2>/dev/null)
    local public_key=$(cat /opt/v2ray/config/public_key.txt 2>/dev/null)
    local config_private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' /opt/v2ray/config/config.json 2>/dev/null)
    
    # Check if private keys match
    if [ "$private_key" != "$config_private_key" ]; then
        warning "Private key mismatch between file and configuration"
        [ "$debug" = true ] && {
            log "File private key: ${private_key:0:20}..."
            log "Config private key: ${config_private_key:0:20}..."
        }
        return 1
    fi
    
    # Validate key pair using xray command if available
    if command -v xray >/dev/null 2>&1; then
        local generated_public_key=$(echo "$private_key" | xray x25519 -i base64 2>/dev/null)
        if [ -n "$generated_public_key" ] && [ "$generated_public_key" != "$public_key" ]; then
            warning "Public key does not match private key"
            [ "$debug" = true ] && {
                log "Expected public key: $generated_public_key"
                log "Current public key: $public_key"
            }
            return 1
        fi
    fi
    
    [ "$debug" = true ] && log "Reality key pair validation passed"
    return 0
}

# Validate SNI domains accessibility
validate_sni_domains() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Validating SNI domains..."
    
    local sni_domains
    mapfile -t sni_domains < <(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[]' /opt/v2ray/config/config.json 2>/dev/null)
    
    for domain in "${sni_domains[@]}"; do
        if [ -n "$domain" ] && [ "$domain" != "null" ]; then
            if ! curl -s --connect-timeout 5 "https://$domain" >/dev/null 2>&1; then
                warning "SNI domain $domain is not accessible"
                [ "$debug" = true ] && log "Failed to connect to https://$domain"
                return 1
            else
                [ "$debug" = true ] && log "SNI domain $domain is accessible"
            fi
        fi
    done
    
    return 0
}

# Validate shortIds format
validate_short_ids() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Validating shortIds format..."
    
    local short_ids
    mapfile -t short_ids < <(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[]' /opt/v2ray/config/config.json 2>/dev/null)
    
    for sid in "${short_ids[@]}"; do
        if [ -n "$sid" ] && [ "$sid" != "null" ]; then
            # Check if shortId is valid hex string (8-16 characters)
            if ! [[ "$sid" =~ ^[0-9a-fA-F]{8,16}$ ]]; then
                warning "Invalid shortId format: $sid"
                [ "$debug" = true ] && log "shortId should be 8-16 hex characters"
                return 1
            else
                [ "$debug" = true ] && log "shortId $sid format is valid"
            fi
        fi
    done
    
    return 0
}

# Fix Reality configuration issues
fix_reality_config() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Attempting to fix Reality configuration..."
    
    # Get current server info
    get_server_info
    
    # Regenerate key pair if needed
    if ! validate_reality_keys "$debug"; then
        log "Regenerating Reality key pair..."
        
        if command -v xray >/dev/null 2>&1; then
            local new_private_key=$(xray x25519)
            local new_public_key=$(echo "$new_private_key" | xray x25519 -i base64)
            
            # Update key files
            echo "$new_private_key" > /opt/v2ray/config/private_key.txt
            echo "$new_public_key" > /opt/v2ray/config/public_key.txt
            
            # Update configuration
            jq ".inbounds[0].streamSettings.realitySettings.privateKey = \"$new_private_key\"" \
                /opt/v2ray/config/config.json > /opt/v2ray/config/config.json.tmp
            mv /opt/v2ray/config/config.json.tmp /opt/v2ray/config/config.json
            
            # Update server info
            export PRIVATE_KEY="$new_private_key"
            export PUBLIC_KEY="$new_public_key"
            
            log "Reality key pair regenerated"
        else
            error "xray command not available for key generation"
            return 1
        fi
    fi
    
    # Update user connection links with new keys
    if [ -d "/opt/v2ray/users" ]; then
        log "Updating user connection links..."
        for user_file in /opt/v2ray/users/*.json; do
            if [ -f "$user_file" ]; then
                local user_name=$(basename "$user_file" .json)
                # Update public key in user config
                jq ".public_key = \"$PUBLIC_KEY\"" "$user_file" > "${user_file}.tmp"
                mv "${user_file}.tmp" "$user_file"
                
                [ "$debug" = true ] && log "Updated keys for user: $user_name"
            fi
        done
    fi
    
    return 0
}

# Main validation function
validate_server_config() {
    local debug=${1:-false}
    
    log "Validating VPN server configuration..."
    
    local validation_failed=false
    
    # Check if Reality is enabled
    if [ "$USE_REALITY" = true ]; then
        if ! validate_reality_keys "$debug"; then
            warning "Reality key validation failed"
            validation_failed=true
        fi
        
        if ! validate_sni_domains "$debug"; then
            warning "SNI domain validation failed"
            validation_failed=true
        fi
        
        if ! validate_short_ids "$debug"; then
            warning "shortId validation failed"
            validation_failed=true
        fi
    fi
    
    if [ "$validation_failed" = true ]; then
        log "Configuration validation failed. Attempting automatic fixes..."
        if fix_reality_config "$debug"; then
            log "Configuration issues have been automatically fixed"
            log "Restarting Xray container to apply changes..."
            
            # Restart container
            cd /opt/v2ray && docker-compose restart
            sleep 5
            
            log "Container restarted. Please test your connections."
            return 0
        else
            error "Failed to automatically fix configuration issues"
            return 1
        fi
    else
        log "Configuration validation passed"
        return 0
    fi
}

# Export functions
export -f validate_reality_keys
export -f validate_sni_domains  
export -f validate_short_ids
export -f fix_reality_config
export -f validate_server_config