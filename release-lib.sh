#!/bin/bash

release_error() {
  echo "Release error: $*" >&2
  return 1
}

load_release_manifest() {
  local manifest=${1:-release.env}
  local line key value
  [[ -f "$manifest" ]] || release_error "manifest not found: $manifest"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || release_error "invalid line in $manifest: $line"
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      RELEASE_VERSION|INFRA_VERSION|API_VERSION|API_COMMIT|ADMIN_VERSION|ADMIN_COMMIT|USER_VERSION|USER_COMMIT)
        export "$key=$value"
        ;;
      *) release_error "unknown key in $manifest: $key" ;;
    esac
  done < "$manifest"

  : "${RELEASE_VERSION:?Missing RELEASE_VERSION}"
  : "${INFRA_VERSION:?Missing INFRA_VERSION}"
  : "${API_VERSION:?Missing API_VERSION}"
  : "${API_COMMIT:?Missing API_COMMIT}"
  : "${ADMIN_VERSION:?Missing ADMIN_VERSION}"
  : "${ADMIN_COMMIT:?Missing ADMIN_COMMIT}"
  : "${USER_VERSION:?Missing USER_VERSION}"
  : "${USER_COMMIT:?Missing USER_COMMIT}"

  [[ "$RELEASE_VERSION" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]] ||
    release_error "invalid CalVer: $RELEASE_VERSION"
  for value in "$INFRA_VERSION" "$API_VERSION" "$ADMIN_VERSION" "$USER_VERSION"; do
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] ||
      release_error "invalid SemVer: $value"
  done
  for value in "$API_COMMIT" "$ADMIN_COMMIT" "$USER_COMMIT"; do
    [[ "$value" =~ ^[0-9a-f]{40}$ ]] || release_error "invalid commit: $value"
  done
}

package_version() {
  awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' "$1/package.json"
}

validate_component() {
  local name=$1 directory=$2 expected_version=$3 expected_commit=$4
  local actual_version actual_commit
  actual_version=$(package_version "$directory")
  actual_commit=$(git -C "$directory" rev-parse HEAD)
  [[ "$actual_version" == "$expected_version" ]] ||
    release_error "$name package version is $actual_version, expected $expected_version"
  [[ "$actual_commit" == "$expected_commit" ]] ||
    release_error "$name commit is $actual_commit, expected $expected_commit"
}

validate_release_source() {
  local manifest=${1:-release.env}
  load_release_manifest "$manifest"
  [[ "$(tr -d '[:space:]' < VERSION)" == "$INFRA_VERSION" ]] ||
    release_error "infrastructure VERSION does not match $INFRA_VERSION"
  validate_component api api "$API_VERSION" "$API_COMMIT"
  validate_component admin admin "$ADMIN_VERSION" "$ADMIN_COMMIT"
  validate_component user user "$USER_VERSION" "$USER_COMMIT"
  echo "Release ${RELEASE_VERSION} verified."
}
