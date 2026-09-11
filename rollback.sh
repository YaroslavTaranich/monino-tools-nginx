#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
MANIFEST=${1:-.previous-release.env}

[[ -f "$MANIFEST" ]] || {
  echo "Previous release manifest not found: $MANIFEST" >&2
  exit 1
}

while IFS='=' read -r key value; do
  case "$key" in
    RELEASE_VERSION|API_VERSION|ADMIN_VERSION|USER_VERSION) export "$key=$value" ;;
  esac
done < "$MANIFEST"

: "${RELEASE_VERSION:?Missing RELEASE_VERSION}"
: "${API_VERSION:?Missing API_VERSION}"
: "${ADMIN_VERSION:?Missing ADMIN_VERSION}"
: "${USER_VERSION:?Missing USER_VERSION}"

for service in api admin user; do
  case "$service" in
    api) version=$API_VERSION ;;
    admin) version=$ADMIN_VERSION ;;
    user) version=$USER_VERSION ;;
  esac
  if ! docker image inspect "monino-tools-${service}:${version}" > /dev/null 2>&1; then
    echo "Missing rollback image: monino-tools-${service}:${version}" >&2
    exit 1
  fi
done

docker compose up -d --no-build --no-deps api admin user
./smoke-test.sh
echo "Release ${RELEASE_VERSION} restored. Database migrations were left in place by design."
