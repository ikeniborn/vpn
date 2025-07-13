"""Virtual Scrolling Implementation for VPN Manager TUI.

This module provides high-performance virtual scrolling widgets that can handle
large datasets efficiently by only rendering visible items.
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Generic, Protocol, TypeVar

from rich.console import Console, RenderableType
from rich.table import Table
from rich.text import Text
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Vertical
from textual.geometry import Size
from textual.message import Message
from textual.scroll_view import ScrollView
from textual.widget import Widget
from textual.widgets import ScrollView, Static

console = Console()

T = TypeVar('T')


class VirtualDataSource(Protocol[T]):
    """Protocol for virtual scrolling data sources."""

    def get_item_count(self) -> int:
        """Get total number of items."""
        ...

    def get_item(self, index: int) -> T:
        """Get item at specific index."""
        ...

    def get_item_height(self, index: int) -> int:
        """Get height of item at specific index."""
        ...

    async def load_items(self, start: int, count: int) -> list[T]:
        """Load items in range asynchronously."""
        ...


@dataclass
class VirtualViewport:
    """Viewport for virtual scrolling."""
    start_index: int = 0
    end_index: int = 0
    scroll_offset: int = 0
    visible_height: int = 0
    total_height: int = 0
    item_height: int = 1

    @property
    def visible_count(self) -> int:
        """Number of visible items."""
        return max(0, self.end_index - self.start_index)

    def update_for_scroll(self, scroll_y: int, container_height: int, total_items: int) -> None:
        """Update viewport for scroll position."""
        self.scroll_offset = scroll_y
        self.visible_height = container_height

        # Calculate visible range with buffer
        buffer_items = 5  # Render extra items for smooth scrolling

        self.start_index = max(0, (scroll_y // self.item_height) - buffer_items)
        visible_item_count = (container_height // self.item_height) + (2 * buffer_items)
        self.end_index = min(total_items, self.start_index + visible_item_count)

        self.total_height = total_items * self.item_height


class VirtualListItem(Widget):
    """Individual item in virtual list."""

    def __init__(self,
                 data: Any,
                 index: int,
                 height: int = 1,
                 renderer: Callable[[Any, int], RenderableType] | None = None,
                 **kwargs):
        super().__init__(**kwargs)
        self.data = data
        self.index = index
        self.item_height = height
        self.renderer = renderer or self._default_renderer

    def _default_renderer(self, data: Any, index: int) -> RenderableType:
        """Default item renderer."""
        return Text(f"{index}: {data!s}")

    def render(self) -> RenderableType:
        """Render the list item."""
        return self.renderer(self.data, self.index)

    def get_content_height(self, container: Size, viewport: Size) -> int:
        """Get height of item content."""
        return self.item_height


class VirtualList(ScrollView, Generic[T]):
    """High-performance virtual scrolling list widget."""

    DEFAULT_CSS = """
    VirtualList {
        scrollbar-gutter: stable;
        overflow-y: auto;
        height: 100%;
    }
    
    VirtualList > .virtual-container {
        height: auto;
    }
    
    VirtualList VirtualListItem {
        width: 100%;
        margin: 0;
        padding: 0 1;
    }
    
    VirtualList VirtualListItem:hover {
        background: $surface-lighten-1;
    }
    
    VirtualList VirtualListItem.--selected {
        background: $primary;
        color: $text-on-primary;
    }
    """

    BINDINGS = [
        Binding("up", "cursor_up", "Move Up", show=False),
        Binding("down", "cursor_down", "Move Down", show=False),
        Binding("pageup", "page_up", "Page Up", show=False),
        Binding("pagedown", "page_down", "Page Down", show=False),
        Binding("home", "scroll_home", "Home", show=False),
        Binding("end", "scroll_end", "End", show=False),
        Binding("enter", "select_item", "Select", show=False),
    ]

    class ItemSelected(Message):
        """Message sent when item is selected."""

        def __init__(self, item: Any, index: int) -> None:
            super().__init__()
            self.item = item
            self.index = index

    class ItemActivated(Message):
        """Message sent when item is activated (double-click/enter)."""

        def __init__(self, item: Any, index: int) -> None:
            super().__init__()
            self.item = item
            self.index = index

    def __init__(self,
                 data_source: VirtualDataSource[T] | None = None,
                 item_height: int = 1,
                 item_renderer: Callable[[T, int], RenderableType] | None = None,
                 enable_selection: bool = True,
                 **kwargs):
        super().__init__(**kwargs)

        # Configuration
        self.data_source = data_source
        self.item_height = item_height
        self.item_renderer = item_renderer
        self.enable_selection = enable_selection

        # State
        self.viewport = VirtualViewport(item_height=item_height)
        self.rendered_items: dict[int, VirtualListItem] = {}
        self.selected_index: int | None = None
        self.cursor_index: int = 0

        # Container for items
        self.container = Vertical(classes="virtual-container")

        # Performance tracking
        self.render_count = 0
        self.last_render_time = 0.0

        # Loading state
        self.is_loading = False
        self.load_error: str | None = None

    def compose(self) -> ComposeResult:
        """Compose the virtual list."""
        yield self.container

    def on_mount(self) -> None:
        """Initialize virtual list when mounted."""
        self.refresh_viewport()

    def set_data_source(self, data_source: VirtualDataSource[T]) -> None:
        """Set new data source and refresh."""
        self.data_source = data_source
        self.selected_index = None
        self.cursor_index = 0
        self.refresh_viewport()

    def refresh_viewport(self) -> None:
        """Refresh the virtual viewport and rendered items."""
        if not self.data_source:
            return

        # Update viewport for current scroll position
        total_items = self.data_source.get_item_count()
        container_height = self.container_size.height if hasattr(self, 'container_size') else 20

        self.viewport.update_for_scroll(
            scroll_y=self.scroll_offset.y,
            container_height=container_height,
            total_items=total_items
        )

        # Update virtual scrollbar height
        self.virtual_size = Size(
            self.size.width,
            self.viewport.total_height
        )

        # Render visible items
        self._update_rendered_items()

    def _update_rendered_items(self) -> None:
        """Update the rendered items in viewport."""
        if not self.data_source:
            return

        # Remove items outside viewport
        to_remove = [
            index for index in self.rendered_items.keys()
            if index < self.viewport.start_index or index >= self.viewport.end_index
        ]

        for index in to_remove:
            item = self.rendered_items.pop(index)
            self.container.remove(item)

        # Add new items in viewport
        for index in range(self.viewport.start_index, self.viewport.end_index):
            if index not in self.rendered_items:
                try:
                    data = self.data_source.get_item(index)
                    item_height = self.data_source.get_item_height(index)

                    item = VirtualListItem(
                        data=data,
                        index=index,
                        height=item_height,
                        renderer=self.item_renderer
                    )

                    # Add selection styling
                    if self.enable_selection and index == self.selected_index:
                        item.add_class("--selected")

                    self.rendered_items[index] = item
                    self.container.mount(item)

                except Exception as e:
                    console.print(f"[red]Error rendering item {index}: {e}[/red]")

        # Update positions
        self._update_item_positions()

        self.render_count += 1

    def _update_item_positions(self) -> None:
        """Update positions of rendered items for smooth scrolling."""
        for index, item in self.rendered_items.items():
            # Calculate item position relative to viewport
            item_y = (index * self.item_height) - self.viewport.scroll_offset

            # Set item position (this would be done via CSS in real implementation)
            item.styles.margin = (item_y, 0, 0, 0)

    def on_scroll(self, event) -> None:
        """Handle scroll events."""
        self.refresh_viewport()

    def action_cursor_up(self) -> None:
        """Move cursor up."""
        if self.enable_selection and self.data_source:
            total_items = self.data_source.get_item_count()
            if total_items > 0:
                self.cursor_index = max(0, self.cursor_index - 1)
                self._update_selection()
                self._scroll_to_cursor()

    def action_cursor_down(self) -> None:
        """Move cursor down."""
        if self.enable_selection and self.data_source:
            total_items = self.data_source.get_item_count()
            if total_items > 0:
                self.cursor_index = min(total_items - 1, self.cursor_index + 1)
                self._update_selection()
                self._scroll_to_cursor()

    def action_page_up(self) -> None:
        """Move cursor up by page."""
        if self.enable_selection and self.data_source:
            page_size = self.viewport.visible_height // self.item_height
            self.cursor_index = max(0, self.cursor_index - page_size)
            self._update_selection()
            self._scroll_to_cursor()

    def action_page_down(self) -> None:
        """Move cursor down by page."""
        if self.enable_selection and self.data_source:
            total_items = self.data_source.get_item_count()
            page_size = self.viewport.visible_height // self.item_height
            self.cursor_index = min(total_items - 1, self.cursor_index + page_size)
            self._update_selection()
            self._scroll_to_cursor()

    def action_scroll_home(self) -> None:
        """Scroll to top."""
        if self.enable_selection:
            self.cursor_index = 0
            self._update_selection()
            self._scroll_to_cursor()

    def action_scroll_end(self) -> None:
        """Scroll to bottom."""
        if self.enable_selection and self.data_source:
            total_items = self.data_source.get_item_count()
            if total_items > 0:
                self.cursor_index = total_items - 1
                self._update_selection()
                self._scroll_to_cursor()

    def action_select_item(self) -> None:
        """Select/activate current item."""
        if self.selected_index is not None and self.data_source:
            try:
                item = self.data_source.get_item(self.selected_index)
                self.post_message(self.ItemActivated(item, self.selected_index))
            except Exception as e:
                console.print(f"[red]Error activating item: {e}[/red]")

    def _update_selection(self) -> None:
        """Update visual selection."""
        if not self.enable_selection:
            return

        old_selected = self.selected_index
        self.selected_index = self.cursor_index

        # Update item styles
        if old_selected is not None and old_selected in self.rendered_items:
            self.rendered_items[old_selected].remove_class("--selected")

        if self.selected_index is not None and self.selected_index in self.rendered_items:
            self.rendered_items[self.selected_index].add_class("--selected")

        # Send selection message
        if self.selected_index is not None and self.data_source:
            try:
                item = self.data_source.get_item(self.selected_index)
                self.post_message(self.ItemSelected(item, self.selected_index))
            except Exception:
                pass

    def _scroll_to_cursor(self) -> None:
        """Scroll to ensure cursor is visible."""
        if self.selected_index is None:
            return

        cursor_y = self.selected_index * self.item_height
        viewport_top = self.scroll_offset.y
        viewport_bottom = viewport_top + self.viewport.visible_height

        # Scroll if cursor is outside viewport
        if cursor_y < viewport_top:
            self.scroll_to(y=cursor_y)
        elif cursor_y + self.item_height > viewport_bottom:
            self.scroll_to(y=cursor_y - self.viewport.visible_height + self.item_height)

    def on_click(self, event) -> None:
        """Handle click events for selection."""
        if not self.enable_selection or not self.data_source:
            return

        # Calculate clicked item index
        relative_y = event.screen_offset.y - self.region.y + self.scroll_offset.y
        clicked_index = relative_y // self.item_height

        total_items = self.data_source.get_item_count()
        if 0 <= clicked_index < total_items:
            self.cursor_index = clicked_index
            self._update_selection()

    def get_visible_items(self) -> list[T]:
        """Get currently visible items."""
        if not self.data_source:
            return []

        items = []
        for index in range(self.viewport.start_index, self.viewport.end_index):
            try:
                items.append(self.data_source.get_item(index))
            except Exception:
                pass

        return items

    def scroll_to_item(self, index: int) -> None:
        """Scroll to specific item."""
        if self.data_source and 0 <= index < self.data_source.get_item_count():
            self.cursor_index = index
            self._update_selection()
            self._scroll_to_cursor()

    def get_performance_stats(self) -> dict[str, Any]:
        """Get performance statistics."""
        return {
            'render_count': self.render_count,
            'rendered_items': len(self.rendered_items),
            'viewport_size': self.viewport.visible_count,
            'total_items': self.data_source.get_item_count() if self.data_source else 0,
            'viewport_start': self.viewport.start_index,
            'viewport_end': self.viewport.end_index,
        }


class SimpleDataSource(Generic[T]):
    """Simple in-memory data source for virtual scrolling."""

    def __init__(self, items: list[T], item_height: int = 1):
        self.items = items
        self.item_height = item_height

    def get_item_count(self) -> int:
        return len(self.items)

    def get_item(self, index: int) -> T:
        if 0 <= index < len(self.items):
            return self.items[index]
        raise IndexError(f"Item index {index} out of range")

    def get_item_height(self, index: int) -> int:
        return self.item_height

    async def load_items(self, start: int, count: int) -> list[T]:
        end = min(start + count, len(self.items))
        return self.items[start:end]

    def add_item(self, item: T) -> None:
        """Add item to data source."""
        self.items.append(item)

    def remove_item(self, index: int) -> None:
        """Remove item from data source."""
        if 0 <= index < len(self.items):
            del self.items[index]

    def update_item(self, index: int, item: T) -> None:
        """Update item in data source."""
        if 0 <= index < len(self.items):
            self.items[index] = item


class AsyncDataSource(Generic[T]):
    """Asynchronous data source with lazy loading."""

    def __init__(self,
                 loader: Callable[[int, int], list[T]],
                 total_count: int,
                 item_height: int = 1,
                 cache_size: int = 1000):
        self.loader = loader
        self.total_count = total_count
        self.item_height = item_height
        self.cache_size = cache_size

        # Cache for loaded items
        self.cache: dict[int, T] = {}
        self.cache_order: list[int] = []

        # Loading state
        self.loading_ranges: set = set()

    def get_item_count(self) -> int:
        return self.total_count

    def get_item(self, index: int) -> T:
        if index in self.cache:
            return self.cache[index]

        # Return placeholder while loading
        return self._get_placeholder(index)

    def get_item_height(self, index: int) -> int:
        return self.item_height

    async def load_items(self, start: int, count: int) -> list[T]:
        """Load items asynchronously."""
        range_key = (start, count)

        if range_key in self.loading_ranges:
            return []  # Already loading

        self.loading_ranges.add(range_key)

        try:
            items = await self.loader(start, count)

            # Add to cache
            for i, item in enumerate(items):
                item_index = start + i
                self._add_to_cache(item_index, item)

            return items

        finally:
            self.loading_ranges.discard(range_key)

    def _get_placeholder(self, index: int) -> T:
        """Get placeholder for unloaded item."""
        # This should return a placeholder object of type T
        # Implementation depends on the specific type
        return f"Loading item {index}..."  # type: ignore

    def _add_to_cache(self, index: int, item: T) -> None:
        """Add item to cache with LRU eviction."""
        if index in self.cache:
            # Update existing item
            self.cache[index] = item
            return

        # Add new item
        self.cache[index] = item
        self.cache_order.append(index)

        # Evict old items if cache is full
        while len(self.cache) > self.cache_size:
            oldest_index = self.cache_order.pop(0)
            del self.cache[oldest_index]


class VirtualTable(VirtualList[dict[str, Any]]):
    """Virtual scrolling table widget."""

    DEFAULT_CSS = """
    VirtualTable {
        border: solid $primary;
    }
    
    VirtualTable .table-header {
        background: $primary;
        color: $text-on-primary;
        text-style: bold;
        dock: top;
        height: 1;
    }
    """

    def __init__(self,
                 columns: list[dict[str, Any]],
                 data_source: VirtualDataSource[dict[str, Any]] | None = None,
                 **kwargs):
        """Initialize virtual table.
        
        Args:
            columns: List of column definitions with 'key', 'title', 'width' keys
            data_source: Data source for table rows
        """
        self.columns = columns
        super().__init__(
            data_source=data_source,
            item_renderer=self._render_row,
            **kwargs
        )

        # Table header
        self.header = Static("", classes="table-header")

    def compose(self) -> ComposeResult:
        """Compose the virtual table."""
        yield self.header
        yield from super().compose()

    def on_mount(self) -> None:
        """Initialize table when mounted."""
        self._update_header()
        super().on_mount()

    def _update_header(self) -> None:
        """Update table header."""
        header_table = Table.grid()

        for column in self.columns:
            width = column.get('width', 10)
            header_table.add_column(min_width=width, max_width=width)

        header_table.add_row(*[col['title'] for col in self.columns])
        self.header.update(header_table)

    def _render_row(self, row_data: dict[str, Any], index: int) -> RenderableType:
        """Render table row."""
        row_table = Table.grid()

        for column in self.columns:
            width = column.get('width', 10)
            row_table.add_column(min_width=width, max_width=width)

        row_values = []
        for column in self.columns:
            key = column['key']
            value = row_data.get(key, '')
            formatter = column.get('formatter')

            if formatter:
                value = formatter(value)

            row_values.append(str(value)[:width])  # Truncate to column width

        row_table.add_row(*row_values)
        return row_table


# Example usage and testing

class DemoDataSource(SimpleDataSource[str]):
    """Demo data source for testing."""

    def __init__(self, count: int = 10000):
        items = [f"Item {i:05d} - Lorem ipsum dolor sit amet" for i in range(count)]
        super().__init__(items, item_height=1)


def demo_virtual_list():
    """Demo virtual list usage."""
    from textual.app import App

    class VirtualListDemo(App):
        def compose(self) -> ComposeResult:
            data_source = DemoDataSource(10000)
            virtual_list = VirtualList(data_source=data_source)
            yield Container(virtual_list)

        def on_virtual_list_item_selected(self, event: VirtualList.ItemSelected) -> None:
            self.title = f"Selected: {event.item}"

    return VirtualListDemo()


if __name__ == "__main__":
    # Run demo
    app = demo_virtual_list()
    app.run()
