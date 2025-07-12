#!/usr/bin/env python3
"""Verify project dependencies and check for conflicts."""

import subprocess
import sys
from pathlib import Path
import tomli
import json


def load_pyproject():
    """Load pyproject.toml dependencies."""
    pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
    with open(pyproject_path, "rb") as f:
        data = tomli.load(f)
    
    deps = {}
    
    # Get main dependencies
    if "tool" in data and "poetry" in data["tool"] and "dependencies" in data["tool"]["poetry"]:
        deps["main"] = data["tool"]["poetry"]["dependencies"]
    
    # Get dev dependencies
    if "tool" in data and "poetry" in data["tool"] and "group" in data["tool"]["poetry"]:
        dev_group = data["tool"]["poetry"]["group"].get("dev", {})
        if "dependencies" in dev_group:
            deps["dev"] = dev_group["dependencies"]
    
    return deps


def check_installed_versions():
    """Check installed package versions."""
    result = subprocess.run(
        [sys.executable, "-m", "pip", "list", "--format=json"],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error getting installed packages: {result.stderr}")
        return {}
    
    installed = {}
    for pkg in json.loads(result.stdout):
        installed[pkg["name"].lower().replace("-", "_")] = pkg["version"]
    
    return installed


def main():
    """Main verification function."""
    print("🔍 Verifying project dependencies...\n")
    
    # Load dependencies
    deps = load_pyproject()
    installed = check_installed_versions()
    
    # Check main dependencies
    print("📦 Main Dependencies:")
    for pkg, version in deps.get("main", {}).items():
        if pkg == "python":
            continue
        
        pkg_name = pkg.lower().replace("-", "_")
        installed_version = installed.get(pkg_name, "NOT INSTALLED")
        
        if installed_version == "NOT INSTALLED":
            print(f"  ❌ {pkg}: {version} (NOT INSTALLED)")
        else:
            print(f"  ✅ {pkg}: {version} (installed: {installed_version})")
    
    print("\n🛠️  Dev Dependencies:")
    for pkg, version in deps.get("dev", {}).items():
        pkg_name = pkg.lower().replace("-", "_")
        installed_version = installed.get(pkg_name, "NOT INSTALLED")
        
        if installed_version == "NOT INSTALLED":
            print(f"  ❌ {pkg}: {version} (NOT INSTALLED)")
        else:
            print(f"  ✅ {pkg}: {version} (installed: {installed_version})")
    
    # Check for security issues
    print("\n🔒 Security Check:")
    security_result = subprocess.run(
        [sys.executable, "-m", "pip", "check"],
        capture_output=True,
        text=True
    )
    
    if security_result.returncode == 0:
        print("  ✅ No known security vulnerabilities")
    else:
        print(f"  ❌ Security issues found:\n{security_result.stdout}")
    
    # Check Python version
    print(f"\n🐍 Python Version: {sys.version}")
    if sys.version_info >= (3, 10):
        print("  ✅ Python version meets requirements")
    else:
        print("  ❌ Python 3.10+ required")
    
    print("\n✨ Dependency verification complete!")


if __name__ == "__main__":
    main()