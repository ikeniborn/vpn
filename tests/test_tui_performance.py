"""
Comprehensive tests for TUI performance optimization components.
"""

import pytest
import asyncio
import time
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

from vpn.tui.performance import (
    # Profiler
    TUIProfiler, PerformanceMetric, RenderingProfile,
    start_profiling, stop_profiling, profile_operation,
    
    # Virtual Scrolling
    VirtualList, VirtualViewport, SimpleDataSource, VirtualListItem,
    
    # Pagination
    PageInfo, PageRequest, InMemoryDataSource, PaginationControls,
    SortOrder, SortConfig, FilterConfig,
    
    # Reactive Optimization
    ReactiveScheduler, UpdatePriority, UpdateType, OptimizedWidget,
    get_reactive_optimizer, register_optimized_widget,
    
    # Render Caching
    RenderCache, CachePolicy, CachedWidget, get_cache_manager,
    register_cached_widget
)


class TestTUIProfiler:
    """Test TUI profiler functionality."""
    
    def test_profiler_initialization(self):
        """Test profiler initialization."""
        profiler = TUIProfiler()
        assert not profiler.is_profiling
        assert profiler.start_time is None
        assert len(profiler.metrics) == 0
    
    def test_start_stop_profiling(self):
        """Test starting and stopping profiling."""
        profiler = TUIProfiler()
        
        # Start profiling
        profiler.start_profiling(monitor_memory=False, monitor_cpu=False)
        assert profiler.is_profiling
        assert profiler.start_time is not None
        
        # Stop profiling
        profiler.stop_profiling()
        assert not profiler.is_profiling
        assert profiler.end_time is not None
    
    def test_profile_operation_context_manager(self):
        """Test profile operation context manager."""
        profiler = TUIProfiler()
        
        with profiler.profile_operation("test_operation") as metric:
            assert metric.name == "test_operation"
            assert metric.start_time > 0
            time.sleep(0.01)  # Small delay
        
        # Check that metric was completed
        assert len(profiler.metrics) == 1
        completed_metric = profiler.metrics[0]
        assert completed_metric.is_complete
        assert completed_metric.duration > 0
    
    def test_performance_metric(self):
        """Test performance metric tracking."""
        metric = PerformanceMetric("test", time.perf_counter())
        assert not metric.is_complete
        
        metric.finish()
        assert metric.is_complete
        assert metric.duration > 0
    
    def test_rendering_profile(self):
        """Test rendering profile tracking."""
        profile = RenderingProfile()
        
        # Add some render metrics
        for i in range(5):
            metric = PerformanceMetric(f"render_{i}", time.perf_counter())
            time.sleep(0.001)  # Small delay
            metric.finish()
            profile.add_render(metric)
        
        assert profile.total_renders == 5
        assert profile.avg_render_time > 0
        assert profile.min_render_time <= profile.max_render_time
    
    @pytest.mark.asyncio
    async def test_measure_render_performance(self):
        """Test render performance measurement."""
        profiler = TUIProfiler()
        
        # Mock app with refresh method
        mock_app = Mock()
        mock_app.refresh = Mock()
        profiler.app = mock_app
        
        stats = profiler.measure_render_performance(iterations=10)
        
        assert 'min_time' in stats
        assert 'max_time' in stats
        assert 'avg_time' in stats
        assert 'renders_per_second' in stats
        assert mock_app.refresh.call_count == 10


