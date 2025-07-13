"""Reactive Updates Optimization for VPN Manager TUI.

This module provides optimized reactive update mechanisms to minimize
unnecessary UI updates and improve TUI performance.
"""

import asyncio
import threading
import time
import weakref
from collections import defaultdict, deque
from collections.abc import Callable
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional, TypeVar

from rich.console import Console
from textual._context import active_app
from textual.reactive import Reactive
from textual.widget import Widget

console = Console()

T = TypeVar('T')


class UpdatePriority(Enum):
    """Priority levels for reactive updates."""
    LOW = 0
    NORMAL = 1
    HIGH = 2
    CRITICAL = 3


class UpdateType(Enum):
    """Types of reactive updates."""
    DATA_CHANGE = "data_change"
    STYLE_CHANGE = "style_change"
    LAYOUT_CHANGE = "layout_change"
    CONTENT_CHANGE = "content_change"
    STATE_CHANGE = "state_change"


@dataclass
class UpdateRequest:
    """Request for reactive update."""
    widget_id: str
    widget_ref: weakref.ref
    update_type: UpdateType
    priority: UpdatePriority
    data: Any
    timestamp: float = field(default_factory=time.perf_counter)
    callback: Callable | None = None
    debounce_key: str | None = None

    @property
    def age(self) -> float:
        """Get age of update request in seconds."""
        return time.perf_counter() - self.timestamp

    def is_valid(self) -> bool:
        """Check if widget reference is still valid."""
        return self.widget_ref() is not None


@dataclass
class UpdateBatch:
    """Batch of related updates."""
    updates: list[UpdateRequest] = field(default_factory=list)
    priority: UpdatePriority = UpdatePriority.NORMAL
    created_at: float = field(default_factory=time.perf_counter)

    def add_update(self, update: UpdateRequest) -> None:
        """Add update to batch."""
        self.updates.append(update)
        # Increase batch priority if needed
        if update.priority.value > self.priority.value:
            self.priority = update.priority

    def is_empty(self) -> bool:
        """Check if batch is empty."""
        return len(self.updates) == 0


