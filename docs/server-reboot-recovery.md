# Server Reboot Recovery Guide

This document provides instructions for recovering services after a server reboot when SSH, HTTPS, VLESS+Reality tunnel, and Outline VPN connectivity are lost.

## Common Issues After Reboot

After a server reboot, you may encounter the following issues:

- SSH connectivity lost
- HTTPS connections failing
- VLESS+Reality tunnel broken between Server 1 and Server 2
- Outline VPN clients unable to connect
- "context canceled" errors in v2ray logs

These issues typically occur because:

1. Docker containers may not restart properly
2. iptables rules might be lost or only partially restored
3. Port bindings may not be correctly established
4. Network interfaces might initialize in a different order

## Automatic Recovery

We've created a comprehensive recovery script that addresses all these issues. The script:

- Detects whether it's running on Server 1 or Server 2
- Restarts appropriate Docker containers with correct networking
- Reapplies iptables rules for proper routing
- Ensures Server 2 can authenticate to Server 1
- Restarts Outline VPN services on Server 2 if present
- Tests connectivity to verify the fix

### Using the Recovery Script

1. Connect to the server via emergency console access (since SSH may be down)
2. Run the recovery script:

   ```bash
   sudo ./script/recover-services-after-reboot.sh
   ```

3. The script will automatically detect which server it's running on and apply the appropriate fixes
4. Check the output to verify services were restored successfully

### Running on Both Servers

If you have access to both servers, run the script on Server 1 first, then on Server 2:

1. On Server 1 (VLESS+Reality entry point):
   ```bash
   sudo ./script/recover-services-after-reboot.sh
   ```

2. On Server 2 (Tunnel client + Outline VPN):
   ```bash
   sudo ./script/recover-services-after-reboot.sh
   ```

This ensures that Server 1 is properly accepting connections before Server 2 attempts to connect through it.

## Manual Recovery Steps

If the automatic script doesn't resolve all issues, you can follow these manual steps:

### Server 1 (VLESS+Reality Entry Point)

1. Restart Docker if it's not running:
   ```bash
   sudo systemctl restart docker
   ```

2. Restart the v2ray container:
   ```bash
   sudo docker restart v2ray || sudo docker run -d --name v2ray --restart always --network host -v /opt/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core:latest
   ```

3. Add Server 2's UUID to the client list:
   ```bash
   sudo ./script/fix-server-uuid.sh
   ```

4. Restore iptables rules:
   ```bash
   sudo ./script/setup-tunnel-routing.sh
   ```

5. Check if services are running:
   ```bash
   ss -tulpn | grep -E "443"
   docker logs v2ray
   ```

### Server 2 (Tunnel Client + Outline VPN)

1. Restart Docker if it's not running:
   ```bash
   sudo systemctl restart docker
   ```

2. Fix port bindings:
   ```bash
   sudo ./script/fix-port-binding.sh
   ```

3. Ensure routing rules are properly set:
   ```bash
   sudo ./script/setup-tunnel-routing.sh
   ```

4. Restart Outline VPN if installed:
   ```bash
   cd /opt/outline && sudo docker-compose down && sudo docker-compose up -d
   ```

5. Test tunnel connectivity:
   ```bash
   sudo ./script/test-tunnel-connection.sh
   ```

6. Check if services are running:
   ```bash
   ss -tulpn | grep -E "11080|18080|11081"
   docker logs v2ray-client
   ```

## Preventing Future Issues

To prevent these issues after future reboots:

1. Ensure Docker is set to start on boot:
   ```bash
   sudo systemctl enable docker
   ```

