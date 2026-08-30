#!/bin/bash

# Safe parser for manifest.env. The manifest is data, never shell code.

manifest_error() {
  printf 'Invalid manifest: %s\n' "$1" >&2
  return 1
}

load_manifest() {
  local manifest_path manifest_line manifest_key manifest_value seen_manifest_keys
  manifest_path="$1"
  [ -f "$manifest_path" ] || { manifest_error "file not found: $manifest_path"; return 1; }

  MANIFEST_SCHEMA=""
  UPSTREAM_REPOSITORY=""
  UPSTREAM_TAG=""
  UPSTREAM_VERSION=""
  UPSTREAM_ASSET=""
  UPSTREAM_SIZE=""
  UPSTREAM_SHA256=""
  UPSTREAM_URL=""
  TARGET_ARCH=""
  MIN_MACOS_MAJOR=""
  EXPECTED_BUNDLE_ID=""
  seen_manifest_keys="|"

  while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    case "$manifest_line" in
      ''|'#'*) continue ;;
      *=*)
        manifest_key="${manifest_line%%=*}"
        manifest_value="${manifest_line#*=}"
        case "$manifest_key" in
          MANIFEST_SCHEMA|UPSTREAM_REPOSITORY|UPSTREAM_TAG|UPSTREAM_VERSION|UPSTREAM_ASSET|UPSTREAM_SIZE|UPSTREAM_SHA256|UPSTREAM_URL|TARGET_ARCH|MIN_MACOS_MAJOR|EXPECTED_BUNDLE_ID)
            case "$seen_manifest_keys" in
              *"|$manifest_key|"*) manifest_error "duplicate field: $manifest_key"; return 1 ;;
            esac
            seen_manifest_keys="$seen_manifest_keys$manifest_key|"
            printf -v "$manifest_key" '%s' "$manifest_value"
            ;;
          *) manifest_error "unknown field: $manifest_key"; return 1 ;;
        esac
        ;;
      *) manifest_error "line is not KEY=VALUE"; return 1 ;;
    esac
  done < "$manifest_path"

  [ "$MANIFEST_SCHEMA" = "1" ] || { manifest_error "unsupported schema"; return 1; }
  [ "$UPSTREAM_REPOSITORY" = "clash-verge-rev/clash-verge-rev" ] || { manifest_error "repository allowlist mismatch"; return 1; }
  [ "$TARGET_ARCH" = "x86_64" ] || { manifest_error "architecture allowlist mismatch"; return 1; }
  [ "$MIN_MACOS_MAJOR" = "12" ] || { manifest_error "minimum macOS allowlist mismatch"; return 1; }
  [ "$EXPECTED_BUNDLE_ID" = "io.github.clash-verge-rev.clash-verge-rev" ] || { manifest_error "bundle ID allowlist mismatch"; return 1; }
  if ! [[ "$UPSTREAM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    manifest_error "version must be numeric SemVer"
    return 1
  fi
  [ "$UPSTREAM_TAG" = "v$UPSTREAM_VERSION" ] || { manifest_error "tag/version mismatch"; return 1; }
  [ "$UPSTREAM_ASSET" = "Clash.Verge_${UPSTREAM_VERSION}_x64.dmg" ] || { manifest_error "asset/version mismatch"; return 1; }
  [ "$UPSTREAM_URL" = "https://github.com/$UPSTREAM_REPOSITORY/releases/download/$UPSTREAM_TAG/$UPSTREAM_ASSET" ] || { manifest_error "official URL mismatch"; return 1; }

  case "$UPSTREAM_SIZE" in
    ''|*[!0-9]*) manifest_error "invalid size"; return 1 ;;
  esac
  if [ "$UPSTREAM_SIZE" -lt 1000000 ] || [ "$UPSTREAM_SIZE" -gt 500000000 ]; then
    manifest_error "size outside allowed range"
    return 1
  fi
  if ! [[ "$UPSTREAM_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    manifest_error "invalid SHA-256"
    return 1
  fi
}