class TestVirtualScrolling:
    """Test virtual scrolling functionality."""
    
    def test_virtual_viewport(self):
        """Test virtual viewport calculations."""
        viewport = VirtualViewport(item_height=20)
        
        # Update for scroll position
        viewport.update_for_scroll(
            scroll_y=100,
            container_height=400,
            total_items=1000
        )
        
        assert viewport.scroll_offset == 100
        assert viewport.visible_height == 400
        assert viewport.start_index >= 0
        assert viewport.end_index > viewport.start_index
        assert viewport.total_height == 1000 * 20
    
    def test_simple_data_source(self):
        """Test simple data source."""
        items = [f"Item {i}" for i in range(100)]
        data_source = SimpleDataSource(items, item_height=1)
        
        assert data_source.get_item_count() == 100
        assert data_source.get_item(50) == "Item 50"
        assert data_source.get_item_height(0) == 1
        
        # Test adding/removing items
        data_source.add_item("New Item")
        assert data_source.get_item_count() == 101
        
        data_source.remove_item(0)
        assert data_source.get_item_count() == 100
    
    def test_virtual_list_item(self):
        """Test virtual list item."""
        def custom_renderer(data, index):
            return f"Custom: {data} at {index}"
        
        item = VirtualListItem("test data", 5, renderer=custom_renderer)
        assert item.data == "test data"
        assert item.index == 5
        
        rendered = item.render()
        assert "Custom: test data at 5" in str(rendered)
    
    @pytest.mark.asyncio
    async def test_virtual_list_basic_operations(self):
        """Test basic virtual list operations."""
        # Create data source
        items = [f"Item {i}" for i in range(50)]
        data_source = SimpleDataSource(items)
        
        # Create virtual list
        virtual_list = VirtualList(data_source=data_source, item_height=1)
        
        # Test data source setting
        assert virtual_list.data_source == data_source
        assert virtual_list.item_height == 1
        
        # Test cursor movement
        virtual_list.cursor_index = 0
        virtual_list.action_cursor_down()
        assert virtual_list.cursor_index == 1
        
        virtual_list.action_cursor_up()
        assert virtual_list.cursor_index == 0


class TestPagination:
    """Test pagination functionality."""
    
    def test_page_info(self):
        """Test page info calculations."""
        page_info = PageInfo()
        page_info.update(current_page=2, page_size=10, total_items=95)
        
        assert page_info.current_page == 2
        assert page_info.page_size == 10
        assert page_info.total_items == 95
        assert page_info.total_pages == 10  # ceil(95/10)
        assert page_info.has_previous is True
        assert page_info.has_next is True
        assert page_info.start_index == 10  # (2-1)*10
        assert page_info.end_index == 20   # min(10+10, 95)
    
    def test_page_request(self):
        """Test page request structure."""
        request = PageRequest(
            page=2,
            page_size=15,
            sort_configs=[SortConfig("name", SortOrder.DESC)],
            filter_configs=[FilterConfig("active", True)],
            search_query="test"
        )
        
        assert request.page == 2
        assert request.page_size == 15
        assert len(request.sort_configs) == 1
        assert len(request.filter_configs) == 1
        assert request.search_query == "test"
    
    @pytest.mark.asyncio
    async def test_in_memory_data_source(self):
        """Test in-memory data source."""
        # Create test data
        class TestUser:
            def __init__(self, name, active, score):
                self.name = name
                self.active = active
                self.score = score
        
        users = [
            TestUser("Alice", True, 95),
            TestUser("Bob", False, 87),
            TestUser("Charlie", True, 92),
            TestUser("David", False, 78),
            TestUser("Eve", True, 88)
        ]
        
        data_source = InMemoryDataSource(
            items=users,
            sort_fields=["name", "score"],
            filter_fields=[{"field": "active", "type": "boolean"}]
        )
        
        # Test basic counts
        assert len(users) == 5
        total_count = await data_source.get_total_count()
        assert total_count == 5
        
        # Test pagination
        request = PageRequest(page=1, page_size=3)
        result = await data_source.get_page(request)
        
        assert result.page_info.total_items == 5
        assert result.page_info.total_pages == 2
        assert len(result.items) == 3
        
        # Test sorting
        request = PageRequest(
            page=1,
            page_size=10,
            sort_configs=[SortConfig("score", SortOrder.DESC)]
        )
        result = await data_source.get_page(request)
        
        scores = [user.score for user in result.items]
        assert scores == sorted(scores, reverse=True)
        
        # Test filtering
        request = PageRequest(
            page=1,
            page_size=10,
            filter_configs=[FilterConfig("active", True)]
        )
        result = await data_source.get_page(request)
        
        assert all(user.active for user in result.items)
        assert len(result.items) == 3  # Only active users
    
    def test_pagination_controls(self):
        """Test pagination controls widget."""
        page_info = PageInfo()
        page_info.update(current_page=5, page_size=20, total_items=200)
        
        controls = PaginationControls(page_info)
        
        # Test initial state
        assert not controls.first_button.disabled
        assert not controls.prev_button.disabled
        assert not controls.next_button.disabled
        assert not controls.last_button.disabled
        
        # Test first page
        page_info.update(current_page=1, page_size=20, total_items=200)
        controls.update_page_info(page_info)
        
        assert controls.first_button.disabled
        assert controls.prev_button.disabled
        assert not controls.next_button.disabled
        assert not controls.last_button.disabled


