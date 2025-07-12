"""
Enhanced user management service with health checks and resilience patterns.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
from uuid import uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from vpn.core.database import DatabaseManager, UserDB, get_session
from vpn.core.exceptions import (
    UserAlreadyExistsError,
    UserNotFoundError,
    ValidationError,
    DatabaseError,
)
from vpn.core.models import (
    ConnectionInfo,
    CryptoKeys,
    ProtocolConfig,
    ProtocolType,
    TrafficStats,
    User,
    UserStatus,
)
from vpn.services.base_service import (
    EnhancedBaseService,
    ServiceHealth,
    ServiceStatus,
    with_retry,
    CircuitBreaker,
    ConnectionPool,
)
from vpn.services.crypto import CryptoService
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class EnhancedUserManager(EnhancedBaseService[User]):
    """Enhanced user management service with resilience patterns."""
    
    def __init__(self, session: Optional[AsyncSession] = None):
        """Initialize enhanced user manager."""
        super().__init__(
            session=session,
            circuit_breaker=CircuitBreaker(
                failure_threshold=3,
                recovery_timeout=30,
                expected_exception=DatabaseError
            ),
            name="UserManager"
        )
        
        self.crypto_service = CryptoService()
        self._user_cache: Dict[str, User] = {}
        
        # Database connection pool
        self._db_pool = ConnectionPool(
            factory=self._create_db_session,
            max_size=5
        )
    
    async def _create_db_session(self) -> AsyncSession:
        """Create new database session."""
        async for session in get_session():
            return session
    
    async def health_check(self) -> ServiceHealth:
        """Perform health check on user service."""
        try:
            # Test database connectivity
            async with self._db_pool.connection() as session:
                db_manager = DatabaseManager(session)
                users = await db_manager.list_users()
                user_count = len(users)
            
            # Test crypto service
            test_keys = await self.crypto_service.generate_keys(ProtocolType.VLESS)
            
            return ServiceHealth(
                service=self.name,
                status=ServiceStatus.HEALTHY,
                message=f"Service operational. {user_count} users managed.",
                metrics={
                    "user_count": user_count,
                    "cache_size": len(self._user_cache),
                    "crypto_operational": bool(test_keys),
                    "circuit_breaker_state": self.circuit_breaker.state.value,
                    "failure_count": self.circuit_breaker.failure_count,
                }
            )
        
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            return ServiceHealth(
                service=self.name,
                status=ServiceStatus.UNHEALTHY,
                message=f"Service unhealthy: {str(e)}",
                metrics={
                    "cache_size": len(self._user_cache),
                    "circuit_breaker_state": self.circuit_breaker.state.value,
                    "failure_count": self.circuit_breaker.failure_count,
                }
            )
    
    async def cleanup(self):
        """Cleanup service resources."""
        self.logger.info("Cleaning up UserManager resources...")
        await self._db_pool.close_all()
        self._user_cache.clear()
    
    async def reconnect(self):
        """Reconnect/reinitialize service connections."""
        self.logger.info("Reconnecting UserManager...")
        await self._db_pool.close_all()
        self._user_cache.clear()
        # Reset circuit breaker
        self.circuit_breaker.failure_count = 0
        self.circuit_breaker.state = self.circuit_breaker.CircuitBreakerState.CLOSED
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def create_user(
        self,
        username: str,
        protocol: str | ProtocolType,
        email: Optional[str] = None,
        **kwargs
    ) -> User:
        """Create a new VPN user with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._create_user_impl,
                username=username,
                protocol=protocol,
                email=email,
                **kwargs
            )
        except Exception as e:
            self.logger.error(f"Failed to create user {username}: {e}")
            raise
    
    async def _create_user_impl(
        self,
        username: str,
        protocol: str | ProtocolType,
        email: Optional[str] = None,
        **kwargs
    ) -> User:
        """Internal user creation implementation."""
        # Validate input
        if not username or not username.strip():
            raise ValidationError("Username cannot be empty")
        
        username = username.strip().lower()
        
        # Check if user exists
        async with self._db_pool.connection() as session:
            db_manager = DatabaseManager(session)
            
            existing_user = await db_manager.get_user_by_username(username)
            if existing_user:
                raise UserAlreadyExistsError(username)
            
            # Convert protocol
            if isinstance(protocol, str):
                try:
                    protocol = ProtocolType(protocol.lower())
                except ValueError:
                    raise ValidationError(f"Unsupported protocol: {protocol}")
            
            # Generate cryptographic keys
            keys = await self.crypto_service.generate_keys(protocol)
            
            # Create protocol configuration
            protocol_config = ProtocolConfig(
                type=protocol,
                **kwargs.get('protocol_settings', {})
            )
            
            # Create user model
            user_data = {
                'id': str(uuid4()),
                'username': username,
                'email': email,
                'status': UserStatus.ACTIVE,
                'protocol': protocol_config.model_dump(),
                'keys': keys.model_dump(),
                'traffic': TrafficStats().model_dump(),
                'created_at': datetime.utcnow(),
                **{k: v for k, v in kwargs.items() if k not in ['protocol_settings']}
            }
            
            # Save to database
            user_db = await db_manager.create_user(user_data)
            
            # Convert to domain model
            user = User.model_validate(user_db.__dict__)
            
            # Cache user
            self._user_cache[user.id] = user
            
            self.logger.info(f"Created user: {username} ({user.id})")
            return user
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def get_user(self, user_id: str) -> Optional[User]:
        """Get user by ID with caching and retry."""
        # Check cache first
        if user_id in self._user_cache:
            return self._user_cache[user_id]
        
        try:
            return await self.circuit_breaker.call(self._get_user_impl, user_id)
        except Exception as e:
            self.logger.error(f"Failed to get user {user_id}: {e}")
            return None
    
    async def _get_user_impl(self, user_id: str) -> Optional[User]:
        """Internal get user implementation."""
        async with self._db_pool.connection() as session:
            db_manager = DatabaseManager(session)
            user_db = await db_manager.get_user(user_id)
            
            if not user_db:
                return None
            
            user = User.model_validate(user_db.__dict__)
            self._user_cache[user.id] = user
            return user
    
    async def get_user_by_username(self, username: str) -> Optional[User]:
        """Get user by username."""
        # Check cache
        for user in self._user_cache.values():
            if user.username == username:
                return user
        
        try:
            return await self.circuit_breaker.call(
                self._get_user_by_username_impl, 
                username
            )
        except Exception as e:
            self.logger.error(f"Failed to get user by username {username}: {e}")
            return None
    
    async def _get_user_by_username_impl(self, username: str) -> Optional[User]:
        """Internal get user by username implementation."""
        async with self._db_pool.connection() as session:
            db_manager = DatabaseManager(session)
            user_db = await db_manager.get_user_by_username(username)
            
            if not user_db:
                return None
            
            user = User.model_validate(user_db.__dict__)
            self._user_cache[user.id] = user
            return user
    
    async def list_users(self, status: Optional[UserStatus] = None) -> List[User]:
        """List all users with optional status filter."""
        try:
            return await self.circuit_breaker.call(self._list_users_impl, status)
        except Exception as e:
            self.logger.error(f"Failed to list users: {e}")
            return []
    
    async def _list_users_impl(self, status: Optional[UserStatus] = None) -> List[User]:
        """Internal list users implementation."""
        async with self._db_pool.connection() as session:
            db_manager = DatabaseManager(session)
            status_filter = status.value if status else None
            users_db = await db_manager.list_users(status=status_filter)
            
            users = []
            for user_db in users_db:
                user = User.model_validate(user_db.__dict__)
                self._user_cache[user.id] = user
                users.append(user)
            
            return users
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def update_user(self, user_id: str, **kwargs) -> Optional[User]:
        """Update user with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._update_user_impl,
                user_id,
                **kwargs
            )
        except Exception as e:
            self.logger.error(f"Failed to update user {user_id}: {e}")
            return None
    
    async def _update_user_impl(self, user_id: str, **kwargs) -> Optional[User]:
        """Internal update user implementation."""
        async with self._db_pool.connection() as session:
            db_manager = DatabaseManager(session)
            
            # Get current user
            user_db = await db_manager.get_user(user_id)
            if not user_db:
                raise UserNotFoundError(user_id)
            
            # Update fields
            update_data = {}
            for key, value in kwargs.items():
                if hasattr(user_db, key):
                    update_data[key] = value
            
            if update_data:
                update_data['updated_at'] = datetime.utcnow()
                
                # Update in database
                for key, value in update_data.items():
                    setattr(user_db, key, value)
                
                await session.commit()
            
            # Update cache
            user = User.model_validate(user_db.__dict__)
            self._user_cache[user.id] = user
            
            return user
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def delete_user(self, user_id: str) -> bool:
        """Delete user with retry logic."""
        try:
            return await self.circuit_breaker.call(self._delete_user_impl, user_id)
        except Exception as e:
            self.logger.error(f"Failed to delete user {user_id}: {e}")
            return False
    
    async def _delete_user_impl(self, user_id: str) -> bool:
        """Internal delete user implementation."""
        async with self._db_pool.connection() as session:
            db_manager = DatabaseManager(session)
            
            user_db = await db_manager.get_user(user_id)
            if not user_db:
                return False
            
            await session.delete(user_db)
            await session.commit()
            
            # Remove from cache
            self._user_cache.pop(user_id, None)
            
            self.logger.info(f"Deleted user: {user_id}")
            return True
    
    async def get_user_stats(self) -> Dict[str, any]:
        """Get user statistics."""
        try:
            users = await self.list_users()
            
            stats = {
                'total_users': len(users),
                'active_users': sum(1 for u in users if u.status == UserStatus.ACTIVE),
                'inactive_users': sum(1 for u in users if u.status == UserStatus.INACTIVE),
                'expired_users': sum(1 for u in users if u.status == UserStatus.EXPIRED),
                'protocols': {},
                'total_traffic_gb': 0,
            }
            
            for user in users:
                # Count protocols
                protocol = user.protocol.type
                stats['protocols'][protocol] = stats['protocols'].get(protocol, 0) + 1
                
                # Sum traffic
                if user.traffic:
                    stats['total_traffic_gb'] += user.traffic.total_mb / 1024
            
            return stats
            
        except Exception as e:
            self.logger.error(f"Failed to get user stats: {e}")
            return {}