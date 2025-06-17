#!/bin/bash
#
# Test script for Server Management Modules
# Tests all Phase 4 server management functionality
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test logging functions
test_log() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

test_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

test_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Test execution function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    test_info "Running: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        test_log "✅ PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        test_error "❌ FAILED: $test_name"
        return 1
    fi
}

# Setup test environment
setup_test_environment() {
    test_info "Setting up test environment..."
    
    # Set project directory
    PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export PROJECT_DIR
    
    # Create temporary test directory
    TEST_DIR="/tmp/vpn_server_test_$$"
    mkdir -p "$TEST_DIR"
    export TEST_DIR
    
    # Mock configuration for testing
    WORK_DIR="$TEST_DIR/v2ray"
    CONFIG_FILE="$WORK_DIR/config/config.json"
    USERS_DIR="$WORK_DIR/users"
    
    mkdir -p "$WORK_DIR/config"
    mkdir -p "$WORK_DIR/logs"
    mkdir -p "$USERS_DIR"
    
    # Create mock configuration file
    cat > "$CONFIG_FILE" <<EOL
{
  "inbounds": [
    {
      "port": 10443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "12345678-1234-1234-1234-123456789012",
            "email": "testuser1",
            "flow": "xtls-rprx-vision"
          },
          {
            "id": "87654321-4321-4321-4321-210987654321",
            "email": "testuser2",
            "flow": "xtls-rprx-vision"
          }
        ]
      },
      "streamSettings": {
        "security": "reality",
        "realitySettings": {
          "privateKey": "c29567a5ff1928bcf525e2d4016f7d7ce6f3c14c25c6aacc1998de43ba7b6a3e",
          "shortIds": ["0453245bd68b99ae", "ab12cd34ef567890"]
        }
      }
    }
  ]
}
EOL
    
    # Create mock server configuration files
    echo "10443" > "$WORK_DIR/config/port.txt"
    echo "addons.mozilla.org" > "$WORK_DIR/config/sni.txt"
    echo "vless+reality" > "$WORK_DIR/config/protocol.txt"
    echo "c29567a5ff1928bcf525e2d4016f7d7ce6f3c14c25c6aacc1998de43ba7b6a3e" > "$WORK_DIR/config/private_key.txt"
    echo "YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc" > "$WORK_DIR/config/public_key.txt"
    echo "0453245bd68b99ae" > "$WORK_DIR/config/short_id.txt"
    echo "true" > "$WORK_DIR/config/use_reality.txt"
    
    # Create mock docker-compose file
    cat > "$WORK_DIR/docker-compose.yml" <<EOL
version: '3.8'
services:
  xray:
    image: teddysun/xray:latest
    container_name: xray
    restart: unless-stopped
    ports:
      - "10443:10443"
    volumes:
      - ./config:/opt/v2ray/config
      - ./logs:/opt/v2ray/logs
    networks:
      - xray-net

networks:
  xray-net:
    driver: bridge
EOL
    
    # Create mock log files
    touch "$WORK_DIR/logs/access.log"
    touch "$WORK_DIR/logs/error.log"
    
    # Create mock user files
    cat > "$USERS_DIR/testuser1.json" <<EOL
{
  "name": "testuser1",
  "uuid": "12345678-1234-1234-1234-123456789012",
  "port": 10443,
  "server": "127.0.0.1",
  "sni": "addons.mozilla.org",
  "private_key": "c29567a5ff1928bcf525e2d4016f7d7ce6f3c14c25c6aacc1998de43ba7b6a3e",
  "public_key": "YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc",
  "short_id": "0453245bd68b99ae",
  "protocol": "vless+reality"
}
EOL
    
    echo "vless://testuser1@127.0.0.1:10443" > "$USERS_DIR/testuser1.link"
    
    # Export variables for modules
    export WORK_DIR CONFIG_FILE USERS_DIR
    
    test_log "Test environment setup completed"
}

# Cleanup test environment
cleanup_test_environment() {
    test_info "Cleaning up test environment..."
    
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        test_log "Test directory cleaned up: $TEST_DIR"
    fi
}

