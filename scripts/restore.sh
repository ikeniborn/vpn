#!/bin/bash
#
# restore.sh - Restore script for the integrated VPN solution
# This script restores from backups created by backup.sh

set -euo pipefail

# Base directories
BASE_DIR="/opt/vpn"
OUTLINE_DIR="${BASE_DIR}/outline-server"
V2RAY_DIR="${BASE_DIR}/v2ray"
BACKUP_DIR="${BASE_DIR}/backups"
LOG_DIR="${BASE_DIR}/logs"
TEMP_DIR="${BASE_DIR}/temp"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
BACKUP_FILE=""
RESTORE_OUTLINE=true
RESTORE_V2RAY=true
RESTORE_DOCKER_COMPOSE=true
RESTORE_SYSTEM=false
BACKUP_ENCRYPTED=false
ENCRYPTION_KEY=""
DRY_RUN=false
SKIP_RESTART=false

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "${LOG_DIR}/restore.log"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "${LOG_DIR}/restore.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "${LOG_DIR}/restore.log"
    exit 1
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Restore VPN configuration from a backup.

Options:
  --file FILE             Path to backup file to restore from (required)
  --skip-outline          Skip restoring Outline Server configuration
  --skip-v2ray            Skip restoring v2ray configuration
  --skip-docker-compose   Skip restoring Docker Compose configuration
  --include-system        Include system configuration restoration (default: excluded)
  --encrypted             Specify that the backup file is encrypted
  --key KEY               Decryption key for encrypted backup
  --dry-run               Perform a dry run without making changes
  --skip-restart          Skip restarting services after restore
  --help                  Display this help message

Example:
  $(basename "$0") --file /opt/vpn/backups/vpn-backup-20250519-120000.tar.gz
EOF
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --file)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    error "Error: --file requires a path argument"
                fi
                BACKUP_FILE="$2"
                shift
                ;;
            --skip-outline)
                RESTORE_OUTLINE=false
                ;;
            --skip-v2ray)
                RESTORE_V2RAY=false
                ;;
            --skip-docker-compose)
                RESTORE_DOCKER_COMPOSE=false
                ;;
            --include-system)
                RESTORE_SYSTEM=true
                ;;
            --encrypted)
                BACKUP_ENCRYPTED=true
                ;;
            --key)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    error "Error: --key requires a value argument"
                fi
                ENCRYPTION_KEY="$2"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                info "Performing a dry run. No changes will be made."
                ;;
            --skip-restart)
                SKIP_RESTART=true
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
    
    # Validate required parameters
    if [ -z "$BACKUP_FILE" ]; then
        error "Backup file is required. Use --file to specify backup file."
    fi
    
    # Validate that the backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        error "Backup file does not exist: $BACKUP_FILE"
    fi
    
    # Check if the backup file is encrypted
    if [[ "$BACKUP_FILE" == *.enc ]]; then
        BACKUP_ENCRYPTED=true
        if [ -z "$ENCRYPTION_KEY" ]; then
            error "Encrypted backup requires a decryption key. Use --key to specify key."
        fi
    fi
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
    
    if [ "$BACKUP_ENCRYPTED" = "true" ] && ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}. Please install them and try again."
    fi
}

