"""Main Textual application for VPN Manager TUI.
"""


from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Footer, Header

from vpn.tui.screens.dashboard import DashboardScreen
from vpn.tui.screens.main_menu import MainMenuScreen
from vpn.tui.screens.monitoring import MonitoringScreen
from vpn.tui.screens.servers import ServersScreen
from vpn.tui.screens.settings import SettingsScreen
from vpn.tui.screens.users import UsersScreen
from vpn.tui.widgets.navigation import NavigationSidebar


class VPNManagerApp(App):
    """Main VPN Manager TUI application."""

    CSS_PATH = "styles.css"
    TITLE = "VPN Manager"
    SUB_TITLE = "Terminal User Interface"

    BINDINGS = [
        Binding("h", "push_screen('main_menu')", "Home", priority=True),
        Binding("d", "push_screen('dashboard')", "Dashboard", priority=True),
        Binding("u", "push_screen('users')", "Users", priority=True),
        Binding("s", "push_screen('servers')", "Servers", priority=True),
        Binding("m", "push_screen('monitoring')", "Monitoring", priority=True),
        Binding("ctrl+s", "push_screen('settings')", "Settings"),
        Binding("q", "quit", "Quit"),
        Binding("ctrl+c", "quit", "Quit", show=False),
        Binding("?", "help", "Help"),
        Binding("t", "toggle_theme", "Theme"),
    ]

    SCREENS = {
        "main_menu": MainMenuScreen,
        "dashboard": DashboardScreen,
        "users": UsersScreen,
        "servers": ServersScreen,
        "monitoring": MonitoringScreen,
        "settings": SettingsScreen,
    }

    def __init__(self):
        """Initialize the application."""
        super().__init__()

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        yield NavigationSidebar()
        yield Footer()

    def on_mount(self) -> None:
        """Called when app starts."""
        # Push the main menu screen by default
        self.push_screen("main_menu")

    def action_push_screen(self, screen: str) -> None:
        """Push a screen onto the screen stack."""
        if screen in self.SCREENS:
            self.push_screen(self.SCREENS[screen]())

    def action_toggle_theme(self) -> None:
        """Toggle between dark and light themes."""
        self.dark = not self.dark
        theme_name = "dark" if self.dark else "light"
        self.notify(f"Switched to {theme_name} theme")

    def action_help(self) -> None:
        """Show help screen."""
        from vpn.tui.screens.help import HelpScreen
        self.push_screen(HelpScreen())


def run_tui() -> None:
    """Run the TUI application."""
    app = VPNManagerApp()
    app.run()


if __name__ == "__main__":
    run_tui()
