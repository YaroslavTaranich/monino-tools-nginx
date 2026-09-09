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

check_status() {
  local label=$1
  local expected=$2
  local method=$3
  local url=$4
  local actual
  actual=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --max-time 20 --request "$method" "$url")
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: ${label} expected ${expected}, received ${actual}" >&2
    return 1
  fi
  echo "OK: ${label} (${actual})"
}

check_url "main page" "$SITE_URL/"
check_url "admin login page" "$ADMIN_URL/"
check_url "API health" "$API_URL/health"
check_status "profile requires a session" 401 GET "$API_URL/auth/profile"
check_status "registration is closed" 404 POST "$API_URL/auth/reg"
check_status "user management is removed" 404 GET "$API_URL/user"

IFS=$'\t' read -r CATEGORY_ID CATEGORY_NAME TOOL_ID TOOL_NAME < <(docker compose exec -T api node - "$API_URL" <<'NODE'
const baseUrl = process.argv[2];
Promise.all([
  fetch(`${baseUrl}/category`).then((response) => {
    if (!response.ok) throw new Error(`/category ${response.status}`);
    return response.json();
  }),
  fetch(`${baseUrl}/tools`).then((response) => {
    if (!response.ok) throw new Error(`/tools ${response.status}`);
    return response.json();
  }),
  fetch(`${baseUrl}/tool-types`).then((response) => {
    if (!response.ok) throw new Error(`/tool-types ${response.status}`);
    return response.json();
  }),
]).then(([categories, tools, toolTypes]) => {
  if (!categories.length || !tools.length) process.exit(2);
  if (!toolTypes.length) process.exit(4);
  if (tools.some((tool) => !tool.tool_type_id || !tool.toolType || tool.toolType.id !== tool.tool_type_id || Object.prototype.hasOwnProperty.call(tool, 'tool_type'))) {
    process.exit(5);
  }
  const byId = new Map(tools.map(tool => [tool.id, tool]));
  for (const tool of tools) {
    if (typeof tool.accessory_only !== 'boolean' || !Array.isArray(tool.related_tool_ids) || !Array.isArray(tool.related_tools) || !Array.isArray(tool.images)) {
      throw new Error(`Missing accessory fields on tool ${tool.id}`);
    }
    if (tool.images.length > 5) throw new Error(`Too many images on tool ${tool.id}`);
    const covers = tool.images.filter((image) => image.is_cover);
    if (tool.images.length && (covers.length !== 1 || covers[0].storage_key !== tool.image)) {
      throw new Error(`Invalid image cover on tool ${tool.id}`);
    }
    if (tool.images.some((image, index) => index && image.sort_order < tool.images[index - 1].sort_order)) {
      throw new Error(`Invalid image order on tool ${tool.id}`);
    }
    const ids = tool.related_tool_ids;
    if (new Set(ids).size !== ids.length || ids.includes(tool.id) || JSON.stringify(ids) !== JSON.stringify(tool.related_tools.map(item => item.id))) {
      throw new Error(`Invalid related tool list on ${tool.id}`);
    }
    for (const related of tool.related_tools) {
      const target = byId.get(related.id);
      if (!target || target.accessory_only === tool.accessory_only || !target.related_tool_ids.includes(tool.id) || 'related_tools' in related) {
        throw new Error(`Invalid symmetric relationship ${tool.id} - ${related.id}`);
      }
    }
  }
  const tool = tools.find((item) => categories.some((category) => category.id === item.categoryId));
  if (!tool) process.exit(3);
  const category = categories.find((item) => item.id === tool.categoryId);
  console.log([category.id, category.name, tool.id, tool.name].join('\t'));
}).catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
)

docker compose exec -T api node - <<'NODE'
const { Client } = require('pg');

const client = new Client({
  host: process.env.POSTGRES_HOST,
  port: Number(process.env.POSTGRES_PORT || 5432),
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  database: process.env.POSTGRES_DB,
});

