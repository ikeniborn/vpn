# 📋 VPN Project Optimization Tasks

## 🎯 Primary Goal
Refactor the monolithic VPN scripts into a modular architecture with each script containing 300-500 lines maximum.

### Recent Updates
- ✅ **Client Installation**: Unified client installation into single `install_client.sh` script with v2rayA Web UI
- ✅ **Documentation**: Updated all documentation to reflect client script changes
- ✅ **Client Connectivity Fix**: Fixed internet connectivity issue by changing network mode from host to bridge
- ✅ **Proxy Configuration**: Added proper proxy ports (20170-20172) and updated firewall rules
- ✅ **Client Stability**: Enhanced stability by disabling transparent proxy and adding proper network capabilities

## 📊 Current Status
- [ ] **Total Lines**: 2,891+ (install: 1,365 + manage: 1,426 + client: 797 + deploy: 394 + watchdog: 278)
- [ ] **Target**: ~25 modules × 200-300 lines each
- [ ] **Duplicate Code**: ~15% (colors, functions, checks)
- [x] **Client Script**: Unified into single `install_client.sh` with v2rayA Web UI (completed)
- [x] **Client Issues**: Fixed connectivity problems with proxy mode configuration
- [x] **Stability Improvements**: Added health checks, resource limits, and watchdog service (completed)
- [x] **Deployment Tools**: Added deploy.sh script and CI/CD configuration (completed)

---

## 🚀 Phase 1: Foundation (Priority: HIGH)
**Deadline**: Week 1

### ✅ Create Library Structure
- [ ] Create `lib/` directory
- [ ] Create `modules/` directory structure
- [ ] Create `config/` for templates

### ✅ Extract Common Functions
- [ ] Create `lib/common.sh` (~100 lines)
  - [ ] Move color definitions (7 colors)
  - [ ] Move log(), error(), warning() functions
  - [ ] Add press_enter() and utility functions
  - [ ] Define common variables (WORK_DIR, etc.)

### ✅ Configuration Management
- [ ] Create `lib/config.sh` (~150 lines)
  - [ ] Extract get_server_info() from manage_users.sh
  - [ ] Add save_config() function
  - [ ] Add load_config() function
  - [ ] Add validate_config() function

---

## 🔧 Phase 2: Core Libraries (Priority: HIGH)
**Deadline**: Week 1-2

### ✅ Network Utilities
- [ ] Create `lib/network.sh` (~200 lines)
  - [ ] Move check_port_available() from install_vpn.sh
  - [ ] Move generate_free_port() from install_vpn.sh
  - [ ] Move check_sni_domain() from install_vpn.sh
  - [ ] Add network interface detection

### ✅ Docker Operations
- [ ] Create `lib/docker.sh` (~150 lines)
  - [ ] Extract Docker installation check
  - [ ] Add container management functions
  - [ ] Move docker-compose operations
  - [ ] Add health check functions

### ✅ Cryptography Functions
- [ ] Create `lib/crypto.sh` (~100 lines)
  - [ ] Extract key generation logic
  - [ ] Move UUID generation
  - [ ] Add short ID generation
  - [ ] Extract key rotation logic

### ✅ User Interface
- [ ] Create `lib/ui.sh` (~200 lines)
  - [ ] Move show_menu() from manage_users.sh
  - [ ] Move show_client_info() functions
  - [ ] Add progress indicators
  - [ ] Add input validation functions

---

## 👥 Phase 3: User Management Modules (Priority: HIGH)
**Deadline**: Week 2

### ✅ User Operations
- [ ] Create `modules/users/add.sh` (~250 lines)
  - [ ] Extract add_user() function
  - [ ] Include user validation
  - [ ] QR code generation logic

- [ ] Create `modules/users/delete.sh` (~100 lines)
  - [ ] Extract delete_user() function
  - [ ] Add cleanup operations

- [ ] Create `modules/users/edit.sh` (~150 lines)
  - [ ] Extract edit_user() function
  - [ ] Include update logic

- [ ] Create `modules/users/list.sh` (~100 lines)
  - [ ] Extract list_users() function
  - [ ] Add formatting options

- [ ] Create `modules/users/show.sh` (~150 lines)
  - [ ] Extract show_user() function
  - [ ] Include QR display logic

---

## 🖥️ Phase 4: Server Management Modules (Priority: MEDIUM)
**Deadline**: Week 2-3

### ✅ Server Operations
- [ ] Create `modules/server/status.sh` (~150 lines)
  - [ ] Extract show_status() function
  - [ ] Add health checks

- [ ] Create `modules/server/restart.sh` (~100 lines)
  - [ ] Extract restart_server() function
  - [ ] Add validation checks

- [ ] Create `modules/server/rotate_keys.sh` (~200 lines)
  - [ ] Extract rotate_reality_keys() function
  - [ ] Add backup logic

- [ ] Create `modules/server/uninstall.sh` (~150 lines)
  - [ ] Extract uninstall_vpn() function
  - [ ] Add cleanup operations

---

## 📊 Phase 5: Monitoring Modules (Priority: MEDIUM)
**Deadline**: Week 3

### ✅ Analytics and Logging
- [ ] Create `modules/monitoring/statistics.sh` (~250 lines)
  - [ ] Extract show_traffic_stats() function
  - [ ] Add vnstat integration

