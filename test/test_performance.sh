#!/bin/bash

# =============================================================================
# Performance Testing Module
# 
# This module tests the performance optimizations implemented in the VPN system
# according to OPTIMIZATION.md specifications.
#
# Test Categories:
# - Module loading performance 
# - Docker operations caching
# - String operations optimization
# - File operations optimization
# - Memory usage monitoring
#
# Dependencies: lib/performance.sh, test/test_common.sh
# =============================================================================

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source performance library
source "$PROJECT_ROOT/lib/performance.sh" || {
    echo "❌ Failed to load performance library"
    exit 1
}

# Test configuration
TEST_ITERATIONS=10
TEST_TIMEOUT=30

# =============================================================================
# PERFORMANCE TEST RESULTS
# =============================================================================

declare -A PERFORMANCE_RESULTS
TEST_COUNT=0
PASSED_TESTS=0
FAILED_TESTS=0

# Record test result
record_test_result() {
    local test_name="$1"
    local duration="$2"
    local status="$3"
    
    PERFORMANCE_RESULTS["$test_name"]="$duration:$status"
    ((TEST_COUNT++))
    
    if [ "$status" = "PASS" ]; then
        ((PASSED_TESTS++))
        echo "  ✅ $test_name: ${duration}s"
    else
        ((FAILED_TESTS++))
        echo "  ❌ $test_name: ${duration}s ($status)"
    fi
}

# =============================================================================
# MODULE LOADING PERFORMANCE TESTS
# =============================================================================

test_lazy_loading_performance() {
    echo "🔄 Testing lazy module loading performance..."
    
    # Test loading time for individual modules
    local modules=(
        "menu/main_menu.sh"
        "menu/server_handlers.sh"
        "menu/server_installation.sh"
        "install/prerequisites.sh"
        "install/docker_setup.sh"
    )
    
    for module in "${modules[@]}"; do
        if [ -f "$PROJECT_ROOT/modules/$module" ]; then
            local start_time=$(date +%s.%N)
            
            # Test lazy loading
            load_module_lazy "$module" >/dev/null 2>&1
            local load_result=$?
            
            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
            
            if [ $load_result -eq 0 ] && (( $(echo "$duration < 1.0" | bc -l 2>/dev/null || echo "1") )); then
                record_test_result "lazy_load_$module" "$duration" "PASS"
            else
                record_test_result "lazy_load_$module" "$duration" "FAIL"
            fi
        fi
    done
}

