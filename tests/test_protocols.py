"""
Tests for VPN protocol implementations.
"""

import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from vpn.core.models import ProtocolConfig, ProtocolType, ServerConfig, User
from vpn.protocols.base import BaseProtocol, ConnectionInfo
from vpn.protocols.shadowsocks import ShadowsocksProtocol
from vpn.protocols.vless import VLESSProtocol
from vpn.protocols.wireguard import WireGuardProtocol


@pytest.fixture
def temp_dir():
    """Create temporary directory for tests."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        yield Path(tmp_dir)


@pytest.fixture
def sample_user():
    """Create sample user for testing."""
    protocol = ProtocolConfig(type=ProtocolType.VLESS)
    return User(
        username="testuser",
        email="test@example.com",
        protocol=protocol
    )


@pytest.fixture
def sample_server_config(temp_dir):
    """Create sample server config for testing."""
    protocol = ProtocolConfig(type=ProtocolType.VLESS)
    return ServerConfig(
        name="test-server",
        protocol=protocol,
        port=8443,
        domain="vpn.example.com",
        public_ip="1.2.3.4",
        config_path=temp_dir / "config",
        data_path=temp_dir / "data",
        extra_config={
            "reality": {
                "dest": "www.google.com:443",
                "server_names": ["www.google.com"],
                "private_key": "test_private_key",
                "public_key": "test_public_key",
                "short_ids": ["", "0123456789abcdef"]
            }
        }
    )


class TestVLESSProtocol:
    """Test VLESS protocol implementation."""

    def test_init(self, sample_server_config):
        """Test VLESS protocol initialization."""
        protocol = VLESSProtocol(sample_server_config)

        assert protocol.server_config == sample_server_config
        assert protocol.name == "vless"
        assert protocol.reality_config == sample_server_config.extra_config["reality"]

    @pytest.mark.asyncio
    async def test_generate_server_config(self, sample_server_config, temp_dir):
        """Test server configuration generation."""
        protocol = VLESSProtocol(sample_server_config)

        # Create template file
        template_path = temp_dir / "config.json.j2"
        template_content = """
{
  "inbounds": [{
    "port": {{ server.port }},
    "protocol": "{{ protocol }}",
    "settings": {
      "clients": [
        {% for user in users %}
        {
          "id": "{{ user.id }}",
          "email": "{{ user.email }}"
        }{% if not loop.last %},{% endif %}
        {% endfor %}
      ]
    }
  }]
}
"""
        template_path.write_text(template_content)

        # Mock users
        with patch('vpn.protocols.vless.get_all_users') as mock_users:
            mock_users.return_value = []

            config = await protocol.generate_server_config(template_path)

            assert "8443" in config
            assert "vless" in config
            assert "inbounds" in config

    @pytest.mark.asyncio
    async def test_generate_user_config(self, sample_server_config, sample_user):
        """Test user configuration generation."""
        protocol = VLESSProtocol(sample_server_config)

        config = await protocol.generate_user_config(sample_user)

        assert config["id"] == str(sample_user.id)
        assert config["email"] == sample_user.email
        assert config["level"] == 0

    @pytest.mark.asyncio
    async def test_generate_connection_link(self, sample_server_config, sample_user):
        """Test connection link generation."""
        protocol = VLESSProtocol(sample_server_config)

        link = await protocol.generate_connection_link(sample_user)

        assert link.startswith("vless://")
        assert str(sample_user.id) in link
        assert "vpn.example.com" in link
        assert "8443" in link
        assert sample_user.username in link

    @pytest.mark.asyncio
    async def test_validate_config(self, sample_server_config):
        """Test configuration validation."""
        protocol = VLESSProtocol(sample_server_config)

        # Valid config
        is_valid = await protocol.validate_config({})
        assert is_valid is True

        # Invalid config (missing reality keys)
        sample_server_config.extra_config["reality"] = {}
        protocol = VLESSProtocol(sample_server_config)

        is_valid = await protocol.validate_config({})
        assert is_valid is False

    def test_get_docker_image(self, sample_server_config):
        """Test Docker image retrieval."""
        protocol = VLESSProtocol(sample_server_config)

        image = protocol.get_docker_image()
        assert image == "teddysun/xray:latest"

    def test_get_docker_env(self, sample_server_config):
        """Test Docker environment variables."""
        protocol = VLESSProtocol(sample_server_config)

        env = protocol.get_docker_env()

        assert "XRAY_CONFIG" in env
        assert env["XRAY_CONFIG"] == "/etc/xray/config.json"

    def test_get_docker_volumes(self, sample_server_config):
        """Test Docker volume mappings."""
        protocol = VLESSProtocol(sample_server_config)

        volumes = protocol.get_docker_volumes()

        assert any("/etc/xray" in v for v in volumes.values())
        assert any("/var/log/xray" in v for v in volumes.values())

    def test_get_docker_ports(self, sample_server_config):
        """Test Docker port mappings."""
        protocol = VLESSProtocol(sample_server_config)

        ports = protocol.get_docker_ports()

        assert "8443/tcp" in ports
        assert "8443/udp" in ports

    def test_get_health_check(self, sample_server_config):
        """Test health check configuration."""
        protocol = VLESSProtocol(sample_server_config)

        health_check = protocol.get_health_check()

        assert "test" in health_check
        assert "xray" in health_check["test"][1]
        assert health_check["interval"] == "30s"

    @pytest.mark.asyncio
    async def test_generate_reality_keys(self, sample_server_config):
        """Test Reality key generation."""
        protocol = VLESSProtocol(sample_server_config)

        with patch('subprocess.run') as mock_run:
            # Mock successful xray key generation
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="Private key: test_private_key\nPublic key: test_public_key\n"
            )

            keys = await protocol.generate_reality_keys()

            assert "private_key" in keys
            assert "public_key" in keys
            assert keys["private_key"] == "test_private_key"
            assert keys["public_key"] == "test_public_key"

    @pytest.mark.asyncio
    async def test_generate_reality_keys_fallback(self, sample_server_config):
        """Test Reality key generation fallback."""
        protocol = VLESSProtocol(sample_server_config)

        with patch('subprocess.run') as mock_run:
            # Mock failed xray key generation
            mock_run.return_value = MagicMock(returncode=1)

            with patch('vpn.services.crypto.CryptoService') as mock_crypto:
                mock_crypto_instance = AsyncMock()
                mock_crypto_instance.generate_private_key.return_value = "fallback_private"
                mock_crypto_instance.derive_public_key.return_value = "fallback_public"
                mock_crypto.return_value = mock_crypto_instance

                keys = await protocol.generate_reality_keys()

                assert keys["private_key"] == "fallback_private"
                assert keys["public_key"] == "fallback_public"


class TestShadowsocksProtocol:
    """Test Shadowsocks protocol implementation."""

    def test_init(self, sample_server_config):
        """Test Shadowsocks protocol initialization."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        assert protocol.server_config == sample_server_config
        assert protocol.name == "shadowsocks"
        assert protocol.cipher == "aes-256-gcm"
        assert len(protocol.password) >= 16

    @pytest.mark.asyncio
    async def test_generate_server_config(self, sample_server_config, temp_dir):
        """Test server configuration generation."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        # Create template file
        template_path = temp_dir / "config.json.j2"
        template_content = """
{
  "server": "0.0.0.0",
  "server_port": {{ server.port }},
  "method": "{{ cipher }}",
  "password": "{{ password }}"
}
"""
        template_path.write_text(template_content)

        with patch.object(protocol, '_get_all_users', return_value=[]):
            config = await protocol.generate_server_config(template_path)

            assert "8443" in config
            assert "aes-256-gcm" in config
            assert protocol.password in config

    @pytest.mark.asyncio
    async def test_generate_user_config(self, sample_server_config, sample_user):
        """Test user configuration generation."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        config = await protocol.generate_user_config(sample_user)

        assert config["id"] == str(sample_user.id)
        assert config["name"] == sample_user.username
        assert config["method"] == "aes-256-gcm"
        assert "password" in config
        assert "accessUrl" in config

    @pytest.mark.asyncio
    async def test_generate_connection_link(self, sample_server_config, sample_user):
        """Test connection link generation."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        link = await protocol.generate_connection_link(sample_user)

        assert link.startswith("ss://")
        assert "vpn.example.com" in link
        assert "8443" in link
        assert sample_user.username in link

    @pytest.mark.asyncio
    async def test_validate_config(self, sample_server_config):
        """Test configuration validation."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        # Valid config
        is_valid = await protocol.validate_config({})
        assert is_valid is True

        # Invalid cipher
        protocol.cipher = "invalid_cipher"
        is_valid = await protocol.validate_config({})
        assert is_valid is False

    def test_get_docker_image(self, sample_server_config):
        """Test Docker image retrieval."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        image = protocol.get_docker_image()
        assert "shadowbox" in image or "shadowsocks" in image

    def test_get_docker_env(self, sample_server_config):
        """Test Docker environment variables."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        env = protocol.get_docker_env()

        assert "METHOD" in env
        assert "PASSWORD" in env
        assert env["METHOD"] == "aes-256-gcm"

    def test_get_docker_ports(self, sample_server_config):
        """Test Docker port mappings."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        ports = protocol.get_docker_ports()

        assert "8443/tcp" in ports
        assert "8443/udp" in ports

    @pytest.mark.asyncio
    async def test_generate_access_key(self, sample_server_config, sample_user):
        """Test access key generation."""
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        protocol = ShadowsocksProtocol(sample_server_config)

        access_key = await protocol.generate_access_key(sample_user)

        assert "password" in access_key
        assert "port" in access_key
        assert "method" in access_key
        assert "access_url" in access_key
        assert access_key["access_url"].startswith("ss://")


class TestWireGuardProtocol:
    """Test WireGuard protocol implementation."""

    def test_init(self, sample_server_config):
        """Test WireGuard protocol initialization."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        assert protocol.server_config == sample_server_config
        assert protocol.name == "wireguard"
        assert protocol.interface == "wg0"
        assert protocol.network == "10.0.0.0/24"

    @pytest.mark.asyncio
    async def test_generate_server_config(self, sample_server_config, temp_dir):
        """Test server configuration generation."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        # Create template file
        template_path = temp_dir / "wg0.conf.j2"
        template_content = """
