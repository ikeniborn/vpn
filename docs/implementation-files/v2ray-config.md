# v2ray Configuration with VLESS+Reality

This file defines the v2ray configuration with VLESS protocol and Reality TLS simulation, including optimized routing rules for integration with Shadowsocks/Outline Server.

## File Path
```
/opt/vpn/v2ray/config.json
```

## Configuration

```json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "default_uuid_here",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "default-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com"
          ],
          "privateKey": "your_private_key_here",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "your_short_id_here"
          ],
          "fingerprint": "chrome"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "listen": "172.16.238.3",
      "port": 443,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "0.0.0.0",
        "network": "tcp,udp",
        "followRedirect": true
      },
      "tag": "outline_in",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "protocol": "freedom",
      "tag": "streaming_out",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 100,
          "tcpFastOpen": true,
          "tcpKeepAliveInterval": 25
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "browsing_out",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["outline_in"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": [
          "youtube.com", "googlevideo.com", "*.googlevideo.com",
          "netflix.com", "netflixdnstest.com", "*.nflxvideo.net",
          "hulu.com", "hulustream.com",
          "spotify.com", "*.spotifycdn.com",
          "twitch.tv", "*.ttvnw.net", "*.jtvnw.net",
          "amazon.com/Prime-Video", "primevideo.com", "aiv-cdn.net"
        ],
        "outboundTag": "streaming_out"
      },
      {
        "type": "field",
        "domain": [
          "*.googleusercontent.com", "*.gstatic.com", 
          "*.facebook.com", "*.fbcdn.net",
          "*.twitter.com", "*.twimg.com",
          "*.instagram.com", "*.cdninstagram.com"
        ],
        "outboundTag": "browsing_out"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
```

## Description

### Key Components

1. **Log Configuration**:
   - Warning level to reduce disk usage
   - Separate access and error logs for better troubleshooting

2. **Inbounds**:
   - **VLESS Protocol Inbound**:
     - Listens on port 443 (standard HTTPS port)
     - Uses VLESS protocol with Reality for advanced TLS simulation
     - Client authentication via UUID
     - Flow control with xtls-rprx-vision for better performance
   
   - **Dokodemo-door Inbound**:
     - Special internal proxy to receive traffic from Outline Server
     - Listens on 172.16.238.3 (internal Docker network address)
     - Transparent proxy for all protocols (TCP/UDP)
     - Tagged as "outline_in" for routing rules

3. **Outbounds**:
   - **direct**: Default outbound for general traffic
   - **blocked**: Black hole for unwanted traffic (ads, malicious sites)
   - **streaming_out**: Optimized for streaming services with:
     - TCP Fast Open
     - TCP Keep-alive for connection persistence
     - Traffic marking for QoS (Quality of Service)
   - **browsing_out**: Configured for general web browsing

4. **Reality Settings**:
   - **dest**: Target site to mimic (Microsoft.com)
   - **privateKey**: X25519 private key
   - **serverNames**: SNI values to accept
   - **shortIds**: Short IDs for client authentication
   - **fingerprint**: Chrome browser TLS fingerprint simulation

5. **Routing Rules**:
   - Content-aware routing based on domains, protocols, and source
   - Special handling for traffic from Outline Server
   - Advertising domains blocked
   - Streaming services optimized
   - Social media and content delivery optimized
   - BitTorrent traffic handled directly
   - Private network access blocked

### Integration with Outline Server

The key integration point is the dokodemo-door inbound with:
- Listening on the internal Docker network IP
- Sniffing enabled to detect HTTP/TLS traffic
- Traffic tagged for routing decisions

### Performance Optimizations

1. **Streaming Traffic Optimization**:
   - TCP Fast Open for reduced connection establishment time
   - Keep-alive settings to maintain connection
   - Traffic marking for potential QoS handling

2. **Content-Based Routing**:
   - Different traffic types routed to optimized outbounds
   - Streaming domains identified for special handling
   - Content delivery networks optimized

3. **Security Measures**:
   - Private networks blocked to prevent access to local resources
   - Advertising domains blocked at the routing level
   - Sniffing enabled to properly identify traffic types

### Implementation Notes

1. **UUID Generation**:
   - Replace "default_uuid_here" with a generated UUID
   - Multiple clients can be added to the "clients" array

2. **Reality Keys**:
   - Generate X25519 key pair using:
     ```
     docker run --rm v2fly/v2fly-core:latest xray x25519
     ```
   - Replace "your_private_key_here" with the generated private key
   - Replace "your_short_id_here" with a random 16-character hex string

3. **Domain Selection**:
   - The routing rules should be customized based on user needs
   - Domain lists should be regularly updated to maintain effectiveness
   - Consider using geosite:category-X lists for broader categories

4. **Security Considerations**:
   - The config.json file should have restricted permissions (0644)
   - Private key should never be shared or exposed
   - Reality settings should be updated periodically