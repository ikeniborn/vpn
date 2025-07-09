"""
Performance benchmarks for VPN management system.
"""

import pytest
import asyncio
import time
from unittest.mock import AsyncMock, MagicMock, patch
from concurrent.futures import ThreadPoolExecutor
import psutil
import json
from pathlib import Path
import tempfile
from datetime import datetime

from vpn.services.user_manager import UserManager
from vpn.services.server_manager import ServerManager
from vpn.services.proxy_server import ProxyServerManager
from vpn.services.crypto import CryptoService
from vpn.services.docker_manager import DockerManager
from vpn.core.models import User, ProtocolType, ProtocolConfig, ServerConfig, DockerConfig
from vpn.cli.main import cli
from click.testing import CliRunner


class BenchmarkResult:
    """Benchmark result container."""
    
    def __init__(self, name: str, duration: float, memory_usage: float, cpu_usage: float = 0):
        self.name = name
        self.duration = duration
        self.memory_usage = memory_usage
        self.cpu_usage = cpu_usage
        self.timestamp = datetime.now()
    
    def __str__(self):
        return f"{self.name}: {self.duration:.4f}s, {self.memory_usage:.2f}MB, {self.cpu_usage:.2f}% CPU"


class BenchmarkRunner:
    """Benchmark runner with performance monitoring."""
    
    def __init__(self):
        self.results = []
        self.process = psutil.Process()
    
    async def run_benchmark(self, name: str, func, *args, **kwargs):
        """Run a benchmark with performance monitoring."""
        # Get initial memory usage
        initial_memory = self.process.memory_info().rss / 1024 / 1024
        initial_cpu = self.process.cpu_percent()
        
        # Run the benchmark
        start_time = time.time()
        result = await func(*args, **kwargs)
        end_time = time.time()
        
        # Get final memory usage
        final_memory = self.process.memory_info().rss / 1024 / 1024
        final_cpu = self.process.cpu_percent()
        
        # Calculate metrics
        duration = end_time - start_time
        memory_usage = final_memory - initial_memory
        cpu_usage = final_cpu - initial_cpu
        
        # Store result
        benchmark_result = BenchmarkResult(name, duration, memory_usage, cpu_usage)
        self.results.append(benchmark_result)
        
        return result, benchmark_result
    
    def print_results(self):
        """Print benchmark results."""
        print("\n=== Performance Benchmark Results ===")
        for result in self.results:
            print(result)
        
        if self.results:
            avg_duration = sum(r.duration for r in self.results) / len(self.results)
            avg_memory = sum(r.memory_usage for r in self.results) / len(self.results)
            print(f"\nAverage Duration: {avg_duration:.4f}s")
            print(f"Average Memory Usage: {avg_memory:.2f}MB")


@pytest.fixture
def benchmark_runner():
    """Create benchmark runner."""
    return BenchmarkRunner()


@pytest.fixture
def mock_user_manager():
    """Create mock user manager for benchmarks."""
    manager = AsyncMock(spec=UserManager)
    manager.create = AsyncMock()
    manager.list = AsyncMock()
    manager.get = AsyncMock()
    manager.delete = AsyncMock()
    return manager


@pytest.fixture
def mock_server_manager():
    """Create mock server manager for benchmarks."""
    manager = AsyncMock(spec=ServerManager)
    manager.install = AsyncMock()
    manager.start_server = AsyncMock()
    manager.stop_server = AsyncMock()
    manager.list_servers = AsyncMock()
    return manager


@pytest.fixture
def sample_users():
    """Create sample users for benchmarks."""
    users = []
    for i in range(100):
        protocol = ProtocolConfig(type=ProtocolType.VLESS)
        user = User(
            username=f"user{i:03d}",
            email=f"user{i:03d}@example.com",
            protocol=protocol
        )
        users.append(user)
    return users


