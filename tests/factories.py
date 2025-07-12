"""
Test data factories for VPN Manager using factory_boy pattern.

This module provides factories for creating test data objects with
realistic and consistent data for comprehensive testing.
"""

import json
import uuid
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

import factory
from factory import fuzzy
from faker import Faker

# Initialize Faker
fake = Faker()


class BaseFactory(factory.Factory):
    """Base factory with common configurations."""
    
    class Meta:
        abstract = True
    
    @classmethod
    def create_batch_dict(cls, size: int, **kwargs) -> List[Dict[str, Any]]:
        """Create a batch of factory instances as dictionaries."""
        return [cls.build_dict(**kwargs) for _ in range(size)]
    
    @classmethod
    def build_dict(cls, **kwargs) -> Dict[str, Any]:
        """Build factory instance as dictionary."""
        instance = cls.build(**kwargs)
        if hasattr(instance, '__dict__'):
            return instance.__dict__
        return dict(instance._asdict()) if hasattr(instance, '_asdict') else {}


class UserDataFactory(BaseFactory):
    """Factory for creating user data dictionaries."""
    
    class Meta:
        model = dict
    
    id = factory.LazyFunction(lambda: str(uuid.uuid4()))
    username = factory.Sequence(lambda n: f"testuser{n}")
    email = factory.LazyAttribute(lambda obj: f"{obj.username}@{fake.domain_name()}")
    status = fuzzy.FuzzyChoice(['active', 'inactive', 'expired', 'suspended'])
    protocol_type = fuzzy.FuzzyChoice(['vless', 'shadowsocks', 'wireguard', 'http', 'socks5'])
    port = fuzzy.FuzzyInteger(1000, 65535)
    server_ip = factory.LazyFunction(fake.ipv4)
    created_at = factory.LazyFunction(datetime.utcnow)
    updated_at = factory.LazyFunction(datetime.utcnow)
    expires_at = factory.LazyFunction(lambda: datetime.utcnow() + timedelta(days=30))
    
    @factory.lazy_attribute
    def protocol_settings(self):
        """Generate protocol-specific settings."""
        settings_map = {
            'vless': {
                'clients': [{'id': str(uuid.uuid4())}],
                'decryption': 'none',
                'fallbacks': []
            },
            'shadowsocks': {
                'method': 'chacha20-ietf-poly1305',
                'password': fake.password(length=16)
            },
            'wireguard': {
                'private_key': fake.sha256(),
                'public_key': fake.sha256(),
                'address': f"10.0.0.{fake.random_int(2, 254)}/24"
            },
            'http': {
                'username': fake.user_name(),
                'password': fake.password()
            },
            'socks5': {
                'username': fake.user_name(),
                'password': fake.password()
            }
        }
        return settings_map.get(self.protocol_type, {})


class AdminUserDataFactory(UserDataFactory):
    """Factory for admin users."""
    
    username = factory.Sequence(lambda n: f"admin{n}")
    email = factory.LazyAttribute(lambda obj: f"{obj.username}@admin.local")
    status = 'active'
    
    @factory.lazy_attribute
    def privileges(self):
        return ['user_management', 'server_management', 'system_admin']


class ExpiredUserDataFactory(UserDataFactory):
    """Factory for expired users."""
    
    status = 'expired'
    expires_at = factory.LazyFunction(lambda: datetime.utcnow() - timedelta(days=1))


