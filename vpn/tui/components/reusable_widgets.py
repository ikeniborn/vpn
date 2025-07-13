"""Reusable TUI widgets for VPN Manager.

This module provides a comprehensive collection of reusable Textual widgets
optimized for common UI patterns in the VPN Manager application.
"""

from collections.abc import Callable
from enum import Enum

from textual import on
from textual.app import ComposeResult
from textual.containers import Container, Horizontal
from textual.message import Message
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.timer import Timer
from textual.validation import ValidationResult, Validator
from textual.widget import Widget
from textual.widgets import Button, Input, Label, ProgressBar, Static


class StatusType(Enum):
    """Status indicator types."""
    SUCCESS = "success"
    WARNING = "warning"
    ERROR = "error"
    INFO = "info"
    LOADING = "loading"


# Data Display Widgets

class InfoCard(Container):
    """Reusable info card widget."""

    DEFAULT_CSS = """
    InfoCard {
        width: 100%;
        height: auto;
        margin: 1;
        padding: 1;
        border: solid $primary-lighten-2;
        background: $surface;
    }
    
    .info-card-title {
        text-style: bold;
        color: $primary;
        margin-bottom: 1;
    }
    
    .info-card-content {
        color: $text;
    }
    
    .info-card-footer {
        margin-top: 1;
        text-align: right;
        color: $text-muted;
    }
    
    InfoCard.highlighted {
        border: solid $accent;
        background: $accent-lighten-3;
    }
    
    InfoCard.error {
        border: solid $error;
        background: $error-lighten-3;
    }
    """

    def __init__(
        self,
        title: str,
        content: str = "",
        footer: str = "",
        highlighted: bool = False,
        error: bool = False,
        **kwargs
    ):
        """Initialize info card."""
        super().__init__(**kwargs)
        self.title = title
        self.content = content
        self.footer = footer

        if highlighted:
            self.add_class("highlighted")
        if error:
            self.add_class("error")

    def compose(self) -> ComposeResult:
        """Compose the info card."""
        yield Static(self.title, classes="info-card-title")
        if self.content:
            yield Static(self.content, classes="info-card-content")
        if self.footer:
            yield Static(self.footer, classes="info-card-footer")

    def update_content(self, content: str) -> None:
        """Update card content."""
        content_widget = self.query_one(".info-card-content", Static)
        content_widget.update(content)

    def update_footer(self, footer: str) -> None:
        """Update card footer."""
        footer_widget = self.query_one(".info-card-footer", Static)
        footer_widget.update(footer)


class StatusIndicator(Static):
    """Status indicator with color coding."""

    DEFAULT_CSS = """
    StatusIndicator.success {
        color: $success;
        text-style: bold;
    }
    
    StatusIndicator.warning {
        color: $warning;
        text-style: bold;
    }
    
    StatusIndicator.error {
        color: $error;
        text-style: bold;
    }
    
    StatusIndicator.info {
        color: $primary;
        text-style: bold;
    }
    
    StatusIndicator.loading {
        color: $accent;
        text-style: bold;
    }
    """

    status = reactive(StatusType.INFO)

    def __init__(
        self,
        text: str = "",
        status: StatusType = StatusType.INFO,
        **kwargs
    ):
        """Initialize status indicator."""
        super().__init__(text, **kwargs)
        self.status = status

    def watch_status(self, status: StatusType) -> None:
        """Watch status changes."""
        # Remove all status classes
        for status_type in StatusType:
            self.remove_class(status_type.value)

        # Add current status class
        self.add_class(status.value)

        # Update icon based on status
        icons = {
            StatusType.SUCCESS: "✓",
            StatusType.WARNING: "⚠",
            StatusType.ERROR: "✗",
            StatusType.INFO: "ℹ",
            StatusType.LOADING: "⟳",
        }

        current_text = str(self.renderable)
        # Remove existing icon if any
        for icon in icons.values():
            current_text = current_text.replace(f"{icon} ", "")

        self.update(f"{icons[status]} {current_text}")


