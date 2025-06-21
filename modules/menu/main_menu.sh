#!/bin/bash

# =============================================================================
# Main Menu Module
# 
# This module handles the main interactive menu display and navigation.
# Extracted from vpn.sh for modular architecture.
#
# Functions exported:
# - show_main_menu()
# - handle_menu_choice()
# - run_interactive_menu()
#
# Dependencies: lib/common.sh, lib/ui.sh
# =============================================================================

# Source required libraries if not already sourced
if [ -z "$COMMON_SOURCED" ]; then
    MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    COMMON_PATH="${PROJECT_ROOT:-$MODULE_DIR/../..}/lib/common.sh"
    source "$COMMON_PATH" 2>/dev/null || {
        echo "Error: Cannot source lib/common.sh from $COMMON_PATH"
        return 1 2>/dev/null || exit 1
    }
fi

# =============================================================================
# MAIN MENU DISPLAY
# =============================================================================

show_main_menu() {
    clear
    echo -e "${GREEN}=== VPN Management System v${SCRIPT_VERSION:-3.0} ===${NC}"
    echo ""
    echo -e "${YELLOW}Server Management:${NC}"
    echo "  1)  📦 Install VPN Server"
    echo "  2)  📊 Server Status"
    echo "  3)  🔄 Restart Server"
    echo "  4)  🗑️  Uninstall Server"
    echo ""
    echo -e "${YELLOW}User Management:${NC}"
    echo "  5)  👥 User Management"
    echo ""
    echo -e "${YELLOW}Advanced:${NC}"
    echo "  6)  🛡️  Watchdog Service"
    echo "  7)  🔧 Fix Reality Issues"
    echo "  8)  ✅ Validate Configuration"
    echo "  9)  🔍 System Diagnostics"
    echo "  10) 🧹 Clean Up Unused Ports"
    echo ""
    echo -e "${YELLOW}Security & Performance:${NC}"
    echo "  11) 🔒 Security Hardening"
    echo "  12) 🚀 Speed Testing"
    echo "  13) 📊 Monitoring Dashboard"
    echo ""
    echo -e "${YELLOW}Help & Info:${NC}"
    echo "  14) ❓ Show Help"
    echo "  15) ℹ️  Show Version"
    echo ""
    echo -e "${RED}  0)  🚪 Exit${NC}"
    echo ""
}

# =============================================================================
# MENU CHOICE HANDLING
# =============================================================================

handle_menu_choice() {
    local choice="$1"
    
    case "$choice" in
        1)
            handle_server_install
            ;;
        2)
            handle_server_status
            ;;
        3)
            handle_server_restart
            ;;
        4)
            handle_server_uninstall
            ;;
        5)
            handle_user_management
            ;;
        6)
            handle_watchdog_menu
            ;;
        7)
            handle_fix_reality
            ;;
        8)
            handle_validate_config
            ;;
        9)
            handle_system_diagnostics
            ;;
        10)
            handle_cleanup_ports
            ;;
        11)
            handle_security_hardening
            ;;
        12)
            handle_speed_testing
            ;;
        13)
            handle_monitoring_dashboard
            ;;
        14)
            show_usage
            read -p "Press Enter to continue..."
            ;;
        15)
            show_version
            read -p "Press Enter to continue..."
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            warning "Invalid option. Please choose 0-15."
            ;;
    esac
}

# =============================================================================
# SUBMENU HANDLERS
# =============================================================================


# Removed duplicate Xray management menu - functionality moved to main menu options

handle_watchdog_menu() {
    echo -e "${BLUE}Watchdog Service:${NC}"
    echo "1) Install Service"
    echo "2) Start Service"
    echo "3) Stop Service"
    echo "4) Restart Service"
    echo "5) Service Status"
    echo "6) Remove Service"
    echo "0) Back"
    read -p "Select option: " watchdog_choice
    case "$watchdog_choice" in
        1) SUB_ACTION="install"; handle_watchdog ;;
        2) SUB_ACTION="start"; handle_watchdog ;;
        3) SUB_ACTION="stop"; handle_watchdog ;;
        4) SUB_ACTION="restart"; handle_watchdog ;;
        5) SUB_ACTION="status"; handle_watchdog ;;
        6) SUB_ACTION="remove"; handle_watchdog ;;
        0) return ;;
        *) warning "Invalid option" ;;
    esac
}

