"""
CLI commands for YAML configuration management.
"""

import asyncio
from pathlib import Path
from typing import Optional, List

import typer
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

from vpn.cli.exit_codes import handle_cli_errors, ExitCode, exit_manager
from vpn.core.yaml_config import yaml_config_manager, create_default_templates
from vpn.core.yaml_schema import yaml_schema_validator, PresetCategory, PresetScope
from vpn.core.yaml_templates import vpn_template_engine, TemplateType, TemplateContext
from vpn.core.yaml_presets import yaml_preset_manager
from vpn.core.yaml_migration import yaml_migration_engine, SourceFormat, TargetFormat

console = Console()

# Create YAML commands group
app = typer.Typer(
    name="yaml",
    help="YAML configuration management commands",
    no_args_is_help=True
)


@app.command("validate")
def validate_yaml(
    file_path: Path = typer.Argument(help="YAML file to validate"),
    schema_type: str = typer.Option("config", help="Schema type: config, user_preset, server_config"),
    show_details: bool = typer.Option(False, "--details", help="Show detailed validation results")
):
    """Validate YAML configuration file against schema."""
    with handle_cli_errors("YAML validation"):
        if not file_path.exists():
            exit_manager.exit_with_code(
                ExitCode.FILE_NOT_FOUND,
                f"File not found: {file_path}"
            )
        
        # Load and validate YAML
        result = yaml_config_manager.load_yaml(
            file_path,
            validate_schema=True,
            schema_model=yaml_schema_validator.schemas.get(schema_type)
        )
        
        if result.is_valid:
            console.print(f"[green]✓ {file_path} is valid {schema_type} YAML[/green]")
            
            if show_details:
                console.print(f"\n[blue]File:[/blue] {file_path}")
                console.print(f"[blue]Schema:[/blue] {schema_type}")
                console.print(f"[blue]Size:[/blue] {file_path.stat().st_size} bytes")
                
                if result.warnings:
                    console.print(f"\n[yellow]Warnings:[/yellow]")
                    for warning in result.warnings:
                        console.print(f"  • {warning}")
        else:
            console.print(f"[red]✗ {file_path} validation failed[/red]")
            console.print(f"\n[red]Errors:[/red]")
            for error in result.errors:
                console.print(f"  • {error}")
            
            exit_manager.exit_with_code(ExitCode.VALIDATION_ERROR, "YAML validation failed")


@app.command("schema")
def manage_schema(
    action: str = typer.Argument(help="Action: generate, save, show"),
    schema_type: str = typer.Option("config", help="Schema type: config, user_preset, server_config"),
    output_path: Optional[Path] = typer.Option(None, "--output", "-o", help="Output file path")
):
    """Manage YAML schemas."""
    with handle_cli_errors("Schema management"):
        if action == "generate":
            schema = yaml_schema_validator.generate_json_schema(schema_type)
            if output_path:
                import json
                with open(output_path, 'w') as f:
                    json.dump(schema, f, indent=2)
                console.print(f"[green]✓ Schema saved to {output_path}[/green]")
            else:
                import json
                console.print(json.dumps(schema, indent=2))
        
        elif action == "save":
            if not output_path:
                output_path = Path(f"{schema_type}_schema.json")
            
            success = yaml_schema_validator.save_json_schema(schema_type, output_path)
            if success:
                console.print(f"[green]✓ Schema saved to {output_path}[/green]")
            else:
                exit_manager.exit_with_code(ExitCode.GENERAL_ERROR, "Failed to save schema")
        
        elif action == "show":
            yaml_schema_validator.show_schema_info(schema_type)
        
        else:
            exit_manager.exit_with_code(
                ExitCode.INVALID_INPUT,
                f"Invalid action: {action}. Use: generate, save, show"
            )


