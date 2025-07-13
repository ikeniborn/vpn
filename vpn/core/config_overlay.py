"""Configuration overlay system for layered configuration management.

Supports multiple configuration layers with precedence:
1. Environment variables (highest priority)
2. CLI arguments
3. User config overlay files
4. User config files
5. System config files
6. Default values (lowest priority)
"""

import json
from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from vpn.core.config_loader import ConfigLoader
from vpn.core.enhanced_config import EnhancedSettings
from vpn.core.exceptions import ConfigurationError
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ConfigOverlay:
    """Manages configuration overlays and merging."""

    def __init__(self):
        """Initialize config overlay manager."""
        self.loader = ConfigLoader()
        self._overlay_cache: dict[str, dict[str, Any]] = {}

    def create_overlay(
        self,
        name: str,
        config_data: dict[str, Any],
        base_config: str | None = None,
        description: str | None = None
    ) -> Path:
        """Create a configuration overlay file.
        
        Args:
            name: Overlay name (e.g., 'development', 'production')
            config_data: Configuration data to overlay
            base_config: Base configuration to extend from
            description: Optional description of the overlay
            
        Returns:
            Path to created overlay file
        """
        settings = EnhancedSettings()
        overlay_dir = settings.paths.config_path / "overlays"
        overlay_dir.mkdir(parents=True, exist_ok=True)

        overlay_path = overlay_dir / f"{name}.yaml"

        # Create overlay metadata
        overlay_content = {
            "meta": {
                "overlay_name": name,
                "description": description or f"Configuration overlay: {name}",
                "base_config": base_config,
                "created_by": "vpn-manager",
                "overlay_version": "1.0"
            }
        }

        # Add configuration data
        overlay_content.update(config_data)

        # Save overlay file
        with open(overlay_path, 'w') as f:
            yaml.dump(overlay_content, f, default_flow_style=False, sort_keys=False)

        logger.info(f"Created configuration overlay: {overlay_path}")
        return overlay_path

    def list_overlays(self) -> list[dict[str, Any]]:
        """List available configuration overlays.
        
        Returns:
            List of overlay information dictionaries
        """
        settings = EnhancedSettings()
        overlay_dir = settings.paths.config_path / "overlays"

        if not overlay_dir.exists():
            return []

        overlays = []

        for overlay_file in overlay_dir.glob("*.yaml"):
            try:
                overlay_data = self.loader.load_config(overlay_file)
                meta = overlay_data.get("meta", {})

                overlays.append({
                    "name": overlay_file.stem,
                    "path": overlay_file,
                    "description": meta.get("description", "No description"),
                    "base_config": meta.get("base_config"),
                    "overlay_version": meta.get("overlay_version", "unknown")
                })

            except Exception as e:
                logger.warning(f"Failed to load overlay {overlay_file}: {e}")
                overlays.append({
                    "name": overlay_file.stem,
                    "path": overlay_file,
                    "description": f"Error loading overlay: {e}",
                    "base_config": None,
                    "overlay_version": "error"
                })

        return sorted(overlays, key=lambda x: x["name"])

    def load_overlay(self, name: str) -> dict[str, Any]:
        """Load a specific configuration overlay.
        
        Args:
            name: Overlay name
            
        Returns:
            Overlay configuration data
        """
        if name in self._overlay_cache:
            return self._overlay_cache[name].copy()

        settings = EnhancedSettings()
        overlay_path = settings.paths.config_path / "overlays" / f"{name}.yaml"

        if not overlay_path.exists():
            raise ConfigurationError(f"Overlay not found: {name}")

        try:
            overlay_data = self.loader.load_config(overlay_path)

            # Remove metadata from config data
            config_data = {k: v for k, v in overlay_data.items() if k != "meta"}

            # Cache the overlay
            self._overlay_cache[name] = config_data.copy()

            logger.debug(f"Loaded overlay: {name}")
            return config_data

        except Exception as e:
            raise ConfigurationError(f"Failed to load overlay {name}: {e}")

    def merge_configs(
        self,
        base_config: dict[str, Any],
        *overlay_configs: dict[str, Any]
    ) -> dict[str, Any]:
        """Merge multiple configuration dictionaries.
        
        Args:
            base_config: Base configuration
            *overlay_configs: Configuration overlays to merge (in order of precedence)
            
        Returns:
            Merged configuration
        """
        result = base_config.copy()

        for overlay in overlay_configs:
            result = self._deep_merge(result, overlay)

        return result

    def _deep_merge(self, base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
        """Deep merge two configuration dictionaries.
        
        Args:
            base: Base configuration
            overlay: Overlay configuration
            
        Returns:
            Merged configuration
        """
        result = base.copy()

        for key, value in overlay.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                # Recursively merge nested dictionaries
                result[key] = self._deep_merge(result[key], value)
            else:
                # Override or add new value
                result[key] = value

        return result

    def apply_overlays(
        self,
        base_config_path: Path | None = None,
        overlay_names: list[str] | None = None,
        environment_overrides: dict[str, Any] | None = None
    ) -> EnhancedSettings:
        """Apply configuration overlays to create final configuration.
        
        Args:
            base_config_path: Path to base configuration file
            overlay_names: List of overlay names to apply (in order)
            environment_overrides: Environment variable overrides
            
        Returns:
            Final merged configuration as EnhancedSettings
        """
        # Start with base configuration
        if base_config_path and base_config_path.exists():
            base_config = self.loader.load_config(base_config_path)
            logger.debug(f"Loaded base config: {base_config_path}")
        else:
            # Use default configuration
            base_config = {}
            logger.debug("Using default configuration as base")

        configs_to_merge = [base_config]

        # Apply overlays in order
        if overlay_names:
            for overlay_name in overlay_names:
                try:
                    overlay_config = self.load_overlay(overlay_name)
                    configs_to_merge.append(overlay_config)
                    logger.debug(f"Applied overlay: {overlay_name}")
                except Exception as e:
                    logger.error(f"Failed to apply overlay {overlay_name}: {e}")
                    raise ConfigurationError(f"Overlay application failed: {overlay_name}")

        # Apply environment overrides
        if environment_overrides:
            configs_to_merge.append(environment_overrides)
            logger.debug("Applied environment overrides")

        # Merge all configurations
        final_config = self.merge_configs(*configs_to_merge)

        # Create and validate final settings
        try:
            settings = EnhancedSettings(**final_config)
            logger.info("Configuration overlays applied successfully")
            return settings
        except ValidationError as e:
            logger.error(f"Configuration validation failed after overlay application: {e}")
            raise ConfigurationError(f"Invalid merged configuration: {e}")

    def create_predefined_overlays(self) -> list[Path]:
        """Create predefined overlay templates.
        
        Returns:
            List of created overlay paths
        """
        overlays = []

        # Development overlay
        dev_config = {
            "debug": True,
            "log_level": "DEBUG",
            "database": {
                "url": "sqlite:///dev.db",
                "echo": True
            },
            "monitoring": {
                "enable_metrics": False
            },
            "tui": {
                "theme": "light",
                "refresh_rate": 2
            }
        }
        overlays.append(self.create_overlay(
            "development",
            dev_config,
            description="Development environment configuration"
        ))

        # Production overlay
        prod_config = {
            "debug": False,
            "log_level": "INFO",
            "database": {
                "pool_size": 10,
                "echo": False
            },
            "security": {
                "token_expire_minutes": 60,
                "require_password_complexity": True
            },
            "monitoring": {
                "enable_metrics": True,
                "enable_opentelemetry": True
            },
            "tui": {
                "theme": "dark"
            }
        }
        overlays.append(self.create_overlay(
            "production",
            prod_config,
            description="Production environment configuration"
        ))

        # Testing overlay
        test_config = {
            "debug": True,
            "log_level": "WARNING",
            "database": {
                "url": "sqlite:///:memory:",
                "echo": False
            },
            "monitoring": {
                "enable_metrics": False
            },
            "security": {
                "enable_auth": False
            }
        }
        overlays.append(self.create_overlay(
            "testing",
            test_config,
            description="Testing environment configuration"
        ))

        # Docker overlay
        docker_config = {
            "paths": {
                "install_path": "/app",
                "config_path": "/app/config",
                "data_path": "/app/data"
            },
            "database": {
                "url": "postgresql://vpn:password@postgres:5432/vpn"
            },
            "docker": {
                "socket": "unix:///var/run/docker.sock"
            }
        }
        overlays.append(self.create_overlay(
            "docker",
            docker_config,
            description="Docker deployment configuration"
        ))

        # High-security overlay
        security_config = {
            "security": {
                "enable_auth": True,
                "password_min_length": 12,
                "require_password_complexity": True,
                "max_login_attempts": 3,
                "lockout_duration": 30,
                "token_expire_minutes": 30
            },
            "monitoring": {
                "enable_metrics": True,
                "alert_cpu_threshold": 70.0,
                "alert_memory_threshold": 80.0
            }
        }
        overlays.append(self.create_overlay(
            "high-security",
            security_config,
            description="High security configuration"
        ))

        logger.info(f"Created {len(overlays)} predefined overlays")
        return overlays

    def delete_overlay(self, name: str) -> bool:
        """Delete a configuration overlay.
        
        Args:
            name: Overlay name to delete
            
        Returns:
            True if deleted successfully
        """
        settings = EnhancedSettings()
        overlay_path = settings.paths.config_path / "overlays" / f"{name}.yaml"

        if not overlay_path.exists():
            logger.warning(f"Overlay not found for deletion: {name}")
            return False

        try:
            overlay_path.unlink()

            # Remove from cache
            if name in self._overlay_cache:
                del self._overlay_cache[name]

            logger.info(f"Deleted overlay: {name}")
            return True

        except Exception as e:
            logger.error(f"Failed to delete overlay {name}: {e}")
            return False

    def export_overlay(self, name: str, output_path: Path, format_type: str = "yaml") -> bool:
        """Export an overlay to a file.
        
        Args:
            name: Overlay name
            output_path: Output file path
            format_type: Export format ('yaml', 'json', 'toml')
            
        Returns:
            True if exported successfully
        """
        try:
            overlay_config = self.load_overlay(name)

            if format_type.lower() == "json":
                with open(output_path, 'w') as f:
                    json.dump(overlay_config, f, indent=2)
            elif format_type.lower() == "yaml":
                with open(output_path, 'w') as f:
                    yaml.dump(overlay_config, f, default_flow_style=False)
            elif format_type.lower() == "toml":
                import toml
                with open(output_path, 'w') as f:
                    toml.dump(overlay_config, f)
            else:
                raise ValueError(f"Unsupported export format: {format_type}")

            logger.info(f"Exported overlay {name} to {output_path}")
            return True

        except Exception as e:
            logger.error(f"Failed to export overlay {name}: {e}")
            return False

    def clear_cache(self):
        """Clear the overlay cache."""
        self._overlay_cache.clear()
        logger.debug("Overlay cache cleared")


# Global overlay manager instance
_config_overlay: ConfigOverlay | None = None


def get_config_overlay() -> ConfigOverlay:
    """Get the global config overlay manager instance."""
    global _config_overlay
    if _config_overlay is None:
        _config_overlay = ConfigOverlay()
    return _config_overlay


def apply_configuration_overlays(
    overlay_names: list[str],
    base_config_path: Path | None = None
) -> EnhancedSettings:
    """Apply configuration overlays and return final settings.
    
    Args:
        overlay_names: List of overlay names to apply
        base_config_path: Optional base configuration path
        
    Returns:
        Final merged configuration
    """
    overlay_manager = get_config_overlay()
    return overlay_manager.apply_overlays(
        base_config_path=base_config_path,
        overlay_names=overlay_names
    )
