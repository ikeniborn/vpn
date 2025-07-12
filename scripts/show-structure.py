#!/usr/bin/env python3
"""Show project structure in a clean format."""

import os
from pathlib import Path


def show_tree(directory, prefix="", max_depth=2, current_depth=0):
    """Display directory tree structure."""
    if current_depth >= max_depth:
        return
    
    items = sorted(Path(directory).iterdir(), key=lambda x: (not x.is_dir(), x.name))
    
    for i, item in enumerate(items):
        is_last = i == len(items) - 1
        current_prefix = "└── " if is_last else "├── "
        print(f"{prefix}{current_prefix}{item.name}")
        
        if item.is_dir() and not item.name.startswith('.') and current_depth < max_depth - 1:
            extension = "    " if is_last else "│   "
            show_tree(item, prefix + extension, max_depth, current_depth + 1)


def main():
    """Main function to display project structure."""
    print("📁 VPN Manager - Clean Project Structure")
    print("=" * 50)
    print()
    
    # Root level - show only directories and key files
    print("📂 Root Directory:")
    root_items = {
        "Directories": [],
        "Key Files": [],
        "Config Files": []
    }
    
    for item in sorted(Path(".").iterdir()):
        if item.name.startswith('.git') and item.name != '.github':
            continue
            
        if item.is_dir():
            if not item.name.startswith('.'):
                root_items["Directories"].append(item.name)
        else:
            if item.suffix in ['.md', '.toml', '.txt', '.yml']:
                root_items["Config Files"].append(item.name)
            elif item.name == 'Makefile':
                root_items["Key Files"].append(item.name)
    
    for category, items in root_items.items():
        if items:
            print(f"\n  {category}:")
            for item in sorted(items):
                print(f"    • {item}")
    
    print("\n" + "─" * 50)
    
    # Show key directories with depth
    key_dirs = [
        ("vpn/", "Source Code", 2),
        ("tests/", "Test Suite", 1),
        ("docs/", "Documentation", 2),
        ("config/", "Configuration", 1),
        ("docker/", "Docker Files", 1),
        (".config/", "Dev Config", 2)
    ]
    
    for dir_path, description, depth in key_dirs:
        if Path(dir_path).exists():
            print(f"\n📂 {description} ({dir_path}):")
            show_tree(dir_path, "  ", depth)
    
    # Summary statistics
    print("\n" + "─" * 50)
    print("\n📊 Project Statistics:")
    
    stats = {
        "Python files": len(list(Path("vpn").rglob("*.py"))),
        "Test files": len(list(Path("tests").rglob("test_*.py"))),
        "Documentation": len(list(Path("docs").rglob("*.md"))),
        "Config files": len(list(Path("config").glob("*"))) if Path("config").exists() else 0,
        "Docker files": len(list(Path("docker").glob("*"))) if Path("docker").exists() else 0
    }
    
    for name, count in stats.items():
        print(f"  • {name}: {count}")
    
    print("\n✨ Project structure is clean and organized!")


if __name__ == "__main__":
    main()