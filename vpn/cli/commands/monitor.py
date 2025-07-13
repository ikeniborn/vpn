"""Monitoring and statistics CLI commands.
"""

import typer
from rich.console import Console

from vpn.cli.formatters.base import get_formatter

app = typer.Typer(help="Monitoring and statistics commands")
console = Console()


@app.command("traffic")
def show_traffic():
    """Show traffic statistics."""
    formatter = get_formatter()
    console.print(formatter.format_info("Traffic monitoring not yet implemented"))


@app.command("health")
def show_health():
    """Show system health status."""
    formatter = get_formatter()
    console.print(formatter.format_info("Health monitoring not yet implemented"))


@app.command("alerts")
def show_alerts():
    """Show system alerts."""
    formatter = get_formatter()
    console.print(formatter.format_info("Alert monitoring not yet implemented"))
