# Decision Log

This file records architectural and implementation decisions using a list format.
2025-05-18 18:14:25 - Memory Bank initialization.
2025-05-18 23:31:20 - Added decisions for Outline VPN and v2ray VLESS integration project.

## Decision

* Remove monitoring and management components from the Outline VPN installation
* Replace the existing script with a completely new implementation that integrates v2ray with VLESS protocol
* Configure v2ray as the front-facing service that masks traffic to the Outline VPN
* Use WebSocket over TLS as the transport protocol for enhanced obfuscation

## Rationale 

* Monitoring/management components create additional attack surfaces and could potentially leak information
* Complete script replacement allows for more thorough integration rather than patching the existing script
* v2ray VLESS protocol provides excellent traffic obfuscation capabilities against DPI
* WebSocket over TLS resembles legitimate HTTPS traffic, making it difficult to detect or block
* Using v2ray as the front-facing service provides better protection for the actual VPN service (Outline)

## Implementation Details

* Maintain compatibility with the original script's command-line arguments
* Keep essential functionality from the original script (Docker installation, certificate generation)
* Add v2ray-specific configuration with VLESS protocol, WebSocket transport, and TLS encryption
* Create Docker containers for both Outline VPN and v2ray with proper integration
* Automatically generate and output all necessary connection information
* Remove Watchtower container since it's typically part of monitoring/management
* Use TLS certificates for both services to ensure secure communications
* Configure v2ray to route traffic directly to Outline VPN for actual VPN functionality
* Provide fallback mechanisms for non-VPN traffic to avoid obvious VPN fingerprinting
[2025-05-18 23:45:16] - Fixed Docker host network namespace conflict by switching from host networking to port mapping

## Decision

* Changed Docker container networking from `--net host` to explicit port mapping
* Created a custom Docker network for inter-container communication
* Updated container references to use Docker network container names

## Rationale 

* Docker error: "cannot share the host's network namespace when user namespaces are enabled"
* Some Linux distributions enable user namespaces by default which prevents host network sharing
* Using port mapping is more flexible and compatible with systems using Docker user namespaces
* Custom Docker network enables containers to reference each other by name

## Implementation Details

* Replaced `--net host` with explicit port mapping (`-p port:port`) for both TCP and UDP
* Created a dedicated "outline-network" Docker network
* Updated v2ray configuration to reference Outline container by name instead of localhost
* Added network creation step in installation process