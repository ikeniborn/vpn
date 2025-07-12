"""
Advanced caching service with TTL, metrics, and invalidation patterns.

This module provides a comprehensive caching layer for the VPN Manager application
with features like time-to-live (TTL), cache warming, pattern-based invalidation,
and detailed metrics tracking.
"""

import asyncio
import json
import re
import time
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, List, Optional, Set, Union, Pattern
from uuid import uuid4
import hashlib

from vpn.services.base_service import EnhancedBaseService, ServiceHealth, ServiceStatus
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class CacheEntry:
    """Individual cache entry with metadata."""
    key: str
    value: Any
    created_at: float
    ttl: Optional[float] = None
    access_count: int = 0
    last_accessed: float = field(default_factory=time.time)
    tags: Set[str] = field(default_factory=set)
    
    @property
    def is_expired(self) -> bool:
        """Check if cache entry has expired."""
        if self.ttl is None:
            return False
        return time.time() - self.created_at > self.ttl
    
    @property
    def age_seconds(self) -> float:
        """Get age of cache entry in seconds."""
        return time.time() - self.created_at
    
    def touch(self):
        """Update last accessed time and increment access count."""
        self.last_accessed = time.time()
        self.access_count += 1


@dataclass
class CacheMetrics:
    """Cache performance metrics."""
    hits: int = 0
    misses: int = 0
    sets: int = 0
    deletes: int = 0
    evictions: int = 0
    total_size: int = 0
    memory_usage_bytes: int = 0
    avg_access_time_ms: float = 0.0
    
    @property
    def hit_ratio(self) -> float:
        """Calculate cache hit ratio."""
        total = self.hits + self.misses
        return self.hits / total if total > 0 else 0.0
    
    @property
    def miss_ratio(self) -> float:
        """Calculate cache miss ratio."""
        return 1.0 - self.hit_ratio


