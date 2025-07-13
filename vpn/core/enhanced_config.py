"""Enhanced configuration management with Pydantic 2.11+ features.
"""

from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    computed_field,
    field_serializer,
    field_validator,
    model_validator,
)
from pydantic_settings import BaseSettings, SettingsConfigDict


class LogLevel(str, Enum):
    """Supported log levels."""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class OutputFormat(str, Enum):
    """Supported output formats."""
    TABLE = "table"
    JSON = "json"
    YAML = "yaml"
    PLAIN = "plain"


class Theme(str, Enum):
    """Supported TUI themes."""
    DARK = "dark"
    LIGHT = "light"
    AUTO = "auto"


class ProtocolType(str, Enum):
    """Supported VPN protocols."""
    VLESS = "vless"
    SHADOWSOCKS = "shadowsocks"
    WIREGUARD = "wireguard"
    HTTP = "http"
    SOCKS5 = "socks5"


class DatabaseConfig(BaseModel):
    """Database configuration section."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    url: str = Field(
        default="sqlite+aiosqlite:///vpn.db",
        description="Database connection URL"
    )
    echo: bool = Field(
        default=False,
        description="Enable SQL query logging"
    )
    pool_size: int = Field(
        default=5,
        ge=1,
        le=50,
        description="Database connection pool size"
    )
    max_overflow: int = Field(
        default=10,
        ge=0,
        le=100,
        description="Maximum pool overflow connections"
    )
    pool_timeout: int = Field(
        default=30,
        ge=1,
        le=300,
        description="Connection pool timeout in seconds"
    )

    @field_validator("url")
    @classmethod
    def validate_database_url(cls, v: str) -> str:
        """Validate database URL format."""
        if not v:
            raise ValueError("Database URL cannot be empty")

        supported_schemes = ["sqlite", "sqlite+aiosqlite", "postgresql", "postgresql+asyncpg"]
        scheme = v.split("://")[0] if "://" in v else ""

        if scheme not in supported_schemes:
            raise ValueError(
                f"Unsupported database scheme '{scheme}'. "
                f"Supported: {', '.join(supported_schemes)}"
            )
        return v

    @computed_field
    @property
    def is_sqlite(self) -> bool:
        """Check if using SQLite database."""
        return self.url.startswith("sqlite")

    @computed_field
    @property
    def is_memory_db(self) -> bool:
        """Check if using in-memory database."""
        return ":memory:" in self.url


class DockerConfig(BaseModel):
    """Docker configuration section."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    socket: str = Field(
        default="/var/run/docker.sock",
        description="Docker socket path"
    )
    timeout: int = Field(
        default=30,
        ge=5,
        le=300,
        description="Docker operation timeout in seconds"
    )
    max_connections: int = Field(
        default=10,
        ge=1,
        le=50,
        description="Maximum Docker client connections"
    )
    registry_url: str | None = Field(
        default=None,
        description="Private Docker registry URL"
    )
    registry_username: str | None = Field(
        default=None,
        description="Registry username"
    )
    registry_password: str | None = Field(
        default=None,
        description="Registry password"
    )

    @field_validator("socket")
    @classmethod
    def validate_socket_path(cls, v: str) -> str:
        """Validate Docker socket path."""
        if v.startswith("unix://"):
            socket_path = v[7:]  # Remove unix:// prefix
        else:
            socket_path = v

        if not socket_path.startswith("/"):
            raise ValueError("Docker socket must be an absolute path")

        return v

    @field_serializer("registry_password")
    def serialize_password(self, value: str | None) -> str | None:
        """Mask password in serialization."""
        return "***" if value else None


class NetworkConfig(BaseModel):
    """Network configuration section."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    default_port_range: tuple[int, int] = Field(
        default=(10000, 65000),
        description="Default port range for VPN servers"
    )
    enable_firewall: bool = Field(
        default=True,
        description="Enable automatic firewall management"
    )
    firewall_backup: bool = Field(
        default=True,
        description="Backup firewall rules before modification"
    )
    allowed_networks: list[str] = Field(
        default_factory=lambda: ["0.0.0.0/0"],
        description="Allowed networks for VPN access"
    )
    blocked_ports: set[int] = Field(
        default_factory=set,
        description="Ports blocked from automatic assignment"
    )
    health_check_endpoints: list[str] = Field(
        default_factory=lambda: ["8.8.8.8", "1.1.1.1"],
        description="Endpoints for network health checks"
    )

    @field_validator("default_port_range")
    @classmethod
    def validate_port_range(cls, v: tuple[int, int]) -> tuple[int, int]:
        """Validate port range."""
        min_port, max_port = v
        if min_port < 1024:
            raise ValueError("Minimum port must be >= 1024 for non-root operation")
        if max_port > 65535:
            raise ValueError("Maximum port must be <= 65535")
        if min_port >= max_port:
            raise ValueError("Minimum port must be less than maximum port")
        return v

    @field_validator("allowed_networks")
    @classmethod
    def validate_networks(cls, v: list[str]) -> list[str]:
        """Validate network CIDR notation."""
        import ipaddress
        for network in v:
            try:
                ipaddress.ip_network(network, strict=False)
            except ValueError:
                raise ValueError(f"Invalid network CIDR: {network}")
        return v

    @computed_field
    @property
    def port_range_size(self) -> int:
        """Calculate port range size."""
        return self.default_port_range[1] - self.default_port_range[0] + 1


class SecurityConfig(BaseModel):
    """Security configuration section."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    enable_auth: bool = Field(
        default=True,
        description="Enable authentication"
    )
    secret_key: str | None = Field(
        default=None,
        min_length=32,
        description="Secret key for token generation"
    )
    token_expire_minutes: int = Field(
        default=60 * 24,  # 24 hours
        ge=5,
        le=60 * 24 * 30,  # 30 days
        description="Token expiration time in minutes"
    )
    max_login_attempts: int = Field(
        default=5,
        ge=1,
        le=20,
        description="Maximum login attempts before lockout"
    )
    lockout_duration: int = Field(
        default=15,
        ge=1,
        le=1440,  # 24 hours
        description="Account lockout duration in minutes"
    )
    password_min_length: int = Field(
        default=8,
        ge=4,
        le=128,
        description="Minimum password length"
    )
    require_password_complexity: bool = Field(
        default=True,
        description="Require complex passwords"
    )

    @model_validator(mode="after")
    def validate_auth_requirements(self) -> "SecurityConfig":
        """Validate authentication requirements."""
        if self.enable_auth and not self.secret_key:
            # Generate a default secret key
            import secrets
            self.secret_key = secrets.token_urlsafe(32)
        return self

    @field_serializer("secret_key")
    def serialize_secret_key(self, value: str | None) -> str | None:
        """Mask secret key in serialization."""
        return f"{value[:8]}..." if value else None

    @computed_field
    @property
    def token_expire_timedelta(self) -> timedelta:
        """Get token expiration as timedelta."""
        return timedelta(minutes=self.token_expire_minutes)


class MonitoringConfig(BaseModel):
    """Monitoring and metrics configuration."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    enable_metrics: bool = Field(
        default=True,
        description="Enable metrics collection"
    )
    metrics_port: int = Field(
        default=9090,
        ge=1024,
        le=65535,
        description="Metrics server port"
    )
    metrics_retention_days: int = Field(
        default=30,
        ge=1,
        le=365,
        description="Metrics retention period in days"
    )
    health_check_interval: int = Field(
        default=30,
        ge=5,
        le=300,
        description="Health check interval in seconds"
    )
    alert_cpu_threshold: float = Field(
        default=90.0,
        ge=10.0,
        le=100.0,
        description="CPU usage alert threshold (%)"
    )
    alert_memory_threshold: float = Field(
        default=90.0,
        ge=10.0,
        le=100.0,
        description="Memory usage alert threshold (%)"
    )
    alert_disk_threshold: float = Field(
        default=85.0,
        ge=10.0,
        le=100.0,
        description="Disk usage alert threshold (%)"
    )
    enable_opentelemetry: bool = Field(
        default=False,
        description="Enable OpenTelemetry tracing"
    )
    otlp_endpoint: str | None = Field(
        default=None,
        description="OpenTelemetry collector endpoint"
    )

    @computed_field
    @property
    def metrics_retention_timedelta(self) -> timedelta:
        """Get retention period as timedelta."""
        return timedelta(days=self.metrics_retention_days)


class TUIConfig(BaseModel):
    """Terminal UI configuration section."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    theme: Theme = Field(
        default=Theme.DARK,
        description="TUI color theme"
    )
    refresh_rate: int = Field(
        default=1,
        ge=1,
        le=10,
        description="Screen refresh rate in seconds"
    )
    show_stats: bool = Field(
        default=True,
        description="Show system statistics"
    )
    show_help: bool = Field(
        default=True,
        description="Show help panel"
    )
    enable_mouse: bool = Field(
        default=True,
        description="Enable mouse support"
    )
    page_size: int = Field(
        default=20,
        ge=5,
        le=100,
        description="Items per page in lists"
    )
    animation_duration: float = Field(
        default=0.3,
        ge=0.0,
        le=2.0,
        description="Animation duration in seconds"
    )
    keyboard_shortcuts: dict[str, str] = Field(
        default_factory=lambda: {
            "quit": "q,ctrl+c",
            "help": "h,f1",
            "refresh": "r,f5",
            "menu": "m,f10",
            "search": "/,ctrl+f",
        },
        description="Keyboard shortcuts mapping"
    )


class PathConfig(BaseModel):
    """Path configuration section."""
    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid"
    )

    install_path: Path = Field(
        default=Path("/opt/vpn"),
        description="Installation directory"
    )
    config_path: Path = Field(
        default=Path.home() / ".config" / "vpn-manager",
        description="Configuration directory"
    )
    data_path: Path = Field(
        default=Path.home() / ".local" / "share" / "vpn-manager",
        description="Data directory"
    )
    log_path: Path = Field(
        default=Path.home() / ".local" / "share" / "vpn-manager" / "logs",
        description="Log directory"
    )
    template_path: Path = Field(
        default=Path(__file__).parent.parent / "templates",
        description="Template directory"
    )

    @field_validator("install_path", "config_path", "data_path", "log_path")
    @classmethod
    def create_paths(cls, v: Path) -> Path:
        """Create directories if they don't exist."""
        v = v.expanduser().absolute()
        try:
            v.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            # If we can't create the directory, fall back to user directory
            if str(v).startswith("/opt/") or str(v).startswith("/etc/"):
                fallback = Path.home() / ".local" / "share" / "vpn-manager"
                fallback.mkdir(parents=True, exist_ok=True)
                return fallback
            raise
        return v

    @computed_field
    @property
    def backup_path(self) -> Path:
        """Get backup directory path."""
        backup_dir = self.data_path / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        return backup_dir

    def get_server_config_path(self, server_name: str) -> Path:
        """Get path for server configuration file."""
        server_dir = self.config_path / "servers"
        server_dir.mkdir(parents=True, exist_ok=True)
        return server_dir / f"{server_name}.toml"

    def get_user_data_path(self, username: str) -> Path:
        """Get path for user data directory."""
        user_dir = self.data_path / "users" / username
        user_dir.mkdir(parents=True, exist_ok=True)
        return user_dir


class EnhancedSettings(BaseSettings):
    """Enhanced application settings with Pydantic 2.11+ features.
    
    Environment variables are prefixed with VPN_.
    For example: VPN_DEBUG=true, VPN_APP__LOG_LEVEL=DEBUG
    """
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="VPN_",
        env_nested_delimiter="__",
        case_sensitive=False,
        validate_default=True,
        extra="ignore",
        str_strip_whitespace=True,
    )

    # Application metadata
    app_name: str = Field(
        default="VPN Manager",
        description="Application name"
    )
    version: str = Field(
        default="2.0.0",
        description="Application version"
    )
    debug: bool = Field(
        default=False,
        description="Enable debug mode"
    )
    log_level: LogLevel = Field(
        default=LogLevel.INFO,
        description="Logging level"
    )

    # Configuration sections
    paths: PathConfig = Field(
        default_factory=PathConfig,
        description="File system paths"
    )
    database: DatabaseConfig = Field(
        default_factory=DatabaseConfig,
        description="Database configuration"
    )
    docker: DockerConfig = Field(
        default_factory=DockerConfig,
        description="Docker configuration"
    )
    network: NetworkConfig = Field(
        default_factory=NetworkConfig,
        description="Network configuration"
    )
    security: SecurityConfig = Field(
        default_factory=SecurityConfig,
        description="Security configuration"
    )
    monitoring: MonitoringConfig = Field(
        default_factory=MonitoringConfig,
        description="Monitoring configuration"
    )
    tui: TUIConfig = Field(
        default_factory=TUIConfig,
        description="Terminal UI configuration"
    )

    # Server defaults
    default_protocol: ProtocolType = Field(
        default=ProtocolType.VLESS,
        description="Default VPN protocol"
    )
    auto_start_servers: bool = Field(
        default=True,
        description="Auto-start servers on application start"
    )

    # Development settings
    reload: bool = Field(
        default=False,
        description="Enable hot reload in development"
    )
    profile: bool = Field(
        default=False,
        description="Enable performance profiling"
    )

    @model_validator(mode="after")
    def post_validation(self) -> "EnhancedSettings":
        """Post-validation processing."""
        # Ensure log directory exists
        self.paths.log_path.mkdir(parents=True, exist_ok=True)

        # Set database path if using SQLite
        if self.database.is_sqlite and not self.database.is_memory_db:
            # Update database URL to use absolute path
            if ":///" in self.database.url:
                db_file = self.database.url.split("///")[-1]
                if not db_file.startswith("/"):
                    # Relative path, make it absolute
                    absolute_path = self.paths.data_path / db_file
                    scheme = self.database.url.split("///")[0]
                    self.database.url = f"{scheme}///{absolute_path}"

        return self

    @computed_field
    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.debug or self.reload or self.profile

    @computed_field
    @property
    def config_file_paths(self) -> list[Path]:
        """Get list of potential config file locations."""
        return [
            Path.cwd() / "config.yaml",
            Path.cwd() / "config.toml",
            self.paths.config_path / "config.yaml",
            self.paths.config_path / "config.toml",
            Path("/etc/vpn-manager/config.yaml"),
            Path("/etc/vpn-manager/config.toml"),
        ]

    @field_serializer("log_level")
    def serialize_log_level(self, value: LogLevel) -> str:
        """Serialize log level enum."""
        return value.value


