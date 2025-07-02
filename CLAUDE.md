# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rust-based VPN management system that provides comprehensive tools for managing Xray (VLESS+Reality), Outline VPN servers, and HTTP/SOCKS5 proxy servers. It replaces an original Bash implementation with a type-safe, high-performance alternative written in Rust.

### Key Infrastructure Components

- **Proxy/Load Balancer**: Traefik v3.x for reverse proxy, load balancing, and automatic SSL/TLS termination
- **VPN Server**: Xray-core with VLESS+Reality protocol for secure tunneling
- **Proxy Server**: Custom Rust-based HTTP/HTTPS and SOCKS5 proxy with authentication
- **Identity Management**: Custom Rust-based identity service with LDAP/OAuth2 support
- **Monitoring**: Prometheus + Grafana + Jaeger for comprehensive observability
- **Storage**: PostgreSQL for persistent data, Redis for sessions and caching
- **Orchestration**: Docker Compose with Traefik service discovery
- **Deployment**: Multi-arch Docker images (amd64, arm64) available on Docker Hub

## Build and Development Commands

### Core Development Commands

```bash
# Build the entire workspace
cargo build --workspace

# Build with optimizations (release mode)
cargo build --release --workspace

# Install the CLI tool
cargo install --path crates/vpn-cli

# Run tests for all crates
cargo test --workspace

# Run tests for a specific crate
cargo test -p vpn-users
cargo test -p vpn-docker
cargo test -p vpn-proxy

# Format all code
cargo fmt --all

# Run linter with all features
cargo clippy --all-features --workspace -- -D warnings

# Check for security vulnerabilities
cargo audit

# Generate and open documentation
cargo doc --workspace --open

# Run benchmarks
cargo bench

# Clean build artifacts
cargo clean
```

### Docker Build Commands

```bash
# Build multi-arch Docker images locally
./scripts/docker-build.sh

# Build and push to registry
PUSH=true ./scripts/docker-build.sh

# Build specific image
docker buildx build --platform linux/amd64,linux/arm64 -t vpn:latest .

# Deploy using Docker Hub images
docker-compose -f docker-compose.hub.yml up -d

# Quick start with Docker
curl -L https://raw.githubusercontent.com/yourusername/vpn/master/docker-compose.hub.yml -o docker-compose.yml
docker-compose up -d
```

### Running Specific Tests

```bash
# Run a single test by name
cargo test test_user_creation

# Run tests matching a pattern
cargo test user::

# Run tests with output displayed
cargo test -- --nocapture

# Run tests in a specific module
cargo test --package vpn-users --lib user::tests

# Run integration tests only
cargo test --test integration_tests
```

### Cross-Compilation

```bash
# Install cross-compilation tool
cargo install cross

# Build for ARM64 (e.g., Raspberry Pi 4)
cross build --target aarch64-unknown-linux-gnu --release

# Build for ARMv7 (e.g., Raspberry Pi 3)
cross build --target armv7-unknown-linux-gnueabihf --release
```

### CLI Usage Examples

```bash
# Check privileges status
vpn privileges

# List users (read-only, no sudo needed)
vpn users list

# Create user (requires sudo, will prompt)
vpn users create alice

# Install VPN server
sudo vpn install --protocol vless --port 8443

# Install proxy server
sudo vpn install --protocol proxy-server --port 8888

# Proxy management
vpn proxy status --detailed
vpn proxy monitor --user alice
vpn proxy test https://google.com

# Run with custom install path
vpn --install-path /tmp/test-vpn users list

# Use verbose mode to see privilege information
vpn --verbose users list
```

## Architecture and Crate Structure

### Workspace Layout

The project uses a Rust workspace with specialized crates organized in layers:

```
Core Libraries (Foundation Layer):
├── vpn-crypto     # Cryptographic operations (X25519, UUID, QR codes)
├── vpn-docker     # Docker container management and health monitoring
├── vpn-network    # Network utilities (port checking, firewall, IP detection)
└── vpn-compose    # Docker Compose orchestration and service management

Service Layer (Business Logic):
├── vpn-users      # User lifecycle, connection links, batch operations
├── vpn-server     # Server installation, configuration, lifecycle
├── vpn-proxy      # HTTP/HTTPS and SOCKS5 proxy server with auth
├── vpn-monitor    # Traffic stats, health monitoring, alerts, metrics
├── vpn-identity   # Identity service with LDAP/OAuth2 support
├── vpn-cluster    # Distributed clustering and coordination
├── vpn-operator   # Kubernetes operator for VPN management
└── vpn-telemetry  # Advanced telemetry and observability

Application Layer:
└── vpn-cli        # CLI interface, interactive menu, privilege management

Runtime Layer:
├── vpn-runtime    # Runtime abstraction and factory patterns
└── vpn-types      # Shared types and validation

Deprecated Crates:
└── vpn-containerd # DEPRECATED: Containerd runtime (kept for reference)
```

### Key Design Patterns

1. **Error Handling**: Each crate defines its own error type using `thiserror`, with automatic conversion between crate errors.

2. **Async/Await**: All I/O operations use Tokio for async execution. Docker operations, file I/O, and network calls are all async.

3. **Privilege Management**: The CLI automatically detects when operations need root privileges and can request elevation via sudo with user confirmation.

