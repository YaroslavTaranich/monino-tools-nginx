#!/bin/sh
set -e

echo "Installing required packages..."
apk add --no-cache postgresql-client tar find

echo "Creating backup directory..."
BACKUP_DIR="/backups/$(date '+%Y-%m-%d_%H-%M-%S')"
mkdir -p "$BACKUP_DIR"

echo "Backing up PostgreSQL database..."
export PGPASSWORD="$POSTGRES_PASSWORD"
pg_dump -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$BACKUP_DIR/db.sql"

echo "Archiving static files..."
tar -czf "$BACKUP_DIR/static.tar.gz" -C /static-data .

echo "Cleaning old backups (older than 7 days)..."
find /backups -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "Backup completed successfully to $BACKUP_DIR"
ls -la "$BACKUP_DIR"