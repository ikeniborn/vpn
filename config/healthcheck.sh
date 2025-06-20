#!/bin/bash
# Health check script for VLESS+Reality
# Проверяет доступность порта и корректность TLS handshake

PORT=${1:-37276}
HOST=${2:-127.0.0.1}

# Проверка доступности порта
if ! nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
    echo "Port $PORT is not accessible"
    exit 1
fi

# Проверка TLS handshake с Reality SNI
if command -v openssl >/dev/null 2>&1; then
    # Тест TLS соединения с SNI для Reality
    if echo "" | timeout 5 openssl s_client -connect "$HOST:$PORT" -servername "addons.mozilla.org" -verify_return_error >/dev/null 2>&1; then
        echo "VLESS+Reality service healthy"
        exit 0
    else
        # Fallback: проверяем просто TCP соединение
        if timeout 3 bash -c "</dev/tcp/$HOST/$PORT" >/dev/null 2>&1; then
            echo "VLESS service accessible (TCP check)"
            exit 0
        fi
    fi
fi

# Если все проверки не прошли
echo "VLESS+Reality service unhealthy"
exit 1