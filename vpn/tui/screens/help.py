"""
Help screen showing keyboard shortcuts and usage.
"""

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Vertical
from textual.screen import Screen
from textual.widgets import Static, DataTable

from vpn.tui.screens.base import BaseScreen


class HelpScreen(BaseScreen):
    """Help screen with keyboard shortcuts and usage information."""
    
    DEFAULT_CSS = """
    HelpScreen {
        background: $surface;
    }
    
    HelpScreen .help-section {
        margin: 1;
        padding: 1;
        background: $panel;
        border: solid $primary-background;
    }
    
    HelpScreen .help-title {
        text-style: bold;
        color: $primary;
        margin-bottom: 1;
    }
    """
    
    BINDINGS = [
        Binding("escape", "app.pop_screen", "Close"),
        Binding("q", "app.pop_screen", "Close"),
    ]
    
    def compose(self) -> ComposeResult:
        """Create help screen layout."""
        yield from self.compose_header("Help", "Keyboard shortcuts and usage")
        
        with Container():
            # Global shortcuts
            with Vertical(classes="help-section"):
                yield Static("Global Shortcuts", classes="help-title")
                shortcuts_table = DataTable(show_header=False)
                yield shortcuts_table
            
            # Navigation
            with Vertical(classes="help-section"):
                yield Static("Navigation", classes="help-title")
                yield Static("• Use D, U, S, M keys to switch between screens")
                yield Static("• Press ESC to go back")
                yield Static("• Use Tab to move between elements")
    
    def on_mount(self) -> None:
        """Setup help content."""
        # Add global shortcuts
        table = self.query_one(DataTable)
        table.add_columns("Key", "Action")
        
        shortcuts = [
            ("D", "Dashboard"),
            ("U", "Users Management"),
            ("S", "Server Management"),
            ("M", "Monitoring"),
            ("Ctrl+S", "Settings"),
            ("?", "Help"),
            ("T", "Toggle Theme"),
            ("Q", "Quit"),
            ("Ctrl+C", "Force Quit"),
        ]
        
        for key, action in shortcuts:
            table.add_row(f"[bold]{key}[/bold]", action)