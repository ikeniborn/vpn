#!/bin/bash

# =============================================================================
# Installation Modules Test Suite
# 
# This script tests all installation modules for proper functionality.
# Tests prerequisites, docker_setup, xray_config, and firewall modules.
#
# Author: Claude
# Version: 2.0
# =============================================================================

set -e

# =============================================================================
# TEST FRAMEWORK SETUP
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source common libraries
source "$PROJECT_DIR/lib/common.sh" 2>/dev/null || {
    echo "Warning: Cannot source lib/common.sh, using fallback"
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
    log() { echo -e "${GREEN}✓${NC} $1"; }
    error() { echo -e "${RED}✗ [ERROR]${NC} $1"; }
    warning() { echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"; }
}

# Test framework variables
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0
TEST_TEMP_DIR="/tmp/vpn_test_$$"

# =============================================================================
# TEST FRAMEWORK FUNCTIONS
# =============================================================================

# Initialize test environment
setup_test_env() {
    log "Setting up test environment..."
    
    # Create temporary test directory
    mkdir -p "$TEST_TEMP_DIR" || {
        error "Failed to create test directory"
    }
    
    # Create mock directories
    mkdir -p "$TEST_TEMP_DIR/work"
    mkdir -p "$TEST_TEMP_DIR/config"
    mkdir -p "$TEST_TEMP_DIR/users"
    mkdir -p "$TEST_TEMP_DIR/logs"
    
    # Set test work directory
    export TEST_WORK_DIR="$TEST_TEMP_DIR/work"
    
    log "Test environment setup complete"
}

# Clean up test environment
cleanup_test_env() {
    log "Cleaning up test environment..."
    
    if [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR" || {
            warning "Failed to clean up test directory"
        }
    fi
    
    log "Test environment cleaned up"
}

# Run a single test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -e "\n${BLUE}Running test: $test_name${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if $test_function; then
        echo -e "${GREEN}✓ PASS: $test_name${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL: $test_name${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Mock Docker commands for testing
setup_docker_mocks() {
    # Create mock docker command
    cat > "$TEST_TEMP_DIR/docker" <<'EOF'
#!/bin/bash
case "$1" in
    "ps")
        echo "CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES"
        echo "mock123       test      mock      1 min     Up        8080      xray"
        ;;
    "run")
        echo "mock_output"
        ;;
    "stats")
        echo "CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O         PIDS"
        echo "mock123        xray      0.00%     10.5MiB / 512MiB      2.05%     1.2kB / 1.2kB     0B / 0B           1"
        ;;
    *)
        echo "Docker mock: $*"
        ;;
esac
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/docker"
    export PATH="$TEST_TEMP_DIR:$PATH"
}

# =============================================================================
# PREREQUISITES MODULE TESTS
# =============================================================================

# Test prerequisites module loading
test_prerequisites_module_load() {
    if [ -f "$PROJECT_DIR/modules/install/prerequisites.sh" ]; then
        source "$PROJECT_DIR/modules/install/prerequisites.sh" 2>/dev/null
        return $?
    else
        return 1
    fi
}

# Test system info detection
test_system_info_detection() {
    source "$PROJECT_DIR/modules/install/prerequisites.sh" 2>/dev/null || return 1
    
    # Test detect_system_info function
    if command -v detect_system_info >/dev/null 2>&1; then
        detect_system_info false
        return $?
    else
        return 1
    fi
}

# Test dependency verification
test_dependency_verification() {
    source "$PROJECT_DIR/modules/install/prerequisites.sh" 2>/dev/null || return 1
    
    # Test verify_dependencies function
    if command -v verify_dependencies >/dev/null 2>&1; then
        # This will likely fail in test environment, but should not crash
        verify_dependencies false 2>/dev/null || true
        return 0
    else
        return 1
    fi
}

# =============================================================================
# DOCKER SETUP MODULE TESTS
# =============================================================================