@app.command("template")
def manage_templates(
    action: str = typer.Argument(help="Action: list, create, render, validate, info"),
    template_name: Optional[str] = typer.Option(None, "--name", "-n", help="Template name"),
    template_type: Optional[str] = typer.Option(None, "--type", "-t", help="Template type"),
    output_path: Optional[Path] = typer.Option(None, "--output", "-o", help="Output file path"),
    variables_file: Optional[Path] = typer.Option(None, "--vars", help="Variables file for rendering")
):
    """Manage YAML templates."""
    with handle_cli_errors("Template management"):
        if action == "list":
            template_type_enum = None
            if template_type:
                try:
                    template_type_enum = TemplateType(template_type)
                except ValueError:
                    exit_manager.exit_with_code(
                        ExitCode.INVALID_INPUT,
                        f"Invalid template type: {template_type}"
                    )
            
            templates = vpn_template_engine.list_templates(template_type_enum)
            
            if not templates:
                console.print("[yellow]No templates found[/yellow]")
                return
            
            table = Table(title="Available Templates")
            table.add_column("Name", style="green")
            table.add_column("Type", style="blue")
            table.add_column("Description", style="dim")
            
            for template in templates:
                info = vpn_template_engine.get_template_info(template)
                table.add_row(
                    template,
                    info.get('type', 'unknown'),
                    info.get('description', '')[:50] + "..." if len(info.get('description', '')) > 50 else info.get('description', '')
                )
            
            console.print(table)
        
        elif action == "create":
            if not template_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Template name required")
            
            console.print("[yellow]Creating default VPN templates...[/yellow]")
            create_default_templates()
            console.print(f"[green]✓ Default templates created[/green]")
        
        elif action == "render":
            if not template_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Template name required")
            
            # Load variables if provided
            variables = {}
            if variables_file and variables_file.exists():
                var_result = yaml_config_manager.load_yaml(variables_file, validate_schema=False)
                if var_result.is_valid:
                    variables = var_result.data
            
            # Create template context
            context = TemplateContext(
                template_type=TemplateType.VLESS,  # Default
                variables=variables
            )
            
            # Render template
            result = vpn_template_engine.render_template(
                f"{template_name}.yaml",
                context,
                output_path
            )
            
            if result.is_valid:
                if output_path:
                    console.print(f"[green]✓ Template rendered to {output_path}[/green]")
                else:
                    console.print(result.content)
            else:
                console.print(f"[red]✗ Template rendering failed[/red]")
                for error in result.errors:
                    console.print(f"  • {error}")
                exit_manager.exit_with_code(ExitCode.GENERAL_ERROR, "Template rendering failed")
        
        elif action == "validate":
            if not template_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Template name required")
            
            result = vpn_template_engine.validate_template(template_name)
            
            if result.is_valid:
                console.print(f"[green]✓ Template '{template_name}' is valid[/green]")
            else:
                console.print(f"[red]✗ Template '{template_name}' validation failed[/red]")
                for error in result.errors:
                    console.print(f"  • {error}")
                for warning in result.warnings:
                    console.print(f"  ⚠ {warning}")
                exit_manager.exit_with_code(ExitCode.VALIDATION_ERROR, "Template validation failed")
        
        elif action == "info":
            if not template_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Template name required")
            
            info = vpn_template_engine.get_template_info(template_name)
            
            if not info['exists']:
                exit_manager.exit_with_code(
                    ExitCode.FILE_NOT_FOUND,
                    f"Template '{template_name}' not found"
                )
            
            info_text = f"[bold]{info['name']}[/bold]\n"
            info_text += f"{info.get('description', 'No description')}\n\n"
            info_text += f"[blue]Type:[/blue] {info.get('type', 'unknown')}\n"
            info_text += f"[blue]Author:[/blue] {info.get('author', 'unknown')}\n"
            info_text += f"[blue]Created:[/blue] {info.get('created', 'unknown')}\n"
            info_text += f"[blue]Size:[/blue] {info.get('size', 0)} bytes\n"
            if info.get('path'):
                info_text += f"[blue]Path:[/blue] {info['path']}\n"
            
            console.print(Panel(info_text, title="Template Information"))
        
        else:
            exit_manager.exit_with_code(
                ExitCode.INVALID_INPUT,
                f"Invalid action: {action}. Use: list, create, render, validate, info"
            )


