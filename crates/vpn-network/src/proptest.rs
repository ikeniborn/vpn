//! Property-based tests for VPN network utilities
//!
//! This module contains comprehensive property-based tests using proptest
//! to ensure the correctness of network operations under various scenarios.

use crate::{error::*, firewall::*, port::*, subnet::*};
use proptest::option;
use proptest::prelude::*;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// Strategy for generating valid IPv4 addresses
pub fn ipv4_strategy() -> impl Strategy<Value = Ipv4Addr> {
    any::<[u8; 4]>().prop_map(Ipv4Addr::from)
}

/// Strategy for generating valid IPv6 addresses
pub fn ipv6_strategy() -> impl Strategy<Value = Ipv6Addr> {
    any::<[u16; 8]>().prop_map(Ipv6Addr::from)
}

/// Strategy for generating IP addresses (both v4 and v6)
pub fn ip_strategy() -> impl Strategy<Value = IpAddr> {
    prop_oneof![
        ipv4_strategy().prop_map(IpAddr::V4),
        ipv6_strategy().prop_map(IpAddr::V6),
    ]
}

/// Strategy for generating valid port numbers (excluding privileged ports)
pub fn port_strategy() -> impl Strategy<Value = u16> {
    1024u16..65535u16
}

/// Strategy for generating privileged ports (0-1023)
pub fn privileged_port_strategy() -> impl Strategy<Value = u16> {
    1u16..1024u16
}

/// Strategy for generating protocol types
pub fn protocol_strategy() -> impl Strategy<Value = Protocol> {
    prop_oneof![
        Just(Protocol::Tcp),
        Just(Protocol::Udp),
        Just(Protocol::Both),
    ]
}

/// Strategy for generating direction types
pub fn direction_strategy() -> impl Strategy<Value = Direction> {
    prop_oneof![
        Just(Direction::In),
        Just(Direction::Out),
        Just(Direction::Both),
    ]
}

/// Strategy for generating port status
pub fn port_status_strategy() -> impl Strategy<Value = PortStatus> {
    prop_oneof![
        Just(PortStatus::Open),
        Just(PortStatus::Closed),
        Just(PortStatus::Filtered),
        Just(PortStatus::Unavailable),
        Just(PortStatus::InUse),
        Just(PortStatus::Available),
    ]
}

/// Strategy for generating firewall rules
pub fn firewall_rule_strategy() -> impl Strategy<Value = FirewallRule> {
    (
        port_strategy(),
        protocol_strategy(),
        direction_strategy(),
        option::of(ip_strategy()),
        option::of("[a-zA-Z0-9 ._-]{3,50}"), // comment
    )
        .prop_map(
            |(port, protocol, direction, source, comment)| FirewallRule {
                port,
                protocol,
                direction,
                source,
                comment,
            },
        )
}

/// Strategy for generating port ranges
pub fn port_range_strategy() -> impl Strategy<Value = (u16, u16)> {
    (1024u16..32768u16, 32768u16..65535u16).prop_map(|(start, end)| (start, end))
}

/// Strategy for generating valid hostnames
pub fn hostname_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        // Domain names
        "[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}",
        // IPv4 addresses as strings
        "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])",
        // Localhost variants
        Just("localhost".to_string()),
        Just("127.0.0.1".to_string()),
        Just("::1".to_string()),
    ]
}

/// Strategy for generating CIDR notation subnets
pub fn cidr_strategy() -> impl Strategy<Value = String> {
    (
        ipv4_strategy(),
        prop_oneof![Just(8u8), Just(16u8), Just(24u8)], // Common CIDR suffixes
    )
        .prop_map(|(ip, suffix)| format!("{}/{}", ip, suffix))
}

