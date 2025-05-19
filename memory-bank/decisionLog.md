# Decision Log

This file records architectural and implementation decisions using a list format.
2025-05-19 11:04:58 - Initial Memory Bank creation.
2025-05-19 11:22:39 - Added decisions for two-server tunnel configuration.

## Decision

* Use VLESS protocol with Reality encryption for VPN implementation
* Implement a two-server tunnel configuration with Outline VPN

## Rationale 

* The VLESS protocol is lightweight and efficient compared to alternatives
* Reality protocol provides advanced security without requiring SSL certificates
* The combination offers improved traffic obfuscation and resistance to deep packet inspection
* Better performance with direct TCP connections and efficient flow control
* Strong resistance to active probing by emulating legitimate browser fingerprints
* Two-server setup provides additional security and flexibility:
  * Server 1 (entry point) can be located in a region with less internet restrictions
  * Server 2 (Outline VPN host) can be located closer to users for better performance
  * Traffic is obfuscated twice - once by Outline and once by the VLESS-Reality tunnel
  * Server separation creates defense in depth

## Implementation Details

* Docker-based deployment for simplified installation and management
* Configuration stored in /opt/v2ray directory
* User database maintained in /opt/v2ray/users.db for managing credentials
* Default configuration mimics legitimate TLS traffic to approved destinations
* Option for port knocking to secure SSH access
* Firewall configured with secure defaults to protect server
* Two-server tunnel implementation:
  * Server 1:
    * Accepts incoming connections from Server 2
    * Uses Reality protocol for secure communication
    * Forwards traffic from Server 2 to the internet
  * Server 2:
    * Connects to Server 1 using VLESS+Reality protocol
    * Hosts Outline VPN for end-user connections
    * Routes all Outline VPN traffic through Server 1
  * Transparent to end-users who connect through Outline VPN
  * Systemd services ensure tunnel persistence across reboots
  * Multiple proxy types (SOCKS, HTTP, transparent) for flexibility

## Decision

* Fix x25519 key generation in setup-vless-reality-server.sh

## Rationale

* The v2fly/v2fly-core Docker image doesn't properly support the `xray x25519` command that was being used
* Direct key generation with OpenSSL provides a more reliable solution
* This approach eliminates dependency on container-specific commands

## Implementation Details

* Replaced Docker container key generation with direct OpenSSL-based generation
* Maintained the same key format and usage in the configuration
* Fixed the "unknown command" error that was preventing successful deployment

[2025-05-19 15:24:40] - Fixed setup-vless-reality-server.sh script key generation