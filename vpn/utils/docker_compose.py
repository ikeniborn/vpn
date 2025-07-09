"""
Docker Compose integration for VPN Manager.
"""

import asyncio
import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import yaml
from rich.console import Console
from rich.progress import track

from vpn.core.config import settings
from vpn.core.models import ProtocolType
from vpn.utils.logger import get_logger

logger = get_logger(__name__)
console = Console()


class DockerComposeManager:
    """Manages Docker Compose deployments for VPN services."""
    
    def __init__(self, project_name: str = "vpn-manager"):
        self.project_name = project_name
        self.compose_dir = settings.install_path / "compose"
        self.templates_dir = Path(__file__).parent / "templates" / "compose"
        self.compose_file = self.compose_dir / "docker-compose.yml"
        self.env_file = self.compose_dir / ".env"
    
    async def initialize_compose_project(self) -> bool:
        """Initialize a new Docker Compose project."""
        try:
            # Create compose directory
            self.compose_dir.mkdir(parents=True, exist_ok=True)
            
            # Generate base compose configuration
            await self.generate_base_compose()
            
            # Generate environment file
            await self.generate_env_file()
            
            console.print(f"[green]✓ Docker Compose project initialized at: {self.compose_dir}[/green]")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize compose project: {e}")
            return False
    
    async def generate_base_compose(self):
        """Generate base docker-compose.yml file."""
        compose_config = {
            'version': '3.8',
            'networks': {
                'vpn-network': {
                    'driver': 'bridge',
                    'ipam': {
                        'config': [{'subnet': '172.20.0.0/16'}]
                    }
                }
            },
            'volumes': {
                'vpn-data': {},
                'vpn-logs': {},
                'vpn-config': {},
            },
            'services': {
                'traefik': {
                    'image': 'traefik:v3.0',
                    'container_name': f'{self.project_name}-traefik',
                    'ports': ['80:80', '443:443', '8080:8080'],
                    'volumes': [
                        '/var/run/docker.sock:/var/run/docker.sock:ro',
                        'vpn-config:/etc/traefik',
                        'vpn-logs:/var/log/traefik'
                    ],
                    'command': [
                        '--api.dashboard=true',
                        '--providers.docker=true',
                        '--providers.docker.exposedbydefault=false',
                        '--entrypoints.web.address=:80',
                        '--entrypoints.websecure.address=:443',
                        '--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}',
                        '--certificatesresolvers.letsencrypt.acme.storage=/etc/traefik/acme.json',
                        '--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web',
                        '--log.level=INFO',
                        '--accesslog=true'
                    ],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped',
                    'labels': [
                        'traefik.enable=true',
                        'traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)',
                        'traefik.http.routers.traefik.entrypoints=websecure',
                        'traefik.http.routers.traefik.tls.certresolver=letsencrypt',
                        'traefik.http.services.traefik.loadbalancer.server.port=8080'
                    ]
                },
                'postgres': {
                    'image': 'postgres:15-alpine',
                    'container_name': f'{self.project_name}-postgres',
                    'environment': [
                        'POSTGRES_DB=${POSTGRES_DB}',
                        'POSTGRES_USER=${POSTGRES_USER}',
                        'POSTGRES_PASSWORD=${POSTGRES_PASSWORD}'
                    ],
                    'volumes': [
                        'vpn-data:/var/lib/postgresql/data',
                        './init-scripts:/docker-entrypoint-initdb.d'
                    ],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped',
                    'healthcheck': {
                        'test': ['CMD-SHELL', 'pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}'],
                        'interval': '10s',
                        'timeout': '5s',
                        'retries': 5
                    }
                },
                'redis': {
                    'image': 'redis:7-alpine',
                    'container_name': f'{self.project_name}-redis',
                    'command': ['redis-server', '--appendonly', 'yes', '--requirepass', '${REDIS_PASSWORD}'],
                    'volumes': ['vpn-data:/data'],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped',
                    'healthcheck': {
                        'test': ['CMD', 'redis-cli', '--raw', 'incr', 'ping'],
                        'interval': '10s',
                        'timeout': '3s',
                        'retries': 5
                    }
                },
                'vpn-manager': {
                    'image': 'vpn-manager:latest',
                    'container_name': f'{self.project_name}-manager',
                    'depends_on': ['postgres', 'redis'],
                    'environment': [
                        'DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}',
                        'REDIS_URL=redis://:{REDIS_PASSWORD}@redis:6379/0',
                        'VPN_DOMAIN=${DOMAIN}',
                        'VPN_DEBUG=${DEBUG:-false}'
                    ],
                    'volumes': [
                        'vpn-config:/app/config',
                        'vpn-logs:/app/logs',
                        '/var/run/docker.sock:/var/run/docker.sock:ro'
                    ],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped',
                    'labels': [
                        'traefik.enable=true',
                        'traefik.http.routers.vpn-manager.rule=Host(`vpn.${DOMAIN}`)',
                        'traefik.http.routers.vpn-manager.entrypoints=websecure',
                        'traefik.http.routers.vpn-manager.tls.certresolver=letsencrypt',
                        'traefik.http.services.vpn-manager.loadbalancer.server.port=8000'
                    ]
                }
            }
        }
        
        # Write compose file
        with open(self.compose_file, 'w') as f:
            yaml.dump(compose_config, f, default_flow_style=False, sort_keys=False)
    
    async def generate_env_file(self):
        """Generate .env file with default values."""
        env_content = """# VPN Manager Docker Compose Configuration

# Domain Configuration
DOMAIN=your-domain.com
ACME_EMAIL=admin@your-domain.com

# Database Configuration
POSTGRES_DB=vpn_manager
POSTGRES_USER=vpn_user
POSTGRES_PASSWORD=your_secure_postgres_password

# Redis Configuration
REDIS_PASSWORD=your_secure_redis_password

# VPN Manager Configuration
DEBUG=false
LOG_LEVEL=INFO

# Service Scaling
VLESS_REPLICAS=1
SHADOWSOCKS_REPLICAS=1
WIREGUARD_REPLICAS=1
PROXY_REPLICAS=1

# Resource Limits
MANAGER_CPU_LIMIT=1.0
MANAGER_MEMORY_LIMIT=512M
VPN_CPU_LIMIT=0.5
VPN_MEMORY_LIMIT=256M

# Monitoring
ENABLE_MONITORING=true
GRAFANA_PASSWORD=admin
PROMETHEUS_RETENTION=7d
"""
        
        with open(self.env_file, 'w') as f:
            f.write(env_content)
    
    async def add_vpn_service(self, protocol: ProtocolType, config: Dict) -> bool:
        """Add a VPN service to the compose configuration."""
        try:
            # Load existing compose file
            with open(self.compose_file, 'r') as f:
                compose_config = yaml.safe_load(f)
            
            service_name = f"vpn-{protocol.value}"
            
            # Generate service configuration based on protocol
            if protocol == ProtocolType.VLESS:
                service_config = await self._generate_vless_service(config)
            elif protocol == ProtocolType.SHADOWSOCKS:
                service_config = await self._generate_shadowsocks_service(config)
            elif protocol == ProtocolType.WIREGUARD:
                service_config = await self._generate_wireguard_service(config)
            else:
                raise ValueError(f"Unsupported protocol: {protocol}")
            
            # Add service to compose config
            compose_config['services'][service_name] = service_config
            
            # Write updated compose file
            with open(self.compose_file, 'w') as f:
                yaml.dump(compose_config, f, default_flow_style=False, sort_keys=False)
            
            console.print(f"[green]✓ Added {protocol.value} service to compose configuration[/green]")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add VPN service: {e}")
            return False
    
    async def _generate_vless_service(self, config: Dict) -> Dict:
        """Generate VLESS service configuration."""
        return {
            'image': 'ghcr.io/xtls/xray-core:latest',
            'container_name': f'{self.project_name}-vless',
            'ports': [f"{config.get('port', 8443)}:{config.get('port', 8443)}"],
            'volumes': [
                'vpn-config:/etc/xray',
                'vpn-logs:/var/log/xray'
            ],
            'environment': [
                f"VLESS_PORT={config.get('port', 8443)}",
                f"VLESS_DOMAIN={config.get('domain', '${DOMAIN}')}",
                f"VLESS_UUID={config.get('uuid', '${VLESS_UUID}')}"
            ],
            'networks': ['vpn-network'],
            'restart': 'unless-stopped',
            'healthcheck': {
                'test': ['CMD-SHELL', f'curl -f http://localhost:{config.get("port", 8443)}/health || exit 1'],
                'interval': '30s',
                'timeout': '10s',
                'retries': 3
            },
            'deploy': {
                'replicas': '${VLESS_REPLICAS:-1}',
                'resources': {
                    'limits': {
                        'cpus': '${VPN_CPU_LIMIT:-0.5}',
                        'memory': '${VPN_MEMORY_LIMIT:-256M}'
                    }
                }
            },
            'labels': [
                'traefik.enable=true',
                f'traefik.tcp.routers.vless.rule=HostSNI(`{config.get("domain", "${DOMAIN}")}`)',
                f'traefik.tcp.routers.vless.entrypoints=vless',
                f'traefik.tcp.services.vless.loadbalancer.server.port={config.get("port", 8443)}'
            ]
        }
    
    async def _generate_shadowsocks_service(self, config: Dict) -> Dict:
        """Generate Shadowsocks service configuration."""
        return {
            'image': 'shadowsocks/shadowsocks-libev:latest',
            'container_name': f'{self.project_name}-shadowsocks',
            'ports': [f"{config.get('port', 8388)}:{config.get('port', 8388)}"],
            'environment': [
                f"PASSWORD={config.get('password', '${SS_PASSWORD}')}",
                f"METHOD={config.get('method', 'chacha20-ietf-poly1305')}",
                f"TIMEOUT=300"
            ],
            'command': [
                'ss-server',
                '-s', '0.0.0.0',
                '-p', str(config.get('port', 8388)),
                '-k', '${SS_PASSWORD}',
                '-m', config.get('method', 'chacha20-ietf-poly1305'),
                '-t', '300',
                '--fast-open',
                '-v'
            ],
            'networks': ['vpn-network'],
            'restart': 'unless-stopped',
            'deploy': {
                'replicas': '${SHADOWSOCKS_REPLICAS:-1}',
                'resources': {
                    'limits': {
                        'cpus': '${VPN_CPU_LIMIT:-0.5}',
                        'memory': '${VPN_MEMORY_LIMIT:-256M}'
                    }
                }
            }
        }
    
    async def _generate_wireguard_service(self, config: Dict) -> Dict:
        """Generate WireGuard service configuration."""
        return {
            'image': 'linuxserver/wireguard:latest',
            'container_name': f'{self.project_name}-wireguard',
            'cap_add': ['NET_ADMIN', 'SYS_MODULE'],
            'environment': [
                'PUID=1000',
                'PGID=1000',
                'TZ=UTC',
                f"SERVERURL={config.get('domain', '${DOMAIN}')}",
                f"SERVERPORT={config.get('port', 51820)}",
                f"PEERS={config.get('peers', 10)}",
                'PEERDNS=auto',
                'INTERNAL_SUBNET=10.13.13.0'
            ],
            'volumes': [
                'vpn-config:/config',
                '/lib/modules:/lib/modules:ro'
            ],
            'ports': [f"{config.get('port', 51820)}:{config.get('port', 51820)}/udp"],
            'sysctls': ['net.ipv4.conf.all.src_valid_mark=1'],
            'networks': ['vpn-network'],
            'restart': 'unless-stopped',
            'deploy': {
                'replicas': '${WIREGUARD_REPLICAS:-1}',
                'resources': {
                    'limits': {
                        'cpus': '${VPN_CPU_LIMIT:-0.5}',
                        'memory': '${VPN_MEMORY_LIMIT:-256M}'
                    }
                }
            }
        }
    
    async def add_monitoring_stack(self) -> bool:
        """Add monitoring services (Prometheus, Grafana, Jaeger)."""
        try:
            # Load existing compose file
            with open(self.compose_file, 'r') as f:
                compose_config = yaml.safe_load(f)
            
            monitoring_services = {
                'prometheus': {
                    'image': 'prom/prometheus:latest',
                    'container_name': f'{self.project_name}-prometheus',
                    'ports': ['9090:9090'],
                    'volumes': [
                        'vpn-config:/etc/prometheus',
                        'vpn-data:/prometheus'
                    ],
                    'command': [
                        '--config.file=/etc/prometheus/prometheus.yml',
                        '--storage.tsdb.path=/prometheus',
                        '--web.console.libraries=/etc/prometheus/console_libraries',
                        '--web.console.templates=/etc/prometheus/consoles',
                        '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-7d}',
                        '--web.enable-lifecycle'
                    ],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped'
                },
                'grafana': {
                    'image': 'grafana/grafana:latest',
                    'container_name': f'{self.project_name}-grafana',
                    'ports': ['3000:3000'],
                    'environment': [
                        'GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}',
                        'GF_USERS_ALLOW_SIGN_UP=false'
                    ],
                    'volumes': [
                        'vpn-data:/var/lib/grafana',
                        'vpn-config:/etc/grafana'
                    ],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped',
                    'labels': [
                        'traefik.enable=true',
                        'traefik.http.routers.grafana.rule=Host(`grafana.${DOMAIN}`)',
                        'traefik.http.routers.grafana.entrypoints=websecure',
                        'traefik.http.routers.grafana.tls.certresolver=letsencrypt',
                        'traefik.http.services.grafana.loadbalancer.server.port=3000'
                    ]
                },
                'jaeger': {
                    'image': 'jaegertracing/all-in-one:latest',
                    'container_name': f'{self.project_name}-jaeger',
                    'ports': ['16686:16686', '14268:14268'],
                    'environment': [
                        'COLLECTOR_OTLP_ENABLED=true'
                    ],
                    'networks': ['vpn-network'],
                    'restart': 'unless-stopped',
                    'labels': [
                        'traefik.enable=true',
                        'traefik.http.routers.jaeger.rule=Host(`jaeger.${DOMAIN}`)',
                        'traefik.http.routers.jaeger.entrypoints=websecure',
                        'traefik.http.routers.jaeger.tls.certresolver=letsencrypt',
                        'traefik.http.services.jaeger.loadbalancer.server.port=16686'
                    ]
                }
            }
            
            # Add monitoring services
            compose_config['services'].update(monitoring_services)
            
            # Write updated compose file
            with open(self.compose_file, 'w') as f:
                yaml.dump(compose_config, f, default_flow_style=False, sort_keys=False)
            
            console.print("[green]✓ Added monitoring stack to compose configuration[/green]")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add monitoring stack: {e}")
            return False
    
    async def deploy_stack(self, services: Optional[List[str]] = None) -> bool:
        """Deploy the Docker Compose stack."""
        try:
            cmd = ['docker-compose', '-f', str(self.compose_file), '-p', self.project_name]
            
            if services:
                cmd.extend(['up', '-d'] + services)
            else:
                cmd.extend(['up', '-d'])
            
            console.print(f"[blue]Deploying stack: {' '.join(cmd)}[/blue]")
            
            result = subprocess.run(
                cmd,
                cwd=self.compose_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                console.print("[green]✓ Stack deployed successfully[/green]")
                return True
            else:
                console.print(f"[red]Stack deployment failed: {result.stderr}[/red]")
                return False
                
        except Exception as e:
            logger.error(f"Failed to deploy stack: {e}")
            return False
    
    async def scale_service(self, service: str, replicas: int) -> bool:
        """Scale a specific service."""
        try:
            cmd = [
                'docker-compose', '-f', str(self.compose_file), '-p', self.project_name,
                'up', '-d', '--scale', f'{service}={replicas}', service
            ]
            
            result = subprocess.run(
                cmd,
                cwd=self.compose_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                console.print(f"[green]✓ Scaled {service} to {replicas} replicas[/green]")
                return True
            else:
                console.print(f"[red]Failed to scale {service}: {result.stderr}[/red]")
                return False
                
        except Exception as e:
            logger.error(f"Failed to scale service: {e}")
            return False
    
    async def get_service_logs(self, service: str, lines: int = 100) -> List[str]:
        """Get logs from a specific service."""
        try:
            cmd = [
                'docker-compose', '-f', str(self.compose_file), '-p', self.project_name,
                'logs', '--tail', str(lines), service
            ]
            
            result = subprocess.run(
                cmd,
                cwd=self.compose_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                return result.stdout.split('\n')
            else:
                logger.error(f"Failed to get logs for {service}: {result.stderr}")
                return []
                
        except Exception as e:
            logger.error(f"Failed to get service logs: {e}")
            return []
    
    async def get_stack_status(self) -> Dict:
        """Get status of all services in the stack."""
        try:
            cmd = [
                'docker-compose', '-f', str(self.compose_file), '-p', self.project_name,
                'ps', '--format', 'json'
            ]
            
            result = subprocess.run(
                cmd,
                cwd=self.compose_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                import json
                services = json.loads(result.stdout) if result.stdout.strip() else []
                return {
                    'services': services,
                    'total': len(services),
                    'running': len([s for s in services if s.get('State') == 'running'])
                }
            else:
                logger.error(f"Failed to get stack status: {result.stderr}")
                return {'services': [], 'total': 0, 'running': 0}
                
        except Exception as e:
            logger.error(f"Failed to get stack status: {e}")
            return {'services': [], 'total': 0, 'running': 0}
    
    async def remove_stack(self, volumes: bool = False) -> bool:
        """Remove the entire Docker Compose stack."""
        try:
            cmd = ['docker-compose', '-f', str(self.compose_file), '-p', self.project_name, 'down']
            
            if volumes:
                cmd.append('--volumes')
            
            result = subprocess.run(
                cmd,
                cwd=self.compose_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                console.print("[green]✓ Stack removed successfully[/green]")
                return True
            else:
                console.print(f"[red]Failed to remove stack: {result.stderr}[/red]")
                return False
                
        except Exception as e:
            logger.error(f"Failed to remove stack: {e}")
            return False