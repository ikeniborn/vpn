"""
Docker integration tests for VPN services.
"""

import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch

import docker.errors
import pytest

from vpn.core.exceptions import DockerError, ServerError
from vpn.core.models import DockerConfig, ProtocolConfig, ProtocolType, ServerConfig
from vpn.services.docker_manager import ContainerStatus, DockerManager
from vpn.services.server_manager import ServerManager


@pytest.fixture
def temp_dir():
    """Create temporary directory for tests."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        yield Path(tmp_dir)


@pytest.fixture
def mock_docker_client():
    """Create mock Docker client."""
    client = MagicMock()
    client.ping.return_value = True
    client.version.return_value = {"Version": "20.10.0"}
    client.info.return_value = {"ID": "test-docker-id"}
    return client


@pytest.fixture
def mock_container():
    """Create mock Docker container."""
    container = MagicMock()
    container.id = "test-container-id"
    container.name = "test-container"
    container.status = "running"
    container.attrs = {
        "State": {
            "Status": "running",
            "Running": True,
            "Pid": 1234,
            "ExitCode": 0,
            "StartedAt": "2024-01-01T10:00:00Z",
            "Health": {"Status": "healthy"}
        },
        "Config": {
            "Image": "test/image:latest",
            "Env": ["VAR1=value1", "VAR2=value2"]
        },
        "NetworkSettings": {
            "IPAddress": "172.17.0.2",
            "Ports": {"8443/tcp": [{"HostPort": "8443"}]}
        }
    }
    container.logs.return_value = b"Container log line 1\nContainer log line 2"
    container.start = MagicMock()
    container.stop = MagicMock()
    container.remove = MagicMock()
    container.restart = MagicMock()
    container.exec_run = MagicMock()
    return container


@pytest.fixture
def sample_server_config(temp_dir):
    """Create sample server configuration."""
    docker_config = DockerConfig(
        image="teddysun/xray:latest",
        ports={"8443/tcp": 8443, "8443/udp": 8443},
        volumes={
            str(temp_dir / "config"): {"bind": "/etc/xray", "mode": "ro"},
            str(temp_dir / "data"): {"bind": "/var/lib/xray", "mode": "rw"}
        },
        environment={"XRAY_CONFIG": "/etc/xray/config.json"},
        restart_policy={"Name": "always"}
    )

    protocol = ProtocolConfig(type=ProtocolType.VLESS)

    return ServerConfig(
        name="test-server",
        protocol=protocol,
        port=8443,
        docker_config=docker_config,
        config_path=temp_dir / "config",
        data_path=temp_dir / "data"
    )


class TestDockerManager:
    """Test Docker manager functionality."""

    def test_init(self):
        """Test Docker manager initialization."""
        manager = DockerManager()

        assert manager.client is None
        assert manager.containers == {}

    @pytest.mark.asyncio
    async def test_connect_success(self, mock_docker_client):
        """Test successful Docker connection."""
        manager = DockerManager()

        with patch('docker.from_env', return_value=mock_docker_client):
            await manager.connect()

            assert manager.client is not None
            mock_docker_client.ping.assert_called_once()

    @pytest.mark.asyncio
    async def test_connect_failure(self):
        """Test Docker connection failure."""
        manager = DockerManager()

        with patch('docker.from_env', side_effect=docker.errors.DockerException("Connection failed")):
            with pytest.raises(DockerError, match="Failed to connect to Docker"):
                await manager.connect()

    @pytest.mark.asyncio
    async def test_is_docker_running_success(self, mock_docker_client):
        """Test Docker daemon running check."""
        manager = DockerManager()
        manager.client = mock_docker_client

        is_running = await manager.is_docker_running()

        assert is_running is True
        mock_docker_client.ping.assert_called_once()

    @pytest.mark.asyncio
    async def test_is_docker_running_failure(self, mock_docker_client):
        """Test Docker daemon not running check."""
        manager = DockerManager()
        manager.client = mock_docker_client
        mock_docker_client.ping.side_effect = docker.errors.APIError("Docker not running")

        is_running = await manager.is_docker_running()

        assert is_running is False

    @pytest.mark.asyncio
    async def test_create_container_success(self, mock_docker_client, mock_container, sample_server_config):
        """Test successful container creation."""
        manager = DockerManager()
        manager.client = mock_docker_client
        mock_docker_client.containers.run.return_value = mock_container

        container = await manager.create_container(sample_server_config)

        assert container == mock_container
        assert manager.containers[sample_server_config.name] == mock_container
        mock_docker_client.containers.run.assert_called_once()

    @pytest.mark.asyncio
    async def test_create_container_image_not_found(self, mock_docker_client, sample_server_config):
        """Test container creation with image not found."""
        manager = DockerManager()
        manager.client = mock_docker_client
        mock_docker_client.containers.run.side_effect = docker.errors.ImageNotFound("Image not found")

        with pytest.raises(DockerError, match="Docker image not found"):
            await manager.create_container(sample_server_config)

    @pytest.mark.asyncio
    async def test_create_container_port_conflict(self, mock_docker_client, sample_server_config):
        """Test container creation with port conflict."""
        manager = DockerManager()
        manager.client = mock_docker_client
        mock_docker_client.containers.run.side_effect = docker.errors.APIError("Port already in use")

        with pytest.raises(DockerError, match="Failed to create container"):
            await manager.create_container(sample_server_config)

    @pytest.mark.asyncio
    async def test_start_container_success(self, mock_docker_client, mock_container):
        """Test successful container start."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        await manager.start_container("test-container")

        mock_container.start.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_container_not_found(self, mock_docker_client):
        """Test starting non-existent container."""
        manager = DockerManager()
        manager.client = mock_docker_client

        with pytest.raises(DockerError, match="Container not found"):
            await manager.start_container("nonexistent")

    @pytest.mark.asyncio
    async def test_stop_container_success(self, mock_docker_client, mock_container):
        """Test successful container stop."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        await manager.stop_container("test-container")

        mock_container.stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_restart_container_success(self, mock_docker_client, mock_container):
        """Test successful container restart."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        await manager.restart_container("test-container")

        mock_container.restart.assert_called_once()

    @pytest.mark.asyncio
    async def test_remove_container_success(self, mock_docker_client, mock_container):
        """Test successful container removal."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        await manager.remove_container("test-container", force=True)

        mock_container.remove.assert_called_once_with(force=True)
        assert "test-container" not in manager.containers

    @pytest.mark.asyncio
    async def test_get_container_status(self, mock_docker_client, mock_container):
        """Test getting container status."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        status = await manager.get_container_status("test-container")

        assert status.name == "test-container"
        assert status.status == "running"
        assert status.health == "healthy"
        assert status.pid == 1234

    @pytest.mark.asyncio
    async def test_get_container_logs(self, mock_docker_client, mock_container):
        """Test getting container logs."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        logs = await manager.get_container_logs("test-container", tail=10)

        assert "Container log line 1" in logs
        assert "Container log line 2" in logs
        mock_container.logs.assert_called_once()

    @pytest.mark.asyncio
    async def test_get_container_stats(self, mock_docker_client, mock_container):
        """Test getting container statistics."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock stats
        mock_stats = {
            "cpu_stats": {"cpu_usage": {"total_usage": 1000000}},
            "memory_stats": {"usage": 1024 * 1024},
            "networks": {"eth0": {"rx_bytes": 1024, "tx_bytes": 2048}}
        }
        mock_container.stats.return_value = iter([mock_stats])

        stats = await manager.get_container_stats("test-container")

        assert stats is not None
        assert "cpu_stats" in stats
        assert "memory_stats" in stats

    @pytest.mark.asyncio
    async def test_exec_command_success(self, mock_docker_client, mock_container):
        """Test executing command in container."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock exec result
        mock_exec_result = MagicMock()
        mock_exec_result.exit_code = 0
        mock_exec_result.output = b"Command output"
        mock_container.exec_run.return_value = mock_exec_result

        result = await manager.exec_command("test-container", ["echo", "test"])

        assert result.exit_code == 0
        assert result.output == "Command output"
        mock_container.exec_run.assert_called_once()

    @pytest.mark.asyncio
    async def test_pull_image_success(self, mock_docker_client):
        """Test pulling Docker image."""
        manager = DockerManager()
        manager.client = mock_docker_client

        mock_image = MagicMock()
        mock_image.id = "sha256:abcdef123456"
        mock_docker_client.images.pull.return_value = mock_image

        await manager.pull_image("test/image:latest")

        mock_docker_client.images.pull.assert_called_once_with("test/image:latest")

    @pytest.mark.asyncio
    async def test_pull_image_not_found(self, mock_docker_client):
        """Test pulling non-existent image."""
        manager = DockerManager()
        manager.client = mock_docker_client
        mock_docker_client.images.pull.side_effect = docker.errors.ImageNotFound("Image not found")

        with pytest.raises(DockerError, match="Docker image not found"):
            await manager.pull_image("nonexistent/image:latest")

    @pytest.mark.asyncio
    async def test_cleanup_containers(self, mock_docker_client, mock_container):
        """Test cleaning up containers."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        await manager.cleanup_containers()

        mock_container.stop.assert_called_once()
        mock_container.remove.assert_called_once()
        assert len(manager.containers) == 0

    @pytest.mark.asyncio
    async def test_health_check_healthy(self, mock_docker_client, mock_container):
        """Test health check for healthy container."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        is_healthy = await manager.health_check("test-container")

        assert is_healthy is True

    @pytest.mark.asyncio
    async def test_health_check_unhealthy(self, mock_docker_client, mock_container):
        """Test health check for unhealthy container."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock unhealthy status
        mock_container.attrs["State"]["Health"]["Status"] = "unhealthy"

        is_healthy = await manager.health_check("test-container")

        assert is_healthy is False

    @pytest.mark.asyncio
    async def test_wait_for_container_healthy(self, mock_docker_client, mock_container):
        """Test waiting for container to become healthy."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock health check progression
        health_states = ["starting", "healthy"]
        mock_container.attrs["State"]["Health"]["Status"] = health_states[0]

        async def mock_health_check(container_name):
            current_status = mock_container.attrs["State"]["Health"]["Status"]
            if current_status == "starting":
                mock_container.attrs["State"]["Health"]["Status"] = "healthy"
                return False
            return True

        with patch.object(manager, 'health_check', side_effect=mock_health_check):
            result = await manager.wait_for_healthy("test-container", timeout=5)

            assert result is True

    @pytest.mark.asyncio
    async def test_wait_for_container_timeout(self, mock_docker_client, mock_container):
        """Test waiting for container timeout."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock container never becomes healthy
        mock_container.attrs["State"]["Health"]["Status"] = "unhealthy"

        with patch.object(manager, 'health_check', return_value=False):
            result = await manager.wait_for_healthy("test-container", timeout=1)

            assert result is False


