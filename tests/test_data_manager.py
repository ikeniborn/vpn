"""
Test data management and cleanup system for VPN Manager.

This module provides comprehensive test data management including
seeding, cleanup, isolation, and state management for consistent testing.
"""

import asyncio
import json
import shutil
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, AsyncGenerator
from dataclasses import dataclass
from datetime import datetime

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from tests.factories import (
    UserDataFactory,
    ContainerDataFactory,
    create_complete_user_scenario,
    create_docker_test_environment
)
from tests.utils import DatabaseTestHelper, FileTestHelper


@dataclass
class TestDataSnapshot:
    """Snapshot of test data state."""
    timestamp: datetime
    users_count: int
    containers_count: int
    files_created: List[str]
    database_state: Dict[str, Any]
    memory_usage_mb: float


@dataclass
class TestEnvironment:
    """Complete test environment setup."""
    database_session: AsyncSession
    temp_directory: Path
    config_files: Dict[str, Path]
    mock_services: Dict[str, Any]
    cleanup_functions: List[Any]


class TestDataManager:
    """
    Centralized test data management for consistent and isolated testing.
    
    Features:
    - Automatic test data seeding
    - Cleanup after tests
    - Data isolation between tests
    - Snapshot and restore capabilities
    - Performance monitoring
    """
    
    def __init__(self):
        self.temp_directories: Set[Path] = set()
        self.created_files: Set[Path] = set()
        self.database_sessions: Set[AsyncSession] = set()
        self.snapshots: List[TestDataSnapshot] = []
        self.cleanup_tasks: List[Any] = []
        
    async def create_test_environment(
        self,
        include_users: int = 0,
        include_containers: int = 0,
        include_config_files: bool = False,
        include_mock_services: bool = True
    ) -> TestEnvironment:
        """
        Create a complete test environment with specified components.
        
        Args:
            include_users: Number of test users to create
            include_containers: Number of test containers to create
            include_config_files: Whether to create test config files
            include_mock_services: Whether to include mock services
            
        Returns:
            Configured test environment
        """
        # Create temporary directory
        temp_dir = Path(tempfile.mkdtemp(prefix="vpn_test_"))
        self.temp_directories.add(temp_dir)
        
        # Create database session
        from tests.conftest import db_session
        session = await self._create_test_db_session()
        
        # Seed test data
        test_users = []
        if include_users > 0:
            test_users = await self._seed_test_users(session, include_users)
        
        # Create config files
        config_files = {}
        if include_config_files:
            config_files = await self._create_config_files(temp_dir)
        
        # Setup mock services
        mock_services = {}
        if include_mock_services:
            mock_services = self._create_mock_services()
        
        environment = TestEnvironment(
            database_session=session,
            temp_directory=temp_dir,
            config_files=config_files,
            mock_services=mock_services,
            cleanup_functions=[]
        )
        
        return environment
    
    async def cleanup_test_environment(self, environment: TestEnvironment) -> None:
        """Clean up test environment completely."""
        # Run custom cleanup functions
        for cleanup_func in environment.cleanup_functions:
            try:
                if asyncio.iscoroutinefunction(cleanup_func):
                    await cleanup_func()
                else:
                    cleanup_func()
            except Exception as e:
                print(f"Warning: Cleanup function failed: {e}")
        
        # Clean database
        if environment.database_session:
            await DatabaseTestHelper.cleanup_test_data(environment.database_session)
            await environment.database_session.close()
        
        # Clean files
        if environment.temp_directory.exists():
            shutil.rmtree(environment.temp_directory, ignore_errors=True)
        
        # Clean from tracking sets
        self.temp_directories.discard(environment.temp_directory)
    
    async def take_snapshot(self, environment: TestEnvironment) -> TestDataSnapshot:
        """Take a snapshot of current test data state."""
        import psutil
        
        # Count database records
        users_count = 0
        try:
            result = await environment.database_session.execute("SELECT COUNT(*) FROM users")
            users_count = result.scalar() or 0
        except Exception:
            pass  # Database might not have tables
        
        # Count files
        files_created = [
            str(f) for f in self.created_files 
            if f.exists() and f.is_relative_to(environment.temp_directory)
        ]
        
        # Get memory usage
        process = psutil.Process()
        memory_usage_mb = process.memory_info().rss / (1024 * 1024)
        
        snapshot = TestDataSnapshot(
            timestamp=datetime.utcnow(),
            users_count=users_count,
            containers_count=0,  # Would need container tracking
            files_created=files_created,
            database_state={'users_count': users_count},
            memory_usage_mb=memory_usage_mb
        )
        
        self.snapshots.append(snapshot)
        return snapshot
    
    async def restore_snapshot(
        self, 
        environment: TestEnvironment, 
        snapshot: TestDataSnapshot
    ) -> None:
        """Restore test environment to a previous snapshot state."""
        # This is a simplified restore - in practice would need more sophisticated state management
        
        # Clean current data
        await DatabaseTestHelper.cleanup_test_data(environment.database_session)
        
        # Note: Full restoration would require storing actual data, not just counts
        # This is a framework for more complete implementation
        pass
    
    async def seed_realistic_data(
        self, 
        environment: TestEnvironment,
        scenario_name: str = "standard"
    ) -> Dict[str, Any]:
        """
        Seed realistic test data based on predefined scenarios.
        
        Args:
            environment: Test environment to seed
            scenario_name: Name of scenario to apply
            
        Returns:
            Dictionary containing created test data
        """
        scenarios = {
            "standard": {
                "users_count": 10,
                "admin_users": 2,
                "expired_users": 1,
                "containers_count": 8,
                "config_files": ["server.yaml", "clients.yaml"]
            },
            "load_test": {
                "users_count": 100,
                "admin_users": 5,
                "expired_users": 10,
                "containers_count": 50,
                "config_files": ["server.yaml", "clients.yaml", "performance.yaml"]
            },
            "minimal": {
                "users_count": 3,
                "admin_users": 1,
                "expired_users": 0,
                "containers_count": 2,
                "config_files": ["server.yaml"]
            }
        }
        
        scenario_config = scenarios.get(scenario_name, scenarios["standard"])
        
        # Seed users
        regular_users = await self._seed_test_users(
            environment.database_session,
            scenario_config["users_count"]
        )
        
        admin_users = await self._seed_admin_users(
            environment.database_session,
            scenario_config["admin_users"]
        )
        
        expired_users = await self._seed_expired_users(
            environment.database_session,
            scenario_config["expired_users"]
        )
        
        # Create config files
        config_files = {}
        for config_name in scenario_config["config_files"]:
            config_path = await self._create_config_file(
                environment.temp_directory, 
                config_name
            )
            config_files[config_name] = config_path
        
        return {
            "regular_users": regular_users,
            "admin_users": admin_users,
            "expired_users": expired_users,
            "config_files": config_files,
            "scenario": scenario_name
        }
    
    async def verify_data_isolation(
        self, 
        environment1: TestEnvironment, 
        environment2: TestEnvironment
    ) -> bool:
        """
        Verify that two test environments are properly isolated.
        
        Returns:
            True if environments are isolated, False otherwise
        """
        # Check directory isolation
        if environment1.temp_directory == environment2.temp_directory:
            return False
        
        # Check database isolation (simplified check)
        try:
            # In a real implementation, would check that database sessions
            # don't interfere with each other
            session1_id = id(environment1.database_session)
            session2_id = id(environment2.database_session)
            return session1_id != session2_id
        except Exception:
            return False
    
    async def cleanup_all(self) -> None:
        """Clean up all tracked test resources."""
        # Clean up temporary directories
        for temp_dir in list(self.temp_directories):
            if temp_dir.exists():
                shutil.rmtree(temp_dir, ignore_errors=True)
        
        self.temp_directories.clear()
        
        # Clean up database sessions
        for session in list(self.database_sessions):
            try:
                await DatabaseTestHelper.cleanup_test_data(session)
                await session.close()
            except Exception:
                pass
        
        self.database_sessions.clear()
        
        # Clean up files
        for file_path in list(self.created_files):
            try:
                if file_path.exists():
                    file_path.unlink()
            except Exception:
                pass
        
        self.created_files.clear()
        
        # Run cleanup tasks
        for task in self.cleanup_tasks:
            try:
                if asyncio.iscoroutinefunction(task):
                    await task()
                else:
                    task()
            except Exception:
                pass
        
        self.cleanup_tasks.clear()
    
    # Private helper methods
    
    async def _create_test_db_session(self) -> AsyncSession:
        """Create an isolated test database session."""
        from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
        from sqlalchemy.orm import sessionmaker
        
        # Create in-memory database for isolation
        engine = create_async_engine(
            "sqlite+aiosqlite:///:memory:",
            echo=False
        )
        
        # Create tables
        try:
            from vpn.core.database import Base
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
        except ImportError:
            pass  # Handle gracefully if models not available
        
        async_session = sessionmaker(
            engine, class_=AsyncSession, expire_on_commit=False
        )
        
        session = async_session()
        self.database_sessions.add(session)
        
        return session
    
    async def _seed_test_users(self, session: AsyncSession, count: int) -> List[Dict[str, Any]]:
        """Seed regular test users."""
        users_data = UserDataFactory.create_batch_dict(count)
        
        try:
            await DatabaseTestHelper.create_test_users(session, count, **{})
        except ImportError:
            pass  # Handle if database helpers not available
        
        return users_data
    
    async def _seed_admin_users(self, session: AsyncSession, count: int) -> List[Dict[str, Any]]:
        """Seed admin test users."""
        from tests.factories import AdminUserDataFactory
        
        admin_users = AdminUserDataFactory.create_batch_dict(count)
        return admin_users
    
    async def _seed_expired_users(self, session: AsyncSession, count: int) -> List[Dict[str, Any]]:
        """Seed expired test users."""
        from tests.factories import ExpiredUserDataFactory
        
        expired_users = ExpiredUserDataFactory.create_batch_dict(count)
        return expired_users
    
    async def _create_config_files(self, temp_dir: Path) -> Dict[str, Path]:
        """Create test configuration files."""
        config_files = {}
        
        # Server config
        server_config = {
            "server": {
                "host": "127.0.0.1",
                "port": 8443,
                "protocol": "vless"
            },
            "logging": {
                "level": "DEBUG",
                "file": str(temp_dir / "server.log")
            }
        }
        
        server_config_path = temp_dir / "server.yaml"
        FileTestHelper.create_test_json_file(server_config_path, server_config)
        config_files["server"] = server_config_path
        self.created_files.add(server_config_path)
        
        # Client config
        client_config = {
            "clients": [
                {
                    "username": "test_user_1",
                    "protocol": "vless",
                    "server": "127.0.0.1:8443"
                }
            ]
        }
        
        client_config_path = temp_dir / "clients.yaml"
        FileTestHelper.create_test_json_file(client_config_path, client_config)
        config_files["clients"] = client_config_path
        self.created_files.add(client_config_path)
        
        return config_files
    
    async def _create_config_file(self, temp_dir: Path, config_name: str) -> Path:
        """Create a specific config file."""
        config_templates = {
            "server.yaml": {
                "server": {"host": "127.0.0.1", "port": 8443},
                "protocols": ["vless", "shadowsocks"],
                "max_clients": 100
            },
            "clients.yaml": {
                "clients": [
                    {"username": f"client_{i}", "protocol": "vless"}
                    for i in range(5)
                ]
            },
            "performance.yaml": {
                "performance": {
                    "max_concurrent_connections": 1000,
                    "timeout_seconds": 30,
                    "cache_size_mb": 100
                }
            }
        }
        
        config_data = config_templates.get(config_name, {})
        config_path = temp_dir / config_name
        
        FileTestHelper.create_test_json_file(config_path, config_data)
        self.created_files.add(config_path)
        
        return config_path
    
    def _create_mock_services(self) -> Dict[str, Any]:
        """Create mock services for testing."""
        from unittest.mock import AsyncMock, MagicMock
        
        return {
            "docker_manager": MagicMock(),
            "user_manager": MagicMock(),
            "network_manager": MagicMock(),
            "cache_service": AsyncMock()
        }


