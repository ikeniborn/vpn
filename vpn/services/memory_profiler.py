"""Memory profiling and optimization service for VPN Manager.

This module provides comprehensive memory monitoring, leak detection,
and optimization strategies for the VPN Manager application.
"""

import asyncio
import gc
import os
import tracemalloc
import weakref
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

import psutil

from vpn.services.base_service import EnhancedBaseService, ServiceHealth, ServiceStatus
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class MemorySnapshot:
    """Memory usage snapshot at a point in time."""
    timestamp: datetime
    process_memory_mb: float
    rss_memory_mb: float
    vms_memory_mb: float
    python_objects_count: int
    gc_generation_counts: list[int]
    largest_objects: list[tuple[str, int]]  # (type_name, count)
    tracemalloc_top: list[tuple[str, float]]  # (filename:lineno, size_mb)


@dataclass
class MemoryLeak:
    """Detected memory leak information."""
    object_type: str
    count_increase: int
    size_increase_mb: float
    growth_rate_per_hour: float
    first_detected: datetime
    last_updated: datetime
    severity: str  # 'low', 'medium', 'high', 'critical'


@dataclass
class MemoryProfilerConfig:
    """Configuration for memory profiler."""
    snapshot_interval: float = 300.0  # 5 minutes
    tracemalloc_enabled: bool = True
    tracemalloc_frames: int = 25
    leak_detection_enabled: bool = True
    leak_threshold_mb: float = 10.0
    max_snapshots: int = 100
    gc_optimization_enabled: bool = True


