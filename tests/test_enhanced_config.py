"""
Tests for enhanced configuration management.
"""

import os
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

from vpn.core.enhanced_config import (
    DatabaseConfig,
    DockerConfig,
    EnhancedSettings,
    LogLevel,
    MonitoringConfig,
    NetworkConfig,
    OutputFormat,
    PathConfig,
    ProtocolType,
    RuntimeConfig,
    SecurityConfig,
    Theme,
    TUIConfig,
    get_runtime_config,
    get_settings,
    reload_settings,
    update_runtime_config,
)


class TestDatabaseConfig:
    """Test database configuration."""

    def test_default_values(self):
        """Test default database configuration values."""
        config = DatabaseConfig()

        assert config.url == "sqlite+aiosqlite:///db/vpn.db"
        assert config.echo is False
        assert config.pool_size == 5
        assert config.max_overflow == 10
        assert config.pool_timeout == 30
        assert config.is_sqlite is True
        assert config.is_memory_db is False

    def test_sqlite_detection(self):
        """Test SQLite database detection."""
        sqlite_config = DatabaseConfig(url="sqlite:///test.db")
        assert sqlite_config.is_sqlite is True

        postgres_config = DatabaseConfig(url="postgresql://user:pass@localhost/db")
        assert postgres_config.is_sqlite is False

    def test_memory_db_detection(self):
        """Test in-memory database detection."""
        memory_config = DatabaseConfig(url="sqlite:///:memory:")
        assert memory_config.is_memory_db is True

        file_config = DatabaseConfig(url="sqlite:///test.db")
        assert file_config.is_memory_db is False

    def test_url_validation(self):
        """Test database URL validation."""
        # Valid URLs
        valid_urls = [
            "sqlite:///test.db",
            "sqlite+aiosqlite:///test.db",
            "postgresql://user:pass@localhost/db",
            "postgresql+asyncpg://user:pass@localhost/db",
        ]

        for url in valid_urls:
            config = DatabaseConfig(url=url)
            assert config.url == url

        # Invalid URLs
        with pytest.raises(ValueError, match="Unsupported database scheme"):
            DatabaseConfig(url="mysql://user:pass@localhost/db")

        with pytest.raises(ValueError, match="Database URL cannot be empty"):
            DatabaseConfig(url="")

    def test_pool_constraints(self):
        """Test database pool size constraints."""
        # Valid pool sizes
        DatabaseConfig(pool_size=1)
        DatabaseConfig(pool_size=50)

        # Invalid pool sizes
        with pytest.raises(ValueError):
            DatabaseConfig(pool_size=0)

        with pytest.raises(ValueError):
            DatabaseConfig(pool_size=51)


class TestDockerConfig:
    """Test Docker configuration."""

    def test_default_values(self):
        """Test default Docker configuration values."""
        config = DockerConfig()

        assert config.socket == "/var/run/docker.sock"
        assert config.timeout == 30
        assert config.max_connections == 10
        assert config.registry_url is None
        assert config.registry_username is None
        assert config.registry_password is None

    def test_socket_validation(self):
        """Test Docker socket path validation."""
        # Valid socket paths
        valid_sockets = [
            "/var/run/docker.sock",
            "unix:///var/run/docker.sock",
            "/tmp/docker.sock",
        ]

        for socket in valid_sockets:
            config = DockerConfig(socket=socket)
            assert config.socket == socket

        # Invalid socket paths
        with pytest.raises(ValueError, match="Docker socket must be an absolute path"):
            DockerConfig(socket="docker.sock")

    def test_password_serialization(self):
        """Test password masking in serialization."""
        config = DockerConfig(registry_password="secret123")

        # Password should be masked in serialization
        serialized = config.model_dump()
        assert serialized["registry_password"] == "***"

        # No password should serialize as None
        config_no_pass = DockerConfig()
        serialized_no_pass = config_no_pass.model_dump()
        assert serialized_no_pass["registry_password"] is None

    def test_timeout_constraints(self):
        """Test timeout constraints."""
        # Valid timeouts
        DockerConfig(timeout=5)
        DockerConfig(timeout=300)

        # Invalid timeouts
        with pytest.raises(ValueError):
            DockerConfig(timeout=4)

        with pytest.raises(ValueError):
            DockerConfig(timeout=301)


