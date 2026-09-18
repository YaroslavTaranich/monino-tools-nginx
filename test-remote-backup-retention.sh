#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

for timestamp in \
  20260301T120000Z 20260401T120000Z 20260501T120000Z \
  20260601T120000Z 20260701T120000Z 20260801T120000Z \
  20260824T120000Z 20260831T120000Z 20260907T120000Z \
  20260913T120000Z 20260914T120000Z 20260915T120000Z \
  20260916T120000Z 20260917T100000Z 20260917T120000Z 20260918T120000Z \
  20260918T180000Z 20260919T120000Z; do
  echo "monino-tools-backup-${timestamp}.tar.gz"
done > "$WORK_DIR/input"

python3 "$SCRIPT_DIR/remote-backup-retention.py" --now 20260919T130000Z \
  < "$WORK_DIR/input" > "$WORK_DIR/plan"

grep -q $'^KEEP\tmonino-tools-backup-20260919T120000Z.tar.gz\t' "$WORK_DIR/plan"
grep -q $'^KEEP\tmonino-tools-backup-20260918T180000Z.tar.gz\t' "$WORK_DIR/plan"
grep -q $'^DELETE\tmonino-tools-backup-20260917T100000Z.tar.gz\texpired' "$WORK_DIR/plan"
grep -q $'^KEEP\tmonino-tools-backup-20260831T120000Z.tar.gz\t.*weekly' "$WORK_DIR/plan"
grep -q $'^KEEP\tmonino-tools-backup-20260401T120000Z.tar.gz\tmonthly' "$WORK_DIR/plan"
grep -q $'^DELETE\tmonino-tools-backup-20260301T120000Z.tar.gz\texpired' "$WORK_DIR/plan"

if printf '%s\n%s\n' \
  monino-tools-backup-20260919T120000Z.tar.gz \
  monino-tools-backup-20260919T120000Z.tar.gz | \
  python3 "$SCRIPT_DIR/remote-backup-retention.py" --now 20260919T130000Z > /dev/null 2>&1; then
  echo "Duplicate backup names were accepted." >&2
  exit 1
fi

echo "Remote backup retention test passed."