class MemoryProfiler(EnhancedBaseService):
    """Advanced memory profiling and optimization service.
    
    Features:
    - Continuous memory monitoring
    - Memory leak detection
    - Garbage collection optimization
    - Object tracking and analysis
    - Memory usage alerts
    - Automatic cleanup recommendations
    """

    def __init__(self, config: MemoryProfilerConfig | None = None):
        """Initialize memory profiler.
        
        Args:
            config: Profiler configuration
        """
        super().__init__(name="MemoryProfiler")

        self.config = config or MemoryProfilerConfig()
        self.process = psutil.Process(os.getpid())

        # Memory snapshots
        self._snapshots: list[MemorySnapshot] = []
        self._object_counts: dict[str, list[tuple[datetime, int]]] = defaultdict(list)

        # Leak detection
        self._detected_leaks: dict[str, MemoryLeak] = {}
        self._baseline_snapshot: MemorySnapshot | None = None

        # Object tracking
        self._tracked_objects: set[weakref.ReferenceType] = set()
        self._object_creation_stats: dict[str, int] = defaultdict(int)

        # Monitoring task
        self._monitoring_task: asyncio.Task | None = None

        # Lock for thread safety
        self._lock = asyncio.Lock()

        self.logger.info("Memory profiler initialized")

    async def start(self) -> None:
        """Start memory profiler and monitoring."""
        await super().start()

        # Enable tracemalloc if configured
        if self.config.tracemalloc_enabled and not tracemalloc.is_tracing():
            tracemalloc.start(self.config.tracemalloc_frames)
            self.logger.info("Tracemalloc started")

        # Take baseline snapshot
        self._baseline_snapshot = await self._take_snapshot()

        # Start monitoring task
        self._monitoring_task = asyncio.create_task(self._monitoring_loop())

        self.logger.info("Memory profiler started")

    async def stop(self) -> None:
        """Stop memory profiler."""
        if self._monitoring_task:
            self._monitoring_task.cancel()
            try:
                await self._monitoring_task
            except asyncio.CancelledError:
                pass

        # Stop tracemalloc
        if tracemalloc.is_tracing():
            tracemalloc.stop()
            self.logger.info("Tracemalloc stopped")

        await super().stop()
        self.logger.info("Memory profiler stopped")

    async def get_current_memory_usage(self) -> dict[str, Any]:
        """Get current memory usage information.
        
        Returns:
            Dictionary with current memory metrics
        """
        try:
            # Process memory info
            memory_info = self.process.memory_info()
            memory_percent = self.process.memory_percent()

            # Python object counts
            object_counts = {}
            for obj_type, count in self._get_object_counts().items():
                object_counts[obj_type] = count

            # Garbage collection stats
            gc_stats = {f"generation_{i}": len(gc.get_objects(i)) for i in range(3)}

            # Tracemalloc current stats
            tracemalloc_stats = {}
            if tracemalloc.is_tracing():
                current, peak = tracemalloc.get_traced_memory()
                tracemalloc_stats = {
                    'current_mb': current / (1024 * 1024),
                    'peak_mb': peak / (1024 * 1024)
                }

            return {
                'process_memory_mb': memory_info.rss / (1024 * 1024),
                'process_memory_percent': memory_percent,
                'virtual_memory_mb': memory_info.vms / (1024 * 1024),
                'python_objects': object_counts,
                'garbage_collection': gc_stats,
                'tracemalloc': tracemalloc_stats,
                'tracked_objects_count': len(self._tracked_objects),
                'timestamp': datetime.utcnow().isoformat()
            }

        except Exception as e:
            self.logger.error(f"Failed to get memory usage: {e}")
            return {}

    async def take_manual_snapshot(self) -> MemorySnapshot:
        """Take a manual memory snapshot.
        
        Returns:
            Memory snapshot
        """
        return await self._take_snapshot()

    async def detect_memory_leaks(self) -> list[MemoryLeak]:
        """Detect potential memory leaks.
        
        Returns:
            List of detected memory leaks
        """
        if not self.config.leak_detection_enabled:
            return []

        async with self._lock:
            current_time = datetime.utcnow()
            detected_leaks = []

            # Analyze object count trends
            for obj_type, count_history in self._object_counts.items():
                if len(count_history) < 3:  # Need at least 3 data points
                    continue

                # Calculate growth trend
                growth_trend = self._calculate_growth_trend(count_history)

                if growth_trend > 0:  # Growing
                    # Check if it's a significant leak
                    latest_count = count_history[-1][1]
                    baseline_count = count_history[0][1] if count_history else 0

                    count_increase = latest_count - baseline_count

                    # Estimate memory impact (rough)
                    estimated_size_mb = count_increase * self._estimate_object_size(obj_type) / (1024 * 1024)

                    if estimated_size_mb > self.config.leak_threshold_mb:
                        # Calculate growth rate per hour
                        time_diff = (count_history[-1][0] - count_history[0][0]).total_seconds() / 3600
                        growth_rate = count_increase / time_diff if time_diff > 0 else 0

                        # Determine severity
                        severity = self._calculate_leak_severity(estimated_size_mb, growth_rate)

                        leak = MemoryLeak(
                            object_type=obj_type,
                            count_increase=count_increase,
                            size_increase_mb=estimated_size_mb,
                            growth_rate_per_hour=growth_rate,
                            first_detected=self._detected_leaks.get(obj_type,
                                MemoryLeak(obj_type, 0, 0, 0, current_time, current_time, 'low')).first_detected,
                            last_updated=current_time,
                            severity=severity
                        )

                        self._detected_leaks[obj_type] = leak
                        detected_leaks.append(leak)

            return detected_leaks

    async def optimize_memory(self) -> dict[str, Any]:
        """Perform memory optimization operations.
        
        Returns:
            Dictionary with optimization results
        """
        optimization_results = {
            'actions_taken': [],
            'memory_freed_mb': 0,
            'before_memory_mb': 0,
            'after_memory_mb': 0
        }

        try:
            # Get memory before optimization
            before_memory = self.process.memory_info().rss / (1024 * 1024)
            optimization_results['before_memory_mb'] = before_memory

            # Force garbage collection
            if self.config.gc_optimization_enabled:
                collected_objects = gc.collect()
                optimization_results['actions_taken'].append(f"Garbage collection: {collected_objects} objects")

            # Clean up weak references
            cleaned_refs = self._cleanup_weak_references()
            if cleaned_refs > 0:
                optimization_results['actions_taken'].append(f"Cleaned {cleaned_refs} weak references")

            # Clean up old snapshots
            cleaned_snapshots = await self._cleanup_old_snapshots()
            if cleaned_snapshots > 0:
                optimization_results['actions_taken'].append(f"Cleaned {cleaned_snapshots} old snapshots")

            # Get memory after optimization
            after_memory = self.process.memory_info().rss / (1024 * 1024)
            optimization_results['after_memory_mb'] = after_memory
            optimization_results['memory_freed_mb'] = before_memory - after_memory

            self.logger.info(f"Memory optimization completed: {optimization_results}")

        except Exception as e:
            self.logger.error(f"Memory optimization failed: {e}")
            optimization_results['error'] = str(e)

        return optimization_results

    async def get_memory_report(self) -> dict[str, Any]:
        """Generate comprehensive memory usage report.
        
        Returns:
            Detailed memory report
        """
        current_usage = await self.get_current_memory_usage()
        detected_leaks = await self.detect_memory_leaks()

        # Calculate trends
        memory_trend = self._calculate_memory_trend()

        # Top memory consumers
        top_objects = self._get_top_memory_consumers()

        # Tracemalloc top allocations
        tracemalloc_top = []
        if tracemalloc.is_tracing():
            tracemalloc_top = self._get_tracemalloc_top()

        return {
            'current_usage': current_usage,
            'memory_trend': memory_trend,
            'detected_leaks': [
                {
                    'object_type': leak.object_type,
                    'count_increase': leak.count_increase,
                    'size_increase_mb': leak.size_increase_mb,
                    'growth_rate_per_hour': leak.growth_rate_per_hour,
                    'severity': leak.severity,
                    'first_detected': leak.first_detected.isoformat(),
                    'last_updated': leak.last_updated.isoformat()
                }
                for leak in detected_leaks
            ],
            'top_memory_consumers': top_objects,
            'tracemalloc_allocations': tracemalloc_top,
            'snapshots_count': len(self._snapshots),
            'baseline_memory_mb': self._baseline_snapshot.process_memory_mb if self._baseline_snapshot else 0,
            'recommendations': self._generate_recommendations(detected_leaks, current_usage),
            'generated_at': datetime.utcnow().isoformat()
        }

    def track_object(self, obj: Any) -> None:
        """Track an object for memory monitoring.
        
        Args:
            obj: Object to track
        """
        try:
            ref = weakref.ref(obj)
            self._tracked_objects.add(ref)

            obj_type = type(obj).__name__
            self._object_creation_stats[obj_type] += 1

        except TypeError:
            # Object doesn't support weak references
            pass

    async def _monitoring_loop(self):
        """Background monitoring loop."""
        while True:
            try:
                await asyncio.sleep(self.config.snapshot_interval)

                # Take snapshot
                snapshot = await self._take_snapshot()

                # Update object counts
                await self._update_object_counts()

                # Detect leaks periodically
                if self.config.leak_detection_enabled:
                    leaks = await self.detect_memory_leaks()
                    if leaks:
                        self.logger.warning(f"Detected {len(leaks)} potential memory leaks")

            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in memory monitoring loop: {e}")

    async def _take_snapshot(self) -> MemorySnapshot:
        """Take a memory usage snapshot."""
        current_time = datetime.utcnow()

        # Process memory info
        memory_info = self.process.memory_info()

        # Python object counts
        object_counts = self._get_object_counts()
        total_objects = sum(object_counts.values())

        # Top objects by count
        top_objects = sorted(object_counts.items(), key=lambda x: x[1], reverse=True)[:10]

        # GC generation counts
        gc_counts = [len(gc.get_objects(i)) for i in range(3)]

        # Tracemalloc top allocations
        tracemalloc_top = []
        if tracemalloc.is_tracing():
            tracemalloc_top = self._get_tracemalloc_top()[:10]

        snapshot = MemorySnapshot(
            timestamp=current_time,
            process_memory_mb=memory_info.rss / (1024 * 1024),
            rss_memory_mb=memory_info.rss / (1024 * 1024),
            vms_memory_mb=memory_info.vms / (1024 * 1024),
            python_objects_count=total_objects,
            gc_generation_counts=gc_counts,
            largest_objects=top_objects,
            tracemalloc_top=tracemalloc_top
        )

        async with self._lock:
            self._snapshots.append(snapshot)

            # Limit snapshots to max count
            if len(self._snapshots) > self.config.max_snapshots:
                self._snapshots = self._snapshots[-self.config.max_snapshots:]

        return snapshot

    async def _update_object_counts(self):
        """Update object count history."""
        current_time = datetime.utcnow()
        object_counts = self._get_object_counts()

        async with self._lock:
            for obj_type, count in object_counts.items():
                self._object_counts[obj_type].append((current_time, count))

                # Keep only recent history (last 24 hours)
                cutoff_time = current_time - timedelta(hours=24)
                self._object_counts[obj_type] = [
                    (ts, cnt) for ts, cnt in self._object_counts[obj_type]
                    if ts > cutoff_time
                ]

    def _get_object_counts(self) -> dict[str, int]:
        """Get current Python object counts by type."""
        return {
            obj_type.__name__: count
            for obj_type, count in gc.get_count().__dict__.items()
            if isinstance(count, int)
        }

    def _get_tracemalloc_top(self) -> list[tuple[str, float]]:
        """Get top memory allocations from tracemalloc."""
        if not tracemalloc.is_tracing():
            return []

        snapshot = tracemalloc.take_snapshot()
        top_stats = snapshot.statistics('lineno')

        return [
            (f"{stat.traceback.format()[-1]}", stat.size / (1024 * 1024))
            for stat in top_stats[:10]
        ]

    def _get_top_memory_consumers(self) -> list[dict[str, Any]]:
        """Get top memory consuming object types."""
        object_counts = self._get_object_counts()

        # Estimate memory usage per object type
        estimated_usage = []
        for obj_type, count in object_counts.items():
            estimated_size = self._estimate_object_size(obj_type) * count
            estimated_usage.append({
                'type': obj_type,
                'count': count,
                'estimated_size_mb': estimated_size / (1024 * 1024)
            })

        return sorted(estimated_usage, key=lambda x: x['estimated_size_mb'], reverse=True)[:10]

    def _estimate_object_size(self, obj_type: str) -> int:
        """Estimate size of object by type (rough approximation)."""
        size_estimates = {
            'dict': 1000,
            'list': 500,
            'str': 100,
            'int': 28,
            'float': 24,
            'tuple': 200,
            'set': 500,
            'bytes': 50,
            'function': 1000,
            'type': 2000,
            'module': 5000,
        }
        return size_estimates.get(obj_type, 500)  # Default 500 bytes

    def _calculate_growth_trend(self, count_history: list[tuple[datetime, int]]) -> float:
        """Calculate growth trend for object counts."""
        if len(count_history) < 2:
            return 0.0

        # Simple linear regression for trend
        n = len(count_history)
        x_sum = sum(i for i in range(n))
        y_sum = sum(count for _, count in count_history)
        xy_sum = sum(i * count for i, (_, count) in enumerate(count_history))
        x2_sum = sum(i * i for i in range(n))

        if n * x2_sum - x_sum * x_sum == 0:
            return 0.0

        slope = (n * xy_sum - x_sum * y_sum) / (n * x2_sum - x_sum * x_sum)
        return slope

    def _calculate_leak_severity(self, size_mb: float, growth_rate: float) -> str:
        """Calculate severity of a memory leak."""
        if size_mb > 100 or growth_rate > 1000:
            return 'critical'
        elif size_mb > 50 or growth_rate > 500:
            return 'high'
        elif size_mb > 20 or growth_rate > 100:
            return 'medium'
        else:
            return 'low'

    def _calculate_memory_trend(self) -> dict[str, Any]:
        """Calculate memory usage trend."""
        if len(self._snapshots) < 2:
            return {'trend': 'unknown', 'change_mb': 0}

        recent_snapshots = self._snapshots[-10:]  # Last 10 snapshots
        first_memory = recent_snapshots[0].process_memory_mb
        last_memory = recent_snapshots[-1].process_memory_mb

        change_mb = last_memory - first_memory
        trend = 'increasing' if change_mb > 5 else 'decreasing' if change_mb < -5 else 'stable'

        return {
            'trend': trend,
            'change_mb': change_mb,
            'first_memory_mb': first_memory,
            'last_memory_mb': last_memory,
            'snapshots_analyzed': len(recent_snapshots)
        }

    def _cleanup_weak_references(self) -> int:
        """Clean up dead weak references."""
        initial_count = len(self._tracked_objects)
        self._tracked_objects = {ref for ref in self._tracked_objects if ref() is not None}
        return initial_count - len(self._tracked_objects)

    async def _cleanup_old_snapshots(self) -> int:
        """Clean up old snapshots beyond the limit."""
        async with self._lock:
            initial_count = len(self._snapshots)
            if initial_count > self.config.max_snapshots:
                self._snapshots = self._snapshots[-self.config.max_snapshots:]
                return initial_count - len(self._snapshots)
            return 0

    def _generate_recommendations(self, leaks: list[MemoryLeak], current_usage: dict[str, Any]) -> list[str]:
        """Generate memory optimization recommendations."""
        recommendations = []

        # Leak-based recommendations
        critical_leaks = [leak for leak in leaks if leak.severity == 'critical']
        if critical_leaks:
            recommendations.append("CRITICAL: Address critical memory leaks immediately")
            for leak in critical_leaks:
                recommendations.append(f"- Investigate {leak.object_type} creation patterns")

        # Memory usage recommendations
        memory_percent = current_usage.get('process_memory_percent', 0)
        if memory_percent > 80:
            recommendations.append("High memory usage detected (>80%)")
            recommendations.append("- Consider reducing cache sizes")
            recommendations.append("- Run garbage collection more frequently")

        # Object count recommendations
        python_objects = current_usage.get('python_objects', {})
        for obj_type, count in python_objects.items():
            if count > 100000:  # Arbitrary threshold
                recommendations.append(f"High {obj_type} count ({count:,}) - consider optimization")

        if not recommendations:
            recommendations.append("Memory usage appears healthy")

        return recommendations

    async def get_health(self) -> ServiceHealth:
        """Get service health with memory-specific metrics."""
        base_health = await super().get_health()

        try:
            current_usage = await self.get_current_memory_usage()
            leaks = await self.detect_memory_leaks()

            # Health scoring based on memory metrics
            health_score = 1.0
            memory_percent = current_usage.get('process_memory_percent', 0)

            if memory_percent > 90:
                health_score -= 0.5  # Very high memory usage
            elif memory_percent > 80:
                health_score -= 0.3  # High memory usage

            critical_leaks = len([leak for leak in leaks if leak.severity == 'critical'])
            if critical_leaks > 0:
                health_score -= 0.4  # Critical leaks

            if health_score >= 0.8:
                status = ServiceStatus.HEALTHY
            elif health_score >= 0.5:
                status = ServiceStatus.DEGRADED
            else:
                status = ServiceStatus.UNHEALTHY

            return ServiceHealth(
                service_name=self.name,
                status=status,
                details={
                    **base_health.details,
                    'memory_usage': current_usage,
                    'detected_leaks': len(leaks),
                    'critical_leaks': critical_leaks,
                    'health_score': health_score
                }
            )

        except Exception as e:
            self.logger.error(f"Failed to get memory profiler health: {e}")
            return ServiceHealth(
                service_name=self.name,
                status=ServiceStatus.UNHEALTHY,
                details={'error': str(e)}
            )


# Global instance
_memory_profiler: MemoryProfiler | None = None


async def get_memory_profiler() -> MemoryProfiler:
    """Get or create the global memory profiler instance."""
    global _memory_profiler

    if _memory_profiler is None:
        _memory_profiler = MemoryProfiler()
        await _memory_profiler.start()

    return _memory_profiler


async def shutdown_memory_profiler():
    """Shutdown the global memory profiler."""
    global _memory_profiler

    if _memory_profiler is not None:
        await _memory_profiler.stop()
        _memory_profiler = None