- [ ] Create `modules/monitoring/logging.sh` (~200 lines)
  - [ ] Extract configure_xray_logging() function
  - [ ] Add log level management

- [ ] Create `modules/monitoring/logs_viewer.sh` (~150 lines)
  - [ ] Extract view_user_logs() function
  - [ ] Add search functionality

---

## 🔄 Phase 6: Main Script Refactoring (Priority: HIGH)
**Deadline**: Week 3-4

### ✅ Installation Script
- [ ] Refactor `install.sh` to ~300 lines
  - [ ] Use module imports
  - [ ] Simplify main flow
  - [ ] Remove duplicate code

- [ ] Create `modules/install/prerequisites.sh` (~150 lines)
  - [ ] System checks
  - [ ] Dependency installation

- [ ] Create `modules/install/docker_setup.sh` (~150 lines)
  - [ ] Docker installation
  - [ ] Container setup

- [ ] Create `modules/install/xray_config.sh` (~200 lines)
  - [ ] Configuration generation
  - [ ] Initial setup

- [ ] Create `modules/install/firewall.sh` (~100 lines)
  - [ ] UFW configuration
  - [ ] Port management

### ✅ Management Script
- [ ] Refactor `manage.sh` to ~300 lines
  - [ ] Use module imports
  - [ ] Simplify menu system
  - [ ] Dynamic module loading

### ✅ Create Standalone Scripts
- [ ] Create `uninstall.sh` (~100 lines)
  - [ ] Complete removal script
  - [ ] Separate from management
- [ ] Refactor `install_client.sh` (~300 lines)
  - [ ] Extract common functions to lib/
  - [ ] Use shared Docker utilities
  - [ ] Simplify configuration flow

---

## 🧪 Phase 7: Testing & Documentation (Priority: HIGH)
**Deadline**: Week 4

### ✅ Testing
- [ ] Create test framework
- [ ] Write unit tests for libraries
- [ ] Write integration tests
- [ ] Perform system testing

### ✅ Documentation
- [ ] Document each module
- [ ] Update README.md
- [ ] Create developer guide
- [ ] Add inline documentation

---

## 📈 Progress Tracking

### Week 1 Goals
- [ ] Complete Phase 1 (Foundation)
- [ ] Complete 50% of Phase 2 (Core Libraries)

### Week 2 Goals
- [ ] Complete Phase 2 (Core Libraries)
- [ ] Complete Phase 3 (User Management)
- [ ] Start Phase 4 (Server Management)

### Week 3 Goals
- [ ] Complete Phase 4 (Server Management)
- [ ] Complete Phase 5 (Monitoring)
- [ ] Start Phase 6 (Main Scripts)

### Week 4 Goals
- [ ] Complete Phase 6 (Main Scripts)
- [ ] Complete Phase 7 (Testing & Documentation)
- [ ] Final review and optimization

---

## 🏆 Success Criteria

1. **✅ Line Count**: No script exceeds 500 lines
2. **✅ Modularity**: 15-20 focused modules created
3. **✅ Code Duplication**: Reduced to < 5%
4. **✅ Functionality**: All features preserved
5. **✅ Performance**: No execution time regression
6. **✅ Documentation**: All modules documented
7. **✅ Testing**: > 80% code coverage

---

## 📝 Notes

- Start with high-priority tasks that provide immediate value
- Test each module after extraction to ensure functionality
- Keep backup of original scripts until refactoring is complete
- Document decisions and changes in commit messages
- Consider creating a migration guide for existing installations

## 🐛 Discovered During Work

### Client Installation Issues (2025-05-28) - COMPLETED
- **Issue**: Client loses internet connectivity when connected to VPN server
- **Root Cause**: Using `network_mode: host` in Docker caused routing conflicts
- **Solution**: 
  - Changed to `network_mode: bridge`
  - Added explicit proxy ports (20170-20172)
  - Disabled transparent proxy mode
  - Added proper network capabilities
  - Updated documentation with proxy configuration instructions
- **Status**: ✅ Fixed and tested

### Client Management Improvements (2025-05-28) - COMPLETED
- **Added**: Uninstall functionality to v2raya-client management script
- **Added**: Smart main menu that detects if client is already installed
- **Fixed**: Docker Compose warning about obsolete version attribute
- **Improved**: User experience with context-aware menu options
- **Status**: ✅ Completed and tested

### Container Stability Improvements (2025-06-17) - COMPLETED
- **Issue**: VPN containers stop daily and need manual restart
- **Root Cause**: No health monitoring and resource constraints
- **Solution**:
  - Added comprehensive health checks for all containers (xray, shadowbox, watchtower)
  - Implemented resource limits (CPU: 0.5-2 cores, Memory: 512MB-2GB)
  - Changed restart policy from `always` to `unless-stopped` for better control
  - Created VPN Watchdog Service for 24/7 monitoring with automatic recovery
  - Added log rotation and system resource monitoring
- **Status**: ✅ Completed and deployed

### Deployment & DevOps Enhancement (2025-06-17) - COMPLETED
- **Added**: `deploy.sh` script for automated deployment with backup/restore
- **Added**: GitHub Actions CI/CD workflow for staging/production deployments
- **Added**: Multi-environment support with environment variables
- **Added**: Auto-discovery for flexible deployment paths
- **Added**: Watchdog management UI in main menu (option 12)
- **Improved**: Docker Compose with override file for production settings
- **Status**: ✅ Completed and ready for CI/CD