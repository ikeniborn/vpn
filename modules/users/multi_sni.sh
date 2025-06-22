#!/bin/bash

# Multi-SNI Domain Support Module
# Allows users to have multiple SNI domains for enhanced security and flexibility

# Get module directory
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/common.sh" || exit 1
source "$PROJECT_ROOT/lib/config.sh" || exit 1
source "$PROJECT_ROOT/lib/network.sh" || exit 1

# Ensure network functions are available
if ! type validate_sni_domain &>/dev/null; then
    # Fallback implementation if network library not properly loaded
    validate_sni_domain() {
        local domain="$1"
        
        if [ -z "$domain" ]; then
            return 1
        fi
        
        # Basic format validation
        if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            # Check DNS resolution
            if host "$domain" >/dev/null 2>&1 || nslookup "$domain" >/dev/null 2>&1; then
                return 0
            fi
        fi
        
        return 1
    }
fi

# SNI domain configuration file
SNI_CONFIG_FILE="/opt/v2ray/config/multi_sni.json"

# Test SNI domain quality (simple implementation)
test_sni_quality() {
    local domain="$1"
    
    # Simple DNS resolution test
    if host "$domain" >/dev/null 2>&1 || nslookup "$domain" >/dev/null 2>&1; then
        # Test HTTPS connectivity
        if curl -sI -m 5 "https://$domain" >/dev/null 2>&1; then
            echo "good"
        else
            echo "medium"
        fi
    else
        echo "poor"
    fi
}

# Initialize multi-SNI configuration
init_multi_sni() {
    if [ ! -f "$SNI_CONFIG_FILE" ]; then
        echo '{"domains": {}, "rotation": {"enabled": false, "interval": 86400}}' > "$SNI_CONFIG_FILE"
        chmod 600 "$SNI_CONFIG_FILE"
    fi
}

# Add SNI domain for user
add_user_sni_domain() {
    local username="$1"
    local sni_domain="$2"
    local priority="${3:-1}"  # Default priority is 1
    
    [ -z "$username" ] || [ -z "$sni_domain" ] && {
        error "Username and SNI domain are required"
        return 1
    }
    
    # Validate SNI domain
    if ! validate_sni_domain "$sni_domain"; then
        error "Invalid SNI domain: $sni_domain"
        return 1
    fi
    
    # Test SNI domain quality
    info "Testing SNI domain quality..."
    local quality=$(test_sni_quality "$sni_domain")
    if [ "$quality" = "poor" ]; then
        warning "SNI domain $sni_domain has poor quality (high latency or packet loss)"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" != "y" ]] && return 1
    fi
    
    # Load existing configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null || echo '{"domains": {}}')
    
    # Add domain using jq
    config=$(echo "$config" | jq --arg user "$username" --arg domain "$sni_domain" --arg prio "$priority" \
        '.domains[$user] = (.domains[$user] // []) + [{
            "domain": $domain,
            "priority": ($prio | tonumber),
            "added": (now | todate),
            "quality": "good",
            "last_check": (now | todate)
        }]')
    
    # Save configuration
    echo "$config" | jq '.' > "$SNI_CONFIG_FILE"
    
    success "Added SNI domain $sni_domain for user $username (priority: $priority)"
    
    # Update user configuration
    update_user_sni_config "$username"
}

# Remove SNI domain from user
remove_user_sni_domain() {
    local username="$1"
    local sni_domain="$2"
    
    [ -z "$username" ] || [ -z "$sni_domain" ] && {
        error "Username and SNI domain are required"
        return 1
    }
    
    # Load existing configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$config" ] && {
        error "No SNI configuration found"
        return 1
    }
    
    # Remove domain using jq
    config=$(echo "$config" | jq --arg user "$username" --arg domain "$sni_domain" \
        '.domains[$user] = (.domains[$user] // []) | map(select(.domain != $domain))')
    
    # Save configuration
    echo "$config" | jq '.' > "$SNI_CONFIG_FILE"
    
    success "Removed SNI domain $sni_domain from user $username"
    
    # Update user configuration
    update_user_sni_config "$username"
}

# List SNI domains for user
list_user_sni_domains() {
    local username="$1"
    
    [ -z "$username" ] && {
        error "Username is required"
        return 1
    }
    
    # Load configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$config" ] && {
        info "No SNI domains configured"
        return 0
    }
    
    # Extract user domains
    local domains=$(echo "$config" | jq -r --arg user "$username" \
        '.domains[$user] // [] | sort_by(.priority) | .[] | 
        "Priority \(.priority): \(.domain) (Quality: \(.quality), Added: \(.added))"')
    
    if [ -z "$domains" ]; then
        info "No SNI domains configured for user $username"
    else
        echo -e "${BOLD}SNI domains for user $username:${NC}"
        echo "$domains" | while IFS= read -r line; do
            echo "  $line"
        done
    fi
}

