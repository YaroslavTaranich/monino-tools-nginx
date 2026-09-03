#!/bin/bash
set -euo pipefail

for service in api admin user; do
  if ! docker image inspect "monino-tools-${service}:rollback" > /dev/null 2>&1; then
    echo "Missing rollback image: monino-tools-${service}:rollback" >&2
    exit 1
  fi
done

APP_VERSION=rollback docker compose up -d --no-build --no-deps api admin user
echo "Previous application images restored. Database migrations were left in place by design."
