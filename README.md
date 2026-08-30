# Mac Clash Intel 一键安装包

这是给旧款 Intel Mac（重点适配 MacBook Pro Retina 15-inch Mid 2015）准备的 Clash Verge Rev 安装与只读诊断工具。

> 重要：这个 ZIP 只安装客户端，不包含订阅或节点，也不会把受限节点变成可用节点。原节点若只能访问 GitHub，安装后仍需在自己的订阅中换节点，或联系节点服务商。

当前审核组合：

- Clash Verge Rev `v2.5.2`
- Intel 资产 `Clash.Verge_2.5.2_x64.dmg`
- macOS `12+`（Monterey 或更高）
- SHA-256 `c9fcec27d3e4b4fffe31f314369aaa4017d80c1293c8b1cb65d85de223e9cb6c`

## 为什么选择它

Mid 2015 的 15 英寸 Retina MacBook Pro 是 Intel x86_64，Apple 官方最高支持 macOS Monterey 12。Clash Verge Rev 当前安装文档要求 macOS 12+，而 v2.5.2 的发布说明还明确包含 Monterey 兼容修复，因此比给 Apple Silicon 或新系统准备的包更合适。

本仓库不镜像、不修改、不重签上游 App。安装脚本只从官方 GitHub Release 下载固定资产，并依次核对：

1. 官方仓库、tag 和文件名；
2. 文件大小与 SHA-256；
3. DMG 文件系统；
4. 唯一 App 与 Bundle ID；
5. macOS 代码签名和 Gatekeeper 评估。

任何一项失败都会停止。脚本不会关闭 Gatekeeper，不会清除 quarantine，不会自动修改 DNS、系统代理或 TUN。

## 下载与安装

1. 在本仓库打开 `Releases → Latest → Assets`，下载 `Mac-Clash-Intel-OneClick-*.zip`。
2. 不要使用绿色 `Code → Download ZIP`，也不要下载 `Source code (zip/tar.gz)`；它们不是保留 Finder 双击脚本权限的成品包。
3. 解压成品 ZIP，双击 `双击安装-Clash-Verge.command`。
4. 安装和诊断两个 `.command` 首次运行时都可能被 macOS 分别拦截。请在 Finder 中按住 Control 点按或右键点按对应文件，选择“打开”，再在对话框中点“打开”。不要关闭 Gatekeeper，也不要运行 `xattr` 绕过命令。
5. 安装到“应用程序”需要管理员账户密码。Terminal 输入密码时不会显示字符，这是正常的；输完按回车即可。

安装器会从官方 GitHub Release 下载并验证 Intel x64 DMG，然后安装到 `/Applications/Clash Verge.app`。如果自动启动失败，请到“应用程序”中手动打开 Clash Verge。

更新已有安装时，旧 App 会保存在 `/Applications/.clash-verge-backup-*/Clash Verge.app`；Terminal 会显示本次的精确路径。确认新版本正常前不要删除该回滚副本。

## 安装后配置

1. 打开 `订阅`，粘贴并导入自己的订阅链接。
2. 打开 `代理`，选择并激活一个节点。
3. 打开 `设置 → 系统设置`，先开启 `系统代理` 测试浏览器；确认可用后再考虑 TUN。
4. 分别测试 GitHub、YouTube、ChatGPT，以及实际要使用的 Codex。

订阅 URL、UUID、配置 YAML 和 API Key 不应放进仓库、Issue、Actions Secret 或诊断报告。

## “只有 GitHub 能开”的判定

- Rule 失败、Global 成功：规则或规则集问题；
- Rule/Global 都只有 GitHub 成功：节点出口或上游限制，换客户端通常无效；
- YouTube 正常、ChatGPT 返回 403：常见于出口地区、IP 信誉或风控；
- 显式本地代理成功、浏览器失败：系统代理、浏览器扩展或 QUIC 路径；
- 系统代理成功、TUN 失败：单独检查 TUN/DNS/路由，先保留可用的系统代理。

双击 `双击诊断-Clash-Verge.command` 可生成桌面报告。脚本不修改代理、DNS 或路由，但会主动访问 GitHub、YouTube、ChatGPT 和 OpenAI API；这些站点会看到当时的出口 IP。

报告不记录响应正文、公网 IP、订阅、节点名或配置正文；非本机代理地址会隐藏，PAC URL 不会写入。报告仍会包含 macOS 版本、CPU 架构、用户确认的 Rule/Global 模式、本机代理状态与端口、DNS 成功/失败及 HTTP/curl 状态。分享前请人工浏览一遍。

OpenAI API 在没有 API Key 时返回 `401` 是预期结果，只说明 `api.openai.com` 这条网络路径已到达，不代表 ChatGPT 登录或 Codex 的全部依赖都可用。

## 维护与发布

```bash
bash tests/run.sh
bash scripts/check-upstream.sh
bash scripts/verify-upstream-macos.sh # 需要 Intel macOS
bash scripts/build-release.sh
```

每周工作流只检查上游是否更新；发现新版本后创建人工审核 Issue，不会直接发布未经验证的新二进制。打 `v*` tag 后，Intel macOS runner 会生成保留可执行权限的 ZIP 并发布 Release。

当前 CI 只在 GitHub 的 `macos-15-intel` runner 上验证脚本、DMG、签名和 ZIP 权限。它不能代替 Monterey 12 真机上的 Finder 解压、Gatekeeper、管理员授权和首次启动验收；正式交付前仍需在 Intel Monterey 真机完整走一遍。

## 上游与许可证

- [Clash Verge Rev 官方仓库](https://github.com/clash-verge-rev/clash-verge-rev)
- [v2.5.2 官方 Release](https://github.com/clash-verge-rev/clash-verge-rev/releases/tag/v2.5.2)
- [官方安装文档](https://www.clashverge.dev/install.html)
- [Apple：Monterey 兼容机型](https://support.apple.com/en-us/103260)

本仓库的原创脚本采用 MIT License。上游 Clash Verge Rev 采用 GPL-3.0；本仓库不包含其二进制或源代码，安装时由用户直接从上游官方 Release 获取。
