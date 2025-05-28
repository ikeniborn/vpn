#!/bin/bash

# Скрипт установки VLESS клиента с Web UI в Docker
# Использует v2rayA для веб-управления
# Поддержка Ubuntu, Debian, ALT Linux
# Автор: Claude
# Версия: 2.0

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Функции вывода сообщений
log() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗ [ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
    error "Пожалуйста, запустите скрипт с правами суперпользователя (sudo)"
fi

# Определение дистрибутива
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$(echo ${ID} | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$VERSION_ID
        OS_PRETTY_NAME=$PRETTY_NAME
        
        # Проверка на ALT Linux
        if [[ "${ID}" == "altlinux" ]] || [[ "${PRETTY_NAME}" =~ "ALT" ]]; then
            OS_NAME="altlinux"
            PACKAGE_MANAGER="apt-get"
            PACKAGE_UPDATE="apt-get update"
            PACKAGE_INSTALL="apt-get install -y"
        # Проверка на Debian/Ubuntu
        elif [[ "${ID}" == "debian" ]] || [[ "${ID}" == "ubuntu" ]]; then
            PACKAGE_MANAGER="apt"
            PACKAGE_UPDATE="apt update"
            PACKAGE_INSTALL="apt install -y"
        else
            error "Неподдерживаемый дистрибутив: ${PRETTY_NAME}"
        fi
    else
        error "Не удается определить дистрибутив. Файл /etc/os-release не найден."
    fi
    
    log "Определен дистрибутив: ${OS_PRETTY_NAME}"
}

# Установка Docker
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker уже установлен"
        return
    fi
    
    log "Установка Docker..."
    
    case $OS_NAME in
        altlinux)
            # Установка Docker на ALT Linux
            $PACKAGE_UPDATE
            $PACKAGE_INSTALL docker-ce docker-ce-cli containerd.io docker-compose-plugin curl wget
            systemctl enable docker
            systemctl start docker
            ;;
        debian|ubuntu)
            # Установка Docker на Debian/Ubuntu
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh
            systemctl enable docker
            systemctl start docker
            ;;
        *)
            error "Установка Docker не поддерживается для $OS_NAME"
            ;;
    esac
    
    # Проверка установки
    if command -v docker >/dev/null 2>&1; then
        log "Docker успешно установлен"
    else
        error "Не удалось установить Docker"
    fi
}

# Установка Docker Compose
install_docker_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        log "Docker Compose уже установлен"
        return
    fi
    
    log "Установка Docker Compose..."
    
    # Определение архитектуры
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            COMPOSE_ARCH="x86_64"
            ;;
        aarch64|arm64)
            COMPOSE_ARCH="aarch64"
            ;;
        armv7l|armhf)
            COMPOSE_ARCH="armv7l"
            ;;
        *)
            error "Неподдерживаемая архитектура: $ARCH"
            ;;
    esac
    
    # Загрузка последней версии Docker Compose
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    if command -v docker-compose >/dev/null 2>&1; then
        log "Docker Compose успешно установлен"
    else
        error "Не удалось установить Docker Compose"
    fi
}

# Установка дополнительных пакетов
install_dependencies() {
    log "Установка дополнительных пакетов..."
    
    case $OS_NAME in
        altlinux)
            $PACKAGE_UPDATE
            $PACKAGE_INSTALL openssl curl wget net-tools
            ;;
        debian|ubuntu)
            $PACKAGE_UPDATE
            $PACKAGE_INSTALL openssl curl wget net-tools
            ;;
    esac
    
    log "Дополнительные пакеты установлены"
}

# Создание рабочей директории
WORK_DIR="/opt/v2raya-client"
CONFIG_DIR="$WORK_DIR/config"
DATA_DIR="$WORK_DIR/data"

create_directories() {
    log "Создание рабочих директорий..."
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$WORK_DIR/nginx/conf.d"
    mkdir -p "$WORK_DIR/nginx/ssl"
    chmod -R 755 "$WORK_DIR"
    log "Директории созданы"
}

# Функция проверки порта
check_port_available() {
    local port=$1
    if command -v netstat >/dev/null 2>&1; then
        ! netstat -tuln | grep -q ":$port "
    elif command -v ss >/dev/null 2>&1; then
        ! ss -tuln | grep -q ":$port "
    else
        ! timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null
    fi
}

