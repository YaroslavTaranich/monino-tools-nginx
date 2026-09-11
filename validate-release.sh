#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
# shellcheck source=release-lib.sh
source ./release-lib.sh

validate_release_source "${1:-release.env}"

if [[ ${GITHUB_REF_TYPE:-} == tag ]]; then
  [[ ${GITHUB_REF_NAME:-} == "v${INFRA_VERSION}" ]] ||
    release_error "tag ${GITHUB_REF_NAME:-} does not match v${INFRA_VERSION}"
fi
