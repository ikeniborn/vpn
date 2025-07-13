"""Enhanced shell completion system for Typer CLI.

This module provides advanced shell completion capabilities using Typer 0.16+ features:
- Dynamic completion for user names, server names, protocols
- Context-aware completion suggestions
- Custom completion for file paths and configurations
- Completion caching for performance
"""

import time
from collections.abc import Callable
from functools import lru_cache
from pathlib import Path
from typing import Any

import typer
from rich.console import Console

console = Console()


class CompletionCache:
    """Cache system for completion suggestions to improve performance."""

    def __init__(self, ttl_seconds: int = 300):  # 5 minutes TTL
        """Initialize completion cache."""
        self.ttl_seconds = ttl_seconds
        self._cache: dict[str, dict[str, Any]] = {}

    def get(self, key: str) -> list[str] | None:
        """Get cached completion results."""
        if key in self._cache:
            cached_data = self._cache[key]
            if time.time() - cached_data['timestamp'] < self.ttl_seconds:
                return cached_data['data']
            else:
                # Expired, remove from cache
                del self._cache[key]
        return None

    def set(self, key: str, data: list[str]) -> None:
        """Cache completion results."""
        self._cache[key] = {
            'data': data,
            'timestamp': time.time()
        }

    def clear(self) -> None:
        """Clear all cached data."""
        self._cache.clear()


# Global completion cache
completion_cache = CompletionCache()


def complete_user_names(incomplete: str) -> list[str]:
    """Complete user names from the database."""
    cache_key = f"users:{incomplete}"
    cached = completion_cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        # Get users asynchronously
        import asyncio

        from vpn.services.user_manager import UserManager

        async def get_users():
            user_manager = UserManager()
            users = await user_manager.list()
            return [user.username for user in users if user.username.startswith(incomplete)]

        # Run in event loop if available, otherwise create new one
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                # If we're in an async context, we can't run another event loop
                # Return cached results or empty list
                return completion_cache.get("users:*") or []
            else:
                users = loop.run_until_complete(get_users())
        except RuntimeError:
            # No event loop, create new one
            users = asyncio.run(get_users())

        # Cache results
        completion_cache.set(cache_key, users)
        return users

    except Exception:
        # If anything fails, return empty list
        return []


def complete_server_names(incomplete: str) -> list[str]:
    """Complete server names from the configuration."""
    cache_key = f"servers:{incomplete}"
    cached = completion_cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        import asyncio

        from vpn.services.docker_manager import DockerManager

        async def get_servers():
            docker_manager = DockerManager()
            containers = await docker_manager.list_containers()

            server_names = []
            for container in containers:
                # Extract server names from container names
                name = container.get('name', '')
                if name.startswith('vpn-'):
                    # Extract readable name from container name
                    parts = name.split('-')
                    if len(parts) >= 3:
                        server_name = '-'.join(parts[2:])  # Skip 'vpn' and protocol
                        if server_name.startswith(incomplete):
                            server_names.append(server_name)

            return server_names

        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                return completion_cache.get("servers:*") or []
            else:
                servers = loop.run_until_complete(get_servers())
        except RuntimeError:
            servers = asyncio.run(get_servers())

        completion_cache.set(cache_key, servers)
        return servers

    except Exception:
        return []


def complete_protocols(incomplete: str) -> list[str]:
    """Complete protocol names."""
    protocols = ["vless", "shadowsocks", "wireguard", "http", "socks5", "unified_proxy"]
    return [proto for proto in protocols if proto.startswith(incomplete)]


def complete_formats(incomplete: str) -> list[str]:
    """Complete output format names."""
    formats = ["table", "json", "yaml", "plain", "csv"]
    return [fmt for fmt in formats if fmt.startswith(incomplete)]


def complete_log_levels(incomplete: str) -> list[str]:
    """Complete log level names."""
    levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
    return [level.lower() for level in levels if level.lower().startswith(incomplete.lower())]


def complete_config_files(incomplete: str) -> list[str]:
    """Complete configuration file paths."""
    try:
        from vpn.core.config import settings

        # Common config file locations
        search_paths = [
            Path.cwd(),
            settings.config_path,
            Path.home() / ".config" / "vpn-manager",
            Path("/etc/vpn-manager"),
        ]

        suggestions = []

        for search_path in search_paths:
            if search_path.exists():
                # Look for config files
                for pattern in ["*.yaml", "*.yml", "*.toml", "*.json"]:
                    for file_path in search_path.glob(pattern):
                        if file_path.name.startswith(incomplete):
                            suggestions.append(str(file_path))

        return suggestions[:10]  # Limit to 10 suggestions

    except Exception:
        return []


def complete_theme_names(incomplete: str) -> list[str]:
    """Complete theme names."""
    try:
        from vpn.tui.components import get_global_theme_manager

        theme_manager = get_global_theme_manager()
        if theme_manager:
            themes = theme_manager.get_themes()
            return [theme.metadata.name for theme in themes
                   if theme.metadata.name.lower().startswith(incomplete.lower())]

        # Fallback to built-in theme names
        builtin_themes = ["Dark Blue", "Light Blue", "Dark Green", "Cyberpunk", "Minimal Mono"]
        return [theme for theme in builtin_themes if theme.lower().startswith(incomplete.lower())]

    except Exception:
        # Fallback to built-in themes
        builtin_themes = ["Dark Blue", "Light Blue", "Dark Green", "Cyberpunk", "Minimal Mono"]
        return [theme for theme in builtin_themes if theme.lower().startswith(incomplete.lower())]


def complete_docker_images(incomplete: str) -> list[str]:
    """Complete Docker image names for VPN protocols."""
    # Common VPN images
    images = [
        "ghcr.io/xtls/xray-core:latest",
        "shadowsocks/shadowsocks-libev:latest",
        "linuxserver/wireguard:latest",
        "nginx:alpine",
        "haproxy:alpine",
        "vpn/vless-reality:latest",
        "vpn/shadowsocks:latest",
        "vpn/wireguard:latest",
    ]

    return [img for img in images if img.startswith(incomplete)]


def complete_network_interfaces(incomplete: str) -> list[str]:
    """Complete network interface names."""
    try:
        import psutil

        interfaces = []
        for interface_name, _ in psutil.net_if_addrs().items():
            if interface_name.startswith(incomplete):
                interfaces.append(interface_name)

        return interfaces

    except Exception:
        # Fallback to common interface names
        common_interfaces = ["eth0", "ens33", "wlan0", "docker0", "br-", "veth"]
        return [iface for iface in common_interfaces if iface.startswith(incomplete)]


def complete_ports(incomplete: str) -> list[str]:
    """Complete common port numbers."""
    common_ports = [
        "80", "443", "8080", "8443", "8388", "1080", "3128",
        "51820", "1194", "500", "4500", "22", "3389", "5432", "3306"
    ]

    return [port for port in common_ports if port.startswith(incomplete)]


def complete_countries(incomplete: str) -> list[str]:
    """Complete country codes for server locations."""
    countries = [
        "US", "UK", "DE", "FR", "JP", "CA", "AU", "NL", "SE", "NO",
        "CH", "SG", "HK", "KR", "IN", "BR", "MX", "ES", "IT", "RU"
    ]

    return [country for country in countries if country.lower().startswith(incomplete.lower())]


@lru_cache(maxsize=128)
def get_completion_for_context(context: str, incomplete: str) -> list[str]:
    """Get completion suggestions based on context."""
    completion_map = {
        'user': complete_user_names,
        'server': complete_server_names,
        'protocol': complete_protocols,
        'format': complete_formats,
        'log_level': complete_log_levels,
        'config_file': complete_config_files,
        'theme': complete_theme_names,
        'docker_image': complete_docker_images,
        'network_interface': complete_network_interfaces,
        'port': complete_ports,
        'country': complete_countries,
    }

    completion_func = completion_map.get(context)
    if completion_func:
        return completion_func(incomplete)

    return []


def install_completion_for_command(command_app: typer.Typer, completions: dict[str, str]) -> None:
    """Install completion functions for command parameters."""

    def create_completion_callback(context: str):
        """Create a completion callback for a specific context."""
        def completion_callback(incomplete: str) -> list[str]:
            return get_completion_for_context(context, incomplete)
        return completion_callback

    # This would be used to enhance existing commands with completion
    # The actual implementation would require modifying each command definition
    pass


class EnhancedCompletion:
    """Enhanced completion system with advanced features."""

    def __init__(self):
        """Initialize enhanced completion system."""
        self.cache = CompletionCache()
        self.completion_hooks: dict[str, Callable] = {}

    def register_completion_hook(self, context: str, func: Callable) -> None:
        """Register a custom completion hook."""
        self.completion_hooks[context] = func

    def get_completions(self, context: str, incomplete: str, **kwargs) -> list[str]:
        """Get completions with enhanced context awareness."""
        # Try custom hooks first
        if context in self.completion_hooks:
            try:
                return self.completion_hooks[context](incomplete, **kwargs)
            except Exception:
                pass  # Fall back to default completion

        # Use default completion
        return get_completion_for_context(context, incomplete)

    def preload_cache(self) -> None:
        """Preload commonly used completions into cache."""
        try:
            # Preload user and server lists
            complete_user_names("")
            complete_server_names("")

            console.print("[dim]Completion cache preloaded[/dim]")
        except Exception:
            pass  # Not critical if preloading fails


# Global enhanced completion instance
enhanced_completion = EnhancedCompletion()


def setup_enhanced_completion():
    """Set up enhanced completion system."""
    # Register additional completion hooks
    enhanced_completion.register_completion_hook(
        'active_users',
        lambda incomplete, **kwargs: [
            user for user in complete_user_names(incomplete)
            # Could add filtering for only active users here
        ]
    )

    enhanced_completion.register_completion_hook(
        'running_servers',
        lambda incomplete, **kwargs: [
            server for server in complete_server_names(incomplete)
            # Could add filtering for only running servers here
        ]
    )

    # Preload cache for better performance
    enhanced_completion.preload_cache()


def completion_examples():
    """Show examples of enhanced completion usage."""
    examples = [
        "# User operations with completion",
        "vpn users list <TAB>                    # Shows available users",
        "vpn users delete john<TAB>              # Completes to john_doe",
        "vpn users create --protocol vl<TAB>     # Completes to vless",
        "",
        "# Server operations with completion",
        "vpn server status prod<TAB>             # Completes server names",
        "vpn server logs --format j<TAB>         # Completes to json",
        "vpn server create --image shadow<TAB>   # Completes Docker images",
        "",
        "# Configuration with completion",
        "vpn config set --log-level d<TAB>       # Completes to debug",
        "vpn config load ~/.config/vpn<TAB>      # Completes config files",
        "vpn config theme cyber<TAB>             # Completes to cyberpunk",
        "",
        "# Enable completion:",
        "vpn completions bash --install          # Install bash completion",
        "vpn completions zsh --install           # Install zsh completion",
        "vpn completions fish --install          # Install fish completion",
    ]

    return "\n".join(examples)
