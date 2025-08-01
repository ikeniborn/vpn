# Исправление отображения Outline (Shadowsocks) в статусе VPN

## Проблема
После установки Outline VPN сервера, он не отображался в выводе команды `vpn status` и в основном меню показывался как неработающий.

## Причины
1. **Неправильные имена контейнеров в коде**: В файле `lifecycle.rs` искались контейнеры с именами `shadowsocks` и `shadowsocks-watchtower`, в то время как реальные имена контейнеров были `outline-shadowbox` и `outline-watchtower`.

2. **Ошибка запуска контейнера Outline**: Контейнер постоянно перезапускался из-за ошибки `TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string`, вызванной отсутствием необходимых переменных окружения и файлов конфигурации.

3. **Неполная инициализация директорий**: Функция `create_outline_directories` не создавала все необходимые поддиректории и файлы для Outline.

## Внесенные изменения

### 1. Обновление имен контейнеров в `lifecycle.rs`
```rust
// Было:
("shadowsocks", "shadowsocks-server"),
"shadowsocks",
"shadowsocks-watchtower",

// Стало:
("outline-shadowbox", "outline-server"),
"outline-shadowbox",
"outline-watchtower",
```

### 2. Улучшение инициализации директорий в `templates.rs`
```rust
fn create_outline_directories(&self, install_path: &Path) -> Result<()> {
    let directories = [
        "persisted-state",
        "persisted-state/outline-ss-server", 
        "persisted-state/prometheus",
        "management"
    ];
    // ... создание начальных файлов конфигурации
}
```

### 3. Исправление docker-compose для Outline
- Использование официального образа `quay.io/outline/shadowbox:stable`
- Добавление необходимых переменных окружения: `SB_API_PREFIX`, `SB_PUBLIC_IP`
- Правильная настройка volumes и портов

### 4. Добавление тестов
Создан файл `outline_status_test.rs` с тестами для проверки отображения Outline контейнеров в статусе.

## Результат
- Outline контейнер успешно запускается и работает
- Команда `vpn status --detailed` корректно отображает контейнеры Outline
- Тесты проходят успешно

## Примечание
Для просмотра детальной информации о контейнерах необходимо использовать флаг `--detailed`:
```bash
sudo vpn status --detailed
```