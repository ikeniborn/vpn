"""Main menu screen with interactive options for VPN management."""

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Grid, Vertical
from textual.widgets import Button, Static

from vpn.tui.screens.base import BaseScreen


class MainMenuScreen(BaseScreen):
    """Main menu screen with all VPN management options."""

    DEFAULT_CSS = """
    MainMenuScreen {
        background: $surface;
    }
    
    .menu-title {
        text-align: center;
        text-style: bold;
        color: $primary;
        margin: 2 0;
        padding: 1;
    }
    
    .menu-container {
        align: center middle;
        width: 60;
        height: auto;
        margin: 2;
    }
    
    .menu-button {
        width: 100%;
        margin: 1 0;
        height: 3;
    }
    
    .menu-section-title {
        text-align: center;
        text-style: bold;
        color: $accent;
        margin: 1 0;
    }
    
    .menu-description {
        text-align: center;
        color: $text-muted;
        margin: 0 0 2 0;
    }
    """

    BINDINGS = [
        Binding("1", "install_server", "Install VPN Server"),
        Binding("2", "manage_servers", "Manage Servers"),
        Binding("3", "manage_users", "Manage Users"),
        Binding("4", "monitoring", "Monitoring"),
        Binding("5", "settings", "Settings"),
        Binding("q", "quit", "Quit"),
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def compose(self) -> ComposeResult:
        """Create main menu layout."""
        yield Static("🔐 VPN Manager", classes="menu-title")
        yield Static("Complete VPN Management System", classes="menu-description")
        
        with Container(classes="menu-container"):
            with Vertical():
                # Installation section
                yield Static("📦 Installation", classes="menu-section-title")
                yield Button(
                    "1. Install VPN Server",
                    id="install-server",
                    variant="primary",
                    classes="menu-button"
                )
                
                # Management section
                yield Static("🛠️ Management", classes="menu-section-title")
                yield Button(
                    "2. Manage VPN Servers",
                    id="manage-servers",
                    variant="default",
                    classes="menu-button"
                )
                yield Button(
                    "3. Manage Users",
                    id="manage-users",
                    variant="default",
                    classes="menu-button"
                )
                
                # Monitoring section
                yield Static("📊 Monitoring", classes="menu-section-title")
                yield Button(
                    "4. System Monitoring",
                    id="monitoring",
                    variant="default",
                    classes="menu-button"
                )
                
                # Settings section
                yield Static("⚙️ Configuration", classes="menu-section-title")
                yield Button(
                    "5. Settings",
                    id="settings",
                    variant="default",
                    classes="menu-button"
                )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        button_id = event.button.id
        
        if button_id == "install-server":
            self.action_install_server()
        elif button_id == "manage-servers":
            self.action_manage_servers()
        elif button_id == "manage-users":
            self.action_manage_users()
        elif button_id == "monitoring":
            self.action_monitoring()
        elif button_id == "settings":
            self.action_settings()

    def action_install_server(self) -> None:
        """Open VPN server installation screen."""
        from vpn.tui.screens.install_server import InstallServerScreen
        self.app.push_screen(InstallServerScreen())

    def action_manage_servers(self) -> None:
        """Open server management screen."""
        from vpn.tui.screens.servers import ServersScreen
        self.app.push_screen(ServersScreen())

    def action_manage_users(self) -> None:
        """Open user management screen."""
        from vpn.tui.screens.users import UsersScreen
        self.app.push_screen(UsersScreen())

    def action_monitoring(self) -> None:
        """Open monitoring screen."""
        from vpn.tui.screens.monitoring import MonitoringScreen
        self.app.push_screen(MonitoringScreen())

    def action_settings(self) -> None:
        """Open settings screen."""
        from vpn.tui.screens.settings import SettingsScreen
        self.app.push_screen(SettingsScreen())