class TestNetworkConfig:
    """Test network configuration."""

    def test_default_values(self):
        """Test default network configuration values."""
        config = NetworkConfig()

        assert config.default_port_range == (10000, 65000)
        assert config.enable_firewall is True
        assert config.firewall_backup is True
        assert config.allowed_networks == ["0.0.0.0/0"]
        assert config.blocked_ports == set()
        assert len(config.health_check_endpoints) == 2
        assert config.port_range_size == 55001

    def test_port_range_validation(self):
        """Test port range validation."""
        # Valid port ranges
        NetworkConfig(default_port_range=(1024, 65535))
        NetworkConfig(default_port_range=(8000, 9000))

        # Invalid port ranges
        with pytest.raises(ValueError, match="Minimum port must be >= 1024"):
            NetworkConfig(default_port_range=(80, 8080))

        with pytest.raises(ValueError, match="Maximum port must be <= 65535"):
            NetworkConfig(default_port_range=(8000, 70000))

        with pytest.raises(ValueError, match="Minimum port must be less than maximum"):
            NetworkConfig(default_port_range=(8080, 8000))

    def test_network_validation(self):
        """Test network CIDR validation."""
        # Valid networks
        valid_networks = [
            "192.168.1.0/24",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "0.0.0.0/0",
        ]

        config = NetworkConfig(allowed_networks=valid_networks)
        assert config.allowed_networks == valid_networks

        # Invalid networks
        with pytest.raises(ValueError, match="Invalid network CIDR"):
            NetworkConfig(allowed_networks=["192.168.1.0/33"])

        with pytest.raises(ValueError, match="Invalid network CIDR"):
            NetworkConfig(allowed_networks=["invalid-network"])

    def test_port_range_size_computation(self):
        """Test port range size computation."""
        config = NetworkConfig(default_port_range=(8000, 8010))
        assert config.port_range_size == 11


class TestSecurityConfig:
    """Test security configuration."""

    def test_default_values(self):
        """Test default security configuration values."""
        config = SecurityConfig()

        assert config.enable_auth is True
        assert config.secret_key is not None  # Auto-generated
        assert len(config.secret_key) >= 32
        assert config.token_expire_minutes == 60 * 24
        assert config.max_login_attempts == 5
        assert config.lockout_duration == 15
        assert config.password_min_length == 8
        assert config.require_password_complexity is True

    def test_secret_key_generation(self):
        """Test automatic secret key generation."""
        config = SecurityConfig(enable_auth=True, secret_key=None)
        assert config.secret_key is not None
        assert len(config.secret_key) >= 32

    def test_secret_key_serialization(self):
        """Test secret key masking in serialization."""
        config = SecurityConfig(secret_key="very-secret-key-123456789")

        serialized = config.model_dump()
        assert serialized["secret_key"] == "very-sec..."

    def test_token_expire_timedelta(self):
        """Test token expiration timedelta computation."""
        config = SecurityConfig(token_expire_minutes=60)
        assert config.token_expire_timedelta == timedelta(minutes=60)

    def test_constraints(self):
        """Test field constraints."""
        # Valid values
        SecurityConfig(token_expire_minutes=5)
        SecurityConfig(token_expire_minutes=60 * 24 * 30)
        SecurityConfig(password_min_length=4)
        SecurityConfig(password_min_length=128)

        # Invalid values
        with pytest.raises(ValueError):
            SecurityConfig(token_expire_minutes=4)

        with pytest.raises(ValueError):
            SecurityConfig(token_expire_minutes=60 * 24 * 31)


class TestTUIConfig:
    """Test TUI configuration."""

    def test_default_values(self):
        """Test default TUI configuration values."""
        config = TUIConfig()

        assert config.theme == Theme.DARK
        assert config.refresh_rate == 1
        assert config.show_stats is True
        assert config.show_help is True
        assert config.enable_mouse is True
        assert config.page_size == 20
        assert config.animation_duration == 0.3
        assert isinstance(config.keyboard_shortcuts, dict)
        assert "quit" in config.keyboard_shortcuts

    def test_constraints(self):
        """Test TUI configuration constraints."""
        # Valid values
        TUIConfig(refresh_rate=1)
        TUIConfig(refresh_rate=10)
        TUIConfig(page_size=5)
        TUIConfig(page_size=100)
        TUIConfig(animation_duration=0.0)
        TUIConfig(animation_duration=2.0)

        # Invalid values
        with pytest.raises(ValueError):
            TUIConfig(refresh_rate=0)

        with pytest.raises(ValueError):
            TUIConfig(refresh_rate=11)