# Update user configuration with SNI domains
update_user_sni_config() {
    local username="$1"
    local user_config="/opt/v2ray/users/${username}.json"
    
    [ ! -f "$user_config" ] && {
        error "User configuration not found: $username"
        return 1
    }
    
    # Load SNI configuration
    local sni_config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$sni_config" ] && return 0
    
    # Get primary SNI domain (highest priority)
    local primary_sni=$(echo "$sni_config" | jq -r --arg user "$username" \
        '.domains[$user] // [] | sort_by(.priority) | .[0].domain // ""')
    
    [ -z "$primary_sni" ] && {
        warning "No SNI domains configured for user $username"
        return 0
    }
    
    # Update user configuration with primary SNI
    local config=$(cat "$user_config")
    config=$(echo "$config" | jq --arg sni "$primary_sni" \
        '.streamSettings.realitySettings.serverName = $sni')
    
    echo "$config" | jq '.' > "$user_config"
    
    # Regenerate user links and QR codes
    generate_user_links "$username"
    
    info "Updated user $username configuration with SNI: $primary_sni"
}

# Generate user links with multiple SNI domains
generate_user_links() {
    local username="$1"
    local user_dir="/opt/v2ray/users"
    
    # Load user configuration
    local user_config="$user_dir/${username}.json"
    [ ! -f "$user_config" ] && {
        error "User configuration not found"
        return 1
    }
    
    # Load SNI configuration
    local sni_config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$sni_config" ] && return 0
    
    # Get all SNI domains for user
    local domains=$(echo "$sni_config" | jq -r --arg user "$username" \
        '.domains[$user] // [] | sort_by(.priority) | .[].domain')
    
    # Generate links for each domain
    local link_num=1
    echo "$domains" | while IFS= read -r sni_domain; do
        [ -z "$sni_domain" ] && continue
        
        # Generate VLESS link
        local uuid=$(jq -r '.clients[0].id' "$user_config")
        local port=$(grep -oP 'listen.*?(\d+)' /opt/v2ray/config/config.json | grep -oP '\d+' | head -1)
        local public_key=$(cat /opt/v2ray/config/public_key.txt)
        local short_id=$(cat /opt/v2ray/config/short_id.txt)
        local server_ip=$(get_server_ip)
        
        local vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni_domain}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VPN-${username}-SNI${link_num}"
        
        # Save link
        echo "$vless_link" > "$user_dir/${username}_sni${link_num}.link"
        
        # Generate QR code
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t PNG -o "$user_dir/${username}_sni${link_num}.png" "$vless_link"
        fi
        
        ((link_num++))
    done
    
    success "Generated ${link_num} connection links for user $username"
}

# Check SNI domain quality for all users
check_all_sni_quality() {
    info "Checking SNI domain quality for all users..."
    
    # Load configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$config" ] && {
        info "No SNI domains configured"
        return 0
    }
    
    # Extract all unique domains
    local all_domains=$(echo "$config" | jq -r '.domains | to_entries | .[].value | .[].domain' | sort -u)
    
    # Test each domain
    echo "$all_domains" | while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        
        info "Testing $domain..."
        local quality=$(test_sni_quality "$domain")
        
        # Update quality in configuration
        config=$(cat "$SNI_CONFIG_FILE")
        config=$(echo "$config" | jq --arg domain "$domain" --arg quality "$quality" \
            '(.domains | to_entries | .[].value[] | select(.domain == $domain)) |= 
            (.quality = $quality | .last_check = (now | todate))')
        echo "$config" | jq '.' > "$SNI_CONFIG_FILE"
        
        echo "  Quality: $quality"
    done
    
    success "SNI quality check completed"
}

# Enable/disable SNI rotation
configure_sni_rotation() {
    local enabled="$1"
    local interval="${2:-86400}"  # Default 24 hours
    
    # Load configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null || echo '{"domains": {}, "rotation": {}}')
    
    # Update rotation settings
    config=$(echo "$config" | jq --arg enabled "$enabled" --arg interval "$interval" \
        '.rotation.enabled = ($enabled == "true") | .rotation.interval = ($interval | tonumber)')
    
    echo "$config" | jq '.' > "$SNI_CONFIG_FILE"
    
    if [ "$enabled" = "true" ]; then
        success "SNI rotation enabled (interval: ${interval}s)"
        
        # Create rotation script
        cat > /opt/v2ray/scripts/rotate_sni.sh << 'EOF'
#!/bin/bash
# SNI Rotation Script

source /path/to/vpn/modules/users/multi_sni.sh
rotate_user_sni_domains
EOF
        chmod +x /opt/v2ray/scripts/rotate_sni.sh
        
        # Add cron job
        (crontab -l 2>/dev/null | grep -v "rotate_sni.sh"; echo "0 */6 * * * /opt/v2ray/scripts/rotate_sni.sh >> /opt/v2ray/logs/sni_rotation.log 2>&1") | crontab -
    else
        success "SNI rotation disabled"
        
        # Remove cron job
        crontab -l 2>/dev/null | grep -v "rotate_sni.sh" | crontab -
    fi
}

