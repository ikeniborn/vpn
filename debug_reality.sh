#!/bin/bash

# Скрипт для диагностики проблем с Reality в manage_users.sh

WORK_DIR="/opt/v2ray"
CONFIG_FILE="$WORK_DIR/config/config.json"

echo "=== Диагностика Reality ==="

# Проверка существования файлов
echo "1. Проверка файлов:"
echo "   CONFIG_FILE=$CONFIG_FILE"
if [ -f "$CONFIG_FILE" ]; then
    echo "   ✓ Конфигурационный файл существует"
else
    echo "   ✗ Конфигурационный файл НЕ существует"
    exit 1
fi

# Проверка содержимого конфига
echo ""
echo "2. Содержимое конфигурации:"
if command -v jq >/dev/null 2>&1; then
    echo "   streamSettings.security:"
    SECURITY=$(jq -r '.inbounds[0].streamSettings.security' "$CONFIG_FILE")
    echo "   $SECURITY"
    
    echo "   Полные streamSettings:"
    jq '.inbounds[0].streamSettings' "$CONFIG_FILE"
else
    echo "   jq не установлен, показываем сырой JSON:"
    cat "$CONFIG_FILE"
fi

# Проверка файлов настроек
echo ""
echo "3. Файлы настроек:"
if [ -f "$WORK_DIR/config/use_reality.txt" ]; then
    echo "   ✓ use_reality.txt: $(cat "$WORK_DIR/config/use_reality.txt")"
else
    echo "   ✗ use_reality.txt НЕ существует"
fi

if [ -f "$WORK_DIR/config/protocol.txt" ]; then
    echo "   ✓ protocol.txt: $(cat "$WORK_DIR/config/protocol.txt")"
else
    echo "   ✗ protocol.txt НЕ существует"
fi

if [ -f "$WORK_DIR/config/public_key.txt" ]; then
    echo "   ✓ public_key.txt: $(cat "$WORK_DIR/config/public_key.txt")"
else
    echo "   ✗ public_key.txt НЕ существует"
fi

if [ -f "$WORK_DIR/config/private_key.txt" ]; then
    echo "   ✓ private_key.txt: $(cat "$WORK_DIR/config/private_key.txt")"
else
    echo "   ✗ private_key.txt НЕ существует"
fi

if [ -f "$WORK_DIR/config/short_id.txt" ]; then
    echo "   ✓ short_id.txt: $(cat "$WORK_DIR/config/short_id.txt")"
else
    echo "   ✗ short_id.txt НЕ существует"
fi

echo ""
echo "=== Конец диагностики ==="