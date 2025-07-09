"""
User details widget for displaying detailed user information.
"""

from typing import Optional

from textual.app import ComposeResult
from textual.containers import Vertical
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import Static, Button, Label

from vpn.core.models import User


class UserDetailsWidget(Widget):
    """Widget showing detailed user information."""
    
    DEFAULT_CSS = """
    UserDetailsWidget {
        width: 40;
        margin: 1;
        padding: 1;
        background: $panel;
        border: solid $primary-background;
    }
    
    UserDetailsWidget .detail-title {
        text-style: bold;
        color: $primary;
        margin-bottom: 1;
    }
    
    UserDetailsWidget .detail-row {
        height: 2;
        margin-bottom: 1;
    }
    
    UserDetailsWidget .detail-label {
        text-style: bold;
        color: $text-muted;
    }
    
    UserDetailsWidget .detail-value {
        color: $text;
    }
    
    UserDetailsWidget .no-selection {
        text-align: center;
        color: $text-muted;
        margin-top: 5;
    }
    """
    
    user = reactive[Optional[User]](None)
    
    def compose(self) -> ComposeResult:
        """Create widget layout."""
        yield Vertical(id="details-container")
    
    def watch_user(self, user: Optional[User]) -> None:
        """Update display when user changes."""
        container = self.query_one("#details-container", Vertical)
        container.remove_children()
        
        if user is None:
            container.mount(
                Static("Select a user to view details", classes="no-selection")
            )
            return
        
        # Title
        container.mount(Static(f"User: {user.username}", classes="detail-title"))
        
        # User details
        details = [
            ("ID", str(user.id)),
            ("Email", user.email or "Not set"),
            ("Status", user.status.title()),
            ("Protocol", user.protocol.type.value),
            ("Created", user.created_at.strftime("%Y-%m-%d %H:%M")),
            ("Updated", user.updated_at.strftime("%Y-%m-%d %H:%M") if user.updated_at else "Never"),
        ]
        
        for label, value in details:
            with container:
                row = Vertical(classes="detail-row")
                row.mount(Static(label, classes="detail-label"))
                row.mount(Static(value, classes="detail-value"))
        
        # Traffic stats
        container.mount(Static("Traffic Statistics", classes="detail-title"))
        
        traffic_stats = [
            ("Upload", self._format_bytes(user.traffic.upload_bytes)),
            ("Download", self._format_bytes(user.traffic.download_bytes)),
            ("Total", self._format_bytes(user.traffic.total_bytes)),
            ("Last Active", user.traffic.last_activity.strftime("%Y-%m-%d %H:%M") if user.traffic.last_activity else "Never"),
        ]
        
        for label, value in traffic_stats:
            with container:
                row = Vertical(classes="detail-row")
                row.mount(Static(label, classes="detail-label"))
                row.mount(Static(value, classes="detail-value"))
        
        # Actions
        container.mount(Static("Actions", classes="detail-title"))
        with container:
            actions = Vertical()
            actions.mount(Button("📋 Copy Connection", id="copy-connection"))
            actions.mount(Button("📊 View QR Code", id="show-qr"))
            actions.mount(Button("🔄 Reset Traffic", id="reset-traffic"))
    
    def _format_bytes(self, bytes: int) -> str:
        """Format bytes to human readable."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes < 1024.0:
                return f"{bytes:.2f} {unit}"
            bytes /= 1024.0
        return f"{bytes:.2f} PB"