class ContainerDataFactory(BaseFactory):
    """Factory for Docker container data."""
    
    class Meta:
        model = dict
    
    id = factory.LazyFunction(lambda: fake.sha256()[:12])
    name = factory.Sequence(lambda n: f"vpn_container_{n}")
    status = fuzzy.FuzzyChoice(['running', 'stopped', 'paused', 'restarting'])
    image = 'vpn-server:latest'
    created = factory.LazyFunction(datetime.utcnow)
    
    @factory.lazy_attribute
    def network_settings(self):
        return {
            'IPAddress': fake.ipv4_private(),
            'Gateway': '172.17.0.1',
            'NetworkMode': 'bridge'
        }
    
    @factory.lazy_attribute
    def ports(self):
        port = fake.random_int(8000, 9000)
        return {
            f"{port}/tcp": [{"HostIp": "0.0.0.0", "HostPort": str(port)}]
        }
    
    @factory.lazy_attribute
    def environment(self):
        return {
            'VPN_TYPE': fake.random_element(['vless', 'shadowsocks', 'wireguard']),
            'VPN_PORT': str(fake.random_int(8000, 9000)),
            'VPN_USER_ID': str(uuid.uuid4())
        }


class RunningContainerFactory(ContainerDataFactory):
    """Factory for running containers."""
    status = 'running'


class StoppedContainerFactory(ContainerDataFactory):
    """Factory for stopped containers."""
    status = 'stopped'


class ProtocolConfigFactory(BaseFactory):
    """Factory for protocol configurations."""
    
    class Meta:
        model = dict
    
    type = fuzzy.FuzzyChoice(['vless', 'shadowsocks', 'wireguard', 'http', 'socks5'])
    port = fuzzy.FuzzyInteger(8000, 9000)
    
    @factory.lazy_attribute
    def settings(self):
        """Generate protocol-specific settings."""
        if self.type == 'vless':
            return {
                'clients': [
                    {
                        'id': str(uuid.uuid4()),
                        'email': fake.email(),
                        'level': 0,
                        'alterId': 0
                    }
                ],
                'decryption': 'none',
                'fallbacks': []
            }
        elif self.type == 'shadowsocks':
            return {
                'method': 'chacha20-ietf-poly1305',
                'password': fake.password(length=16),
                'network': 'tcp,udp'
            }
        elif self.type == 'wireguard':
            return {
                'private_key': fake.sha256()[:44],
                'public_key': fake.sha256()[:44],
                'address': f"10.0.0.{fake.random_int(2, 254)}/24",
                'dns': ['1.1.1.1', '8.8.8.8']
            }
        elif self.type == 'http':
            return {
                'username': fake.user_name(),
                'password': fake.password(),
                'realm': 'VPN Access'
            }
        elif self.type == 'socks5':
            return {
                'username': fake.user_name(),
                'password': fake.password(),
                'udp': True
            }
        return {}


class VlessProtocolFactory(ProtocolConfigFactory):
    """Factory specifically for VLESS protocol."""
    type = 'vless'


class ShadowsocksProtocolFactory(ProtocolConfigFactory):
    """Factory specifically for Shadowsocks protocol."""
    type = 'shadowsocks'


class WireguardProtocolFactory(ProtocolConfigFactory):
    """Factory specifically for WireGuard protocol."""
    type = 'wireguard'


class ConnectionInfoFactory(BaseFactory):
    """Factory for connection information."""
    
    class Meta:
        model = dict
    
    server_ip = factory.LazyFunction(fake.ipv4)
    server_port = fuzzy.FuzzyInteger(8000, 9000)
    client_id = factory.LazyFunction(lambda: str(uuid.uuid4()))
    public_key = factory.LazyFunction(lambda: fake.sha256()[:44])
    private_key = factory.LazyFunction(lambda: fake.sha256()[:44])
    
    @factory.lazy_attribute
    def connection_string(self):
        """Generate connection string based on protocol."""
        return f"vpn://{self.server_ip}:{self.server_port}?id={self.client_id}"


class TrafficStatsFactory(BaseFactory):
    """Factory for traffic statistics."""
    
    class Meta:
        model = dict
    
    upload_mb = fuzzy.FuzzyFloat(0, 1000, precision=2)
    download_mb = fuzzy.FuzzyFloat(0, 5000, precision=2)
    total_mb = factory.LazyAttribute(lambda obj: obj.upload_mb + obj.download_mb)
    last_activity = factory.LazyFunction(lambda: datetime.utcnow() - timedelta(hours=fake.random_int(1, 24)))
    
    @factory.lazy_attribute
    def daily_stats(self):
        """Generate daily traffic statistics."""
        stats = {}
        for i in range(7):  # Last 7 days
            date = (datetime.utcnow() - timedelta(days=i)).strftime('%Y-%m-%d')
            stats[date] = {
                'upload': round(fake.random.uniform(0, 100), 2),
                'download': round(fake.random.uniform(0, 500), 2)
            }
        return stats