# Create temporary directory
create_temp_dir() {
    info "Creating temporary directory..."
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Clean previous files if they exist
    rm -rf "${TEMP_DIR:?}"/*
    
    info "Temporary directory created at ${TEMP_DIR}"
}

# Extract backup archive
extract_backup() {
    info "Extracting backup archive..."
    
    # Create a local variable for the actual backup file
    local extract_file="$BACKUP_FILE"
    
    # If the backup is encrypted, decrypt it first
    if [ "$BACKUP_ENCRYPTED" = "true" ]; then
        info "Verifying backup integrity before decryption..."
        # Create a temporary hash for verification
        local temp_hash_file="${TEMP_DIR}/backup_hash.txt"
        # Generate hash of the encrypted file
        openssl dgst -sha256 -hex "${BACKUP_FILE}" > "${temp_hash_file}"
        info "Backup verification complete."
        
        info "Decrypting backup..."
        local decrypted_file="${TEMP_DIR}/$(basename "${BACKUP_FILE%.enc}")"
        if ! openssl enc -d -aes-256-cbc -in "${BACKUP_FILE}" -out "${decrypted_file}" -k "${ENCRYPTION_KEY}"; then
            error "Backup decryption failed. Please verify your encryption key is correct."
        fi
        extract_file="$decrypted_file"
    fi
    
    # Extract the archive
    tar -xzf "${extract_file}" -C "${TEMP_DIR}"
    
    # Find the extracted backup directory
    local backup_dir_path=$(find "${TEMP_DIR}" -type d -name "20*" | sort | head -n 1)
    
    if [ -z "$backup_dir_path" ]; then
        error "Could not find a valid backup directory in the archive."
    fi
    
    EXTRACTED_DIR="$backup_dir_path"
    info "Backup extracted to ${EXTRACTED_DIR}"
    
    # If dry run, show what would be restored
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would restore the following components:"
        if [ "$RESTORE_OUTLINE" = "true" ] && [ -d "${EXTRACTED_DIR}/outline-server" ]; then
            echo "- Outline Server"
        fi
        if [ "$RESTORE_V2RAY" = "true" ] && [ -d "${EXTRACTED_DIR}/v2ray" ]; then
            echo "- v2ray"
        fi
        if [ "$RESTORE_DOCKER_COMPOSE" = "true" ] && [ -d "${EXTRACTED_DIR}/docker" ]; then
            echo "- Docker Compose configuration"
        fi
        if [ "$RESTORE_SYSTEM" = "true" ] && [ -d "${EXTRACTED_DIR}/system" ]; then
            echo "- System configuration"
        fi
    fi
}

# Restore Outline Server configuration
restore_outline() {
    if [ "$RESTORE_OUTLINE" != "true" ]; then
        info "Skipping Outline Server restoration as requested."
        return 0
    fi
    
    info "Restoring Outline Server configuration..."
    
    # Check if outline configuration exists in backup
    if [ ! -d "${EXTRACTED_DIR}/outline-server" ]; then
        warn "Outline Server configuration not found in backup. Skipping."
        return 1
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would restore Outline Server configuration from ${EXTRACTED_DIR}/outline-server"
        return 0
    fi
    
    # Create backups of current config if it exists
    if [ -f "${OUTLINE_DIR}/config.json" ]; then
        cp "${OUTLINE_DIR}/config.json" "${OUTLINE_DIR}/config.json.before-restore"
        info "Created backup of current Outline Server configuration"
    fi
    
    # Create directories if they don't exist
    mkdir -p "${OUTLINE_DIR}"
    
    # Restore main configuration
    if [ -f "${EXTRACTED_DIR}/outline-server/config.json" ]; then
        cp "${EXTRACTED_DIR}/outline-server/config.json" "${OUTLINE_DIR}/"
        chmod 600 "${OUTLINE_DIR}/config.json"
    else
        warn "Outline Server config.json not found in backup."
    fi
    
    # Restore access policy
    if [ -f "${EXTRACTED_DIR}/outline-server/access.json" ]; then
        cp "${EXTRACTED_DIR}/outline-server/access.json" "${OUTLINE_DIR}/"
        chmod 600 "${OUTLINE_DIR}/access.json"
    fi
    
    # Restore user data
    if [ -d "${EXTRACTED_DIR}/outline-server/data" ]; then
        # Remove current user data if it exists
        if [ -d "${OUTLINE_DIR}/data" ]; then
            rm -rf "${OUTLINE_DIR}/data"
        fi
        
        # Copy user data from backup
        cp -r "${EXTRACTED_DIR}/outline-server/data" "${OUTLINE_DIR}/"
    else
        warn "Outline Server user data not found in backup."
    fi
    
    info "Outline Server configuration restored successfully."
}

# Restore v2ray configuration
restore_v2ray() {
    if [ "$RESTORE_V2RAY" != "true" ]; then
        info "Skipping v2ray restoration as requested."
        return 0
    }
    
    info "Restoring v2ray configuration..."
    
    # Check if v2ray configuration exists in backup
    if [ ! -d "${EXTRACTED_DIR}/v2ray" ]; then
        warn "v2ray configuration not found in backup. Skipping."
        return 1
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would restore v2ray configuration from ${EXTRACTED_DIR}/v2ray"
        return 0
    fi
    
    # Create backups of current config if it exists
    if [ -f "${V2RAY_DIR}/config.json" ]; then
        cp "${V2RAY_DIR}/config.json" "${V2RAY_DIR}/config.json.before-restore"
        info "Created backup of current v2ray configuration"
    fi
    
    # Create directories if they don't exist
    mkdir -p "${V2RAY_DIR}"
    
    # Restore configuration
    if [ -f "${EXTRACTED_DIR}/v2ray/config.json" ]; then
        cp "${EXTRACTED_DIR}/v2ray/config.json" "${V2RAY_DIR}/"
        chmod 644 "${V2RAY_DIR}/config.json"
    else
        warn "v2ray config.json not found in backup."
    fi
    
    # Restore Reality keypair
    if [ -f "${EXTRACTED_DIR}/v2ray/reality_keypair.txt" ]; then
        cp "${EXTRACTED_DIR}/v2ray/reality_keypair.txt" "${V2RAY_DIR}/"
        chmod 600 "${V2RAY_DIR}/reality_keypair.txt"
    else
        warn "v2ray Reality keypair not found in backup."
    fi
    
    # Restore users database
    if [ -f "${EXTRACTED_DIR}/v2ray/users.db" ]; then
        cp "${EXTRACTED_DIR}/v2ray/users.db" "${V2RAY_DIR}/"
        chmod 600 "${V2RAY_DIR}/users.db"
    else
        warn "v2ray users database not found in backup."
    fi
    
    info "v2ray configuration restored successfully."
}

# Restore Docker Compose configuration
restore_docker_compose() {
    if [ "$RESTORE_DOCKER_COMPOSE" != "true" ]; then
        info "Skipping Docker Compose restoration as requested."
        return 0
    }
    
    info "Restoring Docker Compose configuration..."
    
    # Check if docker compose configuration exists in backup
    if [ ! -d "${EXTRACTED_DIR}/docker" ]; then
        warn "Docker Compose configuration not found in backup. Skipping."
        return 1
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would restore Docker Compose configuration from ${EXTRACTED_DIR}/docker"
        return 0
    fi
    
    # Create backup of current config if it exists
    if [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        cp "${BASE_DIR}/docker-compose.yml" "${BASE_DIR}/docker-compose.yml.before-restore"
        info "Created backup of current Docker Compose configuration"
    fi
    
    # Restore docker-compose.yml
    if [ -f "${EXTRACTED_DIR}/docker/docker-compose.yml" ]; then
        cp "${EXTRACTED_DIR}/docker/docker-compose.yml" "${BASE_DIR}/"
    else
        warn "docker-compose.yml not found in backup."
    fi
    
    info "Docker Compose configuration restored successfully."
}

# Restore system configuration
restore_system_config() {
    if [ "$RESTORE_SYSTEM" != "true" ]; then
        info "Skipping system configuration restoration as requested."
        return 0
    }
    
    info "Restoring system configuration..."
    
    # Check if system configuration exists in backup
    if [ ! -d "${EXTRACTED_DIR}/system" ]; then
        warn "System configuration not found in backup. Skipping."
        return 1
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would restore system configuration from ${EXTRACTED_DIR}/system"
        return 0
    fi
    
    warn "System configuration restoration can potentially disrupt your system."
    warn "This will update system settings based on the backup."
    
    read -p "Are you sure you want to proceed? [y/N] " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "System configuration restoration skipped by user."
        return 0
    fi
    
    # Restore IP forwarding if available
    if [ -f "${EXTRACTED_DIR}/system/ip-forwarding.txt" ]; then
        info "Restoring IP forwarding configuration..."
        
        # Extract ip_forward setting
        local ip_forward_setting=$(grep 'net.ipv4.ip_forward' "${EXTRACTED_DIR}/system/ip-forwarding.txt" || echo "net.ipv4.ip_forward=1")
        
        # Update sysctl.conf
        if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
            sed -i "s/^#\?net.ipv4.ip_forward.*/${ip_forward_setting}/" /etc/sysctl.conf
        else
            echo "${ip_forward_setting}" >> /etc/sysctl.conf
        fi
        
        # Apply sysctl changes
        sysctl -p
    fi
    
    # Restore UFW firewall rules if available
    if [ -f "${EXTRACTED_DIR}/system/ufw-status.txt" ] && command -v ufw &> /dev/null; then
        info "Restoring UFW firewall rules..."
        
        # Extract ports that need to be allowed
        local outline_port=$(grep -o "8[0-9]* *ALLOW" "${EXTRACTED_DIR}/system/ufw-status.txt" | awk '{print $1}' | head -1)
        local v2ray_port=$(grep -o "443 *ALLOW" "${EXTRACTED_DIR}/system/ufw-status.txt" | awk '{print $1}' | head -1)
        
        # Apply firewall rules
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp
        
        if [ -n "$outline_port" ]; then
            ufw allow "${outline_port}/tcp"
            ufw allow "${outline_port}/udp"
        else
            ufw allow 8388/tcp
            ufw allow 8388/udp
        fi
        
        if [ -n "$v2ray_port" ]; then
            ufw allow "${v2ray_port}/tcp"
            ufw allow "${v2ray_port}/udp"
        else
            ufw allow 443/tcp
            ufw allow 443/udp
        fi
        
        # Enable UFW
        echo "y" | ufw enable
    fi
    
    info "System configuration restored successfully."
}