# Rotate SNI domains for all users
rotate_user_sni_domains() {
    info "Rotating SNI domains..."
    
    # Load configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$config" ] && return 0
    
    # Check if rotation is enabled
    local rotation_enabled=$(echo "$config" | jq -r '.rotation.enabled // false')
    [ "$rotation_enabled" != "true" ] && {
        info "SNI rotation is disabled"
        return 0
    }
    
    # Get all users
    local users=$(echo "$config" | jq -r '.domains | keys[]')
    
    # Rotate for each user
    echo "$users" | while IFS= read -r username; do
        [ -z "$username" ] && continue
        
        # Get user domains sorted by priority
        local domains=$(echo "$config" | jq -r --arg user "$username" \
            '.domains[$user] // [] | sort_by(.priority)')
        
        # Check if user has multiple domains
        local domain_count=$(echo "$domains" | jq 'length')
        [ "$domain_count" -le 1 ] && continue
        
        # Rotate priorities (1->2, 2->3, ..., n->1)
        local rotated=$(echo "$domains" | jq '[
            .[-1] | .priority = 1,
            .[0:-1][] | .priority += 1
        ] | sort_by(.priority)')
        
        # Update configuration
        config=$(cat "$SNI_CONFIG_FILE")
        config=$(echo "$config" | jq --arg user "$username" --argjson domains "$rotated" \
            '.domains[$user] = $domains')
        echo "$config" | jq '.' > "$SNI_CONFIG_FILE"
        
        # Update user configuration
        update_user_sni_config "$username"
        
        info "Rotated SNI domains for user $username"
    done
    
    success "SNI rotation completed"
}

# Export user's SNI configuration
export_user_sni_config() {
    local username="$1"
    local output_file="${2:-${username}_sni_config.json}"
    
    [ -z "$username" ] && {
        error "Username is required"
        return 1
    }
    
    # Load configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null)
    [ -z "$config" ] && {
        error "No SNI configuration found"
        return 1
    }
    
    # Extract user configuration
    local user_config=$(echo "$config" | jq --arg user "$username" \
        '{user: $user, domains: .domains[$user] // [], rotation: .rotation}')
    
    # Save to file
    echo "$user_config" | jq '.' > "$output_file"
    
    success "Exported SNI configuration to $output_file"
}

# Import user's SNI configuration
import_user_sni_config() {
    local import_file="$1"
    
    [ ! -f "$import_file" ] && {
        error "Import file not found: $import_file"
        return 1
    }
    
    # Load import data
    local import_data=$(cat "$import_file")
    local username=$(echo "$import_data" | jq -r '.user')
    local domains=$(echo "$import_data" | jq -r '.domains')
    
    [ -z "$username" ] && {
        error "Invalid import file: missing username"
        return 1
    }
    
    # Load existing configuration
    local config=$(cat "$SNI_CONFIG_FILE" 2>/dev/null || echo '{"domains": {}}')
    
    # Merge domains
    config=$(echo "$config" | jq --arg user "$username" --argjson domains "$domains" \
        '.domains[$user] = $domains')
    
    # Save configuration
    echo "$config" | jq '.' > "$SNI_CONFIG_FILE"
    
    success "Imported SNI configuration for user $username"
    
    # Update user configuration
    update_user_sni_config "$username"
}

# Interactive SNI management menu
manage_user_sni_interactive() {
    local username="$1"
    
    [ -z "$username" ] && {
        error "Username is required"
        return 1
    }
    
    while true; do
        echo
        echo -e "${BOLD}SNI Domain Management - User: $username${NC}"
        echo "1. List SNI domains"
        echo "2. Add SNI domain"
        echo "3. Remove SNI domain"
        echo "4. Test SNI quality"
        echo "5. Export configuration"
        echo "6. Import configuration"
        echo "0. Back"
        echo
        
        read -p "Select option: " choice
        
        case $choice in
            1)
                list_user_sni_domains "$username"
                ;;
            2)
                read -p "Enter SNI domain: " sni_domain
                read -p "Enter priority (1-10, default 1): " priority
                priority=${priority:-1}
                add_user_sni_domain "$username" "$sni_domain" "$priority"
                ;;
            3)
                list_user_sni_domains "$username"
                read -p "Enter SNI domain to remove: " sni_domain
                remove_user_sni_domain "$username" "$sni_domain"
                ;;
            4)
                check_all_sni_quality
                ;;
            5)
                read -p "Export filename (default: ${username}_sni_config.json): " filename
                export_user_sni_config "$username" "$filename"
                ;;
            6)
                read -p "Import filename: " filename
                import_user_sni_config "$filename"
                ;;
            0)
                break
                ;;
            *)
                error "Invalid option"
                ;;
        esac
    done
}

# Initialize on module load
init_multi_sni

# Export functions
export -f init_multi_sni
export -f add_user_sni_domain
export -f remove_user_sni_domain
export -f list_user_sni_domains
export -f update_user_sni_config
export -f generate_user_links
export -f check_all_sni_quality
export -f configure_sni_rotation
export -f rotate_user_sni_domains
export -f export_user_sni_config
export -f import_user_sni_config
export -f manage_user_sni_interactive