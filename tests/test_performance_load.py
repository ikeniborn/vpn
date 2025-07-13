"""
Performance and load testing for VPN Manager.

This module contains performance tests, benchmarks, and load testing
scenarios to ensure the system performs well under various conditions.
"""

import asyncio
import time
import tracemalloc
from unittest.mock import AsyncMock

import pytest

from tests.factories import (
    LoadTestDataFactory,
    UserDataFactory,
)
from tests.utils import AsyncTestHelper, PerformanceTestHelper, TestAssertions


@pytest.mark.performance
@pytest.mark.asyncio
class TestDatabasePerformance:
    """Test database operation performance."""

    async def test_user_creation_performance(
        self,
        db_session,
        performance_monitor
    ):
        """Test single user creation performance."""
        user_data = UserDataFactory.build_dict()

        performance_monitor.start()

        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            user = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type']
            )

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        metrics = performance_monitor.stop()

        # Assert performance targets
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            1.0,  # Should complete within 1 second
            "Single user creation"
        )

        # Memory usage should be reasonable
        assert metrics['peak_memory'] < 10 * 1024 * 1024  # 10MB

    @pytest.mark.slow
    async def test_batch_user_creation_performance(
        self,
        db_session,
        performance_monitor
    ):
        """Test batch user creation performance."""
        batch_size = 100
        users_data = UserDataFactory.create_batch_dict(batch_size)

        performance_monitor.start()

        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            created_users = await user_manager.create_users_batch(
                users_data, batch_size=50
            )

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        metrics = performance_monitor.stop()

        # Assert batch performance
        assert len(created_users) == batch_size

        # Should be much faster than individual creates (target: <5s for 100 users)
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            5.0,
            f"Batch creation of {batch_size} users"
        )

        # Calculate throughput
        throughput = batch_size / metrics['duration']
        assert throughput >= 20  # At least 20 users/second

    async def test_query_optimization_performance(
        self,
        db_session,
        performance_monitor
    ):
        """Test optimized query performance."""
        # Setup: Create test data
        try:
            from vpn.services.enhanced_user_manager import (
                EnhancedUserManager,
                PaginationParams,
                QueryFilters,
            )

            user_manager = EnhancedUserManager(session=db_session)

            # Create test users
            test_users = UserDataFactory.create_batch_dict(50)
            await user_manager.create_users_batch(test_users)

            # Test optimized listing
            performance_monitor.start()

            paginated_result = await user_manager.list_users_optimized(
                pagination=PaginationParams(page=1, page_size=20),
                filters=QueryFilters(status='active')
            )

            metrics = performance_monitor.stop()

            # Assert
            assert paginated_result.total_count >= 0
            assert len(paginated_result.items) <= 20

            # Query should be fast
            PerformanceTestHelper.assert_execution_time(
                metrics['duration'],
                0.5,  # Should complete within 500ms
                "Optimized user listing with pagination"
            )

        except ImportError:
            pytest.skip("Enhanced user manager not available")

    async def test_concurrent_database_operations(
        self,
        db_session,
        performance_monitor
    ):
        """Test concurrent database operations performance."""
        concurrent_operations = 20
        users_data = UserDataFactory.create_batch_dict(concurrent_operations)

        performance_monitor.start()

        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Create tasks for concurrent operations
            tasks = []
            for user_data in users_data:
                task = user_manager.create(
                    username=user_data['username'],
                    email=user_data['email'],
                    protocol_type=user_data['protocol_type']
                )
                tasks.append(task)

            # Execute concurrently
            results = await AsyncTestHelper.run_parallel(
                *tasks, max_concurrent=10
            )

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        metrics = performance_monitor.stop()

        # Assert
        successful_operations = len([r for r in results if not isinstance(r, Exception)])
        assert successful_operations >= concurrent_operations * 0.8  # 80% success rate

        # Concurrent operations should be faster than sequential
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            10.0,  # Should complete within 10 seconds
            f"{concurrent_operations} concurrent database operations"
        )


