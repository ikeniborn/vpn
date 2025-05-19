#!/bin/bash

# ===================================================================
# VLESS-Reality Tunnel Uninstall Script
# ===================================================================
# This script:
# - Safely removes VLESS+Reality tunnel components
# - Restores system configurations
# - Can handle both Server 1 and Server 2 uninstallation
# - Provides options for complete or partial removal
# ===================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
SERVER_TYPE=""
REMOVE_OUTLINE=false
REMOVE_V2RAY=false
RESET_IPTABLES=false
V2RAY_DIR="/opt/v2ray"
OUTLINE_DIR="/opt/outline"
FORCE=false

# Function to display status messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to display usage
display_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script safely removes VLESS+Reality tunnel components and restores system configurations.

Required Options:
  --server-type TYPE       Specify "server1" or "server2"

Optional Options:
  --remove-outline         Remove Outline VPN (Server 2 only)
  --remove-v2ray           Remove VLESS+Reality components
  --reset-iptables         Reset all iptables rules (use with caution)
  --force                  Skip confirmation prompts
  --help                   Display this help message

Examples:
  $(basename "$0") --server-type server1 --remove-v2ray
  $(basename "$0") --server-type server2 --remove-outline --remove-v2ray

EOF
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root or with sudo privileges"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --server-type)
                SERVER_TYPE="$2"
                shift
                ;;
            --remove-outline)
                REMOVE_OUTLINE=true
                ;;
            --remove-v2ray)
                REMOVE_V2RAY=true
                ;;
            --reset-iptables)
                RESET_IPTABLES=true
                ;;
            --force)
                FORCE=true
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

    # Check required parameters
    if [ -z "$SERVER_TYPE" ]; then
        error "Server type is required. Use --server-type option."
    fi

    if [ "$SERVER_TYPE" != "server1" ] && [ "$SERVER_TYPE" != "server2" ]; then
        error "Server type must be 'server1' or 'server2'."
    fi

    # If nothing to remove is specified, show warning
    if ! $REMOVE_OUTLINE && ! $REMOVE_V2RAY && ! $RESET_IPTABLES; then
        warn "No removal actions specified. Use --remove-outline, --remove-v2ray, or --reset-iptables."
        warn "Running in information-only mode. No changes will be made."
    fi

    # Server 1 cannot remove Outline
    if [ "$SERVER_TYPE" == "server1" ] && $REMOVE_OUTLINE; then
        warn "Server 1 does not have Outline VPN. Ignoring --remove-outline option."
        REMOVE_OUTLINE=false
    fi

    info "Uninstall configuration:"
    info "- Server type: $SERVER_TYPE"
    info "- Remove Outline VPN: $REMOVE_OUTLINE"
    info "- Remove VLESS+Reality: $REMOVE_V2RAY"
    info "- Reset iptables rules: $RESET_IPTABLES"
}

# Confirm uninstallation
confirm_uninstall() {
    if $FORCE; then
        return 0
    fi

    local actions=""
    if $REMOVE_V2RAY; then
        actions="${actions}VLESS+Reality components, "
    fi
    if $REMOVE_OUTLINE; then
        actions="${actions}Outline VPN, "
    fi
    if $RESET_IPTABLES; then
        actions="${actions}iptables rules, "
    fi

    # Trim trailing comma and space
    actions="${actions%, }"

    if [ -n "$actions" ]; then
        echo ""
        echo "====================================================================="
        echo "WARNING: This will remove the following from $SERVER_TYPE:"
        echo "- $actions"
        echo "====================================================================="
        echo ""
        read -p "Are you sure you want to proceed? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            info "Uninstallation cancelled."
            exit 0
        fi
    else
        info "Information-only mode. No changes will be made."
    fi
}