class CachingService(EnhancedBaseService):
    """
    Advanced caching service with comprehensive features.
    
    Features:
    - TTL (Time-To-Live) support
    - Pattern-based invalidation
    - Cache warming and preloading
    - Detailed metrics tracking
    - LRU eviction policy
    - Tag-based grouping
    - Memory usage monitoring
    """
    
    def __init__(
        self,
        max_size: int = 10000,
        default_ttl: float = 300.0,  # 5 minutes
        cleanup_interval: float = 60.0,  # 1 minute
        max_memory_mb: float = 100.0
    ):
        """
        Initialize caching service.
        
        Args:
            max_size: Maximum number of cache entries
            default_ttl: Default TTL in seconds
            cleanup_interval: Cleanup interval in seconds
            max_memory_mb: Maximum memory usage in MB
        """
        super().__init__(name="CachingService")
        
        self._cache: Dict[str, CacheEntry] = {}
        self._max_size = max_size
        self._default_ttl = default_ttl
        self._cleanup_interval = cleanup_interval
        self._max_memory_bytes = int(max_memory_mb * 1024 * 1024)
        
        # Metrics tracking
        self._metrics = CacheMetrics()
        self._access_times: List[float] = []
        
        # Tag tracking for invalidation
        self._tag_to_keys: Dict[str, Set[str]] = defaultdict(set)
        
        # Cleanup task
        self._cleanup_task: Optional[asyncio.Task] = None
        
        # Lock for thread safety
        self._lock = asyncio.Lock()
        
        self.logger.info(f"Initialized caching service with max_size={max_size}, default_ttl={default_ttl}s")
    
    async def start(self) -> None:
        """Start the caching service and cleanup task."""
        await super().start()
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
        self.logger.info("Caching service started")
    
    async def stop(self) -> None:
        """Stop the caching service and cleanup task."""
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
        
        await super().stop()
        self.logger.info("Caching service stopped")
    
    async def get(
        self, 
        key: str, 
        default: Any = None
    ) -> Any:
        """
        Get value from cache.
        
        Args:
            key: Cache key
            default: Default value if key not found
            
        Returns:
            Cached value or default
        """
        start_time = time.time()
        
        async with self._lock:
            entry = self._cache.get(key)
            
            if entry is None:
                self._metrics.misses += 1
                self._record_access_time(start_time)
                return default
            
            if entry.is_expired:
                # Remove expired entry
                await self._remove_entry(key)
                self._metrics.misses += 1
                self._record_access_time(start_time)
                return default
            
            # Update access metadata
            entry.touch()
            self._metrics.hits += 1
            self._record_access_time(start_time)
            
            return entry.value
    
    async def set(
        self,
        key: str,
        value: Any,
        ttl: Optional[float] = None,
        tags: Optional[Set[str]] = None
    ) -> None:
        """
        Set value in cache.
        
        Args:
            key: Cache key
            value: Value to cache
            ttl: Time-to-live in seconds (uses default if None)
            tags: Tags for grouping and invalidation
        """
        if ttl is None:
            ttl = self._default_ttl
        
        tags = tags or set()
        
        async with self._lock:
            # Check if we need to evict entries
            if len(self._cache) >= self._max_size:
                await self._evict_lru()
            
            # Remove existing entry if present
            if key in self._cache:
                await self._remove_entry(key)
            
            # Create new entry
            entry = CacheEntry(
                key=key,
                value=value,
                created_at=time.time(),
                ttl=ttl,
                tags=tags
            )
            
            self._cache[key] = entry
            self._metrics.sets += 1
            
            # Update tag mappings
            for tag in tags:
                self._tag_to_keys[tag].add(key)
            
            # Check memory usage
            await self._check_memory_usage()
            
        self.logger.debug(f"Cached key '{key}' with TTL {ttl}s and tags {tags}")
    
    async def delete(self, key: str) -> bool:
        """
        Delete key from cache.
        
        Args:
            key: Cache key to delete
            
        Returns:
            True if key was deleted, False if not found
        """
        async with self._lock:
            if key in self._cache:
                await self._remove_entry(key)
                self._metrics.deletes += 1
                return True
            return False
    
    async def get_with_cache_aside(
        self,
        key: str,
        fetch_func: Callable,
        ttl: Optional[float] = None,
        tags: Optional[Set[str]] = None,
        *args,
        **kwargs
    ) -> Any:
        """
        Get value with cache-aside pattern.
        
        If key exists in cache, return cached value.
        If not, call fetch_func to get value, cache it, and return.
        
        Args:
            key: Cache key
            fetch_func: Function to fetch value if not cached
            ttl: TTL for cached value
            tags: Tags for the cached value
            *args, **kwargs: Arguments for fetch_func
            
        Returns:
            Cached or fetched value
        """
        # Try to get from cache first
        cached_value = await self.get(key)
        if cached_value is not None:
            return cached_value
        
        # Fetch the value
        if asyncio.iscoroutinefunction(fetch_func):
            value = await fetch_func(*args, **kwargs)
        else:
            value = fetch_func(*args, **kwargs)
        
        # Cache the value
        if value is not None:
            await self.set(key, value, ttl=ttl, tags=tags)
        
        return value
    
    async def invalidate_pattern(self, pattern: str) -> int:
        """
        Invalidate cache keys matching a pattern.
        
        Args:
            pattern: Regex pattern to match keys
            
        Returns:
            Number of keys invalidated
        """
        regex = re.compile(pattern)
        keys_to_delete = []
        
        async with self._lock:
            for key in self._cache.keys():
                if regex.match(key):
                    keys_to_delete.append(key)
        
        # Delete matched keys
        for key in keys_to_delete:
            await self.delete(key)
        
        self.logger.info(f"Invalidated {len(keys_to_delete)} keys matching pattern '{pattern}'")
        return len(keys_to_delete)
    
    async def invalidate_tags(self, tags: Union[str, Set[str]]) -> int:
        """
        Invalidate all cache entries with specified tags.
        
        Args:
            tags: Tag or set of tags to invalidate
            
        Returns:
            Number of keys invalidated
        """
        if isinstance(tags, str):
            tags = {tags}
        
        keys_to_delete = set()
        
        async with self._lock:
            for tag in tags:
                if tag in self._tag_to_keys:
                    keys_to_delete.update(self._tag_to_keys[tag])
        
        # Delete tagged keys
        for key in keys_to_delete:
            await self.delete(key)
        
        self.logger.info(f"Invalidated {len(keys_to_delete)} keys with tags {tags}")
        return len(keys_to_delete)
    
    async def warm_cache(
        self,
        warm_data: Dict[str, Any],
        ttl: Optional[float] = None,
        tags: Optional[Set[str]] = None
    ) -> int:
        """
        Warm cache with predefined data.
        
        Args:
            warm_data: Dictionary of key-value pairs to cache
            ttl: TTL for all entries
            tags: Tags for all entries
            
        Returns:
            Number of entries cached
        """
        count = 0
        for key, value in warm_data.items():
            await self.set(key, value, ttl=ttl, tags=tags)
            count += 1
        
        self.logger.info(f"Warmed cache with {count} entries")
        return count
    
    async def get_cache_metrics(self) -> Dict[str, Any]:
        """
        Get detailed cache metrics.
        
        Returns:
            Dictionary with cache performance metrics
        """
        async with self._lock:
            self._metrics.total_size = len(self._cache)
            self._metrics.memory_usage_bytes = await self._calculate_memory_usage()
            
            # Calculate average access time
            if self._access_times:
                self._metrics.avg_access_time_ms = sum(self._access_times) / len(self._access_times) * 1000
            
            return {
                'hits': self._metrics.hits,
                'misses': self._metrics.misses,
                'hit_ratio': self._metrics.hit_ratio,
                'miss_ratio': self._metrics.miss_ratio,
                'sets': self._metrics.sets,
                'deletes': self._metrics.deletes,
                'evictions': self._metrics.evictions,
                'total_size': self._metrics.total_size,
                'max_size': self._max_size,
                'memory_usage_mb': self._metrics.memory_usage_bytes / (1024 * 1024),
                'max_memory_mb': self._max_memory_bytes / (1024 * 1024),
                'avg_access_time_ms': self._metrics.avg_access_time_ms,
                'tag_count': len(self._tag_to_keys),
                'last_updated': datetime.utcnow().isoformat()
            }
    
    async def get_cache_info(self, key: str) -> Optional[Dict[str, Any]]:
        """
        Get information about a specific cache entry.
        
        Args:
            key: Cache key
            
        Returns:
            Dictionary with entry information or None if not found
        """
        async with self._lock:
            entry = self._cache.get(key)
            if entry is None:
                return None
            
            return {
                'key': entry.key,
                'created_at': datetime.fromtimestamp(entry.created_at).isoformat(),
                'ttl': entry.ttl,
                'age_seconds': entry.age_seconds,
                'access_count': entry.access_count,
                'last_accessed': datetime.fromtimestamp(entry.last_accessed).isoformat(),
                'tags': list(entry.tags),
                'is_expired': entry.is_expired,
                'value_type': type(entry.value).__name__
            }
    
    async def clear(self) -> int:
        """
        Clear all cache entries.
        
        Returns:
            Number of entries cleared
        """
        async with self._lock:
            count = len(self._cache)
            self._cache.clear()
            self._tag_to_keys.clear()
            
        self.logger.info(f"Cleared {count} cache entries")
        return count
    
    async def _cleanup_loop(self):
        """Background task to clean up expired entries."""
        while True:
            try:
                await asyncio.sleep(self._cleanup_interval)
                await self._cleanup_expired()
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in cleanup loop: {e}")
    
    async def _cleanup_expired(self) -> int:
        """Remove expired entries from cache."""
        expired_keys = []
        
        async with self._lock:
            for key, entry in self._cache.items():
                if entry.is_expired:
                    expired_keys.append(key)
        
        # Remove expired entries
        for key in expired_keys:
            await self.delete(key)
        
        if expired_keys:
            self.logger.debug(f"Cleaned up {len(expired_keys)} expired cache entries")
        
        return len(expired_keys)
    
    async def _evict_lru(self) -> None:
        """Evict least recently used entry."""
        if not self._cache:
            return
        
        # Find LRU entry
        lru_key = min(
            self._cache.keys(),
            key=lambda k: self._cache[k].last_accessed
        )
        
        await self._remove_entry(lru_key)
        self._metrics.evictions += 1
        
        self.logger.debug(f"Evicted LRU entry: {lru_key}")
    
    async def _remove_entry(self, key: str) -> None:
        """Remove entry and update tag mappings."""
        if key not in self._cache:
            return
        
        entry = self._cache[key]
        
        # Remove from tag mappings
        for tag in entry.tags:
            if tag in self._tag_to_keys:
                self._tag_to_keys[tag].discard(key)
                # Clean up empty tag sets
                if not self._tag_to_keys[tag]:
                    del self._tag_to_keys[tag]
        
        # Remove from cache
        del self._cache[key]
    
    async def _calculate_memory_usage(self) -> int:
        """Estimate memory usage of cache entries."""
        # This is a rough estimation
        total_size = 0
        for entry in self._cache.values():
            try:
                # Estimate size of the entry
                value_size = len(str(entry.value).encode('utf-8'))
                key_size = len(entry.key.encode('utf-8'))
                metadata_size = 200  # Rough estimate for metadata
                total_size += value_size + key_size + metadata_size
            except Exception:
                # Fallback for non-serializable objects
                total_size += 1000  # Rough estimate
        
        return total_size
    
    async def _check_memory_usage(self) -> None:
        """Check and handle memory usage limits."""
        memory_usage = await self._calculate_memory_usage()
        
        while memory_usage > self._max_memory_bytes and self._cache:
            await self._evict_lru()
            memory_usage = await self._calculate_memory_usage()
            
            if memory_usage > self._max_memory_bytes:
                self.logger.warning(f"Cache memory usage ({memory_usage / (1024*1024):.1f}MB) exceeds limit")
    
    def _record_access_time(self, start_time: float) -> None:
        """Record access time for metrics."""
        access_time = time.time() - start_time
        self._access_times.append(access_time)
        
        # Keep only recent access times (last 1000)
        if len(self._access_times) > 1000:
            self._access_times = self._access_times[-1000:]
    
    async def get_health(self) -> ServiceHealth:
        """Get service health with cache-specific metrics."""
        base_health = await super().get_health()
        
        metrics = await self.get_cache_metrics()
        
        # Determine health based on hit ratio and memory usage
        hit_ratio = metrics['hit_ratio']
        memory_usage_ratio = metrics['memory_usage_mb'] / metrics['max_memory_mb']
        
        # Health scoring
        health_score = 1.0
        if hit_ratio < 0.5:
            health_score -= 0.3  # Poor hit ratio
        if memory_usage_ratio > 0.9:
            health_score -= 0.2  # High memory usage
        
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
                'cache_metrics': metrics,
                'health_score': health_score
            }
        )


# Singleton instance for global use
_caching_service: Optional[CachingService] = None


async def get_caching_service() -> CachingService:
    """Get or create the global caching service instance."""
    global _caching_service
    
    if _caching_service is None:
        _caching_service = CachingService()
        await _caching_service.start()
    
    return _caching_service


async def shutdown_caching_service():
    """Shutdown the global caching service."""
    global _caching_service
    
    if _caching_service is not None:
        await _caching_service.stop()
        _caching_service = None