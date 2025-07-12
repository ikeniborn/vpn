#!/usr/bin/env python3
"""
Check and verify dependency versions for VPN Manager.
"""

import sys
import importlib.metadata
from typing import Tuple


def check_version(package: str, required: str) -> Tuple[str, bool]:
    """Check if package version meets requirement."""
    try:
        version = importlib.metadata.version(package)
        
        # Parse versions
        current_parts = [int(x) for x in version.split('.')[:2]]
        required_parts = [int(x) for x in required.split('.')[:2]]
        
        # Compare major.minor
        meets_requirement = current_parts >= required_parts
        
        return version, meets_requirement
    except Exception as e:
        return f"Error: {e}", False


def main():
    """Check all critical dependencies."""
    print("VPN Manager Dependency Check")
    print("=" * 40)
    
    requirements = {
        "pydantic": "2.11",
        "pydantic-settings": "2.6",
        "textual": "0.47",
        "typer": "0.12",
        "rich": "13.7",
        "pyyaml": "6.0",
    }
    
    all_good = True
    
    for package, required in requirements.items():
        version, ok = check_version(package, required)
        status = "✓" if ok else "✗"
        color = "\033[32m" if ok else "\033[31m"
        reset = "\033[0m"
        
        print(f"{color}{status}{reset} {package:<20} {version:<10} (required: >={required})")
        
        if not ok:
            all_good = False
    
    print("=" * 40)
    
    if all_good:
        print("\033[32m✓ All dependencies meet requirements!\033[0m")
    else:
        print("\033[31m✗ Some dependencies need updating.\033[0m")
        print("\nTo update dependencies:")
        print("  pip install -U -e .")
        print("  # or")
        print("  poetry update")
        
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())