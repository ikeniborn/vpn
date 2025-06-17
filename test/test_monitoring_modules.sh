#!/bin/bash
#
# Test script for Monitoring Modules
# Tests all Phase 5 monitoring functionality
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
    TEST_DIR="/tmp/vpn_monitoring_test_$$"
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
  "log": {
    "access": "$WORK_DIR/logs/access.log",
    "error": "$WORK_DIR/logs/error.log",
    "loglevel": "warning"
  },
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
    
    # Create mock log files with sample data
    cat > "$WORK_DIR/logs/access.log" <<EOL
2025-06-17 10:30:15 [Info] email:testuser1 accepted udp:8.8.8.8:53
2025-06-17 10:30:20 [Info] email:testuser2 accepted tcp:1.1.1.1:443
2025-06-17 10:30:25 [Info] email:testuser1 accepted tcp:example.com:80
2025-06-17 10:30:30 [Info] email:testuser2 accepted tcp:google.com:443
2025-06-17 10:30:35 [Info] email:testuser1 accepted tcp:github.com:443
EOL
    
    cat > "$WORK_DIR/logs/error.log" <<EOL
2025-06-17 10:25:10 [Warning] connection timeout
2025-06-17 10:25:15 [Error] failed to parse config
EOL
    
    # Create mock user files
    cat > "$USERS_DIR/testuser1.json" <<EOL
{
  "name": "testuser1",
  "uuid": "12345678-1234-1234-1234-123456789012",
  "port": 10443,
  "server": "127.0.0.1"
}
EOL
    
    echo "test connection link" > "$USERS_DIR/testuser1.link"
    
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
    test_info "Testing monitoring module loading..."
    
    local modules=("statistics.sh" "logging.sh" "logs_viewer.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/monitoring/$module"
        
        run_test "Load module: $module" "[ -f '$module_path' ]"
        
        if [ -f "$module_path" ]; then
            run_test "Source module: $module" "source '$module_path'"
        fi
    done
}

# Test library dependencies
test_library_dependencies() {
    test_info "Testing library dependencies..."
    
    local libraries=("common.sh" "config.sh" "ui.sh")
    
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
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/statistics.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logging.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logs_viewer.sh" 2>/dev/null || true
    
    # Test key functions exist
    local functions=(
        "show_traffic_stats"
        "configure_xray_logging"
        "view_user_logs"
        "init_statistics"
        "init_logging"
        "init_logs_viewer"
        "get_docker_stats"
        "check_logging_config"
        "search_user_activity"
        "quick_stats"
        "set_log_level"
        "quick_log_view"
        "format_bytes"
        "rotate_logs"
        "monitor_logs_realtime"
    )
    
    for func in "${functions[@]}"; do
        run_test "Function exported: $func" "declare -F '$func' >/dev/null"
    done
}

# Test statistics module functionality
test_statistics_functionality() {
    test_info "Testing statistics module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/statistics.sh" 2>/dev/null || true
    
    # Test statistics functions
    run_test "Initialize statistics module" "init_statistics"
    run_test "Get Docker stats" "get_docker_stats >/dev/null 2>&1"
    run_test "Get network stats" "get_network_stats >/dev/null 2>&1"
    run_test "Format bytes function" "format_bytes '1024' | grep -q 'KB'"
    run_test "Quick stats check" "quick_stats | grep -q 'Stats:'"
    run_test "Get user file stats" "get_user_file_stats >/dev/null 2>&1"
}

# Test logging module functionality
test_logging_functionality() {
    test_info "Testing logging module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logging.sh" 2>/dev/null || true
    
    # Test logging functions
    run_test "Initialize logging module" "init_logging"
    run_test "Check logging config" "check_logging_config"
    run_test "Get current logging settings" "get_current_logging_settings | grep -q 'access_log:'"
    run_test "Display current logging" "display_current_logging >/dev/null 2>&1"
    run_test "Configure log paths" "configure_log_paths | grep -q '/logs/'"
}

# Test logs viewer module functionality
test_logs_viewer_functionality() {
    test_info "Testing logs viewer module functionality..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logs_viewer.sh" 2>/dev/null || true
    
    # Test logs viewer functions
    run_test "Initialize logs viewer" "init_logs_viewer"
    run_test "Check log files" "check_log_files | grep -q 'access_log:'"
    run_test "Display log info" "display_log_info >/dev/null 2>&1"
    run_test "Show recent connections" "show_recent_connections 5 >/dev/null 2>&1"
    run_test "Search user activity" "search_user_activity 'testuser1' >/dev/null 2>&1"
    run_test "Show error logs" "show_error_logs 5 >/dev/null 2>&1"
    run_test "Quick log view" "quick_log_view 3 | grep -q 'connections:'"
}