# Генерация свободного порта
generate_free_port() {
    local min_port=${1:-2017}
    local max_port=${2:-3017}
    local port
    
    for i in {1..20}; do
        port=$((RANDOM % (max_port - min_port + 1) + min_port))
        if check_port_available $port; then
            echo $port
            return 0
        fi
    done
    
    echo 2017
    return 1
}

# Генерация случайного пароля
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-16
}

# Настройка параметров
configure_installation() {
    echo ""
    echo -e "${GREEN}🔧 Настройка параметров установки${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    
    # Порт веб-интерфейса
    echo -e "${GREEN}🌐 Настройка порта веб-интерфейса:${NC}"
    echo -e "   ${YELLOW}1${NC} 🎲 Автоматический выбор порта"
    echo -e "   ${YELLOW}2${NC} ✏️  Указать порт вручную"
    echo -e "   ${YELLOW}3${NC} 🏢 Использовать стандартный порт (2017)"
    echo ""
    read -p "$(echo -e ${GREEN}Ваш выбор [1]:${NC} )" PORT_CHOICE
    PORT_CHOICE=${PORT_CHOICE:-1}
    
    case $PORT_CHOICE in
        1)
            WEB_PORT=$(generate_free_port 2017 3017)
            log "Выбран порт веб-интерфейса: $WEB_PORT"
            ;;
        2)
            while true; do
                read -p "Введите порт для веб-интерфейса [2017]: " WEB_PORT
                WEB_PORT=${WEB_PORT:-2017}
                
                if ! [[ "$WEB_PORT" =~ ^[0-9]+$ ]] || [ "$WEB_PORT" -lt 1024 ] || [ "$WEB_PORT" -gt 65535 ]; then
                    warning "Некорректный порт. Введите число от 1024 до 65535."
                    continue
                fi
                
                if check_port_available $WEB_PORT; then
                    log "Порт $WEB_PORT свободен"
                    break
                else
                    warning "Порт $WEB_PORT уже используется"
                    read -p "Использовать занятый порт? (y/n): " use_port
                    if [ "$use_port" = "y" ]; then
                        break
                    fi
                fi
            done
            ;;
        3)
            WEB_PORT=2017
            ;;
        *)
            WEB_PORT=$(generate_free_port 2017 3017)
            ;;
    esac
    
    # Пароль администратора
    echo ""
    echo -e "${GREEN}🔐 Настройка пароля администратора:${NC}"
    echo -e "   ${YELLOW}1${NC} 🎲 Сгенерировать случайный пароль"
    echo -e "   ${YELLOW}2${NC} ✏️  Указать свой пароль"
    echo ""
    read -p "$(echo -e ${GREEN}Ваш выбор [1]:${NC} )" PASS_CHOICE
    PASS_CHOICE=${PASS_CHOICE:-1}
    
    case $PASS_CHOICE in
        1)
            ADMIN_PASSWORD=$(generate_password)
            log "Сгенерирован пароль администратора"
            ;;
        2)
            while true; do
                read -s -p "Введите пароль администратора: " ADMIN_PASSWORD
                echo
                if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
                    warning "Пароль должен содержать минимум 8 символов"
                    continue
                fi
                read -s -p "Повторите пароль: " ADMIN_PASSWORD_CONFIRM
                echo
                if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
                    warning "Пароли не совпадают"
                    continue
                fi
                break
            done
            ;;
        *)
            ADMIN_PASSWORD=$(generate_password)
            ;;
    esac
    
    # Настройка HTTPS
    echo ""
    read -p "Включить HTTPS для веб-интерфейса? (y/n) [n]: " ENABLE_HTTPS
    ENABLE_HTTPS=${ENABLE_HTTPS:-n}
    
    if [ "$ENABLE_HTTPS" = "y" ]; then
        HTTPS_PORT=$(generate_free_port 2443 3443)
        log "Выбран HTTPS порт: $HTTPS_PORT"
        
        # Генерация самоподписанного сертификата
        log "Генерация SSL сертификата..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$WORK_DIR/nginx/ssl/server.key" \
            -out "$WORK_DIR/nginx/ssl/server.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=v2raya.local" 2>/dev/null
    fi
}

