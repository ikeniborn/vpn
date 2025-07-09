"""
Server status widget with context menu support for server management.
"""

from typing import List, Optional

from textual import on
from textual.app import ComposeResult
from textual.containers import Vertical
from textual.coordinate import Coordinate
from textual.message import Message
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import DataTable, Static

from vpn.tui.widgets.context_menu import ContextMenuItem, ContextMenuMixin
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ServerStatus(Widget, ContextMenuMixin):
    """Widget showing server status information with context menu support."""
    
    DEFAULT_CSS = """
    ServerStatus {
        width: 100%;
        height: 100%;
        border: solid $primary;
    }
    
    ServerStatus .header {
        height: 3;
        background: $primary;
        color: $text-on-primary;
        padding: 1;
        dock: top;
    }
    
    ServerStatus .server-table {
        height: 1fr;
    }
    
    ServerStatus .footer {
        height: 3;
        background: $surface;
        color: $text-muted;
        padding: 1;
        dock: bottom;
    }
    """
    
    selected_server: reactive[Optional[str]] = reactive(None)
    
    class ServerAction(Message):
        """Message sent when a server action is triggered."""
        
        def __init__(self, action: str, server_name: str) -> None:
            self.action = action
            self.server_name = server_name
            super().__init__()
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.servers_data = []
    
    def compose(self) -> ComposeResult:
        """Create widget layout."""
        with Vertical():
            # Header
            yield Static("🖥️ Server Status", classes="header")
            
            # Server table
            table = DataTable(id="server_table", cursor_type="row", classes="server-table")
            table.add_columns("Server", "Protocol", "Port", "Status", "Uptime", "CPU", "Memory")
            yield table
            
            # Footer
            yield Static("Right-click for server actions • F10 for keyboard menu", classes="footer")
    
    def on_mount(self) -> None:
        """Setup the table when mounted."""
        self.refresh_servers()
        
        # Set up context menu
        self.set_context_menu_items(self._create_server_context_menu())
    
    def refresh_servers(self) -> None:
        """Refresh server data and update table."""
        # Sample data - replace with real data from server manager
        self.servers_data = [
            {
                "name": "vpn-server-1",
                "protocol": "VLESS",
                "port": "8443",
                "status": "running",
                "uptime": "2d 14h",
                "cpu": "15%",
                "memory": "128MB"
            },
            {
                "name": "outline-server",
                "protocol": "Shadowsocks",
                "port": "8388",
                "status": "running",
                "uptime": "5d 3h",
                "cpu": "8%",
                "memory": "64MB"
            },
            {
                "name": "wireguard-1",
                "protocol": "WireGuard",
                "port": "51820",
                "status": "stopped",
                "uptime": "-",
                "cpu": "0%",
                "memory": "0MB"
            },
            {
                "name": "proxy-server",
                "protocol": "HTTP/SOCKS5",
                "port": "8080",
                "status": "running",
                "uptime": "12h",
                "cpu": "5%",
                "memory": "32MB"
            }
        ]
        
        self._update_table()
    
    def _update_table(self) -> None:
        """Update the data table with server information."""
        try:
            table = self.query_one("#server_table", DataTable)
            table.clear()
            
            for server in self.servers_data:
                # Format status with color and icon
                status_text = server["status"].title()
                if server["status"] == "running":
                    status_text = f"🟢 {status_text}"
                elif server["status"] == "stopped":
                    status_text = f"🔴 {status_text}"
                elif server["status"] == "error":
                    status_text = f"🟡 {status_text}"
                
                # Format CPU and memory with colors
                cpu_usage = server["cpu"]
                if "%" in cpu_usage:
                    cpu_val = int(cpu_usage.replace("%", ""))
                    if cpu_val > 80:
                        cpu_usage = f"[red]{cpu_usage}[/red]"
                    elif cpu_val > 50:
                        cpu_usage = f"[yellow]{cpu_usage}[/yellow]"
                    else:
                        cpu_usage = f"[green]{cpu_usage}[/green]"
                
                table.add_row(
                    server["name"],
                    server["protocol"],
                    server["port"],
                    status_text,
                    server["uptime"],
                    cpu_usage,
                    server["memory"],
                    key=server["name"]
                )
        except Exception as e:
            logger.error(f"Failed to update server table: {e}")
    
    @on(DataTable.RowSelected)
    def on_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection in the data table."""
        if event.row_key:
            self.selected_server = event.row_key.value
    
    def on_click(self, event) -> None:
        """Handle click events for context menu."""
        if hasattr(event, 'button') and event.button == 3:  # Right click
            if self.selected_server:
                # Create context menu for selected server
                self.set_context_menu_items(self._create_server_context_menu())
                self.show_context_menu(Coordinate(event.x, event.y))
                event.prevent_default()
        else:
            # Hide context menu on left click
            self.hide_context_menu()
    
    def on_key(self, event) -> None:
        """Handle keyboard events."""
        if event.key == "f10" or (event.key == "f" and event.shift):
            # Show context menu with keyboard
            if self.selected_server:
                self.set_context_menu_items(self._create_server_context_menu())
                self.show_context_menu()
                event.prevent_default()
        elif event.key == "f5":
            # Refresh servers
            self.refresh_servers()
            event.prevent_default()
        elif event.key == "s" and self.selected_server:
            # Start/stop server
            server_info = self._get_server_info(self.selected_server)
            if server_info:
                if server_info["status"] == "running":
                    self._handle_server_action("stop", self.selected_server)
                else:
                    self._handle_server_action("start", self.selected_server)
            event.prevent_default()
        elif event.key == "r" and self.selected_server:
            # Restart server
            self._handle_server_action("restart", self.selected_server)
            event.prevent_default()
        elif event.key == "l" and self.selected_server:
            # View logs
            self._handle_server_action("logs", self.selected_server)
            event.prevent_default()
        
        # Call parent handler
        super().on_key(event)
    
    def _get_server_info(self, server_name: str) -> Optional[dict]:
        """Get server information by name."""
        return next((s for s in self.servers_data if s["name"] == server_name), None)
    
    def _create_server_context_menu(self) -> List[ContextMenuItem]:
        """Create context menu items for server management."""
        if not self.selected_server:
            return []
        
        server_info = self._get_server_info(self.selected_server)
        if not server_info:
            return []
        
        is_running = server_info["status"] == "running"
        
        return [
            ContextMenuItem(
                "Stop Server" if is_running else "Start Server",
                action=lambda: self._handle_server_action("stop" if is_running else "start", self.selected_server),
                shortcut="S"
            ),
            ContextMenuItem(
                "Restart Server",
                action=lambda: self._handle_server_action("restart", self.selected_server),
                shortcut="R",
                enabled=is_running
            ),
            ContextMenuItem("", separator=True),
            ContextMenuItem(
                "View Logs",
                action=lambda: self._handle_server_action("logs", self.selected_server),
                shortcut="L"
            ),
            ContextMenuItem(
                "Edit Configuration",
                action=lambda: self._handle_server_action("config", self.selected_server),
                shortcut="F4"
            ),
            ContextMenuItem("", separator=True),
            ContextMenuItem(
                "Server Statistics",
                action=lambda: self._handle_server_action("stats", self.selected_server),
                shortcut="T"
            ),
            ContextMenuItem(
                "Connection Info",
                action=lambda: self._handle_server_action("info", self.selected_server),
                shortcut="I"
            ),
            ContextMenuItem("", separator=True),
            ContextMenuItem(
                "Export Configuration",
                action=lambda: self._handle_server_action("export", self.selected_server),
                shortcut="E"
            ),
            ContextMenuItem(
                "Backup Server Data",
                action=lambda: self._handle_server_action("backup", self.selected_server),
                shortcut="B"
            ),
            ContextMenuItem("", separator=True),
            ContextMenuItem(
                "Remove Server",
                action=lambda: self._handle_server_action("remove", self.selected_server),
                shortcut="Del",
                enabled=not is_running
            ),
        ]
    
    def _handle_server_action(self, action: str, server_name: str) -> None:
        """Handle server action from context menu."""
        try:
            # Update server status for immediate feedback
            if action == "start":
                self._update_server_status(server_name, "running")
            elif action == "stop":
                self._update_server_status(server_name, "stopped")
            elif action == "restart":
                # Temporarily show stopping, then running
                self._update_server_status(server_name, "stopped")
                # In a real implementation, you would wait for restart
                self._update_server_status(server_name, "running")
            
            # Post message for parent to handle
            self.post_message(self.ServerAction(action, server_name))
            
        except Exception as e:
            logger.error(f"Failed to handle server action {action}: {e}")
    
    def _update_server_status(self, server_name: str, new_status: str) -> None:
        """Update server status in the data."""
        for server in self.servers_data:
            if server["name"] == server_name:
                server["status"] = new_status
                if new_status == "running":
                    server["uptime"] = "0m"
                    server["cpu"] = "5%"
                    server["memory"] = "64MB"
                else:
                    server["uptime"] = "-"
                    server["cpu"] = "0%"
                    server["memory"] = "0MB"
                break
        
        self._update_table()
    
    def get_selected_server(self) -> Optional[str]:
        """Get the currently selected server."""
        return self.selected_server
    
    def get_server_count(self) -> int:
        """Get the total number of servers."""
        return len(self.servers_data)
    
    def get_running_servers(self) -> List[dict]:
        """Get list of running servers."""
        return [s for s in self.servers_data if s["status"] == "running"]


# Alias for backward compatibility
ServerStatusWidget = ServerStatus