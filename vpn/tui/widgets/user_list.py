"""
User list widget with context menu support for user management.
"""

import asyncio
from typing import List, Optional

from rich.table import Table
from rich.text import Text
from textual import on, work
from textual.app import ComposeResult
from textual.containers import Vertical, VerticalScroll
from textual.coordinate import Coordinate
from textual.message import Message
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import DataTable, Input, Static

from vpn.core.models import User, UserStatus
from vpn.services.user_manager import UserManager
from vpn.tui.widgets.context_menu import ContextMenu, ContextMenuItem, ContextMenuMixin, create_user_context_menu
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class UserList(Widget, ContextMenuMixin):
    """Widget for displaying a list of users with context menu support."""
    
    DEFAULT_CSS = """
    UserList {
        height: 100%;
        border: solid $primary;
    }
    
    UserList .header {
        height: 3;
        background: $primary;
        color: $text;
        padding: 1;
        dock: top;
    }
    
    UserList .search-bar {
        height: 3;
        dock: top;
        padding: 0 1;
    }
    
    UserList .user-table {
        height: 1fr;
    }
    
    UserList .footer {
        height: 3;
        background: $surface;
        color: $text-muted;
        padding: 1;
        dock: bottom;
    }
    """
    
    users: reactive[List[User]] = reactive([])
    selected_user: reactive[Optional[User]] = reactive(None)
    filter_text: reactive[str] = reactive("")
    
    class UserSelected(Message):
        """Message sent when a user is selected."""
        
        def __init__(self, user: User) -> None:
            self.user = user
            super().__init__()
    
    class UserAction(Message):
        """Message sent when a user action is triggered."""
        
        def __init__(self, action: str, user: User) -> None:
            self.action = action
            self.user = user
            super().__init__()
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.user_manager = UserManager()
        self._filtered_users: List[User] = []
        self._loading = False
        # Initialize context menu attributes from mixin
        self._context_menu = None
        self._context_menu_items = []
    
    def compose(self) -> ComposeResult:
        """Compose the user list widget."""
        with Vertical():
            # Header
            yield Static("👥 User Management", classes="header")
            
            # Search bar
            with Vertical(classes="search-bar"):
                yield Input(placeholder="Search users...", id="search_input")
            
            # User table
            with VerticalScroll(classes="user-table"):
                table = DataTable(id="user_table", cursor_type="row")
                table.add_columns("Username", "Email", "Status", "Protocol", "Traffic")
                yield table
            
            # Footer
            yield Static("Right-click for context menu • F10 for keyboard menu", classes="footer")
    
    def on_mount(self) -> None:
        """Initialize the user list when mounted."""
        self.refresh_users()
    
    @work(exclusive=True)
    async def refresh_users(self) -> None:
        """Refresh the user list from the user manager."""
        if self._loading:
            return
        
        self._loading = True
        try:
            users = await self.user_manager.list_users()
            self.users = users
            self._apply_filter()
        except Exception as e:
            logger.error(f"Failed to refresh users: {e}")
        finally:
            self._loading = False
    
    def _apply_filter(self) -> None:
        """Apply search filter to users."""
        if not self.filter_text:
            self._filtered_users = self.users
        else:
            filter_lower = self.filter_text.lower()
            self._filtered_users = [
                user for user in self.users
                if (filter_lower in user.username.lower() or
                    (user.email and filter_lower in user.email.lower()) or
                    filter_lower in user.status.value.lower())
            ]
        
        self._update_table()
    
    def _update_table(self) -> None:
        """Update the data table with filtered users."""
        try:
            table = self.query_one("#user_table", DataTable)
            table.clear()
            
            for user in self._filtered_users:
                # Format status with color
                status_text = user.status.value.title()
                if user.status == UserStatus.ACTIVE:
                    status_text = f"[green]{status_text}[/green]"
                elif user.status == UserStatus.SUSPENDED:
                    status_text = f"[yellow]{status_text}[/yellow]"
                elif user.status == UserStatus.INACTIVE:
                    status_text = f"[red]{status_text}[/red]"
                
                # Format traffic
                traffic = f"↑{self._format_bytes(user.traffic.upload_bytes)} ↓{self._format_bytes(user.traffic.download_bytes)}"
                
                table.add_row(
                    user.username,
                    user.email or "—",
                    status_text,
                    user.protocol.protocol.value.upper(),
                    traffic,
                    key=str(user.id)
                )
        except Exception as e:
            logger.error(f"Failed to update table: {e}")
    
    def _format_bytes(self, bytes_count: int) -> str:
        """Format bytes count for display."""
        if bytes_count < 1024:
            return f"{bytes_count}B"
        elif bytes_count < 1024 * 1024:
            return f"{bytes_count / 1024:.1f}KB"
        elif bytes_count < 1024 * 1024 * 1024:
            return f"{bytes_count / (1024 * 1024):.1f}MB"
        else:
            return f"{bytes_count / (1024 * 1024 * 1024):.1f}GB"
    
    @on(Input.Changed, "#search_input")
    def on_search_changed(self, event: Input.Changed) -> None:
        """Handle search input changes."""
        self.filter_text = event.value
        self._apply_filter()
    
    @on(DataTable.RowSelected)
    def on_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection in the data table."""
        if event.row_key:
            # Find user by ID
            user_id = event.row_key.value
            user = next((u for u in self._filtered_users if str(u.id) == user_id), None)
            
            if user:
                self.selected_user = user
                self.post_message(self.UserSelected(user))
    
    def on_click(self, event) -> None:
        """Handle click events for context menu."""
        if hasattr(event, 'button') and event.button == 3:  # Right click
            # Check if click is on a user row
            if self.selected_user:
                # Create context menu for selected user
                self.set_context_menu_items(self._create_user_context_menu(self.selected_user))
                self.show_context_menu(Coordinate(event.x, event.y))
                event.prevent_default()
        else:
            # Hide context menu on left click
            self.hide_context_menu()
    
    def on_key(self, event) -> None:
        """Handle keyboard events."""
        if event.key == "f10" or (event.key == "f" and event.shift):
            # Show context menu with keyboard
            if self.selected_user:
                self.set_context_menu_items(self._create_user_context_menu(self.selected_user))
                self.show_context_menu()
                event.prevent_default()
        elif event.key == "f5":
            # Refresh users
            self.refresh_users()
            event.prevent_default()
        elif event.key == "ctrl+f":
            # Focus search input
            try:
                search_input = self.query_one("#search_input", Input)
                search_input.focus()
                event.prevent_default()
            except Exception:
                pass
        elif event.key == "delete" and self.selected_user:
            # Delete user
            self._handle_user_action("delete", self.selected_user)
            event.prevent_default()
        elif event.key == "enter" and self.selected_user:
            # View user details
            self._handle_user_action("view", self.selected_user)
            event.prevent_default()
        
        # Call parent handler
        super().on_key(event)
    
    def _create_user_context_menu(self, user: User) -> List[ContextMenuItem]:
        """Create context menu items for a specific user."""
        return [
            ContextMenuItem(
                "View Details",
                action=lambda: self._handle_user_action("view", user),
                shortcut="Enter"
            ),
            ContextMenuItem(
                "Edit User",
                action=lambda: self._handle_user_action("edit", user),
                shortcut="F2"
            ),
            ContextMenuItem("", separator=True),
            ContextMenuItem(
                "Generate QR Code",
                action=lambda: self._handle_user_action("qr", user),
                shortcut="Q"
            ),
            ContextMenuItem(
                "Show Connection",
                action=lambda: self._handle_user_action("connection", user),
                shortcut="C"
            ),
            ContextMenuItem(
                "Reset Traffic",
                action=lambda: self._handle_user_action("reset_traffic", user),
                shortcut="R"
            ),
            ContextMenuItem("", separator=True),
            ContextMenuItem(
                "Suspend User" if user.status == UserStatus.ACTIVE else "Activate User",
                action=lambda: self._handle_user_action("toggle_status", user),
                shortcut="S"
            ),
            ContextMenuItem(
                "Delete User",
                action=lambda: self._handle_user_action("delete", user),
                shortcut="Del",
                enabled=True
            ),
        ]
    
    def _handle_user_action(self, action: str, user: User) -> None:
        """Handle user action from context menu."""
        self.post_message(self.UserAction(action, user))
    
    @on(ContextMenu.ItemSelected)
    def on_context_menu_item_selected(self, event: ContextMenu.ItemSelected) -> None:
        """Handle context menu item selection."""
        # Actions are handled by the lambda functions in menu items
        pass
    
    def watch_users(self, users: List[User]) -> None:
        """React to users list changes."""
        self._apply_filter()
    
    def watch_filter_text(self, filter_text: str) -> None:
        """React to filter text changes."""
        self._apply_filter()
    
    def get_selected_user(self) -> Optional[User]:
        """Get the currently selected user."""
        return self.selected_user
    
    def select_user(self, user_id: str) -> None:
        """Select a user by ID."""
        user = next((u for u in self._filtered_users if str(u.id) == user_id), None)
        if user:
            self.selected_user = user
            
            # Update table selection
            try:
                table = self.query_one("#user_table", DataTable)
                table.cursor_row = next(
                    (i for i, row in enumerate(table.rows) if row.key.value == user_id),
                    0
                )
            except Exception:
                pass
    
    def add_user(self, user: User) -> None:
        """Add a new user to the list."""
        self.users = [*self.users, user]
    
    def update_user(self, user: User) -> None:
        """Update an existing user in the list."""
        updated_users = []
        for u in self.users:
            if u.id == user.id:
                updated_users.append(user)
            else:
                updated_users.append(u)
        self.users = updated_users
    
    def remove_user(self, user_id: str) -> None:
        """Remove a user from the list."""
        self.users = [u for u in self.users if str(u.id) != user_id]
        
        # Clear selection if removed user was selected
        if self.selected_user and str(self.selected_user.id) == user_id:
            self.selected_user = None