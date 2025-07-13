"""Stats card widget for displaying metrics.
"""

from textual.app import ComposeResult
from textual.containers import Vertical
from textual.css.query import NoMatches
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import Static


class StatsCard(Widget):
    """Card widget for displaying statistics."""

    DEFAULT_CSS = """
    StatsCard {
        height: 7;
        padding: 1 2;
        background: $boost;
        border: solid $primary-background;
    }
    
    StatsCard:hover {
        border: solid $primary;
    }
    
    StatsCard .stats-title {
        text-style: bold;
        color: $text-muted;
    }
    
    StatsCard .stats-value {
        text-style: bold;
        color: $primary;
        text-align: center;
        content-align: center middle;
        height: 3;
    }
    """

    value = reactive("0")

    def __init__(
        self,
        title: str,
        value: str = "0",
        id: str = None,
        classes: str = None
    ):
        """Initialize stats card."""
        super().__init__(id=id, classes=classes)
        self.title = title
        self.value = value

    def compose(self) -> ComposeResult:
        """Create card layout."""
        with Vertical():
            yield Static(self.title, classes="stats-title")
            yield Static(self.value, classes="stats-value")

    def watch_value(self, new_value: str) -> None:
        """Update displayed value."""
        try:
            value_widget = self.query_one(".stats-value", Static)
            value_widget.update(new_value)
        except NoMatches:
            pass  # Widget not mounted yet
