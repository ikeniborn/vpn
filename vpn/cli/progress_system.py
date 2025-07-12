"""
Progress bar system for long-running CLI operations.

This module provides comprehensive progress tracking for CLI operations:
- Rich progress bars with multiple styles
- Task progress tracking with ETA
- Spinner animations for indeterminate operations
- Nested progress for complex operations
- Real-time status updates
"""

import asyncio
import time
from typing import Dict, List, Optional, Any, Callable, Union, AsyncIterator
from dataclasses import dataclass
from contextlib import asynccontextmanager
from enum import Enum

from rich.console import Console
from rich.progress import (
    Progress, TaskID, SpinnerColumn, TextColumn, BarColumn, 
    TaskProgressColumn, TimeRemainingColumn, TimeElapsedColumn,
    MofNCompleteColumn, TransferSpeedColumn, FileSizeColumn,
    ProgressColumn
)
from rich.live import Live
from rich.table import Table
from rich.panel import Panel
from rich.text import Text
from rich.spinner import Spinner

console = Console()


class ProgressStyle(Enum):
    """Different progress bar styles."""
    DEFAULT = "default"
    MINIMAL = "minimal"
    DETAILED = "detailed"
    TRANSFER = "transfer"
    SPINNER = "spinner"
    CUSTOM = "custom"


@dataclass
class ProgressTask:
    """Represents a progress task."""
    name: str
    total: Optional[float] = None
    completed: float = 0
    description: str = ""
    visible: bool = True
    started: bool = False
    finished: bool = False
    task_id: Optional[TaskID] = None
    subtasks: List['ProgressTask'] = None
    
    def __post_init__(self):
        if self.subtasks is None:
            self.subtasks = []


class ProgressTracker:
    """Enhanced progress tracker with multiple styles and features."""
    
    def __init__(self, style: ProgressStyle = ProgressStyle.DEFAULT):
        """Initialize progress tracker."""
        self.style = style
        self.progress: Optional[Progress] = None
        self.tasks: Dict[str, ProgressTask] = {}
        self.live: Optional[Live] = None
        self._setup_progress()
    
    def _setup_progress(self):
        """Set up progress bar based on style."""
        if self.style == ProgressStyle.DEFAULT:
            self.progress = Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TaskProgressColumn(),
                TimeRemainingColumn(),
                console=console,
                expand=True
            )
        
        elif self.style == ProgressStyle.MINIMAL:
            self.progress = Progress(
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=20),
                TaskProgressColumn(),
                console=console
            )
        
        elif self.style == ProgressStyle.DETAILED:
            self.progress = Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TaskProgressColumn(),
                MofNCompleteColumn(),
                TimeElapsedColumn(),
                TimeRemainingColumn(),
                console=console,
                expand=True
            )
        
        elif self.style == ProgressStyle.TRANSFER:
            self.progress = Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TaskProgressColumn(),
                FileSizeColumn(),
                TransferSpeedColumn(),
                TimeRemainingColumn(),
                console=console,
                expand=True
            )
        
        elif self.style == ProgressStyle.SPINNER:
            self.progress = Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console
            )
    
    def start(self):
        """Start the progress tracker."""
        if self.progress:
            self.progress.start()
            self.live = Live(self.progress, console=console, refresh_per_second=10)
            self.live.start()
    
    def stop(self):
        """Stop the progress tracker."""
        if self.live:
            self.live.stop()
        if self.progress:
            self.progress.stop()
    
    def add_task(
        self,
        name: str,
        description: str,
        total: Optional[float] = None,
        visible: bool = True
    ) -> str:
        """Add a new progress task."""
        if not self.progress:
            return name
        
        task_id = self.progress.add_task(description, total=total, visible=visible)
        
        task = ProgressTask(
            name=name,
            total=total,
            description=description,
            visible=visible,
            task_id=task_id
        )
        
        self.tasks[name] = task
        return name
    
    def update_task(
        self,
        name: str,
        advance: Optional[float] = None,
        completed: Optional[float] = None,
        description: Optional[str] = None,
        total: Optional[float] = None
    ):
        """Update a progress task."""
        if name not in self.tasks or not self.progress:
            return
        
        task = self.tasks[name]
        
        kwargs = {}
        if advance is not None:
            kwargs['advance'] = advance
            task.completed += advance
        
        if completed is not None:
            kwargs['completed'] = completed
            task.completed = completed
        
        if description is not None:
            kwargs['description'] = description
            task.description = description
        
        if total is not None:
            kwargs['total'] = total
            task.total = total
        
        if task.task_id is not None:
            self.progress.update(task.task_id, **kwargs)
    
    def complete_task(self, name: str):
        """Mark a task as completed."""
        if name in self.tasks:
            task = self.tasks[name]
            task.finished = True
            if task.task_id is not None and self.progress:
                if task.total:
                    self.progress.update(task.task_id, completed=task.total)
                self.progress.update(task.task_id, description=f"✓ {task.description}")
    
    def remove_task(self, name: str):
        """Remove a progress task."""
        if name in self.tasks and self.progress:
            task = self.tasks[name]
            if task.task_id is not None:
                self.progress.remove_task(task.task_id)
            del self.tasks[name]
    
    @asynccontextmanager
    async def task(
        self,
        name: str,
        description: str,
        total: Optional[float] = None
    ):
        """Context manager for progress tasks."""
        task_name = self.add_task(name, description, total)
        try:
            yield self
        finally:
            self.complete_task(task_name)