class TestUserManagementBenchmarks:
    """Benchmark user management operations."""
    
    @pytest.mark.asyncio
    async def test_user_creation_benchmark(self, benchmark_runner, mock_user_manager):
        """Benchmark user creation performance."""
        
        async def create_user():
            protocol = ProtocolConfig(type=ProtocolType.VLESS)
            user = User(
                username="testuser",
                email="test@example.com",
                protocol=protocol
            )
            mock_user_manager.create.return_value = user
            return await mock_user_manager.create(
                username="testuser",
                protocol=ProtocolType.VLESS,
                email="test@example.com"
            )
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "User Creation",
            create_user
        )
        
        assert result is not None
        assert benchmark.duration < 0.1  # Should complete in under 100ms
        assert benchmark.memory_usage < 10  # Should use less than 10MB
    
    @pytest.mark.asyncio
    async def test_user_list_benchmark(self, benchmark_runner, mock_user_manager, sample_users):
        """Benchmark user listing performance."""
        
        async def list_users():
            mock_user_manager.list.return_value = sample_users
            return await mock_user_manager.list()
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "User List (100 users)",
            list_users
        )
        
        assert len(result) == 100
        assert benchmark.duration < 0.05  # Should complete in under 50ms
        assert benchmark.memory_usage < 5  # Should use less than 5MB
    
    @pytest.mark.asyncio
    async def test_user_search_benchmark(self, benchmark_runner, mock_user_manager, sample_users):
        """Benchmark user search performance."""
        
        async def search_users():
            # Mock search returning filtered users
            filtered_users = [u for u in sample_users if "user001" in u.username]
            mock_user_manager.search = AsyncMock(return_value=filtered_users)
            return await mock_user_manager.search(query="user001")
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "User Search",
            search_users
        )
        
        assert len(result) == 1
        assert benchmark.duration < 0.02  # Should complete in under 20ms
    
    @pytest.mark.asyncio
    async def test_batch_user_creation_benchmark(self, benchmark_runner, mock_user_manager):
        """Benchmark batch user creation performance."""
        
        async def batch_create_users():
            users_data = [
                {"username": f"batch_user{i:03d}", "protocol": ProtocolType.VLESS}
                for i in range(50)
            ]
            
            created_users = []
            for user_data in users_data:
                protocol = ProtocolConfig(type=user_data["protocol"])
                user = User(username=user_data["username"], protocol=protocol)
                created_users.append(user)
            
            mock_user_manager.create_batch = AsyncMock(return_value=created_users)
            return await mock_user_manager.create_batch(users_data)
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Batch User Creation (50 users)",
            batch_create_users
        )
        
        assert len(result) == 50
        assert benchmark.duration < 0.5  # Should complete in under 500ms
        assert benchmark.memory_usage < 20  # Should use less than 20MB
    
    @pytest.mark.asyncio
    async def test_concurrent_user_operations(self, benchmark_runner, mock_user_manager):
        """Benchmark concurrent user operations."""
        
        async def concurrent_operations():
            # Create multiple concurrent operations
            tasks = []
            
            # Create users concurrently
            for i in range(10):
                protocol = ProtocolConfig(type=ProtocolType.VLESS)
                user = User(username=f"concurrent_user{i}", protocol=protocol)
                mock_user_manager.create.return_value = user
                
                task = mock_user_manager.create(
                    username=f"concurrent_user{i}",
                    protocol=ProtocolType.VLESS
                )
                tasks.append(task)
            
            # List users concurrently
            for _ in range(5):
                mock_user_manager.list.return_value = []
                tasks.append(mock_user_manager.list())
            
            return await asyncio.gather(*tasks)
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Concurrent User Operations (15 ops)",
            concurrent_operations
        )
        
        assert len(result) == 15
        assert benchmark.duration < 0.2  # Should complete in under 200ms


class TestCryptoServiceBenchmarks:
    """Benchmark cryptographic operations."""
    
    @pytest.mark.asyncio
    async def test_key_generation_benchmark(self, benchmark_runner):
        """Benchmark key generation performance."""
        
        async def generate_keys():
            crypto_service = CryptoService()
            
            # Generate multiple key types
            private_key = await crypto_service.generate_private_key()
            public_key = await crypto_service.derive_public_key(private_key)
            uuid = await crypto_service.generate_uuid()
            password = await crypto_service.generate_password()
            
            return {
                "private_key": private_key,
                "public_key": public_key,
                "uuid": uuid,
                "password": password
            }
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Crypto Key Generation",
            generate_keys
        )
        
        assert result["private_key"] is not None
        assert result["public_key"] is not None
        assert result["uuid"] is not None
        assert result["password"] is not None
        assert benchmark.duration < 0.01  # Should complete in under 10ms
    
    @pytest.mark.asyncio
    async def test_batch_key_generation_benchmark(self, benchmark_runner):
        """Benchmark batch key generation performance."""
        
        async def generate_batch_keys():
            crypto_service = CryptoService()
            
            # Generate keys for 50 users
            keys = []
            for i in range(50):
                private_key = await crypto_service.generate_private_key()
                public_key = await crypto_service.derive_public_key(private_key)
                uuid = await crypto_service.generate_uuid()
                
                keys.append({
                    "private_key": private_key,
                    "public_key": public_key,
                    "uuid": uuid
                })
            
            return keys
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Batch Key Generation (50 keys)",
            generate_batch_keys
        )
        
        assert len(result) == 50
        assert benchmark.duration < 0.5  # Should complete in under 500ms
        assert benchmark.memory_usage < 15  # Should use less than 15MB
    
    @pytest.mark.asyncio
    async def test_qr_code_generation_benchmark(self, benchmark_runner):
        """Benchmark QR code generation performance."""
        
        async def generate_qr_codes():
            crypto_service = CryptoService()
            
            # Generate QR codes for different connection strings
            connection_strings = [
                "vless://uuid1@server1:8443?params#user1",
                "ss://base64data@server2:8443#user2",
                "wireguard://config_data#user3"
            ]
            
            qr_codes = []
            for conn_str in connection_strings:
                qr_code = await crypto_service.generate_qr_code(conn_str)
                qr_codes.append(qr_code)
            
            return qr_codes
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "QR Code Generation (3 codes)",
            generate_qr_codes
        )
        
        assert len(result) == 3
        assert benchmark.duration < 0.1  # Should complete in under 100ms


