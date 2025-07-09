"""
VPN server management service.
"""

import asyncio
from pathlib import Path
from typing import Dict, List, Optional, Type

from vpn.core.config import get_config
from vpn.core.exceptions import (
    ServerError,
    ValidationError,
    NotFoundError,
    AlreadyExistsError
)
from vpn.core.models import ServerConfig, ServerStatus, ProtocolType
from vpn.protocols import (
    BaseProtocol,
    VLESSProtocol,
    ShadowsocksProtocol,
    WireGuardProtocol
)
from vpn.services.base import BaseService
from vpn.services.docker_manager import DockerManager
from vpn.services.network_manager import NetworkManager
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ServerManager(BaseService):
    """Manages VPN server lifecycle."""
    
    # Protocol registry
    PROTOCOLS: Dict[str, Type[BaseProtocol]] = {
        "vless": VLESSProtocol,
        "shadowsocks": ShadowsocksProtocol,
        "wireguard": WireGuardProtocol,
    }
    
    def __init__(self):
        """Initialize server manager."""
        super().__init__()
        self.docker = DockerManager()
        self.network = NetworkManager()
        self.config = get_config()
        self.servers: Dict[str, ServerConfig] = {}
    
    async def install(
        self,
        protocol: str | ProtocolType,
        port: int,
        name: Optional[str] = None,
        domain: Optional[str] = None,
        **extra_config
    ) -> ServerConfig:
        """
        Install a new VPN server.
        
        Args:
            protocol: VPN protocol to use
            port: Port number for the server
            name: Optional server name
            domain: Optional domain name
            **extra_config: Protocol-specific configuration
            
        Returns:
            Server configuration
        """
        # Validate protocol
        if isinstance(protocol, str):
            protocol = ProtocolType(protocol.lower())
        
        if protocol.value not in self.PROTOCOLS:
            raise ValidationError(
                f"Unsupported protocol: {protocol.value}",
                {"supported": list(self.PROTOCOLS.keys())}
            )
        
        # Generate server name
        if not name:
            name = f"{protocol.value}-server-{port}"
        
        # Check if server already exists
        if await self.exists(name):
            raise AlreadyExistsError(f"Server '{name}' already exists")
        
        # Create server configuration
        server_config = ServerConfig(
            name=name,
            protocol=protocol,
            port=port,
            domain=domain,
            public_ip=await self.network.get_public_ip(),
            status=ServerStatus.INSTALLING,
            config_path=self.config.config_path / "servers" / name,
            data_path=self.config.data_path / "servers" / name,
            extra_config=extra_config
        )
        
        try:
            # Create protocol instance
            protocol_impl = self.PROTOCOLS[protocol.value](server_config)
            
            # Pre-installation checks
            logger.info(f"Running pre-installation checks for {name}")
            checks = await protocol_impl.pre_install_check()
            
            if not all(checks.values()):
                failed_checks = [k for k, v in checks.items() if not v]
                raise ServerError(
                    "Pre-installation checks failed",
                    {"failed_checks": failed_checks}
                )
            
            # Create directories
            server_config.config_path.mkdir(parents=True, exist_ok=True)
            server_config.data_path.mkdir(parents=True, exist_ok=True)
            
            # Generate configuration
            logger.info(f"Generating configuration for {name}")
            template_path = Path(__file__).parent.parent / "templates" / protocol.value
            
            if protocol.value == "vless":
                template_file = template_path / "config.json.j2"
            elif protocol.value == "shadowsocks":
                template_file = template_path / "config.json.j2"
            elif protocol.value == "wireguard":
                template_file = template_path / "wg0.conf.j2"
            else:
                template_file = template_path / "config.j2"
            
            config_content = await protocol_impl.generate_server_config(template_file)
            
            # Write configuration
            config_file = server_config.config_path / "config.json"
            if protocol.value == "wireguard":
                config_file = server_config.config_path / "wg0.conf"
            
            config_file.write_text(config_content)
            
            # Setup firewall rules
            logger.info(f"Configuring firewall for {name}")
            for rule in protocol_impl.get_firewall_rules():
                await self.network.add_firewall_rule(**rule)
            
            # Create Docker container
            logger.info(f"Creating Docker container for {name}")
            container_config = {
                "image": protocol_impl.get_docker_image(),
                "name": f"vpn-{name}",
                "environment": protocol_impl.get_docker_env(),
                "volumes": protocol_impl.get_docker_volumes(),
                "ports": protocol_impl.get_docker_ports(),
                "restart_policy": {"Name": "unless-stopped"},
                "labels": {
                    "vpn.protocol": protocol.value,
                    "vpn.server": name,
                    "vpn.managed": "true"
                }
            }
            
            # Add health check if available
            health_check = protocol_impl.get_health_check()
            if health_check:
                container_config["healthcheck"] = health_check
            
            # Pull image
            await self.docker.pull_image(protocol_impl.get_docker_image())
            
            # Create and start container
            container_id = await self.docker.create_container(**container_config)
            await self.docker.start_container(container_id)
            
            # Wait for container to be healthy
            await self._wait_for_healthy(container_id, timeout=60)
            
            # Update server status
            server_config.status = ServerStatus.RUNNING
            server_config.container_id = container_id
            
            # Save server configuration
            self.servers[name] = server_config
            await self._save_servers()
            
            logger.info(f"Successfully installed {name}")
            return server_config
            
        except Exception as e:
            logger.error(f"Failed to install server {name}: {e}")
            # Cleanup on failure
            await self._cleanup_failed_install(server_config)
            raise ServerError(f"Failed to install server: {str(e)}")
    
    async def uninstall(self, name: str, force: bool = False) -> None:
        """
        Uninstall a VPN server.
        
        Args:
            name: Server name
            force: Force removal even if container is running
        """
        server = await self.get(name)
        
        try:
            # Stop container if running
            if server.container_id:
                if await self.docker.is_container_running(server.container_id):
                    logger.info(f"Stopping container for {name}")
                    await self.docker.stop_container(server.container_id)
                
                # Remove container
                logger.info(f"Removing container for {name}")
                await self.docker.remove_container(server.container_id, force=force)
            
            # Remove firewall rules
            protocol_impl = self.PROTOCOLS[server.protocol.value](server)
            for rule in protocol_impl.get_firewall_rules():
                await self.network.remove_firewall_rule(**rule)
            
            # Remove configuration files
            if server.config_path.exists():
                import shutil
                shutil.rmtree(server.config_path)
            
            if server.data_path.exists():
                import shutil
                shutil.rmtree(server.data_path)
            
            # Remove from servers list
            del self.servers[name]
            await self._save_servers()
            
            logger.info(f"Successfully uninstalled {name}")
            
        except Exception as e:
            logger.error(f"Failed to uninstall server {name}: {e}")
            raise ServerError(f"Failed to uninstall server: {str(e)}")
    
    async def start(self, name: str) -> None:
        """Start a VPN server."""
        server = await self.get(name)
        
        if not server.container_id:
            raise ServerError(f"Server {name} has no container")
        
        if server.status == ServerStatus.RUNNING:
            logger.info(f"Server {name} is already running")
            return
        
        await self.docker.start_container(server.container_id)
        server.status = ServerStatus.RUNNING
        await self._save_servers()
        
        logger.info(f"Started server {name}")
    
    async def stop(self, name: str) -> None:
        """Stop a VPN server."""
        server = await self.get(name)
        
        if not server.container_id:
            raise ServerError(f"Server {name} has no container")
        
        if server.status == ServerStatus.STOPPED:
            logger.info(f"Server {name} is already stopped")
            return
        
        await self.docker.stop_container(server.container_id)
        server.status = ServerStatus.STOPPED
        await self._save_servers()
        
        logger.info(f"Stopped server {name}")
    
    async def restart(self, name: str) -> None:
        """Restart a VPN server."""
        await self.stop(name)
        await asyncio.sleep(1)  # Brief pause
        await self.start(name)
    
    async def get(self, name: str) -> ServerConfig:
        """Get server configuration."""
        await self._load_servers()
        
        if name not in self.servers:
            raise NotFoundError(f"Server '{name}' not found")
        
        return self.servers[name]
    
    async def list(self, protocol: Optional[str] = None) -> List[ServerConfig]:
        """List all servers."""
        await self._load_servers()
        
        servers = list(self.servers.values())
        
        if protocol:
            servers = [s for s in servers if s.protocol.value == protocol]
        
        return servers
    
    async def exists(self, name: str) -> bool:
        """Check if server exists."""
        await self._load_servers()
        return name in self.servers
    
    async def get_status(self, name: str) -> ServerStatus:
        """Get current server status."""
        server = await self.get(name)
        
        if not server.container_id:
            return ServerStatus.ERROR
        
        # Check container status
        try:
            info = await self.docker.inspect_container(server.container_id)
            state = info.get("State", {})
            
            if state.get("Running"):
                # Check health if available
                health = state.get("Health", {})
                if health:
                    health_status = health.get("Status", "none")
                    if health_status == "healthy":
                        return ServerStatus.RUNNING
                    elif health_status == "unhealthy":
                        return ServerStatus.ERROR
                    else:
                        return ServerStatus.STARTING
                return ServerStatus.RUNNING
            elif state.get("Restarting"):
                return ServerStatus.RESTARTING
            else:
                return ServerStatus.STOPPED
                
        except Exception as e:
            logger.error(f"Failed to get status for {name}: {e}")
            return ServerStatus.ERROR
    
    async def get_logs(
        self,
        name: str,
        lines: int = 100,
        follow: bool = False
    ) -> str | asyncio.StreamReader:
        """Get server logs."""
        server = await self.get(name)
        
        if not server.container_id:
            raise ServerError(f"Server {name} has no container")
        
        return await self.docker.get_logs(
            server.container_id,
            lines=lines,
            follow=follow
        )
    
    async def update_config(self, name: str, **updates) -> ServerConfig:
        """Update server configuration."""
        server = await self.get(name)
        
        # Update configuration
        for key, value in updates.items():
            if hasattr(server, key):
                setattr(server, key, value)
            else:
                server.extra_config[key] = value
        
        # Save changes
        await self._save_servers()
        
        # Restart server to apply changes
        if server.status == ServerStatus.RUNNING:
            await self.restart(name)
        
        return server
    
    async def _wait_for_healthy(self, container_id: str, timeout: int = 60) -> None:
        """Wait for container to become healthy."""
        start_time = asyncio.get_event_loop().time()
        
        while True:
            elapsed = asyncio.get_event_loop().time() - start_time
            if elapsed > timeout:
                raise ServerError(f"Container failed to become healthy within {timeout}s")
            
            try:
                info = await self.docker.inspect_container(container_id)
                health = info.get("State", {}).get("Health", {})
                
                if not health:
                    # No health check, assume healthy if running
                    if info.get("State", {}).get("Running"):
                        return
                else:
                    status = health.get("Status", "none")
                    if status == "healthy":
                        return
                    elif status == "unhealthy":
                        raise ServerError("Container health check failed")
            
            except Exception as e:
                logger.warning(f"Error checking container health: {e}")
            
            await asyncio.sleep(2)
    
    async def _cleanup_failed_install(self, server_config: ServerConfig) -> None:
        """Clean up after failed installation."""
        try:
            # Remove container if exists
            if server_config.container_id:
                await self.docker.remove_container(
                    server_config.container_id,
                    force=True
                )
            
            # Remove directories
            if server_config.config_path.exists():
                import shutil
                shutil.rmtree(server_config.config_path)
            
            if server_config.data_path.exists():
                import shutil
                shutil.rmtree(server_config.data_path)
            
        except Exception as e:
            logger.error(f"Error during cleanup: {e}")
    
    async def _load_servers(self) -> None:
        """Load servers from persistent storage."""
        # TODO: Implement persistent storage
        # For now, servers are kept in memory
        pass
    
    async def _save_servers(self) -> None:
        """Save servers to persistent storage."""
        # TODO: Implement persistent storage
        # For now, servers are kept in memory
        pass