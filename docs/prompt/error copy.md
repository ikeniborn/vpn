# Role 
Ты профессиональный разработчик Rust применяющий лучшие практики разработки. Ты разрабатываешь сервис для установки и управления VPN и Proxy сервером. С использование протоколок Vless, Shadowrocks, Wireguard, Socks5, HTTP.
# Artefacts
## Module
VPN Server Installation
## Service
Shadowsocks
# Request  
При установке сервера отображает параметры для протокола vless. 
VPN server installation completed successfully!
✓ VPN server installed successfully!
Server Details:
  Host: 80.209.240.162
  Port: 8388
  SNI: www.google.com
Initial User: vpnuser
✓ Server installed successfully!
Но сервис shadowsocks должен отобразить строку подклчюение к manadgment для управления.
Пользователи не создаются через сервис.
Проверить корректность устанвоки для протокола. 
Изучить базовый код по ссылке https://github.com/EricQmore/outline-vpn-arm
## Logs
✔ Select an option · 📦 Install VPN Server - Install and configure a new VPN server
VPN Server Installation
=======================

✔ Select VPN protocol · Shadowsocks

ℹ Selected protocol: Shadowsocks
✔ Proceed with installation of this protocol? · yes
✔ Use custom port? · no
✔ Configure firewall rules? · yes
✔ Enable auto-start on boot? · yes

Installation Summary:
  Protocol: Shadowsocks
  Firewall: Enabled
  Auto-start: Enabled

ℹ Starting installation...
⠁ Installing VPN server...                                                                                                                                                       Starting VPN server installation...
🧹 Checking for conflicting containers...
 INFO Checking for conflicting containers...
✓ Container conflict cleanup completed
🔍 Automatically selecting available VPN subnet...
💾 Saving server configuration...
✓ Detected server IP: 80.209.240.162
✓ Server configuration saved to /opt/shadowsocks/server_info.json
⚠️ Detected fixed subnet configuration, regenerating Docker Compose file...
🧹 Checking for conflicting containers...
 INFO Checking for conflicting containers...
✓ Container conflict cleanup completed
🐳 Starting VPN containers...
✓ Containers started, waiting for initialization...
✓ Container deployment completed
🔍 Verifying installation...
✓ Configuration files validated
✓ Docker Compose configuration found
✓ VPN containers are running
✓ Container health check passed
⏳ Waiting for service to start (attempt 1/10)
⏳ Waiting for service to start (attempt 2/10)
⏳ Waiting for service to start (attempt 3/10)
⏳ Waiting for service to start (attempt 4/10)
✓ Service connectivity verified
🎉 Installation verification completed successfully!
VPN server installation completed successfully!
✓ VPN server installed successfully!
Server Details:
  Host: 80.209.240.162
  Port: 8388
  SNI: www.google.com
Initial User: vpnuser
✓ Server installed successfully!

ℹ Next steps:
  1. Create users with 'User Management'
  2. Check server status
  3. View logs and monitoring
## Request task
1. Проанализируй ошибки и хорошо подумай над их причинами.
   1. При необходимости уточни информацию по документации с помощью инструмента context7 для Google Script App, clasp, rollup.
2. Тщательно подумай над решением каждой ошибки. Проверь выбранные решения на оптимальность и эффективность с учетом архитектуры приложения.
3. Сформируй план задач для устранения проблем. Обдумай и проверь этот план повторно.
4. Обязательно согласуй подготовленный план перед началом внесения изменений в код.
5. Выполни согласованные задачи по корректировки кода только после согласования пользвоателем.
6. По завершению всех изменений разверни код в dev среде.
7. Сделай коммит и пуш в гит.
	
