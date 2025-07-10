"""
Users management screen.
"""

import asyncio
from typing import List, Optional

from textual import on, work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical, ScrollableContainer
from textual.reactive import reactive
from textual.widgets import Button, DataTable, Input, Label, Select, Static

from vpn.core.models import User, ProtocolType
from vpn.tui.screens.base import BaseScreen
from vpn.tui.dialogs.user_form import UserFormDialog
from vpn.tui.dialogs.confirm import ConfirmDialog
from vpn.tui.widgets.user_details import UserDetailsWidget


class UsersScreen(BaseScreen):
    """Screen for managing VPN users."""
    
    DEFAULT_CSS = """
    UsersScreen {
        background: $surface;
    }
    
    .users-header {
        height: 3;
        margin: 1;
        padding: 0 1;
    }
    
    .users-table-container {
        margin: 1;
        height: 1fr;
    }
    
    .user-actions {
        height: 5;
        margin: 1;
        align: center middle;
    }
    
    .search-box {
        width: 30;
        margin-right: 2;
    }
    
    .filter-select {
        width: 20;
        margin-right: 2;
    }
    """
    
    BINDINGS = [
        Binding("n", "new_user", "New User"),
        Binding("e", "edit_user", "Edit"),
        Binding("d", "delete_user", "Delete"),
        Binding("r", "refresh", "Refresh"),
        Binding("enter", "show_details", "Details"),
        Binding("/", "focus_search", "Search"),
    ]
    
    selected_user: reactive[Optional[User]] = reactive(None)
    search_query = reactive("")
    status_filter = reactive("all")
    
    def __init__(self):
        """Initialize users screen."""
        super().__init__()
        self.users: List[User] = []
    
    def compose(self) -> ComposeResult:
        """Create users screen layout."""
        yield from self.compose_header("Users Management", "Manage VPN users")
        
        # Search and filter bar
        with Horizontal(classes="users-header"):
            yield Input(
                placeholder="Search users...",
                classes="search-box",
                id="search-input"
            )
            yield Select(
                [
                    ("all", "All Users"),
                    ("active", "Active"),
                    ("inactive", "Inactive"),
                    ("suspended", "Suspended"),
                ],
                value="all",
                classes="filter-select",
                id="status-filter"
            )
            yield Button("🔄 Refresh", id="refresh-btn", variant="primary")
        
        # Main content area
        with Horizontal():
            # Users table
            with Container(classes="users-table-container"):
                yield DataTable(id="users-table", cursor_type="row")
            
            # User details panel
            yield UserDetailsWidget(id="user-details")
        
        # Action buttons
        with Horizontal(classes="user-actions"):
            yield Button("➕ New User", id="new-user-btn", variant="primary")
            yield Button("✏️  Edit", id="edit-user-btn", disabled=True)
            yield Button("🗑️  Delete", id="delete-user-btn", variant="error", disabled=True)
            yield Button("📋 Export", id="export-btn")
            yield Button("📥 Import", id="import-btn")
    
    def on_mount(self) -> None:
        """Setup the screen when mounted."""
        # Setup users table
        table = self.query_one("#users-table", DataTable)
        table.add_columns(
            "Username",
            "Email",
            "Protocol",
            "Status",
            "Traffic ↑",
            "Traffic ↓",
            "Created",
        )
        table.cursor_type = "row"
        
        # Load users
        self.load_users()
    
    @work(exclusive=True)
    async def load_users(self) -> None:
        """Load users from backend."""
        try:
            self.users = await self.user_manager.list()
            self.update_table()
        except Exception as e:
            self.show_error(f"Failed to load users: {e}")
    
    def update_table(self) -> None:
        """Update users table with current data."""
        table = self.query_one("#users-table", DataTable)
        table.clear()
        
        # Filter users
        filtered_users = self.filter_users()
        
        # Add rows
        for user in filtered_users:
            table.add_row(
                user.username,
                user.email or "-",
                user.protocol.type.value,
                self._format_status(user.status),
                self._format_bytes(user.traffic.upload_bytes),
                self._format_bytes(user.traffic.download_bytes),
                user.created_at.strftime("%Y-%m-%d"),
                key=str(user.id)
            )
    
    def filter_users(self) -> List[User]:
        """Filter users based on search and status."""
        users = self.users
        
        # Apply search filter
        if self.search_query:
            query = self.search_query.lower()
            users = [
                u for u in users
                if query in u.username.lower() or
                   (u.email and query in u.email.lower())
            ]
        
        # Apply status filter
        if self.status_filter != "all":
            users = [u for u in users if u.status == self.status_filter]
        
        return users
    
    def _format_status(self, status: str) -> str:
        """Format status with emoji."""
        status_map = {
            "active": "🟢 Active",
            "inactive": "🟡 Inactive",
            "suspended": "🔴 Suspended",
        }
        return status_map.get(status, status)
    
    def _format_bytes(self, bytes: int) -> str:
        """Format bytes to human readable."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes < 1024.0:
                return f"{bytes:.1f} {unit}"
            bytes /= 1024.0
        return f"{bytes:.1f} PB"
    
    @on(DataTable.RowSelected)
    def on_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection."""
        user_id = event.row_key.value
        self.selected_user = next((u for u in self.users if str(u.id) == user_id), None)
        
        # Update button states
        self.query_one("#edit-user-btn", Button).disabled = self.selected_user is None
        self.query_one("#delete-user-btn", Button).disabled = self.selected_user is None
        
        # Update details panel
        if self.selected_user:
            details_widget = self.query_one("#user-details", UserDetailsWidget)
            details_widget.user = self.selected_user
    
    @on(Input.Changed, "#search-input")
    def on_search_changed(self, event: Input.Changed) -> None:
        """Handle search input changes."""
        self.search_query = event.value
        self.update_table()
    
    @on(Select.Changed, "#status-filter")
    def on_filter_changed(self, event: Select.Changed) -> None:
        """Handle filter changes."""
        self.status_filter = event.value
        self.update_table()
    
    @on(Button.Pressed, "#new-user-btn")
    def action_new_user(self) -> None:
        """Show new user dialog."""
        def handle_create(user_data):
            self.create_user(user_data)
        
        self.app.push_screen(UserFormDialog(callback=handle_create))
    
    @on(Button.Pressed, "#edit-user-btn")
    def action_edit_user(self) -> None:
        """Show edit user dialog."""
        if not self.selected_user:
            return
        
        def handle_edit(user_data):
            self.update_user(self.selected_user.id, user_data)
        
        self.app.push_screen(
            UserFormDialog(user=self.selected_user, callback=handle_edit)
        )
    
    @on(Button.Pressed, "#delete-user-btn")
    def action_delete_user(self) -> None:
        """Show delete confirmation."""
        if not self.selected_user:
            return
        
        def handle_confirm():
            self.delete_user(self.selected_user.id)
        
        self.app.push_screen(
            ConfirmDialog(
                title="Delete User",
                message=f"Are you sure you want to delete user '{self.selected_user.username}'?",
                callback=handle_confirm
            )
        )
    
    @on(Button.Pressed, "#refresh-btn")
    def action_refresh(self) -> None:
        """Refresh users list."""
        self.load_users()
    
    def action_focus_search(self) -> None:
        """Focus search input."""
        self.query_one("#search-input", Input).focus()
    
    def action_show_details(self) -> None:
        """Show detailed user information."""
        if self.selected_user:
            # Could push a detail screen or expand the details panel
            pass
    
    @work
    async def create_user(self, user_data: dict) -> None:
        """Create new user."""
        try:
            user = await self.user_manager.create(**user_data)
            self.show_success(f"User '{user.username}' created successfully")
            await self.load_users()
        except Exception as e:
            self.show_error(f"Failed to create user: {e}")
    
    @work
    async def update_user(self, user_id: str, user_data: dict) -> None:
        """Update existing user."""
        try:
            await self.user_manager.update(user_id, **user_data)
            self.show_success("User updated successfully")
            await self.load_users()
        except Exception as e:
            self.show_error(f"Failed to update user: {e}")
    
    @work
    async def delete_user(self, user_id: str) -> None:
        """Delete user."""
        try:
            await self.user_manager.delete(user_id)
            self.show_success("User deleted successfully")
            self.selected_user = None
            await self.load_users()
        except Exception as e:
            self.show_error(f"Failed to delete user: {e}")