# Создание конфигурации v2rayA
create_v2raya_config() {
    log "Создание конфигурации v2rayA..."
    
    # Создаем базовую конфигурацию
    cat > "$CONFIG_DIR/v2raya.conf" <<EOF
# v2rayA configuration
V2RAYA_ADDRESS=0.0.0.0:2017
V2RAYA_CONFIG=/etc/v2raya
EOF
}

# Создание конфигурации nginx
create_nginx_config() {
    log "Создание конфигурации nginx..."
    
    if [ "$ENABLE_HTTPS" = "y" ]; then
        cat > "$WORK_DIR/nginx/conf.d/v2raya.conf" <<EOF
server {
    listen 80;
    server_name _;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;
    
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://v2raya:2017;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
}
EOF
    else
        cat > "$WORK_DIR/nginx/conf.d/v2raya.conf" <<EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://v2raya:2017;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
}
EOF
    fi
}

# Создание docker-compose.yml
create_docker_compose() {
    log "Создание Docker Compose конфигурации..."
    
    cat > "$WORK_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  v2raya:
    image: mzz2017/v2raya:latest
    container_name: v2raya
    restart: unless-stopped
    privileged: true
    network_mode: host
    volumes:
      - ./data:/etc/v2raya
      - /lib/modules:/lib/modules:ro
      - /etc/resolv.conf:/etc/resolv.conf
    environment:
      - V2RAYA_ADDRESS=0.0.0.0:2017
      - V2RAYA_LOG_FILE=/var/log/v2raya/v2raya.log
      - IPTABLES_MODE=tproxy
      - V2RAYA_TRANSPARENT=true
EOF

    # Если не используем nginx, открываем порт напрямую
    if [ "$ENABLE_HTTPS" != "y" ]; then
        cat >> "$WORK_DIR/docker-compose.yml" <<EOF
    ports:
      - "${WEB_PORT}:2017"
EOF
    fi

    cat >> "$WORK_DIR/docker-compose.yml" <<EOF

  nginx:
    image: nginx:alpine
    container_name: v2raya-nginx
    restart: unless-stopped
    ports:
EOF

    if [ "$ENABLE_HTTPS" = "y" ]; then
        cat >> "$WORK_DIR/docker-compose.yml" <<EOF
      - "${WEB_PORT}:80"
      - "${HTTPS_PORT}:443"
EOF
    else
        cat >> "$WORK_DIR/docker-compose.yml" <<EOF
      - "${WEB_PORT}:80"
EOF
    fi

    cat >> "$WORK_DIR/docker-compose.yml" <<EOF
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - v2raya
    networks:
      - v2raya-network

networks:
  v2raya-network:
    driver: bridge
EOF
}

# Создание docker-compose для простой установки без nginx
create_simple_docker_compose() {
    log "Создание упрощенной Docker Compose конфигурации..."
    
    cat > "$WORK_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  v2raya:
    image: mzz2017/v2raya:latest
    container_name: v2raya
    restart: unless-stopped
    privileged: true
    network_mode: host
    ports:
      - "${WEB_PORT}:2017"
    volumes:
      - ./data:/etc/v2raya
      - /lib/modules:/lib/modules:ro
      - /etc/resolv.conf:/etc/resolv.conf
    environment:
      - V2RAYA_ADDRESS=0.0.0.0:2017
      - V2RAYA_LOG_FILE=/var/log/v2raya/v2raya.log
      - IPTABLES_MODE=tproxy
      - V2RAYA_TRANSPARENT=true
EOF
}

# Создание скрипта управления
create_management_script() {
    local script_path="/usr/local/bin/v2raya-client"
    
    cat > "$script_path" <<'EOF'
#!/bin/bash

WORK_DIR="/opt/v2raya-client"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_menu() {
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}      ${GREEN}v2rayA Client Management${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "1. 🌐 Открыть веб-интерфейс"
    echo "2. ▶️  Запустить v2rayA"
    echo "3. ⏹️  Остановить v2rayA"
    echo "4. 🔄 Перезапустить v2rayA"
    echo "5. 📊 Статус служб"
    echo "6. 📝 Просмотр логов"
    echo "7. 🔧 Информация о подключении"
    echo "8. 🔐 Сбросить пароль администратора"
    echo "9. 🆙 Обновить v2rayA"
    echo "0. 🚪 Выход"
    echo ""
}

get_connection_info() {
    if [ -f "$WORK_DIR/.env" ]; then
        source "$WORK_DIR/.env"
    fi
    
    local ip=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}Информация о подключении:${NC}"
    echo -e "  Веб-интерфейс: ${YELLOW}http://$ip:$WEB_PORT${NC}"
    if [ "$ENABLE_HTTPS" = "y" ]; then
        echo -e "  HTTPS: ${YELLOW}https://$ip:$HTTPS_PORT${NC}"
    fi
    echo -e "  Логин: ${YELLOW}admin${NC}"
    if [ -n "$ADMIN_PASSWORD" ]; then
        echo -e "  Пароль: ${YELLOW}$ADMIN_PASSWORD${NC}"
    fi
    echo ""
    echo -e "${BLUE}Подключение через браузер:${NC}"
    echo -e "  1. Откройте браузер"
    echo -e "  2. Перейдите по адресу выше"
    echo -e "  3. Войдите с указанными данными"
}

