"""
Tests for optimized Pydantic models.
"""

from datetime import datetime, timedelta

import pytest

from vpn.core.optimized_models import (
    OptimizedDockerConfig,
    OptimizedFirewallRule,
    OptimizedServerConfig,
    OptimizedTrafficStats,
    OptimizedUser,
    PerformanceMetrics,
    ProtocolType,
    ProxyConfig,
    ServerStatus,
    ShadowsocksConfig,
    UserStatus,
    VLESSConfig,
    WireGuardConfig,
    create_optimized_user,
    validate_user_batch,
)


class TestOptimizedTrafficStats:
    """Test OptimizedTrafficStats model."""

    def test_frozen_model(self):
        """Test that TrafficStats is frozen."""
        stats = OptimizedTrafficStats(
            upload_bytes=1024,
            download_bytes=2048,
            total_bytes=3072
        )

        # Should not be able to modify frozen model
        with pytest.raises(AttributeError):
            stats.upload_bytes = 2048

        # Should be hashable
        assert hash(stats) is not None

        # Can be used as dict key
        test_dict = {stats: "value"}
        assert test_dict[stats] == "value"

    def test_computed_fields(self):
        """Test computed fields for traffic stats."""
        stats = OptimizedTrafficStats(
            upload_bytes=1024 * 1024 * 10,  # 10 MB
            download_bytes=1024 * 1024 * 20,  # 20 MB
            total_bytes=1024 * 1024 * 30,  # 30 MB
        )

        assert stats.upload_mb == 10.0
        assert stats.download_mb == 20.0
        assert stats.total_mb == 30.0

    def test_validation(self):
        """Test validation of traffic stats."""
        # Negative values should fail
        with pytest.raises(ValueError):
            OptimizedTrafficStats(upload_bytes=-1)

        with pytest.raises(ValueError):
            OptimizedTrafficStats(download_bytes=-1)

        with pytest.raises(ValueError):
            OptimizedTrafficStats(total_bytes=-1)


class TestProtocolConfigs:
    """Test protocol configuration models."""

    def test_vless_config(self):
        """Test VLESS configuration."""
        config = VLESSConfig(
            flow="xtls-rprx-direct",
            reality_enabled=True,
            reality_public_key="test_key",
            reality_short_id="test_id"
        )

        assert config.protocol_type == "vless"
        assert config.flow == "xtls-rprx-direct"
        assert config.reality_enabled is True
        assert config.encryption == "none"  # default

    def test_shadowsocks_config(self):
        """Test Shadowsocks configuration."""
        config = ShadowsocksConfig(
            method="aes-256-gcm",
            password="test_password"
        )

        assert config.protocol_type == "shadowsocks"
        assert config.method == "aes-256-gcm"
        assert config.password == "test_password"

    def test_wireguard_config(self):
        """Test WireGuard configuration."""
        config = WireGuardConfig(
            private_key="private_test",
            public_key="public_test",
            endpoint="1.2.3.4:51820",
            allowed_ips=["10.0.0.0/8", "192.168.0.0/16"]
        )

        assert config.protocol_type == "wireguard"
        assert config.endpoint == "1.2.3.4:51820"
        assert len(config.allowed_ips) == 2

    def test_proxy_config(self):
        """Test proxy configuration."""
        config = ProxyConfig(
            protocol_type="socks5",
            auth_required=True,
            username="proxy_user",
            password="proxy_pass",
            rate_limit=100
        )

        assert config.protocol_type == "socks5"
        assert config.auth_required is True
        assert config.rate_limit == 100


