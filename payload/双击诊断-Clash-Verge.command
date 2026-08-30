#!/bin/bash

# Read-only Clash connectivity triage for macOS.
# It does not change proxy, DNS, routes, Clash settings, or subscription data.

set -u
umask 077

say() {
  printf '\n==== %s ====\n' "$1"
}

usage() {
  cat <<'EOF'
双击运行即可。该脚本只读检查：
- macOS / CPU
- Clash Verge 进程与本机监听端口
- 当前系统代理（不会更改）
- GitHub、YouTube、ChatGPT、OpenAI API 的未显式代理与本机代理 HTTP 状态

不会读取订阅 URL、节点名、配置正文或公网 IP，也不会修改 DNS/路由。
测试会主动访问上述站点；站点会看到你的出口 IP。
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$(/usr/bin/uname -s 2>/dev/null)" != "Darwin" ]; then
  printf '[停止] 此诊断脚本只能在 macOS 上运行。\n' >&2
  exit 1
fi

cat <<'EOF'

Clash Verge 只读网络诊断
-------------------------
请先在「代理」中选好节点，并确认当前是 Rule 还是 Global 模式。
本次最多约 90 秒，会访问 GitHub、YouTube、ChatGPT 和 OpenAI API；
这些站点会看到当前出口 IP，但报告不会记录公网 IP 或响应正文。
EOF
printf '\n本次要记录的模式：[1] Rule  [2] Global  [3] 不确定（默认 3）：'
read -r mode_choice || true
case "${mode_choice:-3}" in
  1) declared_mode="Rule" ;;
  2) declared_mode="Global" ;;
  *) declared_mode="不确定" ;;
esac

timestamp="$(/bin/date +%Y%m%d-%H%M%S)"
report_dir="$HOME/Desktop"
[ -d "$report_dir" ] || report_dir="$HOME"
report="$report_dir/Clash诊断-$timestamp.txt"

exec > >(/usr/bin/tee "$report") 2>&1

say "说明"
printf '时间：%s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')"
printf '用户确认的模式：%s\n' "$declared_mode"
printf '这是只读诊断；结果不含订阅链接、节点名、配置正文或公网 IP。\n'
printf '测试站点会看到出口 IP；分享报告前仍请自行浏览一遍。\n'

say "系统"
/usr/bin/sw_vers
printf '架构：%s\n' "$(/usr/bin/uname -m)"

say "Clash Verge 进程"
if /usr/bin/pgrep -f '/Clash Verge.app/' >/dev/null 2>&1; then
  printf '状态：正在运行\n'
else
  printf '状态：未发现正在运行的 App\n'
fi

say "本机常见代理端口"
found_port=""
for candidate in 7897 7890; do
  if /usr/bin/nc -z -w 1 127.0.0.1 "$candidate" >/dev/null 2>&1; then
    printf '127.0.0.1:%s 正在监听\n' "$candidate"
    [ -n "$found_port" ] || found_port="$candidate"
  else
    printf '127.0.0.1:%s 未监听\n' "$candidate"
  fi
done

say "系统代理（只显示状态与本机端口）"
proxy_dump="$(/usr/sbin/scutil --proxy 2>/dev/null || true)"
http_enabled="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/HTTPEnable/ {print $3; exit}')"
http_host="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/HTTPProxy/ {print $3; exit}')"
http_port="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/HTTPPort/ {print $3; exit}')"
https_enabled="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/HTTPSEnable/ {print $3; exit}')"
https_host="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/HTTPSProxy/ {print $3; exit}')"
https_port="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/HTTPSPort/ {print $3; exit}')"
pac_enabled="$(printf '%s\n' "$proxy_dump" | /usr/bin/awk '/ProxyAutoConfigEnable/ {print $3; exit}')"

printf 'HTTP 启用：%s\n' "${http_enabled:-0}"
case "$http_host" in
  127.*|localhost|::1) printf 'HTTP 本机目标：%s:%s\n' "$http_host" "${http_port:-未知}" ;;
  '') ;;
  *) printf 'HTTP 目标：非本机地址（已隐藏）\n' ;;
esac
printf 'HTTPS 启用：%s\n' "${https_enabled:-0}"
case "$https_host" in
  127.*|localhost|::1) printf 'HTTPS 本机目标：%s:%s\n' "$https_host" "${https_port:-未知}" ;;
  '') ;;
  *) printf 'HTTPS 目标：非本机地址（已隐藏）\n' ;;
esac
printf 'PAC 启用：%s（URL 不记录）\n' "${pac_enabled:-0}"

proxy_url=""
proxy_source=""
case "${https_port:-}" in
  ''|*[!0-9]*) valid_https_port=0 ;;
  *)
    if [ "$https_port" -ge 1 ] && [ "$https_port" -le 65535 ]; then
      valid_https_port=1
    else
      valid_https_port=0
    fi
    ;;
