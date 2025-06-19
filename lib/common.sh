#!/bin/bash

# VPN Project Common Library
# Contains shared functions, colors, and utilities used across all scripts

# Mark as sourced
export COMMON_SOURCED=true

# Exit on error
set -e

# Define project root directory
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export PROJECT_ROOT
fi

# ========================= COLOR DEFINITIONS =========================

# Color codes for terminal output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'    # Bright yellow for better visibility
export BLUE='\033[0;36m'      # Cyan instead of blue for better readability
export PURPLE='\033[0;35m'    # Purple for additional highlights
export WHITE='\033[1;37m'     # Bright white for emphasis
export NC='\033[0m'           # No Color

# ========================= COMMON VARIABLES =========================

# Default working directories
export WORK_DIR="${WORK_DIR:-/opt/v2ray}"
export OUTLINE_DIR="${OUTLINE_DIR:-/opt/outline}"
export USERS_DIR="$WORK_DIR/users"
export CONFIG_FILE="$WORK_DIR/config/config.json"
export LOGS_DIR="$WORK_DIR/logs"

# Default ports
export OUTLINE_API_PORT="${OUTLINE_API_PORT:-9000}"

# Script directory (dynamically determined)
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ========================= LOGGING FUNCTIONS =========================

# Log success message
log() {
    echo -e "${GREEN}✓${NC} $1"
}

# Log error message and exit
error() {
    echo -e "${RED}✗ [ERROR]${NC} $1" >&2
    exit 1
}

# Log warning message
warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1" >&2
}

# Log info message
info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

# Log debug message (only if DEBUG=1)
debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${PURPLE}🐛 [DEBUG]${NC} $1" >&2
    fi
}

# ========================= UTILITY FUNCTIONS =========================

# Wait for user to press Enter
press_enter() {
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Пожалуйста, запустите скрипт с правами суперпользователя (sudo)"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get current IP address
get_current_ip() {
    curl -s https://api.ipify.org 2>/dev/null || echo "127.0.0.1"
}

# ========================= DIRECTORY FUNCTIONS =========================

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        debug "Created directory: $dir"
    fi
}

# Ensure working directories exist
ensure_work_dirs() {
    ensure_dir "$WORK_DIR"
    ensure_dir "$WORK_DIR/config"
    ensure_dir "$USERS_DIR"
    ensure_dir "$LOGS_DIR"
}

# ========================= FILE FUNCTIONS =========================

# Safe file read
safe_read_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file"
    else
        debug "File not found: $file"
        return 1
    fi
}

# Safe file write
safe_write_file() {
    local file="$1"
    local content="$2"
    local dir=$(dirname "$file")
    
    ensure_dir "$dir"
    echo "$content" > "$file"
    debug "Written to file: $file"
}

# ========================= VALIDATION FUNCTIONS =========================

# Validate port number
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# Validate UUID format
validate_uuid() {
    local uuid="$1"
    if [[ "$uuid" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]]; then
        return 0
    else
        return 1
    fi
}

# ========================= GENERATION FUNCTIONS =========================

# Generate random string
generate_random_string() {
    local length="${1:-32}"
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    
    if command_exists openssl; then
        openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
    elif [ -c /dev/urandom ]; then
        < /dev/urandom tr -dc "$chars" | head -c"$length"
    else
        # Fallback method
        for i in $(seq 1 "$length"); do
            echo -n "${chars:$(( RANDOM % ${#chars} )):1}"
        done
    fi
}

# ========================= INITIALIZATION =========================

# Initialize common library
init_common() {
    debug "Initializing common library"
    ensure_work_dirs
}

# Auto-initialize when sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    debug "Common library loaded"
fi