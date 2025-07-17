#!/bin/bash

set -euo pipefail

# Check if running with sudo
if [[ $EUID -eq 0 ]]; then
    echo "Error: This script should not be run with sudo."
    echo "Please run: ./build-release.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${SCRIPT_DIR}/release"
RELEASE_NAME="vpn-release"
VERSION=$(grep '^version' "${SCRIPT_DIR}/Cargo.toml" | head -1 | cut -d'"' -f2)

echo "Building VPN Management System Release v${VERSION}..."

mkdir -p "${RELEASE_DIR}"

if [ -f "${RELEASE_DIR}/${RELEASE_NAME}.tar.gz" ]; then
    echo "Removing old release archive..."
    rm -f "${RELEASE_DIR}/${RELEASE_NAME}.tar.gz"
fi

echo "Building Rust applications..."

# Set up DATABASE_URL for sqlx macros (required for vpn-identity)
TEMP_DB="/tmp/vpn_build_$$_.db"
export DATABASE_URL="sqlite://$TEMP_DB"

# Create temporary database with schema for sqlx macros
if command -v sqlite3 >/dev/null 2>&1; then
    echo "Setting up temporary database for sqlx macros..."
    if [ -f "${SCRIPT_DIR}/crates/vpn-identity/migrations/001_initial.sql" ]; then
        sqlite3 "$TEMP_DB" < "${SCRIPT_DIR}/crates/vpn-identity/migrations/001_initial.sql" 2>/dev/null || true
    else
        # Create empty database if migration file doesn't exist
        sqlite3 "$TEMP_DB" "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY);" 2>/dev/null || true
    fi
fi

# Build all workspace members with compatible CPU target (continue on error)
# Use x86-64-v2 for better compatibility with older CPUs
cd "${SCRIPT_DIR}"
RUSTFLAGS="-C target-cpu=x86-64-v2" cargo build --release --locked --workspace || echo "  ⚠ Some workspace members failed to build"

# Also build specific binaries that might not be default members
echo "Building additional binaries..."
RUSTFLAGS="-C target-cpu=x86-64-v2" cargo build --release --locked -p vpn-proxy --bin vpn-proxy-auth 2>/dev/null || echo "  ⚠ vpn-proxy-auth build failed"
DATABASE_URL="sqlite::memory:" RUSTFLAGS="-C target-cpu=x86-64-v2" cargo build --release --locked -p vpn-identity --bin vpn-identity 2>/dev/null || echo "  ⚠ vpn-identity build failed"

echo "Creating release directory structure..."
TEMP_DIR=$(mktemp -d)
RELEASE_CONTENT="${TEMP_DIR}/${RELEASE_NAME}"
mkdir -p "${RELEASE_CONTENT}"

echo "Copying binaries..."
mkdir -p "${RELEASE_CONTENT}/bin"

# Copy main VPN CLI binary
if [ -f "${SCRIPT_DIR}/target/release/vpn" ]; then
    cp "${SCRIPT_DIR}/target/release/vpn" "${RELEASE_CONTENT}/bin/vpn"
    # Create symlinks for compatibility
    ln -sf vpn "${RELEASE_CONTENT}/bin/vpn-manager"
    ln -sf vpn "${RELEASE_CONTENT}/bin/vpn-cli"
    echo "  ✓ Copied vpn CLI"
else
    echo "  ✗ vpn binary not found"
fi

# Copy proxy auth binary
if [ -f "${SCRIPT_DIR}/target/release/vpn-proxy-auth" ]; then
    cp "${SCRIPT_DIR}/target/release/vpn-proxy-auth" "${RELEASE_CONTENT}/bin/vpn-proxy"
    echo "  ✓ Copied vpn-proxy"
else
    echo "  ✗ vpn-proxy-auth binary not found"
fi

# Copy identity binary
if [ -f "${SCRIPT_DIR}/target/release/vpn-identity" ]; then
    cp "${SCRIPT_DIR}/target/release/vpn-identity" "${RELEASE_CONTENT}/bin/vpn-identity"
    echo "  ✓ Copied vpn-identity"
else
    echo "  ✗ vpn-identity binary not found"
fi

# Create placeholder API binary (if needed)
# Note: vpn-api might be integrated into the main vpn binary
ln -sf vpn "${RELEASE_CONTENT}/bin/vpn-api"