class TestOptimizedUser:
    """Test OptimizedUser model."""

    def test_user_creation(self):
        """Test basic user creation."""
        user = OptimizedUser(
            username="test_user",
            email="test@example.com",
            protocol_config=VLESSConfig(),
            status=UserStatus.ACTIVE
        )

        assert user.username == "test_user"
        assert user.email == "test@example.com"
        assert user.is_active is True
        assert isinstance(user.traffic, OptimizedTrafficStats)

    def test_username_normalization(self):
        """Test username normalization."""
        user = OptimizedUser(
            username="TEST_USER  ",  # With uppercase and spaces
            protocol_config=VLESSConfig()
        )

        assert user.username == "test_user"  # Normalized to lowercase, trimmed

    def test_email_normalization(self):
        """Test email normalization."""
        user = OptimizedUser(
            username="test",
            email="TEST@EXAMPLE.COM  ",
            protocol_config=VLESSConfig()
        )

        assert user.email == "test@example.com"  # Normalized

    def test_username_validation(self):
        """Test username validation."""
        # Too short
        with pytest.raises(ValueError):
            OptimizedUser(
                username="ab",
                protocol_config=VLESSConfig()
            )

        # Too long
        with pytest.raises(ValueError):
            OptimizedUser(
                username="a" * 51,
                protocol_config=VLESSConfig()
            )

        # Invalid characters
        with pytest.raises(ValueError):
            OptimizedUser(
                username="test@user",
                protocol_config=VLESSConfig()
            )

    def test_email_validation(self):
        """Test email validation."""
        # Invalid email format
        with pytest.raises(ValueError):
            OptimizedUser(
                username="test",
                email="invalid-email",
                protocol_config=VLESSConfig()
            )

        with pytest.raises(ValueError):
            OptimizedUser(
                username="test",
                email="test@",
                protocol_config=VLESSConfig()
            )

    def test_expiry_calculation(self):
        """Test expiry date calculations."""
        future_date = datetime.utcnow() + timedelta(days=30)
        user = OptimizedUser(
            username="test",
            protocol_config=VLESSConfig(),
            expires_at=future_date
        )

        assert user.is_active is True
        assert user.days_until_expiry == 29 or user.days_until_expiry == 30

        # Test expired user
        past_date = datetime.utcnow() - timedelta(days=1)
        expired_user = OptimizedUser(
            username="expired",
            protocol_config=VLESSConfig(),
            expires_at=past_date
        )

        assert expired_user.is_active is False
        assert expired_user.days_until_expiry == 0

    def test_discriminated_union_parsing(self):
        """Test discriminated union for protocol configs."""
        # Test with different protocol types
        vless_user = OptimizedUser(
            username="vless_user",
            protocol_config={"protocol_type": "vless", "flow": "xtls-rprx-direct"}
        )
        assert isinstance(vless_user.protocol_config, VLESSConfig)

        ss_user = OptimizedUser(
            username="ss_user",
            protocol_config={"protocol_type": "shadowsocks", "method": "aes-256-gcm"}
        )
        assert isinstance(ss_user.protocol_config, ShadowsocksConfig)

        wg_user = OptimizedUser(
            username="wg_user",
            protocol_config={"protocol_type": "wireguard", "endpoint": "1.2.3.4:51820"}
        )
        assert isinstance(wg_user.protocol_config, WireGuardConfig)

    def test_serialization(self):
        """Test user serialization."""
        user = OptimizedUser(
            username="test",
            email="test@example.com",
            protocol_config=VLESSConfig(reality_enabled=True),
        )

        # JSON serialization
        json_data = user.model_dump_json()
        assert isinstance(json_data, str)
        assert "test" in json_data

        # Python dict serialization
        dict_data = user.model_dump(mode='python')
        assert isinstance(dict_data, dict)
        assert dict_data['username'] == "test"
        assert dict_data['email'] == "test@example.com"


class TestOptimizedFirewallRule:
    """Test OptimizedFirewallRule model."""

    def test_frozen_firewall_rule(self):
        """Test that firewall rules are frozen."""
        rule = OptimizedFirewallRule(
            protocol="tcp",
            port=8443,
            action="allow"
        )

        # Should not be able to modify
        with pytest.raises(AttributeError):
            rule.port = 9000

        # Should be hashable
        assert hash(rule) is not None

    def test_port_validation(self):
        """Test port validation."""
        # Valid port
        rule = OptimizedFirewallRule(port=8443)
        assert rule.port == 8443

        # Port too low
        with pytest.raises(ValueError):
            OptimizedFirewallRule(port=80)

        # Port too high
        with pytest.raises(ValueError):
            OptimizedFirewallRule(port=70000)

    def test_source_validation(self):
        """Test source IP/CIDR validation."""
        # Valid IP
        rule1 = OptimizedFirewallRule(
            port=8443,
            source="192.168.1.1"
        )
        assert rule1.source == "192.168.1.1"

        # Valid CIDR
        rule2 = OptimizedFirewallRule(
            port=8443,
            source="10.0.0.0/8"
        )
        assert rule2.source == "10.0.0.0/8"

        # Invalid IP
        with pytest.raises(ValueError):
            OptimizedFirewallRule(
                port=8443,
                source="999.999.999.999"
            )


class TestOptimizedDockerConfig:
    """Test OptimizedDockerConfig model."""

    def test_docker_config_creation(self):
        """Test Docker config creation."""
        config = OptimizedDockerConfig(
            image="vpn/vless-reality",
            tag="v2.0",
            container_name="vpn-vless",
            environment={"KEY": "value"},
            ports={"8443/tcp": 8443}
        )

        assert config.image == "vpn/vless-reality"
        assert config.tag == "v2.0"
        assert config.container_name == "vpn-vless"
        assert config.environment["KEY"] == "value"

    def test_image_validation(self):
        """Test image name validation."""
        # Empty image name
        with pytest.raises(ValueError):
            OptimizedDockerConfig(image="")

        # Too long image name
        with pytest.raises(ValueError):
            OptimizedDockerConfig(image="a" * 256)

    def test_container_name_validation(self):
        """Test container name validation."""
        # Too long container name
        with pytest.raises(ValueError):
            OptimizedDockerConfig(
                image="test",
                container_name="a" * 65
            )

    def test_environment_validation(self):
        """Test environment variable validation."""
        # Valid environment variables
        config = OptimizedDockerConfig(
            image="test",
            environment={
                "VAR_NAME": "value",
                "ANOTHER_VAR": "value2"
            }
        )
        assert len(config.environment) == 2

        # Invalid environment variable name
        with pytest.raises(ValueError):
            OptimizedDockerConfig(
                image="test",
                environment={"VAR-NAME": "value"}  # Hyphen not allowed
            )


