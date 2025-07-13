"""Enhanced VPN Manager TUI application with Textual 0.47+ optimizations.

This module demonstrates the integration of all optimization components:
- Lazy loading for heavy screens
- Advanced keyboard shortcuts
- Reusable component library
- Proper focus management
- Theme customization system
"""

from pathlib import Path
from typing import Any

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Footer, Header

# Import our optimization components
from vpn.tui.components import (
    FocusConfig,
    FocusGroup,
    # Focus management
    InfoCard,
    # Lazy loading
    LazyScreen,
    ShortcutContext,
    ShortcutCustomizationScreen,
    ShortcutHelpScreen,
    # Keyboard shortcuts
    StatusIndicator,
    StatusType,
    ThemeCustomizationScreen,
    # Theme system
    Toast,
    create_loading_config,
    initialize_focus_manager,
    initialize_shortcuts,
    initialize_theme_manager,
)

# Import existing screens (we'll enhance them)
from vpn.tui.screens.monitoring import MonitoringScreen
from vpn.tui.screens.servers import ServersScreen
from vpn.tui.screens.settings import SettingsScreen
from vpn.tui.screens.users import UsersScreen
from vpn.tui.widgets.navigation import NavigationSidebar


class EnhancedDashboardScreen(LazyScreen):
    """Enhanced dashboard with lazy loading."""

    def __init__(self):
        """Initialize enhanced dashboard."""
        loading_config = create_loading_config(
            auto_load=True,
            show_spinner=True,
            loading_message="Loading dashboard data...",
            timeout_seconds=10
        )
        super().__init__(loading_config=loading_config)

        # Add lazy sections
        self.add_lazy_section(
            "stats_section",
            DashboardStatsSection,
            loading_config=create_loading_config(
                auto_load=True,
                debounce_ms=500,
                cache_duration=30
            )
        )

        self.add_lazy_section(
            "activity_section",
            DashboardActivitySection,
            loading_config=create_loading_config(
                auto_load=False,  # Load on demand
                show_progress=True
            )
        )


class DashboardStatsSection(LazyLoadableWidget):
    """Lazy-loaded stats section for dashboard."""

    async def load_data(self) -> dict[str, Any]:
        """Load dashboard statistics."""
        # Simulate async data loading
        import asyncio
        await asyncio.sleep(1)  # Simulate API call

        return {
            "total_users": 145,
            "active_users": 98,
            "total_servers": 12,
            "total_traffic": "2.4 TB"
        }

    def render_content(self, data: dict[str, Any]) -> ComposeResult:
        """Render the stats content."""
        from textual.containers import Grid

        with Grid(classes="stats-grid"):
            yield InfoCard("Total Users", str(data["total_users"]))
            yield InfoCard("Active Users", str(data["active_users"]))
            yield InfoCard("Total Servers", str(data["total_servers"]))
            yield InfoCard("Total Traffic", data["total_traffic"])


class DashboardActivitySection(LazyLoadableWidget):
    """Lazy-loaded activity section for dashboard."""

    async def load_data(self) -> List[dict[str, str]]:
        """Load recent activity data."""
        # Simulate async data loading
        import asyncio
        await asyncio.sleep(2)  # Simulate longer API call

        return [
            {"time": "14:32", "event": "User login", "user": "john_doe", "status": "success"},
            {"time": "14:28", "event": "Server started", "user": "admin", "status": "success"},
            {"time": "14:25", "event": "Configuration updated", "user": "admin", "status": "warning"},
            {"time": "14:20", "event": "User created", "user": "admin", "status": "success"},
        ]

    def render_content(self, data: List[dict[str, str]]) -> ComposeResult:
        """Render the activity content."""
        from textual.containers import Container
        from textual.widgets import DataTable

        with Container(classes="activity-container"):
            yield Static("Recent Activity", classes="section-title")

            table = DataTable(id="activity-table")
            table.add_columns("Time", "Event", "User", "Status")

            for activity in data:
                status_indicator = StatusIndicator(
                    activity["status"],
                    StatusType.SUCCESS if activity["status"] == "success"
                    else StatusType.WARNING
                )

                table.add_row(
                    activity["time"],
                    activity["event"],
                    activity["user"],
                    status_indicator
                )

            yield table