4. **Read-Only Mode**: When running without proper permissions, the system gracefully degrades to read-only mode instead of failing.

5. **Modular Configuration**: Each crate can operate independently with its own configuration, but they compose into a unified system.

### Critical Cross-Crate Dependencies

1. **UserManager** (vpn-users) requires:
   - ServerConfig for server details
   - Storage path with write permissions (or falls back to read-only)
   - Docker connectivity for container operations

2. **ServerInstaller** (vpn-server) orchestrates:
   - ContainerManager (vpn-docker) for Docker operations
   - FirewallManager (vpn-network) for network rules
   - ConfigGenerator (vpn-users) for user configurations

3. **CommandHandler** (vpn-cli) coordinates:
   - All service layer crates for operations
   - PrivilegeManager for permission handling
   - ConfigManager for settings

### State Management

- **User data**: Stored as JSON files in `{install_path}/users/{user_id}/config.json`
- **Server config**: TOML format in `/etc/vpn/config.toml` or specified path
- **Docker state**: Managed by Docker daemon, accessed via bollard API
- **Logs**: Written to `/var/log/vpn/` or specified directory

### Key Gotchas and Solutions

1. **Permission Errors**: The system handles permission denied errors gracefully:
   ```rust
   // In UserManager::load_users_from_disk()
   if e.kind() == std::io::ErrorKind::PermissionDenied {
       // Switch to read-only mode
       return Ok(());
   }
   ```

2. **Docker API Changes**: Using bollard 0.15, some APIs changed:
   - CPU stats are no longer Option<T>
   - wait_container returns a Stream, not a Future
   - Network bytes don't return Option

3. **Lifetime Issues**: BatchOperations uses Arc<UserManager> instead of lifetimes to avoid complexity.

4. **Import Paths**: 
   - VpnProtocol comes from `vpn_users::user::VpnProtocol`
   - Protocol/Direction come from `vpn_network::firewall::{Protocol, Direction}`

## Testing Strategy

### Unit Tests
- Each crate has unit tests in `src/` files using `#[cfg(test)]` modules
- Test data uses tempdir for isolation
- Mock Docker responses for container tests

### Integration Tests
- Located in `tests/integration_tests.rs`
- Test CLI binary compilation and execution
- Verify workspace builds successfully

### Manual Testing Scenarios
1. Test privilege escalation: `vpn users create testuser`
2. Test read-only mode: `vpn users list` (without sudo)
3. Test migration: `vpn migrate from-bash --source /opt/v2ray`
4. Test performance: `vpn benchmark --compare-bash`

## CI/CD Pipeline

GitHub Actions workflows (`.github/workflows/`):
- **ci.yml**: Tests on Ubuntu and macOS with stable and beta Rust
- **release.yml**: Automated releases with binary artifacts
- Security audit with cargo-audit
- Code coverage with tarpaulin
- Cross-compilation for ARM architectures
- Multi-arch Docker image builds
- Caching for faster builds

## Migration from Bash

The system includes comprehensive migration tools:
1. **Analysis**: `vpn migrate analyze --source /opt/v2ray`
2. **Backup**: `vpn migrate backup --source /opt/v2ray`
3. **Migration**: `vpn migrate from-bash --source /opt/v2ray`
4. **Verification**: `vpn migrate verify-migration`
5. **Rollback**: `vpn migrate rollback --backup {path}`

Key preservation during migration:
- User UUIDs and keys
- Server configuration
- Traffic statistics
- Connection links

## Performance Characteristics

Current optimized performance:
- **Startup time**: 0.005s (95% better than original target)
- **Memory usage**: ~10MB (optimized with connection pooling)
- **Docker operations**: <20ms (with caching)
- **User creation**: 15ms
- **Key generation**: 8ms
- Concurrent operations via Tokio async runtime
- Zero-cost abstractions for type safety

Compared to original Bash implementation:
- 26x faster startup time
- 73% reduction in memory usage

## Common Development Tasks

### Adding a New Command
1. Add variant to `Commands` enum in `crates/vpn-cli/src/cli.rs`
2. Add handler method in `CommandHandler` (commands.rs)
3. Update pattern match in `main.rs`
4. Add tests in relevant crate

### Updating Docker API Calls
1. Check bollard 0.15 documentation for API
2. Handle both success and error cases
3. Update error types if needed
4. Test with actual Docker daemon

### Adding New User Fields
1. Update `User` struct in `vpn-users/src/user.rs`
2. Add migration for existing users
3. Update serialization/deserialization
4. Update CLI display formatting

## Documentation Structure

Comprehensive documentation is organized in the `docs/` directory:
- **docs/CHANGELOG.md**: Complete version history and migration guides
- **docs/architecture/**: System architecture diagrams and design docs
- **docs/guides/**: User guides for Docker, operations, performance, security
- **docs/specs/**: Technical specifications for components

## Project Status

**Current Status**: Production Ready - Maintenance Mode
- Core development completed (8 weeks, ~50,000+ lines of code)
- All major features implemented and tested
- Docker Hub images available for multi-arch deployment
- Comprehensive documentation and architecture diagrams
- Focus: Testing improvements, optimization, and future enhancements

</invoke>