class TestPathConfig:
    """Test path configuration."""

    def test_default_values(self):
        """Test default path configuration values."""
        config = PathConfig()

        assert config.install_path == Path("/opt/vpn")
        assert config.config_path == Path.home() / ".config" / "vpn-manager"
        assert config.data_path == Path.home() / ".local" / "share" / "vpn-manager"
        assert config.log_path == Path.home() / ".local" / "share" / "vpn-manager" / "logs"
        assert config.template_path.name == "templates"

    def test_path_creation(self):
        """Test automatic path creation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            test_path = Path(temp_dir) / "test_config"
            config = PathConfig(config_path=test_path)

            # Path should be created automatically
            assert config.config_path.exists()
            assert config.config_path.is_dir()

    def test_permission_fallback(self):
        """Test fallback when path creation fails due to permissions."""
        # Try to create path in /opt (likely to fail without root)
        with patch("pathlib.Path.mkdir", side_effect=PermissionError):
            config = PathConfig(install_path=Path("/opt/test-vpn"))

            # Should fall back to user directory
            assert str(config.install_path).startswith(str(Path.home()))

    def test_backup_path_computation(self):
        """Test backup path computation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config = PathConfig(data_path=Path(temp_dir))
            backup_path = config.backup_path

            assert backup_path == config.data_path / "backups"
            assert backup_path.exists()

    def test_server_config_path(self):
        """Test server configuration path generation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config = PathConfig(config_path=Path(temp_dir))
            server_path = config.get_server_config_path("test-server")

            expected_path = Path(temp_dir) / "servers" / "test-server.toml"
            assert server_path == expected_path
            assert server_path.parent.exists()

    def test_user_data_path(self):
        """Test user data path generation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config = PathConfig(data_path=Path(temp_dir))
            user_path = config.get_user_data_path("testuser")

            expected_path = Path(temp_dir) / "users" / "testuser"
            assert user_path == expected_path
            assert user_path.exists()


class TestEnhancedSettings:
    """Test enhanced settings."""

    def test_default_values(self):
        """Test default enhanced settings values."""
        settings = EnhancedSettings()

        assert settings.app_name == "VPN Manager"
        assert settings.version == "2.0.0"
        assert settings.debug is False
        assert settings.log_level == LogLevel.INFO
        assert settings.default_protocol == ProtocolType.VLESS
        assert settings.auto_start_servers is True
        assert settings.reload is False
        assert settings.profile is False

        # Test nested configurations
        assert isinstance(settings.paths, PathConfig)
        assert isinstance(settings.database, DatabaseConfig)
        assert isinstance(settings.docker, DockerConfig)
        assert isinstance(settings.network, NetworkConfig)
        assert isinstance(settings.security, SecurityConfig)
        assert isinstance(settings.monitoring, MonitoringConfig)
        assert isinstance(settings.tui, TUIConfig)

    def test_development_mode_detection(self):
        """Test development mode detection."""
        # Non-development mode
        settings = EnhancedSettings(debug=False, reload=False, profile=False)
        assert settings.is_development is False

        # Development modes
        debug_settings = EnhancedSettings(debug=True)
        assert debug_settings.is_development is True

        reload_settings = EnhancedSettings(reload=True)
        assert reload_settings.is_development is True

        profile_settings = EnhancedSettings(profile=True)
        assert profile_settings.is_development is True

    def test_config_file_paths(self):
        """Test configuration file paths generation."""
        settings = EnhancedSettings()
        paths = settings.config_file_paths

        assert len(paths) >= 6
        assert any(path.name == "config.yaml" for path in paths)
        assert any(path.name == "config.toml" for path in paths)

    def test_log_level_serialization(self):
        """Test log level enum serialization."""
        settings = EnhancedSettings(log_level=LogLevel.DEBUG)
        serialized = settings.model_dump()

        assert serialized["log_level"] == "DEBUG"

    def test_environment_variable_support(self):
        """Test environment variable configuration."""
        with patch.dict(os.environ, {
            "VPN_DEBUG": "true",
            "VPN_LOG_LEVEL": "DEBUG",
            "VPN_APP_NAME": "Test VPN",
            "VPN_DATABASE__ECHO": "true",
            "VPN_DOCKER__TIMEOUT": "60",
        }):
            settings = EnhancedSettings()

            assert settings.debug is True
            assert settings.log_level == LogLevel.DEBUG
            assert settings.app_name == "Test VPN"
            assert settings.database.echo is True
            assert settings.docker.timeout == 60


class TestRuntimeConfig:
    """Test runtime configuration."""

    def test_default_values(self):
        """Test default runtime configuration values."""
        config = RuntimeConfig()

        assert config.dry_run is False
        assert config.force is False
        assert config.quiet is False
        assert config.verbose is False
        assert config.output_format == OutputFormat.TABLE
        assert config.no_color is False
        assert config.operation_timeout == 300
        assert config.batch_size == 50
        assert config.retry_attempts == 3
        assert config.session_id is None
        assert config.user_id is None
        assert isinstance(config.start_time, datetime)

    def test_session_duration(self):
        """Test session duration computation."""
        start_time = datetime.utcnow() - timedelta(minutes=5)
        config = RuntimeConfig(start_time=start_time)

        duration = config.session_duration
        assert duration.total_seconds() >= 300  # 5 minutes

    def test_effective_log_level(self):
        """Test effective log level computation."""
        # Default
        config = RuntimeConfig()
        assert config.effective_log_level == LogLevel.INFO

        # Verbose mode
        verbose_config = RuntimeConfig(verbose=True)
        assert verbose_config.effective_log_level == LogLevel.DEBUG

        # Quiet mode
        quiet_config = RuntimeConfig(quiet=True)
        assert quiet_config.effective_log_level == LogLevel.ERROR

        # Verbose takes precedence over quiet
        mixed_config = RuntimeConfig(verbose=True, quiet=True)
        assert mixed_config.effective_log_level == LogLevel.DEBUG

    def test_constraints(self):
        """Test runtime configuration constraints."""
        # Valid values
        RuntimeConfig(operation_timeout=10)
        RuntimeConfig(operation_timeout=3600)
        RuntimeConfig(batch_size=1)
        RuntimeConfig(batch_size=1000)
        RuntimeConfig(retry_attempts=1)
        RuntimeConfig(retry_attempts=10)

        # Invalid values
        with pytest.raises(ValueError):
            RuntimeConfig(operation_timeout=9)

        with pytest.raises(ValueError):
            RuntimeConfig(operation_timeout=3601)


class TestGlobalConfiguration:
    """Test global configuration functions."""

    def test_get_settings(self):
        """Test get_settings function."""
        settings1 = get_settings()
        settings2 = get_settings()

        # Should return same instance
        assert settings1 is settings2
        assert isinstance(settings1, EnhancedSettings)

    def test_get_runtime_config(self):
        """Test get_runtime_config function."""
        config1 = get_runtime_config()
        config2 = get_runtime_config()

        # Should return same instance
        assert config1 is config2
        assert isinstance(config1, RuntimeConfig)

    def test_reload_settings(self):
        """Test reload_settings function."""
        original_settings = get_settings()
        reloaded_settings = reload_settings()

        # Should be different instances
        assert original_settings is not reloaded_settings
        assert isinstance(reloaded_settings, EnhancedSettings)

    def test_update_runtime_config(self):
        """Test update_runtime_config function."""
        original_config = get_runtime_config()
        original_verbose = original_config.verbose

        updated_config = update_runtime_config(verbose=True, dry_run=True)

        # Should be same instance with updated values
        assert updated_config is original_config
        assert updated_config.verbose is True
        assert updated_config.dry_run is True

    def test_update_runtime_config_invalid_field(self):
        """Test update_runtime_config with invalid field."""
        update_runtime_config(invalid_field="value")

        # Should not raise error, just ignore invalid fields
        config = get_runtime_config()
        assert not hasattr(config, "invalid_field")


class TestConfigurationIntegration:
    """Test configuration integration scenarios."""

    def test_sqlite_path_resolution(self):
        """Test SQLite database path resolution."""
        with tempfile.TemporaryDirectory() as temp_dir:
            settings = EnhancedSettings()
            settings.paths.data_path = Path(temp_dir)
            settings.database.url = "sqlite+aiosqlite:///test.db"

            # Trigger post-validation
            settings = EnhancedSettings.model_validate(settings.model_dump())

            # Database URL should now contain absolute path
            assert str(temp_dir) in settings.database.url

    def test_memory_database_unchanged(self):
        """Test that in-memory database URL remains unchanged."""
        settings = EnhancedSettings()
        settings.database.url = "sqlite:///:memory:"

        # Trigger post-validation
        settings = EnhancedSettings.model_validate(settings.model_dump())

        # URL should remain unchanged
        assert settings.database.url == "sqlite:///:memory:"

    def test_log_path_creation(self):
        """Test log path creation during validation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            settings = EnhancedSettings()
            settings.paths.log_path = Path(temp_dir) / "logs"

            # Trigger post-validation
            settings = EnhancedSettings.model_validate(settings.model_dump())

            # Log path should be created
            assert settings.paths.log_path.exists()

    def test_nested_environment_variables(self):
        """Test nested environment variable configuration."""
        with patch.dict(os.environ, {
            "VPN_NETWORK__DEFAULT_PORT_RANGE": "8000,9000",
            "VPN_SECURITY__TOKEN_EXPIRE_MINUTES": "120",
            "VPN_TUI__THEME": "light",
            "VPN_MONITORING__ENABLE_METRICS": "false",
        }):
            settings = EnhancedSettings()

            assert settings.network.default_port_range == (8000, 9000)
            assert settings.security.token_expire_minutes == 120
            assert settings.tui.theme == Theme.LIGHT
            assert settings.monitoring.enable_metrics is False