# =============================================================================
# INTERACTIVE MENU LOOP
# =============================================================================

run_interactive_menu() {
    # Set interactive mode flag
    export INTERACTIVE_MODE=1
    
    # Trap to ensure we always exit with 0
    trap 'exit 0' INT TERM EXIT
    
    while true; do
        show_main_menu
        read -p "Select option (0-15): " choice
        
        # Handle errors gracefully
        handle_menu_choice "$choice" || {
            # If error occurred, show message and continue
            echo ""
            read -p "Press Enter to continue..."
            continue
        }
        
        if [ "$choice" = "0" ]; then
            exit 0
        fi
        
        if [ "$choice" = "0" ] || [ "$choice" = "7" ] || [ "$choice" = "8" ]; then
            # Exit or help/version already have their own prompts or exits
            true
        else
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# =============================================================================
# ADVANCED OPTION HANDLERS
# =============================================================================

# Handler for Fix Reality Issues option
handle_fix_reality() {
    echo -e "${BLUE}🔧 Запуск исправления Reality ключей...${NC}"
    echo
    
    # Call the fix_reality function from vpn.sh
    if fix_reality; then
        echo -e "${GREEN}✅ Reality ключи успешно исправлены${NC}"
    else
        echo -e "${RED}❌ Ошибка при исправлении Reality ключей${NC}"
    fi
    
    echo
    echo -e "${CYAN}Нажмите Enter для продолжения...${NC}"
    read
}

# Handler for Validate Configuration option
handle_validate_config() {
    echo -e "${BLUE}✅ Запуск проверки конфигурации...${NC}"
    echo
    
    # Load the validate module if not already loaded
    load_module_lazy "server/validate_config.sh"
    
    # Call the validate configuration function
    if validate_server_config; then
        echo -e "${GREEN}✅ Конфигурация прошла проверку${NC}"
    else
        echo -e "${RED}❌ Обнаружены проблемы в конфигурации${NC}"
    fi
    
    echo
    echo -e "${CYAN}Нажмите Enter для продолжения...${NC}"
    read
}

# Handler for System Diagnostics option
handle_system_diagnostics() {
    echo -e "${BLUE}🔍 Запуск системной диагностики...${NC}"
    echo
    
    # Load the diagnostics module if not already loaded
    load_module_lazy "system/diagnostics.sh"
    
    # Run full diagnostics
    if run_full_diagnostics; then
        echo -e "${GREEN}✅ Диагностика завершена${NC}"
    else
        echo -e "${YELLOW}⚠️  Обнаружены проблемы, см. отчет выше${NC}"
    fi
    
    echo
    echo -e "${CYAN}Нажмите Enter для продолжения...${NC}"
    read
}

# Handler for Cleanup Ports option
handle_cleanup_ports() {
    echo -e "${BLUE}🧹 Очистка неиспользуемых VPN портов...${NC}"
    echo
    
    # Call the cleanup function from vpn.sh
    if cleanup_vpn_ports_interactive; then
        echo -e "${GREEN}✅ Очистка портов завершена${NC}"
    else
        echo -e "${RED}❌ Ошибка при очистке портов${NC}"
    fi
    
    echo
    echo -e "${CYAN}Нажмите Enter для продолжения...${NC}"
    read
}

# Handler for Security Hardening option
handle_security_hardening() {
    echo -e "${BLUE}🔒 Security Hardening Management${NC}"
    echo
    
    # Load security module if not already loaded
    load_module_lazy "security/hardening.sh"
    
    # Show security menu
    while true; do
        echo -e "${BOLD}Security Features:${NC}"
        echo "1. Run Security Audit"
        echo "2. Apply Security Hardening"
        echo "3. Configure Security Features"
        echo "4. View Security Status"
        echo "0. Back"
        echo
        
        read -p "Select option: " sec_choice
        
        case $sec_choice in
            1)
                run_security_audit
                read -p "Press Enter to continue..."
                ;;
            2)
                apply_security_hardening
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "\n${BOLD}Available Security Features:${NC}"
                echo "1. Fail2ban (Brute-force protection)"
                echo "2. Port Knocking"
                echo "3. Geo-blocking"
                echo "4. Rate Limiting"
                echo "5. Connection Limits"
                echo "6. Intrusion Detection"
                echo
                read -p "Select feature to configure: " feature_choice
                
                case $feature_choice in
                    1) feature="fail2ban" ;;
                    2) feature="port_knocking" ;;
                    3) feature="geo_blocking" ;;
                    4) feature="rate_limiting" ;;
                    5) feature="connection_limits" ;;
                    6) feature="intrusion_detection" ;;
                    *) echo "Invalid choice"; continue ;;
                esac
                
                read -p "Enable or disable? (enable/disable): " action
                if [ "$action" = "enable" ] || [ "$action" = "disable" ]; then
                    configure_security_feature "$feature" "$action"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                if [ -f "/opt/v2ray/config/security.json" ]; then
                    echo -e "\n${BOLD}Current Security Configuration:${NC}"
                    jq '.' /opt/v2ray/config/security.json
                else
                    echo "Security configuration not found"
                fi
                read -p "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                warning "Invalid option"
                ;;
        esac
    done
}