@pytest.mark.performance
@pytest.mark.asyncio
class TestDockerPerformance:
    """Test Docker operations performance."""

    async def test_single_container_operations_performance(
        self,
        mock_enhanced_docker_manager,
        performance_monitor
    ):
        """Test performance of single container operations."""
        container_id = "test_container_123"

        # Configure mocks with realistic delays
        async def mock_with_delay(delay=0.1):
            await asyncio.sleep(delay)
            return True

        mock_enhanced_docker_manager.start_container = AsyncMock(side_effect=lambda _: mock_with_delay(0.2))
        mock_enhanced_docker_manager.get_container_stats = AsyncMock(
            return_value={'cpu_percent': 10.0, 'memory_mb': 50.0}
        )
        mock_enhanced_docker_manager.stop_container = AsyncMock(side_effect=lambda _: mock_with_delay(0.3))

        performance_monitor.start()

        # Test container lifecycle
        await mock_enhanced_docker_manager.start_container(container_id)
        stats = await mock_enhanced_docker_manager.get_container_stats(container_id)
        await mock_enhanced_docker_manager.stop_container(container_id)

        metrics = performance_monitor.stop()

        # Assert
        assert stats is not None

        # Total operation should complete quickly
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            2.0,  # Should complete within 2 seconds
            "Container lifecycle operations"
        )

    @pytest.mark.slow
    async def test_batch_container_operations_performance(
        self,
        mock_enhanced_docker_manager,
        performance_monitor
    ):
        """Test performance of batch container operations."""
        container_count = 50
        container_ids = [f"container_{i}" for i in range(container_count)]

        # Mock batch operations with realistic timing
        success_results = dict.fromkeys(container_ids, True)
        stats_results = {
            cid: {'cpu_percent': 10.0, 'memory_mb': 50.0}
            for cid in container_ids
        }

        mock_enhanced_docker_manager.start_containers_batch.return_value = success_results
        mock_enhanced_docker_manager.get_containers_stats_batch.return_value = stats_results
        mock_enhanced_docker_manager.stop_containers_batch.return_value = success_results

        performance_monitor.start()

        # Execute batch operations
        start_results = await mock_enhanced_docker_manager.start_containers_batch(
            container_ids, max_concurrent=10
        )
        stats_results = await mock_enhanced_docker_manager.get_containers_stats_batch(
            container_ids, max_concurrent=20
        )
        stop_results = await mock_enhanced_docker_manager.stop_containers_batch(
            container_ids, max_concurrent=10
        )

        metrics = performance_monitor.stop()

        # Assert
        assert len(start_results) == container_count
        assert len(stats_results) == container_count
        assert len(stop_results) == container_count

        # Batch operations should be significantly faster than sequential
        # Target: < 15 seconds for 50 containers
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            15.0,
            f"Batch operations on {container_count} containers"
        )

        # Calculate effective throughput
        total_operations = container_count * 3  # start, stats, stop
        throughput = total_operations / metrics['duration']
        assert throughput >= 10  # At least 10 operations/second


@pytest.mark.performance
@pytest.mark.asyncio
class TestCachingPerformance:
    """Test caching system performance."""

    async def test_cache_hit_performance(self, performance_monitor):
        """Test cache hit performance."""
        try:
            from vpn.services.caching_service import CachingService

            cache = CachingService(max_size=1000, default_ttl=300)
            await cache.start()

            # Pre-populate cache
            test_data = {f"key_{i}": f"value_{i}" for i in range(100)}
            await cache.warm_cache(test_data)

            performance_monitor.start()

            # Test cache hits
            for key in test_data:
                value = await cache.get(key)
                assert value is not None

            metrics = performance_monitor.stop()

            # Cache hits should be very fast
            avg_time_per_operation = metrics['duration'] / len(test_data)
            assert avg_time_per_operation < 0.001  # Less than 1ms per operation

            await cache.stop()

        except ImportError:
            pytest.skip("Caching service not available")

    async def test_cache_miss_and_population_performance(self, performance_monitor):
        """Test cache miss and population performance."""
        try:
            from vpn.services.caching_service import CachingService

            cache = CachingService(max_size=1000, default_ttl=300)
            await cache.start()

            performance_monitor.start()

            # Test cache misses and population
            for i in range(100):
                key = f"new_key_{i}"
                value = f"new_value_{i}"
                await cache.set(key, value)
                retrieved = await cache.get(key)
                assert retrieved == value

            metrics = performance_monitor.stop()

            # Cache operations should still be fast
            avg_time_per_operation = metrics['duration'] / 200  # 100 sets + 100 gets
            assert avg_time_per_operation < 0.01  # Less than 10ms per operation

            await cache.stop()

        except ImportError:
            pytest.skip("Caching service not available")