[Interface]
PrivateKey = {{ private_key }}
Address = {{ address }}
ListenPort = {{ port }}

{% for peer in peers %}
[Peer]
PublicKey = {{ peer.public_key }}
AllowedIPs = {{ peer.allowed_ips | join(', ') }}
{% endfor %}
"""
        template_path.write_text(template_content)

        with patch.object(protocol, '_get_peer_configs', return_value=[]):
            config = await protocol.generate_server_config(template_path)

            assert "Interface" in config
            assert "PrivateKey" in config
            assert "8443" in config

    @pytest.mark.asyncio
    async def test_generate_user_config(self, sample_server_config, sample_user):
        """Test user configuration generation."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        # Mock key generation
        with patch.object(protocol, 'generate_keypair') as mock_keys:
            mock_keys.return_value = {
                "private_key": "test_private",
                "public_key": "test_public"
            }

            with patch.object(protocol, 'generate_preshared_key') as mock_psk:
                mock_psk.return_value = "test_preshared"

                config = await protocol.generate_user_config(sample_user)

                assert config["public_key"] == "test_public"
                assert config["preshared_key"] == "test_preshared"
                assert "allowed_ips" in config
                assert "client_config" in config

    @pytest.mark.asyncio
    async def test_generate_connection_link(self, sample_server_config, sample_user):
        """Test connection link generation."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        # Mock required methods
        with patch.object(protocol, 'generate_user_config') as mock_config:
            mock_config.return_value = {
                "client_config": {
                    "private_key": "test_private",
                    "address": "10.0.0.2/24",
                    "dns": ["1.1.1.1"],
                    "mtu": 1420
                },
                "preshared_key": "test_preshared"
            }

            sample_server_config.extra_config["public_key"] = "server_public_key"

            link = await protocol.generate_connection_link(sample_user)

            assert link.startswith("wireguard://")
            assert sample_user.username in link

    @pytest.mark.asyncio
    async def test_validate_config(self, sample_server_config):
        """Test configuration validation."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        # Mock subprocess for wg command
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(returncode=0)

            is_valid = await protocol.validate_config({})
            assert is_valid is True

            # Test invalid network
            protocol.network = "invalid_network"
            is_valid = await protocol.validate_config({})
            assert is_valid is False

    def test_get_docker_image(self, sample_server_config):
        """Test Docker image retrieval."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        image = protocol.get_docker_image()
        assert "wireguard" in image

    def test_get_docker_env(self, sample_server_config):
        """Test Docker environment variables."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        env = protocol.get_docker_env()

        assert "SERVERURL" in env
        assert "SERVERPORT" in env
        assert "INTERNAL_SUBNET" in env
        assert env["SERVERPORT"] == "8443"

    def test_get_docker_ports(self, sample_server_config):
        """Test Docker port mappings."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        ports = protocol.get_docker_ports()

        assert "8443/udp" in ports

    @pytest.mark.asyncio
    async def test_generate_keypair(self, sample_server_config):
        """Test key pair generation."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        with patch('subprocess.run') as mock_run:
            # Mock wg genkey
            mock_run.side_effect = [
                MagicMock(returncode=0, stdout="test_private_key"),
                MagicMock(returncode=0, stdout="test_public_key")
            ]

            keys = await protocol.generate_keypair()

            assert keys["private_key"] == "test_private_key"
            assert keys["public_key"] == "test_public_key"

    @pytest.mark.asyncio
    async def test_generate_preshared_key(self, sample_server_config):
        """Test preshared key generation."""
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        protocol = WireGuardProtocol(sample_server_config)

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="test_preshared_key")

            psk = await protocol.generate_preshared_key()

            assert psk == "test_preshared_key"


