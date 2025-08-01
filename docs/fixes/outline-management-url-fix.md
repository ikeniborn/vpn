# Исправление отображения Management URL для Outline

## Проблема
При установке Outline (Shadowsocks) сервера не отображался Management URL для доступа к веб-интерфейсу управления, хотя информация сохранялась в файле server_info.json.

## Причины
1. **Несоответствие протоколов**: В коде проверялся только `Protocol::Outline`, но при установке использовался `Protocol::Shadowsocks`
2. **Отсутствие информации об управлении пользователями**: При попытке создать пользователя через CLI не было ясного указания, что для Outline нужно использовать веб-интерфейс

## Внесенные изменения

### 1. Исправление отображения Management URL при установке
В файле `crates/vpn-cli/src/commands.rs`:
- Добавлена проверка `Protocol::Shadowsocks` в дополнение к `Protocol::Outline`
- Улучшены информационные сообщения

### 2. Добавление информации при управлении пользователями
- При попытке создать пользователя для Outline/Shadowsocks показывается сообщение с Management URL
- Объясняется, что управление пользователями происходит через веб-интерфейс

### 3. Отображение Management URL в статусе
- При выполнении `vpn status --detailed` теперь показывается Management URL для Outline

## Результат
После установки Outline сервера:
```
Server Details:
  Host: 80.209.240.162
  Port: 8388
  Management URL: https://80.209.240.162:9388/6FE2z6i02VtMpwt+i67W+9u29jnHPMsEKCLckNiYC90=/

🔑 IMPORTANT: Save the management URL above to access the Outline Manager
   You can use it to create and manage users through the web interface.
   Note: Users for Outline are managed through the web interface, not CLI.
```

При попытке создать пользователя:
```
$ sudo vpn users create test-user --protocol shadowsocks
ℹ️  Outline/Shadowsocks users are managed through the web interface.

🔑 Access the Outline Manager at:
   https://80.209.240.162:9388/6FE2z6i02VtMpwt+i67W+9u29jnHPMsEKCLckNiYC90=/

Use this web interface to:
   • Create and manage access keys
   • Monitor server metrics
   • Configure server settings
```

## Тесты
Добавлены тесты в `crates/vpn-cli/tests/outline_management_test.rs` для проверки:
- Корректного маппинга протоколов
- Формирования Management URL
- Чтения информации из server_info.json