class ReactiveScheduler:
    """Optimized scheduler for reactive updates."""

    def __init__(self,
                 batch_interval: float = 0.016,  # ~60 FPS
                 debounce_interval: float = 0.1,
                 max_updates_per_frame: int = 50):

        self.batch_interval = batch_interval
        self.debounce_interval = debounce_interval
        self.max_updates_per_frame = max_updates_per_frame

        # Update queues by priority
        self.update_queues: dict[UpdatePriority, deque] = {
            priority: deque() for priority in UpdatePriority
        }

        # Debouncing
        self.debounce_cache: dict[str, UpdateRequest] = {}
        self.debounce_timers: dict[str, float] = {}

        # Batching
        self.current_batch = UpdateBatch()
        self.batch_timer: asyncio.Task | None = None

        # Performance tracking
        self.processed_updates = 0
        self.batched_updates = 0
        self.debounced_updates = 0
        self.processing_times: deque = deque(maxlen=100)

        # Thread safety
        self.lock = threading.RLock()

        # Active flag
        self.is_active = True

    def schedule_update(self,
                       widget: Widget,
                       update_type: UpdateType,
                       data: Any,
                       priority: UpdatePriority = UpdatePriority.NORMAL,
                       callback: Callable | None = None,
                       debounce_key: str | None = None) -> None:
        """Schedule a reactive update."""
        if not self.is_active:
            return

        widget_id = f"{widget.__class__.__name__}_{id(widget)}"

        # Create update request
        update = UpdateRequest(
            widget_id=widget_id,
            widget_ref=weakref.ref(widget),
            update_type=update_type,
            priority=priority,
            data=data,
            callback=callback,
            debounce_key=debounce_key
        )

        with self.lock:
            # Handle debouncing
            if debounce_key:
                self._handle_debounced_update(update)
            else:
                self._add_update_to_queue(update)

    def _handle_debounced_update(self, update: UpdateRequest) -> None:
        """Handle debounced update."""
        debounce_key = update.debounce_key
        current_time = time.perf_counter()

        # Check if we should debounce
        if debounce_key in self.debounce_timers:
            last_time = self.debounce_timers[debounce_key]
            if current_time - last_time < self.debounce_interval:
                # Replace existing debounced update
                self.debounce_cache[debounce_key] = update
                self.debounce_timers[debounce_key] = current_time
                self.debounced_updates += 1
                return

        # Process immediately if not debouncing
        self.debounce_timers[debounce_key] = current_time
        self._add_update_to_queue(update)

    def _add_update_to_queue(self, update: UpdateRequest) -> None:
        """Add update to appropriate priority queue."""
        priority_queue = self.update_queues[update.priority]
        priority_queue.append(update)

        # Start batch processing if needed
        if not self.batch_timer:
            self._start_batch_timer()

    def _start_batch_timer(self) -> None:
        """Start batch processing timer."""
        if active_app.get():
            self.batch_timer = asyncio.create_task(self._batch_process_updates())

    async def _batch_process_updates(self) -> None:
        """Process updates in batches."""
        try:
            await asyncio.sleep(self.batch_interval)

            with self.lock:
                # Process debounced updates
                self._process_debounced_updates()

                # Process priority queues
                updates_processed = 0

                # Process in priority order
                for priority in sorted(UpdatePriority, key=lambda x: x.value, reverse=True):
                    queue = self.update_queues[priority]

                    while queue and updates_processed < self.max_updates_per_frame:
                        update = queue.popleft()

                        if update.is_valid():
                            await self._execute_update(update)
                            updates_processed += 1

                        self.processed_updates += 1

                # Continue processing if there are more updates
                has_updates = any(queue for queue in self.update_queues.values())
                if has_updates:
                    self._start_batch_timer()
                else:
                    self.batch_timer = None

        except Exception as e:
            console.print(f"[red]Error in batch processing: {e}[/red]")
            self.batch_timer = None

    def _process_debounced_updates(self) -> None:
        """Process debounced updates that are ready."""
        current_time = time.perf_counter()
        ready_keys = []

        for debounce_key, last_time in self.debounce_timers.items():
            if current_time - last_time >= self.debounce_interval:
                ready_keys.append(debounce_key)

        for key in ready_keys:
            if key in self.debounce_cache:
                update = self.debounce_cache.pop(key)
                del self.debounce_timers[key]
                self._add_update_to_queue(update)

    async def _execute_update(self, update: UpdateRequest) -> None:
        """Execute a single update."""
        start_time = time.perf_counter()

        try:
            widget = update.widget_ref()
            if not widget:
                return

            # Execute update based on type
            if update.update_type == UpdateType.DATA_CHANGE:
                await self._handle_data_change(widget, update)
            elif update.update_type == UpdateType.STYLE_CHANGE:
                await self._handle_style_change(widget, update)
            elif update.update_type == UpdateType.LAYOUT_CHANGE:
                await self._handle_layout_change(widget, update)
            elif update.update_type == UpdateType.CONTENT_CHANGE:
                await self._handle_content_change(widget, update)
            elif update.update_type == UpdateType.STATE_CHANGE:
                await self._handle_state_change(widget, update)

            # Execute callback if provided
            if update.callback:
                if asyncio.iscoroutinefunction(update.callback):
                    await update.callback(widget, update.data)
                else:
                    update.callback(widget, update.data)

        except Exception as e:
            console.print(f"[red]Error executing update: {e}[/red]")

        finally:
            # Track performance
            execution_time = time.perf_counter() - start_time
            self.processing_times.append(execution_time)

    async def _handle_data_change(self, widget: Widget, update: UpdateRequest) -> None:
        """Handle data change update."""
        # Update reactive attributes if applicable
        if hasattr(widget, '_reactives'):
            for name, reactive_obj in widget._reactives.items():
                if name in update.data:
                    setattr(widget, name, update.data[name])

        # Refresh widget if needed
        if hasattr(widget, 'refresh'):
            widget.refresh()

    async def _handle_style_change(self, widget: Widget, update: UpdateRequest) -> None:
        """Handle style change update."""
        if hasattr(widget, 'styles') and isinstance(update.data, dict):
            for style_name, style_value in update.data.items():
                setattr(widget.styles, style_name, style_value)

    async def _handle_layout_change(self, widget: Widget, update: UpdateRequest) -> None:
        """Handle layout change update."""
        if hasattr(widget, 'refresh'):
            widget.refresh(layout=True)

    async def _handle_content_change(self, widget: Widget, update: UpdateRequest) -> None:
        """Handle content change update."""
        if hasattr(widget, 'update') and update.data is not None:
            widget.update(update.data)
        elif hasattr(widget, 'refresh'):
            widget.refresh()

    async def _handle_state_change(self, widget: Widget, update: UpdateRequest) -> None:
        """Handle state change update."""
        if isinstance(update.data, dict):
            for attr, value in update.data.items():
                if hasattr(widget, attr):
                    setattr(widget, attr, value)

        if hasattr(widget, 'refresh'):
            widget.refresh()

    def get_stats(self) -> dict[str, Any]:
        """Get scheduler performance statistics."""
        with self.lock:
            avg_processing_time = (
                sum(self.processing_times) / len(self.processing_times)
                if self.processing_times else 0
            )

            pending_updates = sum(len(queue) for queue in self.update_queues.values())

            return {
                'processed_updates': self.processed_updates,
                'batched_updates': self.batched_updates,
                'debounced_updates': self.debounced_updates,
                'pending_updates': pending_updates,
                'avg_processing_time': avg_processing_time,
                'max_processing_time': max(self.processing_times) if self.processing_times else 0,
                'debounce_cache_size': len(self.debounce_cache),
                'is_active': self.is_active
            }

    def clear_stats(self) -> None:
        """Clear performance statistics."""
        with self.lock:
            self.processed_updates = 0
            self.batched_updates = 0
            self.debounced_updates = 0
            self.processing_times.clear()

    def shutdown(self) -> None:
        """Shutdown scheduler."""
        self.is_active = False
        if self.batch_timer:
            self.batch_timer.cancel()


