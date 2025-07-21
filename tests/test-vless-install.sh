#!/bin/bash
# Test VLESS installation with retry mechanism

set -e

echo "Testing VLESS installation with improved startup verification..."

# First, uninstall any existing VLESS installation
if [ -d "/opt/vless" ]; then
    echo "Removing existing VLESS installation..."
    sudo /home/ikeniborn/Documents/Project/vpn/target/release/vpn uninstall --purge || true
fi

# Now test the installation
echo "Installing VLESS server..."
sudo /home/ikeniborn/Documents/Project/vpn/target/release/vpn install \
    --protocol vless \
    --firewall \
    --auto-start

# Check if installation succeeded
if [ $? -eq 0 ]; then
    echo "✓ Installation completed successfully!"
    
    # Verify service is running
    if docker ps | grep -q vless-xray; then
        echo "✓ VLESS container is running"
        
        # Check if port is listening
        if sudo netstat -tlnp | grep -q 18443; then
            echo "✓ Port 18443 is listening"
            
            # Show container status
            docker ps | grep vless
            
            echo ""
            echo "Test PASSED! VLESS installation works with retry mechanism."
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
    echo "✗ Installation failed"
    exit 1
fi