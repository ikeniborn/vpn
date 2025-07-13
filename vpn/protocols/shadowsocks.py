"""Shadowsocks/Outline protocol implementation.
"""

import base64
import secrets
from pathlib import Path
from typing import Any

from vpn.core.models import ServerConfig, User
from vpn.protocols.base import BaseProtocol


class ShadowsocksProtocol(BaseProtocol):
    """Shadowsocks protocol implementation."""

    SUPPORTED_CIPHERS = [
        "aes-256-gcm",
        "aes-128-gcm",
        "chacha20-ietf-poly1305",
        "xchacha20-ietf-poly1305",
        "2022-blake3-aes-256-gcm",
        "2022-blake3-chacha20-poly1305",
    ]

    def __init__(self, server_config: ServerConfig):
        """Initialize Shadowsocks protocol."""
        super().__init__(server_config)
        self.cipher = self.server_config.extra_config.get("cipher", "aes-256-gcm")
        self.password = self.server_config.extra_config.get("password", self._generate_password())

    def _generate_password(self) -> str:
        """Generate a secure random password."""
        return secrets.token_urlsafe(32)

    async def generate_server_config(self, template_path: Path) -> str:
        """Generate Shadowsocks server configuration."""
        from jinja2 import Environment, FileSystemLoader

        env = Environment(
            loader=FileSystemLoader(template_path.parent),
            trim_blocks=True,
            lstrip_blocks=True
        )

        template = env.get_template(template_path.name)

        # For multi-user support, generate access keys
        users = await self._get_all_users()
        access_keys = []

        for user in users:
            key = await self.generate_access_key(user)
            access_keys.append({
                "id": str(user.id),
                "name": user.username,
                "password": key["password"],
                "port": key.get("port", self.server_config.port),
                "method": self.cipher
            })

        context = {
            "server": self.server_config,
            "cipher": self.cipher,
            "password": self.password,
            "access_keys": access_keys,
            "dns": self.server_config.extra_config.get("dns", ["8.8.8.8", "8.8.4.4"]),
            "timeout": self.server_config.extra_config.get("timeout", 300),
        }

        return template.render(**context)

    async def generate_user_config(self, user: User) -> dict[str, Any]:
        """Generate Shadowsocks user configuration."""
        # For Outline, each user gets a unique access key
        access_key = await self.generate_access_key(user)

        return {
            "id": str(user.id),
            "name": user.username,
            "password": access_key["password"],
            "port": access_key.get("port", self.server_config.port),
            "method": self.cipher,
            "accessUrl": access_key["access_url"]
        }

    async def generate_access_key(self, user: User) -> dict[str, Any]:
        """Generate unique access key for user."""
        # Generate user-specific password
        user_password = f"{self.password}:{user.id}"

        # Create access URL
        server = self.server_config.public_ip or self.server_config.domain or "localhost"
        auth = base64.b64encode(f"{self.cipher}:{user_password}".encode()).decode()
        access_url = f"ss://{auth}@{server}:{self.server_config.port}#{user.username}"

        return {
            "password": user_password,
            "port": self.server_config.port,
            "method": self.cipher,
            "access_url": access_url
        }

    async def generate_connection_link(self, user: User) -> str:
        """Generate Shadowsocks connection link."""
        access_key = await self.generate_access_key(user)
        return access_key["access_url"]

    async def validate_config(self, config: dict[str, Any]) -> bool:
        """Validate Shadowsocks configuration."""
        # Check cipher
        if self.cipher not in self.SUPPORTED_CIPHERS:
            return False

        # Check password
        if not self.password or len(self.password) < 16:
            return False

        return True

    def get_docker_image(self) -> str:
        """Get Shadowsocks Docker image."""
        # Use Outline server for better management
        if self.server_config.extra_config.get("use_outline", True):
            return "outlinewikipedia/shadowbox:stable"
        else:
            return "shadowsocks/shadowsocks-libev:latest"

    def get_docker_env(self) -> dict[str, str]:
        """Get environment variables."""
        env = {
            "METHOD": self.cipher,
            "PASSWORD": self.password,
            "TIMEOUT": str(self.server_config.extra_config.get("timeout", 300)),
        }

        if self.server_config.extra_config.get("use_outline", True):
            env.update({
                "SB_API_PORT": "8080",
                "SB_METRICS_PORT": "9090",
            })

        return env

    def get_docker_volumes(self) -> dict[str, str]:
        """Get volume mappings."""
        base_path = self.server_config.data_path

        if self.server_config.extra_config.get("use_outline", True):
            return {
                f"{base_path}/shadowbox/persisted-state": "/opt/outline/persisted-state",
                f"{base_path}/shadowbox/access.txt": "/opt/outline/access.txt",
            }
        else:
            return {
                f"{self.server_config.config_path}/shadowsocks": "/etc/shadowsocks",
            }

    def get_docker_ports(self) -> dict[str, str]:
        """Get port mappings."""
        ports = {
            f"{self.server_config.port}/tcp": f"{self.server_config.port}/tcp",
            f"{self.server_config.port}/udp": f"{self.server_config.port}/udp",
        }

        if self.server_config.extra_config.get("use_outline", True):
            # Add management ports
            ports.update({
                "8080/tcp": "8080/tcp",  # API
                "9090/tcp": "9090/tcp",  # Metrics
            })

        return ports

    def get_health_check(self) -> dict[str, Any]:
        """Get health check configuration."""
        if self.server_config.extra_config.get("use_outline", True):
            return {
                "test": ["CMD", "curl", "-f", "http://localhost:8080/api/"],
                "interval": "30s",
                "timeout": "10s",
                "retries": 3,
                "start_period": "30s"
            }
        else:
            return {
                "test": ["CMD", "ss-server", "-h"],
                "interval": "30s",
                "timeout": "10s",
                "retries": 3,
                "start_period": "10s"
            }

    def get_connection_instructions(self) -> str:
        """Get Shadowsocks-specific connection instructions."""
        return """
Shadowsocks Connection Instructions:

1. Install a Shadowsocks client:
   - Windows/Mac: Shadowsocks-Windows, ShadowsocksX-NG
   - iOS: Shadowrocket, Outline
   - Android: Shadowsocks, Outline

2. Copy the connection link (ss://) or scan the QR code

3. Import the configuration:
   - Click "Add Server" in your client
   - Paste the link or scan QR code
   - The client will auto-configure

4. Connect to start using the VPN!

Note: Shadowsocks is optimized for bypassing censorship
with minimal overhead and good performance.
"""

    async def _get_all_users(self):
        """Get all users for multi-user config."""
        from vpn.services.user_manager import UserManager
        manager = UserManager()
        users = await manager.list(protocol="shadowsocks")
        return users
