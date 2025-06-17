#!/bin/bash

# =============================================================================
# VPN Server Installation Script (Modular Version)
# 
# This script installs and configures a VPN server using Xray with VLESS+Reality
# or Outline VPN protocols. It has been refactored to use modular architecture.
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
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "Error: Cannot source lib/common.sh"
    exit 1
}

source "$SCRIPT_DIR/lib/config.sh" || {
    error "Cannot source lib/config.sh"
}

source "$SCRIPT_DIR/lib/network.sh" || {
    error "Cannot source lib/network.sh"
}

source "$SCRIPT_DIR/lib/crypto.sh" || {
    error "Cannot source lib/crypto.sh"
}

source "$SCRIPT_DIR/lib/ui.sh" || {
    error "Cannot source lib/ui.sh"
}

# Source installation modules
source "$SCRIPT_DIR/modules/install/prerequisites.sh" || {
    error "Cannot source modules/install/prerequisites.sh"
}

source "$SCRIPT_DIR/modules/install/docker_setup.sh" || {
    error "Cannot source modules/install/docker_setup.sh"
}

source "$SCRIPT_DIR/modules/install/xray_config.sh" || {
    error "Cannot source modules/install/xray_config.sh"
}

source "$SCRIPT_DIR/modules/install/firewall.sh" || {
    error "Cannot source modules/install/firewall.sh"
}

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

WORK_DIR="/opt/v2ray"
SERVER_IP=""
SERVER_PORT=""
SERVER_SNI=""
PROTOCOL=""
USE_REALITY=false
USER_NAME=""
USER_UUID=""
PRIVATE_KEY=""
PUBLIC_KEY=""
SHORT_ID=""

# =============================================================================
# USER INTERACTION FUNCTIONS
# =============================================================================

# Choose VPN server type
choose_vpn_type() {
    echo -e "${BLUE}Выберите тип VPN сервера:${NC}"
    echo "1) Xray VPN (VLESS+Reality) - Рекомендуется"
    echo "2) Xray VPN (VLESS Basic)"
    echo "3) Outline VPN (Shadowsocks)"
    
    while true; do
        read -p "Выберите вариант (1-3): " choice
        case $choice in
            1)
                PROTOCOL="vless-reality"
                USE_REALITY=true
                log "Выбран протокол: VLESS+Reality"
                break
                ;;
            2)
                PROTOCOL="vless-basic"
                USE_REALITY=false
                log "Выбран протокол: VLESS Basic"
                break
                ;;
            3)
                PROTOCOL="outline"
                USE_REALITY=false
                log "Выбран протокол: Outline (Shadowsocks)"
                break
                ;;
            *)
                warning "Пожалуйста, выберите 1, 2 или 3"
                ;;
        esac
    done
}

# Get server configuration
get_server_config() {
    # Get external IP
    SERVER_IP=$(get_external_ip)
    if [ -z "$SERVER_IP" ]; then
        read -p "Не удалось определить внешний IP. Введите IP адрес сервера: " SERVER_IP
    fi
    log "Внешний IP сервера: $SERVER_IP"
    
    # Get server port
    echo -e "${BLUE}Выберите порт сервера:${NC}"
    echo "1) Автоматический выбор свободного порта (10000-65000) - Рекомендуется"
    echo "2) Ввести порт вручную"
    echo "3) Использовать стандартный порт (10443)"
    
    while true; do
        read -p "Выберите вариант (1-3): " port_choice
        case $port_choice in
            1)
                SERVER_PORT=$(generate_free_port 10000 65000 true 20 10443)
                log "Автоматически выбран порт: $SERVER_PORT"
                break
                ;;
            2)
                read -p "Введите порт (1024-65535): " custom_port
                if validate_port "$custom_port" && check_port_available "$custom_port"; then
                    SERVER_PORT="$custom_port"
                    log "Выбран порт: $SERVER_PORT"
                    break
                else
                    warning "Порт недоступен или некорректен"
                fi
                ;;
            3)
                SERVER_PORT="10443"
                if check_port_available "$SERVER_PORT"; then
                    log "Использован стандартный порт: $SERVER_PORT"
                    break
                else
                    warning "Стандартный порт занят, выберите другой вариант"
                fi
                ;;
            *)
                warning "Пожалуйста, выберите 1, 2 или 3"
                ;;
        esac
    done
}

# Get user configuration
get_user_config() {
    # Generate UUID
    USER_UUID=$(generate_uuid)
    log "Сгенерирован UUID: $USER_UUID"
    
    # Get username
    read -p "Введите имя первого пользователя (по умолчанию: user1): " input_name
    USER_NAME="${input_name:-user1}"
    log "Имя пользователя: $USER_NAME"
}

# Get SNI configuration for Reality
get_sni_config() {
    if [ "$USE_REALITY" != true ]; then
        return 0
    fi
    
    echo -e "${BLUE}Выберите домен для SNI (Server Name Indication):${NC}"
    echo "1) addons.mozilla.org - Рекомендуется"
    echo "2) www.lovelive-anime.jp"
    echo "3) www.swift.org"
    echo "4) Ввести свой домен"
    echo "5) Автоматический выбор лучшего домена"
    
    local sni_domains=(
        "addons.mozilla.org"
        "www.lovelive-anime.jp"
        "www.swift.org"
    )
    
    while true; do
        read -p "Выберите вариант (1-5): " sni_choice
        case $sni_choice in
            1|2|3)
                local selected_domain="${sni_domains[$((sni_choice-1))]}"
                if check_sni_domain "$selected_domain"; then
                    SERVER_SNI="$selected_domain"
                    log "Выбран домен SNI: $SERVER_SNI"
                    break
                else
                    warning "Домен недоступен, попробуйте другой"
                fi
                ;;
            4)
                read -p "Введите домен: " custom_domain
                if check_sni_domain "$custom_domain"; then
                    SERVER_SNI="$custom_domain"
                    log "Выбран пользовательский домен: $SERVER_SNI"
                    break
                else
                    warning "Домен недоступен или некорректен"
                fi
                ;;
            5)
                log "Поиск лучшего домена..."
                for domain in "${sni_domains[@]}"; do
                    if check_sni_domain "$domain"; then
                        SERVER_SNI="$domain"
                        log "Автоматически выбран домен: $SERVER_SNI"
                        break
                    fi
                done
                if [ -n "$SERVER_SNI" ]; then
                    break
                else
                    warning "Не удалось найти доступный домен"
                fi
                ;;
            *)
                warning "Пожалуйста, выберите 1-5"
                ;;
        esac
    done
}

