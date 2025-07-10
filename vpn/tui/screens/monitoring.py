"""
Monitoring dashboard screen.
"""

from textual.app import ComposeResult
from textual.containers import Container
from textual.widgets import Static

from vpn.tui.screens.base import BaseScreen


class MonitoringScreen(BaseScreen):
    """Screen for monitoring system metrics."""
    
    DEFAULT_CSS = """
    MonitoringScreen {
        background: $surface;
    }
    """
    
    def compose(self) -> ComposeResult:
        """Create monitoring screen layout."""
        yield from self.compose_header("System Monitoring", "Real-time metrics")
        
        # Placeholder content
        with Container():
            yield Static("Monitoring dashboard - Coming soon!", classes="placeholder")