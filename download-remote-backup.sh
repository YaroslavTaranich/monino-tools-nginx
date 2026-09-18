#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/remote-backup-lib.sh"

REQUESTED=${1:-latest}
DESTINATION=${2:-./backups/remote-restore}
WORK_DIR=$(mktemp -d)
STAGING_DIR=
cleanup() {
  remote_backup_cleanup_credentials
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

remote_backup_require_credentials
remote_backup_list "$WORK_DIR/list.xml"
python3 "$SCRIPT_DIR/parse-webdav-list.py" < "$WORK_DIR/list.xml" > "$WORK_DIR/names"
grep -E '^monino-tools-backup-[0-9]{8}T[0-9]{6}Z\.tar\.gz$' "$WORK_DIR/names" \
  > "$WORK_DIR/archives" || true

if [[ "$REQUESTED" == latest ]]; then
  ARCHIVE_NAME=$(sort "$WORK_DIR/archives" | tail -n 1)
else
  ARCHIVE_NAME=$REQUESTED
fi
remote_backup_validate_archive_name "$ARCHIVE_NAME" || {
  echo "No valid remote backup selected." >&2
  exit 1
}
grep -Fxq "$ARCHIVE_NAME" "$WORK_DIR/archives" || {
  echo "Remote backup does not exist: $ARCHIVE_NAME" >&2
  exit 1
}
grep -Fxq "$ARCHIVE_NAME.sha256" "$WORK_DIR/names" || {
  echo "Remote checksum is missing: $ARCHIVE_NAME.sha256" >&2
  exit 1
}

remote_backup_get "$ARCHIVE_NAME" "$WORK_DIR/$ARCHIVE_NAME"
remote_backup_get "$ARCHIVE_NAME.sha256" "$WORK_DIR/$ARCHIVE_NAME.sha256"
remote_backup_verify_download "$WORK_DIR/$ARCHIVE_NAME" "$WORK_DIR/$ARCHIVE_NAME.sha256"

mkdir -p "$DESTINATION"
DESTINATION=$(cd "$DESTINATION" && pwd)
BACKUP_TIMESTAMP=${ARCHIVE_NAME#monino-tools-backup-}
BACKUP_TIMESTAMP=${BACKUP_TIMESTAMP%.tar.gz}
[[ ! -e "$DESTINATION/$BACKUP_TIMESTAMP" ]] || {
  echo "Destination backup already exists: $DESTINATION/$BACKUP_TIMESTAMP" >&2
  exit 1
}
STAGING_DIR="$DESTINATION/.remote-backup-staging-${BACKUP_TIMESTAMP}-$$"
remote_backup_safe_extract "$WORK_DIR/$ARCHIVE_NAME" "$STAGING_DIR"
[[ -d "$STAGING_DIR/$BACKUP_TIMESTAMP" ]] || {
  echo "Remote archive does not contain the expected backup directory." >&2
  exit 1
}
"$SCRIPT_DIR/verify-backup.sh" "$STAGING_DIR/$BACKUP_TIMESTAMP"
mv "$STAGING_DIR/$BACKUP_TIMESTAMP" "$DESTINATION/$BACKUP_TIMESTAMP"
rm -rf "$STAGING_DIR"
STAGING_DIR=
echo "Remote backup downloaded and verified: $DESTINATION/$BACKUP_TIMESTAMP"
