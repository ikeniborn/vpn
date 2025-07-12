"""
YAML-based template system for VPN configurations.

This module provides a comprehensive template system for generating VPN configurations
using YAML templates with Jinja2 templating engine.
"""

import os
import uuid
import secrets
import base64
import hashlib
from pathlib import Path
from typing import Dict, Any, List, Optional, Union, Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
import re

from jinja2 import (
    Environment, FileSystemLoader, DictLoader, Template,
    select_autoescape, StrictUndefined, TemplateNotFound,
    TemplateSyntaxError, TemplateRuntimeError
)
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa, x25519
from rich.console import Console

console = Console()


class TemplateType(str, Enum):
    """Types of VPN configuration templates."""
    VLESS = "vless"
    SHADOWSOCKS = "shadowsocks"
    WIREGUARD = "wireguard"
    HTTP_PROXY = "http_proxy"
    SOCKS5_PROXY = "socks5_proxy"
    UNIFIED_PROXY = "unified_proxy"
    DOCKER_COMPOSE = "docker_compose"
    NGINX_CONFIG = "nginx_config"
    USER_PRESET = "user_preset"
    BATCH_CONFIG = "batch_config"


@dataclass
class TemplateContext:
    """Context for template rendering."""
    template_type: TemplateType
    variables: Dict[str, Any] = field(default_factory=dict)
    functions: Dict[str, Callable] = field(default_factory=dict)
    filters: Dict[str, Callable] = field(default_factory=dict)
    globals: Dict[str, Any] = field(default_factory=dict)
    
    def update(self, **kwargs) -> None:
        """Update context variables."""
        self.variables.update(kwargs)
    
    def add_function(self, name: str, func: Callable) -> None:
        """Add custom function to context."""
        self.functions[name] = func
    
    def add_filter(self, name: str, func: Callable) -> None:
        """Add custom filter to context."""
        self.filters[name] = func


@dataclass
class TemplateResult:
    """Result of template rendering."""
    content: str
    template_type: TemplateType
    variables_used: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    render_time: Optional[float] = None
    
    @property
    def is_valid(self) -> bool:
        """Check if rendering was successful."""
        return len(self.errors) == 0
    
    @property
    def has_warnings(self) -> bool:
        """Check if there are warnings."""
        return len(self.warnings) > 0


