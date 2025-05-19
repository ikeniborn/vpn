# VLESS-Reality Tunnel Troubleshooting Guide

This document provides solutions for fixing the "context canceled" error that occurs when Server 2 tries to connect to Server 1 via VLESS+Reality tunnel.

## Understanding the "context canceled" Error

The "context canceled" error in VLESS outbound connections typically indicates an authentication or TLS handshake failure. This occurs when there's a mismatch between the client's connection parameters and what the server expects.

The most common causes are:

1. **UUID Mismatch**: The UUID used by Server 2 isn't recognized by Server 1
2. **Reality Parameters Mismatch**: The public key, short ID, or flow settings don't match
3. **Protocol Configuration Issues**: Flow settings or encryption methods don't align

## Diagnosing the Issue

The logs on Server 2 may show errors like:
```
app/proxyman/outbound: failed to process outbound traffic > proxy/vless/outbound: connection ends > context canceled
```

This indicates that Server 2 is attempting to connect to Server 1, but Server 1 is rejecting the connection, likely due to authentication failure.

## Solution: Fix the UUID Mismatch

The most direct solution is to add Server 2's UUID to Server 1's client list. We've created a script (`fix-server-uuid.sh`) that does this automatically.

### Step 1: On Server 1 (The Entry Point Server)

1. Run the fix script:

   ```bash
   sudo ./script/fix-server-uuid.sh
   ```

   This will:
   - Add the UUID `9daf9658-2b84-4d23-9d07-cfac80499241` to Server 1's client list
   - Restart the v2ray container to apply the changes
   - Output the correct Reality parameters (public key and short ID) that Server 2 should be using

2. Note the Reality parameters displayed by the script (public key and short ID)

### Step 2: On Server 2 (The Tunnel Client)

If the script indicated a mismatch in the Reality parameters (public key or short ID), you need to update Server 2's configuration:

1. Option 1: Run the setup script again with the correct parameters:

   ```bash
   sudo ./script/setup-vless-server2.sh \
     --server1-address IP_ADDRESS \
     --server1-uuid 9daf9658-2b84-4d23-9d07-cfac80499241 \
     --server1-pubkey "SERVER1_PUBLIC_KEY" \
     --server1-shortid "SERVER1_SHORT_ID"
   ```

2. Option 2: Edit the configuration file directly:

   ```bash
   sudo nano /opt/v2ray/config.json
   ```

   Update the `publicKey` and `shortId` values in the `realitySettings` section.

3. Restart the v2ray client container:

   ```bash
   sudo docker restart v2ray-client
   ```

### Step 3: Verify the Connection

After applying these changes, verify that the tunnel is working:

1. On Server 2, test the connection:

   ```bash
   sudo ./script/test-tunnel-connection.sh
   ```

2. Check that traffic can flow through the tunnel:

   ```bash
   curl -x http://127.0.0.1:18080 https://ifconfig.me
   ```

   The output should show Server 1's IP address, not Server 2's.

## Additional Troubleshooting Steps

If the issue persists after fixing the UUID and Reality parameters, try these steps:

1. Check port binding on Server 2:

   ```bash
   sudo ./script/fix-port-binding.sh
   ```

2. Verify that ports are properly listening on Server 2:

   ```bash
   ss -tulpn | grep -E "11080|18080|11081"
   ```

3. Review the v2ray logs on both servers:

   ```bash
   sudo docker logs v2ray        # On Server 1
   sudo docker logs v2ray-client # On Server 2
   ```

4. Ensure the system clocks on both servers are reasonably synchronized, as large time differences can affect TLS-based handshakes.

5. Check that the firewall on Server 1 is allowing incoming connections from Server 2's IP address on the VLESS port.

## Understanding the Configuration Parameters

For a VLESS+Reality tunnel between two servers:

- **UUID**: A unique identifier that authenticates Server 2 to Server 1
- **Public Key**: Part of the Reality protocol's encryption, used by clients to verify the server
- **Short ID**: An identifier used in the Reality handshake
- **Flow**: Determines the traffic flow control method, commonly "xtls-rprx-vision" for VLESS+Reality

All these parameters must match between Server 2's outbound connection and Server 1's inbound configuration for a successful connection.