@app.command("preset")
def manage_presets(
    action: str = typer.Argument(help="Action: list, create, apply, delete, show, export, import"),
    preset_name: Optional[str] = typer.Option(None, "--name", "-n", help="Preset name"),
    category: Optional[str] = typer.Option(None, "--category", "-c", help="Preset category"),
    scope: Optional[str] = typer.Option(None, "--scope", "-s", help="Preset scope"),
    description: Optional[str] = typer.Option(None, "--description", "-d", help="Preset description"),
    file_path: Optional[Path] = typer.Option(None, "--file", "-f", help="File path for import/export"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Simulate preset application"),
    force: bool = typer.Option(False, "--force", help="Force operation")
):
    """Manage YAML user presets."""
    with handle_cli_errors("Preset management"):
        if action == "list":
            # Parse filters
            category_filter = None
            if category:
                try:
                    category_filter = PresetCategory(category)
                except ValueError:
                    exit_manager.exit_with_code(
                        ExitCode.INVALID_INPUT,
                        f"Invalid category: {category}"
                    )
            
            scope_filter = None
            if scope:
                try:
                    scope_filter = PresetScope(scope)
                except ValueError:
                    exit_manager.exit_with_code(
                        ExitCode.INVALID_INPUT,
                        f"Invalid scope: {scope}"
                    )
            
            presets = yaml_preset_manager.list_presets(category_filter, scope_filter)
            
            if not presets:
                console.print("[yellow]No presets found[/yellow]")
                return
            
            table = Table(title="User Presets")
            table.add_column("Name", style="green")
            table.add_column("Category", style="blue")
            table.add_column("Scope", style="cyan")
            table.add_column("Description", style="dim")
            table.add_column("Updated", style="yellow")
            
            for preset in presets:
                table.add_row(
                    preset.name,
                    preset.category.value,
                    preset.scope.value,
                    preset.description[:40] + "..." if len(preset.description) > 40 else preset.description,
                    preset.updated_at.strftime("%Y-%m-%d")
                )
            
            console.print(table)
        
        elif action == "create":
            if not preset_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Preset name required")
            
            category_enum = PresetCategory.CUSTOM
            if category:
                try:
                    category_enum = PresetCategory(category)
                except ValueError:
                    exit_manager.exit_with_code(
                        ExitCode.INVALID_INPUT,
                        f"Invalid category: {category}"
                    )
            
            scope_enum = PresetScope.USER
            if scope:
                try:
                    scope_enum = PresetScope(scope)
                except ValueError:
                    exit_manager.exit_with_code(
                        ExitCode.INVALID_INPUT,
                        f"Invalid scope: {scope}"
                    )
            
            success = yaml_preset_manager.create_preset(
                preset_name,
                category_enum,
                scope_enum,
                description or ""
            )
            
            if success:
                console.print(f"[green]✓ Created preset '{preset_name}'[/green]")
            else:
                exit_manager.exit_with_code(ExitCode.GENERAL_ERROR, "Failed to create preset")
        
        elif action == "apply":
            if not preset_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Preset name required")
            
            result = yaml_preset_manager.apply_preset(preset_name, dry_run=dry_run)
            
            if result.success:
                console.print(f"[green]✓ Applied preset '{preset_name}'[/green]")
                
                if result.applied_users:
                    console.print(f"[blue]Users:[/blue] {', '.join(result.applied_users)}")
                if result.applied_servers:
                    console.print(f"[blue]Servers:[/blue] {', '.join(result.applied_servers)}")
                if result.applied_configs:
                    console.print(f"[blue]Configs:[/blue] {', '.join(result.applied_configs)}")
                
                if result.has_warnings:
                    console.print(f"\n[yellow]Warnings:[/yellow]")
                    for warning in result.warnings:
                        console.print(f"  • {warning}")
            else:
                console.print(f"[red]✗ Failed to apply preset '{preset_name}'[/red]")
                for error in result.errors:
                    console.print(f"  • {error}")
                exit_manager.exit_with_code(ExitCode.OPERATION_FAILED, "Preset application failed")
        
        elif action == "delete":
            if not preset_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Preset name required")
            
            success = yaml_preset_manager.delete_preset(preset_name, confirm=force)
            
            if success:
                console.print(f"[green]✓ Deleted preset '{preset_name}'[/green]")
            else:
                exit_manager.exit_with_code(ExitCode.GENERAL_ERROR, "Failed to delete preset")
        
        elif action == "show":
            if not preset_name:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "Preset name required")
            
            yaml_preset_manager.show_preset_info(preset_name)
        
        elif action == "export":
            if not preset_name or not file_path:
                exit_manager.exit_with_code(
                    ExitCode.REQUIRED_FIELD_MISSING,
                    "Preset name and file path required for export"
                )
            
            success = yaml_preset_manager.export_preset(preset_name, file_path)
            
            if success:
                console.print(f"[green]✓ Exported preset '{preset_name}' to {file_path}[/green]")
            else:
                exit_manager.exit_with_code(ExitCode.EXPORT_ERROR, "Failed to export preset")
        
        elif action == "import":
            if not file_path:
                exit_manager.exit_with_code(ExitCode.REQUIRED_FIELD_MISSING, "File path required for import")
            
            if not file_path.exists():
                exit_manager.exit_with_code(ExitCode.FILE_NOT_FOUND, f"File not found: {file_path}")
            
            category_enum = None
            if category:
                try:
                    category_enum = PresetCategory(category)
                except ValueError:
                    exit_manager.exit_with_code(
                        ExitCode.INVALID_INPUT,
                        f"Invalid category: {category}"
                    )
            
            success = yaml_preset_manager.import_preset(
                file_path,
                preset_name,
                category_enum,
                overwrite=force
            )
            
            if success:
                imported_name = preset_name or file_path.stem
                console.print(f"[green]✓ Imported preset '{imported_name}' from {file_path}[/green]")
            else:
                exit_manager.exit_with_code(ExitCode.IMPORT_ERROR, "Failed to import preset")
        
        else:
            exit_manager.exit_with_code(
                ExitCode.INVALID_INPUT,
                f"Invalid action: {action}. Use: list, create, apply, delete, show, export, import"
            )


