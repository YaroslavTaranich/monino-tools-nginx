#!/bin/bash

REMOTE_BACKUP_BASE_URL=${REMOTE_BACKUP_BASE_URL:-https://webdav.yandex.ru}
REMOTE_BACKUP_PARENT_URL="${REMOTE_BACKUP_BASE_URL%/}/Monino%20Tools"
REMOTE_BACKUP_URL="${REMOTE_BACKUP_PARENT_URL}/backups"
REMOTE_BACKUP_CURL_CONFIG=

remote_backup_require_credentials() {
  if [[ -z ${YANDEX_WEBDAV_USERNAME:-} || -z ${YANDEX_WEBDAV_PASSWORD:-} ]]; then
    echo "YANDEX_WEBDAV_USERNAME and YANDEX_WEBDAV_PASSWORD are required." >&2
    return 2
  fi
  if [[ "$YANDEX_WEBDAV_USERNAME" == *$'\n'* || "$YANDEX_WEBDAV_USERNAME" == *$'\r'* || "$YANDEX_WEBDAV_PASSWORD" == *$'\n'* || "$YANDEX_WEBDAV_PASSWORD" == *$'\r'* ]]; then
    echo "WebDAV credentials must not contain line breaks." >&2
    return 2
  fi

  local credentials escaped
  credentials="${YANDEX_WEBDAV_USERNAME}:${YANDEX_WEBDAV_PASSWORD}"
  escaped=${credentials//\\/\\\\}
  escaped=${escaped//\"/\\\"}
  umask 077
  REMOTE_BACKUP_CURL_CONFIG=$(mktemp)
  printf 'silent\nshow-error\nconnect-timeout = 30\nretry = 3\nretry-delay = 5\nuser = "%s"\n' \
    "$escaped" > "$REMOTE_BACKUP_CURL_CONFIG"
}

remote_backup_cleanup_credentials() {
  if [[ -n ${REMOTE_BACKUP_CURL_CONFIG:-} && -f $REMOTE_BACKUP_CURL_CONFIG ]]; then
    rm -f "$REMOTE_BACKUP_CURL_CONFIG"
  fi
}

remote_backup_expect_status() {
  local operation=$1
  local status=$2
  shift 2
  local allowed
  for allowed in "$@"; do
    [[ "$status" == "$allowed" ]] && return 0
  done
  echo "$operation failed with HTTP status $status." >&2
  return 1
}

remote_backup_mkcol() {
  local url=$1 status
  status=$(curl --config "$REMOTE_BACKUP_CURL_CONFIG" --request MKCOL \
    --output /dev/null --write-out '%{http_code}' "$url")
  remote_backup_expect_status "Creating $url" "$status" 201 405
}

remote_backup_ensure_collection() {
  remote_backup_mkcol "$REMOTE_BACKUP_PARENT_URL"
  remote_backup_mkcol "$REMOTE_BACKUP_URL"
}

remote_backup_put() {
  local source=$1 name=$2 status
  status=$(curl --config "$REMOTE_BACKUP_CURL_CONFIG" --upload-file "$source" \
    --output /dev/null --write-out '%{http_code}' "$REMOTE_BACKUP_URL/$name")
  remote_backup_expect_status "Uploading $name" "$status" 200 201 204
}

remote_backup_get() {
  local name=$1 destination=$2
  curl --config "$REMOTE_BACKUP_CURL_CONFIG" --fail \
    --output "$destination" "$REMOTE_BACKUP_URL/$name"
}

remote_backup_delete() {
  local name=$1 status
  [[ "$name" =~ ^monino-tools-backup-[0-9]{8}T[0-9]{6}Z\.tar\.gz(\.sha256)?$ ]] || {
    echo "Refusing to delete unexpected remote name: $name" >&2
    return 2
  }
  status=$(curl --config "$REMOTE_BACKUP_CURL_CONFIG" --request DELETE \
    --output /dev/null --write-out '%{http_code}' "$REMOTE_BACKUP_URL/$name")
  remote_backup_expect_status "Deleting $name" "$status" 200 204 404
}

remote_backup_list() {
  local destination=$1 status
  status=$(curl --config "$REMOTE_BACKUP_CURL_CONFIG" --request PROPFIND \
    --header 'Depth: 1' --output "$destination" --write-out '%{http_code}' \
    "$REMOTE_BACKUP_URL")
  remote_backup_expect_status "Listing remote backups" "$status" 207
}

remote_backup_sha256() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

remote_backup_validate_archive_name() {
  [[ "$1" =~ ^monino-tools-backup-[0-9]{8}T[0-9]{6}Z\.tar\.gz$ ]]
}

remote_backup_verify_download() {
  local archive=$1 checksum_file=$2 expected actual
  expected=$(awk 'NR == 1 {print $1}' "$checksum_file")
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "Invalid remote checksum file." >&2
    return 1
  }
  expected=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
  actual=$(remote_backup_sha256 "$archive")
  [[ "$actual" == "$expected" ]] || {
    echo "Remote backup checksum mismatch." >&2
    return 1
  }
}

remote_backup_safe_extract() {
  local archive=$1 destination=$2 entry listing
  listing=$(tar -tzf "$archive")
  while IFS= read -r entry; do
    if [[ "$entry" == /* || "$entry" == .. || "$entry" == ../* || "$entry" == */.. || "$entry" == */../* ]]; then
      echo "Unsafe path in remote backup archive: $entry" >&2
      return 1
    fi
  done <<< "$listing"
  mkdir -p "$destination"
  tar -C "$destination" -xzf "$archive"
}
