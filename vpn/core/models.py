"""
Core Pydantic models for VPN Manager.
"""

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Literal, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator, ConfigDict, field_serializer, computed_field


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


class ProxyType(str, Enum):
    """Proxy server types."""
    
    HTTP = "http"
    HTTPS = "https"
    SOCKS5 = "socks5"


class TrafficStats(BaseModel):
    """Traffic statistics model."""
    
    upload_bytes: int = 0
    download_bytes: int = 0
    total_bytes: int = 0
    last_reset: datetime = Field(default_factory=datetime.utcnow)
    
    model_config = ConfigDict(from_attributes=True)
    
    @computed_field
    @property
    def upload_mb(self) -> float:
        """Upload in megabytes."""
        return self.upload_bytes / (1024 * 1024)
    
    @computed_field
    @property
    def download_mb(self) -> float:
        """Download in megabytes."""
        return self.download_bytes / (1024 * 1024)
    
    @computed_field
    @property
    def total_mb(self) -> float:
        """Total traffic in megabytes."""
        return self.total_bytes / (1024 * 1024)


class CryptoKeys(BaseModel):
    """Cryptographic keys for protocols."""
    
    private_key: Optional[str] = None
    public_key: Optional[str] = None
    short_id: Optional[str] = None
    uuid: Optional[str] = Field(default_factory=lambda: str(uuid4()))
    password: Optional[str] = None
    
    model_config = ConfigDict(from_attributes=True)


class ProtocolConfig(BaseModel):
    """Protocol-specific configuration."""
    
    type: ProtocolType
    settings: Dict[str, Any] = Field(default_factory=dict)
    
    # VLESS specific
    flow: Optional[str] = None
    encryption: Optional[str] = "none"
    
    # Reality specific
    reality_enabled: bool = False
    reality_public_key: Optional[str] = None
    reality_short_id: Optional[str] = None
    
    # Shadowsocks specific
    method: Optional[str] = None
    
    # WireGuard specific
    endpoint: Optional[str] = None
    allowed_ips: List[str] = Field(default_factory=list)
    
    # Proxy specific
    auth_required: bool = False
    rate_limit: Optional[int] = None  # bytes per second
    connection_limit: Optional[int] = None
    
    model_config = ConfigDict(from_attributes=True)


class User(BaseModel):
    """User model with comprehensive validation."""
    
    id: UUID = Field(default_factory=uuid4)
    username: str = Field(..., min_length=3, max_length=50)
    email: Optional[str] = None
    status: UserStatus = UserStatus.ACTIVE
    protocol: ProtocolConfig
    keys: CryptoKeys = Field(default_factory=CryptoKeys)
    traffic: TrafficStats = Field(default_factory=TrafficStats)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    notes: Optional[str] = None
    
    model_config = ConfigDict(
        from_attributes=True,
    )
    
    @field_serializer('id')
    def serialize_uuid(self, value: UUID) -> str:
        """Serialize UUID to string."""
        return str(value)
    
    @field_serializer('created_at', 'updated_at', 'expires_at')
    def serialize_datetime(self, value: Optional[datetime]) -> Optional[str]:
        """Serialize datetime to ISO format."""
        return value.isoformat() if value else None
    
    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        """Validate username format."""
        if not v.replace("_", "").replace("-", "").isalnum():
            raise ValueError("Username must contain only letters, numbers, hyphens, and underscores")
        return v.lower()
    
    @field_validator("email")
    @classmethod
    def validate_email(cls, v: Optional[str]) -> Optional[str]:
        """Basic email validation."""
        if v is None:
            return v
        if "@" not in v or "." not in v.split("@")[1]:
            raise ValueError("Invalid email format")
        return v.lower()
    
    @computed_field
    @property
    def is_active(self) -> bool:
        """Check if user is active and not expired."""
        if self.status != UserStatus.ACTIVE:
            return False
        if self.expires_at and datetime.utcnow() > self.expires_at:
            return False
        return True
    
    def generate_connection_link(self) -> str:
        """Generate connection link based on protocol."""
        # This will be implemented based on protocol type
        return f"{self.protocol.type}://{self.username}@example.com"


class FirewallRule(BaseModel):
    """Firewall rule configuration."""
    
    protocol: Literal["tcp", "udp", "both"] = "tcp"
    port: int = Field(..., ge=1, le=65535)
    source: Optional[str] = None  # IP or CIDR
    action: Literal["allow", "deny"] = "allow"
    comment: Optional[str] = None
    
    model_config = ConfigDict(from_attributes=True)


class ProxyConfig(BaseModel):
    """Proxy server configuration."""
    
    type: ProxyType
    port: int = Field(..., ge=1024, le=65535)
    host: str = "0.0.0.0"
    auth_required: bool = True
    max_connections: int = 100
    buffer_size: int = 8192
    timeout: int = 300  # seconds
    rate_limit: Optional[int] = None  # requests per minute
    allowed_hosts: List[str] = Field(default_factory=list)
    blocked_hosts: List[str] = Field(default_factory=list)
    
    model_config = ConfigDict(from_attributes=True)


class DockerConfig(BaseModel):
    """Docker-specific configuration."""
    
    image: str
    tag: str = "latest"
    container_name: Optional[str] = None
    environment: Dict[str, str] = Field(default_factory=dict)
    volumes: List[str] = Field(default_factory=list)
    ports: Dict[str, int] = Field(default_factory=dict)
    networks: List[str] = Field(default_factory=list)
    restart_policy: Literal["no", "always", "unless-stopped"] = "unless-stopped"
    
    model_config = ConfigDict(from_attributes=True)


class ServerConfig(BaseModel):
    """Server configuration model."""
    
    id: str = Field(default_factory=lambda: str(uuid4()))
    name: str
    protocol: ProtocolConfig
    port: int = Field(..., ge=1, le=65535)
    docker_config: DockerConfig
    firewall_rules: List[FirewallRule] = Field(default_factory=list)
    status: ServerStatus = ServerStatus.STOPPED
    auto_start: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None
    
    model_config = ConfigDict(
        from_attributes=True,
    )
    
    @field_serializer('created_at', 'updated_at')
    def serialize_datetime(self, value: Optional[datetime]) -> Optional[str]:
        """Serialize datetime to ISO format."""
        return value.isoformat() if value else None
    
    @field_validator("port")
    @classmethod
    def validate_port(cls, v: int) -> int:
        """Validate port is not a well-known port."""
        if v < 1024:
            raise ValueError("Port must be >= 1024 for non-root operation")
        return v


class ConnectionInfo(BaseModel):
    """Connection information for clients."""
    
    user_id: UUID
    protocol: ProtocolType
    server_address: str
    server_port: int
    connection_link: str
    qr_code: Optional[str] = None
    instructions: Optional[str] = None
    
    model_config = ConfigDict(from_attributes=True)


class SystemStatus(BaseModel):
    """System-wide status information."""
    
    servers: List[ServerConfig]
    total_users: int
    active_users: int
    total_traffic: TrafficStats
    system_resources: Dict[str, float]  # CPU, memory, disk
    docker_status: bool
    last_check: datetime = Field(default_factory=datetime.utcnow)
    
    model_config = ConfigDict(from_attributes=True)


class Alert(BaseModel):
    """System alert/notification model."""
    
    id: UUID = Field(default_factory=uuid4)
    level: Literal["info", "warning", "error", "critical"]
    title: str
    message: str
    source: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    acknowledged: bool = False
    acknowledged_at: Optional[datetime] = None
    resolved: bool = False
    resolved_at: Optional[datetime] = None
    
    model_config = ConfigDict(from_attributes=True)