class OptimizedReactive(Reactive[T]):
    """Optimized reactive attribute with smart update scheduling."""

    def __init__(self,
                 default: T | Callable[[], T],
                 layout: bool = False,
                 repaint: bool = True,
                 update_priority: UpdatePriority = UpdatePriority.NORMAL,
                 debounce_key: str | None = None,
                 compute: Callable[[T], T] | None = None):

        super().__init__(default, layout=layout, repaint=repaint, compute=compute)
        self.update_priority = update_priority
        self.debounce_key = debounce_key
        self._scheduler: ReactiveScheduler | None = None

    def set_scheduler(self, scheduler: ReactiveScheduler) -> None:
        """Set the scheduler for this reactive."""
        self._scheduler = scheduler

    def _check_watchers(self, obj: object, old_value: T, value: T) -> None:
        """Override to use optimized scheduler."""
        if self._scheduler and hasattr(obj, '__class__'):
            # Determine update type
            update_type = UpdateType.LAYOUT_CHANGE if self.layout else UpdateType.CONTENT_CHANGE

            # Schedule optimized update
            self._scheduler.schedule_update(
                widget=obj,
                update_type=update_type,
                data={self.name: value},
                priority=self.update_priority,
                debounce_key=self.debounce_key
            )
        else:
            # Fallback to default behavior
            super()._check_watchers(obj, old_value, value)


class OptimizedWidget(Widget):
    """Base widget with optimized reactive updates."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._reactive_scheduler: ReactiveScheduler | None = None
        self._update_counters: dict[str, int] = defaultdict(int)
        self._last_update_times: dict[str, float] = {}

    def set_reactive_scheduler(self, scheduler: ReactiveScheduler) -> None:
        """Set reactive scheduler for this widget."""
        self._reactive_scheduler = scheduler

        # Update existing reactive attributes
        if hasattr(self, '_reactives'):
            for reactive_obj in self._reactives.values():
                if isinstance(reactive_obj, OptimizedReactive):
                    reactive_obj.set_scheduler(scheduler)

    def schedule_update(self,
                       update_type: UpdateType,
                       data: Any,
                       priority: UpdatePriority = UpdatePriority.NORMAL,
                       callback: Callable | None = None,
                       debounce_key: str | None = None) -> None:
        """Schedule a manual update."""
        if self._reactive_scheduler:
            self._reactive_scheduler.schedule_update(
                widget=self,
                update_type=update_type,
                data=data,
                priority=priority,
                callback=callback,
                debounce_key=debounce_key
            )

    def batch_update(self, updates: dict[str, Any]) -> None:
        """Batch multiple reactive updates."""
        if self._reactive_scheduler:
            self._reactive_scheduler.schedule_update(
                widget=self,
                update_type=UpdateType.DATA_CHANGE,
                data=updates,
                priority=UpdatePriority.NORMAL,
                debounce_key=f"{id(self)}_batch"
            )

    def get_update_stats(self) -> dict[str, Any]:
        """Get update statistics for this widget."""
        return {
            'update_counters': dict(self._update_counters),
            'last_update_times': dict(self._last_update_times),
            'has_scheduler': self._reactive_scheduler is not None
        }

    def _track_update(self, update_type: str) -> None:
        """Track update for statistics."""
        self._update_counters[update_type] += 1
        self._last_update_times[update_type] = time.perf_counter()


class ReactiveOptimizer:
    """Global reactive optimization manager."""

    _instance: Optional['ReactiveOptimizer'] = None

    def __init__(self):
        self.scheduler = ReactiveScheduler()
        self.optimized_widgets: set[weakref.ref] = set()
        self.monitoring_enabled = False
        self.performance_logs: deque = deque(maxlen=1000)

    @classmethod
    def get_instance(cls) -> 'ReactiveOptimizer':
        """Get singleton instance."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def register_widget(self, widget: Widget) -> None:
        """Register widget for optimization."""
        if isinstance(widget, OptimizedWidget):
            widget.set_reactive_scheduler(self.scheduler)

        self.optimized_widgets.add(weakref.ref(widget))
        self._cleanup_dead_references()

    def unregister_widget(self, widget: Widget) -> None:
        """Unregister widget from optimization."""
        widget_refs_to_remove = []
        for widget_ref in self.optimized_widgets:
            if widget_ref() is widget:
                widget_refs_to_remove.append(widget_ref)

        for widget_ref in widget_refs_to_remove:
            self.optimized_widgets.discard(widget_ref)

    def _cleanup_dead_references(self) -> None:
        """Clean up dead widget references."""
        dead_refs = []
        for widget_ref in self.optimized_widgets:
            if widget_ref() is None:
                dead_refs.append(widget_ref)

        for dead_ref in dead_refs:
            self.optimized_widgets.discard(dead_ref)

    def enable_monitoring(self) -> None:
        """Enable performance monitoring."""
        self.monitoring_enabled = True

    def disable_monitoring(self) -> None:
        """Disable performance monitoring."""
        self.monitoring_enabled = False

    def get_global_stats(self) -> dict[str, Any]:
        """Get global optimization statistics."""
        self._cleanup_dead_references()

        scheduler_stats = self.scheduler.get_stats()

        widget_stats = []
        for widget_ref in self.optimized_widgets:
            widget = widget_ref()
            if widget and hasattr(widget, 'get_update_stats'):
                stats = widget.get_update_stats()
                stats['widget_type'] = widget.__class__.__name__
                stats['widget_id'] = id(widget)
                widget_stats.append(stats)

        return {
            'scheduler': scheduler_stats,
            'active_widgets': len(self.optimized_widgets),
            'monitoring_enabled': self.monitoring_enabled,
            'widget_stats': widget_stats
        }

    def log_performance(self, operation: str, duration: float, **metadata) -> None:
        """Log performance data."""
        if self.monitoring_enabled:
            log_entry = {
                'timestamp': time.perf_counter(),
                'operation': operation,
                'duration': duration,
                'metadata': metadata
            }
            self.performance_logs.append(log_entry)

    def get_performance_logs(self, operation: str | None = None) -> list[dict[str, Any]]:
        """Get performance logs."""
        logs = list(self.performance_logs)

        if operation:
            logs = [log for log in logs if log['operation'] == operation]

        return logs

    def shutdown(self) -> None:
        """Shutdown optimizer."""
        self.scheduler.shutdown()
        self.optimized_widgets.clear()
        self.performance_logs.clear()


