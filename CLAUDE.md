# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rust-based VPN management system that provides comprehensive tools for managing Xray (VLESS+Reality), Outline VPN servers, and HTTP/SOCKS5 proxy servers. It's a high-performance replacement for a Bash implementation, offering 420x faster startup and 78% memory reduction.

## Build and Development Commands

### Building the Project
```bash
# Build all workspace members (may have some errors for optional crates)
cargo build --release --workspace

# Build specific binaries
cargo build --release -p vpn-proxy --bin vpn-proxy-auth
DATABASE_URL="sqlite::memory:" cargo build --release -p vpn-identity --bin vpn-identity

# Create full release package
./build-release.sh
```

### Testing
```bash
# Run all tests
cargo test --workspace

# Run tests for specific crate
cargo test -p vpn-server

# Run integration tests
cargo test --test integration_tests
```

### Code Quality
```bash
# Format code
cargo fmt --all

# Run clippy linter
cargo clippy --workspace --all-targets

# Security audit
cargo audit
```

### Running the Application
```bash
# Interactive menu (requires sudo for admin operations)
sudo vpn menu

# Direct commands
vpn users list
vpn status
vpn docker ps
```

## Architecture Overview

### Workspace Structure
The project uses a Cargo workspace with specialized crates:
- `vpn-cli` - Main CLI interface and command routing
- `vpn-server` - VPN server management (install, start, stop)
- `vpn-users` - User management with batch operations
- `vpn-proxy` - HTTP/SOCKS5 proxy implementation
- `vpn-docker` - Docker integration with connection pooling
- `vpn-compose` - Docker Compose orchestration
- `vpn-crypto` - X25519 key generation, password hashing
- `vpn-network` - Network utilities, firewall management
- `vpn-monitor` - Metrics and monitoring integration
- `vpn-identity` - LDAP/OAuth2 authentication service
- `vpn-types` - Shared types and validation

### Key Design Patterns

1. **Error Handling**: Uses `thiserror` for custom errors, `anyhow` for error propagation
2. **Async Runtime**: Tokio-based async throughout, with runtime management in `vpn-runtime`
3. **Docker Integration**: Connection pooling via `bollard`, lazy initialization
4. **Configuration**: TOML-based configs in `/opt/vpn/configs/`
5. **Zero-Copy I/O**: Uses Linux splice for proxy performance
6. **Privilege Management**: Automatic sudo escalation for privileged operations

### Important Files and Paths

- Main entry point: `crates/vpn-cli/src/main.rs`
- CLI command routing: `crates/vpn-cli/src/commands.rs`
- Docker operations: `crates/vpn-docker/src/container.rs`
- User management: `crates/vpn-users/src/manager.rs`
- Proxy server: `crates/vpn-proxy/src/`

### Deployment and Installation

- Release builds use `build-release.sh` to create distribution archive
- Install script at `templates/release-scripts/install.sh`
- Docker Compose templates in `templates/docker-compose/`
- Service configs for Traefik, Xray, etc. in `templates/`

### Database and State

- Uses SQLite for vpn-identity (compile-time verification via sqlx)
- JSON files for user data in `/opt/vpn/db/`
- Redis for session management (when deployed)
- PostgreSQL for production deployment