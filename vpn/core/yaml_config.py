"""Enhanced YAML configuration system for VPN Manager.

This module provides comprehensive YAML configuration support:
- Advanced YAML configuration loading and validation
- YAML schema generation and validation
- Configuration merging and inheritance
- Custom YAML tag support for VPN-specific data types
- Configuration templating with Jinja2 integration
- Multi-environment configuration management
"""

import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import yaml
from jinja2 import Environment, FileSystemLoader, Template, select_autoescape
from pydantic import BaseModel, ValidationError
from rich.console import Console

console = Console()


@dataclass
class YamlLoadResult:
    """Result of YAML loading operation."""
    data: dict[str, Any]
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    source_file: Path | None = None
    loaded_at: datetime = field(default_factory=datetime.now)

    @property
    def is_valid(self) -> bool:
        """Check if the loaded data is valid."""
        return len(self.errors) == 0

    @property
    def has_warnings(self) -> bool:
        """Check if there are warnings."""
        return len(self.warnings) > 0


class VPNYamlConstructor(yaml.SafeLoader):
    """Custom YAML constructor for VPN-specific data types."""

    def __init__(self, stream):
        super().__init__(stream)
        # Add custom constructors
        self.add_constructor('!duration', self._construct_duration)
        self.add_constructor('!protocol', self._construct_protocol)
        self.add_constructor('!port_range', self._construct_port_range)
        self.add_constructor('!file_size', self._construct_file_size)
        self.add_constructor('!env', self._construct_env_var)
        self.add_constructor('!include', self._construct_include)
        self.add_constructor('!merge', self._construct_merge)

    def _construct_duration(self, loader, node):
        """Construct duration from string (e.g., '5m', '1h', '30s')."""
        value = loader.construct_scalar(node)

        # Parse duration string
        pattern = r'^(\d+)([smhd])$'
        match = re.match(pattern, value.lower())

        if not match:
            raise yaml.constructor.ConstructorError(
                None, None, f"Invalid duration format: {value}", node.start_mark
            )

        amount, unit = match.groups()
        amount = int(amount)

        multipliers = {
            's': 1,
            'm': 60,
            'h': 3600,
            'd': 86400
        }

        return amount * multipliers[unit]

    def _construct_protocol(self, loader, node):
        """Construct protocol configuration."""
        if isinstance(node, yaml.ScalarNode):
            # Simple protocol name
            return {"type": loader.construct_scalar(node)}
        elif isinstance(node, yaml.MappingNode):
            # Full protocol configuration
            return loader.construct_mapping(node)
        else:
            raise yaml.constructor.ConstructorError(
                None, None, "Protocol must be a string or mapping", node.start_mark
            )

    def _construct_port_range(self, loader, node):
        """Construct port range from string (e.g., '8000-8100')."""
        value = loader.construct_scalar(node)

        if '-' in value:
            start, end = value.split('-', 1)
            return {"start": int(start), "end": int(end)}
        else:
            port = int(value)
            return {"start": port, "end": port}

    def _construct_file_size(self, loader, node):
        """Construct file size from string (e.g., '100MB', '1GB')."""
        value = loader.construct_scalar(node).upper()

        pattern = r'^(\d+(?:\.\d+)?)(B|KB|MB|GB|TB)$'
        match = re.match(pattern, value)

        if not match:
            raise yaml.constructor.ConstructorError(
                None, None, f"Invalid file size format: {value}", node.start_mark
            )

        amount, unit = match.groups()
        amount = float(amount)

        multipliers = {
            'B': 1,
            'KB': 1024,
            'MB': 1024 ** 2,
            'GB': 1024 ** 3,
            'TB': 1024 ** 4
        }

        return int(amount * multipliers[unit])

    def _construct_env_var(self, loader, node):
        """Construct value from environment variable."""
        if isinstance(node, yaml.ScalarNode):
            var_name = loader.construct_scalar(node)
            default = None
        elif isinstance(node, yaml.MappingNode):
            mapping = loader.construct_mapping(node)
            var_name = mapping.get('name') or mapping.get('var')
            default = mapping.get('default')
        else:
            raise yaml.constructor.ConstructorError(
                None, None, "Environment variable must be string or mapping", node.start_mark
            )

        value = os.getenv(var_name, default)
        if value is None:
            raise yaml.constructor.ConstructorError(
                None, None, f"Environment variable {var_name} not found", node.start_mark
            )

        return value

    def _construct_include(self, loader, node):
        """Include another YAML file."""
        filename = loader.construct_scalar(node)

        # Get the directory of the current file being loaded
        if hasattr(loader.stream, 'name'):
            current_dir = Path(loader.stream.name).parent
            include_path = current_dir / filename
        else:
            include_path = Path(filename)

        if not include_path.exists():
            raise yaml.constructor.ConstructorError(
                None, None, f"Include file not found: {include_path}", node.start_mark
            )

        with open(include_path) as f:
            return yaml.load(f, Loader=VPNYamlConstructor)

    def _construct_merge(self, loader, node):
        """Merge multiple mappings."""
        if not isinstance(node, yaml.SequenceNode):
            raise yaml.constructor.ConstructorError(
                None, None, "Merge requires a sequence", node.start_mark
            )

        result = {}
        for item_node in node.value:
            item = loader.construct_object(item_node)
            if isinstance(item, dict):
                result.update(item)
            else:
                raise yaml.constructor.ConstructorError(
                    None, None, "Merge items must be mappings", item_node.start_mark
                )

        return result


