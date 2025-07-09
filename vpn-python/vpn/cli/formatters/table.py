"""
Table formatter for rich terminal tables.
"""

from typing import Any, Dict, List, Optional

from rich.console import Console
from rich.table import Table

from .base import OutputFormatter


class TableFormatter(OutputFormatter):
    """Format output as rich terminal tables."""
    
    def __init__(self, no_color: bool = False):
        """Initialize table formatter."""
        super().__init__(no_color)
        self.console = Console(no_color=no_color)
    
    def format_single(
        self,
        data: Dict[str, Any],
        title: Optional[str] = None,
        **kwargs
    ) -> str:
        """Format a single item as a key-value table."""
        table = Table(title=title, show_header=False)
        table.add_column("Field", style="cyan", no_wrap=True)
        table.add_column("Value")
        
        for key, value in data.items():
            # Convert key from snake_case to Title Case
            display_key = key.replace("_", " ").title()
            
            # Format value
            if isinstance(value, bool):
                display_value = "✓ Yes" if value else "✗ No"
                style = "green" if value else "red"
                table.add_row(display_key, f"[{style}]{display_value}[/{style}]")
            elif isinstance(value, (list, dict)):
                display_value = str(value)
                table.add_row(display_key, display_value)
            elif value is None:
                table.add_row(display_key, "[dim]Not set[/dim]")
            else:
                table.add_row(display_key, str(value))
        
        # Capture output as string
        from io import StringIO
        buffer = StringIO()
        temp_console = Console(file=buffer, no_color=self.no_color)
        temp_console.print(table)
        return buffer.getvalue()
    
    def format_list(
        self,
        data: List[Dict[str, Any]],
        columns: Optional[List[str]] = None,
        title: Optional[str] = None,
        **kwargs
    ) -> str:
        """Format a list of items as a table."""
        if not data:
            return "No data to display"
        
        # Determine columns
        if not columns:
            columns = list(data[0].keys()) if data else []
        
        # Create table
        table = Table(title=title, show_header=True, header_style="bold magenta")
        
        # Add columns
        for col in columns:
            # Special formatting for certain columns
            if col in ["status", "state"]:
                table.add_column(col.title(), justify="center")
            elif col in ["port", "id", "cpu", "memory"]:
                table.add_column(col.title(), justify="right")
            else:
                table.add_column(col.replace("_", " ").title())
        
        # Add rows
        for item in data:
            row = []
            for col in columns:
                value = item.get(col, "")
                
                # Format special values
                if col == "status":
                    if value == "active":
                        row.append("[green]● Active[/green]")
                    elif value == "inactive":
                        row.append("[yellow]● Inactive[/yellow]")
                    elif value == "suspended":
                        row.append("[red]● Suspended[/red]")
                    else:
                        row.append(str(value))
                elif col == "traffic":
                    if isinstance(value, dict):
                        total_mb = value.get("total_mb", 0)
                        row.append(f"{total_mb:.2f} MB")
                    else:
                        row.append(str(value))
                elif isinstance(value, bool):
                    row.append("[green]✓[/green]" if value else "[red]✗[/red]")
                elif value is None:
                    row.append("[dim]-[/dim]")
                else:
                    row.append(str(value))
            
            table.add_row(*row)
        
        # Capture output as string
        from io import StringIO
        buffer = StringIO()
        temp_console = Console(file=buffer, no_color=self.no_color)
        temp_console.print(table)
        return buffer.getvalue()
    
    def format_error(self, error: str, details: Optional[Dict] = None) -> str:
        """Format error with rich styling."""
        output = f"[red]✗ Error:[/red] {error}"
        if details:
            output += "\n[yellow]Details:[/yellow]"
            for key, value in details.items():
                output += f"\n  • {key}: {value}"
        
        from io import StringIO
        buffer = StringIO()
        temp_console = Console(file=buffer, no_color=self.no_color)
        temp_console.print(output)
        return buffer.getvalue()
    
    def format_success(self, message: str) -> str:
        """Format success with rich styling."""
        from io import StringIO
        buffer = StringIO()
        temp_console = Console(file=buffer, no_color=self.no_color)
        temp_console.print(f"[green]✓[/green] {message}")
        return buffer.getvalue()
    
    def format_warning(self, message: str) -> str:
        """Format warning with rich styling."""
        from io import StringIO
        buffer = StringIO()
        temp_console = Console(file=buffer, no_color=self.no_color)
        temp_console.print(f"[yellow]⚠[/yellow] {message}")
        return buffer.getvalue()
    
    def format_info(self, message: str) -> str:
        """Format info with rich styling."""
        from io import StringIO
        buffer = StringIO()
        temp_console = Console(file=buffer, no_color=self.no_color)
        temp_console.print(f"[blue]ℹ[/blue] {message}")
        return buffer.getvalue()