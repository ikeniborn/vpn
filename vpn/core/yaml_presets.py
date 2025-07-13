"""YAML user-defined presets system for VPN Manager.

This module provides comprehensive support for creating, managing, and applying
user-defined presets using YAML configuration files.
"""

import os
import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel
from rich.tree import Tree

from .yaml_config import YamlConfigManager
from .yaml_schema import UserPresetSchema, ValidationResult, yaml_schema_validator
from .yaml_templates import (
    TemplateContext,
    TemplateType,
    VPNTemplateEngine,
)

console = Console()


class PresetCategory(str, Enum):
    """Categories for organizing presets."""
    DEVELOPMENT = "development"
    PRODUCTION = "production"
    TESTING = "testing"
    PERSONAL = "personal"
    BUSINESS = "business"
    GAMING = "gaming"
    STREAMING = "streaming"
    SECURITY = "security"
    CUSTOM = "custom"


class PresetScope(str, Enum):
    """Scope of preset application."""
    USER = "user"           # Single user configuration
    SERVER = "server"       # Single server configuration
    ENVIRONMENT = "environment"  # Complete environment setup
    NETWORK = "network"     # Network configuration only
    SECURITY = "security"   # Security settings only


@dataclass
class PresetMetadata:
    """Metadata for user-defined presets."""
    name: str
    category: PresetCategory
    scope: PresetScope
    description: str = ""
    version: str = "1.0.0"
    author: str = "user"
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)
    tags: set[str] = field(default_factory=set)
    dependencies: list[str] = field(default_factory=list)
    file_path: Path | None = None

    @property
    def is_valid(self) -> bool:
        """Check if preset metadata is valid."""
        return bool(self.name and self.category and self.scope)


@dataclass
class PresetApplicationResult:
    """Result of applying a preset."""
    success: bool
    preset_name: str
    applied_users: list[str] = field(default_factory=list)
    applied_servers: list[str] = field(default_factory=list)
    applied_configs: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def has_warnings(self) -> bool:
        """Check if application has warnings."""
        return len(self.warnings) > 0

    @property
    def has_errors(self) -> bool:
        """Check if application has errors."""
        return len(self.errors) > 0


