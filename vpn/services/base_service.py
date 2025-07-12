"""
Enhanced base service with health checks, circuit breaker, and dependency injection.
"""

import asyncio
import time
from abc import ABC, abstractmethod
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, Generic, Optional, Type, TypeVar, Callable
from functools import wraps

from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from vpn.core.config import settings
from vpn.core.exceptions import ServiceError
from vpn.utils.logger import get_logger


T = TypeVar("T")


class ServiceStatus(str, Enum):
    """Service health status."""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"


class ServiceHealth(BaseModel):
    """Service health information."""
    service: str
    status: ServiceStatus
    message: Optional[str] = None
    last_check: datetime = Field(default_factory=datetime.utcnow)
    uptime_seconds: Optional[float] = None
    metrics: Dict[str, Any] = Field(default_factory=dict)


class CircuitBreakerState(str, Enum):
    """Circuit breaker states."""
    CLOSED = "closed"  # Normal operation
    OPEN = "open"      # Failing, reject calls
    HALF_OPEN = "half_open"  # Testing if service recovered


class CircuitBreaker:
    """Circuit breaker pattern implementation."""
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: int = 60,
        expected_exception: Type[Exception] = Exception
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.expected_exception = expected_exception
        self.failure_count = 0
        self.last_failure_time = None
        self.state = CircuitBreakerState.CLOSED
    
    async def call(self, func: Callable, *args, **kwargs):
        """Execute function with circuit breaker protection."""
        if self.state == CircuitBreakerState.OPEN:
            if self._should_attempt_reset():
                self.state = CircuitBreakerState.HALF_OPEN
            else:
                raise ServiceError("Service unavailable - circuit breaker is OPEN")
        
        try:
            result = await func(*args, **kwargs)
            self._on_success()
            return result
        except self.expected_exception as e:
            self._on_failure()
            raise e
    
    def _should_attempt_reset(self) -> bool:
        """Check if we should try to reset the circuit."""
        return (
            self.last_failure_time and
            time.time() - self.last_failure_time >= self.recovery_timeout
        )
    
    def _on_success(self):
        """Reset circuit breaker on successful call."""
        self.failure_count = 0
        self.state = CircuitBreakerState.CLOSED
        self.last_failure_time = None
    
    def _on_failure(self):
        """Record failure and potentially open circuit."""
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitBreakerState.OPEN


class ServiceRegistry:
    """Global service registry for dependency injection."""
    
    _instance = None
    _services: Dict[str, Any] = {}
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def register(self, name: str, service: Any):
        """Register a service."""
        self._services[name] = service
    
    def get(self, name: str) -> Any:
        """Get a registered service."""
        if name not in self._services:
            raise ServiceError(f"Service '{name}' not found in registry")
        return self._services[name]
    
    def clear(self):
        """Clear all registered services."""
        self._services.clear()


class EnhancedBaseService(ABC, Generic[T]):
    """Enhanced base service with health checks and resilience patterns."""
    
    def __init__(
        self,
        session: Optional[AsyncSession] = None,
        circuit_breaker: Optional[CircuitBreaker] = None,
        name: Optional[str] = None
    ):
        """Initialize enhanced service.
        
        Args:
            session: Optional database session
            circuit_breaker: Optional circuit breaker instance
            name: Service name for registry
        """
        self._session = session
        self.logger = get_logger(name or self.__class__.__name__)
        self.settings = settings
        self.name = name or self.__class__.__name__
        self._start_time = datetime.utcnow()
        
        # Circuit breaker
        self.circuit_breaker = circuit_breaker or CircuitBreaker()
        
        # Register in global registry
        ServiceRegistry().register(self.name, self)
        
        # Health check cache
        self._last_health_check: Optional[ServiceHealth] = None
        self._health_check_interval = 30  # seconds
    
    @property
    def uptime(self) -> timedelta:
        """Get service uptime."""
        return datetime.utcnow() - self._start_time
    
    @abstractmethod
    async def health_check(self) -> ServiceHealth:
        """Perform health check on the service.
        
        Must be implemented by subclasses.
        """
        pass
    
    async def get_health(self, force_check: bool = False) -> ServiceHealth:
        """Get service health with caching."""
        now = datetime.utcnow()
        
        # Check cache
        if not force_check and self._last_health_check:
            age = (now - self._last_health_check.last_check).total_seconds()
            if age < self._health_check_interval:
                return self._last_health_check
        
        # Perform new health check
        try:
            health = await self.health_check()
            health.uptime_seconds = self.uptime.total_seconds()
            self._last_health_check = health
            return health
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            return ServiceHealth(
                service=self.name,
                status=ServiceStatus.UNHEALTHY,
                message=str(e),
                uptime_seconds=self.uptime.total_seconds()
            )
    
    @abstractmethod
    async def cleanup(self):
        """Cleanup service resources.
        
        Called when service is shutting down.
        """
        pass
    
    @abstractmethod
    async def reconnect(self):
        """Reconnect/reinitialize service connections.
        
        Called when service needs to recover from errors.
        """
        pass
    
    async def __aenter__(self):
        """Async context manager entry."""
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.cleanup()
    
    @asynccontextmanager
    async def transaction(self):
        """Database transaction context manager."""
        if not self._session:
            raise ServiceError("No database session available")
        
        async with self._session.begin():
            yield self._session
    
    def with_circuit_breaker(self, func: Callable):
        """Decorator to apply circuit breaker to methods."""
        @wraps(func)
        async def wrapper(*args, **kwargs):
            return await self.circuit_breaker.call(func, *args, **kwargs)
        return wrapper
    
    def inject(self, service_name: str) -> Any:
        """Inject a dependency from the service registry."""
        return ServiceRegistry().get(service_name)


