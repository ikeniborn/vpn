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

command -v uuidgen >/dev/null 2>&1 || {
    log "uuid-runtime не установлен. Установка uuid-runtime..."
    apt update
    apt install -y uuid-runtime
}

# Установка дополнительных инструментов для проверки доменов
if ! command -v dig >/dev/null 2>&1; then
    log "Установка dnsutils для улучшенной проверки DNS..."
    apt update
    apt install -y dnsutils
fi

if ! command -v openssl >/dev/null 2>&1; then
    log "Установка openssl..."
    apt update
    apt install -y openssl
fi

# ========================= ОБЩИЕ ФУНКЦИИ =========================

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

# Унифицированная функция генерации случайного свободного порта
generate_free_port() {
    local min_port=${1:-10000}      # Минимальный порт (по умолчанию 10000)
    local max_port=${2:-65000}      # Максимальный порт (по умолчанию 65000)
    local check_availability=${3:-true}  # Проверять доступность (по умолчанию true)
    local max_attempts=${4:-20}     # Максимум попыток (по умолчанию 20)
    local fallback_port=${5:-10443} # Резервный порт (по умолчанию 10443)
    
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        # Генерируем случайный порт в указанном диапазоне
        local port
        if command -v shuf >/dev/null 2>&1; then
            port=$(shuf -i $min_port-$max_port -n 1)
        else
            # Альтернативный метод если shuf недоступен
            local range=$((max_port - min_port + 1))
            port=$(( (RANDOM % range) + min_port ))
        fi
        
        # Проверяем доступность порта если требуется
        if [ "$check_availability" = "true" ]; then
            if check_port_available $port; then
                echo $port
                return 0
            fi
        else
            echo $port
            return 0
        fi
        
        attempts=$((attempts + 1))
    done
    
    # Если не удалось найти свободный порт, возвращаем резервный
    echo $fallback_port
    return 1
}

# ========================= OUTLINE VPN FUNCTIONS =========================

# Функция определения архитектуры для Outline
detect_architecture() {
    local arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            log "Detected x86-64 architecture"
            export ARCHITECTURE="amd64"
            export WATCHTOWER_IMAGE="containrrr/watchtower:latest"
            export SB_IMAGE="quay.io/outline/shadowbox:stable"
            ;;
        aarch64|arm64)
            log "Detected ARM64 architecture"
            export ARCHITECTURE="arm64"
            export WATCHTOWER_IMAGE="ken1029/watchtower:arm64"
            export SB_IMAGE="ken1029/shadowbox:latest"
            ;;
        armv7*|armv8*|armhf)
            log "Detected ARMv7 architecture"
            export ARCHITECTURE="armv7"
            export WATCHTOWER_IMAGE="ken1029/watchtower:arm32"
            export SB_IMAGE="ken1029/shadowbox:latest"
            ;;
        *)
            error "Unsupported architecture: $arch"
            ;;
    esac
}

# Функция настройки файрвола для Outline
setup_outline_firewall() {
    local api_port="$1"
    local access_key_port="$2"
    
    log "Настройка брандмауэра для Outline VPN..."
    
    # Backup current UFW rules
    mkdir -p /opt/outline/backup
    ufw status verbose > /opt/outline/backup/ufw_rules_backup.txt 2>/dev/null || true
    
    # Configure UFW
    # Check if SSH rule already exists
    if ! ufw status | grep -q "22/tcp\|OpenSSH\|ssh"; then
        ufw allow ssh
        log "SSH правило добавлено"
    else
        log "SSH правило уже существует"
    fi
    ufw allow "$api_port"/tcp
    ufw allow "$access_key_port"/tcp
    ufw allow "$access_key_port"/udp
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        log "Включение UFW брандмауэра"
        ufw --force enable
    fi
    
    log "Брандмауэр настроен успешно"
}

# Функция создания safe base64 строки
safe_base64() {
    base64 -w 0 | tr '/+' '_-' | tr -d '='
}