class CryptoKeysFactory(BaseFactory):
    """Factory for cryptographic keys."""
    
    class Meta:
        model = dict
    
    public_key = factory.LazyFunction(lambda: fake.sha256()[:44])
    private_key = factory.LazyFunction(lambda: fake.sha256()[:44])
    shared_secret = factory.LazyFunction(lambda: fake.sha256()[:32])
    
    @factory.lazy_attribute
    def key_pair(self):
        """Generate additional key pair information."""
        return {
            'algorithm': 'X25519',
            'created_at': datetime.utcnow().isoformat(),
            'fingerprint': fake.sha256()[:16]
        }


class ServerConfigFactory(BaseFactory):
    """Factory for server configurations."""
    
    class Meta:
        model = dict
    
    name = factory.Sequence(lambda n: f"vpn-server-{n}")
    host = factory.LazyFunction(fake.ipv4)
    domain = factory.LazyFunction(fake.domain_name)
    port = fuzzy.FuzzyInteger(8000, 9000)
    protocol = fuzzy.FuzzyChoice(['vless', 'shadowsocks', 'wireguard'])
    max_users = fuzzy.FuzzyInteger(10, 1000)
    region = factory.LazyFunction(fake.country_code)
    
    @factory.lazy_attribute
    def ssl_config(self):
        return {
            'enabled': True,
            'cert_path': f"/etc/ssl/certs/{self.domain}.crt",
            'key_path': f"/etc/ssl/private/{self.domain}.key",
            'auto_renew': True
        }


class NetworkConfigFactory(BaseFactory):
    """Factory for network configurations."""
    
    class Meta:
        model = dict
    
    interface = factory.LazyFunction(lambda: fake.random_element(['eth0', 'wg0', 'tun0']))
    subnet = factory.LazyFunction(lambda: f"10.{fake.random_int(0, 255)}.0.0/16")
    dns_servers = factory.LazyFunction(lambda: ['1.1.1.1', '8.8.8.8'])
    mtu = fuzzy.FuzzyInteger(1280, 1500)
    
    @factory.lazy_attribute
    def firewall_rules(self):
        return [
            f"ALLOW {self.interface} IN",
            f"ALLOW {self.interface} OUT",
            f"DROP ALL IN"
        ]


class TestScenarioFactory(BaseFactory):
    """Factory for creating test scenarios."""
    
    class Meta:
        model = dict
    
    name = factory.Sequence(lambda n: f"test_scenario_{n}")
    description = factory.LazyFunction(fake.text)
    users_count = fuzzy.FuzzyInteger(1, 10)
    containers_count = fuzzy.FuzzyInteger(1, 5)
    duration_minutes = fuzzy.FuzzyInteger(1, 60)
    
    @factory.lazy_attribute
    def expected_results(self):
        return {
            'success_rate': 0.95,
            'max_response_time': 2.0,
            'max_memory_usage': 100 * 1024 * 1024  # 100MB
        }


