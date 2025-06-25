#!/bin/bash
#
# Unified Real-time Dashboard Module
# Combines dashboard functionality with real-time traffic monitoring
# Author: Claude
# Version: 1.0

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"
source "$PROJECT_DIR/lib/network.sh"

# Global variables
DASHBOARD_PORT="8080"
DASHBOARD_DIR="/opt/v2ray/dashboard"
METRICS_FILE="$DASHBOARD_DIR/metrics.json"
HISTORY_DIR="$DASHBOARD_DIR/data"
SERVER_PID_FILE="$DASHBOARD_DIR/server.pid"

# Initialize unified dashboard
init_unified_dashboard() {
    log "Initializing unified dashboard..."
    
    # Create directories
    mkdir -p "$DASHBOARD_DIR/www" "$HISTORY_DIR" 2>/dev/null || true
    
    # Check required tools
    for tool in jq ss python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "Installing $tool..."
            apt-get update -qq >/dev/null 2>&1
            case "$tool" in
                "jq") apt-get install -y jq >/dev/null 2>&1 ;;
                "ss") apt-get install -y iproute2 >/dev/null 2>&1 ;;
                "python3") apt-get install -y python3 >/dev/null 2>&1 ;;
            esac
        fi
    done
    
    log "Unified dashboard initialized"
}

# Get primary interface (reuse from traffic_monitor)
get_primary_interface() {
    local interface=""
    
    # Find interface with default route (excluding tunnels)
    interface=$(ip route | grep '^default' | grep -v 'tun\|tap\|wg' | head -1 | awk '{print $5}')
    
    # Fallback methods
    if [ -z "$interface" ] || [[ "$interface" =~ (tun|tap|wg) ]]; then
        for ip in 8.8.8.8 1.1.1.1; do
            local route_info=$(ip route get "$ip" 2>/dev/null | head -1)
            if [ -n "$route_info" ]; then
                interface=$(echo "$route_info" | grep -oP 'dev \K[^ ]+' | grep -v 'tun\|tap\|wg' | head -1)
                if [ -n "$interface" ] && ! [[ "$interface" =~ (tun|tap|wg) ]]; then
                    break
                fi
            fi
        done
    fi
    
    # Check common interface names
    if [ -z "$interface" ] || [[ "$interface" =~ (tun|tap|wg|outline) ]]; then
        for iface in enp1s0 enp0s3 ens3 eth0 wlan0; do
            if ip link show "$iface" >/dev/null 2>&1; then
                local state=$(ip link show "$iface" | grep -oP 'state \K[^ ]+')
                if [ "$state" = "UP" ] || [ "$state" = "UNKNOWN" ]; then
                    interface="$iface"
                    break
                fi
            fi
        done
    fi
    
    # Final fallback - return the first UP interface
    if [ -z "$interface" ]; then
        interface=$(ip link show | grep -E "state UP" | head -1 | grep -oP ': \K[^:]+' | grep -v "lo" || echo "enp1s0")
    fi
    
    echo "${interface:-enp1s0}"
}

# Get VPN port
get_vpn_port() {
    local port=""
    
    # Try to get port from config.json
    if [ -f "/opt/v2ray/config/config.json" ]; then
        port=$(jq -r '.inbounds[0].port // empty' /opt/v2ray/config/config.json 2>/dev/null)
    fi
    
    # Fallback: try to find port from docker inspect
    if [ -z "$port" ] || [ "$port" = "null" ]; then
        port=$(docker inspect xray 2>/dev/null | jq -r '.[0].NetworkSettings.Ports | keys[0] // empty' 2>/dev/null | cut -d'/' -f1)
    fi
    
    # Fallback: try netstat for listening ports
    if [ -z "$port" ] || [ "$port" = "null" ]; then
        port=$(netstat -tlnp 2>/dev/null | grep -E ":(443|8443|1080|8080|9999)" | head -1 | awk '{print $4}' | cut -d':' -f2)
    fi
    
    echo "${port:-443}"
}

