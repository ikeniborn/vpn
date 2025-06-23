#!/bin/bash

# =============================================================================
# Installation Progress Tracking and Rollback Module
# 
# This module provides installation progress tracking with checkpoint-based
# rollback capability for safe VPN installation.
#
# Functions exported:
# - init_installation_tracking()
# - track_progress()
# - create_checkpoint()
# - rollback_installation()
# - show_progress()
# - cleanup_installation()
#
# Dependencies: lib/common.sh
# =============================================================================

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Installation tracking directory
INSTALL_TRACKING_DIR="/var/lib/vpn-install"
PROGRESS_FILE="$INSTALL_TRACKING_DIR/progress.json"
CHECKPOINT_DIR="$INSTALL_TRACKING_DIR/checkpoints"
ROLLBACK_SCRIPT="$INSTALL_TRACKING_DIR/rollback.sh"
INSTALL_LOG="$INSTALL_TRACKING_DIR/installation.log"

# Installation steps
declare -A INSTALLATION_STEPS=(
    ["system_validation"]="System Requirements Validation"
    ["dependency_install"]="Dependency Installation"
    ["docker_setup"]="Docker Environment Setup"
    ["network_config"]="Network Configuration"
    ["firewall_setup"]="Firewall Configuration"
    ["vpn_install"]="VPN Server Installation"
    ["user_creation"]="Initial User Creation"
    ["service_start"]="Service Startup"
    ["verification"]="Installation Verification"
)

# Step weights for progress calculation
declare -A STEP_WEIGHTS=(
    ["system_validation"]=5
    ["dependency_install"]=15
    ["docker_setup"]=20
    ["network_config"]=10
    ["firewall_setup"]=10
    ["vpn_install"]=20
    ["user_creation"]=10
    ["service_start"]=5
    ["verification"]=5
)

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize installation tracking
init_installation_tracking() {
    local install_id="${1:-$(date +%Y%m%d_%H%M%S)}"
    local install_type="${2:-vpn}"
    
    log "Initializing installation tracking..."
    
    # Create tracking directory
    mkdir -p "$INSTALL_TRACKING_DIR" "$CHECKPOINT_DIR"
    
    # Initialize progress file
    cat > "$PROGRESS_FILE" <<EOF
{
    "install_id": "$install_id",
    "install_type": "$install_type",
    "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "in_progress",
    "current_step": "init",
    "completed_steps": [],
    "failed_steps": [],
    "checkpoints": [],
    "progress_percentage": 0,
    "rollback_available": false
}
EOF
    
    # Initialize installation log
    echo "=== VPN Installation Log ===" > "$INSTALL_LOG"
    echo "Install ID: $install_id" >> "$INSTALL_LOG"
    echo "Start Time: $(date)" >> "$INSTALL_LOG"
    echo "===========================" >> "$INSTALL_LOG"
    echo "" >> "$INSTALL_LOG"
    
    # Initialize rollback script
    cat > "$ROLLBACK_SCRIPT" <<'EOF'
#!/bin/bash
# VPN Installation Rollback Script
# Generated automatically - DO NOT EDIT

echo "Starting installation rollback..."

# Rollback will be populated as installation progresses
EOF
    chmod +x "$ROLLBACK_SCRIPT"
    
    success "Installation tracking initialized"
    return 0
}

# =============================================================================
# PROGRESS TRACKING
# =============================================================================

# Track installation progress
track_progress() {
    local step="$1"
    local status="${2:-started}"  # started, completed, failed
    local message="${3:-}"
    
    # Validate step
    if [ -z "${INSTALLATION_STEPS[$step]}" ]; then
        error "Unknown installation step: $step"
        return 1
    fi
    
    # Log progress
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $step: $status - $message" >> "$INSTALL_LOG"
    
    # Update progress file
    if [ -f "$PROGRESS_FILE" ]; then
        local temp_file=$(mktemp)
        
        # Read current progress
        local current_progress=$(cat "$PROGRESS_FILE")
        
        # Update based on status
        case "$status" in
            "started")
                # Update current step
                echo "$current_progress" | jq \
                    --arg step "$step" \
                    --arg desc "${INSTALLATION_STEPS[$step]}" \
                    '.current_step = $step | .current_step_description = $desc' \
                    > "$temp_file"
                ;;
                
            "completed")
                # Add to completed steps and calculate progress
                local completed_steps=$(echo "$current_progress" | jq -r '.completed_steps[]' | tr '\n' ' ')
                completed_steps="$completed_steps $step"
                
                # Calculate progress percentage
                local total_weight=0
                local completed_weight=0
                
                for s in "${!STEP_WEIGHTS[@]}"; do
                    total_weight=$((total_weight + ${STEP_WEIGHTS[$s]}))
                    if [[ " $completed_steps " =~ " $s " ]]; then
                        completed_weight=$((completed_weight + ${STEP_WEIGHTS[$s]}))
                    fi
                done
                
                local progress_percentage=$((completed_weight * 100 / total_weight))
                
                echo "$current_progress" | jq \
                    --arg step "$step" \
                    --argjson progress "$progress_percentage" \
                    '.completed_steps += [$step] | .progress_percentage = $progress' \
                    > "$temp_file"
                ;;
                
            "failed")
                # Add to failed steps and update status
                echo "$current_progress" | jq \
                    --arg step "$step" \
                    --arg msg "$message" \
                    '.failed_steps += [{"step": $step, "message": $msg}] | .status = "failed"' \
                    > "$temp_file"
                ;;
        esac
        
        # Save updated progress
        mv "$temp_file" "$PROGRESS_FILE"
    fi
    
    # Show progress if in interactive mode
    if [ -t 1 ]; then
        show_progress
    fi
    
    return 0
}