esac
if [ "$https_enabled" = "1" ] && [ "$valid_https_port" -eq 1 ]; then
  case "$https_host" in
    127.*|localhost)
      proxy_url="http://$https_host:$https_port"
      proxy_source="系统 HTTPS 代理（本机回环地址）"
      ;;
    ::1)
      proxy_url="http://[::1]:$https_port"
      proxy_source="系统 HTTPS 代理（本机回环地址）"
      ;;
  esac
fi
if [ -z "$proxy_url" ] && [ -n "$found_port" ]; then
  proxy_url="http://127.0.0.1:$found_port"
  proxy_source="常见本机端口（未验证监听进程归属）"
fi

say "DNS 解析（只显示成功/失败）"
for host in github.com www.youtube.com chatgpt.com api.openai.com; do
  if /usr/bin/dscacheutil -q host -a name "$host" 2>/dev/null | /usr/bin/grep -q '^ip_address:'; then
    printf '%-24s OK\n' "$host"
  else
    printf '%-24s FAIL\n' "$host"
  fi
done

probe() {
  label="$1"
  url="$2"
  proxy_arg="${3:-}"
  start="$(/bin/date +%s)"

  printf '正在测试 %-12s ... ' "$label"

  if [ -n "$proxy_arg" ]; then
    code="$(/usr/bin/curl -q --silent --show-error --output /dev/null --connect-timeout 4 --max-time 8 --proto '=https' --proxy "$proxy_arg" --write-out '%{http_code}' "$url" 2>/dev/null)"
    curl_status=$?
  else
    code="$(/usr/bin/curl -q --silent --show-error --output /dev/null --connect-timeout 4 --max-time 8 --proto '=https' --proxy '' --noproxy '*' --write-out '%{http_code}' "$url" 2>/dev/null)"
    curl_status=$?
  fi

  elapsed=$(( $(/bin/date +%s) - start ))
  [ -n "$code" ] || code="000"
  printf 'HTTP=%s curl=%s time=%ss\n' "$code" "$curl_status" "$elapsed"
}

say "未显式指定 HTTP 代理（仍可能被 TUN/VPN 接管）"
probe "GitHub" "https://github.com/robots.txt"
probe "YouTube" "https://www.youtube.com/generate_204"
probe "ChatGPT" "https://chatgpt.com/"
probe "OpenAI API" "https://api.openai.com/v1/models"

say "经检测到的本机 HTTP 代理（通常是 Clash，但未验证进程归属）"
if [ -n "$proxy_url" ]; then
  printf '来源：%s\n' "$proxy_source"
  printf '使用本机代理：%s\n' "$proxy_url"
  probe "GitHub" "https://github.com/robots.txt" "$proxy_url"
  probe "YouTube" "https://www.youtube.com/generate_204" "$proxy_url"
  probe "ChatGPT" "https://chatgpt.com/" "$proxy_url"
  probe "OpenAI API" "https://api.openai.com/v1/models" "$proxy_url"
else
  printf '没有检测到可用的系统 HTTPS 代理或 7897/7890 监听端口。\n'
fi

say "如何读结果"
cat <<'EOF'
- HTTP 非 000：至少到达了某个 HTTPS/HTTP 端点，但不保证网页全部功能可用。
- HTTP 200/204：该测试地址的网络路径通常已通。
- OpenAI API 返回 401：仅表示未带 API Key 时成功到达 API 端点，不代表 ChatGPT 网页可用。
- HTTP 3xx：已到达重定向端点；429/5xx：可能是限流或服务端/出口问题。
- ChatGPT 返回 403：已到站，但也可能是出口地区、IP 信誉、WAF 或 curl 客户端策略，不能单独定因。
- HTTP 000：连接、TLS、DNS、节点握手或路由层失败。

按这个顺序定位：
1. 确保订阅已选中节点，并开启「系统代理」。
2. 在 Rule 模式跑一次本脚本，开头选择 Rule，记下结果。
3. 临时切到 Global 模式，等待几秒后再跑一次，然后切回原模式。
4. Global 成功、Rule 失败：规则/规则集问题。
5. 两种模式都只有 GitHub 成功：节点出口或上游限制；换客户端通常无效，应换节点或联系节点服务商。
6. 显式代理成功、浏览器失败：系统代理、浏览器扩展或浏览器 QUIC 路径问题。
7. 系统代理成功、TUN 失败：先继续用系统代理，再单独检查 TUN/DNS/路由，不要盲改 DNS。
EOF

say "报告位置"
printf '已保存到桌面（若无桌面目录则保存到个人目录）：Clash诊断-%s.txt\n' "$timestamp"

if [ -t 0 ]; then
  printf '\n按回车键关闭此窗口...'
  read -r _unused || true
fi