# Stop and remove Docker containers
remove_containers() {
    info "Checking for Docker containers to remove..."

    if [ "$SERVER_TYPE" == "server1" ]; then
        # Server 1 containers
        if $REMOVE_V2RAY; then
            if docker ps -a --format '{{.Names}}' | grep -q "^v2ray$"; then
                info "Removing v2ray container..."
                docker stop v2ray || warn "Failed to stop v2ray container"
                docker rm v2ray || warn "Failed to remove v2ray container"
            else
                info "v2ray container not found."
            fi
        fi
    else
        # Server 2 containers
        if $REMOVE_V2RAY; then
            if docker ps -a --format '{{.Names}}' | grep -q "^v2ray-client$"; then
                info "Removing v2ray-client container..."
                docker stop v2ray-client || warn "Failed to stop v2ray-client container"
                docker rm v2ray-client || warn "Failed to remove v2ray-client container"
            else
                info "v2ray-client container not found."
            fi
        fi

        if $REMOVE_OUTLINE; then
            # Check if Outline is installed
            if [ -d "$OUTLINE_DIR" ] && [ -f "$OUTLINE_DIR/docker-compose.yml" ]; then
                info "Stopping Outline VPN containers..."
                cd "$OUTLINE_DIR"
                
                # Try to use docker-compose to stop and remove containers
                if command -v docker-compose &> /dev/null; then
                    docker-compose down || warn "Failed to stop Outline containers with docker-compose"
                elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
                    docker compose down || warn "Failed to stop Outline containers with docker compose"
                else
                    warn "Neither docker-compose nor docker compose plugin found. Trying to stop containers manually."
                    docker stop outline-server watchtower shadowbox || warn "Failed to stop some Outline containers"
                    docker rm outline-server watchtower shadowbox || warn "Failed to remove some Outline containers"
                fi
            else
                warn "Outline installation not found at $OUTLINE_DIR"
            fi
        fi
    fi
}

# Remove systemd services
remove_services() {
    info "Removing systemd services..."

    if [ "$SERVER_TYPE" == "server1" ]; then
        # Server 1 services - typically none specific to tunnel
        info "No specific tunnel services to remove on Server 1."
    else
        # Server 2 services
        local services=()
        if $REMOVE_V2RAY; then
            services+=("v2ray-tunnel.service" "tunnel-routing.service")
        fi
        if $REMOVE_OUTLINE; then
            services+=("outline-tunnel-routing.service")
        fi

        for service in "${services[@]}"; do
            if systemctl list-unit-files | grep -q "$service"; then
                info "Stopping and disabling $service..."
                systemctl stop "$service" || warn "Failed to stop $service"
                systemctl disable "$service" || warn "Failed to disable $service"
                rm -f "/etc/systemd/system/$service" || warn "Failed to remove $service file"
            else
                info "$service not found."
            fi
        done

        systemctl daemon-reload
    fi
}

# Remove configuration files
remove_files() {
    info "Removing configuration files..."

    if $REMOVE_V2RAY; then
        if [ -d "$V2RAY_DIR" ]; then
            # Create backup
            local backup_dir="${V2RAY_DIR}_backup_$(date +%Y%m%d%H%M%S)"
            info "Creating backup of $V2RAY_DIR to $backup_dir..."
            cp -r "$V2RAY_DIR" "$backup_dir" || warn "Failed to create backup of $V2RAY_DIR"
            
            # Remove directory
            info "Removing $V2RAY_DIR..."
            rm -rf "$V2RAY_DIR" || warn "Failed to remove $V2RAY_DIR"
        else
            info "v2ray directory not found at $V2RAY_DIR"
        fi
    fi

    if [ "$SERVER_TYPE" == "server2" ] && $REMOVE_OUTLINE; then
        if [ -d "$OUTLINE_DIR" ]; then
            # Create backup
            local backup_dir="${OUTLINE_DIR}_backup_$(date +%Y%m%d%H%M%S)"
            info "Creating backup of $OUTLINE_DIR to $backup_dir..."
            cp -r "$OUTLINE_DIR" "$backup_dir" || warn "Failed to create backup of $OUTLINE_DIR"
            
            # Remove directory
            info "Removing $OUTLINE_DIR..."
            rm -rf "$OUTLINE_DIR" || warn "Failed to remove $OUTLINE_DIR"
        else
            info "Outline directory not found at $OUTLINE_DIR"
        fi
    fi

    # Remove scripts that might have been created
    local script_files=(
        "/usr/local/bin/setup-tunnel-routing.sh"
        "/usr/local/bin/outline-tunnel-routing.sh"
    )

    for script in "${script_files[@]}"; do
        if [ -f "$script" ]; then
            info "Removing $script..."
            rm -f "$script" || warn "Failed to remove $script"
        fi
    done
}

