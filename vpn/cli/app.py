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
from vpn.cli.exit_codes import (
    ExitCode, exit_manager, handle_cli_errors, setup_exit_codes_for_cli,
    show_exit_codes_help
)

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
    # Set up exit code handling
    setup_exit_codes_for_cli()
    
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
    if config_file:
        if config_file.exists():
            logger.info(f"Loading configuration from: {config_file}")
            # TODO: Implement config file loading
        else:
            exit_manager.exit_with_code(
                ExitCode.CONFIG_FILE_NOT_FOUND,
                f"Configuration file not found: {config_file}"
            )


@app.command()
def tui():
    """Launch the Terminal User Interface."""
    with handle_cli_errors("TUI launch"):
        try:
            from vpn.tui.app import VPNManagerApp
            
            console.print("[bold]Launching VPN Manager TUI...[/bold]")
            app = VPNManagerApp()
            app.run()
            exit_manager.exit_with_code(ExitCode.SUCCESS, "TUI session completed")
        except ImportError:
            exit_manager.exit_with_code(
                ExitCode.GENERAL_ERROR,
                "TUI dependencies not installed",
                suggestion="Install with: pip install textual"
            )


@app.command()
def menu():
    """Launch interactive menu (legacy)."""
    console.print("[yellow]The menu command is deprecated. Use 'vpn tui' instead.[/yellow]")
    tui()


@app.command()
def doctor():
    """Run comprehensive system diagnostics."""
    async def _run_doctor():
        from vpn.utils.diagnostics import run_diagnostics
        from rich.table import Table
        
        console.print("[bold]Running comprehensive system diagnostics...[/bold]\n")
        
        with console.status("Performing diagnostic checks..."):
            checks, summary = await run_diagnostics()
        
        # Display results
        table = Table(title="System Diagnostics Report", show_header=True)
        table.add_column("Component", style="cyan", width=20)
        table.add_column("Status", justify="center", width=8)
        table.add_column("Details", style="dim")
        
        for check in checks:
            status_style = "green" if check.status == "✓" else "yellow" if check.status == "⚠" else "red"
            table.add_row(
                check.name,
                f"[{status_style}]{check.status}[/{status_style}]",
                check.details
            )
        
        console.print(table)
        
        # Display summary
        console.print("\n[bold]Summary:[/bold]")
        console.print(f"  Total checks: {summary['total']}")
        console.print(f"  [green]✓ Passed: {summary['passed']}[/green]")
        console.print(f"  [yellow]⚠ Warnings: {summary['warnings']}[/yellow]")
        console.print(f"  [red]✗ Errors: {summary['errors']}[/red]")
        
        # Determine exit code based on results
        if summary['errors'] == 0 and summary['warnings'] == 0:
            console.print("\n[green]✅ System is ready for VPN operations![/green]")
            return ExitCode.SUCCESS
        elif summary['errors'] == 0:
            console.print("\n[yellow]⚠️ System is mostly ready with some warnings.[/yellow]")
            return ExitCode.SUCCESS  # Warnings don't fail the check
        else:
            console.print("\n[red]❌ System has issues that need to be resolved.[/red]")
            console.print("[dim]Run 'vpn doctor --help' for troubleshooting tips.[/dim]")
            return ExitCode.SYSTEM_ERROR
    
    with handle_cli_errors("System diagnostics"):
        exit_code = run_async(_run_doctor())
        exit_manager.exit_with_code(exit_code)


@app.command()
def init():
    """Initialize VPN Manager configuration."""
    console.print("[bold]Initializing VPN Manager...[/bold]\n")
    
    with handle_cli_errors("VPN Manager initialization"):
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
        exit_manager.exit_with_code(ExitCode.SUCCESS, "VPN Manager initialized successfully")


@app.command()
def migrate(
    rust_path: Optional[Path] = typer.Option(
        None,
        "--rust-path",
        help="Path to Rust VPN Manager installation"
    ),
    no_backup: bool = typer.Option(
        False,
        "--no-backup",
        help="Skip creating backup"
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Only analyze what would be migrated"
    ),
):
    """Migrate from Rust VPN Manager to Python version."""
    async def _run_migration():
        from vpn.utils.migration import migrate_from_rust
        
        if dry_run:
            console.print("[blue]🔍 Analyzing Rust installation (dry run)...[/blue]\n")
        else:
            console.print("[bold]🚀 Migrating from Rust VPN Manager...[/bold]\n")
            
            if not no_backup:
                console.print("[yellow]Creating backup before migration...[/yellow]")
        
        try:
            migrated_count, errors = await migrate_from_rust(
                rust_path=rust_path,
                backup=not no_backup,
                dry_run=dry_run
            )
            
            if dry_run:
                console.print(f"\n[blue]Dry run complete: {migrated_count} users found[/blue]")
            else:
                if migrated_count > 0:
                    console.print(f"\n[green]✅ Migration successful: {migrated_count} users migrated[/green]")
                else:
                    console.print("\n[yellow]⚠️ No users migrated[/yellow]")
            
            if errors:
                console.print(f"\n[red]❌ {len(errors)} errors occurred:[/red]")
                for error in errors:
                    console.print(f"  • {error}")
                    
                if not dry_run:
                    raise typer.Exit(1)
            
        except Exception as e:
            console.print(f"\n[red]Migration failed: {e}[/red]")
            raise typer.Exit(1)
    
    with handle_cli_errors("Migration"):
        run_async(_run_migration())


