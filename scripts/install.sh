#!/bin/bash
# Wrapper script to call the actual install script

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the actual install script
exec "$SCRIPT_DIR/install/install.sh" "$@"