class EnhancedVPNManagerApp(App):
    """Enhanced VPN Manager application with all optimizations."""

    CSS_PATH = "enhanced_styles.css"
    TITLE = "VPN Manager Pro"
    SUB_TITLE = "Enhanced Terminal User Interface"

    # Enhanced bindings will be managed by ShortcutManager
    BINDINGS = []  # Start empty, will be populated dynamically

    SCREENS = {
        "dashboard": EnhancedDashboardScreen,
        "users": UsersScreen,
        "servers": ServersScreen,
        "monitoring": MonitoringScreen,
        "settings": SettingsScreen,
    }

    def __init__(self, config_dir: Path | None = None):
        """Initialize enhanced application."""
        super().__init__()

        self.config_dir = config_dir or Path.home() / ".config" / "vpn-manager"
        self.config_dir.mkdir(parents=True, exist_ok=True)

        # Initialize managers
        self.shortcut_manager = initialize_shortcuts(self.config_dir / "shortcuts.json")
        self.focus_manager = initialize_focus_manager(self, FocusConfig())
        self.theme_manager = initialize_theme_manager(self.config_dir)

        # Set up theme change callback
        self.theme_manager.add_theme_change_callback(self._on_theme_changed)

        # Current theme tracking
        self._current_theme_name = "Dark Blue"

        # Toast notifications
        self._active_toasts: List[Toast] = []

        # Set up keyboard shortcuts
        self._setup_enhanced_bindings()

        # Set up focus management
        self._setup_focus_management()

    def _setup_enhanced_bindings(self) -> None:
        """Set up enhanced keyboard bindings."""
        # Get global shortcuts
        global_shortcuts = self.shortcut_manager.get_active_shortcuts(ShortcutContext.GLOBAL)

        # Convert to Textual bindings
        for shortcut in global_shortcuts:
            if shortcut.enabled:
                binding = Binding(
                    key=shortcut.key,
                    action=shortcut.action,
                    description=shortcut.description,
                    show=shortcut.show_in_footer,
                    priority=shortcut.priority > 50
                )
                self.BINDINGS.append(binding)

    def _setup_focus_management(self) -> None:
        """Set up focus management."""
        # Create main focus ring
        main_ring = self.focus_manager.create_ring("main")

        # Create groups for different screens
        dashboard_group = FocusGroup("dashboard", config=FocusConfig(wrap_around=True))
        users_group = FocusGroup("users", config=FocusConfig(wrap_around=True))
        servers_group = FocusGroup("servers", config=FocusConfig(wrap_around=True))

        # Add groups to ring
        main_ring.add_group(dashboard_group)
        main_ring.add_group(users_group)
        main_ring.add_group(servers_group)

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        yield NavigationSidebar()
        yield Footer()

    def on_mount(self) -> None:
        """Called when app starts."""
        # Apply initial theme
        initial_theme = self.theme_manager.get_current_theme()
        if initial_theme:
            self._apply_theme(initial_theme)

        # Push the dashboard screen by default
        self.push_screen("dashboard")

        # Show welcome toast
        self.show_toast("Welcome to VPN Manager Pro!", "success", duration=3.0)

    def _on_theme_changed(self, theme) -> None:
        """Handle theme changes."""
        self._apply_theme(theme)
        self.show_toast(f"Theme changed to {theme.metadata.name}", "info")

    def _apply_theme(self, theme) -> None:
        """Apply a theme to the application."""
        # Update app theme properties
        self._current_theme_name = theme.metadata.name

        # Apply color scheme (this would need to be implemented based on Textual's theming system)
        # For Textual 0.47+, this might involve updating CSS variables or design system
        pass

    def action_push_screen(self, screen: str) -> None:
        """Enhanced screen pushing with focus management."""
        if screen in self.SCREENS:
            screen_instance = self.SCREENS[screen]()

            # Set up focus management for the screen
            if hasattr(screen_instance, 'setup_focus'):
                screen_instance.setup_focus(self.focus_manager)

            self.push_screen(screen_instance)

            # Update focus ring for screen
            if screen in self.focus_manager._rings:
                self.focus_manager.switch_to_screen_ring(screen_instance)

    def action_toggle_theme(self) -> None:
        """Enhanced theme toggling with theme manager."""
        current_theme = self.theme_manager.get_current_theme()

        if current_theme and current_theme.metadata.name == "Dark Blue":
            self.theme_manager.set_theme("Light Blue")
        else:
            self.theme_manager.set_theme("Dark Blue")

    def action_show_shortcuts(self) -> None:
        """Show keyboard shortcuts help."""
        self.push_screen(ShortcutHelpScreen(self.shortcut_manager))

    def action_customize_shortcuts(self) -> None:
        """Show shortcut customization screen."""
        self.push_screen(ShortcutCustomizationScreen(self.shortcut_manager))

    def action_customize_theme(self) -> None:
        """Show theme customization screen."""
        self.push_screen(ThemeCustomizationScreen(self.theme_manager))

    def action_refresh_current(self) -> None:
        """Refresh the current screen."""
        current_screen = self.screen
        if hasattr(current_screen, 'reload_all_sections'):
            current_screen.reload_all_sections()
        self.show_toast("Screen refreshed", "info")

    def action_search(self) -> None:
        """Open search/filter dialog."""
        from vpn.tui.components.reusable_widgets import InputDialog

        def handle_search(value: str) -> None:
            if value:
                self.show_toast(f"Searching for: {value}", "info")
                # Implement search logic here

        dialog = InputDialog(
            title="Search",
            prompt="Enter search term:",
            placeholder="Search users, servers, etc."
        )

        def on_input_submitted(event):
            handle_search(event.value)

        dialog.add_class("search-dialog")
        self.push_screen(dialog)

    def action_export(self) -> None:
        """Export current data."""
        self.show_toast("Export functionality coming soon", "info")

    def action_toggle_debug(self) -> None:
        """Toggle debug mode."""
        # Toggle debug mode implementation
        self.show_toast("Debug mode toggled", "warning")

    def action_show_logs(self) -> None:
        """Show application logs."""
        self.show_toast("Logs viewer coming soon", "info")

    def show_toast(
        self,
        message: str,
        toast_type: str = "info",
        duration: float | None = 3.0
    ) -> None:
        """Show a toast notification."""
        toast = Toast(
            message=message,
            toast_type=toast_type,
            duration=duration,
            closeable=True
        )

        # Add toast to active list
        self._active_toasts.append(toast)

        # Mount toast (position would need to be managed)
        # This is a simplified implementation
        toast.add_class("app-toast")

        # Auto-remove from active list when dismissed
        def on_toast_removed():
            if toast in self._active_toasts:
                self._active_toasts.remove(toast)

        # Set up removal callback
        toast.set_timer(duration or 3.0, on_toast_removed)

    def on_key(self, event) -> None:
        """Enhanced key handling with shortcut manager."""
        # Let the shortcut manager handle the key first
        if hasattr(self.shortcut_manager, 'handle_key'):
            if self.shortcut_manager.handle_key(event.key):
                event.prevent_default()
                return

        # Fall back to default handling
        super().on_key(event)


