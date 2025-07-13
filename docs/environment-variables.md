# Environment Variables

VPN Manager supports extensive configuration through environment variables. All environment variables use the `VPN_` prefix and support nested configuration using double underscores (`__`).

## Configuration Hierarchy

Environment variables follow this precedence order (highest to lowest):

1. **Environment variables** (VPN_*)
2. **Configuration files** (~/.config/vpn-manager/config.yaml)
3. **System config** (/etc/vpn-manager/config.yaml)
4. **Default values**

## Variable Format

### Basic Variables
```bash
VPN_DEBUG=true
VPN_LOG_LEVEL=DEBUG
VPN_APP_NAME="My VPN Manager"
```

### Nested Configuration
Use double underscores (`__`) to set nested configuration values:

```bash
# Database configuration
VPN_DATABASE__URL="postgresql://user:pass@localhost/vpn"
VPN_DATABASE__ECHO=true
VPN_DATABASE__POOL_SIZE=10

# Docker configuration  
VPN_DOCKER__SOCKET="/var/run/docker.sock"
VPN_DOCKER__TIMEOUT=60
VPN_DOCKER__MAX_CONNECTIONS=15

# Network configuration
VPN_NETWORK__DEFAULT_PORT_RANGE="10000,20000"
VPN_NETWORK__ENABLE_FIREWALL=true

# Security configuration
VPN_SECURITY__ENABLE_AUTH=true
VPN_SECURITY__TOKEN_EXPIRE_MINUTES=1440

# TUI configuration
VPN_TUI__THEME=dark
VPN_TUI__REFRESH_RATE=2

# Monitoring configuration
VPN_MONITORING__ENABLE_METRICS=true
VPN_MONITORING__METRICS_PORT=9090
```

## Complete Variable Reference

### Application Settings

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_APP_NAME` | Application name | "VPN Manager" | `VPN_APP_NAME="My VPN"` |
| `VPN_VERSION` | Application version | "2.0.0" | `VPN_VERSION="2.1.0"` |
| `VPN_DEBUG` | Enable debug mode | `false` | `VPN_DEBUG=true` |
| `VPN_LOG_LEVEL` | Logging level | "INFO" | `VPN_LOG_LEVEL=DEBUG` |
| `VPN_DEFAULT_PROTOCOL` | Default VPN protocol | "vless" | `VPN_DEFAULT_PROTOCOL=shadowsocks` |
| `VPN_AUTO_START_SERVERS` | Auto-start servers | `true` | `VPN_AUTO_START_SERVERS=false` |
| `VPN_RELOAD` | Enable hot reload | `false` | `VPN_RELOAD=true` |
| `VPN_PROFILE` | Enable profiling | `false` | `VPN_PROFILE=true` |

### Path Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_PATHS__INSTALL_PATH` | Installation directory | "/opt/vpn" | `VPN_PATHS__INSTALL_PATH=/usr/local/vpn` |
| `VPN_PATHS__CONFIG_PATH` | Config directory | "~/.config/vpn-manager" | `VPN_PATHS__CONFIG_PATH=/etc/vpn` |
| `VPN_PATHS__DATA_PATH` | Data directory | "~/.local/share/vpn-manager" | `VPN_PATHS__DATA_PATH=/var/lib/vpn` |
| `VPN_PATHS__LOG_PATH` | Log directory | "~/.local/share/vpn-manager/logs" | `VPN_PATHS__LOG_PATH=/var/log/vpn` |
| `VPN_PATHS__TEMPLATE_PATH` | Template directory | Auto-detected | `VPN_PATHS__TEMPLATE_PATH=/opt/vpn/templates` |

### Database Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_DATABASE__URL` | Database connection URL | "sqlite+aiosqlite:///db/vpn.db" | `VPN_DATABASE__URL=postgresql://user:pass@localhost/vpn` |
| `VPN_DATABASE__ECHO` | Enable SQL query logging | `false` | `VPN_DATABASE__ECHO=true` |
| `VPN_DATABASE__POOL_SIZE` | Connection pool size | 5 | `VPN_DATABASE__POOL_SIZE=10` |
| `VPN_DATABASE__MAX_OVERFLOW` | Pool overflow connections | 10 | `VPN_DATABASE__MAX_OVERFLOW=20` |
| `VPN_DATABASE__POOL_TIMEOUT` | Pool timeout (seconds) | 30 | `VPN_DATABASE__POOL_TIMEOUT=60` |

