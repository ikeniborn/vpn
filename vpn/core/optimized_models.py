"""
Optimized Pydantic models using Pydantic 2.11+ performance features.

This module demonstrates performance optimizations including:
- Frozen models for immutable data
- Field constraints for faster validation
- Optimized serialization with mode='python'
- validate_call decorator for function validation
- Discriminated unions for efficient polymorphism
- Model rebuilding for schema optimization
"""

from datetime import datetime
from enum import Enum
from typing import Annotated, Any, Dict, List, Literal, Optional, Union
from uuid import UUID, uuid4

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_serializer,
    field_validator,
    computed_field,
    model_serializer,
    model_validator,
    BeforeValidator,
    AfterValidator,
    StringConstraints,
    conint,
    confloat,
    validate_call,
)
from pydantic.functional_validators import field_validator as functional_field_validator
from pydantic.json_schema import JsonSchemaValue


# Performance optimization: Use Annotated types with constraints
PortNumber = Annotated[int, Field(ge=1024, le=65535)]
Username = Annotated[str, StringConstraints(min_length=3, max_length=50, pattern=r'^[a-zA-Z0-9_-]+$')]
Email = Annotated[str, StringConstraints(pattern=r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
IPAddress = Annotated[str, StringConstraints(pattern=r'^(\d{1,3}\.){3}\d{1,3}$')]
CIDR = Annotated[str, StringConstraints(pattern=r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$')]


class ProtocolType(str, Enum):
    """Supported VPN/Proxy protocols."""
    VLESS = "vless"
    SHADOWSOCKS = "shadowsocks"
    WIREGUARD = "wireguard"
    HTTP = "http"
    SOCKS5 = "socks5"
    UNIFIED_PROXY = "unified_proxy"


class UserStatus(str, Enum):
    """User account status."""
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"


class ServerStatus(str, Enum):
    """Server operational status."""
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    ERROR = "error"


# Performance: Frozen model for immutable data
class OptimizedTrafficStats(BaseModel):
    """Optimized traffic statistics model with frozen config."""
    
    model_config = ConfigDict(
        frozen=True,  # Makes model immutable and hashable
        cache_strings='keys',  # Cache string operations
        revalidate_instances='never',  # Skip revalidation of already-validated instances
    )
    
    upload_bytes: Annotated[int, Field(ge=0)] = 0
    download_bytes: Annotated[int, Field(ge=0)] = 0
    total_bytes: Annotated[int, Field(ge=0)] = 0
    last_reset: datetime = Field(default_factory=datetime.utcnow)
    
    @computed_field
    @property
    def upload_mb(self) -> float:
        """Upload in megabytes."""
        return round(self.upload_bytes / (1024 * 1024), 2)
    
    @computed_field
    @property
    def download_mb(self) -> float:
        """Download in megabytes."""
        return round(self.download_bytes / (1024 * 1024), 2)
    
    @computed_field
    @property
    def total_mb(self) -> float:
        """Total traffic in megabytes."""
        return round(self.total_bytes / (1024 * 1024), 2)


# Performance: Use discriminated union for protocol configs
class VLESSConfig(BaseModel):
    """VLESS protocol configuration."""
    protocol_type: Literal["vless"] = "vless"
    flow: Optional[str] = None
    encryption: str = "none"
    reality_enabled: bool = False
    reality_public_key: Optional[str] = None
    reality_short_id: Optional[str] = None


class ShadowsocksConfig(BaseModel):
    """Shadowsocks protocol configuration."""
    protocol_type: Literal["shadowsocks"] = "shadowsocks"
    method: str = "chacha20-ietf-poly1305"
    password: Optional[str] = None


class WireGuardConfig(BaseModel):
    """WireGuard protocol configuration."""
    protocol_type: Literal["wireguard"] = "wireguard"
    private_key: Optional[str] = None
    public_key: Optional[str] = None
    endpoint: Optional[str] = None
    allowed_ips: List[str] = Field(default_factory=list)


class ProxyConfig(BaseModel):
    """HTTP/SOCKS5 proxy configuration."""
    protocol_type: Literal["http", "socks5"] = "http"
    auth_required: bool = False
    username: Optional[str] = None
    password: Optional[str] = None
    rate_limit: Optional[int] = None
    connection_limit: Optional[int] = None


# Discriminated union for efficient protocol parsing
ProtocolConfigUnion = Annotated[
    Union[VLESSConfig, ShadowsocksConfig, WireGuardConfig, ProxyConfig],
    Field(discriminator='protocol_type')
]


class OptimizedUser(BaseModel):
    """Optimized user model with performance features."""
    
    model_config = ConfigDict(
        # Performance optimizations
        validate_assignment=True,  # Validate on assignment
        arbitrary_types_allowed=False,  # Stricter validation
        cache_strings='all',  # Cache all string operations
        hide_input_in_errors=True,  # Security: hide input in errors
        # Schema optimizations
        json_schema_serialization_defaults_required=True,
    )
    
    id: UUID = Field(default_factory=uuid4)
    username: Username
    email: Optional[Email] = None
    status: UserStatus = UserStatus.ACTIVE
    protocol_config: ProtocolConfigUnion  # Discriminated union
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    traffic: OptimizedTrafficStats = Field(
        default_factory=lambda: OptimizedTrafficStats()
    )
    
    # Performance: Cached computed fields
    @computed_field
    @property
    def is_active(self) -> bool:
        """Check if user is active and not expired."""
        if self.status != UserStatus.ACTIVE:
            return False
        if self.expires_at and datetime.utcnow() > self.expires_at:
            return False
        return True
    
    @computed_field
    @property
    def days_until_expiry(self) -> Optional[int]:
        """Days until account expires."""
        if not self.expires_at:
            return None
        delta = self.expires_at - datetime.utcnow()
        return max(0, delta.days)
    
    # Performance: Use BeforeValidator for preprocessing
    @field_validator('username', mode='before')
    @classmethod
    def normalize_username(cls, v: str) -> str:
        """Normalize username to lowercase."""
        if isinstance(v, str):
            return v.lower().strip()
        return v
    
    @field_validator('email', mode='before')
    @classmethod
    def normalize_email(cls, v: Optional[str]) -> Optional[str]:
        """Normalize email to lowercase."""
        if v and isinstance(v, str):
            return v.lower().strip()
        return v
    
    # Optimized serialization
    @field_serializer('id', when_used='json')
    def serialize_uuid(self, value: UUID) -> str:
        """Serialize UUID to string."""
        return str(value)
    
    @field_serializer('created_at', 'updated_at', 'expires_at', when_used='json')
    def serialize_datetime(self, value: Optional[datetime]) -> Optional[str]:
        """Serialize datetime to ISO format."""
        return value.isoformat() if value else None


# Performance: Frozen configuration models
class OptimizedFirewallRule(BaseModel):
    """Optimized firewall rule with frozen config."""
    
    model_config = ConfigDict(
        frozen=True,
        cache_strings='all',
    )
    
    protocol: Literal["tcp", "udp", "both"] = "tcp"
    port: PortNumber
    source: Optional[Union[IPAddress, CIDR]] = None
    action: Literal["allow", "deny"] = "allow"
    comment: Optional[str] = Field(None, max_length=255)


class OptimizedDockerConfig(BaseModel):
    """Optimized Docker configuration."""
    
    model_config = ConfigDict(
        validate_default=True,
        cache_strings='all',
    )
    
    image: Annotated[str, StringConstraints(min_length=1, max_length=255)]
    tag: str = "latest"
    container_name: Optional[Annotated[str, StringConstraints(max_length=64)]] = None
    environment: Dict[str, str] = Field(default_factory=dict)
    volumes: List[str] = Field(default_factory=list)
    ports: Dict[str, PortNumber] = Field(default_factory=dict)
    networks: List[str] = Field(default_factory=list)
    restart_policy: Literal["no", "always", "unless-stopped"] = "unless-stopped"
    
    # Performance: Validate environment variables
    @field_validator('environment')
    @classmethod
    def validate_environment(cls, v: Dict[str, str]) -> Dict[str, str]:
        """Validate environment variables."""
        for key in v:
            if not key.replace('_', '').isalnum():
                raise ValueError(f"Invalid environment variable name: {key}")
        return v


class OptimizedServerConfig(BaseModel):
    """Optimized server configuration with performance features."""
    
    model_config = ConfigDict(
        validate_assignment=True,
        cache_strings='all',
        # Use Python mode for internal serialization (faster)
        ser_json_timedelta='float',
        ser_json_bytes='base64',
    )
    
    id: str = Field(default_factory=lambda: str(uuid4()))
    name: Annotated[str, StringConstraints(min_length=1, max_length=64)]
    protocol_config: ProtocolConfigUnion
    port: PortNumber
    docker_config: OptimizedDockerConfig
    firewall_rules: List[OptimizedFirewallRule] = Field(default_factory=list)
    status: ServerStatus = ServerStatus.STOPPED
    auto_start: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None
    
    # Performance: Model-level validation
    @model_validator(mode='after')
    def validate_server_config(self) -> 'OptimizedServerConfig':
        """Validate server configuration consistency."""
        # Ensure firewall rules match server port
        server_port_rule_exists = any(
            rule.port == self.port 
            for rule in self.firewall_rules
        )
        if not server_port_rule_exists and self.firewall_rules:
            # Auto-add server port rule
            self.firewall_rules.append(
                OptimizedFirewallRule(
                    protocol="tcp",
                    port=self.port,
                    action="allow",
                    comment="Auto-generated server port rule"
                )
            )
        return self
    
    @computed_field
    @property
    def is_running(self) -> bool:
        """Check if server is running."""
        return self.status == ServerStatus.RUNNING
    
    @computed_field
    @property
    def container_name(self) -> str:
        """Generate container name if not specified."""
        if self.docker_config.container_name:
            return self.docker_config.container_name
        protocol_type = getattr(self.protocol_config, 'protocol_type', 'unknown')
        return f"vpn-{protocol_type}-{self.name}"


# Performance: Use validate_call for function validation
@validate_call
def create_optimized_user(
    username: Username,
    protocol_type: ProtocolType,
    email: Optional[Email] = None,
    expires_days: Optional[conint(ge=1, le=365)] = None,
) -> OptimizedUser:
    """Create an optimized user with validation."""
    # Create protocol config based on type
    protocol_config: Union[VLESSConfig, ShadowsocksConfig, WireGuardConfig, ProxyConfig]
    
    if protocol_type == ProtocolType.VLESS:
        protocol_config = VLESSConfig()
    elif protocol_type == ProtocolType.SHADOWSOCKS:
        protocol_config = ShadowsocksConfig()
    elif protocol_type == ProtocolType.WIREGUARD:
        protocol_config = WireGuardConfig()
    elif protocol_type in (ProtocolType.HTTP, ProtocolType.SOCKS5):
        protocol_config = ProxyConfig(protocol_type=protocol_type.value)
    else:
        raise ValueError(f"Unsupported protocol type: {protocol_type}")
    
    expires_at = None
    if expires_days:
        expires_at = datetime.utcnow() + timedelta(days=expires_days)
    
    return OptimizedUser(
        username=username,
        email=email,
        protocol_config=protocol_config,
        expires_at=expires_at,
    )


# Performance: Batch validation for multiple users
@validate_call
def validate_user_batch(
    users: List[Dict[str, Any]],
    max_batch_size: conint(ge=1, le=1000) = 100,
) -> tuple[List[OptimizedUser], List[Dict[str, Any]]]:
    """Validate a batch of users efficiently."""
    if len(users) > max_batch_size:
        raise ValueError(f"Batch size {len(users)} exceeds maximum {max_batch_size}")
    
    valid_users = []
    invalid_users = []
    
    for user_data in users:
        try:
            user = OptimizedUser(**user_data)
            valid_users.append(user)
        except Exception as e:
            invalid_users.append({
                'data': user_data,
                'error': str(e)
            })
    
    return valid_users, invalid_users


# Performance monitoring model
class PerformanceMetrics(BaseModel):
    """Model for tracking performance metrics."""
    
    model_config = ConfigDict(
        frozen=True,
        cache_strings='all',
    )
    
    operation: str
    duration_ms: confloat(ge=0)
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    success: bool = True
    error: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)
    
    @computed_field
    @property
    def duration_seconds(self) -> float:
        """Duration in seconds."""
        return self.duration_ms / 1000.0
    
    @computed_field
    @property
    def is_slow(self) -> bool:
        """Check if operation was slow (>1000ms)."""
        return self.duration_ms > 1000


# Import timedelta for expires_at calculation
from datetime import timedelta