class ProgressCard(Container):
    """Card widget with progress bar."""

    DEFAULT_CSS = """
    ProgressCard {
        width: 100%;
        height: auto;
        margin: 1;
        padding: 1;
        border: solid $primary-lighten-2;
        background: $surface;
    }
    
    .progress-title {
        text-style: bold;
        margin-bottom: 1;
    }
    
    .progress-details {
        margin: 1 0;
        color: $text-muted;
    }
    """

    progress = reactive(0.0)

    def __init__(
        self,
        title: str,
        total: int = 100,
        show_percentage: bool = True,
        show_eta: bool = False,
        **kwargs
    ):
        """Initialize progress card."""
        super().__init__(**kwargs)
        self.title = title
        self.total = total
        self.show_percentage = show_percentage
        self.show_eta = show_eta
        self._start_time = None

    def compose(self) -> ComposeResult:
        """Compose the progress card."""
        yield Static(self.title, classes="progress-title")
        yield ProgressBar(total=self.total, id="progress-bar")
        if self.show_percentage or self.show_eta:
            yield Static("", classes="progress-details", id="progress-details")

    def watch_progress(self, progress: float) -> None:
        """Watch progress changes."""
        progress_bar = self.query_one("#progress-bar", ProgressBar)
        progress_bar.advance(progress - progress_bar.progress)

        if self.show_percentage or self.show_eta:
            details = []

            if self.show_percentage:
                percentage = (progress / self.total) * 100
                details.append(f"{percentage:.1f}%")

            if self.show_eta and self._start_time:
                # Simple ETA calculation
                import time
                elapsed = time.time() - self._start_time
                if progress > 0:
                    total_time = elapsed * (self.total / progress)
                    remaining = total_time - elapsed
                    details.append(f"ETA: {remaining:.0f}s")

            if details:
                details_widget = self.query_one("#progress-details", Static)
                details_widget.update(" | ".join(details))

    def start(self) -> None:
        """Start progress tracking."""
        import time
        self._start_time = time.time()

    def complete(self) -> None:
        """Mark progress as complete."""
        self.progress = self.total


class MetricCard(Container):
    """Card displaying a metric with trend."""

    DEFAULT_CSS = """
    MetricCard {
        width: 100%;
        height: auto;
        margin: 1;
        padding: 1;
        border: solid $primary-lighten-2;
        background: $surface;
    }
    
    .metric-title {
        color: $text-muted;
        text-align: center;
        margin-bottom: 1;
    }
    
    .metric-value {
        text-style: bold;
        text-align: center;
        color: $primary;
        margin-bottom: 1;
    }
    
    .metric-trend {
        text-align: center;
        color: $success;
    }
    
    .metric-trend.negative {
        color: $error;
    }
    
    .metric-trend.neutral {
        color: $text-muted;
    }
    """

    def __init__(
        self,
        title: str,
        value: str,
        trend: str | None = None,
        trend_positive: bool | None = None,
        **kwargs
    ):
        """Initialize metric card."""
        super().__init__(**kwargs)
        self.title = title
        self.value = value
        self.trend = trend
        self.trend_positive = trend_positive

    def compose(self) -> ComposeResult:
        """Compose the metric card."""
        yield Static(self.title, classes="metric-title")
        yield Static(self.value, classes="metric-value", id="metric-value")

        if self.trend:
            trend_classes = "metric-trend"
            if self.trend_positive is False:
                trend_classes += " negative"
            elif self.trend_positive is None:
                trend_classes += " neutral"

            yield Static(self.trend, classes=trend_classes)

    def update_value(self, value: str, trend: str | None = None, trend_positive: bool | None = None) -> None:
        """Update metric value and trend."""
        value_widget = self.query_one("#metric-value", Static)
        value_widget.update(value)

        if trend is not None:
            self.trend = trend
            self.trend_positive = trend_positive
            # Re-compose trend widget
            # This is a simplified approach - in practice, you'd update the existing widget


# Input Widgets

class FormField(Container):
    """Form field with label and validation."""

    DEFAULT_CSS = """
    FormField {
        width: 100%;
        height: auto;
        margin: 1 0;
    }
    
    .field-label {
        margin-bottom: 1;
        color: $text;
    }
    
    .field-label.required::after {
        content: " *";
        color: $error;
    }
    
    .field-error {
        margin-top: 1;
        color: $error;
        text-style: italic;
    }
    
    .field-help {
        margin-top: 1;
        color: $text-muted;
        text-style: italic;
    }
    """

    def __init__(
        self,
        label: str,
        field_id: str,
        required: bool = False,
        help_text: str = "",
        validator: Validator | None = None,
        **kwargs
    ):
        """Initialize form field."""
        super().__init__(**kwargs)
        self.label = label
        self.field_id = field_id
        self.required = required
        self.help_text = help_text
        self.validator = validator
        self._error_message = ""

    def compose(self) -> ComposeResult:
        """Compose the form field."""
        label_classes = "field-label"
        if self.required:
            label_classes += " required"

        yield Label(self.label, classes=label_classes)
        yield Input(id=self.field_id, validators=[self.validator] if self.validator else [])

        if self._error_message:
            yield Static(self._error_message, classes="field-error", id="field-error")

        if self.help_text:
            yield Static(self.help_text, classes="field-help")

    def set_error(self, message: str) -> None:
        """Set field error message."""
        self._error_message = message
        try:
            error_widget = self.query_one("#field-error", Static)
            error_widget.update(message)
        except:
            # Error widget doesn't exist, add it
            if message:
                self.mount(Static(message, classes="field-error", id="field-error"))

    def clear_error(self) -> None:
        """Clear field error."""
        self._error_message = ""
        try:
            error_widget = self.query_one("#field-error", Static)
            error_widget.remove()
        except:
            pass  # Widget doesn't exist