class OperationProgress:
    """Progress tracking for specific operations."""
    
    def __init__(self, operation_name: str, style: ProgressStyle = ProgressStyle.DEFAULT):
        """Initialize operation progress."""
        self.operation_name = operation_name
        self.tracker = ProgressTracker(style)
        self.start_time = time.time()
    
    async def __aenter__(self):
        """Async context manager entry."""
        self.tracker.start()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        elapsed = time.time() - self.start_time
        
        if exc_type is None:
            console.print(f"[green]✓ {self.operation_name} completed in {elapsed:.2f}s[/green]")
        else:
            console.print(f"[red]✗ {self.operation_name} failed after {elapsed:.2f}s[/red]")
        
        # Give time to see final status
        await asyncio.sleep(0.5)
        self.tracker.stop()
    
    def add_task(self, name: str, description: str, total: Optional[float] = None) -> str:
        """Add a task to this operation."""
        return self.tracker.add_task(name, description, total)
    
    def update(self, name: str, **kwargs):
        """Update a task."""
        self.tracker.update_task(name, **kwargs)
    
    def complete(self, name: str):
        """Complete a task."""
        self.tracker.complete_task(name)


# Pre-configured progress styles for common operations

async def with_progress(
    operation_name: str,
    operation_func: Callable,
    style: ProgressStyle = ProgressStyle.DEFAULT,
    *args,
    **kwargs
) -> Any:
    """Execute an operation with progress tracking."""
    async with OperationProgress(operation_name, style) as progress:
        return await operation_func(progress, *args, **kwargs)


async def user_creation_progress(
    progress: OperationProgress,
    users_data: List[Dict[str, Any]]
) -> List[Any]:
    """Progress tracking for user creation."""
    task_name = progress.add_task(
        "create_users",
        "Creating users...",
        total=len(users_data)
    )
    
    created_users = []
    
    for i, user_data in enumerate(users_data):
        progress.update(
            task_name,
            description=f"Creating user: {user_data.get('username', f'user_{i}')}",
            completed=i
        )
        
        # Simulate user creation (replace with actual logic)
        await asyncio.sleep(0.5)  # Simulate API call
        
        # Here you would call the actual user creation logic
        # user = await user_manager.create(user_data)
        # created_users.append(user)
        
        created_users.append(f"user_{i}")  # Placeholder
    
    progress.complete(task_name)
    return created_users


async def server_startup_progress(
    progress: OperationProgress,
    server_names: List[str]
) -> Dict[str, bool]:
    """Progress tracking for server startup."""
    task_name = progress.add_task(
        "start_servers",
        "Starting servers...",
        total=len(server_names)
    )
    
    results = {}
    
    for i, server_name in enumerate(server_names):
        progress.update(
            task_name,
            description=f"Starting server: {server_name}",
            completed=i
        )
        
        # Simulate server startup
        await asyncio.sleep(1.0)  # Simulate startup time
        
        # Here you would call actual server startup logic
        # success = await server_manager.start(server_name)
        # results[server_name] = success
        
        results[server_name] = True  # Placeholder
    
    progress.complete(task_name)
    return results


async def backup_progress(
    progress: OperationProgress,
    backup_path: str,
    components: List[str]
) -> str:
    """Progress tracking for backup operations."""
    # Main backup task
    main_task = progress.add_task(
        "backup_main",
        "Creating backup...",
        total=len(components)
    )
    
    for i, component in enumerate(components):
        # Individual component task
        component_task = progress.add_task(
            f"backup_{component}",
            f"Backing up {component}...",
            total=100
        )
        
        # Simulate component backup with sub-progress
        for j in range(100):
            progress.update(
                component_task,
                advance=1,
                description=f"Backing up {component}... ({j+1}%)"
            )
            await asyncio.sleep(0.02)  # Simulate work
        
        progress.complete(component_task)
        progress.update(main_task, advance=1)
    
    progress.complete(main_task)
    return backup_path


