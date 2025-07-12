"""
Lazy loading components for Textual TUI screens.

This module provides lazy loading functionality for heavy TUI screens using Textual 0.47+ features.
"""

import asyncio
from abc import ABC, abstractmethod
from typing import Any, Dict, Optional, Callable, List, Union
from dataclasses import dataclass
from enum import Enum

from textual import on
from textual.app import ComposeResult
from textual.containers import Container, Vertical, Horizontal
from textual.reactive import reactive
from textual.timer import Timer
from textual.widgets import Static, ProgressBar, Spinner, Button
from textual.screen import Screen
from textual.worker import Worker, WorkerState


class LoadingState(Enum):
    """Loading states for lazy components."""
    NOT_STARTED = "not_started"
    LOADING = "loading"
    LOADED = "loaded"
    ERROR = "error"
    REFRESHING = "refreshing"


@dataclass
class LoadingConfig:
    """Configuration for lazy loading behavior."""
    
    # Loading behavior
    auto_load: bool = True  # Auto-load when component is mounted
    show_spinner: bool = True  # Show loading spinner
    show_progress: bool = False  # Show progress bar
    timeout_seconds: Optional[int] = 30  # Loading timeout
    
    # Performance settings
    debounce_ms: int = 300  # Debounce refresh requests
    cache_duration: int = 60  # Cache duration in seconds
    virtual_scrolling: bool = False  # Enable virtual scrolling for large lists
    
    # UI settings
    loading_message: str = "Loading..."
    error_retry_button: bool = True
    placeholder_height: int = 10