class LoadTestDataFactory(BaseFactory):
    """Factory for load testing data."""
    
    class Meta:
        model = dict
    
    concurrent_users = fuzzy.FuzzyInteger(10, 100)
    requests_per_second = fuzzy.FuzzyInteger(10, 1000)
    test_duration = fuzzy.FuzzyInteger(60, 3600)  # 1 minute to 1 hour
    
    @factory.lazy_attribute
    def user_data_batch(self):
        """Generate batch of users for load testing."""
        return UserDataFactory.create_batch_dict(self.concurrent_users)
    
    @factory.lazy_attribute
    def container_data_batch(self):
        """Generate batch of containers for load testing."""
        return ContainerDataFactory.create_batch_dict(self.concurrent_users // 2)


class PerformanceBenchmarkFactory(BaseFactory):
    """Factory for performance benchmark data."""
    
    class Meta:
        model = dict
    
    operation_name = factory.LazyFunction(lambda: fake.random_element([
        'user_creation', 'container_start', 'config_generation', 'stats_collection'
    ]))
    target_duration_ms = fuzzy.FuzzyInteger(100, 5000)
    target_memory_mb = fuzzy.FuzzyInteger(10, 100)
    sample_size = fuzzy.FuzzyInteger(10, 100)
    
    @factory.lazy_attribute
    def baseline_metrics(self):
        return {
            'avg_duration_ms': self.target_duration_ms * 0.8,
            'p95_duration_ms': self.target_duration_ms * 1.2,
            'max_memory_mb': self.target_memory_mb * 0.9
        }


class ErrorScenarioFactory(BaseFactory):
    """Factory for error testing scenarios."""
    
    class Meta:
        model = dict
    
    error_type = factory.LazyFunction(lambda: fake.random_element([
        'network_error', 'database_error', 'docker_error', 'validation_error'
    ]))
    error_message = factory.LazyFunction(fake.sentence)
    should_retry = factory.LazyFunction(fake.boolean)
    retry_count = fuzzy.FuzzyInteger(0, 3)
    
    @factory.lazy_attribute
    def error_context(self):
        return {
            'component': fake.random_element(['user_manager', 'docker_manager', 'network_manager']),
            'operation': fake.random_element(['create', 'update', 'delete', 'list']),
            'timestamp': datetime.utcnow().isoformat()
        }


# Convenience functions for common factory combinations
def create_complete_user_scenario(count: int = 1) -> List[Dict[str, Any]]:
    """Create complete user scenarios with all related data."""
    scenarios = []
    
    for _ in range(count):
        user_data = UserDataFactory.build_dict()
        protocol_config = ProtocolConfigFactory.build_dict(type=user_data['protocol_type'])
        connection_info = ConnectionInfoFactory.build_dict()
        traffic_stats = TrafficStatsFactory.build_dict()
        crypto_keys = CryptoKeysFactory.build_dict()
        
        scenario = {
            'user': user_data,
            'protocol': protocol_config,
            'connection': connection_info,
            'traffic': traffic_stats,
            'keys': crypto_keys
        }
        scenarios.append(scenario)
    
    return scenarios


def create_docker_test_environment(containers_count: int = 3) -> Dict[str, Any]:
    """Create a complete Docker test environment."""
    return {
        'containers': ContainerDataFactory.create_batch_dict(containers_count),
        'network_config': NetworkConfigFactory.build_dict(),
        'server_config': ServerConfigFactory.build_dict()
    }


def create_performance_test_suite() -> Dict[str, Any]:
    """Create a complete performance test suite."""
    return {
        'load_test': LoadTestDataFactory.build_dict(),
        'benchmarks': [PerformanceBenchmarkFactory.build_dict() for _ in range(5)],
        'scenarios': [TestScenarioFactory.build_dict() for _ in range(3)]
    }


# Export all factories
__all__ = [
    'UserDataFactory',
    'AdminUserDataFactory', 
    'ExpiredUserDataFactory',
    'ContainerDataFactory',
    'RunningContainerFactory',
    'StoppedContainerFactory',
    'ProtocolConfigFactory',
    'VlessProtocolFactory',
    'ShadowsocksProtocolFactory',
    'WireguardProtocolFactory',
    'ConnectionInfoFactory',
    'TrafficStatsFactory',
    'CryptoKeysFactory',
    'ServerConfigFactory',
    'NetworkConfigFactory',
    'TestScenarioFactory',
    'LoadTestDataFactory',
    'PerformanceBenchmarkFactory',
    'ErrorScenarioFactory',
    'create_complete_user_scenario',
    'create_docker_test_environment',
    'create_performance_test_suite'
]