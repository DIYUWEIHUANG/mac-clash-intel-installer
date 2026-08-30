#!/bin/bash

# Maintainer/CI verification of the pinned upstream DMG on a real Intel macOS runner.
# It never installs the application or changes proxy/network settings.

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=manifest-lib.sh
. "$ROOT_DIR/scripts/manifest-lib.sh"
load_manifest "$ROOT_DIR/manifest.env"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verify-clash-upstream.XXXXXX")"
MOUNT_DIR="$TMP_ROOT/mount"
DMG_PATH="$TMP_ROOT/$UPSTREAM_ASSET"
MOUNTED=0

fail() {
  printf 'Verification failed: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ "$MOUNTED" -eq 1 ]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

test "$(uname -s)" = "Darwin"
test "$(uname -m)" = "$TARGET_ARCH"
mkdir -p "$MOUNT_DIR"

curl -q \
  --fail \
  --location \
  --proto '=https' \
  --proto-redir '=https' \
  --retry 3 \
  --retry-all-errors \
  --retry-delay 2 \
  --connect-timeout 15 \
  --max-time 900 \
  --output "$DMG_PATH" \
  "$UPSTREAM_URL"

actual_size="$(stat -f %z "$DMG_PATH")"
actual_sha="$(shasum -a 256 "$DMG_PATH" | awk '{print tolower($1)}')"
test "$actual_size" = "$UPSTREAM_SIZE"
test "$actual_sha" = "$UPSTREAM_SHA256"

hdiutil verify "$DMG_PATH"
MOUNTED=1
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null

SOURCE_APP="$MOUNT_DIR/Clash Verge.app"
test -d "$SOURCE_APP"

app_count=0
for app_candidate in "$MOUNT_DIR"/*.app; do
  if [ -d "$app_candidate" ]; then
    app_count=$((app_count + 1))
  fi
done
test "$app_count" -eq 1

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
test "$bundle_id" = "$EXPECTED_BUNDLE_ID"

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_APP/Contents/Info.plist")"
executable_path="$SOURCE_APP/Contents/MacOS/$executable_name"
test -x "$executable_path"

codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"
spctl --assess --type execute --verbose=3 "$SOURCE_APP"

signature_details="$(codesign -dv --verbose=4 "$SOURCE_APP" 2>&1)"
team_id="$(printf '%s\n' "$signature_details" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
authority_lines="$(printf '%s\n' "$signature_details" | sed -n 's/^Authority=//p')"
[ -n "$team_id" ] || team_id="<not reported>"
[ -n "$authority_lines" ] || authority_lines="<not reported>"

main_architectures="$(lipo -archs "$executable_path")"
case " $main_architectures " in
  *" $TARGET_ARCH "*) ;;
  *) fail "main executable lacks $TARGET_ARCH; got: $main_architectures" ;;
esac

deployment_targets() {
  binary_path="$1"
  otool -l "$binary_path" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" {
      wanted = "minos"
      next
    }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" {
      wanted = "version"
      next
    }
    wanted != "" && $1 == wanted {
      print $2
      wanted = ""
    }
  '
}

validate_deployment_target() {
  binary_path="$1"
  deployment_target="$2"
  target_major="${deployment_target%%.*}"
  case "$target_major" in
    ''|*[!0-9]*) fail "invalid deployment target '$deployment_target' in $binary_path" ;;
  esac
  [ "$target_major" -le "$MIN_MACOS_MAJOR" ] || {
    fail "$binary_path requires macOS $deployment_target, newer than allowed macOS $MIN_MACOS_MAJOR"
  }
}

info_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)"
arch_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersionByArchitecture:x86_64' "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -n "$info_minimum" ]; then
  validate_deployment_target "Info.plist:LSMinimumSystemVersion" "$info_minimum"
fi
if [ -n "$arch_minimum" ]; then
  validate_deployment_target "Info.plist:LSMinimumSystemVersionByArchitecture:x86_64" "$arch_minimum"
fi

mach_o_count=0
while IFS= read -r -d '' binary_path; do
  file_description="$(file -b "$binary_path")"
  case "$file_description" in
    *Mach-O*) ;;
    *) continue ;;
  esac

  mach_o_count=$((mach_o_count + 1))
  binary_architectures="$(lipo -archs "$binary_path" 2>/dev/null)" || {
    fail "cannot inspect architectures for $binary_path"
  }
  case " $binary_architectures " in
    *" $TARGET_ARCH "*) ;;
    *) fail "$binary_path lacks $TARGET_ARCH; got: $binary_architectures" ;;
  esac

  binary_targets="$(deployment_targets "$binary_path")"
  [ -n "$binary_targets" ] || fail "no macOS deployment target found in $binary_path"
  target_count=0
  while IFS= read -r deployment_target; do
    [ -n "$deployment_target" ] || continue
    target_count=$((target_count + 1))
    validate_deployment_target "$binary_path" "$deployment_target"
  done <<EOF
$binary_targets
EOF
  [ "$target_count" -gt 0 ] || fail "no usable deployment target found in $binary_path"

  relative_binary="${binary_path#$SOURCE_APP/}"
  compact_targets="$(printf '%s\n' "$binary_targets" | paste -sd ',' -)"
  printf '  Mach-O: %s | arch=%s | minos=%s\n' \
    "$relative_binary" "$binary_architectures" "$compact_targets"
done < <(find "$SOURCE_APP" -type f -print0)

[ "$mach_o_count" -gt 0 ] || fail "no Mach-O files found in the application bundle"

printf 'Verified upstream release on Intel macOS:\n'
printf '  tag=%s\n  asset=%s\n  size=%s\n  sha256=%s\n  bundle_id=%s\n  plist_minimum=%s\n  plist_x86_64_minimum=%s\n  main_architectures=%s\n  mach_o_count=%s\n  team_id=%s\n' \
  "$UPSTREAM_TAG" "$UPSTREAM_ASSET" "$actual_size" "$actual_sha" "$bundle_id" \
  "${info_minimum:-<not declared>}" "${arch_minimum:-<not declared>}" \
  "$main_architectures" "$mach_o_count" "$team_id"
while IFS= read -r authority; do
  printf '  authority=%s\n' "$authority"
done <<EOF
$authority_lines
EOF