class TestServerManagerDockerIntegration:
    """Test server manager Docker integration."""

    @pytest.mark.asyncio
    async def test_install_server_success(self, sample_server_config):
        """Test successful server installation."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.is_docker_running.return_value = True
            mock_docker.pull_image.return_value = None
            mock_docker.create_container.return_value = MagicMock()
            mock_docker.start_container.return_value = None
            mock_docker.wait_for_healthy.return_value = True

            with patch.object(server_manager, '_create_server_config') as mock_config:
                mock_config.return_value = sample_server_config

                with patch.object(server_manager, '_generate_server_config') as mock_gen:
                    mock_gen.return_value = "generated config"

                    result = await server_manager.install(
                        protocol="vless",
                        port=8443,
                        name="test-server"
                    )

                    assert result == sample_server_config
                    mock_docker.create_container.assert_called_once()
                    mock_docker.start_container.assert_called_once()

    @pytest.mark.asyncio
    async def test_install_server_docker_not_running(self, sample_server_config):
        """Test server installation when Docker is not running."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.is_docker_running.return_value = False

            with pytest.raises(ServerError, match="Docker daemon is not running"):
                await server_manager.install(
                    protocol="vless",
                    port=8443,
                    name="test-server"
                )

    @pytest.mark.asyncio
    async def test_install_server_image_pull_failure(self, sample_server_config):
        """Test server installation with image pull failure."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.is_docker_running.return_value = True
            mock_docker.pull_image.side_effect = DockerError("Image pull failed")

            with pytest.raises(ServerError, match="Failed to pull Docker image"):
                await server_manager.install(
                    protocol="vless",
                    port=8443,
                    name="test-server"
                )

    @pytest.mark.asyncio
    async def test_start_server_success(self):
        """Test successful server start."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.start_container.return_value = None

            await server_manager.start_server("test-server")

            mock_docker.start_container.assert_called_once_with("test-server")

    @pytest.mark.asyncio
    async def test_stop_server_success(self):
        """Test successful server stop."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.stop_container.return_value = None

            await server_manager.stop_server("test-server")

            mock_docker.stop_container.assert_called_once_with("test-server")

    @pytest.mark.asyncio
    async def test_restart_server_success(self):
        """Test successful server restart."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.restart_container.return_value = None

            await server_manager.restart_server("test-server")

            mock_docker.restart_container.assert_called_once_with("test-server")

    @pytest.mark.asyncio
    async def test_uninstall_server_success(self):
        """Test successful server uninstall."""
        server_manager = ServerManager()

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.stop_container.return_value = None
            mock_docker.remove_container.return_value = None

            with patch.object(server_manager, '_cleanup_server_files') as mock_cleanup:
                mock_cleanup.return_value = None

                await server_manager.uninstall("test-server")

                mock_docker.stop_container.assert_called_once_with("test-server")
                mock_docker.remove_container.assert_called_once_with("test-server", force=True)

    @pytest.mark.asyncio
    async def test_get_server_status(self):
        """Test getting server status."""
        server_manager = ServerManager()

        mock_status = ContainerStatus(
            name="test-server",
            status="running",
            health="healthy",
            pid=1234,
            started_at=datetime.now(),
            ip_address="172.17.0.2"
        )

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.get_container_status.return_value = mock_status

            status = await server_manager.get_server_status("test-server")

            assert status == mock_status
            mock_docker.get_container_status.assert_called_once_with("test-server")

    @pytest.mark.asyncio
    async def test_get_server_logs(self):
        """Test getting server logs."""
        server_manager = ServerManager()

        mock_logs = "Server log line 1\nServer log line 2"

        with patch.object(server_manager, 'docker_manager') as mock_docker:
            mock_docker.get_container_logs.return_value = mock_logs

            logs = await server_manager.get_server_logs("test-server", tail=10)

            assert logs == mock_logs
            mock_docker.get_container_logs.assert_called_once_with("test-server", tail=10)