# Test startup time optimization
test_startup_performance() {
    echo "🚀 Testing startup performance..."
    
    local start_time=$(date +%s.%N)
    
    # Simulate startup process
    (
        cd "$PROJECT_ROOT"
        timeout 10 bash -c "source vpn.sh help" >/dev/null 2>&1
    )
    local startup_result=$?
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "10")
    
    # Target: < 2 seconds startup time
    if [ $startup_result -eq 0 ] && (( $(echo "$duration < 2.0" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "startup_time" "$duration" "PASS"
    else
        record_test_result "startup_time" "$duration" "FAIL"
    fi
}

# =============================================================================
# CACHING PERFORMANCE TESTS  
# =============================================================================

test_container_caching() {
    echo "🐳 Testing Docker container caching..."
    
    # Test cache hit performance
    local container="test_container"
    
    # First call (cache miss)
    local start_time=$(date +%s.%N)
    get_container_status_cached "$container" >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    local cache_miss_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Second call (cache hit)
    start_time=$(date +%s.%N)
    get_container_status_cached "$container" >/dev/null 2>&1
    end_time=$(date +%s.%N)
    local cache_hit_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Cache hit should be significantly faster
    if (( $(echo "$cache_hit_time < $cache_miss_time" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "container_caching" "$cache_hit_time" "PASS"
    else
        record_test_result "container_caching" "$cache_hit_time" "FAIL"
    fi
}

test_config_caching() {
    echo "⚙️ Testing configuration caching..."
    
    # Create test config file
    local test_config="/tmp/test_config.json"
    echo '{"test": {"value": "cached_data"}}' > "$test_config"
    
    # Test cache performance
    local start_time=$(date +%s.%N)
    for i in {1..5}; do
        get_config_cached "$test_config" "test.value" >/dev/null 2>&1
    done
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Cleanup
    rm -f "$test_config"
    
    # Multiple cached reads should be fast
    if (( $(echo "$duration < 0.1" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "config_caching" "$duration" "PASS"  
    else
        record_test_result "config_caching" "$duration" "FAIL"
    fi
}

# =============================================================================
# STRING OPERATIONS PERFORMANCE TESTS
# =============================================================================

test_string_operations() {
    echo "📝 Testing optimized string operations..."
    
    local test_items=("item1" "item2" "item3" "item4" "item5")
    
    # Test optimized join function
    local start_time=$(date +%s.%N)
    for i in {1..100}; do
        join_strings "," "${test_items[@]}" >/dev/null 2>&1
    done
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Should complete 100 operations quickly
    if (( $(echo "$duration < 0.5" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "string_operations" "$duration" "PASS"
    else
        record_test_result "string_operations" "$duration" "FAIL"
    fi
}

# =============================================================================
# FILE OPERATIONS PERFORMANCE TESTS
# =============================================================================

test_file_operations() {
    echo "📁 Testing optimized file operations..."
    
    # Create test files
    local test_files=()
    for i in {1..5}; do
        local test_file="/tmp/test_file_$i.txt"
        echo "test_data_$i" > "$test_file"
        test_files+=("$test_file")
    done
    
    # Test batch file reading
    local start_time=$(date +%s.%N)
    read_multiple_files "${test_files[@]}" >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Cleanup
    for file in "${test_files[@]}"; do
        rm -f "$file"
    done
    
    # Batch reading should be fast
    if (( $(echo "$duration < 0.1" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "file_operations" "$duration" "PASS"
    else
        record_test_result "file_operations" "$duration" "FAIL"
    fi
}

# =============================================================================
# MEMORY USAGE TESTS
# =============================================================================

test_memory_usage() {
    echo "🧠 Testing memory usage optimization..."
    
    # Get initial memory usage
    local initial_memory=$(grep VmRSS /proc/$$/status 2>/dev/null | awk '{print $2}' || echo "0")
    
    # Load multiple modules and perform operations
    for i in {1..10}; do
        get_container_status_cached "test_container_$i" >/dev/null 2>&1
        get_config_cached "/tmp/nonexistent.json" "test.key" >/dev/null 2>&1
    done
    
    # Trigger cleanup
    cleanup_resources
    
    # Get final memory usage
    local final_memory=$(grep VmRSS /proc/$$/status 2>/dev/null | awk '{print $2}' || echo "0")
    local memory_diff=$((final_memory - initial_memory))
    
    # Memory usage should remain reasonable (< 10MB increase)
    if [ "$memory_diff" -lt 10240 ]; then
        record_test_result "memory_usage" "${memory_diff}KB" "PASS"
    else
        record_test_result "memory_usage" "${memory_diff}KB" "FAIL"
    fi
}

# =============================================================================
# PARALLEL PROCESSING TESTS
# =============================================================================

test_parallel_operations() {
    echo "⚡ Testing parallel processing performance..."
    
    # Test parallel container checks
    local start_time=$(date +%s.%N)
    check_all_containers >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    
    # Parallel operations should be faster than sequential
    if (( $(echo "$duration < 2.0" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "parallel_operations" "$duration" "PASS"
    else
        record_test_result "parallel_operations" "$duration" "FAIL"
    fi
}

# =============================================================================
# BENCHMARK INTEGRATION TESTS
# =============================================================================

test_benchmark_tools() {
    echo "📊 Testing benchmark tools..."
    
    # Test benchmark module function
    local start_time=$(date +%s.%N)
    timeout 10 benchmark_modules >/dev/null 2>&1
    local benchmark_result=$?
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "10")
    
    if [ $benchmark_result -eq 0 ] && (( $(echo "$duration < 10" | bc -l 2>/dev/null || echo "0") )); then
        record_test_result "benchmark_tools" "$duration" "PASS"
    else
        record_test_result "benchmark_tools" "$duration" "FAIL"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "🚀 Starting VPN Performance Tests"
    echo "=================================="
    echo ""
    
    # Run performance test suites
    test_lazy_loading_performance
    test_startup_performance
    test_container_caching
    test_config_caching
    test_string_operations
    test_file_operations
    test_memory_usage
    test_parallel_operations
    test_benchmark_tools
    
    # Clear caches to avoid interference
    clear_all_caches
    
    echo ""
    echo "📊 Performance Test Results"
    echo "============================"
    echo "Total tests: $TEST_COUNT"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo "🎉 All performance tests passed!"
        echo ""
        echo "✨ Performance targets achieved:"
        echo "  • Startup time: < 2 seconds"  
        echo "  • Container caching: Active"
        echo "  • String operations: Optimized"
        echo "  • Memory usage: Controlled"
        echo "  • Parallel processing: Working"
        exit 0
    else
        echo "⚠️  Some performance tests failed"
        echo "📋 Check optimization implementation"
        exit 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi