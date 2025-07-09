"""
Enhanced log viewer widget with search and filtering capabilities.
"""

import asyncio
import re
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from rich.text import Text
from textual import on, work
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widget import Widget
from textual.widgets import Button, Input, Label, Log, Static

from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class LogEntry:
    """Represents a single log entry."""
    
    def __init__(self, timestamp: datetime, level: str, message: str, source: str = ""):
        self.timestamp = timestamp
        self.level = level.upper()
        self.message = message
        self.source = source
    
    def matches_filter(self, search_term: str, level_filter: Optional[str] = None) -> bool:
        """Check if this log entry matches the given filters."""
        if level_filter and self.level != level_filter.upper():
            return False
        
        if search_term:
            search_lower = search_term.lower()
            return (
                search_lower in self.message.lower() or
                search_lower in self.source.lower() or
                search_lower in self.level.lower()
            )
        
        return True
    
    def to_rich_text(self, highlight_term: Optional[str] = None) -> Text:
        """Convert log entry to Rich Text with syntax highlighting."""
        timestamp_str = self.timestamp.strftime("%H:%M:%S")
        
        # Color based on log level
        level_colors = {
            "DEBUG": "dim",
            "INFO": "blue",
            "WARNING": "yellow",
            "ERROR": "red",
            "CRITICAL": "bold red",
        }
        
        level_color = level_colors.get(self.level, "white")
        
        # Create formatted text
        text = Text()
        text.append(f"[{timestamp_str}] ", style="dim")
        text.append(f"{self.level:8}", style=level_color)
        
        if self.source:
            text.append(f" {self.source}: ", style="cyan")
        else:
            text.append(" ", style="cyan")
        
        # Highlight search terms
        message = self.message
        if highlight_term and highlight_term.lower() in message.lower():
            # Case-insensitive highlighting
            pattern = re.compile(re.escape(highlight_term), re.IGNORECASE)
            last_end = 0
            
            for match in pattern.finditer(message):
                # Add text before match
                if match.start() > last_end:
                    text.append(message[last_end:match.start()])
                
                # Add highlighted match
                text.append(message[match.start():match.end()], style="black on yellow")
                last_end = match.end()
            
            # Add remaining text
            if last_end < len(message):
                text.append(message[last_end:])
        else:
            text.append(message)
        
        return text


