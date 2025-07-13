"""
Integration tests for CLI commands.
"""

import json
import os
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from click.testing import CliRunner

from vpn.cli.main import cli
from vpn.core.exceptions import UserAlreadyExistsError, UserNotFoundError
from vpn.core.models import ProtocolConfig, ProtocolType, User, UserStatus


@pytest.fixture
def cli_runner():
    """Create CLI runner for testing."""
    return CliRunner()


@pytest.fixture
def temp_config_dir():
    """Create temporary config directory."""
    with tempfile.TemporaryDirectory() as temp_dir:
        config_path = Path(temp_dir) / "config"
        config_path.mkdir()
        yield config_path


@pytest.fixture
def mock_user_manager():
    """Create mock user manager."""
    manager = AsyncMock()
    manager.create = AsyncMock()
    manager.get = AsyncMock()
    manager.list = AsyncMock()
    manager.delete = AsyncMock()
    manager.update_status = AsyncMock()
    return manager


@pytest.fixture
def mock_server_manager():
    """Create mock server manager."""
    manager = AsyncMock()
    manager.install = AsyncMock()
    manager.start = AsyncMock()
    manager.stop = AsyncMock()
    manager.list_servers = AsyncMock()
    manager.uninstall = AsyncMock()
    return manager


@pytest.fixture
def mock_proxy_manager():
    """Create mock proxy manager."""
    manager = AsyncMock()
    manager.start_http_proxy = AsyncMock()
    manager.start_socks5_proxy = AsyncMock()
    manager.stop_proxy = AsyncMock()
    manager.list_servers = AsyncMock()
    manager.get_server_stats = AsyncMock()
    return manager


@pytest.fixture
def sample_user():
    """Create sample user for testing."""
    protocol = ProtocolConfig(type=ProtocolType.VLESS)
    return User(
        username="testuser",
        email="test@example.com",
        protocol=protocol,
        status=UserStatus.ACTIVE
    )