class TestReactiveOptimization:
    """Test reactive optimization functionality."""
    
    def test_reactive_scheduler(self):
        """Test reactive scheduler."""
        scheduler = ReactiveScheduler(
            batch_interval=0.01,
            debounce_interval=0.05,
            max_updates_per_frame=10
        )
        
        # Create mock widget
        mock_widget = Mock()
        
        # Schedule some updates
        for i in range(5):
            scheduler.schedule_update(
                widget=mock_widget,
                update_type=UpdateType.DATA_CHANGE,
                data={"value": i},
                priority=UpdatePriority.NORMAL
            )
        
        # Check that updates are queued
        assert len(scheduler.update_queues[UpdatePriority.NORMAL]) == 5
        
        # Test stats
        stats = scheduler.get_stats()
        assert 'processed_updates' in stats
        assert 'pending_updates' in stats
    
    def test_optimized_widget(self):
        """Test optimized widget base class."""
        widget = OptimizedWidget()
        
        # Test update scheduling
        widget.schedule_update(
            update_type=UpdateType.CONTENT_CHANGE,
            data={"content": "test"},
            priority=UpdatePriority.HIGH
        )
        
        # Test batch updates
        widget.batch_update({
            "prop1": "value1",
            "prop2": "value2"
        })
        
        # Test stats
        stats = widget.get_update_stats()
        assert 'update_counters' in stats
        assert 'last_update_times' in stats
    
    def test_reactive_optimizer_singleton(self):
        """Test reactive optimizer singleton."""
        optimizer1 = get_reactive_optimizer()
        optimizer2 = get_reactive_optimizer()
        
        assert optimizer1 is optimizer2
    
    def test_widget_registration(self):
        """Test widget registration for optimization."""
        optimizer = get_reactive_optimizer()
        mock_widget = Mock()
        
        # Register widget
        register_optimized_widget(mock_widget)
        
        # Test global stats
        stats = optimizer.get_global_stats()
        assert 'active_widgets' in stats
        assert stats['active_widgets'] > 0


