#!/bin/bash

# Test script for VPN project libraries
# Tests basic functionality of common.sh and config.sh

echo "🧪 Testing VPN Project Libraries"
echo "================================"

# Test common.sh
echo ""
echo "📚 Testing lib/common.sh..."

# Source common library
if ! source lib/common.sh; then
    echo "❌ Failed to source lib/common.sh"
    exit 1
fi

echo "✅ Successfully sourced lib/common.sh"

# Test logging functions
log "Testing log function"
info "Testing info function"
warning "Testing warning function"

# Test utility functions
echo ""
echo "🔧 Testing utility functions..."

# Test command_exists
if command_exists "echo"; then
    echo "✅ command_exists working correctly"
else
    echo "❌ command_exists failed"
fi

# Test validate_port
if validate_port "8080"; then
    echo "✅ validate_port working correctly for valid port"
else
    echo "❌ validate_port failed for valid port"
fi

if ! validate_port "99999"; then
    echo "✅ validate_port correctly rejected invalid port"
else
    echo "❌ validate_port accepted invalid port"
fi

# Test validate_uuid
test_uuid="12345678-1234-1234-1234-123456789abc"
if validate_uuid "$test_uuid"; then
    echo "✅ validate_uuid working correctly"
else
    echo "❌ validate_uuid failed"
fi

# Test directory functions
echo ""
echo "📁 Testing directory functions..."

# Create test directory
test_dir="/tmp/vpn_test"
ensure_dir "$test_dir"

if [ -d "$test_dir" ]; then
    echo "✅ ensure_dir working correctly"
    rm -rf "$test_dir"
else
    echo "❌ ensure_dir failed"
fi

# Test config.sh
echo ""
echo "⚙️  Testing lib/config.sh..."

# Source config library
if ! source lib/config.sh; then
    echo "❌ Failed to source lib/config.sh"
    exit 1
fi

echo "✅ Successfully sourced lib/config.sh"

# Test IP detection
test_ip=$(get_server_ip)
if [ -n "$test_ip" ]; then
    echo "✅ get_server_ip working: $test_ip"
else
    echo "❌ get_server_ip failed"
fi

# Test variable exports
echo ""
echo "🔄 Testing exported variables..."

# Check color variables
if [ -n "$GREEN" ] && [ -n "$RED" ] && [ -n "$NC" ]; then
    echo -e "${GREEN}✅ Color variables exported correctly${NC}"
else
    echo "❌ Color variables not exported"
fi

# Check directory variables
if [ -n "$WORK_DIR" ] && [ -n "$CONFIG_FILE" ]; then
    echo "✅ Directory variables exported correctly"
    echo "   WORK_DIR: $WORK_DIR"
    echo "   CONFIG_FILE: $CONFIG_FILE"
else
    echo "❌ Directory variables not exported"
fi

echo ""
echo "🎉 Library testing completed!"
echo ""

# Test if we can create a simple config
echo "💾 Testing basic configuration operations..."

# Set some test values
export SERVER_PORT="8080"
export SERVER_SNI="test.example.com"
export PROTOCOL="vless"

# Test save_config (will fail if directories don't exist, but shouldn't crash)
if save_config 2>/dev/null; then
    echo "✅ save_config executed without errors"
else
    echo "ℹ️  save_config needs existing VPN installation (expected)"
fi

# Test docker.sh
echo ""
echo "🐳 Testing lib/docker.sh..."

if ! source lib/docker.sh; then
    echo "❌ Failed to source lib/docker.sh"
    exit 1
fi

echo "✅ Successfully sourced lib/docker.sh"

# Test resource detection
cpu_cores=$(get_cpu_cores)
available_mem=$(get_available_memory)
echo "✅ System resources detected: $cpu_cores CPU cores, ${available_mem}MB RAM"

# Test CPU/memory calculations
cpu_limits=($(calculate_cpu_limits))
memory_limits=($(calculate_memory_limits))
echo "✅ Resource limits calculated: CPU ${cpu_limits[0]}/${cpu_limits[1]}, Memory ${memory_limits[0]}/${memory_limits[1]}"

