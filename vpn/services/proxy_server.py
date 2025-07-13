"""HTTP/HTTPS and SOCKS5 proxy server implementation.
"""

import asyncio
import base64
import socket
import struct
import time

from aiohttp import ClientSession, web

from vpn.core.config import get_config
from vpn.core.exceptions import ProxyError
from vpn.core.models import ProxyConfig, ProxyType, User
from vpn.services.base import BaseService
from vpn.services.user_manager import UserManager
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ProxyAuth:
    """Authentication handler for proxy server."""

    def __init__(self, user_manager: UserManager):
        """Initialize auth handler."""
        self.user_manager = user_manager
        self.active_sessions: set[str] = set()

    async def authenticate(self, username: str, password: str) -> User | None:
        """Authenticate user credentials."""
        try:
            user = await self.user_manager.get_by_username(username)
            if user and user.status == "active":
                # Verify password (simple check for now)
                # In production, use proper password hashing
                if password == str(user.keys.private_key):
                    return user
        except Exception as e:
            logger.error(f"Authentication error: {e}")

        return None

    def parse_basic_auth(self, auth_header: str) -> tuple[str | None, str | None]:
        """Parse Basic authentication header."""
        try:
            scheme, credentials = auth_header.split(' ', 1)
            if scheme.lower() != 'basic':
                return None, None

            decoded = base64.b64decode(credentials).decode('utf-8')
            username, password = decoded.split(':', 1)
            return username, password
        except Exception:
            return None, None


class RateLimiter:
    """Rate limiting for proxy connections."""

    def __init__(self, requests_per_minute: int = 60):
        """Initialize rate limiter."""
        self.requests_per_minute = requests_per_minute
        self.requests: dict[str, list[float]] = {}

    def is_allowed(self, client_ip: str) -> bool:
        """Check if request is allowed."""
        now = time.time()

        # Clean old entries
        if client_ip in self.requests:
            self.requests[client_ip] = [
                req_time for req_time in self.requests[client_ip]
                if now - req_time < 60  # Keep last minute
            ]
        else:
            self.requests[client_ip] = []

        # Check rate limit
        if len(self.requests[client_ip]) >= self.requests_per_minute:
            return False

        # Add current request
        self.requests[client_ip].append(now)
        return True


class HTTPProxyServer:
    """HTTP/HTTPS proxy server."""

    def __init__(self, config: ProxyConfig, auth: ProxyAuth, rate_limiter: RateLimiter):
        """Initialize HTTP proxy server."""
        self.config = config
        self.auth = auth
        self.rate_limiter = rate_limiter
        self.app = web.Application()
        self.setup_routes()

    def setup_routes(self):
        """Setup proxy routes."""
        self.app.router.add_route('*', '/{path:.*}', self.handle_request)

    async def handle_request(self, request: web.Request) -> web.Response:
        """Handle proxy request."""
        client_ip = request.remote

        # Rate limiting
        if not self.rate_limiter.is_allowed(client_ip):
            logger.warning(f"Rate limit exceeded for {client_ip}")
            return web.Response(status=429, text="Too Many Requests")

        # Authentication
        if self.config.auth_required:
            auth_header = request.headers.get('Proxy-Authorization')
            if not auth_header:
                return web.Response(
                    status=407,
                    headers={'Proxy-Authenticate': 'Basic realm="Proxy"'},
                    text="Proxy Authentication Required"
                )

            username, password = self.auth.parse_basic_auth(auth_header)
            if not username or not password:
                return web.Response(status=407, text="Invalid credentials format")

            user = await self.auth.authenticate(username, password)
            if not user:
                logger.warning(f"Authentication failed for {username} from {client_ip}")
                return web.Response(status=407, text="Authentication failed")

            logger.info(f"Authenticated user {username} from {client_ip}")

        # Handle CONNECT method for HTTPS
        if request.method == 'CONNECT':
            return await self.handle_connect(request)

        # Handle regular HTTP requests
        return await self.handle_http(request)

    async def handle_connect(self, request: web.Request) -> web.Response:
        """Handle HTTPS CONNECT requests."""
        host_port = request.path_qs

        try:
            # Parse host and port
            if ':' in host_port:
                host, port = host_port.rsplit(':', 1)
                port = int(port)
            else:
                host = host_port
                port = 443

            # Create connection to target
            target_reader, target_writer = await asyncio.open_connection(host, port)

            # Send connection established response
            response = web.Response(status=200, text="Connection established")

            # TODO: Implement tunnel forwarding
            # This would require lower-level socket handling

            return response

        except Exception as e:
            logger.error(f"CONNECT error: {e}")
            return web.Response(status=502, text="Bad Gateway")

    async def handle_http(self, request: web.Request) -> web.Response:
        """Handle HTTP requests."""
        url = request.path_qs

        # If URL is relative, it should be absolute for proxy
        if not url.startswith('http'):
            return web.Response(status=400, text="Bad Request")

        try:
            # Forward request
            async with ClientSession() as session:
                async with session.request(
                    method=request.method,
                    url=url,
                    headers=dict(request.headers),
                    data=await request.read(),
                    allow_redirects=False
                ) as resp:

                    # Create response
                    body = await resp.read()
                    headers = dict(resp.headers)

                    # Remove hop-by-hop headers
                    for header in ['connection', 'proxy-authenticate', 'proxy-authorization']:
                        headers.pop(header, None)

                    return web.Response(
                        status=resp.status,
                        headers=headers,
                        body=body
                    )

        except Exception as e:
            logger.error(f"HTTP proxy error: {e}")
            return web.Response(status=502, text="Bad Gateway")


