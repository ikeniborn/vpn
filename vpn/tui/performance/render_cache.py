"""
Render Caching System for VPN Manager TUI.

This module provides intelligent render caching to avoid expensive re-renders
and improve TUI performance by caching rendered content and widget states.
"""

import asyncio
import hashlib
import pickle
import time
import weakref
from typing import Any, Dict, List, Optional, Callable, Union, Tuple, Set
from dataclasses import dataclass, field
from abc import ABC, abstractmethod
from enum import Enum
from collections import OrderedDict, defaultdict
import threading

from textual.app import App
from textual.widget import Widget
from textual.strip import Strip
from textual.geometry import Size, Region
from textual.render import Measurement
from textual._segment_tools import Segment

from rich.console import Console, RenderableType
from rich.text import Text
from rich.panel import Panel

console = Console()


class CachePolicy(Enum):
    """Cache eviction policies."""
    LRU = "lru"           # Least Recently Used
    LFU = "lfu"           # Least Frequently Used
    TTL = "ttl"           # Time To Live
    SIZE_BASED = "size"   # Size-based eviction


class CacheEvent(Enum):
    """Cache events for monitoring."""
    HIT = "hit"
    MISS = "miss"
    EVICTION = "eviction"
    INVALIDATION = "invalidation"
    CLEANUP = "cleanup"


@dataclass
class CacheEntry:
    """Cache entry with metadata."""
    key: str
    content: Any
    size_bytes: int
    created_at: float = field(default_factory=time.perf_counter)
    last_accessed: float = field(default_factory=time.perf_counter)
    access_count: int = 0
    ttl: Optional[float] = None
    dependencies: Set[str] = field(default_factory=set)
    
    @property
    def age(self) -> float:
        """Get age of cache entry in seconds."""
        return time.perf_counter() - self.created_at
    
    @property
    def is_expired(self) -> bool:
        """Check if entry is expired."""
        if self.ttl is None:
            return False
        return self.age > self.ttl
    
    def touch(self) -> None:
        """Update access information."""
        self.last_accessed = time.perf_counter()
        self.access_count += 1


@dataclass
class CacheStats:
    """Cache performance statistics."""
    hits: int = 0
    misses: int = 0
    evictions: int = 0
    invalidations: int = 0
    total_size: int = 0
    entry_count: int = 0
    
    @property
    def hit_ratio(self) -> float:
        """Calculate cache hit ratio."""
        total = self.hits + self.misses
        return self.hits / total if total > 0 else 0.0
    
    @property
    def avg_entry_size(self) -> float:
        """Calculate average entry size."""
        return self.total_size / self.entry_count if self.entry_count > 0 else 0.0


