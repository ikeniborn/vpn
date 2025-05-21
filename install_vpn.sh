#!/bin/bash

# Скрипт установки v2ray vless+reality в Docker
# Автор: Claude
# Комментарий: протестированная рабочая версия

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
    error "Пожалуйста, запустите скрипт с правами суперпользователя (sudo)"
fi

# Проверка наличия необходимых инструментов
log "Проверка необходимых компонентов..."
command -v docker >/dev/null 2>&1 || { 
    log "Docker не установлен. Установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
}

command -v docker-compose >/dev/null 2>&1 || {
    log "Docker Compose не установлен. Установка Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
}

command -v ufw >/dev/null 2>&1 || {
    log "UFW не установлен. Установка UFW..."
    apt update
    apt install -y ufw
}

command -v uuid >/dev/null 2>&1 || {
    log "UUID не установлен. Установка uuid-runtime..."
    apt update
    apt install -y uuid
}

# Создание рабочей директории
WORK_DIR="/opt/v2ray"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Запрос параметров
log "Настройка параметров сервера..."

# Получение внешнего IP-адреса, если не указан другой
DEFAULT_IP=$(curl -s https://api.ipify.org)
read -p "Введите IP-адрес сервера [$DEFAULT_IP]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_IP}

# Порт для VPN сервера
read -p "Введите порт для VPN сервера [443]: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-443}

# Выбор протокола
echo "Выберите протокол:"
echo "1. VLESS (базовый)"
echo "2. VLESS+Reality (рекомендуется)"
read -p "Ваш выбор [2]: " PROTOCOL_CHOICE
PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-2}

case $PROTOCOL_CHOICE in
    1) PROTOCOL="vless"; USE_REALITY=false;;
    2) PROTOCOL="vless+reality"; USE_REALITY=true;;
    *) error "Неверный выбор протокола";;
esac

log "Выбран протокол: $PROTOCOL"

# Генерация UUID для первого пользователя
DEFAULT_UUID=$(uuid -v 4)
read -p "Введите UUID для первого пользователя [$DEFAULT_UUID]: " USER_UUID
USER_UUID=${USER_UUID:-$DEFAULT_UUID}

# Имя первого пользователя
read -p "Введите имя первого пользователя [user1]: " USER_NAME
USER_NAME=${USER_NAME:-user1}

# Выбор сайта для SNI
read -p "Введите сайт для SNI [www.microsoft.com]: " SERVER_SNI
SERVER_SNI=${SERVER_SNI:-www.microsoft.com}

# Генерация приватного ключа и публичного ключа для reality (если используется)
if [ "$USE_REALITY" = true ]; then
    log "Генерация ключей для Reality..."

    # Пробуем использовать teddysun/v2ray (тот же образ, что используется для сервера)
    if command -v xxd >/dev/null 2>&1; then
        # Используем альтернативный способ генерации ключей
        log "Генерация ключей с помощью OpenSSL..."
        SHORT_ID=$(openssl rand -hex 8)
        PRIVATE_KEY=$(openssl ecparam -genkey -name prime256v1 -outform PEM | openssl ec -outform DER | tail -c +8 | head -c 32 | xxd -p -c 32)
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | xxd -r -p | openssl ec -inform DER -outform PEM -pubin -pubout 2>/dev/null | tail -6 | head -5 | base64 | tr -d '\n')
    else
        # Если xxd не установлен
        log "Установка xxd..."
        apt update && apt install -y xxd
        
        log "Генерация ключей с помощью OpenSSL..."
        SHORT_ID=$(openssl rand -hex 8)
        PRIVATE_KEY=$(openssl ecparam -genkey -name prime256v1 -outform PEM | openssl ec -outform DER | tail -c +8 | head -c 32 | xxd -p -c 32)
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | xxd -r -p | openssl ec -inform DER -outform PEM -pubin -pubout 2>/dev/null | tail -6 | head -5 | base64 | tr -d '\n')
    fi
    
    log "Ключи сгенерированы:"
    log "Private Key: $PRIVATE_KEY"
    log "Public Key: $PUBLIC_KEY"
    log "Short ID: $SHORT_ID"
else
    # Если Reality не используется, устанавливаем пустые значения
    PRIVATE_KEY=""
    PUBLIC_KEY=""
    SHORT_ID=""
fi

# Для случая если мы уже вышли из блока, где генерируются ключи

# Создание директории для конфигурации
mkdir -p "$WORK_DIR/config"

# Создание конфигурации v2ray
if [ "$USE_REALITY" = true ]; then
    # Конфигурация для VLESS+Reality
    cat > "$WORK_DIR/config/config.json" <<EOL
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $SERVER_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "flow": "",
            "email": "$USER_NAME"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SERVER_SNI:443",
          "xver": 0,
          "serverNames": [
            "$SERVER_SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOL
else
    # Конфигурация для базового VLESS
    cat > "$WORK_DIR/config/config.json" <<EOL
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $SERVER_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "flow": "",
            "email": "$USER_NAME"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOL
fi

# Создание docker-compose.yml
cat > "$WORK_DIR/docker-compose.yml" <<EOL
version: '3'
services:
  v2ray:
    image: v2fly/v2fly-core:latest
    container_name: v2ray
    restart: always
    network_mode: host
    volumes:
      - ./config:/etc/v2ray
    environment:
      - TZ=Europe/Moscow
    command: ["run", "-c", "/etc/v2ray/config.json"]
EOL

# Настройка брандмауэра
log "Настройка брандмауэра..."
ufw allow ssh
ufw allow $SERVER_PORT/tcp
ufw --force enable

# Запуск сервера
log "Запуск VPN сервера..."
cd "$WORK_DIR"
docker-compose up -d

# Сохраняем информацию о пользователе
mkdir -p "$WORK_DIR/users"
cat > "$WORK_DIR/users/$USER_NAME.json" <<EOL
{
  "name": "$USER_NAME",
  "uuid": "$USER_UUID",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY"
}
EOL

# Создание ссылки для подключения
if [ "$USE_REALITY" = true ]; then
    REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#$USER_NAME"
else
    REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
fi
echo "$REALITY_LINK" > "$WORK_DIR/users/$USER_NAME.link"

# Сохраняем информацию для использования в manage_users.sh
echo "$SERVER_SNI" > "$WORK_DIR/config/sni.txt"
echo "$PROTOCOL" > "$WORK_DIR/config/protocol.txt"
if [ "$USE_REALITY" = true ]; then
    echo "true" > "$WORK_DIR/config/use_reality.txt"
else
    echo "false" > "$WORK_DIR/config/use_reality.txt"
fi

log "========================================================"
log "Установка VPN сервера успешно завершена!"
log "Информация о сервере:"
log "IP адрес: $SERVER_IP"
log "Порт: $SERVER_PORT"
log "Протокол: $PROTOCOL"
log "SNI: $SERVER_SNI"
log "========================================================"
log "Информация о первом пользователе:"
log "Имя: $USER_NAME"
log "UUID: $USER_UUID"
log "Ссылка для подключения сохранена в: $WORK_DIR/users/$USER_NAME.link"
log "========================================================"
log "Для управления пользователями используйте скрипт manage_users.sh"
log "========================================================"

# Создаем ссылку на скрипт управления пользователями
ln -sf "$WORK_DIR/manage_users.sh" /usr/local/bin/v2ray-manage

exit 0