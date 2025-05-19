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

## Decision

* Fix Docker network creation and improve tunnel configuration in setup-vless-server2.sh

## Rationale

* The original Docker network creation logic was causing errors when the network already existed
* The Reality protocol configuration had formatting issues in the JSON structure
* The tunnel diagnostics were insufficient for proper troubleshooting

## Implementation Details

* Improved Docker network creation with better error handling and checking
* Fixed the Reality protocol JSON configuration to ensure valid format
* Enhanced tunnel diagnostics with detailed error reporting and suggestions
* Added proper logging directory setup with correct permissions
* Implemented container verification to confirm successful creation
* Added JSON configuration validation with auto-repair functionality
* Implemented debug mode fallback for container startup failures
* Added comprehensive container diagnostics with safe output of configuration

[2025-05-19 16:37:40] - Fixed setup-vless-server2.sh script Docker network and tunnel configuration
[2025-05-19 16:49:10] - Improved container startup reliability in setup-vless-server2.sh

## Decision

* Refactor the v2ray configuration generation in setup-vless-server2.sh

## Rationale

* The original JSON template approach caused syntax errors with trailing commas and inconsistent formatting
* Command line parameter passing to the Docker container was causing "unknown command" errors
* The container failed to start reliably due to these configuration issues

## Implementation Details

* Completely restructured configuration template generation using variables
* Used a cleaner approach with heredoc to create properly formatted JSON
* Removed incorrect command-line parameters from Docker run commands
* Set debug log level by default for better diagnostics
* Added detailed documentation of configuration settings during generation
* Created distinct templates for different Reality setting combinations

[2025-05-19 16:51:50] - Fixed JSON configuration and container command issues

## Decision

* Completely rewrite the setup-vless-server2.sh script using a progressive configuration building approach

## Rationale

* Multiple isolated fixes were not working correctly together
* The script had various subtle JSON formatting issues that were hard to patch individually
* A comprehensive solution was needed to ensure proper container startup
* The approach of patching parts of the script was proving insufficient for robust operation

## Implementation Details

* Developed a progressive JSON building approach using multiple appends to ensure valid structure
* Rebuilt the container startup process with proper validation at each step
* Removed all command parameters that were causing errors
* Created a more robust error handling system with informative diagnostics
* Added comprehensive validation of the configuration before attempting container startup
* Used properly secure file permissions throughout the script
* Added detailed progress reporting for easier troubleshooting

[2025-05-19 16:57:40] - Completely rebuilt the setup-vless-server2.sh script

## Decision

* Create a dedicated v2ray configuration validation script

## Rationale

* Inline validation and fixing of JSON configuration was not sufficient
* The container continued to fail due to JSON syntax errors that were hard to detect
* A dedicated script allows for more robust error checking and repair
* Isolating validation logic makes it reusable for other components

## Implementation Details

* Created validate-v2ray-config.sh with specialized JSON validation logic
* Added backup and restore capabilities for configuration safety
* Implemented specific fixes for common JSON errors like trailing commas
* Used sed for quick syntax error correction
* Added integration with the main setup script
* Provided detailed error reporting for better troubleshooting

[2025-05-19 17:00:30] - Created dedicated v2ray configuration validation script

## Decision

* Simplify container command and create direct fix script for v2ray configuration

## Rationale

* Previous approach with validation was insufficient to fix specific JSON issues
* Passing command parameters to the Docker container was causing "unknown command" errors
* Need to directly target known syntax issues in the configuration file
* A simpler container command coupled with targeted fixes is more reliable

## Implementation Details

* Removed additional command parameters from docker run command
* Created fix-v2ray-config.sh script to make direct edits to the configuration file
* Used targeted sed commands to fix known problematic sections like trailing commas
* Implemented backup mechanism for safe editing
* Made configuration validation non-fatal to allow container startup attempts
* Simplified overall logic for better maintainability

[2025-05-19 17:06:30] - Created direct configuration fix script and simplified container command

## Decision

* Create a dedicated configuration generator script with strict JSON structure control

## Rationale

* Previous approaches with validation and fixes were still insufficient
* Identified specific JSON issues in the configuration:
  * Missing UUID in users section
  * Trailing commas in realitySettings
* Direct text manipulation with sed not reliable enough for complex JSON
* Need complete control over JSON generation process