# Convenience functions

def get_reactive_optimizer() -> ReactiveOptimizer:
    """Get global reactive optimizer instance."""
    return ReactiveOptimizer.get_instance()


def register_optimized_widget(widget: Widget) -> None:
    """Register widget for reactive optimization."""
    optimizer = get_reactive_optimizer()
    optimizer.register_widget(widget)


def schedule_widget_update(widget: Widget,
                         update_type: UpdateType,
                         data: Any,
                         priority: UpdatePriority = UpdatePriority.NORMAL,
                         **kwargs) -> None:
    """Schedule optimized widget update."""
    optimizer = get_reactive_optimizer()
    optimizer.scheduler.schedule_update(
        widget=widget,
        update_type=update_type,
        data=data,
        priority=priority,
        **kwargs
    )


def create_optimized_reactive(default: T,
                            update_priority: UpdatePriority = UpdatePriority.NORMAL,
                            debounce_key: str | None = None,
                            **kwargs) -> OptimizedReactive[T]:
    """Create optimized reactive attribute."""
    reactive_attr = OptimizedReactive(
        default=default,
        update_priority=update_priority,
        debounce_key=debounce_key,
        **kwargs
    )

    # Set scheduler
    optimizer = get_reactive_optimizer()
    reactive_attr.set_scheduler(optimizer.scheduler)

    return reactive_attr


# Example usage

class ExampleOptimizedWidget(OptimizedWidget):
    """Example widget with optimized reactives."""

    # High-priority reactive for critical updates
    status = create_optimized_reactive(
        "idle",
        update_priority=UpdatePriority.HIGH,
        debounce_key="status_update"
    )

    # Low-priority reactive for non-critical updates
    stats = create_optimized_reactive(
        {},
        update_priority=UpdatePriority.LOW,
        debounce_key="stats_update"
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        # Register for optimization
        register_optimized_widget(self)

    def update_status(self, new_status: str) -> None:
        """Update status with automatic optimization."""
        self.status = new_status

    def update_stats(self, new_stats: dict[str, Any]) -> None:
        """Update stats with batching."""
        self.batch_update({"stats": new_stats})


if __name__ == "__main__":
    # Demo reactive optimization
    optimizer = get_reactive_optimizer()
    optimizer.enable_monitoring()

    # Create example widget
    widget = ExampleOptimizedWidget()

    # Simulate rapid updates
    for i in range(100):
        widget.update_status(f"status_{i}")
        widget.update_stats({"counter": i})

    # Show stats
    stats = optimizer.get_global_stats()
    console.print("[green]Optimization stats:[/green]")
    console.print(stats)

    optimizer.shutdown()