class VPNTemplateEngine:
    """Enhanced template engine for VPN configurations."""
    
    def __init__(self, template_dirs: Optional[List[Path]] = None):
        """Initialize template engine."""
        self.template_dirs = template_dirs or [
            Path(__file__).parent.parent / "templates",
            Path.home() / ".config" / "vpn-manager" / "templates"
        ]
        
        # Ensure template directories exist
        for template_dir in self.template_dirs:
            template_dir.mkdir(parents=True, exist_ok=True)
        
        # Setup Jinja2 environment
        self.env = Environment(
            loader=FileSystemLoader([str(d) for d in self.template_dirs]),
            autoescape=select_autoescape(['yaml', 'yml', 'json']),
            undefined=StrictUndefined,
            trim_blocks=True,
            lstrip_blocks=True,
            keep_trailing_newline=True
        )
        
        # Add custom functions, filters, and globals
        self._setup_template_functions()
        self._setup_template_filters()
        self._setup_template_globals()
    
    def _setup_template_functions(self) -> None:
        """Setup custom template functions."""
        self.env.globals.update({
            'uuid4': lambda: str(uuid.uuid4()),
            'uuid4_short': lambda: str(uuid.uuid4())[:8],
            'random_password': self._generate_random_password,
            'random_hex': self._generate_random_hex,
            'random_base64': self._generate_random_base64,
            'generate_wg_key': self._generate_wireguard_key,
            'generate_wg_public': self._generate_wireguard_public,
            'generate_x25519_key': self._generate_x25519_key,
            'generate_rsa_key': self._generate_rsa_key,
            'hash_password': self._hash_password,
            'encode_base64': self._encode_base64,
            'decode_base64': self._decode_base64,
            'now': datetime.now,
            'utcnow': datetime.utcnow,
            'env': os.getenv,
            'file_exists': lambda path: Path(path).exists(),
            'dir_exists': lambda path: Path(path).is_dir(),
        })
    
    def _setup_template_filters(self) -> None:
        """Setup custom template filters."""
        self.env.filters.update({
            'to_port_range': self._port_range_filter,
            'to_cidr': self._cidr_filter,
            'to_duration': self._duration_filter,
            'to_file_size': self._file_size_filter,
            'to_yaml': self._yaml_filter,
            'from_yaml': self._from_yaml_filter,
            'to_json': self._json_filter,
            'from_json': self._from_json_filter,
            'slugify': self._slugify_filter,
            'sanitize': self._sanitize_filter,
            'quote_shell': self._quote_shell_filter,
            'indent_yaml': self._indent_yaml_filter,
        })
    
    def _setup_template_globals(self) -> None:
        """Setup global template variables."""
        self.env.globals.update({
            'protocols': [e.value for e in TemplateType],
            'default_ports': {
                'vless': 443,
                'shadowsocks': 8388,
                'wireguard': 51820,
                'http': 3128,
                'socks5': 1080,
            },
            'encryption_methods': {
                'shadowsocks': ['aes-256-gcm', 'aes-128-gcm', 'chacha20-ietf-poly1305'],
                'wireguard': ['curve25519', 'ed25519'],
            },
        })
    
    def render_template(
        self,
        template_name: str,
        context: TemplateContext,
        output_path: Optional[Path] = None
    ) -> TemplateResult:
        """
        Render template with context.
        
        Args:
            template_name: Name of template file
            context: Template context with variables
            output_path: Optional output file path
        """
        import time
        start_time = time.time()
        
        result = TemplateResult(
            content="",
            template_type=context.template_type
        )
        
        try:
            # Load template
            template = self.env.get_template(template_name)
            
            # Prepare rendering context
            render_context = {
                **context.variables,
                **context.globals,
                **context.functions
            }
            
            # Add custom filters to environment
            if context.filters:
                for name, filter_func in context.filters.items():
                    self.env.filters[name] = filter_func
            
            # Render template
            content = template.render(**render_context)
            result.content = content
            
            # Track variables used (simplified - would need AST analysis for complete accuracy)
            result.variables_used = list(context.variables.keys())
            
            # Save to file if output path provided
            if output_path:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                with open(output_path, 'w', encoding='utf-8') as f:
                    f.write(content)
            
        except TemplateNotFound as e:
            result.errors.append(f"Template not found: {e}")
        except TemplateSyntaxError as e:
            result.errors.append(f"Template syntax error: {e}")
        except TemplateRuntimeError as e:
            result.errors.append(f"Template runtime error: {e}")
        except Exception as e:
            result.errors.append(f"Unexpected error: {e}")
        
        result.render_time = time.time() - start_time
        return result
    
    def create_template(
        self,
        template_name: str,
        template_content: str,
        template_type: TemplateType,
        description: str = "",
        author: str = "VPN Manager"
    ) -> bool:
        """Create new template file."""
        try:
            # Choose appropriate template directory (first writable one)
            template_dir = self.template_dirs[0]
            template_path = template_dir / f"{template_name}.yaml"
            
            # Add template header
            header = f"""# VPN Manager Template: {template_name}
# Type: {template_type.value}
# Description: {description}
# Author: {author}
# Created: {datetime.now().isoformat()}
# 
# This template uses Jinja2 syntax for variable substitution
# Available functions: uuid4(), random_password(), generate_wg_key(), etc.
# Available filters: to_port_range, to_cidr, to_duration, etc.

"""
            
            full_content = header + template_content
            
            with open(template_path, 'w', encoding='utf-8') as f:
                f.write(full_content)
            
            return True
            
        except Exception as e:
            console.print(f"[red]Error creating template: {e}[/red]")
            return False
    
    def list_templates(self, template_type: Optional[TemplateType] = None) -> List[str]:
        """List available templates."""
        templates = []
        
        for template_dir in self.template_dirs:
            if not template_dir.exists():
                continue
            
            for template_file in template_dir.glob("*.yaml"):
                template_name = template_file.stem
                
                # Filter by type if specified
                if template_type:
                    try:
                        with open(template_file, 'r') as f:
                            header = f.read(500)  # Read first 500 chars
                        if f"Type: {template_type.value}" not in header:
                            continue
                    except:
                        continue
                
                templates.append(template_name)
        
        return sorted(list(set(templates)))  # Remove duplicates and sort
    
    def get_template_info(self, template_name: str) -> Dict[str, Any]:
        """Get template metadata."""
        info = {
            'name': template_name,
            'exists': False,
            'type': None,
            'description': '',
            'author': '',
            'created': '',
            'path': None,
            'size': 0,
        }
        
        try:
            template = self.env.get_template(f"{template_name}.yaml")
            info['exists'] = True
            
            # Get template source and metadata
            source = self.env.loader.get_source(self.env, f"{template_name}.yaml")
            info['path'] = source[1]  # filename
            
            if info['path']:
                template_path = Path(info['path'])
                info['size'] = template_path.stat().st_size
                
                # Parse metadata from header
                with open(template_path, 'r') as f:
                    content = f.read(1000)  # Read first 1000 chars for metadata
                
                # Extract metadata using regex
                type_match = re.search(r'# Type: (.+)', content)
                if type_match:
                    info['type'] = type_match.group(1).strip()
                
                desc_match = re.search(r'# Description: (.+)', content)
                if desc_match:
                    info['description'] = desc_match.group(1).strip()
                
                author_match = re.search(r'# Author: (.+)', content)
                if author_match:
                    info['author'] = author_match.group(1).strip()
                
                created_match = re.search(r'# Created: (.+)', content)
                if created_match:
                    info['created'] = created_match.group(1).strip()
            
        except TemplateNotFound:
            pass
        except Exception as e:
            info['error'] = str(e)
        
        return info
    
    def validate_template(self, template_name: str) -> TemplateResult:
        """Validate template syntax."""
        result = TemplateResult(
            content="",
            template_type=TemplateType.VLESS  # Default, will be updated
        )
        
        try:
            template = self.env.get_template(f"{template_name}.yaml")
            
            # Try to render with minimal context to check syntax
            minimal_context = {
                'server_name': 'test',
                'port': 8443,
                'protocol': 'vless',
            }
            
            # This will raise syntax errors if template is invalid
            template.render(**minimal_context)
            
            # Template is valid
            result.content = "Template syntax is valid"
            
        except TemplateNotFound:
            result.errors.append(f"Template '{template_name}' not found")
        except TemplateSyntaxError as e:
            result.errors.append(f"Syntax error in template: {e}")
        except Exception as e:
            result.warnings.append(f"Template may have runtime issues: {e}")
        
        return result
    
    # Helper methods for template functions
    
    def _generate_random_password(self, length: int = 32) -> str:
        """Generate random password."""
        alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return ''.join(secrets.choice(alphabet) for _ in range(length))
    
    def _generate_random_hex(self, length: int = 32) -> str:
        """Generate random hex string."""
        return secrets.token_hex(length // 2)
    
    def _generate_random_base64(self, length: int = 32) -> str:
        """Generate random base64 string."""
        return base64.b64encode(secrets.token_bytes(length)).decode('ascii')
    
    def _generate_wireguard_key(self) -> str:
        """Generate WireGuard private key."""
        key = x25519.X25519PrivateKey.generate()
        return base64.b64encode(
            key.private_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PrivateFormat.Raw,
                encryption_algorithm=serialization.NoEncryption()
            )
        ).decode('ascii')
    
    def _generate_wireguard_public(self, private_key: str) -> str:
        """Generate WireGuard public key from private key."""
        try:
            private_bytes = base64.b64decode(private_key)
            private_key_obj = x25519.X25519PrivateKey.from_private_bytes(private_bytes)
            public_key_obj = private_key_obj.public_key()
            return base64.b64encode(
                public_key_obj.public_bytes(
                    encoding=serialization.Encoding.Raw,
                    format=serialization.PublicFormat.Raw
                )
            ).decode('ascii')
        except:
            return self._generate_random_base64(32)
    
    def _generate_x25519_key(self) -> Dict[str, str]:
        """Generate X25519 key pair."""
        private_key = x25519.X25519PrivateKey.generate()
        public_key = private_key.public_key()
        
        return {
            'private': base64.b64encode(
                private_key.private_bytes(
                    encoding=serialization.Encoding.Raw,
                    format=serialization.PrivateFormat.Raw,
                    encryption_algorithm=serialization.NoEncryption()
                )
            ).decode('ascii'),
            'public': base64.b64encode(
                public_key.public_bytes(
                    encoding=serialization.Encoding.Raw,
                    format=serialization.PublicFormat.Raw
                )
            ).decode('ascii')
        }
    
    def _generate_rsa_key(self, key_size: int = 2048) -> Dict[str, str]:
        """Generate RSA key pair."""
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=key_size
        )
        public_key = private_key.public_key()
        
        private_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        
        public_pem = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        
        return {
            'private': private_pem.decode('utf-8'),
            'public': public_pem.decode('utf-8')
        }
    
    def _hash_password(self, password: str, algorithm: str = 'sha256') -> str:
        """Hash password using specified algorithm."""
        if algorithm == 'sha256':
            return hashlib.sha256(password.encode()).hexdigest()
        elif algorithm == 'md5':
            return hashlib.md5(password.encode()).hexdigest()
        else:
            return password
    
    def _encode_base64(self, text: str) -> str:
        """Encode text to base64."""
        return base64.b64encode(text.encode('utf-8')).decode('ascii')
    
    def _decode_base64(self, encoded: str) -> str:
        """Decode base64 to text."""
        try:
            return base64.b64decode(encoded).decode('utf-8')
        except:
            return encoded
    
    # Filter methods
    
    def _port_range_filter(self, value: Union[int, str]) -> str:
        """Format port range."""
        if isinstance(value, int):
            return str(value)
        elif '-' in str(value):
            return str(value)
        else:
            return str(value)
    
    def _cidr_filter(self, ip: str, prefix: int = 24) -> str:
        """Format IP address as CIDR."""
        return f"{ip}/{prefix}"
    
    def _duration_filter(self, seconds: Union[int, str]) -> str:
        """Format duration in human-readable format."""
        if isinstance(seconds, str):
            return seconds
        
        if seconds >= 86400:
            return f"{seconds // 86400}d"
        elif seconds >= 3600:
            return f"{seconds // 3600}h"
        elif seconds >= 60:
            return f"{seconds // 60}m"
        else:
            return f"{seconds}s"
    
    def _file_size_filter(self, bytes_value: Union[int, str]) -> str:
        """Format file size in human-readable format."""
        if isinstance(bytes_value, str):
            return bytes_value
        
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_value < 1024:
                return f"{bytes_value:.1f}{unit}"
            bytes_value /= 1024
        return f"{bytes_value:.1f}PB"
    
    def _yaml_filter(self, value: Any) -> str:
        """Convert value to YAML format."""
        import yaml
        return yaml.dump(value, default_flow_style=False)
    
    def _from_yaml_filter(self, value: str) -> Any:
        """Parse YAML string."""
        import yaml
        return yaml.safe_load(value)
    
    def _json_filter(self, value: Any) -> str:
        """Convert value to JSON format."""
        import json
        return json.dumps(value, indent=2)
    
    def _from_json_filter(self, value: str) -> Any:
        """Parse JSON string."""
        import json
        return json.loads(value)
    
    def _slugify_filter(self, value: str) -> str:
        """Convert string to URL-safe slug."""
        import re
        value = re.sub(r'[^\w\s-]', '', value.lower())
        return re.sub(r'[-\s]+', '-', value).strip('-')
    
    def _sanitize_filter(self, value: str) -> str:
        """Sanitize string for use in configuration."""
        import re
        return re.sub(r'[^\w\-.]', '_', value)
    
    def _quote_shell_filter(self, value: str) -> str:
        """Quote string for shell usage."""
        import shlex
        return shlex.quote(value)
    
    def _indent_yaml_filter(self, value: str, indent: int = 2) -> str:
        """Indent YAML content."""
        lines = value.split('\n')
        indented_lines = [' ' * indent + line if line.strip() else line for line in lines]
        return '\n'.join(indented_lines)


