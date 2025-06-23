#!/bin/bash

# =============================================================================
# Menu Module Loader
# 
# This module loads all menu-related modules.
# Provides a single function to load all menu functionality.
#
# Functions exported:
# - load_menu_modules()
#
# Dependencies: modules/menu/*
# =============================================================================

# =============================================================================
# MENU MODULE LOADING
# =============================================================================

load_menu_modules() {
    local debug="${1:-false}"
    local module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    [ "$debug" = true ] && log "Loading menu modules from: $module_dir"
    
    # Load main menu module
    if [ -f "$module_dir/main_menu.sh" ]; then
        source "$module_dir/main_menu.sh" || {
            error "Failed to load main_menu.sh"
            return 1
        }
        [ "$debug" = true ] && log "Loaded main_menu.sh"
    else
        error "Main menu module not found: $module_dir/main_menu.sh"
        return 1
    fi
    
    # Load user management menu module
    if [ -f "$module_dir/user_menu.sh" ]; then
        source "$module_dir/user_menu.sh" || {
            error "Failed to load user_menu.sh"
            return 1
        }
        [ "$debug" = true ] && log "Loaded user_menu.sh"
    else
        error "User menu module not found: $module_dir/user_menu.sh"
        return 1
    fi
    
    # Load server handlers module
    if [ -f "$module_dir/server_handlers.sh" ]; then
        source "$module_dir/server_handlers.sh" || {
            error "Failed to load server_handlers.sh"
            return 1
        }
        [ "$debug" = true ] && log "Loaded server_handlers.sh"
    else
        error "Server handlers module not found: $module_dir/server_handlers.sh"
        return 1
    fi
    
    [ "$debug" = true ] && log "All menu modules loaded successfully"
    return 0
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f load_menu_modules