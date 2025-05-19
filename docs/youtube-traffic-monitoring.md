# YouTube Traffic Monitoring Guide

This document explains how to use the YouTube traffic monitoring scripts to verify that YouTube traffic is properly flowing through the Outline VPN tunnel between Server 2 and Server 1.

## Overview

Two monitoring scripts have been created:

1. **Server 1 Script (`monitor-youtube-traffic-server1.sh`)**: Monitors incoming traffic from Server 2, identifying YouTube-related connections.
2. **Server 2 Script (`monitor-youtube-traffic-server2.sh`)**: Monitors Outline VPN client traffic being sent through the tunnel to Server 1, focusing on YouTube-related connections.

These scripts help you verify that:
- YouTube traffic from clients is properly tunneled
- The tunnel configuration is working correctly
- Traffic is flowing in both directions

## Prerequisites

- Both scripts must be run as root or with sudo privileges
- The following tools must be installed on both servers:
  - `tcpdump`
  - `host` (for DNS lookups)
  - Basic command-line tools (`grep`, `awk`, etc.)

## Server 1: Monitoring Incoming YouTube Traffic

### Usage

On Server 1, run:

```bash
sudo ./script/monitor-youtube-traffic-server1.sh --server2-ip <SERVER2_IP> [OPTIONS]
```

Required parameters:
- `--server2-ip IP`: The IP address of Server 2

Optional parameters:
- `--interface IFACE`: Network interface to monitor (default: eth0)
- `--duration SECONDS`: How long to monitor (0 = indefinitely, which is the default)
- `--log-file FILE`: Path to log file (default: /var/log/youtube-traffic-monitor.log)
- `--verbose`: Enable detailed output of each detected YouTube connection
- `--help`: Display usage information

### Example

```bash
sudo ./script/monitor-youtube-traffic-server1.sh --server2-ip 192.168.1.100 --verbose --duration 1800
```

This will monitor all YouTube traffic coming from Server 2 for 30 minutes (1800 seconds) with detailed logging.

## Server 2: Monitoring Outgoing YouTube Traffic

### Usage

On Server 2, run:

```bash
sudo ./script/monitor-youtube-traffic-server2.sh --server1-ip <SERVER1_IP> [OPTIONS]
```

Required parameters:
- `--server1-ip IP`: The IP address of Server 1

Optional parameters:
- `--outline-port PORT`: Outline VPN port (default: 7777, auto-detected if possible)
- `--outline-network NET`: Outline VPN client network (default: 10.0.0.0/24)
- `--interface IFACE`: Network interface to monitor (default: eth0)
- `--duration SECONDS`: How long to monitor (0 = indefinitely, which is the default)
- `--log-file FILE`: Path to log file (default: /var/log/youtube-traffic-outline-monitor.log)
- `--verbose`: Enable detailed output of each detected YouTube connection
- `--skip-checks`: Skip container and port checks and proceed directly to monitoring
- `--help`: Display usage information

### Example

```bash
sudo ./script/monitor-youtube-traffic-server2.sh --server1-ip 203.0.113.10 --verbose
```

This will monitor all YouTube traffic from Outline VPN clients being sent to Server 1 indefinitely with detailed logging.

## Testing Procedure

To test YouTube traffic routing through the tunnel:

1. Start the monitoring script on Server 1:
   ```bash
   sudo ./script/monitor-youtube-traffic-server1.sh --server2-ip <SERVER2_IP> --verbose
   ```

2. Start the monitoring script on Server 2:
   ```bash
   sudo ./script/monitor-youtube-traffic-server2.sh --server1-ip <SERVER1_IP> --verbose
   ```

   If you encounter any port detection issues, try using the `--skip-checks` option:
   ```bash
   sudo ./script/monitor-youtube-traffic-server2.sh --skip-checks --server1-ip <SERVER1_IP> --verbose
   ```

3. Connect a client to the Outline VPN on Server 2

4. Open YouTube on the connected client and play a video

5. Observe both monitoring scripts - they should detect and log YouTube traffic

## Interpreting the Results

### Server 1 Script Output

The Server 1 monitoring script detects YouTube traffic by:
- Analyzing packets coming from Server 2
- Performing reverse DNS lookups to identify YouTube domains
- Tracking the volume of YouTube traffic as a percentage of all traffic from Server 2

The script provides:
- Real-time logs of YouTube connections
- Traffic summaries every 50 YouTube packets
- Total data transferred statistics

### Server 2 Script Output

The Server 2 monitoring script detects YouTube traffic by:
- Monitoring DNS queries from Outline clients for YouTube domains
- Tracking subsequent connections to Server 1 from clients that made YouTube DNS queries
- Calculating the percentage of tunnel traffic related to YouTube

The script provides:
- Real-time logs of YouTube DNS queries and traffic
- List of active clients accessing YouTube
- Statistics on tunnel usage

## Troubleshooting

### Port Detection on Server 2

The Server 2 script includes intelligent port detection for Outline VPN. It will try to:

1. Check Docker container port mappings
2. Look inside the container for listening ports
3. Check host system for ports associated with the Outline service
4. Fall back to the default or user-specified port

If the script cannot detect the correct port but you're sure Outline is running, use the `--skip-checks` option to bypass port verification and continue with monitoring.

## Troubleshooting

If no YouTube traffic is detected:

1. **Verify Outline is using the correct port**:
   ```bash
   docker port shadowbox
   ```

2. **Check tunnel connectivity**:
   ```bash
   ./script/test-tunnel-connection.sh --server-type server2 --server1-address <SERVER1_IP>
   ```

2. **Verify Outline VPN status**:
   ```bash
   docker ps | grep shadowbox
   ```

3. **Check for active VPN clients**:
   ```bash
   ss -anp | grep <OUTLINE_PORT>
   ```

4. **Verify firewall settings**:
   ```bash
   iptables -t nat -L | grep REDIRECT
   ```

5. **Test tunnel with a direct URL**:
   ```bash
   curl -x http://127.0.0.1:8080 https://youtube.com -I
   ```

## Log Files

Both scripts maintain detailed logs:

- Server 1: `/var/log/youtube-traffic-monitor.log`
- Server 2: `/var/log/youtube-traffic-outline-monitor.log`

These logs contain timestamps, connection details, and traffic statistics that can be used for later analysis.