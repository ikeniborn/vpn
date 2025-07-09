"""
Server status widget showing running VPN servers.
"""

from textual.app import ComposeResult
from textual.containers import Vertical
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import Static, DataTable


class ServerStatusWidget(Widget):
    """Widget showing server status information."""
    
    DEFAULT_CSS = """
    ServerStatusWidget {
        width: 50%;
        height: 20;
        margin: 1;
        padding: 1;
        background: $panel;
        border: solid $primary-background;
    }
    
    ServerStatusWidget .widget-title {
        text-style: bold;
        margin-bottom: 1;
    }
    """
    
    def compose(self) -> ComposeResult:
        """Create widget layout."""
        with Vertical():
            yield Static("Server Status", classes="widget-title")
            yield DataTable(id="server-status-table")
    
    def on_mount(self) -> None:
        """Setup the table when mounted."""
        table = self.query_one("#server-status-table", DataTable)
        table.add_columns("Server", "Protocol", "Port", "Status", "Uptime")
        
        # Add sample data (replace with real data in production)
        table.add_rows([
            ["vpn-server-1", "VLESS", "8443", "🟢 Running", "2d 14h"],
            ["outline-server", "Shadowsocks", "8388", "🟢 Running", "5d 3h"],
            ["wireguard-1", "WireGuard", "51820", "🔴 Stopped", "-"],
        ])