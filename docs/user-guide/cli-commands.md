# CLI Commands Reference

Complete reference for all VPN Manager command-line interface commands.

## Global Options

These options are available for all commands:

```bash
vpn [GLOBAL_OPTIONS] COMMAND [ARGS]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--config PATH` | Configuration file path | `~/.config/vpn-manager/config.toml` |
| `--verbose, -v` | Enable verbose output | `False` |
| `--quiet, -q` | Suppress non-essential output | `False` |
| `--format FORMAT` | Output format: table, json, yaml, plain | `table` |
| `--no-color` | Disable colored output | `False` |
| `--help` | Show help message | |
| `--version` | Show version information | |

## User Management

### `vpn users`

Manage VPN users and their configurations.

#### `vpn users list`

List all users with their details.

```bash
vpn users list [OPTIONS]
```

**Options:**
- `--status STATUS`: Filter by user status (active, inactive, suspended)
- `--protocol PROTOCOL`: Filter by protocol (vless, shadowsocks, wireguard)
- `--format FORMAT`: Output format (table, json, yaml, plain)
- `--show-keys`: Include user keys in output
- `--show-traffic`: Include traffic statistics

**Examples:**
```bash
# List all users
vpn users list

# List only active VLESS users
vpn users list --status active --protocol vless

# Export users as JSON
vpn users list --format json > users-backup.json

# Show users with traffic stats
vpn users list --show-traffic --format table
```

#### `vpn users create`

Create a new VPN user.

```bash
vpn users create USERNAME [OPTIONS]
```

**Arguments:**
- `USERNAME`: Unique username for the user

**Options:**
- `--protocol PROTOCOL`: VPN protocol (vless, shadowsocks, wireguard) [required]
- `--email EMAIL`: User email address
- `--expires DURATION`: Expiration duration (e.g., 30d, 1y, never)
- `--traffic-limit BYTES`: Traffic limit in bytes (e.g., 10GB, 1TB)
- `--description TEXT`: User description
- `--generate-qr`: Generate QR code for connection

**Examples:**
```bash
# Create basic VLESS user
vpn users create alice --protocol vless

# Create user with email and expiration
vpn users create bob --protocol shadowsocks --email bob@example.com --expires 30d

# Create user with traffic limit
vpn users create carol --protocol wireguard --traffic-limit 10GB

# Create user and show QR code
vpn users create dave --protocol vless --generate-qr
```

#### `vpn users show`

Show detailed information about a specific user.

```bash
vpn users show USERNAME [OPTIONS]
```

**Options:**
- `--connection-info`: Show connection details and configuration
- `--qr-code`: Display QR code for mobile clients
- `--config-file`: Show client configuration file
- `--keys`: Show encryption keys

**Examples:**
```bash
# Show user details
vpn users show alice

# Show connection information
vpn users show alice --connection-info

# Show QR code
vpn users show alice --qr-code

# Show client config file
vpn users show alice --config-file
```

#### `vpn users delete`

Delete a user.

```bash
vpn users delete USERNAME [OPTIONS]
```

**Options:**
- `--force`: Skip confirmation prompt
- `--keep-data`: Keep user data and statistics

**Examples:**
```bash
# Delete user with confirmation
vpn users delete alice

# Force delete without confirmation
vpn users delete bob --force

# Delete user but keep statistics
vpn users delete carol --keep-data
```

#### `vpn users update`

Update user properties.

```bash
vpn users update USERNAME [OPTIONS]
```

**Options:**
- `--email EMAIL`: Update email address
- `--status STATUS`: Update status (active, inactive, suspended)
- `--expires DURATION`: Update expiration
- `--traffic-limit BYTES`: Update traffic limit
- `--description TEXT`: Update description

**Examples:**
```bash
# Update user email
vpn users update alice --email alice-new@example.com

# Suspend user
vpn users update bob --status suspended

# Extend expiration
vpn users update carol --expires 60d
```

#### Additional User Commands

```bash
# Search users
vpn users search QUERY

# Get user statistics
vpn users stats [USERNAME]

# Reset user traffic
vpn users reset-traffic USERNAME

# Export users
vpn users export [--format json|yaml] [--include-keys]

# Import users
vpn users import FILE [--skip-existing] [--update-existing]

# Batch create users
vpn users create-batch FILE
```

## Server Management

### `vpn server`

Manage VPN servers and their lifecycle.

#### `vpn server install`

Install a new VPN server.

```bash
vpn server install [OPTIONS]
```

**Options:**
- `--protocol PROTOCOL`: VPN protocol (vless, shadowsocks, wireguard) [required]
- `--port PORT`: Server port [required]
- `--name NAME`: Server name (default: protocol-server)
- `--domain DOMAIN`: Server domain name
- `--network CIDR`: Network subnet for WireGuard
- `--dns SERVERS`: DNS servers (comma-separated)
- `--auto-start`: Start server after installation

