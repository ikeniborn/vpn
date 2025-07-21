#!/bin/bash
# Test protocol-specific installation check

echo "Testing protocol-specific installation detection..."
echo ""
echo "Current installation status:"
echo "- VLESS: $([ -f /opt/vless/docker-compose.yml ] && echo "INSTALLED" || echo "NOT INSTALLED")"
echo "- Shadowsocks: $([ -f /opt/shadowsocks/docker-compose.yml ] && echo "INSTALLED" || echo "NOT INSTALLED")" 
echo "- WireGuard: $([ -f /opt/wireguard/docker-compose.yml ] && echo "INSTALLED" || echo "NOT INSTALLED")"
echo "- Proxy: $([ -f /opt/proxy/docker-compose.yml ] && echo "INSTALLED" || echo "NOT INSTALLED")"
echo ""
echo "Expected behavior:"
echo "1. When selecting an uninstalled protocol - should NOT ask about reinstallation"
echo "2. When selecting an installed protocol - should ask about reinstallation"
echo "3. If old artifacts exist without docker-compose.yml - should offer cleanup"
echo ""

# Create a test artifact directory to simulate old installation
echo "Creating test artifact in /tmp/test-proxy to simulate old installation..."
sudo mkdir -p /tmp/test-proxy
sudo touch /tmp/test-proxy/old-config.txt
echo ""

echo "Test scenarios:"
echo "1. Select HTTP/SOCKS5 Proxy - should proceed without reinstall question"
echo "2. Select VLESS+Reality - should ask about reinstall (if installed)"
echo ""
echo "Press Enter to start the menu test..."
read

/home/ikeniborn/Documents/Project/vpn/target/release/vpn menu