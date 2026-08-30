#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALLER="$ROOT_DIR/payload/双击安装-Clash-Verge.command"
DIAGNOSTIC="$ROOT_DIR/payload/双击诊断-Clash-Verge.command"
# shellcheck source=../scripts/manifest-lib.sh
. "$ROOT_DIR/scripts/manifest-lib.sh"
load_manifest "$ROOT_DIR/manifest.env"

/bin/bash -n "$INSTALLER"
/bin/bash -n "$DIAGNOSTIC"
/bin/bash -n "$ROOT_DIR/scripts/build-release.sh"
/bin/bash -n "$ROOT_DIR/scripts/check-upstream.sh"
/bin/bash -n "$ROOT_DIR/scripts/verify-upstream-macos.sh"
/bin/bash -n "$ROOT_DIR/scripts/manifest-lib.sh"

test_tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/clash-installer-test.XXXXXX")"
trap 'rm -rf "$test_tmp_root"' EXIT
installer_fixture="$test_tmp_root/package"
mkdir -p "$installer_fixture"
cp "$INSTALLER" "$installer_fixture/双击安装-Clash-Verge.command"
cp "$ROOT_DIR/manifest.env" "$installer_fixture/manifest.env"

plan="$(/bin/bash "$installer_fixture/双击安装-Clash-Verge.command" --print-plan)"
printf '%s\n' "$plan" | grep -F "稳定版本：$UPSTREAM_TAG" >/dev/null
printf '%s\n' "$plan" | grep -F "目标平台：macOS $MIN_MACOS_MAJOR+ / $TARGET_ARCH" >/dev/null
printf '%s\n' "$plan" | grep -F "$UPSTREAM_SHA256" >/dev/null

# Reject unbraced variable expansions immediately followed by a UTF-8 byte.
# Bash 3.2 with nounset can misparse that boundary under a UTF-8 locale.
unicode_adjacent="$(LC_ALL=C /usr/bin/perl -ne \
  'print "$ARGV:$.:$_" if /\$[A-Za-z_][A-Za-z0-9_]*(?=[\x80-\xFF])/' \
  "$INSTALLER")"
if [ -n "$unicode_adjacent" ]; then
  printf 'Unbraced variable expansion is adjacent to non-ASCII text:\n%s\n' \
    "$unicode_adjacent" >&2
  exit 1
fi

# Exercise the real macOS/Bash 3.2 environment preflight without downloading.
if [ "$(uname -s)" = "Darwin" ]; then
  preflight_output="$(LC_ALL=en_US.UTF-8 /bin/bash \
    "$installer_fixture/双击安装-Clash-Verge.command" --check-environment 2>&1)"
  printf '%s\n' "$preflight_output" | grep -F '[环境] Intel x86_64，macOS ' >/dev/null
  if printf '%s\n' "$preflight_output" | grep -F 'unbound variable' >/dev/null; then
    printf 'Installer failed during Unicode-adjacent variable expansion.\n' >&2
    exit 1
  fi
fi

bad_dmg="$test_tmp_root/wrong-size.dmg"
printf 'not a dmg\n' > "$bad_dmg"
if wrong_size_output="$(/bin/bash "$installer_fixture/双击安装-Clash-Verge.command" \
  --verify-file "$bad_dmg" 2>&1)"; then
  printf 'Installer accepted a DMG with the wrong size.\n' >&2
  exit 1
fi
printf '%s\n' "$wrong_size_output" | grep -F '文件大小不匹配：期望 ' >/dev/null
if printf '%s\n' "$wrong_size_output" | grep -F 'unbound variable' >/dev/null; then
  printf 'Wrong-size error path failed during Unicode-adjacent expansion.\n' >&2
  exit 1
fi

help_text="$(/bin/bash "$DIAGNOSTIC" --help)"
printf '%s\n' "$help_text" | grep -F '不会更改' >/dev/null

malicious_manifest="$test_tmp_root/malicious.env"
duplicate_manifest="$test_tmp_root/duplicate.env"
printf 'ROOT_DIR=/\n' > "$malicious_manifest"
if /bin/bash -c '. "$1"; load_manifest "$2"' _ "$ROOT_DIR/scripts/manifest-lib.sh" "$malicious_manifest" >/dev/null 2>&1; then
  printf 'Manifest parser accepted an unknown/dangerous field.\n' >&2
  exit 1
fi

cp "$ROOT_DIR/manifest.env" "$duplicate_manifest"
printf 'UPSTREAM_TAG=%s\n' "$UPSTREAM_TAG" >> "$duplicate_manifest"
if /bin/bash -c '. "$1"; load_manifest "$2"' _ "$ROOT_DIR/scripts/manifest-lib.sh" "$duplicate_manifest" >/dev/null 2>&1; then
  printf 'Manifest parser accepted a duplicate field.\n' >&2
  exit 1
fi

cp "$ROOT_DIR/manifest.env" "$installer_fixture/manifest.env"
printf 'UPSTREAM_TAG=%s\n' "$UPSTREAM_TAG" >> "$installer_fixture/manifest.env"
if /bin/bash "$installer_fixture/双击安装-Clash-Verge.command" --print-plan >/dev/null 2>&1; then
  printf 'Installer accepted a duplicate manifest field.\n' >&2
  exit 1
fi

for invalid_version in 01.0.0 1.02.3 1.0.03 1.0 1.0.0-rc1 '1.0.0/../../escape'; do
  if PACKAGE_VERSION="$invalid_version" /bin/bash "$ROOT_DIR/scripts/build-release.sh" >/dev/null 2>&1; then
    printf 'Build accepted invalid PACKAGE_VERSION: %s\n' "$invalid_version" >&2
    exit 1
  fi
done

if grep -RInE '(subscription-url|token[[:space:]]*=|api[_-]?key[[:space:]]*=|BEGIN (RSA|OPENSSH) PRIVATE KEY)' \
  "$ROOT_DIR/payload" "$ROOT_DIR/manifest.env"; then
  printf 'Potential secret found in distributable files.\n' >&2
  exit 1
fi

printf 'All local tests passed.\n'
