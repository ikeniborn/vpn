"""
Data Pagination System for VPN Manager TUI.

This module provides efficient pagination widgets and data management
for handling large datasets with smooth navigation and performance optimization.
"""

import asyncio
import math
from typing import Any, Dict, List, Optional, Callable, Union, Generic, TypeVar, Protocol
from dataclasses import dataclass, field
from abc import ABC, abstractmethod
from enum import Enum

from textual.app import ComposeResult
from textual.widget import Widget
from textual.widgets import Button, Static, Input, Select, LoadingIndicator
from textual.containers import Container, Horizontal, Vertical
from textual.reactive import reactive, var
from textual.message import Message
from textual.binding import Binding
from textual.events import Click

from rich.console import Console, RenderableType
from rich.text import Text
from rich.table import Table
from rich.panel import Panel
from rich.align import Align

console = Console()

T = TypeVar('T')


class SortOrder(Enum):
    """Sort order enumeration."""
    ASC = "asc"
    DESC = "desc"


@dataclass
class SortConfig:
    """Sort configuration."""
    field: str
    order: SortOrder = SortOrder.ASC


@dataclass
class FilterConfig:
    """Filter configuration."""
    field: str
    value: Any
    operator: str = "eq"  # eq, ne, gt, lt, gte, lte, contains, startswith, endswith


@dataclass
class PageInfo:
    """Pagination information."""
    current_page: int = 1
    page_size: int = 20
    total_items: int = 0
    total_pages: int = 0
    has_next: bool = False
    has_previous: bool = False
    start_index: int = 0
    end_index: int = 0
    
    def update(self, current_page: int, page_size: int, total_items: int) -> None:
        """Update pagination info."""
        self.current_page = max(1, current_page)
        self.page_size = max(1, page_size)
        self.total_items = max(0, total_items)
        self.total_pages = math.ceil(total_items / page_size) if page_size > 0 else 0
        self.has_next = self.current_page < self.total_pages
        self.has_previous = self.current_page > 1
        self.start_index = (self.current_page - 1) * page_size
        self.end_index = min(self.start_index + page_size, total_items)


@dataclass
class PageRequest:
    """Page request with filtering and sorting."""
    page: int = 1
    page_size: int = 20
    sort_configs: List[SortConfig] = field(default_factory=list)
    filter_configs: List[FilterConfig] = field(default_factory=list)
    search_query: str = ""


@dataclass
class PageResult(Generic[T]):
    """Page result with data and metadata."""
    items: List[T]
    page_info: PageInfo
    load_time: float = 0.0
    error: Optional[str] = None


class PaginatedDataSource(Protocol[T]):
    """Protocol for paginated data sources."""
    
    async def get_page(self, request: PageRequest) -> PageResult[T]:
        """Get page of data based on request."""
        ...
    
    async def get_total_count(self, filters: List[FilterConfig] = None, search: str = "") -> int:
        """Get total item count with optional filtering."""
        ...
    
    def get_sort_fields(self) -> List[str]:
        """Get available sort fields."""
        ...
    
    def get_filter_fields(self) -> List[Dict[str, Any]]:
        """Get available filter fields with metadata."""
        ...


