"""
Custom exceptions for VPN Manager.
"""

from typing import Any, Dict, Optional


class VPNError(Exception):
    """Base exception for all VPN Manager errors."""
    
    def __init__(
        self,
        message: str,
        error_code: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(message)
        self.message = message
        self.error_code = error_code or self.__class__.__name__
        self.details = details or {}


class ConfigurationError(VPNError):
    """Configuration related errors."""
    pass


class ValidationError(VPNError):
    """Data validation errors."""
    pass


class UserError(VPNError):
    """User management related errors."""
    pass


class UserNotFoundError(UserError):
    """User not found error."""
    
    def __init__(self, username: str):
        super().__init__(
            f"User '{username}' not found",
            details={"username": username}
        )


class UserAlreadyExistsError(UserError):
    """User already exists error."""
    
    def __init__(self, username: str):
        super().__init__(
            f"User '{username}' already exists",
            details={"username": username}
        )


class ServerError(VPNError):
    """Server management related errors."""
    pass


class ServerNotFoundError(ServerError):
    """Server not found error."""
    
    def __init__(self, server_id: str):
        super().__init__(
            f"Server '{server_id}' not found",
            details={"server_id": server_id}
        )


class ServerAlreadyRunningError(ServerError):
    """Server already running error."""
    
    def __init__(self, server_id: str):
        super().__init__(
            f"Server '{server_id}' is already running",
            details={"server_id": server_id}
        )


# Generic aliases for compatibility
NotFoundError = UserNotFoundError
AlreadyExistsError = UserAlreadyExistsError


class DockerError(VPNError):
    """Docker related errors."""
    pass


class DockerNotAvailableError(DockerError):
    """Docker is not available or not running."""
    
    def __init__(self):
        super().__init__(
            "Docker is not available. Please ensure Docker is installed and running."
        )


class NetworkError(VPNError):
    """Network related errors."""
    pass


class PortAlreadyInUseError(NetworkError):
    """Port is already in use."""
    
    def __init__(self, port: int, protocol: str = "tcp"):
        super().__init__(
            f"Port {port}/{protocol} is already in use",
            details={"port": port, "protocol": protocol}
        )


class FirewallError(NetworkError):
    """Firewall configuration errors."""
    pass


class PermissionError(VPNError):
    """Permission related errors."""
    
    def __init__(self, operation: str):
        super().__init__(
            f"Permission denied for operation: {operation}. Run with appropriate privileges.",
            details={"operation": operation}
        )


class CryptoError(VPNError):
    """Cryptographic operation errors."""
    pass


class TemplateError(VPNError):
    """Template rendering errors."""
    pass


class DatabaseError(VPNError):
    """Database operation errors."""
    pass


class MonitoringError(VPNError):
    """Monitoring and metrics related errors."""
    pass


class ProxyError(VPNError):
    """Proxy server related errors."""
    pass


class AuthenticationError(ProxyError):
    """Authentication failed."""
    
    def __init__(self, reason: str = "Invalid credentials"):
        super().__init__(
            f"Authentication failed: {reason}",
            error_code="AUTH_FAILED"
        )


class RateLimitError(ProxyError):
    """Rate limit exceeded."""
    
    def __init__(self, limit: int, window: int):
        super().__init__(
            f"Rate limit exceeded: {limit} requests per {window} seconds",
            error_code="RATE_LIMIT_EXCEEDED",
            details={"limit": limit, "window": window}
        )