class ValidatedInput(Input):
    """Input widget with real-time validation."""

    def __init__(
        self,
        validators: list[Validator] | None = None,
        on_validation: Callable[[ValidationResult], None] | None = None,
        **kwargs
    ):
        """Initialize validated input."""
        super().__init__(validators=validators, **kwargs)
        self.on_validation = on_validation

    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes."""
        result = self.validate(event.value)
        if self.on_validation:
            self.on_validation(result)


# Dialog Widgets

class ConfirmDialog(ModalScreen):
    """Confirmation dialog."""

    DEFAULT_CSS = """
    ConfirmDialog {
        align: center middle;
    }
    
    .confirm-dialog {
        width: 50%;
        height: auto;
        background: $surface;
        border: solid $primary;
        padding: 2;
    }
    
    .confirm-title {
        text-style: bold;
        text-align: center;
        margin-bottom: 2;
        color: $warning;
    }
    
    .confirm-message {
        text-align: center;
        margin-bottom: 2;
    }
    
    .confirm-buttons {
        margin-top: 2;
    }
    """

    class Confirmed(Message):
        """Message sent when dialog is confirmed."""
        def __init__(self, result: bool) -> None:
            super().__init__()
            self.result = result

    def __init__(
        self,
        title: str = "Confirm",
        message: str = "Are you sure?",
        confirm_text: str = "Yes",
        cancel_text: str = "No",
        **kwargs
    ):
        """Initialize confirm dialog."""
        super().__init__(**kwargs)
        self.title = title
        self.message = message
        self.confirm_text = confirm_text
        self.cancel_text = cancel_text

    def compose(self) -> ComposeResult:
        """Compose the dialog."""
        with Container(classes="confirm-dialog"):
            yield Static(self.title, classes="confirm-title")
            yield Static(self.message, classes="confirm-message")

            with Horizontal(classes="confirm-buttons"):
                yield Button(self.confirm_text, id="confirm", variant="primary")
                yield Button(self.cancel_text, id="cancel")

    @on(Button.Pressed, "#confirm")
    def confirm_pressed(self) -> None:
        """Handle confirm button."""
        self.post_message(self.Confirmed(True))
        self.dismiss(True)

    @on(Button.Pressed, "#cancel")
    def cancel_pressed(self) -> None:
        """Handle cancel button."""
        self.post_message(self.Confirmed(False))
        self.dismiss(False)


class InputDialog(ModalScreen):
    """Input dialog for getting user text input."""

    DEFAULT_CSS = """
    InputDialog {
        align: center middle;
    }
    
    .input-dialog {
        width: 60%;
        height: auto;
        background: $surface;
        border: solid $primary;
        padding: 2;
    }
    
    .input-title {
        text-style: bold;
        text-align: center;
        margin-bottom: 2;
    }
    
    .input-field {
        margin: 2 0;
    }
    
    .input-buttons {
        margin-top: 2;
    }
    """

    class InputSubmitted(Message):
        """Message sent when input is submitted."""
        def __init__(self, value: str) -> None:
            super().__init__()
            self.value = value

    def __init__(
        self,
        title: str = "Input",
        prompt: str = "Enter value:",
        placeholder: str = "",
        default_value: str = "",
        **kwargs
    ):
        """Initialize input dialog."""
        super().__init__(**kwargs)
        self.title = title
        self.prompt = prompt
        self.placeholder = placeholder
        self.default_value = default_value

    def compose(self) -> ComposeResult:
        """Compose the dialog."""
        with Container(classes="input-dialog"):
            yield Static(self.title, classes="input-title")
            yield Static(self.prompt)

            yield Input(
                placeholder=self.placeholder,
                value=self.default_value,
                id="input-field",
                classes="input-field"
            )

            with Horizontal(classes="input-buttons"):
                yield Button("OK", id="ok", variant="primary")
                yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        """Focus the input field when mounted."""
        self.query_one("#input-field", Input).focus()

    @on(Button.Pressed, "#ok")
    def ok_pressed(self) -> None:
        """Handle OK button."""
        input_field = self.query_one("#input-field", Input)
        self.post_message(self.InputSubmitted(input_field.value))
        self.dismiss(input_field.value)

    @on(Button.Pressed, "#cancel")
    def cancel_pressed(self) -> None:
        """Handle cancel button."""
        self.dismiss(None)

    @on(Input.Submitted)
    def input_submitted(self, event: Input.Submitted) -> None:
        """Handle input submission."""
        self.post_message(self.InputSubmitted(event.value))
        self.dismiss(event.value)


# Layout Widgets

class SplitView(Container):
    """Resizable split view container."""

    DEFAULT_CSS = """
    SplitView {
        width: 100%;
        height: 100%;
    }
    
    .split-pane {
        height: 100%;
    }
    
    .split-horizontal .split-pane {
        width: 50%;
    }
    
    .split-vertical .split-pane {
        height: 50%;
    }
    
    .split-resizer {
        background: $primary-lighten-2;
    }
    
    .split-horizontal .split-resizer {
        width: 1;
        height: 100%;
    }
    
    .split-vertical .split-resizer {
        width: 100%;
        height: 1;
    }
    """

    def __init__(
        self,
        left_content: Widget,
        right_content: Widget,
        orientation: str = "horizontal",
        split_ratio: float = 0.5,
        resizable: bool = True,
        **kwargs
    ):
        """Initialize split view."""
        super().__init__(**kwargs)
        self.left_content = left_content
        self.right_content = right_content
        self.orientation = orientation
        self.split_ratio = split_ratio
        self.resizable = resizable

        self.add_class(f"split-{orientation}")

    def compose(self) -> ComposeResult:
        """Compose the split view."""
        yield Container(self.left_content, classes="split-pane", id="left-pane")

        if self.resizable:
            yield Container(classes="split-resizer", id="resizer")

        yield Container(self.right_content, classes="split-pane", id="right-pane")


# Utility Widgets

class LoadingSpinner(Static):
    """Animated loading spinner."""

    DEFAULT_CSS = """
    LoadingSpinner {
        text-align: center;
        color: $accent;
        text-style: bold;
    }
    """

    def __init__(self, message: str = "Loading...", **kwargs):
        """Initialize loading spinner."""
        super().__init__(message, **kwargs)
        self._animation_timer: Timer | None = None
        self._spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self._spinner_index = 0
        self._message = message

    def on_mount(self) -> None:
        """Start spinner animation."""
        self._animation_timer = self.set_interval(0.1, self._animate)

    def on_unmount(self) -> None:
        """Stop spinner animation."""
        if self._animation_timer:
            self._animation_timer.stop()

    def _animate(self) -> None:
        """Animate the spinner."""
        char = self._spinner_chars[self._spinner_index]
        self.update(f"{char} {self._message}")
        self._spinner_index = (self._spinner_index + 1) % len(self._spinner_chars)


class Toast(Container):
    """Toast notification widget."""

    DEFAULT_CSS = """
    Toast {
        width: auto;
        height: auto;
        padding: 1 2;
        margin: 1;
        border-radius: 1;
        background: $surface;
        border: solid $primary;
    }
    
    Toast.success {
        border: solid $success;
        background: $success-lighten-3;
    }
    
    Toast.warning {
        border: solid $warning;
        background: $warning-lighten-3;
    }
    
    Toast.error {
        border: solid $error;
        background: $error-lighten-3;
    }
    
    .toast-message {
        color: $text;
    }
    
    .toast-close {
        color: $text-muted;
        text-style: bold;
    }
    """

    def __init__(
        self,
        message: str,
        toast_type: str = "info",
        duration: float | None = 3.0,
        closeable: bool = True,
        **kwargs
    ):
        """Initialize toast notification."""
        super().__init__(**kwargs)
        self.message = message
        self.toast_type = toast_type
        self.duration = duration
        self.closeable = closeable

        self.add_class(toast_type)

    def compose(self) -> ComposeResult:
        """Compose the toast."""
        with Horizontal():
            yield Static(self.message, classes="toast-message")

            if self.closeable:
                yield Button("×", id="close-toast", classes="toast-close")

    def on_mount(self) -> None:
        """Auto-close toast if duration is set."""
        if self.duration:
            self.set_timer(self.duration, self.remove)

    @on(Button.Pressed, "#close-toast")
    def close_toast(self) -> None:
        """Handle close button."""
        self.remove()
