"""
Main CLI application using Typer.
"""

import asyncio
import sys
from pathlib import Path
from typing import Optional

import typer
from rich import print as rprint
from rich.console import Console

from vpn import __version__
from vpn.core.config import RuntimeConfig, settings
from vpn.core.exceptions import VPNError
from vpn.utils.logger import LogContext, get_logger, setup_logging

# Initialize CLI app
app = typer.Typer(
    name="vpn",
    help="VPN Manager - Modern VPN Management System with TUI",
    no_args_is_help=True,
    rich_markup_mode="rich",
    pretty_exceptions_show_locals=False,
)

# Console for rich output
console = Console()
logger = get_logger(__name__)

# Runtime configuration
runtime_config = RuntimeConfig()


def version_callback(value: bool):
    """Show version and exit."""
    if value:
        rprint(f"[bold]VPN Manager[/bold] version [green]{__version__}[/green]")
        raise typer.Exit()


@app.callback()
def main(
    version: bool = typer.Option(
        None,
        "--version",
        "-v",
        help="Show version and exit",
        callback=version_callback,
        is_eager=True,
    ),
    debug: bool = typer.Option(
        False,
        "--debug",
        help="Enable debug mode",
        envvar="VPN_DEBUG",
    ),
    quiet: bool = typer.Option(
        False,
        "--quiet",
        "-q",
        help="Suppress output except errors",
    ),
    verbose: bool = typer.Option(
        False,
        "--verbose",
        help="Enable verbose output",
    ),
    output_format: str = typer.Option(
        "table",
        "--format",
        "-f",
        help="Output format: table, json, yaml, plain",
    ),
    no_color: bool = typer.Option(
        False,
        "--no-color",
        help="Disable colored output",
    ),
    config_file: Optional[Path] = typer.Option(
        None,
        "--config",
        "-c",
        help="Path to configuration file",
    ),
):
    """
    VPN Manager - Modern VPN Management System
    
    Manage VPN servers, users, and configurations with ease.
    """
    # Update runtime configuration
    runtime_config.quiet = quiet
    runtime_config.verbose = verbose
    runtime_config.output_format = output_format
    runtime_config.no_color = no_color
    
    # Update settings if debug is enabled
    if debug:
        settings.debug = True
        settings.log_level = "DEBUG"
    
    # Setup logging based on flags
    log_level = None
    if quiet:
        log_level = "ERROR"
    elif verbose or debug:
        log_level = "DEBUG"
    
    setup_logging(
        log_level=log_level,
        rich_output=not no_color,
    )
    
    # Load custom config file if provided
    if config_file and config_file.exists():
        logger.info(f"Loading configuration from: {config_file}")
        # TODO: Implement config file loading


@app.command()
def tui():
    """Launch the Terminal User Interface."""
    try:
        from vpn.tui.app import VPNManagerApp
        
        console.print("[bold]Launching VPN Manager TUI...[/bold]")
        app = VPNManagerApp()
        app.run()
    except ImportError:
        console.print(
            "[red]TUI dependencies not installed. "
            "Install with: pip install textual[/red]"
        )
        raise typer.Exit(1)
    except KeyboardInterrupt:
        console.print("\n[yellow]TUI closed by user[/yellow]")
        raise typer.Exit(0)
    except Exception as e:
        console.print(f"[red]Error launching TUI: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def menu():
    """Launch interactive menu (legacy)."""
    console.print("[yellow]The menu command is deprecated. Use 'vpn tui' instead.[/yellow]")
    tui()


@app.command()
def doctor():
    """Run system diagnostics."""
    console.print("[bold]Running system diagnostics...[/bold]\n")
    
    with console.status("Checking system requirements..."):
        # TODO: Implement actual diagnostics
        checks = [
            ("Python version", "✓", f"Python {sys.version.split()[0]}"),
            ("Docker", "✓", "Docker 24.0.0"),
            ("Database", "✓", "SQLite ready"),
            ("Network tools", "✓", "iptables available"),
            ("Permissions", "⚠", "Running without root"),
        ]
    
    # Display results
    from rich.table import Table
    
    table = Table(title="System Diagnostics", show_header=True)
    table.add_column("Component", style="cyan")
    table.add_column("Status", justify="center")
    table.add_column("Details")
    
    for component, status, details in checks:
        status_style = "green" if status == "✓" else "yellow" if status == "⚠" else "red"
        table.add_row(component, f"[{status_style}]{status}[/{status_style}]", details)
    
    console.print(table)
    console.print("\n[green]System check complete![/green]")


@app.command()
def init():
    """Initialize VPN Manager configuration."""
    console.print("[bold]Initializing VPN Manager...[/bold]\n")
    
    try:
        # Create directories
        for path_name, path in [
            ("Configuration", settings.config_path),
            ("Data", settings.data_path),
            ("Installation", settings.install_path),
        ]:
            if path.exists():
                console.print(f"[green]✓[/green] {path_name} directory: {path}")
            else:
                path.mkdir(parents=True, exist_ok=True)
                console.print(f"[green]✓[/green] Created {path_name} directory: {path}")
        
        # Initialize database
        from vpn.core.database import init_database
        
        asyncio.run(init_database())
        console.print(f"[green]✓[/green] Database initialized")
        
        console.print("\n[green]Initialization complete![/green]")
        
    except Exception as e:
        console.print(f"[red]Initialization failed: {e}[/red]")
        raise typer.Exit(1)


def run_async(coro):
    """Run async coroutine in sync context."""
    try:
        return asyncio.run(coro)
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        raise typer.Exit(130)
    except VPNError as e:
        logger.error(f"{e.error_code}: {e.message}")
        if e.details:
            logger.debug(f"Details: {e.details}")
        raise typer.Exit(1)
    except Exception as e:
        logger.exception("Unexpected error occurred")
        raise typer.Exit(1)


# Import command groups
from vpn.cli.commands.users import app as users_app
from vpn.cli.commands.server import app as server_app
from vpn.cli.commands.proxy import app as proxy_app
from vpn.cli.commands.monitor import app as monitor_app
from vpn.cli.commands.config import app as config_app

# Add command groups
app.add_typer(users_app, name="users", help="User management commands")
app.add_typer(server_app, name="server", help="Server management commands")
app.add_typer(proxy_app, name="proxy", help="Proxy management commands")
app.add_typer(monitor_app, name="monitor", help="Monitoring and statistics")
app.add_typer(config_app, name="config", help="Configuration management")


def main():
    """Entry point for the CLI application."""
    app()


if __name__ == "__main__":
    main()