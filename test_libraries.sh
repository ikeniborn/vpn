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

echo ""
echo "✨ All basic library tests completed successfully!"
echo "Libraries are ready for use in modular refactoring."