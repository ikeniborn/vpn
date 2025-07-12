"""
Auto-reconnection logic for services with health monitoring.
"""

import asyncio
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set

from vpn.services.base_service import EnhancedBaseService, ServiceHealth, ServiceStatus
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class AutoReconnectManager:
    """Manages automatic reconnection for services."""
    
    def __init__(
        self,
        health_check_interval: int = 30,
        max_failure_count: int = 3,
        reconnect_delay: int = 60,
        max_reconnect_attempts: int = 5
    ):
        """Initialize auto-reconnect manager.
        
        Args:
            health_check_interval: Seconds between health checks
            max_failure_count: Failures before triggering reconnect
            reconnect_delay: Delay between reconnect attempts
            max_reconnect_attempts: Max reconnection attempts before giving up
        """
        self.health_check_interval = health_check_interval
        self.max_failure_count = max_failure_count
        self.reconnect_delay = reconnect_delay
        self.max_reconnect_attempts = max_reconnect_attempts
        
        self._services: Dict[str, EnhancedBaseService] = {}
        self._failure_counts: Dict[str, int] = {}
        self._reconnect_attempts: Dict[str, int] = {}
        self._last_health_checks: Dict[str, datetime] = {}
        self._monitoring_tasks: Dict[str, asyncio.Task] = {}
        self._is_running = False
        self._shutdown_event = asyncio.Event()
        
        # Service states
        self._unhealthy_services: Set[str] = set()
        self._reconnecting_services: Set[str] = set()
    
    def register_service(self, service: EnhancedBaseService):
        """Register a service for auto-reconnect monitoring."""
        service_name = service.name
        self._services[service_name] = service
        self._failure_counts[service_name] = 0
        self._reconnect_attempts[service_name] = 0
        self._last_health_checks[service_name] = datetime.utcnow()
        
        logger.info(f"Registered service '{service_name}' for auto-reconnect monitoring")
        
        # Start monitoring if manager is running
        if self._is_running:
            self._start_service_monitoring(service_name)
    
    def unregister_service(self, service_name: str):
        """Unregister a service from monitoring."""
        if service_name in self._services:
            # Stop monitoring task
            if service_name in self._monitoring_tasks:
                self._monitoring_tasks[service_name].cancel()
                del self._monitoring_tasks[service_name]
            
            # Clean up state
            del self._services[service_name]
            self._failure_counts.pop(service_name, None)
            self._reconnect_attempts.pop(service_name, None)
            self._last_health_checks.pop(service_name, None)
            self._unhealthy_services.discard(service_name)
            self._reconnecting_services.discard(service_name)
            
            logger.info(f"Unregistered service '{service_name}' from auto-reconnect monitoring")
    
    async def start(self):
        """Start the auto-reconnect manager."""
        if self._is_running:
            logger.warning("AutoReconnectManager is already running")
            return
        
        self._is_running = True
        self._shutdown_event.clear()
        
        # Start monitoring tasks for all registered services
        for service_name in self._services:
            self._start_service_monitoring(service_name)
        
        logger.info("AutoReconnectManager started")
    
    async def stop(self):
        """Stop the auto-reconnect manager."""
        if not self._is_running:
            return
        
        self._is_running = False
        self._shutdown_event.set()
        
        # Cancel all monitoring tasks
        for task in self._monitoring_tasks.values():
            task.cancel()
        
        # Wait for tasks to complete
        if self._monitoring_tasks:
            await asyncio.gather(
                *self._monitoring_tasks.values(),
                return_exceptions=True
            )
        
        self._monitoring_tasks.clear()
        logger.info("AutoReconnectManager stopped")
    
    def _start_service_monitoring(self, service_name: str):
        """Start monitoring task for a service."""
        if service_name in self._monitoring_tasks:
            self._monitoring_tasks[service_name].cancel()
        
        task = asyncio.create_task(self._monitor_service(service_name))
        self._monitoring_tasks[service_name] = task
        
        logger.debug(f"Started monitoring for service '{service_name}'")
    
    async def _monitor_service(self, service_name: str):
        """Monitor a service for health and handle reconnection."""
        service = self._services[service_name]
        
        try:
            while self._is_running and not self._shutdown_event.is_set():
                try:
                    # Perform health check
                    health = await service.get_health(force_check=True)
                    self._last_health_checks[service_name] = datetime.utcnow()
                    
                    await self._handle_health_result(service_name, health)
                    
                    # Wait for next check
                    try:
                        await asyncio.wait_for(
                            self._shutdown_event.wait(),
                            timeout=self.health_check_interval
                        )
                        break  # Shutdown was triggered
                    except asyncio.TimeoutError:
                        continue  # Normal timeout, continue monitoring
                
                except Exception as e:
                    logger.error(f"Health check failed for service '{service_name}': {e}")
                    await self._handle_health_check_failure(service_name)
                    
                    # Short delay before retry
                    try:
                        await asyncio.wait_for(
                            self._shutdown_event.wait(),
                            timeout=5
                        )
                        break
                    except asyncio.TimeoutError:
                        continue
        
        except asyncio.CancelledError:
            logger.debug(f"Monitoring cancelled for service '{service_name}'")
        except Exception as e:
            logger.error(f"Monitoring failed for service '{service_name}': {e}")
    
    async def _handle_health_result(self, service_name: str, health: ServiceHealth):
        """Handle health check result for a service."""
        if health.status == ServiceStatus.HEALTHY:
            # Service is healthy
            if service_name in self._unhealthy_services:
                logger.info(f"Service '{service_name}' recovered to healthy state")
                self._unhealthy_services.discard(service_name)
                self._reconnecting_services.discard(service_name)
            
            # Reset failure count
            self._failure_counts[service_name] = 0
            self._reconnect_attempts[service_name] = 0
        
        elif health.status == ServiceStatus.DEGRADED:
            # Service is degraded but functional
            if service_name not in self._unhealthy_services:
                logger.warning(f"Service '{service_name}' is in degraded state: {health.message}")
            
            # Increment failure count but don't trigger immediate reconnect
            self._failure_counts[service_name] += 1
            
            # Only trigger reconnect if degraded for too long
            if self._failure_counts[service_name] >= self.max_failure_count * 2:
                await self._trigger_reconnect(service_name)
        
        elif health.status in [ServiceStatus.UNHEALTHY, ServiceStatus.UNKNOWN]:
            # Service is unhealthy
            if service_name not in self._unhealthy_services:
                logger.error(f"Service '{service_name}' became unhealthy: {health.message}")
                self._unhealthy_services.add(service_name)
            
            self._failure_counts[service_name] += 1
            
            # Trigger reconnect if failure threshold reached
            if self._failure_counts[service_name] >= self.max_failure_count:
                await self._trigger_reconnect(service_name)
    
    async def _handle_health_check_failure(self, service_name: str):
        """Handle health check failure (exception during check)."""
        self._failure_counts[service_name] += 1
        
        if service_name not in self._unhealthy_services:
            logger.error(f"Service '{service_name}' health check failed")
            self._unhealthy_services.add(service_name)
        
        # Trigger reconnect if failure threshold reached
        if self._failure_counts[service_name] >= self.max_failure_count:
            await self._trigger_reconnect(service_name)
    
    async def _trigger_reconnect(self, service_name: str):
        """Trigger reconnection for a service."""
        if service_name in self._reconnecting_services:
            logger.debug(f"Service '{service_name}' is already reconnecting")
            return
        
        # Check if we've exceeded max reconnect attempts
        if self._reconnect_attempts[service_name] >= self.max_reconnect_attempts:
            logger.error(
                f"Service '{service_name}' exceeded max reconnect attempts "
                f"({self.max_reconnect_attempts}). Giving up."
            )
            return
        
        self._reconnecting_services.add(service_name)
        self._reconnect_attempts[service_name] += 1
        
        logger.info(
            f"Triggering reconnect for service '{service_name}' "
            f"(attempt {self._reconnect_attempts[service_name]}/{self.max_reconnect_attempts})"
        )
        
        try:
            service = self._services[service_name]
            
            # Perform reconnection
            await service.reconnect()
            
            # Reset failure count after successful reconnect
            self._failure_counts[service_name] = 0
            
            logger.info(f"Successfully reconnected service '{service_name}'")
            
        except Exception as e:
            logger.error(f"Failed to reconnect service '{service_name}': {e}")
        
        finally:
            self._reconnecting_services.discard(service_name)
            
            # Wait before next potential reconnect attempt
            if self._reconnect_attempts[service_name] < self.max_reconnect_attempts:
                try:
                    await asyncio.wait_for(
                        self._shutdown_event.wait(),
                        timeout=self.reconnect_delay
                    )
                except asyncio.TimeoutError:
                    pass
    
    async def get_service_status(self, service_name: str) -> Optional[Dict]:
        """Get current status of a monitored service."""
        if service_name not in self._services:
            return None
        
        service = self._services[service_name]
        
        try:
            health = await service.get_health()
            
            return {
                "name": service_name,
                "status": health.status.value,
                "message": health.message,
                "uptime_seconds": health.uptime_seconds,
                "failure_count": self._failure_counts[service_name],
                "reconnect_attempts": self._reconnect_attempts[service_name],
                "is_unhealthy": service_name in self._unhealthy_services,
                "is_reconnecting": service_name in self._reconnecting_services,
                "last_health_check": self._last_health_checks[service_name].isoformat(),
                "metrics": health.metrics,
            }
        
        except Exception as e:
            return {
                "name": service_name,
                "status": "error",
                "message": f"Failed to get status: {e}",
                "failure_count": self._failure_counts[service_name],
                "reconnect_attempts": self._reconnect_attempts[service_name],
                "is_unhealthy": True,
                "is_reconnecting": service_name in self._reconnecting_services,
                "last_health_check": self._last_health_checks[service_name].isoformat(),
            }
    
    async def get_all_service_status(self) -> List[Dict]:
        """Get status of all monitored services."""
        statuses = []
        
        for service_name in self._services:
            status = await self.get_service_status(service_name)
            if status:
                statuses.append(status)
        
        return statuses
    
    async def force_reconnect(self, service_name: str) -> bool:
        """Force reconnection of a specific service."""
        if service_name not in self._services:
            logger.error(f"Service '{service_name}' is not registered")
            return False
        
        logger.info(f"Forcing reconnect for service '{service_name}'")
        
        # Reset attempts to allow forced reconnect
        original_attempts = self._reconnect_attempts[service_name]
        self._reconnect_attempts[service_name] = 0
        
        try:
            await self._trigger_reconnect(service_name)
            return True
        except Exception as e:
            logger.error(f"Force reconnect failed for service '{service_name}': {e}")
            self._reconnect_attempts[service_name] = original_attempts
            return False
    
    def get_manager_stats(self) -> Dict:
        """Get manager statistics."""
        total_services = len(self._services)
        unhealthy_count = len(self._unhealthy_services)
        reconnecting_count = len(self._reconnecting_services)
        healthy_count = total_services - unhealthy_count
        
        total_failures = sum(self._failure_counts.values())
        total_reconnects = sum(self._reconnect_attempts.values())
        
        return {
            "is_running": self._is_running,
            "total_services": total_services,
            "healthy_services": healthy_count,
            "unhealthy_services": unhealthy_count,
            "reconnecting_services": reconnecting_count,
            "total_failures": total_failures,
            "total_reconnects": total_reconnects,
            "health_check_interval": self.health_check_interval,
            "max_failure_count": self.max_failure_count,
            "reconnect_delay": self.reconnect_delay,
            "max_reconnect_attempts": self.max_reconnect_attempts,
        }