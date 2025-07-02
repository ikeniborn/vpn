#!/bin/bash
# VPN Resources Backup Script
# This script backs up VPN server configurations and secrets

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/tmp/vpn-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="vpn-backup-${TIMESTAMP}"
NAMESPACE="${NAMESPACE:-all}"
S3_BUCKET="${S3_BUCKET:-}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

check_requirements() {
    log "Checking requirements..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is required but not installed"
        exit 1
    fi
    
    if ! kubectl auth can-i get vpnservers.vpn.io &> /dev/null; then
        error "No permission to access VPN resources"
        exit 1
    fi
    
    if [[ -n "$S3_BUCKET" ]] && ! command -v aws &> /dev/null; then
        error "AWS CLI is required for S3 backup but not installed"
        exit 1
    fi
}

create_backup_dir() {
    log "Creating backup directory: ${BACKUP_DIR}/${BACKUP_NAME}"
    mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"
}

backup_crds() {
    log "Backing up CRDs..."
    kubectl get crd vpnservers.vpn.io -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/crd-vpnservers.yaml"
}

backup_vpn_servers() {
    log "Backing up VPN servers..."
    
    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get vpnservers --all-namespaces -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/vpnservers-all.yaml"
    else
        kubectl get vpnservers -n "$NAMESPACE" -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/vpnservers-${NAMESPACE}.yaml"
    fi
}

backup_secrets() {
    log "Backing up VPN secrets..."
    
    # Get all VPN-related secrets
    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get secrets --all-namespaces -l app=vpn-server -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/secrets-all.yaml"
    else
        kubectl get secrets -n "$NAMESPACE" -l app=vpn-server -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/secrets-${NAMESPACE}.yaml"
    fi
    
    # Encrypt secrets file
    if command -v gpg &> /dev/null && [[ -n "${GPG_RECIPIENT:-}" ]]; then
        log "Encrypting secrets with GPG..."
        gpg --encrypt --recipient "$GPG_RECIPIENT" "${BACKUP_DIR}/${BACKUP_NAME}/secrets-"*.yaml
        rm -f "${BACKUP_DIR}/${BACKUP_NAME}/secrets-"*.yaml
    else
        warn "GPG encryption not configured. Secrets stored in plain text!"
    fi
}

backup_configmaps() {
    log "Backing up VPN ConfigMaps..."
    
    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get configmaps --all-namespaces -l app=vpn-server -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/configmaps-all.yaml"
    else
        kubectl get configmaps -n "$NAMESPACE" -l app=vpn-server -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/configmaps-${NAMESPACE}.yaml"
    fi
}

backup_pvcs() {
    log "Backing up VPN PersistentVolumeClaims..."
    
    if [[ "$NAMESPACE" == "all" ]]; then
        kubectl get pvc --all-namespaces -l app=vpn-server -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/pvcs-all.yaml"
    else
        kubectl get pvc -n "$NAMESPACE" -l app=vpn-server -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/pvcs-${NAMESPACE}.yaml"
    fi
}

create_manifest() {
    log "Creating backup manifest..."
    
    cat > "${BACKUP_DIR}/${BACKUP_NAME}/manifest.json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_name": "${BACKUP_NAME}",
  "namespace": "${NAMESPACE}",
  "kubernetes_version": "$(kubectl version --short -o json | jq -r .serverVersion.gitVersion)",
  "operator_version": "$(kubectl get deployment -n vpn-system vpn-operator -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo 'unknown')",
  "vpn_server_count": $(kubectl get vpnservers --all-namespaces -o json | jq '.items | length'),
  "files": $(find "${BACKUP_DIR}/${BACKUP_NAME}" -type f -name "*.yaml*" -exec basename {} \; | jq -R . | jq -s .)
}
EOF
}

compress_backup() {
    log "Compressing backup..."
    
    cd "${BACKUP_DIR}"
    tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}/"
    rm -rf "${BACKUP_NAME}"
    
    log "Backup created: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    log "Size: $(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)"
}

upload_to_s3() {
    if [[ -z "$S3_BUCKET" ]]; then
        return
    fi
    
    log "Uploading backup to S3..."
    
    aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" "s3://${S3_BUCKET}/vpn-backups/${BACKUP_NAME}.tar.gz"
    
    # Upload manifest separately for easy querying
    tar -xzf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -O "${BACKUP_NAME}/manifest.json" | \
        aws s3 cp - "s3://${S3_BUCKET}/vpn-backups/manifests/${BACKUP_NAME}.json"
    
    log "Backup uploaded to S3: s3://${S3_BUCKET}/vpn-backups/${BACKUP_NAME}.tar.gz"
}

cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Local cleanup
    find "${BACKUP_DIR}" -name "vpn-backup-*.tar.gz" -mtime +${RETENTION_DAYS} -delete
    
    # S3 cleanup
    if [[ -n "$S3_BUCKET" ]]; then
        aws s3 ls "s3://${S3_BUCKET}/vpn-backups/" | \
            awk '{print $4}' | \
            grep "^vpn-backup-" | \
            while read -r file; do
                file_date=$(echo "$file" | sed -n 's/vpn-backup-\([0-9]\{8\}\).*/\1/p')
                if [[ -n "$file_date" ]]; then
                    if [[ $(date -d "$file_date" +%s 2>/dev/null || echo 0) -lt $(date -d "-${RETENTION_DAYS} days" +%s) ]]; then
                        aws s3 rm "s3://${S3_BUCKET}/vpn-backups/$file"
                        log "Deleted old backup: $file"
                    fi
                fi
            done
    fi
}

# Main execution
main() {
    log "Starting VPN resources backup..."
    
    check_requirements
    create_backup_dir
    
    # Perform backups
    backup_crds
    backup_vpn_servers
    backup_secrets
    backup_configmaps
    backup_pvcs
    create_manifest
    
    # Package and upload
    compress_backup
    upload_to_s3
    cleanup_old_backups
    
    log "Backup completed successfully!"
}

# Run main function
main "$@"