class LazyLoadableWidget(Container, ABC):
    """Base class for widgets that support lazy loading."""
    
    state = reactive(LoadingState.NOT_STARTED)
    
    def __init__(
        self, 
        loading_config: Optional[LoadingConfig] = None,
        id: Optional[str] = None,
        classes: Optional[str] = None,
        **kwargs
    ):
        """Initialize lazy loadable widget."""
        super().__init__(id=id, classes=classes, **kwargs)
        self.loading_config = loading_config or LoadingConfig()
        self._last_refresh = 0
        self._cached_data: Optional[Any] = None
        self._loader_worker: Optional[Worker] = None
        
    def compose(self) -> ComposeResult:
        """Compose the loading interface."""
        if self.loading_config.auto_load:
            yield from self._compose_loading()
        else:
            yield from self._compose_placeholder()
    
    def _compose_loading(self) -> ComposeResult:
        """Compose loading interface."""
        with Vertical(classes="lazy-loading-container"):
            if self.loading_config.show_spinner:
                yield Spinner(classes="lazy-spinner")
            
            if self.loading_config.show_progress:
                yield ProgressBar(classes="lazy-progress")
            
            yield Static(
                self.loading_config.loading_message, 
                classes="lazy-loading-message"
            )
    
    def _compose_placeholder(self) -> ComposeResult:
        """Compose placeholder interface."""
        with Vertical(classes="lazy-placeholder"):
            yield Static(
                f"Click to load {self.__class__.__name__}",
                classes="lazy-placeholder-text"
            )
            yield Button("Load", id="load-button", classes="lazy-load-button")
    
    def _compose_error(self, error_message: str) -> ComposeResult:
        """Compose error interface."""
        with Vertical(classes="lazy-error-container"):
            yield Static("❌ Loading Failed", classes="lazy-error-title")
            yield Static(error_message, classes="lazy-error-message")
            
            if self.loading_config.error_retry_button:
                yield Button("Retry", id="retry-button", classes="lazy-retry-button")
    
    @abstractmethod
    async def load_data(self) -> Any:
        """Load data for the widget. Must be implemented by subclasses."""
        pass
    
    @abstractmethod
    def render_content(self, data: Any) -> ComposeResult:
        """Render the loaded content. Must be implemented by subclasses."""
        pass
    
    def on_mount(self) -> None:
        """Called when widget is mounted."""
        if self.loading_config.auto_load:
            self.call_later(self.load)
    
    @on(Button.Pressed, "#load-button")
    async def handle_load_button(self) -> None:
        """Handle load button press."""
        await self.load()
    
    @on(Button.Pressed, "#retry-button")
    async def handle_retry_button(self) -> None:
        """Handle retry button press."""
        await self.reload()
    
    async def load(self) -> None:
        """Load the widget content."""
        if self.state == LoadingState.LOADING:
            return  # Already loading
        
        self.state = LoadingState.LOADING
        await self._update_loading_ui()
        
        try:
            # Start loading worker
            self._loader_worker = self.run_worker(
                self._load_with_timeout(),
                exclusive=True,
                name=f"loader-{self.id}"
            )
            
        except Exception as e:
            await self._handle_loading_error(str(e))
    
    async def reload(self) -> None:
        """Reload the widget content."""
        # Check debounce
        import time
        current_time = time.time()
        if (current_time - self._last_refresh) * 1000 < self.loading_config.debounce_ms:
            return
        
        self._last_refresh = current_time
        
        # Clear cache and reload
        self._cached_data = None
        self.state = LoadingState.REFRESHING
        await self.load()
    
    async def _load_with_timeout(self) -> Any:
        """Load data with timeout handling."""
        if self.loading_config.timeout_seconds:
            return await asyncio.wait_for(
                self.load_data(),
                timeout=self.loading_config.timeout_seconds
            )
        else:
            return await self.load_data()
    
    async def _update_loading_ui(self) -> None:
        """Update UI for loading state."""
        # Clear current content
        await self.remove_children()
        
        # Show loading interface
        await self.mount(*list(self._compose_loading()))
    
    async def _update_content_ui(self, data: Any) -> None:
        """Update UI with loaded content."""
        # Cache the data
        self._cached_data = data
        
        # Clear loading interface
        await self.remove_children()
        
        # Show content
        await self.mount(*list(self.render_content(data)))
    
    async def _update_error_ui(self, error_message: str) -> None:
        """Update UI for error state."""
        # Clear current content
        await self.remove_children()
        
        # Show error interface
        await self.mount(*list(self._compose_error(error_message)))
    
    async def _handle_loading_error(self, error_message: str) -> None:
        """Handle loading errors."""
        self.state = LoadingState.ERROR
        await self._update_error_ui(error_message)
        
        # Log error
        self.log.error(f"Lazy loading failed for {self.__class__.__name__}: {error_message}")
    
    def on_worker_state_changed(self, event: Worker.StateChanged) -> None:
        """Handle worker state changes."""
        if event.worker.name != f"loader-{self.id}":
            return
        
        if event.state == WorkerState.SUCCESS:
            # Loading succeeded
            asyncio.create_task(self._handle_loading_success(event.worker.result))
        elif event.state == WorkerState.ERROR:
            # Loading failed
            error_msg = str(event.worker.error) if event.worker.error else "Unknown error"
            asyncio.create_task(self._handle_loading_error(error_msg))
        elif event.state == WorkerState.CANCELLED:
            # Loading cancelled
            self.state = LoadingState.NOT_STARTED
    
    async def _handle_loading_success(self, data: Any) -> None:
        """Handle successful loading."""
        self.state = LoadingState.LOADED
        await self._update_content_ui(data)
    
    def watch_state(self, state: LoadingState) -> None:
        """Watch state changes."""
        # Update CSS classes based on state
        self.remove_class("loading", "loaded", "error", "refreshing")
        self.add_class(state.value.replace("_", "-"))