# Handler for Speed Testing option
handle_speed_testing() {
    echo -e "${BLUE}🚀 Connection Speed Testing${NC}"
    echo
    
    # Load speed test module if not already loaded
    load_module_lazy "monitoring/speed_test.sh"
    
    # Show speed test menu
    while true; do
        echo -e "${BOLD}Speed Test Options:${NC}"
        echo "1. Run Comprehensive Speed Test"
        echo "2. Test Latency Only"
        echo "3. Test Download Speed"
        echo "4. Test Upload Speed"
        echo "5. Show Speed Test History"
        echo "6. Schedule Periodic Tests"
        echo "7. Export Test Results"
        echo "0. Back"
        echo
        
        read -p "Select option: " speed_choice
        
        case $speed_choice in
            1)
                run_comprehensive_speed_test
                read -p "Press Enter to continue..."
                ;;
            2)
                for endpoint in "8.8.8.8" "1.1.1.1"; do
                    echo -n "Testing $endpoint: "
                    result=$(test_connection_latency "$endpoint" 5)
                    if echo "$result" | jq -e '.avg' >/dev/null 2>&1; then
                        avg=$(echo "$result" | jq -r '.avg')
                        echo -e "${GREEN}${avg}ms${NC}"
                    else
                        echo -e "${RED}Failed${NC}"
                    fi
                done
                read -p "Press Enter to continue..."
                ;;
            3)
                test_download_speed
                read -p "Press Enter to continue..."
                ;;
            4)
                test_upload_speed
                read -p "Press Enter to continue..."
                ;;
            5)
                show_speed_test_history 20
                read -p "Press Enter to continue..."
                ;;
            6)
                read -p "Test interval in hours (default: 6): " interval
                read -p "Enable scheduling? (yes/no): " enable
                schedule_speed_tests "${interval:-6}" "$([[ "$enable" == "yes" ]] && echo "true" || echo "false")"
                read -p "Press Enter to continue..."
                ;;
            7)
                read -p "Export format (json/csv): " format
                export_speed_test_results "$format"
                read -p "Press Enter to continue..."
                ;;
            0)
                break
                ;;
            *)
                warning "Invalid option"
                ;;
        esac
    done
}

# Handler for Monitoring Dashboard option
handle_monitoring_dashboard() {
    echo -e "${BLUE}📊 Monitoring Dashboard Management${NC}"
    echo
    
    # Load dashboard module if not already loaded
    load_module_lazy "monitoring/dashboard.sh"
    
    # Show dashboard menu
    dashboard_menu
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f show_main_menu
export -f handle_menu_choice
# handle_xray_management removed - functionality integrated into main menu
export -f handle_watchdog_menu
export -f handle_fix_reality
export -f handle_validate_config
export -f handle_system_diagnostics
export -f handle_cleanup_ports
export -f handle_security_hardening
export -f handle_speed_testing
export -f handle_monitoring_dashboard
export -f run_interactive_menu