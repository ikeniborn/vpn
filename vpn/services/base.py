"""Base service class and interfaces.
"""

from abc import ABC, abstractmethod
from typing import Generic, TypeVar

from sqlalchemy.ext.asyncio import AsyncSession

from vpn.core.config import settings
from vpn.utils.logger import get_logger

T = TypeVar("T")


class BaseService(ABC, Generic[T]):
    """Base class for all services."""

    def __init__(self, session: AsyncSession | None = None):
        """Initialize service.
        
        Args:
            session: Optional database session. If not provided, service
                    will create its own session when needed.
        """
        self._session = session
        self.logger = get_logger(self.__class__.__name__)
        self.settings = settings

    @property
    def session(self) -> AsyncSession | None:
        """Get database session."""
        return self._session

    async def __aenter__(self):
        """Async context manager entry."""
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self._session:
            await self._session.close()


class CRUDService(BaseService[T], ABC):
    """Base class for services with CRUD operations."""

    @abstractmethod
    async def create(self, **kwargs) -> T:
        """Create a new entity."""
        pass

    @abstractmethod
    async def get(self, id: str) -> T | None:
        """Get entity by ID."""
        pass

    @abstractmethod
    async def list(self, **filters) -> list[T]:
        """List entities with optional filters."""
        pass

    @abstractmethod
    async def update(self, id: str, **kwargs) -> T | None:
        """Update entity."""
        pass

    @abstractmethod
    async def delete(self, id: str) -> bool:
        """Delete entity."""
        pass


class EventEmitter:
    """Mixin for services that emit events."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._event_handlers = {}

    def on(self, event: str, handler):
        """Register event handler."""
        if event not in self._event_handlers:
            self._event_handlers[event] = []
        self._event_handlers[event].append(handler)

    async def emit(self, event: str, data=None):
        """Emit event to all registered handlers."""
        if event in self._event_handlers:
            for handler in self._event_handlers[event]:
                if asyncio.iscoroutinefunction(handler):
                    await handler(data)
                else:
                    handler(data)


import asyncio