# =============================================================================
# CHECKPOINT MANAGEMENT
# =============================================================================

# Create installation checkpoint
create_checkpoint() {
    local checkpoint_name="$1"
    local description="${2:-Checkpoint}"
    
    log "Creating checkpoint: $checkpoint_name"
    
    local checkpoint_id="cp_$(date +%Y%m%d_%H%M%S)_${checkpoint_name}"
    local checkpoint_dir="$CHECKPOINT_DIR/$checkpoint_id"
    
    # Create checkpoint directory
    mkdir -p "$checkpoint_dir"
    
    # Save checkpoint metadata
    cat > "$checkpoint_dir/metadata.json" <<EOF
{
    "checkpoint_id": "$checkpoint_id",
    "checkpoint_name": "$checkpoint_name",
    "description": "$description",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "progress_state": $(cat "$PROGRESS_FILE")
}
EOF
    
    # Define what to backup based on checkpoint
    case "$checkpoint_name" in
        "pre_install")
            # Backup existing configurations if any
            [ -d "/opt/v2ray" ] && tar -czf "$checkpoint_dir/v2ray_backup.tar.gz" /opt/v2ray 2>/dev/null || true
            [ -d "/opt/outline" ] && tar -czf "$checkpoint_dir/outline_backup.tar.gz" /opt/outline 2>/dev/null || true
            
            # Backup firewall rules
            iptables-save > "$checkpoint_dir/iptables_backup.rules" 2>/dev/null || true
            [ -f "/etc/ufw/ufw.conf" ] && cp /etc/ufw/ufw.conf "$checkpoint_dir/ufw_backup.conf" 2>/dev/null || true
            ;;
            
        "post_dependencies")
            # List installed packages
            if command -v dpkg >/dev/null 2>&1; then
                dpkg -l > "$checkpoint_dir/installed_packages_dpkg.txt"
            elif command -v rpm >/dev/null 2>&1; then
                rpm -qa > "$checkpoint_dir/installed_packages_rpm.txt"
            fi
            ;;
            
        "post_docker")
            # Save Docker state
            docker ps -a > "$checkpoint_dir/docker_containers.txt" 2>/dev/null || true
            docker images > "$checkpoint_dir/docker_images.txt" 2>/dev/null || true
            ;;
            
        "post_network")
            # Save network configuration
            ip addr show > "$checkpoint_dir/ip_addresses.txt"
            ip route show > "$checkpoint_dir/ip_routes.txt"
            iptables-save > "$checkpoint_dir/iptables_current.rules"
            ;;
            
        "post_vpn_install")
            # Backup VPN configurations
            [ -d "/opt/v2ray/config" ] && cp -r /opt/v2ray/config "$checkpoint_dir/v2ray_config" 2>/dev/null || true
            [ -d "/opt/outline/config" ] && cp -r /opt/outline/config "$checkpoint_dir/outline_config" 2>/dev/null || true
            ;;
    esac
    
    # Update progress file with checkpoint
    if [ -f "$PROGRESS_FILE" ]; then
        local temp_file=$(mktemp)
        cat "$PROGRESS_FILE" | jq \
            --arg cp_id "$checkpoint_id" \
            '.checkpoints += [$cp_id] | .rollback_available = true' \
            > "$temp_file"
        mv "$temp_file" "$PROGRESS_FILE"
    fi
    
    # Add rollback commands to rollback script
    echo "" >> "$ROLLBACK_SCRIPT"
    echo "# Rollback from checkpoint: $checkpoint_name" >> "$ROLLBACK_SCRIPT"
    
    case "$checkpoint_name" in
        "post_vpn_install")
            cat >> "$ROLLBACK_SCRIPT" <<'EOF'