class TestDockerManagerBenchmarks:
    """Benchmark Docker operations."""
    
    @pytest.mark.asyncio
    async def test_container_lifecycle_benchmark(self, benchmark_runner):
        """Benchmark container lifecycle operations."""
        
        async def container_lifecycle():
            docker_manager = DockerManager()
            
            # Mock Docker operations
            with patch.object(docker_manager, 'create_container') as mock_create:
                with patch.object(docker_manager, 'start_container') as mock_start:
                    with patch.object(docker_manager, 'stop_container') as mock_stop:
                        with patch.object(docker_manager, 'remove_container') as mock_remove:
                            
                            mock_create.return_value = MagicMock()
                            mock_start.return_value = None
                            mock_stop.return_value = None
                            mock_remove.return_value = None
                            
                            # Simulate container lifecycle
                            server_config = MagicMock()
                            server_config.name = "test-server"
                            
                            container = await docker_manager.create_container(server_config)
                            await docker_manager.start_container("test-server")
                            await docker_manager.stop_container("test-server")
                            await docker_manager.remove_container("test-server")
                            
                            return container
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Container Lifecycle",
            container_lifecycle
        )
        
        assert result is not None
        assert benchmark.duration < 0.1  # Should complete in under 100ms
    
    @pytest.mark.asyncio
    async def test_multiple_containers_benchmark(self, benchmark_runner):
        """Benchmark managing multiple containers."""
        
        async def manage_multiple_containers():
            docker_manager = DockerManager()
            
            # Mock Docker operations
            with patch.object(docker_manager, 'create_container') as mock_create:
                with patch.object(docker_manager, 'start_container') as mock_start:
                    
                    mock_create.return_value = MagicMock()
                    mock_start.return_value = None
                    
                    # Create and start 10 containers
                    containers = []
                    for i in range(10):
                        server_config = MagicMock()
                        server_config.name = f"server-{i}"
                        
                        container = await docker_manager.create_container(server_config)
                        await docker_manager.start_container(f"server-{i}")
                        containers.append(container)
                    
                    return containers
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Multiple Containers (10 containers)",
            manage_multiple_containers
        )
        
        assert len(result) == 10
        assert benchmark.duration < 0.5  # Should complete in under 500ms
    
    @pytest.mark.asyncio
    async def test_container_monitoring_benchmark(self, benchmark_runner):
        """Benchmark container monitoring operations."""
        
        async def monitor_containers():
            docker_manager = DockerManager()
            
            # Mock monitoring operations
            with patch.object(docker_manager, 'get_container_status') as mock_status:
                with patch.object(docker_manager, 'get_container_logs') as mock_logs:
                    with patch.object(docker_manager, 'get_container_stats') as mock_stats:
                        
                        mock_status.return_value = MagicMock()
                        mock_logs.return_value = "Container logs"
                        mock_stats.return_value = {"cpu": 10, "memory": 100}
                        
                        # Monitor 5 containers
                        monitoring_data = []
                        for i in range(5):
                            container_name = f"server-{i}"
                            
                            status = await docker_manager.get_container_status(container_name)
                            logs = await docker_manager.get_container_logs(container_name)
                            stats = await docker_manager.get_container_stats(container_name)
                            
                            monitoring_data.append({
                                "status": status,
                                "logs": logs,
                                "stats": stats
                            })
                        
                        return monitoring_data
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Container Monitoring (5 containers)",
            monitor_containers
        )
        
        assert len(result) == 5
        assert benchmark.duration < 0.2  # Should complete in under 200ms