class RenderCache:
    """High-performance render cache with multiple eviction policies."""
    
    def __init__(self,
                 max_size_mb: int = 50,
                 max_entries: int = 1000,
                 policy: CachePolicy = CachePolicy.LRU,
                 default_ttl: Optional[float] = None):
        
        self.max_size_bytes = max_size_mb * 1024 * 1024
        self.max_entries = max_entries
        self.policy = policy
        self.default_ttl = default_ttl
        
        # Cache storage
        self.entries: OrderedDict[str, CacheEntry] = OrderedDict()
        self.stats = CacheStats()
        
        # Thread safety
        self.lock = threading.RLock()
        
        # Dependency tracking
        self.dependency_map: Dict[str, Set[str]] = defaultdict(set)
        
        # Event listeners
        self.event_listeners: List[Callable[[CacheEvent, str, Any], None]] = []
        
        # Cleanup task
        self.cleanup_task: Optional[asyncio.Task] = None
        self.cleanup_interval = 60.0  # 1 minute
    
    def get(self, key: str) -> Optional[Any]:
        """Get cached content by key."""
        with self.lock:
            entry = self.entries.get(key)
            
            if entry is None:
                self.stats.misses += 1
                self._emit_event(CacheEvent.MISS, key, None)
                return None
            
            # Check expiration
            if entry.is_expired:
                self._remove_entry(key)
                self.stats.misses += 1
                self._emit_event(CacheEvent.MISS, key, None)
                return None
            
            # Update access info
            entry.touch()
            
            # Move to end for LRU
            if self.policy == CachePolicy.LRU:
                self.entries.move_to_end(key)
            
            self.stats.hits += 1
            self._emit_event(CacheEvent.HIT, key, entry.content)
            
            return entry.content
    
    def put(self, 
            key: str, 
            content: Any,
            ttl: Optional[float] = None,
            dependencies: Optional[Set[str]] = None) -> None:
        """Put content in cache."""
        
        with self.lock:
            # Calculate content size
            try:
                size_bytes = len(pickle.dumps(content))
            except Exception:
                size_bytes = 1024  # Fallback estimate
            
            # Check if content is too large
            if size_bytes > self.max_size_bytes:
                console.print(f"[yellow]Content too large for cache: {size_bytes} bytes[/yellow]")
                return
            
            # Remove existing entry if present
            if key in self.entries:
                self._remove_entry(key)
            
            # Create new entry
            entry = CacheEntry(
                key=key,
                content=content,
                size_bytes=size_bytes,
                ttl=ttl or self.default_ttl,
                dependencies=dependencies or set()
            )
            
            # Ensure cache capacity
            self._ensure_capacity(size_bytes)
            
            # Add entry
            self.entries[key] = entry
            self.stats.entry_count += 1
            self.stats.total_size += size_bytes
            
            # Update dependency tracking
            for dep in entry.dependencies:
                self.dependency_map[dep].add(key)
    
    def invalidate(self, key: str) -> bool:
        """Invalidate cache entry."""
        with self.lock:
            if key in self.entries:
                self._remove_entry(key)
                self.stats.invalidations += 1
                self._emit_event(CacheEvent.INVALIDATION, key, None)
                return True
            return False
    
    def invalidate_by_dependency(self, dependency: str) -> int:
        """Invalidate all entries with given dependency."""
        with self.lock:
            dependent_keys = self.dependency_map.get(dependency, set()).copy()
            count = 0
            
            for key in dependent_keys:
                if self.invalidate(key):
                    count += 1
            
            # Clean up dependency map
            if dependency in self.dependency_map:
                del self.dependency_map[dependency]
            
            return count
    
    def clear(self) -> None:
        """Clear entire cache."""
        with self.lock:
            self.entries.clear()
            self.dependency_map.clear()
            self.stats = CacheStats()
            self._emit_event(CacheEvent.CLEANUP, "all", None)
    
    def cleanup_expired(self) -> int:
        """Clean up expired entries."""
        with self.lock:
            expired_keys = []
            
            for key, entry in self.entries.items():
                if entry.is_expired:
                    expired_keys.append(key)
            
            for key in expired_keys:
                self._remove_entry(key)
            
            if expired_keys:
                self._emit_event(CacheEvent.CLEANUP, f"expired_{len(expired_keys)}", expired_keys)
            
            return len(expired_keys)
    
    def get_stats(self) -> CacheStats:
        """Get cache statistics."""
        with self.lock:
            # Update current stats
            self.stats.entry_count = len(self.entries)
            self.stats.total_size = sum(entry.size_bytes for entry in self.entries.values())
            return self.stats
    
    def get_detailed_stats(self) -> Dict[str, Any]:
        """Get detailed cache statistics."""
        with self.lock:
            stats = self.get_stats()
            
            # Calculate additional metrics
            if self.entries:
                ages = [entry.age for entry in self.entries.values()]
                access_counts = [entry.access_count for entry in self.entries.values()]
                sizes = [entry.size_bytes for entry in self.entries.values()]
                
                detailed = {
                    'basic_stats': {
                        'hits': stats.hits,
                        'misses': stats.misses,
                        'hit_ratio': stats.hit_ratio,
                        'evictions': stats.evictions,
                        'invalidations': stats.invalidations,
                        'entry_count': stats.entry_count,
                        'total_size_mb': stats.total_size / (1024 * 1024),
                        'avg_entry_size_kb': stats.avg_entry_size / 1024
                    },
                    'entry_metrics': {
                        'avg_age': sum(ages) / len(ages),
                        'max_age': max(ages),
                        'avg_access_count': sum(access_counts) / len(access_counts),
                        'max_access_count': max(access_counts),
                        'min_entry_size': min(sizes),
                        'max_entry_size': max(sizes)
                    },
                    'capacity': {
                        'max_size_mb': self.max_size_bytes / (1024 * 1024),
                        'max_entries': self.max_entries,
                        'utilization_percent': (stats.total_size / self.max_size_bytes) * 100,
                        'entries_utilization_percent': (stats.entry_count / self.max_entries) * 100
                    },
                    'dependencies': {
                        'dependency_count': len(self.dependency_map),
                        'total_dependent_entries': sum(len(deps) for deps in self.dependency_map.values())
                    }
                }
            else:
                detailed = {
                    'basic_stats': {
                        'hits': stats.hits,
                        'misses': stats.misses,
                        'hit_ratio': stats.hit_ratio,
                        'evictions': stats.evictions,
                        'invalidations': stats.invalidations,
                        'entry_count': 0,
                        'total_size_mb': 0,
                        'avg_entry_size_kb': 0
                    },
                    'entry_metrics': {},
                    'capacity': {
                        'max_size_mb': self.max_size_bytes / (1024 * 1024),
                        'max_entries': self.max_entries,
                        'utilization_percent': 0,
                        'entries_utilization_percent': 0
                    },
                    'dependencies': {
                        'dependency_count': 0,
                        'total_dependent_entries': 0
                    }
                }
            
            return detailed
    
    def add_event_listener(self, listener: Callable[[CacheEvent, str, Any], None]) -> None:
        """Add cache event listener."""
        self.event_listeners.append(listener)
    
    def start_background_cleanup(self) -> None:
        """Start background cleanup task."""
        if not self.cleanup_task:
            self.cleanup_task = asyncio.create_task(self._background_cleanup())
    
    def stop_background_cleanup(self) -> None:
        """Stop background cleanup task."""
        if self.cleanup_task:
            self.cleanup_task.cancel()
            self.cleanup_task = None
    
    # Private methods
    
    def _ensure_capacity(self, new_size: int) -> None:
        """Ensure cache has capacity for new entry."""
        # Check if we need to make space
        while (len(self.entries) >= self.max_entries or 
               self.stats.total_size + new_size > self.max_size_bytes):
            
            if not self.entries:
                break
            
            # Evict based on policy
            if self.policy == CachePolicy.LRU:
                # Remove least recently used (first in OrderedDict)
                key = next(iter(self.entries))
            elif self.policy == CachePolicy.LFU:
                # Remove least frequently used
                key = min(self.entries.keys(), 
                         key=lambda k: self.entries[k].access_count)
            elif self.policy == CachePolicy.TTL:
                # Remove oldest entry
                key = min(self.entries.keys(),
                         key=lambda k: self.entries[k].created_at)
            else:  # SIZE_BASED
                # Remove largest entry
                key = max(self.entries.keys(),
                         key=lambda k: self.entries[k].size_bytes)
            
            self._remove_entry(key)
            self.stats.evictions += 1
            self._emit_event(CacheEvent.EVICTION, key, None)
    
    def _remove_entry(self, key: str) -> None:
        """Remove entry from cache."""
        if key in self.entries:
            entry = self.entries.pop(key)
            self.stats.entry_count -= 1
            self.stats.total_size -= entry.size_bytes
            
            # Clean up dependencies
            for dep in entry.dependencies:
                if dep in self.dependency_map:
                    self.dependency_map[dep].discard(key)
                    if not self.dependency_map[dep]:
                        del self.dependency_map[dep]
    
    def _emit_event(self, event: CacheEvent, key: str, data: Any) -> None:
        """Emit cache event to listeners."""
        for listener in self.event_listeners:
            try:
                listener(event, key, data)
            except Exception as e:
                console.print(f"[red]Error in cache event listener: {e}[/red]")
    
    async def _background_cleanup(self) -> None:
        """Background cleanup task."""
        while True:
            try:
                await asyncio.sleep(self.cleanup_interval)
                expired_count = self.cleanup_expired()
                if expired_count > 0:
                    console.print(f"[blue]Cleaned up {expired_count} expired cache entries[/blue]")
            except asyncio.CancelledError:
                break
            except Exception as e:
                console.print(f"[red]Error in background cleanup: {e}[/red]")


