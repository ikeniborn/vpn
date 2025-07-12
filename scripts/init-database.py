#!/usr/bin/env python3
"""
Initialize VPN Manager database on remote server.
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from vpn.core.config import settings
from vpn.core.database import init_database, engine


async def main():
    """Initialize database with proper error handling."""
    print("VPN Manager Database Initialization")
    print("=" * 40)
    
    # Show configuration
    print(f"Database URL: {settings.database_url}")
    print(f"Database path: {settings.database_path}")
    print(f"Config path: {settings.config_path}")
    print(f"Data path: {settings.data_path}")
    print()
    
    # Create necessary directories
    print("Creating directories...")
    settings.data_path.mkdir(parents=True, exist_ok=True)
    settings.config_path.mkdir(parents=True, exist_ok=True)
    (settings.data_path / "logs").mkdir(exist_ok=True)
    print("✓ Directories created")
    
    # Initialize database
    print("\nInitializing database...")
    try:
        await init_database()
        print("✓ Database tables created successfully")
        
        # Test connection
        async with engine.connect() as conn:
            result = await conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = [row[0] for row in result]
            print(f"\nCreated tables: {', '.join(tables)}")
            
    except Exception as e:
        print(f"✗ Database initialization failed: {e}")
        return 1
    
    print("\nDatabase initialization complete!")
    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)