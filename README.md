# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a> |
  <a href="#-features">Features</a> |
  <a href="#-one-click-installation">Installation</a> |
  <a href="#-interactive-setup-wizard">Setup Wizard</a> |
  <a href="#-management-menu">Menu</a>
</p>

---

An ultra-lightweight, rock-solid one-click management script for Cloudflare Argo Tunnel — **VLESS + VMess dual protocol** over WebSocket + TLS.

**ArgoX-Mini** installs only what Argo needs: Xray-core + cloudflared. No Nginx, no Caddy, no Reality, no Hysteria2, no XHTTP. All Xray inbounds bind strictly to `127.0.0.1` — your VPS exposes zero proxy ports to the public internet.

## ✨ Features

- **VLESS + VMess Dual Protocol** — Both over WS+TLS+Argo via Xray fallback routing. One tunnel, two protocols, zero extra components.
- **Interactive Install Wizard** — 6-step guided setup: node name → CDN address → port → UUID → tunnel type → internal ports. Every step has sensible defaults (just press Enter).
- **`vless://` + `vmess://` One-Click Import** — After install, both links + QR code are printed. Custom node names appear in links (e.g. `#Tokyo-VLESS`).
- **Persistent Configuration** — Settings saved to `/etc/xray/argox.conf`. Reinstall without losing your customizations.
- **Zero Public Exposure** — Xray listens on `127.0.0.1` only. No proxy ports on the public internet. Immune to active scans.
- **Fixed Argo Tunnel Support** — Switch between temporary `.trycloudflare.com` domains and permanent CF Zero Trust Token tunnels.
- **Config Modification** — Change node name, UUID, CDN endpoint, ports, or toggle tunnel type anytime from the menu.
- **No Caddy / No Nginx** — Cloudflare handles TLS at the edge. Your VPS needs zero certificates.
- **Built-in Carrier-Optimized CDN Pool** — 13 pre-configured domains covering China Mobile / Unicom / Telecom routing.
- **Auto Port Conflict Detection** — If default internal ports are in use, the installer finds free ones automatically.
- **Env Var Overrides** — `NODE_NAME=Tokyo ARGO_PORT=9090 CDN_PORT=8443 bash <(curl ...)` for non-interactive deployment.

## 🚀 One-Click Installation

Ubuntu / Debian / CentOS, root:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

First run auto-launches the setup wizard. Press Enter through each step for defaults.

### Non-interactive (env vars)

```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe CDN_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🎛 Interactive Setup Wizard

```
━━━ ① 节点名称 ━━━
  节点名称 [ArgoX-Mini]: Tokyo-Aria

━━━ ② CDN 优选地址 ━━━
  1. 默认 cdn.31514926.xyz
  2. 从优选列表中选择
  3. 自定义

━━━ ③ 客户端端口 ━━━
  端口 [443]: _

━━━ ④ 用户 ID (UUID) ━━━
  UUID [自动生成]: _

━━━ ⑤ Argo 隧道类型 ━━━
  1. 临时隧道 (.trycloudflare.com)
  2. 固定隧道 (CF Zero Trust Token)

━━━ ⑥ 内部端口 ━━━
  起始端口 [8080]: _
```

## 🛠️ Management Menu

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VLESS + VMess 双协议  |  WS + TLS + Argo    ║
╚══════════════════════════════════════════════════╝

  节点名称 : Tokyo-Aria
  Xray     : ● 运行中     Argo : ● 运行中
  UUID     : abcd1234-...
  域名     : xxx.trycloudflare.com
  CDN      : cdn.31514926.xyz:443

───────────────── 节点管理 ─────────────────
  1. 查看节点链接 (VLESS + VMess)
  2. 更换优选域名 / 线路
  3. 修改配置 (名称 / UUID / 隧道 / 端口)

───────────────── 服务控制 ─────────────────
  4. 启动 服务
  5. 停止 服务
  6. 重启 服务 (刷新域名)

───────────────── 系统维护 ─────────────────
  7. 重新安装 (保留配置)
  8. 完全卸载
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
                                                            │  fallback router │
                                                            │  /vless-argo→8081│
                                                            │  /vmess-argo→8082│
                                                            └──┬───────────┬───┘
                                                               │           │
                                                         VLESS+WS    VMess+WS
                                                         :8081       :8082
                                                        (127.0.0.1 only)
```

## 💻 Client Configuration

**Recommended:** Copy the `vless://` or `vmess://` link from terminal → Import from clipboard.

| Setting | VLESS | VMess |
|---|---|---|
| Address | `cdn.31514926.xyz` (or chosen CDN) | Same |
| Port | `443` (or chosen port) | Same |
| UUID | From terminal | From terminal |
| Network | `ws` | `ws` |
| Path | `/vless-argo` | `/vmess-argo` |
| TLS | `tls` | `tls` |
| SNI / Host | `xxxx.trycloudflare.com` | Same |
| AlterId | — | `0` |
| Security | `none` | `none` |

Supported clients: v2rayN, Nekoray, Nekobox, Shadowrocket, Sing-box, V2Box, Karing, Clash Meta.

## 📄 License

MIT License. Fork, modify, share freely.
