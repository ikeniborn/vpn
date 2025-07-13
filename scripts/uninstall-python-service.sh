#!/bin/bash
# VPN Python Service Complete Uninstallation Script
# This script completely removes the Python-based VPN service and all related components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FORCE_REMOVE="${FORCE_REMOVE:-false}"
PRESERVE_DATA="${PRESERVE_DATA:-false}"
QUIET="${QUIET:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Logging functions
log() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root for system-wide changes
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root - will perform system-wide cleanup"
    else
        info "Running as user - will clean user-specific installations"
    fi
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd ($description)"
    else
        log "$description"
        eval "$cmd" || warn "Failed: $description"
    fi
}

# Stop and remove systemd services
remove_systemd_services() {
    log "Removing systemd services..."
    
    local services=(
        "vpn-manager"
        "vpn-server"
        "vpn-proxy"
        "vpn-monitor"
        "vpn-python"
        "vpn.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            execute "systemctl stop $service" "Stopping $service"
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            execute "systemctl disable $service" "Disabling $service"
        fi
        
        if [[ -f "/etc/systemd/system/$service.service" ]]; then
            execute "rm -f /etc/systemd/system/$service.service" "Removing $service.service"
        fi
    done
    
    execute "systemctl daemon-reload" "Reloading systemd daemon"
}

# Stop and remove Docker containers
remove_docker_containers() {
    log "Removing Docker containers and resources..."
    
    # Stop and remove VPN-related containers
    local containers
    containers=$(docker ps -a --filter="label=vpn-manager" --format="{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        for container in $containers; do
            execute "docker stop $container" "Stopping container $container"
            execute "docker rm $container" "Removing container $container"
        done
    fi
    
    # Remove VPN-related containers by name pattern
    local vpn_containers
    vpn_containers=$(docker ps -a --format="{{.Names}}" | grep -E "(vpn|vless|shadowsocks|wireguard|xray)" 2>/dev/null || true)
    
    if [[ -n "$vpn_containers" ]]; then
        for container in $vpn_containers; do
            if [[ "$FORCE_REMOVE" == "true" ]] || confirm_action "Remove container $container?"; then
                execute "docker stop $container" "Stopping $container"
                execute "docker rm $container" "Removing $container"
            fi
        done
    fi
    
    # Remove VPN-related networks
    local networks
    networks=$(docker network ls --filter="label=vpn-manager" --format="{{.Name}}" 2>/dev/null || true)
    
    if [[ -n "$networks" ]]; then
        for network in $networks; do
            execute "docker network rm $network" "Removing network $network"
        done
    fi
    
    # Remove VPN-related volumes
    local volumes
    volumes=$(docker volume ls --filter="label=vpn-manager" --format="{{.Name}}" 2>/dev/null || true)
    
    if [[ -n "$volumes" ]] && [[ "$PRESERVE_DATA" != "true" ]]; then
        for volume in $volumes; do
            if [[ "$FORCE_REMOVE" == "true" ]] || confirm_action "Remove volume $volume (contains data)?"; then
                execute "docker volume rm $volume" "Removing volume $volume"
            fi
        done
    fi
    
    # Remove VPN-related images
    local images
    images=$(docker images --filter="label=vpn-manager" --format="{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    
    if [[ -n "$images" ]]; then
        for image in $images; do
            execute "docker rmi $image" "Removing image $image"
        done
    fi
}

# Remove Python virtual environments and packages
remove_python_environments() {
    log "Removing Python virtual environments and packages..."
    
    # Common virtual environment locations
    local venv_paths=(
        "$HOME/.virtualenvs/vpn"
        "$HOME/.virtualenvs/vpn-manager"
        "$HOME/venv"
        "$HOME/.local/share/virtualenvs/vpn*"
        "/opt/vpn/venv"
        "/opt/vpn-manager/venv"
        "./venv"
    )
    
    for venv_path in "${venv_paths[@]}"; do
        if [[ -d "$venv_path" ]]; then
            execute "rm -rf $venv_path" "Removing virtual environment $venv_path"
        fi
    done
    
    # Remove global pip installations
    local pip_packages=(
        "vpn-manager"
        "vpn"
        "vpn-cli"
        "vpn-tui"
    )
    
    for package in "${pip_packages[@]}"; do
        if pip list | grep -q "^$package"; then
            execute "pip uninstall -y $package" "Uninstalling pip package $package"
        fi
        
        if pip3 list | grep -q "^$package"; then
            execute "pip3 uninstall -y $package" "Uninstalling pip3 package $package"
        fi
    done
}

# Remove configuration files and directories
remove_configuration_files() {
    log "Removing configuration files and directories..."
    
    local config_paths=(
        "/etc/vpn"
        "/etc/vpn-manager"
        "$HOME/.config/vpn"
        "$HOME/.config/vpn-manager"
        "$HOME/.vpn"
        "/opt/vpn"
        "/opt/vpn-manager"
        "/var/lib/vpn"
        "/var/lib/vpn-manager"
    )
    
    for config_path in "${config_paths[@]}"; do
        if [[ -e "$config_path" ]]; then
            if [[ "$PRESERVE_DATA" == "true" ]]; then
                warn "Preserving data directory: $config_path"
            elif [[ "$FORCE_REMOVE" == "true" ]] || confirm_action "Remove configuration directory $config_path?"; then
                execute "rm -rf $config_path" "Removing $config_path"
            fi
        fi
    done
}

# Remove log files
remove_log_files() {
    log "Removing log files..."
    
    local log_paths=(
        "/var/log/vpn"
        "/var/log/vpn-manager"
        "$HOME/.local/share/vpn/logs"
        "/tmp/vpn*.log"
        "/tmp/vpn-manager*.log"
    )
    
    for log_path in "${log_paths[@]}"; do
        if [[ -e "$log_path" ]]; then
            execute "rm -rf $log_path" "Removing log files $log_path"
        fi
    done
}

# Remove binary files and executables
remove_binaries() {
    log "Removing binary files and executables..."
    
    local binary_paths=(
        "/usr/local/bin/vpn"
        "/usr/local/bin/vpn-manager"
        "/usr/bin/vpn"
        "/usr/bin/vpn-manager"
        "$HOME/.local/bin/vpn"
        "$HOME/.local/bin/vpn-manager"
    )
    
    for binary_path in "${binary_paths[@]}"; do
        if [[ -f "$binary_path" ]]; then
            execute "rm -f $binary_path" "Removing binary $binary_path"
        fi
    done
}

# Remove database files
remove_databases() {
    log "Removing database files..."
    
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        warn "Preserving database files as requested"
        return
    fi
    
    local db_paths=(
        "/var/lib/vpn/*.db"
        "/var/lib/vpn-manager/*.db"
        "$HOME/.local/share/vpn/*.db"
        "$HOME/.config/vpn/*.db"
        "./db/vpn.db"
        "./vpn.db"
    )
    
    for db_path in "${db_paths[@]}"; do
        if compgen -G "$db_path" > /dev/null 2>&1; then
            if [[ "$FORCE_REMOVE" == "true" ]] || confirm_action "Remove database files $db_path?"; then
                execute "rm -f $db_path" "Removing database files $db_path"
            fi
        fi
    done
}

# Remove cron jobs and scheduled tasks
remove_scheduled_tasks() {
    log "Removing scheduled tasks..."
    
    # Remove cron jobs
    if command -v crontab >/dev/null 2>&1; then
        local current_crontab
        current_crontab=$(crontab -l 2>/dev/null || true)
        
        if [[ -n "$current_crontab" ]]; then
            local new_crontab
            new_crontab=$(echo "$current_crontab" | grep -v -E "(vpn|vpn-manager)" || true)
            
            if [[ "$current_crontab" != "$new_crontab" ]]; then
                execute "echo '$new_crontab' | crontab -" "Updating crontab to remove VPN entries"
            fi
        fi
    fi
    
    # Remove systemd timers
    local timers=(
        "vpn-backup.timer"
        "vpn-cleanup.timer"
        "vpn-monitor.timer"
        "vpn-update.timer"
    )
    
    for timer in "${timers[@]}"; do
        if systemctl is-active --quiet "$timer" 2>/dev/null; then
            execute "systemctl stop $timer" "Stopping timer $timer"
        fi
        
        if systemctl is-enabled --quiet "$timer" 2>/dev/null; then
            execute "systemctl disable $timer" "Disabling timer $timer"
        fi
        
        if [[ -f "/etc/systemd/system/$timer" ]]; then
            execute "rm -f /etc/systemd/system/$timer" "Removing $timer"
        fi
    done
}

# Remove shell integrations
remove_shell_integrations() {
    log "Removing shell integrations..."
    
    local shell_files=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.profile"
        "$HOME/.bash_profile"
    )
    
    for shell_file in "${shell_files[@]}"; do
        if [[ -f "$shell_file" ]]; then
            # Remove VPN-related lines
            execute "sed -i.bak '/# VPN Manager/,/# End VPN Manager/d' $shell_file" "Removing VPN entries from $shell_file"
            execute "sed -i.bak '/vpn.*completion/d' $shell_file" "Removing VPN completions from $shell_file"
        fi
    done
    
    # Remove completion files
    local completion_paths=(
        "/etc/bash_completion.d/vpn"
        "/usr/share/bash-completion/completions/vpn"
        "$HOME/.local/share/bash-completion/completions/vpn"
    )
    
    for completion_path in "${completion_paths[@]}"; do
        if [[ -f "$completion_path" ]]; then
            execute "rm -f $completion_path" "Removing completion file $completion_path"
        fi
    done
}

# Remove firewall rules
remove_firewall_rules() {
    log "Removing firewall rules..."
    
    # UFW rules
    if command -v ufw >/dev/null 2>&1; then
        local ufw_rules
        ufw_rules=$(ufw status numbered 2>/dev/null | grep -E "(8443|8080|8388|51820)" | awk '{print $1}' | tr -d '[]' || true)
        
        if [[ -n "$ufw_rules" ]]; then
            for rule in $ufw_rules; do
                execute "ufw --force delete $rule" "Removing UFW rule $rule"
            done
        fi
    fi
    
    # iptables rules (basic cleanup)
    if command -v iptables >/dev/null 2>&1; then
        warn "Manual iptables cleanup may be required for ports: 8443, 8080, 8388, 51820"
    fi
    
    # firewalld rules
    if command -v firewall-cmd >/dev/null 2>&1; then
        local ports=("8443/tcp" "8080/tcp" "8388/tcp" "51820/udp")
        
        for port in "${ports[@]}"; do
            if firewall-cmd --list-ports | grep -q "$port"; then
                execute "firewall-cmd --permanent --remove-port=$port" "Removing firewalld port $port"
            fi
        done
        
        execute "firewall-cmd --reload" "Reloading firewalld"
    fi
}

# Remove temporary files
remove_temp_files() {
    log "Removing temporary files..."
    
    local temp_patterns=(
        "/tmp/vpn*"
        "/tmp/vpn-manager*"
        "/var/tmp/vpn*"
        "$HOME/.cache/vpn*"
        "$HOME/.tmp/vpn*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "$pattern" > /dev/null 2>&1; then
            execute "rm -rf $pattern" "Removing temporary files $pattern"
        fi
    done
}

# Remove Python cache files
remove_python_cache() {
    log "Removing Python cache files..."
    
    # Find and remove __pycache__ directories
    local pycache_dirs
    pycache_dirs=$(find . -type d -name "__pycache__" 2>/dev/null || true)
    
    if [[ -n "$pycache_dirs" ]]; then
        while IFS= read -r dir; do
            execute "rm -rf '$dir'" "Removing Python cache $dir"
        done <<< "$pycache_dirs"
    fi
    
    # Remove .pyc files
    local pyc_files
    pyc_files=$(find . -name "*.pyc" -type f 2>/dev/null || true)
    
    if [[ -n "$pyc_files" ]]; then
        while IFS= read -r file; do
            execute "rm -f '$file'" "Removing Python compiled file $file"
        done <<< "$pyc_files"
    fi
}

# Confirm action with user
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE_REMOVE" == "true" ]]; then
        return 0
    fi
    
    echo -n "$message [y/N]: "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Show cleanup summary
show_summary() {
    log "Cleanup Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ Systemd services stopped and removed"
    echo "  ✅ Docker containers, networks, and volumes cleaned"
    echo "  ✅ Python virtual environments removed"
    echo "  ✅ Configuration files and directories cleaned"
    echo "  ✅ Log files removed"
    echo "  ✅ Binary files and executables removed"
    if [[ "$PRESERVE_DATA" != "true" ]]; then
        echo "  ✅ Database files removed"
    else
        echo "  ⏭️  Database files preserved"
    fi
    echo "  ✅ Scheduled tasks and cron jobs removed"
    echo "  ✅ Shell integrations cleaned"
    echo "  ✅ Firewall rules removed"
    echo "  ✅ Temporary and cache files cleaned"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        warn "Some data was preserved. To remove everything, run with --force --no-preserve-data"
    fi
    
    log "Python VPN service has been completely removed from the system."
    log "You can now safely install the Rust-based VPN system."
}

# Show usage information
show_usage() {
    cat << EOF
VPN Python Service Complete Uninstallation Script

Usage: $0 [OPTIONS]

Options:
    -f, --force             Force removal without confirmation prompts
    -p, --preserve-data     Preserve user data and databases
    -q, --quiet             Quiet mode (suppress info messages)
    -n, --dry-run           Show what would be done without executing
    -h, --help              Show this help message

Environment Variables:
    FORCE_REMOVE            Force removal (true/false)
    PRESERVE_DATA           Preserve data (true/false)
    QUIET                   Quiet mode (true/false)
    DRY_RUN                 Dry run mode (true/false)

Examples:
    # Standard removal with confirmations
    sudo $0

    # Force removal without prompts
    sudo $0 --force

    # Remove everything except user data
    sudo $0 --force --preserve-data

    # Show what would be removed without doing it
    sudo $0 --dry-run

    # Quiet removal
    sudo $0 --quiet --force

This script will remove:
  • All VPN-related systemd services
  • All VPN Docker containers, networks, and volumes
  • Python virtual environments and packages
  • Configuration files and directories
  • Log files and temporary files
  • Binary files and executables
  • Database files (unless --preserve-data is used)
  • Cron jobs and systemd timers
  • Shell integrations and completions
  • Firewall rules for VPN ports
  • Python cache files
EOF
}

# Main cleanup function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_REMOVE=true
                shift
                ;;
            -p|--preserve-data)
                PRESERVE_DATA=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    log "Starting complete Python VPN service removal..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Check privileges
    check_privileges
    
    # Confirm destructive operation
    if [[ "$FORCE_REMOVE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo
        warn "This will completely remove the Python VPN service and all related components."
        if [[ "$PRESERVE_DATA" != "true" ]]; then
            warn "This includes user data, configurations, and databases."
        fi
        echo
        if ! confirm_action "Are you sure you want to continue?"; then
            log "Operation cancelled by user."
            exit 0
        fi
    fi
    
    # Perform cleanup operations
    remove_systemd_services
    remove_docker_containers
    remove_python_environments
    remove_configuration_files
    remove_log_files
    remove_binaries
    remove_databases
    remove_scheduled_tasks
    remove_shell_integrations
    remove_firewall_rules
    remove_temp_files
    remove_python_cache
    
    # Show summary
    if [[ "$DRY_RUN" != "true" ]]; then
        show_summary
    else
        log "Dry run completed. Use without --dry-run to actually perform the cleanup."
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi