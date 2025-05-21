#!/bin/bash

# Тест функции show_user для пользователя user1

WORK_DIR="/opt/v2ray"
CONFIG_FILE="$WORK_DIR/config/config.json"
USERS_DIR="$WORK_DIR/users"
USER_NAME="user1"

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

echo "=== Тест show_user для $USER_NAME ==="

# Проверяем существование пользователя в конфиге
if ! jq -e ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\")" "$CONFIG_FILE" > /dev/null; then
    echo "ERROR: Пользователь с именем '$USER_NAME' не найден в конфиге"
    exit 1
fi

# Получаем информацию о сервере (копируем логику из manage_users.sh)
SERVER_IP=$(curl -s https://api.ipify.org)

if [ -f "$CONFIG_FILE" ]; then
    SERVER_PORT=$(jq '.inbounds[0].port' "$CONFIG_FILE")
    
    if [ -f "$WORK_DIR/config/sni.txt" ]; then
        SERVER_SNI=$(cat "$WORK_DIR/config/sni.txt")
    else
        SERVER_SNI="www.microsoft.com"
    fi
    
    SECURITY=$(jq -r '.inbounds[0].streamSettings.security' "$CONFIG_FILE")
    log "Найдена настройка security в конфиге: $SECURITY"
    
    if [ "$SECURITY" = "reality" ]; then
        USE_REALITY=true
        PROTOCOL="vless+reality"
        log "Установлено использование Reality"
    else
        USE_REALITY=false
        PROTOCOL="vless"
        log "Использование Reality отключено"
    fi
    
    # Получение ключей Reality
    if [ "$USE_REALITY" = true ]; then
        if [ -f "$WORK_DIR/config/public_key.txt" ]; then
            PUBLIC_KEY=$(cat "$WORK_DIR/config/public_key.txt")
        fi
        if [ -f "$WORK_DIR/config/short_id.txt" ]; then
            SHORT_ID=$(cat "$WORK_DIR/config/short_id.txt")
        fi
    fi
fi

echo "=== Результат get_server_info ==="
echo "USE_REALITY: $USE_REALITY"
echo "PROTOCOL: $PROTOCOL"
echo "PUBLIC_KEY: $PUBLIC_KEY"
echo "SHORT_ID: $SHORT_ID"

# Проверка наличия файла с данными пользователя
if [ -f "$USERS_DIR/$USER_NAME.json" ]; then
    echo "=== Файл пользователя найден ==="
    
    # Получение данных из файла (как в manage_users.sh)
    USER_UUID=$(jq -r '.uuid' "$USERS_DIR/$USER_NAME.json")
    FILE_SERVER_PORT=$(jq -r '.port' "$USERS_DIR/$USER_NAME.json")
    FILE_SERVER_SNI=$(jq -r '.sni' "$USERS_DIR/$USER_NAME.json")
    FILE_PUBLIC_KEY=$(jq -r '.public_key' "$USERS_DIR/$USER_NAME.json")
    FILE_PROTOCOL=$(jq -r '.protocol' "$USERS_DIR/$USER_NAME.json")
    
    echo "Данные из файла пользователя:"
    echo "  UUID: $USER_UUID"
    echo "  PORT: $FILE_SERVER_PORT"
    echo "  SNI: $FILE_SERVER_SNI"
    echo "  PUBLIC_KEY: $FILE_PUBLIC_KEY"
    echo "  PROTOCOL: $FILE_PROTOCOL"
    
    # Создание ссылки для подключения (как в manage_users.sh)
    if [ "$USE_REALITY" = true ]; then
        REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#$USER_NAME"
        echo "=== Создана Reality ссылка ==="
    else
        REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
        echo "=== Создана обычная VLESS ссылка ==="
    fi
    
    echo "Итоговая ссылка:"
    echo "$REALITY_LINK"
    
    echo ""
    echo "Сравнение с сохраненной ссылкой:"
    if [ -f "$USERS_DIR/$USER_NAME.link" ]; then
        SAVED_LINK=$(cat "$USERS_DIR/$USER_NAME.link")
        echo "Сохраненная: $SAVED_LINK"
        
        if [ "$REALITY_LINK" = "$SAVED_LINK" ]; then
            echo "✓ Ссылки совпадают"
        else
            echo "✗ Ссылки различаются!"
        fi
    fi
else
    echo "ERROR: Файл пользователя не найден"
fi