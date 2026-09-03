#!/bin/bash
set -euo pipefail

BACKUP_ROOT=${BACKUP_ROOT:-./backups}
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"

docker compose exec -T postgres sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --create --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
  > "${BACKUP_DIR}/postgres.dump"

docker compose run --rm --no-deps -T api tar -C /app/static -czf - . \
  > "${BACKUP_DIR}/static-data.tar.gz"

docker compose config --no-interpolate > "${BACKUP_DIR}/compose.yml"
git -c safe.directory="$PWD" rev-parse HEAD > "${BACKUP_DIR}/git-revision.txt"
(
  cd "$BACKUP_DIR"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum postgres.dump static-data.tar.gz > SHA256SUMS
  else
    shasum -a 256 postgres.dump static-data.tar.gz > SHA256SUMS
  fi
)

echo "Backup created: ${BACKUP_DIR}"