async def migration_progress(
    progress: OperationProgress,
    source_path: str,
    items_count: int
) -> Dict[str, Any]:
    """Progress tracking for migration operations."""
    # Discovery phase
    discovery_task = progress.add_task(
        "discovery",
        "Discovering items to migrate...",
        total=None  # Indeterminate
    )
    
    await asyncio.sleep(2)  # Simulate discovery
    progress.complete(discovery_task)
    
    # Migration phase
    migration_task = progress.add_task(
        "migration",
        "Migrating items...",
        total=items_count
    )
    
    migrated_items = []
    
    for i in range(items_count):
        progress.update(
            migration_task,
            description=f"Migrating item {i+1}/{items_count}",
            advance=1
        )
        
        # Simulate migration work
        await asyncio.sleep(0.3)
        migrated_items.append(f"item_{i}")
    
    progress.complete(migration_task)
    
    return {
        "migrated_count": len(migrated_items),
        "items": migrated_items,
        "source": source_path
    }


class BatchProgressTracker:
    """Progress tracker for batch operations with multiple parallel tasks."""
    
    def __init__(self, operation_name: str):
        """Initialize batch progress tracker."""
        self.operation_name = operation_name
        self.progress = Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            MofNCompleteColumn(),
            TimeRemainingColumn(),
            console=console,
            expand=True
        )
        self.active_tasks: Dict[str, TaskID] = {}
        self.completed_tasks = 0
        self.total_tasks = 0
    
    async def __aenter__(self):
        """Async context manager entry."""
        self.progress.start()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await asyncio.sleep(0.5)  # Show final state
        self.progress.stop()
        
        if exc_type is None:
            console.print(f"[green]✓ {self.operation_name} completed: {self.completed_tasks}/{self.total_tasks} tasks[/green]")
        else:
            console.print(f"[red]✗ {self.operation_name} failed: {self.completed_tasks}/{self.total_tasks} tasks completed[/red]")
    
    def add_batch_task(self, name: str, description: str, total: float = 100) -> str:
        """Add a task to the batch."""
        task_id = self.progress.add_task(description, total=total)
        self.active_tasks[name] = task_id
        self.total_tasks += 1
        return name
    
    def update_batch_task(self, name: str, **kwargs):
        """Update a batch task."""
        if name in self.active_tasks:
            self.progress.update(self.active_tasks[name], **kwargs)
    
    def complete_batch_task(self, name: str):
        """Complete a batch task."""
        if name in self.active_tasks:
            task_id = self.active_tasks[name]
            self.progress.update(task_id, completed=100)
            self.progress.remove_task(task_id)
            del self.active_tasks[name]
            self.completed_tasks += 1


# Convenience functions for common operations

async def create_users_with_progress(users_data: List[Dict[str, Any]]) -> List[Any]:
    """Create users with progress tracking."""
    return await with_progress(
        "User Creation",
        user_creation_progress,
        ProgressStyle.DETAILED,
        users_data
    )


async def start_servers_with_progress(server_names: List[str]) -> Dict[str, bool]:
    """Start servers with progress tracking."""
    return await with_progress(
        "Server Startup",
        server_startup_progress,
        ProgressStyle.DEFAULT,
        server_names
    )


async def backup_with_progress(backup_path: str, components: List[str]) -> str:
    """Create backup with progress tracking."""
    return await with_progress(
        "System Backup",
        backup_progress,
        ProgressStyle.DETAILED,
        backup_path,
        components
    )


async def migrate_with_progress(source_path: str, items_count: int) -> Dict[str, Any]:
    """Migrate data with progress tracking."""
    return await with_progress(
        "Data Migration",
        migration_progress,
        ProgressStyle.DETAILED,
        source_path,
        items_count
    )


# Progress decorators for CLI commands

def with_spinner(message: str):
    """Decorator to add spinner to CLI commands."""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            with console.status(message):
                return await func(*args, **kwargs)
        return wrapper
    return decorator


def with_progress_bar(operation_name: str, style: ProgressStyle = ProgressStyle.DEFAULT):
    """Decorator to add progress bar to CLI commands."""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            async with OperationProgress(operation_name, style) as progress:
                return await func(progress, *args, **kwargs)
        return wrapper
    return decorator