class VPNYamlRepresenter(yaml.SafeDumper):
    """Custom YAML representer for VPN-specific data types."""

    def __init__(self, stream, **kwargs):
        super().__init__(stream, **kwargs)
        # Add custom representers
        self.add_representer(timedelta, self._represent_duration)
        self.add_representer(Path, self._represent_path)

    def _represent_duration(self, dumper, data):
        """Represent duration as string."""
        total_seconds = int(data.total_seconds())

        if total_seconds >= 86400 and total_seconds % 86400 == 0:
            return dumper.represent_scalar('!duration', f"{total_seconds // 86400}d")
        elif total_seconds >= 3600 and total_seconds % 3600 == 0:
            return dumper.represent_scalar('!duration', f"{total_seconds // 3600}h")
        elif total_seconds >= 60 and total_seconds % 60 == 0:
            return dumper.represent_scalar('!duration', f"{total_seconds // 60}m")
        else:
            return dumper.represent_scalar('!duration', f"{total_seconds}s")

    def _represent_path(self, dumper, data):
        """Represent Path as string."""
        return dumper.represent_scalar('tag:yaml.org,2002:str', str(data))


class YamlConfigManager:
    """Enhanced YAML configuration manager with advanced features."""

    def __init__(self, template_dir: Path | None = None):
        """Initialize YAML config manager."""
        self.template_dir = template_dir or Path(__file__).parent.parent / "templates" / "config"
        self.template_dir.mkdir(parents=True, exist_ok=True)

        # Setup Jinja2 environment for templating
        self.jinja_env = Environment(
            loader=FileSystemLoader(str(self.template_dir)),
            autoescape=select_autoescape(['yaml', 'yml']),
            trim_blocks=True,
            lstrip_blocks=True
        )

        # Add custom Jinja2 filters
        self.jinja_env.filters['to_yaml'] = self._to_yaml_filter
        self.jinja_env.filters['from_yaml'] = self._from_yaml_filter
        self.jinja_env.filters['env_var'] = self._env_var_filter

    def load_yaml(
        self,
        source: str | Path | dict[str, Any],
        validate_schema: bool = True,
        schema_model: type[BaseModel] | None = None,
        template_vars: dict[str, Any] | None = None
    ) -> YamlLoadResult:
        """Load YAML configuration with validation and templating.
        
        Args:
            source: YAML string, file path, or dictionary
            validate_schema: Whether to validate against schema
            schema_model: Pydantic model for validation
            template_vars: Variables for Jinja2 templating
        """
        result = YamlLoadResult(data={})

        try:
            # Handle different source types
            if isinstance(source, dict):
                yaml_content = yaml.dump(source, Dumper=VPNYamlRepresenter)
                result.source_file = None
            elif isinstance(source, (str, Path)):
                if Path(source).exists():
                    # File path
                    result.source_file = Path(source)
                    with open(source, encoding='utf-8') as f:
                        yaml_content = f.read()
                else:
                    # YAML string
                    yaml_content = str(source)
            else:
                raise ValueError(f"Unsupported source type: {type(source)}")

            # Apply templating if variables provided
            if template_vars:
                try:
                    template = Template(yaml_content)
                    yaml_content = template.render(**template_vars)
                except Exception as e:
                    result.errors.append(f"Templating error: {e}")
                    return result

            # Load YAML with custom constructor
            try:
                data = yaml.load(yaml_content, Loader=VPNYamlConstructor)
                if data is None:
                    data = {}
                result.data = data
            except yaml.YAMLError as e:
                result.errors.append(f"YAML parsing error: {e}")
                return result

            # Schema validation
            if validate_schema and schema_model:
                try:
                    validated_data = schema_model(**data)
                    result.data = validated_data.model_dump()
                except ValidationError as e:
                    for error in e.errors():
                        field_path = ' -> '.join(str(loc) for loc in error['loc'])
                        result.errors.append(f"Validation error in {field_path}: {error['msg']}")
                except Exception as e:
                    result.errors.append(f"Schema validation error: {e}")

        except Exception as e:
            result.errors.append(f"Unexpected error: {e}")

        return result

    def save_yaml(
        self,
        data: dict[str, Any],
        output_path: Path,
        template_name: str | None = None,
        template_vars: dict[str, Any] | None = None,
        sort_keys: bool = True,
        indent: int = 2
    ) -> bool:
        """Save configuration as YAML file.
        
        Args:
            data: Configuration data to save
            output_path: Output file path
            template_name: Template file name for formatting
            template_vars: Variables for template rendering
            sort_keys: Whether to sort keys alphabetically
            indent: YAML indentation level
        """
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)

            if template_name:
                # Use template for structured output
                try:
                    template = self.jinja_env.get_template(template_name)
                    content = template.render(config=data, **(template_vars or {}))

                    with open(output_path, 'w', encoding='utf-8') as f:
                        f.write(content)

                    return True
                except Exception as e:
                    console.print(f"[yellow]Template error, falling back to direct YAML: {e}[/yellow]")

            # Direct YAML dump
            with open(output_path, 'w', encoding='utf-8') as f:
                yaml.dump(
                    data,
                    f,
                    Dumper=VPNYamlRepresenter,
                    default_flow_style=False,
                    sort_keys=sort_keys,
                    indent=indent,
                    allow_unicode=True,
                    encoding='utf-8'
                )

            return True

        except Exception as e:
            console.print(f"[red]Error saving YAML file: {e}[/red]")
            return False

    def merge_configs(
        self,
        base_config: dict[str, Any],
        *override_configs: dict[str, Any],
        deep_merge: bool = True
    ) -> dict[str, Any]:
        """Merge multiple configuration dictionaries.
        
        Args:
            base_config: Base configuration
            override_configs: Configurations to merge on top
            deep_merge: Whether to perform deep merge
        """
        if not deep_merge:
            # Shallow merge
            result = base_config.copy()
            for config in override_configs:
                result.update(config)
            return result

        # Deep merge
        def deep_merge_dicts(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
            result = base.copy()

            for key, value in override.items():
                if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                    result[key] = deep_merge_dicts(result[key], value)
                else:
                    result[key] = value

            return result

        result = base_config.copy()
        for config in override_configs:
            result = deep_merge_dicts(result, config)

        return result

    def validate_yaml_file(self, file_path: Path, schema_model: type[BaseModel]) -> YamlLoadResult:
        """Validate YAML file against Pydantic model."""
        return self.load_yaml(file_path, validate_schema=True, schema_model=schema_model)

    def create_template(
        self,
        template_name: str,
        template_content: str,
        description: str = ""
    ) -> bool:
        """Create a new YAML template."""
        try:
            template_path = self.template_dir / f"{template_name}.yaml"

            # Add template header with description
            if description:
                header = f"# {description}\n# Generated on {datetime.now().isoformat()}\n\n"
                template_content = header + template_content

            with open(template_path, 'w', encoding='utf-8') as f:
                f.write(template_content)

            return True

        except Exception as e:
            console.print(f"[red]Error creating template: {e}[/red]")
            return False

    def list_templates(self) -> list[str]:
        """List available YAML templates."""
        if not self.template_dir.exists():
            return []

        templates = []
        for file_path in self.template_dir.glob("*.yaml"):
            templates.append(file_path.stem)

        return sorted(templates)

    def render_template(
        self,
        template_name: str,
        variables: dict[str, Any],
        output_path: Path | None = None
    ) -> str | bool:
        """Render YAML template with variables.
        
        Returns:
            Rendered content if output_path is None, otherwise success boolean
        """
        try:
            template = self.jinja_env.get_template(f"{template_name}.yaml")
            content = template.render(**variables)

            if output_path:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                with open(output_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                return True
            else:
                return content

        except Exception as e:
            console.print(f"[red]Error rendering template: {e}[/red]")
            return False if output_path else ""

    def convert_from_toml(self, toml_path: Path, yaml_path: Path) -> bool:
        """Convert TOML configuration to YAML."""
        try:
            import tomli

            with open(toml_path, 'rb') as f:
                toml_data = tomli.load(f)

            return self.save_yaml(toml_data, yaml_path)

        except ImportError:
            console.print("[red]tomli package required for TOML conversion[/red]")
            return False
        except Exception as e:
            console.print(f"[red]Error converting TOML to YAML: {e}[/red]")
            return False

    def convert_to_toml(self, yaml_path: Path, toml_path: Path) -> bool:
        """Convert YAML configuration to TOML."""
        try:
            import tomli_w

            result = self.load_yaml(yaml_path, validate_schema=False)
            if not result.is_valid:
                console.print(f"[red]YAML file has errors: {result.errors}[/red]")
                return False

            toml_path.parent.mkdir(parents=True, exist_ok=True)
            with open(toml_path, 'wb') as f:
                tomli_w.dump(result.data, f)

            return True

        except ImportError:
            console.print("[red]tomli-w package required for TOML conversion[/red]")
            return False
        except Exception as e:
            console.print(f"[red]Error converting YAML to TOML: {e}[/red]")
            return False

    def _to_yaml_filter(self, value: Any) -> str:
        """Jinja2 filter to convert value to YAML."""
        return yaml.dump(value, Dumper=VPNYamlRepresenter, default_flow_style=False)

    def _from_yaml_filter(self, value: str) -> Any:
        """Jinja2 filter to parse YAML string."""
        return yaml.load(value, Loader=VPNYamlConstructor)

    def _env_var_filter(self, var_name: str, default: str = "") -> str:
        """Jinja2 filter to get environment variable."""
        return os.getenv(var_name, default)


class YamlConfigValidator:
    """YAML configuration validator with schema support."""

    def __init__(self, yaml_manager: YamlConfigManager | None = None):
        """Initialize validator."""
        self.yaml_manager = yaml_manager or YamlConfigManager()

    def validate_structure(self, config: dict[str, Any], required_sections: list[str]) -> list[str]:
        """Validate that required sections exist in configuration."""
        errors = []

        for section in required_sections:
            if section not in config:
                errors.append(f"Missing required section: {section}")
            elif not isinstance(config[section], dict):
                errors.append(f"Section '{section}' must be a dictionary")

        return errors

    def validate_environment_refs(self, config: dict[str, Any]) -> list[str]:
        """Validate that all environment variable references are available."""
        errors = []

        def check_env_refs(obj: Any, path: str = ""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    check_env_refs(value, f"{path}.{key}" if path else key)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    check_env_refs(item, f"{path}[{i}]")
            elif isinstance(obj, str) and obj.startswith("${") and obj.endswith("}"):
                env_var = obj[2:-1]
                if env_var not in os.environ:
                    errors.append(f"Environment variable '{env_var}' not found (used in {path})")

        check_env_refs(config)
        return errors

    def validate_file_paths(self, config: dict[str, Any]) -> list[str]:
        """Validate that file paths in configuration exist."""
        errors = []

        def check_paths(obj: Any, path: str = ""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    # Check if key suggests a file path
                    if any(keyword in key.lower() for keyword in ['path', 'file', 'cert', 'key']):
                        if isinstance(value, str) and value and not Path(value).exists():
                            errors.append(f"File not found: {value} (in {path}.{key})")
                    check_paths(value, f"{path}.{key}" if path else key)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    check_paths(item, f"{path}[{i}]")

        check_paths(config)
        return errors

    def validate_network_config(self, config: dict[str, Any]) -> list[str]:
        """Validate network-related configuration."""
        errors = []

        if 'network' in config:
            network_config = config['network']

            # Validate ports
            if 'ports' in network_config:
                ports = network_config['ports']
                if isinstance(ports, dict):
                    for service, port_config in ports.items():
                        if isinstance(port_config, int):
                            if not (1 <= port_config <= 65535):
                                errors.append(f"Invalid port for {service}: {port_config}")
                        elif isinstance(port_config, dict):
                            if 'start' in port_config and 'end' in port_config:
                                start, end = port_config['start'], port_config['end']
                                if not (1 <= start <= end <= 65535):
                                    errors.append(f"Invalid port range for {service}: {start}-{end}")

            # Validate IP addresses
            if 'bind_address' in network_config:
                import ipaddress
                try:
                    ipaddress.ip_address(network_config['bind_address'])
                except ValueError:
                    errors.append(f"Invalid IP address: {network_config['bind_address']}")

        return errors


# Global YAML configuration manager instance
yaml_config_manager = YamlConfigManager()


def load_yaml_config(
    source: str | Path,
    schema_model: type[BaseModel] | None = None,
    template_vars: dict[str, Any] | None = None
) -> YamlLoadResult:
    """Convenience function to load YAML configuration."""
    return yaml_config_manager.load_yaml(
        source,
        validate_schema=bool(schema_model),
        schema_model=schema_model,
        template_vars=template_vars
    )


def save_yaml_config(
    data: dict[str, Any],
    output_path: Path,
    template_name: str | None = None
) -> bool:
    """Convenience function to save YAML configuration."""
    return yaml_config_manager.save_yaml(data, output_path, template_name)


def create_default_templates():
    """Create default YAML templates for VPN configuration."""
    manager = yaml_config_manager

    # Base configuration template
    base_config_template = """# VPN Manager Base Configuration
# This template provides a complete configuration structure with sensible defaults

# Application settings
app:
  name: "{{ app_name | default('VPN Manager') }}"
  version: "{{ app_version | default('1.0.0') }}"
  debug: {{ debug | default(false) | lower }}
  log_level: "{{ log_level | default('INFO') }}"

# Database configuration
database:
  type: "{{ db_type | default('sqlite') }}"
  {% if db_type == 'sqlite' -%}
  path: "{{ db_path | default('~/.config/vpn-manager/vpn.db') }}"
  {% else -%}
  host: "{{ db_host | default('localhost') }}"
  port: {{ db_port | default(5432) }}
  name: "{{ db_name | default('vpn_manager') }}"
  user: "{{ db_user | default('vpn') }}"
  password: !env { name: "VPN_DB_PASSWORD", default: "" }
  {% endif %}
  pool_size: {{ db_pool_size | default(10) }}
  max_overflow: {{ db_max_overflow | default(20) }}

# Docker configuration
docker:
  host: "{{ docker_host | default('unix:///var/run/docker.sock') }}"
  timeout: !duration "{{ docker_timeout | default('30s') }}"
  auto_remove: {{ docker_auto_remove | default(true) | lower }}
  restart_policy: "{{ docker_restart_policy | default('unless-stopped') }}"
  network_name: "{{ docker_network | default('vpn-network') }}"

# Network settings
network:
  bind_address: "{{ bind_address | default('0.0.0.0') }}"
  ports:
    vless: !port_range "{{ vless_ports | default('8443') }}"
    shadowsocks: !port_range "{{ shadowsocks_ports | default('8388') }}"
    wireguard: !port_range "{{ wireguard_ports | default('51820') }}"
    http_proxy: !port_range "{{ http_proxy_ports | default('3128') }}"
    socks5_proxy: !port_range "{{ socks5_proxy_ports | default('1080') }}"
  dns_servers:
    - "{{ primary_dns | default('1.1.1.1') }}"
    - "{{ secondary_dns | default('8.8.8.8') }}"

# Security settings
security:
  tls:
    enabled: {{ tls_enabled | default(true) | lower }}
    cert_path: "{{ tls_cert_path | default('/etc/ssl/certs/vpn.crt') }}"
    key_path: "{{ tls_key_path | default('/etc/ssl/private/vpn.key') }}"
    auto_generate: {{ tls_auto_generate | default(true) | lower }}
  
  authentication:
    required: {{ auth_required | default(false) | lower }}
    method: "{{ auth_method | default('token') }}"
    token_expiry: !duration "{{ token_expiry | default('24h') }}"
  
  rate_limiting:
    enabled: {{ rate_limiting_enabled | default(true) | lower }}
    max_requests: {{ max_requests | default(100) }}
    window: !duration "{{ rate_limit_window | default('1h') }}"

# Monitoring and metrics
monitoring:
  enabled: {{ monitoring_enabled | default(true) | lower }}
  metrics_port: {{ metrics_port | default(9090) }}
  health_check_interval: !duration "{{ health_check_interval | default('30s') }}"
  
  prometheus:
    enabled: {{ prometheus_enabled | default(false) | lower }}
    endpoint: "{{ prometheus_endpoint | default('/metrics') }}"
  
  logging:
    file_path: "{{ log_file_path | default('/var/log/vpn-manager/app.log') }}"
    max_size: !file_size "{{ log_max_size | default('100MB') }}"
    backup_count: {{ log_backup_count | default(5) }}
    format: "{{ log_format | default('%(asctime)s - %(name)s - %(levelname)s - %(message)s') }}"

# User interface settings
ui:
  theme: "{{ ui_theme | default('dark') }}"
  language: "{{ ui_language | default('en') }}"
  
  tui:
    refresh_rate: {{ tui_refresh_rate | default(10) }}
    mouse_support: {{ tui_mouse_support | default(true) | lower }}
    shortcuts_enabled: {{ tui_shortcuts_enabled | default(true) | lower }}

# Paths configuration
paths:
  config_dir: "{{ config_dir | default('~/.config/vpn-manager') }}"
  data_dir: "{{ data_dir | default('~/.local/share/vpn-manager') }}"
  cache_dir: "{{ cache_dir | default('~/.cache/vpn-manager') }}"
  templates_dir: "{{ templates_dir | default('~/.config/vpn-manager/templates') }}"
  backup_dir: "{{ backup_dir | default('~/.local/share/vpn-manager/backups') }}"

# Protocol-specific configurations
protocols:
  vless:
    enabled: {{ vless_enabled | default(true) | lower }}
    reality:
      enabled: {{ vless_reality_enabled | default(true) | lower }}
      dest: "{{ vless_reality_dest | default('example.com:443') }}"
      server_names:
        - "{{ vless_server_name | default('example.com') }}"
    
  shadowsocks:
    enabled: {{ shadowsocks_enabled | default(true) | lower }}
    method: "{{ shadowsocks_method | default('aes-256-gcm') }}"
    timeout: !duration "{{ shadowsocks_timeout | default('60s') }}"
    
  wireguard:
    enabled: {{ wireguard_enabled | default(true) | lower }}
    interface: "{{ wireguard_interface | default('wg0') }}"
    private_key_path: "{{ wireguard_private_key | default('/etc/wireguard/private.key') }}"
    
  proxy:
    http:
      enabled: {{ http_proxy_enabled | default(true) | lower }}
      authentication: {{ http_proxy_auth | default(false) | lower }}
    
    socks5:
      enabled: {{ socks5_proxy_enabled | default(true) | lower }}
      authentication: {{ socks5_proxy_auth | default(false) | lower }}

# Environment-specific overrides
{% if environment == 'development' -%}
# Development environment overrides
app:
  debug: true
  log_level: "DEBUG"

database:
  path: "./dev_vpn.db"

docker:
  auto_remove: true

monitoring:
  health_check_interval: !duration "10s"
{% endif %}

{% if environment == 'production' -%}
# Production environment overrides
app:
  debug: false
  log_level: "INFO"

security:
  authentication:
    required: true
  
  tls:
    enabled: true
    auto_generate: false

monitoring:
  enabled: true
  prometheus:
    enabled: true
{% endif %}
"""

    manager.create_template(
        "base_config",
        base_config_template,
        "Base VPN Manager configuration with all sections and environment support"
    )

    # User preset template
    user_preset_template = """# User Preset Configuration
# Template for creating user-defined presets

preset:
  name: "{{ preset_name }}"
  description: "{{ preset_description | default('Custom user preset') }}"
  version: "{{ preset_version | default('1.0.0') }}"
  created_by: "{{ created_by | default('user') }}"
  created_at: "{{ created_at | default(now()) }}"

# User configuration
users:
  {% for user in users -%}
  - username: "{{ user.username }}"
    protocol: !protocol "{{ user.protocol | default('vless') }}"
    {% if user.email -%}
    email: "{{ user.email }}"
    {% endif -%}
    {% if user.expiry_days -%}
    expires_in: !duration "{{ user.expiry_days }}d"
    {% endif -%}
    traffic_limit: {{ user.traffic_limit | default('unlimited') }}
    active: {{ user.active | default(true) | lower }}
    
    # Protocol-specific settings
    {% if user.protocol == 'vless' -%}
    vless:
      uuid: "{{ user.uuid | default(uuid4()) }}"
      flow: "{{ user.flow | default('xtls-rprx-vision') }}"
    {% elif user.protocol == 'shadowsocks' -%}
    shadowsocks:
      password: "{{ user.password | default(random_password()) }}"
      method: "{{ user.method | default('aes-256-gcm') }}"
    {% elif user.protocol == 'wireguard' -%}
    wireguard:
      private_key: "{{ user.private_key | default(generate_wg_key()) }}"
      public_key: "{{ user.public_key | default(derive_wg_public(user.private_key)) }}"
      allowed_ips: "{{ user.allowed_ips | default('0.0.0.0/0, ::/0') }}"
    {% endif %}
  {% endfor %}

# Server configuration for this preset
servers:
  {% for server in servers -%}
  - name: "{{ server.name }}"
    protocol: !protocol "{{ server.protocol }}"
    port: {{ server.port }}
    {% if server.domain -%}
    domain: "{{ server.domain }}"
    {% endif -%}
    auto_start: {{ server.auto_start | default(true) | lower }}
    
    # Resource limits
    resources:
      memory: "{{ server.memory | default('512MB') }}"
      cpu_limit: "{{ server.cpu_limit | default('1.0') }}"
      
    # Protocol-specific server settings
    {% if server.protocol == 'vless' -%}
    vless:
      reality:
        enabled: {{ server.reality_enabled | default(true) | lower }}
        dest: "{{ server.reality_dest | default('example.com:443') }}"
        server_names:
          - "{{ server.server_name | default('example.com') }}"
    {% endif %}
  {% endfor %}

# Network configuration for this preset
network:
  isolation: {{ network_isolation | default(true) | lower }}
  custom_routes:
    {% for route in custom_routes -%}
    - destination: "{{ route.destination }}"
      gateway: "{{ route.gateway }}"
      {% if route.metric -%}
      metric: {{ route.metric }}
      {% endif %}
    {% endfor %}

# Monitoring settings for this preset
monitoring:
  alerts:
    {% for alert in alerts -%}
    - name: "{{ alert.name }}"
      condition: "{{ alert.condition }}"
      threshold: {{ alert.threshold }}
      action: "{{ alert.action | default('notify') }}"
    {% endfor %}
"""

    manager.create_template(
        "user_preset",
        user_preset_template,
        "Template for user-defined presets with users, servers, and monitoring"
    )

    # Server configuration template
    server_config_template = """# Server Configuration Template
# Template for individual VPN server configurations

server:
  name: "{{ server_name }}"
  description: "{{ server_description | default('VPN Server') }}"
  protocol: !protocol "{{ protocol }}"
  
  # Network configuration
  network:
    port: {{ port }}
    bind_address: "{{ bind_address | default('0.0.0.0') }}"
    {% if domain -%}
    domain: "{{ domain }}"
    {% endif -%}
    {% if ipv6_enabled -%}
    ipv6: {{ ipv6_enabled | lower }}
    {% endif %}
  
  # Security settings
  security:
    {% if protocol == 'vless' -%}
    # VLESS with Reality configuration
    reality:
      enabled: {{ reality_enabled | default(true) | lower }}
      dest: "{{ reality_dest | default('example.com:443') }}"
      server_names:
        {% for name in server_names -%}
        - "{{ name }}"
        {% endfor %}
      private_key: !env { name: "VLESS_PRIVATE_KEY", default: "" }
      public_key: !env { name: "VLESS_PUBLIC_KEY", default: "" }
    
    # Transport settings
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
    
    {% elif protocol == 'shadowsocks' -%}
    # Shadowsocks configuration
    method: "{{ ss_method | default('aes-256-gcm') }}"
    password: !env { name: "SS_PASSWORD", default: "{{ ss_password | default(random_password()) }}" }
    timeout: !duration "{{ ss_timeout | default('60s') }}"
    
    # Plugin settings
    {% if ss_plugin -%}
    plugin:
      name: "{{ ss_plugin }}"
      options: "{{ ss_plugin_options | default('') }}"
    {% endif %}
    
    {% elif protocol == 'wireguard' -%}
    # WireGuard configuration
    interface: "{{ wg_interface | default('wg0') }}"
    private_key: !env { name: "WG_PRIVATE_KEY", default: "" }
    public_key: !env { name: "WG_PUBLIC_KEY", default: "" }
    
    # Peer configuration
    peers:
      {% for peer in peers -%}
      - public_key: "{{ peer.public_key }}"
        allowed_ips: "{{ peer.allowed_ips | default('0.0.0.0/0, ::/0') }}"
        {% if peer.endpoint -%}
        endpoint: "{{ peer.endpoint }}"
        {% endif -%}
        {% if peer.persistent_keepalive -%}
        persistent_keepalive: {{ peer.persistent_keepalive }}
        {% endif %}
      {% endfor %}
    
    {% elif protocol in ['http', 'socks5'] -%}
    # Proxy configuration
    authentication:
      enabled: {{ proxy_auth_enabled | default(false) | lower }}
      {% if proxy_auth_enabled -%}
      users:
        {% for user in proxy_users -%}
        - username: "{{ user.username }}"
          password: "{{ user.password }}"
        {% endfor %}
      {% endif %}
    
    # Access control
    {% if proxy_acl -%}
    access_control:
      {% for rule in proxy_acl -%}
      - action: "{{ rule.action }}"
        source: "{{ rule.source }}"
        {% if rule.destination -%}
        destination: "{{ rule.destination }}"
        {% endif %}
      {% endfor %}
    {% endif %}
    {% endif %}
  
  # Docker configuration
  docker:
    image: "{{ docker_image }}"
    {% if docker_tag -%}
    tag: "{{ docker_tag }}"
    {% endif -%}
    restart_policy: "{{ restart_policy | default('unless-stopped') }}"
    
    # Resource limits
    resources:
      memory: "{{ memory_limit | default('512MB') }}"
      cpu_limit: "{{ cpu_limit | default('1.0') }}"
      {% if cpu_reservation -%}
      cpu_reservation: "{{ cpu_reservation }}"
      {% endif -%}
      {% if memory_reservation -%}
      memory_reservation: "{{ memory_reservation }}"
      {% endif %}
    
    # Environment variables
    environment:
      {% for key, value in environment_vars.items() -%}
      {{ key }}: "{{ value }}"
      {% endfor %}
    
    # Volume mounts
    volumes:
      {% for volume in volumes -%}
      - host_path: "{{ volume.host_path }}"
        container_path: "{{ volume.container_path }}"
        {% if volume.read_only -%}
        read_only: {{ volume.read_only | lower }}
        {% endif %}
      {% endfor %}
    
    # Port mappings
    ports:
      {% for port_map in port_mappings -%}
      - host_port: {{ port_map.host_port }}
        container_port: {{ port_map.container_port }}
        {% if port_map.protocol -%}
        protocol: "{{ port_map.protocol }}"
        {% endif %}
      {% endfor %}
  
  # Health checks
  health_check:
    enabled: {{ health_check_enabled | default(true) | lower }}
    interval: !duration "{{ health_check_interval | default('30s') }}"
    timeout: !duration "{{ health_check_timeout | default('10s') }}"
    retries: {{ health_check_retries | default(3) }}
    {% if health_check_command -%}
    command: "{{ health_check_command }}"
    {% endif %}
  
  # Logging configuration
  logging:
    level: "{{ log_level | default('INFO') }}"
    {% if log_file -%}
    file: "{{ log_file }}"
    {% endif -%}
    {% if log_max_size -%}
    max_size: !file_size "{{ log_max_size }}"
    {% endif -%}
    format: "{{ log_format | default('json') }}"
  
  # Monitoring and metrics
  monitoring:
    metrics_enabled: {{ metrics_enabled | default(true) | lower }}
    {% if metrics_port -%}
    metrics_port: {{ metrics_port }}
    {% endif -%}
    
    # Custom metrics
    custom_metrics:
      {% for metric in custom_metrics -%}
      - name: "{{ metric.name }}"
        type: "{{ metric.type }}"
        description: "{{ metric.description }}"
        {% if metric.labels -%}
        labels:
          {% for label in metric.labels -%}
          - "{{ label }}"
          {% endfor %}
        {% endif %}
      {% endfor %}
"""

    manager.create_template(
        "server_config",
        server_config_template,
        "Template for individual VPN server configurations with protocol-specific settings"
    )

    console.print("[green]✓ Default YAML templates created successfully[/green]")


if __name__ == "__main__":
    # Create default templates when module is run directly
    create_default_templates()
