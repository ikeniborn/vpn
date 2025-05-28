# 🏗️ VPN Project Refactoring Plan

## 📋 Project Overview

**Current State:**
- 3 main scripts: `install_vpn.sh` (1,269 lines), `manage_users.sh` (1,258 lines), and `install_client.sh` (client with Web UI)
- Significant code duplication between scripts
- All functionality embedded in single files
- Limited modularity and reusability

**Target State:**
- Modular architecture with scripts under 500 lines each
- Shared library for common functions
- Clear separation of concerns
- Easy to maintain and extend

## 🎯 Refactoring Goals

1. **Code Reduction**: Reduce each script to 300-500 lines maximum
2. **DRY Principle**: Eliminate duplicate code
3. **Modularity**: Create reusable components
4. **Maintainability**: Improve code organization and readability
5. **Extensibility**: Make it easy to add new features

## 🏛️ Proposed Architecture

```
vpn/
├── lib/                    # Shared libraries
│   ├── common.sh          # Common functions (log, error, warning, colors)
│   ├── config.sh          # Configuration management
│   ├── network.sh         # Network utilities (port, SNI validation)
│   ├── docker.sh          # Docker operations
│   ├── crypto.sh          # Key generation and management
│   └── ui.sh              # User interface components
│
├── modules/               # Feature modules
│   ├── install/
│   │   ├── prerequisites.sh    # System requirements check
│   │   ├── docker_setup.sh     # Docker installation
│   │   ├── xray_config.sh      # Xray configuration
│   │   └── firewall.sh         # UFW setup
│   │
│   ├── users/
│   │   ├── add.sh             # Add user functionality
│   │   ├── delete.sh          # Delete user functionality
│   │   ├── edit.sh            # Edit user functionality
│   │   ├── list.sh            # List users functionality
│   │   └── show.sh            # Show user details
│   │
│   ├── server/
│   │   ├── status.sh          # Server status
│   │   ├── restart.sh         # Restart operations
│   │   ├── rotate_keys.sh     # Key rotation
│   │   └── uninstall.sh       # Uninstallation
│   │
│   └── monitoring/
│       ├── statistics.sh      # Traffic statistics
│       ├── logging.sh         # Log configuration
│       └── logs_viewer.sh     # Log analysis
│
├── config/                # Configuration templates
│   ├── xray_template.json
│   └── docker-compose.template.yml
│
├── install.sh            # Main installer (< 300 lines)
├── manage.sh             # Management interface (< 300 lines)
├── install_client.sh     # Client installer with Web UI
└── uninstall.sh          # Uninstaller script
```

## 📦 Module Breakdown

### lib/common.sh (~100 lines)
- Color definitions
- log(), error(), warning() functions
- Common variables (WORK_DIR, etc.)
- Utility functions

### lib/config.sh (~150 lines)
- Configuration file management
- Settings persistence
- Configuration validation
- Default values

### lib/network.sh (~200 lines)
- Port availability checking
- Port generation
- SNI domain validation
- Network interface detection

### lib/docker.sh (~150 lines)
- Docker installation check
- Container management
- Docker-compose operations
- Container health checks

### lib/crypto.sh (~100 lines)
- X25519 key generation
- Key rotation logic
- UUID generation
- Short ID generation

### lib/ui.sh (~200 lines)
- Menu display functions
- User input validation
- Progress indicators
- Client info display

### Main Scripts

#### install.sh (~300 lines)
```bash
#!/bin/bash
# Load libraries
source lib/common.sh
source lib/config.sh
source lib/network.sh
source lib/docker.sh
source lib/crypto.sh

# Main installation flow
main() {
    check_root
    show_welcome
    
    # Load modules
    source modules/install/prerequisites.sh
    source modules/install/docker_setup.sh
    source modules/install/xray_config.sh
    source modules/install/firewall.sh
    
    # Execute installation
    check_prerequisites
    setup_docker
    configure_xray
    setup_firewall
    
    show_completion_message
}

main "$@"
```

#### manage.sh (~300 lines)
```bash
#!/bin/bash
# Load libraries
source lib/common.sh
source lib/config.sh
source lib/ui.sh

# Load configuration
load_server_config

# Main menu loop
while true; do
    show_menu
    read_user_choice
    
    case $choice in
        1) source modules/users/list.sh && list_users ;;
        2) source modules/users/add.sh && add_user ;;
        3) source modules/users/delete.sh && delete_user ;;
        # ... etc
    esac
done
```

## 🔄 Refactoring Steps

### Phase 1: Create Library Structure (Week 1)
1. Create `lib/` directory structure
2. Extract common functions to `lib/common.sh`
3. Move color definitions and utilities
4. Test library imports

### Phase 2: Extract Network & Docker (Week 1)
1. Create `lib/network.sh` with port/SNI functions
2. Create `lib/docker.sh` with container operations
3. Update scripts to use libraries
4. Test functionality

### Phase 3: Modularize User Management (Week 2)
1. Create `modules/users/` structure
2. Extract user operations to separate files
3. Implement module loading in manage.sh
4. Test user operations

### Phase 4: Modularize Server Operations (Week 2)
1. Create `modules/server/` structure
2. Extract server operations
3. Implement module loading
4. Test server operations

### Phase 5: Modularize Monitoring (Week 3)
1. Create `modules/monitoring/` structure
2. Extract monitoring functions
3. Implement module loading
4. Test monitoring features

### Phase 6: Refactor Main Scripts (Week 3)
1. Rewrite `install.sh` using modules
2. Rewrite `manage.sh` using modules
3. Create `uninstall.sh` as separate script
4. Final testing

## 🧪 Testing Strategy

### Unit Testing
- Test each module independently
- Verify library functions
- Mock dependencies where needed

### Integration Testing
- Test module interactions
- Verify configuration persistence
- Test error handling

### System Testing
- Full installation test
- Complete user lifecycle test
- Server operation tests
- Monitoring functionality

## 📈 Success Metrics

1. **Line Count**: Each script < 500 lines
2. **Code Duplication**: < 5% duplicate code
3. **Module Count**: 15-20 focused modules
4. **Test Coverage**: > 80% functionality tested
5. **Performance**: No regression in execution time

## 🚀 Benefits

1. **Maintainability**: Easier to fix bugs and add features
2. **Readability**: Clear structure and organization
3. **Reusability**: Shared libraries reduce code
4. **Testability**: Modular design enables testing
5. **Scalability**: Easy to add new VPN types or features

## 📝 Notes

- Maintain backward compatibility during refactoring
- Document each module's purpose and usage
- Keep user-facing interfaces unchanged
- Preserve all existing functionality
- Add comprehensive error handling in modules