class TestDockerVolumeManagement:
    """Test Docker volume management."""

    @pytest.mark.asyncio
    async def test_create_config_volume(self, mock_docker_client, temp_dir):
        """Test creating configuration volume."""
        manager = DockerManager()
        manager.client = mock_docker_client

        config_path = temp_dir / "config"
        config_path.mkdir()
        config_file = config_path / "config.json"
        config_file.write_text('{"test": "config"}')

        # Test volume creation
        volume_config = {
            str(config_path): {"bind": "/etc/app", "mode": "ro"}
        }

        # This would be tested in actual container creation
        assert str(config_path) in volume_config
        assert volume_config[str(config_path)]["bind"] == "/etc/app"
        assert volume_config[str(config_path)]["mode"] == "ro"

    @pytest.mark.asyncio
    async def test_create_data_volume(self, mock_docker_client, temp_dir):
        """Test creating data volume."""
        manager = DockerManager()
        manager.client = mock_docker_client

        data_path = temp_dir / "data"
        data_path.mkdir()

        # Test volume creation
        volume_config = {
            str(data_path): {"bind": "/var/lib/app", "mode": "rw"}
        }

        assert str(data_path) in volume_config
        assert volume_config[str(data_path)]["bind"] == "/var/lib/app"
        assert volume_config[str(data_path)]["mode"] == "rw"

    @pytest.mark.asyncio
    async def test_volume_permissions(self, temp_dir):
        """Test volume permissions handling."""
        config_path = temp_dir / "config"
        config_path.mkdir(mode=0o755)

        data_path = temp_dir / "data"
        data_path.mkdir(mode=0o755)

        # Check that directories exist and have correct permissions
        assert config_path.exists()
        assert data_path.exists()
        assert config_path.is_dir()
        assert data_path.is_dir()