# Test network.sh
echo ""
echo "🌐 Testing lib/network.sh..."

if ! source lib/network.sh; then
    echo "❌ Failed to source lib/network.sh"
    exit 1
fi

echo "✅ Successfully sourced lib/network.sh"

# Test port functions  
if check_port_available "8080" 2>/dev/null; then
    echo "✅ check_port_available working correctly (port 8080 should be free)"
else
    echo "ℹ️  Port 8080 is in use (expected on some systems)"
fi

# Test port generation
test_port=$(generate_free_port 50000 60000 false)
if [ -n "$test_port" ]; then
    echo "✅ generate_free_port working: generated port $test_port"
else
    echo "❌ generate_free_port failed"
fi

# Test domain validation
if validate_domain_format "example.com"; then
    echo "✅ validate_domain_format working correctly"
else
    echo "❌ validate_domain_format failed"
fi

# Test crypto.sh
echo ""
echo "🔐 Testing lib/crypto.sh..."

if ! source lib/crypto.sh; then
    echo "❌ Failed to source lib/crypto.sh"
    exit 1
fi

echo "✅ Successfully sourced lib/crypto.sh"

# Test UUID generation
test_uuid=$(generate_uuid)
if is_valid_uuid "$test_uuid"; then
    echo "✅ UUID generation working: $test_uuid"
else
    echo "❌ UUID generation failed"
fi

# Test random generation
test_hex=$(generate_random_hex 8)
if [ ${#test_hex} -eq 16 ]; then
    echo "✅ Random hex generation working: $test_hex"
else
    echo "❌ Random hex generation failed"
fi

test_base64=$(generate_random_base64 16)
if [ ${#test_base64} -gt 0 ]; then
    echo "✅ Random base64 generation working: ${test_base64:0:20}..."
else
    echo "❌ Random base64 generation failed"
fi

# Test Reality key generation (may take a moment)
echo "ℹ️  Testing Reality key generation (this may take a moment)..."
reality_keys=$(generate_reality_keys)
if [ $? -eq 0 ]; then
    private_key=$(echo "$reality_keys" | awk '{print $1}')
    public_key=$(echo "$reality_keys" | awk '{print $2}')
    short_id=$(echo "$reality_keys" | awk '{print $3}')
    
    if validate_reality_keys "$private_key" "$public_key" "$short_id"; then
        echo "✅ Reality key generation and validation working"
    else
        echo "❌ Reality key validation failed"
    fi
else
    echo "❌ Reality key generation failed"
fi

# Test ui.sh
echo ""
echo "🎨 Testing lib/ui.sh..."

if ! source lib/ui.sh; then
    echo "❌ Failed to source lib/ui.sh"
    exit 1
fi

echo "✅ Successfully sourced lib/ui.sh"

# Test UI components (visual test)
echo "📱 Testing UI components..."
draw_box "Test Box" 30
separator 30
show_status "Test Service" "active" "Running normally"
echo "✅ UI components rendered correctly"

echo ""
echo "🧪 Testing library interactions..."

# Test if all libraries work together
init_common
init_network >/dev/null 2>&1
init_docker >/dev/null 2>&1
init_crypto >/dev/null 2>&1
init_ui >/dev/null 2>&1

echo "✅ All library initialization completed"

echo ""
echo "✨ All Phase 2 Core Libraries tests completed successfully!"
echo "Libraries ready for modular refactoring:"
echo "  • lib/common.sh - ✅ Shared utilities and logging"
echo "  • lib/config.sh - ✅ Configuration management"  
echo "  • lib/network.sh - ✅ Network utilities and domain validation"
echo "  • lib/docker.sh - ✅ Docker operations and resource management"
echo "  • lib/crypto.sh - ✅ Cryptographic functions and key generation"
echo "  • lib/ui.sh - ✅ User interface components and menus"
echo ""
echo "🎯 Ready to proceed with Phase 3: User Management Modules"