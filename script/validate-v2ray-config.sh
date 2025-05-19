#!/bin/bash

# ===================================================================
# V2Ray Configuration Validation Script
# ===================================================================
# This script:
# - Validates the V2Ray configuration file
# - Checks for common configuration errors
# - Verifies that required inbound and outbound proxies are configured
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CONFIG_FILE="/opt/v2ray/config.json"
VERBOSE=false

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    return 1
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script validates the V2Ray configuration file and checks for common errors.

Options:
  --config FILE       Path to V2Ray configuration file (default: /opt/v2ray/config.json)
  --verbose           Show detailed validation output
  --help              Display this help message

Example:
  $(basename "$0") --config /path/to/config.json --verbose

EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --help)
                display_usage
                exit 0
                ;;
            *)
                warn "Unknown parameter: $1"
                ;;
        esac
        shift
    done

    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    info "Using configuration file: $CONFIG_FILE"
}

# Check if the file is a valid JSON
validate_json() {
    info "Checking if the file is valid JSON..."
    
    if ! command -v jq &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            info "jq is not installed. Installing it now..."
            apt-get update && apt-get install -y jq
        else
            warn "jq is not installed and cannot be automatically installed."
            warn "Skipping JSON validation."
            return 0
        fi
    fi
    
    if jq empty "$CONFIG_FILE" 2>/dev/null; then
        info "✓ Configuration file is valid JSON."
        return 0
    else
        error "✗ Configuration file is not valid JSON. Please check the syntax."
        return 1
    fi
}

# Verify required fields in the configuration
verify_required_fields() {
    info "Verifying required fields in the configuration..."
    
    # Use jq to check for required fields
    if [ "$VERBOSE" = true ]; then
        info "Checking for 'inbounds' array..."
    fi
    
    if ! jq -e '.inbounds' "$CONFIG_FILE" >/dev/null 2>&1; then
        error "✗ Missing 'inbounds' field in configuration."
        return 1
    fi
    
    if [ "$VERBOSE" = true ]; then
        info "Checking for 'outbounds' array..."
    fi
    
    if ! jq -e '.outbounds' "$CONFIG_FILE" >/dev/null 2>&1; then
        error "✗ Missing 'outbounds' field in configuration."
        return 1
    fi
    
    info "✓ Required fields (inbounds, outbounds) are present."
    return 0
}

# Check inbound proxies configuration
check_inbounds() {
    info "Checking inbound proxies configuration..."
    
    # Get the number of inbound proxies
    local inbound_count=$(jq '.inbounds | length' "$CONFIG_FILE")
    info "Found $inbound_count inbound proxy/proxies."
    
    # Check each inbound proxy for required fields
    for i in $(seq 0 $((inbound_count-1))); do
        local inbound_protocol=$(jq -r ".inbounds[$i].protocol" "$CONFIG_FILE")
        local inbound_port=$(jq -r ".inbounds[$i].port" "$CONFIG_FILE")
        local inbound_tag=$(jq -r ".inbounds[$i].tag // \"<no tag>\"" "$CONFIG_FILE")
        
        if [ "$VERBOSE" = true ]; then
            info "Inbound #$i: Protocol=$inbound_protocol, Port=$inbound_port, Tag=$inbound_tag"
        fi
        
        # Check if the protocol is supported
        case "$inbound_protocol" in
            vless|vmess|dokodemo-door|socks|http|shadowsocks|trojan)
                # These are common v2ray protocols, so they're fine
                ;;
            *)
                warn "✗ Inbound #$i uses unsupported or uncommon protocol: $inbound_protocol"
                ;;
        esac
        
        # For VLESS protocol, check if there's a security field with "reality"
        if [ "$inbound_protocol" = "vless" ]; then
            local security=$(jq -r ".inbounds[$i].settings.security // \"none\"" "$CONFIG_FILE")
            
            if [ "$security" = "reality" ]; then
                if [ "$VERBOSE" = true ]; then
                    info "✓ Inbound #$i uses VLESS with Reality."
                fi
                
                # Check for required Reality fields
                if ! jq -e ".inbounds[$i].settings.reality" "$CONFIG_FILE" >/dev/null 2>&1; then
                    warn "✗ Inbound #$i uses Reality but is missing Reality settings."
                fi
            fi
        fi
        
        # Check for duplicated ports
        for j in $(seq 0 $((inbound_count-1))); do
            if [ "$i" != "$j" ]; then
                local other_port=$(jq -r ".inbounds[$j].port" "$CONFIG_FILE")
                if [ "$inbound_port" = "$other_port" ]; then
                    warn "✗ Duplicate port $inbound_port used by inbounds #$i and #$j."
                fi
            fi
        done
    done
    
    info "✓ Inbound proxies check completed."
    return 0
}

