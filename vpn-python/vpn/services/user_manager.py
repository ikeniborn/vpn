"""
User management service.
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
from vpn.services.base import CRUDService, EventEmitter
from vpn.services.crypto import CryptoService
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class UserManager(CRUDService[User], EventEmitter):
    """Service for managing VPN users."""
    
    def __init__(self, session: Optional[AsyncSession] = None):
        """Initialize user manager."""
        super().__init__(session)
        self.crypto_service = CryptoService()
        self._user_cache: Dict[str, User] = {}
    
    async def create(
        self,
        username: str,
        protocol: str | ProtocolType,
        email: Optional[str] = None,
        **kwargs
    ) -> User:
        """
        Create a new user.
        
        Args:
            username: Username (will be normalized)
            protocol: VPN protocol type
            email: Optional email address
            **kwargs: Additional user attributes
            
        Returns:
            Created user
            
        Raises:
            UserAlreadyExistsError: If username already exists
            ValidationError: If validation fails
        """
        # Normalize username
        username = username.lower().strip()
        
        # Check if user exists
        if await self.get_by_username(username):
            raise UserAlreadyExistsError(username)
        
        # Create protocol config
        if isinstance(protocol, str):
            protocol = ProtocolType(protocol)
        
        protocol_config = ProtocolConfig(type=protocol)
        
        # Generate keys based on protocol
        keys = await self.crypto_service.generate_keys(protocol)
        
        # Create user model
        user = User(
            username=username,
            email=email,
            protocol=protocol_config,
            keys=keys,
            **kwargs
        )
        
        # Save to database
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            user_data = user.model_dump(mode="json")
            await db_manager.create_user(user_data)
        
        # Save configuration files
        await self._save_user_config(user)
        
        # Emit event
        await self.emit("user.created", user)
        
        logger.info(f"Created user: {username}")
        return user
    
    async def get(self, user_id: str) -> Optional[User]:
        """Get user by ID."""
        # Check cache first
        if user_id in self._user_cache:
            return self._user_cache[user_id]
        
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            user_db = await db_manager.get_user(user_id)
            
            if not user_db:
                return None
            
            user = self._db_to_model(user_db)
            self._user_cache[user_id] = user
            return user
    
    async def get_by_username(self, username: str) -> Optional[User]:
        """Get user by username."""
        username = username.lower().strip()
        
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            user_db = await db_manager.get_user_by_username(username)
            
            if not user_db:
                return None
            
            return self._db_to_model(user_db)
    
    async def list(
        self,
        status: Optional[UserStatus] = None,
        limit: Optional[int] = None,
        offset: int = 0,
    ) -> List[User]:
        """
        List users with optional filters.
        
        Args:
            status: Filter by user status
            limit: Maximum number of results
            offset: Offset for pagination
            
        Returns:
            List of users
        """
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            users_db = await db_manager.list_users(
                status=status.value if status else None
            )
            
            # Apply pagination
            if offset:
                users_db = users_db[offset:]
            if limit:
                users_db = users_db[:limit]
            
            return [self._db_to_model(u) for u in users_db]
    
    async def update(
        self,
        user_id: str,
        **kwargs
    ) -> Optional[User]:
        """
        Update user attributes.
        
        Args:
            user_id: User ID
            **kwargs: Attributes to update
            
        Returns:
            Updated user or None if not found
        """
        user = await self.get(user_id)
        if not user:
            return None
        
        # Update model
        update_data = {}
        for key, value in kwargs.items():
            if hasattr(user, key):
                setattr(user, key, value)
                update_data[key] = value
        
        # Update database
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            user_db = await db_manager.update_user(user_id, update_data)
            
            if not user_db:
                return None
        
        # Update cache
        self._user_cache[user_id] = user
        
        # Update config files
        await self._save_user_config(user)
        
        # Emit event
        await self.emit("user.updated", user)
        
        logger.info(f"Updated user: {user.username}")
        return user
    
    async def delete(self, user_id: str) -> bool:
        """
        Delete user.
        
        Args:
            user_id: User ID
            
        Returns:
            True if deleted, False if not found
        """
        user = await self.get(user_id)
        if not user:
            return False
        
        # Delete from database
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            deleted = await db_manager.delete_user(user_id)
            
            if not deleted:
                return False
        
        # Remove from cache
        if user_id in self._user_cache:
            del self._user_cache[user_id]
        
        # Delete config files
        await self._delete_user_config(user)
        
        # Emit event
        await self.emit("user.deleted", user)
        
        logger.info(f"Deleted user: {user.username}")
        return True
    
    async def update_status(
        self,
        user_id: str,
        status: UserStatus
    ) -> Optional[User]:
        """Update user status."""
        return await self.update(user_id, status=status)
    
    async def reset_traffic(self, user_id: str) -> Optional[User]:
        """Reset user traffic statistics."""
        user = await self.get(user_id)
        if not user:
            return None
        
        user.traffic = TrafficStats()
        return await self.update(user_id, traffic=user.traffic.model_dump())
    
    async def update_traffic(
        self,
        user_id: str,
        upload_bytes: int = 0,
        download_bytes: int = 0
    ) -> Optional[User]:
        """Update user traffic statistics."""
        user = await self.get(user_id)
        if not user:
            return None
        
        user.traffic.upload_bytes += upload_bytes
        user.traffic.download_bytes += download_bytes
        user.traffic.total_bytes += upload_bytes + download_bytes
        
        # Log to database
        async with get_session() as session:
            db_manager = DatabaseManager(session)
            await db_manager.log_traffic(user_id, upload_bytes, download_bytes)
        
        return await self.update(user_id, traffic=user.traffic.model_dump())
    
    async def generate_connection_info(
        self,
        user_id: str,
        server_address: str,
        server_port: int
    ) -> ConnectionInfo:
        """
        Generate connection information for user.
        
        Args:
            user_id: User ID
            server_address: Server address/IP
            server_port: Server port
            
        Returns:
            Connection information with link and QR code
        """
        user = await self.get(user_id)
        if not user:
            raise UserNotFoundError(f"User ID: {user_id}")
        
        # Generate connection link based on protocol
        link = await self._generate_connection_link(user, server_address, server_port)
        
        # Generate QR code
        qr_code = await self.crypto_service.generate_qr_code(link)
        
        return ConnectionInfo(
            user_id=user.id,
            protocol=user.protocol.type,
            server_address=server_address,
            server_port=server_port,
            connection_link=link,
            qr_code=qr_code,
            instructions=self._get_protocol_instructions(user.protocol.type)
        )
    
    # Batch operations
    
    async def create_batch(
        self,
        users_data: List[Dict]
    ) -> List[User]:
        """Create multiple users from list of data."""
        created_users = []
        
        for user_data in users_data:
            try:
                user = await self.create(**user_data)
                created_users.append(user)
            except Exception as e:
                logger.error(f"Failed to create user {user_data.get('username')}: {e}")
        
        return created_users
    
    async def delete_batch(self, user_ids: List[str]) -> int:
        """Delete multiple users by IDs."""
        deleted_count = 0
        
        for user_id in user_ids:
            if await self.delete(user_id):
                deleted_count += 1
        
        return deleted_count
    
    async def update_status_batch(
        self,
        user_ids: List[str],
        status: UserStatus
    ) -> int:
        """Update status for multiple users."""
        updated_count = 0
        
        for user_id in user_ids:
            if await self.update_status(user_id, status):
                updated_count += 1
        
        return updated_count
    
    # Import/Export operations
    
    async def export_users(
        self,
        format: str = "json",
        include_keys: bool = False
    ) -> str:
        """
        Export all users to specified format.
        
        Args:
            format: Export format (json, csv, yaml)
            include_keys: Include sensitive key data
            
        Returns:
            Exported data as string
        """
        users = await self.list()
        
        if format == "json":
            data = []
            for user in users:
                user_dict = user.model_dump(mode="json")
                if not include_keys:
                    user_dict.pop("keys", None)
                data.append(user_dict)
            return json.dumps(data, indent=2)
        
        elif format == "csv":
            import csv
            import io
            
            output = io.StringIO()
            if users:
                fieldnames = ["id", "username", "email", "status", "protocol", "created_at"]
                writer = csv.DictWriter(output, fieldnames=fieldnames)
                writer.writeheader()
                
                for user in users:
                    writer.writerow({
                        "id": str(user.id),
                        "username": user.username,
                        "email": user.email or "",
                        "status": user.status.value,
                        "protocol": user.protocol.type.value,
                        "created_at": user.created_at.isoformat()
                    })
            
            return output.getvalue()
        
        else:
            raise ValueError(f"Unsupported export format: {format}")
    
    async def import_users(
        self,
        data: str,
        format: str = "json",
        skip_existing: bool = True
    ) -> Dict[str, int]:
        """
        Import users from data.
        
        Args:
            data: Import data as string
            format: Import format (json, csv)
            skip_existing: Skip users that already exist
            
        Returns:
            Dictionary with import statistics
        """
        stats = {"imported": 0, "skipped": 0, "failed": 0}
        
        if format == "json":
            users_data = json.loads(data)
            
            for user_data in users_data:
                username = user_data.get("username")
                
                if skip_existing and await self.get_by_username(username):
                    stats["skipped"] += 1
                    continue
                
                try:
                    await self.create(**user_data)
                    stats["imported"] += 1
                except Exception as e:
                    logger.error(f"Failed to import user {username}: {e}")
                    stats["failed"] += 1
        
        else:
            raise ValueError(f"Unsupported import format: {format}")
        
        return stats
    
    # Private methods
    
    def _db_to_model(self, user_db: UserDB) -> User:
        """Convert database model to Pydantic model."""
        return User(
            id=user_db.id,
            username=user_db.username,
            email=user_db.email,
            status=UserStatus(user_db.status),
            protocol=ProtocolConfig(**user_db.protocol),
            keys=CryptoKeys(**user_db.keys),
            traffic=TrafficStats(**user_db.traffic),
            created_at=user_db.created_at,
            updated_at=user_db.updated_at,
            expires_at=user_db.expires_at,
            notes=user_db.notes
        )
    
    async def _save_user_config(self, user: User) -> None:
        """Save user configuration to file."""
        user_dir = self.settings.get_user_data_path(user.username)
        config_file = user_dir / "config.json"
        
        config_data = user.model_dump(mode="json")
        config_file.write_text(json.dumps(config_data, indent=2))
    
    async def _delete_user_config(self, user: User) -> None:
        """Delete user configuration files."""
        user_dir = self.settings.get_user_data_path(user.username)
        if user_dir.exists():
            import shutil
            shutil.rmtree(user_dir)
    
    async def _generate_connection_link(
        self,
        user: User,
        server_address: str,
        server_port: int
    ) -> str:
        """Generate connection link based on protocol."""
        if user.protocol.type == ProtocolType.VLESS:
            # VLESS link format
            return (
                f"vless://{user.keys.uuid}@{server_address}:{server_port}"
                f"?encryption={user.protocol.encryption or 'none'}"
                f"&type=tcp"
                f"&security=reality"
                f"&pbk={user.protocol.reality_public_key or ''}"
                f"&sid={user.protocol.reality_short_id or ''}"
                f"#{user.username}"
            )
        
        elif user.protocol.type == ProtocolType.SHADOWSOCKS:
            # Shadowsocks link format
            import base64
            auth = f"{user.protocol.method}:{user.keys.password}"
            encoded = base64.b64encode(auth.encode()).decode()
            return f"ss://{encoded}@{server_address}:{server_port}#{user.username}"
        
        else:
            # Generic format for other protocols
            return f"{user.protocol.type.value}://{user.username}@{server_address}:{server_port}"
    
    def _get_protocol_instructions(self, protocol: ProtocolType) -> str:
        """Get connection instructions for protocol."""
        instructions = {
            ProtocolType.VLESS: "Use any Xray/V2Ray compatible client",
            ProtocolType.SHADOWSOCKS: "Use Shadowsocks client or Outline",
            ProtocolType.WIREGUARD: "Use WireGuard client",
            ProtocolType.HTTP: "Configure HTTP proxy in your browser/system",
            ProtocolType.SOCKS5: "Configure SOCKS5 proxy in your application",
        }
        return instructions.get(protocol, "Follow protocol-specific instructions")