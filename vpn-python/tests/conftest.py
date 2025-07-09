"""
Pytest configuration and shared fixtures.
"""

import asyncio
from pathlib import Path
from typing import AsyncGenerator, Generator

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

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
    """Create a test database session."""
    # Use in-memory SQLite for tests
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        echo=False,
    )
    
    # Create tables
    # Note: We'll import and create Base.metadata later when we have models
    # async with engine.begin() as conn:
    #     await conn.run_sync(Base.metadata.create_all)
    
    # Create session
    async_session = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    
    async with async_session() as session:
        yield session
    
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