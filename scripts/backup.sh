#!/bin/bash
#
# backup.sh - Backup script for the integrated VPN solution
# This script creates timestamped backups of all configuration files and user data

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
BACKUP_DIR="${BASE_DIR}/backups"
LOG_DIR="${BASE_DIR}/logs"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
RETENTION_DAYS=30
BACKUP_ENCRYPTION="false"
ENCRYPTION_KEY=""

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "${LOG_DIR}/backup.log"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "${LOG_DIR}/backup.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "${LOG_DIR}/backup.log"
    exit 1
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create a backup of all VPN configurations and user data.

Options:
  --retention DAYS    Number of days to keep backups (default: 30)
  --encrypt           Enable backup encryption
  --key KEY           Encryption key for backup
  --help              Display this help message

Example:
  $(basename "$0") --retention 60 --encrypt --key "your-secure-passphrase"
EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --retention)
                RETENTION_DAYS="$2"
                shift
                ;;
            --encrypt)
                BACKUP_ENCRYPTION="true"
                ;;
            --key)
                ENCRYPTION_KEY="$2"
                shift
                ;;
            --help)
                display_usage
                exit 0
                ;;
            *)
                warn "Unknown parameter: $1"
                ;;
        esac
        shift
    done
}

# Check required dependencies
check_dependencies() {
    info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check for required tools
    if ! command -v tar &> /dev/null; then
        missing_deps+=("tar")
    fi
    
    if ! command -v gzip &> /dev/null; then
        missing_deps+=("gzip")
    fi
    
    if [ "$BACKUP_ENCRYPTION" = "true" ] && ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}. Please install them and try again."
    fi
}

# Create backup directories
create_backup_dirs() {
    info "Creating backup directories..."
    
    # Create the base backup directory if it doesn't exist
    mkdir -p "${BACKUP_DIR}"
    
    # Create timestamp-based backup directory
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    CURRENT_BACKUP_DIR="${BACKUP_DIR}/${timestamp}"
    mkdir -p "${CURRENT_BACKUP_DIR}"
    
    # Set appropriate permissions
    chmod 700 "${BACKUP_DIR}"
    chmod 700 "${CURRENT_BACKUP_DIR}"
    
    info "Backup will be stored in: ${CURRENT_BACKUP_DIR}"
}

