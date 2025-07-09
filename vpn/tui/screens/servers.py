"""
Server management screen.
"""

from textual.app import ComposeResult
from textual.containers import Container
from textual.widgets import Static, DataTable

from vpn.tui.screens.base import BaseScreen


class ServersScreen(BaseScreen):
    """Screen for managing VPN servers."""
    
    DEFAULT_CSS = """
    ServersScreen {
        background: $surface;
    }
    """
    
    def compose(self) -> ComposeResult:
        """Create servers screen layout."""
        yield self.compose_header("Server Management", "Manage VPN servers")
        
        # Placeholder content
        with Container():
            yield Static("Server management screen - Coming soon!", classes="placeholder")
            yield DataTable(id="servers-table")