class InMemoryDataSource(Generic[T]):
    """In-memory paginated data source."""
    
    def __init__(self, 
                 items: List[T],
                 sort_fields: Optional[List[str]] = None,
                 filter_fields: Optional[List[Dict[str, Any]]] = None):
        self.items = items
        self.sort_fields = sort_fields or []
        self.filter_fields = filter_fields or []
    
    async def get_page(self, request: PageRequest) -> PageResult[T]:
        """Get page of data."""
        import time
        start_time = time.perf_counter()
        
        try:
            # Apply filters
            filtered_items = self._apply_filters(self.items, request.filter_configs, request.search_query)
            
            # Apply sorting
            sorted_items = self._apply_sorting(filtered_items, request.sort_configs)
            
            # Calculate pagination
            total_items = len(sorted_items)
            page_info = PageInfo()
            page_info.update(request.page, request.page_size, total_items)
            
            # Extract page items
            start_idx = page_info.start_index
            end_idx = page_info.end_index
            page_items = sorted_items[start_idx:end_idx]
            
            load_time = time.perf_counter() - start_time
            
            return PageResult(
                items=page_items,
                page_info=page_info,
                load_time=load_time
            )
            
        except Exception as e:
            load_time = time.perf_counter() - start_time
            return PageResult(
                items=[],
                page_info=PageInfo(),
                load_time=load_time,
                error=str(e)
            )
    
    async def get_total_count(self, filters: List[FilterConfig] = None, search: str = "") -> int:
        """Get total count with filtering."""
        filters = filters or []
        filtered_items = self._apply_filters(self.items, filters, search)
        return len(filtered_items)
    
    def get_sort_fields(self) -> List[str]:
        """Get available sort fields."""
        return self.sort_fields
    
    def get_filter_fields(self) -> List[Dict[str, Any]]:
        """Get available filter fields."""
        return self.filter_fields
    
    def _apply_filters(self, items: List[T], filters: List[FilterConfig], search: str) -> List[T]:
        """Apply filters to items."""
        filtered = items
        
        # Apply search
        if search:
            search_lower = search.lower()
            filtered = [
                item for item in filtered
                if search_lower in str(item).lower()
            ]
        
        # Apply field filters
        for filter_config in filters:
            filtered = self._apply_single_filter(filtered, filter_config)
        
        return filtered
    
    def _apply_single_filter(self, items: List[T], filter_config: FilterConfig) -> List[T]:
        """Apply single filter to items."""
        field = filter_config.field
        value = filter_config.value
        operator = filter_config.operator
        
        def matches(item: T) -> bool:
            try:
                if hasattr(item, field):
                    item_value = getattr(item, field)
                elif isinstance(item, dict):
                    item_value = item.get(field)
                else:
                    return False
                
                if operator == "eq":
                    return item_value == value
                elif operator == "ne":
                    return item_value != value
                elif operator == "gt":
                    return item_value > value
                elif operator == "lt":
                    return item_value < value
                elif operator == "gte":
                    return item_value >= value
                elif operator == "lte":
                    return item_value <= value
                elif operator == "contains":
                    return str(value).lower() in str(item_value).lower()
                elif operator == "startswith":
                    return str(item_value).lower().startswith(str(value).lower())
                elif operator == "endswith":
                    return str(item_value).lower().endswith(str(value).lower())
                else:
                    return True
                    
            except Exception:
                return False
        
        return [item for item in items if matches(item)]
    
    def _apply_sorting(self, items: List[T], sort_configs: List[SortConfig]) -> List[T]:
        """Apply sorting to items."""
        if not sort_configs:
            return items
        
        def sort_key(item: T):
            keys = []
            for sort_config in sort_configs:
                field = sort_config.field
                
                try:
                    if hasattr(item, field):
                        value = getattr(item, field)
                    elif isinstance(item, dict):
                        value = item.get(field)
                    else:
                        value = ""
                    
                    # Handle reverse sorting
                    if sort_config.order == SortOrder.DESC:
                        if isinstance(value, (int, float)):
                            value = -value
                        elif isinstance(value, str):
                            # For strings, we'll sort in reverse later
                            pass
                    
                    keys.append(value)
                    
                except Exception:
                    keys.append("")
            
            return keys
        
        # Sort items
        sorted_items = sorted(items, key=sort_key)
        
        # Handle string reverse sorting
        if sort_configs and sort_configs[0].order == SortOrder.DESC:
            first_field = sort_configs[0].field
            try:
                # Check if first field is string
                if items and hasattr(items[0], first_field):
                    first_value = getattr(items[0], first_field)
                elif items and isinstance(items[0], dict):
                    first_value = items[0].get(first_field)
                else:
                    first_value = ""
                
                if isinstance(first_value, str):
                    sorted_items.reverse()
            except Exception:
                pass
        
        return sorted_items


