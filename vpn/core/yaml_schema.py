"""
YAML schema validation system for VPN Manager.

This module provides comprehensive YAML schema validation using Pydantic models
and JSON Schema generation for YAML configuration files.
"""

import json
import jsonschema
from pathlib import Path
from typing import Dict, Any, List, Optional, Union, Type, get_origin, get_args
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field, create_model, ValidationError
from pydantic.json_schema import GenerateJsonSchema, JsonSchemaValue
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

console = Console()


class ProtocolType(str, Enum):
    """Supported VPN protocols."""
    VLESS = "vless"
    SHADOWSOCKS = "shadowsocks"
    WIREGUARD = "wireguard"
    HTTP = "http"
    SOCKS5 = "socks5"
    UNIFIED_PROXY = "unified_proxy"


class LogLevel(str, Enum):
    """Supported log levels."""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class ThemeType(str, Enum):
    """Supported UI themes."""
    DARK = "dark"
    LIGHT = "light"
    AUTO = "auto"


class PresetCategory(str, Enum):
    """Preset categories."""
    VPN = "vpn"
    PROXY = "proxy"
    SECURITY = "security"
    PERFORMANCE = "performance"


class PresetScope(str, Enum):
    """Preset scopes."""
    GLOBAL = "global"
    USER = "user"
    PROJECT = "project"


@dataclass
class ValidationResult:
    """Result of YAML schema validation."""
    is_valid: bool
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    schema_version: Optional[str] = None
    validated_data: Optional[Dict[str, Any]] = None
    
    @property
    def has_errors(self) -> bool:
        """Check if validation has errors."""
        return len(self.errors) > 0
    
    @property
    def has_warnings(self) -> bool:
        """Check if validation has warnings."""
        return len(self.warnings) > 0


# Pydantic models for YAML schema validation

class AppConfig(BaseModel):
    """Application configuration schema."""
    name: str = Field(default="VPN Manager", description="Application name")
    version: str = Field(default="1.0.0", description="Application version")
    debug: bool = Field(default=False, description="Enable debug mode")
    log_level: LogLevel = Field(default=LogLevel.INFO, description="Logging level")


class DatabaseConfig(BaseModel):
    """Database configuration schema."""
    type: str = Field(default="sqlite", pattern=r"^(sqlite|postgresql|mysql)$", description="Database type")
    path: Optional[str] = Field(default=None, description="SQLite database file path")
    host: Optional[str] = Field(default=None, description="Database host")
    port: Optional[int] = Field(default=None, ge=1, le=65535, description="Database port")
    name: Optional[str] = Field(default=None, description="Database name")
    user: Optional[str] = Field(default=None, description="Database user")
    password: Optional[str] = Field(default=None, description="Database password")
    pool_size: int = Field(default=10, ge=1, le=100, description="Connection pool size")
    max_overflow: int = Field(default=20, ge=0, le=100, description="Maximum pool overflow")


class DockerConfig(BaseModel):
    """Docker configuration schema."""
    host: str = Field(default="unix:///var/run/docker.sock", description="Docker host")
    timeout: int = Field(default=30, ge=1, le=300, description="Docker timeout in seconds")
    auto_remove: bool = Field(default=True, description="Auto-remove containers")
    restart_policy: str = Field(
        default="unless-stopped",
        pattern=r"^(no|on-failure|always|unless-stopped)$",
        description="Container restart policy"
    )
    network_name: str = Field(default="vpn-network", description="Docker network name")


class PortRange(BaseModel):
    """Port range configuration."""
    start: int = Field(ge=1, le=65535, description="Start port")
    end: int = Field(ge=1, le=65535, description="End port")
    
    def model_post_init(self, __context: Any) -> None:
        """Validate port range."""
        if self.start > self.end:
            raise ValueError("Start port must be less than or equal to end port")


