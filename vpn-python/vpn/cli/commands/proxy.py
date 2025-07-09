"""
Proxy management CLI commands.
"""

import typer
from rich.console import Console

from vpn.cli.formatters.base import get_formatter

app = typer.Typer(help="Proxy management commands")
console = Console()


@app.command("start")
def start_proxy():
    """Start proxy server."""
    formatter = get_formatter()
    console.print(formatter.format_info("Proxy start command not yet implemented"))


@app.command("stop")
def stop_proxy():
    """Stop proxy server."""
    formatter = get_formatter()
    console.print(formatter.format_info("Proxy stop command not yet implemented"))


@app.command("status")
def proxy_status():
    """Show proxy server status."""
    formatter = get_formatter()
    console.print(formatter.format_info("Proxy status command not yet implemented"))


@app.command("users")
def proxy_users():
    """Manage proxy users."""
    formatter = get_formatter()
    console.print(formatter.format_info("Proxy users command not yet implemented"))