### Docker Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_DOCKER__SOCKET` | Docker socket path | "/var/run/docker.sock" | `VPN_DOCKER__SOCKET=tcp://localhost:2376` |
| `VPN_DOCKER__TIMEOUT` | Operation timeout (seconds) | 30 | `VPN_DOCKER__TIMEOUT=60` |
| `VPN_DOCKER__MAX_CONNECTIONS` | Max client connections | 10 | `VPN_DOCKER__MAX_CONNECTIONS=20` |
| `VPN_DOCKER__REGISTRY_URL` | Private registry URL | `null` | `VPN_DOCKER__REGISTRY_URL=registry.company.com` |
| `VPN_DOCKER__REGISTRY_USERNAME` | Registry username | `null` | `VPN_DOCKER__REGISTRY_USERNAME=myuser` |
| `VPN_DOCKER__REGISTRY_PASSWORD` | Registry password | `null` | `VPN_DOCKER__REGISTRY_PASSWORD=mypass` |

### Network Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_NETWORK__DEFAULT_PORT_RANGE` | Port range (min,max) | "10000,65000" | `VPN_NETWORK__DEFAULT_PORT_RANGE=8000,9000` |
| `VPN_NETWORK__ENABLE_FIREWALL` | Enable firewall management | `true` | `VPN_NETWORK__ENABLE_FIREWALL=false` |
| `VPN_NETWORK__FIREWALL_BACKUP` | Backup firewall rules | `true` | `VPN_NETWORK__FIREWALL_BACKUP=false` |
| `VPN_NETWORK__ALLOWED_NETWORKS` | Allowed CIDR networks | "0.0.0.0/0" | `VPN_NETWORK__ALLOWED_NETWORKS=192.168.1.0/24,10.0.0.0/8` |
| `VPN_NETWORK__BLOCKED_PORTS` | Blocked port numbers | `""` | `VPN_NETWORK__BLOCKED_PORTS=22,80,443` |
| `VPN_NETWORK__HEALTH_CHECK_ENDPOINTS` | Health check IPs | "8.8.8.8,1.1.1.1" | `VPN_NETWORK__HEALTH_CHECK_ENDPOINTS=1.1.1.1` |

### Security Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_SECURITY__ENABLE_AUTH` | Enable authentication | `true` | `VPN_SECURITY__ENABLE_AUTH=false` |
| `VPN_SECURITY__SECRET_KEY` | JWT secret key | Auto-generated | `VPN_SECURITY__SECRET_KEY=supersecretkey123` |
| `VPN_SECURITY__TOKEN_EXPIRE_MINUTES` | Token expiration | 1440 (24h) | `VPN_SECURITY__TOKEN_EXPIRE_MINUTES=60` |
| `VPN_SECURITY__MAX_LOGIN_ATTEMPTS` | Max login attempts | 5 | `VPN_SECURITY__MAX_LOGIN_ATTEMPTS=3` |
| `VPN_SECURITY__LOCKOUT_DURATION` | Lockout duration (minutes) | 15 | `VPN_SECURITY__LOCKOUT_DURATION=30` |
| `VPN_SECURITY__PASSWORD_MIN_LENGTH` | Min password length | 8 | `VPN_SECURITY__PASSWORD_MIN_LENGTH=12` |
| `VPN_SECURITY__REQUIRE_PASSWORD_COMPLEXITY` | Require complex passwords | `true` | `VPN_SECURITY__REQUIRE_PASSWORD_COMPLEXITY=false` |

### Monitoring Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_MONITORING__ENABLE_METRICS` | Enable metrics collection | `true` | `VPN_MONITORING__ENABLE_METRICS=false` |
| `VPN_MONITORING__METRICS_PORT` | Metrics server port | 9090 | `VPN_MONITORING__METRICS_PORT=8080` |
| `VPN_MONITORING__METRICS_RETENTION_DAYS` | Metrics retention | 30 | `VPN_MONITORING__METRICS_RETENTION_DAYS=7` |
| `VPN_MONITORING__HEALTH_CHECK_INTERVAL` | Health check interval (seconds) | 30 | `VPN_MONITORING__HEALTH_CHECK_INTERVAL=60` |
| `VPN_MONITORING__ALERT_CPU_THRESHOLD` | CPU alert threshold (%) | 90.0 | `VPN_MONITORING__ALERT_CPU_THRESHOLD=80.0` |
| `VPN_MONITORING__ALERT_MEMORY_THRESHOLD` | Memory alert threshold (%) | 90.0 | `VPN_MONITORING__ALERT_MEMORY_THRESHOLD=85.0` |
| `VPN_MONITORING__ALERT_DISK_THRESHOLD` | Disk alert threshold (%) | 85.0 | `VPN_MONITORING__ALERT_DISK_THRESHOLD=80.0` |
| `VPN_MONITORING__ENABLE_OPENTELEMETRY` | Enable OpenTelemetry | `false` | `VPN_MONITORING__ENABLE_OPENTELEMETRY=true` |
| `VPN_MONITORING__OTLP_ENDPOINT` | OTLP collector endpoint | `null` | `VPN_MONITORING__OTLP_ENDPOINT=http://jaeger:14268` |