class NetworkConfig(BaseModel):
    """Network configuration schema."""
    bind_address: str = Field(default="0.0.0.0", pattern=r"^(\d{1,3}\.){3}\d{1,3}$", description="Bind address")
    ports: Dict[str, Union[int, PortRange]] = Field(default_factory=dict, description="Port mappings")
    dns_servers: List[str] = Field(default_factory=lambda: ["1.1.1.1", "8.8.8.8"], description="DNS servers")


class TLSConfig(BaseModel):
    """TLS configuration schema."""
    enabled: bool = Field(default=True, description="Enable TLS")
    cert_path: str = Field(default="/etc/ssl/certs/vpn.crt", description="Certificate file path")
    key_path: str = Field(default="/etc/ssl/private/vpn.key", description="Private key file path")
    auto_generate: bool = Field(default=True, description="Auto-generate certificates")


class AuthenticationConfig(BaseModel):
    """Authentication configuration schema."""
    required: bool = Field(default=False, description="Require authentication")
    method: str = Field(default="token", pattern=r"^(token|basic|oauth)$", description="Authentication method")
    token_expiry: int = Field(default=86400, ge=300, le=604800, description="Token expiry in seconds")


class RateLimitConfig(BaseModel):
    """Rate limiting configuration schema."""
    enabled: bool = Field(default=True, description="Enable rate limiting")
    max_requests: int = Field(default=100, ge=1, le=10000, description="Maximum requests per window")
    window: int = Field(default=3600, ge=60, le=86400, description="Rate limit window in seconds")


class SecurityConfig(BaseModel):
    """Security configuration schema."""
    tls: TLSConfig = Field(default_factory=TLSConfig, description="TLS configuration")
    authentication: AuthenticationConfig = Field(default_factory=AuthenticationConfig, description="Authentication config")
    rate_limiting: RateLimitConfig = Field(default_factory=RateLimitConfig, description="Rate limiting config")


class PrometheusConfig(BaseModel):
    """Prometheus monitoring configuration."""
    enabled: bool = Field(default=False, description="Enable Prometheus metrics")
    endpoint: str = Field(default="/metrics", description="Metrics endpoint")


class LoggingConfig(BaseModel):
    """Logging configuration schema."""
    file_path: str = Field(default="/var/log/vpn-manager/app.log", description="Log file path")
    max_size: str = Field(default="100MB", pattern=r"^\d+(\.\d+)?(B|KB|MB|GB)$", description="Maximum log file size")
    backup_count: int = Field(default=5, ge=1, le=50, description="Number of backup log files")
    format: str = Field(
        default="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        description="Log format string"
    )


class MonitoringConfig(BaseModel):
    """Monitoring configuration schema."""
    enabled: bool = Field(default=True, description="Enable monitoring")
    metrics_port: int = Field(default=9090, ge=1024, le=65535, description="Metrics port")
    health_check_interval: int = Field(default=30, ge=5, le=300, description="Health check interval in seconds")
    prometheus: PrometheusConfig = Field(default_factory=PrometheusConfig, description="Prometheus configuration")
    logging: LoggingConfig = Field(default_factory=LoggingConfig, description="Logging configuration")


class TUIConfig(BaseModel):
    """TUI configuration schema."""
    refresh_rate: int = Field(default=10, ge=1, le=60, description="TUI refresh rate")
    mouse_support: bool = Field(default=True, description="Enable mouse support")
    shortcuts_enabled: bool = Field(default=True, description="Enable keyboard shortcuts")


class UIConfig(BaseModel):
    """UI configuration schema."""
    theme: ThemeType = Field(default=ThemeType.DARK, description="UI theme")
    language: str = Field(default="en", pattern=r"^[a-z]{2}$", description="UI language")
    tui: TUIConfig = Field(default_factory=TUIConfig, description="TUI-specific configuration")


