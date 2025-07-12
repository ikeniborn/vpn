#!/usr/bin/env python3
"""
Test new Pydantic 2.11+ features.
"""

import json
from datetime import datetime

from vpn.core.models import User, TrafficStats, UserStatus
from vpn.core.validators import AdvancedServerConfig, ProxyAuthConfig, BandwidthLimit
from vpn.core.schema_examples import VPNProtocolConfig, UserQuota


def test_computed_fields():
    """Test computed fields."""
    print("Testing computed fields...")
    
    # Create traffic stats
    traffic = TrafficStats(
        upload_bytes=1024 * 1024 * 100,  # 100 MB
        download_bytes=1024 * 1024 * 200,  # 200 MB
        total_bytes=1024 * 1024 * 300  # 300 MB
    )
    
    print(f"Upload: {traffic.upload_mb:.2f} MB (computed)")
    print(f"Download: {traffic.download_mb:.2f} MB (computed)")
    print(f"Total: {traffic.total_mb:.2f} MB (computed)")
    print()


def test_field_serializers():
    """Test field serializers."""
    print("Testing field serializers...")
    
    # Create user
    user = User(
        username="testuser",
        email="test@example.com",
        status=UserStatus.ACTIVE,
        protocol={"type": "vless"},
        keys={"public": "test"},
        traffic=TrafficStats()
    )
    
    # Serialize to JSON
    user_json = user.model_dump_json(indent=2)
    print("Serialized user:")
    print(user_json)
    print()


def test_model_validators():
    """Test model validators."""
    print("Testing model validators...")
    
    # Test valid config
    try:
        config = AdvancedServerConfig(
            protocol="VLESS",  # Will be normalized to lowercase
            port=8443,
            start_date=datetime.now(),
            end_date=datetime.now().replace(year=datetime.now().year + 1),
            max_users=100,
            current_users=50
        )
        print(f"✓ Valid config: protocol={config.protocol}, users={config.current_users}/{config.max_users}")
    except Exception as e:
        print(f"✗ Error: {e}")
    
    # Test invalid dates
    try:
        config = AdvancedServerConfig(
            protocol="vless",
            port=8443,
            start_date=datetime.now(),
            end_date=datetime.now().replace(year=datetime.now().year - 1),  # Past date
            max_users=100,
            current_users=50
        )
        print("✗ Should have failed validation")
    except ValueError as e:
        print(f"✓ Correctly caught error: {e}")
    
    # Test proxy auth
    try:
        auth = ProxyAuthConfig(
            auth_type="basic",
            username="admin",
            password="secret"
        )
        print(f"✓ Valid auth config: {auth.auth_type}")
    except Exception as e:
        print(f"✗ Error: {e}")
    
    print()


def test_json_schema():
    """Test JSON schema generation."""
    print("Testing JSON schema generation...")
    
    # Generate schema
    schema = VPNProtocolConfig.model_json_schema()
    print("VPN Protocol Config Schema:")
    print(json.dumps(schema, indent=2))
    print()
    
    # Test with example
    config = VPNProtocolConfig(
        protocol="vless",
        port=8443,
        transport="tcp"
    )
    print(f"Example config: {config.model_dump_json()}")
    print()


def test_user_quota():
    """Test user quota with examples."""
    print("Testing user quota schema...")
    
    # Create quota
    quota = UserQuota(
        max_devices=5,
        bandwidth_limit_mbps=100.0,
        traffic_limit_gb=500.0,
        expires_days=90
    )
    
    print(f"Quota: {quota.model_dump_json(indent=2)}")
    
    # Show schema with examples
    schema = UserQuota.model_json_schema()
    print(f"\nSchema examples: {len(schema.get('examples', []))} examples")
    print()


def main():
    """Run all tests."""
    print("=" * 50)
    print("Testing Pydantic 2.11+ Features")
    print("=" * 50)
    print()
    
    test_computed_fields()
    test_field_serializers()
    test_model_validators()
    test_json_schema()
    test_user_quota()
    
    print("All tests completed!")


if __name__ == "__main__":
    main()