open_webui() {
    local ip=$(hostname -I | awk '{print $1}')
    local url="http://$ip:$WEB_PORT"
    
    echo -e "${GREEN}Открытие веб-интерфейса...${NC}"
    echo -e "URL: ${YELLOW}$url${NC}"
    
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" 2>/dev/null
    else
        echo -e "${YELLOW}Откройте в браузере: $url${NC}"
    fi
}

status_services() {
    echo -e "${GREEN}Статус служб:${NC}"
    cd "$WORK_DIR"
    docker-compose ps
}

view_logs() {
    echo -e "${GREEN}Выберите службу для просмотра логов:${NC}"
    echo "1. v2rayA"
    echo "2. Nginx (если используется)"
    echo "3. Все службы"
    read -p "Выбор: " log_choice
    
    cd "$WORK_DIR"
    case $log_choice in
        1) docker-compose logs -f --tail=50 v2raya;;
        2) docker-compose logs -f --tail=50 nginx;;
        3) docker-compose logs -f --tail=50;;
        *) docker-compose logs -f --tail=50;;
    esac
}

reset_password() {
    echo -e "${YELLOW}Сброс пароля администратора...${NC}"
    local new_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
    
    # Обновляем пароль в файле окружения
    if [ -f "$WORK_DIR/.env" ]; then
        sed -i "s/ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$new_password/" "$WORK_DIR/.env"
    else
        echo "ADMIN_PASSWORD=$new_password" > "$WORK_DIR/.env"
    fi
    
    echo -e "${GREEN}Новый пароль: ${YELLOW}$new_password${NC}"
    echo -e "${YELLOW}Запишите этот пароль!${NC}"
}

update_v2raya() {
    echo -e "${GREEN}Обновление v2rayA...${NC}"
    cd "$WORK_DIR"
    docker-compose pull
    docker-compose up -d
    echo -e "${GREEN}v2rayA обновлен${NC}"
}

while true; do
    show_menu
    read -p "Выберите действие: " choice
    
    case $choice in
        1) open_webui;;
        2) 
            cd "$WORK_DIR"
            docker-compose up -d
            echo -e "${GREEN}v2rayA запущен${NC}"
            ;;
        3)
            cd "$WORK_DIR"
            docker-compose down
            echo -e "${GREEN}v2rayA остановлен${NC}"
            ;;
        4)
            cd "$WORK_DIR"
            docker-compose restart
            echo -e "${GREEN}v2rayA перезапущен${NC}"
            ;;
        5) status_services;;
        6) view_logs;;
        7) get_connection_info;;
        8) reset_password;;
        9) update_v2raya;;
        0) exit 0;;
        *) echo -e "${RED}Неверный выбор${NC}";;
    esac
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
    clear
done
EOF

    chmod +x "$script_path"
    log "Скрипт управления создан: $script_path"
}

# Сохранение конфигурации
save_configuration() {
    cat > "$WORK_DIR/.env" <<EOF
# v2rayA Client Configuration
WEB_PORT=$WEB_PORT
ENABLE_HTTPS=$ENABLE_HTTPS
HTTPS_PORT=${HTTPS_PORT:-}
ADMIN_PASSWORD=$ADMIN_PASSWORD
INSTALL_DATE=$(date -Iseconds)
EOF
    
    chmod 600 "$WORK_DIR/.env"
    log "Конфигурация сохранена"
}

