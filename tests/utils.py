"""
Test utilities and helper functions for VPN Manager testing.

This module provides common utilities, helpers, and assertion functions
used across the test suite for consistent and efficient testing.
"""

import asyncio
import json
import random
import string
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Union
from unittest.mock import AsyncMock, MagicMock

# Type definitions
JsonData = Union[dict[str, Any], list[Any], str, int, float, bool, None]


class TestDataGenerator:
    """Generate realistic test data for VPN Manager components."""

    @staticmethod
    def random_string(length: int = 10, charset: str = string.ascii_letters) -> str:
        """Generate a random string of specified length."""
        return ''.join(random.choices(charset, k=length))

    @staticmethod
    def random_username() -> str:
        """Generate a random username for testing."""
        prefixes = ['user', 'admin', 'test', 'dev', 'vpn']
        return f"{random.choice(prefixes)}{random.randint(100, 9999)}"

    @staticmethod
    def random_email(domain: str = "example.com") -> str:
        """Generate a random email address."""
        username = TestDataGenerator.random_string(8).lower()
        return f"{username}@{domain}"

    @staticmethod
    def random_ip() -> str:
        """Generate a random IP address."""
        return ".".join([str(random.randint(1, 255)) for _ in range(4)])

    @staticmethod
    def random_port() -> int:
        """Generate a random port number."""
        return random.randint(1000, 65535)

    @staticmethod
    def random_uuid() -> str:
        """Generate a random UUID."""
        return str(uuid.uuid4())

    @staticmethod
    def random_protocol() -> str:
        """Generate a random VPN protocol."""
        protocols = ['vless', 'shadowsocks', 'wireguard', 'http', 'socks5']
        return random.choice(protocols)

    @staticmethod
    def random_status() -> str:
        """Generate a random user status."""
        statuses = ['active', 'inactive', 'expired', 'suspended']
        return random.choice(statuses)

    @staticmethod
    def future_datetime(days: int = 30) -> datetime:
        """Generate a future datetime."""
        return datetime.utcnow() + timedelta(days=days)

    @staticmethod
    def past_datetime(days: int = 30) -> datetime:
        """Generate a past datetime."""
        return datetime.utcnow() - timedelta(days=days)


class MockFactory:
    """Factory for creating mock objects with realistic behavior."""

    @staticmethod
    def create_mock_user(
        username: str | None = None,
        email: str | None = None,
        status: str | None = None,
        protocol_type: str | None = None
    ) -> dict[str, Any]:
        """Create a mock user data dictionary."""
        return {
            'id': TestDataGenerator.random_uuid(),
            'username': username or TestDataGenerator.random_username(),
            'email': email or TestDataGenerator.random_email(),
            'status': status or TestDataGenerator.random_status(),
            'protocol_type': protocol_type or TestDataGenerator.random_protocol(),
            'port': TestDataGenerator.random_port(),
            'server_ip': TestDataGenerator.random_ip(),
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow(),
            'expires_at': TestDataGenerator.future_datetime(),
        }

    @staticmethod
    def create_mock_container(
        container_id: str | None = None,
        name: str | None = None,
        status: str = "running"
    ) -> MagicMock:
        """Create a mock Docker container."""
        container = MagicMock()
        container.id = container_id or TestDataGenerator.random_string(12, string.ascii_lowercase + string.digits)
        container.name = name or f"vpn_container_{TestDataGenerator.random_string(6)}"
        container.status = status
        container.attrs = {
            "State": {"Status": status, "Running": status == "running"},
            "NetworkSettings": {"IPAddress": TestDataGenerator.random_ip()},
            "Config": {"Image": "vpn-server:latest"}
        }

        # Mock async methods
        container.start = AsyncMock()
        container.stop = AsyncMock()
        container.restart = AsyncMock()
        container.remove = AsyncMock()
        container.stats = AsyncMock(return_value={
            "cpu_stats": {"cpu_usage": {"total_usage": random.randint(1000000, 10000000)}},
            "memory_stats": {
                "usage": random.randint(50000000, 200000000),
                "limit": 500000000
            }
        })

        return container

    @staticmethod
    def create_mock_docker_client() -> MagicMock:
        """Create a mock Docker client."""
        client = MagicMock()
        client.ping.return_value = True
        client.version.return_value = {
            "Version": "24.0.0",
            "ApiVersion": "1.43",
        }
        client.containers = MagicMock()
        client.containers.list = MagicMock(return_value=[])
        client.containers.get = MagicMock()
        client.containers.run = MagicMock()

        return client

    @staticmethod
    def create_mock_protocol_config(protocol_type: str = "vless") -> dict[str, Any]:
        """Create a mock protocol configuration."""
        configs = {
            "vless": {
                "type": "vless",
                "port": TestDataGenerator.random_port(),
                "settings": {
                    "clients": [{"id": TestDataGenerator.random_uuid()}],
                    "decryption": "none",
                    "fallbacks": []
                }
            },
            "shadowsocks": {
                "type": "shadowsocks",
                "port": TestDataGenerator.random_port(),
                "settings": {
                    "method": "chacha20-ietf-poly1305",
                    "password": TestDataGenerator.random_string(16)
                }
            },
            "wireguard": {
                "type": "wireguard",
                "port": TestDataGenerator.random_port(),
                "settings": {
                    "private_key": TestDataGenerator.random_string(44),
                    "public_key": TestDataGenerator.random_string(44),
                    "address": f"10.0.0.{random.randint(2, 254)}/24"
                }
            }
        }

        return configs.get(protocol_type, configs["vless"])


