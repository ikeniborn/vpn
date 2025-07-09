"""
User form dialog for creating/editing users.
"""

from typing import Callable, Optional

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Input, Label, Select, Static

from vpn.core.models import User, ProtocolType


class UserFormDialog(ModalScreen):
    """Modal dialog for user form."""
    
    DEFAULT_CSS = """
    UserFormDialog {
        align: center middle;
    }
    
    UserFormDialog > Container {
        width: 60;
        height: 25;
        background: $surface;
        border: double $primary;
        padding: 2;
    }
    
    UserFormDialog .dialog-title {
        text-style: bold;
        color: $primary;
        text-align: center;
        margin-bottom: 2;
    }
    
    UserFormDialog .form-group {
        height: 4;
        margin-bottom: 1;
    }
    
    UserFormDialog .form-label {
        margin-bottom: 1;
    }
    
    UserFormDialog Input {
        width: 100%;
    }
    
    UserFormDialog Select {
        width: 100%;
    }
    
    UserFormDialog .button-container {
        align: center middle;
        height: 3;
        margin-top: 2;
    }
    """
    
    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("ctrl+s", "save", "Save"),
    ]
    
    def __init__(
        self,
        user: Optional[User] = None,
        callback: Optional[Callable] = None
    ):
        """Initialize user form dialog."""
        super().__init__()
        self.user = user
        self.callback = callback
        self.is_edit = user is not None
    
    def compose(self) -> ComposeResult:
        """Create form layout."""
        title = f"Edit User: {self.user.username}" if self.is_edit else "Create New User"
        
        with Container():
            yield Static(title, classes="dialog-title")
            
            # Username field
            with Vertical(classes="form-group"):
                yield Label("Username:", classes="form-label")
                yield Input(
                    value=self.user.username if self.user else "",
                    placeholder="Enter username",
                    id="username-input",
                    disabled=self.is_edit  # Can't change username
                )
            
            # Email field
            with Vertical(classes="form-group"):
                yield Label("Email (optional):", classes="form-label")
                yield Input(
                    value=self.user.email or "" if self.user else "",
                    placeholder="user@example.com",
                    id="email-input"
                )
            
            # Protocol selection
            with Vertical(classes="form-group"):
                yield Label("Protocol:", classes="form-label")
                protocol_choices = [
                    (p.value, p.value.upper()) for p in ProtocolType
                ]
                current_protocol = self.user.protocol.type.value if self.user else "vless"
                yield Select(
                    protocol_choices,
                    value=current_protocol,
                    id="protocol-select"
                )
            
            # Status selection (edit only)
            if self.is_edit:
                with Vertical(classes="form-group"):
                    yield Label("Status:", classes="form-label")
                    status_choices = [
                        ("active", "Active"),
                        ("inactive", "Inactive"),
                        ("suspended", "Suspended"),
                    ]
                    yield Select(
                        status_choices,
                        value=self.user.status,
                        id="status-select"
                    )
            
            # Buttons
            with Horizontal(classes="button-container"):
                yield Button("Cancel", id="cancel-btn", variant="default")
                yield Button("Save", id="save-btn", variant="primary")
    
    @on(Button.Pressed, "#save-btn")
    def action_save(self) -> None:
        """Handle save action."""
        # Collect form data
        user_data = {
            "username": self.query_one("#username-input", Input).value,
            "email": self.query_one("#email-input", Input).value or None,
            "protocol": self.query_one("#protocol-select", Select).value,
        }
        
        if self.is_edit:
            user_data["status"] = self.query_one("#status-select", Select).value
        
        # Validate
        if not user_data["username"]:
            self.app.notify("Username is required", severity="error")
            return
        
        # Call callback
        if self.callback:
            self.callback(user_data)
        
        self.dismiss()
    
    @on(Button.Pressed, "#cancel-btn")
    def action_cancel(self) -> None:
        """Handle cancel action."""
        self.dismiss()