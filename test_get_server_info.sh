#!/bin/bash

# Тест функции get_server_info из manage_users.sh

WORK_DIR="/opt/v2ray"
CONFIG_FILE="$WORK_DIR/config/config.json"
USERS_DIR="$WORK_DIR/users"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Копируем логику get_server_info из manage_users.sh
echo "=== Тест get_server_info ==="

SERVER_IP=$(curl -s https://api.ipify.org)
echo "SERVER_IP: $SERVER_IP"

if [ -f "$CONFIG_FILE" ]; then
    SERVER_PORT=$(jq '.inbounds[0].port' "$CONFIG_FILE")
    echo "SERVER_PORT: $SERVER_PORT"
    
    # Чтение SNI из файла, если он существует
    if [ -f "$WORK_DIR/config/sni.txt" ]; then
        SERVER_SNI=$(cat "$WORK_DIR/config/sni.txt")
        echo "SERVER_SNI из файла: $SERVER_SNI"
    else
        SERVER_SNI="www.microsoft.com"
        echo "SERVER_SNI по умолчанию: $SERVER_SNI"
    fi
    
    # Определение использования Reality - приоритет конфигурации JSON
    log "Проверка использования Reality..."
    SECURITY=$(jq -r '.inbounds[0].streamSettings.security' "$CONFIG_FILE")
    log "Найдена настройка security в конфиге: $SECURITY"
    
    if [ "$SECURITY" = "reality" ]; then
        USE_REALITY=true
        PROTOCOL="vless+reality"
        log "Установлено использование Reality из конфигурации"
        log "USE_REALITY = $USE_REALITY, PROTOCOL = $PROTOCOL"
    else
        USE_REALITY=false
        PROTOCOL="vless"
        log "Использование Reality отключено из конфигурации"
        log "USE_REALITY = $USE_REALITY, PROTOCOL = $PROTOCOL"
    fi
    
    echo "=== Результат ==="
    echo "USE_REALITY: $USE_REALITY"
    echo "PROTOCOL: $PROTOCOL"
    echo "SERVER_PORT: $SERVER_PORT"
    echo "SERVER_SNI: $SERVER_SNI"
    
    # Проверяем ключи
    if [ "$USE_REALITY" = true ]; then
        if [ -f "$WORK_DIR/config/public_key.txt" ]; then
            PUBLIC_KEY=$(cat "$WORK_DIR/config/public_key.txt")
            echo "PUBLIC_KEY: $PUBLIC_KEY"
        fi
        
        if [ -f "$WORK_DIR/config/short_id.txt" ]; then
            SHORT_ID=$(cat "$WORK_DIR/config/short_id.txt")
            echo "SHORT_ID: $SHORT_ID"
        fi
        
        # Тестируем создание ссылки
        USER_UUID="test-uuid-123"
        USER_NAME="test-user"
        
        if [ "$USE_REALITY" = true ]; then
            REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#$USER_NAME"
            echo "=== Создана Reality ссылка ==="
        else
            REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
            echo "=== Создана обычная VLESS ссылка ==="
        fi
        
        echo "$REALITY_LINK"
    fi
else
    echo "ERROR: CONFIG_FILE не найден"
fi