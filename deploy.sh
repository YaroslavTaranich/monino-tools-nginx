#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
# shellcheck source=release-lib.sh
source ./release-lib.sh

RELEASE_MANIFEST=${RELEASE_MANIFEST:-release.env}
SERVICES=(api admin user)
CHANGED_SERVICES=()
ROLLBACK_ARMED=0
PREVIOUS_IMAGE_COUNT=0

validate_release_source "$RELEASE_MANIFEST"

service_version() {
  case "$1" in
    api) echo "$API_VERSION" ;;
    admin) echo "$ADMIN_VERSION" ;;
    user) echo "$USER_VERSION" ;;
  esac
}

service_commit() {
  case "$1" in
    api) echo "$API_COMMIT" ;;
    admin) echo "$ADMIN_COMMIT" ;;
    user) echo "$USER_COMMIT" ;;
  esac
}

target_image() {
  echo "monino-tools-$1:$(service_version "$1")"
}

revision_image() {
  echo "monino-tools-$1:$(service_commit "$1")"
}

capture_previous_release() {
  local output=.previous-release.env.tmp
  local service container_id image_ref version release
  release=legacy
  : > "$output"

  for service in "${SERVICES[@]}"; do
    container_id=$(docker compose ps -q "$service" 2>/dev/null)
    [[ -n "$container_id" ]] || continue
    image_ref=$(docker inspect --format '{{.Config.Image}}' "$container_id")
    version=${image_ref##*:}
    release=$(docker inspect --format '{{index .Config.Labels "com.moninotools.release"}}' "$container_id" 2>/dev/null || true)
    [[ -n "$release" ]] || release=legacy
    case "$service" in
      api) PREVIOUS_API_VERSION=$version ;;
      admin) PREVIOUS_ADMIN_VERSION=$version ;;
      user) PREVIOUS_USER_VERSION=$version ;;
    esac
    PREVIOUS_IMAGE_COUNT=$((PREVIOUS_IMAGE_COUNT + 1))
  done

  if [[ "$PREVIOUS_IMAGE_COUNT" -eq "${#SERVICES[@]}" ]]; then
    {
      echo "RELEASE_VERSION=$release"
      echo "API_VERSION=$PREVIOUS_API_VERSION"
      echo "ADMIN_VERSION=$PREVIOUS_ADMIN_VERSION"
      echo "USER_VERSION=$PREVIOUS_USER_VERSION"
    } > "$output"
    mv "$output" .previous-release.env
  else
    rm -f "$output"
  fi
}

restore_previous_images() {
  if [[ "$ROLLBACK_ARMED" -ne 1 ]]; then
    return
  fi
  echo "Deployment failed; restoring release ${PREVIOUS_RELEASE_VERSION:-previous}." >&2
  API_VERSION=$PREVIOUS_API_VERSION \
    ADMIN_VERSION=$PREVIOUS_ADMIN_VERSION \
    USER_VERSION=$PREVIOUS_USER_VERSION \
    docker compose up -d --no-build --no-deps api admin user || true
}

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

verify_existing_version() {
  local service=$1 image revision expected_commit
  image=$(target_image "$service")
  expected_commit=$(service_commit "$service")
  if docker image inspect "$image" > /dev/null 2>&1; then
    revision=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")
    [[ "$revision" == "$expected_commit" ]] ||
      release_error "$image already exists with revision ${revision:-unknown}; version reuse is forbidden"
  fi
}

capture_previous_release
for service in "${SERVICES[@]}"; do
  verify_existing_version "$service"
  container_id=$(docker compose ps -q "$service" 2>/dev/null)
  current_image=
  if [[ -n "$container_id" ]]; then
    current_image=$(docker inspect --format '{{.Config.Image}}' "$container_id")
  fi
  if [[ "$current_image" != "$(target_image "$service")" ]]; then
    CHANGED_SERVICES+=("$service")
  fi
done

if [[ "${#CHANGED_SERVICES[@]}" -eq 0 ]]; then
  echo "Release ${RELEASE_VERSION} is already deployed."
  ./smoke-test.sh
  exit 0
fi

echo "Changed services: ${CHANGED_SERVICES[*]}"
docker compose build "${CHANGED_SERVICES[@]}"
for service in "${CHANGED_SERVICES[@]}"; do
  verify_existing_version "$service"
  docker tag "$(target_image "$service")" "$(revision_image "$service")"
done

RELEASE_MANIFEST="$RELEASE_MANIFEST" ./create-backup.sh
if [[ "$PREVIOUS_IMAGE_COUNT" -eq "${#SERVICES[@]}" ]]; then
  PREVIOUS_RELEASE_VERSION=$(sed -n 's/^RELEASE_VERSION=//p' .previous-release.env)
  ROLLBACK_ARMED=1
fi
trap restore_previous_images ERR

if [[ " ${CHANGED_SERVICES[*]} " == *" api "* ]]; then
  docker compose run --rm --no-deps api npm run migration:up
  docker compose run --rm --no-deps api npm run images:cleanup -- --delete
  docker compose up -d --no-deps api
  wait_healthy api
fi

for service in admin user; do
  if [[ " ${CHANGED_SERVICES[*]} " == *" $service "* ]]; then
    docker compose up -d --no-deps "$service"
    wait_healthy "$service"
  fi
done

./smoke-test.sh
ROLLBACK_ARMED=0
echo "Release ${RELEASE_VERSION} deployed successfully: ${CHANGED_SERVICES[*]}."
