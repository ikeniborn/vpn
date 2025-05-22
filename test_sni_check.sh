#!/bin/bash

# Тест функции проверки SNI доменов

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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функция проверки доступности SNI домена (копия из install_vpn.sh)
check_sni_domain() {
    local domain=$1
    local timeout=5
    
    log "Проверка доступности домена $domain..."
    
    # Проверка DNS резолюции с таймаутом
    if ! timeout 5 nslookup "$domain" >/dev/null 2>&1; then
        warning "Домен $domain не резолвится в DNS или таймаут"
        return 1
    fi
    
    # Проверка HTTPS доступности с коротким таймаутом
    if ! curl -s --connect-timeout $timeout --max-time $timeout --fail "https://$domain" >/dev/null 2>&1; then
        warning "Домен $domain недоступен по HTTPS"
        return 1
    fi
    
    # Проверка поддержки TLS 1.3 с таймаутом
    local tls_check=$(timeout 10 bash -c "echo | openssl s_client -connect '$domain:443' -tls1_3 -quiet 2>/dev/null" | grep "TLSv1.3" || echo "")
    if [ -z "$tls_check" ]; then
        # Более мягкая проверка - проверяем хотя бы TLS соединение
        local tls_any=$(timeout 5 bash -c "echo | openssl s_client -connect '$domain:443' -quiet 2>/dev/null" | grep "Protocol" || echo "")
        if [ -z "$tls_any" ]; then
            warning "Домен $domain не поддерживает безопасное TLS соединение"
            return 1
        else
            warning "Домен $domain поддерживает TLS, но TLS 1.3 не подтвержден"
            # Не возвращаем ошибку, так как домен все еще может работать
        fi
    fi
    
    log "✓ Домен $domain прошел основные проверки"
    return 0
}

echo "=== Тест функции проверки SNI доменов ==="
echo ""

# Тестируемые домены
DOMAINS=("addons.mozilla.org" "www.lovelive-anime.jp" "www.swift.org" "google.com" "invalid-domain-test-12345.com")

for domain in "${DOMAINS[@]}"; do
    echo "Тестирование: $domain"
    start_time=$(date +%s)
    
    if timeout 20 bash -c "check_sni_domain '$domain'"; then
        result="✅ Успешно"
    else
        result="❌ Неудачно"
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo "Результат: $result (время: ${duration}с)"
    echo "----------------------------------------"
done

echo ""
echo "=== Тест завершен ==="