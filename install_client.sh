#!/bin/bash

# =============================================================================
# VPN Client Installation Script (Modular Version)
# 
# This script installs VLESS client with v2rayA Web UI in Docker.
# Supports Ubuntu, Debian, ALT Linux with modular architecture.
#
# Author: Claude
# Version: 2.0 (Modular)
# =============================================================================

set -e

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || {
    # Fallback definitions if libraries are not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
    
    log() { echo -e "${GREEN}✓${NC} $1"; }
    error() { echo -e "${RED}✗ [ERROR]${NC} $1"; exit 1; }
    warning() { echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"; }
    info() { echo -e "${BLUE}ℹ️  [INFO]${NC} $1"; }
}

# Try to source Docker utilities
if [ -f "$SCRIPT_DIR/lib/docker.sh" ]; then
    source "$SCRIPT_DIR/lib/docker.sh"
fi

# Try to source prerequisites module
if [ -f "$SCRIPT_DIR/modules/install/prerequisites.sh" ]; then
    source "$SCRIPT_DIR/modules/install/prerequisites.sh"
fi

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

WORK_DIR="/opt/v2raya"
CLIENT_VERSION="2.2.5"
WEB_PORT="2017"
SOCKS_PORT="20170"
HTTP_PORT="20171"
MIXED_PORT="20172"

# OS Detection variables
OS_NAME=""
OS_VERSION=""
OS_PRETTY_NAME=""

# =============================================================================
# SYSTEM DETECTION
# =============================================================================

# Detect operating system
detect_os() {
    log "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$(echo ${ID} | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$VERSION_ID
        OS_PRETTY_NAME=$PRETTY_NAME
    else
        error "Cannot detect operating system"
    fi
    
    log "Detected OS: $OS_PRETTY_NAME"
    
    # Validate supported OS
    case "$OS_NAME" in
        ubuntu|debian|alt)
            log "Supported operating system detected"
            ;;
        *)
            warning "Operating system may not be fully supported: $OS_NAME"
            ;;
    esac
}

# =============================================================================
# DEPENDENCY MANAGEMENT
# =============================================================================

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    # Use modular prerequisites if available
    if command -v install_system_dependencies >/dev/null 2>&1; then
        install_system_dependencies true
        return $?
    fi
    
    # Fallback to basic installation
    case "$OS_NAME" in
        ubuntu|debian)
            apt update
            apt install -y curl wget gnupg2 software-properties-common
            ;;
        alt)
            apt-get update
            apt-get install -y curl wget gnupg2
            ;;
        *)
            error "Unsupported package manager for OS: $OS_NAME"
            ;;
    esac
    
    # Install Docker
    if ! command -v docker >/dev/null 2>&1; then
        log "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        rm -f get-docker.sh
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        log "Installing Docker Compose..."
        local compose_version="v2.20.3"
        curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
}

# =============================================================================
# CLIENT INSTALLATION
# =============================================================================

# Create client directories
setup_client_directories() {
    log "Setting up client directories..."
    
    mkdir -p "$WORK_DIR"
    mkdir -p "$WORK_DIR/config"
    mkdir -p "$WORK_DIR/logs"
    
    # Set appropriate permissions
    chmod 755 "$WORK_DIR" "$WORK_DIR/config" "$WORK_DIR/logs"
    
    log "Client directories created"
}