class WidgetRenderCache:
    """Specialized cache for widget rendering."""
    
    def __init__(self, cache: RenderCache):
        self.cache = cache
        self.render_hashes: Dict[str, str] = {}
    
    def get_widget_cache_key(self, 
                           widget: Widget,
                           size: Size,
                           render_data: Any = None) -> str:
        """Generate cache key for widget render."""
        widget_id = f"{widget.__class__.__name__}_{id(widget)}"
        
        # Include relevant widget state
        state_parts = [
            widget_id,
            str(size),
            str(getattr(widget, 'styles', {})),
            str(render_data) if render_data else ""
        ]
        
        # Add reactive attributes
        if hasattr(widget, '_reactives'):
            for name in sorted(widget._reactives.keys()):
                value = getattr(widget, name, None)
                state_parts.append(f"{name}:{value}")
        
        # Create hash
        state_string = "|".join(state_parts)
        return hashlib.md5(state_string.encode()).hexdigest()
    
    def get_render(self, 
                  widget: Widget,
                  size: Size,
                  render_data: Any = None) -> Optional[RenderableType]:
        """Get cached render for widget."""
        cache_key = self.get_widget_cache_key(widget, size, render_data)
        return self.cache.get(cache_key)
    
    def cache_render(self,
                    widget: Widget,
                    size: Size,
                    rendered_content: RenderableType,
                    render_data: Any = None,
                    ttl: Optional[float] = None) -> None:
        """Cache widget render."""
        cache_key = self.get_widget_cache_key(widget, size, render_data)
        
        # Determine dependencies
        dependencies = {
            f"widget_{id(widget)}",
            f"class_{widget.__class__.__name__}"
        }
        
        # Add reactive dependencies
        if hasattr(widget, '_reactives'):
            for name in widget._reactives.keys():
                dependencies.add(f"reactive_{id(widget)}_{name}")
        
        self.cache.put(
            key=cache_key,
            content=rendered_content,
            ttl=ttl,
            dependencies=dependencies
        )
    
    def invalidate_widget(self, widget: Widget) -> int:
        """Invalidate all cached renders for widget."""
        widget_dep = f"widget_{id(widget)}"
        return self.cache.invalidate_by_dependency(widget_dep)
    
    def invalidate_widget_reactive(self, widget: Widget, reactive_name: str) -> int:
        """Invalidate cached renders for specific reactive."""
        reactive_dep = f"reactive_{id(widget)}_{reactive_name}"
        return self.cache.invalidate_by_dependency(reactive_dep)