# Check outbound proxies configuration
check_outbounds() {
    info "Checking outbound proxies configuration..."
    
    # Get the number of outbound proxies
    local outbound_count=$(jq '.outbounds | length' "$CONFIG_FILE")
    info "Found $outbound_count outbound proxy/proxies."
    
    # Check if we have at least one outbound
    if [ "$outbound_count" -eq 0 ]; then
        error "✗ No outbound proxies defined. At least one is required."
        return 1
    fi
    
    # Check each outbound proxy for required fields
    for i in $(seq 0 $((outbound_count-1))); do
        local outbound_protocol=$(jq -r ".outbounds[$i].protocol" "$CONFIG_FILE")
        local outbound_tag=$(jq -r ".outbounds[$i].tag // \"<no tag>\"" "$CONFIG_FILE")
        
        if [ "$VERBOSE" = true ]; then
            info "Outbound #$i: Protocol=$outbound_protocol, Tag=$outbound_tag"
        fi
        
        # Check if protocol is supported
        case "$outbound_protocol" in
            vless|vmess|freedom|blackhole|socks|http|shadowsocks|trojan)
                # These are common v2ray protocols, so they're fine
                ;;
            *)
                warn "✗ Outbound #$i uses unsupported or uncommon protocol: $outbound_protocol"
                ;;
        esac
        
        # For VLESS protocol with reality, check the necessary fields
        if [ "$outbound_protocol" = "vless" ]; then
            if jq -e ".outbounds[$i].settings.vnext" "$CONFIG_FILE" >/dev/null 2>&1; then
                # Check for server address
                local server_count=$(jq ".outbounds[$i].settings.vnext | length" "$CONFIG_FILE")
                
                if [ "$server_count" -gt 0 ]; then
                    local server_address=$(jq -r ".outbounds[$i].settings.vnext[0].address" "$CONFIG_FILE")
                    local server_port=$(jq -r ".outbounds[$i].settings.vnext[0].port" "$CONFIG_FILE")
                    
                    if [ -z "$server_address" ] || [ "$server_address" = "null" ]; then
                        warn "✗ Outbound #$i (VLESS) is missing server address."
                    elif [ "$server_address" = "0.0.0.0" ] || [ "$server_address" = "127.0.0.1" ]; then
                        warn "✗ Outbound #$i (VLESS) uses localhost as server address. This is probably wrong."
                    fi
                    
                    if [ -z "$server_port" ] || [ "$server_port" = "null" ] || [ "$server_port" -eq 0 ]; then
                        warn "✗ Outbound #$i (VLESS) has invalid server port."
                    fi
                    
                    # Check for users
                    if ! jq -e ".outbounds[$i].settings.vnext[0].users" "$CONFIG_FILE" >/dev/null 2>&1; then
                        warn "✗ Outbound #$i (VLESS) is missing users configuration."
                    else
                        local user_count=$(jq ".outbounds[$i].settings.vnext[0].users | length" "$CONFIG_FILE")
                        
                        if [ "$user_count" -eq 0 ]; then
                            warn "✗ Outbound #$i (VLESS) has no users configured."
                        else
                            # Check the first user's ID
                            local user_id=$(jq -r ".outbounds[$i].settings.vnext[0].users[0].id" "$CONFIG_FILE")
                            
                            if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
                                warn "✗ Outbound #$i (VLESS) user is missing ID."
                            fi
                            
                            # Check for flow field if using VLESS
                            local flow=$(jq -r ".outbounds[$i].settings.vnext[0].users[0].flow // \"\"" "$CONFIG_FILE")
                            
                            if [ "$VERBOSE" = true ] && [ -n "$flow" ]; then
                                info "Outbound #$i (VLESS) user has flow: $flow"
                            fi
                        fi
                    fi
                    
                    # Check for Reality settings if protocol is VLESS
                    if jq -e ".outbounds[$i].streamSettings.security" "$CONFIG_FILE" >/dev/null 2>&1; then
                        local security=$(jq -r ".outbounds[$i].streamSettings.security" "$CONFIG_FILE")
                        
                        if [ "$security" = "reality" ]; then
                            if [ "$VERBOSE" = true ]; then
                                info "✓ Outbound #$i uses VLESS with Reality."
                            fi
                            
                            # Check for required Reality fields
                            if ! jq -e ".outbounds[$i].streamSettings.realitySettings" "$CONFIG_FILE" >/dev/null 2>&1; then
                                warn "✗ Outbound #$i uses Reality but is missing Reality settings."
                            else
                                # Check for serverName (SNI)
                                local server_name=$(jq -r ".outbounds[$i].streamSettings.realitySettings.serverName" "$CONFIG_FILE")
                                
                                if [ -z "$server_name" ] || [ "$server_name" = "null" ]; then
                                    warn "✗ Outbound #$i (Reality) is missing serverName (SNI)."
                                fi
                                
                                # Check for fingerprint
                                local fingerprint=$(jq -r ".outbounds[$i].streamSettings.realitySettings.fingerprint" "$CONFIG_FILE")
                                
                                if [ -z "$fingerprint" ] || [ "$fingerprint" = "null" ]; then
                                    warn "✗ Outbound #$i (Reality) is missing fingerprint."
                                fi
                                
                                # Check for publicKey (required for server authentication)
                                local public_key=$(jq -r ".outbounds[$i].streamSettings.realitySettings.publicKey" "$CONFIG_FILE")
                                
                                if [ -z "$public_key" ] || [ "$public_key" = "null" ]; then
                                    warn "✗ Outbound #$i (Reality) is missing publicKey."
                                fi
                            fi
                        fi
                    fi
                fi
            else
                warn "✗ Outbound #$i (VLESS) is missing vnext configuration."
            fi
        fi
    done
    
    info "✓ Outbound proxies check completed."
    return 0
}

