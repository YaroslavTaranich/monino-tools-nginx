#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=$(mktemp -d)
SERVER_PID=
source "$SCRIPT_DIR/remote-backup-lib.sh"

cleanup() {
  remote_backup_cleanup_credentials
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" > /dev/null 2>&1 || true
    wait "$SERVER_PID" > /dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

python3 "$SCRIPT_DIR/test-webdav-server.py" "$WORK_DIR/storage" "$WORK_DIR/port" &
SERVER_PID=$!
for _ in $(seq 1 50); do
  [[ -s "$WORK_DIR/port" ]] && break
  sleep 0.1
done
[[ -s "$WORK_DIR/port" ]]

REMOTE_BACKUP_BASE_URL="http://127.0.0.1:$(cat "$WORK_DIR/port")"
REMOTE_BACKUP_PARENT_URL="${REMOTE_BACKUP_BASE_URL}/Monino%20Tools"
REMOTE_BACKUP_URL="${REMOTE_BACKUP_PARENT_URL}/backups"
YANDEX_WEBDAV_USERNAME=test-user
YANDEX_WEBDAV_PASSWORD='test password'
remote_backup_require_credentials
remote_backup_ensure_collection

ARCHIVE_NAME=monino-tools-backup-20260919T120000Z.tar.gz
printf 'backup payload' > "$WORK_DIR/$ARCHIVE_NAME"
printf '%s  %s\n' "$(remote_backup_sha256 "$WORK_DIR/$ARCHIVE_NAME")" "$ARCHIVE_NAME" \
  > "$WORK_DIR/$ARCHIVE_NAME.sha256"
remote_backup_put "$WORK_DIR/$ARCHIVE_NAME.sha256" "$ARCHIVE_NAME.sha256"
remote_backup_put "$WORK_DIR/$ARCHIVE_NAME" "$ARCHIVE_NAME"
remote_backup_list "$WORK_DIR/list.xml"
python3 "$SCRIPT_DIR/parse-webdav-list.py" < "$WORK_DIR/list.xml" > "$WORK_DIR/names"
grep -Fxq "$ARCHIVE_NAME" "$WORK_DIR/names"
grep -Fxq "$ARCHIVE_NAME.sha256" "$WORK_DIR/names"

remote_backup_get "$ARCHIVE_NAME" "$WORK_DIR/downloaded"
cmp "$WORK_DIR/$ARCHIVE_NAME" "$WORK_DIR/downloaded"
remote_backup_delete "$ARCHIVE_NAME"
remote_backup_delete "$ARCHIVE_NAME.sha256"
remote_backup_list "$WORK_DIR/list-after-delete.xml"
python3 "$SCRIPT_DIR/parse-webdav-list.py" < "$WORK_DIR/list-after-delete.xml" \
  | grep -Fq "$ARCHIVE_NAME" && {
    echo "Deleted archive is still listed." >&2
    exit 1
  }

echo "Remote backup WebDAV transport test passed."
