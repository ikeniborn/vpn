"""
Enhanced network management service with health checks and resilience patterns.
"""

import asyncio
import ipaddress
import socket
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import aiofiles
import psutil

from vpn.core.exceptions import (
    FirewallError,
    NetworkError,
    PermissionError,
    PortAlreadyInUseError,
)
from vpn.core.models import FirewallRule
from vpn.services.base_service import (
    EnhancedBaseService,
    ServiceHealth,
    ServiceStatus,
    with_retry,
    CircuitBreaker,
    ConnectionPool,
)
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class EnhancedNetworkManager(EnhancedBaseService[None]):
    """Enhanced network management service with resilience patterns."""
    
    def __init__(self):
        """Initialize enhanced network manager."""
        super().__init__(
            circuit_breaker=CircuitBreaker(
                failure_threshold=3,
                recovery_timeout=30,
                expected_exception=NetworkError
            ),
            name="NetworkManager"
        )
        
        self._firewall_backup = Path("/tmp/vpn_firewall_backup.rules")
        self._public_ip_cache = None
        self._cache_timestamp = 0
        self._cache_ttl = 300  # 5 minutes
        
        # Network test endpoints for health checks
        self._test_endpoints = [
            ("8.8.8.8", 53),  # Google DNS
            ("1.1.1.1", 53),  # Cloudflare DNS
            ("208.67.222.222", 53),  # OpenDNS
        ]
    
    async def health_check(self) -> ServiceHealth:
        """Perform health check on network service."""
        try:
            metrics = {}
            
            # Test network connectivity
            connectivity_score = await self._test_network_connectivity()
            metrics["connectivity_score"] = connectivity_score
            
            # Check firewall status
            firewall_operational = await self._test_firewall_access()
            metrics["firewall_operational"] = firewall_operational
            
            # Check port availability
            test_port = await self.find_available_port(50000, 50100)
            metrics["port_scan_operational"] = test_port is not None
            
            # Get network interface info
            interfaces = await self.get_local_ips()
            metrics["local_interfaces_count"] = len(interfaces)
            
            # Check public IP accessibility
            public_ip = await self.get_public_ip()
            metrics["public_ip_accessible"] = public_ip is not None
            
            # Determine overall status
            if connectivity_score >= 0.7 and firewall_operational:
                status = ServiceStatus.HEALTHY
                message = f"Network operational. Connectivity: {connectivity_score:.1%}"
            elif connectivity_score >= 0.3:
                status = ServiceStatus.DEGRADED
                message = f"Network degraded. Limited connectivity: {connectivity_score:.1%}"
            else:
                status = ServiceStatus.UNHEALTHY
                message = "Network connectivity issues detected"
            
            metrics.update({
                "circuit_breaker_state": self.circuit_breaker.state.value,
                "failure_count": self.circuit_breaker.failure_count,
            })
            
            return ServiceHealth(
                service=self.name,
                status=status,
                message=message,
                metrics=metrics
            )
        
        except Exception as e:
            self.logger.error(f"Network health check failed: {e}")
            return ServiceHealth(
                service=self.name,
                status=ServiceStatus.UNHEALTHY,
                message=f"Health check failed: {str(e)}",
                metrics={
                    "circuit_breaker_state": self.circuit_breaker.state.value,
                    "failure_count": self.circuit_breaker.failure_count,
                }
            )
    
    async def cleanup(self):
        """Cleanup network manager resources."""
        self.logger.info("Cleaning up NetworkManager resources...")
        # Clear caches
        self._public_ip_cache = None
        self._cache_timestamp = 0
    
    async def reconnect(self):
        """Reconnect/reinitialize network connections."""
        self.logger.info("Reconnecting NetworkManager...")
        await self.cleanup()
        
        # Reset circuit breaker
        self.circuit_breaker.failure_count = 0
        self.circuit_breaker.state = self.circuit_breaker.CircuitBreakerState.CLOSED
    
    async def _test_network_connectivity(self) -> float:
        """Test network connectivity to multiple endpoints."""
        successful_tests = 0
        total_tests = len(self._test_endpoints)
        
        async def test_endpoint(host: str, port: int) -> bool:
            try:
                _, writer = await asyncio.wait_for(
                    asyncio.open_connection(host, port),
                    timeout=3.0
                )
                writer.close()
                await writer.wait_closed()
                return True
            except Exception:
                return False
        
        # Test all endpoints concurrently
        tasks = [test_endpoint(host, port) for host, port in self._test_endpoints]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        successful_tests = sum(1 for result in results if result is True)
        return successful_tests / total_tests if total_tests > 0 else 0.0
    
    async def _test_firewall_access(self) -> bool:
        """Test if firewall commands are accessible."""
        try:
            # Simple test that doesn't require root
            result = await self._execute_command(["which", "iptables"])
            return result.returncode == 0
        except Exception:
            return False
    
    # Port management with resilience
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def check_port_available(
        self,
        port: int,
        protocol: str = "tcp",
        host: str = "0.0.0.0"
    ) -> bool:
        """Check if port is available with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._check_port_available_impl,
                port,
                protocol,
                host
            )
        except Exception as e:
            self.logger.error(f"Failed to check port {port} availability: {e}")
            return False
    
    async def _check_port_available_impl(
        self,
        port: int,
        protocol: str,
        host: str
    ) -> bool:
        """Internal port availability check implementation."""
        try:
            if protocol.lower() == "tcp":
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            else:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            
            sock.settimeout(1)
            result = sock.connect_ex((host, port))
            sock.close()
            
            # 0 means port is in use
            return result != 0
            
        except Exception as e:
            self.logger.error(f"Port availability check failed: {e}")
            raise NetworkError(f"Port check failed: {e}")
    
    async def find_available_port(
        self,
        start_port: int = 10000,
        end_port: int = 65000,
        protocol: str = "tcp"
    ) -> Optional[int]:
        """Find an available port in range with enhanced error handling."""
        try:
            return await self.circuit_breaker.call(
                self._find_available_port_impl,
                start_port,
                end_port,
                protocol
            )
        except Exception as e:
            self.logger.error(f"Failed to find available port: {e}")
            return None
    
    async def _find_available_port_impl(
        self,
        start_port: int,
        end_port: int,
        protocol: str
    ) -> Optional[int]:
        """Internal find available port implementation."""
        import random
        
        # Try random ports first for better distribution
        for _ in range(100):
            port = random.randint(start_port, end_port)
            if await self._check_port_available_impl(port, protocol, "0.0.0.0"):
                return port
        
        # Fall back to sequential search
        for port in range(start_port, end_port + 1):
            if await self._check_port_available_impl(port, protocol, "0.0.0.0"):
                return port
        
        return None
    
    async def get_listening_ports(self) -> Dict[int, str]:
        """Get all listening ports on the system with error handling."""
        try:
            return await self.circuit_breaker.call(self._get_listening_ports_impl)
        except Exception as e:
            self.logger.error(f"Failed to get listening ports: {e}")
            return {}
    
    async def _get_listening_ports_impl(self) -> Dict[int, str]:
        """Internal get listening ports implementation."""
        ports = {}
        
        for conn in psutil.net_connections(kind='inet'):
            if conn.status == psutil.CONN_LISTEN:
                port = conn.laddr.port
                try:
                    process = psutil.Process(conn.pid)
                    ports[port] = process.name()
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    ports[port] = "unknown"
        
        return ports
    
    # Firewall management with resilience
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def add_firewall_rule(self, rule: FirewallRule) -> bool:
        """Add firewall rule with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._add_firewall_rule_impl,
                rule
            )
        except Exception as e:
            self.logger.error(f"Failed to add firewall rule: {e}")
            raise
    
    async def _add_firewall_rule_impl(self, rule: FirewallRule) -> bool:
        """Internal add firewall rule implementation."""
        # Check if running with sufficient privileges
        if not await self._check_privileges():
            raise PermissionError("add_firewall_rule")
        
        # Build iptables command
        commands = []
        
        if rule.protocol in ["tcp", "both"]:
            cmd = self._build_iptables_command("A", rule, "tcp")
            commands.append(cmd)
        
        if rule.protocol in ["udp", "both"]:
            cmd = self._build_iptables_command("A", rule, "udp")
            commands.append(cmd)
        
        # Execute commands
        for cmd in commands:
            result = await self._execute_command(cmd)
            if result.returncode != 0:
                self.logger.error(f"Failed to add firewall rule: {result.stderr}")
                raise FirewallError(f"Failed to add firewall rule: {result.stderr}")
        
        self.logger.info(f"Added firewall rule for port {rule.port}/{rule.protocol}")
        return True
    
    @with_retry(max_attempts=2, initial_delay=0.5)
    async def remove_firewall_rule(self, rule: FirewallRule) -> bool:
        """Remove firewall rule with retry logic."""
        try:
            return await self.circuit_breaker.call(
                self._remove_firewall_rule_impl,
                rule
            )
        except Exception as e:
            self.logger.error(f"Failed to remove firewall rule: {e}")
            return False
    
    async def _remove_firewall_rule_impl(self, rule: FirewallRule) -> bool:
        """Internal remove firewall rule implementation."""
        # Check if running with sufficient privileges
        if not await self._check_privileges():
            raise PermissionError("remove_firewall_rule")
        
        # Build iptables command
        commands = []
        
        if rule.protocol in ["tcp", "both"]:
            cmd = self._build_iptables_command("D", rule, "tcp")
            commands.append(cmd)
        
        if rule.protocol in ["udp", "both"]:
            cmd = self._build_iptables_command("D", rule, "udp")
            commands.append(cmd)
        
        # Execute commands
        for cmd in commands:
            result = await self._execute_command(cmd)
            # Ignore errors for deletion (rule might not exist)
            if result.returncode != 0:
                self.logger.warning(f"Rule might not exist: {result.stderr}")
        
        self.logger.info(f"Removed firewall rule for port {rule.port}/{rule.protocol}")
        return True
    
    async def list_firewall_rules(self) -> List[str]:
        """List current firewall rules with error handling."""
        try:
            return await self.circuit_breaker.call(self._list_firewall_rules_impl)
        except Exception as e:
            self.logger.error(f"Failed to list firewall rules: {e}")
            return []
    
    async def _list_firewall_rules_impl(self) -> List[str]:
        """Internal list firewall rules implementation."""
        cmd = ["iptables", "-L", "-n", "-v"]
        result = await self._execute_command(cmd)
        
        if result.returncode != 0:
            raise FirewallError(f"Failed to list firewall rules: {result.stderr}")
        
        return result.stdout.split('\n')
    
    @with_retry(max_attempts=2, initial_delay=1.0)
    async def backup_firewall_rules(self) -> bool:
        """Backup current firewall rules with retry."""
        try:
            return await self.circuit_breaker.call(self._backup_firewall_rules_impl)
        except Exception as e:
            self.logger.error(f"Failed to backup firewall rules: {e}")
            return False
    
    async def _backup_firewall_rules_impl(self) -> bool:
        """Internal backup firewall rules implementation."""
        cmd = ["iptables-save"]
        result = await self._execute_command(cmd)
        
        if result.returncode != 0:
            raise FirewallError(f"Failed to backup firewall rules: {result.stderr}")
        
        async with aiofiles.open(self._firewall_backup, 'w') as f:
            await f.write(result.stdout)
        
        self.logger.info(f"Backed up firewall rules to {self._firewall_backup}")
        return True
    
    @with_retry(max_attempts=2, initial_delay=1.0)
    async def restore_firewall_rules(self) -> bool:
        """Restore firewall rules from backup with retry."""
        try:
            return await self.circuit_breaker.call(self._restore_firewall_rules_impl)
        except Exception as e:
            self.logger.error(f"Failed to restore firewall rules: {e}")
            return False
    
    async def _restore_firewall_rules_impl(self) -> bool:
        """Internal restore firewall rules implementation."""
        if not self._firewall_backup.exists():
            self.logger.warning("No firewall backup found")
            return False
        
        async with aiofiles.open(self._firewall_backup, 'r') as f:
            rules = await f.read()
        
        cmd = ["iptables-restore"]
        result = await self._execute_command(cmd, input=rules)
        
        if result.returncode != 0:
            raise FirewallError(f"Failed to restore firewall rules: {result.stderr}")
        
        self.logger.info("Restored firewall rules from backup")
        return True
    
    # IP address management with caching and resilience
    
    @with_retry(max_attempts=3, initial_delay=1.0)
    async def get_public_ip(self, force_refresh: bool = False) -> Optional[str]:
        """Get public IP address with retry and caching."""
        # Check cache
        current_time = time.time()
        if not force_refresh and self._public_ip_cache:
            if current_time - self._cache_timestamp < self._cache_ttl:
                return self._public_ip_cache
        
        try:
            return await self.circuit_breaker.call(
                self._get_public_ip_impl,
                current_time
            )
        except Exception as e:
            self.logger.error(f"Failed to get public IP: {e}")
            return None
    
    async def _get_public_ip_impl(self, current_time: float) -> Optional[str]:
        """Internal get public IP implementation."""
        import httpx
        
        # Try multiple services for redundancy
        services = [
            "https://api.ipify.org",
            "https://ipinfo.io/ip",
            "https://checkip.amazonaws.com",
            "https://icanhazip.com",
        ]
        
        async with httpx.AsyncClient(timeout=5) as client:
            for service in services:
                try:
                    response = await client.get(service)
                    if response.status_code == 200:
                        ip = response.text.strip()
                        
                        # Validate IP
                        ipaddress.ip_address(ip)
                        
                        # Update cache
                        self._public_ip_cache = ip
                        self._cache_timestamp = current_time
                        
                        return ip
                except Exception:
                    continue
        
        raise NetworkError("All public IP services failed")
    
    async def get_local_ips(self) -> List[str]:
        """Get all local IP addresses with error handling."""
        try:
            return await self.circuit_breaker.call(self._get_local_ips_impl)
        except Exception as e:
            self.logger.error(f"Failed to get local IPs: {e}")
            return []
    
    async def _get_local_ips_impl(self) -> List[str]:
        """Internal get local IPs implementation."""
        ips = []
        
        for interface, addrs in psutil.net_if_addrs().items():
            for addr in addrs:
                if addr.family == socket.AF_INET:
                    ip = addr.address
                    # Skip loopback
                    if not ip.startswith("127."):
                        ips.append(ip)
        
        return ips
    
    async def get_default_interface(self) -> Optional[str]:
        """Get default network interface with error handling."""
        try:
            return await self.circuit_breaker.call(self._get_default_interface_impl)
        except Exception as e:
            self.logger.error(f"Failed to get default interface: {e}")
            return None
    
    async def _get_default_interface_impl(self) -> Optional[str]:
        """Internal get default interface implementation."""
        # Get interface stats
        stats = psutil.net_if_stats()
        
        # Find interface with default route
        for interface, stat in stats.items():
            if stat.isup and not interface.startswith("lo"):
                # Check if this interface has an IP
                addrs = psutil.net_if_addrs().get(interface, [])
                for addr in addrs:
                    if addr.family == socket.AF_INET:
                        return interface
        
        return None
    
    # Subnet management with validation
    
    async def validate_subnet(self, subnet: str) -> bool:
        """Validate subnet notation with error handling."""
        try:
            ipaddress.ip_network(subnet, strict=False)
            return True
        except ValueError:
            return False
    
    async def check_subnet_conflicts(self, subnet: str) -> List[str]:
        """Check for subnet conflicts with error handling."""
        try:
            return await self.circuit_breaker.call(
                self._check_subnet_conflicts_impl,
                subnet
            )
        except Exception as e:
            self.logger.error(f"Failed to check subnet conflicts: {e}")
            return []
    
    async def _check_subnet_conflicts_impl(self, subnet: str) -> List[str]:
        """Internal check subnet conflicts implementation."""
        conflicts = []
        
        target_network = ipaddress.ip_network(subnet, strict=False)
        
        # Check Docker networks
        try:
            import docker
            client = docker.from_env()
            
            for network in client.networks.list():
                if network.attrs.get("IPAM"):
                    for config in network.attrs["IPAM"].get("Config", []):
                        if "Subnet" in config:
                            existing_network = ipaddress.ip_network(
                                config["Subnet"], 
                                strict=False
                            )
                            
                            if target_network.overlaps(existing_network):
                                conflicts.append(f"Docker network: {network.name}")
                                
        except Exception as e:
            self.logger.warning(f"Failed to check Docker networks: {e}")
        
        # Check system interfaces
        for interface, addrs in psutil.net_if_addrs().items():
            for addr in addrs:
                if addr.family == socket.AF_INET and addr.netmask:
                    try:
                        # Calculate network from IP and netmask
                        ip_int = int(ipaddress.ip_address(addr.address))
                        mask_int = int(ipaddress.ip_address(addr.netmask))
                        network_int = ip_int & mask_int
                        network_addr = ipaddress.ip_address(network_int)
                        
                        # Calculate prefix length
                        prefix_len = bin(mask_int).count('1')
                        
                        existing_network = ipaddress.ip_network(
                            f"{network_addr}/{prefix_len}",
                            strict=False
                        )
                        
                        if target_network.overlaps(existing_network):
                            conflicts.append(f"System interface: {interface}")
                            
                    except Exception:
                        continue
        
        return conflicts
    
    async def suggest_subnet(self) -> str:
        """Suggest an available subnet for Docker with conflict checking."""
        # Common private network ranges to try
        candidates = [
            "172.20.0.0/16",
            "172.21.0.0/16",
            "172.22.0.0/16",
            "172.23.0.0/16",
            "172.24.0.0/16",
            "172.25.0.0/16",
            "10.10.0.0/16",
            "10.20.0.0/16",
            "10.30.0.0/16",
        ]
        
        for subnet in candidates:
            conflicts = await self.check_subnet_conflicts(subnet)
            if not conflicts:
                return subnet
        
        # Default fallback
        return "172.20.0.0/16"
    
    # Private methods
    
    async def _check_privileges(self) -> bool:
        """Check if running with sufficient privileges."""
        import os
        return os.geteuid() == 0
    
    async def _execute_command(
        self,
        cmd: List[str],
        input: Optional[str] = None,
        timeout: int = 30
    ) -> subprocess.CompletedProcess:
        """Execute shell command asynchronously with timeout."""
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE if input else None,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(
                process.communicate(input=input.encode() if input else None),
                timeout=timeout
            )
            
            return subprocess.CompletedProcess(
                args=cmd,
                returncode=process.returncode,
                stdout=stdout.decode(),
                stderr=stderr.decode()
            )
        
        except asyncio.TimeoutError:
            # Kill the process if it times out
            if process:
                process.kill()
                await process.wait()
            raise NetworkError(f"Command timed out after {timeout}s: {' '.join(cmd)}")
    
    def _build_iptables_command(
        self,
        action: str,
        rule: FirewallRule,
        protocol: str
    ) -> List[str]:
        """Build iptables command from rule."""
        cmd = ["iptables", f"-{action}", "INPUT"]
        
        # Protocol
        cmd.extend(["-p", protocol])
        
        # Port
        cmd.extend(["--dport", str(rule.port)])
        
        # Source
        if rule.source:
            cmd.extend(["-s", rule.source])
        
        # Action
        target = "ACCEPT" if rule.action == "allow" else "DROP"
        cmd.extend(["-j", target])
        
        # Comment
        if rule.comment:
            cmd.extend(["-m", "comment", "--comment", rule.comment])
        
        return cmd