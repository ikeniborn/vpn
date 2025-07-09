"""
WireGuard protocol implementation.
"""

import ipaddress
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from vpn.core.models import User, ServerConfig
from vpn.protocols.base import BaseProtocol


class WireGuardProtocol(BaseProtocol):
    """WireGuard protocol implementation."""
    
    def __init__(self, server_config: ServerConfig):
        """Initialize WireGuard protocol."""
        super().__init__(server_config)
        self.interface = self.server_config.extra_config.get("interface", "wg0")
        self.network = self.server_config.extra_config.get("network", "10.0.0.0/24")
        self.dns = self.server_config.extra_config.get("dns", ["1.1.1.1", "1.0.0.1"])
    
    async def generate_server_config(self, template_path: Path) -> str:
        """Generate WireGuard server configuration."""
        from jinja2 import Environment, FileSystemLoader
        
        env = Environment(
            loader=FileSystemLoader(template_path.parent),
            trim_blocks=True,
            lstrip_blocks=True
        )
        
        template = env.get_template(template_path.name)
        
        # Get or generate server keys
        server_private_key = self.server_config.extra_config.get("private_key")
        if not server_private_key:
            keys = await self.generate_keypair()
            server_private_key = keys["private_key"]
            self.server_config.extra_config["private_key"] = server_private_key
            self.server_config.extra_config["public_key"] = keys["public_key"]
        
        # Get all peer configurations
        peers = await self._get_peer_configs()
        
        context = {
            "server": self.server_config,
            "interface": self.interface,
            "private_key": server_private_key,
            "address": self._get_server_address(),
            "port": self.server_config.port,
            "peers": peers,
            "post_up": self._get_post_up_rules(),
            "post_down": self._get_post_down_rules(),
        }
        
        return template.render(**context)
    
    async def generate_user_config(self, user: User) -> Dict[str, Any]:
        """Generate WireGuard peer configuration."""
        # Generate keys for user if not exists
        if not user.keys.private_key:
            keys = await self.generate_keypair()
            user.keys.private_key = keys["private_key"]
            user.keys.public_key = keys["public_key"]
        
        # Allocate IP address for user
        client_ip = await self._allocate_client_ip(user)
        
        return {
            "public_key": user.keys.public_key,
            "preshared_key": await self.generate_preshared_key(),
            "allowed_ips": [f"{client_ip}/32"],
            "client_config": {
                "address": f"{client_ip}/24",
                "private_key": user.keys.private_key,
                "dns": self.dns,
                "mtu": 1420,
            }
        }
    
    async def generate_connection_link(self, user: User) -> str:
        """Generate WireGuard configuration for user."""
        # WireGuard doesn't use URLs, generate config file content
        config = await self.generate_user_config(user)
        server_public_key = self.server_config.extra_config.get("public_key")
        
        if not server_public_key:
            raise ValueError("Server public key not found")
        
        server = self.server_config.public_ip or self.server_config.domain or "localhost"
        
        # Generate configuration file content
        client_config = f"""[Interface]
PrivateKey = {config['client_config']['private_key']}
Address = {config['client_config']['address']}
DNS = {', '.join(self.dns)}
MTU = {config['client_config']['mtu']}

[Peer]
PublicKey = {server_public_key}
PresharedKey = {config['preshared_key']}
Endpoint = {server}:{self.server_config.port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
        
        # Encode as base64 for easy sharing
        import base64
        encoded = base64.b64encode(client_config.encode()).decode()
        
        # Return a custom URL scheme for WireGuard
        return f"wireguard://{encoded}#{user.username}"
    
    async def validate_config(self, config: Dict[str, Any]) -> bool:
        """Validate WireGuard configuration."""
        # Check network configuration
        try:
            ipaddress.ip_network(self.network)
        except ValueError:
            return False
        
        # Check if WireGuard tools are available
        try:
            subprocess.run(["wg", "--version"], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False
        
        return True
    
    def get_docker_image(self) -> str:
        """Get WireGuard Docker image."""
        return "linuxserver/wireguard:latest"
    
    def get_docker_env(self) -> Dict[str, str]:
        """Get environment variables."""
        return {
            "PUID": "1000",
            "PGID": "1000",
            "TZ": "UTC",
            "SERVERURL": self.server_config.domain or self.server_config.public_ip or "",
            "SERVERPORT": str(self.server_config.port),
            "PEERS": "50",  # Max number of peers
            "PEERDNS": ",".join(self.dns),
            "INTERNAL_SUBNET": self.network,
            "ALLOWEDIPS": "0.0.0.0/0",
        }
    
    def get_docker_volumes(self) -> Dict[str, str]:
        """Get volume mappings."""
        return {
            f"{self.server_config.config_path}/wireguard": "/config",
            "/lib/modules": "/lib/modules:ro",
        }
    
    def get_docker_ports(self) -> Dict[str, str]:
        """Get port mappings."""
        return {
            f"{self.server_config.port}/udp": f"{self.server_config.port}/udp",
        }
    
    def get_health_check(self) -> Dict[str, Any]:
        """Get health check configuration."""
        return {
            "test": ["CMD", "wg", "show"],
            "interval": "30s",
            "timeout": "10s",
            "retries": 3,
            "start_period": "30s"
        }
    
    def get_connection_instructions(self) -> str:
        """Get WireGuard-specific connection instructions."""
        return """
