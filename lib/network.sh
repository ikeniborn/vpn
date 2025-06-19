#!/bin/bash

# VPN Project Network Utilities Library
# Handles port checking, SNI domain validation, and network interface detection

# Source common library
if [ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# ========================= PORT MANAGEMENT =========================

# Check if port is available (not in use)
check_port_available() {
    local port="$1"
    
    if [ -z "$port" ]; then
        error "Port number required"
        return 1
    fi
    
    if ! validate_port "$port"; then
        error "Invalid port number: $port"
        return 1
    fi
    
    # Method 1: Use netstat if available
    if command_exists netstat; then
        ! netstat -tuln 2>/dev/null | grep -q ":$port "
        return $?
    fi
    
    # Method 2: Use ss if available  
    if command_exists ss; then
        ! ss -tuln 2>/dev/null | grep -q ":$port "
        return $?
    fi
    
    # Method 3: Try to connect to port as check
    ! timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null
}

# Generate random free port within specified range
generate_free_port() {
    local min_port=${1:-10000}      # Minimum port (default 10000)
    local max_port=${2:-65000}      # Maximum port (default 65000)
    local check_availability=${3:-true}  # Check availability (default true)
    local max_attempts=${4:-20}     # Maximum attempts (default 20)
    local fallback_port=${5:-10443} # Fallback port (default 10443)
    
    local attempts=0
    
    # Validate input parameters
    if ! validate_port "$min_port" || ! validate_port "$max_port"; then
        error "Invalid port range: $min_port-$max_port"
        echo "$fallback_port"
        return 1
    fi
    
    if [ "$min_port" -ge "$max_port" ]; then
        error "Minimum port must be less than maximum port"
        echo "$fallback_port"
        return 1
    fi
    
    debug "Generating free port in range $min_port-$max_port (max attempts: $max_attempts)"
    
    while [ $attempts -lt $max_attempts ]; do
        # Generate random port in specified range
        local port
        if command_exists shuf; then
            port=$(shuf -i $min_port-$max_port -n 1)
        else
            # Alternative method if shuf is not available
            local range=$((max_port - min_port + 1))
            port=$(( (RANDOM % range) + min_port ))
        fi
        
        # Check port availability if required
        if [ "$check_availability" = "true" ]; then
            if check_port_available "$port"; then
                debug "Found free port: $port"
                echo "$port"
                return 0
            fi
            debug "Port $port is in use, trying another..."
        else
            echo "$port"
            return 0
        fi
        
        attempts=$((attempts + 1))
    done
    
    # If couldn't find free port, return fallback
    warning "Could not find free port after $max_attempts attempts, using fallback: $fallback_port"
    echo "$fallback_port"
    return 1
}

# Get list of used ports
get_used_ports() {
    local protocol="${1:-tcp}"  # tcp or udp
    
    if command_exists netstat; then
        netstat -tuln 2>/dev/null | grep "^$protocol" | awk '{print $4}' | sed 's/.*://' | sort -n | uniq
    elif command_exists ss; then
        ss -tuln 2>/dev/null | grep "^$protocol" | awk '{print $5}' | sed 's/.*://' | sort -n | uniq
    else
        warning "No network tools available to check used ports"
        return 1
    fi
}

# ========================= DOMAIN VALIDATION =========================

# Validate domain name format
validate_domain_format() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        return 1
    fi
    
    # RFC compliant domain name regex
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check if domain resolves in DNS
check_domain_dns() {
    local domain="$1"
    local timeout="${2:-3}"
    
    debug "Checking DNS resolution for $domain..."
    
    # Method 1: Use dig if available (most reliable)
    if command_exists dig; then
        if timeout "$timeout" dig +short "$domain" >/dev/null 2>&1; then
            debug "Domain $domain resolves (dig)"
            return 0
        else
            debug "Domain $domain does not resolve (dig)"
            return 1
        fi
    fi
    
    # Method 2: Use host if available
    if command_exists host; then
        if timeout "$timeout" host "$domain" >/dev/null 2>&1; then
            debug "Domain $domain resolves (host)"
            return 0
        else
            debug "Domain $domain does not resolve (host)"
            return 1
        fi
    fi
    
    # Method 3: Use nslookup as fallback
    if command_exists nslookup; then
        if timeout "$timeout" nslookup "$domain" >/dev/null 2>&1; then
            debug "Domain $domain resolves (nslookup)"
            return 0
        else
            debug "Domain $domain does not resolve (nslookup)"
            return 1
        fi
    fi
    
    warning "No DNS tools available for domain resolution check"
    return 1
}

# Check if domain is accessible on specific port
check_domain_port() {
    local domain="$1"
    local port="${2:-443}"
    local timeout="${3:-3}"
    
    debug "Checking $domain:$port accessibility..."
    
    # Try TCP connection
    if timeout "$timeout" bash -c "</dev/tcp/$domain/$port" 2>/dev/null; then
        debug "Domain $domain is accessible on port $port"
        return 0
    else
        debug "Domain $domain is not accessible on port $port"
        return 1
    fi
}

# Check HTTPS accessibility
check_domain_https() {
    local domain="$1"
    local timeout="${2:-5}"
    
    debug "Checking HTTPS accessibility for $domain..."
    
    if ! command_exists curl; then
        warning "curl not available for HTTPS check"
        return 1
    fi
    
    local http_code=$(timeout "$timeout" curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$timeout" --max-time "$timeout" \
        --insecure --location --user-agent "Mozilla/5.0 (compatible; VPN-Checker)" \
        "https://$domain" 2>/dev/null || echo "000")
    
    debug "HTTPS response code for $domain: $http_code"
    
    if [ "$http_code" != "000" ]; then
        return 0
    else
        return 1
    fi
}

# Comprehensive SNI domain check
check_sni_domain() {
    local domain="$1"
    local timeout="${2:-5}"
    
    if [ -z "$domain" ]; then
        error "Domain name required"
        return 1
    fi
    
    log "Проверка доступности домена $domain..."
    
    # Step 1: Validate domain format
    if ! validate_domain_format "$domain"; then
        warning "Некорректный формат домена: $domain"
        return 1
    fi
    
    # Step 2: DNS resolution check
    if ! check_domain_dns "$domain" "$timeout"; then
        warning "Домен $domain не резолвится в DNS"
        return 1
    fi
    
    # Step 3: TCP connection to port 443
    if ! check_domain_port "$domain" 443 "$timeout"; then
        warning "Домен $domain недоступен на порту 443"
        return 1
    fi
    
    # Step 4: HTTPS accessibility check
    if ! check_domain_https "$domain" "$timeout"; then
        warning "Домен $domain не отвечает на HTTPS запросы"
        return 1
    fi
    
    # Step 5: Optional TLS check
    if command_exists openssl; then
        local tls_check=$(timeout "$timeout" bash -c "echo | openssl s_client -connect '$domain:443' -servername '$domain' -quiet 2>/dev/null | head -n 1" | grep -i "verify\|protocol\|cipher" 2>/dev/null || echo "")
        
        if [ -z "$tls_check" ]; then
            debug "Could not verify TLS details for $domain, but basic checks passed"
        else
            debug "TLS connection verified for $domain"
        fi
    fi
    
    log "✓ Домен $domain прошел все проверки"
    return 0
}

# ========================= PREDEFINED DOMAINS =========================

# List of known good SNI domains
get_default_sni_domains() {
    cat <<EOF
addons.mozilla.org
www.swift.org
golang.org
www.kernel.org
cdn.jsdelivr.net
registry.npmjs.org
api.github.com
www.lovelive-anime.jp
EOF
}

# Get SNI domain (interactive selection)
get_sni_domain() {
    local debug="${1:-false}"
    
    [ "$debug" = true ] && log "Getting SNI domain for Reality protocol..."
    
    # List of pre-configured domains
    local domains=(
        "addons.mozilla.org"
        "www.swift.org"
        "golang.org"
        "www.kernel.org"
        "cdn.jsdelivr.net"
        "registry.npmjs.org"
        "api.github.com"
        "www.lovelive-anime.jp"
    )
    
    echo -e "${BLUE}Available SNI domains:${NC}"
    local i=1
    for domain in "${domains[@]}"; do
        echo "$i) $domain"
        ((i++))
    done
    
    while true; do
        read -p "Select domain (1-${#domains[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#domains[@]}" ]; then
            SERVER_SNI="${domains[$((choice-1))]}"
            [ "$debug" = true ] && log "Selected SNI domain: $SERVER_SNI"
            
            # Verify selected domain
            echo -n "Checking domain accessibility... "
            if check_sni_domain "$SERVER_SNI" 5; then
                echo -e "${GREEN}✓ Domain is accessible${NC}"
                return 0
            else
                echo -e "${YELLOW}⚠ Domain may not be accessible, but will proceed${NC}"
                return 0
            fi
        else
            warning "Invalid selection. Please choose 1-${#domains[@]}"
        fi
    done
}

# Validate SNI domain format and accessibility
validate_sni_domain() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        return 1
    fi
    
    # Basic format validation
    if ! validate_domain_format "$domain"; then
        return 1
    fi
    
    # Check DNS resolution
    if ! check_domain_dns "$domain" 3; then
        return 1
    fi
    
    return 0
}