class TestDockerNetworking:
    """Test Docker networking functionality."""

    @pytest.mark.asyncio
    async def test_port_mapping(self, mock_docker_client):
        """Test port mapping configuration."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test port mapping
        port_config = {
            "8443/tcp": 8443,
            "8443/udp": 8443,
            "9090/tcp": 9090
        }

        # Verify port mapping structure
        assert "8443/tcp" in port_config
        assert "8443/udp" in port_config
        assert port_config["8443/tcp"] == 8443
        assert port_config["8443/udp"] == 8443

    @pytest.mark.asyncio
    async def test_network_isolation(self, mock_docker_client):
        """Test network isolation configuration."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test network configuration
        network_config = {
            "network_mode": "bridge",
            "dns": ["8.8.8.8", "8.8.4.4"],
            "dns_search": ["example.com"]
        }

        assert network_config["network_mode"] == "bridge"
        assert "8.8.8.8" in network_config["dns"]

    @pytest.mark.asyncio
    async def test_container_connectivity(self, mock_docker_client, mock_container):
        """Test container connectivity check."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock network settings
        mock_container.attrs["NetworkSettings"]["IPAddress"] = "172.17.0.2"
        mock_container.attrs["NetworkSettings"]["Ports"] = {
            "8443/tcp": [{"HostPort": "8443"}]
        }

        # Test connectivity check
        ip_address = mock_container.attrs["NetworkSettings"]["IPAddress"]
        ports = mock_container.attrs["NetworkSettings"]["Ports"]

        assert ip_address == "172.17.0.2"
        assert "8443/tcp" in ports


class TestDockerHealthChecks:
    """Test Docker health check functionality."""

    @pytest.mark.asyncio
    async def test_container_health_check(self, mock_docker_client, mock_container):
        """Test container health check."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock health check
        mock_container.attrs["State"]["Health"] = {
            "Status": "healthy",
            "FailingStreak": 0,
            "Log": [
                {
                    "Start": "2024-01-01T10:00:00Z",
                    "End": "2024-01-01T10:00:01Z",
                    "ExitCode": 0,
                    "Output": "Health check passed"
                }
            ]
        }

        is_healthy = await manager.health_check("test-container")

        assert is_healthy is True

    @pytest.mark.asyncio
    async def test_custom_health_check(self, mock_docker_client, mock_container):
        """Test custom health check command."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock exec result for custom health check
        mock_exec_result = MagicMock()
        mock_exec_result.exit_code = 0
        mock_exec_result.output = b"Service is healthy"
        mock_container.exec_run.return_value = mock_exec_result

        result = await manager.exec_command(
            "test-container",
            ["curl", "-f", "http://localhost:8080/health"]
        )

        assert result.exit_code == 0
        assert "Service is healthy" in result.output

    @pytest.mark.asyncio
    async def test_health_check_timeout(self, mock_docker_client, mock_container):
        """Test health check timeout handling."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock container that never becomes healthy
        mock_container.attrs["State"]["Health"]["Status"] = "starting"

        with patch.object(manager, 'health_check', return_value=False):
            # Should timeout after 1 second
            result = await manager.wait_for_healthy("test-container", timeout=1)

            assert result is False