class ConnectionPool:
    """Generic connection pool for services."""
    
    def __init__(self, factory: Callable, max_size: int = 10):
        """Initialize connection pool.
        
        Args:
            factory: Async callable that creates connections
            max_size: Maximum pool size
        """
        self.factory = factory
        self.max_size = max_size
        self._pool: asyncio.Queue = asyncio.Queue(maxsize=max_size)
        self._created = 0
        self._lock = asyncio.Lock()
    
    async def acquire(self):
        """Acquire a connection from pool."""
        # Try to get from pool
        try:
            return self._pool.get_nowait()
        except asyncio.QueueEmpty:
            pass
        
        # Create new if under limit
        async with self._lock:
            if self._created < self.max_size:
                conn = await self.factory()
                self._created += 1
                return conn
        
        # Wait for available connection
        return await self._pool.get()
    
    async def release(self, conn):
        """Release connection back to pool."""
        try:
            self._pool.put_nowait(conn)
        except asyncio.QueueFull:
            # Pool is full, close the connection
            if hasattr(conn, 'close'):
                await conn.close()
    
    async def close_all(self):
        """Close all connections in pool."""
        while not self._pool.empty():
            try:
                conn = self._pool.get_nowait()
                if hasattr(conn, 'close'):
                    await conn.close()
            except asyncio.QueueEmpty:
                break
        self._created = 0
    
    @asynccontextmanager
    async def connection(self):
        """Context manager for connection acquisition."""
        conn = await self.acquire()
        try:
            yield conn
        finally:
            await self.release(conn)


class RetryPolicy:
    """Retry policy for service operations."""
    
    def __init__(
        self,
        max_attempts: int = 3,
        initial_delay: float = 1.0,
        max_delay: float = 60.0,
        exponential_base: float = 2.0,
        jitter: bool = True
    ):
        self.max_attempts = max_attempts
        self.initial_delay = initial_delay
        self.max_delay = max_delay
        self.exponential_base = exponential_base
        self.jitter = jitter
    
    def calculate_delay(self, attempt: int) -> float:
        """Calculate delay for retry attempt."""
        delay = min(
            self.initial_delay * (self.exponential_base ** (attempt - 1)),
            self.max_delay
        )
        
        if self.jitter:
            # Add random jitter (0-25% of delay)
            import random
            delay *= (1 + random.random() * 0.25)
        
        return delay
    
    async def execute(self, func: Callable, *args, **kwargs):
        """Execute function with retry policy."""
        last_exception = None
        
        for attempt in range(1, self.max_attempts + 1):
            try:
                return await func(*args, **kwargs)
            except Exception as e:
                last_exception = e
                if attempt < self.max_attempts:
                    delay = self.calculate_delay(attempt)
                    await asyncio.sleep(delay)
                    continue
                raise
        
        raise last_exception


# Export convenience decorator
def with_retry(
    max_attempts: int = 3,
    initial_delay: float = 1.0,
    exceptions: tuple = (Exception,)
):
    """Decorator to add retry logic to async methods."""
    def decorator(func):
        policy = RetryPolicy(max_attempts=max_attempts, initial_delay=initial_delay)
        
        @wraps(func)
        async def wrapper(*args, **kwargs):
            try:
                return await policy.execute(func, *args, **kwargs)
            except exceptions:
                raise
            except Exception:
                # Re-raise unexpected exceptions without retry
                raise
        
        return wrapper
    return decorator