def create_enhanced_styles() -> str:
    """Create enhanced CSS styles for the optimized app."""
    return """
    /* Enhanced styles for optimized TUI */
    
    /* Lazy loading components */
    .lazy-loading-container {
        align: center middle;
        height: 100%;
    }
    
    .lazy-spinner {
        margin: 1;
        color: $accent;
    }
    
    .lazy-loading-message {
        text-align: center;
        margin: 1;
        text-style: italic;
        color: $text-muted;
    }
    
    /* Focus indicators */
    Widget:focus {
        border: solid $accent;
        background: $surface-lighten-1;
    }
    
    /* Enhanced stats grid */
    .stats-grid {
        grid-size: 4 1;
        grid-gutter: 1;
        margin: 1;
    }
    
    /* Activity section */
    .activity-container {
        height: 100%;
        margin: 1;
    }
    
    .section-title {
        text-style: bold;
        color: $primary;
        margin-bottom: 1;
    }
    
    /* Toast notifications */
    .app-toast {
        position: absolute;
        top: 2;
        right: 2;
        z-index: 1000;
        min-width: 30;
    }
    
    /* Search dialog */
    .search-dialog {
        align: center middle;
    }
    
    /* Enhanced navigation */
    NavigationSidebar {
        width: 20;
        dock: left;
        background: $surface;
        border-right: solid $primary-lighten-2;
    }
    
    /* Theme transitions */
    * {
        transition: background 200ms, color 200ms, border 200ms;
    }
    
    /* Responsive design helpers */
    @media (max-width: 80) {
        .stats-grid {
            grid-size: 2 2;
        }
    }
    
    @media (max-width: 50) {
        .stats-grid {
            grid-size: 1 4;
        }
    }
    """


def run_enhanced_tui(config_dir: Path | None = None) -> None:
    """Run the enhanced TUI application."""
    app = EnhancedVPNManagerApp(config_dir)

    # Write enhanced styles to file
    styles_path = (config_dir or Path.cwd()) / "enhanced_styles.css"
    with open(styles_path, 'w') as f:
        f.write(create_enhanced_styles())

    app.run()


if __name__ == "__main__":
    run_enhanced_tui()