# Generate Reality keys
generate_reality_keys() {
    if [ "$USE_REALITY" != true ]; then
        return 0
    fi
    
    log "Генерация ключей Reality..."
    
    # Generate keys using crypto library
    local keys=$(generate_reality_keypair)
    PRIVATE_KEY=$(echo "$keys" | cut -d' ' -f1)
    PUBLIC_KEY=$(echo "$keys" | cut -d' ' -f2)
    
    # Generate short ID
    SHORT_ID=$(generate_short_id)
    
    log "Ключи Reality сгенерированы"
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

# Install Xray VPN
install_xray_vpn() {
    log "Установка Xray VPN..."
    
    # Setup directories
    setup_xray_directories "$WORK_DIR" true || {
        error "Failed to setup Xray directories"
    }
    
    # Create configuration
    setup_xray_configuration "$WORK_DIR" "$PROTOCOL" "$SERVER_PORT" "$USER_UUID" \
        "$USER_NAME" "$SERVER_IP" "$SERVER_SNI" "$PRIVATE_KEY" "$PUBLIC_KEY" \
        "$SHORT_ID" true || {
        error "Failed to create Xray configuration"
    }
    
    # Setup Docker environment
    setup_docker_environment "$WORK_DIR" "$SERVER_PORT" true || {
        error "Failed to setup Docker environment"
    }
    
    # Configure firewall
    setup_xray_firewall "$SERVER_PORT" true || {
        error "Failed to configure firewall"
    }
    
    log "Xray VPN установлен успешно"
}

# Install Outline VPN (placeholder - would need full implementation)
install_outline_vpn() {
    warning "Outline VPN installation not implemented in modular version"
    warning "Please use the original script for Outline VPN"
    return 1
}

# =============================================================================
# POST-INSTALLATION
# =============================================================================

# Show client information
show_client_info() {
    echo -e "\n${GREEN}=== ИНФОРМАЦИЯ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
    echo -e "${BLUE}Сервер:${NC} $SERVER_IP"
    echo -e "${BLUE}Порт:${NC} $SERVER_PORT"
    echo -e "${BLUE}Протокол:${NC} $PROTOCOL"
    echo -e "${BLUE}Пользователь:${NC} $USER_NAME"
    
    if [ "$USE_REALITY" = true ]; then
        echo -e "${BLUE}SNI:${NC} $SERVER_SNI"
        echo -e "${BLUE}Public Key:${NC} $PUBLIC_KEY"
        echo -e "${BLUE}Short ID:${NC} $SHORT_ID"
    fi
    
    # Show connection link
    if [ -f "$WORK_DIR/users/$USER_NAME.link" ]; then
        echo -e "\n${GREEN}Ссылка для подключения:${NC}"
        cat "$WORK_DIR/users/$USER_NAME.link"
        echo
    fi
    
    # Show QR code location
    if [ -f "$WORK_DIR/users/$USER_NAME.png" ]; then
        echo -e "${GREEN}QR-код сохранен:${NC} $WORK_DIR/users/$USER_NAME.png"
    fi
}

# Setup management script
setup_management() {
    log "Настройка управления..."
    
    # Create management script symlink
    if [ -f "$SCRIPT_DIR/manage_users.sh" ]; then
        ln -sf "$SCRIPT_DIR/manage_users.sh" /usr/local/bin/v2ray-manage 2>/dev/null || {
            warning "Failed to create management script symlink"
        }
        log "Скрипт управления доступен через: v2ray-manage"
    fi
}

# =============================================================================
# MAIN INSTALLATION FLOW
# =============================================================================

main() {
    # Welcome message
    echo -e "${GREEN}=== VPN Server Installation (Modular Version) ===${NC}"
    echo -e "${BLUE}Версия: 2.0${NC}\n"
    
    # Check prerequisites
    log "Проверка системных требований..."
    check_root_privileges true || exit 1
    detect_system_info true
    
    # Install dependencies
    log "Установка зависимостей..."
    install_system_dependencies true || {
        error "Failed to install system dependencies"
    }
    
    verify_dependencies true || {
        error "Dependency verification failed"
    }
    
    # Get configuration
    choose_vpn_type
    get_server_config
    get_user_config
    get_sni_config
    generate_reality_keys
    
    # Install VPN based on chosen protocol
    case "$PROTOCOL" in
        "vless-reality"|"vless-basic")
            install_xray_vpn
            ;;
        "outline")
            install_outline_vpn
            ;;
        *)
            error "Unknown protocol: $PROTOCOL"
            ;;
    esac
    
    # Post-installation setup
    setup_management
    
    # Show results
    echo -e "\n${GREEN}=== УСТАНОВКА ЗАВЕРШЕНА ===${NC}"
    show_client_info
    
    echo -e "\n${YELLOW}Для управления пользователями используйте:${NC}"
    echo -e "${WHITE}sudo v2ray-manage${NC}"
    
    echo -e "\n${GREEN}Установка VPN сервера завершена успешно!${NC}"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi