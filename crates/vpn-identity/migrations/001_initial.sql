-- Initial schema for VPN Identity service (SQLite compatible)

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    email TEXT,
    display_name TEXT,
    provider TEXT NOT NULL,
    provider_id TEXT,
    roles TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login TEXT
);

CREATE TABLE IF NOT EXISTS roles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    permissions TEXT NOT NULL DEFAULT '[]',
    description TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS permissions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    resource TEXT NOT NULL,
    action TEXT NOT NULL,
    description TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Add some sample data for sqlx macros to work
INSERT OR IGNORE INTO permissions (id, name, resource, action, description) VALUES 
('perm1', 'admin', 'system', 'manage', 'System admin permissions'),
('perm2', 'user', 'vpn', 'connect', 'VPN connection permissions');

INSERT OR IGNORE INTO roles (id, name, permissions, description) VALUES 
('role1', 'admin', '["admin"]', 'Administrator role'),
('role2', 'user', '["user"]', 'Regular user role');

INSERT OR IGNORE INTO users (id, username, provider, roles) VALUES 
('user1', 'admin', 'local', '["admin"]'),
('user2', 'testuser', 'local', '["user"]');