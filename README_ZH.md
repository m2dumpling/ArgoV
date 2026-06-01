# ArgoX-Mini 纯净版隧道管理面板

<p align="center">
  <a href="./README.md"><b>🌐 English Documentation</b></a>
</p>

---

一个极度精简、坚如磐石且绝无臃肿的 Cloudflare Argo 穿透隧道（VMess + WebSocket）一键安装与管理脚本。

与市面上其他全家桶脚本不同，**ArgoX-Mini** 从底层彻底抹除了所有不需要的直连协议（如 Reality、Hysteria2、XHTTP）以及网页服务器依赖（如 Nginx、Caddy）。脚本强制 Xray 仅在本地回环监听，确保您的 VPS 在公网上零特征、零原生代理端口暴露。

## ✨ 项目特点

- **绝对纯净**：零无用组件。无需安装 Caddy/Nginx，VPS 本地无需繁琐地申请和续签 TLS 证书。
- **极致安全性**：Xray 核心严格绑定 `127.0.0.1`。公网无任何开放的可疑代理端口，完美免疫防火墙的垃圾流量主动探测。
- **内置三网优选分流**：直接集成了经过优化的优质 CDN 域名，细分为三网通用、移动专线、联通专线和电信专线。
- **原生快捷控制台**：安装后自动向系统注入 `argo-v2` 环境变量，随时随地一行命令唤醒可视化管理菜单。

## 🚀 一键部署安装

在您的 Linux VPS 终端中（支持 Ubuntu/Debian/CentOS 的 root 用户），直接复制并运行以下命令：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🛠️ 日常快捷管理

安装完成后，在终端中输入以下快捷指令即可秒开彩色交互式管理面板：

```bash
argo-v2
```

**菜单功能详解：**

- **查看节点连接参数**：提取当前的 VMess 核心凭证以及由 Cloudflare 动态分配的临时伪装域名。
- **启动 服务**：一键拉起 Xray 内核与 Argo 隧道守护进程。
- **停止 服务**：临时彻底关闭后端与隧道，释放系统资源，不留痕迹。
- **重启 服务**：刷新缓存并重新向 Cloudflare 申请一个全新的随机 `.trycloudflare.com` 域名。
- **更换/选择分流优选域名**：快捷查看和切换适合您本地网络环境的优选接入点。
- **重新一键全自动安装**：彻底清理残留并重新全新部署。

## 💻 客户端配置指南 (以 v2rayN 为例)

服务端部署成功后，在 `argo-v2` 菜单中选择 **1** 获取专属参数。打开 v2rayN，新建一个 VMess 服务器，严格对照下方清单填写：

| 配置项 | 填写内容 | 说明 |
|---|---|---|
| **地址 (Address)** | `cdn.31514926.xyz` | 优选接入点（也可使用菜单 5 中的分流域名） |
| **端口 (Port)** | `443` | 必须为 443 |
| **用户 ID (UUID)** | `[您的专属 UUID]` | 从服务端终端输出中完整复制 |
| **额外 ID (alterId)** | `0` | 保持默认值 |
| **加密方式** | `none` | 推荐 none，外层已有 TLS 保护 |
| **传输协议 (network)** | `ws` | 选择 WebSocket 传输 |
| **伪装域名 (Host)** | `xxxx.trycloudflare.com` | ⚠️ 核心步骤：必须填写终端输出的临时域名 |
| **路径 (path)** | `/vmess-argo` | 固定的内部转发路径 |
| **传输层安全 (TLS)** | `tls` | 下拉菜单开启 tls 传输安全 |
| **SNI** | `xxxx.trycloudflare.com` | 必须与上方伪装域名 (Host) 完全一致 |

## 📄 开源协议

本项目基于 MIT License 协议开源，欢迎自由 Fork、二次改造和分享！
