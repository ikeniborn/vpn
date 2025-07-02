#!/bin/bash
# VPN Resources Restore Script
# This script restores VPN server configurations from backup

set -euo pipefail

# Configuration
BACKUP_FILE="${1:-}"
RESTORE_NAMESPACE="${RESTORE_NAMESPACE:-}"
S3_BUCKET="${S3_BUCKET:-}"
TEMP_DIR="/tmp/vpn-restore-$$"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

usage() {
    cat <<EOF
Usage: $0 [BACKUP_FILE|BACKUP_NAME]

Restore VPN resources from backup.

Arguments:
  BACKUP_FILE    Path to local backup file or name of S3 backup

Environment Variables:
  RESTORE_NAMESPACE  Namespace to restore to (default: original namespace)
  S3_BUCKET         S3 bucket for remote backups
  DRY_RUN          If set to 'true', show what would be restored without applying
  GPG_PASSPHRASE   Passphrase for decrypting secrets (if encrypted)

Examples:
  # Restore from local file
  $0 /tmp/vpn-backups/vpn-backup-20240101-120000.tar.gz
  
  # Restore from S3
  S3_BUCKET=my-backup-bucket $0 vpn-backup-20240101-120000
  
  # Dry run
  DRY_RUN=true $0 backup.tar.gz
  
  # Restore to different namespace
  RESTORE_NAMESPACE=vpn-staging $0 backup.tar.gz
EOF
}

check_requirements() {
    log "Checking requirements..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is required but not installed"
        exit 1
    fi
    
    if ! kubectl auth can-i create vpnservers.vpn.io &> /dev/null; then
        error "No permission to create VPN resources"
        exit 1
    fi
    
    if [[ -n "$S3_BUCKET" ]] && ! command -v aws &> /dev/null; then
        error "AWS CLI is required for S3 restore but not installed"
        exit 1
    fi
}

download_from_s3() {
    local backup_name="$1"
    
    if [[ ! "$backup_name" =~ \.tar\.gz$ ]]; then
        backup_name="${backup_name}.tar.gz"
    fi
    
    log "Downloading backup from S3: s3://${S3_BUCKET}/vpn-backups/${backup_name}"
    
    aws s3 cp "s3://${S3_BUCKET}/vpn-backups/${backup_name}" "${TEMP_DIR}/${backup_name}"
    BACKUP_FILE="${TEMP_DIR}/${backup_name}"
}

extract_backup() {
    log "Extracting backup..."
    
    mkdir -p "$TEMP_DIR"
    tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"
    
    # Find extracted directory
    EXTRACT_DIR=$(find "$TEMP_DIR" -name "vpn-backup-*" -type d | head -1)
    if [[ -z "$EXTRACT_DIR" ]]; then
        error "Could not find backup directory in archive"
        exit 1
    fi
    
    log "Backup extracted to: $EXTRACT_DIR"
}

