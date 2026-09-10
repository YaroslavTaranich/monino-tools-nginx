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

./verify-backup.sh "$BACKUP_DIR"

docker compose stop api admin user
docker compose exec -T postgres sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --clean --if-exists --create --username="$POSTGRES_USER" --dbname=postgres' \
  < "$BACKUP_DIR/postgres.dump"

docker compose run --rm --no-deps -T api sh -c \
  'set -eu
  staging=/app/static/.restore-staging
  rm -rf "$staging"
  mkdir "$staging"
  trap '\''rm -rf "$staging"'\'' EXIT
  tar -C "$staging" -xzf -
  for path in /app/static/* /app/static/.[!.]* /app/static/..?*; do
    [ -e "$path" ] || continue
    [ "$path" = "$staging" ] || rm -rf "$path"
  done
  for path in "$staging"/* "$staging"/.[!.]* "$staging"/..?*; do
    [ -e "$path" ] || continue
    mv "$path" /app/static/
  done
  rmdir "$staging"
  trap - EXIT' \
  < "$BACKUP_DIR/static-data.tar.gz"

if [[ ${RESTORE_START_SERVICES:-yes} == yes ]]; then
  docker compose up -d api admin user
fi
echo "Restore complete: ${BACKUP_DIR}"