class TestBaseProtocol:
    """Test base protocol functionality."""

    def test_abstract_methods(self):
        """Test that BaseProtocol is abstract."""
        with pytest.raises(TypeError):
            BaseProtocol()

    @pytest.mark.asyncio
    async def test_get_connection_info(self, sample_server_config, sample_user):
        """Test connection info generation."""
        # Create concrete protocol instance
        protocol = VLESSProtocol(sample_server_config)

        with patch.object(protocol, 'generate_connection_link') as mock_link:
            mock_link.return_value = "vless://test-connection-string"

            with patch('vpn.services.crypto.CryptoService') as mock_crypto:
                mock_crypto_instance = AsyncMock()
                mock_crypto_instance.generate_qr_code.return_value = "qr_code_data"
                mock_crypto.return_value = mock_crypto_instance

                connection_info = await protocol.get_connection_info(sample_user)

                assert isinstance(connection_info, ConnectionInfo)
                assert connection_info.protocol == "vless"
                assert connection_info.server == "vpn.example.com"
                assert connection_info.port == 8443
                assert connection_info.user_id == str(sample_user.id)
                assert connection_info.connection_string == "vless://test-connection-string"
                assert connection_info.qr_code == "qr_code_data"

    def test_get_connection_instructions(self, sample_server_config):
        """Test connection instructions generation."""
        protocol = VLESSProtocol(sample_server_config)

        instructions = protocol.get_connection_instructions()

        assert "Install" in instructions
        assert "client" in instructions
        assert "VLESS" in instructions

    def test_get_firewall_rules(self, sample_server_config):
        """Test firewall rules generation."""
        protocol = VLESSProtocol(sample_server_config)

        rules = protocol.get_firewall_rules()

        assert len(rules) == 2
        assert rules[0]["port"] == 8443
        assert rules[0]["protocol"] == "tcp"
        assert rules[1]["protocol"] == "udp"
        assert all(rule["action"] == "ACCEPT" for rule in rules)

    @pytest.mark.asyncio
    async def test_pre_install_check(self, sample_server_config):
        """Test pre-installation checks."""
        protocol = VLESSProtocol(sample_server_config)

        with patch.object(protocol, '_check_port_available', return_value=True):
            with patch.object(protocol, '_check_docker_running', return_value=True):
                with patch.object(protocol, '_check_resources', return_value=True):

                    checks = await protocol.pre_install_check()

                    assert checks["port_available"] is True
                    assert checks["docker_running"] is True
                    assert checks["resources_available"] is True

    @pytest.mark.asyncio
    async def test_check_port_available(self, sample_server_config):
        """Test port availability check."""
        protocol = VLESSProtocol(sample_server_config)

        with patch('vpn.services.network_manager.NetworkManager') as mock_network:
            mock_network_instance = AsyncMock()
            mock_network_instance.is_port_available.return_value = True
            mock_network.return_value = mock_network_instance

            is_available = await protocol._check_port_available()

            assert is_available is True
            mock_network_instance.is_port_available.assert_called_once_with(8443)

    @pytest.mark.asyncio
    async def test_check_docker_running(self, sample_server_config):
        """Test Docker daemon check."""
        protocol = VLESSProtocol(sample_server_config)

        with patch('vpn.services.docker_manager.DockerManager') as mock_docker:
            mock_docker_instance = AsyncMock()
            mock_docker_instance.is_docker_running.return_value = True
            mock_docker.return_value = mock_docker_instance

            is_running = await protocol._check_docker_running()

            assert is_running is True

    @pytest.mark.asyncio
    async def test_check_resources(self, sample_server_config):
        """Test system resources check."""
        protocol = VLESSProtocol(sample_server_config)

        with patch('psutil.virtual_memory') as mock_memory:
            mock_memory.return_value = MagicMock(available=1024 * 1024 * 1024)  # 1GB

            with patch('psutil.disk_usage') as mock_disk:
                mock_disk.return_value = MagicMock(free=2048 * 1024 * 1024)  # 2GB

                has_resources = await protocol._check_resources()

                assert has_resources is True

    @pytest.mark.asyncio
    async def test_check_resources_insufficient(self, sample_server_config):
        """Test system resources check with insufficient resources."""
        protocol = VLESSProtocol(sample_server_config)

        with patch('psutil.virtual_memory') as mock_memory:
            mock_memory.return_value = MagicMock(available=256 * 1024 * 1024)  # 256MB

            with patch('psutil.disk_usage') as mock_disk:
                mock_disk.return_value = MagicMock(free=500 * 1024 * 1024)  # 500MB

                has_resources = await protocol._check_resources()

                assert has_resources is False


