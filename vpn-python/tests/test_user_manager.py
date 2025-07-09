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