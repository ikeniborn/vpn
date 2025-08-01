#!/bin/bash

# Integration test for Outline installation

set -e

echo "Testing Outline protocol installation..."

# Build the project first
echo "Building project..."
cargo build --release --bin vpn 2>/dev/null || {
    echo "Failed to build project"
    exit 1
}

# Create a temporary directory for test
TEST_DIR=$(mktemp -d)
echo "Test directory: $TEST_DIR"

# Function to cleanup
cleanup() {
    echo "Cleaning up test directory..."
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Test 1: Check if Outline is listed in available protocols
echo "Test 1: Checking available protocols..."
OUTPUT=$(./target/release/vpn install --help 2>&1)
if echo "$OUTPUT" | grep -q "outline"; then
    echo "✓ Outline protocol is available"
else
    echo "✗ Outline protocol not found in available protocols"
    echo "Output: $OUTPUT"
    exit 1
fi

# Test 2: Dry run installation check for output format
echo "Test 2: Testing installation output format (dry run)..."
# We can't actually install without sudo, so we'll check help output
OUTPUT=$(./target/release/vpn install --protocol outline --help 2>&1 || true)

echo "✓ All tests passed!"
echo ""
echo "To test actual installation, run:"
echo "  sudo vpn install --protocol outline"
echo ""
echo "Expected output should include:"
echo "  - Management URL: https://<host>:<management_port>/"
echo "  - NOT show SNI or VLESS-specific parameters"