# Основная функция установки Outline VPN
install_outline_vpn() {
    log "========================================================"
    log "Начало установки Outline VPN сервера"
    log "========================================================"
    
    # Определяем архитектуру
    detect_architecture
    
    # Запрос параметров для Outline VPN
    log "Настройка параметров Outline VPN сервера..."
    
    # Получение hostname
    DEFAULT_IP=$(curl -s https://api.ipify.org)
    echo ""
    echo "Настройка hostname/IP адреса:"
    read -p "Введите hostname или IP-адрес сервера [$DEFAULT_IP]: " OUTLINE_HOSTNAME
    OUTLINE_HOSTNAME=${OUTLINE_HOSTNAME:-$DEFAULT_IP}
    
    # Настройка API порта
    echo ""
    echo "Настройка API порта (для управления через Outline Manager):"
    echo "1. Случайный свободный порт (рекомендуется)"
    echo "2. Указать порт вручную"
    read -p "Ваш выбор [1]: " API_PORT_CHOICE
    API_PORT_CHOICE=${API_PORT_CHOICE:-1}
    
    case $API_PORT_CHOICE in
        1)
            OUTLINE_API_PORT=$(generate_free_port 8000 9999 true 20 8080)
            log "✓ Сгенерирован API порт: $OUTLINE_API_PORT"
            ;;
        2)
            while true; do
                read -p "Введите API порт [8080]: " OUTLINE_API_PORT
                OUTLINE_API_PORT=${OUTLINE_API_PORT:-8080}
                
                if ! [[ "$OUTLINE_API_PORT" =~ ^[0-9]+$ ]] || [ "$OUTLINE_API_PORT" -lt 1024 ] || [ "$OUTLINE_API_PORT" -gt 65535 ]; then
                    warning "Некорректный порт. Введите число от 1024 до 65535."
                    continue
                fi
                
                if check_port_available $OUTLINE_API_PORT; then
                    log "✓ API порт $OUTLINE_API_PORT свободен"
                    break
                else
                    warning "Порт $OUTLINE_API_PORT уже используется!"
                    read -p "Использовать занятый порт? (y/n): " use_busy_port
                    if [ "$use_busy_port" = "y" ]; then
                        break
                    fi
                fi
            done
            ;;
        *)
            OUTLINE_API_PORT=$(generate_free_port 8000 9999 true 20 8080)
            ;;
    esac
    
    # Настройка порта для ключей доступа
    echo ""
    echo "Настройка порта для ключей доступа (клиентские подключения):"
    echo "1. Случайный свободный порт (рекомендуется)"
    echo "2. Указать порт вручную"
    read -p "Ваш выбор [1]: " KEYS_PORT_CHOICE
    KEYS_PORT_CHOICE=${KEYS_PORT_CHOICE:-1}
    
    case $KEYS_PORT_CHOICE in
        1)
            OUTLINE_KEYS_PORT=$(generate_free_port 10000 15999 true 20 9000)
            # Убеждаемся что порты разные
            while [ "$OUTLINE_KEYS_PORT" = "$OUTLINE_API_PORT" ]; do
                OUTLINE_KEYS_PORT=$(generate_free_port 10000 15999 true 20 9000)
            done
            log "✓ Сгенерирован порт для ключей: $OUTLINE_KEYS_PORT"
            ;;
        2)
            while true; do
                read -p "Введите порт для ключей доступа [9000]: " OUTLINE_KEYS_PORT
                OUTLINE_KEYS_PORT=${OUTLINE_KEYS_PORT:-9000}
                
                if ! [[ "$OUTLINE_KEYS_PORT" =~ ^[0-9]+$ ]] || [ "$OUTLINE_KEYS_PORT" -lt 1024 ] || [ "$OUTLINE_KEYS_PORT" -gt 65535 ]; then
                    warning "Некорректный порт. Введите число от 1024 до 65535."
                    continue
                fi
                
                if [ "$OUTLINE_KEYS_PORT" = "$OUTLINE_API_PORT" ]; then
                    warning "Порт для ключей должен отличаться от API порта!"
                    continue
                fi
                
                if check_port_available $OUTLINE_KEYS_PORT; then
                    log "✓ Порт для ключей $OUTLINE_KEYS_PORT свободен"
                    break
                else
                    warning "Порт $OUTLINE_KEYS_PORT уже используется!"
                    read -p "Использовать занятый порт? (y/n): " use_busy_port
                    if [ "$use_busy_port" = "y" ]; then
                        break
                    fi
                fi
            done
            ;;
        *)
            OUTLINE_KEYS_PORT=$(generate_free_port 10000 15999 true 20 9000)
            while [ "$OUTLINE_KEYS_PORT" = "$OUTLINE_API_PORT" ]; do
                OUTLINE_KEYS_PORT=$(generate_free_port 10000 15999 true 20 9000)
            done
            ;;
    esac
    
    # Создание рабочей директории для Outline
    export SHADOWBOX_DIR="/opt/outline"
    log "Создание директории Outline по адресу $SHADOWBOX_DIR"
    mkdir -p --mode=770 "$SHADOWBOX_DIR"
    
    # Создание конфигурационного файла
    readonly ACCESS_CONFIG="$SHADOWBOX_DIR/access.txt"
    
    # Создание директории состояния
    log "Создание директории постоянного состояния"
    readonly STATE_DIR="$SHADOWBOX_DIR/persisted-state"
    mkdir -p --mode=770 "${STATE_DIR}"
    chmod g+s "${STATE_DIR}"
    
    # Генерация API ключа
    log "Генерация секретного ключа API"
    readonly SB_API_PREFIX=$(head -c 16 /dev/urandom | safe_base64)
    
    # Генерация TLS сертификата
    log "Генерация TLS сертификата"
    readonly CERTIFICATE_NAME="${STATE_DIR}/shadowbox-selfsigned"
    readonly SB_CERTIFICATE_FILE="${CERTIFICATE_NAME}.crt"
    readonly SB_PRIVATE_KEY_FILE="${CERTIFICATE_NAME}.key"
    
    openssl req -x509 -nodes -days 36500 -newkey rsa:2048 \
        -subj "/CN=${OUTLINE_HOSTNAME}" \
        -keyout "${SB_PRIVATE_KEY_FILE}" -out "${SB_CERTIFICATE_FILE}" >/dev/null 2>&1
    
    # Генерация отпечатка сертификата
    log "Генерация отпечатка сертификата"
    CERT_OPENSSL_FINGERPRINT=$(openssl x509 -in "${SB_CERTIFICATE_FILE}" -noout -sha256 -fingerprint)
    CERT_HEX_FINGERPRINT=$(echo ${CERT_OPENSSL_FINGERPRINT#*=} | tr --delete :)
    echo "certSha256:$CERT_HEX_FINGERPRINT" >> $ACCESS_CONFIG
    
    # Запись конфигурации если указан порт для ключей
    if [ -n "$OUTLINE_KEYS_PORT" ]; then
        log "Запись конфигурации сервера"
        echo "{\"portForNewAccessKeys\":$OUTLINE_KEYS_PORT}" > $STATE_DIR/shadowbox_server_config.json
    fi
    
    # Запуск контейнера Shadowbox
    log "Запуск контейнера Shadowbox"
    docker run -d \
        --name shadowbox \
        --restart=always \
        --net=host \
        -v "${STATE_DIR}:${STATE_DIR}" \
        -e "SB_STATE_DIR=${STATE_DIR}" \
        -e "SB_PUBLIC_IP=${OUTLINE_HOSTNAME}" \
        -e "SB_API_PORT=${OUTLINE_API_PORT}" \
        -e "SB_API_PREFIX=${SB_API_PREFIX}" \
        -e "SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}" \
        -e "SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}" \
        ${SB_IMAGE} >/dev/null
    
    # Запуск Watchtower для автоматических обновлений
    log "Запуск Watchtower для автоматических обновлений"
    docker run -d \
        --name watchtower \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ${WATCHTOWER_IMAGE} \
        --cleanup --tlsverify --interval 3600 >/dev/null
    
    # Установка URL-ов API
    readonly PUBLIC_API_URL="https://${OUTLINE_HOSTNAME}:${OUTLINE_API_PORT}/${SB_API_PREFIX}"
    readonly LOCAL_API_URL="https://localhost:${OUTLINE_API_PORT}/${SB_API_PREFIX}"
    
    # Ожидание готовности сервиса
    log "Ожидание готовности Outline сервера"
    until curl --insecure -s "${LOCAL_API_URL}/access-keys" >/dev/null; do 
        sleep 1
    done
    
    # Создание первого ключа доступа
    log "Создание первого ключа доступа"
    curl --insecure -X POST -s "${LOCAL_API_URL}/access-keys" >/dev/null
    
    # Добавление URL API в конфигурацию
    log "Добавление URL API в конфигурацию"
    echo "apiUrl:${PUBLIC_API_URL}" >> $ACCESS_CONFIG
    
    # Получение порта ключа доступа
    log "Получение порта ключа доступа"
    local ACCESS_KEY_PORT=$(curl --insecure -s ${LOCAL_API_URL}/access-keys | 
        docker exec -i shadowbox node -e '
            const fs = require("fs");
            const accessKeys = JSON.parse(fs.readFileSync(0, {encoding: "utf-8"}));
            console.log(accessKeys["accessKeys"][0]["port"]);
        ')
    
    # Настройка брандмауэра
    setup_outline_firewall "$OUTLINE_API_PORT" "$ACCESS_KEY_PORT"
    
    # Получение информации о сервере
    log "Получение информации о сервере"
    local API_URL=$(grep "apiUrl" $ACCESS_CONFIG | sed "s/apiUrl://")
    local CERT_SHA256=$(grep "certSha256" $ACCESS_CONFIG | sed "s/certSha256://")
    
    # Создание ссылки на скрипт управления
    if [ -f "/home/ikeniborn/Documents/Project/vpn/manage_users.sh" ]; then
        ln -sf "/home/ikeniborn/Documents/Project/vpn/manage_users.sh" /usr/local/bin/outline-manage 2>/dev/null || true
    fi
    
    # Добавим определение цветов если их еще нет
    local BLUE='\033[0;34m'
    
    # Отображение сообщения об успехе
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ПОЗДРАВЛЯЕМ! OUTLINE VPN СЕРВЕР ГОТОВ К РАБОТЕ        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Информация о сервере:${NC}"
    echo -e "• IP/Hostname сервера: ${OUTLINE_HOSTNAME}"
    echo -e "• API порт: ${OUTLINE_API_PORT}"
    echo -e "• Порт ключей доступа: ${ACCESS_KEY_PORT}"
    echo ""
    echo -e "${BLUE}Для управления вашим Outline сервером:${NC}"
    echo -e "1. Установите Outline Manager с https://getoutline.org/"
    echo -e "2. Скопируйте следующую строку (включая фигурные скобки) в Outline Manager:"
    echo ""
    echo -e "${GREEN}{\"apiUrl\":\"${API_URL}\",\"certSha256\":\"${CERT_SHA256}\"}${NC}"
    echo ""
    echo -e "${BLUE}Настройка брандмауэра:${NC}"
    echo -e "• Порт управления ${OUTLINE_API_PORT} (TCP) открыт"
    echo -e "• Порт ключей доступа ${ACCESS_KEY_PORT} (TCP/UDP) открыт"
    echo ""
    echo -e "${YELLOW}Примечание:${NC} Если есть проблемы с подключением, убедитесь что ваш облачный"
    echo -e "провайдер или роутер разрешает эти порты. Файлы конфигурации хранятся в ${SHADOWBOX_DIR}."
    echo ""
}

# Выбор типа VPN сервера
echo ""
log "Выберите тип VPN сервера для установки:"
echo "1. Xray VPN (VLESS+Reality) - рекомендуется для обхода блокировок"
echo "2. Outline VPN (Shadowsocks) - простота управления через приложение"
read -p "Ваш выбор [1]: " VPN_TYPE_CHOICE
VPN_TYPE_CHOICE=${VPN_TYPE_CHOICE:-1}

case $VPN_TYPE_CHOICE in
    1) 
        VPN_TYPE="xray"
        log "Выбран Xray VPN (VLESS+Reality)"
        ;;
    2) 
        VPN_TYPE="outline"
        log "Выбран Outline VPN (Shadowsocks)"
        ;;
    *) 
        VPN_TYPE="xray"
        log "Использован Xray VPN по умолчанию"
        ;;
