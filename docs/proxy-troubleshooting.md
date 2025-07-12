# Proxy Server Troubleshooting Guide

This guide helps resolve common issues with proxy server connections.

## Common Issues and Solutions

### 1. Cannot Connect to Proxy

#### Symptoms
- Browser shows "Proxy server is refusing connections"
- Connection timeout errors
- Unable to reach any websites

#### Solutions

**Check if proxy is running:**
```bash
# Check container status
sudo docker ps | grep proxy

# Expected output should show:
# vpn-squid-proxy   (port 8080)
# vpn-socks5-proxy  (port 1080)
```

**Restart proxy services:**
```bash
# Restart all proxy containers
sudo docker restart vpn-squid-proxy vpn-socks5-proxy

# Or restart individually
sudo docker restart vpn-squid-proxy    # HTTP proxy
sudo docker restart vpn-socks5-proxy   # SOCKS5 proxy
```

**Check firewall rules:**
```bash
# Check if ports are open
sudo iptables -L -n | grep -E "8080|1080"

# Open ports if needed
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
```

### 2. Authentication Failed

#### Symptoms
- "407 Proxy Authentication Required"
- Username/password prompt keeps appearing
- Access denied errors

#### Solutions

**Verify credentials:**
```bash
# List users
python -m vpn users list

# Check user status
python -m vpn users info <username>
```

**Reset user password:**
```bash
# Create new user if needed
python -m vpn users create <username> --protocol proxy

# Get connection string
python -m vpn users show-config <username>
```

**Check authentication logs:**
```bash
# HTTP proxy logs
sudo docker logs vpn-squid-proxy | grep -i auth

# SOCKS5 proxy logs
sudo docker logs vpn-socks5-proxy | grep -i auth
```

### 3. Slow Connection Speed

#### Symptoms
- Pages load slowly
- Downloads are slower than expected
- High latency

#### Solutions

**Check proxy load:**
```bash
# Monitor container resources
sudo docker stats vpn-squid-proxy vpn-socks5-proxy

# Check connection count
sudo netstat -an | grep -E ":8080|:1080" | wc -l
```

**Clear proxy cache (HTTP only):**
```bash
# Clear Squid cache
sudo docker exec vpn-squid-proxy squid -k shutdown
sudo docker exec vpn-squid-proxy rm -rf /var/spool/squid/*
sudo docker restart vpn-squid-proxy
```

**Optimize settings:**
```bash
# Increase SOCKS5 workers
sudo docker exec vpn-socks5-proxy sed -i 's/WORKERS=10/WORKERS=20/' /etc/danted.conf
sudo docker restart vpn-socks5-proxy
```

### 4. Specific Sites Not Working

#### Symptoms
- Some websites don't load
- HTTPS sites show certificate errors
- Streaming services blocked

#### Solutions

**For HTTPS issues:**
```bash
# Use SOCKS5 instead of HTTP proxy
# SOCKS5 handles HTTPS better without certificate issues
```

**Check proxy access logs:**
```bash
# View recent access attempts
sudo docker exec vpn-squid-proxy tail -f /var/log/squid/access.log

# Look for blocked domains
sudo docker exec vpn-squid-proxy grep -i "denied" /var/log/squid/access.log
```

**Bypass proxy for specific sites:**
- Add exceptions in browser proxy settings
- Use PAC file for selective routing

### 5. Connection Drops Frequently

#### Symptoms
- Proxy connection lost randomly
- Need to re-authenticate often
- Intermittent connectivity

#### Solutions

**Check container health:**
```bash
# View container logs for errors
sudo docker logs --tail 50 vpn-squid-proxy
sudo docker logs --tail 50 vpn-socks5-proxy

# Check container restart count
sudo docker inspect vpn-squid-proxy | grep -i restart
```

**Monitor system resources:**
```bash
# Check memory usage
free -h

# Check disk space
df -h

# Check open file limits
ulimit -n
```

**Increase container resources:**
```bash
# Edit docker-compose.yml to add resource limits
# Under each service, add:
# deploy:
#   resources:
#     limits:
#       memory: 512M
#     reservations:
#       memory: 256M
```

## Diagnostic Commands

### Quick Health Check
```bash
# Test HTTP proxy
curl -I -x http://localhost:8080 http://example.com

# Test SOCKS5 proxy
curl -I -x socks5://localhost:1080 http://example.com

# Check listening ports
sudo netstat -tlnp | grep -E "8080|1080"
```

### Performance Testing
```bash
# Measure proxy latency
time curl -x http://localhost:8080 -o /dev/null http://example.com

# Test download speed through proxy
curl -x http://localhost:8080 -o /dev/null -w "%{speed_download}\n" \
  http://speedtest.tele2.net/10MB.zip
```

### Debug Mode

**Enable Squid debug logging:**
```bash
# Edit squid.conf
sudo docker exec vpn-squid-proxy sed -i 's/log_level.*/log_level=ALL,1/' /etc/squid/squid.conf
sudo docker restart vpn-squid-proxy

# View debug logs
sudo docker logs -f vpn-squid-proxy
```

**Enable SOCKS5 verbose logging:**
```bash
# Already configured to log errors
# Check logs with:
sudo docker logs -f vpn-socks5-proxy
```

## Common Error Messages

### HTTP Proxy Errors

| Error | Meaning | Solution |
|-------|---------|----------|
| 403 Forbidden | Access denied by proxy rules | Check ACL configuration |
| 407 Authentication Required | Missing or invalid credentials | Provide correct username/password |
| 502 Bad Gateway | Target server unreachable | Check internet connectivity |
| 504 Gateway Timeout | Request took too long | Try again or check target server |

### SOCKS5 Errors

| Error Code | Meaning | Solution |
|------------|---------|----------|
| 0x01 | General failure | Check proxy logs |
| 0x02 | Connection not allowed | Check firewall rules |
| 0x03 | Network unreachable | Check routing |
| 0x04 | Host unreachable | Verify target host |
| 0x05 | Connection refused | Target port closed |

## Advanced Debugging

### Packet Capture
```bash
# Capture proxy traffic
sudo tcpdump -i any -w proxy.pcap port 8080 or port 1080

# Analyze with Wireshark
wireshark proxy.pcap
```

### Strace Container
```bash
# Trace system calls
sudo docker exec vpn-squid-proxy strace -p 1 -f
```

### Container Shell Access
```bash
# Access HTTP proxy container
sudo docker exec -it vpn-squid-proxy /bin/bash

# Access SOCKS5 proxy container
sudo docker exec -it vpn-socks5-proxy /bin/sh
```

## Getting Help

If issues persist:

1. **Collect diagnostics:**
   ```bash
   python -m vpn doctor > diagnostics.txt
   sudo docker logs vpn-squid-proxy > squid.log
   sudo docker logs vpn-socks5-proxy > socks5.log
   ```

2. **Check system logs:**
   ```bash
   journalctl -u docker -n 100
   dmesg | tail -50
   ```

3. **Report issue with:**
   - Diagnostic output
   - Error messages
   - Steps to reproduce
   - System configuration

## Related Documentation

- [Proxy Setup Guide](./proxy-setup.md)
- [Advanced Configuration](./advanced-proxy-config.md)
- [Security Best Practices](./security.md)