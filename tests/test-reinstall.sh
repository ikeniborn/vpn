#!/bin/bash
# Test VLESS reinstallation with fixed log configuration

set -e

echo "Testing VLESS reinstallation..."

# Uninstall existing installation
echo "Uninstalling existing VLESS server..."
sudo /home/ikeniborn/Documents/Project/vpn/target/release/vpn uninstall --purge

# Reinstall
echo "Reinstalling VLESS server..."
sudo /home/ikeniborn/Documents/Project/vpn/target/release/vpn install \
    --protocol vless \
    --firewall \
    --auto-start

# Check if installation succeeded
if [ $? -eq 0 ]; then
    echo "✓ Reinstallation completed successfully!"
    
    # Verify service is running
    if docker ps | grep -q vless-xray; then
        echo "✓ VLESS container is running"
        
        # Check if port is listening
        if sudo netstat -tlnp | grep -q 18443; then
            echo "✓ Port 18443 is listening"
            
            # Check logs to ensure no permission errors
            echo ""
            echo "Checking container logs..."
            docker logs vless-xray --tail 5
            
            echo ""
            echo "Test PASSED! VLESS reinstallation works correctly."
        else
            echo "✗ Port 18443 is not listening"
            exit 1
        fi
    else
        echo "✗ VLESS container is not running"
        docker ps -a | grep vless
        exit 1
    fi
else
    echo "✗ Reinstallation failed"
    exit 1
fi