# Verify directories exist
verify_directories() {
    info "Verifying that all required directories exist..."
    
    local missing_dirs=()
    
    if [ ! -d "${OUTLINE_DIR}" ]; then
        missing_dirs+=("${OUTLINE_DIR}")
    fi
    
    if [ ! -d "${V2RAY_DIR}" ]; then
        missing_dirs+=("${V2RAY_DIR}")
    fi
    
    if [ ${#missing_dirs[@]} -ne 0 ]; then
        warn "Some directories do not exist: ${missing_dirs[*]}"
        warn "Backups for these components will be skipped."
    fi
}

# Backup Outline Server configuration
backup_outline() {
    info "Backing up Outline Server configuration..."
    
    if [ ! -d "${OUTLINE_DIR}" ]; then
        warn "Outline Server directory not found. Skipping Outline backup."
        return 1
    fi
    
    # Create directory structure in backup location
    mkdir -p "${CURRENT_BACKUP_DIR}/outline-server"
    
    # Backup main configuration file
    if [ -f "${OUTLINE_DIR}/config.json" ]; then
        cp "${OUTLINE_DIR}/config.json" "${CURRENT_BACKUP_DIR}/outline-server/"
    else
        warn "Outline Server config.json not found."
    fi
    
    # Backup access policy
    if [ -f "${OUTLINE_DIR}/access.json" ]; then
        cp "${OUTLINE_DIR}/access.json" "${CURRENT_BACKUP_DIR}/outline-server/"
    fi
    
    # Backup user data
    if [ -d "${OUTLINE_DIR}/data" ]; then
        cp -r "${OUTLINE_DIR}/data" "${CURRENT_BACKUP_DIR}/outline-server/"
    else
        warn "Outline Server user data directory not found."
    fi
    
    info "Outline Server backup completed."
}

# Backup v2ray configuration
backup_v2ray() {
    info "Backing up v2ray configuration..."
    
    if [ ! -d "${V2RAY_DIR}" ]; then
        warn "v2ray directory not found. Skipping v2ray backup."
        return 1
    fi
    
    # Create directory structure in backup location
    mkdir -p "${CURRENT_BACKUP_DIR}/v2ray"
    
    # Backup main configuration file
    if [ -f "${V2RAY_DIR}/config.json" ]; then
        cp "${V2RAY_DIR}/config.json" "${CURRENT_BACKUP_DIR}/v2ray/"
    else
        warn "v2ray config.json not found."
    fi
    
    # Backup Reality keypair
    if [ -f "${V2RAY_DIR}/reality_keypair.txt" ]; then
        cp "${V2RAY_DIR}/reality_keypair.txt" "${CURRENT_BACKUP_DIR}/v2ray/"
    else
        warn "v2ray Reality keypair not found."
    fi
    
    # Backup users database
    if [ -f "${V2RAY_DIR}/users.db" ]; then
        cp "${V2RAY_DIR}/users.db" "${CURRENT_BACKUP_DIR}/v2ray/"
    else
        warn "v2ray users database not found."
    fi
    
    info "v2ray backup completed."
}

# Backup Docker Compose configuration
backup_docker_compose() {
    info "Backing up Docker Compose configuration..."
    
    # Create directory structure in backup location
    mkdir -p "${CURRENT_BACKUP_DIR}/docker"
    
    # Backup docker-compose.yml
    if [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        cp "${BASE_DIR}/docker-compose.yml" "${CURRENT_BACKUP_DIR}/docker/"
    else
        warn "docker-compose.yml not found."
    fi
    
    info "Docker Compose backup completed."
}

# Backup system configuration
backup_system_config() {
    info "Backing up system configuration..."
    
    # Create directory structure in backup location
    mkdir -p "${CURRENT_BACKUP_DIR}/system"
    
    # Backup firewall configuration
    if command -v ufw &> /dev/null; then
        ufw status verbose > "${CURRENT_BACKUP_DIR}/system/ufw-status.txt"
    fi
    
    # Backup IP forwarding configuration
    grep 'ip_forward' /etc/sysctl.conf > "${CURRENT_BACKUP_DIR}/system/ip-forwarding.txt"
    
    # Backup network interfaces
    ip addr show > "${CURRENT_BACKUP_DIR}/system/ip-addr.txt"
    
    # Backup system metrics if available
    if [ -d "${BASE_DIR}/metrics" ]; then
        mkdir -p "${CURRENT_BACKUP_DIR}/metrics"
        cp -r "${BASE_DIR}/metrics"/* "${CURRENT_BACKUP_DIR}/metrics/" 2>/dev/null || true
    fi
    
    info "System configuration backup completed."
}

# Create backup archive
create_backup_archive() {
    info "Creating backup archive..."
    
    local timestamp=$(basename "${CURRENT_BACKUP_DIR}")
    local archive_name="vpn-backup-${timestamp}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_name}"
    
    # Create tar archive
    tar -czf "${archive_path}" -C "${BACKUP_DIR}" "${timestamp}"
    
    # Check if archive was created successfully
    if [ -f "${archive_path}" ]; then
        info "Backup archive created: ${archive_path}"
        
        # Encrypt the archive if requested
        if [ "$BACKUP_ENCRYPTION" = "true" ]; then
            encrypt_backup "${archive_path}"
        fi
        
        # Verify backup archive
        verify_backup "${archive_path}"
        
        # Remove the temporary backup directory
        rm -rf "${CURRENT_BACKUP_DIR}"
    else
        error "Failed to create backup archive."
    fi
}

# Encrypt backup archive
encrypt_backup() {
    local archive_path="$1"
    local encrypted_path="${archive_path}.enc"
    
    info "Encrypting backup archive..."
    
    if [ -z "$ENCRYPTION_KEY" ]; then
        warn "No encryption key provided. Generating a random key."
        ENCRYPTION_KEY=$(openssl rand -base64 32)
        echo "Encryption Key: ${ENCRYPTION_KEY}" > "${BACKUP_DIR}/encryption-key.txt"
        chmod 600 "${BACKUP_DIR}/encryption-key.txt"
        info "Encryption key saved to: ${BACKUP_DIR}/encryption-key.txt"
        warn "IMPORTANT: Keep this key safe! You will need it to restore backups."
    fi
    
    # Encrypt the archive
    openssl enc -aes-256-cbc -salt -in "${archive_path}" -out "${encrypted_path}" -k "${ENCRYPTION_KEY}"
    
    # Check if encryption was successful
    if [ -f "${encrypted_path}" ]; then
        info "Backup encrypted successfully: ${encrypted_path}"
        # Remove the unencrypted archive
        rm -f "${archive_path}"
    else
        error "Failed to encrypt backup archive."
    fi
}

# Verify backup archive
verify_backup() {
    local archive_path="$1"
    
    info "Verifying backup integrity..."
    
    if [ "$BACKUP_ENCRYPTION" = "true" ]; then
        # For encrypted backups, we just check if the file exists and has non-zero size
        if [ -s "${archive_path}.enc" ]; then
            info "Backup verification passed."
        else
            error "Backup verification failed. Encrypted archive does not exist or is empty."
        fi
    else
        # For unencrypted backups, we can test the tar archive
        if tar -tzf "${archive_path}" &> /dev/null; then
            info "Backup verification passed."
        else
            error "Backup verification failed. Archive may be corrupted."
        fi
    fi
}

# Clean up old backups
cleanup_old_backups() {
    info "Cleaning up old backups..."
    
    # Find and delete backups older than RETENTION_DAYS
    find "${BACKUP_DIR}" -name "vpn-backup-*.tar.gz" -type f -mtime "+${RETENTION_DAYS}" -delete
    find "${BACKUP_DIR}" -name "vpn-backup-*.tar.gz.enc" -type f -mtime "+${RETENTION_DAYS}" -delete
    
    # Log the number of backups kept
    local backup_count=$(find "${BACKUP_DIR}" -name "vpn-backup-*.tar.gz*" -type f | wc -l)
    info "Kept ${backup_count} recent backups."
}

# Main function
main() {
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}"
    
    info "Starting backup at $(date)"
    
    parse_args "$@"
    check_dependencies
    create_backup_dirs
    verify_directories
    
    # Perform backups
    backup_outline
    backup_v2ray
    backup_docker_compose
    backup_system_config
    
    # Create backup archive
    create_backup_archive
    
    # Clean up old backups
    cleanup_old_backups
    
    info "Backup completed successfully at $(date)"
}

# Execute main function with all arguments
main "$@"