class PaginationControls(Widget):
    """Pagination control widget."""
    
    DEFAULT_CSS = """
    PaginationControls {
        height: 3;
        background: $surface;
        border: solid $primary;
    }
    
    PaginationControls Horizontal {
        align: center middle;
        height: 100%;
    }
    
    PaginationControls Button {
        margin: 0 1;
        min-width: 8;
    }
    
    PaginationControls Static {
        margin: 0 2;
        text-align: center;
    }
    
    PaginationControls Input {
        width: 6;
        margin: 0 1;
    }
    """
    
    class PageChanged(Message):
        """Message sent when page changes."""
        
        def __init__(self, page: int) -> None:
            super().__init__()
            self.page = page
    
    class PageSizeChanged(Message):
        """Message sent when page size changes."""
        
        def __init__(self, page_size: int) -> None:
            super().__init__()
            self.page_size = page_size
    
    def __init__(self, page_info: Optional[PageInfo] = None, **kwargs):
        super().__init__(**kwargs)
        self.page_info = page_info or PageInfo()
        
        # Controls
        self.first_button = Button("⏮ First", id="first", variant="default")
        self.prev_button = Button("◀ Prev", id="prev", variant="default")
        self.page_input = Input(value=str(self.page_info.current_page), id="page_input")
        self.next_button = Button("Next ▶", id="next", variant="default")
        self.last_button = Button("Last ⏭", id="last", variant="default")
        
        # Page size selector
        self.page_size_select = Select([
            ("10", 10),
            ("20", 20),
            ("50", 50),
            ("100", 100),
            ("200", 200)
        ], value=self.page_info.page_size, id="page_size")
        
        # Info display
        self.info_display = Static("", id="page_info")
    
    def compose(self) -> ComposeResult:
        """Compose pagination controls."""
        with Horizontal():
            yield self.first_button
            yield self.prev_button
            yield Static("Page:")
            yield self.page_input
            yield Static(f"of {self.page_info.total_pages}")
            yield self.next_button
            yield self.last_button
            yield Static("Show:")
            yield self.page_size_select
            yield self.info_display
    
    def update_page_info(self, page_info: PageInfo) -> None:
        """Update pagination information."""
        self.page_info = page_info
        
        # Update controls
        self.first_button.disabled = not page_info.has_previous
        self.prev_button.disabled = not page_info.has_previous
        self.next_button.disabled = not page_info.has_next
        self.last_button.disabled = not page_info.has_next
        
        # Update page input
        self.page_input.value = str(page_info.current_page)
        
        # Update page size
        self.page_size_select.value = page_info.page_size
        
        # Update info display
        if page_info.total_items > 0:
            info_text = f"Showing {page_info.start_index + 1}-{page_info.end_index} of {page_info.total_items}"
        else:
            info_text = "No items"
        
        self.info_display.update(info_text)
        
        # Update page count in label
        for child in self.children:
            if isinstance(child, Static) and "of" in str(child.renderable):
                child.update(f"of {page_info.total_pages}")
                break
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        button_id = event.button.id
        
        if button_id == "first":
            self.post_message(self.PageChanged(1))
        elif button_id == "prev":
            new_page = max(1, self.page_info.current_page - 1)
            self.post_message(self.PageChanged(new_page))
        elif button_id == "next":
            new_page = min(self.page_info.total_pages, self.page_info.current_page + 1)
            self.post_message(self.PageChanged(new_page))
        elif button_id == "last":
            self.post_message(self.PageChanged(self.page_info.total_pages))
    
    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle page input submission."""
        if event.input.id == "page_input":
            try:
                page = int(event.value)
                if 1 <= page <= self.page_info.total_pages:
                    self.post_message(self.PageChanged(page))
                else:
                    # Reset to current page
                    event.input.value = str(self.page_info.current_page)
            except ValueError:
                # Reset to current page
                event.input.value = str(self.page_info.current_page)
    
    def on_select_changed(self, event: Select.Changed) -> None:
        """Handle page size selection."""
        if event.select.id == "page_size":
            self.post_message(self.PageSizeChanged(event.value))


class SearchAndFilter(Widget):
    """Search and filter controls widget."""
    
    DEFAULT_CSS = """
    SearchAndFilter {
        height: 4;
        background: $surface;
        border: solid $accent;
    }
    
    SearchAndFilter Horizontal {
        height: 100%;
        align: left middle;
    }
    
    SearchAndFilter Input {
        width: 1fr;
        margin: 0 1;
    }
    
    SearchAndFilter Button {
        margin: 0 1;
    }
    
    SearchAndFilter Select {
        width: 15;
        margin: 0 1;
    }
    """
    
    class SearchChanged(Message):
        """Message sent when search query changes."""
        
        def __init__(self, query: str) -> None:
            super().__init__()
            self.query = query
    
    class SortChanged(Message):
        """Message sent when sort changes."""
        
        def __init__(self, field: str, order: SortOrder) -> None:
            super().__init__()
            self.field = field
            self.order = order
    
    class FilterChanged(Message):
        """Message sent when filter changes."""
        
        def __init__(self, filters: List[FilterConfig]) -> None:
            super().__init__()
            self.filters = filters
    
    def __init__(self, 
                 sort_fields: Optional[List[str]] = None,
                 filter_fields: Optional[List[Dict[str, Any]]] = None,
                 **kwargs):
        super().__init__(**kwargs)
        self.sort_fields = sort_fields or []
        self.filter_fields = filter_fields or []
        
        # Controls
        self.search_input = Input(placeholder="Search...", id="search")
        self.sort_select = Select([
            (field, field) for field in self.sort_fields
        ], id="sort_field", allow_blank=True)
        self.sort_order_select = Select([
            ("Ascending", SortOrder.ASC),
            ("Descending", SortOrder.DESC)
        ], value=SortOrder.ASC, id="sort_order")
        self.clear_button = Button("Clear", id="clear", variant="default")
    
    def compose(self) -> ComposeResult:
        """Compose search and filter controls."""
        with Horizontal():
            yield Static("Search:")
            yield self.search_input
            yield Static("Sort by:")
            yield self.sort_select
            yield self.sort_order_select
            yield self.clear_button
    
    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle search input changes."""
        if event.input.id == "search":
            self.post_message(self.SearchChanged(event.value))
    
    def on_select_changed(self, event: Select.Changed) -> None:
        """Handle sort selection changes."""
        if event.select.id in ("sort_field", "sort_order"):
            field = self.sort_select.value
            order = self.sort_order_select.value
            
            if field:
                self.post_message(self.SortChanged(field, order))
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "clear":
            self.search_input.value = ""
            self.sort_select.value = self.sort_select.BLANK
            self.post_message(self.SearchChanged(""))


