"""
Enhanced configuration management CLI commands.
"""

import json
import os
from pathlib import Path
from typing import List, Optional

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
    ),
    check_env: bool = typer.Option(
        False,
        "--env/--no-env",
        help="Also validate environment variables"
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
        
        # Also validate environment variables if requested
        if check_env:
            console.print(f"\n🌍 [bold]Validating environment variables...[/bold]")
            
            env_valid, env_issues = validator.validate_environment_variables()
            
            if env_valid:
                console.print("✅ [green]Environment variables are valid![/green]")
            else:
                console.print("❌ [red]Environment variable validation failed[/red]")
                is_valid = False
            
            # Show environment issues
            if env_issues:
                console.print("\n📋 [bold]Environment Validation Results:[/bold]")
                
                env_errors = [i for i in env_issues if i.severity == "error"]
                env_warnings = [i for i in env_issues if i.severity == "warning"]
                env_info = [i for i in env_issues if i.severity == "info"]
                
                if env_errors:
                    console.print(f"\n🚨 [bold red]{len(env_errors)} Environment Error(s):[/bold red]")
                    for issue in env_errors:
                        console.print(f"  • {issue}")
                
                if env_warnings and show_warnings:
                    console.print(f"\n⚠️  [bold yellow]{len(env_warnings)} Environment Warning(s):[/bold yellow]")
                    for issue in env_warnings:
                        console.print(f"  • {issue}")
                
                if env_info:
                    console.print(f"\n💡 [bold blue]{len(env_info)} Environment Info:[/bold blue]")
                    for issue in env_info:
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


@app.command("validate-env")
@handle_errors
def validate_environment(
    show_warnings: bool = typer.Option(
        True,
        "--warnings/--no-warnings",
        help="Show validation warnings"
    ),
    show_values: bool = typer.Option(
        False,
        "--values/--no-values",
        help="Show environment variable values"
    )
):
    """Validate environment variables only."""
    
    validator = ConfigValidator()
    
    console.print("🌍 [bold]Validating environment variables...[/bold]")
    
    try:
        is_valid, issues = validator.validate_environment_variables()
        
        # Display results
        if is_valid:
            console.print("✅ [green]Environment variables are valid![/green]")
        else:
            console.print("❌ [red]Environment variable validation failed[/red]")
        
        # Show issues
        if issues:
            console.print("\n📋 [bold]Environment Validation Results:[/bold]")
            
            errors = [i for i in issues if i.severity == "error"]
            warnings = [i for i in issues if i.severity == "warning"]
            info = [i for i in issues if i.severity == "info"]
            
            if errors:
                console.print(f"\n🚨 [bold red]{len(errors)} Error(s):[/bold red]")
                for issue in errors:
                    output = f"  • {issue}"
                    if show_values and issue.value is not None:
                        output += f" (Value: {issue.value})"
                    console.print(output)
            
            if warnings and show_warnings:
                console.print(f"\n⚠️  [bold yellow]{len(warnings)} Warning(s):[/bold yellow]")
                for issue in warnings:
                    output = f"  • {issue}"
                    if show_values and issue.value is not None:
                        output += f" (Value: {issue.value})"
                    console.print(output)
            
            if info:
                console.print(f"\n💡 [bold blue]{len(info)} Info:[/bold blue]")
                for issue in info:
                    output = f"  • {issue}"
                    if show_values and issue.value is not None:
                        output += f" (Value: {issue.value})"
                    console.print(output)
        
        # Show current environment variables if requested
        if show_values:
            vpn_env_vars = {k: v for k, v in os.environ.items() if k.startswith("VPN_")}
            if vpn_env_vars:
                console.print(f"\n🔧 [bold]Current VPN Environment Variables ({len(vpn_env_vars)}):[/bold]")
                for var, value in sorted(vpn_env_vars.items()):
                    # Mask sensitive values
                    display_value = value
                    if any(word in var.lower() for word in ["secret", "password", "key", "token"]):
                        display_value = "*" * len(value) if len(value) > 0 else ""
                    console.print(f"  {var}={display_value}")
            else:
                console.print("\n💡 [blue]No VPN environment variables found[/blue]")
        
        # Exit with appropriate code
        if not is_valid:
            raise typer.Exit(1)
            
    except Exception as e:
        logger.error(f"Environment validation failed: {e}")
        console.print(f"❌ [red]Environment validation error: {e}[/red]")
        raise typer.Exit(1)


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


@app.command("overlay")
def overlay_commands():
    """Configuration overlay management commands."""
    # This is handled by the overlay subcommand group below
    pass


# Configuration overlay subcommands
overlay_app = typer.Typer(help="Configuration overlay management")
app.add_typer(overlay_app, name="overlay")


@overlay_app.command("list")
@handle_errors
def list_overlays():
    """List available configuration overlays."""
    from vpn.core.config_overlay import get_config_overlay
    
    overlay_manager = get_config_overlay()
    overlays = overlay_manager.list_overlays()
    
    if not overlays:
        console.print("📄 [yellow]No configuration overlays found[/yellow]")
        console.print("\nCreate overlays with: [cyan]vpn config overlay create[/cyan]")
        console.print("Or generate predefined overlays: [cyan]vpn config overlay init[/cyan]")
        return
    
    console.print(f"📄 [bold]Available Configuration Overlays ({len(overlays)}):[/bold]\n")
    
    # Create table
    table = Table(
        "Name", "Description", "Base Config", "Version",
        title="Configuration Overlays",
        show_header=True,
        header_style="bold blue"
    )
    
    for overlay in overlays:
        table.add_row(
            overlay["name"],
            overlay["description"][:50] + "..." if len(overlay["description"]) > 50 else overlay["description"],
            overlay["base_config"] or "-",
            overlay["overlay_version"]
        )
    
    console.print(table)
    console.print(f"\nUse overlays with: [cyan]vpn config overlay apply <name>[/cyan]")


@overlay_app.command("create")
@handle_errors
def create_overlay(
    name: str = typer.Argument(..., help="Overlay name"),
    config_file: Optional[Path] = typer.Option(
        None,
        "--from-file", "-f",
        help="Create overlay from existing config file"
    ),
    description: Optional[str] = typer.Option(
        None,
        "--description", "-d",
        help="Overlay description"
    ),
    base_config: Optional[str] = typer.Option(
        None,
        "--base", "-b",
        help="Base configuration to extend"
    )
):
    """Create a new configuration overlay."""
    from vpn.core.config_overlay import get_config_overlay
    
    overlay_manager = get_config_overlay()
    
    # Load config data
    if config_file:
        if not config_file.exists():
            console.print(f"❌ [red]Config file not found: {config_file}[/red]")
            raise typer.Exit(1)
        
        try:
            config_data = overlay_manager.loader.load_config(config_file)
            console.print(f"📄 Loaded configuration from: {config_file}")
        except Exception as e:
            console.print(f"❌ [red]Failed to load config file: {e}[/red]")
            raise typer.Exit(1)
    else:
        # Create minimal overlay with user input
        console.print("🔧 [bold]Creating overlay interactively...[/bold]")
        console.print("Enter configuration values (press Enter to skip):")
        
        config_data = {}
        
        # Basic settings
        debug = typer.prompt("Debug mode (true/false)", default="", show_default=False)
        if debug:
            config_data["debug"] = debug.lower() in ["true", "1", "yes"]
        
        log_level = typer.prompt("Log level (DEBUG/INFO/WARNING/ERROR)", default="", show_default=False)
        if log_level:
            config_data["log_level"] = log_level.upper()
        
        # Database settings
        db_url = typer.prompt("Database URL", default="", show_default=False)
        if db_url:
            config_data.setdefault("database", {})["url"] = db_url
        
        if not config_data:
            console.print("⚠️  [yellow]No configuration provided, creating empty overlay[/yellow]")
    
    try:
        overlay_path = overlay_manager.create_overlay(
            name=name,
            config_data=config_data,
            base_config=base_config,
            description=description
        )
        
        console.print(f"✅ [green]Created overlay: {name}[/green]")
        console.print(f"📁 Path: {overlay_path}")
        console.print(f"\nApply with: [cyan]vpn config overlay apply {name}[/cyan]")
        
    except Exception as e:
        console.print(f"❌ [red]Failed to create overlay: {e}[/red]")
        raise typer.Exit(1)


@overlay_app.command("apply")
@handle_errors
def apply_overlay(
    overlay_names: List[str] = typer.Argument(..., help="Overlay names to apply (in order)"),
    base_config: Optional[Path] = typer.Option(
        None,
        "--base-config", "-c",
        help="Base configuration file"
    ),
    output: Optional[Path] = typer.Option(
        None,
        "--output", "-o",
        help="Output merged configuration to file"
    ),
    format_type: str = typer.Option(
        "yaml",
        "--format", "-f",
        help="Output format"
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show merged config without saving"
    )
):
    """Apply configuration overlays."""
    from vpn.core.config_overlay import get_config_overlay
    
    overlay_manager = get_config_overlay()
    
    console.print(f"🔧 [bold]Applying overlays: {', '.join(overlay_names)}[/bold]")
    
    try:
        # Apply overlays
        merged_settings = overlay_manager.apply_overlays(
            base_config_path=base_config,
            overlay_names=overlay_names
        )
        
        console.print("✅ [green]Overlays applied successfully![/green]")
        
        # Get merged config as dict
        merged_config = merged_settings.model_dump()
        
        if dry_run or not output:
            # Display merged configuration
            console.print("\n📋 [bold]Merged Configuration:[/bold]")
            
            if format_type.lower() == "json":
                import json
                content = json.dumps(merged_config, indent=2)
                syntax = Syntax(content, "json", theme="monokai", line_numbers=True)
            else:  # yaml
                import yaml
                content = yaml.dump(merged_config, default_flow_style=False)
                syntax = Syntax(content, "yaml", theme="monokai", line_numbers=True)
            
            console.print(syntax)
        
        if output and not dry_run:
            # Save merged configuration
            overlay_manager.loader.save_config(merged_config, output)
            console.print(f"💾 [green]Saved merged configuration: {output}[/green]")
        
    except Exception as e:
        console.print(f"❌ [red]Failed to apply overlays: {e}[/red]")
        raise typer.Exit(1)


@overlay_app.command("delete")
@handle_errors
def delete_overlay(
    name: str = typer.Argument(..., help="Overlay name to delete"),
    force: bool = typer.Option(
        False,
        "--force", "-f",
        help="Delete without confirmation"
    )
):
    """Delete a configuration overlay."""
    from vpn.core.config_overlay import get_config_overlay
    
    overlay_manager = get_config_overlay()
    
    # Check if overlay exists
    overlays = overlay_manager.list_overlays()
    overlay_names = [o["name"] for o in overlays]
    
    if name not in overlay_names:
        console.print(f"❌ [red]Overlay not found: {name}[/red]")
        console.print(f"Available overlays: {', '.join(overlay_names)}")
        raise typer.Exit(1)
    
    # Confirm deletion
    if not force:
        confirm = typer.confirm(f"Delete overlay '{name}'?", default=False)
        if not confirm:
            console.print("❌ Deletion cancelled")
            raise typer.Exit(1)
    
    # Delete overlay
    success = overlay_manager.delete_overlay(name)
    
    if success:
        console.print(f"✅ [green]Deleted overlay: {name}[/green]")
    else:
        console.print(f"❌ [red]Failed to delete overlay: {name}[/red]")
        raise typer.Exit(1)


@overlay_app.command("init")
@handle_errors
def init_predefined_overlays(
    force: bool = typer.Option(
        False,
        "--force", "-f",
        help="Overwrite existing overlays"
    )
):
    """Initialize predefined configuration overlays."""
    from vpn.core.config_overlay import get_config_overlay
    
    overlay_manager = get_config_overlay()
    
    console.print("🚀 [bold]Initializing predefined configuration overlays...[/bold]")
    
    # Check existing overlays
    existing_overlays = {o["name"] for o in overlay_manager.list_overlays()}
    predefined_names = ["development", "production", "testing", "docker", "high-security"]
    
    conflicts = existing_overlays.intersection(predefined_names)
    if conflicts and not force:
        console.print(f"⚠️  [yellow]Existing overlays found: {', '.join(conflicts)}[/yellow]")
        console.print("Use --force to overwrite or delete them first")
        raise typer.Exit(1)
    
    try:
        created_overlays = overlay_manager.create_predefined_overlays()
        
        console.print(f"✅ [green]Created {len(created_overlays)} predefined overlays:[/green]")
        for overlay_path in created_overlays:
            console.print(f"  📄 {overlay_path.stem}")
        
        console.print(f"\n💡 [bold]Usage examples:[/bold]")
        console.print("  Development: [cyan]vpn config overlay apply development[/cyan]")
        console.print("  Production:  [cyan]vpn config overlay apply production[/cyan]")
        console.print("  Docker:      [cyan]vpn config overlay apply docker production[/cyan]")
        console.print("  List all:    [cyan]vpn config overlay list[/cyan]")
        
    except Exception as e:
        console.print(f"❌ [red]Failed to create predefined overlays: {e}[/red]")
        raise typer.Exit(1)


@overlay_app.command("export")
@handle_errors
def export_overlay(
    name: str = typer.Argument(..., help="Overlay name to export"),
    output: Path = typer.Argument(..., help="Output file path"),
    format_type: str = typer.Option(
        "yaml",
        "--format", "-f",
        help="Export format (yaml/json/toml)"
    )
):
    """Export an overlay to a file."""
    from vpn.core.config_overlay import get_config_overlay
    
    overlay_manager = get_config_overlay()
    
    console.print(f"📤 [bold]Exporting overlay '{name}' to {output}...[/bold]")
    
    try:
        success = overlay_manager.export_overlay(name, output, format_type)
        
        if success:
            console.print(f"✅ [green]Exported overlay to: {output}[/green]")
        else:
            console.print(f"❌ [red]Failed to export overlay: {name}[/red]")
            raise typer.Exit(1)
            
    except Exception as e:
        console.print(f"❌ [red]Export failed: {e}[/red]")
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


@app.command("hot-reload")
@handle_errors
def manage_hot_reload(
    action: str = typer.Argument(
        ..., 
        help="Action to perform: enable, disable, status, force-reload"
    ),
    watch_env: bool = typer.Option(
        True,
        "--env/--no-env",
        help="Monitor environment variables"
    )
):
    """Manage configuration hot-reload functionality."""
    from vpn.core.config_hotreload import get_hot_reload_manager
    
    manager = get_hot_reload_manager()
    
    if action == "enable":
        console.print("🔄 [bold]Enabling configuration hot-reload...[/bold]")
        
        success = manager.enable_hot_reload()
        
        if success:
            console.print("✅ [green]Configuration hot-reload enabled![/green]")
            console.print("\n💡 [bold]Hot-reload will monitor:[/bold]")
            console.print("  📁 Configuration files (.yaml, .toml, .json)")
            console.print("  📄 Overlay files")
            console.print("  🌍 Environment variables (VPN_*)")
            console.print("  📋 .env files")
            console.print("\nConfiguration will be automatically reloaded when changes are detected.")
        else:
            console.print("❌ [red]Failed to enable hot-reload[/red]")
            console.print("Check that VPN_RELOAD=true in your configuration")
            raise typer.Exit(1)
    
    elif action == "disable":
        console.print("🔄 [bold]Disabling configuration hot-reload...[/bold]")
        
        manager.disable_hot_reload()
        console.print("✅ [green]Configuration hot-reload disabled[/green]")
    
    elif action == "status":
        console.print("📊 [bold]Configuration Hot-Reload Status:[/bold]\n")
        
        status = manager.get_status()
        
        # Create status table
        table = Table(
            "Setting", "Value", "Description",
            title="Hot-Reload Status",
            show_header=True,
            header_style="bold blue"
        )
        
        # Status indicators
        enabled_indicator = "🟢 Enabled" if status["enabled"] else "🔴 Disabled"
        watching_indicator = "👁️  Active" if status["watching"] else "👁️  Inactive"
        observer_indicator = "✅ Running" if status["observer_alive"] else "❌ Stopped"
        env_indicator = "🌍 Monitoring" if status["env_monitoring"] else "🌍 Not monitoring"
        
        table.add_row("Hot-Reload", enabled_indicator, "Overall hot-reload status")
        table.add_row("File Watching", watching_indicator, "File system monitoring")
        table.add_row("Observer", observer_indicator, "File system observer status")
        table.add_row("Environment", env_indicator, "Environment variable monitoring")
        table.add_row("Change Callbacks", str(status["change_callbacks"]), "Registered change handlers")
        table.add_row("Error Callbacks", str(status["error_callbacks"]), "Registered error handlers")
        table.add_row("Environment Variables", str(status["env_vars_count"]), "VPN_* variables being monitored")
        table.add_row("Debounce Delay", f"{status['debounce_delay']}s", "Delay before reload")
        table.add_row("Max Attempts", str(status["max_attempts"]), "Maximum reload attempts")
        
        console.print(table)
        
        if not status["enabled"]:
            console.print("\n💡 [yellow]Enable hot-reload with:[/yellow] [cyan]vpn config hot-reload enable[/cyan]")
    
    elif action == "force-reload":
        console.print("🔄 [bold]Forcing configuration reload...[/bold]")
        
        success = manager.force_reload()
        
        if success:
            console.print("✅ [green]Configuration reload triggered[/green]")
            console.print("Check logs for reload status")
        else:
            console.print("❌ [red]Failed to trigger reload[/red]")
            console.print("Ensure hot-reload is enabled first")
            raise typer.Exit(1)
    
    else:
        console.print(f"❌ [red]Unknown action: {action}[/red]")
        console.print("Available actions: enable, disable, status, force-reload")
        raise typer.Exit(1)


@app.command("restore")
def restore_config():
    """Restore configuration (placeholder for future implementation)."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config restore command not yet implemented"))