# Collect comprehensive metrics
collect_unified_metrics() {
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local interface
    interface=$(get_primary_interface)
    local vpn_port
    vpn_port=$(get_vpn_port)
    
    # Server metrics
    local server_status="offline"
    local uptime="N/A"
    local version="Unknown"
    
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "xray"; then
        server_status="online"
        
        # Get uptime
        local started_at
        started_at=$(docker inspect xray --format='{{.State.StartedAt}}' 2>/dev/null)
        if [ -n "$started_at" ]; then
            local start_epoch
            start_epoch=$(date -d "$started_at" +%s 2>/dev/null)
            if [ -n "$start_epoch" ] && [ "$start_epoch" -gt 0 ]; then
                local current_epoch
                current_epoch=$(date +%s)
                local diff=$((current_epoch - start_epoch))
                local days=$((diff / 86400))
                local hours=$(((diff % 86400) / 3600))
                local minutes=$(((diff % 3600) / 60))
                uptime="${days}d ${hours}h ${minutes}m"
            fi
        fi
        
        version=$(docker exec xray xray version 2>/dev/null | grep -oP 'Xray \K[0-9.]+' || echo "Unknown")
    fi
    
    # Performance metrics
    local cpu="0"
    local memory="0"
    local disk="0"
    
    if [ "$server_status" = "online" ]; then
        cpu=$(docker stats xray --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
        memory=$(docker stats xray --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    fi
    
    disk=$(df -h /opt/v2ray 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    
    # Network metrics
    local rx_bytes=0
    local tx_bytes=0
    
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
    fi
    
    if [ -f "/sys/class/net/$interface/statistics/tx_bytes" ]; then
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
    fi
    
    # Connection metrics
    local active_connections=0
    if [ -n "$vpn_port" ] && [[ "$vpn_port" =~ ^[0-9]+$ ]]; then
        active_connections=$(ss -tn 2>/dev/null | grep ":$vpn_port" | grep ESTAB | wc -l || echo "0")
    fi
    
    # User metrics
    local total_users=0
    local user_list='[]'
    
    if [ -d "/opt/v2ray/users" ]; then
        total_users=$(ls -1 /opt/v2ray/users/*.json 2>/dev/null | wc -l || echo "0")
        
        for user_file in /opt/v2ray/users/*.json; do
            [ -f "$user_file" ] || continue
            
            local username
            username=$(basename "$user_file" .json)
            local uuid
            uuid=$(jq -r '.uuid' "$user_file" 2>/dev/null || echo "")
            
            if [ -n "$uuid" ] && [ "$uuid" != "null" ]; then
                local online="false"
                local last_seen="Never"
                local user_conns="0"
                
                # Check user activity
                if [ -r "/opt/v2ray/logs/access.log" ]; then
                    user_conns=$(grep -c "$uuid" /opt/v2ray/logs/access.log 2>/dev/null || echo "0")
                    if tail -n 50 /opt/v2ray/logs/access.log 2>/dev/null | grep -q "$uuid"; then
                        online="true"
                        last_seen="Recent"
                    fi
                fi
                
                user_list=$(echo "$user_list" | jq --arg user "$username" --argjson online "$([ "$online" = "true" ] && echo true || echo false)" \
                    --argjson conns "$user_conns" --arg seen "$last_seen" \
                    '. + [{"username": $user, "online": $online, "connections": $conns, "last_seen": $seen}]' 2>/dev/null) || user_list='[]'
            fi
        done
    fi
    
    # Traffic history
    local history_file="$HISTORY_DIR/traffic_$(date +%Y%m%d).json"
    local traffic_history='[]'
    if [ -f "$history_file" ]; then
        traffic_history=$(cat "$history_file" 2>/dev/null) || traffic_history='[]'
    fi
    
    # Add current data point
    local current_time=$(date +%H:%M)
    if [[ "$rx_bytes" =~ ^[0-9]+$ ]] && [[ "$tx_bytes" =~ ^[0-9]+$ ]]; then
        traffic_history=$(echo "$traffic_history" | jq --arg time "$current_time" \
            --argjson rx "$rx_bytes" --argjson tx "$tx_bytes" \
            '. + [{"time": $time, "download": $rx, "upload": $tx}] | .[-60:]' 2>/dev/null) || traffic_history='[]'
    fi
    
    # Save traffic history
    echo "$traffic_history" > "$history_file" 2>/dev/null || true
    
    # Connection history
    local conn_history_file="$HISTORY_DIR/connections_$(date +%Y%m%d).json"
    local conn_history='[]'
    if [ -f "$conn_history_file" ]; then
        conn_history=$(cat "$conn_history_file" 2>/dev/null) || conn_history='[]'
    fi
    
    # Add current connection count
    conn_history=$(echo "$conn_history" | jq --arg time "$current_time" --argjson count "$active_connections" \
        '. + [{"time": $time, "count": $count}] | .[-60:]' 2>/dev/null) || conn_history='[]'
    
    # Save connection history
    echo "$conn_history" > "$conn_history_file" 2>/dev/null || true
    
    # Sanitize variables for JSON
    timestamp=${timestamp:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
    server_status=${server_status:-offline}
    uptime=${uptime:-N/A}
    version=${version:-Unknown}
    cpu=${cpu:-0}
    memory=${memory:-0}
    disk=${disk:-0}
    interface=${interface:-unknown}
    rx_bytes=${rx_bytes:-0}
    tx_bytes=${tx_bytes:-0}
    active_connections=${active_connections:-0}
    vpn_port=${vpn_port:-N/A}
    total_users=${total_users:-0}
    
    # Validate JSON arrays
    if ! echo "$traffic_history" | jq empty 2>/dev/null || [ -z "$traffic_history" ]; then
        traffic_history='[]'
    fi
    if ! echo "$conn_history" | jq empty 2>/dev/null; then
        conn_history='[]'
    fi
    if ! echo "$user_list" | jq empty 2>/dev/null; then
        user_list='[]'
    fi
    
    # Ensure numeric values are valid
    if ! [[ "$rx_bytes" =~ ^[0-9]+$ ]]; then rx_bytes=0; fi
    if ! [[ "$tx_bytes" =~ ^[0-9]+$ ]]; then tx_bytes=0; fi
    if ! [[ "$active_connections" =~ ^[0-9]+$ ]]; then active_connections=0; fi
    if ! [[ "$total_users" =~ ^[0-9]+$ ]]; then total_users=0; fi
    
    # Calculate total bytes safely
    local total_bytes=$((rx_bytes + tx_bytes))
    
    # Generate final JSON using printf for better control
    printf '{\n' > "$METRICS_FILE"
    printf '    "timestamp": "%s",\n' "$timestamp" >> "$METRICS_FILE"
    printf '    "server": {\n' >> "$METRICS_FILE"
    printf '        "status": "%s",\n' "$server_status" >> "$METRICS_FILE"
    printf '        "uptime": "%s",\n' "$uptime" >> "$METRICS_FILE"
    printf '        "version": "%s",\n' "$version" >> "$METRICS_FILE"
    printf '        "protocol": "VLESS+Reality"\n' >> "$METRICS_FILE"
    printf '    },\n' >> "$METRICS_FILE"
    printf '    "performance": {\n' >> "$METRICS_FILE"
    printf '        "cpu": "%s",\n' "$cpu" >> "$METRICS_FILE"
    printf '        "memory": "%s",\n' "$memory" >> "$METRICS_FILE"
    printf '        "disk": "%s"\n' "$disk" >> "$METRICS_FILE"
    printf '    },\n' >> "$METRICS_FILE"
    printf '    "network": {\n' >> "$METRICS_FILE"
    printf '        "interface": "%s",\n' "$interface" >> "$METRICS_FILE"
    printf '        "total_bytes": %d,\n' "$total_bytes" >> "$METRICS_FILE"
    printf '        "rx_bytes": %d,\n' "$rx_bytes" >> "$METRICS_FILE"
    printf '        "tx_bytes": %d,\n' "$tx_bytes" >> "$METRICS_FILE"
    printf '        "traffic_history": %s\n' "$traffic_history" >> "$METRICS_FILE"
    printf '    },\n' >> "$METRICS_FILE"
    printf '    "connections": {\n' >> "$METRICS_FILE"
    printf '        "active": %d,\n' "$active_connections" >> "$METRICS_FILE"
    printf '        "port": "%s",\n' "$vpn_port" >> "$METRICS_FILE"
    printf '        "connection_history": %s\n' "$conn_history" >> "$METRICS_FILE"
    printf '    },\n' >> "$METRICS_FILE"
    printf '    "users": {\n' >> "$METRICS_FILE"
    printf '        "total": %d,\n' "$total_users" >> "$METRICS_FILE"
    printf '        "list": %s\n' "$user_list" >> "$METRICS_FILE"
    printf '    }\n' >> "$METRICS_FILE"
    printf '}\n' >> "$METRICS_FILE"
    
    # Validate JSON
    if ! jq empty "$METRICS_FILE" 2>/dev/null; then
        log "Warning: Generated invalid JSON, creating fallback"
        cat > "$METRICS_FILE" << 'FALLBACK_JSON'
{
    "timestamp": "error",
    "server": {"status": "error", "uptime": "N/A", "version": "N/A", "protocol": "VLESS+Reality"},
    "performance": {"cpu": "0", "memory": "0", "disk": "0"},
    "network": {"interface": "unknown", "total_bytes": 0, "rx_bytes": 0, "tx_bytes": 0, "traffic_history": []},
    "connections": {"active": 0, "port": "", "connection_history": []},
    "users": {"total": 0, "list": []}
}
FALLBACK_JSON
    fi
}

# Create enhanced web interface
create_enhanced_dashboard() {
    cat > "$DASHBOARD_DIR/www/index.html" << 'HTML_END'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Dashboard - Real-time Monitoring</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header {
            text-align: center;
            margin-bottom: 30px;
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            text-align: center;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .stat-value {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
        }
        .status-online { color: #4ade80; }
        .status-offline { color: #f87171; }
        .charts-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .chart-container {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.2);
        }
        .users-table {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.2);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid rgba(255,255,255,0.2);
        }
        th { background: rgba(255,255,255,0.2); }
        .online-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .online { background: #4ade80; }
        .offline { background: #f87171; }
        .refresh-info {
            text-align: center;
            margin-top: 20px;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 VPN Real-time Dashboard</h1>
            <p>Comprehensive monitoring and analytics</p>
            <div class="refresh-info">
                <span id="lastUpdate">Loading...</span> | 
                <span id="nextUpdate">Next update in: <span id="countdown">5</span>s</span>
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h3>Server Status</h3>
                <div class="stat-value" id="serverStatus">Loading...</div>
                <p>Uptime: <span id="serverUptime">N/A</span></p>
            </div>
            <div class="stat-card">
                <h3>Active Connections</h3>
                <div class="stat-value" id="activeConnections">0</div>
                <p>Port: <span id="vpnPort">N/A</span></p>
            </div>
            <div class="stat-card">
                <h3>Total Users</h3>
                <div class="stat-value" id="totalUsers">0</div>
                <p>Registered users</p>
            </div>
            <div class="stat-card">
                <h3>Performance</h3>
                <div class="stat-value">
                    CPU: <span id="cpuUsage">0</span>%<br>
                    <small style="font-size: 0.6em;">Memory: <span id="memoryUsage">0</span>%</small>
                </div>
            </div>
        </div>

        <div class="charts-container">
            <div class="chart-container">
                <h3>Traffic History (Last Hour)</h3>
                <canvas id="trafficChart" width="400" height="200"></canvas>
            </div>
            <div class="chart-container">
                <h3>Connection History (Last Hour)</h3>
                <canvas id="connectionsChart" width="400" height="200"></canvas>
            </div>
        </div>

        <div class="users-table">
            <h3>👥 User Management</h3>
            <table>
                <thead>
                    <tr>
                        <th>Status</th>
                        <th>Username</th>
                        <th>Connections</th>
                        <th>Last Seen</th>
                    </tr>
                </thead>
                <tbody id="usersTableBody">
                    <tr><td colspan="4">Loading users...</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <script>
        let trafficChart, connectionsChart;
        let countdownInterval;

        // Initialize charts
        function initCharts() {
            const trafficCtx = document.getElementById('trafficChart').getContext('2d');
            trafficChart = new Chart(trafficCtx, {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Download (MB)',
                        data: [],
                        borderColor: '#4ade80',
                        backgroundColor: 'rgba(74, 222, 128, 0.1)',
                        tension: 0.4
                    }, {
                        label: 'Upload (MB)',
                        data: [],
                        borderColor: '#f59e0b',
                        backgroundColor: 'rgba(245, 158, 11, 0.1)',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    scales: {
                        y: { beginAtZero: true }
                    },
                    plugins: {
                        legend: { labels: { color: '#fff' } }
                    }
                }
            });

            const connectionsCtx = document.getElementById('connectionsChart').getContext('2d');
            connectionsChart = new Chart(connectionsCtx, {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Active Connections',
                        data: [],
                        borderColor: '#8b5cf6',
                        backgroundColor: 'rgba(139, 92, 246, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    scales: {
                        y: { beginAtZero: true }
                    },
                    plugins: {
                        legend: { labels: { color: '#fff' } }
                    }
                }
            });
        }

        // Update dashboard data
        async function updateDashboard() {
            try {
                const response = await fetch('/api/metrics');
                const data = await response.json();
                
                // Update server status
                const serverStatus = document.getElementById('serverStatus');
                serverStatus.textContent = data.server.status.toUpperCase();
                serverStatus.className = `stat-value status-${data.server.status}`;
                document.getElementById('serverUptime').textContent = data.server.uptime;
                
                // Update connection stats
                document.getElementById('activeConnections').textContent = data.connections.active;
                document.getElementById('vpnPort').textContent = data.connections.port || 'N/A';
                
                // Update user stats
                document.getElementById('totalUsers').textContent = data.users.total;
                
                // Update performance
                document.getElementById('cpuUsage').textContent = parseFloat(data.performance.cpu).toFixed(1);
                document.getElementById('memoryUsage').textContent = parseFloat(data.performance.memory).toFixed(1);
                
                // Update traffic chart
                if (data.network.traffic_history && Array.isArray(data.network.traffic_history)) {
                    const labels = data.network.traffic_history.map(item => item.time);
                    const downloads = data.network.traffic_history.map(item => (item.download / 1024 / 1024).toFixed(2));
                    const uploads = data.network.traffic_history.map(item => (item.upload / 1024 / 1024).toFixed(2));
                    
                    trafficChart.data.labels = labels;
                    trafficChart.data.datasets[0].data = downloads;
                    trafficChart.data.datasets[1].data = uploads;
                    trafficChart.update('none');
                }
                
                // Update connections chart
                if (data.connections.connection_history && Array.isArray(data.connections.connection_history)) {
                    const labels = data.connections.connection_history.map(item => item.time);
                    const counts = data.connections.connection_history.map(item => item.count);
                    
                    connectionsChart.data.labels = labels;
                    connectionsChart.data.datasets[0].data = counts;
                    connectionsChart.update('none');
                }
                
                // Update users table
                const tbody = document.getElementById('usersTableBody');
                if (data.users.list && Array.isArray(data.users.list) && data.users.list.length > 0) {
                    tbody.innerHTML = data.users.list.map(user => `
                        <tr>
                            <td><span class="online-indicator ${user.online ? 'online' : 'offline'}"></span></td>
                            <td>${user.username}</td>
                            <td>${user.connections}</td>
                            <td>${user.last_seen}</td>
                        </tr>
                    `).join('');
                } else {
                    tbody.innerHTML = '<tr><td colspan="4">No users found</td></tr>';
                }
                
                // Update timestamp
                document.getElementById('lastUpdate').textContent = `Last update: ${new Date(data.timestamp).toLocaleTimeString()}`;
                
            } catch (error) {
                console.error('Failed to update dashboard:', error);
                document.getElementById('serverStatus').textContent = 'ERROR';
                document.getElementById('serverStatus').className = 'stat-value status-offline';
            }
        }

        // Countdown timer
        function startCountdown() {
            let seconds = 5;
            const countdownElement = document.getElementById('countdown');
            
            if (countdownInterval) clearInterval(countdownInterval);
            
            countdownInterval = setInterval(() => {
                countdownElement.textContent = seconds;
                seconds--;
                
                if (seconds < 0) {
                    seconds = 5;
                    updateDashboard();
                }
            }, 1000);
        }

        // Initialize dashboard
        document.addEventListener('DOMContentLoaded', function() {
            initCharts();
            updateDashboard();
            startCountdown();
        });
    </script>
</body>
</html>
HTML_END
}

# Create Python server
create_dashboard_server() {
    cat > "$DASHBOARD_DIR/server.py" << 'PYTHON_END'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
from urllib.parse import urlparse

class UnifiedDashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory='/opt/v2ray/dashboard/www', **kwargs)
    
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/api/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            
            metrics_file = '/opt/v2ray/dashboard/metrics.json'
            if os.path.exists(metrics_file):
                try:
                    with open(metrics_file, 'r') as f:
                        content = f.read()
                    # Validate JSON before sending
                    json.loads(content)
                    self.wfile.write(content.encode())
                except (json.JSONDecodeError, IOError):
                    error_response = '{"error": "Invalid metrics data"}'
                    self.wfile.write(error_response.encode())
            else:
                error_response = '{"error": "No metrics available"}'
                self.wfile.write(error_response.encode())
        else:
            super().do_GET()

PORT = int(os.environ.get('DASHBOARD_PORT', '8080'))

with socketserver.TCPServer(("127.0.0.1", PORT), UnifiedDashboardHandler) as httpd:
    print(f"Unified Dashboard serving locally at 127.0.0.1:{PORT}")
    httpd.serve_forever()
PYTHON_END
    
    chmod +x "$DASHBOARD_DIR/server.py"
}

# Start unified dashboard
start_unified_dashboard() {
    local port="${1:-8080}"
    
    log "Starting unified dashboard on port $port..."
    
    # Stop existing dashboard
    stop_unified_dashboard
    
    # Initialize
    init_unified_dashboard
    
    # Create web interface and server
    create_enhanced_dashboard
    create_dashboard_server
    
    # Generate initial metrics
    collect_unified_metrics
    
    # Start server
    export DASHBOARD_PORT="$port"
    nohup python3 "$DASHBOARD_DIR/server.py" > "$DASHBOARD_DIR/server.log" 2>&1 &
    echo $! > "$SERVER_PID_FILE"
    
    sleep 2
    
    if [ -f "$SERVER_PID_FILE" ] && kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null; then
        log "✓ Unified dashboard started at http://127.0.0.1:$port"
        
        # Setup metrics collection cron job
        setup_metrics_cron
        
        return 0
    else
        error "Failed to start unified dashboard"
        return 1
    fi
}

# Stop unified dashboard
stop_unified_dashboard() {
    if [ -f "$SERVER_PID_FILE" ]; then
        local pid
        pid=$(cat "$SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            log "Dashboard server stopped"
        fi
        rm -f "$SERVER_PID_FILE"
    fi
    
    # Stop metrics collector
    if [ -f "$DASHBOARD_DIR/metrics_collector.pid" ]; then
        local metrics_pid
        metrics_pid=$(cat "$DASHBOARD_DIR/metrics_collector.pid")
        if kill -0 "$metrics_pid" 2>/dev/null; then
            kill "$metrics_pid" 2>/dev/null
            log "Metrics collector stopped"
        fi
        rm -f "$DASHBOARD_DIR/metrics_collector.pid"
    fi
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "collect_metrics.sh" | crontab - 2>/dev/null || true
}

# Setup metrics collection cron job
setup_metrics_cron() {
    # Create metrics collection script
    cat > "$DASHBOARD_DIR/collect_metrics.sh" << 'METRICS_END'
#!/bin/bash
cd /home/ikeniborn/Documents/Project/vpn
source modules/monitoring/unified_dashboard.sh
collect_unified_metrics
METRICS_END
    chmod +x "$DASHBOARD_DIR/collect_metrics.sh"
    
    # Add to cron (every 5 seconds via background process)
    (crontab -l 2>/dev/null | grep -v "collect_metrics.sh") | crontab -
    
    # Start background metrics collection process
    nohup sh -c 'while true; do /opt/v2ray/dashboard/collect_metrics.sh >/dev/null 2>&1; sleep 5; done' > "$DASHBOARD_DIR/metrics_collector.log" 2>&1 &
    echo $! > "$DASHBOARD_DIR/metrics_collector.pid"
    
    log "✓ Metrics collection started (every 5 seconds)"
}

# Dashboard status
dashboard_status() {
    if [ -f "$SERVER_PID_FILE" ]; then
        local pid
        pid=$(cat "$SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            local port
            port=$(ps aux | grep "$pid" | grep -oP 'DASHBOARD_PORT=\K[0-9]+' || echo "8080")
            echo -e "${GREEN}✓ Dashboard running${NC} (PID: $pid, Port: $port)"
            echo -e "${BLUE}URL:${NC} http://127.0.0.1:$port"
            return 0
        fi
    fi
    
    echo -e "${RED}✗ Dashboard not running${NC}"
    return 1
}

# Show unified dashboard menu
show_unified_dashboard_menu() {
    clear
    echo -e "${GREEN}=== Unified Real-time Dashboard ===${NC}"
    echo ""
    
    # Show current status
    dashboard_status
    echo ""
    
    echo -e "${BLUE}Dashboard Management:${NC}"
    echo "  1. Start Dashboard"
    echo "  2. Stop Dashboard" 
    echo "  3. Restart Dashboard"
    echo "  4. Change Port"
    echo "  5. View Logs"
    echo "  6. Update Metrics Now"
    echo "  7. Back to main menu"
    echo ""
    
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1)
            read -p "Enter port (default: 8080): " port
            port=${port:-8080}
            start_unified_dashboard "$port"
            ;;
        2)
            stop_unified_dashboard
            ;;
        3)
            stop_unified_dashboard
            sleep 1
            start_unified_dashboard
            ;;
        4)
            read -p "Enter new port: " new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
                stop_unified_dashboard
                sleep 1
                start_unified_dashboard "$new_port"
            else
                warning "Invalid port number"
            fi
            ;;
        5)
            if [ -f "$DASHBOARD_DIR/server.log" ]; then
                echo ""
                echo "Last 20 lines of dashboard log:"
                tail -20 "$DASHBOARD_DIR/server.log"
            else
                warning "No log file found"
            fi
            ;;
        6)
            log "Updating metrics..."
            collect_unified_metrics
            log "✓ Metrics updated"
            ;;
        7)
            return 0
            ;;
        *)
            warning "Invalid choice: $choice"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_unified_dashboard_menu
}

# Export functions
export -f init_unified_dashboard
export -f get_primary_interface
export -f get_vpn_port
export -f collect_unified_metrics
export -f start_unified_dashboard
export -f stop_unified_dashboard
export -f dashboard_status
export -f show_unified_dashboard_menu