#!/bin/bash
#
# Test script for User Management Modules
# Tests all Phase 3 user management functionality
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
    TEST_DIR="/tmp/vpn_module_test_$$"
    mkdir -p "$TEST_DIR"
    export TEST_DIR
    
    # Mock configuration for testing
    WORK_DIR="$TEST_DIR/v2ray"
    CONFIG_FILE="$WORK_DIR/config/config.json"
    USERS_DIR="$WORK_DIR/users"
    
    mkdir -p "$WORK_DIR/config"
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
    test_info "Testing module loading..."
    
    local modules=("add.sh" "delete.sh" "edit.sh" "list.sh" "show.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/users/$module"
        
        run_test "Load module: $module" "[ -f '$module_path' ]"
        
        if [ -f "$module_path" ]; then
            run_test "Source module: $module" "source '$module_path'"
        fi
    done
}

# Test library dependencies
test_library_dependencies() {
    test_info "Testing library dependencies..."
    
    local libraries=("common.sh" "config.sh" "crypto.sh" "ui.sh")
    
    for lib in "${libraries[@]}"; do
        local lib_path="$PROJECT_DIR/lib/$lib"
        run_test "Library exists: $lib" "[ -f '$lib_path' ]"
    done
}

# Test function exports
test_function_exports() {
    test_info "Testing function exports..."
    
    # Source all modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/crypto.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/add.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/delete.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/edit.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/list.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/show.sh" 2>/dev/null || true
    
    # Test key functions exist
    local functions=(
        "add_user"
        "delete_user" 
        "edit_user"
        "list_users"
        "show_user"
        "validate_user_input"
        "get_user_count"
        "init_user_add"
        "init_user_delete"
        "init_user_edit"
        "init_user_list"
        "init_user_show"
    )
    
    for func in "${functions[@]}"; do
        run_test "Function exported: $func" "declare -F '$func' >/dev/null"
    done
}

# Test user list functionality
test_list_functionality() {
    test_info "Testing user list functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/list.sh" 2>/dev/null || true
    
    # Test user count
    run_test "Get user count" "get_user_count | grep -q '^2$'"
    
    # Test user names retrieval  
    run_test "Get user names" "get_user_names | grep -q 'testuser1'"
    
    # Test table formatting functions
    run_test "Format table header" "format_table_header | grep -q '╔'"
    run_test "Format table footer" "format_table_footer | grep -q '╚'"
}

# Test validation functions
test_validation_functions() {
    test_info "Testing validation functions..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/add.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/delete.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/edit.sh" 2>/dev/null || true
    
    # Test user existence validation (should pass for existing user)
    run_test "Validate existing user" "validate_user_exists 'testuser1'"
    
    # Test user input validation
    run_test "Valid user input" "validate_user_input 'newuser' '12345678-1234-1234-1234-123456789012'"
}

# Test configuration functions
test_configuration_functions() {
    test_info "Testing configuration functions..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/show.sh" 2>/dev/null || true
    
    # Test server info retrieval
    run_test "Get server info" "get_server_info"
    
    # Test user config ensuring
    run_test "Ensure user config" "ensure_user_config 'testuser1'"
}

# Test connection link generation
test_connection_links() {
    test_info "Testing connection link generation..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/crypto.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/add.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/show.sh" 2>/dev/null || true
    
    # Mock server info
    SERVER_IP="127.0.0.1"
    SERVER_PORT="10443"
    SERVER_SNI="addons.mozilla.org"
    USE_REALITY=true
    PUBLIC_KEY="YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc"
    SHORT_ID="0453245bd68b99ae"
    
    # Test connection link generation
    run_test "Generate connection link" "generate_connection_link 'testuser' '12345678-1234-1234-1234-123456789012' 'ab12cd34' | grep -q 'vless://'"
}

# Test file operations
test_file_operations() {
    test_info "Testing file operations..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/add.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/delete.sh" 2>/dev/null || true
    
    # Mock server info
    SERVER_IP="127.0.0.1"
    SERVER_PORT="10443"
    SERVER_SNI="addons.mozilla.org"
    USE_REALITY=true
    PRIVATE_KEY="c29567a5ff1928bcf525e2d4016f7d7ce6f3c14c25c6aacc1998de43ba7b6a3e"
    PUBLIC_KEY="YEeEMaiyHISSdUKXD5s08OnZ6KQIyDmtlDfK-XmU-hc"
    SHORT_ID="0453245bd68b99ae"
    PROTOCOL="vless+reality"
    
    # Test user config creation
    run_test "Create user config" "create_user_config 'testuser3' '12345678-1234-1234-1234-123456789012' 'ab12cd34ef'"
    
    # Test config file exists
    run_test "Config file created" "[ -f '$USERS_DIR/testuser3.json' ]"
    
    # Test config file content
    run_test "Config file content" "grep -q 'testuser3' '$USERS_DIR/testuser3.json'"
    
    # Test file cleanup
    run_test "Cleanup user files" "cleanup_user_files 'testuser3'"
    
    # Test file removed
    run_test "Config file removed" "[ ! -f '$USERS_DIR/testuser3.json' ]"
}

# Test initialization functions
test_initialization() {
    test_info "Testing module initialization..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/add.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/delete.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/edit.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/list.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/users/show.sh" 2>/dev/null || true
    
    # Test initialization functions
    run_test "Initialize user add" "init_user_add"
    run_test "Initialize user delete" "init_user_delete"
    run_test "Initialize user edit" "init_user_edit"
    run_test "Initialize user list" "init_user_list"
    run_test "Initialize user show" "init_user_show"
}

# Test module permissions
test_module_permissions() {
    test_info "Testing module permissions..."
    
    local modules=("add.sh" "delete.sh" "edit.sh" "list.sh" "show.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/users/$module"
        run_test "Module executable: $module" "[ -x '$module_path' ]"
    done
}

# Test module syntax
test_module_syntax() {
    test_info "Testing module syntax..."
    
    local modules=("add.sh" "delete.sh" "edit.sh" "list.sh" "show.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/users/$module"
        run_test "Module syntax: $module" "bash -n '$module_path'"
    done
}

# Main test execution
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              ${GREEN}VPN User Management Modules Test Suite${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Run all tests
    test_module_loading
    test_library_dependencies
    test_function_exports
    test_list_functionality
    test_validation_functions
    test_configuration_functions
    test_connection_links
    test_file_operations
    test_initialization
    test_module_permissions
    test_module_syntax
    
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
        test_log "🎉 All tests passed! User management modules are ready."
        return 0
    else
        test_error "❌ Some tests failed. Please review the modules."
        return 1
    fi
}

# Run main function
main "$@"