class PaginatedTable(Widget):
    """Paginated table widget combining data display with controls."""
    
    DEFAULT_CSS = """
    PaginatedTable {
        height: 100%;
    }
    
    PaginatedTable .table-container {
        height: 1fr;
        overflow-y: auto;
        border: solid $primary;
    }
    
    PaginatedTable .table-data {
        width: 100%;
        height: auto;
    }
    
    PaginatedTable .loading {
        height: 100%;
        text-align: center;
        vertical-align: middle;
    }
    
    PaginatedTable .error {
        height: 100%;
        text-align: center;
        vertical-align: middle;
        color: $error;
    }
    """
    
    class ItemSelected(Message):
        """Message sent when item is selected."""
        
        def __init__(self, item: Any, index: int) -> None:
            super().__init__()
            self.item = item
            self.index = index
    
    def __init__(self,
                 data_source: PaginatedDataSource[T],
                 columns: List[Dict[str, Any]],
                 page_size: int = 20,
                 item_renderer: Optional[Callable[[T, int], RenderableType]] = None,
                 **kwargs):
        super().__init__(**kwargs)
        
        self.data_source = data_source
        self.columns = columns
        self.item_renderer = item_renderer or self._default_item_renderer
        
        # State
        self.current_request = PageRequest(page_size=page_size)
        self.current_result: Optional[PageResult[T]] = None
        self.is_loading = False
        
        # Components
        self.search_filter = SearchAndFilter(
            sort_fields=data_source.get_sort_fields(),
            filter_fields=data_source.get_filter_fields()
        )
        self.pagination_controls = PaginationControls()
        
        # Data display
        self.data_container = Container(classes="table-container")
        self.data_display = Static("", classes="table-data")
        self.loading_display = LoadingIndicator()
        self.error_display = Static("", classes="error")
        
        # Selected item tracking
        self.selected_index: Optional[int] = None
    
    def compose(self) -> ComposeResult:
        """Compose paginated table."""
        yield self.search_filter
        with Container(classes="table-container"):
            yield self.data_display
            yield self.loading_display
            yield self.error_display
        yield self.pagination_controls
    
    def on_mount(self) -> None:
        """Initialize table when mounted."""
        self.refresh_data()
    
    async def refresh_data(self) -> None:
        """Refresh table data."""
        if self.is_loading:
            return
        
        self.is_loading = True
        self._show_loading()
        
        try:
            # Get data from source
            result = await self.data_source.get_page(self.current_request)
            self.current_result = result
            
            if result.error:
                self._show_error(result.error)
            else:
                self._show_data(result)
                self.pagination_controls.update_page_info(result.page_info)
            
        except Exception as e:
            self._show_error(str(e))
        
        finally:
            self.is_loading = False
    
    def _show_loading(self) -> None:
        """Show loading state."""
        self.data_display.visible = False
        self.error_display.visible = False
        self.loading_display.visible = True
    
    def _show_error(self, error: str) -> None:
        """Show error state."""
        self.data_display.visible = False
        self.loading_display.visible = False
        self.error_display.update(f"Error: {error}")
        self.error_display.visible = True
    
    def _show_data(self, result: PageResult[T]) -> None:
        """Show data."""
        self.loading_display.visible = False
        self.error_display.visible = False
        
        # Render data
        rendered = self._render_data(result.items)
        self.data_display.update(rendered)
        self.data_display.visible = True
    
    def _render_data(self, items: List[T]) -> RenderableType:
        """Render data items."""
        if not items:
            return Text("No data available", style="dim")
        
        # Create table
        table = Table()
        
        # Add columns
        for column in self.columns:
            table.add_column(
                column['title'],
                width=column.get('width'),
                overflow=column.get('overflow', 'ellipsis')
            )
        
        # Add rows
        for i, item in enumerate(items):
            if isinstance(item, dict):
                row_data = [str(item.get(col['key'], '')) for col in self.columns]
            else:
                # Use item renderer for custom objects
                rendered_item = self.item_renderer(item, i)
                if isinstance(rendered_item, (list, tuple)):
                    row_data = [str(val) for val in rendered_item]
                else:
                    # Fallback to string representation
                    row_data = [str(item)] + [''] * (len(self.columns) - 1)
            
            # Apply formatting
            for j, column in enumerate(self.columns):
                if j < len(row_data):
                    formatter = column.get('formatter')
                    if formatter:
                        row_data[j] = formatter(row_data[j])
            
            table.add_row(*row_data)
        
        return table
    
    def _default_item_renderer(self, item: T, index: int) -> RenderableType:
        """Default item renderer."""
        if isinstance(item, dict):
            return [str(item.get(col['key'], '')) for col in self.columns]
        else:
            return str(item)
    
    # Event handlers
    
    def on_pagination_controls_page_changed(self, event: PaginationControls.PageChanged) -> None:
        """Handle page change."""
        self.current_request.page = event.page
        self.refresh_data()
    
    def on_pagination_controls_page_size_changed(self, event: PaginationControls.PageSizeChanged) -> None:
        """Handle page size change."""
        self.current_request.page_size = event.page_size
        self.current_request.page = 1  # Reset to first page
        self.refresh_data()
    
    def on_search_and_filter_search_changed(self, event: SearchAndFilter.SearchChanged) -> None:
        """Handle search change."""
        self.current_request.search_query = event.query
        self.current_request.page = 1  # Reset to first page
        self.refresh_data()
    
    def on_search_and_filter_sort_changed(self, event: SearchAndFilter.SortChanged) -> None:
        """Handle sort change."""
        self.current_request.sort_configs = [SortConfig(event.field, event.order)]
        self.refresh_data()
    
    def get_current_items(self) -> List[T]:
        """Get current page items."""
        if self.current_result:
            return self.current_result.items
        return []
    
    def get_performance_stats(self) -> Dict[str, Any]:
        """Get performance statistics."""
        stats = {
            'current_page': self.current_request.page,
            'page_size': self.current_request.page_size,
            'is_loading': self.is_loading,
        }
        
        if self.current_result:
            stats.update({
                'load_time': self.current_result.load_time,
                'total_items': self.current_result.page_info.total_items,
                'total_pages': self.current_result.page_info.total_pages,
                'items_on_page': len(self.current_result.items)
            })
        
        return stats