class LogViewer(Widget):
    """Enhanced log viewer widget with search and filtering."""
    
    DEFAULT_CSS = """
    LogViewer {
        height: 100%;
        border: solid green;
    }
    
    LogViewer .search-bar {
        height: 3;
        dock: top;
        border: solid blue;
    }
    
    LogViewer .controls {
        height: 3;
        dock: top;
        border: solid yellow;
    }
    
    LogViewer .log-content {
        height: 1fr;
        border: solid cyan;
    }
    
    LogViewer .log-stats {
        height: 3;
        dock: bottom;
        border: solid magenta;
    }
    """
    
    def __init__(self, log_file: Optional[Path] = None, **kwargs):
        super().__init__(**kwargs)
        self.log_file = log_file
        self.log_entries: List[LogEntry] = []
        self.filtered_entries: List[LogEntry] = []
        self.search_term = ""
        self.level_filter: Optional[str] = None
        self.auto_scroll = True
        self.max_entries = 1000
    
    def compose(self) -> ComposeResult:
        """Compose the log viewer widget."""
        with Vertical():
            # Search bar
            with Horizontal(classes="search-bar"):
                yield Label("Search:", shrink=True)
                yield Input(placeholder="Enter search term...", id="search_input")
                yield Button("Clear", id="clear_search", variant="primary")
            
            # Control buttons
            with Horizontal(classes="controls"):
                yield Button("🔍 All", id="filter_all", variant="default")
                yield Button("🐛 Debug", id="filter_debug", variant="default")
                yield Button("ℹ️ Info", id="filter_info", variant="default")
                yield Button("⚠️ Warning", id="filter_warning", variant="default")
                yield Button("❌ Error", id="filter_error", variant="default")
                yield Button("📜 Auto-scroll", id="toggle_scroll", variant="success")
                yield Button("🗑️ Clear", id="clear_logs", variant="error")
            
            # Log content area
            with VerticalScroll(classes="log-content"):
                yield Log(id="log_display", auto_scroll=True)
            
            # Statistics bar
            with Horizontal(classes="log-stats"):
                yield Label("", id="stats_label")
                yield Label("", id="entry_count")
    
    def on_mount(self) -> None:
        """Initialize the log viewer when mounted."""
        self.start_log_monitoring()
        self.update_stats()
    
    @work(exclusive=True)
    async def start_log_monitoring(self) -> None:
        """Start monitoring log files for new entries."""
        if self.log_file and self.log_file.exists():
            await self.load_log_file()
        
        # Start periodic refresh
        while True:
            await asyncio.sleep(1)
            if self.auto_scroll:
                await self.refresh_logs()
    
    async def load_log_file(self) -> None:
        """Load log entries from the log file."""
        try:
            if not self.log_file or not self.log_file.exists():
                return
            
            with open(self.log_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            new_entries = []
            for line in lines[-self.max_entries:]:
                entry = self.parse_log_line(line.strip())
                if entry:
                    new_entries.append(entry)
            
            self.log_entries = new_entries
            await self.apply_filters()
            
        except Exception as e:
            logger.error(f"Failed to load log file: {e}")
    
    def parse_log_line(self, line: str) -> Optional[LogEntry]:
        """Parse a single log line into a LogEntry."""
        if not line.strip():
            return None
        
        try:
            # Try to parse common log formats
            # Format: [timestamp] LEVEL source: message
            # or: timestamp LEVEL message
            
            # Pattern for structured logs
            pattern = r'^\[?(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?)\]?\s+(\w+)\s+(?:(\w+):\s+)?(.+)$'
            match = re.match(pattern, line)
            
            if match:
                timestamp_str, level, source, message = match.groups()
                
                # Parse timestamp
                for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S', '%H:%M:%S'):
                    try:
                        if len(timestamp_str) == 8:  # Just time
                            timestamp = datetime.now().replace(
                                hour=int(timestamp_str[:2]),
                                minute=int(timestamp_str[3:5]),
                                second=int(timestamp_str[6:8]),
                                microsecond=0
                            )
                        else:
                            timestamp = datetime.strptime(timestamp_str[:19], fmt)
                        break
                    except ValueError:
                        continue
                else:
                    timestamp = datetime.now()
                
                return LogEntry(timestamp, level, message, source or "")
            
            else:
                # Fallback: treat as simple message
                return LogEntry(
                    datetime.now(),
                    "INFO",
                    line,
                    "unknown"
                )
                
        except Exception as e:
            logger.debug(f"Failed to parse log line: {line} - {e}")
            return None
    
    async def refresh_logs(self) -> None:
        """Refresh log content."""
        if self.log_file:
            await self.load_log_file()
        else:
            # Add some sample entries for demo
            await self.add_sample_logs()
        
        self.update_stats()
    
    async def add_sample_logs(self) -> None:
        """Add sample log entries for demonstration."""
        sample_entries = [
            LogEntry(datetime.now(), "INFO", "VPN Manager started", "vpn.core"),
            LogEntry(datetime.now(), "DEBUG", "Loading configuration", "vpn.config"),
            LogEntry(datetime.now(), "INFO", "User alice connected", "vpn.users"),
            LogEntry(datetime.now(), "WARNING", "High memory usage detected", "vpn.monitor"),
            LogEntry(datetime.now(), "ERROR", "Failed to connect to Docker", "vpn.docker"),
        ]
        
        # Keep only recent entries
        self.log_entries.extend(sample_entries)
        if len(self.log_entries) > self.max_entries:
            self.log_entries = self.log_entries[-self.max_entries:]
        
        await self.apply_filters()
    
    async def apply_filters(self) -> None:
        """Apply current search and level filters."""
        self.filtered_entries = [
            entry for entry in self.log_entries
            if entry.matches_filter(self.search_term, self.level_filter)
        ]
        
        await self.update_display()
    
    async def update_display(self) -> None:
        """Update the log display with filtered entries."""
        log_widget = self.query_one("#log_display", Log)
        log_widget.clear()
        
        for entry in self.filtered_entries[-100:]:  # Show last 100 entries
            rich_text = entry.to_rich_text(self.search_term if self.search_term else None)
            log_widget.write(rich_text)
        
        if self.auto_scroll:
            # Scroll to bottom
            self.call_after_refresh(lambda: log_widget.scroll_end(animate=False))
    
    def update_stats(self) -> None:
        """Update the statistics display."""
        stats_label = self.query_one("#stats_label", Label)
        entry_count = self.query_one("#entry_count", Label)
        
        total = len(self.log_entries)
        filtered = len(self.filtered_entries)
        
        if self.search_term or self.level_filter:
            stats_label.update(f"Showing {filtered} of {total} entries")
        else:
            stats_label.update(f"Total entries: {total}")
        
        # Count by level
        level_counts = {}
        for entry in self.filtered_entries:
            level_counts[entry.level] = level_counts.get(entry.level, 0) + 1
        
        count_text = " | ".join(f"{level}: {count}" for level, count in level_counts.items())
        entry_count.update(count_text)
    
    @on(Input.Changed, "#search_input")
    async def on_search_changed(self, event: Input.Changed) -> None:
        """Handle search input changes."""
        self.search_term = event.value
        await self.apply_filters()
        self.update_stats()
    
    @on(Button.Pressed, "#clear_search")
    async def on_clear_search(self) -> None:
        """Clear the search input."""
        search_input = self.query_one("#search_input", Input)
        search_input.value = ""
        self.search_term = ""
        await self.apply_filters()
        self.update_stats()
    
    @on(Button.Pressed, "#filter_all")
    async def on_filter_all(self) -> None:
        """Show all log levels."""
        self.level_filter = None
        await self.apply_filters()
        self.update_stats()
        self._update_filter_buttons()
    
    @on(Button.Pressed, "#filter_debug")
    async def on_filter_debug(self) -> None:
        """Filter to debug level."""
        self.level_filter = "DEBUG"
        await self.apply_filters()
        self.update_stats()
        self._update_filter_buttons()
    
    @on(Button.Pressed, "#filter_info")
    async def on_filter_info(self) -> None:
        """Filter to info level."""
        self.level_filter = "INFO"
        await self.apply_filters()
        self.update_stats()
        self._update_filter_buttons()
    
    @on(Button.Pressed, "#filter_warning")
    async def on_filter_warning(self) -> None:
        """Filter to warning level."""
        self.level_filter = "WARNING"
        await self.apply_filters()
        self.update_stats()
        self._update_filter_buttons()
    
    @on(Button.Pressed, "#filter_error")
    async def on_filter_error(self) -> None:
        """Filter to error level."""
        self.level_filter = "ERROR"
        await self.apply_filters()
        self.update_stats()
        self._update_filter_buttons()
    
    @on(Button.Pressed, "#toggle_scroll")
    def on_toggle_scroll(self) -> None:
        """Toggle auto-scroll."""
        self.auto_scroll = not self.auto_scroll
        button = self.query_one("#toggle_scroll", Button)
        if self.auto_scroll:
            button.label = "📜 Auto-scroll"
            button.variant = "success"
        else:
            button.label = "⏸️ Paused"
            button.variant = "warning"
    
    @on(Button.Pressed, "#clear_logs")
    async def on_clear_logs(self) -> None:
        """Clear all log entries."""
        self.log_entries.clear()
        self.filtered_entries.clear()
        await self.update_display()
        self.update_stats()
    
    def _update_filter_buttons(self) -> None:
        """Update the visual state of filter buttons."""
        buttons = {
            "filter_all": None,
            "filter_debug": "DEBUG",
            "filter_info": "INFO",
            "filter_warning": "WARNING",
            "filter_error": "ERROR",
        }
        
        for button_id, level in buttons.items():
            button = self.query_one(f"#{button_id}", Button)
            if self.level_filter == level:
                button.variant = "primary"
            else:
                button.variant = "default"