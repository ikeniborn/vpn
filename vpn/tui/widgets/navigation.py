"""
Navigation sidebar widget.
"""

from textual import on
from textual.app import ComposeResult
from textual.containers import Vertical
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import Button, Static


class NavigationItem(Button):
    """Individual navigation item."""
    
    def __init__(
        self,
        label: str,
        screen_name: str,
        icon: str = "",
        **kwargs
    ):
        """Initialize navigation item."""
        super().__init__(f"{icon} {label}" if icon else label, **kwargs)
        self.screen_name = screen_name
        self.add_class("nav-item")


class NavigationSidebar(Widget):
    """Navigation sidebar for switching between screens."""
    
    DEFAULT_CSS = """
    NavigationSidebar {
        dock: left;
    }
    """
    
    current_screen = reactive("dashboard")
    
    def compose(self) -> ComposeResult:
        """Create navigation items."""
        with Vertical():
            yield Static("VPN Manager", classes="sidebar-title")
            yield NavigationItem("📊 Dashboard", "dashboard", id="nav-dashboard")
            yield NavigationItem("👥 Users", "users", id="nav-users")
            yield NavigationItem("🖥️  Servers", "servers", id="nav-servers")
            yield NavigationItem("📈 Monitoring", "monitoring", id="nav-monitoring")
            yield NavigationItem("⚙️  Settings", "settings", id="nav-settings")
    
    def on_mount(self) -> None:
        """Called when widget is mounted."""
        self.update_active_item()
    
    def watch_current_screen(self, screen_name: str) -> None:
        """Watch for screen changes."""
        self.update_active_item()
    
    def update_active_item(self) -> None:
        """Update active navigation item."""
        for item in self.query(NavigationItem):
            item.remove_class("active")
            if item.screen_name == self.current_screen:
                item.add_class("active")
    
    @on(NavigationItem.Pressed)
    def handle_nav_click(self, event: NavigationItem.Pressed) -> None:
        """Handle navigation item click."""
        nav_item = event.button
        if isinstance(nav_item, NavigationItem):
            self.current_screen = nav_item.screen_name
            self.app.action_push_screen(nav_item.screen_name)