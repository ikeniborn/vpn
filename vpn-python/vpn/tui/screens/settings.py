"""
Settings configuration screen.
"""

from textual.app import ComposeResult
from textual.containers import Container
from textual.widgets import Static

from vpn.tui.screens.base import BaseScreen


class SettingsScreen(BaseScreen):
    """Screen for configuring application settings."""
    
    DEFAULT_CSS = """
    SettingsScreen {
        background: $surface;
    }
    """
    
    def compose(self) -> ComposeResult:
        """Create settings screen layout."""
        yield self.compose_header("Settings", "Configure VPN Manager")
        
        # Placeholder content
        with Container():
            yield Static("Settings screen - Coming soon!", classes="placeholder")