class TestAssertions:
    """Custom assertion functions for VPN Manager testing."""

    @staticmethod
    def assert_user_valid(user_data: dict[str, Any]) -> None:
        """Assert that user data is valid."""
        required_fields = ['id', 'username', 'email', 'status', 'protocol_type']

        for field in required_fields:
            assert field in user_data, f"Missing required field: {field}"
            assert user_data[field] is not None, f"Field {field} is None"

        # Validate specific fields
        assert len(user_data['username']) >= 3, "Username too short"
        assert '@' in user_data['email'], "Invalid email format"
        assert user_data['status'] in ['active', 'inactive', 'expired', 'suspended'], "Invalid status"

    @staticmethod
    def assert_container_valid(container: Any) -> None:
        """Assert that container object is valid."""
        assert hasattr(container, 'id'), "Container missing id attribute"
        assert hasattr(container, 'name'), "Container missing name attribute"
        assert hasattr(container, 'status'), "Container missing status attribute"
        assert container.id is not None, "Container id is None"

    @staticmethod
    def assert_performance_acceptable(
        duration: float,
        max_duration: float,
        memory_delta: int,
        max_memory_delta: int
    ) -> None:
        """Assert that performance metrics are within acceptable limits."""
        assert duration <= max_duration, f"Operation too slow: {duration:.2f}s > {max_duration}s"
        assert memory_delta <= max_memory_delta, f"Memory usage too high: {memory_delta} > {max_memory_delta}"

    @staticmethod
    def assert_json_schema(data: JsonData, schema: dict[str, Any]) -> None:
        """Assert that JSON data conforms to schema (basic validation)."""
        if not isinstance(data, dict):
            raise AssertionError(f"Expected dict, got {type(data)}")

        required = schema.get('required', [])
        properties = schema.get('properties', {})

        for field in required:
            assert field in data, f"Missing required field: {field}"

        for field, value in data.items():
            if field in properties:
                expected_type = properties[field].get('type')
                if expected_type:
                    assert TestAssertions._validate_type(value, expected_type), \
                        f"Field {field} has wrong type: expected {expected_type}, got {type(value)}"

    @staticmethod
    def _validate_type(value: Any, expected_type: str) -> bool:
        """Validate value type against JSON schema type."""
        type_mapping = {
            'string': str,
            'integer': int,
            'number': (int, float),
            'boolean': bool,
            'array': list,
            'object': dict,
            'null': type(None)
        }

        expected_python_type = type_mapping.get(expected_type)
        if expected_python_type is None:
            return True  # Unknown type, skip validation

        return isinstance(value, expected_python_type)


class AsyncTestHelper:
    """Helper functions for async testing."""

    @staticmethod
    async def run_with_timeout(coro, timeout: float = 5.0):
        """Run coroutine with timeout."""
        try:
            return await asyncio.wait_for(coro, timeout=timeout)
        except asyncio.TimeoutError:
            raise AssertionError(f"Operation timed out after {timeout} seconds")

    @staticmethod
    async def run_parallel(*coros, max_concurrent: int = 10):
        """Run multiple coroutines in parallel with concurrency limit."""
        semaphore = asyncio.Semaphore(max_concurrent)

        async def limited_coro(coro):
            async with semaphore:
                return await coro

        tasks = [limited_coro(coro) for coro in coros]
        return await asyncio.gather(*tasks, return_exceptions=True)

    @staticmethod
    def create_async_mock(**kwargs) -> AsyncMock:
        """Create an AsyncMock with custom return values."""
        mock = AsyncMock(**kwargs)
        return mock


