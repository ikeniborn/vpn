# Traffic Monitoring Guide for VLESS+Reality Tunnel Setup

This guide explains how to use the traffic monitoring scripts to check routing and traffic between Server 1 and Server 2 in the VLESS+Reality tunnel configuration.

## Overview

The monitoring scripts help diagnose and verify that traffic is flowing correctly through your tunnel setup:

- `monitor-server1-traffic.sh` - Run on Server 1 to monitor incoming connections from Server 2
- `monitor-server2-traffic.sh` - Run on Server 2 to monitor traffic from Outline VPN clients and verify tunnel routing

These scripts provide real-time monitoring with different detail levels and can help troubleshoot connection issues between the servers.

## Prerequisites

- Both servers must be set up according to the installation guides
- Server 1 must have the VLESS+Reality server running
- Server 2 must have the tunnel to Server 1 configured
- Both scripts should be run with root privileges (using sudo)

## Server 1 Monitoring

### Usage

```bash
./script/monitor-server1-traffic.sh --server2-ip SERVER2_IP [OPTIONS]
```

### Required Parameters

- `--server2-ip IP` - The IP address of Server 2 that connects to Server 1

### Optional Parameters

- `--interval SEC` - Sampling interval in seconds (default: 5)
- `--duration SEC` - Total monitoring duration in seconds (default: 60)
- `--mode MODE` - Monitoring mode: basic, detailed, or continuous (default: basic)
- `--v2ray-port PORT` - V2Ray port (default: 443)
- `--output FILE` - Save output to a file

### Examples

Basic monitoring for 60 seconds:
```bash
sudo ./script/monitor-server1-traffic.sh --server2-ip 203.0.113.2
```

Detailed monitoring with a shorter interval:
```bash
sudo ./script/monitor-server1-traffic.sh --server2-ip 203.0.113.2 --mode detailed --interval 2
```

Continuous monitoring (until manually stopped):
```bash
sudo ./script/monitor-server1-traffic.sh --server2-ip 203.0.113.2 --mode continuous
```

## Server 2 Monitoring

### Usage

```bash
./script/monitor-server2-traffic.sh --server1-address SERVER1_ADDRESS [OPTIONS]
```

### Required Parameters

- `--server1-address ADDR` - The address of Server 1 (IP or hostname)

### Optional Parameters

- `--interval SEC` - Sampling interval in seconds (default: 5)
- `--duration SEC` - Total monitoring duration in seconds (default: 60)
- `--mode MODE` - Monitoring mode: basic, detailed, or continuous (default: basic)
- `--outline-network CIDR` - Outline VPN network CIDR (default: 10.0.0.0/24)
- `--container NAME` - Docker container name for v2ray client (default: v2ray-client)
- `--output FILE` - Save output to a file

### Examples

Basic monitoring:
```bash
sudo ./script/monitor-server2-traffic.sh --server1-address 203.0.113.1
```

Detailed monitoring with results saved to a file:
```bash
sudo ./script/monitor-server2-traffic.sh --server1-address 203.0.113.1 --mode detailed --output tunnel-diagnostics.log
```

## Understanding the Output

Both scripts provide a structured output with several sections:

### Configuration Check

The scripts first verify that the necessary configurations are in place:
- IP forwarding enabled
- Proper iptables rules
- V2Ray/Docker container status
- Listening ports

### Connection Monitoring

During the monitoring phase, the scripts will show:
- Active connections between the servers
- Traffic statistics (packets/bytes)
- For detailed mode: actual packet captures and more comprehensive stats

### Summary Report

At the end of monitoring, a summary is provided:
- Overall connection status (working/not working)
- Total traffic observed
- Any errors found in logs
- Troubleshooting suggestions if issues were detected

## Monitoring Modes

The scripts support three monitoring modes:

1. **Basic** (default): Provides essential connection information with minimal overhead
2. **Detailed**: Shows comprehensive diagnostics including packet captures and performance metrics
3. **Continuous**: Runs indefinitely until manually stopped (Ctrl+C), showing real-time updates

## Troubleshooting Common Issues

### No Connections Detected

If Server 1 doesn't detect connections from Server 2:
- Verify Server 2's UUID is correctly configured on Server 1 (use `fix-server-uuid.sh`)
- Check firewall settings on both servers
- Verify V2Ray is running on both servers

### Traffic Not Routing Through Tunnel

If Server 2 detects Outline clients but traffic isn't going through Server 1:
- Check transparent proxy port (11081) is listening
- Verify iptables REDIRECT rules are properly configured
- Check for any errors in V2Ray logs

### Performance Issues

If the tunnel is working but performance is poor:
- Run with `--mode detailed` to get performance metrics
- Check for packet loss between the servers
- Verify the servers aren't CPU or bandwidth constrained

## Advanced Usage

### Combining with Other Diagnostic Tools

These monitoring scripts can be used alongside other diagnostic tools:

```bash
# Run monitoring while generating test traffic
sudo ./script/monitor-server2-traffic.sh --server1-address 203.0.113.1 --mode continuous &
curl -x http://127.0.0.1:18080 https://example.com
```

### Automated Health Checks

You can use these scripts in cron jobs for automated health checks:

```bash
# Create a cron job to monitor tunnel health every hour
0 * * * * /path/to/script/monitor-server2-traffic.sh --server1-address 203.0.113.1 --output /var/log/tunnel-health.log
```

## Conclusion

These monitoring scripts provide a comprehensive way to verify and troubleshoot your VLESS+Reality tunnel configuration. By regularly monitoring traffic between Server 1 and Server 2, you can ensure your setup continues to function properly and quickly identify any issues that arise.