# Запуск служб
start_services() {
    log "Запуск v2rayA..."
    
    cd "$WORK_DIR"
    
    # Остановка существующих контейнеров
    if docker ps -a | grep -q "v2raya"; then
        log "Остановка существующих контейнеров..."
        docker-compose down
    fi
    
    # Запуск новых контейнеров
    if docker-compose up -d; then
        log "v2rayA успешно запущен"
    else
        error "Не удалось запустить v2rayA"
    fi
    
    # Проверка статуса
    sleep 5
    if docker ps | grep -q "v2raya"; then
        log "Контейнеры работают нормально"
    else
        error "Контейнеры не запустились. Проверьте логи: docker-compose logs"
    fi
}

# Настройка файрвола
setup_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        log "Настройка UFW..."
        ufw allow $WEB_PORT/tcp comment "v2rayA Web UI"
        if [ "$ENABLE_HTTPS" = "y" ]; then
            ufw allow $HTTPS_PORT/tcp comment "v2rayA HTTPS"
        fi
        ufw reload
    elif command -v firewall-cmd >/dev/null 2>&1; then
        log "Настройка firewalld..."
        firewall-cmd --permanent --add-port=$WEB_PORT/tcp
        if [ "$ENABLE_HTTPS" = "y" ]; then
            firewall-cmd --permanent --add-port=$HTTPS_PORT/tcp
        fi
        firewall-cmd --reload
    fi
}

# Показ информации об установке
show_installation_info() {
    local ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}    🎉 ${WHITE}v2rayA КЛИЕНТ УСПЕШНО УСТАНОВЛЕН!${NC} 🎉        ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}🌐 Доступ к веб-интерфейсу:${NC}"
    echo -e "  • Локально: ${YELLOW}http://localhost:$WEB_PORT${NC}"
    echo -e "  • По сети: ${YELLOW}http://$ip:$WEB_PORT${NC}"
    if [ "$ENABLE_HTTPS" = "y" ]; then
        echo -e "  • HTTPS: ${YELLOW}https://$ip:$HTTPS_PORT${NC}"
    fi
    echo ""
    echo -e "${BLUE}🔐 Данные для входа:${NC}"
    echo -e "  • Логин: ${YELLOW}admin${NC}"
    echo -e "  • Пароль: ${YELLOW}$ADMIN_PASSWORD${NC}"
    echo ""
    echo -e "${BLUE}📱 Возможности v2rayA:${NC}"
    echo -e "  ✓ Поддержка VLESS, VMess, Trojan, Shadowsocks"
    echo -e "  ✓ Импорт конфигураций по ссылкам"
    echo -e "  ✓ Управление подписками"
    echo -e "  ✓ Правила маршрутизации"
    echo -e "  ✓ Прозрачный прокси"
    echo -e "  ✓ Статистика трафика"
    echo ""
    echo -e "${BLUE}🔧 Управление клиентом:${NC}"
    echo -e "  Используйте команду: ${YELLOW}sudo v2raya-client${NC}"
    echo ""
    echo -e "${PURPLE}💡 Первые шаги:${NC}"
    echo -e "  1. Откройте веб-интерфейс в браузере"
    echo -e "  2. Войдите с указанными данными"
    echo -e "  3. Нажмите '+' для добавления сервера"
    echo -e "  4. Вставьте ссылку vless:// или другую"
    echo -e "  5. Выберите сервер и нажмите 'Connect'"
    echo ""
    echo -e "${YELLOW}⚠️  ВАЖНО: Сохраните пароль администратора!${NC}"
    echo ""
}

# Основная функция установки
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   🚀 ${GREEN}Установка v2rayA клиента с Web UI${NC}    ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Определение ОС
    detect_os
    
    # Установка компонентов
    install_docker
    install_docker_compose
    install_dependencies
    
    # Создание директорий
    create_directories
    
    # Настройка параметров
    configure_installation
    
    # Создание конфигураций
    create_v2raya_config
    
    # Выбор типа установки
    if [ "$ENABLE_HTTPS" = "y" ]; then
        create_nginx_config
        create_docker_compose
    else
        create_simple_docker_compose
    fi
    
    # Сохранение конфигурации
    save_configuration
    
    # Создание скрипта управления
    create_management_script
    
    # Запуск служб
    start_services
    
    # Настройка файрвола
    setup_firewall
    
    # Показ информации
    show_installation_info
}

# Запуск основной функции
main