class SOCKS5Server:
    """SOCKS5 proxy server."""

    SOCKS_VERSION = 5

    # Authentication methods
    NO_AUTH = 0
    USERNAME_PASSWORD = 2
    NO_ACCEPTABLE = 0xFF

    # Commands
    CONNECT = 1
    BIND = 2
    UDP_ASSOCIATE = 3

    # Address types
    IPV4 = 1
    DOMAIN = 3
    IPV6 = 4

    def __init__(self, config: ProxyConfig, auth: ProxyAuth, rate_limiter: RateLimiter):
        """Initialize SOCKS5 server."""
        self.config = config
        self.auth = auth
        self.rate_limiter = rate_limiter
        self.server = None

    async def start_server(self):
        """Start SOCKS5 server."""
        self.server = await asyncio.start_server(
            self.handle_client,
            self.config.host,
            self.config.port
        )

        logger.info(f"SOCKS5 server listening on {self.config.host}:{self.config.port}")
        await self.server.serve_forever()

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Handle SOCKS5 client connection."""
        client_addr = writer.get_extra_info('peername')
        client_ip = client_addr[0] if client_addr else 'unknown'

        logger.info(f"SOCKS5 connection from {client_ip}")

        # Rate limiting
        if not self.rate_limiter.is_allowed(client_ip):
            logger.warning(f"Rate limit exceeded for {client_ip}")
            writer.close()
            await writer.wait_closed()
            return

        try:
            # Handle authentication negotiation
            if not await self.handle_auth_negotiation(reader, writer):
                return

            # Handle authentication if required
            if self.config.auth_required:
                if not await self.handle_authentication(reader, writer):
                    return

            # Handle connection request
            await self.handle_connection_request(reader, writer)

        except Exception as e:
            logger.error(f"SOCKS5 error for {client_ip}: {e}")
        finally:
            writer.close()
            await writer.wait_closed()

    async def handle_auth_negotiation(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> bool:
        """Handle authentication method negotiation."""
        try:
            # Read version and number of methods
            data = await reader.read(2)
            if len(data) != 2:
                return False

            version, nmethods = struct.unpack('!BB', data)
            if version != self.SOCKS_VERSION:
                return False

            # Read authentication methods
            methods = await reader.read(nmethods)
            if len(methods) != nmethods:
                return False

            methods = list(methods)

            # Choose authentication method
            if self.config.auth_required:
                if self.USERNAME_PASSWORD in methods:
                    chosen_method = self.USERNAME_PASSWORD
                else:
                    chosen_method = self.NO_ACCEPTABLE
            else:
                chosen_method = self.NO_AUTH

            # Send response
            response = struct.pack('!BB', self.SOCKS_VERSION, chosen_method)
            writer.write(response)
            await writer.drain()

            return chosen_method != self.NO_ACCEPTABLE

        except Exception as e:
            logger.error(f"Auth negotiation error: {e}")
            return False

    async def handle_authentication(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> bool:
        """Handle username/password authentication."""
        try:
            # Read version
            data = await reader.read(1)
            if len(data) != 1 or data[0] != 1:
                return False

            # Read username length and username
            ulen_data = await reader.read(1)
            if len(ulen_data) != 1:
                return False

            ulen = ulen_data[0]
            username_data = await reader.read(ulen)
            if len(username_data) != ulen:
                return False

            username = username_data.decode('utf-8')

            # Read password length and password
            plen_data = await reader.read(1)
            if len(plen_data) != 1:
                return False

            plen = plen_data[0]
            password_data = await reader.read(plen)
            if len(password_data) != plen:
                return False

            password = password_data.decode('utf-8')

            # Authenticate
            user = await self.auth.authenticate(username, password)
            success = user is not None

            # Send response
            status = 0 if success else 1
            response = struct.pack('!BB', 1, status)
            writer.write(response)
            await writer.drain()

            if success:
                logger.info(f"SOCKS5 authenticated user {username}")
            else:
                logger.warning(f"SOCKS5 authentication failed for {username}")

            return success

        except Exception as e:
            logger.error(f"SOCKS5 authentication error: {e}")
            return False

    async def handle_connection_request(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Handle SOCKS5 connection request."""
        try:
            # Read request header
            data = await reader.read(4)
            if len(data) != 4:
                return

            version, cmd, rsv, atyp = struct.unpack('!BBBB', data)

            if version != self.SOCKS_VERSION or cmd != self.CONNECT:
                # Send error response
                response = struct.pack('!BBBBIH', self.SOCKS_VERSION, 7, 0, 1, 0, 0)
                writer.write(response)
                await writer.drain()
                return

            # Read address
            if atyp == self.IPV4:
                addr_data = await reader.read(4)
                if len(addr_data) != 4:
                    return
                host = socket.inet_ntoa(addr_data)
            elif atyp == self.DOMAIN:
                domain_len_data = await reader.read(1)
                if len(domain_len_data) != 1:
                    return
                domain_len = domain_len_data[0]
                domain_data = await reader.read(domain_len)
                if len(domain_data) != domain_len:
                    return
                host = domain_data.decode('utf-8')
            elif atyp == self.IPV6:
                addr_data = await reader.read(16)
                if len(addr_data) != 16:
                    return
                host = socket.inet_ntop(socket.AF_INET6, addr_data)
            else:
                # Unsupported address type
                response = struct.pack('!BBBBIH', self.SOCKS_VERSION, 8, 0, 1, 0, 0)
                writer.write(response)
                await writer.drain()
                return

            # Read port
            port_data = await reader.read(2)
            if len(port_data) != 2:
                return
            port = struct.unpack('!H', port_data)[0]

            logger.info(f"SOCKS5 connecting to {host}:{port}")

            # Connect to target
            try:
                target_reader, target_writer = await asyncio.open_connection(host, port)

                # Send success response
                response = struct.pack('!BBBBIH', self.SOCKS_VERSION, 0, 0, 1, 0, 0)
                writer.write(response)
                await writer.drain()

                # Start forwarding data
                await self.forward_data(reader, writer, target_reader, target_writer)

            except Exception as e:
                logger.error(f"Connection to {host}:{port} failed: {e}")
                # Send connection refused
                response = struct.pack('!BBBBIH', self.SOCKS_VERSION, 5, 0, 1, 0, 0)
                writer.write(response)
                await writer.drain()

        except Exception as e:
            logger.error(f"Connection request error: {e}")

    async def forward_data(
        self,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
        target_reader: asyncio.StreamReader,
        target_writer: asyncio.StreamWriter
    ):
        """Forward data between client and target."""
        async def copy_data(reader, writer):
            try:
                while True:
                    data = await reader.read(4096)
                    if not data:
                        break
                    writer.write(data)
                    await writer.drain()
            except Exception:
                pass
            finally:
                writer.close()

        # Start forwarding in both directions
        await asyncio.gather(
            copy_data(client_reader, target_writer),
            copy_data(target_reader, client_writer),
            return_exceptions=True
        )


