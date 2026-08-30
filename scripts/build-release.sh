#!/bin/bash

set -euo pipefail
umask 022

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=manifest-lib.sh
. "$ROOT_DIR/scripts/manifest-lib.sh"
load_manifest "$ROOT_DIR/manifest.env"

PACKAGE_VERSION="${PACKAGE_VERSION:-1.0.0}"
if ! [[ "$PACKAGE_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'PACKAGE_VERSION must be strict numeric SemVer without leading zeros (for example 1.0.0).\n' >&2
  exit 1
fi
PACKAGE_NAME="Mac-Clash-Intel-OneClick-v$PACKAGE_VERSION"
STAGE_DIR="$ROOT_DIR/dist/$PACKAGE_NAME"
ZIP_PATH="$ROOT_DIR/dist/$PACKAGE_NAME.zip"

case "$STAGE_DIR" in
  "$ROOT_DIR/dist/Mac-Clash-Intel-OneClick-v"*) ;;
  *) printf 'Unsafe staging path: %s\n' "$STAGE_DIR" >&2; exit 1 ;;
esac

mkdir -p "$ROOT_DIR/dist"
rm -rf "$STAGE_DIR"
rm -f "$ZIP_PATH" "$ROOT_DIR/dist/SHA256SUMS.txt"
mkdir -p "$STAGE_DIR"

cp "$ROOT_DIR/payload/双击安装-Clash-Verge.command" "$STAGE_DIR/"
cp "$ROOT_DIR/payload/双击诊断-Clash-Verge.command" "$STAGE_DIR/"
cp "$ROOT_DIR/payload/先读我.txt" "$STAGE_DIR/"
cp "$ROOT_DIR/manifest.env" "$STAGE_DIR/"
chmod 755 "$STAGE_DIR/双击安装-Clash-Verge.command"
chmod 755 "$STAGE_DIR/双击诊断-Clash-Verge.command"
chmod 644 "$STAGE_DIR/先读我.txt" "$STAGE_DIR/manifest.env"

if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR" "$ZIP_PATH"
else
  (cd "$ROOT_DIR/dist" && zip -q -r -X "$PACKAGE_NAME.zip" "$PACKAGE_NAME")
fi

(cd "$ROOT_DIR/dist" && shasum -a 256 "$PACKAGE_NAME.zip" > SHA256SUMS.txt)
(cd "$ROOT_DIR/dist" && shasum -a 256 -c SHA256SUMS.txt >/dev/null)

printf 'Built %s\n' "$ZIP_PATH"
printf 'Upstream %s / %s / %s\n' "$UPSTREAM_TAG" "$UPSTREAM_ASSET" "$UPSTREAM_SHA256"
