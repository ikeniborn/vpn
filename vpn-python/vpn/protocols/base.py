"""
Base protocol interface for VPN implementations.
"""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from vpn.core.models import User, ServerConfig


class ProtocolConfig(BaseModel):
    """Base configuration for protocol."""
    
    name: str
    version: str
    port: int
    transport: Optional[str] = None
    security: Optional[str] = None
    extra_settings: Dict[str, Any] = Field(default_factory=dict)


class ConnectionInfo(BaseModel):
    """Connection information for a user."""
    
    protocol: str
    server: str
    port: int
    user_id: str
    connection_string: str
    qr_code: Optional[str] = None
    instructions: Optional[str] = None


class BaseProtocol(ABC):
    """Abstract base class for VPN protocols."""
    
    def __init__(self, server_config: ServerConfig):
        """Initialize protocol with server configuration."""
        self.server_config = server_config
        self.name = self.__class__.__name__.replace("Protocol", "").lower()
    
    @abstractmethod
    async def generate_server_config(self, template_path: Path) -> str:
        """Generate server configuration from template."""
        pass
    
    @abstractmethod
    async def generate_user_config(self, user: User) -> Dict[str, Any]:
        """Generate user-specific configuration."""
        pass
    
    @abstractmethod
    async def generate_connection_link(self, user: User) -> str:
        """Generate connection link for user."""
        pass
    
    @abstractmethod
    async def validate_config(self, config: Dict[str, Any]) -> bool:
        """Validate protocol configuration."""
        pass
    
    @abstractmethod
    def get_docker_image(self) -> str:
        """Get Docker image for this protocol."""
        pass
    
    @abstractmethod
    def get_docker_env(self) -> Dict[str, str]:
        """Get environment variables for Docker container."""
        pass
    
    @abstractmethod
    def get_docker_volumes(self) -> Dict[str, str]:
        """Get volume mappings for Docker container."""
        pass
    
    @abstractmethod
    def get_docker_ports(self) -> Dict[str, str]:
        """Get port mappings for Docker container."""
        pass
    
    @abstractmethod
    def get_health_check(self) -> Dict[str, Any]:
        """Get health check configuration."""
        pass
    
    async def get_connection_info(self, user: User) -> ConnectionInfo:
        """Get complete connection information for user."""
        connection_link = await self.generate_connection_link(user)
        
        # Generate QR code
        from vpn.services.crypto import CryptoService
        crypto = CryptoService()
        qr_code = await crypto.generate_qr_code(connection_link)
        
        return ConnectionInfo(
            protocol=self.name,
            server=self.server_config.public_ip or self.server_config.domain or "localhost",
            port=self.server_config.port,
            user_id=str(user.id),
            connection_string=connection_link,
            qr_code=qr_code,
            instructions=self.get_connection_instructions()
        )
    
    def get_connection_instructions(self) -> str:
        """Get user-friendly connection instructions."""
        return f"""
1. Install a {self.name.upper()} compatible client
2. Copy the connection link or scan the QR code
3. Import the configuration into your client
4. Connect to the VPN server
"""
    
    def get_firewall_rules(self) -> List[Dict[str, Any]]:
        """Get firewall rules needed for this protocol."""
        return [
            {
                "chain": "INPUT",
                "protocol": "tcp",
                "port": self.server_config.port,
                "action": "ACCEPT",
                "comment": f"{self.name} VPN port"
            },
            {
                "chain": "INPUT",
                "protocol": "udp",
                "port": self.server_config.port,
                "action": "ACCEPT",
                "comment": f"{self.name} VPN port (UDP)"
            }
        ]
    
    async def pre_install_check(self) -> Dict[str, bool]:
        """Run pre-installation checks."""
        checks = {
            "port_available": await self._check_port_available(),
            "docker_running": await self._check_docker_running(),
            "resources_available": await self._check_resources(),
        }
        return checks
    
    async def _check_port_available(self) -> bool:
        """Check if the configured port is available."""
        from vpn.services.network_manager import NetworkManager
        network = NetworkManager()
        return await network.is_port_available(self.server_config.port)
    
    async def _check_docker_running(self) -> bool:
        """Check if Docker daemon is running."""
        from vpn.services.docker_manager import DockerManager
        docker = DockerManager()
        return await docker.is_docker_running()
    
    async def _check_resources(self) -> bool:
        """Check if system has enough resources."""
        import psutil
        
        # Check available memory (need at least 512MB free)
        memory = psutil.virtual_memory()
        if memory.available < 512 * 1024 * 1024:
            return False
        
        # Check disk space (need at least 1GB free)
        disk = psutil.disk_usage('/')
        if disk.free < 1024 * 1024 * 1024:
            return False
        
        return True