class PathsConfig(BaseModel):
    """Paths configuration schema."""
    config_dir: str = Field(default="~/.config/vpn-manager", description="Configuration directory")
    data_dir: str = Field(default="~/.local/share/vpn-manager", description="Data directory")
    cache_dir: str = Field(default="~/.cache/vpn-manager", description="Cache directory")
    templates_dir: str = Field(default="~/.config/vpn-manager/templates", description="Templates directory")
    backup_dir: str = Field(default="~/.local/share/vpn-manager/backups", description="Backup directory")


class VLESSRealityConfig(BaseModel):
    """VLESS Reality configuration."""
    enabled: bool = Field(default=True, description="Enable Reality")
    dest: str = Field(default="example.com:443", description="Reality destination")
    server_names: List[str] = Field(default_factory=lambda: ["example.com"], description="Server names")


class VLESSConfig(BaseModel):
    """VLESS protocol configuration."""
    enabled: bool = Field(default=True, description="Enable VLESS protocol")
    reality: VLESSRealityConfig = Field(default_factory=VLESSRealityConfig, description="Reality configuration")


class ShadowsocksConfig(BaseModel):
    """Shadowsocks protocol configuration."""
    enabled: bool = Field(default=True, description="Enable Shadowsocks protocol")
    method: str = Field(
        default="aes-256-gcm",
        pattern=r"^(aes-128-gcm|aes-256-gcm|chacha20-ietf-poly1305)$",
        description="Encryption method"
    )
    timeout: int = Field(default=60, ge=10, le=300, description="Connection timeout in seconds")


class WireGuardConfig(BaseModel):
    """WireGuard protocol configuration."""
    enabled: bool = Field(default=True, description="Enable WireGuard protocol")
    interface: str = Field(default="wg0", pattern=r"^wg\d+$", description="WireGuard interface name")
    private_key_path: str = Field(default="/etc/wireguard/private.key", description="Private key file path")


class HTTPProxyConfig(BaseModel):
    """HTTP proxy configuration."""
    enabled: bool = Field(default=True, description="Enable HTTP proxy")
    authentication: bool = Field(default=False, description="Require authentication")


class SOCKS5ProxyConfig(BaseModel):
    """SOCKS5 proxy configuration."""
    enabled: bool = Field(default=True, description="Enable SOCKS5 proxy")
    authentication: bool = Field(default=False, description="Require authentication")


class ProxyConfig(BaseModel):
    """Proxy configuration schema."""
    http: HTTPProxyConfig = Field(default_factory=HTTPProxyConfig, description="HTTP proxy configuration")
    socks5: SOCKS5ProxyConfig = Field(default_factory=SOCKS5ProxyConfig, description="SOCKS5 proxy configuration")


class ProtocolsConfig(BaseModel):
    """Protocols configuration schema."""
    vless: VLESSConfig = Field(default_factory=VLESSConfig, description="VLESS configuration")
    shadowsocks: ShadowsocksConfig = Field(default_factory=ShadowsocksConfig, description="Shadowsocks configuration")
    wireguard: WireGuardConfig = Field(default_factory=WireGuardConfig, description="WireGuard configuration")
    proxy: ProxyConfig = Field(default_factory=ProxyConfig, description="Proxy configuration")


class VPNConfigSchema(BaseModel):
    """Complete VPN Manager configuration schema."""
    app: AppConfig = Field(default_factory=AppConfig, description="Application configuration")
    database: DatabaseConfig = Field(default_factory=DatabaseConfig, description="Database configuration")
    docker: DockerConfig = Field(default_factory=DockerConfig, description="Docker configuration")
    network: NetworkConfig = Field(default_factory=NetworkConfig, description="Network configuration")
    security: SecurityConfig = Field(default_factory=SecurityConfig, description="Security configuration")
    monitoring: MonitoringConfig = Field(default_factory=MonitoringConfig, description="Monitoring configuration")
    ui: UIConfig = Field(default_factory=UIConfig, description="UI configuration")
    paths: PathsConfig = Field(default_factory=PathsConfig, description="Paths configuration")
    protocols: ProtocolsConfig = Field(default_factory=ProtocolsConfig, description="Protocols configuration")
    
    class Config:
        """Pydantic configuration."""
        extra = "forbid"  # Disallow extra fields
        validate_assignment = True
        use_enum_values = True