class YamlPresetManager:
    """Manager for YAML user-defined presets."""

    def __init__(self, presets_dir: Path | None = None):
        """Initialize preset manager."""
        self.presets_dir = presets_dir or Path.home() / ".config" / "vpn-manager" / "presets"
        self.presets_dir.mkdir(parents=True, exist_ok=True)

        # Create category subdirectories
        for category in PresetCategory:
            (self.presets_dir / category.value).mkdir(exist_ok=True)

        self.yaml_manager = YamlConfigManager()
        self.template_engine = VPNTemplateEngine()

        # Cache for loaded presets
        self._preset_cache: dict[str, dict[str, Any]] = {}
        self._metadata_cache: dict[str, PresetMetadata] = {}

    def create_preset(
        self,
        name: str,
        category: PresetCategory,
        scope: PresetScope,
        description: str = "",
        template_vars: dict[str, Any] | None = None,
        base_template: str | None = None
    ) -> bool:
        """Create a new user-defined preset.
        
        Args:
            name: Preset name
            category: Preset category
            scope: Preset scope
            description: Preset description
            template_vars: Variables for template rendering
            base_template: Base template to use
        """
        try:
            # Validate preset name
            if not self._validate_preset_name(name):
                console.print(f"[red]Invalid preset name: {name}[/red]")
                return False

            # Check if preset already exists
            if self.preset_exists(name):
                console.print(f"[red]Preset '{name}' already exists[/red]")
                return False

            # Determine preset file path
            preset_path = self.presets_dir / category.value / f"{name}.yaml"

            # Create preset content
            if base_template:
                # Use existing template
                template_context = TemplateContext(
                    template_type=TemplateType.USER_PRESET,
                    variables=template_vars or {}
                )

                result = self.template_engine.render_template(
                    base_template,
                    template_context
                )

                if not result.is_valid:
                    console.print(f"[red]Failed to render template: {result.errors}[/red]")
                    return False

                preset_content = result.content
            else:
                # Create minimal preset structure
                preset_content = self._create_minimal_preset(name, category, scope, description, template_vars)

            # Save preset file
            with open(preset_path, 'w', encoding='utf-8') as f:
                f.write(preset_content)

            # Clear cache
            self._clear_cache()

            console.print(f"[green]✓ Created preset '{name}' in category '{category.value}'[/green]")
            return True

        except Exception as e:
            console.print(f"[red]Error creating preset: {e}[/red]")
            return False

    def load_preset(self, name: str) -> dict[str, Any] | None:
        """Load preset by name."""
        if name in self._preset_cache:
            return self._preset_cache[name]

        preset_path = self._find_preset_path(name)
        if not preset_path:
            return None

        try:
            result = self.yaml_manager.load_yaml(
                preset_path,
                validate_schema=True,
                schema_model=UserPresetSchema
            )

            if not result.is_valid:
                console.print(f"[red]Invalid preset '{name}': {result.errors}[/red]")
                return None

            # Cache the preset
            self._preset_cache[name] = result.data
            return result.data

        except Exception as e:
            console.print(f"[red]Error loading preset '{name}': {e}[/red]")
            return None

    def save_preset(self, name: str, preset_data: dict[str, Any]) -> bool:
        """Save preset data."""
        try:
            # Validate preset data
            validation_result = yaml_schema_validator.validate_yaml_data(
                preset_data, "user_preset"
            )

            if not validation_result.is_valid:
                console.print(f"[red]Invalid preset data: {validation_result.errors}[/red]")
                return False

            # Determine category from preset data or metadata
            category = PresetCategory.CUSTOM
            if 'preset' in preset_data and 'category' in preset_data['preset']:
                category = PresetCategory(preset_data['preset']['category'])

            # Save to file
            preset_path = self.presets_dir / category.value / f"{name}.yaml"

            success = self.yaml_manager.save_yaml(
                validation_result.validated_data,
                preset_path,
                template_name="user_preset"
            )

            if success:
                # Update cache
                self._preset_cache[name] = validation_result.validated_data
                # Clear metadata cache to force reload
                if name in self._metadata_cache:
                    del self._metadata_cache[name]

            return success

        except Exception as e:
            console.print(f"[red]Error saving preset '{name}': {e}[/red]")
            return False

    def delete_preset(self, name: str, confirm: bool = False) -> bool:
        """Delete a preset."""
        if not confirm:
            from rich.prompt import Confirm
            if not Confirm.ask(f"Delete preset '{name}'?", default=False):
                return False

        preset_path = self._find_preset_path(name)
        if not preset_path:
            console.print(f"[red]Preset '{name}' not found[/red]")
            return False

        try:
            preset_path.unlink()

            # Clear cache
            if name in self._preset_cache:
                del self._preset_cache[name]
            if name in self._metadata_cache:
                del self._metadata_cache[name]

            console.print(f"[green]✓ Deleted preset '{name}'[/green]")
            return True

        except Exception as e:
            console.print(f"[red]Error deleting preset '{name}': {e}[/red]")
            return False

    def list_presets(
        self,
        category: PresetCategory | None = None,
        scope: PresetScope | None = None,
        tags: list[str] | None = None
    ) -> list[PresetMetadata]:
        """List presets with optional filtering."""
        presets = []

        # Search in all category directories
        search_dirs = [self.presets_dir / cat.value for cat in PresetCategory]

        for preset_dir in search_dirs:
            if not preset_dir.exists():
                continue

            for preset_file in preset_dir.glob("*.yaml"):
                metadata = self.get_preset_metadata(preset_file.stem)
                if metadata:
                    # Apply filters
                    if category and metadata.category != category:
                        continue
                    if scope and metadata.scope != scope:
                        continue
                    if tags and not set(tags).intersection(metadata.tags):
                        continue

                    presets.append(metadata)

        return sorted(presets, key=lambda p: p.name)

    def get_preset_metadata(self, name: str) -> PresetMetadata | None:
        """Get metadata for a preset."""
        if name in self._metadata_cache:
            return self._metadata_cache[name]

        preset_path = self._find_preset_path(name)
        if not preset_path:
            return None

        try:
            preset_data = self.load_preset(name)
            if not preset_data:
                return None

            # Extract metadata
            preset_info = preset_data.get('preset', {})

            metadata = PresetMetadata(
                name=name,
                category=PresetCategory(preset_info.get('category', 'custom')),
                scope=PresetScope(preset_info.get('scope', 'user')),
                description=preset_info.get('description', ''),
                version=preset_info.get('version', '1.0.0'),
                author=preset_info.get('author', 'user'),
                file_path=preset_path
            )

            # Parse timestamps
            if 'created_at' in preset_info:
                metadata.created_at = datetime.fromisoformat(preset_info['created_at'])
            if 'updated_at' in preset_info:
                metadata.updated_at = datetime.fromisoformat(preset_info['updated_at'])

            # Parse tags
            if 'tags' in preset_info:
                metadata.tags = set(preset_info['tags'])

            # Parse dependencies
            if 'dependencies' in preset_info:
                metadata.dependencies = preset_info['dependencies']

            # Get file stats
            if preset_path.exists():
                stat = preset_path.stat()
                if not metadata.created_at or metadata.created_at == metadata.updated_at:
                    metadata.created_at = datetime.fromtimestamp(stat.st_ctime)
                metadata.updated_at = datetime.fromtimestamp(stat.st_mtime)

            # Cache metadata
            self._metadata_cache[name] = metadata
            return metadata

        except Exception as e:
            console.print(f"[red]Error getting metadata for '{name}': {e}[/red]")
            return None

    def apply_preset(
        self,
        name: str,
        target_vars: dict[str, Any] | None = None,
        dry_run: bool = False
    ) -> PresetApplicationResult:
        """Apply a preset configuration.
        
        Args:
            name: Preset name to apply
            target_vars: Variables to override in preset
            dry_run: Only validate, don't actually apply
        """
        result = PresetApplicationResult(success=False, preset_name=name)

        try:
            # Load preset
            preset_data = self.load_preset(name)
            if not preset_data:
                result.errors.append(f"Preset '{name}' not found")
                return result

            # Get metadata
            metadata = self.get_preset_metadata(name)
            if not metadata:
                result.errors.append(f"Cannot get metadata for preset '{name}'")
                return result

            # Merge target variables
            if target_vars:
                preset_data = self._merge_preset_variables(preset_data, target_vars)

            # Apply based on scope
            if metadata.scope == PresetScope.USER:
                self._apply_user_preset(preset_data, result, dry_run)
            elif metadata.scope == PresetScope.SERVER:
                self._apply_server_preset(preset_data, result, dry_run)
            elif metadata.scope == PresetScope.ENVIRONMENT:
                self._apply_environment_preset(preset_data, result, dry_run)
            elif metadata.scope == PresetScope.NETWORK:
                self._apply_network_preset(preset_data, result, dry_run)
            elif metadata.scope == PresetScope.SECURITY:
                self._apply_security_preset(preset_data, result, dry_run)
            else:
                result.errors.append(f"Unknown preset scope: {metadata.scope}")
                return result

            result.success = len(result.errors) == 0

            if dry_run:
                result.warnings.append("Dry run mode - no changes were made")

        except Exception as e:
            result.errors.append(f"Error applying preset: {e}")

        return result

    def export_preset(self, name: str, output_path: Path, include_metadata: bool = True) -> bool:
        """Export preset to a file."""
        try:
            preset_data = self.load_preset(name)
            if not preset_data:
                console.print(f"[red]Preset '{name}' not found[/red]")
                return False

            # Add export metadata if requested
            if include_metadata:
                export_info = {
                    'exported_at': datetime.now().isoformat(),
                    'exported_by': os.getenv('USER', 'unknown'),
                    'source_preset': name,
                    'vpn_manager_version': '1.0.0'  # Would get from package
                }
                preset_data['export_info'] = export_info

            return self.yaml_manager.save_yaml(preset_data, output_path)

        except Exception as e:
            console.print(f"[red]Error exporting preset: {e}[/red]")
            return False

    def import_preset(
        self,
        source_path: Path,
        name: str | None = None,
        category: PresetCategory | None = None,
        overwrite: bool = False
    ) -> bool:
        """Import preset from a file."""
        try:
            # Load preset data
            result = self.yaml_manager.load_yaml(
                source_path,
                validate_schema=True,
                schema_model=UserPresetSchema
            )

            if not result.is_valid:
                console.print(f"[red]Invalid preset file: {result.errors}[/red]")
                return False

            preset_data = result.data

            # Determine preset name
            if not name:
                name = preset_data.get('preset', {}).get('name')
                if not name:
                    name = source_path.stem

            # Check if preset exists
            if self.preset_exists(name) and not overwrite:
                console.print(f"[red]Preset '{name}' already exists. Use --overwrite to replace[/red]")
                return False

            # Determine category
            if not category:
                category_str = preset_data.get('preset', {}).get('category', 'custom')
                category = PresetCategory(category_str)

            # Update preset metadata
            if 'preset' in preset_data:
                preset_data['preset']['name'] = name
                preset_data['preset']['category'] = category.value
                preset_data['preset']['imported_at'] = datetime.now().isoformat()
                preset_data['preset']['imported_from'] = str(source_path)

            # Save preset
            return self.save_preset(name, preset_data)

        except Exception as e:
            console.print(f"[red]Error importing preset: {e}[/red]")
            return False

    def duplicate_preset(
        self,
        source_name: str,
        target_name: str,
        category: PresetCategory | None = None
    ) -> bool:
        """Duplicate an existing preset."""
        try:
            # Load source preset
            source_data = self.load_preset(source_name)
            if not source_data:
                console.print(f"[red]Source preset '{source_name}' not found[/red]")
                return False

            # Check if target exists
            if self.preset_exists(target_name):
                console.print(f"[red]Target preset '{target_name}' already exists[/red]")
                return False

            # Update metadata for duplication
            if 'preset' in source_data:
                source_data['preset']['name'] = target_name
                if category:
                    source_data['preset']['category'] = category.value
                source_data['preset']['version'] = '1.0.0'
                source_data['preset']['created_at'] = datetime.now().isoformat()
                source_data['preset']['duplicated_from'] = source_name

            # Save as new preset
            return self.save_preset(target_name, source_data)

        except Exception as e:
            console.print(f"[red]Error duplicating preset: {e}[/red]")
            return False

    def validate_preset(self, name: str) -> ValidationResult:
        """Validate a preset."""
        preset_data = self.load_preset(name)
        if not preset_data:
            result = ValidationResult(is_valid=False)
            result.errors.append(f"Preset '{name}' not found")
            return result

        return yaml_schema_validator.validate_yaml_data(preset_data, "user_preset")

    def search_presets(self, query: str) -> list[PresetMetadata]:
        """Search presets by name, description, or tags."""
        query_lower = query.lower()
        all_presets = self.list_presets()

        matching_presets = []
        for preset in all_presets:
            if (query_lower in preset.name.lower() or
                query_lower in preset.description.lower() or
                any(query_lower in tag.lower() for tag in preset.tags)):
                matching_presets.append(preset)

        return matching_presets

    def get_preset_dependencies(self, name: str) -> list[str]:
        """Get dependencies for a preset."""
        metadata = self.get_preset_metadata(name)
        if metadata:
            return metadata.dependencies
        return []

    def show_preset_info(self, name: str) -> None:
        """Display detailed information about a preset."""
        metadata = self.get_preset_metadata(name)
        if not metadata:
            console.print(f"[red]Preset '{name}' not found[/red]")
            return

        preset_data = self.load_preset(name)
        if not preset_data:
            console.print(f"[red]Could not load preset '{name}'[/red]")
            return

        # Create info panel
        info_text = f"[bold]{metadata.name}[/bold]\n"
        info_text += f"{metadata.description}\n\n"
        info_text += f"[blue]Category:[/blue] {metadata.category.value}\n"
        info_text += f"[blue]Scope:[/blue] {metadata.scope.value}\n"
        info_text += f"[blue]Version:[/blue] {metadata.version}\n"
        info_text += f"[blue]Author:[/blue] {metadata.author}\n"
        info_text += f"[blue]Created:[/blue] {metadata.created_at.strftime('%Y-%m-%d %H:%M')}\n"
        info_text += f"[blue]Updated:[/blue] {metadata.updated_at.strftime('%Y-%m-%d %H:%M')}\n"

        if metadata.tags:
            info_text += f"[blue]Tags:[/blue] {', '.join(metadata.tags)}\n"

        if metadata.dependencies:
            info_text += f"[blue]Dependencies:[/blue] {', '.join(metadata.dependencies)}\n"

        if metadata.file_path:
            info_text += f"[blue]File:[/blue] {metadata.file_path}\n"

        console.print(Panel(info_text, title="Preset Information"))

        # Show content structure
        tree = Tree("📋 Preset Structure")

        if preset_data.get('users'):
            users_node = tree.add(f"👥 Users ({len(preset_data['users'])})")
            for user in preset_data['users'][:5]:  # Show first 5
                users_node.add(f"• {user.get('username', 'unknown')} ({user.get('protocol', 'unknown')})")
            if len(preset_data['users']) > 5:
                users_node.add(f"... and {len(preset_data['users']) - 5} more")

        if preset_data.get('servers'):
            servers_node = tree.add(f"🖥️ Servers ({len(preset_data['servers'])})")
            for server in preset_data['servers'][:5]:  # Show first 5
                servers_node.add(f"• {server.get('name', 'unknown')} ({server.get('protocol', 'unknown')})")
            if len(preset_data['servers']) > 5:
                servers_node.add(f"... and {len(preset_data['servers']) - 5} more")

        if 'network' in preset_data:
            network_node = tree.add("🌐 Network Configuration")
            network_config = preset_data['network']
            if network_config.get('isolation'):
                network_node.add("• Network isolation enabled")
            if network_config.get('custom_routes'):
                network_node.add(f"• {len(network_config['custom_routes'])} custom routes")

        if 'monitoring' in preset_data:
            monitoring_node = tree.add("📊 Monitoring Configuration")
            monitoring_config = preset_data['monitoring']
            if monitoring_config.get('alerts'):
                monitoring_node.add(f"• {len(monitoring_config['alerts'])} alerts configured")

        console.print(tree)

    def preset_exists(self, name: str) -> bool:
        """Check if a preset exists."""
        return self._find_preset_path(name) is not None

    # Private helper methods

    def _find_preset_path(self, name: str) -> Path | None:
        """Find the file path for a preset."""
        # Search in all category directories
        for category in PresetCategory:
            preset_path = self.presets_dir / category.value / f"{name}.yaml"
            if preset_path.exists():
                return preset_path
        return None

    def _validate_preset_name(self, name: str) -> bool:
        """Validate preset name."""
        if not name or len(name) < 1 or len(name) > 100:
            return False

        # Only allow alphanumeric, hyphens, underscores
        if not re.match(r'^[a-zA-Z0-9_-]+$', name):
            return False

        return True

    def _create_minimal_preset(
        self,
        name: str,
        category: PresetCategory,
        scope: PresetScope,
        description: str,
        template_vars: dict[str, Any] | None
    ) -> str:
        """Create minimal preset YAML content."""
        content = f"""# User-Defined Preset: {name}
# Category: {category.value}
# Scope: {scope.value}
# Created: {datetime.now().isoformat()}

preset:
  name: "{name}"
  description: "{description}"
  category: "{category.value}"
  scope: "{scope.value}"
  version: "1.0.0"
  author: "{os.getenv('USER', 'user')}"
  created_at: "{datetime.now().isoformat()}"
"""

        if scope == PresetScope.USER:
            content += """
# User configurations
users:
  - username: "example_user"
    protocol: "vless"
    email: "user@example.com"
    active: true
"""

        elif scope == PresetScope.SERVER:
            content += """
# Server configurations
servers:
  - name: "example_server"
    protocol: "vless"
    port: 8443
    auto_start: true
"""

        elif scope == PresetScope.ENVIRONMENT:
            content += """
# Complete environment configuration
users:
  - username: "admin"
    protocol: "vless"
    active: true

servers:
  - name: "main_server"
    protocol: "vless"
    port: 8443
    auto_start: true

network:
  isolation: true
  custom_routes: []

monitoring:
  alerts: []
"""

        # Add template variables if provided
        if template_vars:
            content += "\n# Template variables:\n"
            for key, value in template_vars.items():
                content += f"# {key}: {value}\n"

        return content

    def _merge_preset_variables(
        self,
        preset_data: dict[str, Any],
        target_vars: dict[str, Any]
    ) -> dict[str, Any]:
        """Merge target variables into preset data."""
        # This is a simplified merge - in practice, you'd want deep merging
        # and more sophisticated variable substitution
        merged = preset_data.copy()

        # Update specific sections based on target_vars
        if 'users' in target_vars and 'users' in merged:
            # Update user configurations
            for i, user_vars in enumerate(target_vars['users']):
                if i < len(merged['users']):
                    merged['users'][i].update(user_vars)

        if 'servers' in target_vars and 'servers' in merged:
            # Update server configurations
            for i, server_vars in enumerate(target_vars['servers']):
                if i < len(merged['servers']):
                    merged['servers'][i].update(server_vars)

        return merged

    def _apply_user_preset(
        self,
        preset_data: dict[str, Any],
        result: PresetApplicationResult,
        dry_run: bool
    ) -> None:
        """Apply user-scoped preset."""
        if 'users' not in preset_data:
            result.warnings.append("No users defined in preset")
            return

        for user_config in preset_data['users']:
            username = user_config.get('username', 'unknown')

            if dry_run:
                result.applied_users.append(f"{username} (dry-run)")
            else:
                # Here you would integrate with the actual user management system
                # For now, just simulate
                result.applied_users.append(username)
                result.warnings.append(f"User {username} application simulated")

    def _apply_server_preset(
        self,
        preset_data: dict[str, Any],
        result: PresetApplicationResult,
        dry_run: bool
    ) -> None:
        """Apply server-scoped preset."""
        if 'servers' not in preset_data:
            result.warnings.append("No servers defined in preset")
            return

        for server_config in preset_data['servers']:
            server_name = server_config.get('name', 'unknown')

            if dry_run:
                result.applied_servers.append(f"{server_name} (dry-run)")
            else:
                # Here you would integrate with the actual server management system
                result.applied_servers.append(server_name)
                result.warnings.append(f"Server {server_name} application simulated")

    def _apply_environment_preset(
        self,
        preset_data: dict[str, Any],
        result: PresetApplicationResult,
        dry_run: bool
    ) -> None:
        """Apply environment-scoped preset."""
        # Apply users if present
        if 'users' in preset_data:
            self._apply_user_preset(preset_data, result, dry_run)

        # Apply servers if present
        if 'servers' in preset_data:
            self._apply_server_preset(preset_data, result, dry_run)

        # Apply network configuration
        if 'network' in preset_data:
            if dry_run:
                result.applied_configs.append("network (dry-run)")
            else:
                result.applied_configs.append("network")
                result.warnings.append("Network configuration application simulated")

        # Apply monitoring configuration
        if 'monitoring' in preset_data:
            if dry_run:
                result.applied_configs.append("monitoring (dry-run)")
            else:
                result.applied_configs.append("monitoring")
                result.warnings.append("Monitoring configuration application simulated")

    def _apply_network_preset(
        self,
        preset_data: dict[str, Any],
        result: PresetApplicationResult,
        dry_run: bool
    ) -> None:
        """Apply network-scoped preset."""
        if 'network' not in preset_data:
            result.warnings.append("No network configuration in preset")
            return

        if dry_run:
            result.applied_configs.append("network (dry-run)")
        else:
            result.applied_configs.append("network")
            result.warnings.append("Network configuration application simulated")

    def _apply_security_preset(
        self,
        preset_data: dict[str, Any],
        result: PresetApplicationResult,
        dry_run: bool
    ) -> None:
        """Apply security-scoped preset."""
        # Security presets might affect multiple areas
        security_configs = []

        if 'security' in preset_data:
            security_configs.append("security")

        if 'users' in preset_data:
            # Apply security-related user settings
            security_configs.append("user_security")

        if 'servers' in preset_data:
            # Apply security-related server settings
            security_configs.append("server_security")

        if dry_run:
            result.applied_configs.extend([f"{config} (dry-run)" for config in security_configs])
        else:
            result.applied_configs.extend(security_configs)
            result.warnings.append("Security configuration application simulated")

    def _clear_cache(self) -> None:
        """Clear preset caches."""
        self._preset_cache.clear()
        self._metadata_cache.clear()


