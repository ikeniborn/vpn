"""
Configuration management using Pydantic Settings.
"""

from pathlib import Path
from typing import Optional, Tuple

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Application settings with environment variable support.
    
    Environment variables are prefixed with VPN_.
    For example: VPN_DEBUG=true, VPN_INSTALL_PATH=/opt/vpn
    """
    
    # Application settings
    app_name: str = "VPN Manager"
    version: str = "2.0.0"
    debug: bool = False
    log_level: str = "INFO"
    
    # Paths
    install_path: Path = Path("/opt/vpn")
    config_path: Path = Path.home() / ".config" / "vpn-manager"
    data_path: Path = Path.home() / ".local" / "share" / "vpn-manager"
    
    # Database
    database_url: str = "sqlite+aiosqlite:///vpn.db"
    database_echo: bool = False
    
    # Docker
    docker_socket: str = "/var/run/docker.sock"
    docker_timeout: int = 30
    docker_max_connections: int = 10
    
    # Server defaults
    default_protocol: str = "vless"
    default_port_range: Tuple[int, int] = (10000, 65000)
    enable_firewall: bool = True
    auto_start_servers: bool = True
    
    # Security
    enable_auth: bool = True
    secret_key: Optional[str] = None
    token_expire_minutes: int = 60 * 24  # 24 hours
    
    # Monitoring
    enable_metrics: bool = True
    metrics_port: int = 9090
    metrics_retention_days: int = 30
    alert_cpu_threshold: float = 90.0
    alert_memory_threshold: float = 90.0
    alert_disk_threshold: float = 85.0
    
    # TUI settings
    tui_theme: str = "dark"
    tui_refresh_rate: int = 1  # seconds
    
    # Development
    reload: bool = False
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="VPN_",
        case_sensitive=False,
        validate_default=True,
    )
    
    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Validate log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        v = v.upper()
        if v not in valid_levels:
            raise ValueError(f"Invalid log level. Must be one of: {', '.join(valid_levels)}")
        return v
    
    @field_validator("install_path", "config_path", "data_path")
    @classmethod
    def create_paths(cls, v: Path) -> Path:
        """Create directories if they don't exist."""
        v = v.expanduser().absolute()
        v.mkdir(parents=True, exist_ok=True)
        return v
    
    @field_validator("default_port_range")
    @classmethod
    def validate_port_range(cls, v: Tuple[int, int]) -> Tuple[int, int]:
        """Validate port range."""
        min_port, max_port = v
        if min_port < 1024:
            raise ValueError("Minimum port must be >= 1024 for non-root operation")
        if max_port > 65535:
            raise ValueError("Maximum port must be <= 65535")
        if min_port >= max_port:
            raise ValueError("Minimum port must be less than maximum port")
        return v
    
    @property
    def database_path(self) -> Path:
        """Get database file path from URL."""
        if self.database_url.startswith("sqlite"):
            # Extract path from sqlite URL
            path_part = self.database_url.split("///")[-1]
            if path_part == ":memory:":
                return Path(":memory:")
            return self.data_path / path_part
        return Path(":memory:")
    
    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.debug or self.reload
    
    def get_server_config_path(self, server_name: str) -> Path:
        """Get path for server configuration file."""
        return self.config_path / "servers" / f"{server_name}.toml"
    
    def get_user_data_path(self, username: str) -> Path:
        """Get path for user data directory."""
        path = self.data_path / "users" / username
        path.mkdir(parents=True, exist_ok=True)
        return path


# Global settings instance
settings = Settings()


class RuntimeConfig(BaseSettings):
    """Runtime configuration that can be modified during execution."""
    
    # Runtime flags
    dry_run: bool = False
    force: bool = False
    quiet: bool = False
    verbose: bool = False
    output_format: str = "table"
    no_color: bool = False
    
    # Operation timeouts
    operation_timeout: int = 300  # 5 minutes
    
    model_config = SettingsConfigDict(
        validate_default=True,
    )
    
    @field_validator("output_format")
    @classmethod
    def validate_output_format(cls, v: str) -> str:
        """Validate output format."""
        valid_formats = ["table", "json", "yaml", "plain"]
        if v not in valid_formats:
            raise ValueError(f"Invalid output format. Must be one of: {', '.join(valid_formats)}")
        return v