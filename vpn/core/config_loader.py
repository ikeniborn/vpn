"""Unified configuration loader supporting multiple formats.
"""

from pathlib import Path
from typing import Any

import toml
import yaml

from vpn.core.exceptions import ConfigurationError


class ConfigLoader:
    """Unified configuration loader supporting YAML and TOML formats."""

    SUPPORTED_FORMATS = {
        '.yaml': 'yaml',
        '.yml': 'yaml',
        '.toml': 'toml',
    }

    @classmethod
    def load_config(cls, config_path: str | Path) -> dict[str, Any]:
        """Load configuration from file with format auto-detection.
        
        Args:
            config_path: Path to configuration file
            
        Returns:
            Dictionary with configuration data
            
        Raises:
            ConfigurationError: If file format is unsupported or parsing fails
        """
        config_path = Path(config_path)

        if not config_path.exists():
            raise ConfigurationError(
                f"Configuration file not found: {config_path}",
                suggestions=[
                    f"Create configuration file at: {config_path}",
                    "Use --config flag to specify different config file",
                    "Run 'vpn config generate' to create example config"
                ]
            )

        # Detect format by extension
        suffix = config_path.suffix.lower()
        if suffix not in cls.SUPPORTED_FORMATS:
            raise ConfigurationError(
                f"Unsupported configuration format: {suffix}",
                details={"file": str(config_path)},
                suggestions=[
                    "Use .yaml, .yml, or .toml file extension",
                    "Convert your config to supported format"
                ]
            )

        format_type = cls.SUPPORTED_FORMATS[suffix]

        try:
            with open(config_path) as f:
                if format_type == 'yaml':
                    return yaml.safe_load(f) or {}
                else:  # toml
                    return toml.load(f)
        except yaml.YAMLError as e:
            raise ConfigurationError(
                f"Invalid YAML configuration: {e}",
                details={"file": str(config_path)},
                suggestions=[
                    "Check YAML syntax at: https://www.yamllint.com/",
                    "Ensure proper indentation (spaces, not tabs)",
                    "Check for missing colons or quotes"
                ]
            )
        except toml.TomlDecodeError as e:
            raise ConfigurationError(
                f"Invalid TOML configuration: {e}",
                details={"file": str(config_path)},
                suggestions=[
                    "Check TOML syntax at: https://www.toml-lint.com/",
                    "Ensure strings are properly quoted",
                    "Check for missing brackets or equals signs"
                ]
            )
        except Exception as e:
            raise ConfigurationError(
                f"Failed to load configuration: {e}",
                details={"file": str(config_path), "format": format_type}
            )

    @classmethod
    def save_config(
        cls,
        config_data: dict[str, Any],
        config_path: str | Path,
        format_type: str | None = None
    ) -> None:
        """Save configuration to file.
        
        Args:
            config_data: Configuration dictionary
            config_path: Path to save configuration
            format_type: Force specific format ('yaml' or 'toml'), 
                        auto-detect if None
        """
        config_path = Path(config_path)

        # Auto-detect format if not specified
        if format_type is None:
            suffix = config_path.suffix.lower()
            if suffix in cls.SUPPORTED_FORMATS:
                format_type = cls.SUPPORTED_FORMATS[suffix]
            else:
                format_type = 'toml'  # Default to TOML

        # Ensure parent directory exists
        config_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            with open(config_path, 'w') as f:
                if format_type == 'yaml':
                    yaml.dump(
                        config_data,
                        f,
                        default_flow_style=False,
                        sort_keys=False,
                        allow_unicode=True
                    )
                else:  # toml
                    toml.dump(config_data, f)
        except Exception as e:
            raise ConfigurationError(
                f"Failed to save configuration: {e}",
                details={"file": str(config_path), "format": format_type}
            )

    @classmethod
    def merge_configs(
        cls,
        *configs: dict[str, Any],
        deep: bool = True
    ) -> dict[str, Any]:
        """Merge multiple configuration dictionaries.
        
        Args:
            *configs: Configuration dictionaries to merge
            deep: Whether to perform deep merge
            
        Returns:
            Merged configuration dictionary
        """
        result = {}

        for config in configs:
            if deep:
                result = cls._deep_merge(result, config)
            else:
                result.update(config)

        return result

    @classmethod
    def _deep_merge(cls, base: dict[str, Any], update: dict[str, Any]) -> dict[str, Any]:
        """Deep merge two dictionaries."""
        for key, value in update.items():
            if key in base and isinstance(base[key], dict) and isinstance(value, dict):
                base[key] = cls._deep_merge(base[key], value)
            else:
                base[key] = value
        return base

    @classmethod
    def find_config_file(
        cls,
        name: str = "config",
        search_paths: list[Path] | None = None
    ) -> Path | None:
        """Find configuration file in standard locations.
        
        Args:
            name: Base name of config file (without extension)
            search_paths: Additional paths to search
            
        Returns:
            Path to first found config file, or None
        """
        if search_paths is None:
            search_paths = []

        # Standard search locations
        standard_paths = [
            Path.cwd(),  # Current directory
            Path.home() / ".config" / "vpn-manager",  # User config
            Path("/etc") / "vpn-manager",  # System config
        ]

        all_paths = search_paths + standard_paths

        # Try each format in each location
        for path in all_paths:
            for ext in cls.SUPPORTED_FORMATS:
                config_file = path / f"{name}{ext}"
                if config_file.exists():
                    return config_file

        return None

    @classmethod
    def generate_example_config(
        cls,
        format_type: str = "yaml",
        include_comments: bool = True
    ) -> str:
        """Generate example configuration file content.
        
        Args:
            format_type: 'yaml' or 'toml'
            include_comments: Whether to include explanatory comments
            
        Returns:
            Example configuration as string
        """
        example_data = {
            "app": {
                "debug": False,
                "log_level": "INFO",
            },
            "server": {
                "default_protocol": "vless",
                "enable_firewall": True,
                "auto_start_servers": True,
            },
            "tui": {
                "theme": "dark",
                "refresh_rate": 1,
                "show_stats": True,
            },
            "docker": {
                "socket": "/var/run/docker.sock",
                "timeout": 30,
            },
            "database": {
                "url": "sqlite+aiosqlite:///db/vpn.db",
                "echo": False,
            }
        }

        if format_type == "yaml":
            content = "# VPN Manager Configuration\n"
            if include_comments:
                content += "# This is an example configuration file in YAML format\n\n"

            # Add comments for each section
            yaml_lines = yaml.dump(
                example_data,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True
            ).split('\n')

            result = []
            for line in yaml_lines:
                if line.startswith('app:') and include_comments:
                    result.append("# Application settings")
                elif line.startswith('server:') and include_comments:
                    result.append("\n# VPN server defaults")
                elif line.startswith('tui:') and include_comments:
                    result.append("\n# Terminal UI settings")
                elif line.startswith('docker:') and include_comments:
                    result.append("\n# Docker configuration")
                elif line.startswith('database:') and include_comments:
                    result.append("\n# Database settings")
                result.append(line)

            content += '\n'.join(result)

        else:  # toml
            content = "# VPN Manager Configuration\n"
            if include_comments:
                content += "# This is an example configuration file in TOML format\n\n"

            # TOML with sections
            if include_comments:
                content += "# Application settings\n"
            content += "[app]\n"
            content += f"debug = {str(example_data['app']['debug']).lower()}\n"
            content += f'log_level = "{example_data["app"]["log_level"]}"\n\n'

            if include_comments:
                content += "# VPN server defaults\n"
            content += "[server]\n"
            content += f'default_protocol = "{example_data["server"]["default_protocol"]}"\n'
            content += f"enable_firewall = {str(example_data['server']['enable_firewall']).lower()}\n"
            content += f"auto_start_servers = {str(example_data['server']['auto_start_servers']).lower()}\n\n"

            if include_comments:
                content += "# Terminal UI settings\n"
            content += "[tui]\n"
            content += f'theme = "{example_data["tui"]["theme"]}"\n'
            content += f"refresh_rate = {example_data['tui']['refresh_rate']}\n"
            content += f"show_stats = {str(example_data['tui']['show_stats']).lower()}\n\n"

            if include_comments:
                content += "# Docker configuration\n"
            content += "[docker]\n"
            content += f'socket = "{example_data["docker"]["socket"]}"\n'
            content += f"timeout = {example_data['docker']['timeout']}\n\n"

            if include_comments:
                content += "# Database settings\n"
            content += "[database]\n"
            content += f'url = "{example_data["database"]["url"]}"\n'
            content += f"echo = {str(example_data['database']['echo']).lower()}\n"

        return content
