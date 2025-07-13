"""Centralized service manager for enhanced services.
"""

import asyncio
from typing import TypeVar

from vpn.services.auto_reconnect import AutoReconnectManager
from vpn.services.base_service import EnhancedBaseService, ServiceRegistry
from vpn.services.enhanced_docker_manager import EnhancedDockerManager
from vpn.services.enhanced_network_manager import EnhancedNetworkManager
from vpn.services.enhanced_user_manager import EnhancedUserManager
from vpn.utils.logger import get_logger

logger = get_logger(__name__)

T = TypeVar('T', bound=EnhancedBaseService)


class ServiceManager:
    """Centralized manager for all enhanced services."""

    def __init__(self):
        """Initialize service manager."""
        self._services: dict[str, EnhancedBaseService] = {}
        self._auto_reconnect_manager = AutoReconnectManager()
        self._is_running = False
        self._registry = ServiceRegistry()

    async def start(self):
        """Start the service manager and all services."""
        if self._is_running:
            logger.warning("ServiceManager is already running")
            return

        logger.info("Starting ServiceManager...")

        try:
            # Initialize core services
            await self._initialize_services()

            # Start auto-reconnect monitoring
            await self._auto_reconnect_manager.start()

            self._is_running = True
            logger.info("ServiceManager started successfully")

        except Exception as e:
            logger.error(f"Failed to start ServiceManager: {e}")
            await self.stop()
            raise

    async def stop(self):
        """Stop the service manager and all services."""
        if not self._is_running:
            return

        logger.info("Stopping ServiceManager...")

        try:
            # Stop auto-reconnect monitoring
            await self._auto_reconnect_manager.stop()

            # Cleanup all services
            cleanup_tasks = []
            for service_name, service in self._services.items():
                logger.debug(f"Cleaning up service: {service_name}")
                cleanup_tasks.append(service.cleanup())

            if cleanup_tasks:
                await asyncio.gather(*cleanup_tasks, return_exceptions=True)

            # Clear registry
            self._registry.clear()
            self._services.clear()

            self._is_running = False
            logger.info("ServiceManager stopped")

        except Exception as e:
            logger.error(f"Error during ServiceManager shutdown: {e}")

    async def _initialize_services(self):
        """Initialize all core services."""
        services_to_init = [
            ("UserManager", EnhancedUserManager),
            ("DockerManager", EnhancedDockerManager),
            ("NetworkManager", EnhancedNetworkManager),
        ]

        for service_name, service_class in services_to_init:
            try:
                logger.debug(f"Initializing {service_name}...")

                # Create service instance
                if service_name == "UserManager":
                    service = service_class()
                else:
                    service = service_class()

                # Register service
                self._services[service_name] = service

                # Register for auto-reconnect monitoring
                self._auto_reconnect_manager.register_service(service)

                logger.info(f"Initialized {service_name}")

            except Exception as e:
                logger.error(f"Failed to initialize {service_name}: {e}")
                raise

    def get_service(self, service_name: str) -> EnhancedBaseService | None:
        """Get a service by name."""
        return self._services.get(service_name)

    def get_user_manager(self) -> EnhancedUserManager | None:
        """Get the user manager service."""
        return self._services.get("UserManager")

    def get_docker_manager(self) -> EnhancedDockerManager | None:
        """Get the Docker manager service."""
        return self._services.get("DockerManager")

    def get_network_manager(self) -> EnhancedNetworkManager | None:
        """Get the network manager service."""
        return self._services.get("NetworkManager")

    async def get_service_health(self, service_name: str) -> dict | None:
        """Get health status for a specific service."""
        return await self._auto_reconnect_manager.get_service_status(service_name)

    async def get_all_service_health(self) -> list[dict]:
        """Get health status for all services."""
        return await self._auto_reconnect_manager.get_all_service_status()

    async def force_service_reconnect(self, service_name: str) -> bool:
        """Force reconnection of a specific service."""
        return await self._auto_reconnect_manager.force_reconnect(service_name)

    async def perform_system_health_check(self) -> dict:
        """Perform comprehensive system health check."""
        logger.info("Performing system health check...")

        # Get all service statuses
        service_statuses = await self.get_all_service_health()

        # Calculate overall system health
        total_services = len(service_statuses)
        healthy_services = sum(1 for s in service_statuses if s["status"] == "healthy")
        degraded_services = sum(1 for s in service_statuses if s["status"] == "degraded")
        unhealthy_services = sum(1 for s in service_statuses if s["status"] in ["unhealthy", "unknown", "error"])

        # Determine overall status
        if unhealthy_services == 0 and degraded_services == 0:
            overall_status = "healthy"
            overall_message = "All services operational"
        elif unhealthy_services == 0:
            overall_status = "degraded"
            overall_message = f"{degraded_services} service(s) degraded"
        elif unhealthy_services < total_services:
            overall_status = "degraded"
            overall_message = f"{unhealthy_services} service(s) unhealthy, {degraded_services} degraded"
        else:
            overall_status = "unhealthy"
            overall_message = "System experiencing critical issues"

        # Get manager stats
        manager_stats = self._auto_reconnect_manager.get_manager_stats()

        return {
            "overall_status": overall_status,
            "overall_message": overall_message,
            "timestamp": asyncio.get_event_loop().time(),
            "service_manager_running": self._is_running,
            "services": {
                "total": total_services,
                "healthy": healthy_services,
                "degraded": degraded_services,
                "unhealthy": unhealthy_services,
            },
            "auto_reconnect": manager_stats,
            "service_details": service_statuses,
        }

    async def restart_unhealthy_services(self) -> dict[str, bool]:
        """Restart all unhealthy services."""
        logger.info("Restarting unhealthy services...")

        service_statuses = await self.get_all_service_health()
        results = {}

        for status in service_statuses:
            service_name = status["name"]
            if status["status"] in ["unhealthy", "unknown", "error"]:
                logger.info(f"Restarting unhealthy service: {service_name}")
                success = await self.force_service_reconnect(service_name)
                results[service_name] = success

        return results

    async def __aenter__(self):
        """Async context manager entry."""
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.stop()

    @property
    def is_running(self) -> bool:
        """Check if service manager is running."""
        return self._is_running

    def get_registered_services(self) -> list[str]:
        """Get list of registered service names."""
        return list(self._services.keys())


# Global service manager instance
_service_manager: ServiceManager | None = None


async def get_service_manager() -> ServiceManager:
    """Get the global service manager instance."""
    global _service_manager

    if _service_manager is None:
        _service_manager = ServiceManager()
        await _service_manager.start()

    return _service_manager


async def cleanup_service_manager():
    """Cleanup the global service manager."""
    global _service_manager

    if _service_manager is not None:
        await _service_manager.stop()
        _service_manager = None


# Convenience functions for service access
async def get_user_manager() -> EnhancedUserManager | None:
    """Get the enhanced user manager."""
    manager = await get_service_manager()
    return manager.get_user_manager()


async def get_docker_manager() -> EnhancedDockerManager | None:
    """Get the enhanced Docker manager."""
    manager = await get_service_manager()
    return manager.get_docker_manager()


async def get_network_manager() -> EnhancedNetworkManager | None:
    """Get the enhanced network manager."""
    manager = await get_service_manager()
    return manager.get_network_manager()