### TUI Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VPN_TUI__THEME` | Color theme | "dark" | `VPN_TUI__THEME=light` |
| `VPN_TUI__REFRESH_RATE` | Screen refresh rate (seconds) | 1 | `VPN_TUI__REFRESH_RATE=2` |
| `VPN_TUI__SHOW_STATS` | Show system statistics | `true` | `VPN_TUI__SHOW_STATS=false` |
| `VPN_TUI__SHOW_HELP` | Show help panel | `true` | `VPN_TUI__SHOW_HELP=false` |
| `VPN_TUI__ENABLE_MOUSE` | Enable mouse support | `true` | `VPN_TUI__ENABLE_MOUSE=false` |
| `VPN_TUI__PAGE_SIZE` | Items per page | 20 | `VPN_TUI__PAGE_SIZE=50` |
| `VPN_TUI__ANIMATION_DURATION` | Animation duration (seconds) | 0.3 | `VPN_TUI__ANIMATION_DURATION=0.5` |

## Legacy Variables (Deprecated)

These variables are still supported but deprecated. Use the new nested format instead:

| Legacy Variable | New Variable | Status |
|----------------|--------------|---------|
| `VPN_INSTALL_PATH` | `VPN_PATHS__INSTALL_PATH` | ⚠️ Deprecated |
| `VPN_CONFIG_PATH` | `VPN_PATHS__CONFIG_PATH` | ⚠️ Deprecated |
| `VPN_DATA_PATH` | `VPN_PATHS__DATA_PATH` | ⚠️ Deprecated |
| `VPN_DATABASE_URL` | `VPN_DATABASE__URL` | ⚠️ Deprecated |
| `VPN_DOCKER_HOST` | `VPN_DOCKER__SOCKET` | ⚠️ Deprecated |
| `VPN_NO_COLOR` | Use CLI flag `--no-color` | ⚠️ Deprecated |

## Usage Examples

### Development Environment
```bash
# Set up development environment
export VPN_DEBUG=true
export VPN_LOG_LEVEL=DEBUG
export VPN_DATABASE__URL="sqlite:///dev.db"
export VPN_MONITORING__ENABLE_METRICS=false
export VPN_TUI__THEME=light
```

### Production Environment
```bash
# Production configuration
export VPN_DEBUG=false
export VPN_LOG_LEVEL=INFO
export VPN_DATABASE__URL="postgresql://vpn:password@db:5432/vpn_prod"
export VPN_SECURITY__TOKEN_EXPIRE_MINUTES=60
export VPN_MONITORING__ENABLE_METRICS=true
export VPN_MONITORING__OTLP_ENDPOINT="http://jaeger:14268"
```

### Docker Deployment
```bash
# Docker environment
export VPN_PATHS__INSTALL_PATH="/app"
export VPN_PATHS__CONFIG_PATH="/app/config"
export VPN_PATHS__DATA_PATH="/app/data"
export VPN_DATABASE__URL="postgresql://vpn:password@postgres:5432/vpn"
export VPN_DOCKER__SOCKET="unix:///var/run/docker.sock"
```

### High Security Environment
```bash
# Enhanced security settings
export VPN_SECURITY__ENABLE_AUTH=true
export VPN_SECURITY__PASSWORD_MIN_LENGTH=12
export VPN_SECURITY__REQUIRE_PASSWORD_COMPLEXITY=true
export VPN_SECURITY__MAX_LOGIN_ATTEMPTS=3
export VPN_SECURITY__LOCKOUT_DURATION=30
export VPN_SECURITY__TOKEN_EXPIRE_MINUTES=30
```

## Environment File (.env)

You can also use a `.env` file in your project root or config directory:

```bash
# .env file example
VPN_DEBUG=false
VPN_LOG_LEVEL=INFO
VPN_DATABASE__URL=sqlite:///db/vpn.db
VPN_DOCKER__TIMEOUT=60
VPN_NETWORK__DEFAULT_PORT_RANGE=10000,20000
VPN_SECURITY__ENABLE_AUTH=true
VPN_TUI__THEME=dark
VPN_MONITORING__ENABLE_METRICS=true
```

## Validation

Environment variables are automatically validated on startup:

- **Type checking**: Values are converted to the appropriate data types
- **Range validation**: Numeric values are checked against allowed ranges
- **Format validation**: URLs, file paths, and other formats are validated
- **Dependency checking**: Related settings are validated together

Invalid environment variables will cause the application to exit with detailed error messages.

## Debugging Environment Variables

Use the `vpn config show` command to see the final resolved configuration:

```bash
# Show current configuration including env vars
vpn config show

# Show specific section
vpn config show --section database

# Show in different format
vpn config show --format json
```

For debugging environment variable resolution:

```bash
# Enable debug logging
VPN_DEBUG=true VPN_LOG_LEVEL=DEBUG vpn config show
```