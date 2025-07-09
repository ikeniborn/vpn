"""
Confirmation dialog for dangerous operations.
"""

from typing import Callable, Optional

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Static


class ConfirmDialog(ModalScreen):
    """Modal confirmation dialog."""
    
    DEFAULT_CSS = """
    ConfirmDialog {
        align: center middle;
    }
    
    ConfirmDialog > Container {
        width: 50;
        height: 12;
        background: $surface;
        border: double $primary;
        padding: 2;
    }
    
    ConfirmDialog .dialog-title {
        text-style: bold;
        color: $primary;
        text-align: center;
        margin-bottom: 2;
    }
    
    ConfirmDialog .dialog-message {
        text-align: center;
        margin-bottom: 2;
    }
    
    ConfirmDialog .button-container {
        align: center middle;
        height: 3;
    }
    """
    
    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "confirm", "Confirm"),
    ]
    
    def __init__(
        self,
        title: str = "Confirm",
        message: str = "Are you sure?",
        callback: Optional[Callable] = None
    ):
        """Initialize confirmation dialog."""
        super().__init__()
        self.title = title
        self.message = message
        self.callback = callback
    
    def compose(self) -> ComposeResult:
        """Create dialog layout."""
        with Container():
            yield Static(self.title, classes="dialog-title")
            yield Static(self.message, classes="dialog-message")
            with Horizontal(classes="button-container"):
                yield Button("Cancel", id="cancel-btn", variant="default")
                yield Button("Confirm", id="confirm-btn", variant="primary")
    
    @on(Button.Pressed, "#confirm-btn")
    def action_confirm(self) -> None:
        """Handle confirmation."""
        if self.callback:
            self.callback()
        self.dismiss()
    
    @on(Button.Pressed, "#cancel-btn")
    def action_cancel(self) -> None:
        """Handle cancellation."""
        self.dismiss()