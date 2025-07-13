"""Docker integration service.
"""

import asyncio
from datetime import datetime
from typing import Any

import docker
from docker.errors import DockerException, NotFound
from docker.models.containers import Container

from vpn.core.exceptions import DockerError, DockerNotAvailableError
from vpn.core.models import DockerConfig, ServerStatus
from vpn.services.base import BaseService, EventEmitter
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class DockerManager(BaseService, EventEmitter):
    """Service for Docker container management."""

    def __init__(self):
        """Initialize Docker manager."""
        super().__init__()
        self._client = None
        self._container_cache: dict[str, Container] = {}
        self._stats_cache: dict[str, dict] = {}
        self._cache_ttl = 5  # seconds
        self._last_cache_update = {}

    @property
    def client(self) -> docker.DockerClient:
        """Get Docker client (lazy initialization)."""
        if self._client is None:
            try:
                self._client = docker.from_env(timeout=self.settings.docker_timeout)
                # Test connection
                self._client.ping()
            except DockerException as e:
                logger.error(f"Failed to connect to Docker: {e}")
                raise DockerNotAvailableError()
        return self._client

    async def is_available(self) -> bool:
        """Check if Docker is available."""
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self.client.ping)
            return True
        except Exception:
            return False

    async def get_version(self) -> dict[str, Any]:
        """Get Docker version information."""
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(None, self.client.version)
        except Exception as e:
            logger.error(f"Failed to get Docker version: {e}")
            raise DockerError("Failed to get Docker version")

    # Container lifecycle management

    async def create_container(
        self,
        name: str,
        config: DockerConfig,
        **kwargs
    ) -> Container:
        """Create a new container.
        
        Args:
            name: Container name
            config: Docker configuration
            **kwargs: Additional container options
            
        Returns:
            Created container
        """
        try:
            loop = asyncio.get_event_loop()

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
                lambda: self.client.containers.create(**container_config)
            )

            # Cache container
            self._container_cache[container.id] = container

            # Emit event
            await self.emit("container.created", {
                "id": container.id,
                "name": container.name,
                "image": config.image
            })

            logger.info(f"Created container: {container.name}")
            return container

        except Exception as e:
            logger.error(f"Failed to create container: {e}")
            raise DockerError(f"Container creation failed: {e}")

    async def start_container(self, container_id: str) -> bool:
        """Start a container."""
        try:
            container = await self._get_container(container_id)

            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, container.start)

            # Update cache
            self._invalidate_cache(container_id)

            # Emit event
            await self.emit("container.started", {"id": container_id})

            logger.info(f"Started container: {container_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to start container: {e}")
            return False

    async def stop_container(
        self,
        container_id: str,
        timeout: int = 10
    ) -> bool:
        """Stop a container."""
        try:
            container = await self._get_container(container_id)

            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, container.stop, timeout)

            # Update cache
            self._invalidate_cache(container_id)

            # Emit event
            await self.emit("container.stopped", {"id": container_id})

            logger.info(f"Stopped container: {container_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to stop container: {e}")
            return False

    async def restart_container(
        self,
        container_id: str,
        timeout: int = 10
    ) -> bool:
        """Restart a container."""
        try:
            container = await self._get_container(container_id)

            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, container.restart, timeout)

            # Update cache
            self._invalidate_cache(container_id)

            # Emit event
            await self.emit("container.restarted", {"id": container_id})

            logger.info(f"Restarted container: {container_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to restart container: {e}")
            return False

    async def remove_container(
        self,
        container_id: str,
        force: bool = False,
        volumes: bool = True
    ) -> bool:
        """Remove a container."""
        try:
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

            # Emit event
            await self.emit("container.removed", {"id": container_id})

            logger.info(f"Removed container: {container_id}")
            return True

        except Exception as e:
            logger.error(f"Failed to remove container: {e}")
            return False

    # Container information

    async def get_container_status(self, container_id: str) -> ServerStatus:
        """Get container status."""
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

    async def get_container_info(self, container_id: str) -> dict[str, Any]:
        """Get detailed container information."""
        try:
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

        except Exception as e:
            logger.error(f"Failed to get container info: {e}")
            raise DockerError(f"Failed to get container info: {e}")

    async def get_container_stats(
        self,
        container_id: str,
        stream: bool = False
    ) -> dict[str, Any]:
        """Get container resource statistics."""
        # Check cache
        if not stream and container_id in self._stats_cache:
            cache_time = self._last_cache_update.get(container_id, 0)
            if datetime.now().timestamp() - cache_time < self._cache_ttl:
                return self._stats_cache[container_id]

        try:
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

        except Exception as e:
            logger.error(f"Failed to get container stats: {e}")
            return {}

    async def get_container_logs(
        self,
        container_id: str,
        tail: int = 100,
        follow: bool = False
    ) -> str:
        """Get container logs."""
        try:
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

        except Exception as e:
            logger.error(f"Failed to get container logs: {e}")
            return ""

    # Container operations

    async def execute_command(
        self,
        container_id: str,
        command: list[str],
        privileged: bool = False,
        user: str | None = None
    ) -> str:
        """Execute command in container."""
        try:
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
                logger.warning(f"Command exited with code {exit_code}: {command}")

            if isinstance(output, bytes):
                return output.decode('utf-8', errors='replace')
            return output

        except Exception as e:
            logger.error(f"Failed to execute command: {e}")
            raise DockerError(f"Command execution failed: {e}")

    async def list_containers(
        self,
        all: bool = True,
        filters: dict | None = None
    ) -> list[Container]:
        """List containers."""
        try:
            loop = asyncio.get_event_loop()
            containers = await loop.run_in_executor(
                None,
                self.client.containers.list,
                all,
                filters
            )

            return containers

        except Exception as e:
            logger.error(f"Failed to list containers: {e}")
            return []

    # Health monitoring

    async def health_check(self, container_id: str) -> bool:
        """Check container health."""
        try:
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

        except Exception:
            return False

    # Private methods

    async def _get_container(self, container_id: str) -> Container:
        """Get container by ID with caching."""
        if container_id in self._container_cache:
            return self._container_cache[container_id]

        try:
            loop = asyncio.get_event_loop()
            container = await loop.run_in_executor(
                None,
                self.client.containers.get,
                container_id
            )

            self._container_cache[container_id] = container
            return container

        except NotFound:
            raise DockerError(f"Container not found: {container_id}")

    def _parse_volumes(self, volumes: list[str]) -> dict[str, dict]:
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

    def _parse_ports(self, ports: dict[str, int]) -> dict[str, Any]:
        """Parse port configuration."""
        parsed = {}

        for container_port, host_port in ports.items():
            # Format: "8080/tcp": 8080
            if "/" not in container_port:
                container_port = f"{container_port}/tcp"

            parsed[container_port] = host_port

        return parsed

    def _parse_stats(self, stats: dict) -> dict[str, Any]:
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
            logger.error(f"Failed to parse stats: {e}")
            return {}

    def _invalidate_cache(self, container_id: str):
        """Invalidate cached data for container."""
        if container_id in self._stats_cache:
            del self._stats_cache[container_id]
        if container_id in self._last_cache_update:
            del self._last_cache_update[container_id]