class CachedWidget(Widget):
    """Widget with automatic render caching."""
    
    def __init__(self, 
                 cache_ttl: Optional[float] = None,
                 cache_enabled: bool = True,
                 **kwargs):
        super().__init__(**kwargs)
        
        self.cache_ttl = cache_ttl
        self.cache_enabled = cache_enabled
        self._render_cache: Optional[WidgetRenderCache] = None
        self._render_count = 0
        self._cache_hits = 0
        self._cache_misses = 0
    
    def set_render_cache(self, render_cache: WidgetRenderCache) -> None:
        """Set render cache for this widget."""
        self._render_cache = render_cache
    
    def render(self) -> RenderableType:
        """Render with caching."""
        if not self.cache_enabled or not self._render_cache:
            return self._do_render()
        
        # Try cache first
        cached_render = self._render_cache.get_render(
            widget=self,
            size=self.size,
            render_data=self._get_render_data()
        )
        
        if cached_render is not None:
            self._cache_hits += 1
            return cached_render
        
        # Cache miss - render and cache
        self._cache_misses += 1
        rendered_content = self._do_render()
        
        self._render_cache.cache_render(
            widget=self,
            size=self.size,
            rendered_content=rendered_content,
            render_data=self._get_render_data(),
            ttl=self.cache_ttl
        )
        
        self._render_count += 1
        return rendered_content
    
    def _do_render(self) -> RenderableType:
        """Actual render implementation - override in subclasses."""
        return super().render()
    
    def _get_render_data(self) -> Any:
        """Get additional data for cache key - override in subclasses."""
        return None
    
    def invalidate_cache(self) -> None:
        """Invalidate cached renders for this widget."""
        if self._render_cache:
            self._render_cache.invalidate_widget(self)
    
    def get_cache_stats(self) -> Dict[str, Any]:
        """Get cache statistics for this widget."""
        return {
            'render_count': self._render_count,
            'cache_hits': self._cache_hits,
            'cache_misses': self._cache_misses,
            'cache_hit_ratio': self._cache_hits / (self._cache_hits + self._cache_misses) if (self._cache_hits + self._cache_misses) > 0 else 0,
            'cache_enabled': self.cache_enabled
        }


