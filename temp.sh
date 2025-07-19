#!/bin/bash

# Create a stub to test removal
mkdir -p ~/.cargo/bin
cat > ~/.cargo/bin/vpn << 'EOF'
#!/bin/bash
# VPN Management System - Stub Script
echo "This is a test stub that should be removed"
EOF
chmod +x ~/.cargo/bin/vpn

echo "Before installation:"
echo "Stub exists: $([ -f ~/.cargo/bin/vpn ] && echo 'YES' || echo 'NO')"
echo "Which vpn: $(which vpn 2>&1)"
echo

# Build and install new version
bash /home/ikeniborn/Documents/Project/vpn/build-release.sh && \
cd /home/ikeniborn/Downloads && \
rm -rf vpn-release vpn-release.tar.gz && \
cp /home/ikeniborn/Documents/Project/vpn/release/vpn-release.tar.gz /home/ikeniborn/Downloads && \
tar -xzf /home/ikeniborn/Downloads/vpn-release.tar.gz && \
cd vpn-release && \
echo "Installing..." && \
./install.sh && \
echo && \
echo "After installation:" && \
echo "Stub exists: $([ -f ~/.cargo/bin/vpn ] && echo 'YES' || echo 'NO')" && \
echo "Clearing PATH cache..." && \
hash -r && \
echo "Which vpn: $(which vpn 2>&1)" && \
echo && \
echo "Now you can run 'vpn' command!"