class TestProtocolFactory:
    """Test protocol factory functionality."""

    def test_protocol_registry(self):
        """Test protocol registry."""
        from vpn.services.server_manager import ServerManager

        manager = ServerManager()

        assert "vless" in manager.PROTOCOLS
        assert "shadowsocks" in manager.PROTOCOLS
        assert "wireguard" in manager.PROTOCOLS

        assert manager.PROTOCOLS["vless"] == VLESSProtocol
        assert manager.PROTOCOLS["shadowsocks"] == ShadowsocksProtocol
        assert manager.PROTOCOLS["wireguard"] == WireGuardProtocol

    def test_protocol_creation(self, sample_server_config):
        """Test protocol instance creation."""
        from vpn.services.server_manager import ServerManager

        manager = ServerManager()

        # Test VLESS protocol creation
        sample_server_config.protocol.type = ProtocolType.VLESS
        vless_protocol = manager.PROTOCOLS["vless"](sample_server_config)
        assert isinstance(vless_protocol, VLESSProtocol)

        # Test Shadowsocks protocol creation
        sample_server_config.protocol.type = ProtocolType.SHADOWSOCKS
        ss_protocol = manager.PROTOCOLS["shadowsocks"](sample_server_config)
        assert isinstance(ss_protocol, ShadowsocksProtocol)

        # Test WireGuard protocol creation
        sample_server_config.protocol.type = ProtocolType.WIREGUARD
        wg_protocol = manager.PROTOCOLS["wireguard"](sample_server_config)
        assert isinstance(wg_protocol, WireGuardProtocol)
