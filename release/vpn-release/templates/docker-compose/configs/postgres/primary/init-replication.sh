#!/bin/bash
# PostgreSQL Primary Replication Setup Script

set -e

echo "Setting up PostgreSQL primary for replication..."

# Create replication user if it doesn't exist
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    -- Create replication user
    DO
    \$\$
    BEGIN
        IF NOT EXISTS (
            SELECT FROM pg_catalog.pg_roles
            WHERE rolname = '$POSTGRES_REPLICATION_USER'
        ) THEN
            CREATE ROLE $POSTGRES_REPLICATION_USER WITH REPLICATION LOGIN PASSWORD '$POSTGRES_REPLICATION_PASSWORD';
        END IF;
    END
    \$\$;

    -- Grant replication permissions
    GRANT CONNECT ON DATABASE $POSTGRES_DB TO $POSTGRES_REPLICATION_USER;
    
    -- Create replication slot for each replica
    SELECT pg_create_physical_replication_slot('replica_1_slot', true);
    SELECT pg_create_physical_replication_slot('replica_2_slot', true);
    
    -- Ensure proper WAL settings
    ALTER SYSTEM SET wal_level = 'replica';
    ALTER SYSTEM SET max_wal_senders = 10;
    ALTER SYSTEM SET max_replication_slots = 10;
    ALTER SYSTEM SET wal_keep_size = '1GB';
    ALTER SYSTEM SET hot_standby = 'on';
    ALTER SYSTEM SET hot_standby_feedback = 'on';
    ALTER SYSTEM SET wal_log_hints = 'on';
    
    -- Performance settings for replication
    ALTER SYSTEM SET synchronous_commit = 'local';
    ALTER SYSTEM SET checkpoint_segments = 16;
    ALTER SYSTEM SET checkpoint_completion_target = 0.9;
    
    -- Create database for Grafana if needed
    CREATE DATABASE IF NOT EXISTS grafana;
    GRANT ALL PRIVILEGES ON DATABASE grafana TO $POSTGRES_USER;
EOSQL

# Configure pg_hba.conf for replication
cat >> "$PGDATA/pg_hba.conf" <<EOF

# Replication connections
host    replication     $POSTGRES_REPLICATION_USER    172.21.0.0/16    md5
host    replication     $POSTGRES_REPLICATION_USER    172.20.0.0/16    md5
host    all             all                          172.21.0.0/16    md5
host    all             all                          172.20.0.0/16    md5
EOF

# Create archive directory
mkdir -p /mnt/archive
chown postgres:postgres /mnt/archive

echo "PostgreSQL primary replication setup completed!"

# Signal PostgreSQL to reload configuration
pg_ctl reload -D "$PGDATA"