class TestUserCommands:
    """Test user management CLI commands."""

    def test_user_list_empty(self, cli_runner, mock_user_manager):
        """Test listing users when no users exist."""
        mock_user_manager.list.return_value = []

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list'])

            assert result.exit_code == 0
            assert "No users found" in result.output
            mock_user_manager.list.assert_called_once()

    def test_user_list_with_users(self, cli_runner, mock_user_manager, sample_user):
        """Test listing users with existing users."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list'])

            assert result.exit_code == 0
            assert "testuser" in result.output
            assert sample_user.email in result.output
            mock_user_manager.list.assert_called_once()

    def test_user_list_json_format(self, cli_runner, mock_user_manager, sample_user):
        """Test listing users in JSON format."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list', '--format', 'json'])

            assert result.exit_code == 0
            # Should be valid JSON
            json_output = json.loads(result.output)
            assert isinstance(json_output, list)
            assert len(json_output) == 1
            assert json_output[0]["username"] == "testuser"

    def test_user_create_success(self, cli_runner, mock_user_manager, sample_user):
        """Test creating a new user successfully."""
        mock_user_manager.create.return_value = sample_user

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'create', 'testuser',
                '--protocol', 'vless',
                '--email', 'test@example.com'
            ])

            assert result.exit_code == 0
            assert "User 'testuser' created successfully" in result.output
            mock_user_manager.create.assert_called_once_with(
                username="testuser",
                protocol=ProtocolType.VLESS,
                email="test@example.com"
            )

    def test_user_create_already_exists(self, cli_runner, mock_user_manager):
        """Test creating a user that already exists."""
        mock_user_manager.create.side_effect = UserAlreadyExistsError("User already exists")

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'create', 'testuser',
                '--protocol', 'vless'
            ])

            assert result.exit_code == 1
            assert "User already exists" in result.output

    def test_user_create_invalid_protocol(self, cli_runner, mock_user_manager):
        """Test creating a user with invalid protocol."""
        result = cli_runner.invoke(cli, [
            'users', 'create', 'testuser',
            '--protocol', 'invalid'
        ])

        assert result.exit_code == 2  # Click validation error
        assert "Invalid value" in result.output

    def test_user_delete_success(self, cli_runner, mock_user_manager):
        """Test deleting a user successfully."""
        mock_user_manager.delete.return_value = True

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'delete', 'testuser'
            ], input='y\n')

            assert result.exit_code == 0
            assert "User 'testuser' deleted successfully" in result.output
            mock_user_manager.delete.assert_called_once()

    def test_user_delete_not_found(self, cli_runner, mock_user_manager):
        """Test deleting a non-existent user."""
        mock_user_manager.delete.side_effect = UserNotFoundError("User not found")

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'delete', 'nonexistent'
            ], input='y\n')

            assert result.exit_code == 1
            assert "User not found" in result.output

    def test_user_delete_cancelled(self, cli_runner, mock_user_manager):
        """Test cancelling user deletion."""
        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'delete', 'testuser'
            ], input='n\n')

            assert result.exit_code == 0
            assert "Deletion cancelled" in result.output
            mock_user_manager.delete.assert_not_called()

    def test_user_delete_force(self, cli_runner, mock_user_manager):
        """Test force deleting a user."""
        mock_user_manager.delete.return_value = True

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'delete', 'testuser', '--force'
            ])

            assert result.exit_code == 0
            assert "User 'testuser' deleted successfully" in result.output
            mock_user_manager.delete.assert_called_once()

    def test_user_show_success(self, cli_runner, mock_user_manager, sample_user):
        """Test showing user details."""
        mock_user_manager.get.return_value = sample_user

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'show', 'testuser'])

            assert result.exit_code == 0
            assert "testuser" in result.output
            assert sample_user.email in result.output
            mock_user_manager.get.assert_called_once()

    def test_user_show_not_found(self, cli_runner, mock_user_manager):
        """Test showing non-existent user."""
        mock_user_manager.get.return_value = None

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'show', 'nonexistent'])

            assert result.exit_code == 1
            assert "User 'nonexistent' not found" in result.output

    def test_user_status_update(self, cli_runner, mock_user_manager, sample_user):
        """Test updating user status."""
        sample_user.status = UserStatus.SUSPENDED
        mock_user_manager.update_status.return_value = sample_user

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'status', 'testuser', '--status', 'suspended'
            ])

            assert result.exit_code == 0
            assert "User status updated" in result.output
            mock_user_manager.update_status.assert_called_once_with(
                "testuser", UserStatus.SUSPENDED
            )