class TestOptimizedServerConfig:
    """Test OptimizedServerConfig model."""

    def test_server_creation(self):
        """Test server configuration creation."""
        server = OptimizedServerConfig(
            name="test-server",
            protocol_config=VLESSConfig(),
            port=8443,
            docker_config=OptimizedDockerConfig(image="vpn/vless")
        )

        assert server.name == "test-server"
        assert server.port == 8443
        assert server.is_running is False
        assert server.container_name == "vpn-vless-test-server"

    def test_auto_firewall_rule(self):
        """Test automatic firewall rule creation."""
        server = OptimizedServerConfig(
            name="test",
            protocol_config=VLESSConfig(),
            port=8443,
            docker_config=OptimizedDockerConfig(image="test"),
            firewall_rules=[
                OptimizedFirewallRule(port=9000)  # Different port
            ]
        )

        # Should auto-add server port rule
        assert len(server.firewall_rules) == 2
        server_rule = next(r for r in server.firewall_rules if r.port == 8443)
        assert server_rule.action == "allow"
        assert server_rule.comment == "Auto-generated server port rule"

    def test_computed_fields(self):
        """Test computed fields."""
        server = OptimizedServerConfig(
            name="test",
            protocol_config=ShadowsocksConfig(),
            port=8388,
            docker_config=OptimizedDockerConfig(
                image="shadowsocks",
                container_name="custom-name"
            ),
            status=ServerStatus.RUNNING
        )

        assert server.is_running is True
        assert server.container_name == "custom-name"


class TestUtilityFunctions:
    """Test utility functions."""

    def test_create_optimized_user(self):
        """Test create_optimized_user function."""
        user = create_optimized_user(
            username="test_user",
            protocol_type=ProtocolType.VLESS,
            email="test@example.com",
            expires_days=30
        )

        assert user.username == "test_user"
        assert user.email == "test@example.com"
        assert isinstance(user.protocol_config, VLESSConfig)
        assert user.expires_at is not None
        assert user.days_until_expiry >= 29

    def test_validate_user_batch(self):
        """Test batch user validation."""
        users_data = [
            {
                "username": "valid_user_1",
                "protocol_config": {"protocol_type": "vless"}
            },
            {
                "username": "valid_user_2",
                "protocol_config": {"protocol_type": "shadowsocks"}
            },
            {
                "username": "a",  # Invalid - too short
                "protocol_config": {"protocol_type": "vless"}
            },
            {
                "username": "invalid@user",  # Invalid characters
                "protocol_config": {"protocol_type": "vless"}
            }
        ]

        valid_users, invalid_users = validate_user_batch(users_data)

        assert len(valid_users) == 2
        assert len(invalid_users) == 2

        # Check valid users
        assert valid_users[0].username == "valid_user_1"
        assert valid_users[1].username == "valid_user_2"

        # Check invalid users have error info
        assert all('error' in invalid for invalid in invalid_users)
        assert all('data' in invalid for invalid in invalid_users)

    def test_batch_size_limit(self):
        """Test batch size validation."""
        # Create data exceeding max batch size
        large_batch = [
            {"username": f"user_{i}", "protocol_config": {"protocol_type": "vless"}}
            for i in range(101)
        ]

        with pytest.raises(ValueError, match="Batch size .* exceeds maximum"):
            validate_user_batch(large_batch, max_batch_size=100)


class TestPerformanceMetrics:
    """Test PerformanceMetrics model."""

    def test_metrics_creation(self):
        """Test performance metrics creation."""
        metrics = PerformanceMetrics(
            operation="user_creation",
            duration_ms=150.5,
            success=True
        )

        assert metrics.operation == "user_creation"
        assert metrics.duration_ms == 150.5
        assert metrics.duration_seconds == 0.1505
        assert metrics.is_slow is False

    def test_slow_operation_detection(self):
        """Test slow operation detection."""
        slow_metrics = PerformanceMetrics(
            operation="batch_processing",
            duration_ms=1500,
            success=True
        )

        assert slow_metrics.is_slow is True

        fast_metrics = PerformanceMetrics(
            operation="single_validation",
            duration_ms=50,
            success=True
        )

        assert fast_metrics.is_slow is False

    def test_frozen_metrics(self):
        """Test that metrics are frozen."""
        metrics = PerformanceMetrics(
            operation="test",
            duration_ms=100
        )

        # Should not be able to modify
        with pytest.raises(AttributeError):
            metrics.duration_ms = 200

        # Should be hashable
        assert hash(metrics) is not None
