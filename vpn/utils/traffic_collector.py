"""
Enhanced traffic statistics collection and monitoring.
"""

import asyncio
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import psutil
from docker import DockerClient
from docker.errors import DockerException

from vpn.core.config import settings
from vpn.core.models import TrafficStats
from vpn.services.user_manager import UserManager
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class NetworkInterfaceStats:
    """Network interface statistics."""
    interface: str
    bytes_sent: int
    bytes_recv: int
    packets_sent: int
    packets_recv: int
    timestamp: datetime


@dataclass
class ContainerNetworkStats:
    """Container network statistics."""
    container_id: str
    container_name: str
    rx_bytes: int
    tx_bytes: int
    rx_packets: int
    tx_packets: int
    timestamp: datetime


@dataclass
class UserTrafficSample:
    """User traffic sample point."""
    user_id: str
    upload_bytes: int
    download_bytes: int
    active_connections: int
    timestamp: datetime


class TrafficCollector:
    """Collects and processes traffic statistics."""
    
    def __init__(self, collection_interval: int = 30):
        self.collection_interval = collection_interval
        self.user_manager = UserManager()
        self.docker_client = None
        self.collecting = False
        self.stats_history: Dict[str, List[UserTrafficSample]] = {}
        self.interface_stats: Dict[str, List[NetworkInterfaceStats]] = {}
        
        # Initialize Docker client
        try:
            self.docker_client = DockerClient.from_env()
        except DockerException as e:
            logger.warning(f"Docker not available for traffic collection: {e}")
    
    async def start_collection(self):
        """Start traffic collection in background."""
        if self.collecting:
            logger.warning("Traffic collection already running")
            return
        
        self.collecting = True
        logger.info(f"Starting traffic collection (interval: {self.collection_interval}s)")
        
        # Start collection tasks
        tasks = [
            asyncio.create_task(self._collect_system_stats()),
            asyncio.create_task(self._collect_container_stats()),
            asyncio.create_task(self._collect_user_stats()),
        ]
        
        try:
            await asyncio.gather(*tasks)
        except Exception as e:
            logger.error(f"Traffic collection failed: {e}")
        finally:
            self.collecting = False
    
    async def stop_collection(self):
        """Stop traffic collection."""
        self.collecting = False
        logger.info("Stopping traffic collection")
    
    async def _collect_system_stats(self):
        """Collect system-level network statistics."""
        while self.collecting:
            try:
                # Get network interface stats
                net_io = psutil.net_io_counters(pernic=True)
                timestamp = datetime.now()
                
                for interface, stats in net_io.items():
                    # Skip loopback and virtual interfaces
                    if interface in ['lo', 'docker0'] or interface.startswith('veth'):
                        continue
                    
                    interface_stat = NetworkInterfaceStats(
                        interface=interface,
                        bytes_sent=stats.bytes_sent,
                        bytes_recv=stats.bytes_recv,
                        packets_sent=stats.packets_sent,
                        packets_recv=stats.packets_recv,
                        timestamp=timestamp
                    )
                    
                    if interface not in self.interface_stats:
                        self.interface_stats[interface] = []
                    
                    self.interface_stats[interface].append(interface_stat)
                    
                    # Keep only last 1000 samples per interface
                    if len(self.interface_stats[interface]) > 1000:
                        self.interface_stats[interface] = self.interface_stats[interface][-1000:]
                
                await asyncio.sleep(self.collection_interval)
                
            except Exception as e:
                logger.error(f"System stats collection error: {e}")
                await asyncio.sleep(self.collection_interval)
    
    async def _collect_container_stats(self):
        """Collect Docker container network statistics."""
        if not self.docker_client:
            return
        
        while self.collecting:
            try:
                containers = self.docker_client.containers.list()
                timestamp = datetime.now()
                
                for container in containers:
                    try:
                        # Get container stats
                        stats = container.stats(stream=False)
                        
                        # Extract network stats
                        networks = stats.get('networks', {})
                        
                        total_rx = 0
                        total_tx = 0
                        total_rx_packets = 0
                        total_tx_packets = 0
                        
                        for network_name, network_stats in networks.items():
                            total_rx += network_stats.get('rx_bytes', 0)
                            total_tx += network_stats.get('tx_bytes', 0)
                            total_rx_packets += network_stats.get('rx_packets', 0)
                            total_tx_packets += network_stats.get('tx_packets', 0)
                        
                        container_stat = ContainerNetworkStats(
                            container_id=container.id[:12],
                            container_name=container.name,
                            rx_bytes=total_rx,
                            tx_bytes=total_tx,
                            rx_packets=total_rx_packets,
                            tx_packets=total_tx_packets,
                            timestamp=timestamp
                        )
                        
                        # Store container stats
                        container_key = f"container_{container.name}"
                        if container_key not in self.stats_history:
                            self.stats_history[container_key] = []
                        
                        # Keep only last 500 samples per container
                        if len(self.stats_history[container_key]) > 500:
                            self.stats_history[container_key] = self.stats_history[container_key][-500:]
                    
                    except Exception as e:
                        logger.debug(f"Failed to get stats for container {container.name}: {e}")
                
                await asyncio.sleep(self.collection_interval)
                
            except Exception as e:
                logger.error(f"Container stats collection error: {e}")
                await asyncio.sleep(self.collection_interval)
    
    async def _collect_user_stats(self):
        """Collect per-user traffic statistics."""
        while self.collecting:
            try:
                # Get all active users
                users = await self.user_manager.list_users()
                timestamp = datetime.now()
                
                for user in users:
                    if user.status.value != 'active':
                        continue
                    
                    try:
                        # Calculate user traffic from container stats
                        user_traffic = await self._calculate_user_traffic(user.id)
                        
                        if user_traffic:
                            sample = UserTrafficSample(
                                user_id=str(user.id),
                                upload_bytes=user_traffic['upload'],
                                download_bytes=user_traffic['download'],
                                active_connections=user_traffic['connections'],
                                timestamp=timestamp
                            )
                            
                            if str(user.id) not in self.stats_history:
                                self.stats_history[str(user.id)] = []
                            
                            self.stats_history[str(user.id)].append(sample)
                            
                            # Keep only last 500 samples per user
                            if len(self.stats_history[str(user.id)]) > 500:
                                self.stats_history[str(user.id)] = self.stats_history[str(user.id)][-500:]
                            
                            # Update user's persistent traffic stats
                            await self._update_user_traffic_stats(user.id, user_traffic)
                    
                    except Exception as e:
                        logger.debug(f"Failed to collect stats for user {user.username}: {e}")
                
                await asyncio.sleep(self.collection_interval)
                
            except Exception as e:
                logger.error(f"User stats collection error: {e}")
                await asyncio.sleep(self.collection_interval)
    
    async def _calculate_user_traffic(self, user_id: str) -> Optional[Dict]:
        """Calculate traffic for a specific user."""
        try:
            # This is a simplified implementation
            # In a real scenario, you would correlate container stats with user connections
            # For now, we'll use mock data based on user activity
            
            # Check if user has active connections
            active_connections = await self._get_user_connections(user_id)
            
            if active_connections == 0:
                return {
                    'upload': 0,
                    'download': 0,
                    'connections': 0
                }
            
            # Mock traffic data based on active connections
            # In reality, this would come from parsing container logs or network monitoring
            upload_rate = active_connections * 1024 * 50  # 50KB/s per connection
            download_rate = active_connections * 1024 * 200  # 200KB/s per connection
            
            return {
                'upload': upload_rate * self.collection_interval,
                'download': download_rate * self.collection_interval,
                'connections': active_connections
            }
            
        except Exception as e:
            logger.error(f"Failed to calculate user traffic: {e}")
            return None
    
    async def _get_user_connections(self, user_id: str) -> int:
        """Get number of active connections for a user."""
        try:
            # Mock implementation - in reality this would check:
            # 1. VPN server logs
            # 2. Connection tables
            # 3. Network monitoring data
            
            # For now, return a random number between 0-3
            import random
            return random.randint(0, 3)
            
        except Exception as e:
            logger.error(f"Failed to get user connections: {e}")
            return 0
    
    async def _update_user_traffic_stats(self, user_id: str, traffic: Dict):
        """Update user's persistent traffic statistics."""
        try:
            user = await self.user_manager.get(str(user_id))
            if not user:
                return
            
            # Update cumulative stats
            user.traffic.upload_bytes += traffic['upload']
            user.traffic.download_bytes += traffic['download']
            user.traffic.last_seen = datetime.now()
            
            # Update session info if new connections
            if traffic['connections'] > 0:
                user.traffic.total_sessions += 1
            
            # Save updated user
            await self.user_manager.update(str(user_id), user.model_dump())
            
        except Exception as e:
            logger.error(f"Failed to update user traffic stats: {e}")
    
    def get_user_traffic_history(
        self,
        user_id: str,
        hours: int = 24
    ) -> List[UserTrafficSample]:
        """Get traffic history for a user."""
        if user_id not in self.stats_history:
            return []
        
        cutoff_time = datetime.now() - timedelta(hours=hours)
        
        return [
            sample for sample in self.stats_history[user_id]
            if sample.timestamp >= cutoff_time
        ]
    
    def get_interface_stats(
        self,
        interface: str,
        hours: int = 24
    ) -> List[NetworkInterfaceStats]:
        """Get network interface statistics."""
        if interface not in self.interface_stats:
            return []
        
        cutoff_time = datetime.now() - timedelta(hours=hours)
        
        return [
            stat for stat in self.interface_stats[interface]
            if stat.timestamp >= cutoff_time
        ]
    
    def get_traffic_summary(self, hours: int = 24) -> Dict:
        """Get traffic summary for all users."""
        cutoff_time = datetime.now() - timedelta(hours=hours)
        
        summary = {
            'total_upload': 0,
            'total_download': 0,
            'active_users': 0,
            'total_connections': 0,
            'users': {}
        }
        
        for user_id, samples in self.stats_history.items():
            if user_id.startswith('container_'):
                continue
            
            recent_samples = [
                sample for sample in samples
                if sample.timestamp >= cutoff_time
            ]
            
            if not recent_samples:
                continue
            
            user_upload = sum(sample.upload_bytes for sample in recent_samples)
            user_download = sum(sample.download_bytes for sample in recent_samples)
            max_connections = max(sample.active_connections for sample in recent_samples)
            
            if user_upload > 0 or user_download > 0:
                summary['active_users'] += 1
                summary['total_upload'] += user_upload
                summary['total_download'] += user_download
                summary['total_connections'] += max_connections
                
                summary['users'][user_id] = {
                    'upload': user_upload,
                    'download': user_download,
                    'connections': max_connections
                }
        
        return summary


# Global traffic collector instance
_traffic_collector: Optional[TrafficCollector] = None


async def get_traffic_collector() -> TrafficCollector:
    """Get the global traffic collector instance."""
    global _traffic_collector
    
    if _traffic_collector is None:
        _traffic_collector = TrafficCollector()
    
    return _traffic_collector


async def start_traffic_collection(interval: int = 30):
    """Start global traffic collection."""
    collector = await get_traffic_collector()
    await collector.start_collection()


async def stop_traffic_collection():
    """Stop global traffic collection."""
    collector = await get_traffic_collector()
    await collector.stop_collection()


async def get_user_traffic_stats(user_id: str, hours: int = 24) -> List[UserTrafficSample]:
    """Get traffic statistics for a user."""
    collector = await get_traffic_collector()
    return collector.get_user_traffic_history(user_id, hours)


async def get_system_traffic_summary(hours: int = 24) -> Dict:
    """Get system-wide traffic summary."""
    collector = await get_traffic_collector()
    return collector.get_traffic_summary(hours)