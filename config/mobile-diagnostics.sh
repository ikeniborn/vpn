#!/bin/bash
# Диагностика VPN соединений для мобильных сетей

set -euo pipefail

echo "📱 Диагностика VLESS+Reality для мобильных соединений"
echo "=================================================="

# Проверяем порт
PORT=$(cat /opt/v2ray/config/port.txt 2>/dev/null || echo "37276")
SERVER_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "unknown")

echo "🌐 Сервер: $SERVER_IP:$PORT"
echo ""

# Проверка 1: Доступность порта
echo "🔌 Проверка доступности порта..."
if nc -z -w5 127.0.0.1 "$PORT" 2>/dev/null; then
    echo "✅ Порт $PORT локально доступен"
else
    echo "❌ Порт $PORT локально недоступен"
fi

if nc -z -w5 "$SERVER_IP" "$PORT" 2>/dev/null; then
    echo "✅ Порт $PORT внешне доступен"
else
    echo "❌ Порт $PORT внешне недоступен"
fi

echo ""

# Проверка 2: TLS соединение
echo "🔒 Проверка TLS соединения..."
if command -v openssl >/dev/null 2>&1; then
    if echo "" | timeout 10 openssl s_client -connect "$SERVER_IP:$PORT" -servername "addons.mozilla.org" 2>/dev/null | grep -q "CONNECTED"; then
        echo "✅ TLS соединение с SNI работает"
    else
        echo "⚠️  TLS соединение с SNI может не работать"
    fi
else
    echo "⚠️  OpenSSL не установлен для проверки TLS"
fi

echo ""

# Проверка 3: Конфигурация Reality
echo "🎭 Проверка Reality конфигурации..."
if [ -f "/opt/v2ray/config/config.json" ]; then
    if jq -e '.inbounds[0].streamSettings.realitySettings' /opt/v2ray/config/config.json >/dev/null 2>&1; then
        echo "✅ Reality настроен в конфигурации"
        
        # Проверяем SNI
        SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /opt/v2ray/config/config.json 2>/dev/null)
        echo "📝 SNI: $SNI"
        
        # Проверяем количество shortIds
        SHORT_IDS_COUNT=$(jq '.inbounds[0].streamSettings.realitySettings.shortIds | length' /opt/v2ray/config/config.json 2>/dev/null)
        echo "🆔 Количество Short IDs: $SHORT_IDS_COUNT"
        
        # Проверяем maxTimeDiff
        MAX_TIME_DIFF=$(jq '.inbounds[0].streamSettings.realitySettings.maxTimeDiff' /opt/v2ray/config/config.json 2>/dev/null)
        echo "⏱️  Max Time Diff: ${MAX_TIME_DIFF}ms"
        
        if [ "$MAX_TIME_DIFF" -ge 120000 ]; then
            echo "✅ Время синхронизации оптимизировано для мобильных сетей"
        else
            echo "⚠️  Рекомендуется увеличить maxTimeDiff до 120000ms"
        fi
    else
        echo "❌ Reality не настроен"
    fi
else
    echo "❌ Конфигурационный файл не найден"
fi

echo ""

# Проверка 4: Логи контейнера
echo "📋 Последние логи Xray..."
docker logs xray --tail 10 2>/dev/null | grep -E "(started|listening|error|warning)" || echo "Логи недоступны"

echo ""

# Проверка 5: Состояние контейнера
echo "🐳 Состояние Docker контейнера..."
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep xray; then
    echo "✅ Контейнер запущен"
else
    echo "❌ Контейнер не запущен"
fi

echo ""

# Проверка 6: Firewall
echo "🔥 Проверка Firewall..."
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "$PORT"; then
        echo "✅ Порт $PORT разрешен в UFW"
    else
        echo "⚠️  Порт $PORT не найден в правилах UFW"
    fi
else
    echo "⚠️  UFW не установлен"
fi

echo ""
echo "🔧 Рекомендации для мобильных соединений:"
echo "   1. Используйте актуальные клиенты (v2rayNG 1.8.5+, FairVPN)"
echo "   2. Включите Fragment в настройках клиента если доступно"
echo "   3. Попробуйте разные SNI домены"
echo "   4. Проверьте время на устройстве (синхронизация важна для Reality)"
echo "   5. Некоторые провайдеры блокируют порты выше 65000 - ваш порт $PORT в безопасной зоне"
echo ""

# Генерируем ссылку для подключения
if [ -f "/opt/v2ray/users/ikeniborn.link" ]; then
    echo "🔗 Ваша ссылка для подключения:"
    cat /opt/v2ray/users/ikeniborn.link
    echo ""
fi