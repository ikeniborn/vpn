#!/bin/bash
#################################################
# WireGuard Modules Test Suite
# 
# Tests for WireGuard installation and user
# management modules
#################################################

set -euo pipefail

# Test configuration
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${TEST_DIR}/.."
readonly MODULES_DIR="${PROJECT_ROOT}/modules"

# Simple test framework (inline)
echo "🧪 Testing WireGuard Modules"
echo "============================"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    echo "Running test: $test_name"
    
    if $test_function; then
        echo "✅ PASS: $test_name"
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL: $test_name"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# Test WireGuard installation module
test_wireguard_installation_module() {
    local module="${MODULES_DIR}/install/wireguard_setup.sh"
    
    # Check if module exists
    [[ -f "$module" ]] || return 1
    
    # Check if module is executable
    [[ -x "$module" ]] || return 1
    
    # Source the module
    source "$module" || return 1
    
    # Check if required functions are defined
    command -v install_wireguard_server >/dev/null || return 1
    command -v generate_wireguard_keys >/dev/null || return 1
    command -v create_wireguard_config >/dev/null || return 1
    command -v configure_wireguard_firewall >/dev/null || return 1
    
    return 0
}

# Test WireGuard user management modules
test_wireguard_user_modules() {
    local add_module="${MODULES_DIR}/users/wireguard_add.sh"
    local list_module="${MODULES_DIR}/users/wireguard_list.sh"
    local remove_module="${MODULES_DIR}/users/wireguard_remove.sh"
    local menu_module="${MODULES_DIR}/users/wireguard_menu.sh"
    
    # Check if modules exist
    [[ -f "$add_module" ]] || return 1
    [[ -f "$list_module" ]] || return 1
    [[ -f "$remove_module" ]] || return 1
    [[ -f "$menu_module" ]] || return 1
    
    # Source the modules
    source "$add_module" || return 1
    source "$list_module" || return 1
    source "$remove_module" || return 1
    source "$menu_module" || return 1
    
    # Check if required functions are defined
    command -v add_wireguard_user >/dev/null || return 1
    command -v list_wireguard_users >/dev/null || return 1
    command -v remove_wireguard_user >/dev/null || return 1
    command -v show_wireguard_user_menu >/dev/null || return 1
    
    return 0
}

# Test firewall integration
test_wireguard_firewall_integration() {
    local firewall_module="${MODULES_DIR}/install/firewall.sh"
    
    # Check if firewall module exists and has WireGuard support
    [[ -f "$firewall_module" ]] || return 1
    
    # Source the module
    source "$firewall_module" || return 1
    
    # Check if WireGuard firewall functions are defined
    command -v setup_wireguard_firewall >/dev/null || return 1
    command -v setup_wireguard_routing >/dev/null || return 1
    
    return 0
}

# Test menu integration
test_wireguard_menu_integration() {
    local menu_module="${MODULES_DIR}/menu/server_installation.sh"
    
    # Check if menu module exists
    [[ -f "$menu_module" ]] || return 1
    
    # Check if WireGuard option is included in menu
    grep -q "wireguard" "$menu_module" || return 1
    grep -q "WireGuard" "$menu_module" || return 1
    
    # Source the module
    source "$menu_module" || return 1
    
    # Check if WireGuard configuration function is defined
    command -v configure_wireguard >/dev/null || return 1
    command -v get_wireguard_port_config_interactive >/dev/null || return 1
    command -v setup_wireguard_server >/dev/null || return 1
    
    return 0
}

# Test module syntax
test_wireguard_module_syntax() {
    local modules=(
        "${MODULES_DIR}/install/wireguard_setup.sh"
        "${MODULES_DIR}/users/wireguard_add.sh"
        "${MODULES_DIR}/users/wireguard_list.sh"
        "${MODULES_DIR}/users/wireguard_remove.sh"
        "${MODULES_DIR}/users/wireguard_menu.sh"
    )
    
    for module in "${modules[@]}"; do
        [[ -f "$module" ]] || return 1
        bash -n "$module" || return 1
    done
    
    return 0
}

# Test WireGuard constants and configuration
test_wireguard_configuration() {
    local module="${MODULES_DIR}/install/wireguard_setup.sh"
    
    # Source the module
    source "$module" || return 1
    
    # Check if required constants are defined
    [[ -n "${WIREGUARD_DIR:-}" ]] || return 1
    [[ -n "${WIREGUARD_SUBNET:-}" ]] || return 1
    [[ -n "${WIREGUARD_SERVER_IP:-}" ]] || return 1
    [[ -n "${WIREGUARD_DNS:-}" ]] || return 1
    [[ -n "${WIREGUARD_IMAGE:-}" ]] || return 1
    
    # Validate configuration values
    [[ "$WIREGUARD_DIR" == "/opt/wireguard" ]] || return 1
    [[ "$WIREGUARD_SUBNET" == "10.66.66.0/24" ]] || return 1
    [[ "$WIREGUARD_SERVER_IP" == "10.66.66.1" ]] || return 1
    
    return 0
}

# Main test execution
main() {
    echo "🧪 Starting WireGuard Modules Test Suite"
    echo "========================================"
    echo ""
    
    # Run all tests
    run_test "WireGuard Installation Module" test_wireguard_installation_module
    run_test "WireGuard User Management Modules" test_wireguard_user_modules
    run_test "WireGuard Firewall Integration" test_wireguard_firewall_integration
    run_test "WireGuard Menu Integration" test_wireguard_menu_integration
    run_test "WireGuard Module Syntax" test_wireguard_module_syntax
    run_test "WireGuard Configuration" test_wireguard_configuration
    
    # Print summary
    echo "========================================="
    echo "Test Summary:"
    echo "  Total tests: $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "🎉 All tests passed!"
        exit 0
    else
        echo "❌ Some tests failed!"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi