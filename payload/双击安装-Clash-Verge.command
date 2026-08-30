#!/bin/bash

# One-click bootstrapper for Clash Verge Rev on an Intel Mac.
# Compatible with the Bash 3.2 shipped by macOS Monterey.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
MANIFEST_PATH="$SCRIPT_DIR/manifest.env"
TMP_ROOT=""
MOUNT_DIR=""
MOUNTED=0
STAGED_APP=""
ROLLBACK_APP=""
TARGET_APP="/Applications/Clash Verge.app"
NEW_APP_INSTALLED=0
ROOT_STAGE_DIR=""
BACKUP_TX_DIR=""
SAVED_BACKUP_APP=""
DOWNLOAD_PARTIAL=""

say() {
  printf '\n[%s] %s\n' "$1" "$2"
}

warn() {
  printf '\n[提醒] %s\n' "$1" >&2
}

die() {
  printf '\n[停止] %s\n' "$1" >&2
  printf '\n没有修改 Clash 配置、系统代理或 DNS。\n' >&2
  exit 1
}

pause_if_finder() {
  if [ -t 0 ]; then
    printf '\n按回车键关闭此窗口...'
    read -r _unused || true
  fi
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM

  if [ "$MOUNTED" -eq 1 ] && [ -n "$MOUNT_DIR" ]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  fi

  if [ "$status" -ne 0 ]; then
    if [ "$NEW_APP_INSTALLED" -eq 1 ] && [ -e "$TARGET_APP" ] && [ -d "$ROOT_STAGE_DIR" ]; then
      /usr/bin/sudo /bin/mv "$TARGET_APP" "$ROOT_STAGE_DIR/未完成安装.app" >/dev/null 2>&1 || true
    fi

    if [ -n "$ROLLBACK_APP" ] && [ -d "$ROLLBACK_APP" ] && [ ! -e "$TARGET_APP" ]; then
      warn "安装没有完成，正在恢复旧版本。"
      /usr/bin/sudo /bin/mv "$ROLLBACK_APP" "$TARGET_APP" >/dev/null 2>&1 || true
    fi

    if [ -n "$BACKUP_TX_DIR" ] && [ -d "$BACKUP_TX_DIR" ] && [ ! -e "$ROLLBACK_APP" ]; then
      /usr/bin/sudo /bin/rmdir "$BACKUP_TX_DIR" >/dev/null 2>&1 || true
    fi

    if [ -n "$ROOT_STAGE_DIR" ] && [ -d "$ROOT_STAGE_DIR" ]; then
      warn "未完成的暂存目录保留在：$ROOT_STAGE_DIR"
    fi
  fi

  if [ -n "$DOWNLOAD_PARTIAL" ] && [ -f "$DOWNLOAD_PARTIAL" ]; then
    /bin/rm -f "$DOWNLOAD_PARTIAL"
  fi

  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    case "$TMP_ROOT" in
      "${TMPDIR:-/tmp}"/mac-clash-intel.*) /bin/rm -rf "$TMP_ROOT" ;;
      *) warn "临时目录路径异常，未自动清理：$TMP_ROOT" ;;
    esac
  fi

  if [ "$status" -ne 0 ]; then
    pause_if_finder
  fi

  return "$status"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

usage() {
  cat <<'EOF'
用法：
  双击本文件                         下载、验证并安装
  ./双击安装-Clash-Verge.command --print-plan
  ./双击安装-Clash-Verge.command --check-environment
  ./双击安装-Clash-Verge.command --verify-file /path/to/file.dmg
  ./双击安装-Clash-Verge.command --download-only [目录]

安装器不会读取或保存订阅链接，也不会自动开启系统代理、TUN 或修改 DNS。
EOF
}

[ -f "$MANIFEST_PATH" ] || die "缺少 manifest.env，请重新下载完整 ZIP。"

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
            *"|$manifest_key|"*) die "manifest 含有重复字段：$manifest_key" ;;
          esac
          seen_manifest_keys="$seen_manifest_keys$manifest_key|"
          printf -v "$manifest_key" '%s' "$manifest_value"
          ;;
        *) die "manifest 含有未知字段：$manifest_key" ;;
      esac
      ;;
    *) die "manifest 含有无效行。" ;;
  esac
done < "$MANIFEST_PATH"

: "${MANIFEST_SCHEMA:?manifest 缺少 MANIFEST_SCHEMA}"
: "${UPSTREAM_REPOSITORY:?manifest 缺少 UPSTREAM_REPOSITORY}"
: "${UPSTREAM_TAG:?manifest 缺少 UPSTREAM_TAG}"
: "${UPSTREAM_VERSION:?manifest 缺少 UPSTREAM_VERSION}"
: "${UPSTREAM_ASSET:?manifest 缺少 UPSTREAM_ASSET}"
: "${UPSTREAM_SIZE:?manifest 缺少 UPSTREAM_SIZE}"
: "${UPSTREAM_SHA256:?manifest 缺少 UPSTREAM_SHA256}"
: "${UPSTREAM_URL:?manifest 缺少 UPSTREAM_URL}"
: "${TARGET_ARCH:?manifest 缺少 TARGET_ARCH}"
: "${MIN_MACOS_MAJOR:?manifest 缺少 MIN_MACOS_MAJOR}"
: "${EXPECTED_BUNDLE_ID:?manifest 缺少 EXPECTED_BUNDLE_ID}"

[ "$MANIFEST_SCHEMA" = "1" ] || die "不支持的 manifest schema。"
[ "$UPSTREAM_REPOSITORY" = "clash-verge-rev/clash-verge-rev" ] || die "上游仓库白名单不匹配。"
[ "$TARGET_ARCH" = "x86_64" ] || die "目标架构白名单不匹配。"
[ "$MIN_MACOS_MAJOR" = "12" ] || die "最低 macOS 版本白名单不匹配。"
[ "$EXPECTED_BUNDLE_ID" = "io.github.clash-verge-rev.clash-verge-rev" ] || die "Bundle ID 白名单不匹配。"
[ -n "$UPSTREAM_VERSION" ] || die "manifest 缺少版本号。"
if ! [[ "$UPSTREAM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "manifest 中的版本号格式无效。"
fi
[ "$UPSTREAM_TAG" = "v$UPSTREAM_VERSION" ] || die "tag 与版本号不一致。"
[ "$UPSTREAM_ASSET" = "Clash.Verge_${UPSTREAM_VERSION}_x64.dmg" ] || die "资产名与版本号不一致。"
case "$UPSTREAM_SIZE" in
  ''|*[!0-9]*) die "manifest 中的文件大小无效。" ;;
esac
[ "$UPSTREAM_SIZE" -ge 1000000 ] && [ "$UPSTREAM_SIZE" -le 500000000 ] || die "manifest 中的文件大小超出合理范围。"

case "$UPSTREAM_URL" in
  "https://github.com/$UPSTREAM_REPOSITORY/releases/download/$UPSTREAM_TAG/$UPSTREAM_ASSET") ;;
  *) die "manifest 的下载地址不是固定的官方 GitHub Release 地址。" ;;
esac

if ! [[ "$UPSTREAM_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  die "manifest 中的 SHA-256 格式无效。"
fi

print_plan() {
  cat <<EOF
上游仓库：$UPSTREAM_REPOSITORY
稳定版本：$UPSTREAM_TAG
目标平台：macOS $MIN_MACOS_MAJOR+ / $TARGET_ARCH
官方文件：$UPSTREAM_ASSET
文件大小：$UPSTREAM_SIZE bytes
SHA-256 ：$UPSTREAM_SHA256
下载地址：$UPSTREAM_URL
安装位置：$TARGET_APP
EOF
}

file_size() {
  if /usr/bin/stat -f %z "$1" >/dev/null 2>&1; then
    /usr/bin/stat -f %z "$1"
  else
    /usr/bin/stat -c %s "$1"
  fi
}

sha256_file() {
  if command -v /usr/bin/shasum >/dev/null 2>&1; then
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print tolower($1)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | /usr/bin/awk '{print tolower($1)}'
  else
    die "系统缺少 SHA-256 校验工具。"
  fi
}

verify_download() {
  local file_path actual_size actual_sha
  file_path="$1"
  [ -f "$file_path" ] || die "找不到待校验文件：$file_path"

  actual_size="$(file_size "$file_path")"
  [ "$actual_size" = "$UPSTREAM_SIZE" ] || die "文件大小不匹配：期望 ${UPSTREAM_SIZE}，实际 ${actual_size}。"

  say "校验" "正在计算 SHA-256..."
  actual_sha="$(sha256_file "$file_path")"
  [ "$actual_sha" = "$UPSTREAM_SHA256" ] || die "SHA-256 不匹配。文件已损坏或不是审核过的官方版本。"
  say "通过" "大小和 SHA-256 均与官方 Release 元数据一致。"
}

download_dmg() {
  local destination destination_dir destination_name partial
  destination="$1"

  if [ -e "$destination" ]; then
    [ -f "$destination" ] && [ ! -L "$destination" ] || die "目标路径已存在且不是普通文件：$destination"
    say "复用" "发现已有文件，先验证后使用。"
    verify_download "$destination"
    return 0
  fi

  destination_dir="$(/usr/bin/dirname "$destination")"
  destination_name="$(/usr/bin/basename "$destination")"
  partial="$(/usr/bin/mktemp "$destination_dir/.${destination_name}.part.XXXXXX")" || die "无法创建安全的临时下载文件。"
  DOWNLOAD_PARTIAL="$partial"

  say "下载" "正在从官方 GitHub Release 获取 $UPSTREAM_ASSET"
  if ! /usr/bin/curl -q \
    --fail \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 600 \
    --max-filesize 100000000 \
    --progress-bar \
    --output "$partial" \
    "$UPSTREAM_URL"; then
    /bin/rm -f "$partial"
    DOWNLOAD_PARTIAL=""
    return 1
  fi

  verify_download "$partial"
  [ ! -e "$destination" ] || die "下载过程中目标路径被占用，已停止：$destination"
  /bin/mv "$partial" "$destination" || die "无法把已验证文件移动到目标位置。"
  DOWNLOAD_PARTIAL=""
}

download_failed() {
  local release_page
  release_page="https://github.com/$UPSTREAM_REPOSITORY/releases/tag/$UPSTREAM_TAG"
  /usr/bin/open "$release_page" >/dev/null 2>&1 || true
  die "Terminal 无法下载 GitHub Release 资产。已尝试在浏览器打开官方发布页；请下载 $UPSTREAM_ASSET 到下载目录或本 ZIP 目录，再重新双击安装脚本。"
}

validate_root_temp_dir() {
  local root_temp_dir expected_prefix root_owner
  root_temp_dir="$1"
  expected_prefix="$2"
  case "$root_temp_dir" in
    "/Applications/$expected_prefix"*) ;;
    *) die "root 暂存路径不符合预期：$root_temp_dir" ;;
  esac
  [ -d "$root_temp_dir" ] && [ ! -L "$root_temp_dir" ] || die "root 暂存目录无效。"
  root_owner="$(/usr/bin/sudo /usr/bin/stat -f %u "$root_temp_dir" 2>/dev/null || true)"
  [ "$root_owner" = "0" ] || die "root 暂存目录所有者异常。"
}

mode="install"
verify_path=""
download_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --print-plan)
      mode="print-plan"
      shift
      ;;
    --check-environment)
      mode="check-environment"
      shift
      ;;
    --verify-file)
      [ "$#" -ge 2 ] || die "--verify-file 后需要文件路径。"
      mode="verify-file"
      verify_path="$2"
      shift 2
      ;;
    --download-only)
      mode="download-only"
      if [ "$#" -ge 2 ] && [ "${2#-}" = "$2" ]; then
        download_dir="$2"
        shift 2
      else
        shift
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1"
      ;;
  esac
done

case "$mode" in
  print-plan)
    print_plan
    exit 0
    ;;
  verify-file)
    verify_download "$verify_path"
    exit 0
    ;;
esac

[ "$(/usr/bin/uname -s)" = "Darwin" ] || die "这个安装包只能在 macOS 上运行。"

actual_arch="$(/usr/bin/uname -m)"
[ "$actual_arch" = "$TARGET_ARCH" ] || die "这份安装包只适用于 Intel Mac（x86_64）；当前架构是 ${actual_arch}。"

macos_version="$(/usr/bin/sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
case "$macos_major" in
  ''|*[!0-9]*) die "无法识别 macOS 版本：$macos_version" ;;
esac
[ "$macos_major" -ge "$MIN_MACOS_MAJOR" ] || die "最新版要求 macOS ${MIN_MACOS_MAJOR} 或更高；当前是 ${macos_version}。请先升级到 Monterey 12。"

say "环境" "Intel ${actual_arch}，macOS ${macos_version}，符合要求。"

if [ "$mode" = "check-environment" ]; then
  exit 0
fi

available_kb="$(/bin/df -Pk "${TMPDIR:-/tmp}" | /usr/bin/awk 'NR==2 {print $4}')"
case "$available_kb" in
  ''|*[!0-9]*) warn "无法读取临时目录可用空间，将继续。" ;;
  *) [ "$available_kb" -ge 300000 ] || die "临时目录可用空间不足 300 MB。" ;;
esac

if [ "$mode" = "download-only" ]; then
  [ -n "$download_dir" ] || download_dir="$HOME/Downloads"
  /bin/mkdir -p "$download_dir"
  download_path="$download_dir/$UPSTREAM_ASSET"
  download_dmg "$download_path" || download_failed
  say "完成" "已下载并校验：$download_path"
  pause_if_finder
  exit 0
fi

TMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mac-clash-intel.XXXXXX")"
MOUNT_DIR="$TMP_ROOT/mount"
/bin/mkdir -p "$MOUNT_DIR"

DMG_PATH=""
for local_candidate in "$SCRIPT_DIR/$UPSTREAM_ASSET" "$HOME/Downloads/$UPSTREAM_ASSET"; do
  if [ -f "$local_candidate" ] && [ ! -L "$local_candidate" ]; then
    say "本地文件" "发现 ${local_candidate}，将先校验再使用。"
    verify_download "$local_candidate"
    DMG_PATH="$local_candidate"
    break
  fi
done

if [ -z "$DMG_PATH" ]; then
  DMG_PATH="$TMP_ROOT/$UPSTREAM_ASSET"
  download_dmg "$DMG_PATH" || download_failed
fi

say "镜像" "正在验证 DMG 文件系统..."
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null || die "DMG 文件系统验证失败。"

say "挂载" "正在只读挂载官方 DMG..."
MOUNTED=1
/usr/bin/hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null || die "无法挂载已验证的 DMG。"

SOURCE_APP="$MOUNT_DIR/Clash Verge.app"
[ -d "$SOURCE_APP" ] || die "DMG 中没有预期的 Clash Verge.app。"

app_count=0
for app_candidate in "$MOUNT_DIR"/*.app; do
  if [ -d "$app_candidate" ]; then
    app_count=$((app_count + 1))
  fi
done
[ "$app_count" = "1" ] || die "DMG 中的 App 数量异常，已停止。"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$bundle_id" = "$EXPECTED_BUNDLE_ID" ] || die "Bundle ID 不匹配：$bundle_id"

say "签名" "正在验证 App 代码签名与 Gatekeeper 状态..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$SOURCE_APP" || die "App 代码签名验证失败。"
if ! /usr/sbin/spctl --assess --type execute --verbose=3 "$SOURCE_APP"; then
  die "Gatekeeper 未接受这个 App。安装器不会绕过系统安全策略。"
fi

if /usr/bin/pgrep -f '/Clash Verge.app/' >/dev/null 2>&1; then
  say "更新" "正在请求已运行的 Clash Verge 正常退出..."
  /usr/bin/osascript -e 'tell application "Clash Verge" to quit' >/dev/null 2>&1 || true
  wait_count=0
  while /usr/bin/pgrep -f '/Clash Verge.app/' >/dev/null 2>&1 && [ "$wait_count" -lt 10 ]; do
    /bin/sleep 1
    wait_count=$((wait_count + 1))
  done
  /usr/bin/pgrep -f '/Clash Verge.app/' >/dev/null 2>&1 && die "Clash Verge 仍在运行。请退出应用后再试。"
fi

say "授权" "安装到 /Applications 需要管理员账户密码；输入时屏幕不会显示字符，输完按回车即可。"
/usr/bin/sudo -v || die "未获得管理员授权，安装已取消。"

ROOT_STAGE_DIR="$(/usr/bin/sudo /usr/bin/mktemp -d '/Applications/.clash-verge-install.XXXXXX')" || die "无法创建 root 私有暂存目录。"
validate_root_temp_dir "$ROOT_STAGE_DIR" ".clash-verge-install."
STAGED_APP="$ROOT_STAGE_DIR/Clash Verge.app"
/usr/bin/sudo /usr/bin/ditto --rsrc --extattr "$SOURCE_APP" "$STAGED_APP" || die "复制 App 到安全暂存目录失败。"
/usr/bin/sudo /usr/bin/codesign --verify --deep --strict "$STAGED_APP" || die "复制后的 App 签名验证失败。"

if [ -e "$TARGET_APP" ]; then
  backup_stamp="$(/bin/date +%Y%m%d-%H%M%S)"
  BACKUP_TX_DIR="$(/usr/bin/sudo /usr/bin/mktemp -d "/Applications/.clash-verge-backup-${backup_stamp}.XXXXXX")" || die "无法创建 root 私有回滚目录。"
  validate_root_temp_dir "$BACKUP_TX_DIR" ".clash-verge-backup-"
  ROLLBACK_APP="$BACKUP_TX_DIR/Clash Verge.app"
  say "备份" "旧版本将移到：$ROLLBACK_APP"
  /usr/bin/sudo /bin/mv "$TARGET_APP" "$ROLLBACK_APP" || die "无法备份旧版本。"
  SAVED_BACKUP_APP="$ROLLBACK_APP"
fi

/usr/bin/sudo /bin/mv "$STAGED_APP" "$TARGET_APP" || die "无法把新版本放入 /Applications。"
STAGED_APP=""
NEW_APP_INSTALLED=1

/usr/bin/codesign --verify --deep --strict "$TARGET_APP" || die "最终安装签名验证失败。"
if ! /usr/sbin/spctl --assess --type execute --verbose=3 "$TARGET_APP"; then
  die "复制后的 App 未通过 Gatekeeper 复核。"
fi
NEW_APP_INSTALLED=0
ROLLBACK_APP=""
/usr/bin/sudo /bin/rmdir "$ROOT_STAGE_DIR" >/dev/null 2>&1 || warn "空暂存目录未能移除：$ROOT_STAGE_DIR"
ROOT_STAGE_DIR=""

say "完成" "Clash Verge Rev $UPSTREAM_VERSION 已安装。"
cat <<'EOF'

这个 ZIP 只安装客户端，不包含节点，也不能把受限节点变成可用节点。

接下来在应用里完成 4 步：
  1. 打开「订阅」，粘贴并导入你的订阅链接（不要发到 GitHub）。
  2. 打开「代理」，选择并激活一个节点。
  3. 打开「设置 → 系统设置」，先开启「系统代理」测试浏览器；确认后再考虑 TUN。
  4. 分别测试 GitHub、YouTube、ChatGPT。

如果仍然只有 GitHub 能开，请运行同一 ZIP 里的「双击诊断-Clash-Verge.command」。
EOF

if [ -n "$SAVED_BACKUP_APP" ]; then
  printf '\n旧版本回滚副本：%s\n' "$SAVED_BACKUP_APP"
fi

if [ -t 0 ]; then
  printf '\n看完以上步骤后，按回车键启动 Clash Verge...'
  read -r _unused || true
fi

if ! /usr/bin/open "$TARGET_APP"; then
  warn "App 已安装，但自动启动失败。请到应用程序中手动打开 Clash Verge。"
  pause_if_finder
fi
