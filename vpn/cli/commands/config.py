"""
Configuration management CLI commands.
"""

import typer
from rich.console import Console

from vpn.cli.formatters.base import get_formatter

app = typer.Typer(help="Configuration management commands")
console = Console()


@app.command("show")
def show_config():
    """Show current configuration."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config show command not yet implemented"))


@app.command("edit")
def edit_config():
    """Edit configuration."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config edit command not yet implemented"))


@app.command("backup")
def backup_config():
    """Backup configuration."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config backup command not yet implemented"))


@app.command("restore")
def restore_config():
    """Restore configuration."""
    formatter = get_formatter()
    console.print(formatter.format_info("Config restore command not yet implemented"))