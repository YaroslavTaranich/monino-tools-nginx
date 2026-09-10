#!/bin/bash
set -euo pipefail

BACKUP_DIR=${1:-}
REQUIRED_FILES=(postgres.dump static-data.tar.gz SHA256SUMS)

if [[ -z "$BACKUP_DIR" ]]; then
  echo "Usage: $0 <backup-directory>" >&2
  exit 2
fi

for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -s "$BACKUP_DIR/$file" ]]; then
    echo "Backup file is missing or empty: $BACKUP_DIR/$file" >&2
    exit 1
  fi
done

if command -v sha256sum > /dev/null 2>&1; then
  (cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS)
else
  (cd "$BACKUP_DIR" && shasum -a 256 -c SHA256SUMS)
fi

docker compose exec -T postgres pg_restore --list \
  < "$BACKUP_DIR/postgres.dump" > /dev/null

while IFS= read -r entry; do
  if [[ "$entry" == /* || "$entry" == .. || "$entry" == ../* || "$entry" == */.. || "$entry" == */../* ]]; then
    echo "Unsafe path in static-data archive: $entry" >&2
    exit 1
  fi
done < <(tar -tzf "$BACKUP_DIR/static-data.tar.gz")

echo "Backup verified: ${BACKUP_DIR}"
