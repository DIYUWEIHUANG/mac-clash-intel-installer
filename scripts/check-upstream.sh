#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=manifest-lib.sh
. "$ROOT_DIR/scripts/manifest-lib.sh"
load_manifest "$ROOT_DIR/manifest.env"

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required for the maintainer check.\n' >&2
  exit 2
fi

API_ROOT="https://api.github.com/repos/$UPSTREAM_REPOSITORY/releases"
PINNED_API_URL="$API_ROOT/tags/$UPSTREAM_TAG"
LATEST_API_URL="$API_ROOT/latest"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clash-release-check.XXXXXX")"
PINNED_JSON="$TMP_ROOT/pinned.json"
LATEST_JSON="$TMP_ROOT/latest.json"
trap 'rm -rf "$TMP_ROOT"' EXIT

api_headers=(
  --header 'Accept: application/vnd.github+json'
  --header 'X-GitHub-Api-Version: 2022-11-28'
)
api_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -n "$api_token" ]; then
  api_headers+=(--header "Authorization: Bearer $api_token")
fi

fetch_json() {
  destination="$1"
  url="$2"
  curl -q \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --retry 3 \
    --retry-all-errors \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 90 \
    "${api_headers[@]}" \
    --output "$destination" \
    "$url"
}

# Validate the pinned release independently. This must happen even when a newer
# upstream release exists, otherwise replacement of the audited asset is missed.
fetch_json "$PINNED_JSON" "$PINNED_API_URL"
jq -e 'type == "object" and (.tag_name | type == "string") and (.assets | type == "array")' \
  "$PINNED_JSON" >/dev/null || {
    printf 'Pinned release API returned an unexpected document.\n' >&2
    exit 1
  }

pinned_tag="$(jq -r '.tag_name' "$PINNED_JSON")"
pinned_draft="$(jq -r '.draft' "$PINNED_JSON")"
pinned_prerelease="$(jq -r '.prerelease' "$PINNED_JSON")"
[ "$pinned_tag" = "$UPSTREAM_TAG" ] || {
  printf 'Pinned tag mismatch: expected %s, API returned %s.\n' "$UPSTREAM_TAG" "$pinned_tag" >&2
  exit 1
}
[ "$pinned_draft" = "false" ] && [ "$pinned_prerelease" = "false" ] || {
  printf 'Pinned release is a draft or prerelease.\n' >&2
  exit 1
}

asset_count="$(jq --arg name "$UPSTREAM_ASSET" '[.assets[] | select(.name == $name)] | length' "$PINNED_JSON")"
[ "$asset_count" = "1" ] || {
  printf 'Expected exactly one asset named %s; found %s.\n' "$UPSTREAM_ASSET" "$asset_count" >&2
  exit 1
}

api_size="$(jq -r --arg name "$UPSTREAM_ASSET" '.assets[] | select(.name == $name) | .size' "$PINNED_JSON")"
api_digest="$(jq -r --arg name "$UPSTREAM_ASSET" '.assets[] | select(.name == $name) | .digest' "$PINNED_JSON")"
api_url="$(jq -r --arg name "$UPSTREAM_ASSET" '.assets[] | select(.name == $name) | .browser_download_url' "$PINNED_JSON")"

[ "$api_size" = "$UPSTREAM_SIZE" ] || {
  printf 'Pinned asset size mismatch: expected %s, API returned %s.\n' "$UPSTREAM_SIZE" "$api_size" >&2
  exit 1
}
[ "$api_digest" = "sha256:$UPSTREAM_SHA256" ] || {
  printf 'Pinned asset digest mismatch: expected sha256:%s, API returned %s.\n' "$UPSTREAM_SHA256" "$api_digest" >&2
  exit 1
}
[ "$api_url" = "$UPSTREAM_URL" ] || {
  printf 'Pinned asset URL mismatch: expected %s, API returned %s.\n' "$UPSTREAM_URL" "$api_url" >&2
  exit 1
}

printf 'Manifest matches pinned official release %s.\n' "$UPSTREAM_TAG"

# Freshness is a separate decision from pinned-asset integrity.
fetch_json "$LATEST_JSON" "$LATEST_API_URL"
jq -e 'type == "object" and (.tag_name | type == "string")' "$LATEST_JSON" >/dev/null || {
  printf 'Latest release API returned an unexpected document.\n' >&2
  exit 1
}

latest_tag="$(jq -r '.tag_name' "$LATEST_JSON")"
latest_draft="$(jq -r '.draft' "$LATEST_JSON")"
latest_prerelease="$(jq -r '.prerelease' "$LATEST_JSON")"
if ! [[ "$latest_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Latest stable tag is not strict SemVer: %s\n' "$latest_tag" >&2
  exit 1
fi
[ "$latest_draft" = "false" ] && [ "$latest_prerelease" = "false" ] || {
  printf 'Latest endpoint returned a draft or prerelease.\n' >&2
  exit 1
}

if [ "$latest_tag" != "$UPSTREAM_TAG" ]; then
  printf 'UPSTREAM_UPDATE_AVAILABLE current=%s latest=%s\n' "$UPSTREAM_TAG" "$latest_tag"
  exit 10
fi

printf 'Manifest matches official latest release %s.\n' "$UPSTREAM_TAG"
