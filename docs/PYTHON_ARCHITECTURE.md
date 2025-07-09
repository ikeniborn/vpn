# VPN Manager - Python Architecture

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              User Interface Layer                            │
├─────────────────────────┬────────────────────────┬─────────────────────────┤
│      CLI (Click)        │    TUI (Textual)       │    API (Future)         │
│  • Command parsing      │  • Rich terminal UI    │  • RESTful endpoints    │
│  • Output formatting    │  • Real-time updates   │  • WebSocket events     │
│  • Shell completions    │  • Interactive menus   │  • OpenAPI spec         │
└────────────┬────────────┴────────────┬───────────┴─────────────────────────┘
             │                         │
             ▼                         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Application Layer                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐           │
│  │  User Manager   │  │  Server Manager  │  │  Proxy Manager  │           │
│  │  • CRUD ops     │  │  • Install/Remove│  │  • HTTP/SOCKS5  │           │
│  │  • Batch ops    │  │  • Start/Stop    │  │  • Auth system  │           │
│  │  • Import/Export│  │  • Config gen    │  │  • Rate limit   │           │
│  └────────┬────────┘  └────────┬─────────┘  └────────┬────────┘           │
│           │                    │                      │                     │
│  ┌────────▼────────────────────▼──────────────────────▼────────┐           │
│  │                    Service Orchestration                     │           │
│  │  • Dependency injection  • Event system  • Task scheduling  │           │
│  └──────────────────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Core Services                                   │
├──────────────────┬───────────────────┬────────────────────┬────────────────┤
│  Docker Service  │  Network Service  │  Crypto Service    │  Monitor Service│
│  • Container mgmt│  • Firewall rules │  • Key generation  │  • Metrics      │
│  • Image builds  │  • Port checks    │  • QR codes        │  • Logging      │
│  • Log streaming │  • IP detection   │  • Encryption      │  • Alerts       │
└──────────┬───────┴────────┬──────────┴─────────┬──────────┴────────────────┘
           │                 │                    │
           ▼                 ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Data & Storage Layer                              │
├─────────────────────────┬────────────────────────┬─────────────────────────┤
│   SQLite Database       │   Configuration Files  │   Template Engine       │
│   • User records        │   • YAML/TOML/JSON    │   • Jinja2 templates    │
│   • Server state        │   • Env overrides     │   • Config generation   │
│   • Traffic stats       │   • Secrets storage   │   • Script templates    │
└─────────────────────────┴────────────────────────┴─────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          External Integration                                │
├─────────────────────────┬────────────────────────┬─────────────────────────┤
│   System (Bash)         │   Docker Daemon        │   Network Stack         │
│   • iptables           │   • Container runtime  │   • TCP/UDP sockets     │
│   • systemd            │   • Image registry     │   • HTTP/SOCKS proxy    │
│   • File operations    │   • Volume management  │   • VPN protocols       │
└─────────────────────────┴────────────────────────┴─────────────────────────┘
```

## Component Details

### 1. User Interface Layer

#### CLI (Click/Typer)
```python
vpn/
├── cli/
│   ├── app.py          # Main CLI application
│   ├── commands/       # Command implementations
│   │   ├── users.py    # User management commands
│   │   ├── server.py   # Server commands
│   │   ├── proxy.py    # Proxy commands
│   │   └── monitor.py  # Monitoring commands
│   └── formatters/     # Output formatting
│       ├── table.py    # Table formatter
│       ├── json.py     # JSON formatter
│       └── plain.py    # Plain text formatter
```

#### TUI (Textual)
```python
vpn/
├── tui/
│   ├── app.py          # Main Textual application
│   ├── screens/        # Screen implementations
│   │   ├── dashboard.py
│   │   ├── users.py
│   │   ├── server.py
│   │   └── monitor.py
│   ├── widgets/        # Custom widgets
│   │   ├── charts.py   # Traffic charts
│   │   ├── tables.py   # Data tables
│   │   └── gauges.py   # Resource gauges
│   └── themes/         # UI themes
│       ├── dark.py
│       └── light.py
```

### 2. Application Layer

#### Service Architecture
```python
vpn/
├── services/
│   ├── base.py         # Base service class
│   ├── user_manager.py # User management
│   ├── server_manager.py
│   ├── proxy_manager.py
│   ├── monitor_service.py
│   └── orchestrator.py # Service coordination
```

#### Event System
```python
# Event-driven architecture for loose coupling
class EventBus:
    async def publish(self, event: Event) -> None
    async def subscribe(self, event_type: Type[Event], handler: Callable)

