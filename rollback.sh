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

wait_healthy() {
  local service=$1
  local container_id status
  container_id=$(docker compose ps -q "$service")

  for _ in $(seq 1 36); do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")
    if [[ "$status" == healthy || "$status" == running ]]; then
      return 0
    fi
    if [[ "$status" == unhealthy || "$status" == exited || "$status" == dead ]]; then
      docker compose logs --tail=100 "$service" >&2
      return 1
    fi
    sleep 5
  done

  docker compose logs --tail=100 "$service" >&2
  return 1
}

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
for service in api admin user; do
  wait_healthy "$service"
done
./smoke-test.sh
echo "Release ${RELEASE_VERSION} restored. Database migrations were left in place by design."
