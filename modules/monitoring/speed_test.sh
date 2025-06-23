#!/bin/bash

# Connection Speed Testing Module
# Tests VPN connection speeds and provides performance metrics

# Get module directory
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/common.sh" || exit 1
source "$PROJECT_ROOT/lib/network.sh" || exit 1
source "$PROJECT_ROOT/lib/docker.sh" || exit 1

# Speed test configuration
SPEED_TEST_DIR="/opt/v2ray/speed_tests"
SPEED_TEST_LOG="$SPEED_TEST_DIR/history.log"
SPEED_TEST_RESULTS="$SPEED_TEST_DIR/latest.json"

# Test endpoints
declare -A SPEED_TEST_ENDPOINTS=(
    ["Google DNS"]="8.8.8.8"
    ["Cloudflare DNS"]="1.1.1.1"
    ["OpenDNS"]="208.67.222.222"
    ["Quad9 DNS"]="9.9.9.9"
)

# Initialize speed test directory
init_speed_test() {
    mkdir -p "$SPEED_TEST_DIR"
    touch "$SPEED_TEST_LOG"
    chmod 700 "$SPEED_TEST_DIR"
}

# Test connection latency
test_connection_latency() {
    local endpoint="${1:-8.8.8.8}"
    local count="${2:-10}"
    local timeout="${3:-5}"
    
    info "Testing latency to $endpoint..."
    
    # Run ping test
    local ping_result=$(ping -c "$count" -W "$timeout" "$endpoint" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Extract statistics
        local min=$(echo "$ping_result" | grep -oP 'min/avg/max.*?(\d+\.\d+)/' | head -1 | grep -oP '\d+\.\d+')
        local avg=$(echo "$ping_result" | grep -oP 'min/avg/max.*?/(\d+\.\d+)/' | head -1 | grep -oP '\d+\.\d+')
        local max=$(echo "$ping_result" | grep -oP 'min/avg/max.*?/\d+\.\d+/(\d+\.\d+)' | head -1 | grep -oP '\d+\.\d+')
        local loss=$(echo "$ping_result" | grep -oP '(\d+)% packet loss' | grep -oP '\d+')
        
        echo "{\"min\": $min, \"avg\": $avg, \"max\": $max, \"loss\": $loss}"
    else
        echo "{\"error\": \"Connection failed\"}"
    fi
}

# Test download speed
test_download_speed() {
    local test_url="${1:-http://speedtest.tele2.net/10MB.zip}"
    local timeout="${2:-30}"
    
    info "Testing download speed..."
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Download file and measure time
    local start_time=$(date +%s.%N)
    
    if wget -O "$temp_file" --timeout="$timeout" "$test_url" 2>/dev/null; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        local file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null)
        
        # Calculate speed in Mbps
        local speed_mbps=$(echo "scale=2; ($file_size * 8) / ($duration * 1000000)" | bc)
        
        rm -f "$temp_file"
        echo "{\"speed_mbps\": $speed_mbps, \"duration\": $duration, \"bytes\": $file_size}"
    else
        rm -f "$temp_file"
        echo "{\"error\": \"Download failed\"}"
    fi
}