class RenderCacheManager:
    """Global render cache manager."""
    
    _instance: Optional['RenderCacheManager'] = None
    
    def __init__(self):
        self.render_cache = RenderCache(
            max_size_mb=100,
            max_entries=2000,
            policy=CachePolicy.LRU,
            default_ttl=300.0  # 5 minutes
        )
        
        self.widget_cache = WidgetRenderCache(self.render_cache)
        self.cached_widgets: Set[weakref.ref] = set()
        
        # Start background cleanup
        self.render_cache.start_background_cleanup()
        
        # Event monitoring
        self.render_cache.add_event_listener(self._on_cache_event)
        self.event_log: List[Tuple[str, str, str]] = []
    
    @classmethod
    def get_instance(cls) -> 'RenderCacheManager':
        """Get singleton instance."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance
    
    def register_widget(self, widget: Widget) -> None:
        """Register widget for caching."""
        if isinstance(widget, CachedWidget):
            widget.set_render_cache(self.widget_cache)
        
        self.cached_widgets.add(weakref.ref(widget))
        self._cleanup_dead_references()
    
    def unregister_widget(self, widget: Widget) -> None:
        """Unregister widget from caching."""
        # Invalidate widget cache
        self.widget_cache.invalidate_widget(widget)
        
        # Remove from tracked widgets
        widget_refs_to_remove = []
        for widget_ref in self.cached_widgets:
            if widget_ref() is widget:
                widget_refs_to_remove.append(widget_ref)
        
        for widget_ref in widget_refs_to_remove:
            self.cached_widgets.discard(widget_ref)
    
    def _cleanup_dead_references(self) -> None:
        """Clean up dead widget references."""
        dead_refs = []
        for widget_ref in self.cached_widgets:
            if widget_ref() is None:
                dead_refs.append(widget_ref)
        
        for dead_ref in dead_refs:
            self.cached_widgets.discard(dead_ref)
    
    def _on_cache_event(self, event: CacheEvent, key: str, data: Any) -> None:
        """Handle cache events for monitoring."""
        timestamp = time.strftime("%H:%M:%S")
        self.event_log.append((timestamp, event.value, key))
        
        # Keep only last 1000 events
        if len(self.event_log) > 1000:
            self.event_log = self.event_log[-1000:]
    
    def get_global_stats(self) -> Dict[str, Any]:
        """Get global cache statistics."""
        self._cleanup_dead_references()
        
        cache_stats = self.render_cache.get_detailed_stats()
        
        widget_stats = []
        for widget_ref in self.cached_widgets:
            widget = widget_ref()
            if widget and hasattr(widget, 'get_cache_stats'):
                stats = widget.get_cache_stats()
                stats['widget_type'] = widget.__class__.__name__
                stats['widget_id'] = id(widget)
                widget_stats.append(stats)
        
        return {
            'cache_stats': cache_stats,
            'active_widgets': len(self.cached_widgets),
            'widget_stats': widget_stats,
            'recent_events': self.event_log[-10:]  # Last 10 events
        }
    
    def clear_all_caches(self) -> None:
        """Clear all caches."""
        self.render_cache.clear()
    
    def shutdown(self) -> None:
        """Shutdown cache manager."""
        self.render_cache.stop_background_cleanup()
        self.cached_widgets.clear()


# Convenience functions

def get_cache_manager() -> RenderCacheManager:
    """Get global cache manager."""
    return RenderCacheManager.get_instance()


def register_cached_widget(widget: Widget) -> None:
    """Register widget for render caching."""
    manager = get_cache_manager()
    manager.register_widget(widget)


# Example usage

class ExampleCachedWidget(CachedWidget):
    """Example widget with caching."""
    
    def __init__(self, content: str = "Example", **kwargs):
        super().__init__(cache_ttl=60.0, **kwargs)  # 1 minute cache
        self.content = content
        
        # Register for caching
        register_cached_widget(self)
    
    def _do_render(self) -> RenderableType:
        """Expensive render operation."""
        # Simulate expensive rendering
        time.sleep(0.01)  # 10ms delay
        
        return Panel(
            Text(f"Cached Content: {self.content}"),
            title="Cached Widget",
            border_style="blue"
        )
    
    def _get_render_data(self) -> Any:
        """Additional data for cache key."""
        return self.content
    
    def update_content(self, new_content: str) -> None:
        """Update content and invalidate cache."""
        self.content = new_content
        self.invalidate_cache()
        self.refresh()


if __name__ == "__main__":
    # Demo render caching
    manager = get_cache_manager()
    
    # Create cached widget
    widget = ExampleCachedWidget("Initial Content")
    
    # Simulate renders
    for i in range(10):
        rendered = widget.render()
        print(f"Render {i}: {type(rendered)}")
    
    # Update content
    widget.update_content("Updated Content")
    
    # More renders
    for i in range(5):
        rendered = widget.render()
        print(f"Updated Render {i}: {type(rendered)}")
    
    # Show stats
    stats = manager.get_global_stats()
    console.print("[green]Cache Statistics:[/green]")
    console.print(stats)
    
    manager.shutdown()