# User preset schemas

class UserConfig(BaseModel):
    """User configuration in preset."""
    username: str = Field(min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_-]+$", description="Username")
    protocol: ProtocolType = Field(description="VPN protocol")
    email: Optional[str] = Field(default=None, pattern=r"^[^@]+@[^@]+\.[^@]+$", description="User email")
    expires_in: Optional[int] = Field(default=None, ge=3600, description="Expiry time in seconds")
    traffic_limit: Union[str, int] = Field(default="unlimited", description="Traffic limit")
    active: bool = Field(default=True, description="User is active")
    
    # Protocol-specific configurations
    vless: Optional[Dict[str, Any]] = Field(default=None, description="VLESS-specific configuration")
    shadowsocks: Optional[Dict[str, Any]] = Field(default=None, description="Shadowsocks-specific configuration")
    wireguard: Optional[Dict[str, Any]] = Field(default=None, description="WireGuard-specific configuration")


class ServerConfig(BaseModel):
    """Server configuration in preset."""
    name: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$", description="Server name")
    protocol: ProtocolType = Field(description="Server protocol")
    port: int = Field(ge=1024, le=65535, description="Server port")
    domain: Optional[str] = Field(default=None, description="Server domain")
    auto_start: bool = Field(default=True, description="Auto-start server")
    
    # Resource configuration
    resources: Optional[Dict[str, Any]] = Field(default=None, description="Resource limits")
    
    # Protocol-specific configurations
    vless: Optional[Dict[str, Any]] = Field(default=None, description="VLESS server configuration")
    shadowsocks: Optional[Dict[str, Any]] = Field(default=None, description="Shadowsocks server configuration")
    wireguard: Optional[Dict[str, Any]] = Field(default=None, description="WireGuard server configuration")


class NetworkRoute(BaseModel):
    """Network route configuration."""
    destination: str = Field(description="Route destination")
    gateway: str = Field(description="Route gateway")
    metric: Optional[int] = Field(default=None, ge=1, le=1000, description="Route metric")


class AlertConfig(BaseModel):
    """Alert configuration."""
    name: str = Field(min_length=1, max_length=100, description="Alert name")
    condition: str = Field(description="Alert condition")
    threshold: Union[int, float] = Field(description="Alert threshold")
    action: str = Field(default="notify", description="Alert action")


class PresetNetworkConfig(BaseModel):
    """Network configuration for preset."""
    isolation: bool = Field(default=True, description="Network isolation")
    custom_routes: List[NetworkRoute] = Field(default_factory=list, description="Custom routes")


class PresetMonitoringConfig(BaseModel):
    """Monitoring configuration for preset."""
    alerts: List[AlertConfig] = Field(default_factory=list, description="Alert configurations")


class PresetMetadata(BaseModel):
    """Preset metadata."""
    name: str = Field(min_length=1, max_length=100, description="Preset name")
    description: str = Field(default="Custom user preset", description="Preset description")
    version: str = Field(default="1.0.0", pattern=r"^\d+\.\d+\.\d+$", description="Preset version")
    created_by: str = Field(default="user", description="Preset creator")
    created_at: str = Field(default_factory=lambda: datetime.now().isoformat(), description="Creation timestamp")


class UserPresetSchema(BaseModel):
    """User preset configuration schema."""
    preset: PresetMetadata = Field(description="Preset metadata")
    users: List[UserConfig] = Field(default_factory=list, description="User configurations")
    servers: List[ServerConfig] = Field(default_factory=list, description="Server configurations")
    network: PresetNetworkConfig = Field(default_factory=PresetNetworkConfig, description="Network configuration")
    monitoring: PresetMonitoringConfig = Field(default_factory=PresetMonitoringConfig, description="Monitoring configuration")
    
    class Config:
        """Pydantic configuration."""
        extra = "forbid"
        validate_assignment = True