# Example usage and demo

class DemoUser:
    """Demo user class for testing."""
    
    def __init__(self, name: str, email: str, active: bool, created_at: str):
        self.name = name
        self.email = email
        self.active = active
        self.created_at = created_at
    
    def __str__(self) -> str:
        return f"{self.name} ({self.email})"


def create_demo_data_source() -> InMemoryDataSource[DemoUser]:
    """Create demo data source for testing."""
    import random
    from datetime import datetime, timedelta
    
    users = []
    for i in range(500):
        user = DemoUser(
            name=f"User {i:03d}",
            email=f"user{i:03d}@example.com",
            active=random.choice([True, False]),
            created_at=(datetime.now() - timedelta(days=random.randint(0, 365))).strftime("%Y-%m-%d")
        )
        users.append(user)
    
    return InMemoryDataSource(
        items=users,
        sort_fields=["name", "email", "active", "created_at"],
        filter_fields=[
            {"field": "active", "type": "boolean"},
            {"field": "name", "type": "string"},
            {"field": "email", "type": "string"}
        ]
    )


def demo_paginated_table():
    """Demo paginated table usage."""
    from textual.app import App
    
    class PaginationDemo(App):
        def compose(self) -> ComposeResult:
            data_source = create_demo_data_source()
            
            columns = [
                {"key": "name", "title": "Name", "width": 15},
                {"key": "email", "title": "Email", "width": 25},
                {"key": "active", "title": "Active", "width": 8, "formatter": lambda x: "✓" if x else "✗"},
                {"key": "created_at", "title": "Created", "width": 12}
            ]
            
            table = PaginatedTable(
                data_source=data_source,
                columns=columns,
                page_size=10
            )
            yield table
    
    return PaginationDemo()


if __name__ == "__main__":
    # Run demo
    app = demo_paginated_table()
    app.run()