# Test upload speed (using curl to httpbin.org)
test_upload_speed() {
    local size_mb="${1:-1}"
    local timeout="${2:-30}"
    
    info "Testing upload speed..."
    
    # Generate test data
    local test_data=$(dd if=/dev/urandom bs=1M count="$size_mb" 2>/dev/null | base64)
    local data_size=${#test_data}
    
    # Upload data and measure time
    local start_time=$(date +%s.%N)
    
    if curl -X POST -d "$test_data" --max-time "$timeout" \
        -H "Content-Type: text/plain" \
        "http://httpbin.org/post" >/dev/null 2>&1; then
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        
        # Calculate speed in Mbps
        local speed_mbps=$(echo "scale=2; ($data_size * 8) / ($duration * 1000000)" | bc)
        
        echo "{\"speed_mbps\": $speed_mbps, \"duration\": $duration, \"bytes\": $data_size}"
    else
        echo "{\"error\": \"Upload failed\"}"
    fi
}

# Test VPN throughput
test_vpn_throughput() {
    local user="${1}"
    
    info "Testing VPN throughput..."
    
    # Check if VPN is running
    if ! is_vpn_running; then
        error "VPN server is not running"
        return 1
    fi
    
    # Get container network stats before test
    local stats_before=$(docker exec xray cat /proc/net/dev 2>/dev/null | grep -E 'eth0|ens' | head -1)
    local rx_bytes_before=$(echo "$stats_before" | awk '{print $2}')
    local tx_bytes_before=$(echo "$stats_before" | awk '{print $10}')
    
    # Wait for some traffic (or run a specific test)
    sleep 5
    
    # Get container network stats after test
    local stats_after=$(docker exec xray cat /proc/net/dev 2>/dev/null | grep -E 'eth0|ens' | head -1)
    local rx_bytes_after=$(echo "$stats_after" | awk '{print $2}')
    local tx_bytes_after=$(echo "$stats_after" | awk '{print $10}')
    
    # Calculate throughput
    local rx_bytes=$((rx_bytes_after - rx_bytes_before))
    local tx_bytes=$((tx_bytes_after - tx_bytes_before))
    local rx_mbps=$(echo "scale=2; ($rx_bytes * 8) / (5 * 1000000)" | bc)
    local tx_mbps=$(echo "scale=2; ($tx_bytes * 8) / (5 * 1000000)" | bc)
    
    echo "{\"rx_mbps\": $rx_mbps, \"tx_mbps\": $tx_mbps, \"duration\": 5}"
}

# Run comprehensive speed test
run_comprehensive_speed_test() {
    local user="${1}"
    local report_file="${2:-$SPEED_TEST_RESULTS}"
    
    info "Running comprehensive speed test..."
    
    # Initialize results
    local results="{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"tests\": {}}"
    
    # Test latency to multiple endpoints
    echo -e "\n${BOLD}Testing Latency:${NC}"
    for endpoint_name in "${!SPEED_TEST_ENDPOINTS[@]}"; do
        local endpoint="${SPEED_TEST_ENDPOINTS[$endpoint_name]}"
        echo -n "  $endpoint_name ($endpoint): "
        
        local latency_result=$(test_connection_latency "$endpoint" 5 2)
        results=$(echo "$results" | jq --arg name "$endpoint_name" --argjson result "$latency_result" \
            '.tests.latency[$name] = $result')
        
        if echo "$latency_result" | jq -e '.avg' >/dev/null 2>&1; then
            local avg_ms=$(echo "$latency_result" | jq -r '.avg')
            local loss=$(echo "$latency_result" | jq -r '.loss')
            echo -e "${GREEN}${avg_ms}ms (${loss}% loss)${NC}"
        else
            echo -e "${RED}Failed${NC}"
        fi
    done
    
    # Test download speed
    echo -e "\n${BOLD}Testing Download Speed:${NC}"
    echo -n "  Downloading test file: "
    local download_result=$(test_download_speed)
    results=$(echo "$results" | jq --argjson result "$download_result" '.tests.download = $result')
    
    if echo "$download_result" | jq -e '.speed_mbps' >/dev/null 2>&1; then
        local speed=$(echo "$download_result" | jq -r '.speed_mbps')
        echo -e "${GREEN}${speed} Mbps${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    # Test upload speed
    echo -e "\n${BOLD}Testing Upload Speed:${NC}"
    echo -n "  Uploading test data: "
    local upload_result=$(test_upload_speed 1)
    results=$(echo "$results" | jq --argjson result "$upload_result" '.tests.upload = $result')
    
    if echo "$upload_result" | jq -e '.speed_mbps' >/dev/null 2>&1; then
        local speed=$(echo "$upload_result" | jq -r '.speed_mbps')
        echo -e "${GREEN}${speed} Mbps${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    # Test VPN throughput if user specified
    if [ -n "$user" ]; then
        echo -e "\n${BOLD}Testing VPN Throughput:${NC}"
        echo -n "  Measuring container traffic: "
        local vpn_result=$(test_vpn_throughput "$user")
        results=$(echo "$results" | jq --argjson result "$vpn_result" '.tests.vpn_throughput = $result')
        
        if echo "$vpn_result" | jq -e '.rx_mbps' >/dev/null 2>&1; then
            local rx=$(echo "$vpn_result" | jq -r '.rx_mbps')
            local tx=$(echo "$vpn_result" | jq -r '.tx_mbps')
            echo -e "${GREEN}RX: ${rx} Mbps, TX: ${tx} Mbps${NC}"
        else
            echo -e "${RED}Failed${NC}"
        fi
    fi
    
    # Calculate overall score
    local score=$(calculate_performance_score "$results")
    results=$(echo "$results" | jq --arg score "$score" '.overall_score = $score')
    
    # Save results
    echo "$results" | jq '.' > "$report_file"
    
    # Log to history
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | Score: $score" >> "$SPEED_TEST_LOG"
    
    # Display summary
    echo -e "\n${BOLD}Performance Summary:${NC}"
    echo -e "  Overall Score: $(get_score_color "$score")"
    echo -e "  Report saved to: $report_file"
}

# Calculate performance score (0-100)
calculate_performance_score() {
    local results="$1"
    local score=0
    local tests=0
    
    # Latency score (lower is better)
    local avg_latency=$(echo "$results" | jq -r '.tests.latency | to_entries | map(.value.avg // 1000) | add / length')
    if [ "${avg_latency%.*}" -lt 50 ]; then
        score=$((score + 25))
    elif [ "${avg_latency%.*}" -lt 100 ]; then
        score=$((score + 15))
    elif [ "${avg_latency%.*}" -lt 200 ]; then
        score=$((score + 5))
    fi
    
    # Download speed score
    local download_speed=$(echo "$results" | jq -r '.tests.download.speed_mbps // 0')
    if (( $(echo "$download_speed > 50" | bc -l) )); then
        score=$((score + 25))
    elif (( $(echo "$download_speed > 25" | bc -l) )); then
        score=$((score + 15))
    elif (( $(echo "$download_speed > 10" | bc -l) )); then
        score=$((score + 5))
    fi
    
    # Upload speed score
    local upload_speed=$(echo "$results" | jq -r '.tests.upload.speed_mbps // 0')
    if (( $(echo "$upload_speed > 25" | bc -l) )); then
        score=$((score + 25))
    elif (( $(echo "$upload_speed > 10" | bc -l) )); then
        score=$((score + 15))
    elif (( $(echo "$upload_speed > 5" | bc -l) )); then
        score=$((score + 5))
    fi
    
    # VPN throughput score (if available)
    local vpn_rx=$(echo "$results" | jq -r '.tests.vpn_throughput.rx_mbps // 0')
    local vpn_tx=$(echo "$results" | jq -r '.tests.vpn_throughput.tx_mbps // 0')
    if (( $(echo "$vpn_rx > 10 || $vpn_tx > 10" | bc -l) )); then
        score=$((score + 25))
    elif (( $(echo "$vpn_rx > 5 || $vpn_tx > 5" | bc -l) )); then
        score=$((score + 15))
    elif (( $(echo "$vpn_rx > 1 || $vpn_tx > 1" | bc -l) )); then
        score=$((score + 5))
    fi
    
    echo "$score"
}

# Get color for score
get_score_color() {
    local score="$1"
    
    if [ "$score" -ge 80 ]; then
        echo -e "${GREEN}Excellent ($score/100)${NC}"
    elif [ "$score" -ge 60 ]; then
        echo -e "${YELLOW}Good ($score/100)${NC}"
    elif [ "$score" -ge 40 ]; then
        echo -e "${YELLOW}Fair ($score/100)${NC}"
    else
        echo -e "${RED}Poor ($score/100)${NC}"
    fi
}

# Show speed test history
show_speed_test_history() {
    local limit="${1:-10}"
    
    if [ ! -f "$SPEED_TEST_LOG" ]; then
        info "No speed test history available"
        return
    fi
    
    echo -e "${BOLD}Speed Test History (Last $limit):${NC}"
    tail -n "$limit" "$SPEED_TEST_LOG" | while IFS='|' read -r timestamp score; do
        echo "  $timestamp |$(get_score_color "$(echo "$score" | grep -oP '\d+' | head -1)")"
    done
}

# Compare speed tests
compare_speed_tests() {
    local file1="${1}"
    local file2="${2:-$SPEED_TEST_RESULTS}"
    
    [ ! -f "$file1" ] && {
        error "First test file not found: $file1"
        return 1
    }
    
    [ ! -f "$file2" ] && {
        error "Second test file not found: $file2"
        return 1
    }
    
    echo -e "${BOLD}Speed Test Comparison:${NC}"
    
    # Load test results
    local test1=$(cat "$file1")
    local test2=$(cat "$file2")
    
    # Compare timestamps
    local time1=$(echo "$test1" | jq -r '.timestamp')
    local time2=$(echo "$test2" | jq -r '.timestamp')
    echo -e "  Test 1: $time1"
    echo -e "  Test 2: $time2"
    echo
    
    # Compare latencies
    echo -e "${BOLD}Latency Comparison:${NC}"
    for endpoint in "${!SPEED_TEST_ENDPOINTS[@]}"; do
        local lat1=$(echo "$test1" | jq -r --arg e "$endpoint" '.tests.latency[$e].avg // "N/A"')
        local lat2=$(echo "$test2" | jq -r --arg e "$endpoint" '.tests.latency[$e].avg // "N/A"')
        
        if [ "$lat1" != "N/A" ] && [ "$lat2" != "N/A" ]; then
            local diff=$(echo "$lat2 - $lat1" | bc)
            local color=$([[ $(echo "$diff < 0" | bc -l) == 1 ]] && echo "$GREEN" || echo "$RED")
            echo -e "  $endpoint: ${lat1}ms → ${lat2}ms (${color}${diff}ms${NC})"
        fi
    done
    echo
    
    # Compare speeds
    echo -e "${BOLD}Speed Comparison:${NC}"
    local dl1=$(echo "$test1" | jq -r '.tests.download.speed_mbps // "N/A"')
    local dl2=$(echo "$test2" | jq -r '.tests.download.speed_mbps // "N/A"')
    local ul1=$(echo "$test1" | jq -r '.tests.upload.speed_mbps // "N/A"')
    local ul2=$(echo "$test2" | jq -r '.tests.upload.speed_mbps // "N/A"')
    
    if [ "$dl1" != "N/A" ] && [ "$dl2" != "N/A" ]; then
        local diff=$(echo "$dl2 - $dl1" | bc)
        local color=$([[ $(echo "$diff > 0" | bc -l) == 1 ]] && echo "$GREEN" || echo "$RED")
        echo -e "  Download: ${dl1} Mbps → ${dl2} Mbps (${color}${diff} Mbps${NC})"
    fi
    
    if [ "$ul1" != "N/A" ] && [ "$ul2" != "N/A" ]; then
        local diff=$(echo "$ul2 - $ul1" | bc)
        local color=$([[ $(echo "$diff > 0" | bc -l) == 1 ]] && echo "$GREEN" || echo "$RED")
        echo -e "  Upload: ${ul1} Mbps → ${ul2} Mbps (${color}${diff} Mbps${NC})"
    fi
    echo
    
    # Compare scores
    local score1=$(echo "$test1" | jq -r '.overall_score // 0')
    local score2=$(echo "$test2" | jq -r '.overall_score // 0')
    echo -e "${BOLD}Overall Score:${NC}"
    echo -e "  Test 1: $(get_score_color "$score1")"
    echo -e "  Test 2: $(get_score_color "$score2")"
}

# Schedule periodic speed tests
schedule_speed_tests() {
    local interval="${1:-6}"  # Default every 6 hours
    local enabled="${2:-true}"
    
    if [ "$enabled" = "true" ]; then
        # Create speed test script
        cat > /opt/v2ray/scripts/speed_test.sh << EOF
#!/bin/bash
# Automated Speed Test Script

source $PROJECT_ROOT/modules/monitoring/speed_test.sh
run_comprehensive_speed_test "" "$SPEED_TEST_DIR/test_\$(date +%Y%m%d_%H%M%S).json"
EOF
        chmod +x /opt/v2ray/scripts/speed_test.sh
        
        # Add cron job
        (crontab -l 2>/dev/null | grep -v "speed_test.sh"; 
         echo "0 */$interval * * * /opt/v2ray/scripts/speed_test.sh >> $SPEED_TEST_DIR/cron.log 2>&1") | crontab -
        
        success "Speed tests scheduled every $interval hours"
    else
        # Remove cron job
        crontab -l 2>/dev/null | grep -v "speed_test.sh" | crontab -
        rm -f /opt/v2ray/scripts/speed_test.sh
        
        success "Speed test scheduling disabled"
    fi
}

# Export speed test results
export_speed_test_results() {
    local output_format="${1:-json}"
    local output_file="${2:-speed_test_export_$(date +%Y%m%d_%H%M%S).$output_format}"
    
    case "$output_format" in
        json)
            # Combine all test results
            local combined='{"tests": []}'
            for test_file in "$SPEED_TEST_DIR"/*.json; do
                [ -f "$test_file" ] || continue
                local test_data=$(cat "$test_file")
                combined=$(echo "$combined" | jq --argjson test "$test_data" '.tests += [$test]')
            done
            echo "$combined" | jq '.' > "$output_file"
            ;;
            
        csv)
            # Export as CSV
            echo "Timestamp,Score,Avg Latency,Download Mbps,Upload Mbps" > "$output_file"
            for test_file in "$SPEED_TEST_DIR"/*.json; do
                [ -f "$test_file" ] || continue
                jq -r '[
                    .timestamp,
                    .overall_score // 0,
                    (.tests.latency | to_entries | map(.value.avg // 0) | add / length),
                    .tests.download.speed_mbps // 0,
                    .tests.upload.speed_mbps // 0
                ] | @csv' "$test_file" >> "$output_file"
            done
            ;;
            
        *)
            error "Unsupported format: $output_format"
            return 1
            ;;
    esac
    
    success "Speed test results exported to $output_file"
}

# Initialize on module load
init_speed_test

# Export functions
export -f init_speed_test
export -f test_connection_latency
export -f test_download_speed
export -f test_upload_speed
export -f test_vpn_throughput
export -f run_comprehensive_speed_test
export -f calculate_performance_score
export -f get_score_color
export -f show_speed_test_history
export -f compare_speed_tests
export -f schedule_speed_tests
export -f export_speed_test_results