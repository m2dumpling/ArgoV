# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a> |
  <a href="#-features">Features</a> |
  <a href="#-one-click-installation">Installation</a> |
  <a href="#-cli-management-menu">Menu</a>
</p>

---

An ultra-lightweight, rock-solid one-click management script for Cloudflare Argo Tunnel — **VLESS + VMess dual protocol** over WebSocket + TLS.

Unlike bloated multi-protocol scripts (xray-2go bundles 4 protocols with Caddy; ArgoX bundles 11 protocols with Nginx), **ArgoX-Mini** installs only what Argo needs: Xray-core + cloudflared. No Nginx, no Caddy, no Reality, no Hysteria2, no XHTTP. Xray binds strictly to `127.0.0.1` — your VPS exposes zero proxy ports to the public internet.

## ✨ Features

- **VLESS + VMess Dual Protocol** — Both protocols over WS+TLS+Argo. Use VLESS for modern clients (v2rayN, Shadowrocket, Sing-box), or VMess for maximum compatibility.
- **Xray Fallback Routing** — A single Argo tunnel entry point (port 8080) routes `/vless-argo` and `/vmess-argo` to their respective internal inbounds. Zero extra components needed.
- **`vmess://` + `vless://` One-Click Import** — After installation, both links + QR code are printed directly in terminal. Copy-paste into any client, done.
- **Zero Public Exposure** — All Xray inbounds listen on `127.0.0.1` only. Not a single proxy port faces the internet. Immune to active censorship scans.
- **No Caddy / No Nginx** — Cloudflare handles TLS termination at the edge. Your VPS needs no certificates, no web servers, no open ports.
- **Built-in Carrier-Optimized CDN** — Pre-configured domains for China Mobile, China Unicom, China Telecom routing.
- **Interactive Color Panel** — `argo-v2` command launches an organized, color-coded management menu with real-time status.
- **Config Modification** — Change UUID (syncs both protocols), refresh Argo domain, swap CDN endpoints — no reinstall.

## 🚀 One-Click Installation

Ubuntu / Debian / CentOS, root:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

Links appear immediately after install. Import and go.

## 🛠️ CLI Management Menu

```bash
argo-v2
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VLESS + VMess 双协议  |  WS + TLS + Argo    ║
╚══════════════════════════════════════════════════╝

  Xray 内核 : ● 运行中     UUID : abcd1234-...
  Argo 隧道 : ● 运行中

───────────────── 节点管理 ─────────────────
  1. 查看节点链接 (VLESS + VMess 双协议)
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

## 🏗 Architecture

```
┌──────────┐     TLS:443      ┌─────────────┐     HTTP     ┌──────────────────┐
│  Client  │ ────────────────→ │  Cloudflare │ ───────────→ │  cloudflared     │
│ v2rayN   │ ←──────────────── │  Edge       │ ←─────────── │  (Argo Tunnel)   │
└──────────┘     WebSocket     └─────────────┘   localhost  └───────┬──────────┘
                                                                    │
                                                            localhost:8080
                                                                    │
                                                            ┌───────▼──────────┐
                                                            │  Xray Inbound    │
                                                            │  VLESS TCP       │
                                                            │  port 8080       │
                                                            │  ┌─ fallback ─┐  │
                                                            │  │ /vless-argo │  │
                                                            │  │ /vmess-argo │  │
                                                            │  └─────────────┘  │
                                                            └──┬───────────┬───┘
                                                               │           │
                                                      localhost:8081  localhost:8082
                                                      VLESS + WS      VMess + WS
```

## 💻 Client Configuration

### VLESS (recommended for modern clients)

| Setting | Value |
|---|---|
| Address | `cdn.31514926.xyz` (or carrier domain) |
| Port | `443` |
| UUID | Copy from terminal |
| Network | `ws` (WebSocket) |
| Path | `/vless-argo` |
| TLS | `tls` |
| SNI | `xxxx.trycloudflare.com` |

### VMess

| Setting | Value |
|---|---|
| Address | `cdn.31514926.xyz` |
| Port | `443` |
| UUID | Copy from terminal |
| AlterId | `0` |
| Security | `none` |
| Network | `ws` |
| Path | `/vmess-argo` |
| TLS | `tls` |
| SNI | `xxxx.trycloudflare.com` |

**Supported clients:** v2rayN, Nekoray, Nekobox, Shadowrocket, Sing-box, V2Box, Karing, Clash Meta, and any client supporting VLESS/VMess + WS + TLS.

## 📄 License

MIT License. Fork, modify, share freely.