class VirtualScrollingList(LazyLoadableWidget):
    """Virtual scrolling list for large datasets."""
    
    def __init__(
        self,
        item_height: int = 3,
        visible_items: int = 10,
        total_items: int = 0,
        loading_config: Optional[LoadingConfig] = None,
        **kwargs
    ):
        """Initialize virtual scrolling list."""
        loading_config = loading_config or LoadingConfig(virtual_scrolling=True)
        super().__init__(loading_config=loading_config, **kwargs)
        
        self.item_height = item_height
        self.visible_items = visible_items
        self.total_items = total_items
        self.scroll_offset = 0
        self._item_cache: Dict[int, Any] = {}
    
    async def load_data(self) -> List[Any]:
        """Load all data (can be overridden for partial loading)."""
        # Default implementation - subclasses should override
        return []
    
    async def load_item_range(self, start: int, count: int) -> List[Any]:
        """Load a specific range of items."""
        # Default implementation loads all data and slices
        # Subclasses should override for true virtual scrolling
        all_data = await self.load_data()
        return all_data[start:start + count]
    
    def render_content(self, data: List[Any]) -> ComposeResult:
        """Render the virtual scrolling content."""
        with Vertical(classes="virtual-scroll-container"):
            # Render visible items
            start_idx = self.scroll_offset
            end_idx = min(start_idx + self.visible_items, len(data))
            
            for i in range(start_idx, end_idx):
                if i < len(data):
                    yield from self.render_item(i, data[i])
    
    def render_item(self, index: int, item: Any) -> ComposeResult:
        """Render a single item. Should be overridden by subclasses."""
        yield Static(f"Item {index}: {str(item)}", classes="virtual-item")


class LazyScreen(Screen):
    """Screen with lazy loading capabilities."""
    
    DEFAULT_CSS = """
    .lazy-loading-container {
        align: center middle;
        height: 100%;
    }
    
    .lazy-spinner {
        margin: 1;
    }
    
    .lazy-loading-message {
        text-align: center;
        margin: 1;
        text-style: italic;
    }
    
    .lazy-placeholder {
        align: center middle;
        height: 100%;
    }
    
    .lazy-placeholder-text {
        text-align: center;
        margin: 1;
        color: $text-muted;
    }
    
    .lazy-load-button {
        margin: 1;
    }
    
    .lazy-error-container {
        align: center middle;
        height: 100%;
    }
    
    .lazy-error-title {
        text-align: center;
        margin: 1;
        color: $error;
        text-style: bold;
    }
    
    .lazy-error-message {
        text-align: center;
        margin: 1;
        color: $text-muted;
    }
    
    .lazy-retry-button {
        margin: 1;
    }
    
    .virtual-scroll-container {
        height: 100%;
        overflow-y: auto;
    }
    
    .virtual-item {
        height: 3;
        margin: 0 1;
        padding: 1;
        border: solid $primary-lighten-1;
    }
    
    /* State-based styling */
    .loading {
        opacity: 0.8;
    }
    
    .error {
        border: solid $error;
    }
    
    .refreshing .lazy-spinner {
        color: $accent;
    }
    """
    
    def __init__(
        self,
        sections: Optional[List[Dict[str, Any]]] = None,
        loading_config: Optional[LoadingConfig] = None,
        **kwargs
    ):
        """Initialize lazy screen."""
        super().__init__(**kwargs)
        self.sections = sections or []
        self.default_loading_config = loading_config or LoadingConfig()
        self._section_widgets: Dict[str, LazyLoadableWidget] = {}
    
    def add_lazy_section(
        self,
        section_id: str,
        widget_class: type,
        loading_config: Optional[LoadingConfig] = None,
        **widget_kwargs
    ) -> None:
        """Add a lazy-loaded section to the screen."""
        config = loading_config or self.default_loading_config
        widget = widget_class(loading_config=config, id=section_id, **widget_kwargs)
        self._section_widgets[section_id] = widget
    
    def get_section(self, section_id: str) -> Optional[LazyLoadableWidget]:
        """Get a section widget by ID."""
        return self._section_widgets.get(section_id)
    
    async def reload_section(self, section_id: str) -> None:
        """Reload a specific section."""
        widget = self.get_section(section_id)
        if widget:
            await widget.reload()
    
    async def reload_all_sections(self) -> None:
        """Reload all sections."""
        for widget in self._section_widgets.values():
            await widget.reload()


# Utility function for creating lazy loading configurations
def create_loading_config(
    **kwargs
) -> LoadingConfig:
    """Create a loading configuration with sensible defaults."""
    return LoadingConfig(**kwargs)