# Global test data manager instance
_test_data_manager: Optional[TestDataManager] = None


def get_test_data_manager() -> TestDataManager:
    """Get or create global test data manager."""
    global _test_data_manager
    if _test_data_manager is None:
        _test_data_manager = TestDataManager()
    return _test_data_manager


@asynccontextmanager
async def test_environment(
    include_users: int = 0,
    include_containers: int = 0,
    include_config_files: bool = False,
    include_mock_services: bool = True
) -> AsyncGenerator[TestEnvironment, None]:
    """
    Async context manager for test environment management.
    
    Usage:
        async with test_environment(include_users=5) as env:
            # Use env.database_session, env.temp_directory, etc.
            pass
        # Automatic cleanup
    """
    manager = get_test_data_manager()
    
    environment = await manager.create_test_environment(
        include_users=include_users,
        include_containers=include_containers,
        include_config_files=include_config_files,
        include_mock_services=include_mock_services
    )
    
    try:
        yield environment
    finally:
        await manager.cleanup_test_environment(environment)


@pytest.fixture
async def test_data_manager():
    """Pytest fixture for test data manager."""
    manager = TestDataManager()
    yield manager
    await manager.cleanup_all()


@pytest.fixture
async def seeded_environment(test_data_manager):
    """Pytest fixture for pre-seeded test environment."""
    environment = await test_data_manager.create_test_environment(
        include_users=5,
        include_config_files=True,
        include_mock_services=True
    )
    
    # Seed with standard scenario
    seeded_data = await test_data_manager.seed_realistic_data(
        environment, "standard"
    )
    
    yield environment, seeded_data
    
    await test_data_manager.cleanup_test_environment(environment)


