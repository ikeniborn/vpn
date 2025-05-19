# Decision Log

This file records architectural and implementation decisions using a list format.
2025-05-19 11:04:58 - Initial Memory Bank creation.

## Decision

* Use VLESS protocol with Reality encryption for VPN implementation

## Rationale 

* The VLESS protocol is lightweight and efficient compared to alternatives
* Reality protocol provides advanced security without requiring SSL certificates
* The combination offers improved traffic obfuscation and resistance to deep packet inspection
* Better performance with direct TCP connections and efficient flow control
* Strong resistance to active probing by emulating legitimate browser fingerprints

## Implementation Details

* Docker-based deployment for simplified installation and management
* Configuration stored in /opt/v2ray directory
* User database maintained in /opt/v2ray/users.db for managing credentials
* Default configuration mimics legitimate TLS traffic to approved destinations
* Option for port knocking to secure SSH access
* Firewall configured with secure defaults to protect server