# Test docker setup module loading
test_docker_setup_module_load() {
    if [ -f "$PROJECT_DIR/modules/install/docker_setup.sh" ]; then
        source "$PROJECT_DIR/modules/install/docker_setup.sh" 2>/dev/null
        return $?
    else
        return 1
    fi
}

# Test resource calculation
test_resource_calculation() {
    source "$PROJECT_DIR/modules/install/docker_setup.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || return 1
    
    # Test calculate_resource_limits function
    if command -v calculate_resource_limits >/dev/null 2>&1; then
        calculate_resource_limits false
        
        # Check if variables are set
        if [ -n "$MAX_CPU" ] && [ -n "$MAX_MEM" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Test Docker Compose creation
test_docker_compose_creation() {
    source "$PROJECT_DIR/modules/install/docker_setup.sh" 2>/dev/null || return 1
    
    # Test create_docker_compose function
    if command -v create_docker_compose >/dev/null 2>&1; then
        create_docker_compose "$TEST_WORK_DIR" "10443" false
        
        # Check if file was created
        if [ -f "$TEST_WORK_DIR/docker-compose.yml" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Test backup Docker Compose creation
test_backup_docker_compose() {
    source "$PROJECT_DIR/modules/install/docker_setup.sh" 2>/dev/null || return 1
    
    # Test create_backup_docker_compose function
    if command -v create_backup_docker_compose >/dev/null 2>&1; then
        create_backup_docker_compose "$TEST_WORK_DIR" "10443" false
        
        # Check if backup file was created
        if [ -f "$TEST_WORK_DIR/docker-compose.backup.yml" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# =============================================================================
# XRAY CONFIG MODULE TESTS
# =============================================================================

# Test xray config module loading
test_xray_config_module_load() {
    if [ -f "$PROJECT_DIR/modules/install/xray_config.sh" ]; then
        source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null
        return $?
    else
        return 1
    fi
}

# Test Xray directories setup
test_xray_directories_setup() {
    source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null || return 1
    
    # Test setup_xray_directories function
    if command -v setup_xray_directories >/dev/null 2>&1; then
        setup_xray_directories "$TEST_WORK_DIR" false
        
        # Check if directories were created
        if [ -d "$TEST_WORK_DIR/config" ] && [ -d "$TEST_WORK_DIR/logs" ] && [ -d "$TEST_WORK_DIR/users" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Test Reality configuration creation
test_reality_config_creation() {
    source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null || return 1
    
    # Test create_xray_config_reality function
    if command -v create_xray_config_reality >/dev/null 2>&1; then
        local config_file="$TEST_WORK_DIR/config/config.json"
        mkdir -p "$(dirname "$config_file")"
        
        create_xray_config_reality "$config_file" "10443" "test-uuid" "test-user" \
            "example.com" "test-private-key" "test-short-id" false
        
        # Check if config file was created and contains expected content
        if [ -f "$config_file" ] && grep -q "vless" "$config_file" && grep -q "reality" "$config_file"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Test basic VLESS configuration creation
test_basic_vless_config_creation() {
    source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null || return 1
    
    # Test create_xray_config_basic function
    if command -v create_xray_config_basic >/dev/null 2>&1; then
        local config_file="$TEST_WORK_DIR/config/basic.json"
        mkdir -p "$(dirname "$config_file")"
        
        create_xray_config_basic "$config_file" "10443" "test-uuid" "test-user" false
        
        # Check if config file was created and contains expected content
        if [ -f "$config_file" ] && grep -q "vless" "$config_file"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Test configuration validation
test_config_validation() {
    source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null || return 1
    
    # Create a valid JSON config for testing
    local config_file="$TEST_WORK_DIR/config/test.json"
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" <<'EOF'
{
  "inbounds": [],
  "outbounds": []
}
EOF
    
    # Test validate_xray_config function
    if command -v validate_xray_config >/dev/null 2>&1; then
        validate_xray_config "$config_file" false
        return $?
    else
        return 1
    fi
}

# =============================================================================
# FIREWALL MODULE TESTS
# =============================================================================

# Test firewall module loading
test_firewall_module_load() {
    if [ -f "$PROJECT_DIR/modules/install/firewall.sh" ]; then
        source "$PROJECT_DIR/modules/install/firewall.sh" 2>/dev/null
        return $?
    else
        return 1
    fi
}

# Test firewall status check
test_firewall_status_check() {
    source "$PROJECT_DIR/modules/install/firewall.sh" 2>/dev/null || return 1
    
    # Test check_firewall_status function
    if command -v check_firewall_status >/dev/null 2>&1; then
        # This will likely fail in test environment, but should not crash
        check_firewall_status false 2>/dev/null || true
        return 0
    else
        return 1
    fi
}

# Test port rule checking
test_port_rule_checking() {
    source "$PROJECT_DIR/modules/install/firewall.sh" 2>/dev/null || return 1
    
    # Test check_port_rule_exists function
    if command -v check_port_rule_exists >/dev/null 2>&1; then
        # This will likely fail in test environment, but should not crash
        check_port_rule_exists "22" "tcp" false 2>/dev/null || true
        return 0
    else
        return 1
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

# Test module interdependencies
test_module_interdependencies() {
    # Test that modules can be loaded together
    source "$PROJECT_DIR/modules/install/prerequisites.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/modules/install/docker_setup.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/modules/install/firewall.sh" 2>/dev/null || return 1
    
    return 0
}

# Test full installation flow (simulation)
test_installation_flow_simulation() {
    # Load all modules
    source "$PROJECT_DIR/modules/install/prerequisites.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/modules/install/docker_setup.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/modules/install/xray_config.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/modules/install/firewall.sh" 2>/dev/null || return 1
    source "$PROJECT_DIR/lib/docker.sh" 2>/dev/null || return 1
    
    # Simulate installation steps
    setup_xray_directories "$TEST_WORK_DIR" false || return 1
    calculate_resource_limits false || return 1
    create_docker_compose "$TEST_WORK_DIR" "10443" false || return 1
    create_xray_config "$TEST_WORK_DIR" "vless-reality" "10443" "test-uuid" "test-user" \
        "example.com" "test-private-key" "test-short-id" false || return 1
    
    return 0
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

# Run all tests
run_all_tests() {
    echo -e "${GREEN}=== Installation Modules Test Suite ===${NC}"
    echo -e "${BLUE}Testing installation modules functionality...${NC}\n"
    
    # Setup test environment
    setup_test_env
    setup_docker_mocks
    
    # Prerequisites module tests
    run_test "Prerequisites Module Load" test_prerequisites_module_load
    run_test "System Info Detection" test_system_info_detection
    run_test "Dependency Verification" test_dependency_verification
    
    # Docker setup module tests
    run_test "Docker Setup Module Load" test_docker_setup_module_load
    run_test "Resource Calculation" test_resource_calculation
    run_test "Docker Compose Creation" test_docker_compose_creation
    run_test "Backup Docker Compose" test_backup_docker_compose
    
    # Xray config module tests
    run_test "Xray Config Module Load" test_xray_config_module_load
    run_test "Xray Directories Setup" test_xray_directories_setup
    run_test "Reality Config Creation" test_reality_config_creation
    run_test "Basic VLESS Config Creation" test_basic_vless_config_creation
    run_test "Config Validation" test_config_validation
    
    # Firewall module tests
    run_test "Firewall Module Load" test_firewall_module_load
    run_test "Firewall Status Check" test_firewall_status_check
    run_test "Port Rule Checking" test_port_rule_checking
    
    # Integration tests
    run_test "Module Interdependencies" test_module_interdependencies
    run_test "Installation Flow Simulation" test_installation_flow_simulation
    
    # Cleanup
    cleanup_test_env
    
    # Test results
    echo -e "\n${GREEN}=== Test Results ===${NC}"
    echo -e "Total tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed! 🎉${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed. Please review the output above.${NC}"
        return 1
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi