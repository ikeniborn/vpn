"""Configuration migration system for updating config files between versions.
"""

import shutil
from datetime import datetime
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from vpn.core.config_loader import ConfigLoader
from vpn.core.enhanced_config import EnhancedSettings
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ConfigVersion(BaseModel):
    """Configuration version information."""
    version: str = Field(description="Configuration version")
    created_at: datetime = Field(description="Creation timestamp")
    app_version: str = Field(description="Application version that created this config")
    migration_history: list[str] = Field(
        default_factory=list,
        description="List of applied migrations"
    )


class MigrationResult(BaseModel):
    """Result of a configuration migration."""
    success: bool = Field(description="Whether migration was successful")
    from_version: str = Field(description="Source version")
    to_version: str = Field(description="Target version")
    changes_made: list[str] = Field(description="List of changes made during migration")
    warnings: list[str] = Field(
        default_factory=list,
        description="Warnings generated during migration"
    )
    backup_path: Path | None = Field(
        default=None,
        description="Path to backup file created before migration"
    )


class ConfigMigrator:
    """Handles configuration file migrations between versions."""

    # Current configuration version
    CURRENT_VERSION = "2.0.0"

    # Mapping of old config keys to new nested structure
    MIGRATION_MAP = {
        "1.0.0": {
            # Direct key mappings
            "install_path": "paths.install_path",
            "config_path": "paths.config_path",
            "data_path": "paths.data_path",
            "database_url": "database.url",
            "database_echo": "database.echo",
            "docker_socket": "docker.socket",
            "docker_timeout": "docker.timeout",
            "docker_max_connections": "docker.max_connections",
            "default_protocol": "default_protocol",
            "default_port_range": "network.default_port_range",
            "enable_firewall": "network.enable_firewall",
            "enable_auth": "security.enable_auth",
            "secret_key": "security.secret_key",
            "token_expire_minutes": "security.token_expire_minutes",
            "enable_metrics": "monitoring.enable_metrics",
            "metrics_port": "monitoring.metrics_port",
            "tui_theme": "tui.theme",
            "tui_refresh_rate": "tui.refresh_rate",

            # Removed/deprecated keys
            "_deprecated": [
                "old_feature_flag",
                "legacy_setting",
            ]
        },
        "1.5.0": {
            # Additional mappings for 1.5.0 -> 2.0.0
            "auto_start_servers": "auto_start_servers",
            "log_level": "log_level",
            "alert_cpu_threshold": "monitoring.alert_cpu_threshold",
            "alert_memory_threshold": "monitoring.alert_memory_threshold",
            "alert_disk_threshold": "monitoring.alert_disk_threshold",

            "_deprecated": [
                "old_monitoring_endpoint",
            ]
        }
    }

    def __init__(self):
        """Initialize config migrator."""
        self.loader = ConfigLoader()

    def detect_config_version(self, config_data: dict[str, Any]) -> str:
        """Detect configuration version from config data.
        
        Args:
            config_data: Configuration dictionary
            
        Returns:
            Detected version string
        """
        # Check for explicit version field
        if "version" in config_data:
            return config_data["version"]

        # Check for version in metadata
        if "meta" in config_data and "version" in config_data["meta"]:
            return config_data["meta"]["version"]

        # Detect version based on structure
        if "paths" in config_data or "database" in config_data:
            return "2.0.0"  # New structure
        elif "tui_theme" in config_data or "docker_socket" in config_data:
            return "1.5.0"  # Mid-version structure
        else:
            return "1.0.0"  # Legacy structure

    def needs_migration(self, config_path: Path) -> bool:
        """Check if configuration file needs migration.
        
        Args:
            config_path: Path to configuration file
            
        Returns:
            True if migration is needed
        """
        try:
            config_data = self.loader.load_config(config_path)
            current_version = self.detect_config_version(config_data)
            return current_version != self.CURRENT_VERSION
        except Exception as e:
            logger.warning(f"Could not detect config version: {e}")
            return True  # Assume migration needed if can't detect

    def migrate_config(
        self,
        config_path: Path,
        backup: bool = True,
        dry_run: bool = False
    ) -> MigrationResult:
        """Migrate configuration file to current version.
        
        Args:
            config_path: Path to configuration file
            backup: Whether to create backup before migration
            dry_run: Whether to perform dry run without saving changes
            
        Returns:
            Migration result
        """
        logger.info(f"Starting migration of config file: {config_path}")

        try:
            # Load current config
            config_data = self.loader.load_config(config_path)
            current_version = self.detect_config_version(config_data)

            logger.info(f"Detected config version: {current_version}")

            if current_version == self.CURRENT_VERSION:
                return MigrationResult(
                    success=True,
                    from_version=current_version,
                    to_version=self.CURRENT_VERSION,
                    changes_made=["No migration needed - already current version"]
                )

            # Create backup if requested
            backup_path = None
            if backup and not dry_run:
                backup_path = self._create_backup(config_path)

            # Perform migration
            migrated_data, changes, warnings = self._migrate_data(
                config_data,
                current_version,
                self.CURRENT_VERSION
            )

            # Save migrated config if not dry run
            if not dry_run:
                self._save_migrated_config(config_path, migrated_data)
                logger.info(f"Migration completed successfully: {config_path}")
            else:
                logger.info(f"Dry run completed for: {config_path}")

            return MigrationResult(
                success=True,
                from_version=current_version,
                to_version=self.CURRENT_VERSION,
                changes_made=changes,
                warnings=warnings,
                backup_path=backup_path
            )

        except Exception as e:
            logger.error(f"Migration failed for {config_path}: {e}")
            return MigrationResult(
                success=False,
                from_version=current_version if 'current_version' in locals() else "unknown",
                to_version=self.CURRENT_VERSION,
                changes_made=[],
                warnings=[f"Migration failed: {e!s}"]
            )

    def _migrate_data(
        self,
        config_data: dict[str, Any],
        from_version: str,
        to_version: str
    ) -> tuple[dict[str, Any], list[str], list[str]]:
        """Migrate configuration data between versions.
        
        Args:
            config_data: Original configuration data
            from_version: Source version
            to_version: Target version
            
        Returns:
            Tuple of (migrated_data, changes, warnings)
        """
        changes = []
        warnings = []
        migrated_data = {}

        # Get migration path
        migration_path = self._get_migration_path(from_version, to_version)

        for version in migration_path:
            if version in self.MIGRATION_MAP:
                config_data, version_changes, version_warnings = self._apply_version_migration(
                    config_data,
                    version
                )
                changes.extend(version_changes)
                warnings.extend(version_warnings)

        # Create new structure
        migrated_data = self._create_new_structure(config_data)

        # Add metadata
        migrated_data["meta"] = {
            "version": to_version,
            "migrated_at": datetime.utcnow().isoformat(),
            "migration_history": changes
        }

        changes.append(f"Updated config structure to version {to_version}")

        return migrated_data, changes, warnings

    def _get_migration_path(self, from_version: str, to_version: str) -> list[str]:
        """Get ordered list of versions for migration path.
        
        Args:
            from_version: Source version
            to_version: Target version
            
        Returns:
            List of version strings in migration order
        """
        # Simple version ordering - in real implementation, you might want
        # more sophisticated version comparison
        version_order = ["1.0.0", "1.5.0", "2.0.0"]

        try:
            from_idx = version_order.index(from_version)
            to_idx = version_order.index(to_version)

            if from_idx < to_idx:
                return version_order[from_idx:to_idx]
            else:
                return []  # No migration needed or downgrade
        except ValueError:
            logger.warning(f"Unknown version in migration path: {from_version} -> {to_version}")
            return []

    def _apply_version_migration(
        self,
        config_data: dict[str, Any],
        version: str
    ) -> tuple[dict[str, Any], list[str], list[str]]:
        """Apply migration for specific version.
        
        Args:
            config_data: Configuration data
            version: Version to migrate from
            
        Returns:
            Tuple of (updated_data, changes, warnings)
        """
        changes = []
        warnings = []

        if version not in self.MIGRATION_MAP:
            return config_data, changes, warnings

        migration_rules = self.MIGRATION_MAP[version]
        deprecated_keys = migration_rules.get("_deprecated", [])

        # Remove deprecated keys
        for key in deprecated_keys:
            if key in config_data:
                del config_data[key]
                changes.append(f"Removed deprecated setting: {key}")
                warnings.append(f"Deprecated setting '{key}' was removed during migration")

        return config_data, changes, warnings

    def _create_new_structure(self, config_data: dict[str, Any]) -> dict[str, Any]:
        """Create new nested configuration structure.
        
        Args:
            config_data: Original flat configuration data
            
        Returns:
            Nested configuration structure
        """
        # Start with default structure
        default_settings = EnhancedSettings()
        new_config = default_settings.model_dump()

        # Map old keys to new structure
        for old_key, value in config_data.items():
            if old_key == "meta":
                continue  # Skip metadata

            # Find mapping for this key
            new_path = self._find_key_mapping(old_key)
            if new_path:
                self._set_nested_value(new_config, new_path, value)
            else:
                # Keep unmapped keys at root level
                new_config[old_key] = value

        return new_config

    def _find_key_mapping(self, old_key: str) -> str | None:
        """Find new path for old configuration key.
        
        Args:
            old_key: Old configuration key
            
        Returns:
            New nested path or None if not found
        """
        # Search through all migration maps
        for version_map in self.MIGRATION_MAP.values():
            if old_key in version_map and not old_key.startswith("_"):
                return version_map[old_key]

        return None

    def _set_nested_value(self, config: dict[str, Any], path: str, value: Any):
        """Set value in nested configuration structure.
        
        Args:
            config: Configuration dictionary
            path: Dotted path (e.g., "database.url")
            value: Value to set
        """
        parts = path.split(".")
        current = config

        # Navigate to parent
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]

        # Set final value
        current[parts[-1]] = value

    def _create_backup(self, config_path: Path) -> Path:
        """Create backup of configuration file.
        
        Args:
            config_path: Path to configuration file
            
        Returns:
            Path to backup file
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"{config_path.stem}_backup_{timestamp}{config_path.suffix}"
        backup_path = config_path.parent / backup_name

        shutil.copy2(config_path, backup_path)
        logger.info(f"Created config backup: {backup_path}")

        return backup_path

    def _save_migrated_config(self, config_path: Path, config_data: dict[str, Any]):
        """Save migrated configuration to file.
        
        Args:
            config_path: Path to save configuration
            config_data: Migrated configuration data
        """
        # Determine format from file extension
        if config_path.suffix.lower() in [".yaml", ".yml"]:
            format_type = "yaml"
        else:
            format_type = "toml"

        self.loader.save_config(config_data, config_path, format_type)

    def migrate_all_configs(
        self,
        search_paths: list[Path],
        backup: bool = True,
        dry_run: bool = False
    ) -> list[MigrationResult]:
        """Migrate all configuration files found in search paths.
        
        Args:
            search_paths: Paths to search for configuration files
            backup: Whether to create backups
            dry_run: Whether to perform dry run
            
        Returns:
            List of migration results
        """
        results = []

        for search_path in search_paths:
            if not search_path.exists():
                continue

            # Find config files
            config_files = []
            for pattern in ["*.yaml", "*.yml", "*.toml"]:
                config_files.extend(search_path.glob(pattern))

            for config_file in config_files:
                if self.needs_migration(config_file):
                    result = self.migrate_config(config_file, backup, dry_run)
                    results.append(result)
                else:
                    logger.info(f"Config file up to date: {config_file}")

        return results

    def validate_migrated_config(self, config_path: Path) -> bool:
        """Validate migrated configuration file.
        
        Args:
            config_path: Path to configuration file
            
        Returns:
            True if configuration is valid
        """
        try:
            config_data = self.loader.load_config(config_path)

            # Try to create settings instance
            EnhancedSettings(**config_data)

            logger.info(f"Migrated config is valid: {config_path}")
            return True

        except Exception as e:
            logger.error(f"Migrated config validation failed: {e}")
            return False


def migrate_user_config(dry_run: bool = False) -> list[MigrationResult]:
    """Migrate user configuration files.
    
    Args:
        dry_run: Whether to perform dry run
        
    Returns:
        List of migration results
    """
    migrator = ConfigMigrator()

    # Standard search paths
    search_paths = [
        Path.cwd(),
        Path.home() / ".config" / "vpn-manager",
        Path("/etc/vpn-manager"),
    ]

    logger.info("Starting configuration migration...")
    results = migrator.migrate_all_configs(search_paths, backup=True, dry_run=dry_run)

    if results:
        logger.info(f"Migration completed. {len(results)} files processed.")

        # Print summary
        successful = sum(1 for r in results if r.success)
        failed = len(results) - successful

        if successful:
            logger.info(f"Successfully migrated {successful} configuration files")
        if failed:
            logger.warning(f"Failed to migrate {failed} configuration files")
    else:
        logger.info("No configuration files needed migration")

    return results


def rollback_migration(backup_path: Path, original_path: Path) -> bool:
    """Rollback configuration migration using backup.
    
    Args:
        backup_path: Path to backup file
        original_path: Path to original configuration file
        
    Returns:
        True if rollback was successful
    """
    try:
        if not backup_path.exists():
            logger.error(f"Backup file not found: {backup_path}")
            return False

        shutil.copy2(backup_path, original_path)
        logger.info(f"Successfully rolled back configuration: {original_path}")
        return True

    except Exception as e:
        logger.error(f"Rollback failed: {e}")
        return False
