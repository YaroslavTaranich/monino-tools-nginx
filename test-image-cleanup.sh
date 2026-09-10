#!/bin/bash
set -euo pipefail

export COMPOSE_PROJECT_NAME="monino-image-cleanup-test-$$"

cleanup() {
  docker compose down -v --remove-orphans > /dev/null 2>&1 || true
}

trap cleanup EXIT

docker compose up -d postgres
for _ in $(seq 1 30); do
  if docker compose exec -T postgres pg_isready \
    --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" > /dev/null; then
    break
  fi
  sleep 1
done
docker compose exec -T postgres pg_isready \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" > /dev/null

docker compose exec -T postgres psql \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" > /dev/null <<'SQL'
CREATE TABLE categories (id SERIAL PRIMARY KEY, image VARCHAR(255));
CREATE TABLE tools (id SERIAL PRIMARY KEY, image VARCHAR(255));
CREATE TABLE tool_images (id SERIAL PRIMARY KEY, storage_key VARCHAR(255) NOT NULL);
INSERT INTO categories (image) VALUES ('image/category.jpg');
INSERT INTO tools (image) VALUES ('image/cover.webp');
INSERT INTO tool_images (storage_key) VALUES ('image/gallery.webp');
SQL

docker compose run --rm --no-deps -T api sh -c \
  "mkdir -p /app/static/image && touch /app/static/image/category.jpg /app/static/image/cover.webp /app/static/image/gallery.webp /app/static/image/orphan.webp"

docker compose run --rm --no-deps -T -e IMAGE_CLEANUP_MIN_AGE_HOURS=0 api \
  npm run images:cleanup
docker compose run --rm --no-deps -T api test -e /app/static/image/orphan.webp

docker compose run --rm --no-deps -T -e IMAGE_CLEANUP_MIN_AGE_HOURS=0 api \
  npm run images:cleanup -- --delete
docker compose run --rm --no-deps -T api sh -c \
  "test -e /app/static/image/category.jpg && test -e /app/static/image/cover.webp && test -e /app/static/image/gallery.webp && test ! -e /app/static/image/orphan.webp"

echo "Image cleanup test passed."