# Test multiple domains and return the first working one
find_working_sni_domain() {
    local timeout="${1:-5}"
    local max_domains="${2:-5}"
    
    log "Автоматический поиск рабочего SNI домена..."
    
    local count=0
    while IFS= read -r domain && [ $count -lt $max_domains ]; do
        if [ -n "$domain" ]; then
            info "Проверка домена: $domain"
            if check_sni_domain "$domain" "$timeout"; then
                log "✓ Найден рабочий домен: $domain"
                echo "$domain"
                return 0
            fi
            count=$((count + 1))
        fi
    done < <(get_default_sni_domains)
    
    warning "Не удалось найти рабочий SNI домен из списка по умолчанию"
    echo "addons.mozilla.org"  # Fallback
    return 1
}

# ========================= NETWORK INTERFACE DETECTION =========================

# Get external IP address
get_external_ip() {
    local timeout="${1:-5}"
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
        "https://ipinfo.io/ip"
    )
    
    for service in "${services[@]}"; do
        if command_exists curl; then
            local ip=$(timeout "$timeout" curl -s -4 --max-time "$timeout" "$service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
            if [ -n "$ip" ]; then
                echo "$ip"
                return 0
            fi
        elif command_exists wget; then
            local ip=$(timeout "$timeout" wget -qO- -T "$timeout" "$service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
            if [ -n "$ip" ]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    # Fallback: try to get IP from network interface
    local interface=$(get_primary_interface)
    local ip=$(get_interface_ip "$interface")
    if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Get primary network interface
get_primary_interface() {
    # Method 1: Default route interface
    if command_exists ip; then
        ip route | awk '/default/ {print $5; exit}'
        return $?
    fi
    
    # Method 2: Route command
    if command_exists route; then
        route -n | awk '$1 == "0.0.0.0" {print $8; exit}'
        return $?
    fi
    
    # Method 3: Fallback to first non-loopback interface
    if command_exists ip; then
        ip link show | awk -F': ' '/^[0-9]+: [^lo]/ {print $2; exit}'
        return $?
    fi
    
    # Method 4: Last resort
    echo "eth0"
    return 1
}

# Get interface IP address
get_interface_ip() {
    local interface="${1:-$(get_primary_interface)}"
    
    if command_exists ip; then
        ip addr show "$interface" 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1 | head -n1
    else
        ifconfig "$interface" 2>/dev/null | awk '/inet / {print $2}' | head -n1
    fi
}

# ========================= INITIALIZATION =========================

# Initialize network library
init_network() {
    debug "Initializing network library"
    
    # Install required tools if missing
    if ! command_exists netstat && ! command_exists ss; then
        if [ "$EUID" -eq 0 ]; then
            if command_exists apt-get; then
                apt-get update && apt-get install -y net-tools iproute2
            elif command_exists yum; then
                yum install -y net-tools iproute
            fi
        fi
    fi
}