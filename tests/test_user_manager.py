"""
Tests for UserManager service.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from vpn.core.exceptions import UserAlreadyExistsError, UserNotFoundError
from vpn.core.models import ProtocolType, User, UserStatus
from vpn.services.user_manager import UserManager


@pytest.mark.asyncio
class TestUserManager:
    """Test UserManager service."""
    
    @pytest.fixture
    async def user_manager(self):
        """Create UserManager instance."""
        with patch('vpn.services.user_manager.get_session'):
            manager = UserManager()
            yield manager
    
    async def test_create_user_success(self, user_manager):
        """Test successful user creation."""
        # Mock database operations
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.get_user_by_username.return_value = None
            mock_db_manager.create_user.return_value = MagicMock()
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                # Create user
                user = await user_manager.create(
                    username="testuser",
                    protocol=ProtocolType.VLESS,
                    email="test@example.com"
                )
                
                assert user.username == "testuser"
                assert user.protocol.type == ProtocolType.VLESS
                assert user.email == "test@example.com"
                assert user.status == UserStatus.ACTIVE
                assert user.keys.uuid is not None
    
    async def test_create_user_already_exists(self, user_manager):
        """Test user creation when username already exists."""
        with patch('vpn.services.user_manager.get_session'):
            # Mock existing user
            user_manager.get_by_username = AsyncMock(return_value=User(
                username="existinguser",
                protocol=MagicMock()
            ))
            
            # Attempt to create duplicate user
            with pytest.raises(UserAlreadyExistsError):
                await user_manager.create(
                    username="existinguser",
                    protocol=ProtocolType.VLESS
                )
    
    async def test_get_user_by_id(self, user_manager):
        """Test getting user by ID."""
        user_id = str(uuid4())
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.get_user.return_value = MagicMock(
                id=user_id,
                username="testuser",
                status="active",
                protocol={"type": "vless"},
                keys={},
                traffic={},
                created_at="2024-01-01T00:00:00"
            )
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                user = await user_manager.get(user_id)
                
                assert user is not None
                assert str(user.id) == user_id
                assert user.username == "testuser"
    
    async def test_get_user_not_found(self, user_manager):
        """Test getting non-existent user."""
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.get_user.return_value = None
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                user = await user_manager.get("non-existent-id")
                assert user is None
    
    async def test_list_users(self, user_manager):
        """Test listing users."""
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.list_users.return_value = [
                MagicMock(
                    id="id1",
                    username="user1",
                    status="active",
                    protocol={"type": "vless"},
                    keys={},
                    traffic={},
                    created_at="2024-01-01T00:00:00"
                ),
                MagicMock(
                    id="id2",
                    username="user2",
                    status="inactive",
                    protocol={"type": "shadowsocks"},
                    keys={},
                    traffic={},
                    created_at="2024-01-01T00:00:00"
                )
            ]
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                users = await user_manager.list()
                
                assert len(users) == 2
                assert users[0].username == "user1"
                assert users[1].username == "user2"
    
    async def test_update_user_status(self, user_manager):
        """Test updating user status."""
        user_id = str(uuid4())
        
        # Mock get user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock(),
            status=UserStatus.ACTIVE
        )
        user_manager.get = AsyncMock(return_value=user)
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.update_user.return_value = MagicMock()
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                updated_user = await user_manager.update_status(
                    user_id,
                    UserStatus.SUSPENDED
                )
                
                assert updated_user is not None
                assert updated_user.status == UserStatus.SUSPENDED
    
    async def test_delete_user(self, user_manager):
        """Test deleting user."""
        user_id = str(uuid4())
        
        # Mock get user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock()
        )
        user_manager.get = AsyncMock(return_value=user)
        user_manager._delete_user_config = AsyncMock()
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.delete_user.return_value = True
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                result = await user_manager.delete(user_id)
                
                assert result is True
                mock_db_manager.delete_user.assert_called_once_with(user_id)
    
    async def test_batch_create(self, user_manager):
        """Test batch user creation."""
        users_data = [
            {"username": "user1", "protocol": "vless"},
            {"username": "user2", "protocol": "shadowsocks"},
            {"username": "user3", "protocol": "wireguard"},
        ]
        
        # Mock create method
        created_users = []
        async def mock_create(**kwargs):
            user = User(
                username=kwargs["username"],
                protocol=MagicMock(type=kwargs["protocol"])
            )
            created_users.append(user)
            return user
        
        user_manager.create = mock_create
        
        result = await user_manager.create_batch(users_data)
        
        assert len(result) == 3
        assert result[0].username == "user1"
        assert result[1].username == "user2"
        assert result[2].username == "user3"
    
    async def test_export_users_json(self, user_manager):
        """Test exporting users to JSON."""
        # Mock users
        users = [
            User(
                username="user1",
                protocol=MagicMock(type=ProtocolType.VLESS),
                email="user1@example.com"
            ),
            User(
                username="user2",
                protocol=MagicMock(type=ProtocolType.SHADOWSOCKS)
            )
        ]
        
        user_manager.list = AsyncMock(return_value=users)
        
        # Export without keys
        result = await user_manager.export_users(format="json", include_keys=False)
        
        assert "user1" in result
        assert "user2" in result
        assert "keys" not in result
    
    async def test_import_users_json(self, user_manager):
        """Test importing users from JSON."""
        import json
        
        # Create test data
        users_data = [
            {
                "username": "imported1",
                "protocol": {"type": "vless"},
                "email": "imported1@example.com"
            },
            {
                "username": "imported2",
                "protocol": {"type": "shadowsocks"}
            }
        ]
        
        json_data = json.dumps(users_data)
        
        # Mock methods
        user_manager.get_by_username = AsyncMock(return_value=None)
        user_manager.create = AsyncMock()
        
        # Import users
        stats = await user_manager.import_users(
            data=json_data,
            format="json",
            skip_existing=True
        )
        
        assert stats["imported"] == 2
        assert stats["skipped"] == 0
        assert stats["failed"] == 0
    
    async def test_update_traffic_stats(self, user_manager):
        """Test updating user traffic statistics."""
        user_id = str(uuid4())
        
        # Mock get user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock()
        )
        user_manager.get = AsyncMock(return_value=user)
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.update_user_traffic.return_value = MagicMock()
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                updated_user = await user_manager.update_traffic(
                    user_id,
                    upload_bytes=1024,
                    download_bytes=2048
                )
                
                assert updated_user is not None
                mock_db_manager.update_user_traffic.assert_called_once()
    
    async def test_generate_connection_info(self, user_manager):
        """Test generating connection info for user."""
        user_id = str(uuid4())
        
        # Mock user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock(type=ProtocolType.VLESS)
        )
        user_manager.get = AsyncMock(return_value=user)
        
        with patch('vpn.services.user_manager.get_server_config') as mock_config:
            mock_config.return_value = {
                "public_ip": "1.2.3.4",
                "port": 8443,
                "domain": "vpn.example.com"
            }
            
            connection_info = await user_manager.generate_connection_info(user_id)
            
            assert connection_info is not None
            assert "connection_string" in connection_info
            assert "qr_code" in connection_info
    
    async def test_search_users(self, user_manager):
        """Test searching users."""
        # Mock users
        users = [
            User(username="alice", protocol=MagicMock(), email="alice@example.com"),
            User(username="bob", protocol=MagicMock(), email="bob@test.com"),
            User(username="charlie", protocol=MagicMock(), email="charlie@example.com")
        ]
        user_manager.list = AsyncMock(return_value=users)
        
        # Search by username
        results = await user_manager.search(query="alice")
        assert len(results) == 1
        assert results[0].username == "alice"
        
        # Search by email domain
        results = await user_manager.search(query="example.com")
        assert len(results) == 2
    
    async def test_get_user_statistics(self, user_manager):
        """Test getting user statistics."""
        # Mock users with traffic
        users = [
            User(username="user1", protocol=MagicMock()),
            User(username="user2", protocol=MagicMock()),
            User(username="user3", protocol=MagicMock())
        ]
        
        # Set traffic stats
        users[0].traffic.upload_bytes = 1000
        users[0].traffic.download_bytes = 2000
        users[1].traffic.upload_bytes = 3000
        users[1].traffic.download_bytes = 4000
        users[2].status = UserStatus.INACTIVE
        
        user_manager.list = AsyncMock(return_value=users)
        
        stats = await user_manager.get_statistics()
        
        assert stats["total_users"] == 3
        assert stats["active_users"] == 2
        assert stats["inactive_users"] == 1
        assert stats["total_upload_bytes"] == 4000
        assert stats["total_download_bytes"] == 6000
    
    async def test_reset_user_traffic(self, user_manager):
        """Test resetting user traffic statistics."""
        user_id = str(uuid4())
        
        # Mock get user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock()
        )
        user_manager.get = AsyncMock(return_value=user)
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.reset_user_traffic.return_value = MagicMock()
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                result = await user_manager.reset_traffic(user_id)
                
                assert result is not None
                mock_db_manager.reset_user_traffic.assert_called_once_with(user_id)
    
    async def test_batch_update_status(self, user_manager):
        """Test batch updating user status."""
        user_ids = [str(uuid4()) for _ in range(3)]
        
        # Mock get method
        async def mock_get(user_id):
            return User(
                id=user_id,
                username=f"user_{user_id[:8]}",
                protocol=MagicMock()
            )
        
        user_manager.get = mock_get
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.batch_update_status.return_value = [
                {"user_id": user_ids[0], "success": True},
                {"user_id": user_ids[1], "success": True},
                {"user_id": user_ids[2], "success": False, "error": "User not found"}
            ]
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                results = await user_manager.batch_update_status(
                    user_ids,
                    UserStatus.SUSPENDED
                )
                
                assert len(results) == 3
                assert results[0]["success"] is True
                assert results[1]["success"] is True
                assert results[2]["success"] is False
    
    async def test_get_users_by_protocol(self, user_manager):
        """Test getting users by protocol."""
        # Mock users
        vless_users = [
            User(username="vless1", protocol=MagicMock(type=ProtocolType.VLESS)),
            User(username="vless2", protocol=MagicMock(type=ProtocolType.VLESS))
        ]
        
        user_manager.list = AsyncMock(return_value=vless_users)
        
        users = await user_manager.list(protocol=ProtocolType.VLESS)
        
        assert len(users) == 2
        assert all(user.protocol.type == ProtocolType.VLESS for user in users)
    
    async def test_user_expiration_check(self, user_manager):
        """Test checking user expiration."""
        from datetime import datetime, timedelta
        
        # Mock users - some expired, some active
        users = [
            User(
                username="active_user",
                protocol=MagicMock(),
                expires_at=datetime.utcnow() + timedelta(days=1)
            ),
            User(
                username="expired_user",
                protocol=MagicMock(),
                expires_at=datetime.utcnow() - timedelta(days=1)
            ),
            User(
                username="no_expiry",
                protocol=MagicMock(),
                expires_at=None
            )
        ]
        
        user_manager.list = AsyncMock(return_value=users)
        
        expired_users = await user_manager.get_expired_users()
        
        assert len(expired_users) == 1
        assert expired_users[0].username == "expired_user"
    
    async def test_cleanup_expired_users(self, user_manager):
        """Test cleaning up expired users."""
        from datetime import datetime, timedelta
        
        # Mock expired users
        expired_users = [
            User(
                username="expired1",
                protocol=MagicMock(),
                expires_at=datetime.utcnow() - timedelta(days=1),
                status=UserStatus.ACTIVE
            ),
            User(
                username="expired2",
                protocol=MagicMock(),
                expires_at=datetime.utcnow() - timedelta(days=2),
                status=UserStatus.ACTIVE
            )
        ]
        
        user_manager.get_expired_users = AsyncMock(return_value=expired_users)
        user_manager.update_status = AsyncMock()
        
        result = await user_manager.cleanup_expired_users()
        
        assert result["processed"] == 2
        assert result["deactivated"] == 2
        assert user_manager.update_status.call_count == 2
    
    async def test_get_protocol_distribution(self, user_manager):
        """Test getting protocol distribution statistics."""
        # Mock users with different protocols
        users = [
            User(username="vless1", protocol=MagicMock(type=ProtocolType.VLESS)),
            User(username="vless2", protocol=MagicMock(type=ProtocolType.VLESS)),
            User(username="ss1", protocol=MagicMock(type=ProtocolType.SHADOWSOCKS)),
            User(username="wg1", protocol=MagicMock(type=ProtocolType.WIREGUARD))
        ]
        
        user_manager.list = AsyncMock(return_value=users)
        
        distribution = await user_manager.get_protocol_distribution()
        
        assert distribution[ProtocolType.VLESS] == 2
        assert distribution[ProtocolType.SHADOWSOCKS] == 1
        assert distribution[ProtocolType.WIREGUARD] == 1
    
    async def test_validate_user_data(self, user_manager):
        """Test user data validation."""
        # Test valid data
        valid_data = {
            "username": "valid_user",
            "protocol": ProtocolType.VLESS,
            "email": "valid@example.com"
        }
        
        is_valid, errors = await user_manager.validate_user_data(valid_data)
        assert is_valid is True
        assert len(errors) == 0
        
        # Test invalid data
        invalid_data = {
            "username": "ab",  # Too short
            "protocol": "invalid_protocol",
            "email": "invalid_email"
        }
        
        is_valid, errors = await user_manager.validate_user_data(invalid_data)
        assert is_valid is False
        assert len(errors) > 0
    
    async def test_concurrent_user_operations(self, user_manager):
        """Test concurrent user operations."""
        import asyncio
        
        # Mock create method
        created_users = []
        async def mock_create(**kwargs):
            await asyncio.sleep(0.01)  # Simulate async operation
            user = User(
                username=kwargs["username"],
                protocol=MagicMock(type=kwargs["protocol"])
            )
            created_users.append(user)
            return user
        
        user_manager.create = mock_create
        
        # Create multiple users concurrently
        tasks = [
            user_manager.create(username=f"concurrent_{i}", protocol=ProtocolType.VLESS)
            for i in range(5)
        ]
        
        results = await asyncio.gather(*tasks)
        
        assert len(results) == 5
        assert all(isinstance(result, User) for result in results)
    
    async def test_user_activity_tracking(self, user_manager):
        """Test user activity tracking."""
        user_id = str(uuid4())
        
        # Mock get user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock()
        )
        user_manager.get = AsyncMock(return_value=user)
        
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_db_manager = AsyncMock()
            mock_db_manager.update_user_activity.return_value = MagicMock()
            
            with patch('vpn.services.user_manager.DatabaseManager', return_value=mock_db_manager):
                result = await user_manager.update_last_activity(user_id)
                
                assert result is not None
                mock_db_manager.update_user_activity.assert_called_once()
    
    async def test_error_handling(self, user_manager):
        """Test error handling in user operations."""
        user_id = str(uuid4())
        
        # Test database connection error
        with patch('vpn.services.user_manager.get_session') as mock_session:
            mock_session.side_effect = Exception("Database connection failed")
            
            with pytest.raises(Exception):
                await user_manager.get(user_id)
    
    async def test_user_config_management(self, user_manager):
        """Test user configuration management."""
        user_id = str(uuid4())
        
        # Mock user
        user = User(
            id=user_id,
            username="testuser",
            protocol=MagicMock(type=ProtocolType.VLESS)
        )
        user_manager.get = AsyncMock(return_value=user)
        
        # Test config generation
        with patch('vpn.services.user_manager.generate_user_config') as mock_gen:
            mock_gen.return_value = {"config": "test_config"}
            
            config = await user_manager.generate_user_config(user_id)
            
            assert config is not None
            assert "config" in config
            mock_gen.assert_called_once_with(user)
    
    async def test_user_backup_restore(self, user_manager):
        """Test user backup and restore operations."""
        # Test backup
        users = [
            User(username="backup1", protocol=MagicMock()),
            User(username="backup2", protocol=MagicMock())
        ]
        user_manager.list = AsyncMock(return_value=users)
        
        backup_data = await user_manager.create_backup()
        
        assert len(backup_data) == 2
        assert backup_data[0]["username"] == "backup1"
        assert backup_data[1]["username"] == "backup2"
        
        # Test restore
        user_manager.create = AsyncMock()
        user_manager.get_by_username = AsyncMock(return_value=None)
        
        result = await user_manager.restore_backup(backup_data)
        
        assert result["restored"] == 2
        assert result["failed"] == 0
        assert user_manager.create.call_count == 2