"""Base screen class for VPN Manager TUI.
"""


from textual.binding import Binding
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Static

from vpn.core.config import get_config
from vpn.services.docker_manager import DockerManager
from vpn.services.network_manager import NetworkManager
from vpn.services.user_manager import UserManager


class BaseScreen(Screen):
    """Base screen with common functionality."""

    BINDINGS = [
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def __init__(self, name: str | None = None):
        """Initialize base screen."""
        super().__init__(name=name)
        self.config = get_config()
        self._user_manager: UserManager | None = None
        self._docker_manager: DockerManager | None = None
        self._network_manager: NetworkManager | None = None

    @property
    def user_manager(self) -> UserManager:
        """Get user manager instance."""
        if self._user_manager is None:
            self._user_manager = UserManager()
        return self._user_manager

    @property
    def docker_manager(self) -> DockerManager:
        """Get Docker manager instance."""
        if self._docker_manager is None:
            self._docker_manager = DockerManager()
        return self._docker_manager

    @property
    def network_manager(self) -> NetworkManager:
        """Get network manager instance."""
        if self._network_manager is None:
            self._network_manager = NetworkManager()
        return self._network_manager

    def compose_header(self, title: str, subtitle: str | None = None):
        """Create a standard header for screens."""
        widgets = [Static(title, classes="screen-title")]
        if subtitle:
            widgets.append(Static(subtitle, classes="screen-subtitle"))

        yield Horizontal(*widgets, classes="screen-header")

    def show_error(self, message: str) -> None:
        """Show error notification."""
        self.app.notify(message, severity="error", timeout=5)

    def show_success(self, message: str) -> None:
        """Show success notification."""
        self.app.notify(message, severity="information", timeout=3)

    def show_warning(self, message: str) -> None:
        """Show warning notification."""
        self.app.notify(message, severity="warning", timeout=4)

    async def handle_async_error(self, coro, error_message: str):
        """Handle async operations with error handling."""
        try:
            result = await coro
            return result
        except Exception as e:
            self.show_error(f"{error_message}: {e!s}")
            self.log.exception(f"Error in async operation: {error_message}")
            return None

    def mount_with_error_boundary(self, *widgets, **kwargs):
        """Mount widgets within an error boundary."""
        from vpn.tui.widgets.error_display import ErrorBoundary

        boundary = ErrorBoundary(*widgets, **kwargs)
        return self.mount(boundary)

    async def safe_update(self, update_func, error_message: str = "Update failed"):
        """Safely run an update function with error handling."""
        try:
            await update_func()
        except Exception as e:
            self.log.error(f"{error_message}: {e}")
            # Continue running - don't crash the TUI
            pass
