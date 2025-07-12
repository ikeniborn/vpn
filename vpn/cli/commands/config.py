"""
Enhanced configuration management CLI commands.
"""

import json
from pathlib import Path
from typing import Optional

import typer
import yaml
from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax
from rich.table import Table

from vpn.cli.formatters.base import get_formatter
from vpn.cli.utils import handle_errors
from vpn.core.config_loader import ConfigLoader
from vpn.core.config_migration import ConfigMigrator
from vpn.core.config_validator import ConfigSchemaGenerator, ConfigValidator
from vpn.core.enhanced_config import get_settings
from vpn.core.exceptions import ConfigurationError
from vpn.utils.logger import get_logger

app = typer.Typer(help="Enhanced configuration management commands")
console = Console()
logger = get_logger(__name__)


@app.command("show")
@handle_errors
def show_config(
    config_path: Optional[Path] = typer.Option(
        None,
        "--config",
        "-c",
        help="Path to configuration file",
    ),
    format: str = typer.Option(
        "auto",
        "--format",
        "-f",
        help="Output format",
        case_sensitive=False,
    ),
):
    """Show current configuration."""
    # Find config file
    if config_path is None:
        config_path = ConfigLoader.find_config_file()
        if config_path is None:
            console.print("[yellow]No configuration file found[/yellow]")
            console.print("Create one with: [cyan]vpn config generate[/cyan]")
            return
    
    # Load and display config
    try:
        config = ConfigLoader.load_config(config_path)
        console.print(f"[green]Configuration loaded from:[/green] {config_path}")
        console.print()
        
        # Determine format
        if format == "auto":
            format = "yaml" if config_path.suffix in ['.yaml', '.yml'] else "toml"
        
        # Display with syntax highlighting
        if format == "yaml":
            import yaml
            content = yaml.dump(config, default_flow_style=False, sort_keys=False)
            syntax = Syntax(content, "yaml", theme="monokai", line_numbers=True)
        else:  # toml
            import toml
            content = toml.dumps(config)
            syntax = Syntax(content, "toml", theme="monokai", line_numbers=True)
        
        console.print(syntax)
        
    except ConfigurationError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(1)


@app.command("generate")
@handle_errors
def generate_config(
    output_path: Path = typer.Argument(
        "config.yaml",
        help="Path to save configuration file",
    ),
    format: str = typer.Option(
        "auto",
        "--format",
        "-f",
        help="Configuration format (yaml/toml/auto)",
        case_sensitive=False,
    ),
    force: bool = typer.Option(
        False,
        "--force",
        help="Overwrite existing file",
    ),
):
    """Generate example configuration file."""
    # Auto-detect format from extension
    if format == "auto":
        if output_path.suffix in ['.yaml', '.yml']:
            format = "yaml"
        elif output_path.suffix == '.toml':
            format = "toml"
        else:
            console.print("[yellow]Cannot auto-detect format from extension.[/yellow]")
            console.print("Defaulting to YAML format.")
            format = "yaml"
            output_path = output_path.with_suffix('.yaml')
    
    # Check if file exists
    if output_path.exists() and not force:
        console.print(f"[red]File already exists:[/red] {output_path}")
        console.print("Use --force to overwrite")
        raise typer.Exit(1)
    
    # Generate example config
    try:
        content = ConfigLoader.generate_example_config(
            format_type=format,
            include_comments=True
        )
        
        # Save to file
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(content)
        
        console.print(f"[green]✓[/green] Generated {format.upper()} configuration: {output_path}")
        console.print()
        console.print("Edit this file to customize your VPN Manager settings.")
        console.print(f"Use it with: [cyan]vpn --config {output_path} [command][/cyan]")
        
    except Exception as e:
        console.print(f"[red]Failed to generate configuration:[/red] {e}")
        raise typer.Exit(1)


@app.command("validate")
@handle_errors
def validate_config(
    config_path: Optional[Path] = typer.Option(
        None,
        "--config", "-c",
        help="Configuration file to validate (default: auto-detect)"
    ),
    strict: bool = typer.Option(
        False,
        "--strict",
        help="Enable strict validation mode"
    ),
    auto_migrate: bool = typer.Option(
        True,
        "--migrate/--no-migrate",
        help="Automatically migrate old configurations"
    ),
    show_warnings: bool = typer.Option(
        True,
        "--warnings/--no-warnings",
        help="Show validation warnings"
    )
):
    """Validate configuration file with enhanced validation."""
    
    validator = ConfigValidator()
    
    # Auto-detect config file if not specified
    if config_path is None:
        settings = get_settings()
        config_paths = settings.config_file_paths
        
        found_config = None
        for path in config_paths:
            if path.exists():
                found_config = path
                break
        
        if found_config is None:
            console.print("❌ [red]No configuration file found[/red]")
            console.print("\n📋 [bold]Searched locations:[/bold]")
            for path in config_paths:
                console.print(f"  • {path}")
            console.print("\nUse 'vpn config generate' to create a configuration file")
            raise typer.Exit(1)
        
        config_path = found_config
    
    console.print(f"🔍 [bold]Validating configuration: {config_path}[/bold]")
    
    try:
        is_valid, issues = validator.validate_config_file(
            config_path,
            auto_migrate=auto_migrate,
            strict=strict
        )
        
        # Display results
        if is_valid:
            console.print("✅ [green]Configuration is valid![/green]")
        else:
            console.print("❌ [red]Configuration validation failed[/red]")
        
        # Show issues
        if issues:
            console.print("\n📋 [bold]Validation Results:[/bold]")
            
            errors = [i for i in issues if i.severity == "error"]
            warnings = [i for i in issues if i.severity == "warning"]
            info = [i for i in issues if i.severity == "info"]
            
            if errors:
                console.print(f"\n🚨 [bold red]{len(errors)} Error(s):[/bold red]")
                for issue in errors:
                    console.print(f"  • {issue}")
            
            if warnings and show_warnings:
                console.print(f"\n⚠️  [bold yellow]{len(warnings)} Warning(s):[/bold yellow]")
                for issue in warnings:
                    console.print(f"  • {issue}")
            
            if info:
                console.print(f"\n💡 [bold blue]{len(info)} Info:[/bold blue]")
                for issue in info:
                    console.print(f"  • {issue}")
        
        # Exit with appropriate code
        if not is_valid:
            raise typer.Exit(1)
            
    except Exception as e:
        logger.error(f"Validation failed: {e}")
        console.print(f"❌ [red]Validation error: {e}[/red]")
        raise typer.Exit(1)


@app.command("convert")
@handle_errors
def convert_config(
    input_path: Path = typer.Argument(
        ...,
        help="Input configuration file",
        exists=True,
    ),
    output_path: Path = typer.Argument(
        ...,
        help="Output configuration file",
    ),
    force: bool = typer.Option(
        False,
        "--force",
        help="Overwrite existing file",
    ),
):
    """Convert configuration between formats (YAML ↔ TOML)."""
    # Check if output exists
    if output_path.exists() and not force:
        console.print(f"[red]File already exists:[/red] {output_path}")
        console.print("Use --force to overwrite")
        raise typer.Exit(1)
    
    try:
        # Load config
        config = ConfigLoader.load_config(input_path)
        
        # Save in new format
        ConfigLoader.save_config(config, output_path)
        
        console.print(f"[green]✓[/green] Converted configuration:")
        console.print(f"  From: {input_path} ({input_path.suffix[1:].upper()})")
        console.print(f"  To:   {output_path} ({output_path.suffix[1:].upper()})")
        
    except ConfigurationError as e:
        console.print(f"[red]Conversion failed:[/red] {e}")
        raise typer.Exit(1)