# Create Docker Compose configuration
create_docker_compose() {
    log "Creating Docker Compose configuration..."
    
    # Use modular Docker utilities if available
    if command -v calculate_resource_limits >/dev/null 2>&1; then
        calculate_resource_limits true
    else
        # Fallback resource limits
        MAX_CPU="1.0"
        RESERVE_CPU="0.1"
        MAX_MEM="512m"
        RESERVE_MEM="128m"
    fi
    
    cat > "$WORK_DIR/docker-compose.yml" <<EOL
version: '3.8'
services:
  v2raya:
    image: mzz2017/v2raya:latest
    container_name: v2raya
    restart: unless-stopped
    network_mode: bridge
    ports:
      - "${WEB_PORT}:2017"
      - "${SOCKS_PORT}:20170"
      - "${HTTP_PORT}:20171"
      - "${MIXED_PORT}:20172"
    volumes:
      - ./config:/etc/v2raya
      - ./logs:/var/log/v2raya
    environment:
      - V2RAYA_ADDRESS=0.0.0.0:2017
      - V2RAYA_CONFIG=/etc/v2raya
      - V2RAYA_PLUGINLISTENPORT=32346
      - V2RAYA_VLESSGRPCPORT=32347
      - V2RAYA_VERBOSE=info
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:2017/api/version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '$MAX_CPU'
          memory: $MAX_MEM
        reservations:
          cpus: '$RESERVE_CPU'
          memory: $RESERVE_MEM
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOL
    
    log "Docker Compose configuration created"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Use modular firewall utilities if available
    if command -v setup_basic_firewall >/dev/null 2>&1; then
        setup_basic_firewall true
    else
        # Fallback firewall configuration
        if command -v ufw >/dev/null 2>&1; then
            # Ensure SSH is allowed
            if ! ufw status | grep -q "22/tcp\|OpenSSH\|ssh"; then
                ufw allow ssh
            fi
            
            # Allow v2rayA web interface
            ufw allow "$WEB_PORT/tcp"
            
            # Enable firewall if not active
            if ! ufw status | grep -q "Status: active"; then
                ufw --force enable
            fi
        fi
    fi
    
    log "Firewall configured"
}

# Start client services
start_client() {
    log "Starting v2rayA client..."
    
    cd "$WORK_DIR"
    
    # Start services
    if ! docker-compose up -d; then
        error "Failed to start v2rayA client"
    fi
    
    # Wait for startup
    sleep 5
    
    # Verify client is running
    if docker ps | grep -q "v2raya"; then
        log "v2rayA client started successfully"
    else
        error "v2rayA client failed to start"
    fi
}

# =============================================================================
# CLIENT MANAGEMENT
# =============================================================================

# Check if client is already installed
check_existing_installation() {
    if [ -d "$WORK_DIR" ]; then
        if docker ps | grep -q "v2raya"; then
            return 0  # Running
        elif docker ps -a | grep -q "v2raya"; then
            return 1  # Installed but not running
        else
            return 2  # Directory exists but no container
        fi
    else
        return 3  # Not installed
    fi
}

# Show client status
show_client_status() {
    echo -e "\n${GREEN}=== v2rayA Client Status ===${NC}"
    
    if docker ps | grep -q "v2raya"; then
        echo -e "${GREEN}Status: Running${NC}"
        echo -e "${BLUE}Web Interface: http://localhost:$WEB_PORT${NC}"
        echo -e "${BLUE}SOCKS5 Proxy: 127.0.0.1:$SOCKS_PORT${NC}"
        echo -e "${BLUE}HTTP Proxy: 127.0.0.1:$HTTP_PORT${NC}"
        echo -e "${BLUE}Mixed Proxy: 127.0.0.1:$MIXED_PORT${NC}"
        
        # Show container stats
        echo -e "\n${YELLOW}Container Statistics:${NC}"
        docker stats --no-stream v2raya 2>/dev/null || true
    else
        echo -e "${RED}Status: Not Running${NC}"
    fi
}

# Uninstall client
uninstall_client() {
    log "Uninstalling v2rayA client..."
    
    # Stop and remove container
    if docker ps -a | grep -q "v2raya"; then
        docker stop v2raya 2>/dev/null || true
        docker rm v2raya 2>/dev/null || true
    fi
    
    # Remove Docker image
    if docker images | grep -q "mzz2017/v2raya"; then
        docker rmi mzz2017/v2raya:latest 2>/dev/null || true
    fi
    
    # Remove client directory
    if [ -d "$WORK_DIR" ]; then
        echo -e "${YELLOW}Remove client configuration and data? [y/N]${NC}"
        read -p "Remove data: " remove_data
        if [[ "$remove_data" =~ ^[Yy]$ ]]; then
            rm -rf "$WORK_DIR"
            log "Client data removed"
        fi
    fi
    
    # Remove firewall rules
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow "$WEB_PORT/tcp" 2>/dev/null || true
    fi
    
    log "v2rayA client uninstalled"
}

