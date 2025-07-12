"""
Configuration management CLI commands.
"""

from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.syntax import Syntax

from vpn.cli.formatters.base import get_formatter
from vpn.cli.utils import handle_errors
from vpn.core.config_loader import ConfigLoader
from vpn.core.exceptions import ConfigurationError

app = typer.Typer(help="Configuration management commands")
console = Console()


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
    config_path: Path = typer.Argument(
        ...,
        help="Path to configuration file",
        exists=True,
    ),
):
    """Validate configuration file."""
    try:
        # Load config
        config = ConfigLoader.load_config(config_path)
        
        # Try to create Settings object to validate
        from vpn.core.config import Settings
        settings = Settings(**config.get('app', {}))
        
        console.print(f"[green]✓[/green] Configuration is valid: {config_path}")
        console.print(f"  Format: {config_path.suffix[1:].upper()}")
        console.print(f"  Sections: {', '.join(config.keys())}")
        
    except ConfigurationError as e:
        console.print(f"[red]Configuration error:[/red] {e}")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Validation failed:[/red] {e}")
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