class RuntimeConfig(BaseModel):
    """Runtime configuration that can be modified during execution."""
    model_config = ConfigDict(
        validate_assignment=True,
        extra="forbid",
        str_strip_whitespace=True,
    )

    # Runtime flags
    dry_run: bool = Field(
        default=False,
        description="Perform dry run without making changes"
    )
    force: bool = Field(
        default=False,
        description="Force operation even if risky"
    )
    quiet: bool = Field(
        default=False,
        description="Suppress non-error output"
    )
    verbose: bool = Field(
        default=False,
        description="Enable verbose output"
    )
    output_format: OutputFormat = Field(
        default=OutputFormat.TABLE,
        description="Output format for commands"
    )
    no_color: bool = Field(
        default=False,
        description="Disable colored output"
    )

    # Operation settings
    operation_timeout: int = Field(
        default=300,  # 5 minutes
        ge=10,
        le=3600,  # 1 hour
        description="Default operation timeout in seconds"
    )
    batch_size: int = Field(
        default=50,
        ge=1,
        le=1000,
        description="Batch size for bulk operations"
    )
    retry_attempts: int = Field(
        default=3,
        ge=1,
        le=10,
        description="Number of retry attempts for failed operations"
    )

    # Current session info
    session_id: str | None = Field(
        default=None,
        description="Current session identifier"
    )
    user_id: str | None = Field(
        default=None,
        description="Current user identifier"
    )
    start_time: datetime = Field(
        default_factory=datetime.utcnow,
        description="Session start time"
    )

    @computed_field
    @property
    def session_duration(self) -> timedelta:
        """Get current session duration."""
        return datetime.utcnow() - self.start_time

    @computed_field
    @property
    def effective_log_level(self) -> LogLevel:
        """Get effective log level based on flags."""
        if self.verbose:
            return LogLevel.DEBUG
        elif self.quiet:
            return LogLevel.ERROR
        else:
            return LogLevel.INFO


# Global configuration instances
_enhanced_settings: EnhancedSettings | None = None
_runtime_config: RuntimeConfig | None = None


def get_settings() -> EnhancedSettings:
    """Get the global enhanced settings instance."""
    global _enhanced_settings
    if _enhanced_settings is None:
        _enhanced_settings = EnhancedSettings()
    return _enhanced_settings


def get_runtime_config() -> RuntimeConfig:
    """Get the global runtime configuration instance."""
    global _runtime_config
    if _runtime_config is None:
        _runtime_config = RuntimeConfig()
    return _runtime_config


def reload_settings() -> EnhancedSettings:
    """Reload settings from environment and config files."""
    global _enhanced_settings
    _enhanced_settings = EnhancedSettings()
    return _enhanced_settings


def update_runtime_config(**kwargs) -> RuntimeConfig:
    """Update runtime configuration with new values."""
    global _runtime_config
    if _runtime_config is None:
        _runtime_config = RuntimeConfig()

    for key, value in kwargs.items():
        if hasattr(_runtime_config, key):
            setattr(_runtime_config, key, value)

    return _runtime_config