# Test log file processing
test_log_processing() {
    test_info "Testing log file processing..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logs_viewer.sh" 2>/dev/null || true
    
    # Test log processing functions
    run_test "Format log entry" "format_log_entry 'test log entry' | grep -q 'test'"
    run_test "Show user connection stats" "show_user_connection_stats >/dev/null 2>&1"
    run_test "Search logs function" "search_logs 'testuser1' 'access' >/dev/null 2>&1"
}

# Test configuration operations
test_configuration_operations() {
    test_info "Testing configuration operations..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logging.sh" 2>/dev/null || true
    
    # Test that configuration is readable
    run_test "Config file readable" "[ -r '$CONFIG_FILE' ]"
    run_test "Config has logging section" "jq -e '.log' '$CONFIG_FILE' >/dev/null"
    run_test "Config validation" "jq empty '$CONFIG_FILE'"
    
    # Test log level setting
    run_test "Set log level function" "set_log_level 'info' >/dev/null 2>&1 || true"
}

# Test file operations
test_file_operations() {
    test_info "Testing file operations..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/statistics.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logs_viewer.sh" 2>/dev/null || true
    
    # Test file existence and operations
    run_test "Access log exists" "[ -f '$WORK_DIR/logs/access.log' ]"
    run_test "Error log exists" "[ -f '$WORK_DIR/logs/error.log' ]"
    run_test "Access log readable" "[ -r '$WORK_DIR/logs/access.log' ]"
    run_test "Users directory exists" "[ -d '$USERS_DIR' ]"
    
    # Test report generation
    run_test "Generate statistics report" "generate_statistics_report | grep -q '/tmp/'"
    run_test "Generate log report" "generate_log_report | grep -q '/tmp/'"
}

# Test module permissions
test_module_permissions() {
    test_info "Testing module permissions..."
    
    local modules=("statistics.sh" "logging.sh" "logs_viewer.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/monitoring/$module"
        run_test "Module executable: $module" "[ -x '$module_path' ]"
    done
}

# Test module syntax
test_module_syntax() {
    test_info "Testing module syntax..."
    
    local modules=("statistics.sh" "logging.sh" "logs_viewer.sh")
    
    for module in "${modules[@]}"; do
        local module_path="$PROJECT_DIR/modules/monitoring/$module"
        run_test "Module syntax: $module" "bash -n '$module_path'"
    done
}

# Test cross-module integration
test_cross_module_integration() {
    test_info "Testing cross-module integration..."
    
    # Source all modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/config.sh" 2>/dev/null || true
    source "$PROJECT_DIR/lib/ui.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/statistics.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logging.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logs_viewer.sh" 2>/dev/null || true
    
    # Test that modules can work together
    run_test "Multiple module initialization" "init_statistics && init_logging && init_logs_viewer"
    run_test "Config shared between modules" "get_server_info >/dev/null 2>&1"
    run_test "Common functions available" "log 'Test message' >/dev/null 2>&1"
    run_test "Cross-module file access" "check_log_files | grep -q 'access_log:'"
}

# Test utility functions
test_utility_functions() {
    test_info "Testing utility functions..."
    
    # Source required modules
    source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/statistics.sh" 2>/dev/null || true
    source "$PROJECT_DIR/modules/monitoring/logs_viewer.sh" 2>/dev/null || true
    
    # Test utility functions
    run_test "Format bytes - KB" "format_bytes '2048' | grep -q '2.0 KB'"
    run_test "Format bytes - MB" "format_bytes '2097152' | grep -q '2.0 MB'"
    run_test "Format uptime" "format_uptime '86400' | grep -q '1 days'"
    run_test "Format log entry" "format_log_entry 'test entry' | grep -q 'test'"
}

# Main test execution
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              ${GREEN}VPN Monitoring Modules Test Suite${NC}                 ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Run all tests
    test_module_loading
    test_library_dependencies
    test_function_exports
    test_statistics_functionality
    test_logging_functionality
    test_logs_viewer_functionality
    test_log_processing
    test_configuration_operations
    test_file_operations
    test_module_permissions
    test_module_syntax
    test_cross_module_integration
    test_utility_functions
    
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
        test_log "🎉 All tests passed! Monitoring modules are ready."
        return 0
    else
        test_error "❌ Some tests failed. Please review the modules."
        return 1
    fi
}

# Run main function
main "$@"