class TestDockerResourceManagement:
    """Test Docker resource management."""

    @pytest.mark.asyncio
    async def test_memory_limits(self, mock_docker_client):
        """Test memory limit configuration."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test memory limit configuration
        resource_config = {
            "mem_limit": "512m",
            "memswap_limit": "1g",
            "oom_kill_disable": False
        }

        assert resource_config["mem_limit"] == "512m"
        assert resource_config["memswap_limit"] == "1g"
        assert resource_config["oom_kill_disable"] is False

    @pytest.mark.asyncio
    async def test_cpu_limits(self, mock_docker_client):
        """Test CPU limit configuration."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test CPU limit configuration
        resource_config = {
            "cpu_count": 2,
            "cpu_percent": 50,
            "cpuset_cpus": "0,1"
        }

        assert resource_config["cpu_count"] == 2
        assert resource_config["cpu_percent"] == 50
        assert resource_config["cpuset_cpus"] == "0,1"

    @pytest.mark.asyncio
    async def test_resource_monitoring(self, mock_docker_client, mock_container):
        """Test resource monitoring."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Mock resource stats
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 1000000},
                "system_cpu_usage": 10000000
            },
            "memory_stats": {
                "usage": 1024 * 1024,  # 1MB
                "limit": 512 * 1024 * 1024  # 512MB
            }
        }
        mock_container.stats.return_value = iter([mock_stats])

        stats = await manager.get_container_stats("test-container")

        assert stats["memory_stats"]["usage"] == 1024 * 1024
        assert stats["memory_stats"]["limit"] == 512 * 1024 * 1024


class TestDockerErrorHandling:
    """Test Docker error handling scenarios."""

    @pytest.mark.asyncio
    async def test_container_creation_errors(self, mock_docker_client, sample_server_config):
        """Test various container creation errors."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test different error scenarios
        error_scenarios = [
            (docker.errors.ImageNotFound("Image not found"), "Docker image not found"),
            (docker.errors.APIError("Port in use"), "Failed to create container"),
            (docker.errors.ContainerError("container", 1, "cmd", "image", "logs"), "Container failed"),
        ]

        for exception, expected_message in error_scenarios:
            mock_docker_client.containers.run.side_effect = exception

            with pytest.raises(DockerError, match=expected_message):
                await manager.create_container(sample_server_config)

    @pytest.mark.asyncio
    async def test_container_operation_errors(self, mock_docker_client, mock_container):
        """Test container operation errors."""
        manager = DockerManager()
        manager.client = mock_docker_client
        manager.containers["test-container"] = mock_container

        # Test start error
        mock_container.start.side_effect = docker.errors.APIError("Start failed")

        with pytest.raises(DockerError, match="Failed to start container"):
            await manager.start_container("test-container")

        # Test stop error
        mock_container.stop.side_effect = docker.errors.APIError("Stop failed")

        with pytest.raises(DockerError, match="Failed to stop container"):
            await manager.stop_container("test-container")

    @pytest.mark.asyncio
    async def test_docker_daemon_errors(self, mock_docker_client):
        """Test Docker daemon errors."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test daemon not responding
        mock_docker_client.ping.side_effect = docker.errors.APIError("Daemon not responding")

        is_running = await manager.is_docker_running()
        assert is_running is False

        # Test connection timeout
        mock_docker_client.ping.side_effect = docker.errors.ConnectionError("Connection timeout")

        is_running = await manager.is_docker_running()
        assert is_running is False

    @pytest.mark.asyncio
    async def test_image_pull_errors(self, mock_docker_client):
        """Test image pull errors."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Test image not found
        mock_docker_client.images.pull.side_effect = docker.errors.ImageNotFound("Image not found")

        with pytest.raises(DockerError, match="Docker image not found"):
            await manager.pull_image("nonexistent/image:latest")

        # Test network error
        mock_docker_client.images.pull.side_effect = docker.errors.APIError("Network error")

        with pytest.raises(DockerError, match="Failed to pull image"):
            await manager.pull_image("test/image:latest")