## Implementation Details

* Created generate-v2ray-config.sh to produce valid JSON from input parameters
* Used a combination of static templates and dynamic content insertion
* Added line-by-line JSON construction for critical sections
* Implemented proper comma handling in optional parameters
* Added standalone validation process
* Completely replaced the complex heredoc-based configuration with generator script
* Made validation fatal to prevent container startup with invalid configuration

[2025-05-19 17:11:20] - Created dedicated configuration generator script with strict JSON control

## Decision

* Create a completely new configuration generator with placeholder substitution

## Rationale

* Previous approach still resulted in JSON syntax errors
* Direct JSON writing is error-prone with variable substitution
* Template substitution is more reliable than direct writing
* Need to explicitly verify critical values like UUID

## Implementation Details

* Created a completely new configuration template with placeholders
* Used sed for direct substitution instead of variable expansion in heredoc
* Added explicit UUID format validation
* Implemented template-based approach instead of line-by-line building
* Added critical value verification at the end
* Made Docker container use explicit command arguments
* Added automatic fixing with jq if validation fails

[2025-05-19 17:14:55] - Rewrote configuration generator with safe substitution and validation

## Decision

* Simplify the approach by going back to default Docker entrypoint and use direct string interpolation

## Rationale

* Adding command arguments to container was causing issues with v2ray execution
* Template substitution was still producing malformed JSON with commas
* Direct string interpolation in a controlled context is more reliable
* The validation step is critical to ensure correct configuration

## Implementation Details

* Reverted to using default Docker entrypoint with no arguments
* Used direct variable substitution within heredoc rather than placeholders
* Implemented cleaner conditional inclusion of optional parameters
* Added explicit validation that checks critical value presence
* Included comprehensive error checking for common JSON issues
* Used a simpler approach that's less prone to errors

[2025-05-19 17:17:45] - Final simplification of container execution and configuration generation

## Decision

* Create a specialized script to fix the "context canceled" error in the VLESS tunnel

## Rationale

* The error occurs when Server 2's connection parameters don't match Server 1's expectations
* The UUID being used by Server 2 must be added to Server 1's client list
* Reality parameters (public key, short ID) may also be mismatched
* A specialized script ensures consistent application of the fix
* Properly documents the correct parameters that should be used

## Implementation Details

* Created fix-server-uuid.sh script to add a specific UUID to Server 1's client list
* Used jq for safe modification of Server 1's config.json
* Added backup mechanism to preserve original configuration
* Implemented verification of UUID format and existence
* Extracts and displays the Reality parameters that Server 2 should be using
* Identifies mismatches between Server 1's parameters and what Server 2 is using
* Provides clear guidance on updating Server 2's configuration

[2025-05-20 00:51:52] - Created fix-server-uuid.sh script to resolve the "context canceled" error
[2025-05-20 00:52:25] - Added comprehensive troubleshooting guide in vless-reality-tunnel-troubleshooting.md

## Decision

* Create comprehensive traffic monitoring scripts for both Server 1 and Server 2

## Rationale

* Need to verify routing is working correctly in the two-server tunnel setup
* Manual verification methods were time-consuming and error-prone
* Tunnel issues can be difficult to diagnose without proper traffic visibility
* Need to monitor both sides of the tunnel connection to identify specific issues
* Regular monitoring helps ensure the tunnel remains functional over time
* Traffic analysis helps verify that Outline VPN clients are properly routed through Server 1

## Implementation Details

* Created two specialized monitoring scripts:
  * monitor-server1-traffic.sh - Monitors incoming connections from Server 2
  * monitor-server2-traffic.sh - Monitors Outline VPN client traffic and tunnel routing
* Scripts provide multiple monitoring modes (basic, detailed, continuous)
* Functionality includes:
  * Validation of configuration (IP forwarding, iptables rules, listening ports)
  * Real-time connection monitoring with statistics
  * Tunnel performance testing
  * Packet capture for detailed traffic analysis
  * Comprehensive diagnostics for troubleshooting
* Created traffic-monitoring-guide.md with extensive documentation
* Scripts use standard tools (tcpdump, iptables, netstat, ss) for compatibility
* Both scripts work independently but provide complementary information
* Supports saving results to log files for later analysis

[2025-05-20 01:22:34] - Created traffic monitoring scripts for both Server 1 and Server 2