class TestServerManagerBenchmarks:
    """Benchmark server management operations."""
    
    @pytest.mark.asyncio
    async def test_server_installation_benchmark(self, benchmark_runner, mock_server_manager):
        """Benchmark server installation performance."""
        
        async def install_server():
            mock_server_config = MagicMock()
            mock_server_config.name = "test-server"
            mock_server_config.protocol.type = ProtocolType.VLESS
            mock_server_config.port = 8443
            
            mock_server_manager.install.return_value = mock_server_config
            
            return await mock_server_manager.install(
                protocol="vless",
                port=8443,
                name="test-server"
            )
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Server Installation",
            install_server
        )
        
        assert result is not None
        assert benchmark.duration < 0.2  # Should complete in under 200ms
    
    @pytest.mark.asyncio
    async def test_multiple_servers_benchmark(self, benchmark_runner, mock_server_manager):
        """Benchmark managing multiple servers."""
        
        async def manage_multiple_servers():
            servers = []
            
            # Install multiple servers
            for i in range(5):
                mock_server_config = MagicMock()
                mock_server_config.name = f"server-{i}"
                mock_server_config.protocol.type = ProtocolType.VLESS
                mock_server_config.port = 8443 + i
                
                mock_server_manager.install.return_value = mock_server_config
                
                server = await mock_server_manager.install(
                    protocol="vless",
                    port=8443 + i,
                    name=f"server-{i}"
                )
                servers.append(server)
            
            return servers
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Multiple Servers (5 servers)",
            manage_multiple_servers
        )
        
        assert len(result) == 5
        assert benchmark.duration < 0.5  # Should complete in under 500ms


class TestProxyServerBenchmarks:
    """Benchmark proxy server operations."""
    
    @pytest.mark.asyncio
    async def test_proxy_startup_benchmark(self, benchmark_runner):
        """Benchmark proxy server startup performance."""
        
        async def start_proxy_servers():
            proxy_manager = ProxyServerManager()
            
            # Mock proxy server operations
            with patch.object(proxy_manager, 'start_http_proxy') as mock_http:
                with patch.object(proxy_manager, 'start_socks5_proxy') as mock_socks:
                    
                    mock_http.return_value = None
                    mock_socks.return_value = None
                    
                    # Start both types of proxy servers
                    await proxy_manager.start_http_proxy(port=8888, name="http-proxy")
                    await proxy_manager.start_socks5_proxy(port=1080, name="socks5-proxy")
                    
                    return {"http": "started", "socks5": "started"}
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Proxy Server Startup",
            start_proxy_servers
        )
        
        assert result["http"] == "started"
        assert result["socks5"] == "started"
        assert benchmark.duration < 0.1  # Should complete in under 100ms
    
    @pytest.mark.asyncio
    async def test_proxy_connection_handling_benchmark(self, benchmark_runner):
        """Benchmark proxy connection handling performance."""
        
        async def handle_proxy_connections():
            # Simulate handling multiple proxy connections
            connections = []
            
            for i in range(20):
                # Mock connection handling
                connection_data = {
                    "id": i,
                    "client_ip": f"192.168.1.{i+1}",
                    "timestamp": time.time(),
                    "status": "connected"
                }
                connections.append(connection_data)
                
                # Simulate connection processing delay
                await asyncio.sleep(0.001)  # 1ms per connection
            
            return connections
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Proxy Connection Handling (20 connections)",
            handle_proxy_connections
        )
        
        assert len(result) == 20
        assert benchmark.duration < 0.1  # Should complete in under 100ms