# Reset iptables rules
reset_iptables() {
    if ! $RESET_IPTABLES; then
        return
    fi

    info "Resetting iptables rules..."

    if [ "$SERVER_TYPE" == "server1" ]; then
        # Reset NAT masquerading on Server 1
        if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
            # Backup UFW before.rules
            cp /etc/ufw/before.rules /etc/ufw/before.rules.bak || warn "Failed to backup before.rules"
            
            # Remove masquerading rules
            if grep -q "MASQUERADE" /etc/ufw/before.rules; then
                info "Removing masquerading rules from UFW..."
                sed -i '/POSTROUTING -o .* -j MASQUERADE/d' /etc/ufw/before.rules || warn "Failed to remove masquerading rules"
                ufw reload || warn "Failed to reload UFW"
            fi
        else
            # Clear NAT table
            info "Clearing iptables NAT masquerading rules..."
            iptables -t nat -D POSTROUTING -o "$(ip -4 route show default | awk '{print $5}' | head -n1)" -j MASQUERADE 2>/dev/null || true
            
            # Save iptables rules
            if command -v iptables-save &> /dev/null; then
                iptables-save > /etc/iptables/rules.v4 || warn "Failed to save iptables rules"
            fi
        fi
    else
        # Reset Server 2 iptables rules
        info "Clearing iptables tunnel routing rules..."
        
        # Clean up NAT table
        iptables -t nat -F V2RAY 2>/dev/null || true
        iptables -t nat -D PREROUTING -p tcp -j V2RAY 2>/dev/null || true
        iptables -t nat -X V2RAY 2>/dev/null || true
        
        # Clean up mangle table
        iptables -t mangle -F V2RAY 2>/dev/null || true
        iptables -t mangle -F V2RAY_MARK 2>/dev/null || true
        iptables -t mangle -X V2RAY 2>/dev/null || true
        iptables -t mangle -X V2RAY_MARK 2>/dev/null || true
        
        # Remove Outline masquerading rules
        iptables -t nat -D POSTROUTING -o lo -s 10.0.0.0/24 -j MASQUERADE 2>/dev/null || true
        
        # Save iptables rules
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 || warn "Failed to save iptables rules"
        fi
    fi
}

# Restore system configurations
restore_system_config() {
    info "Restoring system configurations..."

    # Disable IP forwarding if needed
    if $RESET_IPTABLES; then
        info "Disabling IP forwarding..."
        echo 0 > /proc/sys/net/ipv4/ip_forward || warn "Failed to disable IP forwarding"
        
        # Update sysctl.conf to disable IP forwarding on boot
        if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
            sed -i 's/^net.ipv4.ip_forward=1/net.ipv4.ip_forward=0/' /etc/sysctl.conf || warn "Failed to update sysctl.conf"
            sysctl -p || warn "Failed to apply sysctl changes"
        fi
    fi

    # Clean up Docker networks if necessary
    if $REMOVE_V2RAY; then
        if docker network ls | grep -q "v2ray-network"; then
            info "Removing Docker network: v2ray-network..."
            docker network rm v2ray-network || warn "Failed to remove Docker network"
        fi
    fi
}

# Display summary
display_summary() {
    echo ""
    echo "====================================================================="
    echo "Uninstallation Summary for $SERVER_TYPE"
    echo "====================================================================="
    
    if $REMOVE_V2RAY; then
        echo "- VLESS+Reality components removed"
    fi
    
    if $REMOVE_OUTLINE; then
        echo "- Outline VPN removed"
    fi
    
    if $RESET_IPTABLES; then
        echo "- iptables rules reset"
    fi
    
    echo ""
    if [ "$SERVER_TYPE" == "server1" ]; then
        echo "To remove the tunnel from Server 2, run this script on Server 2 as well."
    elif [ "$SERVER_TYPE" == "server2" ]; then
        echo "To remove the tunnel from Server 1, run this script on Server 1 as well."
    fi
    echo "====================================================================="
}

# Main function
main() {
    check_root
    parse_args "$@"
    confirm_uninstall
    
    if $REMOVE_V2RAY || $REMOVE_OUTLINE; then
        remove_containers
        remove_services
        remove_files
    fi
    
    if $RESET_IPTABLES; then
        reset_iptables
        restore_system_config
    fi
    
    display_summary
    
    if $REMOVE_V2RAY || $REMOVE_OUTLINE || $RESET_IPTABLES; then
        info "Uninstallation completed. You may need to reboot your system to fully apply changes."
    else
        info "Information gathering completed. No changes were made."
    fi
}

main "$@"