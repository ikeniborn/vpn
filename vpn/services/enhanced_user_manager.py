"""
Enhanced user management service with health checks and resilience patterns.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Union
from uuid import uuid4
import asyncio
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text, select, update, delete, func, and_, or_
from sqlalchemy.orm import selectinload, joinedload
from sqlalchemy.sql import Select

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


@dataclass
class PaginationParams:
    """Pagination parameters for query optimization."""
    page: int = 1
    page_size: int = 50
    
    @property
    def offset(self) -> int:
        """Calculate offset for SQL queries."""
        return (self.page - 1) * self.page_size


@dataclass
class PaginatedResult:
    """Paginated result container."""
    items: List[Any]
    total_count: int
    page: int
    page_size: int
    total_pages: int
    has_next: bool
    has_previous: bool


@dataclass
class QueryFilters:
    """Query filters for user search optimization."""
    username: Optional[str] = None
    email: Optional[str] = None
    status: Optional[str] = None
    protocol_type: Optional[str] = None
    created_after: Optional[datetime] = None
    created_before: Optional[datetime] = None
    expires_after: Optional[datetime] = None
    expires_before: Optional[datetime] = None


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
    
    # Batch Operations for Performance Optimization
    
    @with_retry()
    async def create_users_batch(
        self, 
        users_data: List[Dict[str, Any]], 
        batch_size: int = 100
    ) -> List[User]:
        """
        Create multiple users in optimized batches.
        
        Args:
            users_data: List of user data dictionaries
            batch_size: Number of users to process per batch
            
        Returns:
            List of created User objects
            
        Raises:
            ValidationError: If user data is invalid
            UserAlreadyExistsError: If any user already exists
            DatabaseError: If database operation fails
        """
        if not users_data:
            return []
            
        created_users = []
        
        # Process in batches to avoid overwhelming the database
        for i in range(0, len(users_data), batch_size):
            batch = users_data[i:i + batch_size]
            batch_users = await self._create_batch_chunk(batch)
            created_users.extend(batch_users)
            
        self.logger.info(f"Created {len(created_users)} users in batches")
        return created_users
    
    async def _create_batch_chunk(self, users_data: List[Dict[str, Any]]) -> List[User]:
        """Create a single batch chunk of users."""
        users = []
        user_dbs = []
        
        # Validate and prepare all users first
        for user_data in users_data:
            # Check if user already exists
            if await self.get_user(user_data.get('username', ''), raise_not_found=False):
                raise UserAlreadyExistsError(f"User {user_data['username']} already exists")
            
            # Create user object
            user = await self._prepare_user_from_data(user_data)
            users.append(user)
            
            # Create database record
            user_db = UserDB(
                id=user.id,
                username=user.username,
                email=user.email,
                status=user.status.value,
                protocol=json.dumps(user.protocol.model_dump()),
                connection_info=json.dumps(user.connection_info.model_dump()),
                traffic_stats=json.dumps(user.traffic.model_dump()),
                crypto_keys=json.dumps(user.crypto_keys.model_dump()),
                created_at=user.created_at,
                updated_at=user.updated_at,
                expires_at=user.expires_at,
            )
            user_dbs.append(user_db)
        
        # Bulk insert to database
        session = await get_session()
        try:
            session.add_all(user_dbs)
            await session.commit()
            
            # Update cache
            for user in users:
                self._user_cache[user.id] = user
                
            return users
            
        except Exception as e:
            await session.rollback()
            self.logger.error(f"Failed to create user batch: {e}")
            raise DatabaseError(f"Batch user creation failed: {str(e)}")
        finally:
            await session.close()
    
    @with_retry()
    async def update_users_batch(
        self, 
        updates: Dict[str, Dict[str, Any]], 
        batch_size: int = 100
    ) -> List[User]:
        """
        Update multiple users in optimized batches.
        
        Args:
            updates: Dict mapping user_id to update data
            batch_size: Number of users to process per batch
            
        Returns:
            List of updated User objects
        """
        if not updates:
            return []
            
        updated_users = []
        user_ids = list(updates.keys())
        
        # Process in batches
        for i in range(0, len(user_ids), batch_size):
            batch_ids = user_ids[i:i + batch_size]
            batch_updates = {uid: updates[uid] for uid in batch_ids}
            batch_users = await self._update_batch_chunk(batch_updates)
            updated_users.extend(batch_users)
            
        self.logger.info(f"Updated {len(updated_users)} users in batches")
        return updated_users
    
    async def _update_batch_chunk(self, updates: Dict[str, Dict[str, Any]]) -> List[User]:
        """Update a single batch chunk of users."""
        session = await get_session()
        try:
            updated_users = []
            
            # Fetch existing users
            user_ids = list(updates.keys())
            stmt = select(UserDB).where(UserDB.id.in_(user_ids))
            result = await session.execute(stmt)
            user_dbs = result.scalars().all()
            
            user_db_map = {user_db.id: user_db for user_db in user_dbs}
            
            # Apply updates
            for user_id, update_data in updates.items():
                if user_id not in user_db_map:
                    continue
                    
                user_db = user_db_map[user_id]
                
                # Update fields
                for field, value in update_data.items():
                    if field == 'status' and hasattr(UserStatus, value):
                        user_db.status = value
                    elif field == 'email':
                        user_db.email = value
                    elif field == 'expires_at':
                        user_db.expires_at = value
                        
                user_db.updated_at = datetime.utcnow()
                
                # Convert back to User model
                user = await self._user_db_to_model(user_db)
                updated_users.append(user)
                
                # Update cache
                self._user_cache[user.id] = user
            
            await session.commit()
            return updated_users
            
        except Exception as e:
            await session.rollback()
            self.logger.error(f"Failed to update user batch: {e}")
            raise DatabaseError(f"Batch user update failed: {str(e)}")
        finally:
            await session.close()
    
    @with_retry()
    async def delete_users_batch(
        self, 
        user_ids: List[str], 
        batch_size: int = 100
    ) -> int:
        """
        Delete multiple users in optimized batches.
        
        Args:
            user_ids: List of user IDs to delete
            batch_size: Number of users to process per batch
            
        Returns:
            Number of deleted users
        """
        if not user_ids:
            return 0
            
        total_deleted = 0
        
        # Process in batches
        for i in range(0, len(user_ids), batch_size):
            batch_ids = user_ids[i:i + batch_size]
            deleted_count = await self._delete_batch_chunk(batch_ids)
            total_deleted += deleted_count
            
        self.logger.info(f"Deleted {total_deleted} users in batches")
        return total_deleted
    
    async def _delete_batch_chunk(self, user_ids: List[str]) -> int:
        """Delete a single batch chunk of users."""
        session = await get_session()
        try:
            # Bulk delete
            stmt = delete(UserDB).where(UserDB.id.in_(user_ids))
            result = await session.execute(stmt)
            deleted_count = result.rowcount
            
            await session.commit()
            
            # Remove from cache
            for user_id in user_ids:
                self._user_cache.pop(user_id, None)
                
            return deleted_count
            
        except Exception as e:
            await session.rollback()
            self.logger.error(f"Failed to delete user batch: {e}")
            raise DatabaseError(f"Batch user deletion failed: {str(e)}")
        finally:
            await session.close()
    
    @with_retry()
    async def get_users_batch(
        self, 
        user_ids: List[str], 
        use_cache: bool = True
    ) -> List[User]:
        """
        Get multiple users in a single optimized query.
        
        Args:
            user_ids: List of user IDs to fetch
            use_cache: Whether to use cache for lookup
            
        Returns:
            List of User objects
        """
        if not user_ids:
            return []
            
        users = []
        missing_ids = []
        
        # Check cache first if enabled
        if use_cache:
            for user_id in user_ids:
                if user_id in self._user_cache:
                    users.append(self._user_cache[user_id])
                else:
                    missing_ids.append(user_id)
        else:
            missing_ids = user_ids
        
        # Fetch missing users from database
        if missing_ids:
            session = await get_session()
            try:
                stmt = select(UserDB).where(UserDB.id.in_(missing_ids))
                result = await session.execute(stmt)
                user_dbs = result.scalars().all()
                
                for user_db in user_dbs:
                    user = await self._user_db_to_model(user_db)
                    users.append(user)
                    
                    # Update cache
                    if use_cache:
                        self._user_cache[user.id] = user
                        
            except Exception as e:
                self.logger.error(f"Failed to fetch user batch: {e}")
                raise DatabaseError(f"Batch user fetch failed: {str(e)}")
            finally:
                await session.close()
        
        self.logger.debug(f"Fetched {len(users)} users in batch")
        return users
    
    async def _prepare_user_from_data(self, user_data: Dict[str, Any]) -> User:
        """Prepare a User object from input data."""
        # Generate crypto keys
        crypto_service = CryptoService()
        keys = await crypto_service.generate_keys(
            ProtocolType(user_data.get('protocol_type', 'vless'))
        )
        
        # Create user object with all required fields
        user = User(
            id=str(uuid4()),
            username=user_data['username'],
            email=user_data.get('email', ''),
            status=UserStatus(user_data.get('status', 'active')),
            protocol=ProtocolConfig(
                type=ProtocolType(user_data.get('protocol_type', 'vless')),
                port=user_data.get('port', 8443),
                settings=user_data.get('protocol_settings', {})
            ),
            connection_info=ConnectionInfo(
                server_ip=user_data.get('server_ip', ''),
                server_port=user_data.get('port', 8443),
                client_id=keys.get('client_id', ''),
                public_key=keys.get('public_key', ''),
                private_key=keys.get('private_key', '')
            ),
            traffic=TrafficStats(),
            crypto_keys=CryptoKeys(
                public_key=keys.get('public_key', ''),
                private_key=keys.get('private_key', ''),
                shared_secret=keys.get('shared_secret', '')
            ),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
            expires_at=user_data.get('expires_at')
        )
        
        return user
    
    # Query Optimization Methods
    
    @with_retry()
    async def list_users_optimized(
        self,
        filters: Optional[QueryFilters] = None,
        pagination: Optional[PaginationParams] = None,
        include_relations: bool = False,
        order_by: str = "created_at",
        order_desc: bool = True
    ) -> PaginatedResult:
        """
        Optimized user listing with filtering, pagination, and performance features.
        
        Args:
            filters: Query filters to apply
            pagination: Pagination parameters
            include_relations: Whether to include related data with joinedload
            order_by: Field to order by
            order_desc: Whether to order in descending order
            
        Returns:
            PaginatedResult with users and metadata
        """
        session = await get_session()
        try:
            # Build base query
            stmt = select(UserDB)
            
            # Apply filters
            if filters:
                stmt = self._apply_filters(stmt, filters)
            
            # Add eager loading for relations if requested
            if include_relations:
                # Note: This would be implemented if UserDB had relationships
                # stmt = stmt.options(joinedload(UserDB.some_relation))
                pass
            
            # Get total count for pagination (before applying limit/offset)
            count_stmt = select(func.count()).select_from(stmt.alias())
            count_result = await session.execute(count_stmt)
            total_count = count_result.scalar()
            
            # Apply ordering
            order_column = getattr(UserDB, order_by, UserDB.created_at)
            if order_desc:
                stmt = stmt.order_by(order_column.desc())
            else:
                stmt = stmt.order_by(order_column)
            
            # Apply pagination
            if pagination:
                stmt = stmt.offset(pagination.offset).limit(pagination.page_size)
                page = pagination.page
                page_size = pagination.page_size
            else:
                page = 1
                page_size = total_count
            
            # Execute query
            result = await session.execute(stmt)
            user_dbs = result.scalars().all()
            
            # Convert to User models
            users = []
            for user_db in user_dbs:
                user = await self._user_db_to_model(user_db)
                users.append(user)
                
                # Update cache
                self._user_cache[user.id] = user
            
            # Calculate pagination metadata
            total_pages = (total_count + page_size - 1) // page_size if page_size > 0 else 1
            has_next = page < total_pages
            has_previous = page > 1
            
            return PaginatedResult(
                items=users,
                total_count=total_count,
                page=page,
                page_size=page_size,
                total_pages=total_pages,
                has_next=has_next,
                has_previous=has_previous
            )
            
        except Exception as e:
            self.logger.error(f"Failed to list users optimized: {e}")
            raise DatabaseError(f"Optimized user listing failed: {str(e)}")
        finally:
            await session.close()
    
    def _apply_filters(self, stmt: Select, filters: QueryFilters) -> Select:
        """Apply query filters to SQLAlchemy statement."""
        conditions = []
        
        if filters.username:
            if '*' in filters.username or '%' in filters.username:
                # Wildcard search
                pattern = filters.username.replace('*', '%')
                conditions.append(UserDB.username.like(pattern))
            else:
                # Exact match
                conditions.append(UserDB.username == filters.username)
        
        if filters.email:
            if '*' in filters.email or '%' in filters.email:
                pattern = filters.email.replace('*', '%')
                conditions.append(UserDB.email.like(pattern))
            else:
                conditions.append(UserDB.email == filters.email)
        
        if filters.status:
            conditions.append(UserDB.status == filters.status)
        
        if filters.protocol_type:
            # Note: This would need to be adapted based on how protocol is stored
            conditions.append(UserDB.protocol.like(f'%"type": "{filters.protocol_type}"%'))
        
        if filters.created_after:
            conditions.append(UserDB.created_at >= filters.created_after)
        
        if filters.created_before:
            conditions.append(UserDB.created_at <= filters.created_before)
        
        if filters.expires_after:
            conditions.append(UserDB.expires_at >= filters.expires_after)
        
        if filters.expires_before:
            conditions.append(UserDB.expires_at <= filters.expires_before)
        
        if conditions:
            stmt = stmt.where(and_(*conditions))
        
        return stmt
    
    @with_retry()
    async def search_users_full_text(
        self,
        search_term: str,
        pagination: Optional[PaginationParams] = None
    ) -> PaginatedResult:
        """
        Full-text search across user fields with optimization.
        
        Args:
            search_term: Search term to look for
            pagination: Pagination parameters
            
        Returns:
            PaginatedResult with matching users
        """
        session = await get_session()
        try:
            search_pattern = f"%{search_term}%"
            
            # Build search query across multiple fields
            stmt = select(UserDB).where(
                or_(
                    UserDB.username.like(search_pattern),
                    UserDB.email.like(search_pattern),
                    UserDB.protocol.like(search_pattern),
                    UserDB.connection_info.like(search_pattern)
                )
            )
            
            # Get total count
            count_stmt = select(func.count()).select_from(stmt.alias())
            count_result = await session.execute(count_stmt)
            total_count = count_result.scalar()
            
            # Apply pagination
            if pagination:
                stmt = stmt.offset(pagination.offset).limit(pagination.page_size)
                page = pagination.page
                page_size = pagination.page_size
            else:
                page = 1
                page_size = total_count
            
            # Order by relevance (username matches first)
            stmt = stmt.order_by(
                func.case(
                    (UserDB.username.like(search_pattern), 1),
                    (UserDB.email.like(search_pattern), 2),
                    else_=3
                )
            )
            
            # Execute query
            result = await session.execute(stmt)
            user_dbs = result.scalars().all()
            
            # Convert to User models
            users = []
            for user_db in user_dbs:
                user = await self._user_db_to_model(user_db)
                users.append(user)
            
            # Calculate pagination metadata
            total_pages = (total_count + page_size - 1) // page_size if page_size > 0 else 1
            has_next = page < total_pages
            has_previous = page > 1
            
            return PaginatedResult(
                items=users,
                total_count=total_count,
                page=page,
                page_size=page_size,
                total_pages=total_pages,
                has_next=has_next,
                has_previous=has_previous
            )
            
        except Exception as e:
            self.logger.error(f"Failed to search users: {e}")
            raise DatabaseError(f"User search failed: {str(e)}")
        finally:
            await session.close()
    
    @with_retry()
    async def get_user_statistics_optimized(self) -> Dict[str, Any]:
        """
        Get user statistics using optimized aggregation queries.
        
        Returns:
            Dictionary with comprehensive user statistics
        """
        session = await get_session()
        try:
            # Single query to get all basic counts
            stats_query = select(
                func.count(UserDB.id).label('total_users'),
                func.count(func.case((UserDB.status == 'active', 1))).label('active_users'),
                func.count(func.case((UserDB.status == 'inactive', 1))).label('inactive_users'),
                func.count(func.case((UserDB.status == 'expired', 1))).label('expired_users'),
                func.count(func.case((UserDB.expires_at < func.now(), 1))).label('expired_by_date')
            )
            
            result = await session.execute(stats_query)
            stats = result.first()
            
            # Protocol distribution query
            protocol_query = select(
                UserDB.protocol,
                func.count(UserDB.id).label('count')
            ).group_by(UserDB.protocol)
            
            protocol_result = await session.execute(protocol_query)
            protocol_stats = {}
            
            for row in protocol_result:
                try:
                    protocol_data = json.loads(row.protocol)
                    protocol_type = protocol_data.get('type', 'unknown')
                    protocol_stats[protocol_type] = row.count
                except (json.JSONDecodeError, AttributeError):
                    protocol_stats['unknown'] = protocol_stats.get('unknown', 0) + row.count
            
            # Recent activity query (users created in last 30 days)
            recent_activity_query = select(
                func.count(UserDB.id).label('recent_users')
            ).where(
                UserDB.created_at >= func.date_sub(func.now(), text('INTERVAL 30 DAY'))
            )
            
            recent_result = await session.execute(recent_activity_query)
            recent_count = recent_result.scalar()
            
            return {
                'total_users': stats.total_users,
                'active_users': stats.active_users,
                'inactive_users': stats.inactive_users,
                'expired_users': stats.expired_users,
                'expired_by_date': stats.expired_by_date,
                'protocols': protocol_stats,
                'recent_users_30d': recent_count,
                'cache_size': len(self._user_cache),
                'last_updated': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            self.logger.error(f"Failed to get optimized user statistics: {e}")
            raise DatabaseError(f"Statistics query failed: {str(e)}")
        finally:
            await session.close()
    
    @with_retry()
    async def bulk_update_status(
        self,
        user_ids: List[str],
        new_status: str,
        batch_size: int = 100
    ) -> int:
        """
        Bulk update user status using optimized SQL.
        
        Args:
            user_ids: List of user IDs to update
            new_status: New status to set
            batch_size: Number of users to update per batch
            
        Returns:
            Number of users updated
        """
        if not user_ids:
            return 0
            
        total_updated = 0
        
        # Process in batches
        for i in range(0, len(user_ids), batch_size):
            batch_ids = user_ids[i:i + batch_size]
            updated_count = await self._bulk_update_status_chunk(batch_ids, new_status)
            total_updated += updated_count
        
        self.logger.info(f"Bulk updated status for {total_updated} users")
        return total_updated
    
    async def _bulk_update_status_chunk(self, user_ids: List[str], new_status: str) -> int:
        """Update status for a batch of users."""
        session = await get_session()
        try:
            # Bulk update using SQLAlchemy
            stmt = update(UserDB).where(
                UserDB.id.in_(user_ids)
            ).values(
                status=new_status,
                updated_at=func.now()
            )
            
            result = await session.execute(stmt)
            updated_count = result.rowcount
            
            await session.commit()
            
            # Update cache
            for user_id in user_ids:
                if user_id in self._user_cache:
                    self._user_cache[user_id].status = UserStatus(new_status)
                    self._user_cache[user_id].updated_at = datetime.utcnow()
            
            return updated_count
            
        except Exception as e:
            await session.rollback()
            self.logger.error(f"Failed to bulk update status: {e}")
            raise DatabaseError(f"Bulk status update failed: {str(e)}")
        finally:
            await session.close()