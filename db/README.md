# Database Directory

This directory contains the SQLite database files for the VPN Manager application.

## Files

- `vpn.db` - Main production database
- `*.db` - Other database files (development, testing, backups)

## Location

The database files are stored here relative to the project root to keep data organized and separate from the codebase.

## Backup

The database files in this directory should be included in your backup strategy for production deployments.

## Development

For development, you may see additional database files:
- `dev_vpn.db` - Development database
- `test_*.db` - Test databases (usually temporary)

## Note

This directory is ignored by git (except this README) to prevent committing sensitive database files.