@app.command("migrate")
def migrate_config(
    source_path: Path = typer.Argument(help="Source configuration file"),
    target_path: Path = typer.Argument(help="Target configuration file"),
    plan_name: str = typer.Option("toml_to_yaml", "--plan", "-p", help="Migration plan name"),
    backup: bool = typer.Option(True, "--backup/--no-backup", help="Create backup before migration"),
    validate: bool = typer.Option(True, "--validate/--no-validate", help="Validate result"),
    show_report: bool = typer.Option(False, "--report", help="Show detailed migration report")
):
    """Migrate configuration files to YAML format."""
    with handle_cli_errors("Configuration migration"):
        if not source_path.exists():
            exit_manager.exit_with_code(
                ExitCode.FILE_NOT_FOUND,
                f"Source file not found: {source_path}"
            )
        
        # Check if migration plan exists
        if plan_name not in yaml_migration_engine.list_migration_plans():
            available_plans = yaml_migration_engine.list_migration_plans()
            exit_manager.exit_with_code(
                ExitCode.INVALID_INPUT,
                f"Migration plan '{plan_name}' not found. Available: {', '.join(available_plans)}"
            )
        
        # Perform migration
        result = yaml_migration_engine.migrate_config(
            source_path,
            target_path,
            plan_name,
            backup,
            validate
        )
        
        if result.success:
            console.print(f"[green]✓ Successfully migrated {source_path} to {target_path}[/green]")
            
            if result.backup_file:
                console.print(f"[blue]Backup created:[/blue] {result.backup_file}")
            
            if result.duration:
                console.print(f"[blue]Duration:[/blue] {result.duration:.2f} seconds")
            
            if result.has_warnings:
                console.print(f"\n[yellow]Warnings:[/yellow]")
                for warning in result.warnings:
                    console.print(f"  • {warning}")
            
            if show_report and result.migrated_data:
                # Show structure of migrated data
                from rich.tree import Tree
                
                tree = Tree("📋 Migrated Configuration")
                for section in result.migrated_data.keys():
                    tree.add(f"📁 {section}")
                
                console.print(tree)
        
        else:
            console.print(f"[red]✗ Migration failed[/red]")
            for error in result.errors:
                console.print(f"  • {error}")
            
            if result.has_warnings:
                console.print(f"\n[yellow]Warnings:[/yellow]")
                for warning in result.warnings:
                    console.print(f"  • {warning}")
            
            exit_manager.exit_with_code(ExitCode.OPERATION_FAILED, "Migration failed")