WireGuard Connection Instructions:

1. Install WireGuard client:
   - Windows/Mac/Linux: Official WireGuard app
   - iOS/Android: WireGuard from App Store/Play Store

2. Import configuration:
   - Save the configuration to a .conf file
   - Or scan the QR code in the mobile app
   
3. Activate the tunnel:
   - Click "Activate" in the WireGuard app
   - The connection should establish immediately

4. Verify connection:
   - Check that the status shows "Active"
   - Your traffic is now encrypted through WireGuard

Note: WireGuard offers excellent performance with modern cryptography
and is ideal for both mobile and desktop use.
"""
    
    async def generate_keypair(self) -> Dict[str, str]:
        """Generate WireGuard keypair."""
        # Generate private key
        private_key_result = subprocess.run(
            ["wg", "genkey"],
            capture_output=True,
            text=True,
            check=True
        )
        private_key = private_key_result.stdout.strip()
        
        # Derive public key
        public_key_result = subprocess.run(
            ["wg", "pubkey"],
            input=private_key,
            capture_output=True,
            text=True,
            check=True
        )
        public_key = public_key_result.stdout.strip()
        
        return {
            "private_key": private_key,
            "public_key": public_key
        }
    
    async def generate_preshared_key(self) -> str:
        """Generate WireGuard preshared key."""
        result = subprocess.run(
            ["wg", "genpsk"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    
    def _get_server_address(self) -> str:
        """Get server address within the network."""
        network = ipaddress.ip_network(self.network)
        # Server typically uses .1 address
        return str(list(network.hosts())[0])
    
    async def _allocate_client_ip(self, user: User) -> str:
        """Allocate IP address for client."""
        network = ipaddress.ip_network(self.network)
        hosts = list(network.hosts())
        
        # Skip first IP (server)
        # Use user index or ID to generate consistent IP
        user_index = abs(hash(str(user.id))) % (len(hosts) - 1) + 1
        
        return str(hosts[user_index])
    
    async def _get_peer_configs(self) -> List[Dict[str, Any]]:
        """Get all peer configurations."""
        from vpn.services.user_manager import UserManager
        manager = UserManager()
        users = await manager.list(protocol="wireguard")
        
        peers = []
        for user in users:
            if user.keys.public_key:
                config = await self.generate_user_config(user)
                peers.append({
                    "name": user.username,
                    "public_key": config["public_key"],
                    "preshared_key": config["preshared_key"],
                    "allowed_ips": config["allowed_ips"],
                })
        
        return peers
    
    def _get_post_up_rules(self) -> List[str]:
        """Get iptables rules for PostUp."""
        return [
            f"iptables -A FORWARD -i {self.interface} -j ACCEPT",
            f"iptables -A FORWARD -o {self.interface} -j ACCEPT",
            f"iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE",
        ]
    
    def _get_post_down_rules(self) -> List[str]:
        """Get iptables rules for PostDown."""
        return [
            f"iptables -D FORWARD -i {self.interface} -j ACCEPT",
            f"iptables -D FORWARD -o {self.interface} -j ACCEPT",
            f"iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE",
        ]