class TestCLIBenchmarks:
    """Benchmark CLI operations."""
    
    def test_cli_startup_benchmark(self, benchmark_runner):
        """Benchmark CLI startup performance."""
        
        def cli_startup():
            runner = CliRunner()
            result = runner.invoke(cli, ['--help'])
            return result
        
        # Convert to async for benchmark runner
        async def async_cli_startup():
            return cli_startup()
        
        result, benchmark = asyncio.run(
            benchmark_runner.run_benchmark(
                "CLI Startup",
                async_cli_startup
            )
        )
        
        assert result.exit_code == 0
        assert benchmark.duration < 0.1  # Should complete in under 100ms
    
    def test_cli_command_execution_benchmark(self, benchmark_runner):
        """Benchmark CLI command execution performance."""
        
        def cli_command_execution():
            runner = CliRunner()
            
            # Mock user manager
            with patch('vpn.cli.commands.users.UserManager') as mock_manager:
                mock_manager.return_value.list.return_value = []
                
                result = runner.invoke(cli, ['users', 'list'])
                return result
        
        # Convert to async for benchmark runner
        async def async_cli_command():
            return cli_command_execution()
        
        result, benchmark = asyncio.run(
            benchmark_runner.run_benchmark(
                "CLI Command Execution",
                async_cli_command
            )
        )
        
        assert result.exit_code == 0
        assert benchmark.duration < 0.05  # Should complete in under 50ms


class TestMemoryBenchmarks:
    """Benchmark memory usage."""
    
    @pytest.mark.asyncio
    async def test_memory_usage_scaling(self, benchmark_runner):
        """Benchmark memory usage with increasing load."""
        
        async def memory_scaling_test():
            # Simulate increasing memory usage
            data_structures = []
            
            # Create increasingly large data structures
            for size in [100, 500, 1000, 2000]:
                users = []
                for i in range(size):
                    protocol = ProtocolConfig(type=ProtocolType.VLESS)
                    user = User(
                        username=f"user{i:04d}",
                        email=f"user{i:04d}@example.com",
                        protocol=protocol
                    )
                    users.append(user)
                
                data_structures.append(users)
            
            return data_structures
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Memory Usage Scaling",
            memory_scaling_test
        )
        
        assert len(result) == 4  # Four different sizes
        assert benchmark.memory_usage < 50  # Should use less than 50MB
    
    @pytest.mark.asyncio
    async def test_memory_cleanup_benchmark(self, benchmark_runner):
        """Benchmark memory cleanup performance."""
        
        async def memory_cleanup_test():
            import gc
            
            # Create large data structure
            large_data = []
            for i in range(1000):
                protocol = ProtocolConfig(type=ProtocolType.VLESS)
                user = User(
                    username=f"user{i:04d}",
                    email=f"user{i:04d}@example.com",
                    protocol=protocol
                )
                large_data.append(user)
            
            # Clear the data
            large_data.clear()
            
            # Force garbage collection
            gc.collect()
            
            return "cleanup_complete"
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Memory Cleanup",
            memory_cleanup_test
        )
        
        assert result == "cleanup_complete"
        assert benchmark.duration < 0.1  # Should complete in under 100ms


class TestConcurrencyBenchmarks:
    """Benchmark concurrent operations."""
    
    @pytest.mark.asyncio
    async def test_concurrent_user_operations_benchmark(self, benchmark_runner, mock_user_manager):
        """Benchmark concurrent user operations."""
        
        async def concurrent_user_ops():
            # Create multiple concurrent tasks
            tasks = []
            
            # Create users
            for i in range(20):
                protocol = ProtocolConfig(type=ProtocolType.VLESS)
                user = User(username=f"user{i:03d}", protocol=protocol)
                mock_user_manager.create.return_value = user
                
                task = mock_user_manager.create(
                    username=f"user{i:03d}",
                    protocol=ProtocolType.VLESS
                )
                tasks.append(task)
            
            # List operations
            for _ in range(10):
                mock_user_manager.list.return_value = []
                tasks.append(mock_user_manager.list())
            
            # Execute all tasks concurrently
            results = await asyncio.gather(*tasks)
            return results
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Concurrent Operations (30 tasks)",
            concurrent_user_ops
        )
        
        assert len(result) == 30
        assert benchmark.duration < 0.5  # Should complete in under 500ms
    
    @pytest.mark.asyncio
    async def test_thread_pool_benchmark(self, benchmark_runner):
        """Benchmark thread pool executor performance."""
        
        async def thread_pool_test():
            loop = asyncio.get_event_loop()
            
            def cpu_bound_task(n):
                # Simulate CPU-bound work
                total = 0
                for i in range(n):
                    total += i * i
                return total
            
            # Execute tasks in thread pool
            with ThreadPoolExecutor(max_workers=4) as executor:
                tasks = [
                    loop.run_in_executor(executor, cpu_bound_task, 10000)
                    for _ in range(8)
                ]
                
                results = await asyncio.gather(*tasks)
                return results
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Thread Pool Execution (8 tasks)",
            thread_pool_test
        )
        
        assert len(result) == 8
        assert benchmark.duration < 1.0  # Should complete in under 1 second


