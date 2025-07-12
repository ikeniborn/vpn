"""
Proxy authentication configuration dialog.
"""

from typing import Dict, Optional, Tuple, List
from textual import on
from textual.app import ComposeResult
from textual.containers import Container, Horizontal, Vertical, ScrollableContainer
from textual.widgets import Button, Input, Label, Static, DataTable, Select
from textual.validation import Length, ValidationResult, Validator

from vpn.tui.dialogs.base import BaseDialog
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class ProxyUserValidator(Validator):
    """Validator for proxy username."""
    
    def validate(self, value: str) -> ValidationResult:
        """Validate proxy username."""
        if not value:
            return self.failure("Username is required")
        if len(value) < 3:
            return self.failure("Username must be at least 3 characters")
        if not value.isalnum() and not all(c in "-_." for c in value if not c.isalnum()):
            return self.failure("Username can only contain letters, numbers, -, _, and .")
        return self.success()


class ProxyAuthDialog(BaseDialog):
    """Dialog for configuring proxy authentication."""
    
    DEFAULT_CSS = """
    ProxyAuthDialog {
        width: 70;
        height: 35;
    }
    
    ProxyAuthDialog Container {
        padding: 1;
    }
    
    ProxyAuthDialog .form-row {
        height: 3;
        margin-bottom: 1;
    }
    
    ProxyAuthDialog Label {
        width: 20;
        height: 1;
        margin-top: 1;
    }
    
    ProxyAuthDialog Input {
        width: 100%;
    }
    
    ProxyAuthDialog Select {
        width: 100%;
        margin-top: 1;
    }
    
    ProxyAuthDialog DataTable {
        height: 10;
        margin: 1 0;
        border: solid $primary;
    }
    
    ProxyAuthDialog .info-text {
        color: $text-muted;
        margin: 1 0;
    }
    
    ProxyAuthDialog .button-container {
        dock: bottom;
        height: 3;
        align: center middle;
    }
    """
    
    def __init__(self, server_name: str, current_auth: Optional[Dict] = None, **kwargs):
        """Initialize proxy auth dialog.
        
        Args:
            server_name: Name of the proxy server
            current_auth: Current authentication configuration
        """
        super().__init__(**kwargs)
        self.server_name = server_name
        self.current_auth = current_auth or {}
        self.auth_users: List[Tuple[str, str]] = self.current_auth.get("users", [])
    
    def compose(self) -> ComposeResult:
        """Compose the dialog."""
        yield from self.compose_header(
            f"Proxy Authentication: {self.server_name}",
            "Configure authentication for HTTP/SOCKS5 proxy"
        )
        
        with ScrollableContainer():
            with Container():
                # Authentication mode selection
                yield Static("Authentication Mode", classes="label")
                auth_options = [
                    ("none", "No Authentication"),
                    ("basic", "Basic Authentication (Username/Password)"),
                    ("ip", "IP Whitelist"),
                    ("combined", "Basic Auth + IP Whitelist")
                ]
                yield Select(
                    options=auth_options,
                    value=self.current_auth.get("mode", "none"),
                    id="auth-mode"
                )
                
                # Basic auth section
                with Container(id="basic-auth-section"):
                    yield Static("", classes="spacer")
                    yield Static("User Credentials", classes="section-header")
                    
                    # Add user form
                    with Horizontal(classes="form-row"):
                        with Vertical():
                            yield Label("Username:")
                            yield Input(
                                placeholder="Enter username",
                                id="username",
                                validators=[ProxyUserValidator(), Length(3, 50)]
                            )
                        
                        with Vertical():
                            yield Label("Password:")
                            yield Input(
                                placeholder="Enter password",
                                password=True,
                                id="password",
                                validators=[Length(6, 50)]
                            )
                        
                        yield Button("Add", variant="primary", id="add-user")
                    
                    # Users table
                    yield DataTable(id="users-table", zebra_stripes=True)
                
                # IP whitelist section
                with Container(id="ip-whitelist-section"):
                    yield Static("", classes="spacer")
                    yield Static("IP Whitelist", classes="section-header")
                    
                    with Horizontal(classes="form-row"):
                        with Vertical():
                            yield Label("IP Address/CIDR:")
                            yield Input(
                                placeholder="e.g., 192.168.1.0/24",
                                id="ip-address"
                            )
                        
                        yield Button("Add IP", variant="primary", id="add-ip")
                    
                    yield DataTable(id="ip-table", zebra_stripes=True)
                
                # Info text
                yield Static(
                    "Note: Changes will be applied after restarting the proxy server.",
                    classes="info-text"
                )
        
        # Buttons
        with Horizontal(classes="button-container"):
            yield Button("Save", variant="primary", id="save")
            yield Button("Cancel", variant="default", id="cancel")
    
    def on_mount(self) -> None:
        """Handle mount event."""
        # Setup users table
        users_table = self.query_one("#users-table", DataTable)
        users_table.add_columns("Username", "Password", "Actions")
        
        # Setup IP table
        ip_table = self.query_one("#ip-table", DataTable)
        ip_table.add_columns("IP Address/CIDR", "Actions")
        
        # Load existing users
        self._load_users()
        
        # Update section visibility
        self._update_sections_visibility()
    
    def _load_users(self) -> None:
        """Load existing users into the table."""
        users_table = self.query_one("#users-table", DataTable)
        
        for username, password in self.auth_users:
            users_table.add_row(
                username,
                "••••••••",  # Masked password
                "[red]Delete[/red]"
            )
    
    @on(Select.Changed, "#auth-mode")
    def on_auth_mode_changed(self, event: Select.Changed) -> None:
        """Handle authentication mode change."""
        self._update_sections_visibility()
    
    def _update_sections_visibility(self) -> None:
        """Update visibility of sections based on auth mode."""
        mode = self.query_one("#auth-mode", Select).value
        
        basic_section = self.query_one("#basic-auth-section")
        ip_section = self.query_one("#ip-whitelist-section")
        
        # Show/hide sections based on mode
        basic_section.display = mode in ["basic", "combined"]
        ip_section.display = mode in ["ip", "combined"]
    
    @on(Button.Pressed, "#add-user")
    def on_add_user(self) -> None:
        """Handle add user button press."""
        username_input = self.query_one("#username", Input)
        password_input = self.query_one("#password", Input)
        
        username = username_input.value.strip()
        password = password_input.value.strip()
        
        if not username or not password:
            self.notify("Please enter both username and password", severity="warning")
            return
        
        # Check for duplicate
        if any(u[0] == username for u in self.auth_users):
            self.notify(f"User '{username}' already exists", severity="error")
            return
        
        # Add to list and table
        self.auth_users.append((username, password))
        
        users_table = self.query_one("#users-table", DataTable)
        users_table.add_row(
            username,
            "••••••••",
            "[red]Delete[/red]"
        )
        
        # Clear inputs
        username_input.value = ""
        password_input.value = ""
        
        self.notify(f"User '{username}' added", severity="information")
    
    @on(DataTable.CellHighlighted, "#users-table")
    def on_user_table_cell_highlighted(self, event: DataTable.CellHighlighted) -> None:
        """Handle cell selection in users table."""
        if event.coordinate.column == 2:  # Actions column
            # Delete the user
            row_key = event.data_table.get_row_key_at(event.coordinate.row)
            if row_key is not None:
                username = event.data_table.get_cell(row_key, 0)
                self._delete_user(username, row_key)
    
    def _delete_user(self, username: str, row_key) -> None:
        """Delete a user from the list."""
        # Remove from list
        self.auth_users = [(u, p) for u, p in self.auth_users if u != username]
        
        # Remove from table
        users_table = self.query_one("#users-table", DataTable)
        users_table.remove_row(row_key)
        
        self.notify(f"User '{username}' deleted", severity="information")
    
    @on(Button.Pressed, "#save")
    def on_save(self) -> None:
        """Handle save button press."""
        mode = self.query_one("#auth-mode", Select).value
        
        # Validate based on mode
        if mode in ["basic", "combined"] and not self.auth_users:
            self.notify("Please add at least one user", severity="error")
            return
        
        # Prepare auth configuration
        auth_config = {
            "mode": mode,
            "users": self.auth_users,
            "ip_whitelist": []  # TODO: Implement IP whitelist
        }
        
        self.dismiss(auth_config)
    
    @on(Button.Pressed, "#cancel")
    def on_cancel(self) -> None:
        """Handle cancel button press."""
        self.dismiss(None)