# =============================================================================
# MENU SYSTEM
# =============================================================================

# Show main menu
show_menu() {
    clear
    echo -e "${GREEN}=== v2rayA VPN Client Manager (Modular Version) ===${NC}"
    echo -e "${BLUE}Version: 2.0${NC}\n"
    
    local status
    check_existing_installation
    status=$?
    
    case $status in
        0)
            echo -e "${GREEN}Current Status: Client is running${NC}\n"
            echo "1) 📊 Show Client Status"
            echo "2) 🔄 Restart Client"
            echo "3) ⏹️  Stop Client"
            echo "4) 🗑️  Uninstall Client"
            echo "5) 🌐 Open Web Interface"
            ;;
        1)
            echo -e "${YELLOW}Current Status: Client installed but not running${NC}\n"
            echo "1) ▶️  Start Client"
            echo "2) 📊 Show Client Status"
            echo "3) 🗑️  Uninstall Client"
            ;;
        2|3)
            echo -e "${RED}Current Status: Client not installed${NC}\n"
            echo "1) 📥 Install Client"
            ;;
    esac
    
    echo "0) 🚪 Exit"
    echo
}

# Handle menu selection
handle_menu() {
    local status
    check_existing_installation
    status=$?
    
    case $status in
        0)  # Running
            case $1 in
                1) show_client_status ;;
                2) 
                    cd "$WORK_DIR"
                    docker-compose restart
                    log "Client restarted"
                    ;;
                3) 
                    cd "$WORK_DIR"
                    docker-compose stop
                    log "Client stopped"
                    ;;
                4) uninstall_client ;;
                5) 
                    info "Opening web interface at http://localhost:$WEB_PORT"
                    if command -v xdg-open >/dev/null 2>&1; then
                        xdg-open "http://localhost:$WEB_PORT" 2>/dev/null &
                    fi
                    ;;
                0) exit 0 ;;
                *) warning "Invalid option" ;;
            esac
            ;;
        1)  # Installed but not running
            case $1 in
                1) 
                    cd "$WORK_DIR"
                    docker-compose start
                    log "Client started"
                    ;;
                2) show_client_status ;;
                3) uninstall_client ;;
                0) exit 0 ;;
                *) warning "Invalid option" ;;
            esac
            ;;
        2|3)  # Not installed
            case $1 in
                1) install_client ;;
                0) exit 0 ;;
                *) warning "Invalid option" ;;
            esac
            ;;
    esac
}

# =============================================================================
# INSTALLATION PROCESS
# =============================================================================

# Main installation function
install_client() {
    log "Starting v2rayA client installation..."
    
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script with superuser privileges (sudo)"
    fi
    
    # Detect OS
    detect_os
    
    # Install dependencies
    install_dependencies
    
    # Setup client
    setup_client_directories
    create_docker_compose
    configure_firewall
    start_client
    
    # Show results
    echo -e "\n${GREEN}=== Installation Complete ===${NC}"
    show_client_status
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. Open web interface: http://localhost:$WEB_PORT"
    echo "2. Import your VLESS connection link"
    echo "3. Configure proxy settings in your browser/applications:"
    echo "   - SOCKS5: 127.0.0.1:$SOCKS_PORT"
    echo "   - HTTP: 127.0.0.1:$HTTP_PORT"
    
    log "v2rayA client installation completed"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Interactive mode if no arguments
    if [ $# -eq 0 ]; then
        while true; do
            show_menu
            read -p "Select option: " choice
            handle_menu "$choice"
            if [ "$choice" != "0" ]; then
                echo
                read -p "Press Enter to continue..."
            fi
        done
    else
        # Command line mode
        case "$1" in
            install)
                install_client
                ;;
            status)
                show_client_status
                ;;
            uninstall)
                uninstall_client
                ;;
            *)
                echo "Usage: $0 [install|status|uninstall]"
                echo "  install    Install v2rayA client"
                echo "  status     Show client status"
                echo "  uninstall  Uninstall client"
                echo ""
                echo "Run without arguments for interactive mode"
                exit 1
                ;;
        esac
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi