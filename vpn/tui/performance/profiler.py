"""TUI Performance Profiler for VPN Manager.

This module provides comprehensive profiling tools for analyzing TUI performance,
including rendering times, memory usage, and widget optimization opportunities.
"""

import cProfile
import io
import pstats
import threading
import time
from collections.abc import Callable
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime
from functools import wraps
from pathlib import Path
from typing import Any

import psutil
from rich.console import Console
from rich.live import Live
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TaskProgressColumn,
    TextColumn,
)
from rich.table import Table
from textual.app import App
from textual.widget import Widget

console = Console()


@dataclass
class PerformanceMetric:
    """Single performance measurement."""
    name: str
    start_time: float
    end_time: float | None = None
    duration: float | None = None
    memory_before: float | None = None
    memory_after: float | None = None
    memory_delta: float | None = None
    cpu_percent: float | None = None
    custom_data: dict[str, Any] = field(default_factory=dict)

    @property
    def is_complete(self) -> bool:
        """Check if measurement is complete."""
        return self.end_time is not None

    def finish(self) -> None:
        """Complete the measurement."""
        if not self.is_complete:
            self.end_time = time.perf_counter()
            self.duration = self.end_time - self.start_time

            # Update memory usage
            if self.memory_before is not None:
                process = psutil.Process()
                self.memory_after = process.memory_info().rss / 1024 / 1024  # MB
                self.memory_delta = self.memory_after - self.memory_before


@dataclass
class RenderingProfile:
    """Profile of TUI rendering performance."""
    total_renders: int = 0
    total_render_time: float = 0.0
    min_render_time: float = float('inf')
    max_render_time: float = 0.0
    avg_render_time: float = 0.0
    slow_renders: list[PerformanceMetric] = field(default_factory=list)
    widget_profiles: dict[str, 'WidgetProfile'] = field(default_factory=dict)
    screen_profiles: dict[str, 'ScreenProfile'] = field(default_factory=dict)
    memory_usage: list[float] = field(default_factory=list)

    def add_render(self, metric: PerformanceMetric) -> None:
        """Add a render measurement."""
        if not metric.duration:
            return

        self.total_renders += 1
        self.total_render_time += metric.duration
        self.min_render_time = min(self.min_render_time, metric.duration)
        self.max_render_time = max(self.max_render_time, metric.duration)
        self.avg_render_time = self.total_render_time / self.total_renders

        # Track slow renders (>100ms)
        if metric.duration > 0.1:
            self.slow_renders.append(metric)

        # Track memory
        if metric.memory_after:
            self.memory_usage.append(metric.memory_after)


@dataclass
class WidgetProfile:
    """Performance profile for individual widgets."""
    widget_type: str
    widget_id: str | None = None
    render_count: int = 0
    total_render_time: float = 0.0
    avg_render_time: float = 0.0
    update_count: int = 0
    total_update_time: float = 0.0
    avg_update_time: float = 0.0
    memory_usage: float = 0.0

    def add_render(self, duration: float) -> None:
        """Add render measurement."""
        self.render_count += 1
        self.total_render_time += duration
        self.avg_render_time = self.total_render_time / self.render_count

    def add_update(self, duration: float) -> None:
        """Add update measurement."""
        self.update_count += 1
        self.total_update_time += duration
        self.avg_update_time = self.total_update_time / self.update_count


@dataclass
class ScreenProfile:
    """Performance profile for screens."""
    screen_name: str
    load_time: float | None = None
    switch_time: float | None = None
    widget_count: int = 0
    total_memory: float = 0.0
    render_profile: RenderingProfile = field(default_factory=RenderingProfile)


class TUIProfiler:
    """Comprehensive TUI performance profiler."""

    def __init__(self, app: App | None = None):
        """Initialize profiler."""
        self.app = app
        self.is_profiling = False
        self.start_time: float | None = None
        self.end_time: float | None = None

        # Metrics storage
        self.metrics: list[PerformanceMetric] = []
        self.active_metrics: dict[str, PerformanceMetric] = {}
        self.rendering_profile = RenderingProfile()
        self.widget_profiles: dict[str, WidgetProfile] = {}
        self.screen_profiles: dict[str, ScreenProfile] = {}

        # Memory monitoring
        self.memory_monitor_active = False
        self.memory_samples: list[Tuple[float, float]] = []  # (timestamp, memory_mb)
        self.memory_thread: threading.Thread | None = None

        # CPU profiling
        self.cpu_profiler: cProfile.Profile | None = None
        self.cpu_stats: pstats.Stats | None = None

        # Performance thresholds
        self.slow_render_threshold = 0.1  # 100ms
        self.memory_warning_threshold = 100  # 100MB
        self.cpu_warning_threshold = 80  # 80%

    def start_profiling(self,
                       monitor_memory: bool = True,
                       monitor_cpu: bool = True,
                       sample_interval: float = 0.1) -> None:
        """Start comprehensive profiling."""
        if self.is_profiling:
            console.print("[yellow]Profiling already active[/yellow]")
            return

        self.is_profiling = True
        self.start_time = time.perf_counter()

        console.print("[green]🔍 Starting TUI performance profiling...[/green]")

        # Start memory monitoring
        if monitor_memory:
            self._start_memory_monitoring(sample_interval)

        # Start CPU profiling
        if monitor_cpu:
            self.cpu_profiler = cProfile.Profile()
            self.cpu_profiler.enable()

        # Hook into app if available
        if self.app:
            self._hook_app_events()

    def stop_profiling(self) -> None:
        """Stop profiling and generate report."""
        if not self.is_profiling:
            console.print("[yellow]No active profiling session[/yellow]")
            return

        self.is_profiling = False
        self.end_time = time.perf_counter()

        # Stop memory monitoring
        self._stop_memory_monitoring()

        # Stop CPU profiling
        if self.cpu_profiler:
            self.cpu_profiler.disable()
            # Create stats
            stats_buffer = io.StringIO()
            self.cpu_stats = pstats.Stats(self.cpu_profiler, stream=stats_buffer)

        console.print("[green]✅ Profiling session completed[/green]")

        # Generate summary
        self._generate_summary()

    @contextmanager
    def profile_operation(self, operation_name: str, **custom_data):
        """Context manager for profiling specific operations."""
        metric = self._start_metric(operation_name, **custom_data)
        try:
            yield metric
        finally:
            self._end_metric(operation_name)

    def profile_widget_render(self, widget: Widget, operation: str = "render"):
        """Decorator for profiling widget operations."""
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            def wrapper(*args, **kwargs):
                widget_key = f"{widget.__class__.__name__}_{id(widget)}"
                operation_name = f"widget_{operation}_{widget_key}"

                with self.profile_operation(operation_name,
                                          widget_type=widget.__class__.__name__,
                                          widget_id=getattr(widget, 'id', None),
                                          operation=operation):
                    result = func(*args, **kwargs)

                # Update widget profile
                if operation_name in self.metrics:
                    metric = next(m for m in self.metrics if m.name == operation_name)
                    if metric.duration:
                        self._update_widget_profile(widget, operation, metric.duration)

                return result
            return wrapper
        return decorator

    def profile_screen_switch(self, screen_name: str):
        """Profile screen switching performance."""
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            def wrapper(*args, **kwargs):
                with self.profile_operation(f"screen_switch_{screen_name}",
                                          screen_name=screen_name):
                    result = func(*args, **kwargs)
                return result
            return wrapper
        return decorator

    def measure_render_performance(self, iterations: int = 100) -> dict[str, float]:
        """Measure rendering performance with controlled iterations."""
        console.print(f"[blue]📊 Measuring render performance ({iterations} iterations)...[/blue]")

        render_times = []

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            console=console
        ) as progress:
            task = progress.add_task("Measuring renders", total=iterations)

            for i in range(iterations):
                start_time = time.perf_counter()

                # Trigger render if app is available
                if self.app and hasattr(self.app, 'refresh'):
                    self.app.refresh()

                end_time = time.perf_counter()
                render_times.append(end_time - start_time)

                progress.update(task, advance=1)

        # Calculate statistics
        if render_times:
            stats = {
                'min_time': min(render_times),
                'max_time': max(render_times),
                'avg_time': sum(render_times) / len(render_times),
                'median_time': sorted(render_times)[len(render_times) // 2],
                'total_time': sum(render_times),
                'renders_per_second': len(render_times) / sum(render_times) if sum(render_times) > 0 else 0
            }
        else:
            stats = {}

        return stats

    def analyze_memory_usage(self) -> dict[str, Any]:
        """Analyze memory usage patterns."""
        if not self.memory_samples:
            return {}

        memory_values = [sample[1] for sample in self.memory_samples]

        analysis = {
            'initial_memory': memory_values[0] if memory_values else 0,
            'final_memory': memory_values[-1] if memory_values else 0,
            'peak_memory': max(memory_values) if memory_values else 0,
            'min_memory': min(memory_values) if memory_values else 0,
            'avg_memory': sum(memory_values) / len(memory_values) if memory_values else 0,
            'memory_growth': memory_values[-1] - memory_values[0] if len(memory_values) > 1 else 0,
            'sample_count': len(memory_values)
        }

        # Detect memory leaks (steady growth)
        if len(memory_values) > 10:
            # Calculate trend
            x_vals = list(range(len(memory_values)))
            y_vals = memory_values

            # Simple linear regression
            n = len(x_vals)
            sum_x = sum(x_vals)
            sum_y = sum(y_vals)
            sum_xy = sum(x * y for x, y in zip(x_vals, y_vals, strict=False))
            sum_x2 = sum(x * x for x in x_vals)

            slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
            analysis['memory_trend'] = slope
            analysis['potential_leak'] = slope > 0.1  # Growing > 0.1MB per sample

        return analysis

    def generate_report(self, output_path: Path | None = None) -> str:
        """Generate comprehensive performance report."""
        report_lines = []

        # Header
        report_lines.append("# TUI Performance Report")
        report_lines.append(f"Generated: {datetime.now().isoformat()}")
        report_lines.append("")

        # Session info
        if self.start_time and self.end_time:
            session_duration = self.end_time - self.start_time
            report_lines.append(f"**Session Duration**: {session_duration:.2f} seconds")

        report_lines.append(f"**Total Metrics Collected**: {len(self.metrics)}")
        report_lines.append("")

        # Rendering performance
        report_lines.append("## Rendering Performance")
        rp = self.rendering_profile

        if rp.total_renders > 0:
            report_lines.append(f"- **Total Renders**: {rp.total_renders}")
            report_lines.append(f"- **Average Render Time**: {rp.avg_render_time:.4f}s")
            report_lines.append(f"- **Min Render Time**: {rp.min_render_time:.4f}s")
            report_lines.append(f"- **Max Render Time**: {rp.max_render_time:.4f}s")
            report_lines.append(f"- **Slow Renders (>100ms)**: {len(rp.slow_renders)}")

            if rp.slow_renders:
                report_lines.append("\n### Slow Renders")
                for i, slow_render in enumerate(rp.slow_renders[:5]):  # Top 5
                    report_lines.append(f"{i+1}. {slow_render.name}: {slow_render.duration:.4f}s")

        report_lines.append("")

        # Memory analysis
        memory_analysis = self.analyze_memory_usage()
        if memory_analysis:
            report_lines.append("## Memory Usage")
            report_lines.append(f"- **Initial Memory**: {memory_analysis['initial_memory']:.1f} MB")
            report_lines.append(f"- **Final Memory**: {memory_analysis['final_memory']:.1f} MB")
            report_lines.append(f"- **Peak Memory**: {memory_analysis['peak_memory']:.1f} MB")
            report_lines.append(f"- **Memory Growth**: {memory_analysis['memory_growth']:.1f} MB")

            if memory_analysis.get('potential_leak'):
                report_lines.append("- **⚠️ Potential Memory Leak Detected**")

        report_lines.append("")

        # Widget performance
        if self.widget_profiles:
            report_lines.append("## Widget Performance")
            sorted_widgets = sorted(
                self.widget_profiles.items(),
                key=lambda x: x[1].avg_render_time,
                reverse=True
            )

            for widget_name, profile in sorted_widgets[:10]:  # Top 10
                report_lines.append(f"- **{widget_name}**:")
                report_lines.append(f"  - Renders: {profile.render_count}")
                report_lines.append(f"  - Avg Render Time: {profile.avg_render_time:.4f}s")
                if profile.update_count > 0:
                    report_lines.append(f"  - Updates: {profile.update_count}")
                    report_lines.append(f"  - Avg Update Time: {profile.avg_update_time:.4f}s")

        report_lines.append("")

        # Recommendations
        report_lines.append("## Performance Recommendations")
        recommendations = self._generate_recommendations()
        for rec in recommendations:
            report_lines.append(f"- {rec}")

        # Save report
        report_content = "\n".join(report_lines)

        if output_path:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(report_content)
            console.print(f"[green]📄 Report saved to: {output_path}[/green]")

        return report_content

    def show_live_stats(self, duration: float = 10.0) -> None:
        """Show live performance statistics."""
        console.print(f"[blue]📊 Showing live performance stats for {duration} seconds...[/blue]")

        def create_stats_table():
            table = Table(title="Live TUI Performance Stats")
            table.add_column("Metric", style="cyan")
            table.add_column("Value", style="green")
            table.add_column("Status", justify="center")

            # Current memory
            process = psutil.Process()
            current_memory = process.memory_info().rss / 1024 / 1024
            memory_status = "🔴" if current_memory > self.memory_warning_threshold else "🟢"
            table.add_row("Memory Usage", f"{current_memory:.1f} MB", memory_status)

            # CPU usage
            cpu_percent = process.cpu_percent()
            cpu_status = "🔴" if cpu_percent > self.cpu_warning_threshold else "🟢"
            table.add_row("CPU Usage", f"{cpu_percent:.1f}%", cpu_status)

            # Render stats
            if self.rendering_profile.total_renders > 0:
                rp = self.rendering_profile
                render_status = "🔴" if rp.avg_render_time > self.slow_render_threshold else "🟢"
                table.add_row("Avg Render Time", f"{rp.avg_render_time:.4f}s", render_status)
                table.add_row("Total Renders", str(rp.total_renders), "ℹ️")
                table.add_row("Slow Renders", str(len(rp.slow_renders)), "⚠️" if rp.slow_renders else "🟢")

            # Active metrics
            table.add_row("Active Metrics", str(len(self.active_metrics)), "ℹ️")

            return Panel(table, title="🔍 TUI Performance Monitor", border_style="blue")

        # Show live stats
        start_time = time.time()
        with Live(create_stats_table(), refresh_per_second=2) as live:
            while time.time() - start_time < duration:
                time.sleep(0.5)
                live.update(create_stats_table())

    # Private methods

    def _start_metric(self, name: str, **custom_data) -> PerformanceMetric:
        """Start a performance metric."""
        process = psutil.Process()
        metric = PerformanceMetric(
            name=name,
            start_time=time.perf_counter(),
            memory_before=process.memory_info().rss / 1024 / 1024,  # MB
            cpu_percent=process.cpu_percent(),
            custom_data=custom_data
        )

        self.active_metrics[name] = metric
        return metric

    def _end_metric(self, name: str) -> PerformanceMetric | None:
        """End a performance metric."""
        if name in self.active_metrics:
            metric = self.active_metrics.pop(name)
            metric.finish()
            self.metrics.append(metric)

            # Update rendering profile if it's a render operation
            if 'render' in name.lower():
                self.rendering_profile.add_render(metric)

            return metric
        return None

    def _update_widget_profile(self, widget: Widget, operation: str, duration: float) -> None:
        """Update widget performance profile."""
        widget_key = f"{widget.__class__.__name__}_{id(widget)}"

        if widget_key not in self.widget_profiles:
            self.widget_profiles[widget_key] = WidgetProfile(
                widget_type=widget.__class__.__name__,
                widget_id=getattr(widget, 'id', None)
            )

        profile = self.widget_profiles[widget_key]

        if operation == "render":
            profile.add_render(duration)
        elif operation == "update":
            profile.add_update(duration)

    def _start_memory_monitoring(self, sample_interval: float) -> None:
        """Start background memory monitoring."""
        if self.memory_monitor_active:
            return

        self.memory_monitor_active = True

        def monitor_memory():
            process = psutil.Process()
            start_time = time.time()

            while self.memory_monitor_active:
                try:
                    current_time = time.time() - start_time
                    memory_mb = process.memory_info().rss / 1024 / 1024
                    self.memory_samples.append((current_time, memory_mb))
                    time.sleep(sample_interval)
                except Exception:
                    break

        self.memory_thread = threading.Thread(target=monitor_memory, daemon=True)
        self.memory_thread.start()

    def _stop_memory_monitoring(self) -> None:
        """Stop memory monitoring."""
        self.memory_monitor_active = False
        if self.memory_thread and self.memory_thread.is_alive():
            self.memory_thread.join(timeout=1.0)

    def _hook_app_events(self) -> None:
        """Hook into app events for automatic profiling."""
        # This would hook into Textual app events
        # Implementation depends on specific Textual version and app structure
        pass

    def _generate_summary(self) -> None:
        """Generate and display profiling summary."""
        console.print("\n[bold blue]🔍 TUI Performance Profiling Summary[/bold blue]")

        # Create summary table
        table = Table(title="Performance Summary")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")
        table.add_column("Status", justify="center")

        # Session duration
        if self.start_time and self.end_time:
            duration = self.end_time - self.start_time
            table.add_row("Session Duration", f"{duration:.2f}s", "ℹ️")

        # Total metrics
        table.add_row("Total Metrics", str(len(self.metrics)), "ℹ️")

        # Rendering stats
        rp = self.rendering_profile
        if rp.total_renders > 0:
            status = "🔴" if rp.avg_render_time > self.slow_render_threshold else "🟢"
            table.add_row("Total Renders", str(rp.total_renders), "ℹ️")
            table.add_row("Avg Render Time", f"{rp.avg_render_time:.4f}s", status)
            table.add_row("Slow Renders", str(len(rp.slow_renders)), "⚠️" if rp.slow_renders else "🟢")

        # Memory analysis
        memory_analysis = self.analyze_memory_usage()
        if memory_analysis:
            peak_memory = memory_analysis['peak_memory']
            status = "🔴" if peak_memory > self.memory_warning_threshold else "🟢"
            table.add_row("Peak Memory", f"{peak_memory:.1f} MB", status)

            if memory_analysis.get('potential_leak'):
                table.add_row("Memory Leak", "Detected", "🔴")

        console.print(table)

        # Show recommendations
        recommendations = self._generate_recommendations()
        if recommendations:
            console.print("\n[bold yellow]💡 Performance Recommendations:[/bold yellow]")
            for rec in recommendations:
                console.print(f"  • {rec}")

    def _generate_recommendations(self) -> list[str]:
        """Generate performance improvement recommendations."""
        recommendations = []

        # Rendering recommendations
        rp = self.rendering_profile
        if rp.avg_render_time > self.slow_render_threshold:
            recommendations.append("Consider implementing render caching for slow renders")

        if len(rp.slow_renders) > rp.total_renders * 0.1:  # >10% slow renders
            recommendations.append("Optimize widgets causing slow renders")

        # Memory recommendations
        memory_analysis = self.analyze_memory_usage()
        if memory_analysis:
            if memory_analysis['peak_memory'] > self.memory_warning_threshold:
                recommendations.append("High memory usage detected - consider lazy loading")

            if memory_analysis.get('potential_leak'):
                recommendations.append("Memory leak detected - check for unclosed resources")

        # Widget recommendations
        if self.widget_profiles:
            slow_widgets = [
                name for name, profile in self.widget_profiles.items()
                if profile.avg_render_time > 0.05  # 50ms
            ]

            if slow_widgets:
                recommendations.append(f"Optimize slow widgets: {', '.join(slow_widgets[:3])}")

        # General recommendations
        if not recommendations:
            recommendations.append("Performance looks good! Consider implementing virtual scrolling for large datasets")

        return recommendations


# Global profiler instance
tui_profiler = TUIProfiler()


# Convenience functions

def start_profiling(app: App | None = None, **kwargs) -> None:
    """Start TUI profiling."""
    if app:
        tui_profiler.app = app
    tui_profiler.start_profiling(**kwargs)


def stop_profiling() -> None:
    """Stop TUI profiling."""
    tui_profiler.stop_profiling()


@contextmanager
def profile_operation(operation_name: str, **custom_data):
    """Profile a specific operation."""
    with tui_profiler.profile_operation(operation_name, **custom_data) as metric:
        yield metric


def measure_render_performance(app: App, iterations: int = 100) -> dict[str, float]:
    """Quick render performance measurement."""
    profiler = TUIProfiler(app)
    return profiler.measure_render_performance(iterations)


def generate_performance_report(output_path: Path | None = None) -> str:
    """Generate performance report."""
    return tui_profiler.generate_report(output_path)


if __name__ == "__main__":
    # Demo profiling session
    console.print("[blue]🔍 Starting demo profiling session...[/blue]")

    profiler = TUIProfiler()
    profiler.start_profiling()

    # Simulate some operations
    with profiler.profile_operation("demo_operation"):
        time.sleep(0.1)  # Simulate work

    with profiler.profile_operation("another_operation"):
        time.sleep(0.05)  # Simulate more work

    # Show live stats
    profiler.show_live_stats(duration=3.0)

    profiler.stop_profiling()

    # Generate report
    report = profiler.generate_report()
    console.print(f"\n[green]📄 Generated report ({len(report)} characters)[/green]")
