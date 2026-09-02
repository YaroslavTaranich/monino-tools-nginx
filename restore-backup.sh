#!/bin/bash
set -euo pipefail

BACKUP_DIR=${1:-}

if [[ -z "$BACKUP_DIR" || ! -f "$BACKUP_DIR/postgres.dump" || ! -f "$BACKUP_DIR/static-data.tar.gz" ]]; then
  echo "Usage: RESTORE_CONFIRM=yes $0 <backup-directory>" >&2
  exit 2
fi

if [[ ${RESTORE_CONFIRM:-no} != yes ]]; then
  echo "Restore replaces the current database and image volume. Set RESTORE_CONFIRM=yes to continue." >&2
  exit 2
fi

if command -v sha256sum > /dev/null 2>&1; then
  (cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS)
else
  (cd "$BACKUP_DIR" && shasum -a 256 -c SHA256SUMS)
fi

docker compose stop api admin user
docker compose exec -T postgres sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --clean --if-exists --create --username="$POSTGRES_USER" --dbname=postgres' \
  < "$BACKUP_DIR/postgres.dump"

docker compose run --rm --no-deps -T api sh -c \
  'find /app/static -mindepth 1 -delete && tar -C /app/static -xzf -' \
  < "$BACKUP_DIR/static-data.tar.gz"

docker compose up -d api admin user
echo "Restore complete: ${BACKUP_DIR}"
