#!/bin/bash
set -euo pipefail

SERVICES=(api admin user)
ROLLBACK_ARMED=0
PREVIOUS_IMAGE_COUNT=0

tag_current_images() {
  local service container_id image_id
  for service in "${SERVICES[@]}"; do
    container_id=$(docker compose ps -q "$service" 2>/dev/null)
    if [[ -n "$container_id" ]]; then
      image_id=$(docker inspect --format '{{.Image}}' "$container_id")
      docker tag "$image_id" "monino-tools-${service}:rollback"
      PREVIOUS_IMAGE_COUNT=$((PREVIOUS_IMAGE_COUNT + 1))
    fi
  done
}

rollback_containers() {
  if [[ "$ROLLBACK_ARMED" -ne 1 ]]; then
    return
  fi
  echo "Deployment failed; restoring previous application images." >&2
  APP_VERSION=rollback docker compose up -d --no-build api admin user || true
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

trap rollback_containers ERR

# A failed build leaves all currently running containers untouched.
tag_current_images
docker compose build "${SERVICES[@]}"

./create-backup.sh
if [[ "$PREVIOUS_IMAGE_COUNT" -eq "${#SERVICES[@]}" ]]; then
  ROLLBACK_ARMED=1
fi

# Migrations run in a one-off container before the API is replaced.
docker compose run --rm --no-deps api npm run migration:up

docker compose up -d --no-deps api
wait_healthy api

docker compose up -d --no-deps admin user
wait_healthy admin
wait_healthy user

./smoke-test.sh
ROLLBACK_ARMED=0
echo "Deployment completed successfully."
