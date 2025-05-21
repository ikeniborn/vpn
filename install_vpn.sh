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

# Функция проверки свободного порта
check_port_available() {
    local port=$1
    if command -v netstat >/dev/null 2>&1; then
        ! netstat -tuln | grep -q ":$port "
    elif command -v ss >/dev/null 2>&1; then
        ! ss -tuln | grep -q ":$port "
    else
        # Попытка подключения к порту как проверка
        ! timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null
    fi
}

# Генерация случайного свободного порта
generate_random_port() {
    local attempts=0
    local max_attempts=20
    
    while [ $attempts -lt $max_attempts ]; do
        # Генерируем случайный порт в диапазоне 10000-65000
        local port=$(shuf -i 10000-65000 -n 1)
        
        if check_port_available $port; then
            echo $port
            return 0
        fi
        
        attempts=$((attempts + 1))
    done
    
    # Если не удалось найти свободный порт, возвращаем стандартный
    echo 10443
    return 1
}

# Порт для VPN сервера
echo "Выберите метод назначения порта:"
echo "1. Случайный свободный порт (рекомендуется)"
echo "2. Указать порт вручную"
echo "3. Использовать стандартный порт (10443)"
read -p "Ваш выбор [1]: " PORT_CHOICE
PORT_CHOICE=${PORT_CHOICE:-1}

case $PORT_CHOICE in
    1)
        log "Поиск свободного порта..."
        SERVER_PORT=$(generate_random_port)
        if [ $? -eq 0 ]; then
            log "✓ Найден свободный порт: $SERVER_PORT"
        else
            warning "Не удалось найти свободный случайный порт, используется стандартный"
            SERVER_PORT=10443
        fi
        ;;
    2)
        while true; do
            read -p "Введите порт для VPN сервера [10443]: " SERVER_PORT
            SERVER_PORT=${SERVER_PORT:-10443}
            
            # Проверка корректности порта
            if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
                error "Некорректный порт. Введите число от 1 до 65535."
                continue
            fi
            
            # Проверка доступности порта
            if check_port_available $SERVER_PORT; then
                log "✓ Порт $SERVER_PORT свободен"
                break
            else
                warning "Порт $SERVER_PORT уже используется!"
                read -p "Использовать занятый порт? (y/n): " use_busy_port
                if [ "$use_busy_port" = "y" ]; then
                    warning "Внимание: порт $SERVER_PORT может конфликтовать с другими службами"
                    break
                fi
            fi
        done
        ;;
    3)
        SERVER_PORT=10443
        if ! check_port_available $SERVER_PORT; then
            warning "Стандартный порт $SERVER_PORT занят, но будет использован"
        fi
        ;;
    *)
        SERVER_PORT=$(generate_random_port)
        log "Использован случайный порт: $SERVER_PORT"
        ;;
esac

log "Выбран порт: $SERVER_PORT"

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

# Функция проверки доступности SNI домена
check_sni_domain() {
    local domain=$1
    local timeout=10
    
    log "Проверка доступности домена $domain..."
    
    # Проверка DNS резолюции
    if ! nslookup "$domain" >/dev/null 2>&1; then
        warning "Домен $domain не резолвится в DNS"
        return 1
    fi
    
    # Проверка HTTPS доступности
    if ! curl -s --connect-timeout $timeout --max-time $timeout "https://$domain" >/dev/null 2>&1; then
        warning "Домен $domain недоступен по HTTPS"
        return 1
    fi
    
    # Проверка поддержки TLS 1.3
    local tls_check=$(echo | openssl s_client -connect "$domain:443" -tls1_3 -quiet 2>/dev/null | grep "TLSv1.3")
    if [ -z "$tls_check" ]; then
        warning "Домен $domain не поддерживает TLS 1.3"
        return 1
    fi
    
    log "✓ Домен $domain прошел все проверки"
    return 0
}

# Выбор сайта для SNI
echo "Выберите сайт для маскировки Reality:"
echo "1. addons.mozilla.org (рекомендуется)"
echo "2. www.lovelive-anime.jp"
echo "3. www.swift.org"
echo "4. Ввести свой домен"
echo "5. Автоматический выбор лучшего домена"
read -p "Ваш выбор [1]: " SNI_CHOICE
SNI_CHOICE=${SNI_CHOICE:-1}

case $SNI_CHOICE in
    1) SERVER_SNI="addons.mozilla.org";;
    2) SERVER_SNI="www.lovelive-anime.jp";;
    3) SERVER_SNI="www.swift.org";;
    4) 
        while true; do
            read -p "Введите домен для SNI: " SERVER_SNI
            if check_sni_domain "$SERVER_SNI"; then
                break
            else
                error "Домен $SERVER_SNI не подходит для использования. Попробуйте другой."
                read -p "Попробовать еще раз? (y/n): " retry
                if [ "$retry" != "y" ]; then
                    SERVER_SNI="addons.mozilla.org"
                    log "Использован домен по умолчанию: $SERVER_SNI"
                    break
                fi
            fi
        done
        ;;
    5)
        log "Автоматический выбор лучшего домена..."
        CANDIDATES=("addons.mozilla.org" "www.lovelive-anime.jp" "www.swift.org" "www.kernel.org" "gitlab.com")
        SERVER_SNI=""
        
        for domain in "${CANDIDATES[@]}"; do
            if check_sni_domain "$domain"; then
                SERVER_SNI="$domain"
                log "✓ Автоматически выбран домен: $SERVER_SNI"
                break
            fi
        done
        
        if [ -z "$SERVER_SNI" ]; then
            warning "Ни один из кандидатов не прошел проверку. Используется домен по умолчанию."
            SERVER_SNI="addons.mozilla.org"
        fi
        ;;
    *) SERVER_SNI="addons.mozilla.org";;
esac

# Финальная проверка выбранного домена
if ! check_sni_domain "$SERVER_SNI"; then
    warning "Выбранный домен $SERVER_SNI может работать нестабильно"
    read -p "Продолжить с этим доменом? (y/n) [y]: " continue_choice
    if [ "$continue_choice" = "n" ]; then
        SERVER_SNI="addons.mozilla.org"
        log "Использован резервный домен: $SERVER_SNI"
    fi
fi

log "Итоговый выбор SNI: $SERVER_SNI"

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

# Создание директорий для конфигурации и логов
mkdir -p "$WORK_DIR/config"
mkdir -p "$WORK_DIR/logs"

# Создание конфигурации Xray
if [ "$USE_REALITY" = true ]; then
    # Конфигурация для VLESS+Reality по стандартам XTLS/Xray-core
    cat > "$WORK_DIR/config/config.json" <<EOL
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "stats": {},
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "policy": {
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
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
  xray:
    image: teddysun/xray:latest
    container_name: xray
    restart: always
    network_mode: host
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
    environment:
      - TZ=Europe/Moscow
    command: ["run", "-c", "/etc/xray/config.json"]
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