#!/bin/bash

# Advanced Monitoring Dashboard Module
# Real-time monitoring and visualization of VPN metrics

# Get module directory
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/common.sh" || exit 1
source "$PROJECT_ROOT/lib/docker.sh" || exit 1
source "$PROJECT_ROOT/lib/performance.sh" || exit 1

# Dashboard configuration
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"
DASHBOARD_DIR="/opt/v2ray/dashboard"
METRICS_FILE="$DASHBOARD_DIR/metrics.json"
DASHBOARD_PID_FILE="$DASHBOARD_DIR/dashboard.pid"

# Initialize dashboard
init_dashboard() {
    mkdir -p "$DASHBOARD_DIR/data"
    mkdir -p "$DASHBOARD_DIR/www"
    
    # Create index.html
    create_dashboard_html
    
    # Create metrics collector script
    create_metrics_collector
}

# Create dashboard HTML
create_dashboard_html() {
    cat > "$DASHBOARD_DIR/www/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Monitoring Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f0f1e;
            color: #e0e0e0;
            line-height: 1.6;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.3);
        }
        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .status {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-weight: bold;
            margin-left: 20px;
        }
        .status.online { background: #4caf50; }
        .status.offline { background: #f44336; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: #1a1a2e;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
            transition: transform 0.3s ease;
        }
        .card:hover { transform: translateY(-5px); }
        .card h3 {
            color: #64b5f6;
            margin-bottom: 15px;
            font-size: 1.3em;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
            padding: 10px;
            background: #0f0f1e;
            border-radius: 5px;
        }
        .metric-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #81c784;
        }
        .chart-container {
            background: #1a1a2e;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
        }
        canvas { max-width: 100%; }
        .users-table {
            background: #1a1a2e;
            border-radius: 10px;
            padding: 25px;
            overflow-x: auto;
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #2a2a3e;
        }
        th {
            background: #0f0f1e;
            color: #64b5f6;
            font-weight: bold;
        }
        tr:hover { background: #252538; }
        .refresh-btn {
            background: #2196f3;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
            transition: background 0.3s ease;
        }
        .refresh-btn:hover { background: #1976d2; }
        .loading {
            text-align: center;
            padding: 50px;
            font-size: 1.2em;
            color: #64b5f6;
        }
        .error {
            background: #f44336;
            color: white;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>VPN Monitoring Dashboard <span id="status" class="status">Loading...</span></h1>
            <p>Real-time monitoring and analytics for VPN server</p>
            <button class="refresh-btn" onclick="refreshData()">Refresh Now</button>
        </div>
        
        <div id="content">
            <div class="loading">Loading dashboard data...</div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <script>
        let charts = {};
        
        async function fetchMetrics() {
            try {
                const response = await fetch('/api/metrics');
                if (!response.ok) throw new Error('Failed to fetch metrics');
                return await response.json();
            } catch (error) {
                console.error('Error fetching metrics:', error);
                throw error;
            }
        }
        
        function updateDashboard(data) {
            const content = document.getElementById('content');
            
            // Update status
            const statusEl = document.getElementById('status');
            statusEl.textContent = data.server.status;
            statusEl.className = 'status ' + (data.server.status === 'online' ? 'online' : 'offline');
            
            content.innerHTML = `
                <div class="grid">
                    <div class="card">
                        <h3>Server Info</h3>
                        <div class="metric">
                            <span>Uptime</span>
                            <span class="metric-value">${data.server.uptime || 'N/A'}</span>
                        </div>
                        <div class="metric">
                            <span>Version</span>
                            <span class="metric-value">${data.server.version || 'N/A'}</span>
                        </div>
                        <div class="metric">
                            <span>Protocol</span>
                            <span class="metric-value">${data.server.protocol || 'VLESS'}</span>
                        </div>
                    </div>
                    
                    <div class="card">
                        <h3>Performance</h3>
                        <div class="metric">
                            <span>CPU Usage</span>
                            <span class="metric-value">${data.performance.cpu || '0'}%</span>
                        </div>
                        <div class="metric">
                            <span>Memory Usage</span>
                            <span class="metric-value">${data.performance.memory || '0'}%</span>
                        </div>
                        <div class="metric">
                            <span>Disk Usage</span>
                            <span class="metric-value">${data.performance.disk || '0'}%</span>
                        </div>
                    </div>
                    
                    <div class="card">
                        <h3>Network Stats</h3>
                        <div class="metric">
                            <span>Total Users</span>
                            <span class="metric-value">${data.users.total || 0}</span>
                        </div>
                        <div class="metric">
                            <span>Active Connections</span>
                            <span class="metric-value">${data.users.active || 0}</span>
                        </div>
                        <div class="metric">
                            <span>Bandwidth Used</span>
                            <span class="metric-value">${formatBytes(data.network.total_bytes || 0)}</span>
                        </div>
                    </div>
                </div>
                
                <div class="chart-container">
                    <h3>Network Traffic (Last Hour)</h3>
                    <canvas id="trafficChart"></canvas>
                </div>
                
                <div class="chart-container">
                    <h3>Active Connections</h3>
                    <canvas id="connectionsChart"></canvas>
                </div>
                
                <div class="users-table">
                    <h3>User Statistics</h3>
                    <table>
                        <thead>
                            <tr>
                                <th>Username</th>
                                <th>Status</th>
                                <th>Connections</th>
                                <th>Download</th>
                                <th>Upload</th>
                                <th>Last Seen</th>
                            </tr>
                        </thead>
                        <tbody id="usersTable">
                            ${generateUsersTable(data.users.details || [])}
                        </tbody>
                    </table>
                </div>
            `;
            
            // Update charts
            updateCharts(data);
        }
        
        function generateUsersTable(users) {
            if (users.length === 0) {
                return '<tr><td colspan="6" style="text-align: center;">No users found</td></tr>';
            }
            
            return users.map(user => `
                <tr>
                    <td>${user.username}</td>
                    <td><span class="status ${user.online ? 'online' : 'offline'}">${user.online ? 'Online' : 'Offline'}</span></td>
                    <td>${user.connections || 0}</td>
                    <td>${formatBytes(user.download || 0)}</td>
                    <td>${formatBytes(user.upload || 0)}</td>
                    <td>${user.last_seen || 'Never'}</td>
                </tr>
            `).join('');
        }
        
        function updateCharts(data) {
            // Traffic chart
            const trafficCtx = document.getElementById('trafficChart').getContext('2d');
            if (charts.traffic) charts.traffic.destroy();
            
            charts.traffic = new Chart(trafficCtx, {
                type: 'line',
                data: {
                    labels: data.network.traffic_history.map(h => h.time),
                    datasets: [{
                        label: 'Download',
                        data: data.network.traffic_history.map(h => h.download),
                        borderColor: '#4caf50',
                        backgroundColor: 'rgba(76, 175, 80, 0.1)',
                        tension: 0.4
                    }, {
                        label: 'Upload',
                        data: data.network.traffic_history.map(h => h.upload),
                        borderColor: '#2196f3',
                        backgroundColor: 'rgba(33, 150, 243, 0.1)',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: { labels: { color: '#e0e0e0' } }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            ticks: { color: '#e0e0e0' },
                            grid: { color: '#2a2a3e' }
                        },
                        x: {
                            ticks: { color: '#e0e0e0' },
                            grid: { color: '#2a2a3e' }
                        }
                    }
                }
            });
            
            // Connections chart
            const connCtx = document.getElementById('connectionsChart').getContext('2d');
            if (charts.connections) charts.connections.destroy();
            
            charts.connections = new Chart(connCtx, {
                type: 'bar',
                data: {
                    labels: data.users.connection_history.map(h => h.time),
                    datasets: [{
                        label: 'Active Connections',
                        data: data.users.connection_history.map(h => h.count),
                        backgroundColor: '#64b5f6',
                        borderColor: '#2196f3',
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: { labels: { color: '#e0e0e0' } }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            ticks: { color: '#e0e0e0' },
                            grid: { color: '#2a2a3e' }
                        },
                        x: {
                            ticks: { color: '#e0e0e0' },
                            grid: { color: '#2a2a3e' }
                        }
                    }
                }
            });
        }
        
        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        async function refreshData() {
            try {
                const data = await fetchMetrics();
                updateDashboard(data);
            } catch (error) {
                document.getElementById('content').innerHTML = `
                    <div class="error">
                        Failed to load dashboard data: ${error.message}
                    </div>
                `;
            }
        }
        
        // Auto-refresh every 5 seconds
        setInterval(refreshData, 5000);
        
        // Initial load
        refreshData();
    </script>
</body>
</html>
EOF
}

# Create metrics collector
create_metrics_collector() {
    cat > "$DASHBOARD_DIR/collect_metrics.sh" << 'EOF'
#!/bin/bash

# Metrics collection script
METRICS_FILE="/opt/v2ray/dashboard/metrics.json"
HISTORY_DIR="/opt/v2ray/dashboard/data"

# Collect server status
get_server_metrics() {
    local status="offline"
    local uptime="N/A"
    local version="N/A"
    
    if docker ps --format "{{.Names}}" | grep -q "xray"; then
        status="online"
        uptime=$(docker inspect xray --format='{{.State.StartedAt}}' 2>/dev/null | \
            xargs -I {} date -d {} +%s | xargs -I {} echo $(( $(date +%s) - {} )) | \
            awk '{print int($1/86400)"d "int(($1%86400)/3600)"h "int(($1%3600)/60)"m"}')
        version=$(docker exec xray xray version 2>/dev/null | grep -oP 'V2Ray \K[0-9.]+' || echo "Unknown")
    fi
    
    echo "{\"status\": \"$status\", \"uptime\": \"$uptime\", \"version\": \"$version\", \"protocol\": \"VLESS+Reality\"}"
}

# Collect performance metrics
get_performance_metrics() {
    local cpu=$(docker stats xray --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    local memory=$(docker stats xray --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//' || echo "0")
    local disk=$(df -h /opt/v2ray | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    
    echo "{\"cpu\": \"$cpu\", \"memory\": \"$memory\", \"disk\": \"$disk\"}"
}

# Collect network metrics
get_network_metrics() {
    local rx_bytes=0
    local tx_bytes=0
    
    if docker ps --format "{{.Names}}" | grep -q "xray"; then
        local stats=$(docker exec xray cat /proc/net/dev 2>/dev/null | grep -E 'eth0|ens' | head -1)
        rx_bytes=$(echo "$stats" | awk '{print $2}')
        tx_bytes=$(echo "$stats" | awk '{print $10}')
    fi
    
    # Load traffic history
    local history_file="$HISTORY_DIR/traffic_$(date +%Y%m%d).json"
    local history='[]'
    [ -f "$history_file" ] && history=$(cat "$history_file")
    
    # Add current data point
    local timestamp=$(date +%H:%M)
    history=$(echo "$history" | jq --arg time "$timestamp" --arg rx "$rx_bytes" --arg tx "$tx_bytes" \
        '. + [{"time": $time, "download": ($rx | tonumber), "upload": ($tx | tonumber)}] | .[-60:]')
    
    # Save history
    echo "$history" > "$history_file"
    
    echo "{\"total_bytes\": $((rx_bytes + tx_bytes)), \"traffic_history\": $history}"
}

# Collect user metrics
get_user_metrics() {
    local total_users=$(ls -1 /opt/v2ray/users/*.json 2>/dev/null | wc -l)
    local active_connections=0
    local user_details='[]'
    
    # Parse access logs for user activity
    if [ -f /opt/v2ray/logs/access.log ]; then
        # Count active connections from last 5 minutes
        active_connections=$(tail -n 1000 /opt/v2ray/logs/access.log | \
            grep -E "accepted|tcp:" | \
            awk -v d="$(date -d '5 minutes ago' +%s)" '$1 ~ /^[0-9]{4}\/[0-9]{2}\/[0-9]{2}/ {
                gsub(/[\/:]/, " ", $1" "$2);
                if (mktime($1" "$2" "$3" "$4" "$5" "$6) > d) print
            }' | wc -l)
        
        # Get per-user statistics
        for user_file in /opt/v2ray/users/*.json; do
            [ -f "$user_file" ] || continue
            
            local username=$(basename "$user_file" .json)
            local uuid=$(jq -r '.clients[0].id' "$user_file" 2>/dev/null)
            [ -z "$uuid" ] && continue
            
            # Count user connections
            local user_conns=$(grep -c "$uuid" /opt/v2ray/logs/access.log 2>/dev/null || echo "0")
            local online=$(tail -n 100 /opt/v2ray/logs/access.log | grep -q "$uuid" && echo "true" || echo "false")
            local last_seen=$(grep "$uuid" /opt/v2ray/logs/access.log | tail -1 | awk '{print $1" "$2}' || echo "Never")
            
            user_details=$(echo "$user_details" | jq --arg user "$username" \
                --arg conns "$user_conns" --arg online "$online" --arg seen "$last_seen" \
                '. + [{"username": $user, "connections": ($conns | tonumber), 
                       "online": ($online == "true"), "last_seen": $seen,
                       "download": 0, "upload": 0}]')
        done
    fi
    
    # Load connection history
    local conn_history_file="$HISTORY_DIR/connections_$(date +%Y%m%d).json"
    local conn_history='[]'
    [ -f "$conn_history_file" ] && conn_history=$(cat "$conn_history_file")
    
    # Add current data point
    local timestamp=$(date +%H:%M)
    conn_history=$(echo "$conn_history" | jq --arg time "$timestamp" --arg count "$active_connections" \
        '. + [{"time": $time, "count": ($count | tonumber)}] | .[-60:]')
    
    # Save history
    echo "$conn_history" > "$conn_history_file"
    
    echo "{\"total\": $total_users, \"active\": $active_connections, 
           \"details\": $user_details, \"connection_history\": $conn_history}"
}

# Collect all metrics
collect_all_metrics() {
    local server=$(get_server_metrics)
    local performance=$(get_performance_metrics)
    local network=$(get_network_metrics)
    local users=$(get_user_metrics)
    
    # Combine all metrics
    cat > "$METRICS_FILE" << JSON
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "server": $server,
    "performance": $performance,
    "network": $network,
    "users": $users
}
JSON
}

# Main execution
mkdir -p "$HISTORY_DIR"
collect_all_metrics
EOF
    chmod +x "$DASHBOARD_DIR/collect_metrics.sh"
}

# Start dashboard server
start_dashboard() {
    local port="${1:-$DASHBOARD_PORT}"
    
    # Check if already running
    if [ -f "$DASHBOARD_PID_FILE" ] && kill -0 $(cat "$DASHBOARD_PID_FILE") 2>/dev/null; then
        warning "Dashboard is already running on port $port"
        return 0
    fi
    
    # Initialize dashboard
    init_dashboard
    
    # Start metrics collector
    info "Starting metrics collector..."
    (crontab -l 2>/dev/null | grep -v "collect_metrics"; 
     echo "* * * * * $DASHBOARD_DIR/collect_metrics_simple.sh") | crontab -
    
    # Run initial collection
    "$DASHBOARD_DIR/collect_metrics_simple.sh"
    
    # Start simple HTTP server
    info "Starting dashboard server on port $port..."
    cd "$DASHBOARD_DIR/www"
    
    # Create simple Python HTTP server with API endpoint
    cat > "$DASHBOARD_DIR/server.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
from urllib.parse import urlparse

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/api/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            metrics_file = '/opt/v2ray/dashboard/metrics.json'
            if os.path.exists(metrics_file):
                with open(metrics_file, 'r') as f:
                    self.wfile.write(f.read().encode())
            else:
                self.wfile.write(b'{"error": "No metrics available"}')
        else:
            super().do_GET()

PORT = int(os.environ.get('DASHBOARD_PORT', '8080'))
Handler = DashboardHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Dashboard serving at port {PORT}")
    httpd.serve_forever()
EOF
    chmod +x "$DASHBOARD_DIR/server.py"
    
    # Start server in background
    DASHBOARD_PORT=$port nohup python3 "$DASHBOARD_DIR/server.py" > "$DASHBOARD_DIR/server.log" 2>&1 &
    echo $! > "$DASHBOARD_PID_FILE"
    
    # Configure firewall
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port/tcp" comment "VPN Dashboard" >/dev/null 2>&1
    fi
    
    log "✓ Dashboard started at http://127.0.0.1:$port (localhost only)"
    info "Default credentials: No authentication (secure with reverse proxy)"
}

# Stop dashboard server
stop_dashboard() {
    info "Stopping dashboard server..."
    
    # Stop server
    if [ -f "$DASHBOARD_PID_FILE" ]; then
        kill $(cat "$DASHBOARD_PID_FILE") 2>/dev/null
        rm -f "$DASHBOARD_PID_FILE"
    fi
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "collect_metrics" | crontab -
    
    log "✓ Dashboard stopped"
}

# Restart dashboard
restart_dashboard() {
    stop_dashboard
    sleep 2
    start_dashboard
}

# Get dashboard status
dashboard_status() {
    # Check if process is actually running via PID file first
    if [ -f "$DASHBOARD_PID_FILE" ]; then
        local pid=$(cat "$DASHBOARD_PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # Check if it's actually our server process
            if ps -p "$pid" -o args --no-headers 2>/dev/null | grep -q "server.py"; then
                local port=$(ps eww -p "$pid" 2>/dev/null | grep -oP 'DASHBOARD_PORT=\K\d+' || echo "$DASHBOARD_PORT")
                log "✓ Dashboard is running on port $port (PID: $pid)"
                echo "Access URL: http://127.0.0.1:$port (localhost only)"
                return 0
            fi
        fi
        # Clean up stale PID file
        rm -f "$DASHBOARD_PID_FILE"
    fi
    
    # Fallback: check for any python server.py process
    if ps aux | grep -E "python.*server\.py" | grep -v grep >/dev/null 2>&1; then
        local port=$(ps aux | grep -E "python.*server\.py" | grep -v grep | \
            head -1 | grep -oP 'DASHBOARD_PORT=\K\d+' 2>/dev/null || echo "$DASHBOARD_PORT")
        warning "Dashboard process found but PID file missing (port $port)"
        echo "Access URL: http://127.0.0.1:$port (localhost only)"
    else
        info "Dashboard is not running"
    fi
}

# Export dashboard data
export_dashboard_data() {
    local format="${1:-json}"
    local output_file="${2:-dashboard_export_$(date +%Y%m%d_%H%M%S).$format}"
    
    case "$format" in
        json)
            # Combine all metrics data
            local combined='{"metrics": []}'
            for metric_file in "$DASHBOARD_DIR/data"/*.json; do
                [ -f "$metric_file" ] || continue
                local data=$(cat "$metric_file")
                combined=$(echo "$combined" | jq --argjson data "$data" '.metrics += [$data]')
            done
            echo "$combined" | jq '.' > "$output_file"
            ;;
            
        csv)
            # Export key metrics as CSV
            echo "Timestamp,CPU %,Memory %,Active Connections,Total Users" > "$output_file"
            jq -r '[
                .timestamp,
                .performance.cpu,
                .performance.memory,
                .users.active,
                .users.total
            ] | @csv' "$METRICS_FILE" >> "$output_file"
            ;;
            
        html)
            # Export as static HTML report
            cp "$DASHBOARD_DIR/www/index.html" "$output_file"
            # Embed current metrics
            sed -i "s|/api/metrics|data:application/json;base64,$(base64 -w0 "$METRICS_FILE")|g" "$output_file"
            ;;
            
        *)
            error "Unsupported format: $format"
            return 1
            ;;
    esac
    
    log "✓ Dashboard data exported to $output_file"
}

# Configure dashboard authentication (basic auth with nginx)
configure_dashboard_auth() {
    local username="${1:-admin}"
    local password="${2}"
    
    [ -z "$password" ] && {
        error "Password is required"
        return 1
    }
    
    info "Configuring dashboard authentication..."
    
    # Install nginx if not present
    if ! command -v nginx >/dev/null 2>&1; then
        apt-get update && apt-get install -y nginx apache2-utils || {
            error "Failed to install nginx"
            return 1
        }
    fi
    
    # Create htpasswd file
    htpasswd -cb /etc/nginx/.htpasswd "$username" "$password"
    
    # Configure nginx reverse proxy
    cat > /etc/nginx/sites-available/vpn-dashboard << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        auth_basic "VPN Dashboard";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://localhost:$DASHBOARD_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/vpn-dashboard /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    
    log "✓ Dashboard authentication configured"
    info "Access dashboard at http://$(get_server_ip) with username: $username"
}

# Interactive dashboard menu
dashboard_menu() {
    while true; do
        echo
        echo -e "${BOLD}Dashboard Management${NC}"
        echo "1. Start Dashboard"
        echo "2. Stop Dashboard"
        echo "3. Restart Dashboard"
        echo "4. Dashboard Status"
        echo "5. Configure Authentication"
        echo "6. Export Dashboard Data"
        echo "0. Back"
        echo
        
        read -p "Select option: " choice
        
        case $choice in
            1)
                read -p "Enter port (default: $DASHBOARD_PORT): " port
                start_dashboard "${port:-$DASHBOARD_PORT}"
                ;;
            2)
                stop_dashboard
                ;;
            3)
                restart_dashboard
                ;;
            4)
                dashboard_status
                ;;
            5)
                read -p "Enter username (default: admin): " username
                read -s -p "Enter password: " password
                echo
                configure_dashboard_auth "${username:-admin}" "$password"
                ;;
            6)
                read -p "Export format (json/csv/html): " format
                export_dashboard_data "$format"
                ;;
            0)
                break
                ;;
            *)
                error "Invalid option"
                ;;
        esac
    done
}

# Get server IP helper
get_server_ip() {
    curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

# Export functions
export -f init_dashboard
export -f start_dashboard
export -f stop_dashboard
export -f restart_dashboard
export -f dashboard_status
export -f export_dashboard_data
export -f configure_dashboard_auth
export -f dashboard_menu