# Restart services
restart_services() {
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would restart VPN services after restoration"
        return 0
    fi
    
    if [ "$SKIP_RESTART" = "true" ]; then
        info "Skipping service restart as requested."
        return 0
    fi
    
    info "Restarting VPN services..."
    
    # Check if Docker is running
    if ! command -v docker &> /dev/null || ! systemctl is-active --quiet docker; then
        warn "Docker service is not running. Cannot restart containers."
        warn "Please start Docker and then run: cd ${BASE_DIR} && docker-compose up -d"
        return 1
    fi
    
    # Check if docker-compose file exists
    if [ ! -f "${BASE_DIR}/docker-compose.yml" ]; then
        warn "docker-compose.yml not found. Cannot restart containers."
        warn "Please check your Docker Compose configuration and start services manually."
        return 1
    fi
    
    # Restart containers
    cd "${BASE_DIR}"
    if ! docker-compose down; then
        warn "Failed to stop containers."
    fi
    
    if ! docker-compose up -d; then
        warn "Failed to start containers."
        error "Service restart failed. Please check container logs and configuration."
    fi
    
    info "VPN services restarted successfully."
}

# Cleanup temporary files
cleanup() {
    info "Cleaning up temporary files..."
    
    rm -rf "${TEMP_DIR:?}"/*
    
    info "Cleanup completed."
}

# Verify restoration
verify_restore() {
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run: would verify restoration success"
        return 0
    fi
    
    info "Verifying restoration..."
    local failures=0
    
    # Check if configurations exist
    if [ "$RESTORE_OUTLINE" = "true" ] && [ ! -f "${OUTLINE_DIR}/config.json" ]; then
        warn "Verification failed: Outline Server configuration not found after restore."
        ((failures++))
    fi
    
    if [ "$RESTORE_V2RAY" = "true" ] && [ ! -f "${V2RAY_DIR}/config.json" ]; then
        warn "Verification failed: v2ray configuration not found after restore."
        ((failures++))
    fi
    
    if [ "$RESTORE_DOCKER_COMPOSE" = "true" ] && [ ! -f "${BASE_DIR}/docker-compose.yml" ]; then
        warn "Verification failed: Docker Compose configuration not found after restore."
        ((failures++))
    fi
    
    # If services were restarted, check if they're running
    if [ "$SKIP_RESTART" != "true" ]; then
        if ! docker ps | grep -q "outline-server"; then
            warn "Verification failed: Outline Server container is not running."
            ((failures++))
        fi
        
        if ! docker ps | grep -q "v2ray"; then
            warn "Verification failed: v2ray container is not running."
            ((failures++))
        fi
    fi
    
    if [ "$failures" -gt 0 ]; then
        warn "Verification completed with $failures issues."
    else
        info "Verification successful. All components restored properly."
    fi
}

# Main function
main() {
    # Ensure log directory exists
    mkdir -p "${LOG_DIR}"
    
    info "Starting restore process at $(date)"
    
    parse_args "$@"
    check_dependencies
    create_temp_dir
    extract_backup
    
    # Perform restoration tasks
    restore_outline
    restore_v2ray
    restore_docker_compose
    restore_system_config
    
    # Restart services if not in dry run mode and not skipped
    if [ "$DRY_RUN" != "true" ] && [ "$SKIP_RESTART" != "true" ]; then
        restart_services
    fi
    
    # Verify restoration
    verify_restore
    
    # Cleanup
    cleanup
    
    if [ "$DRY_RUN" = "true" ]; then
        info "Dry run completed. No changes were made."
    else
        info "Restoration completed successfully at $(date)"
    fi
}

# Execute main function with all arguments
main "$@"