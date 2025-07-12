"""
TUI Performance Optimization Package for VPN Manager.

This package provides comprehensive performance optimization tools for the TUI,
including profiling, virtual scrolling, pagination, reactive optimization, and render caching.
"""

from .profiler import (
    TUIProfiler,
    PerformanceMetric,
    RenderingProfile,
    WidgetProfile,
    ScreenProfile,
    tui_profiler,
    start_profiling,
    stop_profiling,
    profile_operation,
    measure_render_performance,
    generate_performance_report
)

from .virtual_scrolling import (
    VirtualDataSource,
    VirtualViewport,
    VirtualList,
    VirtualListItem,
    VirtualTable,
    SimpleDataSource,
    AsyncDataSource,
    DemoDataSource,
    demo_virtual_list
)

from .pagination import (
    SortOrder,
    SortConfig,
    FilterConfig,
    PageInfo,
    PageRequest,
    PageResult,
    PaginatedDataSource,
    InMemoryDataSource,
    PaginationControls,
    SearchAndFilter,
    PaginatedTable,
    create_demo_data_source,
    demo_paginated_table
)

from .reactive_optimization import (
    UpdatePriority,
    UpdateType,
    UpdateRequest,
    UpdateBatch,
    ReactiveScheduler,
    OptimizedReactive,
    OptimizedWidget,
    ReactiveOptimizer,
    get_reactive_optimizer,
    register_optimized_widget,
    schedule_widget_update,
    create_optimized_reactive,
    ExampleOptimizedWidget
)

from .render_cache import (
    CachePolicy,
    CacheEvent,
    CacheEntry,
    CacheStats,
    RenderCache,
    WidgetRenderCache,
    CachedWidget,
    RenderCacheManager,
    get_cache_manager,
    register_cached_widget,
    ExampleCachedWidget
)

__all__ = [
    # Profiler
    'TUIProfiler',
    'PerformanceMetric',
    'RenderingProfile',
    'WidgetProfile',
    'ScreenProfile',
    'tui_profiler',
    'start_profiling',
    'stop_profiling',
    'profile_operation',
    'measure_render_performance',
    'generate_performance_report',
    
    # Virtual Scrolling
    'VirtualDataSource',
    'VirtualViewport',
    'VirtualList',
    'VirtualListItem',
    'VirtualTable',
    'SimpleDataSource',
    'AsyncDataSource',
    'DemoDataSource',
    'demo_virtual_list',
    
    # Pagination
    'SortOrder',
    'SortConfig',
    'FilterConfig',
    'PageInfo',
    'PageRequest',
    'PageResult',
    'PaginatedDataSource',
    'InMemoryDataSource',
    'PaginationControls',
    'SearchAndFilter',
    'PaginatedTable',
    'create_demo_data_source',
    'demo_paginated_table',
    
    # Reactive Optimization
    'UpdatePriority',
    'UpdateType',
    'UpdateRequest',
    'UpdateBatch',
    'ReactiveScheduler',
    'OptimizedReactive',
    'OptimizedWidget',
    'ReactiveOptimizer',
    'get_reactive_optimizer',
    'register_optimized_widget',
    'schedule_widget_update',
    'create_optimized_reactive',
    'ExampleOptimizedWidget',
    
    # Render Caching
    'CachePolicy',
    'CacheEvent',
    'CacheEntry',
    'CacheStats',
    'RenderCache',
    'WidgetRenderCache',
    'CachedWidget',
    'RenderCacheManager',
    'get_cache_manager',
    'register_cached_widget',
    'ExampleCachedWidget'
]


def initialize_performance_system(
    enable_profiling: bool = False,
    enable_caching: bool = True,
    enable_reactive_optimization: bool = True,
    cache_size_mb: int = 100,
    profiling_duration: float = 60.0
) -> dict:
    """
    Initialize the complete TUI performance system.
    
    Args:
        enable_profiling: Enable performance profiling
        enable_caching: Enable render caching
        enable_reactive_optimization: Enable reactive update optimization
        cache_size_mb: Cache size in megabytes
        profiling_duration: Profiling duration in seconds
    
    Returns:
        Dictionary with initialized components
    """
    components = {}
    
    # Initialize profiler
    if enable_profiling:
        components['profiler'] = tui_profiler
        start_profiling()
    
    # Initialize render cache manager
    if enable_caching:
        cache_manager = get_cache_manager()
        # Update cache size if needed
        cache_manager.render_cache.max_size_bytes = cache_size_mb * 1024 * 1024
        components['cache_manager'] = cache_manager
    
    # Initialize reactive optimizer
    if enable_reactive_optimization:
        optimizer = get_reactive_optimizer()
        optimizer.enable_monitoring()
        components['reactive_optimizer'] = optimizer
    
    return components


def get_performance_summary() -> dict:
    """
    Get comprehensive performance summary from all systems.
    
    Returns:
        Dictionary with performance statistics from all components
    """
    summary = {
        'timestamp': time.time(),
        'components': {}
    }
    
    # Profiler stats
    try:
        profiler_stats = tui_profiler.get_stats() if hasattr(tui_profiler, 'get_stats') else {}
        summary['components']['profiler'] = profiler_stats
    except Exception:
        summary['components']['profiler'] = {'error': 'Failed to get profiler stats'}
    
    # Cache manager stats
    try:
        cache_manager = get_cache_manager()
        cache_stats = cache_manager.get_global_stats()
        summary['components']['cache'] = cache_stats
    except Exception:
        summary['components']['cache'] = {'error': 'Failed to get cache stats'}
    
    # Reactive optimizer stats
    try:
        optimizer = get_reactive_optimizer()
        optimizer_stats = optimizer.get_global_stats()
        summary['components']['reactive'] = optimizer_stats
    except Exception:
        summary['components']['reactive'] = {'error': 'Failed to get reactive stats'}
    
    return summary


def optimize_widget_for_performance(widget, 
                                   enable_caching: bool = True,
                                   enable_reactive_optimization: bool = True,
                                   cache_ttl: float = 300.0) -> None:
    """
    Optimize a widget for maximum performance.
    
    Args:
        widget: Widget to optimize
        enable_caching: Enable render caching for the widget
        enable_reactive_optimization: Enable reactive optimization
        cache_ttl: Cache time-to-live in seconds
    """
    
    # Register for caching
    if enable_caching:
        register_cached_widget(widget)
        
        # Set cache TTL if widget supports it
        if hasattr(widget, 'cache_ttl'):
            widget.cache_ttl = cache_ttl
    
    # Register for reactive optimization
    if enable_reactive_optimization:
        register_optimized_widget(widget)


def shutdown_performance_system() -> None:
    """Shutdown all performance optimization components."""
    
    # Stop profiling
    try:
        stop_profiling()
    except Exception:
        pass
    
    # Shutdown cache manager
    try:
        cache_manager = get_cache_manager()
        cache_manager.shutdown()
    except Exception:
        pass
    
    # Shutdown reactive optimizer
    try:
        optimizer = get_reactive_optimizer()
        optimizer.shutdown()
    except Exception:
        pass


# Import time for performance summary
import time