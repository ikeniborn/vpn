#!/bin/bash
# Скрипт для применения исправлений VLESS конфигурации и health check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔧 Применяем исправления для VLESS+Reality..."

# Проверяем права root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Требуются права root. Запустите: sudo $0"
    exit 1
fi

# Останавливаем контейнер
echo "⏹️  Останавливаем Xray контейнер..."
cd /opt/v2ray
docker-compose down || true

# Создаем резервные копии
echo "💾 Создаем резервные копии..."
cp config/config.json config/config.json.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# Применяем оптимизированную конфигурацию
echo "📝 Применяем оптимизированную конфигурацию..."
cp "$SCRIPT_DIR/config-optimized.json" /opt/v2ray/config/config.json

# Применяем исправленный docker-compose
echo "🐳 Обновляем Docker Compose конфигурацию..."
cp "$SCRIPT_DIR/docker-compose-fixed.yml" /opt/v2ray/docker-compose.yml

# Копируем health check скрипт
echo "🏥 Устанавливаем улучшенный health check..."
mkdir -p /opt/v2ray/healthcheck
cp "$SCRIPT_DIR/healthcheck.sh" /opt/v2ray/healthcheck/
chmod +x /opt/v2ray/healthcheck/healthcheck.sh

# Обновляем docker-compose для правильного пути к health check
sed -i 's|/home/ikeniborn/Documents/Project/vpn/config/healthcheck.sh:/usr/local/bin/healthcheck.sh:ro|./healthcheck/healthcheck.sh:/usr/local/bin/healthcheck.sh:ro|g' /opt/v2ray/docker-compose.yml

# Запускаем контейнер
echo "🚀 Запускаем Xray с новой конфигурацией..."
docker-compose up -d

# Ждем запуска
echo "⏱️  Ждем запуска контейнера..."
sleep 10

# Проверяем статус
echo "📊 Проверяем статус контейнера..."
docker-compose ps

echo ""
echo "✅ Исправления применены!"
echo ""
echo "🔍 Что было исправлено:"
echo "   • Health check теперь правильно проверяет VLESS+Reality"
echo "   • Добавлены fallbacks для лучшей маскировки"
echo "   • Оптимизированы TCP настройки для мобильных сетей"
echo "   • Добавлено несколько короткий ID для Reality"
echo "   • Увеличен maxTimeDiff до 120s для мобильных соединений"
echo "   • Включен TCP Fast Open для улучшения производительности"
echo ""
echo "📱 Для мобильных устройств:"
echo "   • Убедитесь, что используете последние клиенты (v2rayNG, FairVPN)"
echo "   • Включите 'Fragment' в настройках клиента если доступно"
echo "   • Попробуйте разные SNI: addons.mozilla.org или developer.mozilla.org"