class TestDatabaseBenchmarks:
    """Benchmark database operations."""
    
    @pytest.mark.asyncio
    async def test_database_operations_benchmark(self, benchmark_runner):
        """Benchmark database operations."""
        
        async def database_operations():
            # Mock database operations
            operations = []
            
            # Simulate database queries
            for i in range(100):
                operation = {
                    "type": "query",
                    "id": i,
                    "duration": 0.001,  # 1ms per query
                    "result": f"result_{i}"
                }
                operations.append(operation)
                
                # Simulate query delay
                await asyncio.sleep(0.001)
            
            return operations
        
        result, benchmark = await benchmark_runner.run_benchmark(
            "Database Operations (100 queries)",
            database_operations
        )
        
        assert len(result) == 100
        assert benchmark.duration < 0.5  # Should complete in under 500ms


@pytest.mark.asyncio
async def test_full_system_benchmark(benchmark_runner):
    """Run a comprehensive system benchmark."""
    
    async def full_system_test():
        # Initialize all services
        user_manager = UserManager()
        server_manager = ServerManager()
        proxy_manager = ProxyServerManager()
        crypto_service = CryptoService()
        
        # Mock all services
        with patch.object(user_manager, 'create') as mock_create:
            with patch.object(server_manager, 'install') as mock_install:
                with patch.object(proxy_manager, 'start_http_proxy') as mock_proxy:
                    
                    # Mock return values
                    protocol = ProtocolConfig(type=ProtocolType.VLESS)
                    user = User(username="testuser", protocol=protocol)
                    mock_create.return_value = user
                    
                    server_config = MagicMock()
                    server_config.name = "test-server"
                    mock_install.return_value = server_config
                    
                    mock_proxy.return_value = None
                    
                    # Execute system operations
                    created_user = await user_manager.create(
                        username="testuser",
                        protocol=ProtocolType.VLESS
                    )
                    
                    installed_server = await server_manager.install(
                        protocol="vless",
                        port=8443,
                        name="test-server"
                    )
                    
                    await proxy_manager.start_http_proxy(port=8888, name="http-proxy")
                    
                    # Generate keys
                    private_key = await crypto_service.generate_private_key()
                    public_key = await crypto_service.derive_public_key(private_key)
                    
                    return {
                        "user": created_user,
                        "server": installed_server,
                        "private_key": private_key,
                        "public_key": public_key
                    }
    
    result, benchmark = await benchmark_runner.run_benchmark(
        "Full System Test",
        full_system_test
    )
    
    assert result["user"] is not None
    assert result["server"] is not None
    assert result["private_key"] is not None
    assert result["public_key"] is not None
    assert benchmark.duration < 0.5  # Should complete in under 500ms
    assert benchmark.memory_usage < 25  # Should use less than 25MB


def test_benchmark_results_export():
    """Test exporting benchmark results."""
    runner = BenchmarkRunner()
    
    # Add sample results
    runner.results.extend([
        BenchmarkResult("Test 1", 0.1, 5.0, 2.0),
        BenchmarkResult("Test 2", 0.2, 10.0, 5.0),
        BenchmarkResult("Test 3", 0.05, 2.0, 1.0),
    ])
    
    # Export to JSON
    export_data = []
    for result in runner.results:
        export_data.append({
            "name": result.name,
            "duration": result.duration,
            "memory_usage": result.memory_usage,
            "cpu_usage": result.cpu_usage,
            "timestamp": result.timestamp.isoformat()
        })
    
    # Verify export data
    assert len(export_data) == 3
    assert export_data[0]["name"] == "Test 1"
    assert export_data[0]["duration"] == 0.1
    assert export_data[0]["memory_usage"] == 5.0


if __name__ == "__main__":
    # Run benchmarks directly
    async def run_all_benchmarks():
        runner = BenchmarkRunner()
        
        # Run key benchmarks
        crypto_service = CryptoService()
        
        # Crypto benchmark
        async def crypto_test():
            return await crypto_service.generate_private_key()
        
        await runner.run_benchmark("Crypto Key Generation", crypto_test)
        
        # Memory benchmark
        async def memory_test():
            data = [i for i in range(1000)]
            return len(data)
        
        await runner.run_benchmark("Memory Test", memory_test)
        
        # Print results
        runner.print_results()
    
    # Run benchmarks
    asyncio.run(run_all_benchmarks())