class ProxyUserListDialog(BaseDialog):
    """Dialog for managing proxy users."""
    
    DEFAULT_CSS = """
    ProxyUserListDialog {
        width: 60;
        height: 25;
    }
    
    ProxyUserListDialog DataTable {
        height: 15;
        margin: 1 0;
        border: solid $primary;
    }
    
    ProxyUserListDialog .button-container {
        dock: bottom;
        height: 3;
        align: center middle;
    }
    """
    
    def __init__(self, server_name: str, users: List[Dict], **kwargs):
        """Initialize proxy user list dialog.
        
        Args:
            server_name: Name of the proxy server
            users: List of proxy users
        """
        super().__init__(**kwargs)
        self.server_name = server_name
        self.users = users
    
    def compose(self) -> ComposeResult:
        """Compose the dialog."""
        yield from self.compose_header(
            f"Proxy Users: {self.server_name}",
            "Manage proxy server users"
        )
        
        with Container():
            yield DataTable(id="users-table", zebra_stripes=True)
            
            with Horizontal(classes="button-container"):
                yield Button("Add User", variant="primary", id="add")
                yield Button("Edit", variant="default", id="edit")
                yield Button("Delete", variant="warning", id="delete")
                yield Button("Close", variant="default", id="close")
    
    def on_mount(self) -> None:
        """Handle mount event."""
        # Setup table
        table = self.query_one("#users-table", DataTable)
        table.add_columns("Username", "Status", "Created", "Last Access")
        
        # Load users
        for user in self.users:
            table.add_row(
                user.get("username", ""),
                user.get("status", "Active"),
                user.get("created", "N/A"),
                user.get("last_access", "Never")
            )
    
    @on(Button.Pressed, "#close")
    def on_close(self) -> None:
        """Handle close button press."""
        self.dismiss(None)