class TestServerCommands:
    """Test server management CLI commands."""

    def test_server_install_success(self, cli_runner, mock_server_manager):
        """Test installing a server successfully."""
        mock_server_config = MagicMock()
        mock_server_config.name = "test-server"
        mock_server_config.protocol.type = ProtocolType.VLESS
        mock_server_config.port = 8443
        mock_server_manager.install.return_value = mock_server_config

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, [
                'server', 'install',
                '--protocol', 'vless',
                '--port', '8443',
                '--name', 'test-server'
            ])

            assert result.exit_code == 0
            assert "Server 'test-server' installed successfully" in result.output
            mock_server_manager.install.assert_called_once()

    def test_server_install_default_name(self, cli_runner, mock_server_manager):
        """Test installing a server with default name."""
        mock_server_config = MagicMock()
        mock_server_config.name = "vless-server"
        mock_server_manager.install.return_value = mock_server_config

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, [
                'server', 'install',
                '--protocol', 'vless',
                '--port', '8443'
            ])

            assert result.exit_code == 0
            mock_server_manager.install.assert_called_once()

    def test_server_install_invalid_port(self, cli_runner, mock_server_manager):
        """Test installing a server with invalid port."""
        result = cli_runner.invoke(cli, [
            'server', 'install',
            '--protocol', 'vless',
            '--port', '80'  # Well-known port
        ])

        assert result.exit_code == 2  # Click validation error
        assert "Invalid value" in result.output

    def test_server_list_empty(self, cli_runner, mock_server_manager):
        """Test listing servers when none exist."""
        mock_server_manager.list_servers.return_value = []

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, ['server', 'list'])

            assert result.exit_code == 0
            assert "No servers found" in result.output

    def test_server_list_with_servers(self, cli_runner, mock_server_manager):
        """Test listing servers with existing servers."""
        mock_server = MagicMock()
        mock_server.name = "test-server"
        mock_server.protocol.type = ProtocolType.VLESS
        mock_server.port = 8443
        mock_server.status = "running"
        mock_server_manager.list_servers.return_value = [mock_server]

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, ['server', 'list'])

            assert result.exit_code == 0
            assert "test-server" in result.output
            assert "8443" in result.output
            assert "running" in result.output

    def test_server_start_success(self, cli_runner, mock_server_manager):
        """Test starting a server successfully."""
        mock_server_manager.start.return_value = None

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, ['server', 'start', 'test-server'])

            assert result.exit_code == 0
            assert "Server 'test-server' started successfully" in result.output
            mock_server_manager.start.assert_called_once_with("test-server")

    def test_server_stop_success(self, cli_runner, mock_server_manager):
        """Test stopping a server successfully."""
        mock_server_manager.stop.return_value = None

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, ['server', 'stop', 'test-server'])

            assert result.exit_code == 0
            assert "Server 'test-server' stopped successfully" in result.output
            mock_server_manager.stop.assert_called_once_with("test-server")

    def test_server_remove_success(self, cli_runner, mock_server_manager):
        """Test removing a server successfully."""
        mock_server_manager.uninstall.return_value = None

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, [
                'server', 'remove', 'test-server'
            ], input='y\n')

            assert result.exit_code == 0
            assert "Server 'test-server' removed successfully" in result.output
            mock_server_manager.uninstall.assert_called_once_with("test-server")

    def test_server_remove_cancelled(self, cli_runner, mock_server_manager):
        """Test cancelling server removal."""
        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, [
                'server', 'remove', 'test-server'
            ], input='n\n')

            assert result.exit_code == 0
            assert "Removal cancelled" in result.output
            mock_server_manager.uninstall.assert_not_called()

    def test_server_remove_force(self, cli_runner, mock_server_manager):
        """Test force removing a server."""
        mock_server_manager.uninstall.return_value = None

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, [
                'server', 'remove', 'test-server', '--force'
            ])

            assert result.exit_code == 0
            assert "Server 'test-server' removed successfully" in result.output
            mock_server_manager.uninstall.assert_called_once_with("test-server")

    def test_server_logs_command(self, cli_runner, mock_server_manager):
        """Test server logs command."""
        mock_server_manager.get_logs.return_value = ["Log line 1", "Log line 2"]

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, ['server', 'logs', 'test-server'])

            assert result.exit_code == 0
            assert "Log line 1" in result.output
            assert "Log line 2" in result.output

    def test_server_restart_success(self, cli_runner, mock_server_manager):
        """Test restarting a server successfully."""
        mock_server_manager.restart.return_value = None

        with patch('vpn.cli.commands.server.ServerManager', return_value=mock_server_manager):
            result = cli_runner.invoke(cli, ['server', 'restart', 'test-server'])

            assert result.exit_code == 0
            assert "Server 'test-server' restarted successfully" in result.output
            mock_server_manager.restart.assert_called_once_with("test-server")


class TestProxyCommands:
    """Test proxy management CLI commands."""

    def test_proxy_start_http_success(self, cli_runner, mock_proxy_manager):
        """Test starting HTTP proxy successfully."""
        mock_proxy_manager.start_http_proxy.return_value = None

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, [
                'proxy', 'start',
                '--type', 'http',
                '--port', '8888'
            ])

            assert result.exit_code == 0
            assert "HTTP proxy started" in result.output
            mock_proxy_manager.start_http_proxy.assert_called_once()

    def test_proxy_start_socks5_success(self, cli_runner, mock_proxy_manager):
        """Test starting SOCKS5 proxy successfully."""
        mock_proxy_manager.start_socks5_proxy.return_value = None

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, [
                'proxy', 'start',
                '--type', 'socks5',
                '--port', '1080'
            ])

            assert result.exit_code == 0
            assert "SOCKS5 proxy started" in result.output
            mock_proxy_manager.start_socks5_proxy.assert_called_once()

    def test_proxy_start_with_auth(self, cli_runner, mock_proxy_manager):
        """Test starting proxy with authentication."""
        mock_proxy_manager.start_http_proxy.return_value = None

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, [
                'proxy', 'start',
                '--type', 'http',
                '--port', '8888',
                '--auth'
            ])

            assert result.exit_code == 0
            mock_proxy_manager.start_http_proxy.assert_called_once()
            # Check that require_auth was set to True
            call_args = mock_proxy_manager.start_http_proxy.call_args
            assert call_args[1]['require_auth'] is True

    def test_proxy_start_no_auth(self, cli_runner, mock_proxy_manager):
        """Test starting proxy without authentication."""
        mock_proxy_manager.start_socks5_proxy.return_value = None

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, [
                'proxy', 'start',
                '--type', 'socks5',
                '--port', '1080',
                '--no-auth'
            ])

            assert result.exit_code == 0
            mock_proxy_manager.start_socks5_proxy.assert_called_once()
            # Check that require_auth was set to False
            call_args = mock_proxy_manager.start_socks5_proxy.call_args
            assert call_args[1]['require_auth'] is False

    def test_proxy_list_empty(self, cli_runner, mock_proxy_manager):
        """Test listing proxies when none exist."""
        mock_proxy_manager.list_servers.return_value = {}

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, ['proxy', 'list'])

            assert result.exit_code == 0
            assert "No proxy servers running" in result.output

    def test_proxy_list_with_servers(self, cli_runner, mock_proxy_manager):
        """Test listing proxies with existing servers."""
        mock_server = MagicMock()
        mock_server.host = "127.0.0.1"
        mock_server.port = 8888
        mock_server.require_auth = True
        mock_server.stats = MagicMock()
        mock_server.stats.requests_count = 100

        mock_proxy_manager.list_servers.return_value = {
            "http-proxy-8888": mock_server
        }

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, ['proxy', 'list'])

            assert result.exit_code == 0
            assert "http-proxy-8888" in result.output
            assert "8888" in result.output
            assert "127.0.0.1" in result.output

    def test_proxy_stop_success(self, cli_runner, mock_proxy_manager):
        """Test stopping proxy successfully."""
        mock_proxy_manager.stop_proxy.return_value = None

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, ['proxy', 'stop', 'http-proxy-8888'])

            assert result.exit_code == 0
            assert "Proxy 'http-proxy-8888' stopped successfully" in result.output
            mock_proxy_manager.stop_proxy.assert_called_once_with("http-proxy-8888")

    def test_proxy_status_command(self, cli_runner, mock_proxy_manager):
        """Test proxy status command."""
        mock_stats = MagicMock()
        mock_stats.requests_count = 100
        mock_stats.bytes_transferred = 1024
        mock_stats.auth_failures = 5
        mock_proxy_manager.get_server_stats.return_value = mock_stats

        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            result = cli_runner.invoke(cli, ['proxy', 'status', 'http-proxy-8888'])

            assert result.exit_code == 0
            assert "100" in result.output  # requests_count
            assert "1024" in result.output  # bytes_transferred

    def test_proxy_test_command(self, cli_runner, mock_proxy_manager):
        """Test proxy test command."""
        with patch('vpn.cli.commands.proxy.ProxyServerManager', return_value=mock_proxy_manager):
            with patch('httpx.get') as mock_get:
                mock_response = MagicMock()
                mock_response.status_code = 200
                mock_response.json.return_value = {"origin": "1.2.3.4"}
                mock_get.return_value = mock_response

                result = cli_runner.invoke(cli, [
                    'proxy', 'test',
                    '--type', 'http',
                    '--port', '8888',
                    '--url', 'http://httpbin.org/ip'
                ])

                assert result.exit_code == 0
                assert "Proxy test successful" in result.output


