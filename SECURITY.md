# Security

## 供应链边界

- 仅从 `https://github.com/clash-verge-rev/clash-verge-rev/releases/` 下载。
- 固定 tag、资产名、大小与 SHA-256；不执行“模糊匹配最新版”。
- 不镜像、不修改、不重签 Clash Verge Rev。
- 不自动关闭 Gatekeeper，不运行 `xattr -dr`，不改变防火墙、DNS、路由或系统代理。
- 更新已有安装时，旧 App 移到 root 管理的 `/Applications/.clash-verge-backup-*/Clash Verge.app`，Terminal 会显示精确路径；失败时尝试恢复。
- 安装和诊断两个 `.command` 都可能在首次运行时分别触发 Gatekeeper。只使用 Finder 的 Control 点按或右键“打开”，不要全局关闭 Gatekeeper。

当前 CI 只在 `macos-15-intel` runner 上验证脚本、官方 DMG、签名和 ZIP 权限。Monterey 12 的 Finder 解压、Gatekeeper、管理员授权和首次启动仍需 Intel 真机验收。

## 隐私边界

这个仓库和成品 ZIP 只提供客户端安装器，不包含订阅、节点、API Key 或私人配置。不要在 Issue、日志、提交或 Actions 中提供订阅 URL、UUID、节点配置、API Key、代理账号或完整 Clash 配置。

诊断不修改本机代理、DNS 或路由，但会主动访问 GitHub、YouTube、ChatGPT 和 OpenAI API；这些外部站点会看到当时的出口 IP。

报告不记录响应正文、公网 IP、订阅、节点名或配置正文；非本机代理地址会隐藏，PAC URL 不会写入。报告仍包含 macOS 版本、CPU 架构、用户确认的模式、本机代理状态与端口、DNS 成功/失败和 HTTP/curl 状态。脱敏不能替代人工检查，分享前仍应浏览完整报告。

## 报告问题

可以提供：macOS 版本、Mac 架构、脚本阶段、HTTP/curl 状态和已脱敏错误。不要粘贴订阅、节点、API Key、PAC URL 或配置正文。