async function verifyToolTypeSchema() {
  await client.connect();
  const { rows } = await client.query(`
    SELECT column_name, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tools'
      AND column_name IN ('tool_type', 'tool_type_id')
  `);
  const { rows: accessoryColumns } = await client.query(`
    SELECT column_name, is_nullable FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tools' AND column_name = 'accessory_only'
  `);
  const { rows: accessoryMigration } = await client.query(
    `SELECT name FROM "SequelizeMeta" WHERE name = '007-tool-accessories'`
  );
  const { rows: imageMigration } = await client.query(
    `SELECT name FROM "SequelizeMeta" WHERE name = '008-tool-images'`
  );
  const { rows: invalidGalleries } = await client.query(`
    SELECT images.tool_id
    FROM tool_images images
    GROUP BY images.tool_id
    HAVING COUNT(*) > 5 OR COUNT(*) FILTER (WHERE images.is_cover) <> 1
  `);
  const { rows: invalidCovers } = await client.query(`
    SELECT tools.id
    FROM tools
    LEFT JOIN tool_images cover
      ON cover.tool_id = tools.id AND cover.is_cover = TRUE
    WHERE tools.image IS DISTINCT FROM cover.storage_key
  `);
  const { rows: invalidLinks } = await client.query(`
    SELECT links.tool_id FROM tool_accessories links
    JOIN tools a ON a.id = links.tool_id JOIN tools b ON b.id = links.accessory_tool_id
    WHERE links.tool_id >= links.accessory_tool_id OR a.accessory_only = b.accessory_only
  `);
  await client.end();
  if (accessoryColumns.length !== 1 || accessoryColumns[0].is_nullable !== 'NO' || accessoryMigration.length !== 1 || invalidLinks.length) {
    throw new Error('Accessory schema or relationships are invalid');
  }
  if (imageMigration.length !== 1 || invalidGalleries.length || invalidCovers.length) {
    throw new Error('Image schema or galleries are invalid');
  }

  const typeIdColumn = rows.find(({ column_name }) => column_name === 'tool_type_id');
  const legacyColumn = rows.find(({ column_name }) => column_name === 'tool_type');
  if (!typeIdColumn || typeIdColumn.is_nullable !== 'NO' || legacyColumn) {
    console.error('Tool type schema is not finalized', rows);
    process.exit(1);
  }
}

verifyToolTypeSchema().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE

check_url "category API" "$API_URL/category/$CATEGORY_ID"
check_url "tool list API" "$API_URL/tools?categoryId=$CATEGORY_ID"
check_url "tool types API" "$API_URL/tool-types"
check_url "tool card API" "$API_URL/tools/$TOOL_ID"
check_url "category page" "$SITE_URL/$CATEGORY_NAME/"
check_url "tool card page" "$SITE_URL/$CATEGORY_NAME/$TOOL_NAME/"

if [[ -n ${SMOKE_ADMIN_NAME:-} && -n ${SMOKE_ADMIN_PASSWORD:-} ]]; then
  LOGIN_PAYLOAD=$(docker compose exec -T api node -e \
    'console.log(JSON.stringify({name: process.argv[1], password: process.argv[2]}))' \
    "$SMOKE_ADMIN_NAME" "$SMOKE_ADMIN_PASSWORD")
  curl --fail --silent --show-error --max-time 20 \
    --cookie-jar "$TMP_DIR/admin.cookies" \
    -H 'Content-Type: application/json' \
    --data "$LOGIN_PAYLOAD" \
    "$API_URL/auth/login" > /dev/null
  curl --fail --silent --show-error --max-time 20 \
    --cookie "$TMP_DIR/admin.cookies" \
    "$API_URL/auth/profile" > /dev/null
  curl --fail --silent --show-error --max-time 20 \
    --cookie "$TMP_DIR/admin.cookies" \
    --request POST \
    "$API_URL/auth/logout" > /dev/null
  echo "OK: admin login, profile and logout"
else
  echo "SKIP: admin authentication (set SMOKE_ADMIN_NAME and SMOKE_ADMIN_PASSWORD to enable)"
fi

echo "Smoke tests passed."
