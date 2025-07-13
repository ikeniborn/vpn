"""Bandwidth limiting and QoS (Quality of Service) management for VPN connections.
"""

import subprocess
from dataclasses import dataclass

from vpn.utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class BandwidthLimit:
    """Bandwidth limit configuration."""
    upload_limit: int  # KB/s
    download_limit: int  # KB/s
    burst_limit: int | None = None  # KB/s
    priority: int = 5  # 1-10, higher is better priority


@dataclass
class QoSRule:
    """Quality of Service rule."""
    user_id: str
    interface: str
    bandwidth_limit: BandwidthLimit
    active: bool = True


class BandwidthManager:
    """Manages bandwidth limiting and QoS for VPN users."""

    def __init__(self):
        self.active_rules: dict[str, QoSRule] = {}
        self.tc_available = self._check_tc_availability()
        self.iptables_available = self._check_iptables_availability()

    def _check_tc_availability(self) -> bool:
        """Check if tc (traffic control) is available."""
        try:
            result = subprocess.run(
                ['tc', '-V'],
                check=False, capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            logger.warning("tc (traffic control) not available - bandwidth limiting disabled")
            return False

    def _check_iptables_availability(self) -> bool:
        """Check if iptables is available."""
        try:
            result = subprocess.run(
                ['iptables', '--version'],
                check=False, capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            logger.warning("iptables not available - some QoS features disabled")
            return False

    async def apply_user_bandwidth_limit(
        self,
        user_id: str,
        interface: str,
        bandwidth_limit: BandwidthLimit
    ) -> bool:
        """Apply bandwidth limit for a specific user."""
        if not self.tc_available:
            logger.warning("Cannot apply bandwidth limit - tc not available")
            return False

        try:
            # Create QoS rule
            rule = QoSRule(
                user_id=user_id,
                interface=interface,
                bandwidth_limit=bandwidth_limit
            )

            # Apply traffic control rules
            success = await self._apply_tc_rules(rule)

            if success:
                self.active_rules[user_id] = rule
                logger.info(
                    f"Applied bandwidth limit for user {user_id}: "
                    f"↑{bandwidth_limit.upload_limit}KB/s ↓{bandwidth_limit.download_limit}KB/s"
                )

            return success

        except Exception as e:
            logger.error(f"Failed to apply bandwidth limit for user {user_id}: {e}")
            return False

    async def _apply_tc_rules(self, rule: QoSRule) -> bool:
        """Apply traffic control rules using tc command."""
        try:
            interface = rule.interface
            user_id = rule.user_id
            limits = rule.bandwidth_limit

            # Create class IDs (using hash of user_id to ensure uniqueness)
            class_id = abs(hash(user_id)) % 10000 + 1000

            # Commands to set up traffic shaping
            commands = [
                # Create root qdisc if not exists
                f"tc qdisc add dev {interface} root handle 1: htb default 999",

                # Create class for user with upload limit
                f"tc class add dev {interface} parent 1: classid 1:{class_id} htb rate {limits.upload_limit}kbit ceil {limits.upload_limit * 2}kbit prio {rule.bandwidth_limit.priority}",

                # Create leaf qdisc for fairness
                f"tc qdisc add dev {interface} parent 1:{class_id} handle {class_id}: sfq perturb 10",
            ]

            # Execute commands
            for cmd in commands:
                try:
                    result = await self._run_tc_command(cmd)
                    if not result:
                        # If root qdisc already exists, ignore the error for the first command
                        if "add dev" in cmd and "root handle" in cmd:
                            continue
                        logger.warning(f"TC command failed: {cmd}")
                except Exception as e:
                    logger.debug(f"TC command error (may be expected): {cmd} - {e}")

            # Apply download limits using ingress
            await self._apply_ingress_limits(interface, user_id, limits.download_limit)

            return True

        except Exception as e:
            logger.error(f"Failed to apply TC rules: {e}")
            return False

    async def _apply_ingress_limits(self, interface: str, user_id: str, download_limit: int):
        """Apply download bandwidth limits using ingress qdisc."""
        try:
            # Ingress shaping is more complex and often requires IFB (Intermediate Functional Block)
            # For simplicity, we'll use a basic ingress policer

            commands = [
                # Add ingress qdisc
                f"tc qdisc add dev {interface} ingress",

                # Add policing rule for download limit
                f"tc filter add dev {interface} parent ffff: protocol ip prio 1 u32 match ip dst 0.0.0.0/0 police rate {download_limit}kbit burst {download_limit * 2}kbit drop",
            ]

            for cmd in commands:
                try:
                    await self._run_tc_command(cmd)
                except Exception as e:
                    logger.debug(f"Ingress command error (may be expected): {cmd} - {e}")

        except Exception as e:
            logger.error(f"Failed to apply ingress limits: {e}")

    async def _run_tc_command(self, command: str) -> bool:
        """Run a tc command."""
        try:
            cmd_parts = command.split()
            result = subprocess.run(
                cmd_parts,
                check=False, capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0:
                return True
            else:
                logger.debug(f"TC command failed: {command} - {result.stderr}")
                return False

        except subprocess.TimeoutExpired:
            logger.error(f"TC command timed out: {command}")
            return False
        except Exception as e:
            logger.error(f"TC command error: {command} - {e}")
            return False

    async def remove_user_bandwidth_limit(self, user_id: str) -> bool:
        """Remove bandwidth limit for a specific user."""
        if user_id not in self.active_rules:
            logger.warning(f"No active bandwidth rule found for user {user_id}")
            return True

        try:
            rule = self.active_rules[user_id]

            # Remove traffic control rules
            success = await self._remove_tc_rules(rule)

            if success:
                del self.active_rules[user_id]
                logger.info(f"Removed bandwidth limit for user {user_id}")

            return success

        except Exception as e:
            logger.error(f"Failed to remove bandwidth limit for user {user_id}: {e}")
            return False

    async def _remove_tc_rules(self, rule: QoSRule) -> bool:
        """Remove traffic control rules for a user."""
        try:
            interface = rule.interface
            user_id = rule.user_id

            # Calculate class ID
            class_id = abs(hash(user_id)) % 10000 + 1000

            # Commands to remove traffic shaping
            commands = [
                # Remove class
                f"tc class del dev {interface} classid 1:{class_id}",

                # Remove filters if any
                f"tc filter del dev {interface} parent 1: prio {rule.bandwidth_limit.priority}",
            ]

            # Execute removal commands
            for cmd in commands:
                try:
                    await self._run_tc_command(cmd)
                except Exception as e:
                    logger.debug(f"TC removal command error (may be expected): {cmd} - {e}")

            return True

        except Exception as e:
            logger.error(f"Failed to remove TC rules: {e}")
            return False

    async def list_active_limits(self) -> list[QoSRule]:
        """List all active bandwidth limits."""
        return list(self.active_rules.values())

    async def get_user_limit(self, user_id: str) -> QoSRule | None:
        """Get bandwidth limit for a specific user."""
        return self.active_rules.get(user_id)

    async def update_user_limit(
        self,
        user_id: str,
        new_limit: BandwidthLimit
    ) -> bool:
        """Update bandwidth limit for a user."""
        if user_id not in self.active_rules:
            logger.warning(f"No active rule found for user {user_id}")
            return False

        try:
            # Remove existing limit
            await self.remove_user_bandwidth_limit(user_id)

            # Apply new limit
            rule = self.active_rules.get(user_id)
            if rule:
                return await self.apply_user_bandwidth_limit(
                    user_id,
                    rule.interface,
                    new_limit
                )

            return False

        except Exception as e:
            logger.error(f"Failed to update bandwidth limit for user {user_id}: {e}")
            return False

    async def clear_all_limits(self) -> bool:
        """Clear all bandwidth limits."""
        try:
            success = True

            for user_id in list(self.active_rules.keys()):
                if not await self.remove_user_bandwidth_limit(user_id):
                    success = False

            logger.info("Cleared all bandwidth limits")
            return success

        except Exception as e:
            logger.error(f"Failed to clear all bandwidth limits: {e}")
            return False

    async def apply_global_bandwidth_limit(
        self,
        interface: str,
        total_upload: int,
        total_download: int
    ) -> bool:
        """Apply global bandwidth limit for the interface."""
        if not self.tc_available:
            logger.warning("Cannot apply global bandwidth limit - tc not available")
            return False

        try:
            # Remove existing root qdisc
            await self._run_tc_command(f"tc qdisc del dev {interface} root")

            # Create new root qdisc with global limits
            commands = [
                f"tc qdisc add dev {interface} root handle 1: htb default 999",
                f"tc class add dev {interface} parent 1: classid 1:1 htb rate {total_upload}kbit ceil {total_upload}kbit",
                f"tc class add dev {interface} parent 1:1 classid 1:999 htb rate {total_upload // 10}kbit ceil {total_upload}kbit prio 9",
            ]

            for cmd in commands:
                await self._run_tc_command(cmd)

            logger.info(f"Applied global bandwidth limit: {total_upload}KB/s upload")
            return True

        except Exception as e:
            logger.error(f"Failed to apply global bandwidth limit: {e}")
            return False

    async def get_interface_stats(self, interface: str) -> dict:
        """Get traffic statistics for an interface."""
        try:
            result = subprocess.run(
                ['tc', '-s', 'class', 'show', 'dev', interface],
                check=False, capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode != 0:
                return {}

            # Parse tc output (simplified)
            stats = {
                'interface': interface,
                'classes': []
            }

            # Basic parsing of tc output
            lines = result.stdout.split('\n')
            for line in lines:
                if 'class htb' in line:
                    # Extract class information
                    stats['classes'].append(line.strip())

            return stats

        except Exception as e:
            logger.error(f"Failed to get interface stats: {e}")
            return {}


# Global bandwidth manager instance
_bandwidth_manager: BandwidthManager | None = None


def get_bandwidth_manager() -> BandwidthManager:
    """Get the global bandwidth manager instance."""
    global _bandwidth_manager

    if _bandwidth_manager is None:
        _bandwidth_manager = BandwidthManager()

    return _bandwidth_manager


async def apply_bandwidth_limit(
    user_id: str,
    interface: str,
    upload_limit: int,
    download_limit: int,
    priority: int = 5
) -> bool:
    """Apply bandwidth limit for a user."""
    manager = get_bandwidth_manager()

    bandwidth_limit = BandwidthLimit(
        upload_limit=upload_limit,
        download_limit=download_limit,
        priority=priority
    )

    return await manager.apply_user_bandwidth_limit(user_id, interface, bandwidth_limit)


async def remove_bandwidth_limit(user_id: str) -> bool:
    """Remove bandwidth limit for a user."""
    manager = get_bandwidth_manager()
    return await manager.remove_user_bandwidth_limit(user_id)


async def list_bandwidth_limits() -> list[QoSRule]:
    """List all active bandwidth limits."""
    manager = get_bandwidth_manager()
    return await manager.list_active_limits()


async def clear_all_bandwidth_limits() -> bool:
    """Clear all bandwidth limits."""
    manager = get_bandwidth_manager()
    return await manager.clear_all_limits()
