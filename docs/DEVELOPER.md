# 🛠️ Developer Guide - VPN Server Modular Architecture

This guide provides comprehensive information for developers working with the VPN server's modular architecture, introduced in Version 2.0.

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Module System](#module-system)
3. [Development Guidelines](#development-guidelines)
4. [Testing Framework](#testing-framework)
5. [Adding New Features](#adding-new-features)
6. [Debugging & Troubleshooting](#debugging--troubleshooting)
7. [Best Practices](#best-practices)

## 🏗️ Architecture Overview

### Design Principles

The modular architecture follows SOLID principles and clean code practices:

- **Single Responsibility**: Each module has one well-defined purpose
- **Open/Closed**: Modules are open for extension, closed for modification
- **Dependency Inversion**: High-level modules don't depend on low-level modules
- **Interface Segregation**: Modules export only necessary functions
- **DRY (Don't Repeat Yourself)**: Common functionality is centralized in libraries
- **Performance First**: Lazy loading, caching, and optimization throughout

### System Layers

```
┌─────────────────────────────────────┐
│        Main Script (vpn.sh)         │  ← Single Entry Point
├─────────────────────────────────────┤
│          Menu System                │  ← User Interface Layer
│      menu/, server_handlers         │
├─────────────────────────────────────┤
│          Feature Modules            │  ← Business Logic Layer
│    users/, server/, monitoring/,    │
│        install/, system/            │
├─────────────────────────────────────┤
│          Core Libraries             │  ← Infrastructure Layer
│  common.sh, config.sh, docker.sh,  │
│  network.sh, crypto.sh, ui.sh,     │
│        performance.sh              │
└─────────────────────────────────────┘
```

### Performance Architecture

The system implements comprehensive performance optimizations:

- **Lazy Module Loading**: Modules loaded only when needed
- **Caching Strategy**: 
  - Docker operations: 5-second TTL
  - Configuration data: 30-second TTL
  - Automatic cache cleanup when size limits exceeded
- **Parallel Processing**: Concurrent health checks and operations
- **Optimized I/O**: Batch file reads, efficient string operations

## 🧩 Module System

### Core Libraries (`lib/`)

#### `lib/common.sh`
- **Purpose**: Shared utilities and common functions
- **Exports**: 
  - Color definitions (`RED`, `GREEN`, `YELLOW`, etc.)
  - Logging functions (`log()`, `error()`, `warning()`)
  - Utility functions (`press_enter()`)
- **Usage**: Source first in all scripts

```bash
source "lib/common.sh"
log "This is a success message"
error "This is an error message"
```

#### `lib/config.sh`
- **Purpose**: Configuration management and validation
- **Key Functions**:
  - `get_server_info()` - Load server configuration
  - `save_config()` - Save configuration to files
  - `validate_config()` - Validate configuration integrity
- **Usage**: Configuration operations

```bash
source "lib/config.sh"
get_server_info
echo "Server port: $SERVER_PORT"
```

#### `lib/docker.sh`
- **Purpose**: Docker operations and resource management
- **Key Functions**:
  - `get_cpu_cores()` - System resource detection
  - `calculate_cpu_limits()` - Resource limit calculation
  - `generate_docker_compose()` - Docker Compose generation
- **Usage**: Docker-related operations

```bash
source "lib/docker.sh"
calculate_resource_limits true
echo "Max CPU: $MAX_CPU"
```

#### `lib/network.sh`
- **Purpose**: Network utilities and port management
- **Key Functions**:
  - `check_port_available()` - Port availability check
  - `generate_free_port()` - Random port generation
  - `check_sni_domain()` - SNI domain validation
  - `get_external_ip()` - External IP detection
- **Usage**: Network operations

```bash
source "lib/network.sh"
if check_port_available 8080; then
    echo "Port 8080 is available"
fi
```

#### `lib/performance.sh`
- **Purpose**: Performance optimizations and monitoring
- **Key Functions**:
  - `get_container_status_cached()` - Cached Docker status checks
  - `time_function()` - Function execution timing
  - `monitor_resources()` - Resource usage monitoring
  - `benchmark_modules()` - Module loading benchmarks
  - `cleanup_resources()` - Memory optimization
- **Usage**: Performance optimization

```bash
source "lib/performance.sh"
# Time a function execution
time_function some_heavy_operation

# Use cached container status
status=$(get_container_status_cached "xray")

# Monitor current resource usage
monitor_resources
```

#### `lib/crypto.sh`
- **Purpose**: Cryptographic functions
- **Key Functions**:
  - `generate_uuid()` - UUID generation
  - `generate_reality_keypair()` - X25519 key generation
  - `generate_short_id()` - Reality short ID generation
- **Usage**: Security operations

```bash
source "lib/crypto.sh"
UUID=$(generate_uuid)
echo "Generated UUID: $UUID"
```

#### `lib/ui.sh`
- **Purpose**: User interface components
- **Key Functions**:
  - Menu display functions
  - Progress indicators
  - Input validation
- **Usage**: Interactive interfaces

### Feature Modules

#### Installation Modules (`modules/install/`)

##### `modules/install/prerequisites.sh`
- **Purpose**: System checks and dependency installation
- **Key Functions**:
  - `check_root_privileges()` - Root access verification
  - `detect_system_info()` - OS and hardware detection
  - `install_system_dependencies()` - Dependency installation
  - `verify_dependencies()` - Installation verification

##### `modules/install/docker_setup.sh`
- **Purpose**: Docker environment setup
- **Key Functions**:
  - `calculate_resource_limits()` - System resource calculation
  - `create_docker_compose()` - Main compose file creation
  - `create_backup_docker_compose()` - Fallback compose creation
  - `start_docker_container()` - Container startup with fallback
  - `verify_container_status()` - Health verification

##### `modules/install/xray_config.sh`
- **Purpose**: Xray configuration generation
- **Key Functions**:
  - `setup_xray_directories()` - Directory structure creation
  - `create_xray_config_reality()` - VLESS+Reality config
  - `create_xray_config_basic()` - Basic VLESS config
  - `validate_xray_config()` - Configuration validation
  - `create_user_data()` - User data files
  - `create_connection_link()` - Client connection links

##### `modules/install/firewall.sh`
- **Purpose**: Firewall configuration
- **Key Functions**:
  - `setup_basic_firewall()` - SSH and basic rules
  - `setup_xray_firewall()` - VPN-specific rules
  - `verify_port_access()` - Port accessibility verification
  - `backup_firewall_rules()` - Rule backup

#### User Management Modules (`modules/users/`)

Each user module follows a consistent pattern:
- Input validation
- Configuration updates
- Service restart if needed
- Success/failure reporting

#### Server Management Modules (`modules/server/`)

- `status.sh` - Health monitoring and diagnostics
- `restart.sh` - Service control with verification
- `rotate_keys.sh` - Security key rotation
- `uninstall.sh` - Clean system removal

#### Monitoring Modules (`modules/monitoring/`)

- `statistics.sh` - Traffic analysis with vnstat integration
- `logging.sh` - Log level configuration
- `logs_viewer.sh` - Log analysis and filtering

## 📝 Development Guidelines

### Creating New Modules

1. **Choose the Right Location**
   ```bash
   lib/           # For shared utilities
   modules/users/ # For user management features
   modules/server/# For server operations
   modules/monitoring/ # For analytics/logging
   modules/install/    # For installation components
   ```

2. **Module Template**
   ```bash
   #!/bin/bash
   
   # =============================================================================
   # Module Name
   # 
   # Brief description of module purpose.
   #
   # Functions exported:
   # - function1() - Description
   # - function2() - Description
   #
   # Dependencies: lib/common.sh, lib/other.sh
   # =============================================================================
   
   # Source required libraries
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/../../lib/common.sh" || {
       echo "Error: Cannot source lib/common.sh"
       exit 1
   }
   
   # Function implementation
   my_function() {
       local param1="$1"
       local debug=${2:-false}
       
       [ "$debug" = true ] && log "Debug: Starting my_function"
       
       # Implementation here
       
       return 0
   }
   
   # Export functions
   export -f my_function
   
   # Direct execution handling
   if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
       # Handle direct script execution
       my_function "$@"
   fi
   ```

3. **Function Naming Convention**
   - Use descriptive, verb-based names
   - Follow snake_case convention
   - Prefix with module context if needed
   - Examples: `add_user()`, `validate_port()`, `create_backup()`

4. **Parameter Handling**
   ```bash
   my_function() {
       local required_param="$1"
       local optional_param="${2:-default_value}"
       local debug=${3:-false}
       
       # Validate required parameters
       if [ -z "$required_param" ]; then
           error "Missing required parameter: required_param"
           return 1
       fi
       
       # Function logic here
   }
   ```

### Error Handling

Always implement comprehensive error handling:

```bash
# Check command success
if ! some_command; then
    error "Command failed: some_command"
    return 1
fi

# Validate files
if [ ! -f "$config_file" ]; then
    error "Configuration file not found: $config_file"
    return 1
fi

# Graceful degradation
if command -v optional_tool >/dev/null 2>&1; then
    optional_tool --do-something
else
    warning "Optional tool not available, skipping feature"
fi
```

### Debug Logging

All functions should support debug mode:

```bash
my_function() {
    local debug=${1:-false}
    
    [ "$debug" = true ] && log "Debug: Function started with params: $*"
    
    # Implementation
    
    [ "$debug" = true ] && log "Debug: Function completed successfully"
    return 0
}
```

## 🧪 Testing Framework

### Test Structure

Each module should have corresponding tests in the `test/` directory:

```bash
test/
├── test_libraries.sh       # Test all lib/ modules
├── test_install_modules.sh # Test modules/install/ modules
├── test_user_modules.sh    # Test modules/users/ modules
├── test_server_modules.sh  # Test modules/server/ modules
├── test_monitoring_modules.sh # Test modules/monitoring/ modules
└── test_performance.sh     # Test performance optimizations
```

### Writing Tests

1. **Test Function Template**
   ```bash
   test_function_name() {
       # Setup
       local test_input="value"
       
       # Execute
       if my_function "$test_input" false; then
           return 0  # Test passed
       else
           return 1  # Test failed
       fi
   }
   ```

2. **Mock External Dependencies**
   ```bash
   # Create mock commands for testing
   setup_mocks() {
       cat > "$TEST_DIR/docker" <<'EOF'
   #!/bin/bash
   echo "Mock docker output"
   exit 0
   EOF
       chmod +x "$TEST_DIR/docker"
       export PATH="$TEST_DIR:$PATH"
   }
   ```

3. **Test Environment**
   ```bash
   setup_test_env() {
       TEST_DIR="/tmp/test_$$"
       mkdir -p "$TEST_DIR"
       export TEST_MODE=true
   }
   
   cleanup_test_env() {
       rm -rf "$TEST_DIR"
   }
   ```

### Running Tests

```bash
# Run individual test suites
./test/test_libraries.sh
./test/test_install_modules.sh

# Run all tests
find test/ -name "test_*.sh" -executable -exec {} \;

# Run tests with verbose output
DEBUG=true ./test/test_libraries.sh
```

## ➕ Adding New Features

### Step-by-Step Process

1. **Planning**
   - Identify which layer the feature belongs to
   - Determine dependencies on existing modules
   - Design the function interface

2. **Implementation**
   ```bash
   # 1. Create the module file
   touch modules/category/new_feature.sh
   
   # 2. Implement following the module template
   # 3. Add comprehensive error handling
   # 4. Include debug logging
   # 5. Export functions
   ```

3. **Integration**
   ```bash
   # Update main scripts to use new module
   source "modules/category/new_feature.sh"
   
   # Add menu option if needed (in manage_users.sh)
   # Update installation flow if needed (in install_vpn.sh)
   ```

4. **Testing**
   ```bash
   # Create test file
   touch test/test_new_feature.sh
   
   # Implement comprehensive tests
   # Include positive and negative test cases
   # Test error conditions
   ```

5. **Documentation**
   - Update README.md with new feature
   - Add inline documentation
   - Update this developer guide if needed

### Example: Adding a New User Feature

Let's say we want to add a user export feature:

1. **Create Module** (`modules/users/export.sh`)
   ```bash
   #!/bin/bash
   
   # =============================================================================
   # User Export Module
   # 
   # Export user configurations in various formats.
   #
   # Functions exported:
   # - export_user_json() - Export user as JSON
   # - export_all_users() - Export all users
   #
   # Dependencies: lib/common.sh, lib/config.sh
   # =============================================================================
   
   export_user_json() {
       local username="$1"
       local output_file="$2"
       local debug=${3:-false}
       
       [ "$debug" = true ] && log "Exporting user: $username"
       
       # Implementation here
       
       return 0
   }
   
   export -f export_user_json
   ```

2. **Add to Management Script**
   ```bash
   # In manage_users.sh, add menu option:
   echo "6) 📤 Export User"
   
   # Add case handler:
   6) export_user_interactive ;;
   ```

3. **Create Tests**
   ```bash
   # In test/test_user_modules.sh:
   test_user_export() {
       # Test implementation
   }
   ```

## 🐛 Debugging & Troubleshooting

### Debug Mode

Enable debug mode for verbose logging:

```bash
# For individual functions
my_function "param" true  # Last parameter enables debug

# For entire scripts
DEBUG=true ./install_vpn.sh
```

### Common Issues

1. **Module Not Found**
   ```bash
   # Error: Cannot source module
   # Solution: Check file paths and permissions
   ls -la modules/category/
   chmod +x modules/category/module.sh
   ```

2. **Function Not Available**
   ```bash
   # Error: command not found
   # Solution: Ensure module is sourced and functions exported
   source "modules/category/module.sh"
   type -t function_name  # Should show "function"
   ```

3. **Permission Errors**
   ```bash
   # Ensure scripts are executable
   find . -name "*.sh" -exec chmod +x {} \;
   ```

### Logging and Diagnostics

```bash
# Enable verbose logging in modules
export DEBUG=true

# Check function availability
declare -F | grep module_function

# Trace script execution
bash -x script.sh
```

## ✨ Best Practices

### Code Quality

1. **Always Use `set -e`**
   ```bash
   #!/bin/bash
   set -e  # Exit on any error
   ```

2. **Validate Inputs**
   ```bash
   validate_input() {
       local input="$1"
       
       if [ -z "$input" ]; then
           error "Input cannot be empty"
           return 1
       fi
       
       # Additional validation
   }
   ```

3. **Use Local Variables**
   ```bash
   my_function() {
       local var1="$1"          # Good
       var2="$2"                # Bad - global variable
   }
   ```

4. **Quote Variables**
   ```bash
   if [ -f "$file_path" ]; then    # Good
   if [ -f $file_path ]; then      # Bad
   ```

### Performance

1. **Minimize External Commands**
   ```bash
   # Good - built-in parameter expansion
   filename="${path##*/}"
   
   # Bad - external command
   filename=$(basename "$path")
   ```

2. **Use Efficient Patterns**
   ```bash
   # Good - single command
   grep -q "pattern" file && echo "found"
   
   # Bad - unnecessary commands
   if grep "pattern" file > /dev/null; then
       echo "found"
   fi
   ```

### Security

1. **Validate User Input**
   ```bash
   validate_username() {
       local username="$1"
       
       # Check for dangerous characters
       if [[ "$username" =~ [^a-zA-Z0-9_-] ]]; then
           error "Invalid username format"
           return 1
       fi
   }
   ```

2. **Use Secure Temporary Files**
   ```bash
   temp_file=$(mktemp)
   trap 'rm -f "$temp_file"' EXIT
   ```

3. **Avoid Command Injection**
   ```bash
   # Good - use arrays for commands
   docker_cmd=("docker" "run" "--name" "$container_name")
   "${docker_cmd[@]}"
   
   # Bad - string concatenation
   docker_cmd="docker run --name $container_name"
   $docker_cmd
   ```

### Documentation

1. **Module Headers**
   - Clear purpose description
   - List of exported functions
   - Dependencies
   - Usage examples

2. **Function Documentation**
   ```bash
   # Brief description
   # Parameters:
   #   $1 - parameter description
   #   $2 - parameter description (optional)
   # Returns:
   #   0 - success
   #   1 - error condition
   my_function() {
       # Implementation
   }
   ```

3. **Inline Comments**
   ```bash
   # Reason: This loop handles edge case where...
   for item in "${array[@]}"; do
       # Process item
   done
   ```

## 🔄 Version Control

### Commit Guidelines

- Use descriptive commit messages
- Reference module names in commits
- Group related changes together

### Branch Strategy

- `main` - Stable releases
- `develop` - Integration branch
- `feature/module-name` - Feature development
- `hotfix/issue-description` - Critical fixes

## ⚡ Performance Guidelines

### Lazy Loading Implementation

Always use lazy loading for modules that aren't immediately needed:

```bash
# In vpn.sh or menu handlers
load_module_lazy() {
    local module="$1"
    [ -z "${LOADED_MODULES[$module]}" ] && {
        source "$SCRIPT_DIR/modules/$module" || return 1
        LOADED_MODULES[$module]=1
    }
}

# Usage
handle_user_operation() {
    # Load user modules only when needed
    load_module_lazy "users/add.sh" || return 1
    add_user "$@"
}
```

### Caching Strategy

Implement caching for expensive operations:

```bash
# Use performance library caching
source "lib/performance.sh"

# Cache container status
status=$(get_container_status_cached "xray")

# Cache configuration data
config_value=$(get_config_cached "/path/to/config.json" "key.path")
```

### Optimization Checklist

- [ ] Use lazy loading for non-critical modules
- [ ] Cache Docker operations (5-second TTL)
- [ ] Cache configuration reads (30-second TTL)
- [ ] Use batch file operations
- [ ] Prefer built-in string operations over external commands
- [ ] Implement parallel processing where applicable
- [ ] Monitor memory usage and cleanup caches

### Performance Testing

```bash
# Run performance benchmarks
./vpn.sh benchmark

# Test specific performance metrics
./test/test_performance.sh

# Monitor resource usage during development
./vpn.sh debug
```

### Best Practices for Performance

1. **Avoid Repeated Operations**
   ```bash
   # Bad: Multiple docker calls
   if docker ps | grep xray; then
       docker logs xray
   fi
   
   # Good: Single cached call
   if [ "$(get_container_status_cached xray)" = "running" ]; then
       docker logs xray
   fi
   ```

2. **Optimize String Operations**
   ```bash
   # Bad: String concatenation in loop
   result=""
   for item in "${items[@]}"; do
       result="$result$item\n"
   done
   
   # Good: Use printf
   printf "%s\n" "${items[@]}"
   ```

3. **Batch File Operations**
   ```bash
   # Bad: Multiple reads
   port=$(cat /opt/v2ray/config/port.txt)
   protocol=$(cat /opt/v2ray/config/protocol.txt)
   
   # Good: Single batch read
   readarray -t configs < <(read_multiple_files port.txt protocol.txt)
   ```

## 📞 Support

For questions about the modular architecture:

1. Check this developer guide
2. Review existing module implementations
3. Run the test suite to understand expected behavior
4. Consult the main README.md for user-facing documentation

Remember: The modular architecture is designed to be self-documenting through clear function names, comprehensive error messages, and consistent patterns across all modules.