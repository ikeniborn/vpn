"""JSON Schema examples using Pydantic 2.11+ features.
"""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.json_schema import JsonSchemaValue


class VPNProtocolConfig(BaseModel):
    """VPN Protocol configuration with rich JSON schema."""

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "protocol": "vless",
                    "security": "reality",
                    "port": 8443,
                    "transport": "tcp"
                },
                {
                    "protocol": "shadowsocks",
                    "method": "chacha20-ietf-poly1305",
                    "port": 8388,
                    "transport": "tcp"
                }
            ]
        }
    )

    protocol: Annotated[
        Literal["vless", "shadowsocks", "wireguard"],
        Field(
            description="VPN protocol type",
            json_schema_extra={"enum_descriptions": {
                "vless": "Modern protocol with Reality security",
                "shadowsocks": "Fast proxy protocol with encryption",
                "wireguard": "Modern kernel-level VPN protocol"
            }}
        )
    ]

    port: Annotated[
        int,
        Field(
            ge=1024,
            le=65535,
            description="Server port number",
            json_schema_extra={"default": 8443}
        )
    ]

    transport: Annotated[
        Literal["tcp", "udp", "grpc", "ws"],
        Field(
            description="Transport protocol",
            json_schema_extra={
                "default": "tcp",
                "enum_descriptions": {
                    "tcp": "Reliable TCP transport",
                    "udp": "Fast UDP transport",
                    "grpc": "gRPC transport for better censorship resistance",
                    "ws": "WebSocket transport for HTTP compatibility"
                }
            }
        )
    ]

    @classmethod
    def model_json_schema(cls, **kwargs) -> JsonSchemaValue:
        """Generate enhanced JSON schema."""
        schema = super().model_json_schema(**kwargs)

        # Add custom schema properties
        schema["$schema"] = "https://json-schema.org/draft/2020-12/schema"
        schema["title"] = "VPN Protocol Configuration"
        schema["description"] = "Configuration for various VPN protocols supported by VPN Manager"

        return schema


class UserQuota(BaseModel):
    """User quota configuration with detailed schema."""

    max_devices: Annotated[
        int,
        Field(
            gt=0,
            le=100,
            description="Maximum number of simultaneous device connections",
            examples=[1, 3, 5, 10]
        )
    ] = 3

    bandwidth_limit_mbps: Annotated[
        float | None,
        Field(
            gt=0,
            le=10000,
            description="Bandwidth limit in Mbps (null for unlimited)",
            examples=[10.0, 100.0, 1000.0, None]
        )
    ] = None

    traffic_limit_gb: Annotated[
        float | None,
        Field(
            gt=0,
            description="Monthly traffic limit in GB (null for unlimited)",
            examples=[100.0, 500.0, 1000.0, None]
        )
    ] = None

    expires_days: Annotated[
        int | None,
        Field(
            gt=0,
            le=365,
            description="Account expiration in days (null for no expiration)",
            examples=[30, 90, 180, 365, None]
        )
    ] = None

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "max_devices": 1,
                    "bandwidth_limit_mbps": 10.0,
                    "traffic_limit_gb": 100.0,
                    "expires_days": 30
                },
                {
                    "max_devices": 5,
                    "bandwidth_limit_mbps": None,
                    "traffic_limit_gb": 1000.0,
                    "expires_days": 365
                },
                {
                    "max_devices": 10,
                    "bandwidth_limit_mbps": None,
                    "traffic_limit_gb": None,
                    "expires_days": None
                }
            ],
            "$id": "https://vpn-manager.example.com/schemas/user-quota.json",
            "additionalProperties": False
        }
    )