echo "Rolling back VPN installation..."
docker stop xray shadowbox 2>/dev/null || true
docker rm xray shadowbox 2>/dev/null || true
rm -rf /opt/v2ray /opt/outline 2>/dev/null || true
EOF
            ;;
            
        "post_docker")
            cat >> "$ROLLBACK_SCRIPT" <<'EOF'
echo "Rolling back Docker installation..."
# Note: We don't remove Docker as it might be used by other services
docker stop $(docker ps -q) 2>/dev/null || true
EOF
            ;;
            
        "post_network")
            if [ -f "$checkpoint_dir/iptables_backup.rules" ]; then
                echo "echo 'Restoring firewall rules...'" >> "$ROLLBACK_SCRIPT"
                echo "iptables-restore < '$checkpoint_dir/iptables_backup.rules' 2>/dev/null || true" >> "$ROLLBACK_SCRIPT"
            fi
            ;;
    esac
    
    success "Checkpoint created: $checkpoint_id"
    return 0
}

# =============================================================================
# ROLLBACK FUNCTIONALITY
# =============================================================================

# Rollback installation to previous state
rollback_installation() {
    local checkpoint_id="${1:-latest}"
    local force=${2:-false}
    
    log "Starting installation rollback..."
    
    # Check if rollback is available
    if [ -f "$PROGRESS_FILE" ]; then
        local rollback_available=$(jq -r '.rollback_available' "$PROGRESS_FILE" 2>/dev/null)
        if [ "$rollback_available" != "true" ] && [ "$force" != true ]; then
            error "No rollback points available"
            return 1
        fi
    else
        error "No installation tracking found"
        return 1
    fi
    
    # Get checkpoint to rollback to
    if [ "$checkpoint_id" = "latest" ]; then
        # Get latest checkpoint
        checkpoint_id=$(ls -t "$CHECKPOINT_DIR" | head -1)
        if [ -z "$checkpoint_id" ]; then
            error "No checkpoints found"
            return 1
        fi
    fi
    
    local checkpoint_dir="$CHECKPOINT_DIR/$checkpoint_id"
    if [ ! -d "$checkpoint_dir" ]; then
        error "Checkpoint not found: $checkpoint_id"
        return 1
    fi
    
    log "Rolling back to checkpoint: $checkpoint_id"
    
    # Execute rollback script
    if [ -f "$ROLLBACK_SCRIPT" ] && [ -x "$ROLLBACK_SCRIPT" ]; then
        log "Executing rollback script..."
        if bash "$ROLLBACK_SCRIPT"; then
            success "Rollback script executed"
        else
            error "Rollback script failed"
        fi
    fi
    
    # Restore from checkpoint
    local checkpoint_name=$(jq -r '.checkpoint_name' "$checkpoint_dir/metadata.json" 2>/dev/null)
    
    case "$checkpoint_name" in
        "pre_install")
            # Restore original configurations
            if [ -f "$checkpoint_dir/v2ray_backup.tar.gz" ]; then
                log "Restoring V2Ray configuration..."
                tar -xzf "$checkpoint_dir/v2ray_backup.tar.gz" -C / 2>/dev/null || true
            fi
            
            if [ -f "$checkpoint_dir/outline_backup.tar.gz" ]; then
                log "Restoring Outline configuration..."
                tar -xzf "$checkpoint_dir/outline_backup.tar.gz" -C / 2>/dev/null || true
            fi
            ;;
    esac
    
    # Update progress file
    if [ -f "$PROGRESS_FILE" ]; then
        local temp_file=$(mktemp)
        cat "$PROGRESS_FILE" | jq \
            --arg cp_id "$checkpoint_id" \
            '.status = "rolled_back" | .rolled_back_to = $cp_id | .end_time = now | .rollback_available = false' \
            > "$temp_file"
        mv "$temp_file" "$PROGRESS_FILE"
    fi
    
    success "Installation rolled back to checkpoint: $checkpoint_id"
    return 0
}

# =============================================================================
# PROGRESS DISPLAY
# =============================================================================

# Show installation progress
show_progress() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        return 0
    fi
    
    local progress_data=$(cat "$PROGRESS_FILE")
    local current_step=$(echo "$progress_data" | jq -r '.current_step')
    local progress_percentage=$(echo "$progress_data" | jq -r '.progress_percentage')
    local status=$(echo "$progress_data" | jq -r '.status')
    
    # Clear line and show progress
    printf "\r\033[K"
    
    # Progress bar
    local bar_length=30
    local filled_length=$((progress_percentage * bar_length / 100))
    local empty_length=$((bar_length - filled_length))
    
    printf "["
    printf "%${filled_length}s" | tr ' ' '='
    printf "%${empty_length}s" | tr ' ' '-'
    printf "] %3d%% " "$progress_percentage"
    
    # Current step
    if [ -n "$current_step" ] && [ "$current_step" != "null" ]; then
        local step_desc="${INSTALLATION_STEPS[$current_step]:-$current_step}"
        printf "- %s" "$step_desc"
    fi
    
    # Status indicator
    case "$status" in
        "completed")
            printf " ✅"
            ;;
        "failed")
            printf " ❌"
            ;;
        "in_progress")
            printf " ⏳"
            ;;
    esac
    
    # New line only if completed or failed
    if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
        echo ""
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