@app.command()
def exit_codes():
    """Show exit code reference and documentation."""
    show_exit_codes_help()
    exit_manager.exit_with_code(ExitCode.SUCCESS)


@app.command()
def completions(
    shell: str = typer.Argument(
        help="Shell type: bash, zsh, fish, powershell"
    ),
    install: bool = typer.Option(
        False,
        "--install",
        help="Install completions to shell configuration"
    )
):
    """Generate shell completions for VPN Manager."""
    from typer.completion import get_completion
    
    valid_shells = ["bash", "zsh", "fish", "powershell"]
    if shell not in valid_shells:
        console.print(f"[red]Invalid shell: {shell}[/red]")
        console.print(f"Valid shells: {', '.join(valid_shells)}")
        raise typer.Exit(1)
    
    try:
        # Generate completion script
        completion_script = get_completion(shell)
        
        if install:
            # Install to shell configuration
            home = Path.home()
            
            if shell == "bash":
                config_files = [home / ".bashrc", home / ".bash_profile"]
                completion_line = 'eval "$(_VPN_COMPLETE=bash_source vpn)"'
            elif shell == "zsh":
                config_files = [home / ".zshrc"]
                completion_line = 'eval "$(_VPN_COMPLETE=zsh_source vpn)"'
            elif shell == "fish":
                config_dir = home / ".config" / "fish" / "completions"
                config_dir.mkdir(parents=True, exist_ok=True)
                completion_file = config_dir / "vpn.fish"
                
                with open(completion_file, 'w') as f:
                    f.write(completion_script)
                
                console.print(f"[green]✓ Fish completions installed to: {completion_file}[/green]")
                console.print("[blue]Restart your shell or run: source ~/.config/fish/config.fish[/blue]")
                return
            elif shell == "powershell":
                console.print("[yellow]PowerShell completion installation not yet supported[/yellow]")
                console.print("Add this to your PowerShell profile:")
                console.print(completion_script)
                return
            
            # For bash/zsh, add to config files
            installed = False
            for config_file in config_files:
                if config_file.exists():
                    # Check if already installed
                    with open(config_file, 'r') as f:
                        content = f.read()
                    
                    if completion_line not in content:
                        with open(config_file, 'a') as f:
                            f.write(f"\n# VPN Manager completions\n{completion_line}\n")
                        
                        console.print(f"[green]✓ Completions added to: {config_file}[/green]")
                        installed = True
                        break
                    else:
                        console.print(f"[yellow]Completions already installed in: {config_file}[/yellow]")
                        installed = True
                        break
            
            if installed:
                console.print("[blue]Restart your shell or run: source ~/.bashrc (or ~/.zshrc)[/blue]")
            else:
                console.print("[red]Could not find shell configuration file[/red]")
                console.print(f"Add this line to your shell config:\n{completion_line}")
        
        else:
            # Just output the completion script
            console.print(completion_script)
    
    except Exception as e:
        console.print(f"[red]Failed to generate completions: {e}[/red]")
        raise typer.Exit(1)


def run_async(coro):
    """Run async coroutine in sync context."""
    try:
        return asyncio.run(coro)
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        exit_manager.exit_with_code(ExitCode.KEYBOARD_INTERRUPT, "Operation cancelled by user")
    except VPNError as e:
        logger.error(f"{e.error_code}: {e.message}")
        if e.details:
            logger.debug(f"Details: {e.details}")
        
        # Map VPN error to appropriate exit code
        code = exit_manager.handle_exception(e)
        exit_manager.exit_with_code(code, f"{e.error_code}: {e.message}")
    except Exception as e:
        logger.exception("Unexpected error occurred")
        code = exit_manager.handle_exception(e)
        exit_manager.exit_with_code(code, f"Unexpected error: {e}")


# Import command groups
from vpn.cli.commands.users import app as users_app
from vpn.cli.commands.server import app as server_app
from vpn.cli.commands.proxy import app as proxy_app
from vpn.cli.commands.monitor import app as monitor_app
from vpn.cli.commands.config import app as config_app
from vpn.cli.commands.compose import app as compose_app
from vpn.cli.commands.yaml_commands import app as yaml_app

# Add command groups
app.add_typer(users_app, name="users", help="User management commands")
app.add_typer(server_app, name="server", help="Server management commands")
app.add_typer(proxy_app, name="proxy", help="Proxy management commands")
app.add_typer(monitor_app, name="monitor", help="Monitoring and statistics")
app.add_typer(config_app, name="config", help="Configuration management")
app.add_typer(compose_app, name="compose", help="Docker Compose orchestration")
app.add_typer(yaml_app, name="yaml", help="YAML configuration management")


def main():
    """Entry point for the CLI application."""
    app()


if __name__ == "__main__":
    main()