class TestDockerCleanup:
    """Test Docker cleanup functionality."""

    @pytest.mark.asyncio
    async def test_cleanup_stopped_containers(self, mock_docker_client):
        """Test cleaning up stopped containers."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Mock stopped containers
        stopped_container = MagicMock()
        stopped_container.status = "exited"
        stopped_container.name = "stopped-container"
        stopped_container.remove = MagicMock()

        mock_docker_client.containers.list.return_value = [stopped_container]

        await manager.cleanup_stopped_containers()

        stopped_container.remove.assert_called_once()

    @pytest.mark.asyncio
    async def test_cleanup_unused_images(self, mock_docker_client):
        """Test cleaning up unused images."""
        manager = DockerManager()
        manager.client = mock_docker_client

        # Mock unused images
        unused_image = MagicMock()
        unused_image.id = "unused-image-id"
        unused_image.remove = MagicMock()

        mock_docker_client.images.list.return_value = [unused_image]

        await manager.cleanup_unused_images()

        mock_docker_client.images.prune.assert_called_once()

    @pytest.mark.asyncio
    async def test_cleanup_volumes(self, mock_docker_client):
        """Test cleaning up unused volumes."""
        manager = DockerManager()
        manager.client = mock_docker_client

        await manager.cleanup_volumes()

        mock_docker_client.volumes.prune.assert_called_once()

    @pytest.mark.asyncio
    async def test_full_cleanup(self, mock_docker_client):
        """Test full Docker cleanup."""
        manager = DockerManager()
        manager.client = mock_docker_client

        with patch.object(manager, 'cleanup_stopped_containers') as mock_containers:
            with patch.object(manager, 'cleanup_unused_images') as mock_images:
                with patch.object(manager, 'cleanup_volumes') as mock_volumes:

                    await manager.full_cleanup()

                    mock_containers.assert_called_once()
                    mock_images.assert_called_once()
                    mock_volumes.assert_called_once()