# Server configuration schema

class ResourceLimits(BaseModel):
    """Resource limits configuration."""
    memory: str = Field(default="512MB", pattern=r"^\d+(\.\d+)?(MB|GB)$", description="Memory limit")
    cpu_limit: str = Field(default="1.0", pattern=r"^\d+(\.\d+)?$", description="CPU limit")
    cpu_reservation: Optional[str] = Field(default=None, pattern=r"^\d+(\.\d+)?$", description="CPU reservation")
    memory_reservation: Optional[str] = Field(default=None, pattern=r"^\d+(\.\d+)?(MB|GB)$", description="Memory reservation")


class VolumeMount(BaseModel):
    """Volume mount configuration."""
    host_path: str = Field(description="Host path")
    container_path: str = Field(description="Container path")
    read_only: bool = Field(default=False, description="Read-only mount")


class PortMapping(BaseModel):
    """Port mapping configuration."""
    host_port: int = Field(ge=1, le=65535, description="Host port")
    container_port: int = Field(ge=1, le=65535, description="Container port")
    protocol: str = Field(default="tcp", pattern=r"^(tcp|udp)$", description="Protocol")


class DockerServerConfig(BaseModel):
    """Docker configuration for server."""
    image: str = Field(description="Docker image")
    tag: Optional[str] = Field(default=None, description="Image tag")
    restart_policy: str = Field(default="unless-stopped", description="Restart policy")
    resources: ResourceLimits = Field(default_factory=ResourceLimits, description="Resource limits")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment variables")
    volumes: List[VolumeMount] = Field(default_factory=list, description="Volume mounts")
    ports: List[PortMapping] = Field(default_factory=list, description="Port mappings")


class HealthCheckConfig(BaseModel):
    """Health check configuration."""
    enabled: bool = Field(default=True, description="Enable health checks")
    interval: int = Field(default=30, ge=5, le=300, description="Health check interval in seconds")
    timeout: int = Field(default=10, ge=1, le=60, description="Health check timeout in seconds")
    retries: int = Field(default=3, ge=1, le=10, description="Health check retries")
    command: Optional[str] = Field(default=None, description="Health check command")


class MetricConfig(BaseModel):
    """Custom metric configuration."""
    name: str = Field(description="Metric name")
    type: str = Field(pattern=r"^(counter|gauge|histogram|summary)$", description="Metric type")
    description: str = Field(description="Metric description")
    labels: List[str] = Field(default_factory=list, description="Metric labels")


class ServerMonitoringConfig(BaseModel):
    """Server monitoring configuration."""
    metrics_enabled: bool = Field(default=True, description="Enable metrics")
    metrics_port: Optional[int] = Field(default=None, ge=1024, le=65535, description="Metrics port")
    custom_metrics: List[MetricConfig] = Field(default_factory=list, description="Custom metrics")


class ServerConfigSchema(BaseModel):
    """Individual server configuration schema."""
    server: Dict[str, Any] = Field(description="Server configuration")
    
    class Config:
        """Pydantic configuration."""
        extra = "allow"  # Allow extra fields for flexibility


