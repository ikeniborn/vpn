#!/usr/bin/env python3
"""
Quick installation test script.
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vpn.core.config import settings
from vpn.core.database import init_database
from vpn.utils.logger import setup_logging, get_logger


async def test_installation():
    """Test basic installation and setup."""
    logger = get_logger(__name__)
    
    print("=== VPN Manager Installation Test ===\n")
    
    # Test 1: Configuration
    print("1. Testing configuration...")
    print(f"   - App name: {settings.app_name}")
    print(f"   - Version: {settings.version}")
    print(f"   - Install path: {settings.install_path}")
    print(f"   - Config path: {settings.config_path}")
    print("   ✓ Configuration loaded successfully\n")
    
    # Test 2: Database initialization
    print("2. Testing database initialization...")
    try:
        await init_database()
        print("   ✓ Database initialized successfully\n")
    except Exception as e:
        print(f"   ✗ Database initialization failed: {e}\n")
        return False
    
    # Test 3: Import services
    print("3. Testing service imports...")
    try:
        from vpn.services.user_manager import UserManager
        from vpn.services.docker_manager import DockerManager
        from vpn.services.network_manager import NetworkManager
        from vpn.services.crypto import CryptoService
        print("   ✓ All services imported successfully\n")
    except Exception as e:
        print(f"   ✗ Service import failed: {e}\n")
        return False
    
    # Test 4: Create test user
    print("4. Testing user creation...")
    try:
        from vpn.core.models import ProtocolType
        
        user_manager = UserManager()
        test_user = await user_manager.create(
            username="test_user",
            protocol=ProtocolType.VLESS,
            email="test@example.com"
        )
        print(f"   ✓ Created test user: {test_user.username}")
        print(f"   - ID: {test_user.id}")
        print(f"   - Protocol: {test_user.protocol.type.value}")
        print(f"   - Keys generated: {'Yes' if test_user.keys.uuid else 'No'}\n")
        
        # Clean up
        await user_manager.delete(str(test_user.id))
        print("   ✓ Test user cleaned up\n")
        
    except Exception as e:
        print(f"   ✗ User creation failed: {e}\n")
        logger.exception("User creation test failed")
        return False
    
    # Test 5: Network utilities
    print("5. Testing network utilities...")
    try:
        network_manager = NetworkManager()
        
        # Check port availability
        port_available = await network_manager.check_port_available(8443)
        print(f"   - Port 8443 available: {port_available}")
        
        # Get public IP
        public_ip = await network_manager.get_public_ip()
        print(f"   - Public IP: {public_ip or 'Could not determine'}")
        
        print("   ✓ Network utilities working\n")
        
    except Exception as e:
        print(f"   ✗ Network utilities failed: {e}\n")
        return False
    
    # Test 6: Docker availability
    print("6. Testing Docker integration...")
    try:
        docker_manager = DockerManager()
        docker_available = await docker_manager.is_available()
        
        if docker_available:
            version = await docker_manager.get_version()
            print(f"   ✓ Docker is available")
            print(f"   - Version: {version.get('Version', 'Unknown')}")
            print(f"   - API Version: {version.get('ApiVersion', 'Unknown')}\n")
        else:
            print("   ⚠ Docker is not available (this is okay for basic testing)\n")
            
    except Exception as e:
        print(f"   ⚠ Docker check failed: {e}")
        print("   (This is okay if Docker is not installed)\n")
    
    print("=== Installation Test Complete ===")
    print("\nAll core components are working correctly!")
    print("\nNext steps:")
    print("1. Run 'python -m vpn init' to initialize the system")
    print("2. Run 'python -m vpn doctor' for system diagnostics")
    print("3. Run 'python -m vpn --help' to see available commands")
    
    return True


def main():
    """Main entry point."""
    # Setup logging
    setup_logging(log_level="INFO")
    
    # Run tests
    success = asyncio.run(test_installation())
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()