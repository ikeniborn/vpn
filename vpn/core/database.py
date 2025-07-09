"""
Database models and session management using SQLAlchemy.
"""

from datetime import datetime
from typing import AsyncGenerator, Optional

from sqlalchemy import JSON, Boolean, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.ext.asyncio import (
    AsyncAttrs,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from vpn.core.config import settings


class Base(AsyncAttrs, DeclarativeBase):
    """Base class for all database models."""
    pass


class UserDB(Base):
    """User database model."""
    
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("username", name="_username_uc"),
    )
    
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    username: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="active")
    protocol: Mapped[dict] = mapped_column(JSON, nullable=False)
    keys: Mapped[dict] = mapped_column(JSON, nullable=False)
    traffic: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)


class ServerDB(Base):
    """Server configuration database model."""
    
    __tablename__ = "servers"
    __table_args__ = (
        UniqueConstraint("name", name="_server_name_uc"),
    )
    
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    protocol: Mapped[dict] = mapped_column(JSON, nullable=False)
    port: Mapped[int] = mapped_column(Integer, nullable=False)
    docker_config: Mapped[dict] = mapped_column(JSON, nullable=False)
    firewall_rules: Mapped[dict] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(20), default="stopped")
    auto_start: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class TrafficLogDB(Base):
    """Traffic statistics log database model."""
    
    __tablename__ = "traffic_logs"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )
    upload_bytes: Mapped[int] = mapped_column(Integer, default=0)
    download_bytes: Mapped[int] = mapped_column(Integer, default=0)
    total_bytes: Mapped[int] = mapped_column(Integer, default=0)


class AlertDB(Base):
    """System alerts database model."""
    
    __tablename__ = "alerts"
    
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    level: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    source: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False, index=True
    )
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)
    acknowledged_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    resolved: Mapped[bool] = mapped_column(Boolean, default=False)
    resolved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class SystemStateDB(Base):
    """System state storage for persistence."""
    
    __tablename__ = "system_state"
    
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value: Mapped[dict] = mapped_column(JSON, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )


# Database engine and session management
engine = create_async_engine(
    settings.database_url,
    echo=settings.database_echo,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

# Session factory
async_session = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def init_database() -> None:
    """Initialize database tables."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """Get database session."""
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


class DatabaseManager:
    """Database operations manager."""
    
    def __init__(self, session: AsyncSession):
        self.session = session
    
    async def create_user(self, user_data: dict) -> UserDB:
        """Create a new user in the database."""
        user = UserDB(**user_data)
        self.session.add(user)
        await self.session.flush()
        return user
    
    async def get_user(self, user_id: str) -> Optional[UserDB]:
        """Get user by ID."""
        return await self.session.get(UserDB, user_id)
    
    async def get_user_by_username(self, username: str) -> Optional[UserDB]:
        """Get user by username."""
        from sqlalchemy import select
        
        stmt = select(UserDB).where(UserDB.username == username)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()
    
    async def list_users(self, status: Optional[str] = None) -> list[UserDB]:
        """List all users with optional status filter."""
        from sqlalchemy import select
        
        stmt = select(UserDB)
        if status:
            stmt = stmt.where(UserDB.status == status)
        
        result = await self.session.execute(stmt)
        return list(result.scalars().all())
    
    async def update_user(self, user_id: str, update_data: dict) -> Optional[UserDB]:
        """Update user data."""
        user = await self.get_user(user_id)
        if not user:
            return None
        
        for key, value in update_data.items():
            setattr(user, key, value)
        
        user.updated_at = datetime.utcnow()
        await self.session.flush()
        return user
    
    async def delete_user(self, user_id: str) -> bool:
        """Delete user."""
        user = await self.get_user(user_id)
        if not user:
            return False
        
        await self.session.delete(user)
        await self.session.flush()
        return True
    
    async def create_server(self, server_data: dict) -> ServerDB:
        """Create a new server configuration."""
        server = ServerDB(**server_data)
        self.session.add(server)
        await self.session.flush()
        return server
    
    async def get_server(self, server_id: str) -> Optional[ServerDB]:
        """Get server by ID."""
        return await self.session.get(ServerDB, server_id)
    
    async def get_server_by_name(self, name: str) -> Optional[ServerDB]:
        """Get server by name."""
        from sqlalchemy import select
        
        stmt = select(ServerDB).where(ServerDB.name == name)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()
    
    async def list_servers(self, status: Optional[str] = None) -> list[ServerDB]:
        """List all servers with optional status filter."""
        from sqlalchemy import select
        
        stmt = select(ServerDB)
        if status:
            stmt = stmt.where(ServerDB.status == status)
        
        result = await self.session.execute(stmt)
        return list(result.scalars().all())
    
    async def log_traffic(self, user_id: str, upload: int, download: int) -> None:
        """Log traffic statistics."""
        log = TrafficLogDB(
            user_id=user_id,
            upload_bytes=upload,
            download_bytes=download,
            total_bytes=upload + download,
        )
        self.session.add(log)
        await self.session.flush()
    
    async def get_user_traffic_stats(
        self, user_id: str, since: Optional[datetime] = None
    ) -> dict:
        """Get user traffic statistics."""
        from sqlalchemy import func, select
        
        stmt = select(
            func.sum(TrafficLogDB.upload_bytes).label("upload"),
            func.sum(TrafficLogDB.download_bytes).label("download"),
            func.sum(TrafficLogDB.total_bytes).label("total"),
        ).where(TrafficLogDB.user_id == user_id)
        
        if since:
            stmt = stmt.where(TrafficLogDB.timestamp >= since)
        
        result = await self.session.execute(stmt)
        row = result.one()
        
        return {
            "upload_bytes": row.upload or 0,
            "download_bytes": row.download or 0,
            "total_bytes": row.total or 0,
        }
    
    async def create_alert(self, alert_data: dict) -> AlertDB:
        """Create a new alert."""
        alert = AlertDB(**alert_data)
        self.session.add(alert)
        await self.session.flush()
        return alert
    
    async def get_active_alerts(self) -> list[AlertDB]:
        """Get all active (unresolved) alerts."""
        from sqlalchemy import select
        
        stmt = select(AlertDB).where(AlertDB.resolved == False)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())
    
    async def save_state(self, key: str, value: dict) -> None:
        """Save system state."""
        from sqlalchemy import select
        
        stmt = select(SystemStateDB).where(SystemStateDB.key == key)
        result = await self.session.execute(stmt)
        state = result.scalar_one_or_none()
        
        if state:
            state.value = value
            state.updated_at = datetime.utcnow()
        else:
            state = SystemStateDB(key=key, value=value)
            self.session.add(state)
        
        await self.session.flush()
    
    async def get_state(self, key: str) -> Optional[dict]:
        """Get system state."""
        from sqlalchemy import select
        
        stmt = select(SystemStateDB).where(SystemStateDB.key == key)
        result = await self.session.execute(stmt)
        state = result.scalar_one_or_none()
        
        return state.value if state else None