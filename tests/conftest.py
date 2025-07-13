"""
Pytest configuration and shared fixtures.
"""

import asyncio
from collections.abc import AsyncGenerator, Generator
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

# Import models and database
try:
    from vpn.core.config import Settings
    from vpn.core.database import Base, UserDB
    from vpn.core.models import ProtocolType, User, UserStatus
except ImportError:
    # Handle import errors gracefully during test discovery
    Base = None
    UserDB = None

# Configure async test event loop
@pytest.fixture(scope="session")
def event_loop() -> Generator[asyncio.AbstractEventLoop, None, None]:
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


# Test database fixture
@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Create a test database session with proper table creation."""
    # Use in-memory SQLite for tests
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        echo=False,
        connect_args={"check_same_thread": False}
    )

    # Create tables if Base is available
    if Base is not None:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    # Create session
    async_session = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with async_session() as session:
        try:
            yield session
        finally:
            await session.rollback()

    await engine.dispose()


@pytest_asyncio.fixture
async def db_engine():
    """Create a test database engine."""
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        echo=False,
        connect_args={"check_same_thread": False}
    )

    if Base is not None:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    yield engine
    await engine.dispose()


# Temporary directory fixture
@pytest.fixture
def temp_dir(tmp_path: Path) -> Path:
    """Create a temporary directory for test files."""
    return tmp_path


# Mock Docker client fixture
@pytest.fixture
def mock_docker_client(mocker):
    """Create a mock Docker client."""
    mock_client = mocker.MagicMock()
    mock_client.ping.return_value = True
    mock_client.version.return_value = {
        "Version": "24.0.0",
        "ApiVersion": "1.43",
    }
    return mock_client


# Test configuration fixture
@pytest.fixture
def test_config(temp_dir: Path) -> dict:
    """Create test configuration."""
    return {
        "app_name": "VPN Manager Test",
        "debug": True,
        "install_path": temp_dir / "vpn",
        "config_path": temp_dir / "config",
        "data_path": temp_dir / "data",
        "database_url": "sqlite+aiosqlite:///:memory:",
        "docker_socket": "/var/run/docker.sock",
        "default_protocol": "vless",
        "default_port_range": (10000, 20000),
    }


# Enhanced Docker fixtures
@pytest.fixture
def mock_docker_container(mocker):
    """Create a mock Docker container with realistic behavior."""
    container = mocker.MagicMock()
    container.id = "test_container_123"
    container.name = "test_vpn_container"
    container.status = "running"
    container.attrs = {
        "State": {"Status": "running", "Running": True},
        "NetworkSettings": {"IPAddress": "172.17.0.2"},
        "Config": {"Image": "vpn-server:latest"}
    }
    container.start = mocker.AsyncMock()
    container.stop = mocker.AsyncMock()
    container.restart = mocker.AsyncMock()
    container.remove = mocker.AsyncMock()
    container.stats = mocker.AsyncMock(return_value={
        "cpu_stats": {"cpu_usage": {"total_usage": 1000000}},
        "memory_stats": {"usage": 50000000, "limit": 100000000}
    })
    return container


@pytest.fixture
def mock_enhanced_docker_manager(mocker, mock_docker_client):
    """Create a mock EnhancedDockerManager."""

    manager = mocker.MagicMock()
    manager.start_container = AsyncMock()
    manager.stop_container = AsyncMock()
    manager.create_container = AsyncMock()
    manager.get_container = AsyncMock()
    manager.list_containers = AsyncMock(return_value=[])
    manager.get_container_stats = AsyncMock(return_value={})

    # Batch operations
    manager.start_containers_batch = AsyncMock(return_value={})
    manager.stop_containers_batch = AsyncMock(return_value={})
    manager.get_containers_stats_batch = AsyncMock(return_value={})

    return manager


# Test environment fixtures
@pytest.fixture
def test_env_vars(monkeypatch):
    """Set up test environment variables."""
    test_vars = {
        "VPN_DEBUG": "1",
        "VPN_LOG_LEVEL": "DEBUG",
        "VPN_CONFIG_PATH": "/tmp/test_config",
        "VPN_INSTALL_PATH": "/tmp/test_vpn",
        "VPN_DATABASE_URL": "sqlite+aiosqlite:///:memory:",
    }

    for key, value in test_vars.items():
        monkeypatch.setenv(key, value)

    return test_vars


@pytest.fixture
def isolated_filesystem(tmp_path):
    """Create an isolated filesystem for testing file operations."""
    # Create directory structure
    config_dir = tmp_path / "config"
    data_dir = tmp_path / "data"
    install_dir = tmp_path / "install"

    config_dir.mkdir()
    data_dir.mkdir()
    install_dir.mkdir()

    return {
        "root": tmp_path,
        "config": config_dir,
        "data": data_dir,
        "install": install_dir
    }


@pytest.fixture
def test_settings(isolated_filesystem, test_env_vars):
    """Create test settings configuration."""
    if Settings is None:
        return {}

    return Settings(
        debug=True,
        log_level="DEBUG",
        config_path=str(isolated_filesystem["config"]),
        data_path=str(isolated_filesystem["data"]),
        install_path=str(isolated_filesystem["install"]),
        database_url="sqlite+aiosqlite:///:memory:",
    )


# Performance testing fixtures
@pytest.fixture
def performance_monitor():
    """Fixture for performance monitoring in tests."""
    import time
    import tracemalloc

    import psutil

    class PerformanceMonitor:
        def __init__(self):
            self.start_time = None
            self.end_time = None
            self.start_memory = None
            self.end_memory = None
            self.process = psutil.Process()

        def start(self):
            tracemalloc.start()
            self.start_time = time.time()
            self.start_memory = self.process.memory_info().rss

        def stop(self):
            self.end_time = time.time()
            self.end_memory = self.process.memory_info().rss
            current, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()

            return {
                "duration": self.end_time - self.start_time,
                "memory_delta": self.end_memory - self.start_memory,
                "peak_memory": peak,
                "current_memory": current
            }

    return PerformanceMonitor()


# Network testing fixtures
@pytest.fixture
def mock_network_manager(mocker):
    """Create a mock NetworkManager."""
    manager = mocker.MagicMock()
    manager.is_port_available = mocker.AsyncMock(return_value=True)
    manager.check_firewall_rule = mocker.AsyncMock(return_value=True)
    manager.add_firewall_rule = mocker.AsyncMock()
    manager.remove_firewall_rule = mocker.AsyncMock()
    manager.get_public_ip = mocker.AsyncMock(return_value="203.0.113.1")
    return manager


# TUI testing fixtures
@pytest.fixture
def mock_textual_app(mocker):
    """Create a mock Textual app for TUI testing."""
    app = mocker.MagicMock()
    app.push_screen = mocker.AsyncMock()
    app.pop_screen = mocker.AsyncMock()
    app.exit = mocker.AsyncMock()
    app.query = mocker.MagicMock()
    return app


# Test data cleanup
@pytest.fixture(autouse=True)
def cleanup_test_data():
    """Automatically clean up test data after each test."""
    yield
    # Cleanup logic here if needed
    import gc
    gc.collect()


# Async context manager fixture
@pytest_asyncio.fixture
async def async_context():
    """Provide async context for tests."""
    class AsyncTestContext:
        def __init__(self):
            self.tasks = []

        async def add_task(self, coro):
            task = asyncio.create_task(coro)
            self.tasks.append(task)
            return task

        async def cleanup(self):
            for task in self.tasks:
                if not task.done():
                    task.cancel()
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass

    context = AsyncTestContext()
    try:
        yield context
    finally:
        await context.cleanup()


# Pytest configuration hooks
def pytest_configure(config):
    """Configure pytest with custom markers and settings."""
    config.addinivalue_line(
        "markers", "unit: Unit tests that test individual components"
    )
    config.addinivalue_line(
        "markers", "integration: Integration tests that test component interaction"
    )
    config.addinivalue_line(
        "markers", "slow: Tests that take more than 5 seconds to run"
    )
    config.addinivalue_line(
        "markers", "performance: Performance and benchmark tests"
    )
    config.addinivalue_line(
        "markers", "docker: Tests that require Docker"
    )
    config.addinivalue_line(
        "markers", "network: Tests that require network access"
    )
    config.addinivalue_line(
        "markers", "tui: Tests for terminal user interface"
    )
    config.addinivalue_line(
        "markers", "load: Load testing scenarios"
    )


def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers automatically."""
    for item in items:
        # Auto-mark slow tests
        if "slow" in item.nodeid or "load" in item.nodeid:
            item.add_marker(pytest.mark.slow)

        # Auto-mark integration tests
        if "integration" in item.nodeid or "test_e2e" in item.nodeid:
            item.add_marker(pytest.mark.integration)

        # Auto-mark docker tests
        if "docker" in item.nodeid:
            item.add_marker(pytest.mark.docker)

        # Auto-mark TUI tests
        if "tui" in item.nodeid:
            item.add_marker(pytest.mark.tui)