# Global preset manager instance
yaml_preset_manager = YamlPresetManager()


def create_preset(
    name: str,
    category: PresetCategory,
    scope: PresetScope,
    description: str = "",
    template_vars: dict[str, Any] | None = None
) -> bool:
    """Convenience function to create preset."""
    return yaml_preset_manager.create_preset(name, category, scope, description, template_vars)


def load_preset(name: str) -> dict[str, Any] | None:
    """Convenience function to load preset."""
    return yaml_preset_manager.load_preset(name)


def apply_preset(
    name: str,
    target_vars: dict[str, Any] | None = None,
    dry_run: bool = False
) -> PresetApplicationResult:
    """Convenience function to apply preset."""
    return yaml_preset_manager.apply_preset(name, target_vars, dry_run)


if __name__ == "__main__":
    # Create some example presets when module is run directly
    manager = YamlPresetManager()

    # Create development preset
    dev_vars = {
        'users': [
            {'username': 'dev_user', 'protocol': 'vless'},
            {'username': 'test_user', 'protocol': 'shadowsocks'}
        ],
        'servers': [
            {'name': 'dev_server', 'protocol': 'vless', 'port': 8443}
        ]
    }

    manager.create_preset(
        "development_env",
        PresetCategory.DEVELOPMENT,
        PresetScope.ENVIRONMENT,
        "Development environment with test users and servers",
        dev_vars
    )

    console.print("[green]✓ Example presets created[/green]")