def create_default_vpn_templates():
    """Create default VPN configuration templates."""
    engine = VPNTemplateEngine()
    
    # VLESS template
    vless_template = """# VLESS Server Configuration
server:
  name: "{{ server_name }}"
  protocol: vless
  port: {{ port | default(443) }}
  {% if domain -%}
  domain: "{{ domain }}"
  {% endif %}

# VLESS configuration
vless:
  uuid: "{{ uuid | default(uuid4()) }}"
  flow: "{{ flow | default('xtls-rprx-vision') }}"
  
  # Reality configuration
  reality:
    enabled: {{ reality_enabled | default(true) | lower }}
    dest: "{{ reality_dest | default('example.com:443') }}"
    server_names:
      {% for name in server_names | default(['example.com']) -%}
      - "{{ name }}"
      {% endfor %}
    private_key: "{{ reality_private_key | default(generate_x25519_key().private) }}"
    public_key: "{{ reality_public_key | default(generate_x25519_key().public) }}"
  
  # Transport configuration
  transport:
    type: "{{ transport_type | default('tcp') }}"
    {% if transport_type == 'grpc' -%}
    grpc:
      service_name: "{{ grpc_service_name | default('TunService') }}"
    {% elif transport_type == 'ws' -%}
    ws:
      path: "{{ ws_path | default('/') }}"
      {% if ws_host -%}
      host: "{{ ws_host }}"
      {% endif %}
    {% endif %}

# Docker configuration
docker:
  image: "{{ docker_image | default('ghcr.io/xtls/xray-core:latest') }}"
  restart_policy: "{{ restart_policy | default('unless-stopped') }}"
  
  resources:
    memory: "{{ memory_limit | default('512MB') }}"
    cpu_limit: "{{ cpu_limit | default('1.0') }}"
  
  environment:
    XRAY_VMESS_AEAD_FORCED: "false"
    XRAY_VLESS_XTLS_ENABLED: "true"
  
  volumes:
    - host_path: "./certs"
      container_path: "/etc/ssl/certs"
      read_only: true
    - host_path: "./logs"
      container_path: "/var/log/xray"
  
  ports:
    - host_port: {{ port }}
      container_port: {{ port }}
      protocol: tcp

# Health check
health_check:
  enabled: {{ health_check_enabled | default(true) | lower }}
  interval: {{ health_check_interval | default(30) }}
  timeout: {{ health_check_timeout | default(10) }}
  retries: {{ health_check_retries | default(3) }}

# Logging
logging:
  level: "{{ log_level | default('INFO') }}"
  access_log: "{{ access_log | default('/var/log/xray/access.log') }}"
  error_log: "{{ error_log | default('/var/log/xray/error.log') }}"
"""
    
    engine.create_template(
        "vless_server",
        vless_template,
        TemplateType.VLESS,
        "VLESS server with Reality configuration"
    )
    
    # Shadowsocks template
    shadowsocks_template = """# Shadowsocks Server Configuration
server:
  name: "{{ server_name }}"
  protocol: shadowsocks
  port: {{ port | default(8388) }}

# Shadowsocks configuration
shadowsocks:
  method: "{{ method | default('aes-256-gcm') }}"
  password: "{{ password | default(random_password(32)) }}"
  timeout: {{ timeout | default(60) }}
  
  {% if plugin -%}
  # Plugin configuration
  plugin:
    name: "{{ plugin }}"
    options: "{{ plugin_options | default('') }}"
  {% endif %}
  
  # Server optimization
  fast_open: {{ fast_open | default(true) | lower }}
  no_delay: {{ no_delay | default(true) | lower }}
  
  # Traffic control
  {% if traffic_limit -%}
  traffic_limit: "{{ traffic_limit }}"
  {% endif %}

# Docker configuration
docker:
  image: "{{ docker_image | default('shadowsocks/shadowsocks-libev:latest') }}"
  restart_policy: "{{ restart_policy | default('unless-stopped') }}"
  
  resources:
    memory: "{{ memory_limit | default('256MB') }}"
    cpu_limit: "{{ cpu_limit | default('0.5') }}"
  
  environment:
    METHOD: "{{ method | default('aes-256-gcm') }}"
    PASSWORD: "{{ password | default(random_password(32)) }}"
    TIMEOUT: "{{ timeout | default(60) }}"
    DNS_ADDRS: "{{ dns_servers | default('8.8.8.8,8.8.4.4') }}"
  
  ports:
    - host_port: {{ port }}
      container_port: {{ port }}
      protocol: "{{ protocol_type | default('tcp') }}"

# Health check
health_check:
  enabled: {{ health_check_enabled | default(true) | lower }}
  interval: {{ health_check_interval | default(30) }}
  timeout: {{ health_check_timeout | default(5) }}
  command: "ss-local -h"

# Monitoring
monitoring:
  metrics_enabled: {{ metrics_enabled | default(true) | lower }}
  prometheus_port: {{ prometheus_port | default(9090) }}
"""
    
    engine.create_template(
        "shadowsocks_server",
        shadowsocks_template,
        TemplateType.SHADOWSOCKS,
        "Shadowsocks server with optimization settings"
    )
    
    # WireGuard template
    wireguard_template = """# WireGuard Server Configuration
server:
  name: "{{ server_name }}"
  protocol: wireguard
  port: {{ port | default(51820) }}

# WireGuard configuration
wireguard:
  interface: "{{ interface | default('wg0') }}"
  private_key: "{{ private_key | default(generate_wg_key()) }}"
  public_key: "{{ public_key | default(generate_wg_public(private_key | default(generate_wg_key()))) }}"
  
  # Network configuration
  address: "{{ address | default('10.0.0.1/24') }}"
  listen_port: {{ port }}
  
  # DNS settings
  dns: "{{ dns_servers | default('1.1.1.1, 8.8.8.8') }}"
  
  # Routing
  table: "{{ routing_table | default('auto') }}"
  mtu: {{ mtu | default(1420) }}
  
  # Keepalive
  persistent_keepalive: {{ persistent_keepalive | default(25) }}
  
  # Post-up and post-down scripts
  post_up:
    {% for cmd in post_up_commands | default([]) -%}
    - "{{ cmd }}"
    {% endfor %}
  
  post_down:
    {% for cmd in post_down_commands | default([]) -%}
    - "{{ cmd }}"
    {% endfor %}
  
  # Peer configurations
  peers:
    {% for peer in peers | default([]) -%}
    - public_key: "{{ peer.public_key }}"
      allowed_ips: "{{ peer.allowed_ips | default('0.0.0.0/0, ::/0') }}"
      {% if peer.endpoint -%}
      endpoint: "{{ peer.endpoint }}"
      {% endif -%}
      {% if peer.persistent_keepalive -%}
      persistent_keepalive: {{ peer.persistent_keepalive }}
      {% endif %}
    {% endfor %}

# Docker configuration
docker:
  image: "{{ docker_image | default('linuxserver/wireguard:latest') }}"
  restart_policy: "{{ restart_policy | default('unless-stopped') }}"
  
  # Privileged mode required for WireGuard
  privileged: true
  
  resources:
    memory: "{{ memory_limit | default('256MB') }}"
    cpu_limit: "{{ cpu_limit | default('0.5') }}"
  
  environment:
    PUID: "{{ puid | default(1000) }}"
    PGID: "{{ pgid | default(1000) }}"
    TZ: "{{ timezone | default('Etc/UTC') }}"
    SERVERURL: "{{ server_url | default('auto') }}"
    SERVERPORT: "{{ port }}"
    PEERS: "{{ peers_count | default(10) }}"
    PEERDNS: "{{ dns_servers | default('auto') }}"
    INTERNAL_SUBNET: "{{ internal_subnet | default('10.0.0.0') }}"
  
  volumes:
    - host_path: "./config"
      container_path: "/config"
    - host_path: "/lib/modules"
      container_path: "/lib/modules"
      read_only: true
  
  ports:
    - host_port: {{ port }}
      container_port: {{ port }}
      protocol: udp
  
  # Required for WireGuard kernel module
  cap_add:
    - NET_ADMIN
    - SYS_MODULE
  
  sysctls:
    - net.ipv4.conf.all.src_valid_mark=1

# Health check
health_check:
  enabled: {{ health_check_enabled | default(true) | lower }}
  interval: {{ health_check_interval | default(30) }}
  timeout: {{ health_check_timeout | default(10) }}
  command: "wg show {{ interface | default('wg0') }}"
"""
    
    engine.create_template(
        "wireguard_server",
        wireguard_template,
        TemplateType.WIREGUARD,
        "WireGuard server with peer management"
    )
    
    # HTTP Proxy template
    http_proxy_template = """# HTTP Proxy Server Configuration
server:
  name: "{{ server_name }}"
  protocol: http
  port: {{ port | default(3128) }}

# HTTP Proxy configuration
http_proxy:
  # Authentication
  authentication:
    enabled: {{ auth_enabled | default(false) | lower }}
    {% if auth_enabled -%}
    method: "{{ auth_method | default('basic') }}"
    users:
      {% for user in proxy_users | default([]) -%}
      - username: "{{ user.username }}"
        password: "{{ user.password | default(random_password(16)) }}"
      {% endfor %}
    {% endif %}
  
  # Access control
  access_control:
    {% for rule in access_rules | default([]) -%}
    - action: "{{ rule.action }}"
      source: "{{ rule.source }}"
      {% if rule.destination -%}
      destination: "{{ rule.destination }}"
      {% endif %}
    {% endfor %}
  
  # Logging
  access_log: {{ access_log_enabled | default(true) | lower }}
  log_format: "{{ log_format | default('combined') }}"
  
  # Connection limits
  max_connections: {{ max_connections | default(1000) }}
  timeout: {{ connection_timeout | default(30) }}
  
  # Cache settings (if applicable)
  {% if cache_enabled -%}
  cache:
    enabled: true
    size: "{{ cache_size | default('256MB') }}"
    max_object_size: "{{ max_object_size | default('10MB') }}"
  {% endif %}

# Docker configuration
docker:
  image: "{{ docker_image | default('nginx:alpine') }}"
  restart_policy: "{{ restart_policy | default('unless-stopped') }}"
  
  resources:
    memory: "{{ memory_limit | default('256MB') }}"
    cpu_limit: "{{ cpu_limit | default('0.5') }}"
  
  volumes:
    - host_path: "./config"
      container_path: "/etc/nginx/conf.d"
    - host_path: "./logs"
      container_path: "/var/log/nginx"
  
  ports:
    - host_port: {{ port }}
      container_port: {{ port }}
      protocol: tcp

# Health check
health_check:
  enabled: {{ health_check_enabled | default(true) | lower }}
  interval: {{ health_check_interval | default(30) }}
  timeout: {{ health_check_timeout | default(5) }}
  command: "curl -f http://localhost:{{ port }}/health || exit 1"
"""
    
    engine.create_template(
        "http_proxy",
        http_proxy_template,
        TemplateType.HTTP_PROXY,
        "HTTP proxy server with authentication and access control"
    )
    
    # Docker Compose template
    docker_compose_template = """# Docker Compose for VPN Services
version: '3.8'

services:
  {% for service in services -%}
  {{ service.name }}:
    image: {{ service.image }}
    container_name: {{ service.name }}
    restart: {{ service.restart_policy | default('unless-stopped') }}
    
    {% if service.ports -%}
    ports:
      {% for port in service.ports -%}
      - "{{ port.host }}:{{ port.container }}{% if port.protocol != 'tcp' %}/{{ port.protocol }}{% endif %}"
      {% endfor %}
    {% endif %}
    
    {% if service.environment -%}
    environment:
      {% for key, value in service.environment.items() -%}
      {{ key }}: "{{ value }}"
      {% endfor %}
    {% endif %}
    
    {% if service.volumes -%}
    volumes:
      {% for volume in service.volumes -%}
      - {{ volume.host }}:{{ volume.container }}{% if volume.read_only %}:ro{% endif %}
      {% endfor %}
    {% endif %}
    
    {% if service.networks -%}
    networks:
      {% for network in service.networks -%}
      - {{ network }}
      {% endfor %}
    {% endif %}
    
    {% if service.depends_on -%}
    depends_on:
      {% for dep in service.depends_on -%}
      - {{ dep }}
      {% endfor %}
    {% endif %}
    
    {% if service.healthcheck -%}
    healthcheck:
      test: {{ service.healthcheck.test }}
      interval: {{ service.healthcheck.interval | default('30s') }}
      timeout: {{ service.healthcheck.timeout | default('10s') }}
      retries: {{ service.healthcheck.retries | default(3) }}
    {% endif %}
    
    {% if service.deploy -%}
    deploy:
      resources:
        limits:
          memory: {{ service.deploy.memory_limit | default('512M') }}
          cpus: '{{ service.deploy.cpu_limit | default('1.0') }}'
        reservations:
          memory: {{ service.deploy.memory_reservation | default('256M') }}
          cpus: '{{ service.deploy.cpu_reservation | default('0.5') }}'
    {% endif %}
  
  {% endfor %}

{% if networks -%}
networks:
  {% for network in networks -%}
  {{ network.name }}:
    driver: {{ network.driver | default('bridge') }}
    {% if network.ipam -%}
    ipam:
      config:
        - subnet: {{ network.ipam.subnet }}
    {% endif %}
    {% if network.external -%}
    external: true
    {% endif %}
  {% endfor %}
{% endif %}

{% if volumes -%}
volumes:
  {% for volume in volumes -%}
  {{ volume.name }}:
    {% if volume.driver -%}
    driver: {{ volume.driver }}
    {% endif -%}
    {% if volume.external -%}
    external: true
    {% endif %}
  {% endfor %}
{% endif %}
"""
    
    engine.create_template(
        "docker_compose",
        docker_compose_template,
        TemplateType.DOCKER_COMPOSE,
        "Docker Compose configuration for VPN services"
    )
    
    console.print("[green]✓ Default VPN templates created successfully[/green]")


# Global template engine instance
vpn_template_engine = VPNTemplateEngine()


def render_vpn_template(
    template_name: str,
    template_type: TemplateType,
    variables: Dict[str, Any],
    output_path: Optional[Path] = None
) -> TemplateResult:
    """Convenience function to render VPN template."""
    context = TemplateContext(template_type=template_type, variables=variables)
    return vpn_template_engine.render_template(template_name, context, output_path)


def create_vpn_template(
    template_name: str,
    template_content: str,
    template_type: TemplateType,
    description: str = ""
) -> bool:
    """Convenience function to create VPN template."""
    return vpn_template_engine.create_template(
        template_name, template_content, template_type, description
    )


if __name__ == "__main__":
    # Create default templates when module is run directly
    create_default_vpn_templates()