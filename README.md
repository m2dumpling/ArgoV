# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a> |
  <a href="#-features">Features</a> |
  <a href="#-one-click-installation">Installation</a> |
  <a href="#-cli-management-menu">Menu</a>
</p>

---

A lightweight, rock-solid, and ultra-pure one-click management script for Cloudflare Argo Tunnel (VMess + WebSocket).

Unlike bloated multi-protocol scripts (e.g. xray-2go), **ArgoX-Mini** strips out all unnecessary direct-connection protocols (Reality, Hysteria2, XHTTP) and web server dependencies (Nginx, Caddy). Xray binds strictly to `127.0.0.1` — your VPS exposes zero proxy ports to the public internet.

## ✨ Features

- **100% Pure Argo** — No Caddy/Nginx. No TLS certificates on your VPS. Xray + cloudflared only.
- **vmess:// One-Click Import** — After installation, a `vmess://` link + QR code are printed directly in terminal. Copy-paste into v2rayN, done.
- **Zero Public Exposure** — Xray listens on `127.0.0.1:8080`. Not a single proxy port faces the internet. Immune to active censorship scans.
- **Built-in Carrier-Optimized CDN** — Pre-configured optimized domains for China Mobile, China Unicom, and China Telecom routing.
- **Interactive Management Panel** — `argo-v2` shortcut injected into your system. Colorful, categorized menu with real-time status indicators.
- **Config Modification** — Change UUID, refresh Argo domain, or swap CDN endpoints without reinstalling.
- **One-Key Uninstall** — Clean removal of all traces from the system.

## 🚀 One-Click Installation

Run in your Linux VPS terminal (Ubuntu/Debian/CentOS, root):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

After install completes, the `vmess://` link is displayed immediately — copy and import.

## 🛠️ CLI Management Menu

```bash
argo-v2
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
╚══════════════════════════════════════════════════╝

  Xray 内核 : ● 运行中     UUID : abcd1234-...  
  Argo 隧道 : ● 运行中
  当前域名  : xxx.trycloudflare.com

───────────────── 节点管理 ─────────────────
  1. 查看节点连接参数 & 一键导入链接
  2. 更换/选择分流优选域名
  3. 修改节点配置 (UUID / 刷新域名)

───────────────── 服务控制 ─────────────────
  4. 启动 服务
  5. 停止 服务
  6. 重启 服务 (获取新临时域名)

───────────────── 系统维护 ─────────────────
  7. 重新一键全自动安装
  8. 完全卸载 ArgoX-Mini
```

## 💻 Client Configuration (v2rayN)

**Option A — One-click import (recommended):** Copy the `vmess://` link from the terminal → v2rayN → Import from clipboard.

**Option B — Manual setup:**

| Parameter | Value | Note |
|---|---|---|
| **Address** | `cdn.31514926.xyz` | Or carrier-specific domains (Menu 2) |
| **Port** | `443` | Cloudflare TLS edge |
| **User ID (UUID)** | `[Generated UUID]` | Copy from terminal output |
| **AlterId** | `0` | Default |
| **Security** | `none` | Outer TLS handles encryption |
| **Network** | `ws` | WebSocket |
| **Host** | `xxxx.trycloudflare.com` | ⚠️ Must match terminal output |
| **Path** | `/vmess-argo` | Fixed routing path |
| **TLS** | `tls` | Enable |
| **SNI** | `xxxx.trycloudflare.com` | Same as Host |

## 📄 License

MIT License. Fork, modify, and share freely.