class ProxyServerManager(BaseService):
    """Manages proxy server instances."""

    def __init__(self):
        """Initialize proxy server manager."""
        super().__init__()
        self.user_manager = UserManager()
        self.config = get_config()
        self.servers: dict[str, asyncio.Task] = {}
        self.auth = ProxyAuth(self.user_manager)
        self.rate_limiter = RateLimiter()

    async def start_http_proxy(
        self,
        host: str = "0.0.0.0",
        port: int = 8888,
        auth_required: bool = True
    ) -> str:
        """Start HTTP proxy server."""
        server_name = f"http-proxy-{port}"

        if server_name in self.servers:
            raise ProxyError(f"HTTP proxy already running on port {port}")

        config = ProxyConfig(
            type=ProxyType.HTTP,
            host=host,
            port=port,
            auth_required=auth_required
        )

        http_server = HTTPProxyServer(config, self.auth, self.rate_limiter)

        # Start server
        runner = web.AppRunner(http_server.app)
        await runner.setup()

        site = web.TCPSite(runner, host, port)
        await site.start()

        logger.info(f"HTTP proxy server started on {host}:{port}")
        return server_name

    async def start_socks5_proxy(
        self,
        host: str = "0.0.0.0",
        port: int = 1080,
        auth_required: bool = True
    ) -> str:
        """Start SOCKS5 proxy server."""
        server_name = f"socks5-proxy-{port}"

        if server_name in self.servers:
            raise ProxyError(f"SOCKS5 proxy already running on port {port}")

        config = ProxyConfig(
            type=ProxyType.SOCKS5,
            host=host,
            port=port,
            auth_required=auth_required
        )

        socks5_server = SOCKS5Server(config, self.auth, self.rate_limiter)

        # Start server in background task
        task = asyncio.create_task(socks5_server.start_server())
        self.servers[server_name] = task

        logger.info(f"SOCKS5 proxy server started on {host}:{port}")
        return server_name

    async def stop_proxy(self, server_name: str) -> None:
        """Stop proxy server."""
        if server_name not in self.servers:
            raise ProxyError(f"Proxy server '{server_name}' not found")

        task = self.servers[server_name]
        task.cancel()

        try:
            await task
        except asyncio.CancelledError:
            pass

        del self.servers[server_name]
        logger.info(f"Stopped proxy server {server_name}")

    async def list_proxies(self) -> list[dict[str, any]]:
        """List running proxy servers."""
        proxies = []

        for server_name, task in self.servers.items():
            status = "running" if not task.done() else "stopped"

            # Parse server info from name
            if server_name.startswith("http-proxy-"):
                proxy_type = "HTTP"
                port = int(server_name.replace("http-proxy-", ""))
            elif server_name.startswith("socks5-proxy-"):
                proxy_type = "SOCKS5"
                port = int(server_name.replace("socks5-proxy-", ""))
            else:
                proxy_type = "unknown"
                port = 0

            proxies.append({
                "name": server_name,
                "type": proxy_type,
                "port": port,
                "status": status
            })

        return proxies

    async def get_proxy_stats(self, server_name: str) -> dict[str, any]:
        """Get proxy server statistics."""
        # TODO: Implement statistics collection
        return {
            "connections": 0,
            "bytes_transferred": 0,
            "requests_per_minute": 0
        }
