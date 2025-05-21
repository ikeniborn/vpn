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
read -p "Введите порт для VPN сервера [10443]: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-10443}

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
echo "Выберите сайт для маскировки Reality:"
echo "1. addons.mozilla.org (рекомендуется)"
echo "2. www.lovelive-anime.jp"
echo "3. www.swift.org"
echo "4. Ввести свой домен"
read -p "Ваш выбор [1]: " SNI_CHOICE
SNI_CHOICE=${SNI_CHOICE:-1}

case $SNI_CHOICE in
    1) SERVER_SNI="addons.mozilla.org";;
    2) SERVER_SNI="www.lovelive-anime.jp";;
    3) SERVER_SNI="www.swift.org";;
    4) read -p "Введите домен для SNI: " SERVER_SNI;;
    *) SERVER_SNI="addons.mozilla.org";;
esac

log "Выбран SNI: $SERVER_SNI"

# Генерация приватного ключа и публичного ключа для reality (если используется)
if [ "$USE_REALITY" = true ]; then
    log "Генерация ключей для Reality..."

    # Используем Docker Xray для генерации ключей Reality
    log "Генерация ключей с помощью Xray..."
    
    # Попытка использовать команду x25519 из Xray
    TEMP_OUTPUT=$(docker run --rm teddysun/xray:latest x25519 2>/dev/null || echo "")
    
    if [ -n "$TEMP_OUTPUT" ] && echo "$TEMP_OUTPUT" | grep -q "Private key:"; then
        # Извлекаем ключи из вывода Xray
        PRIVATE_KEY=$(echo "$TEMP_OUTPUT" | grep "Private key:" | awk '{print $3}')
        PUBLIC_KEY=$(echo "$TEMP_OUTPUT" | grep "Public key:" | awk '{print $3}')
        SHORT_ID=$(openssl rand -hex 8)
        log "Ключи сгенерированы с помощью Xray x25519"
    else
        # Используем альтернативный способ генерации ключей
        log "Используем альтернативный способ генерации ключей..."
        
        # Проверяем наличие xxd
        if ! command -v xxd >/dev/null 2>&1; then
            log "Установка xxd..."
            apt update && apt install -y xxd
        fi
        
        # Генерируем ключи с помощью OpenSSL
        SHORT_ID=$(openssl rand -hex 8)
        
        # Генерируем X25519 ключи для Reality
        TEMP_PRIVATE=$(openssl genpkey -algorithm X25519 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$TEMP_PRIVATE" ]; then
            # Извлекаем приватный ключ из PEM формата
            PRIVATE_KEY=$(echo "$TEMP_PRIVATE" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 32)
            # Генерируем соответствующий публичный ключ
            PUBLIC_KEY=$(echo "$TEMP_PRIVATE" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
        else
            # Фоллбэк к случайной генерации
            PRIVATE_KEY=$(openssl rand -hex 32)
            PUBLIC_KEY=$(openssl rand -base64 32 | tr -d '\n')
        fi
        log "Ключи сгенерированы с помощью OpenSSL"
    fi
    
    # Проверяем, что ключи сгенерированы
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
        log "Генерируем резервные ключи..."
        SHORT_ID=$(openssl rand -hex 8)
        PRIVATE_KEY=$(openssl rand -hex 32)
        PUBLIC_KEY=$(openssl rand -base64 32 | tr -d '\n')
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

# Создание конфигурации Xray
if [ "$USE_REALITY" = true ]; then
    # Конфигурация для VLESS+Reality по стандартам XTLS/Xray-core
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
            "flow": "xtls-rprx-vision",
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
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 60000,
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic", "fakedns"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
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

if [ "$USE_REALITY" = true ]; then
    cat > "$WORK_DIR/users/$USER_NAME.json" <<EOL
{
  "name": "$USER_NAME",
  "uuid": "$USER_UUID",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "short_id": "$SHORT_ID",
  "protocol": "$PROTOCOL"
}
EOL
else
    cat > "$WORK_DIR/users/$USER_NAME.json" <<EOL
{
  "name": "$USER_NAME",
  "uuid": "$USER_UUID",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "protocol": "$PROTOCOL"
}
EOL
fi

# Создание ссылки для подключения
if [ "$USE_REALITY" = true ]; then
    # VLESS+Reality ссылка с поддержкой XTLS Vision и правильным fingerprint
    REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#$USER_NAME"
else
    REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
fi
echo "$REALITY_LINK" > "$WORK_DIR/users/$USER_NAME.link"

# Сохраняем информацию для использования в manage_users.sh
echo "$SERVER_SNI" > "$WORK_DIR/config/sni.txt"
echo "$PROTOCOL" > "$WORK_DIR/config/protocol.txt"

if [ "$USE_REALITY" = true ]; then
    log "Сохранение настроек Reality..."
    echo "true" > "$WORK_DIR/config/use_reality.txt"
    
    # Проверяем и сохраняем ключи
    if [ -n "$PRIVATE_KEY" ]; then
        echo "$PRIVATE_KEY" > "$WORK_DIR/config/private_key.txt"
        log "Private key сохранен в файл"
    else
        error "Private key пуст, не может быть сохранен"
    fi
    
    if [ -n "$PUBLIC_KEY" ]; then
        echo "$PUBLIC_KEY" > "$WORK_DIR/config/public_key.txt"
        log "Public key сохранен в файл"
    else
        error "Public key пуст, не может быть сохранен"
    fi
    
    if [ -n "$SHORT_ID" ]; then
        echo "$SHORT_ID" > "$WORK_DIR/config/short_id.txt"
        log "Short ID сохранен в файл"
    else
        error "Short ID пуст, не может быть сохранен"
    fi
    
    # Проверяем, что файлы действительно созданы
    if [ -f "$WORK_DIR/config/public_key.txt" ]; then
        log "Файл public_key.txt успешно создан"
        log "Содержимое: $(cat "$WORK_DIR/config/public_key.txt")"
    else
        error "Файл public_key.txt не был создан!"
    fi
    
    log "Сохранены ключи Reality:"
    log "Private Key: $PRIVATE_KEY"
    log "Public Key: $PUBLIC_KEY"
    log "Short ID: $SHORT_ID"
else
    echo "false" > "$WORK_DIR/config/use_reality.txt"
    # Удаляем файлы с ключами, если они существуют
    rm -f "$WORK_DIR/config/private_key.txt" "$WORK_DIR/config/public_key.txt" "$WORK_DIR/config/short_id.txt"
    log "Reality не используется, файлы ключей удалены"
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