class TestConfigCommands:
    """Test configuration CLI commands."""

    def test_config_show_command(self, cli_runner, temp_config_dir):
        """Test config show command."""
        # Create a test config file
        config_file = temp_config_dir / "config.toml"
        config_file.write_text("""
[database]
url = "sqlite:///test.db"

[server]
host = "127.0.0.1"
port = 8443
""")

        with patch('vpn.cli.commands.config.get_config_path', return_value=config_file):
            result = cli_runner.invoke(cli, ['config', 'show'])

            assert result.exit_code == 0
            assert "database" in result.output
            assert "sqlite:///test.db" in result.output

    def test_config_set_command(self, cli_runner, temp_config_dir):
        """Test config set command."""
        config_file = temp_config_dir / "config.toml"
        config_file.write_text("""
[database]
url = "sqlite:///test.db"
""")

        with patch('vpn.cli.commands.config.get_config_path', return_value=config_file):
            result = cli_runner.invoke(cli, [
                'config', 'set',
                'database.url',
                'sqlite:///new.db'
            ])

            assert result.exit_code == 0
            assert "Configuration updated" in result.output

    def test_config_get_command(self, cli_runner, temp_config_dir):
        """Test config get command."""
        config_file = temp_config_dir / "config.toml"
        config_file.write_text("""
[database]
url = "sqlite:///test.db"
""")

        with patch('vpn.cli.commands.config.get_config_path', return_value=config_file):
            result = cli_runner.invoke(cli, [
                'config', 'get',
                'database.url'
            ])

            assert result.exit_code == 0
            assert "sqlite:///test.db" in result.output

    def test_config_reset_command(self, cli_runner, temp_config_dir):
        """Test config reset command."""
        config_file = temp_config_dir / "config.toml"
        config_file.write_text("test_config = 'value'")

        with patch('vpn.cli.commands.config.get_config_path', return_value=config_file):
            result = cli_runner.invoke(cli, [
                'config', 'reset'
            ], input='y\n')

            assert result.exit_code == 0
            assert "Configuration reset" in result.output


class TestMonitorCommands:
    """Test monitoring CLI commands."""

    def test_monitor_stats_command(self, cli_runner):
        """Test monitor stats command."""
        with patch('vpn.cli.commands.monitor.get_system_stats') as mock_stats:
            mock_stats.return_value = {
                "cpu_usage": 25.5,
                "memory_usage": 60.2,
                "disk_usage": 45.8,
                "network_stats": {
                    "bytes_sent": 1024,
                    "bytes_recv": 2048
                }
            }

            result = cli_runner.invoke(cli, ['monitor', 'stats'])

            assert result.exit_code == 0
            assert "25.5" in result.output  # CPU usage
            assert "60.2" in result.output  # Memory usage

    def test_monitor_traffic_command(self, cli_runner):
        """Test monitor traffic command."""
        with patch('vpn.cli.commands.monitor.get_traffic_stats') as mock_traffic:
            mock_traffic.return_value = {
                "total_users": 10,
                "active_connections": 5,
                "total_bytes": 1024 * 1024,
                "upload_bytes": 512 * 1024,
                "download_bytes": 512 * 1024
            }

            result = cli_runner.invoke(cli, ['monitor', 'traffic'])

            assert result.exit_code == 0
            assert "10" in result.output  # total_users
            assert "5" in result.output   # active_connections

    def test_monitor_logs_command(self, cli_runner):
        """Test monitor logs command."""
        with patch('vpn.cli.commands.monitor.get_recent_logs') as mock_logs:
            mock_logs.return_value = [
                "2024-01-01 10:00:00 INFO: Server started",
                "2024-01-01 10:01:00 INFO: User connected",
                "2024-01-01 10:02:00 WARN: High CPU usage"
            ]

            result = cli_runner.invoke(cli, ['monitor', 'logs'])

            assert result.exit_code == 0
            assert "Server started" in result.output
            assert "User connected" in result.output
            assert "High CPU usage" in result.output


class TestCLIErrorHandling:
    """Test CLI error handling scenarios."""

    def test_invalid_command(self, cli_runner):
        """Test invalid command handling."""
        result = cli_runner.invoke(cli, ['invalid-command'])

        assert result.exit_code == 2
        assert "No such command" in result.output

    def test_missing_required_argument(self, cli_runner):
        """Test missing required argument."""
        result = cli_runner.invoke(cli, ['users', 'create'])

        assert result.exit_code == 2
        assert "Missing argument" in result.output

    def test_invalid_option_value(self, cli_runner):
        """Test invalid option value."""
        result = cli_runner.invoke(cli, [
            'users', 'list',
            '--format', 'invalid'
        ])

        assert result.exit_code == 2
        assert "Invalid value" in result.output

    def test_service_unavailable_error(self, cli_runner):
        """Test service unavailable error handling."""
        mock_manager = AsyncMock()
        mock_manager.list.side_effect = Exception("Service unavailable")

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_manager):
            result = cli_runner.invoke(cli, ['users', 'list'])

            assert result.exit_code == 1
            assert "Service unavailable" in result.output

    def test_permission_error(self, cli_runner):
        """Test permission error handling."""
        mock_manager = AsyncMock()
        mock_manager.create.side_effect = PermissionError("Permission denied")

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_manager):
            result = cli_runner.invoke(cli, [
                'users', 'create', 'testuser',
                '--protocol', 'vless'
            ])

            assert result.exit_code == 1
            assert "Permission denied" in result.output


class TestCLIFormatting:
    """Test CLI output formatting."""

    def test_table_format(self, cli_runner, mock_user_manager, sample_user):
        """Test table format output."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list', '--format', 'table'])

            assert result.exit_code == 0
            assert "Username" in result.output
            assert "Status" in result.output
            assert "testuser" in result.output

    def test_json_format(self, cli_runner, mock_user_manager, sample_user):
        """Test JSON format output."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list', '--format', 'json'])

            assert result.exit_code == 0
            json_output = json.loads(result.output)
            assert isinstance(json_output, list)
            assert len(json_output) == 1

    def test_yaml_format(self, cli_runner, mock_user_manager, sample_user):
        """Test YAML format output."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list', '--format', 'yaml'])

            assert result.exit_code == 0
            assert "username: testuser" in result.output

    def test_plain_format(self, cli_runner, mock_user_manager, sample_user):
        """Test plain format output."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['users', 'list', '--format', 'plain'])

            assert result.exit_code == 0
            assert "testuser" in result.output

    def test_verbose_output(self, cli_runner, mock_user_manager, sample_user):
        """Test verbose output."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['--verbose', 'users', 'list'])

            assert result.exit_code == 0
            # Should contain debug information
            assert "DEBUG" in result.output or "INFO" in result.output

    def test_quiet_output(self, cli_runner, mock_user_manager, sample_user):
        """Test quiet output."""
        mock_user_manager.list.return_value = [sample_user]

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, ['--quiet', 'users', 'list'])

            assert result.exit_code == 0
            # Should contain minimal output
            assert len(result.output.strip()) < 100


class TestCLIAsync:
    """Test CLI async functionality."""

    def test_async_command_execution(self, cli_runner, mock_user_manager, sample_user):
        """Test that async commands are properly executed."""
        mock_user_manager.create.return_value = sample_user

        # Mock async function
        async def mock_async_create(*args, **kwargs):
            return sample_user

        mock_user_manager.create = mock_async_create

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'create', 'testuser',
                '--protocol', 'vless'
            ])

            assert result.exit_code == 0
            assert "User 'testuser' created successfully" in result.output

    def test_async_error_handling(self, cli_runner, mock_user_manager):
        """Test async error handling."""
        async def mock_async_error(*args, **kwargs):
            raise Exception("Async error")

        mock_user_manager.create = mock_async_error

        with patch('vpn.cli.commands.users.UserManager', return_value=mock_user_manager):
            result = cli_runner.invoke(cli, [
                'users', 'create', 'testuser',
                '--protocol', 'vless'
            ])

            assert result.exit_code == 1
            assert "Async error" in result.output


class TestCLIConfiguration:
    """Test CLI configuration handling."""

    def test_config_file_loading(self, cli_runner, temp_config_dir):
        """Test loading configuration from file."""
        config_file = temp_config_dir / "config.toml"
        config_file.write_text("""
[database]
url = "sqlite:///test.db"

[logging]
level = "DEBUG"
""")

        with patch('vpn.cli.main.get_config_path', return_value=config_file):
            result = cli_runner.invoke(cli, ['--help'])

            assert result.exit_code == 0

    def test_environment_variable_override(self, cli_runner):
        """Test environment variable configuration override."""
        with patch.dict(os.environ, {'VPN_DATABASE_URL': 'sqlite:///env.db'}):
            result = cli_runner.invoke(cli, ['--help'])

            assert result.exit_code == 0

    def test_cli_option_override(self, cli_runner):
        """Test CLI option override."""
        result = cli_runner.invoke(cli, [
            '--config', '/custom/config.toml',
            '--help'
        ])

        assert result.exit_code == 0
