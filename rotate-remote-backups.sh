#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/remote-backup-lib.sh"

WORK_DIR=$(mktemp -d)
cleanup() {
  remote_backup_cleanup_credentials
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

remote_backup_require_credentials
remote_backup_list "$WORK_DIR/list.xml"
python3 "$SCRIPT_DIR/parse-webdav-list.py" < "$WORK_DIR/list.xml" > "$WORK_DIR/names"
grep -E '^monino-tools-backup-[0-9]{8}T[0-9]{6}Z\.tar\.gz$' "$WORK_DIR/names" \
  > "$WORK_DIR/archives" || true
ARCHIVE_COUNT=$(wc -l < "$WORK_DIR/archives" | tr -d ' ')

while IFS= read -r archive; do
  grep -Fxq "$archive.sha256" "$WORK_DIR/names" || {
    echo "Rotation blocked: checksum is missing for $archive." >&2
    exit 1
  }
done < "$WORK_DIR/archives"

RETENTION_ARGS=()
if [[ -n ${REMOTE_BACKUP_NOW:-} ]]; then
  RETENTION_ARGS+=(--now "$REMOTE_BACKUP_NOW")
fi
python3 "$SCRIPT_DIR/remote-backup-retention.py" "${RETENTION_ARGS[@]}" \
  < "$WORK_DIR/archives" > "$WORK_DIR/plan"
cat "$WORK_DIR/plan"

if [[ ${REMOTE_BACKUP_ROTATION_APPLY:-no} != yes ]]; then
  echo "Rotation dry-run complete. Set REMOTE_BACKUP_ROTATION_APPLY=yes to delete expired backups."
  exit 0
fi

DELETE_COUNT=$(awk -F '\t' '$1 == "DELETE" {count++} END {print count+0}' "$WORK_DIR/plan")
if (( DELETE_COUNT > 0 && ARCHIVE_COUNT < 3 )); then
  echo "Rotation blocked: remote listing is unexpectedly short ($ARCHIVE_COUNT archives)." >&2
  exit 1
fi
if (( DELETE_COUNT >= ARCHIVE_COUNT && DELETE_COUNT > 0 )); then
  echo "Rotation blocked: plan would delete every remote backup." >&2
  exit 1
fi

while IFS=$'\t' read -r action archive _reason; do
  [[ "$action" == DELETE ]] || continue
  remote_backup_delete "$archive"
  remote_backup_delete "$archive.sha256"
  echo "Deleted expired remote backup: $archive"
done < "$WORK_DIR/plan"
echo "Remote backup rotation applied."
