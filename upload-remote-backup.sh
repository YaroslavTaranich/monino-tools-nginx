#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/remote-backup-lib.sh"

BACKUP_DIR=${1:-}
if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "Usage: $0 <backup-directory>" >&2
  exit 2
fi

BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd)
BACKUP_TIMESTAMP=$(basename "$BACKUP_DIR")
[[ "$BACKUP_TIMESTAMP" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
  echo "Backup directory must use a UTC timestamp name." >&2
  exit 2
}

WORK_DIR=$(mktemp -d)
cleanup() {
  remote_backup_cleanup_credentials
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

"$SCRIPT_DIR/verify-backup.sh" "$BACKUP_DIR"
ARCHIVE_NAME="monino-tools-backup-${BACKUP_TIMESTAMP}.tar.gz"
ARCHIVE="$WORK_DIR/$ARCHIVE_NAME"
CHECKSUM="$ARCHIVE.sha256"
tar -C "$(dirname "$BACKUP_DIR")" -czf "$ARCHIVE" "$BACKUP_TIMESTAMP"
printf '%s  %s\n' "$(remote_backup_sha256 "$ARCHIVE")" "$ARCHIVE_NAME" > "$CHECKSUM"

remote_backup_require_credentials
remote_backup_ensure_collection
remote_backup_put "$CHECKSUM" "$ARCHIVE_NAME.sha256"
remote_backup_put "$ARCHIVE" "$ARCHIVE_NAME"

DOWNLOADED="$WORK_DIR/downloaded-$ARCHIVE_NAME"
DOWNLOADED_CHECKSUM="$DOWNLOADED.sha256"
remote_backup_get "$ARCHIVE_NAME" "$DOWNLOADED"
remote_backup_get "$ARCHIVE_NAME.sha256" "$DOWNLOADED_CHECKSUM"
remote_backup_verify_download "$DOWNLOADED" "$DOWNLOADED_CHECKSUM"
remote_backup_safe_extract "$DOWNLOADED" "$WORK_DIR/verified"
"$SCRIPT_DIR/verify-backup.sh" "$WORK_DIR/verified/$BACKUP_TIMESTAMP"

echo "Remote backup uploaded and verified: $ARCHIVE_NAME"
"$SCRIPT_DIR/rotate-remote-backups.sh"
