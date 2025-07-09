"""
Base screen class for VPN Manager TUI.
"""

from typing import Optional

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Static

from vpn.core.config import get_config
from vpn.services.user_manager import UserManager
from vpn.services.docker_manager import DockerManager
from vpn.services.network_manager import NetworkManager


class BaseScreen(Screen):
    """Base screen with common functionality."""
    
    BINDINGS = [
        Binding("escape", "app.pop_screen", "Back"),
    ]
    
    def __init__(self, name: Optional[str] = None):
        """Initialize base screen."""
        super().__init__(name=name)
        self.config = get_config()
        self._user_manager: Optional[UserManager] = None
        self._docker_manager: Optional[DockerManager] = None
        self._network_manager: Optional[NetworkManager] = None
    
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
    
    def compose_header(self, title: str, subtitle: Optional[str] = None) -> Container:
        """Create a standard header for screens."""
        with Horizontal(classes="screen-header"):
            yield Static(title, classes="screen-title")
            if subtitle:
                yield Static(subtitle, classes="screen-subtitle")
        return Container()
    
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
            self.show_error(f"{error_message}: {str(e)}")
            return None