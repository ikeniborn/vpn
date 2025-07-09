"""
Traffic chart widget for displaying bandwidth usage.
"""

from textual.app import ComposeResult
from textual.containers import Vertical
from textual.widget import Widget
from textual.widgets import Static, ProgressBar


class TrafficChart(Widget):
    """Widget showing traffic statistics as a chart."""
    
    DEFAULT_CSS = """
    TrafficChart {
        width: 50%;
        height: 20;
        margin: 1;
        padding: 1;
        background: $panel;
        border: solid $primary-background;
    }
    
    TrafficChart .widget-title {
        text-style: bold;
        margin-bottom: 1;
    }
    
    TrafficChart .traffic-row {
        height: 3;
        margin-bottom: 1;
    }
    
    TrafficChart .traffic-label {
        width: 20;
    }
    """
    
    def compose(self) -> ComposeResult:
        """Create widget layout."""
        with Vertical():
            yield Static("Network Traffic (Last 24h)", classes="widget-title")
            
            # Upload traffic
            with Vertical(classes="traffic-row"):
                yield Static("Upload:", classes="traffic-label")
                yield ProgressBar(total=100, show_eta=False, id="upload-bar")
                yield Static("245.3 MB", classes="traffic-value")
            
            # Download traffic
            with Vertical(classes="traffic-row"):
                yield Static("Download:", classes="traffic-label")
                yield ProgressBar(total=100, show_eta=False, id="download-bar")
                yield Static("1.2 GB", classes="traffic-value")
            
            # Total traffic
            with Vertical(classes="traffic-row"):
                yield Static("Total:", classes="traffic-label")
                yield ProgressBar(total=100, show_eta=False, id="total-bar")
                yield Static("1.44 GB", classes="traffic-value")
    
    def on_mount(self) -> None:
        """Set initial progress values."""
        self.query_one("#upload-bar", ProgressBar).progress = 20
        self.query_one("#download-bar", ProgressBar).progress = 75
        self.query_one("#total-bar", ProgressBar).progress = 60