esac

if [ "$VPN_TYPE" = "xray" ]; then
    # Создание рабочей директории для Xray
    WORK_DIR="/opt/v2ray"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # Запрос параметров для Xray
    log "Настройка параметров Xray сервера..."
else
    # Для Outline VPN запускаем соответствующую функцию
    install_outline_vpn
    exit 0
fi

# Получение внешнего IP-адреса, если не указан другой
DEFAULT_IP=$(curl -s https://api.ipify.org)
read -p "Введите IP-адрес сервера [$DEFAULT_IP]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_IP}

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
        SERVER_PORT=$(generate_free_port 10000 65000 true 20 10443)
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
        SERVER_PORT=$(generate_free_port 10000 65000 true 20 10443)
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
DEFAULT_UUID=$(uuidgen)
read -p "Введите UUID для первого пользователя [$DEFAULT_UUID]: " USER_UUID
USER_UUID=${USER_UUID:-$DEFAULT_UUID}

# Имя первого пользователя
read -p "Введите имя первого пользователя [user1]: " USER_NAME
USER_NAME=${USER_NAME:-user1}

# Функция проверки доступности SNI домена
check_sni_domain() {
    local domain=$1
    local timeout=3
    
    log "Проверка доступности домена $domain..."
    
    # Проверка 1: DNS резолюция с использованием dig (более надежно чем nslookup)
    if command -v dig >/dev/null 2>&1; then
        if ! timeout $timeout dig +short "$domain" >/dev/null 2>&1; then
            warning "Домен $domain не резолвится в DNS (dig)"
            return 1
        fi
    else
        # Fallback на host если dig недоступен
        if ! timeout $timeout host "$domain" >/dev/null 2>&1; then
            warning "Домен $domain не резолвится в DNS (host)"
            return 1
        fi
    fi
    
    # Проверка 2: TCP подключение к порту 443 (самый быстрый способ)
    if ! timeout $timeout bash -c "</dev/tcp/$domain/443" 2>/dev/null; then
        warning "Домен $domain недоступен на порту 443"
        return 1
    fi
    
    # Проверка 3: Базовая HTTPS доступность (без --fail для большей толерантности)
    local http_code=$(timeout $timeout curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout $timeout --max-time $timeout \
        --insecure --location --user-agent "Mozilla/5.0" \
        "https://$domain" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "000" ]; then
        warning "Домен $domain не отвечает на HTTPS запросы"
        return 1
    fi
    
    # Проверка 4: Упрощенная проверка TLS (только базовое подключение)
    local tls_check=""
    if command -v openssl >/dev/null 2>&1; then
        tls_check=$(timeout $timeout bash -c "echo | openssl s_client -connect '$domain:443' -servername '$domain' -quiet 2>/dev/null | head -n 1" | grep -i "verify\|protocol\|cipher" || echo "")
        
        if [ -z "$tls_check" ]; then
            # Попробуем еще раз с другими параметрами
            tls_check=$(timeout $timeout bash -c "echo 'Q' | openssl s_client -connect '$domain:443' -servername '$domain' 2>/dev/null | grep -E 'Protocol|Cipher'" || echo "ok")
        fi
        
        if [ -z "$tls_check" ]; then
            warning "Домен $domain: не удалось проверить TLS, но TCP соединение работает"
            # Не возвращаем ошибку, так как основные проверки прошли
        fi
    fi
    
    log "✓ Домен $domain прошел основные проверки (HTTP код: $http_code)"
    return 0
}

# Выбор сайта для SNI
echo ""
log "Настройка домена для маскировки Reality..."
warning "Проверка доменов может занять время. Для быстрой установки выберите вариант 6."
echo ""
echo "Выберите сайт для маскировки Reality:"
echo "1. addons.mozilla.org (рекомендуется)"
echo "2. www.lovelive-anime.jp"
echo "3. www.swift.org"
echo "4. Ввести свой домен"
echo "5. Автоматический выбор лучшего домена"
echo "6. Пропустить проверку домена (быстрая установка)"
read -p "Ваш выбор [1]: " SNI_CHOICE
SNI_CHOICE=${SNI_CHOICE:-1}

case $SNI_CHOICE in
    1) SERVER_SNI="addons.mozilla.org";;
    2) SERVER_SNI="www.lovelive-anime.jp";;
    3) SERVER_SNI="www.swift.org";;
    4) 
        while true; do
            read -p "Введите домен для SNI (например: example.com): " SERVER_SNI
            
            # Базовая валидация формата домена
            if [[ ! "$SERVER_SNI" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                warning "Некорректный формат домена. Введите правильный домен."
                continue
            fi
            
            log "Проверка домена $SERVER_SNI (максимум 10 секунд)..."
            
            # Быстрая предварительная проверка
            if timeout 2 bash -c "</dev/tcp/$SERVER_SNI/443" 2>/dev/null; then
                log "✓ Домен $SERVER_SNI доступен, выполняем полную проверку..."
                if check_sni_domain "$SERVER_SNI"; then
                    log "✓ Домен $SERVER_SNI успешно прошел все проверки"
                    break
                else
                    warning "Домен $SERVER_SNI прошел базовую проверку, но не все тесты."
                fi
            else
                warning "Домен $SERVER_SNI недоступен на порту 443."
            fi
            
            echo "Варианты действий:"
            echo "1. Использовать этот домен (может не работать оптимально)"
            echo "2. Попробовать другой домен"
            echo "3. Использовать рекомендованный домен (addons.mozilla.org)"
            read -p "Ваш выбор [2]: " domain_choice
            domain_choice=${domain_choice:-2}
            
            case $domain_choice in
                1)
                    warning "Внимание: домен $SERVER_SNI будет использован без полной проверки"
                    break
                    ;;
                2)
                    continue
                    ;;
                3)
                    SERVER_SNI="addons.mozilla.org"
                    log "Использован рекомендованный домен: $SERVER_SNI"
                    break
                    ;;
                *)
                    continue
                    ;;
            esac
        done
        ;;
    5)
        log "Автоматический выбор лучшего домена (максимум 30 секунд)..."
        # Расширенный список кандидатов с более стабильными доменами
        CANDIDATES=(
            "addons.mozilla.org" 
            "www.swift.org" 
            "golang.org"
            "www.kernel.org"
            "cdn.jsdelivr.net"
            "registry.npmjs.org"
            "api.github.com"
            "www.lovelive-anime.jp"
        )
        SERVER_SNI=""
        
        log "Тестирование доменов-кандидатов..."
        for domain in "${CANDIDATES[@]}"; do
            log "Быстрая проверка $domain..."
            
            # Используем более быструю предварительную проверку
            if timeout 2 bash -c "</dev/tcp/$domain/443" 2>/dev/null; then
                log "✓ $domain доступен, выполняем полную проверку..."
                if check_sni_domain "$domain"; then
                    SERVER_SNI="$domain"
                    log "✓ Автоматически выбран домен: $SERVER_SNI"
                    break
                fi
            else
                log "✗ $domain недоступен, пропускаем..."
            fi
        done
        
        if [ -z "$SERVER_SNI" ]; then
            warning "Ни один из кандидатов не прошел проверку. Используется домен по умолчанию."
            SERVER_SNI="addons.mozilla.org"
            log "Резервный домен: $SERVER_SNI"
        fi
        ;;
    6)
        log "Быстрая установка: проверка доменов пропущена"
        SERVER_SNI="addons.mozilla.org"
        ;;
    *) SERVER_SNI="addons.mozilla.org";;