**Examples:**
```bash
# Install VLESS server
vpn server install --protocol vless --port 8443 --name main-server

# Install Shadowsocks with domain
vpn server install --protocol shadowsocks --port 8444 --name ss-server --domain ss.example.com

# Install WireGuard with custom network
vpn server install --protocol wireguard --port 51820 --network 10.0.0.0/24 --auto-start
```

#### `vpn server list`

List all installed servers.

```bash
vpn server list [OPTIONS]
```

**Options:**
- `--status STATUS`: Filter by status (running, stopped, error)
- `--protocol PROTOCOL`: Filter by protocol
- `--show-config`: Include server configuration

**Examples:**
```bash
# List all servers
vpn server list

# List only running servers
vpn server list --status running

# Show server configurations
vpn server list --show-config --format yaml
```

#### `vpn server start`

Start a VPN server.

```bash
vpn server start [NAME] [OPTIONS]
```

**Options:**
- `--all`: Start all servers
- `--wait`: Wait for server to be healthy before returning

**Examples:**
```bash
# Start specific server
vpn server start main-server

# Start all servers
vpn server start --all

# Start and wait for health check
vpn server start main-server --wait
```

#### `vpn server stop`

Stop a VPN server.

```bash
vpn server stop [NAME] [OPTIONS]
```

**Options:**
- `--all`: Stop all servers
- `--timeout SECONDS`: Timeout for graceful shutdown

**Examples:**
```bash
# Stop specific server
vpn server stop main-server

# Stop all servers
vpn server stop --all

# Stop with custom timeout
vpn server stop main-server --timeout 30
```

#### `vpn server restart`

Restart a VPN server.

```bash
vpn server restart [NAME] [OPTIONS]
```

#### `vpn server status`

Show server status and statistics.

```bash
vpn server status [NAME] [OPTIONS]
```

**Options:**
- `--detailed`: Show detailed statistics
- `--health`: Show health check status
- `--all`: Show status for all servers

#### `vpn server logs`

Show server logs.

```bash
vpn server logs [NAME] [OPTIONS]
```

**Options:**
- `--follow, -f`: Follow log output
- `--tail LINES`: Number of lines to show from end
- `--since DURATION`: Show logs since duration (e.g., 1h, 30m)
- `--level LEVEL`: Filter by log level

**Examples:**
```bash
# Show recent logs
vpn server logs main-server --tail 50

# Follow logs in real-time
vpn server logs main-server --follow

# Show error logs from last hour
vpn server logs main-server --since 1h --level error
```

#### `vpn server remove`

Remove (uninstall) a VPN server.

```bash
vpn server remove NAME [OPTIONS]
```

**Options:**
- `--force`: Skip confirmation and force removal
- `--keep-data`: Keep server data directory

## Proxy Services

### `vpn proxy`

Manage HTTP and SOCKS5 proxy servers.

#### `vpn proxy start`

Start a proxy server.

```bash
vpn proxy start [OPTIONS]
```

**Options:**
- `--type TYPE`: Proxy type (http, socks5) [required]
- `--port PORT`: Proxy port [required]
- `--name NAME`: Proxy name (default: type-proxy-port)
- `--auth`: Require authentication
- `--no-auth`: Disable authentication
- `--rate-limit RATE`: Rate limit (requests per minute)

**Examples:**
```bash
# Start HTTP proxy with authentication
vpn proxy start --type http --port 8888 --auth

# Start SOCKS5 proxy without authentication
vpn proxy start --type socks5 --port 1080 --no-auth

# Start with rate limiting
vpn proxy start --type http --port 8889 --rate-limit 100
```

#### `vpn proxy list`

List running proxy servers.

```bash
vpn proxy list [OPTIONS]
```

**Options:**
- `--detailed`: Show detailed information

#### `vpn proxy stop`

Stop a proxy server.

```bash
vpn proxy stop NAME [OPTIONS]
```

**Options:**
- `--all`: Stop all proxy servers

#### `vpn proxy status`

Show proxy server statistics.

```bash
vpn proxy status NAME [OPTIONS]
```

**Options:**
- `--detailed`: Show detailed statistics
- `--connections`: Show active connections

#### `vpn proxy test`

Test proxy functionality.

```bash
vpn proxy test [OPTIONS]
```

**Options:**
- `--type TYPE`: Proxy type to test
- `--port PORT`: Proxy port
- `--url URL`: Test URL (default: https://httpbin.org/ip)
- `--timeout SECONDS`: Request timeout

**Examples:**
```bash
# Test HTTP proxy
vpn proxy test --type http --port 8888

# Test with custom URL
vpn proxy test --type http --port 8888 --url https://google.com
```

## Configuration Management

### `vpn config`

Manage VPN Manager configuration.

#### `vpn config show`

Display current configuration.

```bash
vpn config show [OPTIONS]
```

**Options:**
- `--section SECTION`: Show specific section only
- `--format FORMAT`: Output format

#### `vpn config set`

Set configuration value.

```bash
vpn config set KEY VALUE
```

**Examples:**
```bash
# Set server domain
vpn config set server.domain vpn.example.com

# Set log level
vpn config set logging.level debug

# Set database URL
vpn config set database.url sqlite:///custom.db
```

#### `vpn config get`

Get configuration value.

```bash
vpn config get KEY
```

#### `vpn config reset`

Reset configuration to defaults.

```bash
vpn config reset [OPTIONS]
```

**Options:**
- `--section SECTION`: Reset specific section only
- `--force`: Skip confirmation

#### `vpn config init`

Initialize configuration directory and files.

```bash
vpn config init [OPTIONS]
```

**Options:**
- `--force`: Overwrite existing configuration

## Monitoring and Statistics

### `vpn monitor`

Monitor system and VPN statistics.

#### `vpn monitor stats`

Show system statistics.

```bash
vpn monitor stats [OPTIONS]
```

**Options:**
- `--refresh SECONDS`: Auto-refresh interval
- `--detailed`: Show detailed statistics

#### `vpn monitor traffic`

Show traffic statistics.

```bash
vpn monitor traffic [OPTIONS]
```

**Options:**
- `--user USERNAME`: Show traffic for specific user
- `--server NAME`: Show traffic for specific server
- `--since DURATION`: Show traffic since duration

#### `vpn monitor logs`

Show aggregated logs.

```bash
vpn monitor logs [OPTIONS]
```

**Options:**
- `--level LEVEL`: Filter by log level
- `--component COMPONENT`: Filter by component
- `--since DURATION`: Show logs since duration
- `--follow`: Follow logs in real-time

## System Utilities

### `vpn doctor`

Run system diagnostics.

```bash
vpn doctor [OPTIONS]
```

**Options:**
- `--check COMPONENT`: Check specific component (docker, network, permissions)
- `--fix`: Attempt to fix detected issues
- `--verbose`: Show detailed diagnostic information

### `vpn version`

Show version information.

```bash
vpn version [OPTIONS]
```

**Options:**
- `--detailed`: Show detailed version information
- `--check-updates`: Check for available updates

### `vpn logs`

Show VPN Manager logs.

```bash
vpn logs [OPTIONS]
```

**Options:**
- `--level LEVEL`: Filter by log level (debug, info, warning, error)
- `--component COMPONENT`: Filter by component
- `--since DURATION`: Show logs since duration
- `--tail LINES`: Show last N lines
- `--follow`: Follow logs in real-time

### `vpn tui`

Launch the Terminal User Interface.

```bash
vpn tui [OPTIONS]
```

**Options:**
- `--theme THEME`: UI theme (dark, light, auto)
- `--screen SCREEN`: Start with specific screen

## Output Formats

VPN Manager supports multiple output formats:

### Table Format (Default)
```bash
vpn users list --format table
```
Displays data in a formatted table with columns.

### JSON Format
```bash
vpn users list --format json
```
Machine-readable JSON output for scripting.

### YAML Format
```bash
vpn users list --format yaml
```
Human-readable YAML format.

### Plain Format
```bash
vpn users list --format plain
```
Simple text output without formatting.

## Environment Variables

Configure VPN Manager using environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `VPN_CONFIG_PATH` | Configuration file path | `~/.config/vpn-manager/config.toml` |
| `VPN_LOG_LEVEL` | Log level | `info` |
| `VPN_DATABASE_URL` | Database URL | `sqlite:///db/vpn.db` |
| `VPN_DOCKER_HOST` | Docker host | `unix:///var/run/docker.sock` |
| `VPN_NO_COLOR` | Disable colors | `false` |

## Examples and Common Workflows

### Setup New Environment
```bash
# Initialize and setup
vpn config init
vpn doctor --check all --fix

# Install servers
vpn server install --protocol vless --port 8443 --name main
vpn server install --protocol shadowsocks --port 8444 --name backup

# Create users
vpn users create admin --protocol vless --email admin@example.com
vpn users create user1 --protocol vless --expires 30d
vpn users create user2 --protocol shadowsocks

# Start services
vpn server start --all
vpn proxy start --type http --port 8888 --auth
```

### Backup and Restore
```bash
# Backup
vpn users export --format json --include-keys > users-backup.json
vpn config export > config-backup.toml

# Restore on new system
vpn config import config-backup.toml
vpn users import users-backup.json
```

### Monitoring Workflow
```bash
# Real-time monitoring
vpn monitor stats --refresh 5 &
vpn monitor traffic --refresh 10 &
vpn server logs main-server --follow &

# Or use TUI for interactive monitoring
vpn tui
```

## Shell Completion

Enable shell completion for better CLI experience:

```bash
# Bash
vpn --install-completion bash
source ~/.bashrc

# Zsh
vpn --install-completion zsh
source ~/.zshrc

# Fish
vpn --install-completion fish
source ~/.config/fish/config.fish
```

## Error Handling

Common error exit codes:

- `0`: Success
- `1`: General error
- `2`: Invalid command or arguments
- `3`: Permission denied
- `4`: Service unavailable
- `5`: Configuration error

For detailed error information, use `--verbose` flag or check logs with `vpn logs --level error`.