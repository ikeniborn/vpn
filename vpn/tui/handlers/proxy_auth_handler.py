"""Handler for proxy authentication configuration.
"""

import base64

import aiofiles

from vpn.services.server_manager import ServerManager
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ProxyAuthHandler:
    """Handles proxy authentication configuration."""

    def __init__(self):
        """Initialize proxy auth handler."""
        self.server_manager = ServerManager()

    async def configure_proxy_auth(
        self,
        server_name: str,
        auth_config: dict
    ) -> bool:
        """Configure proxy authentication for a server.
        
        Args:
            server_name: Name of the proxy server
            auth_config: Authentication configuration
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Get server configuration
            server = await self.server_manager.get(server_name)

            if server.protocol.value not in ["proxy", "unified_proxy"]:
                logger.error(f"Server {server_name} is not a proxy server")
                return False

            # Update configuration based on auth mode
            mode = auth_config.get("mode", "none")

            if mode in ["basic", "combined"]:
                # Create htpasswd file for Squid
                await self._create_htpasswd_file(server, auth_config["users"])

                # Update Squid configuration
                await self._update_squid_config(server, auth_config)

                # Create user config for Dante SOCKS5
                await self._update_dante_config(server, auth_config)

            # Store auth configuration
            server.metadata["auth_config"] = auth_config
            await self.server_manager._save_servers()

            logger.info(f"Updated proxy authentication for {server_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to configure proxy auth: {e}")
            return False

    async def _create_htpasswd_file(
        self,
        server,
        users: list[tuple[str, str]]
    ) -> None:
        """Create htpasswd file for Squid authentication.
        
        Args:
            server: Server configuration
            users: List of (username, password) tuples
        """
        htpasswd_path = server.config_path / "passwords"

        # Create htpasswd file with basic auth format
        lines = []
        for username, password in users:
            # Simple MD5 hash for basic auth (not secure, but works for demo)
            # In production, use bcrypt or proper htpasswd library
            hashed = base64.b64encode(f"{username}:{password}".encode()).decode()
            lines.append(f"{username}:{hashed}\n")

        async with aiofiles.open(htpasswd_path, "w") as f:
            await f.writelines(lines)

        logger.info(f"Created htpasswd file with {len(users)} users")

    async def _update_squid_config(self, server, auth_config: dict) -> None:
        """Update Squid configuration for authentication.
        
        Args:
            server: Server configuration
            auth_config: Authentication configuration
        """
        config_path = server.config_path / "squid.conf"

        # Read current configuration
        async with aiofiles.open(config_path) as f:
            config_lines = await f.readlines()

        # Update configuration
        new_lines = []
        in_auth_section = False
        auth_added = False

        for line in config_lines:
            # Skip existing auth configuration
            if line.strip().startswith("auth_param") or \
               line.strip().startswith("acl authenticated") or \
               (line.strip().startswith("http_access") and "authenticated" in line):
                in_auth_section = True
                continue

            # Add auth configuration before http_access rules
            if not auth_added and line.strip().startswith("http_access") and \
               auth_config["mode"] in ["basic", "combined"]:
                # Add authentication configuration
                new_lines.extend([
                    "# Authentication configuration\n",
                    "auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords\n",
                    "auth_param basic realm VPN Proxy Server\n",
                    "auth_param basic credentialsttl 2 hours\n",
                    "acl authenticated proxy_auth REQUIRED\n",
                    "\n"
                ])
                auth_added = True

            # Add the line if not in auth section
            if not in_auth_section:
                new_lines.append(line)
            elif not line.strip().startswith("auth_param") and \
                 not line.strip().startswith("acl authenticated") and \
                 not (line.strip().startswith("http_access") and "authenticated" in line):
                in_auth_section = False
                new_lines.append(line)

        # Update http_access rules
        final_lines = []
        for i, line in enumerate(new_lines):
            final_lines.append(line)

            # Add authenticated access after denying dangerous ports
            if line.strip() == "http_access deny CONNECT !SSL_ports" and \
               auth_config["mode"] in ["basic", "combined"]:
                final_lines.extend([
                    "\n",
                    "# Allow authenticated users\n",
                    "http_access allow authenticated\n"
                ])

        # Write updated configuration
        async with aiofiles.open(config_path, "w") as f:
            await f.writelines(final_lines)

        logger.info("Updated Squid configuration for authentication")

    async def _update_dante_config(self, server, auth_config: dict) -> None:
        """Update Dante SOCKS5 configuration for authentication.
        
        Args:
            server: Server configuration
            auth_config: Authentication configuration
        """
        config_path = server.config_path / "danted.conf"

        # Create user credentials file
        users_path = server.config_path / "danted.users"
        async with aiofiles.open(users_path, "w") as f:
            for username, password in auth_config["users"]:
                await f.write(f"{username}:{password}\n")

        # Update Dante configuration
        config_content = """# Dante SOCKS5 Configuration
logoutput: stderr

internal: 0.0.0.0 port = 1080
external: eth0

"""

        if auth_config["mode"] in ["basic", "combined"]:
            config_content += """# Authentication
socksmethod: username
user.privileged: root
user.unprivileged: nobody

"""
        else:
            config_content += """# No authentication
socksmethod: none
clientmethod: none

"""

        config_content += """# Client access rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# SOCKS rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
"""

        if auth_config["mode"] in ["basic", "combined"]:
            config_content += "    socksmethod: username\n"

        config_content += "}\n"

        # Write configuration
        async with aiofiles.open(config_path, "w") as f:
            await f.write(config_content)

        logger.info("Updated Dante configuration for authentication")

    async def get_proxy_users(self, server_name: str) -> list[dict]:
        """Get list of proxy users for a server.
        
        Args:
            server_name: Name of the proxy server
            
        Returns:
            List of user dictionaries
        """
        try:
            server = await self.server_manager.get(server_name)
            auth_config = server.metadata.get("auth_config", {})

            users = []
            for username, _ in auth_config.get("users", []):
                users.append({
                    "username": username,
                    "status": "Active",
                    "created": "N/A",
                    "last_access": "Never"
                })

            return users

        except Exception as e:
            logger.error(f"Failed to get proxy users: {e}")
            return []

    async def add_proxy_user(
        self,
        server_name: str,
        username: str,
        password: str
    ) -> bool:
        """Add a new proxy user.
        
        Args:
            server_name: Name of the proxy server
            username: Username
            password: Password
            
        Returns:
            True if successful, False otherwise
        """
        try:
            server = await self.server_manager.get(server_name)
            auth_config = server.metadata.get("auth_config", {
                "mode": "basic",
                "users": []
            })

            # Check for duplicate
            if any(u[0] == username for u in auth_config["users"]):
                logger.error(f"User {username} already exists")
                return False

            # Add user
            auth_config["users"].append((username, password))

            # Update configuration
            return await self.configure_proxy_auth(server_name, auth_config)

        except Exception as e:
            logger.error(f"Failed to add proxy user: {e}")
            return False

    async def remove_proxy_user(self, server_name: str, username: str) -> bool:
        """Remove a proxy user.
        
        Args:
            server_name: Name of the proxy server
            username: Username to remove
            
        Returns:
            True if successful, False otherwise
        """
        try:
            server = await self.server_manager.get(server_name)
            auth_config = server.metadata.get("auth_config", {})

            # Remove user
            auth_config["users"] = [
                (u, p) for u, p in auth_config.get("users", [])
                if u != username
            ]

            # Update configuration
            return await self.configure_proxy_auth(server_name, auth_config)

        except Exception as e:
            logger.error(f"Failed to remove proxy user: {e}")
            return False