class YamlSchemaValidator:
    """YAML schema validator using Pydantic models."""
    
    def __init__(self):
        """Initialize schema validator."""
        self.schemas = {
            "config": VPNConfigSchema,
            "user_preset": UserPresetSchema,
            "server_config": ServerConfigSchema,
        }
        self.generated_schemas: Dict[str, Dict[str, Any]] = {}
    
    def validate_yaml_data(
        self,
        data: Dict[str, Any],
        schema_type: str = "config"
    ) -> ValidationResult:
        """
        Validate YAML data against schema.
        
        Args:
            data: YAML data to validate
            schema_type: Type of schema (config, user_preset, server_config)
        """
        result = ValidationResult(is_valid=False)
        
        if schema_type not in self.schemas:
            result.errors.append(f"Unknown schema type: {schema_type}")
            return result
        
        schema_model = self.schemas[schema_type]
        
        try:
            # Validate with Pydantic
            validated_instance = schema_model(**data)
            result.validated_data = validated_instance.model_dump()
            result.is_valid = True
            result.schema_version = getattr(schema_model, '__version__', '1.0.0')
            
        except ValidationError as e:
            for error in e.errors():
                field_path = ' -> '.join(str(loc) for loc in error['loc'])
                result.errors.append(f"Field '{field_path}': {error['msg']}")
        except Exception as e:
            result.errors.append(f"Validation error: {e}")
        
        return result
    
    def generate_json_schema(self, schema_type: str = "config") -> Dict[str, Any]:
        """Generate JSON schema for YAML validation."""
        if schema_type not in self.schemas:
            raise ValueError(f"Unknown schema type: {schema_type}")
        
        if schema_type in self.generated_schemas:
            return self.generated_schemas[schema_type]
        
        schema_model = self.schemas[schema_type]
        json_schema = schema_model.model_json_schema()
        
        # Add custom properties
        json_schema["$schema"] = "http://json-schema.org/draft-07/schema#"
        json_schema["title"] = f"VPN Manager {schema_type.replace('_', ' ').title()} Schema"
        json_schema["description"] = f"Schema for VPN Manager {schema_type} YAML files"
        
        self.generated_schemas[schema_type] = json_schema
        return json_schema
    
    def save_json_schema(self, schema_type: str, output_path: Path) -> bool:
        """Save JSON schema to file."""
        try:
            schema = self.generate_json_schema(schema_type)
            
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(schema, f, indent=2)
            
            return True
        except Exception as e:
            console.print(f"[red]Error saving schema: {e}[/red]")
            return False
    
    def validate_with_jsonschema(
        self,
        data: Dict[str, Any],
        schema_type: str = "config"
    ) -> ValidationResult:
        """Validate using JSON Schema (alternative to Pydantic)."""
        result = ValidationResult(is_valid=False)
        
        try:
            schema = self.generate_json_schema(schema_type)
            jsonschema.validate(data, schema)
            
            result.is_valid = True
            result.validated_data = data
            result.schema_version = schema.get('version', '1.0.0')
            
        except jsonschema.ValidationError as e:
            result.errors.append(f"Schema validation error: {e.message}")
            if e.absolute_path:
                path = ' -> '.join(str(p) for p in e.absolute_path)
                result.errors[-1] = f"Field '{path}': {e.message}"
        except jsonschema.SchemaError as e:
            result.errors.append(f"Schema error: {e.message}")
        except Exception as e:
            result.errors.append(f"Validation error: {e}")
        
        return result
    
    def get_schema_documentation(self, schema_type: str = "config") -> str:
        """Generate documentation for schema."""
        if schema_type not in self.schemas:
            return f"Unknown schema type: {schema_type}"
        
        schema_model = self.schemas[schema_type]
        schema = self.generate_json_schema(schema_type)
        
        # Generate markdown documentation
        docs = f"# {schema['title']}\n\n"
        docs += f"{schema['description']}\n\n"
        
        def document_properties(properties: Dict[str, Any], level: int = 2) -> str:
            """Document schema properties recursively."""
            doc = ""
            
            for prop_name, prop_schema in properties.items():
                doc += "#" * level + f" {prop_name}\n\n"
                
                if 'description' in prop_schema:
                    doc += f"{prop_schema['description']}\n\n"
                
                if 'type' in prop_schema:
                    doc += f"**Type:** `{prop_schema['type']}`\n\n"
                
                if 'default' in prop_schema:
                    doc += f"**Default:** `{prop_schema['default']}`\n\n"
                
                if 'enum' in prop_schema:
                    doc += f"**Allowed values:** {', '.join(f'`{v}`' for v in prop_schema['enum'])}\n\n"
                
                if 'pattern' in prop_schema:
                    doc += f"**Pattern:** `{prop_schema['pattern']}`\n\n"
                
                if 'minimum' in prop_schema or 'maximum' in prop_schema:
                    min_val = prop_schema.get('minimum', 'none')
                    max_val = prop_schema.get('maximum', 'none')
                    doc += f"**Range:** {min_val} to {max_val}\n\n"
                
                # Handle nested objects
                if prop_schema.get('type') == 'object' and 'properties' in prop_schema:
                    doc += document_properties(prop_schema['properties'], level + 1)
                
                doc += "\n"
            
            return doc
        
        if 'properties' in schema:
            docs += document_properties(schema['properties'])
        
        return docs
    
    def show_schema_info(self, schema_type: str = "config") -> None:
        """Display schema information in a formatted table."""
        if schema_type not in self.schemas:
            console.print(f"[red]Unknown schema type: {schema_type}[/red]")
            return
        
        schema_model = self.schemas[schema_type]
        schema = self.generate_json_schema(schema_type)
        
        # Create info panel
        info_text = f"[bold]{schema['title']}[/bold]\n"
        info_text += f"{schema['description']}\n\n"
        info_text += f"[blue]Schema Type:[/blue] {schema_type}\n"
        info_text += f"[blue]Model:[/blue] {schema_model.__name__}\n"
        
        if 'properties' in schema:
            info_text += f"[blue]Fields:[/blue] {len(schema['properties'])}\n"
        
        console.print(Panel(info_text, title="Schema Information"))
        
        # Create fields table
        if 'properties' in schema:
            table = Table(title="Schema Fields")
            table.add_column("Field", style="cyan", width=20)
            table.add_column("Type", style="green", width=15)
            table.add_column("Required", justify="center", width=10)
            table.add_column("Description", style="dim")
            
            required_fields = set(schema.get('required', []))
            
            for field_name, field_schema in schema['properties'].items():
                field_type = field_schema.get('type', 'unknown')
                is_required = "✓" if field_name in required_fields else ""
                description = field_schema.get('description', '')
                
                # Truncate long descriptions
                if len(description) > 50:
                    description = description[:47] + "..."
                
                table.add_row(field_name, field_type, is_required, description)
            
            console.print(table)


