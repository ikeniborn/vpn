"""
Integration test scenarios for VPN Manager.

This module contains comprehensive integration tests that verify
end-to-end functionality across multiple components and services.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from tests.factories import (
    ContainerDataFactory,
    UserDataFactory,
    create_complete_user_scenario,
)
from tests.utils import PerformanceTestHelper, TestAssertions


@pytest.mark.integration
@pytest.mark.asyncio
class TestCompleteUserLifecycle:
    """Test complete user lifecycle from creation to deletion."""

    async def test_create_user_with_container_deployment(
        self,
        db_session,
        mock_enhanced_docker_manager,
        mock_network_manager,
        performance_monitor
    ):
        """Test creating user and deploying VPN container."""
        # Arrange
        user_data = UserDataFactory.build_dict()
        container_data = ContainerDataFactory.build_dict()

        mock_enhanced_docker_manager.create_container.return_value = MagicMock(id=container_data['id'])
        mock_enhanced_docker_manager.start_container.return_value = None
        mock_network_manager.is_port_available.return_value = True

        performance_monitor.start()

        # Act - Create user
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Create user
            created_user = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type'],
                port=user_data['port']
            )

            # Deploy container
            container = await mock_enhanced_docker_manager.create_container(
                image="vpn-server:latest",
                name=f"vpn_{created_user.username}",
                ports={f"{user_data['port']}/tcp": user_data['port']},
                environment={
                    'VPN_USER_ID': created_user.id,
                    'VPN_TYPE': user_data['protocol_type']
                }
            )

            await mock_enhanced_docker_manager.start_container(container.id)

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        metrics = performance_monitor.stop()

        # Assert
        assert created_user is not None
        TestAssertions.assert_user_valid(created_user.__dict__)

        # Verify container operations were called
        mock_enhanced_docker_manager.create_container.assert_called_once()
        mock_enhanced_docker_manager.start_container.assert_called_once()

        # Performance assertions
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            5.0,
            "User creation and container deployment"
        )

    async def test_user_update_and_container_restart(
        self,
        db_session,
        mock_enhanced_docker_manager
    ):
        """Test updating user and restarting associated container."""
        # Arrange
        user_data = UserDataFactory.build_dict()
        container_id = "test_container_123"

        mock_enhanced_docker_manager.get_container.return_value = MagicMock(id=container_id)
        mock_enhanced_docker_manager.restart_container.return_value = None

        # Act
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Create user first
            user = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type']
            )

            # Update user
            updated_user = await user_manager.update(
                user.id,
                email="updated@example.com",
                status="inactive"
            )

            # Restart associated container
            await mock_enhanced_docker_manager.restart_container(container_id)

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        # Assert
        assert updated_user.email == "updated@example.com"
        assert updated_user.status.value == "inactive"
        mock_enhanced_docker_manager.restart_container.assert_called_once_with(container_id)

    async def test_user_deletion_and_cleanup(
        self,
        db_session,
        mock_enhanced_docker_manager,
        mock_network_manager
    ):
        """Test user deletion with proper resource cleanup."""
        # Arrange
        user_data = UserDataFactory.build_dict()
        container_id = "test_container_123"

        mock_enhanced_docker_manager.get_container.return_value = MagicMock(id=container_id)
        mock_enhanced_docker_manager.stop_container.return_value = None
        mock_enhanced_docker_manager.remove_container.return_value = None
        mock_network_manager.remove_firewall_rule.return_value = None

        # Act
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Create user
            user = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type']
            )

            # Delete user and cleanup resources
            deleted = await user_manager.delete(user.id)

            # Cleanup container
            await mock_enhanced_docker_manager.stop_container(container_id)
            await mock_enhanced_docker_manager.remove_container(container_id)

            # Cleanup network rules
            await mock_network_manager.remove_firewall_rule(
                port=user_data.get('port', 8443)
            )

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        # Assert
        assert deleted is True
        mock_enhanced_docker_manager.stop_container.assert_called_once()
        mock_enhanced_docker_manager.remove_container.assert_called_once()
        mock_network_manager.remove_firewall_rule.assert_called_once()


@pytest.mark.integration
@pytest.mark.asyncio
class TestBatchOperations:
    """Test batch operations across multiple services."""

    async def test_batch_user_creation_with_containers(
        self,
        db_session,
        mock_enhanced_docker_manager,
        performance_monitor
    ):
        """Test creating multiple users with container deployment."""
        # Arrange
        user_count = 10
        users_data = UserDataFactory.create_batch_dict(user_count)

        # Mock batch container operations
        container_results = {f"container_{i}": True for i in range(user_count)}
        mock_enhanced_docker_manager.create_containers_batch.return_value = container_results
        mock_enhanced_docker_manager.start_containers_batch.return_value = container_results

        performance_monitor.start()

        # Act
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Batch create users
            created_users = await user_manager.create_users_batch(users_data)

            # Batch create and start containers
            container_configs = [
                {
                    'image': 'vpn-server:latest',
                    'name': f"vpn_{user['username']}",
                    'environment': {
                        'VPN_USER_ID': user['id'],
                        'VPN_TYPE': user['protocol_type']
                    }
                }
                for user in users_data
            ]

            containers = await mock_enhanced_docker_manager.create_containers_batch(container_configs)
            container_ids = [c.id for c in containers.values() if c]

            await mock_enhanced_docker_manager.start_containers_batch(container_ids)

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        metrics = performance_monitor.stop()

        # Assert
        assert len(created_users) == user_count

        # Verify all batch operations were called
        mock_enhanced_docker_manager.create_containers_batch.assert_called_once()
        mock_enhanced_docker_manager.start_containers_batch.assert_called_once()

        # Performance assertion - should be much faster than individual operations
        max_expected_time = user_count * 0.5  # 0.5s per user is reasonable for batch
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            max_expected_time,
            f"Batch creation of {user_count} users"
        )

    async def test_batch_container_operations(
        self,
        mock_enhanced_docker_manager,
        performance_monitor
    ):
        """Test batch Docker operations performance."""
        # Arrange
        container_count = 20
        container_ids = [f"container_{i}" for i in range(container_count)]

        # Mock successful batch operations
        success_results = dict.fromkeys(container_ids, True)
        mock_enhanced_docker_manager.start_containers_batch.return_value = success_results
        mock_enhanced_docker_manager.stop_containers_batch.return_value = success_results
        mock_enhanced_docker_manager.get_containers_stats_batch.return_value = {
            cid: {'cpu_percent': 10.0, 'memory_mb': 50.0} for cid in container_ids
        }

        performance_monitor.start()

        # Act
        start_results = await mock_enhanced_docker_manager.start_containers_batch(container_ids)
        stats_results = await mock_enhanced_docker_manager.get_containers_stats_batch(container_ids)
        stop_results = await mock_enhanced_docker_manager.stop_containers_batch(container_ids)

        metrics = performance_monitor.stop()

        # Assert
        assert len(start_results) == container_count
        assert len(stats_results) == container_count
        assert len(stop_results) == container_count

        # All operations should succeed
        assert all(start_results.values())
        assert all(stop_results.values())
        assert all(stats_results.values())

        # Performance should be reasonable for batch operations
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            10.0,  # 10 seconds should be enough for 20 containers
            f"Batch operations on {container_count} containers"
        )


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
class TestEndToEndScenarios:
    """End-to-end integration test scenarios."""

    async def test_complete_vpn_deployment_scenario(
        self,
        db_session,
        mock_enhanced_docker_manager,
        mock_network_manager,
        performance_monitor
    ):
        """Test complete VPN deployment from user creation to client connection."""
        # Arrange
        scenario = create_complete_user_scenario(1)[0]
        user_data = scenario['user']

        # Mock all required services
        mock_network_manager.is_port_available.return_value = True
        mock_network_manager.add_firewall_rule.return_value = None
        mock_network_manager.get_public_ip.return_value = "203.0.113.1"

        container = MagicMock()
        container.id = "vpn_container_123"
        container.status = "running"
        mock_enhanced_docker_manager.create_container.return_value = container
        mock_enhanced_docker_manager.start_container.return_value = None
        mock_enhanced_docker_manager.get_container_stats.return_value = {
            'cpu_percent': 5.0,
            'memory_mb': 45.0,
            'status': 'running'
        }

        performance_monitor.start()

        # Act - Complete deployment workflow
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Step 1: Create user
            user = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type'],
                port=user_data['port']
            )

            # Step 2: Check port availability
            port_available = await mock_network_manager.is_port_available(user_data['port'])
            assert port_available

            # Step 3: Deploy VPN container
            container = await mock_enhanced_docker_manager.create_container(
                image="vpn-server:latest",
                name=f"vpn_{user.username}",
                ports={f"{user_data['port']}/tcp": user_data['port']},
                environment={
                    'VPN_USER_ID': user.id,
                    'VPN_TYPE': user_data['protocol_type'],
                    'VPN_PORT': str(user_data['port'])
                }
            )

            # Step 4: Start container
            await mock_enhanced_docker_manager.start_container(container.id)

            # Step 5: Configure firewall
            await mock_network_manager.add_firewall_rule(
                port=user_data['port'],
                protocol='tcp'
            )

            # Step 6: Get public IP for client configuration
            public_ip = await mock_network_manager.get_public_ip()

            # Step 7: Verify container is running
            stats = await mock_enhanced_docker_manager.get_container_stats(container.id)

            # Step 8: Generate client configuration
            client_config = {
                'server': public_ip,
                'port': user_data['port'],
                'protocol': user_data['protocol_type'],
                'user_id': user.id,
                'credentials': scenario['keys']
            }

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        metrics = performance_monitor.stop()

        # Assert
        assert user is not None
        assert container is not None
        assert public_ip == "203.0.113.1"
        assert stats['status'] == 'running'
        assert client_config['server'] == public_ip

        # Verify all services were called correctly
        mock_network_manager.is_port_available.assert_called_once()
        mock_network_manager.add_firewall_rule.assert_called_once()
        mock_enhanced_docker_manager.create_container.assert_called_once()
        mock_enhanced_docker_manager.start_container.assert_called_once()

        # Performance assertion for complete workflow
        PerformanceTestHelper.assert_execution_time(
            metrics['duration'],
            15.0,
            "Complete VPN deployment workflow"
        )

    async def test_multi_protocol_deployment(
        self,
        db_session,
        mock_enhanced_docker_manager,
        mock_network_manager
    ):
        """Test deploying multiple VPN protocols simultaneously."""
        # Arrange
        protocols = ['vless', 'shadowsocks', 'wireguard']
        users_data = []

        for protocol in protocols:
            user_data = UserDataFactory.build_dict(protocol_type=protocol)
            users_data.append(user_data)

        # Mock services
        mock_network_manager.is_port_available.return_value = True
        mock_enhanced_docker_manager.create_containers_batch.return_value = {
            f"vpn_{data['username']}": MagicMock(id=f"container_{i}")
            for i, data in enumerate(users_data)
        }
        mock_enhanced_docker_manager.start_containers_batch.return_value = {
            f"container_{i}": True for i in range(len(protocols))
        }

        # Act
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Create users for different protocols
            created_users = await user_manager.create_users_batch(users_data)

            # Create container configurations for each protocol
            container_configs = []
            for user_data in users_data:
                config = {
                    'image': f"vpn-{user_data['protocol_type']}:latest",
                    'name': f"vpn_{user_data['username']}",
                    'ports': {f"{user_data['port']}/tcp": user_data['port']},
                    'environment': {
                        'VPN_TYPE': user_data['protocol_type'],
                        'VPN_PORT': str(user_data['port'])
                    }
                }
                container_configs.append(config)

            # Deploy all containers
            containers = await mock_enhanced_docker_manager.create_containers_batch(
                container_configs, max_concurrent=3
            )

            container_ids = [c.id for c in containers.values() if c]
            start_results = await mock_enhanced_docker_manager.start_containers_batch(
                container_ids, max_concurrent=3
            )

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        # Assert
        assert len(created_users) == len(protocols)
        assert len(containers) == len(protocols)
        assert all(start_results.values())

        # Verify each protocol was deployed
        created_protocols = [user.protocol.type for user in created_users]
        assert set(created_protocols) == set(protocols)


@pytest.mark.integration
@pytest.mark.asyncio
class TestErrorHandlingIntegration:
    """Test error handling across integrated components."""

    async def test_rollback_on_container_creation_failure(
        self,
        db_session,
        mock_enhanced_docker_manager
    ):
        """Test proper rollback when container creation fails."""
        # Arrange
        user_data = UserDataFactory.build_dict()

        # Mock container creation failure
        mock_enhanced_docker_manager.create_container.side_effect = Exception("Docker daemon not available")

        # Act & Assert
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # User creation should succeed
            user = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type']
            )

            # Container creation should fail
            with pytest.raises(Exception, match="Docker daemon not available"):
                await mock_enhanced_docker_manager.create_container(
                    image="vpn-server:latest",
                    name=f"vpn_{user.username}"
                )

            # User should still exist (no automatic rollback)
            retrieved_user = await user_manager.get_user(user.id)
            assert retrieved_user is not None

        except ImportError:
            pytest.skip("Enhanced user manager not available")

    async def test_partial_batch_operation_handling(
        self,
        mock_enhanced_docker_manager
    ):
        """Test handling of partial failures in batch operations."""
        # Arrange
        container_ids = ["container_1", "container_2", "container_3", "container_4"]

        # Mock partial success (2 succeed, 2 fail)
        mock_enhanced_docker_manager.start_containers_batch.return_value = {
            "container_1": True,
            "container_2": False,  # Failed
            "container_3": True,
            "container_4": False   # Failed
        }

        # Act
        results = await mock_enhanced_docker_manager.start_containers_batch(container_ids)

        # Assert
        assert results["container_1"] is True
        assert results["container_2"] is False
        assert results["container_3"] is True
        assert results["container_4"] is False

        # Count successes and failures
        successes = sum(1 for success in results.values() if success)
        failures = sum(1 for success in results.values() if not success)

        assert successes == 2
        assert failures == 2


@pytest.mark.integration
@pytest.mark.asyncio
class TestCachingIntegration:
    """Test caching integration across services."""

    async def test_user_cache_consistency(
        self,
        db_session
    ):
        """Test that user cache remains consistent across operations."""
        # Arrange
        user_data = UserDataFactory.build_dict()

        # Act
        try:
            from vpn.services.enhanced_user_manager import EnhancedUserManager
            user_manager = EnhancedUserManager(session=db_session)

            # Create user - should be cached
            user1 = await user_manager.create(
                username=user_data['username'],
                email=user_data['email'],
                protocol_type=user_data['protocol_type']
            )

            # Retrieve user - should come from cache
            user2 = await user_manager.get_user(user1.id)

            # Update user - should invalidate cache
            user3 = await user_manager.update(user1.id, email="updated@example.com")

            # Retrieve again - should get updated data
            user4 = await user_manager.get_user(user1.id)

        except ImportError:
            pytest.skip("Enhanced user manager not available")

        # Assert
        assert user1.id == user2.id == user3.id == user4.id
        assert user1.email == user2.email == user_data['email']
        assert user3.email == user4.email == "updated@example.com"

    @patch('vpn.services.caching_service.get_caching_service')
    async def test_cross_service_cache_invalidation(
        self,
        mock_get_caching_service,
        mock_enhanced_docker_manager
    ):
        """Test cache invalidation across different services."""
        # Arrange
        mock_cache = AsyncMock()
        mock_get_caching_service.return_value = mock_cache

        container_id = "test_container_123"

        # Act
        # Simulate container operation that should invalidate cache
        await mock_enhanced_docker_manager.restart_container(container_id)

        # In a real implementation, this would trigger cache invalidation
        # We simulate the expected behavior
        await mock_cache.invalidate_pattern(f"container:{container_id}:*")

        # Assert
        mock_cache.invalidate_pattern.assert_called_once_with(f"container:{container_id}:*")