# Example events
class UserCreatedEvent(Event):
    user_id: UUID
    username: str
    protocol: str

class ServerStatusChangedEvent(Event):
    server_id: str
    old_status: str
    new_status: str
```

### 3. Core Services

#### Docker Integration
```python
vpn/
├── core/
│   ├── docker/
│   │   ├── client.py      # Async Docker client wrapper
│   │   ├── container.py   # Container management
│   │   ├── compose.py     # Docker Compose integration
│   │   └── monitor.py     # Container monitoring
```

#### Network Management
```python
vpn/
├── core/
│   ├── network/
│   │   ├── firewall.py    # iptables management
│   │   ├── port.py        # Port availability
│   │   ├── ip.py          # IP detection
│   │   └── subnet.py      # Subnet validation
```

### 4. Data Models (Pydantic)

```python
# vpn/models/user.py
from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, Literal
from datetime import datetime
import uuid

class User(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    username: str = Field(..., min_length=3, max_length=50)
    email: Optional[str] = None
    status: Literal["active", "inactive", "suspended"] = "active"
    protocol: VpnProtocol
    keys: Dict[str, str] = Field(default_factory=dict)
    traffic: TrafficStats = Field(default_factory=TrafficStats)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None
    
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat(),
            uuid.UUID: lambda v: str(v)
        }

# vpn/models/server.py
class ServerConfig(BaseModel):
    id: str
    protocol: ProtocolType
    port: int = Field(..., ge=1, le=65535)
    docker_config: DockerConfig
    firewall_rules: List[FirewallRule]
    status: ServerStatus = ServerStatus.STOPPED
    
    @validator('docker_config')
    def validate_docker_config(cls, v):
        # Custom validation logic
        return v
```

### 5. Database Schema (SQLAlchemy)

```python
# vpn/database/models.py
from sqlalchemy import Column, String, Integer, DateTime, JSON
from sqlalchemy.ext.asyncio import AsyncAttrs
from sqlalchemy.orm import DeclarativeBase

class Base(AsyncAttrs, DeclarativeBase):
    pass

class UserDB(Base):
    __tablename__ = "users"
    
    id = Column(String(36), primary_key=True)
    username = Column(String(50), unique=True, nullable=False)
    email = Column(String(255))
    status = Column(String(20), default="active")
    protocol = Column(JSON, nullable=False)
    keys = Column(JSON)
    traffic = Column(JSON)
    created_at = Column(DateTime, nullable=False)
    updated_at = Column(DateTime)

# vpn/database/session.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession

engine = create_async_engine(
    "sqlite+aiosqlite:///vpn.db",
    echo=False,
    pool_pre_ping=True
)

async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSession(engine) as session:
        yield session
```

### 6. Configuration System

```python
# vpn/config/settings.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional, List
from pathlib import Path

class Settings(BaseSettings):
    # Application settings
    app_name: str = "VPN Manager"
    version: str = "2.0.0"
    debug: bool = False
    
    # Paths
    install_path: Path = Path("/opt/vpn")
    config_path: Path = Path.home() / ".config" / "vpn-manager"
    data_path: Path = Path.home() / ".local" / "share" / "vpn-manager"
    
    # Database
    database_url: str = "sqlite+aiosqlite:///vpn.db"
    
    # Docker
    docker_socket: str = "/var/run/docker.sock"
    docker_timeout: int = 30
    
    # Server defaults
    default_protocol: str = "vless"
    default_port_range: tuple[int, int] = (10000, 65000)
    
    # Security
    enable_auth: bool = True
    secret_key: Optional[str] = None
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="VPN_",
        case_sensitive=False
    )

# Load settings
settings = Settings()
```

### 7. Bash Script Integration

```python
# vpn/core/shell.py
import asyncio
from pathlib import Path
from typing import Optional, Dict, Any