# Test module loading
test_module_loading() {
    test_info "Testing server module loading..."
    
    local modules=("status.sh" "restart.sh" "rotate_keys.sh" "uninstall.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/server/$module"
        
        run_test "Load module: $module" "[ -f '$module_path' ]"
        
        if [ -f "$module_path" ]; then
            run_test "Source module: $module" "source '$module_path'"
        fi
    done
}

# Test library dependencies
test_library_dependencies() {
    test_info "Testing library dependencies..."
    
    local libraries=("common.sh" "config.sh" "docker.sh" "network.sh" "crypto.sh" "ui.sh")
    
    for lib in "${libraries[@]}"; do
        local lib_path="$PROJECT_DIR/lib/$lib"
        run_test "Library exists: $lib" "[ -f '$lib_path' ]"
    done
}

# Test function exports
test_function_exports() {
    test_info "Testing function exports..."
    
    # Source all required libraries and modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/network.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/crypto.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/status.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/restart.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/rotate_keys.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/uninstall.sh" 2>/dev/null || true
    
    # Test key functions exist
    local functions=(
        "show_status"
        "restart_server"
        "rotate_reality_keys"
        "uninstall_vpn"
        "init_server_status"
        "init_server_restart"
        "init_key_rotation"
        "init_server_uninstall"
        "check_container_status"
        "validate_configuration"
        "validate_reality_usage"
        "display_uninstall_warning"
        "quick_status"
        "force_restart"
        "emergency_rotate_keys"
        "force_uninstall"
    )
    
    for func in "${functions[@]}"; do
        run_test "Function exported: $func" "declare -F '$func' >/dev/null"
    done
}

# Test status module functionality
test_status_functionality() {
    test_info "Testing status module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/network.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/status.sh" 2>/dev/null || true
    
    # Test status functions
    run_test "Initialize status module" "init_server_status"
    run_test "Display server info" "display_server_info >/dev/null 2>&1"
    run_test "Display user statistics" "display_user_statistics >/dev/null 2>&1"
    run_test "Check system resources" "check_system_resources >/dev/null 2>&1"
    run_test "Quick status check" "quick_status | grep -q 'Status:'"
}

# Test restart module functionality
test_restart_functionality() {
    test_info "Testing restart module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/restart.sh" 2>/dev/null || true
    
    # Test restart functions
    run_test "Initialize restart module" "init_server_restart"
    run_test "Validate configuration" "validate_configuration"
    run_test "Prepare logs" "prepare_logs"
    run_test "Validate port configuration" "validate_port_configuration"
    run_test "Check port conflicts" "check_port_conflicts '10443'"
}

# Test key rotation module functionality
test_key_rotation_functionality() {
    test_info "Testing key rotation module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/crypto.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/rotate_keys.sh" 2>/dev/null || true
    
    # Test key rotation functions
    run_test "Initialize key rotation" "init_key_rotation"
    run_test "Validate Reality usage" "validate_reality_usage"
    run_test "Create config backup" "create_configuration_backup | grep -q '.backup.'"
    run_test "Show current keys" "show_current_keys >/dev/null 2>&1"
}

# Test uninstall module functionality
test_uninstall_functionality() {
    test_info "Testing uninstall module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/uninstall.sh" 2>/dev/null || true
    
    # Test uninstall functions
    run_test "Initialize uninstall module" "init_server_uninstall"
    run_test "Display uninstall warning" "display_uninstall_warning >/dev/null 2>&1"
    run_test "Show removal preview" "show_removal_preview >/dev/null 2>&1"
    run_test "Cleanup systemd services" "cleanup_systemd_services >/dev/null 2>&1"
    run_test "Cleanup cron jobs" "cleanup_cron_jobs >/dev/null 2>&1"
}

# Test configuration validation
test_configuration_validation() {
    test_info "Testing configuration validation..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/restart.sh" 2>/dev/null || true
    
    # Test configuration validation
    run_test "Valid JSON configuration" "jq empty '$CONFIG_FILE'"
    run_test "Configuration has port" "jq -e '.inbounds[0].port' '$CONFIG_FILE' >/dev/null"
    run_test "Configuration has protocol" "jq -e '.inbounds[0].protocol' '$CONFIG_FILE' >/dev/null"
    run_test "Configuration validation passes" "validate_configuration"
}

# Test file operations
test_file_operations() {
    test_info "Testing file operations..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/rotate_keys.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/restart.sh" 2>/dev/null || true
    
    # Test backup creation
    run_test "Create configuration backup" "create_configuration_backup | grep -q 'backup'"
    
    # Test log preparation
    run_test "Prepare logs directory" "prepare_logs && [ -d '$WORK_DIR/logs' ]"
    
    # Test file existence checks
    run_test "Config file exists" "[ -f '$CONFIG_FILE' ]"
    run_test "Users directory exists" "[ -d '$USERS_DIR' ]"
    run_test "Reality config exists" "[ -f '$WORK_DIR/config/use_reality.txt' ]"
}

# Test error handling
test_error_handling() {
    test_info "Testing error handling..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/restart.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/rotate_keys.sh" 2>/dev/null || true
    
    # Test with invalid configuration
    local invalid_config="$TEST_DIR/invalid.json"
    echo "{ invalid json" > "$invalid_config"
    
    # Save original config file
    local original_config="$CONFIG_FILE"
    CONFIG_FILE="$invalid_config"
    
    # Test that validation catches invalid JSON
    run_test "Invalid JSON detected" "! validate_configuration 2>/dev/null"
    
    # Restore original config
    CONFIG_FILE="$original_config"
    
    # Test with missing Reality config
    mv "$WORK_DIR/config/use_reality.txt" "$WORK_DIR/config/use_reality.txt.bak"
    run_test "Missing Reality config detected" "! validate_reality_usage 2>/dev/null"
    mv "$WORK_DIR/config/use_reality.txt.bak" "$WORK_DIR/config/use_reality.txt"
}

# Test module permissions
test_module_permissions() {
    test_info "Testing module permissions..."
    
    local modules=("status.sh" "restart.sh" "rotate_keys.sh" "uninstall.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/server/$module"
        run_test "Module executable: $module" "[ -x '$module_path' ]"
    done
}

# Test module syntax
test_module_syntax() {
    test_info "Testing module syntax..."
    
    local modules=("status.sh" "restart.sh" "rotate_keys.sh" "uninstall.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/server/$module"
        run_test "Module syntax: $module" "bash -n '$module_path'"
    done
}

# Test cross-module integration
test_cross_module_integration() {
    test_info "Testing cross-module integration..."
    
    # Source all modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/network.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/crypto.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/status.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/restart.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/rotate_keys.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/server/uninstall.sh" 2>/dev/null || true
    
    # Test that modules can access each other's functions
    run_test "Status from restart module" "init_server_status && init_server_restart"
    run_test "Config shared between modules" "get_server_info >/dev/null 2>&1"
    run_test "Common functions available" "log 'Test message' >/dev/null 2>&1"
}

# Main test execution
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              ${GREEN}VPN Server Management Modules Test Suite${NC}            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Run all tests
    test_module_loading
    test_library_dependencies
    test_function_exports
    test_status_functionality
    test_restart_functionality
    test_key_rotation_functionality
    test_uninstall_functionality
    test_configuration_validation
    test_file_operations
    test_error_handling
    test_module_permissions
    test_module_syntax
    test_cross_module_integration
    
    # Cleanup
    cleanup_test_environment
    
    # Display results
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                         ${GREEN}Test Results${NC}                              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Total Tests:${NC} $TESTS_TOTAL"
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo ""
    
    # Calculate success rate
    if [ $TESTS_TOTAL -gt 0 ]; then
        local success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
        echo -e "  ${GREEN}Success Rate:${NC} ${success_rate}%"
    else
        echo -e "  ${YELLOW}No tests executed${NC}"
    fi
    
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        test_log "🎉 All tests passed! Server management modules are ready."
        return 0
    else
        test_error "❌ Some tests failed. Please review the modules."
        return 1
    fi
}

# Run main function
main "$@"