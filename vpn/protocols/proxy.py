"""
HTTP/HTTPS and SOCKS5 proxy protocol implementation.
"""

from typing import Dict, List, Any, Optional
from pathlib import Path

from vpn.protocols.base import BaseProtocol, ProtocolConfig
from vpn.core.models import ProtocolType, ServerConfig, User, CryptoKeys
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ProxyProtocol(BaseProtocol):
    """HTTP/HTTPS and SOCKS5 proxy protocol implementation."""
    
    protocol_type = ProtocolType.UNIFIED_PROXY
    default_ports = {
        "http": 8080,
        "socks5": 1080,
    }
    
    def __init__(self, server_config: ServerConfig):
        """Initialize proxy protocol."""
        super().__init__(server_config)
        self.proxy_type = server_config.metadata.get("proxy_type", "http")
    
    def get_docker_image(self) -> str:
        """Get Docker image for proxy server."""
        if self.proxy_type == "socks5":
            return "vimagick/dante:latest"
        return "ubuntu/squid:latest"
    
    def get_docker_compose_config(self) -> Dict[str, Any]:
        """Generate docker-compose configuration."""
        return {
            "version": "3.8",
            "services": {
                "squid-proxy": {
                    "image": "ubuntu/squid:latest",
                    "container_name": f"vpn-squid-proxy-{self.server_config.port}",
                    "restart": "unless-stopped",
                    "ports": [
                        f"{self.server_config.port}:3128"
                    ],
                    "volumes": [
                        f"{self.server_config.config_path}/squid.conf:/etc/squid/squid.conf:ro",
                        "squid-cache:/var/spool/squid",
                        f"{self.server_config.data_path}/logs:/var/log/squid"
                    ],
                    "networks": ["proxy-network"],
                    "environment": {
                        "TZ": "UTC"
                    }
                },
                "socks5-proxy": {
                    "image": "vimagick/dante:latest",
                    "container_name": f"vpn-socks5-proxy-{self.server_config.port}",
                    "restart": "unless-stopped",
                    "ports": [
                        f"{self.default_ports['socks5']}:1080"
                    ],
                    "volumes": [
                        f"{self.server_config.config_path}/danted.conf:/etc/danted.conf:ro"
                    ],
                    "networks": ["proxy-network"],
                    "environment": {
                        "WORKERS": "10"
                    }
                }
            },
            "networks": {
                "proxy-network": {
                    "driver": "bridge",
                    "ipam": {
                        "config": [
                            {"subnet": "172.30.0.0/16"}
                        ]
                    }
                }
            },
            "volumes": {
                "squid-cache": {"driver": "local"}
            }
        }
    
    def get_container_config(self) -> Dict[str, Any]:
        """Get Docker container configuration."""
        config = {
            "name": f"vpn-proxy-{self.server_config.name}",
            "environment": {
                "TZ": "UTC",
            },
            "restart": "unless-stopped",
            "networks": ["bridge"],
        }
        
        if self.proxy_type == "http":
            config.update({
                "image": "ubuntu/squid:latest",
                "ports": {
                    "3128/tcp": self.server_config.port
                },
                "volumes": {
                    f"{self.server_config.config_path}/squid.conf": "/etc/squid/squid.conf:ro",
                    f"{self.server_config.data_path}/cache": "/var/spool/squid",
                    f"{self.server_config.data_path}/logs": "/var/log/squid"
                }
            })
        else:  # socks5
            config.update({
                "image": "vimagick/dante:latest",
                "ports": {
                    "1080/tcp": self.server_config.port
                },
                "volumes": {
                    f"{self.server_config.config_path}/danted.conf": "/etc/danted.conf:ro"
                }
            })
        
        return config
    
    def generate_server_config(self) -> str:
        """Generate proxy server configuration."""
        if self.proxy_type == "http":
            return self._generate_squid_config()
        return self._generate_dante_config()
    
    def _generate_squid_config(self) -> str:
        """Generate Squid proxy configuration."""
        return """# Squid Proxy Configuration
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16

acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localnet
http_access allow localhost
http_access deny all

http_port 3128

coredump_dir /var/spool/squid

refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\\?) 0     0%      0
refresh_pattern .               0       20%     4320

# Authentication (if needed)
# auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
# auth_param basic realm Squid proxy-caching web server
# acl authenticated proxy_auth REQUIRED
# http_access allow authenticated
"""
    
    def _generate_dante_config(self) -> str:
        """Generate Dante SOCKS5 configuration."""
        return """# Dante SOCKS5 Configuration
logoutput: stderr

internal: 0.0.0.0 port = 1080
external: eth0

socksmethod: none
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
}
"""
    
    def generate_user_config(self, user: User) -> str:
        """Generate user configuration."""
        if self.proxy_type == "http":
            # For Squid, we would generate password entries
            # Using private key as password for simplicity
            return f"{user.username}:{user.keys.private_key}"
        # For SOCKS5, authentication is handled differently
        return ""
    
    def get_connection_string(self, user: User) -> str:
        """Get connection string for users."""
        host = self.server_config.public_ip or "server-ip"
        
        if self.proxy_type == "http":
            return f"http://{user.username}:{user.keys.private_key}@{host}:{self.server_config.port}"
        return f"socks5://{user.username}:{user.keys.private_key}@{host}:{self.default_ports['socks5']}"
    
    def get_firewall_rules(self) -> List[Dict[str, Any]]:
        """Get firewall rules for proxy."""
        rules = [
            {
                "action": "allow",
                "direction": "in",
                "protocol": "tcp",
                "port": self.server_config.port,
                "comment": f"Proxy {self.proxy_type} port"
            }
        ]
        
        if self.proxy_type == "all":
            # Add SOCKS5 port
            rules.append({
                "action": "allow",
                "direction": "in", 
                "protocol": "tcp",
                "port": self.default_ports["socks5"],
                "comment": "SOCKS5 proxy port"
            })
        
        return rules
    
    def validate_config(self, config: Dict[str, Any]) -> bool:
        """Validate protocol configuration."""
        proxy_type = config.get("proxy_type", "http")
        if proxy_type not in ["http", "socks5", "all"]:
            return False
        
        port = config.get("port", self.default_ports.get("http"))
        if not isinstance(port, int) or port < 1 or port > 65535:
            return False
        
        return True
    
    async def health_check(self) -> bool:
        """Check if proxy server is healthy."""
        # This would be implemented to check proxy connectivity
        return True
    
    def get_stats_command(self) -> Optional[str]:
        """Get command to retrieve server statistics."""
        if self.proxy_type == "http":
            return "squidclient -h localhost mgr:info"
        return None