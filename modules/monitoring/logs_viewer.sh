#!/bin/bash
#
# Logs Viewer Module
# Handles viewing and analyzing VPN server logs
# Extracted from manage_users.sh as part of Phase 5 refactoring

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/ui.sh"

# Initialize module
init_logs_viewer() {
    debug "Initializing logs viewer module"
    
    # Verify required tools are available
    command -v jq >/dev/null 2>&1 || {
        log "jq not installed. Installing jq..."
        apt install -y jq || error "Failed to install jq"
    }
    
    debug "Logs viewer module initialized successfully"
}

# Check if log files exist
check_log_files() {
    local access_log="$WORK_DIR/logs/access.log"
    local error_log="$WORK_DIR/logs/error.log"
    
    debug "Checking log files existence"
    
    if [ -f "$access_log" ]; then
        echo "access_log:$access_log"
    else
        echo "access_log:missing"
    fi
    
    if [ -f "$error_log" ]; then
        echo "error_log:$error_log"
    else
        echo "error_log:missing"
    fi
}

# Display log file information
display_log_info() {
    debug "Displaying log file information"
    
    local access_log="$WORK_DIR/logs/access.log"
    local error_log="$WORK_DIR/logs/error.log"
    
    echo -e "  ${GREEN}📊 Log Files Information:${NC}"
    
    # Access log info
    if [ -f "$access_log" ]; then
        local size lines
        size=$(du -h "$access_log" 2>/dev/null | cut -f1)
        lines=$(wc -l < "$access_log" 2>/dev/null || echo "0")
        echo -e "    📝 Access Log: ${YELLOW}$access_log${NC}"
        echo -e "      📏 Size: ${YELLOW}$size${NC}, Lines: ${YELLOW}$lines${NC}"
        
        if [ -s "$access_log" ]; then
            local oldest newest
            oldest=$(head -n1 "$access_log" 2>/dev/null | awk '{print $1, $2}' || echo "unknown")
            newest=$(tail -n1 "$access_log" 2>/dev/null | awk '{print $1, $2}' || echo "unknown")
            echo -e "      📅 Range: ${YELLOW}$oldest${NC} to ${YELLOW}$newest${NC}"
        fi
    else
        echo -e "    📝 Access Log: ${RED}Not available${NC}"
    fi
    
    # Error log info
    if [ -f "$error_log" ]; then
        local size lines
        size=$(du -h "$error_log" 2>/dev/null | cut -f1)
        lines=$(wc -l < "$error_log" 2>/dev/null || echo "0")
        echo -e "    🚨 Error Log: ${YELLOW}$error_log${NC}"
        echo -e "      📏 Size: ${YELLOW}$size${NC}, Lines: ${YELLOW}$lines${NC}"
    else
        echo -e "    🚨 Error Log: ${RED}Not available${NC}"
    fi
    
    echo ""
}

# Show recent connections
show_recent_connections() {
    local count="${1:-20}"
    local access_log="$WORK_DIR/logs/access.log"
    
    debug "Showing recent connections: $count entries"
    
    if [ ! -f "$access_log" ]; then
        echo -e "    ${RED}❌ Access log not available${NC}"
        echo -e "    💡 Configure logging first using the logging module"
        return 1
    fi
    
    echo -e "  ${GREEN}📋 Last $count Connections:${NC}"
    echo ""
    
    if [ -s "$access_log" ]; then
        tail -n "$count" "$access_log" 2>/dev/null | while IFS= read -r line; do
            # Parse and format log entry
            local formatted_line
            formatted_line=$(format_log_entry "$line")
            echo -e "    $formatted_line"
        done
    else
        echo -e "    ${YELLOW}📭 No connection logs available${NC}"
    fi
    
    echo ""
}

# Format a single log entry for better readability
format_log_entry() {
    local log_entry="$1"
    
    # Basic formatting - highlight important parts
    local formatted
    formatted=$(echo "$log_entry" | sed -E '
        s/([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})/\x1b[36m\1\x1b[0m/g
        s/(email:[^ ]*)/\x1b[33m\1\x1b[0m/g
        s/(accepted|rejected|error)/\x1b[32m\1\x1b[0m/g
    ')
    
    echo "$formatted"
}

# Search user activity in logs
search_user_activity() {
    local username="$1"
    local access_log="$WORK_DIR/logs/access.log"
    
    debug "Searching user activity for: $username"
    
    if [ -z "$username" ]; then
        echo -e "    ${RED}❌ Username required${NC}"
        return 1
    fi
    
    if [ ! -f "$access_log" ]; then
        echo -e "    ${RED}❌ Access log not available${NC}"
        return 1
    fi
    
    echo -e "  ${GREEN}🔍 Activity for user: ${YELLOW}$username${NC}"
    echo ""
    
    # Search for user activity (case insensitive)
    local activity
    activity=$(grep -i "$username" "$access_log" 2>/dev/null)
    
    if [ -n "$activity" ]; then
        local count
        count=$(echo "$activity" | wc -l)
        echo -e "    📊 Found $count entries:"
        echo ""
        
        # Show last 10 entries
        echo "$activity" | tail -10 | while IFS= read -r line; do
            local formatted_line
            formatted_line=$(format_log_entry "$line")
            echo -e "    $formatted_line"
        done
        
        if [ "$count" -gt 10 ]; then
            echo ""
            echo -e "    ${YELLOW}... and $((count - 10)) more entries${NC}"
        fi
    else
        echo -e "    ${YELLOW}📭 No activity found for user: $username${NC}"
    fi
    
    echo ""
}

# Show connection statistics by user
show_user_connection_stats() {
    local access_log="$WORK_DIR/logs/access.log"
    
    debug "Showing user connection statistics"
    
    if [ ! -f "$access_log" ] || [ ! -s "$access_log" ]; then
        echo -e "    ${RED}❌ Access log not available or empty${NC}"
        return 1
    fi
    
    echo -e "  ${GREEN}📊 Connection Statistics by User:${NC}"
    echo ""
    
    # Extract and count user connections
    local stats
    stats=$(grep -o 'email:[^[:space:]]*' "$access_log" 2>/dev/null | \
           sed 's/email://' | \
           sort | uniq -c | sort -nr | head -10)
    
    if [ -n "$stats" ]; then
        echo -e "    ${BLUE}Top 10 Users by Connections:${NC}"
        echo "$stats" | while read -r count email; do
            echo -e "      ${YELLOW}$email${NC}: $count connections"
        done
    else
        echo -e "    ${YELLOW}📭 No user statistics available${NC}"
    fi
    
    echo ""
}

# Show error log entries
show_error_logs() {
    local count="${1:-20}"
    local error_log="$WORK_DIR/logs/error.log"
    
    debug "Showing error logs: $count entries"
    
    if [ ! -f "$error_log" ]; then
        echo -e "    ${RED}❌ Error log not available${NC}"
        return 1
    fi
    
    echo -e "  ${GREEN}🚨 Last $count Error Entries:${NC}"
    echo ""
    
    if [ -s "$error_log" ]; then
        tail -n "$count" "$error_log" 2>/dev/null | while IFS= read -r line; do
            # Highlight error levels
            local formatted_line
            formatted_line=$(echo "$line" | sed -E '
                s/(ERROR|FATAL)/\x1b[31m\1\x1b[0m/g
                s/(WARNING|WARN)/\x1b[33m\1\x1b[0m/g
                s/([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})/\x1b[36m\1\x1b[0m/g
            ')
            echo -e "    $formatted_line"
        done
    else
        echo -e "    ${GREEN}✅ No errors found${NC}"
    fi
    
    echo ""
}

# Monitor logs in real-time
monitor_logs_realtime() {
    local log_type="${1:-access}"
    local access_log="$WORK_DIR/logs/access.log"
    local error_log="$WORK_DIR/logs/error.log"
    
    debug "Starting real-time log monitoring: $log_type"
    
    case "$log_type" in
        access|connections)
            if [ -f "$access_log" ]; then
                echo -e "  ${GREEN}📊 Real-time Access Log Monitoring${NC}"
                echo -e "  📍 Monitoring: ${YELLOW}$access_log${NC}"
                echo -e "  🛑 Press Ctrl+C to stop"
                echo ""
                tail -f "$access_log" 2>/dev/null || error "Failed to monitor access log"
            else
                error "Access log not available: $access_log"
            fi
            ;;
        error|errors)
            if [ -f "$error_log" ]; then
                echo -e "  ${GREEN}🚨 Real-time Error Log Monitoring${NC}"
                echo -e "  📍 Monitoring: ${YELLOW}$error_log${NC}"
                echo -e "  🛑 Press Ctrl+C to stop"
                echo ""
                tail -f "$error_log" 2>/dev/null || error "Failed to monitor error log"
            else
                error "Error log not available: $error_log"
            fi
            ;;
        both|all)
            if [ -f "$access_log" ] && [ -f "$error_log" ]; then
                echo -e "  ${GREEN}📊 Real-time Log Monitoring (Both Files)${NC}"
                echo -e "  📍 Monitoring: ${YELLOW}$access_log${NC} and ${YELLOW}$error_log${NC}"
                echo -e "  🛑 Press Ctrl+C to stop"
                echo ""
                tail -f "$access_log" "$error_log" 2>/dev/null || error "Failed to monitor logs"
            else
                error "One or both log files not available"
            fi
            ;;
        *)
            error "Invalid log type: $log_type. Use: access, error, or both"
            ;;
    esac
}

# Search logs with patterns
search_logs() {
    local pattern="$1"
    local log_type="${2:-access}"
    local access_log="$WORK_DIR/logs/access.log"
    local error_log="$WORK_DIR/logs/error.log"
    
    debug "Searching logs for pattern: $pattern in $log_type"
    
    if [ -z "$pattern" ]; then
        error "Search pattern required"
    fi
    
    echo -e "  ${GREEN}🔍 Searching for: ${YELLOW}$pattern${NC}"
    echo ""
    
    case "$log_type" in
        access)
            if [ -f "$access_log" ]; then
                local results
                results=$(grep -i "$pattern" "$access_log" 2>/dev/null)
                display_search_results "$results" "access log"
            else
                echo -e "    ${RED}❌ Access log not available${NC}"
            fi
            ;;
        error)
            if [ -f "$error_log" ]; then
                local results
                results=$(grep -i "$pattern" "$error_log" 2>/dev/null)
                display_search_results "$results" "error log"
            else
                echo -e "    ${RED}❌ Error log not available${NC}"
            fi
            ;;
        both)
            echo -e "  ${BLUE}📝 Search in Access Log:${NC}"
            if [ -f "$access_log" ]; then
                local results
                results=$(grep -i "$pattern" "$access_log" 2>/dev/null)
                display_search_results "$results" "access log"
            else
                echo -e "    ${RED}❌ Access log not available${NC}"
            fi
            
            echo -e "  ${BLUE}🚨 Search in Error Log:${NC}"
            if [ -f "$error_log" ]; then
                local results
                results=$(grep -i "$pattern" "$error_log" 2>/dev/null)
                display_search_results "$results" "error log"
            else
                echo -e "    ${RED}❌ Error log not available${NC}"
            fi
            ;;
        *)
            error "Invalid log type: $log_type. Use: access, error, or both"
            ;;
    esac
    
    echo ""
}

# Display search results
display_search_results() {
    local results="$1"
    local log_name="$2"
    
    if [ -n "$results" ]; then
        local count
        count=$(echo "$results" | wc -l)
        echo -e "    📊 Found $count matches in $log_name:"
        echo ""
        
        # Show first 10 results
        echo "$results" | head -10 | while IFS= read -r line; do
            local formatted_line
            formatted_line=$(format_log_entry "$line")
            echo -e "    $formatted_line"
        done
        
        if [ "$count" -gt 10 ]; then
            echo ""
            echo -e "    ${YELLOW}... and $((count - 10)) more matches${NC}"
        fi
    else
        echo -e "    ${YELLOW}📭 No matches found in $log_name${NC}"
    fi
}

# Generate log analysis report
generate_log_report() {
    local output_file="$1"
    local access_log="$WORK_DIR/logs/access.log"
    local error_log="$WORK_DIR/logs/error.log"
    
    debug "Generating log analysis report"
    
    if [ -z "$output_file" ]; then
        output_file="$WORK_DIR/log_analysis_$(date +%Y%m%d_%H%M%S).txt"
    fi
    
    {
        echo "VPN Server Log Analysis Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        # Access log analysis
        if [ -f "$access_log" ] && [ -s "$access_log" ]; then
            echo "ACCESS LOG ANALYSIS"
            echo "==================="
            echo "File: $access_log"
            echo "Size: $(du -h "$access_log" | cut -f1)"
            echo "Total entries: $(wc -l < "$access_log")"
            echo ""
            
            echo "Top 10 Users by Connection Count:"
            grep -o 'email:[^[:space:]]*' "$access_log" 2>/dev/null | \
            sed 's/email://' | sort | uniq -c | sort -nr | head -10
            echo ""
            
            echo "Recent Activity (last 10 entries):"
            tail -10 "$access_log"
            echo ""
        else
            echo "ACCESS LOG: Not available or empty"
            echo ""
        fi
        
        # Error log analysis
        if [ -f "$error_log" ] && [ -s "$error_log" ]; then
            echo "ERROR LOG ANALYSIS"
            echo "=================="
            echo "File: $error_log"
            echo "Size: $(du -h "$error_log" | cut -f1)"
            echo "Total entries: $(wc -l < "$error_log")"
            echo ""
            
            echo "Recent Errors (last 10 entries):"
            tail -10 "$error_log"
            echo ""
        else
            echo "ERROR LOG: Not available or empty"
            echo ""
        fi
        
        # System information
        echo "SYSTEM INFORMATION"
        echo "=================="
        echo "Report generated: $(date)"
        echo "Server IP: $(curl -s https://api.ipify.org 2>/dev/null || echo 'unknown')"
        if [ -f "$CONFIG_FILE" ]; then
            echo "VPN Port: $(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null || echo 'unknown')"
            echo "Users: $(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo 'unknown')"
        fi
        
    } > "$output_file"
    
    if [ $? -eq 0 ]; then
        log "Log analysis report generated: $output_file"
        echo "$output_file"
    else
        error "Failed to generate log analysis report"
    fi
}

# Main function to view user logs
view_user_logs() {
    log "📖 VPN Server Log Viewer"
    echo ""
    
    # Initialize module
    init_logs_viewer
    
    # Check if logs are available
    local log_files
    log_files=$(check_log_files)
    
    local access_log_status error_log_status
    access_log_status=$(echo "$log_files" | grep "access_log:" | cut -d: -f2)
    error_log_status=$(echo "$log_files" | grep "error_log:" | cut -d: -f2)
    
    if [ "$access_log_status" = "missing" ] && [ "$error_log_status" = "missing" ]; then
        echo -e "${RED}❌ No log files available${NC}"
        echo ""
        echo -e "💡 ${YELLOW}To enable logging:${NC}"
        echo "   1. Use the logging configuration module"
        echo "   2. Configure Xray logging from the main menu"
        echo "   3. Restart the VPN server"
        echo ""
        return 1
    fi
    
    # Display log information
    display_log_info
    
    # Interactive menu
    echo -e "  ${GREEN}📋 Log Viewer Options:${NC}"
    echo "    1. Show recent connections (last 20)"
    echo "    2. Search specific user activity"
    echo "    3. Show connection statistics by user"
    echo "    4. Show error logs (last 20)"
    echo "    5. Monitor logs in real-time"
    echo "    6. Search logs with pattern"
    echo "    7. Generate log analysis report"
    echo ""
    
    local choice
    read -p "  Select option [1-7]: " choice
    
    case $choice in
        1)
            show_recent_connections 20
            ;;
        2)
            # Source list module if available for user selection
            if [ -f "$PROJECT_DIR/modules/users/list.sh" ]; then
                source "$PROJECT_DIR/modules/users/list.sh"
                list_users 2>/dev/null || true
            fi
            echo ""
            read -p "  Enter username to search: " username
            if [ -n "$username" ]; then
                search_user_activity "$username"
            fi
            ;;
        3)
            show_user_connection_stats
            ;;
        4)
            show_error_logs 20
            ;;
        5)
            echo ""
            echo "  Monitor which log?"
            echo "    1. Access log (connections)"
            echo "    2. Error log"
            echo "    3. Both logs"
            read -p "  Choose [1-3]: " monitor_choice
            
            case $monitor_choice in
                1) monitor_logs_realtime "access" ;;
                2) monitor_logs_realtime "error" ;;
                3) monitor_logs_realtime "both" ;;
                *) warning "Invalid choice" ;;
            esac
            ;;
        6)
            echo ""
            read -p "  Enter search pattern: " pattern
            if [ -n "$pattern" ]; then
                echo "  Search in which log?"
                echo "    1. Access log"
                echo "    2. Error log"
                echo "    3. Both logs"
                read -p "  Choose [1-3]: " log_choice
                
                case $log_choice in
                    1) search_logs "$pattern" "access" ;;
                    2) search_logs "$pattern" "error" ;;
                    3) search_logs "$pattern" "both" ;;
                    *) warning "Invalid choice" ;;
                esac
            fi
            ;;
        7)
            local report_file
            report_file=$(generate_log_report)
            if [ -n "$report_file" ]; then
                echo "  Report saved to: $report_file"
            fi
            ;;
        *)
            warning "Invalid choice: $choice"
            ;;
    esac
}

# Quick log view (minimal output)
quick_log_view() {
    local count="${1:-5}"
    
    debug "Quick log view: $count entries"
    
    # Initialize module
    init_logs_viewer
    
    local access_log="$WORK_DIR/logs/access.log"
    
    if [ -f "$access_log" ] && [ -s "$access_log" ]; then
        echo "Recent connections:"
        tail -n "$count" "$access_log" 2>/dev/null | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo "No access logs available"
    fi
}

# Export functions for use by other modules
export -f init_logs_viewer
export -f check_log_files
export -f display_log_info
export -f show_recent_connections
export -f format_log_entry
export -f search_user_activity
export -f show_user_connection_stats
export -f show_error_logs
export -f monitor_logs_realtime
export -f search_logs
export -f display_search_results
export -f generate_log_report
export -f view_user_logs
export -f quick_log_view