#!/bin/bash

# VPN Project User Interface Library
# Handles menu display, user input, progress indicators, and UI components

# Source common library
if [ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# ========================= MENU COMPONENTS =========================

# Draw a header around text (no box)
draw_box() {
    local text="$1"
    local width="${2:-50}"
    local char="${3:-=}"
    
    # Simple header with separator
    echo -e "${GREEN}=== $text ===${NC}"
}

# Create a simple separator line
separator() {
    local length="${1:-50}"
    local char="${2:-=}"
    echo -e "${BLUE}$(printf "%*s" $length "" | tr ' ' "$char")${NC}"
}

# Display header with title
show_header() {
    local title="$1"
    local subtitle="$2"
    
    clear
    echo ""
    draw_box "🛡️  $title" 50
    
    if [ -n "$subtitle" ]; then
        echo ""
        echo -e "  ${BLUE}$subtitle${NC}"
    fi
    echo ""
}

# ========================= MENU FUNCTIONS =========================

# Display main VPN management menu
show_main_menu() {
    show_header "Управление Xray VPN сервером"
    
    echo -e "  ${GREEN}👥 Управление пользователями:${NC}"
    echo -e "    ${YELLOW}1${NC}  📋 Список пользователей"
    echo -e "    ${YELLOW}2${NC}  ➕ Добавить пользователя"
    echo -e "    ${YELLOW}3${NC}  ❌ Удалить пользователя"
    echo -e "    ${YELLOW}4${NC}  ✏️  Изменить пользователя"
    echo -e "    ${YELLOW}5${NC}  👤 Показать данные пользователя"
    echo ""
    echo -e "  ${GREEN}⚙️  Управление сервером:${NC}"
    echo -e "    ${YELLOW}6${NC}  📊 Статус сервера"
    echo -e "    ${YELLOW}7${NC}  🔄 Перезапустить сервер"
    echo -e "    ${YELLOW}8${NC}  🔐 Ротация Reality ключей"
    echo ""
    echo -e "  ${GREEN}📈 Мониторинг и статистика:${NC}"
    echo -e "    ${YELLOW}9${NC}  📊 Статистика использования"
    echo -e "    ${YELLOW}10${NC} 📝 Настройка логирования Xray"
    echo -e "    ${YELLOW}11${NC} 📋 Просмотр логов пользователей"
    echo -e "    ${YELLOW}12${NC} 🛡️  Управление Watchdog службой"
    echo ""
    echo -e "  ${RED}⚠️  Опасная зона:${NC}"
    echo -e "    ${YELLOW}13${NC} 🗑️  Удалить VPN сервер"
    echo ""
    echo -e "    ${YELLOW}0${NC}  🚪 Выход"
    echo ""
    separator
    echo ""
}

# Show installation type selection menu
show_installation_menu() {
    show_header "Установщик VPN сервера" "Выберите тип VPN для установки"
    
    echo -e "   ${YELLOW}1${NC} 🚀 ${WHITE}Xray VPN${NC} (VLESS+Reality)"
    echo -e "      ${PURPLE}↳${NC} Рекомендуется для обхода блокировок 🛡️"
    echo -e "   ${YELLOW}2${NC} 📱 ${WHITE}Outline VPN${NC} (Shadowsocks)"
    echo -e "      ${PURPLE}↳${NC} Простота управления через приложение 🎮"
    echo ""
}

# Show client information for different platforms
show_client_info() {
    local vpn_type="${1:-xray}"
    
    echo ""
    draw_box "📱 Рекомендуемые клиенты для $vpn_type VPN" 50
    echo ""
    
    case "$vpn_type" in
        "xray"|"Xray")
            echo -e "  ${GREEN}🤖 Android:${NC}"
            echo -e "    ${YELLOW}•${NC} v2RayTun"
            echo -e "      ${PURPLE}↳${NC} ${WHITE}play.google.com/store/apps/details?id=com.v2raytun.android${NC}"
            echo ""
            echo -e "  ${GREEN}🍎 iOS:${NC}"
            echo -e "    ${YELLOW}•${NC} Shadowrocket"
            echo -e "      ${PURPLE}↳${NC} ${WHITE}apps.apple.com/app/shadowrocket/id932747118${NC}"
            echo -e "    ${YELLOW}•${NC} v2RayTun"
            echo -e "      ${PURPLE}↳${NC} ${WHITE}apps.apple.com/app/v2raytun/id6476628951${NC}"
            ;;
        "outline"|"Outline")
            echo -e "  ${GREEN}🤖 Android:${NC}"
            echo -e "    ${YELLOW}•${NC} Outline Client"
            echo -e "      ${PURPLE}↳${NC} ${WHITE}play.google.com/store/apps/details?id=org.outline.android.client${NC}"
            echo ""
            echo -e "  ${GREEN}🍎 iOS:${NC}"
            echo -e "    ${YELLOW}•${NC} Outline Client"
            echo -e "      ${PURPLE}↳${NC} ${WHITE}apps.apple.com/app/outline-app/id1356177741${NC}"
            echo ""
            echo -e "  ${GREEN}🖥️  Desktop:${NC}"
            echo -e "    ${YELLOW}•${NC} Outline Client"
            echo -e "      ${PURPLE}↳${NC} ${WHITE}getoutline.org/download/${NC}"
            ;;
    esac
    
    echo ""
    echo -e "  ${GREEN}🔗 Способы подключения:${NC}"
    echo -e "    ${YELLOW}1.${NC} 📷 QR-код ${GREEN}(рекомендуется)${NC} - отсканируйте QR-код выше"
    echo -e "    ${YELLOW}2.${NC} 📋 Импорт ссылки - скопируйте ссылку для подключения"
    echo -e "    ${YELLOW}3.${NC} ⚙️  Ручная настройка - введите параметры сервера вручную"
    echo ""
    separator
}