class FileTestHelper:
    """Helper functions for file system testing."""

    @staticmethod
    def create_test_file(
        path: Path,
        content: str = "",
        encoding: str = "utf-8"
    ) -> Path:
        """Create a test file with specified content."""
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding=encoding)
        return path

    @staticmethod
    def create_test_json_file(
        path: Path,
        data: JsonData,
        indent: int = 2
    ) -> Path:
        """Create a test JSON file with specified data."""
        content = json.dumps(data, indent=indent, default=str)
        return FileTestHelper.create_test_file(path, content)

    @staticmethod
    def assert_file_exists(path: Path) -> None:
        """Assert that file exists."""
        assert path.exists(), f"File does not exist: {path}"

    @staticmethod
    def assert_file_content(
        path: Path,
        expected_content: str,
        encoding: str = "utf-8"
    ) -> None:
        """Assert file has expected content."""
        FileTestHelper.assert_file_exists(path)
        actual_content = path.read_text(encoding=encoding)
        assert actual_content == expected_content, \
            f"File content mismatch:\nExpected: {expected_content}\nActual: {actual_content}"

    @staticmethod
    def assert_json_file_content(
        path: Path,
        expected_data: JsonData
    ) -> None:
        """Assert JSON file has expected data."""
        FileTestHelper.assert_file_exists(path)
        with path.open('r') as f:
            actual_data = json.load(f)
        assert actual_data == expected_data, \
            f"JSON content mismatch:\nExpected: {expected_data}\nActual: {actual_data}"


class DatabaseTestHelper:
    """Helper functions for database testing."""

    @staticmethod
    async def create_test_users(
        session,
        count: int = 5,
        **kwargs
    ) -> list[dict[str, Any]]:
        """Create multiple test users in database."""
        from vpn.core.database import UserDB

        users = []
        for i in range(count):
            user_data = MockFactory.create_mock_user(**kwargs)

            # Create UserDB instance
            user_db = UserDB(
                id=user_data['id'],
                username=f"{user_data['username']}_{i}",
                email=f"{i}_{user_data['email']}",
                status=user_data['status'],
                protocol=json.dumps({'type': user_data['protocol_type']}),
                connection_info=json.dumps({}),
                traffic_stats=json.dumps({}),
                crypto_keys=json.dumps({}),
                created_at=user_data['created_at'],
                updated_at=user_data['updated_at'],
                expires_at=user_data['expires_at'],
            )

            session.add(user_db)
            users.append(user_data)

        await session.commit()
        return users

    @staticmethod
    async def cleanup_test_data(session) -> None:
        """Clean up test data from database."""

        # Delete all test users
        await session.execute("DELETE FROM users WHERE username LIKE 'test_%' OR username LIKE 'user_%'")
        await session.commit()


class NetworkTestHelper:
    """Helper functions for network testing."""

    @staticmethod
    def mock_network_response(
        status_code: int = 200,
        json_data: JsonData | None = None,
        text_data: str | None = None
    ) -> MagicMock:
        """Create a mock network response."""
        response = MagicMock()
        response.status_code = status_code
        response.ok = 200 <= status_code < 300

        if json_data is not None:
            response.json.return_value = json_data

        if text_data is not None:
            response.text = text_data

        return response

    @staticmethod
    def assert_valid_ip(ip: str) -> None:
        """Assert that string is a valid IP address."""
        import ipaddress
        try:
            ipaddress.ip_address(ip)
        except ValueError:
            raise AssertionError(f"Invalid IP address: {ip}")

    @staticmethod
    def assert_valid_port(port: int | str) -> None:
        """Assert that port is valid."""
        port_int = int(port)
        assert 1 <= port_int <= 65535, f"Invalid port: {port}"


class PerformanceTestHelper:
    """Helper functions for performance testing."""

    @staticmethod
    def measure_execution_time(func):
        """Decorator to measure function execution time."""
        import functools
        import time

        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs):
            start_time = time.time()
            result = await func(*args, **kwargs)
            execution_time = time.time() - start_time
            return result, execution_time

        @functools.wraps(func)
        def sync_wrapper(*args, **kwargs):
            start_time = time.time()
            result = func(*args, **kwargs)
            execution_time = time.time() - start_time
            return result, execution_time

        return async_wrapper if asyncio.iscoroutinefunction(func) else sync_wrapper

    @staticmethod
    def assert_execution_time(
        execution_time: float,
        max_time: float,
        operation_name: str = "Operation"
    ) -> None:
        """Assert that execution time is within acceptable limits."""
        assert execution_time <= max_time, \
            f"{operation_name} took too long: {execution_time:.3f}s > {max_time}s"

    @staticmethod
    def create_load_test_data(count: int) -> list[dict[str, Any]]:
        """Create large amount of test data for load testing."""
        return [MockFactory.create_mock_user() for _ in range(count)]


# Convenience imports for easier testing
__all__ = [
    'AsyncTestHelper',
    'DatabaseTestHelper',
    'FileTestHelper',
    'MockFactory',
    'NetworkTestHelper',
    'PerformanceTestHelper',
    'TestAssertions',
    'TestDataGenerator'
]
