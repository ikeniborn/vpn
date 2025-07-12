"""
Error display widget for TUI.
"""

from typing import Optional

from rich.console import RenderableType
from rich.panel import Panel
from rich.text import Text
from textual.containers import Container, Vertical
from textual.reactive import reactive
from textual.widgets import Button, Static

from vpn.core.exceptions import VPNError


class ErrorDisplay(Container):
    """Widget for displaying errors with suggestions."""
    
    DEFAULT_CSS = """
    ErrorDisplay {
        height: auto;
        background: $error 20%;
        border: solid $error;
        padding: 1;
        margin: 1;
    }
    
    .error-title {
        text-style: bold;
        color: $error;
        margin-bottom: 1;
    }
    
    .error-message {
        margin-bottom: 1;
    }
    
    .error-details {
        color: $text-muted;
        margin-bottom: 1;
    }
    
    .error-suggestions {
        margin-top: 1;
    }
    
    .error-suggestion-item {
        margin-left: 2;
        color: $warning;
    }
    
    .error-actions {
        margin-top: 1;
        height: 3;
        align: center middle;
    }
    
    .error-dismiss-button {
        background: $surface;
        width: 20;
    }
    """
    
    error: reactive[Optional[Exception]] = reactive(None)
    show_dismiss: reactive[bool] = reactive(True)
    
    def __init__(
        self,
        error: Optional[Exception] = None,
        show_dismiss: bool = True,
        id: Optional[str] = None,
        classes: Optional[str] = None,
    ):
        """Initialize error display.
        
        Args:
            error: The error to display
            show_dismiss: Whether to show dismiss button
            id: Widget ID
            classes: Additional CSS classes
        """
        super().__init__(id=id, classes=classes)
        self.error = error
        self.show_dismiss = show_dismiss
    
    def compose(self):
        """Compose the error display."""
        if self.error:
            yield from self._compose_error()
    
    def _compose_error(self):
        """Compose error content."""
        with Vertical():
            # Error title
            error_type = type(self.error).__name__
            yield Static(f"❌ {error_type}", classes="error-title")
            
            # Error message
            yield Static(str(self.error.args[0] if self.error.args else "Unknown error"), 
                        classes="error-message")
            
            # Error details (if VPNError)
            if isinstance(self.error, VPNError) and self.error.details:
                details_text = "\n".join(
                    f"{k}: {v}" for k, v in self.error.details.items()
                )
                yield Static(details_text, classes="error-details")
            
            # Suggestions (if VPNError)
            if isinstance(self.error, VPNError) and self.error.suggestions:
                yield Static("💡 Suggestions:", classes="error-suggestions")
                for i, suggestion in enumerate(self.error.suggestions, 1):
                    yield Static(f"{i}. {suggestion}", 
                               classes="error-suggestion-item")
            
            # Dismiss button
            if self.show_dismiss:
                with Container(classes="error-actions"):
                    yield Button("Dismiss", 
                               variant="primary", 
                               classes="error-dismiss-button",
                               id="dismiss-error")
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press."""
        if event.button.id == "dismiss-error":
            self.remove()
    
    def watch_error(self, old_error: Optional[Exception], new_error: Optional[Exception]) -> None:
        """Watch for error changes."""
        if new_error != old_error:
            # Remove old content
            self.remove_children()
            
            # Add new content if there's an error
            if new_error:
                self.mount(*list(self._compose_error()))


class ErrorBoundary(Container):
    """Container that catches and displays errors from child widgets."""
    
    DEFAULT_CSS = """
    ErrorBoundary {
        height: 100%;
        width: 100%;
    }
    
    .error-boundary-fallback {
        height: 100%;
        align: center middle;
        background: $surface;
    }
    """
    
    def __init__(
        self,
        *children,
        fallback_message: str = "An error occurred",
        id: Optional[str] = None,
        classes: Optional[str] = None,
    ):
        """Initialize error boundary.
        
        Args:
            *children: Child widgets to wrap
            fallback_message: Message to show on error
            id: Widget ID
            classes: Additional CSS classes
        """
        super().__init__(*children, id=id, classes=classes)
        self.fallback_message = fallback_message
        self._error_display: Optional[ErrorDisplay] = None
    
    def handle_exception(self, exception: Exception) -> None:
        """Handle exceptions from child widgets."""
        # Remove all children
        self.remove_children()
        
        # Create and mount error display
        self._error_display = ErrorDisplay(exception, show_dismiss=False)
        
        with self:
            self.mount(
                Container(
                    self._error_display,
                    classes="error-boundary-fallback"
                )
            )
    
    async def watch_children(self) -> None:
        """Watch for errors in children."""
        try:
            await super().watch_children()
        except Exception as e:
            self.handle_exception(e)


class LoadingErrorBoundary(ErrorBoundary):
    """Error boundary with loading state support."""
    
    DEFAULT_CSS = """
    LoadingErrorBoundary {
        height: 100%;
        width: 100%;
    }
    
    .loading-indicator {
        height: 100%;
        align: center middle;
    }
    """
    
    loading: reactive[bool] = reactive(True)
    error: reactive[Optional[Exception]] = reactive(None)
    
    def __init__(
        self,
        *children,
        loading: bool = True,
        loading_message: str = "Loading...",
        **kwargs
    ):
        """Initialize loading error boundary."""
        super().__init__(*children, **kwargs)
        self.loading = loading
        self.loading_message = loading_message
    
    def compose(self):
        """Compose the widget."""
        if self.loading:
            yield Container(
                Static(f"⏳ {self.loading_message}"),
                classes="loading-indicator"
            )
        elif self.error:
            yield ErrorDisplay(self.error)
        else:
            yield from super().compose()
    
    def watch_loading(self, was_loading: bool, is_loading: bool) -> None:
        """Watch loading state changes."""
        if was_loading and not is_loading:
            self.refresh()
    
    def watch_error(self, old_error: Optional[Exception], new_error: Optional[Exception]) -> None:
        """Watch error state changes."""
        if new_error != old_error:
            self.refresh()
    
    def set_content(self, *children) -> None:
        """Set content after loading."""
        self.loading = False
        self.error = None
        self.remove_children()
        self.mount(*children)
    
    def set_error(self, error: Exception) -> None:
        """Set error state."""
        self.loading = False
        self.error = error