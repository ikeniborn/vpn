"""
VLESS protocol implementation with Reality support.
"""

import json
import uuid
from pathlib import Path
from typing import Any, Dict

from vpn.core.models import User, ServerConfig
from vpn.protocols.base import BaseProtocol


class VLESSProtocol(BaseProtocol):
    """VLESS+Reality protocol implementation."""
    
    def __init__(self, server_config: ServerConfig):
        """Initialize VLESS protocol."""
        super().__init__(server_config)
        self.reality_config = self.server_config.extra_config.get("reality", {})
    
    async def generate_server_config(self, template_path: Path) -> str:
        """Generate Xray server configuration."""
        from jinja2 import Environment, FileSystemLoader
        
        # Setup Jinja2 environment
        env = Environment(
            loader=FileSystemLoader(template_path.parent),
            trim_blocks=True,
            lstrip_blocks=True
        )
        
        template = env.get_template(template_path.name)
        
        # Prepare template context
        context = {
            "server": self.server_config,
            "protocol": "vless",
            "security": "reality",
            "reality": {
                "dest": self.reality_config.get("dest", "www.google.com:443"),
                "server_names": self.reality_config.get("server_names", ["www.google.com"]),
                "private_key": self.reality_config.get("private_key", ""),
                "short_ids": self.reality_config.get("short_ids", [""]),
            },
            "transport": self.server_config.extra_config.get("transport", "tcp"),
        }
        
        return template.render(**context)
    
    async def generate_user_config(self, user: User) -> Dict[str, Any]:
        """Generate VLESS user configuration."""
        return {
            "id": str(user.id),
            "email": user.email or f"{user.username}@vpn.local",
            "level": 0,
            "flow": "xtls-rprx-vision" if self.server_config.extra_config.get("transport") == "tcp" else None
        }
    
    async def generate_connection_link(self, user: User) -> str:
        """Generate VLESS connection link."""
        # Base VLESS link format: vless://uuid@server:port?params#name
        
        params = {
            "type": self.server_config.extra_config.get("transport", "tcp"),
            "security": "reality",
            "pbk": self.reality_config.get("public_key", ""),
            "fp": self.reality_config.get("fingerprint", "chrome"),
            "sni": self.reality_config.get("server_names", ["www.google.com"])[0],
            "sid": self.reality_config.get("short_ids", [""])[0],
        }
        
        # Add flow for TCP transport
        if params["type"] == "tcp":
            params["flow"] = "xtls-rprx-vision"
        
        # Build query string
        query_string = "&".join(f"{k}={v}" for k, v in params.items() if v)
        
        # Build connection link
        server = self.server_config.public_ip or self.server_config.domain or "localhost"
        link = f"vless://{user.id}@{server}:{self.server_config.port}?{query_string}#{user.username}"
        
        return link
    
    async def validate_config(self, config: Dict[str, Any]) -> bool:
        """Validate VLESS configuration."""
        required_fields = ["reality", "transport"]
        for field in required_fields:
            if field not in self.server_config.extra_config:
                return False
        
        # Validate Reality config
        reality = self.server_config.extra_config.get("reality", {})
        if not reality.get("private_key") or not reality.get("public_key"):
            return False
        
        return True
    
    def get_docker_image(self) -> str:
        """Get Xray Docker image."""
        return "teddysun/xray:latest"
    
    def get_docker_env(self) -> Dict[str, str]:
        """Get environment variables."""
        return {
            "XRAY_CONFIG": "/etc/xray/config.json"
        }
    
    def get_docker_volumes(self) -> Dict[str, str]:
        """Get volume mappings."""
        return {
            f"{self.server_config.config_path}/xray": "/etc/xray",
            f"{self.server_config.data_path}/xray/logs": "/var/log/xray"
        }
    
    def get_docker_ports(self) -> Dict[str, str]:
        """Get port mappings."""
        return {
            f"{self.server_config.port}/tcp": f"{self.server_config.port}/tcp",
            f"{self.server_config.port}/udp": f"{self.server_config.port}/udp"
        }
    
    def get_health_check(self) -> Dict[str, Any]:
        """Get health check configuration."""
        return {
            "test": ["CMD", "xray", "api", "stats", "--server=127.0.0.1:10085"],
            "interval": "30s",
            "timeout": "10s",
            "retries": 3,
            "start_period": "10s"
        }
    
    def get_connection_instructions(self) -> str:
        """Get VLESS-specific connection instructions."""
        return """
VLESS+Reality Connection Instructions:

1. Install a VLESS-compatible client:
   - Windows/Mac: v2rayN, Qv2ray
   - iOS: Shadowrocket, Quantumult X
   - Android: v2rayNG, SagerNet

2. Copy the connection link or scan the QR code

3. Import the configuration:
   - Most clients support importing via link or QR code
   - Some clients may require manual configuration

4. Connect and enjoy secure browsing!

Note: VLESS+Reality provides strong encryption and obfuscation,
making your VPN traffic appear as regular HTTPS traffic.
"""
    
    async def generate_reality_keys(self) -> Dict[str, str]:
        """Generate Reality key pair."""
        import subprocess
        
        # Use xray to generate keys
        result = subprocess.run(
            ["xray", "x25519"],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            # Fallback to Python implementation
            from vpn.services.crypto import CryptoService
            crypto = CryptoService()
            private_key = await crypto.generate_private_key()
            public_key = await crypto.derive_public_key(private_key)
            
            return {
                "private_key": private_key,
                "public_key": public_key
            }
        
        # Parse xray output
        lines = result.stdout.strip().split('\n')
        private_key = lines[0].split(': ')[1]
        public_key = lines[1].split(': ')[1]
        
        return {
            "private_key": private_key,
            "public_key": public_key
        }