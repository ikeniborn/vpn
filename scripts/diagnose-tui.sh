#!/bin/bash

# Diagnose TUI issues on remote server
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "========================================"
echo "   VPN Manager TUI Diagnostics"
echo "========================================"
echo

# 1. Check environment variables
log "Checking environment variables..."
echo "VPN_INSTALL_PATH=$VPN_INSTALL_PATH"
echo "VPN_CONFIG_PATH=$VPN_CONFIG_PATH"
echo "VPN_DATA_PATH=$VPN_DATA_PATH"
echo

# 2. Check database
log "Checking database..."
DB_PATH="${VPN_DATA_PATH:-$HOME/.local/share/vpn-manager}/vpn.db"
if [ -f "$DB_PATH" ]; then
    success "Database exists at: $DB_PATH"
    echo "Database size: $(du -h "$DB_PATH" | cut -f1)"
else
    error "Database not found at: $DB_PATH"
    log "Creating database directory..."
    mkdir -p "$(dirname "$DB_PATH")"
fi
echo

# 3. Check Docker
log "Checking Docker connection..."
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        success "Docker is running and accessible"
        echo "Docker version: $(docker --version)"
    else
        error "Docker is installed but not accessible"
        echo "Try: sudo usermod -aG docker $USER && newgrp docker"
    fi
else
    error "Docker is not installed"
fi
echo

# 4. Test Python environment
log "Testing Python environment..."
python3 << 'EOF'
import sys
print(f"Python version: {sys.version}")

try:
    from vpn.core.config import settings
    print(f"✓ Config loaded: install_path={settings.install_path}")
except Exception as e:
    print(f"✗ Config error: {e}")

try:
    from vpn.services.user_manager import UserManager
    print("✓ UserManager imported")
except Exception as e:
    print(f"✗ UserManager import error: {e}")

try:
    from vpn.services.docker_manager import DockerManager
    print("✓ DockerManager imported")
except Exception as e:
    print(f"✗ DockerManager import error: {e}")

try:
    import asyncio
    from vpn.core.database import init_db
    asyncio.run(init_db())
    print("✓ Database initialized")
except Exception as e:
    print(f"✗ Database init error: {e}")
EOF
echo

# 5. Test TUI in debug mode
log "Testing TUI startup..."
echo "Running: vpn --debug tui --help"
vpn --debug tui --help 2>&1 | head -20
echo

# 6. Check logs
log "Checking logs..."
LOG_DIR="${VPN_DATA_PATH:-$HOME/.local/share/vpn-manager}/logs"
if [ -d "$LOG_DIR" ]; then
    echo "Log directory: $LOG_DIR"
    echo "Recent logs:"
    ls -la "$LOG_DIR" 2>/dev/null | tail -5 || echo "No log files found"
else
    warn "Log directory not found: $LOG_DIR"
fi
echo

# 7. Recommendations
echo "========================================"
echo "   Recommendations"
echo "========================================"
echo
if [ ! -f "$DB_PATH" ]; then
    echo "1. Initialize database:"
    echo "   python -m vpn.core.database"
    echo
fi

if ! docker info &> /dev/null; then
    echo "2. Fix Docker access:"
    echo "   sudo usermod -aG docker $USER"
    echo "   newgrp docker"
    echo
fi

echo "3. Run TUI with debug logging:"
echo "   VPN_LOG_LEVEL=DEBUG vpn tui"
echo
echo "4. Check full logs:"
echo "   tail -f $LOG_DIR/*.log"
echo