# Check for routing configuration
check_routing() {
    info "Checking routing configuration..."
    
    # Check if routing exists
    if ! jq -e '.routing' "$CONFIG_FILE" >/dev/null 2>&1; then
        warn "✗ No routing section found in configuration."
        return 0
    fi
    
    # Check for rules
    if ! jq -e '.routing.rules' "$CONFIG_FILE" >/dev/null 2>&1; then
        warn "✗ No routing rules found."
        return 0
    fi
    
    local rule_count=$(jq '.routing.rules | length' "$CONFIG_FILE")
    info "Found $rule_count routing rule(s)."
    
    # Check each rule
    for i in $(seq 0 $((rule_count-1))); do
        local outbound_tag=$(jq -r ".routing.rules[$i].outboundTag // \"<no tag>\"" "$CONFIG_FILE")
        
        if [ "$VERBOSE" = true ]; then
            info "Rule #$i outbound tag: $outbound_tag"
        fi
        
        # Check if the outbound tag exists
        if [ "$outbound_tag" != "<no tag>" ]; then
            local outbound_exists=$(jq --arg tag "$outbound_tag" '.outbounds[] | select(.tag == $tag) | .tag' "$CONFIG_FILE")
            
            if [ -z "$outbound_exists" ]; then
                warn "✗ Rule #$i references non-existent outbound tag: $outbound_tag"
            fi
        fi
    done
    
    info "✓ Routing configuration check completed."
    return 0
}

# Docker validation function
validate_in_docker() {
    info "Attempting to validate configuration using Docker v2ray/v2fly..."
    
    if ! command -v docker &>/dev/null; then
        warn "Docker is not installed. Skipping Docker validation."
        return 0
    fi
    
    # Create a temporary directory for validation
    local tmp_dir=$(mktemp -d)
    cp "$CONFIG_FILE" "$tmp_dir/config.json"
    
    # Run v2ray with the verify flag
    info "Running v2ray validation in Docker container..."
    if docker run --rm -v "$tmp_dir:/config" v2fly/v2fly-core:latest v2ray -test -config /config/config.json; then
        info "✓ V2Ray configuration validation passed."
        rm -rf "$tmp_dir"
        return 0
    else
        error "✗ V2Ray configuration validation failed."
        rm -rf "$tmp_dir"
        return 1
    fi
}

# Main function
main() {
    parse_args "$@"
    
    local validation_success=true
    
    # Run the validation steps, and set validation_success to false if any step fails
    validate_json || validation_success=false
    
    if [ "$validation_success" = true ]; then
        verify_required_fields || validation_success=false
        
        if [ "$validation_success" = true ]; then
            check_inbounds
            check_outbounds
            check_routing
            
            # Only run Docker validation if all other checks passed
            if [ "$validation_success" = true ]; then
                validate_in_docker || validation_success=false
            fi
        fi
    fi
    
    if [ "$validation_success" = true ]; then
        info "===================================================="
        info "✅ Configuration validation completed successfully."
        info "===================================================="
        return 0
    else
        error "===================================================="
        error "❌ Configuration validation failed."
        error "===================================================="
        return 1
    fi
}

main "$@"