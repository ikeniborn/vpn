"""
Network management service.
"""

import asyncio
import ipaddress
import re
import socket
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import aiofiles
import psutil

from vpn.core.exceptions import FirewallError, NetworkError, PermissionError, PortAlreadyInUseError
from vpn.core.models import FirewallRule
from vpn.services.base import BaseService
from vpn.utils.logger import get_logger

logger = get_logger(__name__)


class NetworkManager(BaseService):
    """Service for network operations."""
    
    def __init__(self):
        """Initialize network manager."""
        super().__init__()
        self._firewall_backup = Path("/tmp/vpn_firewall_backup.rules")
        self._public_ip_cache = None
        self._cache_timestamp = 0
        self._cache_ttl = 300  # 5 minutes
    
    # Port management
    
    async def check_port_available(
        self,
        port: int,
        protocol: str = "tcp",
        host: str = "0.0.0.0"
    ) -> bool:
        """
        Check if port is available.
        
        Args:
            port: Port number
            protocol: Protocol (tcp/udp)
            host: Host to check
            
        Returns:
            True if port is available
        """
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
            logger.error(f"Failed to check port availability: {e}")
            return False
    
    async def find_available_port(
        self,
        start_port: int = 10000,
        end_port: int = 65000,
        protocol: str = "tcp"
    ) -> Optional[int]:
        """
        Find an available port in range.
        
        Args:
            start_port: Start of port range
            end_port: End of port range
            protocol: Protocol (tcp/udp)
            
        Returns:
            Available port or None
        """
        import random
        
        # Try random ports first for better distribution
        for _ in range(100):
            port = random.randint(start_port, end_port)
            if await self.check_port_available(port, protocol):
                return port
        
        # Fall back to sequential search
        for port in range(start_port, end_port + 1):
            if await self.check_port_available(port, protocol):
                return port
        
        return None
    
    async def get_listening_ports(self) -> Dict[int, str]:
        """
        Get all listening ports on the system.
        
        Returns:
            Dictionary of port -> process name
        """
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
    
    # Firewall management
    
    async def add_firewall_rule(self, rule: FirewallRule) -> bool:
        """
        Add firewall rule using iptables.
        
        Args:
            rule: Firewall rule to add
            
        Returns:
            True if successful
        """
        try:
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
                    logger.error(f"Failed to add firewall rule: {result.stderr}")
                    return False
            
            logger.info(f"Added firewall rule for port {rule.port}/{rule.protocol}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add firewall rule: {e}")
            raise FirewallError(f"Failed to add firewall rule: {e}")
    
    async def remove_firewall_rule(self, rule: FirewallRule) -> bool:
        """
        Remove firewall rule using iptables.
        
        Args:
            rule: Firewall rule to remove
            
        Returns:
            True if successful
        """
        try:
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
                    logger.warning(f"Rule might not exist: {result.stderr}")
            
            logger.info(f"Removed firewall rule for port {rule.port}/{rule.protocol}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to remove firewall rule: {e}")
            raise FirewallError(f"Failed to remove firewall rule: {e}")
    
    async def list_firewall_rules(self) -> List[str]:
        """
        List current firewall rules.
        
        Returns:
            List of firewall rules
        """
        try:
            cmd = ["iptables", "-L", "-n", "-v"]
            result = await self._execute_command(cmd)
            
            if result.returncode != 0:
                logger.error(f"Failed to list firewall rules: {result.stderr}")
                return []
            
            return result.stdout.split('\n')
            
        except Exception as e:
            logger.error(f"Failed to list firewall rules: {e}")
            return []
    
    async def backup_firewall_rules(self) -> bool:
        """Backup current firewall rules."""
        try:
            cmd = ["iptables-save"]
            result = await self._execute_command(cmd)
            
            if result.returncode != 0:
                logger.error(f"Failed to backup firewall rules: {result.stderr}")
                return False
            
            async with aiofiles.open(self._firewall_backup, 'w') as f:
                await f.write(result.stdout)
            
            logger.info(f"Backed up firewall rules to {self._firewall_backup}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to backup firewall rules: {e}")
            return False
    
    async def restore_firewall_rules(self) -> bool:
        """Restore firewall rules from backup."""
        try:
            if not self._firewall_backup.exists():
                logger.warning("No firewall backup found")
                return False
            
            async with aiofiles.open(self._firewall_backup, 'r') as f:
                rules = await f.read()
            
            cmd = ["iptables-restore"]
            result = await self._execute_command(cmd, input=rules)
            
            if result.returncode != 0:
                logger.error(f"Failed to restore firewall rules: {result.stderr}")
                return False
            
            logger.info("Restored firewall rules from backup")
            return True
            
        except Exception as e:
            logger.error(f"Failed to restore firewall rules: {e}")
            return False
    
    # IP address management
    
    async def get_public_ip(self, force_refresh: bool = False) -> Optional[str]:
        """
        Get public IP address.
        
        Args:
            force_refresh: Force refresh even if cached
            
        Returns:
            Public IP address or None
        """
        import time
        
        # Check cache
        current_time = time.time()
        if not force_refresh and self._public_ip_cache:
            if current_time - self._cache_timestamp < self._cache_ttl:
                return self._public_ip_cache
        
        try:
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
            
            return None
            
        except Exception as e:
            logger.error(f"Failed to get public IP: {e}")
            return None
    
    async def get_local_ips(self) -> List[str]:
        """Get all local IP addresses."""
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
        """Get default network interface."""
        try:
            # Get default gateway
            gateways = psutil.net_if_stats()
            
            # Find interface with default route
            for interface, stats in gateways.items():
                if stats.isup and not interface.startswith("lo"):
                    # Check if this interface has an IP
                    addrs = psutil.net_if_addrs().get(interface, [])
                    for addr in addrs:
                        if addr.family == socket.AF_INET:
                            return interface
            
            return None
            
        except Exception as e:
            logger.error(f"Failed to get default interface: {e}")
            return None
    
    # Subnet management
    
    async def validate_subnet(self, subnet: str) -> bool:
        """
        Validate subnet notation.
        
        Args:
            subnet: Subnet in CIDR notation
            
        Returns:
            True if valid
        """
        try:
            ipaddress.ip_network(subnet, strict=False)
            return True
        except ValueError:
            return False
    
    async def check_subnet_conflicts(self, subnet: str) -> List[str]:
        """
        Check for subnet conflicts with existing networks.
        
        Args:
            subnet: Subnet to check
            
        Returns:
            List of conflicting networks
        """
        conflicts = []
        
        try:
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
                logger.warning(f"Failed to check Docker networks: {e}")
            
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
            
        except Exception as e:
            logger.error(f"Failed to check subnet conflicts: {e}")
            return []
    
    async def suggest_subnet(self) -> str:
        """
        Suggest an available subnet for Docker.
        
        Returns:
            Suggested subnet in CIDR notation
        """
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
        input: Optional[str] = None
    ) -> subprocess.CompletedProcess:
        """Execute shell command asynchronously."""
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE if input else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate(
            input=input.encode() if input else None
        )
        
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=process.returncode,
            stdout=stdout.decode(),
            stderr=stderr.decode()
        )
    
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