#!/bin/bash
set -euo pipefail

SITE_URL=${SITE_URL:-https://moninotools.ru}
API_URL=${API_URL:-https://api.moninotools.ru}
ADMIN_URL=${ADMIN_URL:-https://admin.moninotools.ru}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

check_url() {
  local label=$1
  local url=$2
  curl --fail --silent --show-error --location --max-time 20 "$url" > /dev/null
  echo "OK: ${label} (${url})"
}

check_url "main page" "$SITE_URL/"
check_url "admin login page" "$ADMIN_URL/"
check_url "API health" "$API_URL/health"

curl --fail --silent --show-error --max-time 20 "$API_URL/category" > "$TMP_DIR/categories.json"
curl --fail --silent --show-error --max-time 20 "$API_URL/tools" > "$TMP_DIR/tools.json"

IFS=$'\t' read -r CATEGORY_ID CATEGORY_NAME TOOL_ID TOOL_NAME < <(node - "$TMP_DIR/categories.json" "$TMP_DIR/tools.json" <<'NODE'
const fs = require('fs');
const categories = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const tools = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
if (!categories.length || !tools.length) process.exit(2);
const tool = tools.find((item) => categories.some((category) => category.id === item.categoryId));
if (!tool) process.exit(3);
const category = categories.find((item) => item.id === tool.categoryId);
console.log([category.id, category.name, tool.id, tool.name].join('\t'));
NODE
)

check_url "category API" "$API_URL/category/$CATEGORY_ID"
check_url "tool list API" "$API_URL/tools?categoryId=$CATEGORY_ID"
check_url "tool card API" "$API_URL/tools/$TOOL_ID"
check_url "category page" "$SITE_URL/$CATEGORY_NAME/"
check_url "tool card page" "$SITE_URL/$CATEGORY_NAME/$TOOL_NAME/"

if [[ -n ${SMOKE_ADMIN_NAME:-} && -n ${SMOKE_ADMIN_PASSWORD:-} ]]; then
  LOGIN_PAYLOAD=$(node -e 'console.log(JSON.stringify({name: process.argv[1], password: process.argv[2]}))' "$SMOKE_ADMIN_NAME" "$SMOKE_ADMIN_PASSWORD")
  curl --fail --silent --show-error --max-time 20 \
    -H 'Content-Type: application/json' \
    --data "$LOGIN_PAYLOAD" \
    "$API_URL/auth/admin" > /dev/null
  echo "OK: admin authentication"
else
  echo "SKIP: admin authentication (set SMOKE_ADMIN_NAME and SMOKE_ADMIN_PASSWORD to enable)"
fi

echo "Smoke tests passed."