read_manifest() {
    local manifest_file="${EXTRACT_DIR}/manifest.json"
    
    if [[ ! -f "$manifest_file" ]]; then
        warn "No manifest file found. Proceeding without metadata validation."
        return
    fi
    
    info "Backup Information:"
    info "  Timestamp: $(jq -r .timestamp "$manifest_file")"
    info "  Namespace: $(jq -r .namespace "$manifest_file")"
    info "  Kubernetes Version: $(jq -r .kubernetes_version "$manifest_file")"
    info "  VPN Server Count: $(jq -r .vpn_server_count "$manifest_file")"
    
    # Version compatibility check
    local backup_k8s_version=$(jq -r .kubernetes_version "$manifest_file" | cut -d. -f1-2)
    local current_k8s_version=$(kubectl version --short -o json | jq -r .serverVersion.gitVersion | cut -d. -f1-2)
    
    if [[ "$backup_k8s_version" != "$current_k8s_version" ]]; then
        warn "Kubernetes version mismatch. Backup: $backup_k8s_version, Current: $current_k8s_version"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

decrypt_secrets() {
    log "Checking for encrypted secrets..."
    
    local encrypted_files=$(find "$EXTRACT_DIR" -name "*.gpg" -type f)
    if [[ -z "$encrypted_files" ]]; then
        return
    fi
    
    if ! command -v gpg &> /dev/null; then
        error "GPG is required to decrypt secrets but not installed"
        exit 1
    fi
    
    log "Decrypting secrets..."
    
    for file in $encrypted_files; do
        local output_file="${file%.gpg}"
        if [[ -n "${GPG_PASSPHRASE:-}" ]]; then
            echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 -d "$file" > "$output_file"
        else
            gpg -d "$file" > "$output_file"
        fi
        rm -f "$file"
    done
}

restore_crds() {
    local crd_file="${EXTRACT_DIR}/crd-vpnservers.yaml"
    
    if [[ ! -f "$crd_file" ]]; then
        warn "No CRD backup found. Assuming CRDs are already installed."
        return
    fi
    
    log "Restoring CRDs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would apply: $crd_file"
        kubectl diff -f "$crd_file" || true
    else
        kubectl apply -f "$crd_file"
    fi
}

restore_resources() {
    local resource_type="$1"
    local file_pattern="$2"
    
    log "Restoring ${resource_type}..."
    
    local files=$(find "$EXTRACT_DIR" -name "${file_pattern}" -type f)
    if [[ -z "$files" ]]; then
        warn "No ${resource_type} found to restore"
        return
    fi
    
    for file in $files; do
        if [[ -n "$RESTORE_NAMESPACE" ]]; then
            # Update namespace in resources
            local temp_file="${file}.modified"
            sed "s/namespace: .*/namespace: $RESTORE_NAMESPACE/g" "$file" > "$temp_file"
            file="$temp_file"
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "Would apply: $file"
            kubectl diff -f "$file" || true
        else
            # Apply resources, ignoring already exists errors
            kubectl apply -f "$file" || \
                kubectl replace -f "$file" || \
                warn "Failed to restore some resources from $file"
        fi
    done
}

verify_restore() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    log "Verifying restore..."
    
    # Check VPN servers
    local vpn_count
    if [[ -n "$RESTORE_NAMESPACE" ]]; then
        vpn_count=$(kubectl get vpnservers -n "$RESTORE_NAMESPACE" -o json | jq '.items | length')
    else
        vpn_count=$(kubectl get vpnservers --all-namespaces -o json | jq '.items | length')
    fi
    
    info "VPN servers found: $vpn_count"
    
    # Check for any resources in error state
    local error_count
    if [[ -n "$RESTORE_NAMESPACE" ]]; then
        error_count=$(kubectl get vpnservers -n "$RESTORE_NAMESPACE" -o json | jq '[.items[] | select(.status.phase == "Failed")] | length')
    else
        error_count=$(kubectl get vpnservers --all-namespaces -o json | jq '[.items[] | select(.status.phase == "Failed")] | length')
    fi
    
    if [[ $error_count -gt 0 ]]; then
        warn "Found $error_count VPN servers in Failed state"
    fi
}

cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Main execution
main() {
    if [[ -z "$BACKUP_FILE" ]]; then
        usage
        exit 1
    fi
    
    log "Starting VPN resources restore..."
    
    check_requirements
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    trap cleanup EXIT
    
    # Download from S3 if needed
    if [[ -n "$S3_BUCKET" ]] && [[ ! -f "$BACKUP_FILE" ]]; then
        download_from_s3 "$BACKUP_FILE"
    fi
    
    # Verify backup file exists
    if [[ ! -f "$BACKUP_FILE" ]]; then
        error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    # Extract and prepare
    extract_backup
    read_manifest
    decrypt_secrets
    
    # Confirm restore
    if [[ "$DRY_RUN" != "true" ]]; then
        warn "This will restore VPN resources to your cluster."
        if [[ -n "$RESTORE_NAMESPACE" ]]; then
            warn "Target namespace: $RESTORE_NAMESPACE"
        fi
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Restore resources in order
    restore_crds
    restore_resources "ConfigMaps" "configmaps-*.yaml"
    restore_resources "Secrets" "secrets-*.yaml"
    restore_resources "PVCs" "pvcs-*.yaml"
    restore_resources "VPN Servers" "vpnservers-*.yaml"
    
    # Verify
    verify_restore
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run completed. No changes were made."
    else
        log "Restore completed successfully!"
    fi
}

# Run main function
main "$@"