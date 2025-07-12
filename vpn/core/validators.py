"""
Advanced Pydantic validators using Pydantic 2.11+ features.
"""

from datetime import datetime
from typing import Any, Dict

from pydantic import BaseModel, Field, model_validator, ValidationInfo


class AdvancedServerConfig(BaseModel):
    """Example of advanced validation with Pydantic 2.11+."""
    
    protocol: str
    port: int = Field(ge=1024, le=65535)
    start_date: datetime
    end_date: datetime
    max_users: int = Field(gt=0)
    current_users: int = Field(ge=0)
    
    @model_validator(mode='after')
    def validate_dates(self) -> 'AdvancedServerConfig':
        """Validate that end_date is after start_date."""
        if self.end_date <= self.start_date:
            raise ValueError("end_date must be after start_date")
        return self
    
    @model_validator(mode='after')
    def validate_user_capacity(self) -> 'AdvancedServerConfig':
        """Validate current users don't exceed max users."""
        if self.current_users > self.max_users:
            raise ValueError(f"current_users ({self.current_users}) exceeds max_users ({self.max_users})")
        return self
    
    @model_validator(mode='before')
    @classmethod
    def normalize_protocol(cls, data: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize protocol name before validation."""
        if isinstance(data, dict) and 'protocol' in data:
            data['protocol'] = data['protocol'].lower()
        return data


class ProxyAuthConfig(BaseModel):
    """Proxy authentication configuration with context validation."""
    
    auth_type: str
    username: str | None = None
    password: str | None = None
    token: str | None = None
    
    @model_validator(mode='after')
    def validate_auth_fields(self, info: ValidationInfo) -> 'ProxyAuthConfig':
        """Validate auth fields based on auth_type."""
        if self.auth_type == 'basic':
            if not self.username or not self.password:
                raise ValueError("username and password required for basic auth")
            if self.token:
                raise ValueError("token should not be set for basic auth")
        elif self.auth_type == 'token':
            if not self.token:
                raise ValueError("token required for token auth")
            if self.username or self.password:
                raise ValueError("username/password should not be set for token auth")
        elif self.auth_type == 'none':
            if self.username or self.password or self.token:
                raise ValueError("no credentials should be set for no auth")
        else:
            raise ValueError(f"Unknown auth_type: {self.auth_type}")
        
        return self


class BandwidthLimit(BaseModel):
    """Bandwidth limit configuration with smart defaults."""
    
    download_mbps: float | None = None
    upload_mbps: float | None = None
    total_gb_per_month: float | None = None
    
    @model_validator(mode='after')
    def set_symmetric_limits(self) -> 'BandwidthLimit':
        """Set upload limit to match download if not specified."""
        if self.download_mbps and not self.upload_mbps:
            self.upload_mbps = self.download_mbps
        return self
    
    @model_validator(mode='after')
    def validate_reasonable_limits(self) -> 'BandwidthLimit':
        """Ensure bandwidth limits are reasonable."""
        if self.download_mbps and self.download_mbps > 10000:  # 10 Gbps
            raise ValueError("download_mbps seems unreasonably high (>10 Gbps)")
        if self.upload_mbps and self.upload_mbps > 10000:
            raise ValueError("upload_mbps seems unreasonably high (>10 Gbps)")
        if self.total_gb_per_month and self.total_gb_per_month > 100000:  # 100 TB
            raise ValueError("total_gb_per_month seems unreasonably high (>100 TB)")
        return self