class TestRenderCaching:
    """Test render caching functionality."""
    
    def test_render_cache_basic_operations(self):
        """Test basic cache operations."""
        cache = RenderCache(
            max_size_mb=1,
            max_entries=10,
            policy=CachePolicy.LRU
        )
        
        # Test put and get
        cache.put("key1", "value1")
        assert cache.get("key1") == "value1"
        
        # Test miss
        assert cache.get("nonexistent") is None
        
        # Test invalidation
        assert cache.invalidate("key1") is True
        assert cache.get("key1") is None
        assert cache.invalidate("nonexistent") is False
    
    def test_cache_eviction_lru(self):
        """Test LRU cache eviction."""
        cache = RenderCache(
            max_size_mb=1,
            max_entries=3,
            policy=CachePolicy.LRU
        )
        
        # Fill cache to capacity
        cache.put("key1", "value1")
        cache.put("key2", "value2")
        cache.put("key3", "value3")
        
        # Access key1 to make it more recently used
        cache.get("key1")
        
        # Add another item, should evict key2 (least recently used)
        cache.put("key4", "value4")
        
        assert cache.get("key1") == "value1"  # Still there
        assert cache.get("key2") is None     # Evicted
        assert cache.get("key3") == "value3"  # Still there
        assert cache.get("key4") == "value4"  # New item
    
    def test_cache_ttl(self):
        """Test cache TTL (time-to-live)."""
        cache = RenderCache(
            max_size_mb=1,
            max_entries=10,
            default_ttl=0.1  # 100ms
        )
        
        # Put item with TTL
        cache.put("key1", "value1")
        assert cache.get("key1") == "value1"
        
        # Wait for expiration
        time.sleep(0.15)
        assert cache.get("key1") is None  # Should be expired
    
    def test_cache_dependencies(self):
        """Test cache dependency invalidation."""
        cache = RenderCache(max_size_mb=1, max_entries=10)
        
        # Put items with dependencies
        cache.put("key1", "value1", dependencies={"dep1", "dep2"})
        cache.put("key2", "value2", dependencies={"dep1"})
        cache.put("key3", "value3", dependencies={"dep3"})
        
        # Invalidate by dependency
        invalidated = cache.invalidate_by_dependency("dep1")
        assert invalidated == 2  # key1 and key2
        
        assert cache.get("key1") is None
        assert cache.get("key2") is None
        assert cache.get("key3") == "value3"
    
    def test_cache_stats(self):
        """Test cache statistics tracking."""
        cache = RenderCache(max_size_mb=1, max_entries=10)
        
        # Generate some cache activity
        cache.put("key1", "value1")
        cache.put("key2", "value2")
        
        # Cache hits and misses
        cache.get("key1")  # Hit
        cache.get("key1")  # Hit
        cache.get("nonexistent")  # Miss
        
        # Invalidation
        cache.invalidate("key2")
        
        stats = cache.get_stats()
        assert stats.hits == 2
        assert stats.misses == 1
        assert stats.invalidations == 1
        assert stats.hit_ratio == 2/3
    
    def test_cached_widget(self):
        """Test cached widget functionality."""
        class TestCachedWidget(CachedWidget):
            def __init__(self, content="test"):
                super().__init__(cache_ttl=60.0)
                self.content = content
                self.render_calls = 0
            
            def _do_render(self):
                self.render_calls += 1
                return f"Rendered: {self.content}"
            
            def _get_render_data(self):
                return self.content
        
        widget = TestCachedWidget("initial")
        
        # Mock the cache
        mock_cache = Mock()
        mock_cache.get_render.return_value = None  # Cache miss
        widget.set_render_cache(mock_cache)
        
        # First render should call _do_render
        result = widget.render()
        assert result == "Rendered: initial"
        assert widget.render_calls == 1
        
        # Test cache stats
        stats = widget.get_cache_stats()
        assert 'render_count' in stats
        assert 'cache_hits' in stats
        assert 'cache_misses' in stats
    
    def test_cache_manager_singleton(self):
        """Test cache manager singleton."""
        manager1 = get_cache_manager()
        manager2 = get_cache_manager()
        
        assert manager1 is manager2
    
    def test_widget_cache_registration(self):
        """Test widget cache registration."""
        manager = get_cache_manager()
        mock_widget = Mock()
        
        # Register widget
        register_cached_widget(mock_widget)
        
        # Test global stats
        stats = manager.get_global_stats()
        assert 'cache_stats' in stats
        assert 'active_widgets' in stats


class TestPerformanceIntegration:
    """Test integration between performance components."""
    
    @pytest.mark.asyncio
    async def test_profiler_with_virtual_scrolling(self):
        """Test profiler integration with virtual scrolling."""
        profiler = TUIProfiler()
        profiler.start_profiling(monitor_memory=False, monitor_cpu=False)
        
        # Create virtual list with profiling
        items = [f"Item {i}" for i in range(1000)]
        data_source = SimpleDataSource(items)
        virtual_list = VirtualList(data_source=data_source)
        
        # Simulate operations
        with profiler.profile_operation("virtual_scroll_operations"):
            virtual_list.action_cursor_down()
            virtual_list.action_page_down()
            virtual_list.scroll_to_item(500)
        
        profiler.stop_profiling()
        
        # Check that metrics were recorded
        assert len(profiler.metrics) > 0
        assert any("virtual_scroll_operations" in m.name for m in profiler.metrics)
    
    def test_cached_widget_with_reactive_optimization(self):
        """Test integration of caching and reactive optimization."""
        class IntegratedWidget(CachedWidget, OptimizedWidget):
            def __init__(self):
                CachedWidget.__init__(self, cache_ttl=30.0)
                OptimizedWidget.__init__(self)
                self.data = "initial"
            
            def _do_render(self):
                return f"Rendered: {self.data}"
            
            def update_data(self, new_data):
                self.data = new_data
                # Schedule optimized update
                self.schedule_update(
                    update_type=UpdateType.CONTENT_CHANGE,
                    data={"data": new_data},
                    priority=UpdatePriority.NORMAL
                )
                # Invalidate cache
                self.invalidate_cache()
        
        widget = IntegratedWidget()
        
        # Register for both systems
        register_cached_widget(widget)
        register_optimized_widget(widget)
        
        # Test that both systems are active
        cache_stats = widget.get_cache_stats()
        update_stats = widget.get_update_stats()
        
        assert 'cache_enabled' in cache_stats
        assert 'update_counters' in update_stats


if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v"])