# ========================= INPUT FUNCTIONS =========================

# Get user input with prompt and validation
get_user_input() {
    local prompt="$1"
    local default="$2"
    local validator="$3"  # Optional validation function
    local input=""
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$(echo -e ${GREEN}$prompt [${default}]:${NC} )" input
            input="${input:-$default}"
        else
            read -p "$(echo -e ${GREEN}$prompt:${NC} )" input
        fi
        
        # If no validator specified, accept any non-empty input
        if [ -z "$validator" ]; then
            if [ -n "$input" ]; then
                echo "$input"
                return 0
            else
                warning "Введите значение"
            fi
        else
            # Use validator function
            if $validator "$input"; then
                echo "$input"
                return 0
            else
                warning "Некорректное значение. Попробуйте снова."
            fi
        fi
    done
}

# Get yes/no confirmation
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response=""
    
    while true; do
        read -p "$(echo -e ${YELLOW}$prompt [y/n]:${NC} )" response
        response="${response:-$default}"
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                warning "Пожалуйста, введите 'y' или 'n'"
                ;;
        esac
    done
}

# Get menu choice with validation
get_menu_choice() {
    local prompt="$1"
    local min_choice="${2:-0}"
    local max_choice="${3:-10}"
    local default="${4:-0}"
    local choice=""
    
    while true; do
        read -p "$(echo -e ${GREEN}$prompt [$min_choice-$max_choice]:${NC} )" choice
        choice="${choice:-$default}"
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min_choice" ] && [ "$choice" -le "$max_choice" ]; then
            echo "$choice"
            return 0
        else
            warning "Введите число от $min_choice до $max_choice"
        fi
    done
}

# ========================= PROGRESS INDICATORS =========================

# Show simple progress bar
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local width=50
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${BLUE}%s${NC} [" "$description"
    printf "%*s" $filled "" | tr ' ' '█'
    printf "%*s" $empty "" | tr ' ' '░'
    printf "] %d%%" $percentage
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Show spinner animation
show_spinner() {
    local pid="$1"
    local message="$2"
    local spin='-\|/'
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${BLUE}%s${NC} %c" "$message" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r${GREEN}%s${NC} ✓\n" "$message"
}

# ========================= STATUS DISPLAY =========================

# Show status with colored indicator
show_status() {
    local service="$1"
    local status="$2"
    local details="$3"
    
    case "$status" in
        "active"|"running"|"healthy"|"online")
            echo -e "  • $service: ${GREEN}● $status${NC}"
            ;;
        "inactive"|"stopped"|"unhealthy"|"offline")
            echo -e "  • $service: ${RED}● $status${NC}"
            ;;
        "starting"|"pending"|"loading")
            echo -e "  • $service: ${YELLOW}● $status${NC}"
            ;;
        *)
            echo -e "  • $service: ${BLUE}● $status${NC}"
            ;;
    esac
    
    if [ -n "$details" ]; then
        echo -e "    ${PURPLE}↳${NC} $details"
    fi
}

# ========================= WELCOME/COMPLETION SCREENS =========================

# Show welcome screen
show_welcome() {
    clear
    echo ""
    echo -e "${GREEN}=== 🎉 Добро пожаловать в установщик VPN! ===${NC}"
    echo ""
}

# Show completion message
show_completion() {
    local title="$1"
    local message="$2"
    
    echo ""
    echo -e "${GREEN}=== 🎉 $title ===${NC}"
    echo ""
    
    if [ -n "$message" ]; then
        echo -e "${BLUE}$message${NC}"
        echo ""
    fi
}

# ========================= ERROR DISPLAY =========================

# Show error message with header
show_error_box() {
    local error_msg="$1"
    
    echo ""
    echo -e "${RED}=== ❌ ОШИБКА ===${NC}"
    echo ""
    echo -e "${RED}$error_msg${NC}"
    echo ""
}

# ========================= HELPER FUNCTIONS =========================

# Wait for user to press Enter
wait_for_enter() {
    echo ""
    read -p "$(echo -e ${BLUE}Нажмите Enter для продолжения...${NC})"
}

# Pause with custom message
pause() {
    local message="${1:-Нажмите Enter для продолжения...}"
    echo ""
    read -p "$(echo -e ${BLUE}$message${NC})"
}

# Clear screen and show header
reset_screen() {
    local title="$1"
    clear
    if [ -n "$title" ]; then
        show_header "$title"
    fi
}

# ========================= TABLE DISPLAY =========================

# Display table with headers
show_table() {
    local headers=("$@")
    local max_width=20
    
    # Print header
    printf "${BLUE}"
    for header in "${headers[@]}"; do
        printf "%-${max_width}s " "$header"
    done
    printf "${NC}\n"
    
    # Print separator
    printf "${BLUE}"
    for header in "${headers[@]}"; do
        printf "%*s " $max_width "" | tr ' ' '-'
    done
    printf "${NC}\n"
}

# Add table row
show_table_row() {
    local cells=("$@")
    local max_width=20
    
    for cell in "${cells[@]}"; do
        printf "%-${max_width}s " "$cell"
    done
    printf "\n"
}

# ========================= INITIALIZATION =========================

# Initialize UI library
init_ui() {
    debug "Initializing UI library"
    
    # Set terminal title if supported
    if [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
        printf "\033]0;VPN Management System\007"
    fi
    
    # Ensure proper terminal settings
    stty sane 2>/dev/null || true
}