echo "Copying configuration files..."
mkdir -p "${RELEASE_CONTENT}/configs"
if [[ -d "${SCRIPT_DIR}/configs" ]]; then
    cp -r "${SCRIPT_DIR}/configs"/* "${RELEASE_CONTENT}/configs/" 2>/dev/null || true
fi

echo "Copying templates (Docker configs, service configs, etc.)..."
mkdir -p "${RELEASE_CONTENT}/templates"
if [ -d "${SCRIPT_DIR}/templates" ]; then
    cp -r "${SCRIPT_DIR}/templates"/* "${RELEASE_CONTENT}/templates/" || true
    echo "  ✓ Copied templates directory"
else
    echo "  ✗ templates directory not found"
fi

echo "Copying Docker files from templates..."
mkdir -p "${RELEASE_CONTENT}/docker"
# Copy Dockerfile and docker-compose files from templates
if [ -f "${SCRIPT_DIR}/templates/Dockerfile" ]; then
    cp "${SCRIPT_DIR}/templates/Dockerfile" "${RELEASE_CONTENT}/docker/" || true
fi
if [ -f "${SCRIPT_DIR}/templates/docker-compose.hub.yml" ]; then
    cp "${SCRIPT_DIR}/templates/docker-compose.hub.yml" "${RELEASE_CONTENT}/docker/" || true
fi
# Copy any additional Dockerfiles from templates
find "${SCRIPT_DIR}/templates" -name "Dockerfile*" -exec cp {} "${RELEASE_CONTENT}/docker/" \; 2>/dev/null || true

echo "Copying systemd service files..."
mkdir -p "${RELEASE_CONTENT}/systemd"
find "${SCRIPT_DIR}" -name "*.service" -exec cp {} "${RELEASE_CONTENT}/systemd/" \; 2>/dev/null || true

echo "Copying scripts..."
mkdir -p "${RELEASE_CONTENT}/scripts"
# Copy release install/uninstall scripts to root of release
if [ -f "${SCRIPT_DIR}/templates/release-scripts/install.sh" ]; then
    cp "${SCRIPT_DIR}/templates/release-scripts/install.sh" "${RELEASE_CONTENT}/install.sh"
    chmod +x "${RELEASE_CONTENT}/install.sh"
    echo "  ✓ Copied install.sh"
fi
if [ -f "${SCRIPT_DIR}/templates/release-scripts/uninstall.sh" ]; then
    cp "${SCRIPT_DIR}/templates/release-scripts/uninstall.sh" "${RELEASE_CONTENT}/uninstall.sh"
    chmod +x "${RELEASE_CONTENT}/uninstall.sh"
    echo "  ✓ Copied uninstall.sh"
fi
# Scripts directory is included but might be empty
# Additional operational scripts can be added here if needed

echo "Copying documentation..."
mkdir -p "${RELEASE_CONTENT}/docs"
# Don't copy main README to root of archive since we create our own
if [[ -f "${SCRIPT_DIR}/CHANGELOG.md" ]]; then
    cp "${SCRIPT_DIR}/CHANGELOG.md" "${RELEASE_CONTENT}/" || true
elif [[ -f "${SCRIPT_DIR}/docs/CHANGELOG.md" ]]; then
    cp "${SCRIPT_DIR}/docs/CHANGELOG.md" "${RELEASE_CONTENT}/" || true
fi
cp -r "${SCRIPT_DIR}/docs"/* "${RELEASE_CONTENT}/docs/" 2>/dev/null || true

echo "Copying additional configuration files..."
if [ -f "${SCRIPT_DIR}/templates/deny.toml" ]; then
    cp "${SCRIPT_DIR}/templates/deny.toml" "${RELEASE_CONTENT}/configs/" || true
    echo "  ✓ Copied deny.toml"
fi

echo "Creating installation README..."
cat > "${RELEASE_CONTENT}/README.md" << EOF
# VPN Management System - Installation Guide

## Quick Start

\`\`\`bash
# Extract the archive
tar -xzf vpn-release.tar.gz
cd vpn-release

# Install the system
sudo ./install.sh

# Verify installation
vpn --version
\`\`\`

## Installation Notes

- Extract the archive to a temporary directory (e.g., ~/vpn-install)
- Run \`./install.sh\` to install the VPN system
- Run \`./uninstall.sh\` to remove the VPN system
- The db directory will be created at /opt/vpn/db during installation
- Templates directory contains Docker Compose configurations and service configs
- Docker files are in the docker/ directory within the release
- Installation requires root privileges

## Post-Installation

After installation, the VPN system will be available at:
- Binaries: /usr/local/bin/vpn*
- Configuration: /opt/vpn/configs/
- Logs: /opt/vpn/logs/
- Documentation: /opt/vpn/docs/

To start using the VPN system:
\`\`\`bash
# View help
vpn --help

# Start interactive menu
sudo vpn menu

# Check service status
systemctl status vpn-manager
\`\`\`

## Uninstallation

To remove the VPN system:
\`\`\`bash
# With backup
sudo /opt/vpn/scripts/archive-uninstall.sh

# Without backup (force)
sudo /opt/vpn/scripts/archive-uninstall.sh --force
\`\`\`
EOF

echo "Creating version file..."
echo "VPN Management System v${VERSION}" > "${RELEASE_CONTENT}/VERSION"
echo "Built on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "${RELEASE_CONTENT}/VERSION"
echo "Git commit: $(git rev-parse --short HEAD 2>/dev/null || echo "unknown")" >> "${RELEASE_CONTENT}/VERSION"

echo "Creating release info..."
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_HOST=$(hostname)
BUILD_USER=$(whoami)

# Get binary sizes from the release content directory before creating archive
BINARY_SIZES=$(cd "${RELEASE_CONTENT}/bin" && for file in *; do
    if [ -L "$file" ]; then
        # It's a symlink
        target=$(readlink "$file")
        echo "- $file → $target (symlink)"
    elif [ -f "$file" ]; then
        # It's a regular file
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "unknown")
        echo "- $file ($size bytes)"
    fi
done | sort)

echo "Creating release archive..."
cd "${TEMP_DIR}"
tar -czf "${RELEASE_DIR}/${RELEASE_NAME}.tar.gz" "${RELEASE_NAME}"

echo "Cleaning up..."
rm -rf "${TEMP_DIR}"
# Clean up temporary database
rm -f "$TEMP_DB" 2>/dev/null || true

echo "Creating checksums..."
cd "${RELEASE_DIR}"
sha256sum "${RELEASE_NAME}.tar.gz" > "${RELEASE_NAME}.tar.gz.sha256"

RELEASE_SIZE=$(du -h "${RELEASE_NAME}.tar.gz" | cut -f1)

cat > "${RELEASE_DIR}/RELEASE_INFO.md" << EOF
# VPN Management System Release Information

## Version Details
- **Version**: v${VERSION}
- **Build Date**: ${BUILD_DATE}
- **Git Commit**: ${GIT_COMMIT}
- **Git Branch**: ${GIT_BRANCH}
- **Build Host**: ${BUILD_HOST}
- **Build User**: ${BUILD_USER}
- **Target CPU**: x86-64-v2 (compatible with AMD EPYC, Intel Haswell+)

## Release Contents

### Binaries
${BINARY_SIZES}

### Configuration Files
- Templates directory with Docker Compose configurations
- Service configuration files
- deny.toml for dependency scanning

### Docker Support
- Main Dockerfile for VPN service
- docker-compose.hub.yml for Docker Hub deployment
- Proxy service Dockerfiles
- Identity service Dockerfile

### Installation
- install.sh - Main installation script
- Scripts for remote installation and updates
- Systemd service files (if available)

### Documentation
- README.md - Installation instructions
- CHANGELOG.md - Version history
- docs/ - Detailed documentation

## System Requirements
- Linux (Ubuntu 20.04+, Debian 11+, RHEL 8+, Arch)
- x86_64 or aarch64 architecture
- 2GB+ RAM for building
- Docker (optional, for containerized deployment)
- systemd (for service management)

## Installation Instructions

### From Release Archive
\`\`\`bash
tar -xzf vpn-release.tar.gz
cd vpn-release
sudo ./install.sh
\`\`\`

### Docker Deployment
\`\`\`bash
cd /opt/vpn/docker
docker build -f Dockerfile -t vpn:latest .
docker-compose -f docker-compose.hub.yml up -d
\`\`\`

## Verification
- SHA256 checksum available in vpn-release.tar.gz.sha256
- Verify with: \`sha256sum -c vpn-release.tar.gz.sha256\`

## Support
- GitHub Issues: https://github.com/ikeniborn/vpn/issues
- Documentation: /opt/vpn/docs/

---
Generated by build-release.sh
EOF
echo ""
echo "✅ Release build completed successfully!"
echo "📦 Release archive: ${RELEASE_DIR}/${RELEASE_NAME}.tar.gz"
echo "📏 Size: ${RELEASE_SIZE}"
echo "🔒 SHA256: $(cat ${RELEASE_NAME}.tar.gz.sha256)"
echo "📄 Release info: ${RELEASE_DIR}/RELEASE_INFO.md"