@pytest.mark.load
@pytest.mark.slow
@pytest.mark.asyncio
class TestLoadScenarios:
    """Load testing scenarios."""

    async def test_high_concurrency_user_operations(
        self,
        db_session,
        performance_monitor
    ):
        """Test system under high concurrency user operations."""
        concurrent_users = 100
        operations_per_user = 5

        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Generate load test data
            load_data = LoadTestDataFactory.build_dict(concurrent_users=concurrent_users)

            performance_monitor.start()

            # Create concurrent tasks
            tasks = []
            for i in range(concurrent_users):
                for j in range(operations_per_user):
                    user_data = UserDataFactory.build_dict()
                    user_data['username'] = f"load_user_{i}_{j}"

                    task = user_manager.create(
                        username=user_data['username'],
                        email=user_data['email'],
                        protocol_type=user_data['protocol_type']
                    )
                    tasks.append(task)

            # Execute with controlled concurrency
            results = await AsyncTestHelper.run_parallel(
                *tasks, max_concurrent=50
            )

            metrics = performance_monitor.stop()

            # Analyze results
            successful_operations = len([r for r in results if not isinstance(r, Exception)])
            total_operations = concurrent_users * operations_per_user
            success_rate = successful_operations / total_operations

            # Assert performance targets
            assert success_rate >= 0.90  # At least 90% success rate

            # Should handle high load reasonably
            PerformanceTestHelper.assert_execution_time(
                metrics['duration'],
                60.0,  # Should complete within 1 minute
                f"High concurrency load test ({total_operations} operations)"
            )

            # Calculate throughput
            throughput = successful_operations / metrics['duration']
            assert throughput >= 10  # At least 10 operations/second

        except ImportError:
            pytest.skip("Enhanced user manager not available")

    async def test_sustained_load_performance(
        self,
        mock_enhanced_docker_manager,
        performance_monitor
    ):
        """Test system performance under sustained load."""
        duration_seconds = 30
        operations_per_second = 20

        # Mock operations with small delays to simulate real work
        async def mock_operation():
            await asyncio.sleep(0.01)  # 10ms simulated work
            return True

        mock_enhanced_docker_manager.get_container_stats = AsyncMock(
            side_effect=lambda _: mock_operation()
        )

        performance_monitor.start()

        start_time = time.time()
        operation_count = 0

        # Run sustained load
        while time.time() - start_time < duration_seconds:
            # Create batch of operations
            tasks = []
            for _ in range(operations_per_second):
                task = mock_enhanced_docker_manager.get_container_stats(f"container_{operation_count}")
                tasks.append(task)
                operation_count += 1

            # Execute batch
            await AsyncTestHelper.run_parallel(*tasks, max_concurrent=10)

            # Brief pause to achieve target rate
            await asyncio.sleep(max(0, 1.0 - (time.time() - start_time - (operation_count // operations_per_second))))

        metrics = performance_monitor.stop()

        # Assert sustained performance
        actual_ops_per_second = operation_count / metrics['duration']
        assert actual_ops_per_second >= operations_per_second * 0.8  # Within 20% of target

        # Memory usage should remain stable
        memory_growth = metrics['memory_delta']
        assert memory_growth < 50 * 1024 * 1024  # Less than 50MB growth

    @pytest.mark.parametrize("user_count", [10, 50, 100, 200])
    async def test_scalability_user_counts(
        self,
        db_session,
        user_count,
        performance_monitor
    ):
        """Test scalability with different user counts."""
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            users_data = UserDataFactory.create_batch_dict(user_count)

            performance_monitor.start()

            # Use batch operations for better performance
            created_users = await user_manager.create_users_batch(
                users_data, batch_size=min(50, user_count)
            )

            metrics = performance_monitor.stop()

            # Assert
            assert len(created_users) == user_count

            # Performance should scale reasonably
            max_time = user_count * 0.05  # 50ms per user is reasonable
            PerformanceTestHelper.assert_execution_time(
                metrics['duration'],
                max_time,
                f"Creating {user_count} users"
            )

            # Calculate and assert throughput
            throughput = user_count / metrics['duration']
            min_throughput = 20 if user_count <= 50 else 50  # Higher throughput for larger batches
            assert throughput >= min_throughput

        except ImportError:
            pytest.skip("Enhanced user manager not available")


@pytest.mark.performance
@pytest.mark.asyncio
class TestMemoryProfilerPerformance:
    """Test memory profiler performance impact."""

    async def test_memory_profiler_overhead(self, performance_monitor):
        """Test memory profiler overhead on system performance."""
        try:
            from vpn.services.memory_profiler import (
                MemoryProfiler,
                MemoryProfilerConfig,
            )

            # Test without profiler
            performance_monitor.start()

            # Simulate some work
            test_data = []
            for i in range(10000):
                test_data.append(f"test_string_{i}")

            metrics_without = performance_monitor.stop()

            # Test with profiler
            config = MemoryProfilerConfig(
                snapshot_interval=1.0,
                tracemalloc_enabled=True
            )
            profiler = MemoryProfiler(config)
            await profiler.start()

            performance_monitor.start()

            # Same work with profiler active
            test_data = []
            for i in range(10000):
                test_data.append(f"test_string_{i}")

            metrics_with = performance_monitor.stop()

            await profiler.stop()

            # Assert overhead is acceptable
            overhead_ratio = metrics_with['duration'] / metrics_without['duration']
            assert overhead_ratio < 1.5  # Less than 50% overhead

        except ImportError:
            pytest.skip("Memory profiler not available")


@pytest.mark.performance
def test_benchmark_data_generation():
    """Benchmark test data generation performance."""
    start_time = time.time()

    # Generate large amounts of test data
    users_data = UserDataFactory.create_batch_dict(1000)

    generation_time = time.time() - start_time

    # Assert
    assert len(users_data) == 1000
    assert generation_time < 5.0  # Should generate 1000 users in under 5 seconds

    # Verify data quality
    for user_data in users_data[:10]:  # Check first 10
        TestAssertions.assert_user_valid(user_data)


@pytest.mark.performance
def test_memory_usage_patterns():
    """Test memory usage patterns in test data creation."""
    tracemalloc.start()

    # Create progressively larger datasets
    datasets = []
    for size in [10, 50, 100, 500]:
        users_data = UserDataFactory.create_batch_dict(size)
        datasets.append(users_data)

        current, peak = tracemalloc.get_traced_memory()

        # Memory usage should be reasonable
        assert current < size * 10000  # Less than 10KB per user

    tracemalloc.stop()

    # Cleanup
    del datasets


# Benchmark helpers
class BenchmarkResult:
    """Store benchmark results for analysis."""

    def __init__(self, operation_name: str, duration: float, throughput: float, memory_usage: int):
        self.operation_name = operation_name
        self.duration = duration
        self.throughput = throughput
        self.memory_usage = memory_usage

    def __str__(self):
        return f"{self.operation_name}: {self.duration:.3f}s, {self.throughput:.1f} ops/s, {self.memory_usage/1024/1024:.1f}MB"


@pytest.fixture
def benchmark_results():
    """Fixture to collect benchmark results."""
    results = []
    yield results

    # Print results summary
    if results:
        print("\n=== Benchmark Results ===")
        for result in results:
            print(result)
        print("========================")
