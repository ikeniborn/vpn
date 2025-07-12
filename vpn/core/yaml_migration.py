"""
YAML configuration migration tools for VPN Manager.

This module provides tools for migrating configurations between different formats
and versions, with support for backup, rollback, and data transformation.
"""

import os
import shutil
import json
from pathlib import Path
from typing import Dict, Any, List, Optional, Union, Callable, Tuple
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import re

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
from rich.table import Table
from rich.panel import Panel

from .yaml_config import YamlConfigManager, YamlLoadResult
from .yaml_schema import yaml_schema_validator, ValidationResult

console = Console()


class MigrationStatus(str, Enum):
    """Status of migration operation."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    ROLLED_BACK = "rolled_back"


class SourceFormat(str, Enum):
    """Source configuration formats."""
    TOML = "toml"
    JSON = "json"
    YAML = "yaml"
    INI = "ini"
    ENV = "env"
    DOCKER_COMPOSE = "docker_compose"
    LEGACY_CONFIG = "legacy_config"


class TargetFormat(str, Enum):
    """Target configuration formats."""
    YAML = "yaml"
    TOML = "toml"
    JSON = "json"


@dataclass
class MigrationRule:
    """Rule for transforming configuration data during migration."""
    name: str
    description: str
    source_path: str  # JSONPath-like expression
    target_path: str  # JSONPath-like expression
    transformer: Optional[Callable[[Any], Any]] = None
    required: bool = True
    default_value: Any = None


@dataclass
class MigrationPlan:
    """Plan for configuration migration."""
    name: str
    source_format: SourceFormat
    target_format: TargetFormat
    version_from: str
    version_to: str
    rules: List[MigrationRule] = field(default_factory=list)
    pre_migration_hooks: List[Callable] = field(default_factory=list)
    post_migration_hooks: List[Callable] = field(default_factory=list)
    description: str = ""


@dataclass
class MigrationResult:
    """Result of migration operation."""
    success: bool
    plan_name: str
    source_file: Optional[Path] = None
    target_file: Optional[Path] = None
    backup_file: Optional[Path] = None
    migrated_data: Optional[Dict[str, Any]] = None
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    
    @property
    def duration(self) -> Optional[float]:
        """Get migration duration in seconds."""
        if self.start_time and self.end_time:
            return (self.end_time - self.start_time).total_seconds()
        return None
    
    @property
    def has_warnings(self) -> bool:
        """Check if migration has warnings."""
        return len(self.warnings) > 0
    
    @property
    def has_errors(self) -> bool:
        """Check if migration has errors."""
        return len(self.errors) > 0


class YamlMigrationEngine:
    """Engine for migrating configurations to/from YAML format."""
    
    def __init__(self, backup_dir: Optional[Path] = None):
        """Initialize migration engine."""
        self.backup_dir = backup_dir or Path.home() / ".config" / "vpn-manager" / "backups"
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        
        self.yaml_manager = YamlConfigManager()
        self.migration_plans: Dict[str, MigrationPlan] = {}
        
        # Create default migration plans
        self._create_default_migration_plans()
    
    def register_migration_plan(self, plan: MigrationPlan) -> None:
        """Register a migration plan."""
        self.migration_plans[plan.name] = plan
    
    def migrate_config(
        self,
        source_path: Path,
        target_path: Path,
        plan_name: str,
        backup: bool = True,
        validate_result: bool = True
    ) -> MigrationResult:
        """
        Migrate configuration file using specified plan.
        
        Args:
            source_path: Source configuration file
            target_path: Target configuration file
            plan_name: Name of migration plan to use
            backup: Create backup before migration
            validate_result: Validate result against schema
        """
        result = MigrationResult(
            success=False,
            plan_name=plan_name,
            source_file=source_path,
            target_file=target_path,
            start_time=datetime.now()
        )
        
        try:
            # Get migration plan
            if plan_name not in self.migration_plans:
                result.errors.append(f"Migration plan '{plan_name}' not found")
                return result
            
            plan = self.migration_plans[plan_name]
            
            # Validate source file
            if not source_path.exists():
                result.errors.append(f"Source file not found: {source_path}")
                return result
            
            # Create backup if requested
            if backup:
                backup_file = self._create_backup(source_path)
                result.backup_file = backup_file
                if not backup_file:
                    result.warnings.append("Failed to create backup")
            
            # Load source data
            source_data = self._load_source_data(source_path, plan.source_format)
            if source_data is None:
                result.errors.append("Failed to load source data")
                return result
            
            # Run pre-migration hooks
            for hook in plan.pre_migration_hooks:
                try:
                    hook(source_data, result)
                except Exception as e:
                    result.warnings.append(f"Pre-migration hook failed: {e}")
            
            # Apply migration rules
            migrated_data = self._apply_migration_rules(source_data, plan.rules, result)
            
            # Run post-migration hooks
            for hook in plan.post_migration_hooks:
                try:
                    hook(migrated_data, result)
                except Exception as e:
                    result.warnings.append(f"Post-migration hook failed: {e}")
            
            # Validate migrated data if requested
            if validate_result:
                validation_result = yaml_schema_validator.validate_yaml_data(migrated_data, "config")
                if not validation_result.is_valid:
                    result.warnings.extend([f"Validation: {err}" for err in validation_result.errors])
                    # Don't fail migration for validation errors, just warn
            
            # Save target data
            target_path.parent.mkdir(parents=True, exist_ok=True)
            
            if plan.target_format == TargetFormat.YAML:
                success = self.yaml_manager.save_yaml(migrated_data, target_path)
            elif plan.target_format == TargetFormat.JSON:
                success = self._save_json_data(migrated_data, target_path)
            elif plan.target_format == TargetFormat.TOML:
                success = self._save_toml_data(migrated_data, target_path)
            else:
                result.errors.append(f"Unsupported target format: {plan.target_format}")
                return result
            
            if not success:
                result.errors.append("Failed to save migrated data")
                return result
            
            result.migrated_data = migrated_data
            result.success = True
            
        except Exception as e:
            result.errors.append(f"Migration failed: {e}")
        
        finally:
            result.end_time = datetime.now()
        
        return result
    
    def batch_migrate(
        self,
        source_dir: Path,
        target_dir: Path,
        plan_name: str,
        file_pattern: str = "*.toml",
        backup: bool = True
    ) -> List[MigrationResult]:
        """Migrate multiple configuration files."""
        results = []
        
        if not source_dir.exists():
            result = MigrationResult(success=False, plan_name=plan_name)
            result.errors.append(f"Source directory not found: {source_dir}")
            return [result]
        
        # Find source files
        source_files = list(source_dir.glob(file_pattern))
        
        if not source_files:
            result = MigrationResult(success=False, plan_name=plan_name)
            result.warnings.append(f"No files found matching pattern: {file_pattern}")
            return [result]
        
        # Migrate each file
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            console=console
        ) as progress:
            
            task = progress.add_task("Migrating files...", total=len(source_files))
            
            for source_file in source_files:
                # Determine target file name
                target_file = target_dir / f"{source_file.stem}.yaml"
                
                # Migrate file
                result = self.migrate_config(source_file, target_file, plan_name, backup)
                results.append(result)
                
                # Update progress
                status = "✓" if result.success else "✗"
                progress.update(task, advance=1, description=f"Migrating {source_file.name} {status}")
        
        return results
    
    def rollback_migration(self, result: MigrationResult) -> bool:
        """Rollback a migration using backup."""
        if not result.backup_file or not result.backup_file.exists():
            console.print("[red]No backup file available for rollback[/red]")
            return False
        
        if not result.target_file:
            console.print("[red]No target file to rollback[/red]")
            return False
        
        try:
            # Restore from backup
            shutil.copy2(result.backup_file, result.source_file)
            
            # Remove target file if it exists
            if result.target_file.exists():
                result.target_file.unlink()
            
            console.print(f"[green]✓ Rolled back migration from {result.backup_file}[/green]")
            return True
            
        except Exception as e:
            console.print(f"[red]Rollback failed: {e}[/red]")
            return False
    
    def convert_legacy_config(self, legacy_path: Path, target_path: Path) -> MigrationResult:
        """Convert legacy configuration format to modern YAML."""
        result = MigrationResult(
            success=False,
            plan_name="legacy_to_yaml",
            source_file=legacy_path,
            target_file=target_path,
            start_time=datetime.now()
        )
        
        try:
            # This would contain logic specific to your legacy format
            # For demonstration, assume it's a simple key=value format
            legacy_data = self._parse_legacy_config(legacy_path)
            
            # Transform to modern structure
            modern_data = self._transform_legacy_to_modern(legacy_data, result)
            
            # Save as YAML
            target_path.parent.mkdir(parents=True, exist_ok=True)
            success = self.yaml_manager.save_yaml(modern_data, target_path)
            
            if success:
                result.migrated_data = modern_data
                result.success = True
            else:
                result.errors.append("Failed to save converted configuration")
        
        except Exception as e:
            result.errors.append(f"Legacy conversion failed: {e}")
        
        finally:
            result.end_time = datetime.now()
        
        return result
    
    def migrate_docker_compose(self, compose_path: Path, target_path: Path) -> MigrationResult:
        """Migrate Docker Compose configuration to VPN Manager YAML."""
        result = MigrationResult(
            success=False,
            plan_name="docker_compose_to_yaml",
            source_file=compose_path,
            target_file=target_path,
            start_time=datetime.now()
        )
        
        try:
            # Load Docker Compose file
            compose_data = self.yaml_manager.load_yaml(compose_path, validate_schema=False)
            if not compose_data.is_valid:
                result.errors.extend(compose_data.errors)
                return result
            
            # Transform Docker Compose to VPN Manager format
            vpn_config = self._transform_docker_compose_to_vpn(compose_data.data, result)
            
            # Save as VPN Manager YAML
            target_path.parent.mkdir(parents=True, exist_ok=True)
            success = self.yaml_manager.save_yaml(vpn_config, target_path)
            
            if success:
                result.migrated_data = vpn_config
                result.success = True
            else:
                result.errors.append("Failed to save VPN configuration")
        
        except Exception as e:
            result.errors.append(f"Docker Compose migration failed: {e}")
        
        finally:
            result.end_time = datetime.now()
        
        return result
    
    def export_migration_report(self, results: List[MigrationResult], output_path: Path) -> bool:
        """Export migration report to file."""
        try:
            report_data = {
                'migration_report': {
                    'generated_at': datetime.now().isoformat(),
                    'total_migrations': len(results),
                    'successful': sum(1 for r in results if r.success),
                    'failed': sum(1 for r in results if not r.success),
                    'with_warnings': sum(1 for r in results if r.has_warnings),
                    'migrations': []
                }
            }
            
            for result in results:
                migration_info = {
                    'plan_name': result.plan_name,
                    'source_file': str(result.source_file) if result.source_file else None,
                    'target_file': str(result.target_file) if result.target_file else None,
                    'backup_file': str(result.backup_file) if result.backup_file else None,
                    'success': result.success,
                    'duration': result.duration,
                    'warnings': result.warnings,
                    'errors': result.errors,
                    'start_time': result.start_time.isoformat() if result.start_time else None,
                    'end_time': result.end_time.isoformat() if result.end_time else None,
                }
                report_data['migration_report']['migrations'].append(migration_info)
            
            return self.yaml_manager.save_yaml(report_data, output_path)
            
        except Exception as e:
            console.print(f"[red]Error generating migration report: {e}[/red]")
            return False
    
    def list_migration_plans(self) -> List[str]:
        """List available migration plans."""
        return list(self.migration_plans.keys())
    
    def get_migration_plan(self, name: str) -> Optional[MigrationPlan]:
        """Get migration plan by name."""
        return self.migration_plans.get(name)
    
    def show_migration_stats(self, results: List[MigrationResult]) -> None:
        """Display migration statistics."""
        if not results:
            console.print("[yellow]No migration results to display[/yellow]")
            return
        
        total = len(results)
        successful = sum(1 for r in results if r.success)
        failed = total - successful
        with_warnings = sum(1 for r in results if r.has_warnings)
        
        # Statistics table
        stats_table = Table(title="Migration Statistics")
        stats_table.add_column("Metric", style="cyan")
        stats_table.add_column("Count", justify="right", style="green")
        stats_table.add_column("Percentage", justify="right", style="blue")
        
        stats_table.add_row("Total Migrations", str(total), "100%")
        stats_table.add_row("Successful", str(successful), f"{(successful/total)*100:.1f}%")
        stats_table.add_row("Failed", str(failed), f"{(failed/total)*100:.1f}%")
        stats_table.add_row("With Warnings", str(with_warnings), f"{(with_warnings/total)*100:.1f}%")
        
        console.print(stats_table)
        
        # Timing statistics
        durations = [r.duration for r in results if r.duration is not None]
        if durations:
            avg_duration = sum(durations) / len(durations)
            max_duration = max(durations)
            min_duration = min(durations)
            
            timing_table = Table(title="Timing Statistics")
            timing_table.add_column("Metric", style="cyan")
            timing_table.add_column("Time (seconds)", justify="right", style="green")
            
            timing_table.add_row("Average Duration", f"{avg_duration:.2f}")
            timing_table.add_row("Maximum Duration", f"{max_duration:.2f}")
            timing_table.add_row("Minimum Duration", f"{min_duration:.2f}")
            
            console.print(timing_table)
    
    # Private helper methods
    
    def _create_backup(self, source_path: Path) -> Optional[Path]:
        """Create backup of source file."""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_name = f"{source_path.stem}_{timestamp}{source_path.suffix}"
            backup_path = self.backup_dir / backup_name
            
            shutil.copy2(source_path, backup_path)
            return backup_path
            
        except Exception as e:
            console.print(f"[red]Backup creation failed: {e}[/red]")
            return None
    
    def _load_source_data(self, source_path: Path, source_format: SourceFormat) -> Optional[Dict[str, Any]]:
        """Load data from source file based on format."""
        try:
            if source_format == SourceFormat.YAML:
                result = self.yaml_manager.load_yaml(source_path, validate_schema=False)
                return result.data if result.is_valid else None
            
            elif source_format == SourceFormat.TOML:
                import tomli
                with open(source_path, 'rb') as f:
                    return tomli.load(f)
            
            elif source_format == SourceFormat.JSON:
                with open(source_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            
            elif source_format == SourceFormat.INI:
                import configparser
                config = configparser.ConfigParser()
                config.read(source_path)
                return {section: dict(config[section]) for section in config.sections()}
            
            elif source_format == SourceFormat.ENV:
                data = {}
                with open(source_path, 'r', encoding='utf-8') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#') and '=' in line:
                            key, value = line.split('=', 1)
                            data[key.strip()] = value.strip().strip('"\'')
                return data
            
            elif source_format == SourceFormat.DOCKER_COMPOSE:
                result = self.yaml_manager.load_yaml(source_path, validate_schema=False)
                return result.data if result.is_valid else None
            
            else:
                console.print(f"[red]Unsupported source format: {source_format}[/red]")
                return None
        
        except Exception as e:
            console.print(f"[red]Error loading source data: {e}[/red]")
            return None
    
    def _save_json_data(self, data: Dict[str, Any], target_path: Path) -> bool:
        """Save data as JSON."""
        try:
            with open(target_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            return True
        except Exception as e:
            console.print(f"[red]Error saving JSON data: {e}[/red]")
            return False
    
    def _save_toml_data(self, data: Dict[str, Any], target_path: Path) -> bool:
        """Save data as TOML."""
        try:
            import tomli_w
            with open(target_path, 'wb') as f:
                tomli_w.dump(data, f)
            return True
        except ImportError:
            console.print("[red]tomli-w package required for TOML export[/red]")
            return False
        except Exception as e:
            console.print(f"[red]Error saving TOML data: {e}[/red]")
            return False
    
    def _apply_migration_rules(
        self,
        source_data: Dict[str, Any],
        rules: List[MigrationRule],
        result: MigrationResult
    ) -> Dict[str, Any]:
        """Apply migration rules to transform data."""
        migrated_data = {}
        
        for rule in rules:
            try:
                # Get source value using JSONPath-like expression
                source_value = self._get_nested_value(source_data, rule.source_path)
                
                if source_value is None:
                    if rule.required:
                        result.warnings.append(f"Required field missing: {rule.source_path}")
                    if rule.default_value is not None:
                        source_value = rule.default_value
                    else:
                        continue
                
                # Apply transformer if provided
                if rule.transformer:
                    try:
                        transformed_value = rule.transformer(source_value)
                    except Exception as e:
                        result.warnings.append(f"Transformation failed for {rule.name}: {e}")
                        transformed_value = source_value
                else:
                    transformed_value = source_value
                
                # Set target value using JSONPath-like expression
                self._set_nested_value(migrated_data, rule.target_path, transformed_value)
                
            except Exception as e:
                result.warnings.append(f"Rule '{rule.name}' failed: {e}")
        
        return migrated_data
    
    def _get_nested_value(self, data: Dict[str, Any], path: str) -> Any:
        """Get nested value using dot notation path."""
        keys = path.split('.')
        current = data
        
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return None
        
        return current
    
    def _set_nested_value(self, data: Dict[str, Any], path: str, value: Any) -> None:
        """Set nested value using dot notation path."""
        keys = path.split('.')
        current = data
        
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            current = current[key]
        
        current[keys[-1]] = value
    
    def _parse_legacy_config(self, legacy_path: Path) -> Dict[str, Any]:
        """Parse legacy configuration format."""
        data = {}
        
        with open(legacy_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                
                # Parse key=value pairs
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"\'')
                    
                    # Convert boolean strings
                    if value.lower() in ('true', 'false'):
                        value = value.lower() == 'true'
                    # Convert numeric strings
                    elif value.isdigit():
                        value = int(value)
                    elif re.match(r'^\d+\.\d+$', value):
                        value = float(value)
                    
                    data[key] = value
        
        return data
    
    def _transform_legacy_to_modern(self, legacy_data: Dict[str, Any], result: MigrationResult) -> Dict[str, Any]:
        """Transform legacy data structure to modern format."""
        modern_data = {
            'app': {
                'name': legacy_data.get('APP_NAME', 'VPN Manager'),
                'debug': legacy_data.get('DEBUG', False),
                'log_level': legacy_data.get('LOG_LEVEL', 'INFO')
            },
            'database': {
                'type': legacy_data.get('DB_TYPE', 'sqlite'),
                'path': legacy_data.get('DB_PATH', '~/.config/vpn-manager/vpn.db')
            },
            'docker': {
                'host': legacy_data.get('DOCKER_HOST', 'unix:///var/run/docker.sock'),
                'timeout': legacy_data.get('DOCKER_TIMEOUT', 30)
            },
            'network': {
                'bind_address': legacy_data.get('BIND_ADDRESS', '0.0.0.0'),
                'ports': {}
            },
            'security': {
                'tls': {
                    'enabled': legacy_data.get('TLS_ENABLED', True)
                }
            }
        }
        
        # Transform port configurations
        if 'VLESS_PORT' in legacy_data:
            modern_data['network']['ports']['vless'] = legacy_data['VLESS_PORT']
        if 'SHADOWSOCKS_PORT' in legacy_data:
            modern_data['network']['ports']['shadowsocks'] = legacy_data['SHADOWSOCKS_PORT']
        
        # Add transformation warnings
        transformed_keys = set(legacy_data.keys()) - set([
            'APP_NAME', 'DEBUG', 'LOG_LEVEL', 'DB_TYPE', 'DB_PATH',
            'DOCKER_HOST', 'DOCKER_TIMEOUT', 'BIND_ADDRESS',
            'VLESS_PORT', 'SHADOWSOCKS_PORT', 'TLS_ENABLED'
        ])
        
        if transformed_keys:
            result.warnings.append(f"Some legacy keys were not transformed: {list(transformed_keys)}")
        
        return modern_data
    
    def _transform_docker_compose_to_vpn(self, compose_data: Dict[str, Any], result: MigrationResult) -> Dict[str, Any]:
        """Transform Docker Compose format to VPN Manager format."""
        vpn_config = {
            'app': {
                'name': 'VPN Manager',
                'version': '1.0.0'
            },
            'docker': {
                'auto_remove': True,
                'restart_policy': 'unless-stopped'
            },
            'protocols': {}
        }
        
        services = compose_data.get('services', {})
        
        for service_name, service_config in services.items():
            # Detect service type from image or service name
            image = service_config.get('image', '')
            
            if 'xray' in image.lower() or 'vless' in service_name.lower():
                protocol_type = 'vless'
            elif 'shadowsocks' in image.lower():
                protocol_type = 'shadowsocks'
            elif 'wireguard' in image.lower():
                protocol_type = 'wireguard'
            else:
                result.warnings.append(f"Unknown service type for {service_name}, skipping")
                continue
            
            # Extract port information
            ports = service_config.get('ports', [])
            service_port = None
            
            if ports:
                # Parse port mapping (e.g., "8443:8443" or "8443:8443/tcp")
                port_mapping = ports[0] if isinstance(ports[0], str) else str(ports[0])
                if ':' in port_mapping:
                    service_port = int(port_mapping.split(':')[0])
            
            # Create protocol configuration
            vpn_config['protocols'][protocol_type] = {
                'enabled': True,
                'docker': {
                    'image': image,
                    'restart_policy': service_config.get('restart', 'unless-stopped')
                }
            }
            
            if service_port:
                vpn_config['protocols'][protocol_type]['port'] = service_port
            
            # Extract environment variables
            environment = service_config.get('environment', {})
            if environment:
                vpn_config['protocols'][protocol_type]['docker']['environment'] = environment
            
            # Extract volumes
            volumes = service_config.get('volumes', [])
            if volumes:
                vpn_config['protocols'][protocol_type]['docker']['volumes'] = volumes
        
        return vpn_config
    
    def _create_default_migration_plans(self) -> None:
        """Create default migration plans."""
        
        # TOML to YAML migration plan
        toml_to_yaml_rules = [
            MigrationRule(
                name="app_config",
                description="Migrate application configuration",
                source_path="app",
                target_path="app"
            ),
            MigrationRule(
                name="database_config",
                description="Migrate database configuration",
                source_path="database",
                target_path="database"
            ),
            MigrationRule(
                name="docker_config",
                description="Migrate Docker configuration",
                source_path="docker",
                target_path="docker"
            ),
            MigrationRule(
                name="network_config",
                description="Migrate network configuration",
                source_path="network",
                target_path="network"
            ),
            MigrationRule(
                name="security_config",
                description="Migrate security configuration",
                source_path="security",
                target_path="security"
            ),
            MigrationRule(
                name="monitoring_config",
                description="Migrate monitoring configuration",
                source_path="monitoring",
                target_path="monitoring"
            ),
            MigrationRule(
                name="protocols_config",
                description="Migrate protocols configuration",
                source_path="protocols",
                target_path="protocols"
            ),
        ]
        
        toml_to_yaml_plan = MigrationPlan(
            name="toml_to_yaml",
            source_format=SourceFormat.TOML,
            target_format=TargetFormat.YAML,
            version_from="1.0",
            version_to="1.0",
            rules=toml_to_yaml_rules,
            description="Migrate TOML configuration to YAML format"
        )
        
        self.register_migration_plan(toml_to_yaml_plan)
        
        # JSON to YAML migration plan
        json_to_yaml_plan = MigrationPlan(
            name="json_to_yaml",
            source_format=SourceFormat.JSON,
            target_format=TargetFormat.YAML,
            version_from="1.0",
            version_to="1.0",
            rules=toml_to_yaml_rules,  # Same rules work for JSON
            description="Migrate JSON configuration to YAML format"
        )
        
        self.register_migration_plan(json_to_yaml_plan)
        
        # Environment variables to YAML
        env_to_yaml_rules = [
            MigrationRule(
                name="app_name",
                description="App name from environment",
                source_path="VPN_APP_NAME",
                target_path="app.name",
                default_value="VPN Manager"
            ),
            MigrationRule(
                name="debug_mode",
                description="Debug mode from environment",
                source_path="VPN_DEBUG",
                target_path="app.debug",
                transformer=lambda x: str(x).lower() == 'true',
                default_value=False
            ),
            MigrationRule(
                name="log_level",
                description="Log level from environment",
                source_path="VPN_LOG_LEVEL",
                target_path="app.log_level",
                default_value="INFO"
            ),
            MigrationRule(
                name="database_path",
                description="Database path from environment",
                source_path="VPN_DATABASE_PATH",
                target_path="database.path",
                default_value="~/.config/vpn-manager/vpn.db"
            ),
            MigrationRule(
                name="docker_host",
                description="Docker host from environment",
                source_path="VPN_DOCKER_HOST",
                target_path="docker.host",
                default_value="unix:///var/run/docker.sock"
            ),
            MigrationRule(
                name="bind_address",
                description="Bind address from environment",
                source_path="VPN_BIND_ADDRESS",
                target_path="network.bind_address",
                default_value="0.0.0.0"
            ),
        ]
        
        env_to_yaml_plan = MigrationPlan(
            name="env_to_yaml",
            source_format=SourceFormat.ENV,
            target_format=TargetFormat.YAML,
            version_from="1.0",
            version_to="1.0",
            rules=env_to_yaml_rules,
            description="Migrate environment variables to YAML configuration"
        )
        
        self.register_migration_plan(env_to_yaml_plan)


# Global migration engine instance
yaml_migration_engine = YamlMigrationEngine()


def migrate_config_file(
    source_path: Path,
    target_path: Path,
    plan_name: str = "toml_to_yaml",
    backup: bool = True
) -> MigrationResult:
    """Convenience function to migrate configuration file."""
    return yaml_migration_engine.migrate_config(source_path, target_path, plan_name, backup)


def migrate_legacy_config(legacy_path: Path, target_path: Path) -> MigrationResult:
    """Convenience function to migrate legacy configuration."""
    return yaml_migration_engine.convert_legacy_config(legacy_path, target_path)


def migrate_docker_compose(compose_path: Path, target_path: Path) -> MigrationResult:
    """Convenience function to migrate Docker Compose configuration."""
    return yaml_migration_engine.migrate_docker_compose(compose_path, target_path)


if __name__ == "__main__":
    # Demo migration when module is run directly
    engine = YamlMigrationEngine()
    
    # Show available migration plans
    console.print("[blue]Available Migration Plans:[/blue]")
    for plan_name in engine.list_migration_plans():
        plan = engine.get_migration_plan(plan_name)
        console.print(f"  • {plan_name}: {plan.description}")
    
    console.print("\n[green]✓ YAML migration tools initialized[/green]")