# Global schema validator instance
yaml_schema_validator = YamlSchemaValidator()


def validate_yaml_config(data: Dict[str, Any], schema_type: str = "config") -> ValidationResult:
    """Convenience function to validate YAML configuration."""
    return yaml_schema_validator.validate_yaml_data(data, schema_type)


def generate_config_schema(schema_type: str = "config") -> Dict[str, Any]:
    """Convenience function to generate JSON schema."""
    return yaml_schema_validator.generate_json_schema(schema_type)


def save_schema_file(schema_type: str, output_path: Path) -> bool:
    """Convenience function to save schema to file."""
    return yaml_schema_validator.save_json_schema(schema_type, output_path)


if __name__ == "__main__":
    # Generate and save all schemas when module is run directly
    schema_dir = Path(__file__).parent.parent / "schemas"
    schema_dir.mkdir(exist_ok=True)
    
    for schema_type in yaml_schema_validator.schemas.keys():
        output_path = schema_dir / f"{schema_type}_schema.json"
        if save_schema_file(schema_type, output_path):
            console.print(f"[green]✓ Generated schema: {output_path}[/green]")
        else:
            console.print(f"[red]✗ Failed to generate schema: {output_path}[/red]")
    
    # Display schema info
    for schema_type in yaml_schema_validator.schemas.keys():
        yaml_schema_validator.show_schema_info(schema_type)
        console.print("\n" + "="*80 + "\n")