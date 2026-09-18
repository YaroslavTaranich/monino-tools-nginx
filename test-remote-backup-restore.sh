#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TEST_ROOT=$(mktemp -d)
export COMPOSE_PROJECT_NAME="monino-remote-restore-test-$$"
export COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml:$SCRIPT_DIR/docker-compose.verify.yml"

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

"$SCRIPT_DIR/download-remote-backup.sh" latest "$TEST_ROOT/backups"
BACKUP_DIR=$(find "$TEST_ROOT/backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[[ -n "$BACKUP_DIR" ]]

RESTORE_CONFIRM=yes RESTORE_START_SERVICES=no \
  "$SCRIPT_DIR/restore-backup.sh" "$BACKUP_DIR"
docker compose exec -T postgres psql \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --tuples-only --no-align --command='SELECT 1;' | grep -qx 1
TABLE_COUNT=$(docker compose exec -T postgres psql \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --tuples-only --no-align \
  --command="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
(( TABLE_COUNT > 0 ))
docker compose run --rm --no-deps -T api tar -C /app/static -czf - . > /dev/null

echo "Remote backup restored successfully in isolated Docker volumes."
