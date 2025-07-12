"""
Dashboard screen showing system overview with better error handling.
"""

import asyncio
from datetime import datetime
from typing import Optional

from textual import on
from textual.app import ComposeResult
from textual.containers import Container, Grid, Horizontal, ScrollableContainer
from textual.css.query import NoMatches
from textual.reactive import reactive
from textual.timer import Timer
from textual.widgets import Button, DataTable, Static

from vpn.tui.screens.base import BaseScreen
from vpn.tui.widgets.stats_card import StatsCard
from vpn.tui.widgets.server_status import ServerStatusWidget
from vpn.tui.widgets.traffic_chart import TrafficChart


class DashboardScreen(BaseScreen):
    """Main dashboard screen with system overview."""
    
    DEFAULT_CSS = """
    DashboardScreen {
        background: $surface;
    }
    
    .dashboard-grid {
        grid-size: 4 1;
        grid-gutter: 1;
        margin: 1;
    }
    
    .recent-activity {
        height: 20;
        margin: 1;
    }
    
    .error-panel {
        background: $error;
        color: $text;
        padding: 1;
        margin: 1;
        border: solid $error;
    }
    """
    
    # Reactive properties for real-time updates
    total_users = reactive(0)
    active_users = reactive(0)
    total_servers = reactive(0)
    total_traffic = reactive("0 MB")
    
    def __init__(self):
        """Initialize dashboard screen."""
        super().__init__()
        self.update_timer: Optional[Timer] = None
        self._init_error: Optional[str] = None
    
    def compose(self) -> ComposeResult:
        """Create dashboard layout."""
        yield from self.compose_header("Dashboard", f"Updated: {datetime.now().strftime('%H:%M:%S')}")
        
        # Stats cards grid
        with Grid(classes="dashboard-grid"):
            yield StatsCard("Total Users", str(self.total_users), "users-card")
            yield StatsCard("Active Users", str(self.active_users), "active-card")
            yield StatsCard("Servers", str(self.total_servers), "servers-card")
            yield StatsCard("Total Traffic", self.total_traffic, "traffic-card")
        
        # Main content area
        with Horizontal(classes="dashboard-main"):
            # Server status widget
            yield ServerStatusWidget()
            
            # Traffic chart
            yield TrafficChart()
        
        # Recent activity
        with Container(classes="recent-activity"):
            yield Static("Recent Activity", classes="section-title")
            yield DataTable(id="activity-table")
    
    def on_mount(self) -> None:
        """Called when screen is mounted."""
        # Setup activity table
        table = self.query_one("#activity-table", DataTable)
        table.add_columns("Time", "Event", "User", "Status")
        
        # Check for initialization errors
        self.call_later(self.check_initialization)
        
        # Start update timer
        self.update_timer = self.set_interval(5, self.update_dashboard)
        
        # Initial update
        self.call_later(self.update_dashboard)
    
    def on_unmount(self) -> None:
        """Called when screen is unmounted."""
        if self.update_timer:
            self.update_timer.stop()
    
    async def check_initialization(self) -> None:
        """Check if services are properly initialized."""
        errors = []
        
        # Check database
        try:
            from vpn.core.database import engine
            async with engine.connect() as conn:
                await conn.execute("SELECT 1")
        except Exception as e:
            errors.append(f"Database not initialized: {e}")
        
        # Check Docker
        try:
            await self.docker_manager.client.ping()
        except Exception as e:
            errors.append(f"Docker not accessible: {e}")
        
        if errors:
            self._init_error = "\n".join(errors)
            self.show_initialization_errors()
    
    def show_initialization_errors(self) -> None:
        """Show initialization errors in the UI."""
        if self._init_error:
            # Create error panel
            error_msg = f"""
[bold red]Initialization Errors[/bold red]

{self._init_error}

[yellow]Suggestions:[/yellow]
1. Run: python scripts/init-database.py
2. Ensure Docker is running and accessible
3. Check logs: tail -f ~/.local/share/vpn-manager/logs/*.log
"""
            self.show_error(error_msg)
    
    async def update_dashboard(self) -> None:
        """Update dashboard data with better error handling."""
        # Update user stats
        try:
            users = await self.user_manager.list()
            self.total_users = len(users)
            self.active_users = sum(1 for u in users if u.status == "active")
        except Exception as e:
            self.log.debug(f"Failed to update user stats: {e}")
            # Keep previous values or defaults
        
        # Update server stats
        try:
            containers = await self.docker_manager.list_containers()
            vpn_servers = [c for c in containers if any(
                label.startswith("vpn.") for label in c.get("labels", {})
            )]
            self.total_servers = len(vpn_servers)
        except Exception as e:
            self.log.debug(f"Failed to update server stats: {e}")
            # Keep previous values or defaults
        
        # Update traffic stats
        try:
            users = await self.user_manager.list()
            total_bytes = sum(
                u.traffic.total_bytes for u in users 
                if hasattr(u, 'traffic') and u.traffic
            )
            self.total_traffic = self._format_bytes(total_bytes)
        except Exception as e:
            self.log.debug(f"Failed to update traffic stats: {e}")
            # Keep previous values or defaults
        
        # Update header time
        try:
            header = self.query_one(".screen-subtitle", Static)
            if header:
                header.update(f"Updated: {datetime.now().strftime('%H:%M:%S')}")
        except NoMatches:
            pass
    
    def _format_bytes(self, bytes: int) -> str:
        """Format bytes to human readable."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes < 1024.0:
                return f"{bytes:.2f} {unit}"
            bytes /= 1024.0
        return f"{bytes:.2f} PB"
    
    def watch_total_users(self, value: int) -> None:
        """Watch total users changes."""
        try:
            card = self.query_one("#users-card", StatsCard)
            card.value = str(value)
        except NoMatches:
            pass  # Widget not mounted yet
    
    def watch_active_users(self, value: int) -> None:
        """Watch active users changes."""
        try:
            card = self.query_one("#active-card", StatsCard)
            card.value = str(value)
        except NoMatches:
            pass  # Widget not mounted yet
    
    def watch_total_servers(self, value: int) -> None:
        """Watch total servers changes."""
        try:
            card = self.query_one("#servers-card", StatsCard)
            card.value = str(value)
        except NoMatches:
            pass  # Widget not mounted yet
    
    def watch_total_traffic(self, value: str) -> None:
        """Watch total traffic changes."""
        try:
            card = self.query_one("#traffic-card", StatsCard)
            card.value = value
        except NoMatches:
            pass  # Widget not mounted yet