@app.command("migrate")
@handle_errors
def migrate_config(
    config_path: Optional[Path] = typer.Option(
        None,
        "--config", "-c",
        help="Configuration file to migrate (default: find all)"
    ),
    backup: bool = typer.Option(
        True,
        "--backup/--no-backup",
        help="Create backup before migration"
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show what would be migrated without making changes"
    ),
    force: bool = typer.Option(
        False,
        "--force",
        help="Migrate even if already current version"
    )
):
    """Migrate configuration files to current version."""
    
    migrator = ConfigMigrator()
    
    if config_path:
        # Migrate specific file
        config_paths = [config_path]
    else:
        # Find all config files
        settings = get_settings()
        search_paths = [
            Path.cwd(),
            settings.paths.config_path,
            Path("/etc/vpn-manager")
        ]
        
        config_paths = []
        for search_path in search_paths:
            if search_path.exists():
                for pattern in ["*.yaml", "*.yml", "*.toml"]:
                    config_paths.extend(search_path.glob(pattern))
    
    if not config_paths:
        console.print("❌ [red]No configuration files found for migration[/red]")
        raise typer.Exit(1)
    
    console.print(f"🔄 [bold]Migrating {len(config_paths)} configuration file(s)...[/bold]")
    if dry_run:
        console.print("🧪 [yellow](Dry run mode - no changes will be made)[/yellow]")
    
    results = []
    
    for config_file in config_paths:
        if not config_file.exists():
            continue
        
        console.print(f"\n📄 Processing: {config_file}")
        
        # Check if migration is needed
        if not force and not migrator.needs_migration(config_file):
            console.print("  ✅ Already current version, skipping")
            continue
        
        try:
            result = migrator.migrate_config(config_file, backup=backup, dry_run=dry_run)
            results.append(result)
            
            if result.success:
                console.print(f"  ✅ [green]Migrated from {result.from_version} to {result.to_version}[/green]")
                
                if result.backup_path:
                    console.print(f"  💾 Backup created: {result.backup_path}")
                
                if result.changes_made:
                    console.print("  📝 Changes made:")
                    for change in result.changes_made:
                        console.print(f"    • {change}")
                
                if result.warnings:
                    console.print("  ⚠️  Warnings:")
                    for warning in result.warnings:
                        console.print(f"    • {warning}")
            else:
                console.print(f"  ❌ [red]Migration failed[/red]")
                for warning in result.warnings:
                    console.print(f"    • {warning}")
                    
        except Exception as e:
            logger.error(f"Migration failed for {config_file}: {e}")
            console.print(f"  ❌ [red]Error: {e}[/red]")
    
    # Summary
    if results:
        console.print(f"\n📊 [bold]Migration Summary:[/bold]")
        successful = sum(1 for r in results if r.success)
        failed = len(results) - successful
        
        console.print(f"  ✅ Successful: {successful}")
        if failed:
            console.print(f"  ❌ Failed: {failed}")
        
        if not dry_run and successful > 0:
            console.print("\n💡 [bold]Next steps:[/bold]")
            console.print("1. Validate migrated configurations: vpn config validate")
            console.print("2. Review changes and test your setup")


@app.command("schema")
@handle_errors
def generate_schema(
    format_type: str = typer.Option(
        "json",
        "--format", "-f",
        help="Schema format",
        show_choices=["json", "markdown", "html"]
    ),
    output: Optional[Path] = typer.Option(
        None,
        "--output", "-o",
        help="Output file path"
    ),
    show_content: bool = typer.Option(
        False,
        "--show",
        help="Display schema content without saving"
    )
):
    """Generate configuration schema documentation."""
    
    generator = ConfigSchemaGenerator()
    
    try:
        if format_type == "json":
            # Generate JSON schema
            schema = generator.generate_json_schema()
            content = json.dumps(schema, indent=2)
        else:
            # Generate documentation
            content = generator.generate_schema_documentation(format_type)
        
        if show_content:
            # Display content
            if format_type == "json":
                syntax = Syntax(content, "json", theme="monokai", line_numbers=True)
            elif format_type == "markdown":
                syntax = Syntax(content, "markdown", theme="monokai", line_numbers=True)
            else:
                syntax = Syntax(content, "html", theme="monokai", line_numbers=True)
            
            console.print(Panel(
                syntax,
                title=f"Configuration Schema ({format_type.upper()})",
                expand=False
            ))
            return
        
        # Determine output path
        if output is None:
            settings = get_settings()
            ext = "json" if format_type == "json" else format_type
            output = settings.paths.config_path / f"schema.{ext}"
        
        # Save schema
        generator.save_schema_file(output, format_type)
        
        console.print(f"✅ [green]Generated schema file: {output}[/green]")
        
    except Exception as e:
        logger.error(f"Failed to generate schema: {e}")
        console.print(f"❌ [red]Error generating schema: {e}[/red]")
        raise typer.Exit(1)


@app.command("edit")
def edit_config():
    """Edit configuration (placeholder for future implementation)."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config edit command not yet implemented"))


@app.command("backup")
def backup_config():
    """Backup configuration (placeholder for future implementation)."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config backup command not yet implemented"))


@app.command("restore")
def restore_config():
    """Restore configuration (placeholder for future implementation)."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config restore command not yet implemented"))