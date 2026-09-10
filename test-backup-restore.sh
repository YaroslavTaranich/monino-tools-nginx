#!/bin/bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
BACKUP_ROOT="$TEST_ROOT/backups"
export BACKUP_ROOT
export COMPOSE_PROJECT_NAME="monino-backup-test-$$"

cleanup() {
  docker compose down -v --remove-orphans > /dev/null 2>&1 || true
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

docker compose up -d postgres
for _ in $(seq 1 30); do
  if docker compose exec -T postgres pg_isready \
    --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" > /dev/null; then
    break
  fi
  sleep 1
done
docker compose exec -T postgres pg_isready \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" > /dev/null

docker compose exec -T postgres psql \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --command="CREATE TABLE backup_marker (value TEXT NOT NULL); INSERT INTO backup_marker VALUES ('before-backup');" \
  > /dev/null
docker compose run --rm --no-deps -T api sh -c \
  "mkdir -p /app/static/image && printf 'before-backup' > /app/static/image/backup-test.txt"

./create-backup.sh
BACKUP_DIR=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)

docker compose exec -T postgres psql \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --command="UPDATE backup_marker SET value = 'after-backup';" > /dev/null
docker compose run --rm --no-deps -T api sh -c \
  "printf 'after-backup' > /app/static/image/backup-test.txt; printf 'remove-me' > /app/static/image/extra.txt"

RESTORE_CONFIRM=yes RESTORE_START_SERVICES=no ./restore-backup.sh "$BACKUP_DIR"

DATABASE_VALUE=$(docker compose exec -T postgres psql \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --tuples-only --no-align --command="SELECT value FROM backup_marker;")
[[ "$DATABASE_VALUE" == before-backup ]]

docker compose run --rm --no-deps -T api sh -c \
  "test \"\$(cat /app/static/image/backup-test.txt)\" = before-backup && test ! -e /app/static/image/extra.txt"

echo "Backup restore test passed."