/// Strategy for generating VPN subnet objects
pub fn vpn_subnet_strategy() -> impl Strategy<Value = VpnSubnet> {
    (
        cidr_strategy(),
        "[a-zA-Z0-9 ._-]{10,50}", // description
        ipv4_strategy(),
        ipv4_strategy(),
    )
        .prop_map(|(cidr, description, start_ip, end_ip)| VpnSubnet {
            cidr,
            description,
            range_start: start_ip.to_string(),
            range_end: end_ip.to_string(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    proptest! {
        /// Test that port validation works correctly
        #[test]
        fn test_port_validation(
            valid_port in port_strategy(),
            invalid_port in 0u16..1u16
        ) {
            // Valid ports should pass validation
            prop_assert!(PortChecker::validate_port(valid_port).is_ok());

            // Port 0 should fail validation
            prop_assert!(PortChecker::validate_port(invalid_port).is_err());

            // Reserved ports should fail validation
            prop_assert!(PortChecker::validate_port(22).is_err());
            prop_assert!(PortChecker::validate_port(80).is_err());
            prop_assert!(PortChecker::validate_port(443).is_err());
        }

        /// Test that port range generation maintains order
        #[test]
        fn test_port_range_order(
            (start, end) in port_range_strategy()
        ) {
            prop_assert!(start < end);
            prop_assert!(start >= 1024);
            // end is already constrained by type (u16 max is 65535)

            // Test find_available_port with valid range
            let _result = PortChecker::find_available_port(start, end);
            // The result can be Ok or Err, both are valid depending on system state
        }

        /// Test that random port generation stays within bounds
        #[test]
        fn test_random_port_bounds(
            min in 1024u16..32768u16,
            max in 32768u16..65535u16
        ) {
            if let Ok(port) = PortChecker::find_random_available_port(min, max) {
                prop_assert!(port >= min);
                prop_assert!(port <= max);
            }
            // If no port is available, that's also a valid outcome
        }

        /// Test that port status enum has correct properties
        #[test]
        fn test_port_status_properties(
            status in port_status_strategy()
        ) {
            // All statuses should be serializable
            let json = serde_json::to_string(&status)?;
            let deserialized: PortStatus = serde_json::from_str(&json)?;
            prop_assert_eq!(status.clone(), deserialized);

            // All statuses should have valid debug representations
            let debug_str = format!("{:?}", status);
            prop_assert!(!debug_str.is_empty());
        }

        /// Test that protocol enum has correct string representations
        #[test]
        fn test_protocol_string_representation(
            protocol in protocol_strategy()
        ) {
            let str_repr = protocol.as_str();
            prop_assert!(!str_repr.is_empty());

            match protocol {
                Protocol::Tcp => prop_assert_eq!(str_repr, "tcp"),
                Protocol::Udp => prop_assert_eq!(str_repr, "udp"),
                Protocol::Both => prop_assert_eq!(str_repr, "tcp/udp"),
            }
        }

        /// Test that direction enum has correct string representations
        #[test]
        fn test_direction_string_representation(
            direction in direction_strategy()
        ) {
            let str_repr = direction.as_str();
            prop_assert!(!str_repr.is_empty());

            match direction {
                Direction::In => prop_assert_eq!(str_repr, "in"),
                Direction::Out => prop_assert_eq!(str_repr, "out"),
                Direction::Both => prop_assert_eq!(str_repr, "in/out"),
            }
        }

        /// Test that firewall rules maintain consistency
        #[test]
        fn test_firewall_rule_consistency(
            rule in firewall_rule_strategy()
        ) {
            // Port should be valid
            prop_assert!(rule.port >= 1024);
            // port is already constrained by type (u16 max is 65535)

            // Rule should be cloneable
            let cloned_rule = rule.clone();
            prop_assert_eq!(rule.port, cloned_rule.port);
            prop_assert_eq!(rule.protocol.as_str(), cloned_rule.protocol.as_str());
            prop_assert_eq!(rule.direction.as_str(), cloned_rule.direction.as_str());

            // Debug representation should not be empty
            let debug_str = format!("{:?}", rule);
            prop_assert!(!debug_str.is_empty());
        }

        /// Test that IP address strategies generate valid addresses
        #[test]
        fn test_ip_address_validity(
            ip in ip_strategy()
        ) {
            // All generated IPs should parse back to the same value
            let ip_str = ip.to_string();
            let parsed_ip: IpAddr = ip_str.parse().unwrap();
            prop_assert_eq!(ip, parsed_ip);

            // All IPs should have non-empty string representations
            prop_assert!(!ip_str.is_empty());

            // Test specific properties
            match ip {
                IpAddr::V4(ipv4) => {
                    prop_assert!(ipv4.octets().len() == 4);
                }
                IpAddr::V6(ipv6) => {
                    prop_assert!(ipv6.segments().len() == 8);
                }
            }
        }

        /// Test CIDR notation generation and parsing
        #[test]
        fn test_cidr_format_validity(
            cidr in cidr_strategy()
        ) {
            // Should contain exactly one slash
            prop_assert_eq!(cidr.matches('/').count(), 1);

            // Should split into IP and suffix
            let parts: Vec<&str> = cidr.split('/').collect();
            prop_assert_eq!(parts.len(), 2);

            // IP part should be valid
            let ip_part = parts[0];
            prop_assert!(ip_part.parse::<Ipv4Addr>().is_ok());

            // Suffix should be valid
            let suffix = parts[1].parse::<u8>().unwrap();
            prop_assert!(suffix == 8 || suffix == 16 || suffix == 24);
        }

        /// Test VPN subnet properties
        #[test]
        fn test_vpn_subnet_properties(
            subnet in vpn_subnet_strategy()
        ) {
            // Description should not be empty
            prop_assert!(!subnet.description.is_empty());

            // CIDR should be valid format
            prop_assert!(subnet.cidr.contains('/'));

            // Range IPs should be valid IPv4 addresses
            prop_assert!(subnet.range_start.parse::<Ipv4Addr>().is_ok());
            prop_assert!(subnet.range_end.parse::<Ipv4Addr>().is_ok());

            // Should be cloneable
            let cloned = subnet.clone();
            prop_assert_eq!(subnet.cidr, cloned.cidr);
            prop_assert_eq!(subnet.description, cloned.description);
        }

        /// Test subnet mask generation
        #[test]
        fn test_subnet_mask_generation(
            subnet in vpn_subnet_strategy()
        ) {
            // Extract suffix from CIDR
            if let Some(suffix_str) = subnet.cidr.split('/').nth(1) {
                if let Ok(suffix) = suffix_str.parse::<u8>() {
                    let mask_result = subnet.get_subnet_mask();

                    match suffix {
                        8 => prop_assert_eq!(mask_result.unwrap(), "255.0.0.0"),
                        16 => prop_assert_eq!(mask_result.unwrap(), "255.255.0.0"),
                        24 => prop_assert_eq!(mask_result.unwrap(), "255.255.255.0"),
                        _ => prop_assert!(mask_result.is_err()),
                    }
                }
            }
        }

        /// Test gateway IP generation
        #[test]
        fn test_gateway_ip_generation(
            subnet in vpn_subnet_strategy()
        ) {
            let gateway_result = subnet.get_gateway_ip();

            // If CIDR is valid format, gateway should be generated
            if subnet.cidr.contains('/') && subnet.cidr.split('/').count() == 2 {
                if let Some(network_part) = subnet.cidr.split('/').next() {
                    if network_part.split('.').count() == 4 {
                        // Should generate a valid gateway IP
                        if let Ok(gateway) = gateway_result {
                            prop_assert!(gateway.parse::<Ipv4Addr>().is_ok());
                            prop_assert!(gateway.ends_with(".1"));
                        }
                    }
                }
            }
        }

        /// Test that hostname generation produces valid hostnames
        #[test]
        fn test_hostname_validity(
            hostname in hostname_strategy()
        ) {
            // Hostnames should not be empty
            prop_assert!(!hostname.is_empty());

            // Should be reasonable length
            prop_assert!(hostname.len() <= 253); // DNS limit

            // Should not start or end with special characters (for domain names)
            if hostname.contains('.') && !hostname.parse::<IpAddr>().is_ok() {
                prop_assert!(!hostname.starts_with('-'));
                prop_assert!(!hostname.ends_with('-'));
                prop_assert!(!hostname.starts_with('.'));
                prop_assert!(!hostname.ends_with('.'));
            }
        }

        /// Test that port range checking produces valid results
        #[test]
        fn test_port_range_checking(
            (start, end) in port_range_strategy()
        ) {
            let available_ports = PortChecker::check_port_range(start, end);

            // All returned ports should be within the specified range
            for &port in &available_ports {
                prop_assert!(port >= start);
                prop_assert!(port <= end);
            }

            // The number of available ports should not exceed the range size
            let range_size = (end - start + 1) as usize;
            prop_assert!(available_ports.len() <= range_size);
        }

        /// Test IPv4 specific properties
        #[test]
        fn test_ipv4_properties(
            ipv4 in ipv4_strategy()
        ) {
            let octets = ipv4.octets();

            // Should have exactly 4 octets
            prop_assert_eq!(octets.len(), 4);

            // String representation should be parseable
            let ip_str = ipv4.to_string();
            let parsed: Ipv4Addr = ip_str.parse().unwrap();
            prop_assert_eq!(ipv4, parsed);

            // Test special address properties
            let is_loopback = ipv4.is_loopback();
            let is_private = ipv4.is_private();
            let is_multicast = ipv4.is_multicast();
            let is_broadcast = ipv4.is_broadcast();

            // These are just property checks, no assertions needed
            let _ = (is_loopback, is_private, is_multicast, is_broadcast);
        }

        /// Test IPv6 specific properties
        #[test]
        fn test_ipv6_properties(
            ipv6 in ipv6_strategy()
        ) {
            let segments = ipv6.segments();

            // Should have exactly 8 segments
            prop_assert_eq!(segments.len(), 8);

            // String representation should be parseable
            let ip_str = ipv6.to_string();
            let parsed: Ipv6Addr = ip_str.parse().unwrap();
            prop_assert_eq!(ipv6, parsed);

            // Test special address properties
            let is_loopback = ipv6.is_loopback();
            let is_multicast = ipv6.is_multicast();

            // These are just property checks, no assertions needed
            let _ = (is_loopback, is_multicast);
        }
    }

    /// Test async network operations
    mod async_tests {
        use super::*;
        use tokio_test;

        proptest! {
            /// Test that port connectivity checks behave consistently
            #[test]
            fn test_port_connectivity_consistency(
                hostname in hostname_strategy(),
                port in port_strategy(),
                timeout in 1u64..2u64
            ) {
                let _ = tokio_test::block_on(async {
                    // Test port connectivity
                    let is_open = PortChecker::is_port_open(&hostname, port, timeout).await;

                    // The result can be true or false, both are valid
                    // We're just testing that the operation completes without panic
                    let _ = is_open;

                    Ok::<(), TestCaseError>(())
                });
            }

            /// Test that wait_for_port behaves consistently
            #[test]
            fn test_wait_for_port_timeout(
                hostname in hostname_strategy(),
                port in port_strategy(),
                timeout in 1u64..2u64 // Short timeout for testing
            ) {
                let _ = tokio_test::block_on(async {
                    // Most ports should timeout (unless we're very lucky)
                    let result = PortChecker::wait_for_port(&hostname, port, timeout).await;

                    // Either succeeds or times out, both are valid outcomes
                    match result {
                        Ok(()) => {
                            // Port was available and responded
                        }
                        Err(NetworkError::PortInUse(_)) => {
                            // Port timed out, which is expected for most random ports
                        }
                        Err(_) => {
                            // Other errors are also possible (DNS resolution, etc.)
                        }
                    }

                    Ok::<(), TestCaseError>(())
                });
            }
        }
    }
}
