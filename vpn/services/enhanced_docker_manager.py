"""
Enhanced Docker manager with health checks and resilience patterns.
"""

import asyncio
from datetime import datetime
from typing import Any, Dict, List, Optional

import docker
from docker.errors import APIError, ContainerError, DockerException, NotFound
from docker.models.containers import Container

from vpn.core.exceptions import DockerError, DockerNotAvailableError
from vpn.core.models import DockerConfig, ServerStatus
from vpn.services.base_service import (
    EnhancedBaseService,
    ServiceHealth,
    ServiceStatus,
    with_retry,
    CircuitBreaker,
    ConnectionPool,
)
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class EnhancedDockerManager(EnhancedBaseService[Container]):
    """Enhanced Docker manager with resilience patterns."""
    
    def __init__(self):
        """Initialize enhanced Docker manager."""
        super().__init__(
            circuit_breaker=CircuitBreaker(
                failure_threshold=5,
                recovery_timeout=60,
                expected_exception=DockerError
            ),
            name="DockerManager"
        )
        
        self._client = None
        self._container_cache: Dict[str, Container] = {}
        self._stats_cache: Dict[str, Dict] = {}
        self._cache_ttl = 5  # seconds
        self._last_cache_update = {}
        
        # Docker client connection pool
        self._client_pool = ConnectionPool(
            factory=self._create_docker_client,
            max_size=3
        )
    
    async def _create_docker_client(self) -> docker.DockerClient:
        """Create new Docker client."""
        try:
            client = docker.from_env(timeout=self.settings.docker_timeout)
            # Test connection
            client.ping()
            return client
        except DockerException as e:
            self.logger.error(f"Failed to create Docker client: {e}")
            raise DockerNotAvailableError()
    
    @property
    def client(self) -> docker.DockerClient:
        """Get Docker client (lazy initialization)."""
        if self._client is None:
            try:
                self._client = docker.from_env(timeout=self.settings.docker_timeout)
                # Test connection
                self._client.ping()
            except DockerException as e:
                self.logger.error(f"Failed to connect to Docker: {e}")
                raise DockerNotAvailableError()
        return self._client
    
    async def health_check(self) -> ServiceHealth:
        """Perform health check on Docker service."""
        try:
            # Test Docker connectivity
            client = await self._get_client()
            version_info = client.version()
            
            # Get container statistics
            containers = client.containers.list(all=True)
            running_containers = len([c for c in containers if c.status == "running"])
            total_containers = len(containers)
            
            return ServiceHealth(
                service=self.name,
                status=ServiceStatus.HEALTHY,
                message=f"Docker operational. {running_containers}/{total_containers} containers running.",
                metrics={
                    "docker_version": version_info.get("Version", "unknown"),
                    "api_version": version_info.get("ApiVersion", "unknown"),
                    "total_containers": total_containers,
                    "running_containers": running_containers,
                    "cache_size": len(self._container_cache),
                    "stats_cache_size": len(self._stats_cache),
                    "circuit_breaker_state": self.circuit_breaker.state.value,
                    "failure_count": self.circuit_breaker.failure_count,
                }
            )
        
        except Exception as e:
            self.logger.error(f"Docker health check failed: {e}")
            return ServiceHealth(
                service=self.name,
                status=ServiceStatus.UNHEALTHY,
                message=f"Docker service unhealthy: {str(e)}",
                metrics={
                    "cache_size": len(self._container_cache),
                    "circuit_breaker_state": self.circuit_breaker.state.value,
                    "failure_count": self.circuit_breaker.failure_count,
                }
            )
    
    async def cleanup(self):
        """Cleanup Docker manager resources."""
        self.logger.info("Cleaning up DockerManager resources...")
        await self._client_pool.close_all()
        self._container_cache.clear()
        self._stats_cache.clear()
        self._last_cache_update.clear()
        
        if self._client:
            self._client.close()
            self._client = None
    
    async def reconnect(self):
        """Reconnect Docker client."""
        self.logger.info("Reconnecting DockerManager...")
        await self.cleanup()
        
        # Reset circuit breaker
        self.circuit_breaker.failure_count = 0
        self.circuit_breaker.state = self.circuit_breaker.CircuitBreakerState.CLOSED
    
    async def _get_client(self) -> docker.DockerClient:
        """Get Docker client with connection pooling."""
        try:
            return self.client
        except DockerNotAvailableError:
            # Try to reconnect
            await self.reconnect()
            return self.client
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def is_available(self) -> bool:
        """Check if Docker is available with retry."""
        try:
            return await self.circuit_breaker.call(self._is_available_impl)
        except Exception as e:
            self.logger.error(f"Docker availability check failed: {e}")
            return False
    
    async def _is_available_impl(self) -> bool:
        """Internal Docker availability check."""
        loop = asyncio.get_event_loop()
        client = await self._get_client()
        await loop.run_in_executor(None, client.ping)
        return True
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def get_version(self) -> Dict[str, Any]:
        """Get Docker version information with retry."""
        try:
            return await self.circuit_breaker.call(self._get_version_impl)
        except Exception as e:
            self.logger.error(f"Failed to get Docker version: {e}")
            raise DockerError("Failed to get Docker version")
    
    async def _get_version_impl(self) -> Dict[str, Any]:
        """Internal get version implementation."""
        loop = asyncio.get_event_loop()
        client = await self._get_client()
        return await loop.run_in_executor(None, client.version)
    
    # Container lifecycle management with resilience
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def create_container(
        self,
        name: str,
        config: DockerConfig,
        **kwargs
    ) -> Container:
        """Create a new container with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._create_container_impl,
                name=name,
                config=config,
                **kwargs
            )
        except Exception as e:
            self.logger.error(f"Failed to create container {name}: {e}")
            raise
    
    async def _create_container_impl(
        self,
        name: str,
        config: DockerConfig,
        **kwargs
    ) -> Container:
        """Internal container creation implementation."""
        loop = asyncio.get_event_loop()
        client = await self._get_client()
        
        # Prepare container configuration
        container_config = {
            "image": f"{config.image}:{config.tag}",
            "name": config.container_name or name,
            "environment": config.environment,
            "volumes": self._parse_volumes(config.volumes),
            "ports": self._parse_ports(config.ports),
            "restart_policy": {"Name": config.restart_policy},
            "detach": True,
            **kwargs
        }
        
        # Add networks if specified
        if config.networks:
            container_config["network"] = config.networks[0]
        
        # Create container
        container = await loop.run_in_executor(
            None,
            lambda: client.containers.create(**container_config)
        )
        
        # Cache container
        self._container_cache[container.id] = container
        
        self.logger.info(f"Created container: {container.name} ({container.id})")
        return container
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def start_container(self, container_id: str) -> bool:
        """Start a container with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._start_container_impl,
                container_id
            )
        except Exception as e:
            self.logger.error(f"Failed to start container {container_id}: {e}")
            return False
    
    async def _start_container_impl(self, container_id: str) -> bool:
        """Internal start container implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, container.start)
        
        # Update cache
        self._invalidate_cache(container_id)
        
        self.logger.info(f"Started container: {container_id}")
        return True
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def stop_container(
        self,
        container_id: str,
        timeout: int = 10
    ) -> bool:
        """Stop a container with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._stop_container_impl,
                container_id,
                timeout
            )
        except Exception as e:
            self.logger.error(f"Failed to stop container {container_id}: {e}")
            return False
    
    async def _stop_container_impl(self, container_id: str, timeout: int) -> bool:
        """Internal stop container implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, container.stop, timeout)
        
        # Update cache
        self._invalidate_cache(container_id)
        
        self.logger.info(f"Stopped container: {container_id}")
        return True
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def restart_container(
        self,
        container_id: str,
        timeout: int = 10
    ) -> bool:
        """Restart a container with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._restart_container_impl,
                container_id,
                timeout
            )
        except Exception as e:
            self.logger.error(f"Failed to restart container {container_id}: {e}")
            return False
    
    async def _restart_container_impl(self, container_id: str, timeout: int) -> bool:
        """Internal restart container implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, container.restart, timeout)
        
        # Update cache
        self._invalidate_cache(container_id)
        
        self.logger.info(f"Restarted container: {container_id}")
        return True
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def remove_container(
        self,
        container_id: str,
        force: bool = False,
        volumes: bool = True
    ) -> bool:
        """Remove a container with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._remove_container_impl,
                container_id,
                force,
                volumes
            )
        except Exception as e:
            self.logger.error(f"Failed to remove container {container_id}: {e}")
            return False
    
    async def _remove_container_impl(
        self,
        container_id: str,
        force: bool,
        volumes: bool
    ) -> bool:
        """Internal remove container implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            container.remove,
            volumes,
            force
        )
        
        # Remove from cache
        if container_id in self._container_cache:
            del self._container_cache[container_id]
        self._invalidate_cache(container_id)
        
        self.logger.info(f"Removed container: {container_id}")
        return True
    
    # Container information with caching
    
    async def get_container_status(self, container_id: str) -> ServerStatus:
        """Get container status with error handling."""
        try:
            container = await self._get_container(container_id)
            status = container.status.lower()
            
            status_map = {
                "created": ServerStatus.STOPPED,
                "restarting": ServerStatus.STARTING,
                "running": ServerStatus.RUNNING,
                "removing": ServerStatus.STOPPING,
                "paused": ServerStatus.STOPPED,
                "exited": ServerStatus.STOPPED,
                "dead": ServerStatus.ERROR,
            }
            
            return status_map.get(status, ServerStatus.ERROR)
            
        except NotFound:
            return ServerStatus.STOPPED
        except Exception:
            return ServerStatus.ERROR
    
    async def get_container_info(self, container_id: str) -> Dict[str, Any]:
        """Get detailed container information with retry."""
        try:
            return await self.circuit_breaker.call(
                self._get_container_info_impl,
                container_id
            )
        except Exception as e:
            self.logger.error(f"Failed to get container info: {e}")
            raise DockerError(f"Failed to get container info: {e}")
    
    async def _get_container_info_impl(self, container_id: str) -> Dict[str, Any]:
        """Internal get container info implementation."""
        container = await self._get_container(container_id)
        container.reload()
        
        return {
            "id": container.id,
            "name": container.name,
            "status": container.status,
            "image": container.image.tags[0] if container.image.tags else "unknown",
            "created": container.attrs["Created"],
            "ports": container.ports,
            "networks": list(container.attrs["NetworkSettings"]["Networks"].keys()),
        }
    
    async def get_container_stats(
        self,
        container_id: str,
        stream: bool = False
    ) -> Dict[str, Any]:
        """Get container resource statistics with caching."""
        # Check cache for non-streaming requests
        if not stream and container_id in self._stats_cache:
            cache_time = self._last_cache_update.get(container_id, 0)
            if datetime.now().timestamp() - cache_time < self._cache_ttl:
                return self._stats_cache[container_id]
        
        try:
            return await self.circuit_breaker.call(
                self._get_container_stats_impl,
                container_id,
                stream
            )
        except Exception as e:
            self.logger.error(f"Failed to get container stats: {e}")
            return {}
    
    async def _get_container_stats_impl(
        self,
        container_id: str,
        stream: bool
    ) -> Dict[str, Any]:
        """Internal get container stats implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        stats = await loop.run_in_executor(
            None,
            container.stats,
            stream
        )
        
        if not stream:
            # Parse stats
            parsed_stats = self._parse_stats(stats)
            
            # Update cache
            self._stats_cache[container_id] = parsed_stats
            self._last_cache_update[container_id] = datetime.now().timestamp()
            
            return parsed_stats
        else:
            # Return generator for streaming
            return stats
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def get_container_logs(
        self,
        container_id: str,
        tail: int = 100,
        follow: bool = False
    ) -> str:
        """Get container logs with retry."""
        try:
            return await self.circuit_breaker.call(
                self._get_container_logs_impl,
                container_id,
                tail,
                follow
            )
        except Exception as e:
            self.logger.error(f"Failed to get container logs: {e}")
            return ""
    
    async def _get_container_logs_impl(
        self,
        container_id: str,
        tail: int,
        follow: bool
    ) -> str:
        """Internal get container logs implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        logs = await loop.run_in_executor(
            None,
            container.logs,
            True,  # stdout
            True,  # stderr
            follow,
            tail
        )
        
        if isinstance(logs, bytes):
            return logs.decode('utf-8', errors='replace')
        else:
            # Generator for streaming logs
            return logs
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def execute_command(
        self,
        container_id: str,
        command: List[str],
        privileged: bool = False,
        user: Optional[str] = None
    ) -> str:
        """Execute command in container with retry."""
        try:
            return await self.circuit_breaker.call(
                self._execute_command_impl,
                container_id,
                command,
                privileged,
                user
            )
        except Exception as e:
            self.logger.error(f"Failed to execute command: {e}")
            raise DockerError(f"Command execution failed: {e}")
    
    async def _execute_command_impl(
        self,
        container_id: str,
        command: List[str],
        privileged: bool,
        user: Optional[str]
    ) -> str:
        """Internal execute command implementation."""
        container = await self._get_container(container_id)
        
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            container.exec_run,
            command,
            True,  # stdout
            True,  # stderr
            False,  # stdin
            False,  # tty
            privileged,
            user
        )
        
        exit_code, output = result
        
        if exit_code != 0:
            self.logger.warning(f"Command exited with code {exit_code}: {command}")
        
        if isinstance(output, bytes):
            return output.decode('utf-8', errors='replace')
        return output
    
    async def list_containers(
        self,
        all: bool = True,
        filters: Optional[Dict] = None
    ) -> List[Container]:
        """List containers with retry."""
        try:
            return await self.circuit_breaker.call(
                self._list_containers_impl,
                all,
                filters
            )
        except Exception as e:
            self.logger.error(f"Failed to list containers: {e}")
            return []
    
    async def _list_containers_impl(
        self,
        all: bool,
        filters: Optional[Dict]
    ) -> List[Container]:
        """Internal list containers implementation."""
        loop = asyncio.get_event_loop()
        client = await self._get_client()
        return await loop.run_in_executor(
            None,
            client.containers.list,
            all,
            filters
        )
    
    # Health monitoring
    
    async def health_check_container(self, container_id: str) -> bool:
        """Check container health with error handling."""
        try:
            return await self.circuit_breaker.call(
                self._health_check_container_impl,
                container_id
            )
        except Exception:
            return False
    
    async def _health_check_container_impl(self, container_id: str) -> bool:
        """Internal container health check implementation."""
        container = await self._get_container(container_id)
        
        # Check if container is running
        if container.status != "running":
            return False
        
        # Check health status if available
        health = container.attrs.get("State", {}).get("Health")
        if health:
            return health.get("Status") == "healthy"
        
        # Default to True if running and no health check
        return True
    
    # Private methods
    
    async def _get_container(self, container_id: str) -> Container:
        """Get container by ID with caching and error handling."""
        if container_id in self._container_cache:
            try:
                # Refresh container object
                self._container_cache[container_id].reload()
                return self._container_cache[container_id]
            except Exception:
                # Remove stale cache entry
                del self._container_cache[container_id]
        
        try:
            loop = asyncio.get_event_loop()
            client = await self._get_client()
            container = await loop.run_in_executor(
                None,
                client.containers.get,
                container_id
            )
            
            self._container_cache[container_id] = container
            return container
            
        except NotFound:
            raise DockerError(f"Container not found: {container_id}")
    
    def _parse_volumes(self, volumes: List[str]) -> Dict[str, Dict]:
        """Parse volume configuration."""
        parsed = {}
        
        for volume in volumes:
            parts = volume.split(":")
            if len(parts) >= 2:
                host_path = parts[0]
                container_path = parts[1]
                mode = parts[2] if len(parts) > 2 else "rw"
                
                parsed[host_path] = {
                    "bind": container_path,
                    "mode": mode
                }
        
        return parsed
    
    def _parse_ports(self, ports: Dict[str, int]) -> Dict[str, Any]:
        """Parse port configuration."""
        parsed = {}
        
        for container_port, host_port in ports.items():
            # Format: "8080/tcp": 8080
            if "/" not in container_port:
                container_port = f"{container_port}/tcp"
            
            parsed[container_port] = host_port
        
        return parsed
    
    def _parse_stats(self, stats: Dict) -> Dict[str, Any]:
        """Parse container statistics."""
        try:
            # CPU usage
            cpu_delta = stats["cpu_stats"]["cpu_usage"]["total_usage"] - \
                       stats["precpu_stats"]["cpu_usage"]["total_usage"]
            system_delta = stats["cpu_stats"]["system_cpu_usage"] - \
                          stats["precpu_stats"]["system_cpu_usage"]
            cpu_percent = (cpu_delta / system_delta) * 100.0 if system_delta > 0 else 0.0
            
            # Memory usage
            memory_usage = stats["memory_stats"]["usage"]
            memory_limit = stats["memory_stats"]["limit"]
            memory_percent = (memory_usage / memory_limit) * 100.0 if memory_limit > 0 else 0.0
            
            # Network I/O
            network_rx = 0
            network_tx = 0
            for interface, data in stats.get("networks", {}).items():
                network_rx += data.get("rx_bytes", 0)
                network_tx += data.get("tx_bytes", 0)
            
            return {
                "cpu_percent": round(cpu_percent, 2),
                "memory_usage_mb": round(memory_usage / (1024 * 1024), 2),
                "memory_percent": round(memory_percent, 2),
                "network_rx_mb": round(network_rx / (1024 * 1024), 2),
                "network_tx_mb": round(network_tx / (1024 * 1024), 2),
            }
            
        except Exception as e:
            self.logger.error(f"Failed to parse stats: {e}")
            return {}
    
    def _invalidate_cache(self, container_id: str):
        """Invalidate cached data for container."""
        if container_id in self._stats_cache:
            del self._stats_cache[container_id]
        if container_id in self._last_cache_update:
            del self._last_cache_update[container_id]
        # Keep container cache but force reload on next access