class ShellExecutor:
    """Execute bash scripts with proper error handling"""
    
    def __init__(self, scripts_dir: Path):
        self.scripts_dir = scripts_dir
    
    async def execute(
        self,
        script: str,
        args: List[str],
        env: Optional[Dict[str, str]] = None
    ) -> tuple[int, str, str]:
        """Execute a bash script asynchronously"""
        script_path = self.scripts_dir / script
        
        if not script_path.exists():
            raise FileNotFoundError(f"Script not found: {script}")
        
        cmd = ["bash", str(script_path)] + args
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**os.environ, **(env or {})}
        )
        
        stdout, stderr = await process.communicate()
        
        return process.returncode, stdout.decode(), stderr.decode()

# Example usage
executor = ShellExecutor(Path("scripts"))
code, out, err = await executor.execute(
    "firewall.sh",
    ["add", "tcp", "8443"]
)
```

### 8. Template System (Jinja2)

```python
# vpn/templates/manager.py
from jinja2 import Environment, FileSystemLoader
from pathlib import Path

class TemplateManager:
    def __init__(self, templates_dir: Path):
        self.env = Environment(
            loader=FileSystemLoader(templates_dir),
            autoescape=True,
            trim_blocks=True,
            lstrip_blocks=True
        )
    
    def render(self, template_name: str, **context) -> str:
        """Render a template with the given context"""
        template = self.env.get_template(template_name)
        return template.render(**context)

# Example template usage
template_mgr = TemplateManager(Path("templates"))
xray_config = template_mgr.render(
    "xray/config.json.j2",
    users=users,
    port=8443,
    protocol="vless"
)
```

## Performance Optimization Strategies

### 1. Async Everything
- Use asyncio for all I/O operations
- Implement connection pooling for Docker API
- Batch database operations
- Concurrent task execution with asyncio.gather()

### 2. Caching Layer
```python
from functools import lru_cache
from aiocache import Cache

# Memory cache for frequently accessed data
cache = Cache(Cache.MEMORY)

@cached(ttl=60)
async def get_container_stats(container_id: str):
    # Expensive operation cached for 60 seconds
    return await docker_client.stats(container_id)
```

### 3. Lazy Loading
```python
class LazyProperty:
    """Descriptor for lazy-loaded properties"""
    def __init__(self, func):
        self.func = func
    
    def __get__(self, obj, type=None):
        if obj is None:
            return self
        value = self.func(obj)
        setattr(obj, self.func.__name__, value)
        return value
```

### 4. Resource Management
```python
# Context managers for proper resource cleanup
async with get_docker_client() as docker:
    async with get_db_session() as db:
        # Perform operations
        pass
```

## Security Considerations

### 1. Input Validation
- Pydantic models for all user input
- SQL injection prevention with SQLAlchemy
- Command injection prevention in shell scripts
- Path traversal protection

### 2. Privilege Management
```python
class PrivilegeManager:
    @staticmethod
    def check_privileges() -> bool:
        """Check if running with required privileges"""
        return os.geteuid() == 0
    
    @staticmethod
    async def elevate_privileges(command: List[str]):
        """Run command with elevated privileges"""
        return await asyncio.create_subprocess_exec(
            "sudo", *command
        )
```

### 3. Secure Storage
- Secrets in environment variables
- Encrypted configuration files
- Secure key generation with cryptography library

## Testing Strategy

### 1. Unit Tests
```python
# tests/test_user_manager.py
import pytest
from vpn.services.user_manager import UserManager

@pytest.mark.asyncio
async def test_create_user():
    async with get_test_db() as db:
        manager = UserManager(db)
        user = await manager.create_user("testuser", "vless")
        assert user.username == "testuser"
        assert user.protocol.type == "vless"
```

### 2. Integration Tests
```python
# tests/integration/test_docker.py
@pytest.mark.integration
async def test_container_lifecycle():
    async with DockerClient() as docker:
        container = await docker.create_container(...)
        await docker.start_container(container.id)
        assert await docker.is_running(container.id)
        await docker.stop_container(container.id)
```

### 3. TUI Tests
```python
# tests/tui/test_screens.py
from textual.pilot import Pilot

async def test_dashboard_screen():
    async with VpnTuiApp().run_test() as pilot:
        # Test navigation
        await pilot.press("tab")
        await pilot.press("enter")
        # Assert screen state
```

This architecture provides a clean, maintainable, and extensible foundation for the Python-based VPN management system while preserving all functionality from the Rust implementation.