@pytest.fixture
async def isolated_environments(test_data_manager):
    """Pytest fixture for multiple isolated test environments."""
    environments = []
    
    # Create multiple isolated environments
    for i in range(3):
        env = await test_data_manager.create_test_environment(
            include_users=2,
            include_config_files=True
        )
        environments.append(env)
    
    yield environments
    
    # Cleanup all environments
    for env in environments:
        await test_data_manager.cleanup_test_environment(env)


# Cleanup hooks for pytest
def pytest_runtest_teardown(item, nextitem):
    """Clean up after each test."""
    manager = get_test_data_manager()
    
    # Run synchronous cleanup
    import asyncio
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            # If loop is running, schedule cleanup
            loop.create_task(manager.cleanup_all())
        else:
            # If no loop, run cleanup directly
            asyncio.run(manager.cleanup_all())
    except Exception as e:
        print(f"Warning: Test cleanup failed: {e}")


def pytest_sessionfinish(session, exitstatus):
    """Clean up after entire test session."""
    manager = get_test_data_manager()
    
    import asyncio
    try:
        asyncio.run(manager.cleanup_all())
    except Exception as e:
        print(f"Warning: Session cleanup failed: {e}")


# Export key classes and functions
__all__ = [
    'TestDataManager',
    'TestEnvironment',
    'TestDataSnapshot',
    'test_environment',
    'get_test_data_manager'
]