@app.command("batch-migrate")
def batch_migrate(
    source_dir: Path = typer.Argument(help="Source directory"),
    target_dir: Path = typer.Argument(help="Target directory"),
    plan_name: str = typer.Option("toml_to_yaml", "--plan", "-p", help="Migration plan name"),
    pattern: str = typer.Option("*.toml", "--pattern", help="File pattern to match"),
    backup: bool = typer.Option(True, "--backup/--no-backup", help="Create backups"),
    report_path: Optional[Path] = typer.Option(None, "--report", help="Generate migration report")
):
    """Batch migrate multiple configuration files."""
    with handle_cli_errors("Batch migration"):
        if not source_dir.exists():
            exit_manager.exit_with_code(
                ExitCode.DIRECTORY_NOT_FOUND,
                f"Source directory not found: {source_dir}"
            )
        
        # Create target directory
        target_dir.mkdir(parents=True, exist_ok=True)
        
        # Perform batch migration
        results = yaml_migration_engine.batch_migrate(
            source_dir,
            target_dir,
            plan_name,
            pattern,
            backup
        )
        
        # Show statistics
        yaml_migration_engine.show_migration_stats(results)
        
        # Generate report if requested
        if report_path:
            success = yaml_migration_engine.export_migration_report(results, report_path)
            if success:
                console.print(f"\n[green]✓ Migration report saved to {report_path}[/green]")
            else:
                console.print(f"\n[yellow]⚠ Failed to generate migration report[/yellow]")
        
        # Exit with appropriate code
        failed_count = sum(1 for r in results if not r.success)
        if failed_count > 0:
            exit_manager.exit_with_code(
                ExitCode.OPERATION_FAILED,
                f"{failed_count} migrations failed"
            )
        else:
            console.print(f"\n[green]✓ All {len(results)} migrations completed successfully[/green]")


@app.command("convert")
def convert_format(
    source_path: Path = typer.Argument(help="Source file"),
    target_path: Path = typer.Argument(help="Target file"),
    source_format: str = typer.Option("auto", "--from", help="Source format: auto, toml, json, yaml"),
    target_format: str = typer.Option("yaml", "--to", help="Target format: yaml, toml, json")
):
    """Convert configuration between different formats."""
    with handle_cli_errors("Format conversion"):
        if not source_path.exists():
            exit_manager.exit_with_code(
                ExitCode.FILE_NOT_FOUND,
                f"Source file not found: {source_path}"
            )
        
        # Auto-detect source format if needed
        if source_format == "auto":
            suffix = source_path.suffix.lower()
            if suffix == ".toml":
                source_format = "toml"
            elif suffix == ".json":
                source_format = "json"
            elif suffix in [".yaml", ".yml"]:
                source_format = "yaml"
            else:
                exit_manager.exit_with_code(
                    ExitCode.INVALID_INPUT,
                    f"Cannot auto-detect format for {source_path}"
                )
        
        # Map to enum values
        try:
            source_enum = SourceFormat(source_format)
        except ValueError:
            exit_manager.exit_with_code(
                ExitCode.INVALID_INPUT,
                f"Invalid source format: {source_format}"
            )
        
        try:
            target_enum = TargetFormat(target_format)
        except ValueError:
            exit_manager.exit_with_code(
                ExitCode.INVALID_INPUT,
                f"Invalid target format: {target_format}"
            )
        
        # Use appropriate migration plan
        plan_mapping = {
            ("toml", "yaml"): "toml_to_yaml",
            ("json", "yaml"): "json_to_yaml",
            ("yaml", "yaml"): "yaml_to_yaml",  # Identity
        }
        
        plan_key = (source_format, target_format)
        plan_name = plan_mapping.get(plan_key, "toml_to_yaml")  # Default
        
        # Perform conversion
        result = yaml_migration_engine.migrate_config(
            source_path,
            target_path,
            plan_name,
            backup=False,  # No backup for simple conversion
            validate_result=True
        )
        
        if result.success:
            console.print(f"[green]✓ Converted {source_path} to {target_path}[/green]")
            console.print(f"[blue]Format:[/blue] {source_format} → {target_format}")
            
            if result.has_warnings:
                console.print(f"\n[yellow]Warnings:[/yellow]")
                for warning in result.warnings:
                    console.print(f"  • {warning}")
        else:
            console.print(f"[red]✗ Conversion failed[/red]")
            for error in result.errors:
                console.print(f"  • {error}")
            
            exit_manager.exit_with_code(ExitCode.OPERATION_FAILED, "Format conversion failed")


if __name__ == "__main__":
    app()