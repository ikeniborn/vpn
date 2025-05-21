#!/bin/bash

# Скрипт управления пользователями для v2ray vless+reality
# Автор: Claude

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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
command -v docker >/dev/null 2>&1 || error "Docker не установлен."
command -v uuid >/dev/null 2>&1 || error "uuid-runtime не установлен. Установите с помощью 'apt install uuid-runtime'"
command -v qrencode >/dev/null 2>&1 || {
    log "qrencode не установлен. Установка qrencode..."
    apt update
    apt install -y qrencode
}
command -v jq >/dev/null 2>&1 || {
    log "jq не установлен. Установка jq..."
    apt update
    apt install -y jq
}

# Определение рабочей директории
WORK_DIR="/opt/v2ray"
CONFIG_FILE="$WORK_DIR/config/config.json"
USERS_DIR="$WORK_DIR/users"

# Проверка существования директории и конфигурационного файла
if [ ! -d "$WORK_DIR" ] || [ ! -f "$CONFIG_FILE" ]; then
    error "Директория VPN сервера не существует или сервер не установлен. Сначала запустите скрипт установки."
fi

# Создание директории пользователей, если не существует
mkdir -p "$USERS_DIR"

# Получение информации о сервере
SERVER_IP=$(curl -s https://api.ipify.org)

get_server_info() {
    if [ -f "$CONFIG_FILE" ]; then
        SERVER_PORT=$(jq '.inbounds[0].port' "$CONFIG_FILE")
        
        # Чтение SNI из файла, если он существует
        if [ -f "$WORK_DIR/config/sni.txt" ]; then
            SERVER_SNI=$(cat "$WORK_DIR/config/sni.txt")
        else
            SERVER_SNI="www.microsoft.com"
        fi
        
        # Получение публичного ключа из файла любого пользователя, если он существует
        local first_user_file=$(ls -1 "$USERS_DIR"/*.json 2>/dev/null | head -1)
        if [ -n "$first_user_file" ]; then
            PUBLIC_KEY=$(jq -r '.public_key' "$first_user_file")
            PRIVATE_KEY=$(jq -r '.private_key' "$first_user_file")
        else
            # Если файлов пользователей нет, используем значения по умолчанию
            warning "Нет информации о ключах. Используйте скрипт установки или добавьте ключи вручную."
            PUBLIC_KEY="unknown"
            PRIVATE_KEY="unknown"
        fi
    else
        error "Файл конфигурации не найден: $CONFIG_FILE"
    fi
}

# Отображение списка всех пользователей
list_users() {
    log "Список пользователей:"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "${BLUE}| Имя пользователя | UUID |${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    # Получение списка пользователей из конфигурации
    jq -r '.inbounds[0].settings.clients[] | "| " + (.email // "Без имени") + " | " + .id + " |"' "$CONFIG_FILE"
    
    echo -e "${BLUE}----------------------------------------${NC}"
}

# Добавление нового пользователя
add_user() {
    get_server_info
    
    # Запрос данных нового пользователя
    read -p "Введите имя нового пользователя: " USER_NAME
    
    # Проверка на существование пользователя
    if jq -e ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\")" "$CONFIG_FILE" > /dev/null; then
        error "Пользователь с именем '$USER_NAME' уже существует."
    fi
    
    # Генерация UUID
    USER_UUID=$(uuid -v 4)
    read -p "Введите UUID для пользователя [$USER_UUID]: " INPUT_UUID
    USER_UUID=${INPUT_UUID:-$USER_UUID}
    
    # Добавление пользователя в конфигурацию
    jq ".inbounds[0].settings.clients += [{\"id\": \"$USER_UUID\", \"flow\": \"\", \"email\": \"$USER_NAME\"}]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    # Создание файла с информацией о пользователе
    cat > "$USERS_DIR/$USER_NAME.json" <<EOL
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
    REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
    echo "$REALITY_LINK" > "$USERS_DIR/$USER_NAME.link"
    
    # Генерация QR-кода
    qrencode -t PNG -o "$USERS_DIR/$USER_NAME.png" "$REALITY_LINK"
    
    # Перезапуск сервера для применения изменений
    restart_server
    
    log "Пользователь '$USER_NAME' успешно добавлен!"
    log "UUID: $USER_UUID"
    log "Ссылка для подключения сохранена в: $USERS_DIR/$USER_NAME.link"
    log "QR-код сохранен в: $USERS_DIR/$USER_NAME.png"
    
    # Вывод ссылки и QR-кода в терминал
    echo "Ссылка для подключения:"
    echo "$REALITY_LINK"
    echo "QR-код:"
    qrencode -t ANSIUTF8 "$REALITY_LINK"
}

# Удаление пользователя
delete_user() {
    list_users
    
    read -p "Введите имя пользователя для удаления: " USER_NAME
    
    # Проверка существования пользователя
    if ! jq -e ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\")" "$CONFIG_FILE" > /dev/null; then
        error "Пользователь с именем '$USER_NAME' не найден."
    fi
    
    # Удаление пользователя из конфигурации
    jq "del(.inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\"))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    # Удаление файлов пользователя
    rm -f "$USERS_DIR/$USER_NAME.json" "$USERS_DIR/$USER_NAME.link" "$USERS_DIR/$USER_NAME.png"
    
    # Перезапуск сервера для применения изменений
    restart_server
    
    log "Пользователь '$USER_NAME' успешно удален!"
}

# Изменение данных пользователя
edit_user() {
    list_users
    
    read -p "Введите имя пользователя для редактирования: " USER_NAME
    
    # Проверка существования пользователя
    if ! jq -e ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\")" "$CONFIG_FILE" > /dev/null; then
        error "Пользователь с именем '$USER_NAME' не найден."
    fi
    
    # Получение текущего UUID пользователя
    CURRENT_UUID=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\") | .id" "$CONFIG_FILE")
    
    # Запрос нового имени пользователя
    read -p "Введите новое имя пользователя [$USER_NAME]: " NEW_USER_NAME
    NEW_USER_NAME=${NEW_USER_NAME:-$USER_NAME}
    
    # Запрос нового UUID
    read -p "Введите новый UUID [$CURRENT_UUID]: " NEW_UUID
    NEW_UUID=${NEW_UUID:-$CURRENT_UUID}
    
    # Проверка, не занято ли новое имя
    if [ "$NEW_USER_NAME" != "$USER_NAME" ] && jq -e ".inbounds[0].settings.clients[] | select(.email == \"$NEW_USER_NAME\")" "$CONFIG_FILE" > /dev/null; then
        error "Пользователь с именем '$NEW_USER_NAME' уже существует."
    fi
    
    # Удаляем старого пользователя
    jq "del(.inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\"))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    
    # Добавляем нового пользователя
    jq ".inbounds[0].settings.clients += [{\"id\": \"$NEW_UUID\", \"flow\": \"\", \"email\": \"$NEW_USER_NAME\"}]" "$CONFIG_FILE.tmp" > "$CONFIG_FILE"
    rm "$CONFIG_FILE.tmp"
    
    # Удаление старых файлов и создание новых
    rm -f "$USERS_DIR/$USER_NAME.json" "$USERS_DIR/$USER_NAME.link" "$USERS_DIR/$USER_NAME.png"
    
    # Получаем информацию о сервере
    get_server_info
    
    # Создание файла с информацией о пользователе
    cat > "$USERS_DIR/$NEW_USER_NAME.json" <<EOL
{
  "name": "$NEW_USER_NAME",
  "uuid": "$NEW_UUID",
  "port": $SERVER_PORT,
  "server": "$SERVER_IP",
  "sni": "$SERVER_SNI",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY"
}
EOL
    
    # Создание ссылки для подключения
    REALITY_LINK="vless://$NEW_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$NEW_USER_NAME"
    echo "$REALITY_LINK" > "$USERS_DIR/$NEW_USER_NAME.link"
    
    # Генерация QR-кода
    qrencode -t PNG -o "$USERS_DIR/$NEW_USER_NAME.png" "$REALITY_LINK"
    
    # Перезапуск сервера для применения изменений
    restart_server
    
    log "Пользователь успешно изменен!"
    log "Новое имя: $NEW_USER_NAME"
    log "Новый UUID: $NEW_UUID"
    log "Ссылка для подключения сохранена в: $USERS_DIR/$NEW_USER_NAME.link"
    log "QR-код сохранен в: $USERS_DIR/$NEW_USER_NAME.png"
    
    # Вывод ссылки и QR-кода в терминал
    echo "Ссылка для подключения:"
    echo "$REALITY_LINK"
    echo "QR-код:"
    qrencode -t ANSIUTF8 "$REALITY_LINK"
}

# Показать данные пользователя
show_user() {
    list_users
    
    read -p "Введите имя пользователя для отображения информации: " USER_NAME
    
    # Проверка существования пользователя
    if ! jq -e ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\")" "$CONFIG_FILE" > /dev/null; then
        error "Пользователь с именем '$USER_NAME' не найден."
    fi
    
    # Проверка наличия файла с данными пользователя
    if [ ! -f "$USERS_DIR/$USER_NAME.json" ]; then
        warning "Файл с данными пользователя не найден. Создаем новый файл."
        
        # Получаем информацию о сервере
        get_server_info
        
        # Получаем UUID пользователя
        USER_UUID=$(jq -r ".inbounds[0].settings.clients[] | select(.email == \"$USER_NAME\") | .id" "$CONFIG_FILE")
        
        # Создание файла с информацией о пользователе
        cat > "$USERS_DIR/$USER_NAME.json" <<EOL
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
        REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
        echo "$REALITY_LINK" > "$USERS_DIR/$USER_NAME.link"
        
        # Генерация QR-кода
        qrencode -t PNG -o "$USERS_DIR/$USER_NAME.png" "$REALITY_LINK"
    else
        # Получение данных из файла
        USER_UUID=$(jq -r '.uuid' "$USERS_DIR/$USER_NAME.json")
        SERVER_PORT=$(jq -r '.port' "$USERS_DIR/$USER_NAME.json")
        SERVER_SNI=$(jq -r '.sni' "$USERS_DIR/$USER_NAME.json")
        PUBLIC_KEY=$(jq -r '.public_key' "$USERS_DIR/$USER_NAME.json")
        
        # Обновление IP-адреса, если изменился
        SERVER_IP=$(curl -s https://api.ipify.org)
        jq ".server = \"$SERVER_IP\"" "$USERS_DIR/$USER_NAME.json" > "$USERS_DIR/$USER_NAME.json.tmp"
        mv "$USERS_DIR/$USER_NAME.json.tmp" "$USERS_DIR/$USER_NAME.json"
        
        # Обновление ссылки для подключения
        REALITY_LINK="vless://$USER_UUID@$SERVER_IP:$SERVER_PORT?encryption=none&security=none&type=tcp#$USER_NAME"
        echo "$REALITY_LINK" > "$USERS_DIR/$USER_NAME.link"
        
        # Обновление QR-кода
        qrencode -t PNG -o "$USERS_DIR/$USER_NAME.png" "$REALITY_LINK"
    fi
    
    log "Информация о пользователе '$USER_NAME':"
    log "UUID: $USER_UUID"
    log "IP сервера: $SERVER_IP"
    log "Порт: $SERVER_PORT"
    log "SNI: $SERVER_SNI"
    log "Ссылка для подключения сохранена в: $USERS_DIR/$USER_NAME.link"
    log "QR-код сохранен в: $USERS_DIR/$USER_NAME.png"
    
    # Вывод ссылки и QR-кода в терминал
    echo "Ссылка для подключения:"
    echo "$REALITY_LINK"
    echo "QR-код:"
    qrencode -t ANSIUTF8 "$REALITY_LINK"
}

# Перезапуск v2ray сервера
restart_server() {
    log "Перезапуск VPN сервера..."
    cd "$WORK_DIR"
    docker-compose restart
    log "VPN сервер успешно перезапущен!"
}

# Отображение статуса сервера
show_status() {
    log "Статус VPN сервера:"
    cd "$WORK_DIR"
    docker-compose ps
    
    # Проверка открытых портов
    log "Проверка портов:"
    PORT=$(jq '.inbounds[0].port' "$CONFIG_FILE")
    
    # Проверка доступных команд для проверки портов
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$PORT"; then
            log "Порт $PORT открыт и слушает соединения."
        else
            warning "Порт $PORT закрыт или не слушает соединения!"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$PORT"; then
            log "Порт $PORT открыт и слушает соединения."
        else
            warning "Порт $PORT закрыт или не слушает соединения!"
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i ":$PORT" -P -n | grep -q "LISTEN"; then
            log "Порт $PORT открыт и слушает соединения."
        else
            warning "Порт $PORT закрыт или не слушает соединения!"
        fi
    else
        warning "Не удалось проверить статус порта $PORT. Установите netstat, ss или lsof."
    fi
    
    # Вывод информации о сервере
    get_server_info
    log "IP адрес: $SERVER_IP"
    log "Порт: $SERVER_PORT"
    log "SNI: $SERVER_SNI"

    # Если SNI пустой или "null", отобразим соответствующее сообщение
    if [ "$SERVER_SNI" = "null" ] || [ -z "$SERVER_SNI" ]; then
        log "Используется базовый протокол VLESS без SNI"
    fi
    
    # Количество пользователей
    USERS_COUNT=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    log "Количество пользователей: $USERS_COUNT"
}

# Отображение меню
show_menu() {
    clear
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}=     Управление V2Ray VPN сервером       =${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}= 1. Список пользователей                 =${NC}"
    echo -e "${BLUE}= 2. Добавить пользователя                =${NC}"
    echo -e "${BLUE}= 3. Удалить пользователя                 =${NC}"
    echo -e "${BLUE}= 4. Изменить пользователя                =${NC}"
    echo -e "${BLUE}= 5. Показать данные пользователя         =${NC}"
    echo -e "${BLUE}= 6. Статус сервера                       =${NC}"
    echo -e "${BLUE}= 7. Перезапустить сервер                 =${NC}"
    echo -e "${BLUE}= 0. Выход                                =${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    read -p "Выберите действие [0-7]: " choice
    
    case $choice in
        1) list_users; press_enter ;;
        2) add_user; press_enter ;;
        3) delete_user; press_enter ;;
        4) edit_user; press_enter ;;
        5) show_user; press_enter ;;
        6) show_status; press_enter ;;
        7) restart_server; press_enter ;;
        0) exit 0 ;;
        *) error "Некорректный выбор! Попробуйте снова." ;;
    esac
}

# Функция ожидания нажатия Enter
press_enter() {
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Главный цикл
while true; do
    show_menu
done