# Cleanup installation tracking
cleanup_installation() {
    local keep_logs=${1:-true}
    local keep_checkpoints=${2:-false}
    
    log "Cleaning up installation tracking..."
    
    if [ "$keep_logs" = true ]; then
        # Archive logs
        local archive_dir="/var/log/vpn-install-archives"
        mkdir -p "$archive_dir"
        
        if [ -f "$INSTALL_LOG" ]; then
            local install_id=$(jq -r '.install_id' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
            cp "$INSTALL_LOG" "$archive_dir/install_${install_id}.log"
        fi
    fi
    
    if [ "$keep_checkpoints" != true ]; then
        # Remove checkpoints
        rm -rf "$CHECKPOINT_DIR"
    fi
    
    # Remove tracking files
    rm -f "$PROGRESS_FILE" "$ROLLBACK_SCRIPT"
    
    success "Installation tracking cleaned up"
    return 0
}

# =============================================================================
# INSTALLATION WRAPPER
# =============================================================================

# Wrapper function to track any installation step
tracked_install_step() {
    local step_name="$1"
    local step_function="$2"
    shift 2
    local step_args=("$@")
    
    # Start tracking
    track_progress "$step_name" "started" "Executing ${INSTALLATION_STEPS[$step_name]}"
    
    # Execute step
    local result=0
    if $step_function "${step_args[@]}"; then
        track_progress "$step_name" "completed" "Successfully completed"
        
        # Create checkpoint after important steps
        case "$step_name" in
            "dependency_install")
                create_checkpoint "post_dependencies" "After dependency installation"
                ;;
            "docker_setup")
                create_checkpoint "post_docker" "After Docker setup"
                ;;
            "network_config")
                create_checkpoint "post_network" "After network configuration"
                ;;
            "vpn_install")
                create_checkpoint "post_vpn_install" "After VPN installation"
                ;;
        esac
    else
        result=$?
        track_progress "$step_name" "failed" "Step failed with error code: $result"
        
        # Ask user about rollback
        if [ -t 1 ]; then
            echo ""
            echo "Installation step failed. Would you like to:"
            echo "1) Retry the step"
            echo "2) Rollback to previous checkpoint"
            echo "3) Continue anyway"
            echo "4) Abort installation"
            
            read -p "Select option (1-4): " choice
            
            case "$choice" in
                1)
                    # Retry
                    tracked_install_step "$@"
                    return $?
                    ;;
                2)
                    # Rollback
                    rollback_installation
                    return 1
                    ;;
                3)
                    # Continue
                    warning "Continuing despite error..."
                    result=0
                    ;;
                4)
                    # Abort
                    error "Installation aborted"
                    return 1
                    ;;
            esac
        fi
    fi
    
    return $result
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f init_installation_tracking
export -f track_progress
export -f create_checkpoint
export -f rollback_installation
export -f show_progress
export -f cleanup_installation
export -f tracked_install_step

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

# If script is run directly, provide CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "init")
            init_installation_tracking "${2:-}" "${3:-vpn}"
            ;;
        "track")
            track_progress "$2" "${3:-started}" "${4:-}"
            ;;
        "checkpoint")
            create_checkpoint "$2" "${3:-Checkpoint}"
            ;;
        "rollback")
            rollback_installation "${2:-latest}" "${3:-false}"
            ;;
        "status")
            if [ -f "$PROGRESS_FILE" ]; then
                cat "$PROGRESS_FILE" | jq .
            else
                echo "No installation tracking found"
            fi
            ;;
        "cleanup")
            cleanup_installation "${2:-true}" "${3:-false}"
            ;;
        *)
            echo "Usage: $0 {init|track|checkpoint|rollback|status|cleanup}"
            echo ""
            echo "Commands:"
            echo "  init [id] [type]           - Initialize tracking"
            echo "  track <step> [status] [msg] - Track progress"
            echo "  checkpoint <name> [desc]    - Create checkpoint"
            echo "  rollback [checkpoint]       - Rollback installation"
            echo "  status                      - Show current status"
            echo "  cleanup [logs] [checkpoints] - Cleanup tracking"
            exit 1
            ;;
    esac
fi