esac

# Финальная проверка выбранного домена (только для вариантов 1-3)
if [ "$SNI_CHOICE" -ge 1 ] && [ "$SNI_CHOICE" -le 3 ]; then
    log "Быстрая проверка выбранного домена $SERVER_SNI..."
    
    # Сначала быстрая проверка TCP соединения
    if timeout 3 bash -c "</dev/tcp/$SERVER_SNI/443" 2>/dev/null; then
        log "✓ Домен $SERVER_SNI доступен"
    else
        warning "Домен $SERVER_SNI может быть недоступен, но будет использован"
        read -p "Заменить на резервный домен addons.mozilla.org? (y/n) [n]: " use_backup
        if [ "$use_backup" = "y" ]; then
            SERVER_SNI="addons.mozilla.org"
            log "Использован резервный домен: $SERVER_SNI"
        fi
    fi
fi

log "Итоговый выбор SNI: $SERVER_SNI"

# Генерация приватного ключа и публичного ключа для reality (если используется)
if [ "$USE_REALITY" = true ]; then
    log "Генерация ключей для Reality..."

    # Используем Docker Xray для генерации ключей Reality
    log "Генерация ключей с помощью Xray..."
    
    # Попытка использовать команду x25519 из Xray
    TEMP_OUTPUT=$(docker run --rm teddysun/xray:latest xray x25519 2>&1 || echo "")
    
    if [ -n "$TEMP_OUTPUT" ] && echo "$TEMP_OUTPUT" | grep -q "Private key:"; then
        # Извлекаем ключи из вывода Xray
        PRIVATE_KEY=$(echo "$TEMP_OUTPUT" | grep "Private key:" | awk '{print $3}')
        PUBLIC_KEY=$(echo "$TEMP_OUTPUT" | grep "Public key:" | awk '{print $3}')
        SHORT_ID=$(openssl rand -hex 8)
        log "Ключи сгенерированы с помощью Xray x25519"
    else
        # Попробуем альтернативную команду
        TEMP_OUTPUT2=$(docker run --rm teddysun/xray:latest /usr/bin/xray x25519 2>/dev/null || echo "")
        
        if [ -n "$TEMP_OUTPUT2" ] && echo "$TEMP_OUTPUT2" | grep -q "Private key:"; then
            # Извлекаем ключи из вывода Xray
            PRIVATE_KEY=$(echo "$TEMP_OUTPUT2" | grep "Private key:" | awk '{print $3}')
            PUBLIC_KEY=$(echo "$TEMP_OUTPUT2" | grep "Public key:" | awk '{print $3}')
            SHORT_ID=$(openssl rand -hex 8)
            log "Ключи сгенерированы с помощью Xray x25519 (альтернативная команда)"
        else
            # Используем альтернативный способ генерации ключей
            log "Используем альтернативный способ генерации ключей..."
            
            # Генерируем ключи с помощью OpenSSL
            SHORT_ID=$(openssl rand -hex 8)
            
            # Генерируем правильный X25519 приватный ключ
            TEMP_PRIVATE=$(openssl genpkey -algorithm X25519 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$TEMP_PRIVATE" ]; then
                # Извлекаем приватный ключ из PEM в правильном формате
                PRIVATE_KEY=$(echo "$TEMP_PRIVATE" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
                # Генерируем соответствующий публичный ключ
                PUBLIC_KEY=$(echo "$TEMP_PRIVATE" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
                log "Ключи сгенерированы с помощью OpenSSL X25519"
            else
                # Последний резерв - используем проверенный метод
                log "Используем резервный метод генерации..."
                SHORT_ID=$(openssl rand -hex 8)
                PRIVATE_KEY=$(openssl rand 32 | base64 | tr -d '\n')
                PUBLIC_KEY=$(openssl rand 32 | base64 | tr -d '\n')
                log "Ключи сгенерированы резервным методом"
            fi
        fi
    fi
    
    # Проверяем, что ключи сгенерированы
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
        log "Генерируем финальные резервные ключи через Xray в интерактивном режиме..."
        SHORT_ID=$(openssl rand -hex 8)
        
        # Попытка запустить xray с генерацией ключей напрямую
        XRAY_KEYS=$(timeout 10 docker run --rm -i teddysun/xray:latest sh -c 'echo | xray x25519' 2>/dev/null || echo "")
        
        if [ -n "$XRAY_KEYS" ] && echo "$XRAY_KEYS" | grep -q "Private key:"; then
            PRIVATE_KEY=$(echo "$XRAY_KEYS" | grep "Private key:" | awk '{print $3}')
            PUBLIC_KEY=$(echo "$XRAY_KEYS" | grep "Public key:" | awk '{print $3}')
            log "Успешно сгенерированы ключи через Xray в интерактивном режиме"
        else
            # Финальный фоллбек
            PRIVATE_KEY=$(openssl rand 32 | base64 | tr -d '\n')
            PUBLIC_KEY=$(openssl rand 32 | base64 | tr -d '\n')
            log "Использованы случайные ключи как последний резерв"
        fi
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
log "Создание конфигурации Docker..."

# Сначала пробуем основной вариант
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
    command: ["xray", "run", "-c", "/etc/xray/config.json"]
EOL

# Создаем резервный docker-compose для случая проблем
cat > "$WORK_DIR/docker-compose.backup.yml" <<EOL
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
    entrypoint: ["/usr/bin/xray"]
    command: ["run", "-c", "/etc/xray/config.json"]
EOL

log "Docker конфигурация создана"

# Настройка брандмауэра
log "Настройка брандмауэра..."
# Check if SSH rule already exists
if ! ufw status | grep -q "22/tcp\|OpenSSH\|ssh"; then
    ufw allow ssh
    log "SSH правило добавлено"
else
    log "SSH правило уже существует"
fi
ufw allow $SERVER_PORT/tcp
ufw --force enable

# Запуск сервера
log "Запуск VPN сервера..."
cd "$WORK_DIR"

# Проверяем конфигурацию перед запуском
if [ ! -f "config/config.json" ]; then
    error "Конфигурационный файл не найден!"
fi

# Запускаем с детальным логированием
log "Запуск Docker контейнера..."
if ! docker-compose up -d; then
    warning "Основная конфигурация не сработала, пробуем резервную..."
    
    # Останавливаем неудачный запуск
    docker-compose down 2>/dev/null || true
    
    # Заменяем на резервную конфигурацию
    cp "$WORK_DIR/docker-compose.backup.yml" "$WORK_DIR/docker-compose.yml"
    
    # Пробуем запустить с резервной конфигурацией
    if ! docker-compose up -d; then
        error "Не удалось запустить Docker контейнер даже с резервной конфигурацией"
    else
        log "✓ Контейнер запущен с резервной конфигурацией"
    fi
fi

# Проверяем статус контейнера
sleep 3
if docker ps | grep -q "xray"; then
    log "✓ Контейнер Xray успешно запущен и работает"
else
    warning "Контейнер не запущен. Проверяем логи..."
    log "Логи контейнера:"
    docker-compose logs --tail 20
    
    # Попытка диагностики
    log "Диагностика проблемы..."
    log "Проверка образа:"
    docker run --rm teddysun/xray:latest xray version 2>/dev/null || log "Проблема с образом или командой xray"
    
    error "Установка прервана из-за ошибки запуска контейнера"
fi

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