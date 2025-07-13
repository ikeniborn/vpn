"""
Tests for proxy server implementations.
"""

import asyncio
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from vpn.core.exceptions import ProxyServerError
from vpn.core.models import ProtocolConfig, ProtocolType, User
from vpn.services.proxy_server import (
    HTTPProxyServer,
    ProxyAuthentication,
    ProxyServerManager,
    ProxyStats,
    SOCKS5Handler,
    SOCKS5Server,
)


@pytest.fixture
def temp_dir():
    """Create temporary directory for tests."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        yield Path(tmp_dir)


@pytest.fixture
def sample_user():
    """Create sample user for testing."""
    protocol = ProtocolConfig(type=ProtocolType.HTTP)
    return User(
        username="testuser",
        email="test@example.com",
        protocol=protocol
    )


@pytest.fixture
def mock_auth():
    """Create mock authentication service."""
    auth = AsyncMock(spec=ProxyAuthentication)
    auth.validate_user.return_value = True
    auth.is_rate_limited.return_value = False
    auth.record_request.return_value = None
    return auth


class TestHTTPProxyServer:
    """Test HTTP proxy server implementation."""

    def test_init(self):
        """Test HTTP proxy server initialization."""
        server = HTTPProxyServer(
            host="127.0.0.1",
            port=8888,
            require_auth=True
        )

        assert server.host == "127.0.0.1"
        assert server.port == 8888
        assert server.require_auth is True
        assert server.server is None
        assert server.stats is not None
        assert isinstance(server.stats, ProxyStats)

    @pytest.mark.asyncio
    async def test_start_server(self):
        """Test starting HTTP proxy server."""
        server = HTTPProxyServer(host="127.0.0.1", port=8888)

        with patch('aiohttp.web.run_app') as mock_run:
            mock_run.return_value = None

            await server.start()

            assert mock_run.called
            assert server.server is not None

    @pytest.mark.asyncio
    async def test_stop_server(self):
        """Test stopping HTTP proxy server."""
        server = HTTPProxyServer(host="127.0.0.1", port=8888)

        # Mock running server
        mock_server = MagicMock()
        mock_server.close = AsyncMock()
        mock_server.wait_closed = AsyncMock()
        server.server = mock_server

        await server.stop()

        mock_server.close.assert_called_once()
        mock_server.wait_closed.assert_called_once()
        assert server.server is None

    @pytest.mark.asyncio
    async def test_handle_request_without_auth(self):
        """Test handling HTTP request without authentication."""
        server = HTTPProxyServer(host="127.0.0.1", port=8888, require_auth=False)

        # Mock request
        mock_request = MagicMock()
        mock_request.method = "GET"
        mock_request.url = "http://example.com"
        mock_request.headers = {}

        with patch('aiohttp.ClientSession') as mock_session:
            mock_response = MagicMock()
            mock_response.status = 200
            mock_response.headers = {"Content-Type": "text/html"}
            mock_response.read.return_value = b"<html>test</html>"

            mock_session.return_value.__aenter__.return_value.request.return_value = mock_response

            response = await server.handle_request(mock_request)

            assert response.status == 200
            assert server.stats.requests_count == 1
            assert server.stats.bytes_transferred > 0

    @pytest.mark.asyncio
    async def test_handle_request_with_auth_success(self, mock_auth):
        """Test handling HTTP request with successful authentication."""
        server = HTTPProxyServer(
            host="127.0.0.1",
            port=8888,
            require_auth=True,
            auth_service=mock_auth
        )

        # Mock request with auth header
        mock_request = MagicMock()
        mock_request.method = "GET"
        mock_request.url = "http://example.com"
        mock_request.headers = {"Proxy-Authorization": "Basic dGVzdHVzZXI6cGFzc3dvcmQ="}
        mock_request.remote = "127.0.0.1"

        with patch('aiohttp.ClientSession') as mock_session:
            mock_response = MagicMock()
            mock_response.status = 200
            mock_response.headers = {}
            mock_response.read.return_value = b"success"

            mock_session.return_value.__aenter__.return_value.request.return_value = mock_response

            response = await server.handle_request(mock_request)

            assert response.status == 200
            mock_auth.validate_user.assert_called_once()
            mock_auth.record_request.assert_called_once()

    @pytest.mark.asyncio
    async def test_handle_request_with_auth_failure(self, mock_auth):
        """Test handling HTTP request with failed authentication."""
        mock_auth.validate_user.return_value = False

        server = HTTPProxyServer(
            host="127.0.0.1",
            port=8888,
            require_auth=True,
            auth_service=mock_auth
        )

        # Mock request with invalid auth
        mock_request = MagicMock()
        mock_request.method = "GET"
        mock_request.url = "http://example.com"
        mock_request.headers = {"Proxy-Authorization": "Basic aW52YWxpZA=="}
        mock_request.remote = "127.0.0.1"

        response = await server.handle_request(mock_request)

        assert response.status == 407
        assert server.stats.auth_failures == 1

    @pytest.mark.asyncio
    async def test_handle_connect_request(self):
        """Test handling CONNECT request for HTTPS tunneling."""
        server = HTTPProxyServer(host="127.0.0.1", port=8888, require_auth=False)

        # Mock CONNECT request
        mock_request = MagicMock()
        mock_request.method = "CONNECT"
        mock_request.url = "https://example.com:443"
        mock_request.headers = {}

        with patch('asyncio.open_connection') as mock_connect:
            mock_reader = AsyncMock()
            mock_writer = AsyncMock()
            mock_connect.return_value = (mock_reader, mock_writer)

            with patch.object(server, '_tunnel_data') as mock_tunnel:
                mock_tunnel.return_value = None

                response = await server.handle_request(mock_request)

                assert response.status == 200
                mock_connect.assert_called_once_with("example.com", 443)

    @pytest.mark.asyncio
    async def test_rate_limiting(self, mock_auth):
        """Test rate limiting functionality."""
        mock_auth.is_rate_limited.return_value = True

        server = HTTPProxyServer(
            host="127.0.0.1",
            port=8888,
            require_auth=True,
            auth_service=mock_auth
        )

        # Mock request
        mock_request = MagicMock()
        mock_request.method = "GET"
        mock_request.url = "http://example.com"
        mock_request.headers = {"Proxy-Authorization": "Basic dGVzdA=="}
        mock_request.remote = "127.0.0.1"

        response = await server.handle_request(mock_request)

        assert response.status == 429
        assert server.stats.rate_limited == 1

    def test_extract_auth_credentials(self):
        """Test extracting authentication credentials from header."""
        server = HTTPProxyServer(host="127.0.0.1", port=8888)

        # Test valid Basic auth
        auth_header = "Basic dGVzdDpwYXNzd29yZA=="  # test:password
        username, password = server._extract_auth_credentials(auth_header)
        assert username == "test"
        assert password == "password"

        # Test invalid format
        username, password = server._extract_auth_credentials("Invalid format")
        assert username is None
        assert password is None

        # Test non-Basic auth
        username, password = server._extract_auth_credentials("Bearer token")
        assert username is None
        assert password is None

    def test_stats_tracking(self):
        """Test proxy statistics tracking."""
        server = HTTPProxyServer(host="127.0.0.1", port=8888)

        # Initial stats
        assert server.stats.requests_count == 0
        assert server.stats.bytes_transferred == 0
        assert server.stats.auth_failures == 0
        assert server.stats.rate_limited == 0

        # Update stats
        server.stats.requests_count += 1
        server.stats.bytes_transferred += 1024
        server.stats.auth_failures += 1
        server.stats.rate_limited += 1

        assert server.stats.requests_count == 1
        assert server.stats.bytes_transferred == 1024
        assert server.stats.auth_failures == 1
        assert server.stats.rate_limited == 1


class TestSOCKS5Server:
    """Test SOCKS5 proxy server implementation."""

    def test_init(self):
        """Test SOCKS5 server initialization."""
        server = SOCKS5Server(
            host="127.0.0.1",
            port=1080,
            require_auth=True
        )

        assert server.host == "127.0.0.1"
        assert server.port == 1080
        assert server.require_auth is True
        assert server.server is None
        assert server.stats is not None

    @pytest.mark.asyncio
    async def test_start_server(self):
        """Test starting SOCKS5 server."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)

        with patch('asyncio.start_server') as mock_start:
            mock_server = MagicMock()
            mock_start.return_value = mock_server

            await server.start()

            assert mock_start.called
            assert server.server == mock_server

    @pytest.mark.asyncio
    async def test_stop_server(self):
        """Test stopping SOCKS5 server."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)

        # Mock running server
        mock_server = MagicMock()
        mock_server.close = MagicMock()
        mock_server.wait_closed = AsyncMock()
        server.server = mock_server

        await server.stop()

        mock_server.close.assert_called_once()
        mock_server.wait_closed.assert_called_once()
        assert server.server is None

    @pytest.mark.asyncio
    async def test_handle_client_connection(self):
        """Test handling SOCKS5 client connection."""
        server = SOCKS5Server(host="127.0.0.1", port=1080, require_auth=False)

        # Mock reader/writer
        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Create handler
        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        with patch.object(handler, 'handle_authentication') as mock_auth:
            mock_auth.return_value = True

            with patch.object(handler, 'handle_connection_request') as mock_connect:
                mock_connect.return_value = None

                await handler.handle()

                mock_auth.assert_called_once()
                mock_connect.assert_called_once()

    @pytest.mark.asyncio
    async def test_socks5_authentication_no_auth(self):
        """Test SOCKS5 authentication with no authentication required."""
        server = SOCKS5Server(host="127.0.0.1", port=1080, require_auth=False)

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock initial greeting
        mock_reader.read.return_value = b'\x05\x01\x00'  # SOCKS5, 1 method, NO AUTH

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        result = await handler.handle_authentication()

        assert result is True
        mock_writer.write.assert_called_with(b'\x05\x00')  # SOCKS5, NO AUTH

    @pytest.mark.asyncio
    async def test_socks5_authentication_with_auth(self, mock_auth):
        """Test SOCKS5 authentication with username/password."""
        server = SOCKS5Server(
            host="127.0.0.1",
            port=1080,
            require_auth=True,
            auth_service=mock_auth
        )

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock authentication sequence
        mock_reader.read.side_effect = [
            b'\x05\x01\x02',  # SOCKS5, 1 method, USERNAME/PASSWORD
            b'\x01\x04test\x08password'  # Version 1, username: test, password: password
        ]

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        result = await handler.handle_authentication()

        assert result is True
        mock_auth.validate_user.assert_called_once_with("test", "password")

    @pytest.mark.asyncio
    async def test_socks5_connection_request_ipv4(self):
        """Test SOCKS5 connection request with IPv4 address."""
        server = SOCKS5Server(host="127.0.0.1", port=1080, require_auth=False)

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock connection request: CONNECT to 93.184.216.34:80 (example.com)
        mock_reader.read.return_value = b'\x05\x01\x00\x01\x5d\xb8\xd8\x22\x00\x50'

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        with patch('asyncio.open_connection') as mock_connect:
            mock_target_reader = AsyncMock()
            mock_target_writer = AsyncMock()
            mock_connect.return_value = (mock_target_reader, mock_target_writer)

            with patch.object(handler, 'relay_data') as mock_relay:
                mock_relay.return_value = None

                await handler.handle_connection_request()

                mock_connect.assert_called_once_with("93.184.216.34", 80)
                mock_writer.write.assert_called()

    @pytest.mark.asyncio
    async def test_socks5_connection_request_domain(self):
        """Test SOCKS5 connection request with domain name."""
        server = SOCKS5Server(host="127.0.0.1", port=1080, require_auth=False)

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock connection request: CONNECT to example.com:80
        domain_request = b'\x05\x01\x00\x03\x0bexample.com\x00\x50'
        mock_reader.read.return_value = domain_request

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        with patch('asyncio.open_connection') as mock_connect:
            mock_target_reader = AsyncMock()
            mock_target_writer = AsyncMock()
            mock_connect.return_value = (mock_target_reader, mock_target_writer)

            with patch.object(handler, 'relay_data') as mock_relay:
                mock_relay.return_value = None

                await handler.handle_connection_request()

                mock_connect.assert_called_once_with("example.com", 80)
                mock_writer.write.assert_called()

    @pytest.mark.asyncio
    async def test_socks5_unsupported_command(self):
        """Test SOCKS5 unsupported command handling."""
        server = SOCKS5Server(host="127.0.0.1", port=1080, require_auth=False)

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock BIND request (unsupported)
        mock_reader.read.return_value = b'\x05\x02\x00\x01\x7f\x00\x00\x01\x00\x50'

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        await handler.handle_connection_request()

        # Should respond with "command not supported"
        mock_writer.write.assert_called()
        written_data = mock_writer.write.call_args[0][0]
        assert written_data[1] == 0x07  # Command not supported

    @pytest.mark.asyncio
    async def test_data_relay(self):
        """Test bidirectional data relay."""
        server = SOCKS5Server(host="127.0.0.1", port=1080, require_auth=False)

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()
        mock_target_reader = AsyncMock()
        mock_target_writer = AsyncMock()

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        # Mock data transfer
        mock_reader.read.side_effect = [b'client_data', b'']
        mock_target_reader.read.side_effect = [b'server_data', b'']

        with patch('asyncio.gather') as mock_gather:
            mock_gather.return_value = None

            await handler.relay_data(mock_target_reader, mock_target_writer)

            mock_gather.assert_called_once()


class TestSOCKS5Handler:
    """Test SOCKS5 connection handler."""

    def test_init(self):
        """Test SOCKS5 handler initialization."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)
        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        handler = SOCKS5Handler(server, mock_reader, mock_writer)

        assert handler.server == server
        assert handler.reader == mock_reader
        assert handler.writer == mock_writer
        assert handler.client_addr is not None

    def test_parse_address_ipv4(self):
        """Test parsing IPv4 address from SOCKS5 request."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)
        handler = SOCKS5Handler(server, AsyncMock(), AsyncMock())

        # IPv4 address: 192.168.1.1
        address_data = b'\x01\xc0\xa8\x01\x01'

        addr_type, address = handler._parse_address(address_data)

        assert addr_type == 1  # IPv4
        assert address == "192.168.1.1"

    def test_parse_address_domain(self):
        """Test parsing domain name from SOCKS5 request."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)
        handler = SOCKS5Handler(server, AsyncMock(), AsyncMock())

        # Domain name: example.com
        address_data = b'\x03\x0bexample.com'

        addr_type, address = handler._parse_address(address_data)

        assert addr_type == 3  # Domain
        assert address == "example.com"

    def test_parse_address_ipv6(self):
        """Test parsing IPv6 address from SOCKS5 request."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)
        handler = SOCKS5Handler(server, AsyncMock(), AsyncMock())

        # IPv6 address: ::1
        address_data = b'\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01'

        addr_type, address = handler._parse_address(address_data)

        assert addr_type == 4  # IPv6
        assert address == "::1"

    def test_create_response(self):
        """Test creating SOCKS5 response."""
        server = SOCKS5Server(host="127.0.0.1", port=1080)
        handler = SOCKS5Handler(server, AsyncMock(), AsyncMock())

        # Success response
        response = handler._create_response(0x00, "127.0.0.1", 8080)

        assert response[0] == 0x05  # SOCKS5
        assert response[1] == 0x00  # Success
        assert response[2] == 0x00  # Reserved
        assert response[3] == 0x01  # IPv4

        # Error response
        response = handler._create_response(0x01, "127.0.0.1", 8080)
        assert response[1] == 0x01  # General failure


class TestProxyAuthentication:
    """Test proxy authentication service."""

    def test_init(self):
        """Test authentication service initialization."""
        auth = ProxyAuthentication()

        assert auth.rate_limits == {}
        assert auth.active_sessions == {}
        assert auth.user_manager is None

    @pytest.mark.asyncio
    async def test_validate_user_success(self):
        """Test successful user validation."""
        auth = ProxyAuthentication()

        # Mock user manager
        mock_user_manager = AsyncMock()
        mock_user_manager.get_by_username.return_value = MagicMock(
            username="testuser",
            is_active=True
        )
        auth.user_manager = mock_user_manager

        result = await auth.validate_user("testuser", "password")

        assert result is True
        mock_user_manager.get_by_username.assert_called_once_with("testuser")

    @pytest.mark.asyncio
    async def test_validate_user_not_found(self):
        """Test user validation with non-existent user."""
        auth = ProxyAuthentication()

        # Mock user manager
        mock_user_manager = AsyncMock()
        mock_user_manager.get_by_username.return_value = None
        auth.user_manager = mock_user_manager

        result = await auth.validate_user("nonexistent", "password")

        assert result is False

    @pytest.mark.asyncio
    async def test_validate_user_inactive(self):
        """Test user validation with inactive user."""
        auth = ProxyAuthentication()

        # Mock user manager
        mock_user_manager = AsyncMock()
        mock_user_manager.get_by_username.return_value = MagicMock(
            username="testuser",
            is_active=False
        )
        auth.user_manager = mock_user_manager

        result = await auth.validate_user("testuser", "password")

        assert result is False

    def test_rate_limiting(self):
        """Test rate limiting functionality."""
        auth = ProxyAuthentication()
        client_ip = "192.168.1.1"

        # First request should not be rate limited
        assert auth.is_rate_limited(client_ip) is False

        # Record multiple requests
        for _ in range(60):  # Default rate limit
            auth.record_request(client_ip)

        # Should now be rate limited
        assert auth.is_rate_limited(client_ip) is True

    def test_rate_limit_cleanup(self):
        """Test rate limit cleanup of old entries."""
        auth = ProxyAuthentication()
        client_ip = "192.168.1.1"

        # Record request
        auth.record_request(client_ip)

        # Manually set old timestamp
        auth.rate_limits[client_ip] = [
            datetime.utcnow() - timedelta(minutes=2)
        ]

        # Should clean up old entries
        auth.record_request(client_ip)

        assert len(auth.rate_limits[client_ip]) == 1

    def test_session_management(self):
        """Test session management."""
        auth = ProxyAuthentication()

        # Create session
        session_id = auth.create_session("testuser", "192.168.1.1")

        assert session_id in auth.active_sessions
        assert auth.active_sessions[session_id]["username"] == "testuser"

        # Validate session
        assert auth.validate_session(session_id) is True
        assert auth.validate_session("invalid") is False

        # Remove session
        auth.remove_session(session_id)
        assert session_id not in auth.active_sessions


class TestProxyServerManager:
    """Test proxy server manager."""

    def test_init(self):
        """Test proxy server manager initialization."""
        manager = ProxyServerManager()

        assert manager.servers == {}
        assert manager.auth_service is not None

    @pytest.mark.asyncio
    async def test_start_http_proxy(self):
        """Test starting HTTP proxy server."""
        manager = ProxyServerManager()

        with patch('vpn.services.proxy_server.HTTPProxyServer') as mock_http:
            mock_server = AsyncMock()
            mock_server.start.return_value = None
            mock_http.return_value = mock_server

            await manager.start_http_proxy(
                port=8888,
                require_auth=True,
                name="test-http"
            )

            assert "test-http" in manager.servers
            mock_server.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_socks5_proxy(self):
        """Test starting SOCKS5 proxy server."""
        manager = ProxyServerManager()

        with patch('vpn.services.proxy_server.SOCKS5Server') as mock_socks:
            mock_server = AsyncMock()
            mock_server.start.return_value = None
            mock_socks.return_value = mock_server

            await manager.start_socks5_proxy(
                port=1080,
                require_auth=False,
                name="test-socks5"
            )

            assert "test-socks5" in manager.servers
            mock_server.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_proxy(self):
        """Test stopping proxy server."""
        manager = ProxyServerManager()

        # Mock server
        mock_server = AsyncMock()
        mock_server.stop.return_value = None
        manager.servers["test-proxy"] = mock_server

        await manager.stop_proxy("test-proxy")

        assert "test-proxy" not in manager.servers
        mock_server.stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_nonexistent_proxy(self):
        """Test stopping non-existent proxy server."""
        manager = ProxyServerManager()

        with pytest.raises(ProxyServerError, match="not found"):
            await manager.stop_proxy("nonexistent")

    def test_list_servers(self):
        """Test listing proxy servers."""
        manager = ProxyServerManager()

        # Mock servers
        http_server = MagicMock()
        http_server.host = "127.0.0.1"
        http_server.port = 8888
        http_server.require_auth = True
        http_server.stats = MagicMock()

        socks_server = MagicMock()
        socks_server.host = "127.0.0.1"
        socks_server.port = 1080
        socks_server.require_auth = False
        socks_server.stats = MagicMock()

        manager.servers["http-proxy"] = http_server
        manager.servers["socks5-proxy"] = socks_server

        servers = manager.list_servers()

        assert len(servers) == 2
        assert "http-proxy" in servers
        assert "socks5-proxy" in servers

    def test_get_server_stats(self):
        """Test getting server statistics."""
        manager = ProxyServerManager()

        # Mock server with stats
        mock_server = MagicMock()
        mock_server.stats = MagicMock()
        mock_server.stats.requests_count = 100
        mock_server.stats.bytes_transferred = 1024
        manager.servers["test-proxy"] = mock_server

        stats = manager.get_server_stats("test-proxy")

        assert stats.requests_count == 100
        assert stats.bytes_transferred == 1024

    def test_get_stats_nonexistent_server(self):
        """Test getting stats for non-existent server."""
        manager = ProxyServerManager()

        with pytest.raises(ProxyServerError, match="not found"):
            manager.get_server_stats("nonexistent")

    @pytest.mark.asyncio
    async def test_stop_all_servers(self):
        """Test stopping all proxy servers."""
        manager = ProxyServerManager()

        # Mock servers
        mock_server1 = AsyncMock()
        mock_server2 = AsyncMock()
        manager.servers["server1"] = mock_server1
        manager.servers["server2"] = mock_server2

        await manager.stop_all()

        assert len(manager.servers) == 0
        mock_server1.stop.assert_called_once()
        mock_server2.stop.assert_called_once()


class TestProxyStats:
    """Test proxy statistics tracking."""

    def test_init(self):
        """Test proxy stats initialization."""
        stats = ProxyStats()

        assert stats.requests_count == 0
        assert stats.bytes_transferred == 0
        assert stats.auth_failures == 0
        assert stats.rate_limited == 0
        assert stats.connections_active == 0
        assert isinstance(stats.start_time, datetime)

    def test_stats_update(self):
        """Test updating proxy statistics."""
        stats = ProxyStats()

        # Update various stats
        stats.requests_count = 100
        stats.bytes_transferred = 1024 * 1024  # 1MB
        stats.auth_failures = 5
        stats.rate_limited = 3
        stats.connections_active = 10

        assert stats.requests_count == 100
        assert stats.bytes_transferred == 1024 * 1024
        assert stats.auth_failures == 5
        assert stats.rate_limited == 3
        assert stats.connections_active == 10

    def test_stats_serialization(self):
        """Test proxy stats serialization."""
        stats = ProxyStats()
        stats.requests_count = 50
        stats.bytes_transferred = 2048

        # Test dict conversion
        stats_dict = stats.to_dict()

        assert stats_dict["requests_count"] == 50
        assert stats_dict["bytes_transferred"] == 2048
        assert "start_time" in stats_dict
        assert "uptime_seconds" in stats_dict

    def test_uptime_calculation(self):
        """Test uptime calculation."""
        stats = ProxyStats()

        # Mock start time to 1 minute ago
        stats.start_time = datetime.utcnow() - timedelta(minutes=1)

        uptime = stats.uptime_seconds

        assert uptime >= 60  # Should be at least 60 seconds
        assert uptime <= 70  # Allow some margin for test execution time


class TestProxyIntegration:
    """Test proxy server integration scenarios."""

    @pytest.mark.asyncio
    async def test_proxy_chain_http_to_socks5(self):
        """Test chaining HTTP proxy to SOCKS5 proxy."""
        # This would test more complex scenarios
        # For now, just verify the concept works
        http_manager = ProxyServerManager()
        socks_manager = ProxyServerManager()

        # Mock both servers
        with patch('vpn.services.proxy_server.HTTPProxyServer') as mock_http:
            with patch('vpn.services.proxy_server.SOCKS5Server') as mock_socks:
                mock_http_server = AsyncMock()
                mock_socks_server = AsyncMock()
                mock_http.return_value = mock_http_server
                mock_socks.return_value = mock_socks_server

                # Start both servers
                await http_manager.start_http_proxy(port=8888, name="http-proxy")
                await socks_manager.start_socks5_proxy(port=1080, name="socks5-proxy")

                # Verify both are running
                assert len(http_manager.servers) == 1
                assert len(socks_manager.servers) == 1

    @pytest.mark.asyncio
    async def test_concurrent_proxy_operations(self):
        """Test concurrent proxy operations."""
        manager = ProxyServerManager()

        with patch('vpn.services.proxy_server.HTTPProxyServer') as mock_http:
            with patch('vpn.services.proxy_server.SOCKS5Server') as mock_socks:
                mock_http_server = AsyncMock()
                mock_socks_server = AsyncMock()
                mock_http.return_value = mock_http_server
                mock_socks.return_value = mock_socks_server

                # Start multiple servers concurrently
                tasks = [
                    manager.start_http_proxy(port=8888, name="http-1"),
                    manager.start_http_proxy(port=8889, name="http-2"),
                    manager.start_socks5_proxy(port=1080, name="socks5-1"),
                    manager.start_socks5_proxy(port=1081, name="socks5-2")
                ]

                await asyncio.gather(*tasks)

                # Verify all servers started
                assert len(manager.servers) == 4

                # Stop all servers
                await manager.stop_all()
                assert len(manager.servers) == 0

    @pytest.mark.asyncio
    async def test_proxy_error_handling(self):
        """Test proxy error handling scenarios."""
        manager = ProxyServerManager()

        # Test starting proxy on occupied port
        with patch('vpn.services.proxy_server.HTTPProxyServer') as mock_http:
            mock_server = AsyncMock()
            mock_server.start.side_effect = OSError("Address already in use")
            mock_http.return_value = mock_server

            with pytest.raises(ProxyServerError):
                await manager.start_http_proxy(port=8888, name="test-proxy")

    @pytest.mark.asyncio
    async def test_proxy_authentication_integration(self, sample_user):
        """Test proxy authentication with user management."""
        manager = ProxyServerManager()

        # Mock user manager
        mock_user_manager = AsyncMock()
        mock_user_manager.get_by_username.return_value = sample_user
        manager.auth_service.user_manager = mock_user_manager

        # Test authentication
        result = await manager.auth_service.validate_user("testuser", "password")

        assert result is True
        mock_user_manager.get_by_username.assert_called_once_with("testuser")
