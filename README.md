# 🌐 ArgoV — Next-Gen Proxy Management Panel

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>One-click deploy. Zero public ports. Dynamic routing. Built for geeks.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray_v1.8+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality|Hysteria2-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** is a zero-trust proxy management panel powered by Cloudflare Argo Tunnel. VLESS / VMess traffic is encapsulated inside CF's edge network — zero public ports, no domain required. Native support for VLESS Reality, Xray-native Hysteria2 (with BBR/Brutal congestion control + port hopping), and Shadowsocks. Built-in multi-user traffic quotas with monthly auto-reset, server-side landing relay for clean IP egress, aggregated subscriptions across all your VPSes, and WARP smart split-routing. All in a single Bash script.

[Quick Start](#quick-start) · [Panel](#management-panel) · [Features](#core-features) · [Subscriptions](#dynamic-subscription-server) · [User Quotas](#multi-user-traffic-quotas) · [Aggregation](#aggregated-subscription) · [Relay](#landing-relay) · [WARP](#smart-warp-routing) · [中文版](README_CN.md)

---

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

First run auto-launches the interactive install wizard. Press Enter through each step.

After install, type `ag` to open the panel.

Non-interactive:
```bash
NODE_NAME=Tokyo CDN_DOMAIN=xx.cloudflare.182682.xyz bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## Management Panel

```text
 ╔══════════════════════════════════════════════════╗
 ║     ArgoV  纯净版隧道管理面板                    ║
 ║     VL-Argo VM-Argo SS Reality Hysteria2         ║
 ╚══════════════════════════════════════════════════╝

  名称 : Tokyo    Xray: ● 运行中    Argo: ● 运行中
  UUID : 45c7acf6-1fb...
  域名 : xxx.trycloudflare.com
  CDN  : xx.cloudflare.182682.xyz:443

 ──────────────── ✦ 核心功能 ✦ ────────────────
  1. 🔗 查看节点链接       2. ☁️  更换优选线路
  3. ⚙️  修改基础配置       a. 🧩 管理代理节点 (添加/编辑/删除)
  u. 👥 用户/流量限额       配额用户仅下发本机节点

 ──────────────── ✦ 进阶路由 ✦ ────────────────
  w. 🌐 独立 WARP 分流     r. 🔀 落地节点中继
  g. 📡 聚合订阅 (Aggregation)

 ──────────────── ✦ 状态运维 ✦ ────────────────
  4. ▶️  启动系统        5. ⏹️  停止系统
  6. 🔁 重启 Argo 隧道   7. 🔄 重新安装 (保留数据)
  8. 🆙 更新管理脚本     9. 🗑️  彻底卸载系统
  x. 🚀 更新 Xray 内核   0. 🚪 安全退出
 ───────────────────────────────────────────────
```

## Core Features

| Category | Details |
|----------|---------|
| **Argo Tunnel** | VLESS + VMess via WS + TLS over Cloudflare. `127.0.0.1` only — zero public exposure. Auto domain recovery after reboot |
| **VLESS Reality** | XTLS Vision + Reality stealth. Anti-probing, custom SNI / shortId / fingerprint / x25519 keys |
| **Hysteria2** | Xray-native QUIC protocol. BBR / Brutal congestion control, port hopping (UDP redirect), per-user auth |
| **Shadowsocks** | 7 ciphers: AEAD + SS2022. TCP / UDP / TCP+UDP network modes |
| **Subscription Server** | Python3 HTTP, threaded + 10s auto-refresh, self-signed TLS (CF Full SSL). Outputs base64 for v2rayN / Clash YAML for Mihomo |
| **User Quotas** | Per-user isolated accounts with UUID, token, bidirectional traffic limits (`200G`). Per-user subscription granularity. Monthly auto-reset (Beijing time) |
| **Aggregated Sub** | Collect subscriptions from all your VPSes + airports into one URL. Any source change syncs in ≤10s. Self-signed TLS tolerant |
| **Landing Relay** | Server-side proxy chain to clean-IP VPS. SS / VLESS / VMess / Trojan exit. `AsIs` DNS — zero leak on entry. Split or global mode |
| **WARP Routing** | SOCKS5 :40000 + IPv6 WireGuard. Smart split: Google → IPv6, YouTube → SOCKS5, rest → direct. Custom domain lists |
| **Node Management** | Add / edit / delete all protocols independently. Custom link paste for external nodes. Built-in HY2 port hopping config |
| **System** | Debian / Ubuntu / CentOS / Alpine. `systemd` + `openrc`. Service isolation (`argov-tunnel`, `argov-sub`, `argov-stats`) |

## Dynamic Subscription Server

VPS reboot → Argo tunnel auto-recovers with new domain → subscription server returns fresh links. **Zero SSH.**

| Mode | URL | Setup |
|------|-----|-------|
| Domain (HTTPS) | `https://sub.yourdomain.com:2096/sub?token=xxx` | CF proxy ON, DNS → VPS IP |
| IP (HTTP) | `http://IP:PORT/TOKEN` | None |

- 64-bit random token auth, manually configurable via `3. 修改配置 → 9. 订阅配置`
- Self-signed TLS cert auto-generated and validated per domain change
- CF proxy ports: 2096 / 8443 / 2053 / 2083 / 2087 / 443
- Profile headers for Shadowrocket group naming & v2rayN `Profile-Title`
- Subscription config editor: HTTP ↔ HTTPS, domain, port, custom token

## Multi-User Traffic Quotas

Press `u` to manage independent user accounts:

```text
  name             state    reset    used           quota          token
  ----             -----    -----    ----           -----          -----
  default          on       -        1.96 GB        unlimited      67e66c...
  f1               on       ↑10      987.51 MB      200.00 GB      e87385...
```

- Each user: separate UUID, subscription token, enable/disable toggle, traffic quota
- Limited users receive: VLESS Argo, VMess Argo, Reality, Hysteria2 (no custom links)
- Quota enforcement: `argov-stats` daemon polls Xray StatsService every 60s; auto-disables on breach; preserves user in list
- **Monthly auto-reset**: per-user reset day (1–28, Beijing time). Usage zeroed, disabled users re-enabled. Option `8` in user management

## Aggregated Subscription

Press `g` to merge multiple subscription sources into one URL:

```text
 ── 📡 总订阅 (导入客户端) ──
   https://sub.example.com:2096/agg?token=xxx

 ── 📥 子订阅 (其他 VPS/机场) ──
   1. https://vps2.example.com:2096/sub?token=abc
   2. https://vps3.example.com:8443/sub?token=def

   共 2 个子订阅 + 本机 = 聚合后客户端总节点
```

- One aggregated URL → all nodes from all VPSes + airports
- Any source change: ≤10s sync via `agg_gen.sh` background fetch
- Handles self-signed TLS sources (`curl -skL`)
- Deduplication: `sort -u` across all sources
- Client imports one URL, sees all nodes

## Landing Relay (Server-Side Proxy Chaining)

Press `r` to transparently route traffic through a clean-IP VPS:

```text
 ● 已启用 → ss → 1.2.3.4:28175  模式: 全部
```

- Paste any `ss://` / `vless://` / `vmess://` / `trojan://` link as exit
- **Zero DNS leak**: `domainStrategy: AsIs` — domains pass through proxy protocol as-is; landing VPS resolves DNS
- Modes: **All** (all traffic relayed) or **Split** (domain list only)
- Landing VPS only needs SS-Rust: one command, 5 MB RAM
- Coexists with WARP; survives reboot / reinstall

## Smart WARP Routing

Press `w` for one-click fscarmen WARP with domain-aware splitting:

| Mode | Google | YouTube | Other |
|------|--------|---------|-------|
| SOCKS5 | WARP | WARP | WARP |
| IPv6 | WARP | WARP | WARP |
| Smart Split | WARP IPv6 | WARP SOCKS5 | Direct |

## Architecture

```text
Client → CF Edge (TLS) → Argo Tunnel → localhost:8080 Xray fallback
                                           ├── /vless-argo → VLESS+WS :8081
                                           └── /vmess-argo → VMess+WS :8082

Direct :  VLESS+Reality  ·  Hysteria2 (QUIC, BBR/Brutal)  ·  Shadowsocks

Routing :  Xray rules → warp-out (Socks5 :40000) / v6-direct (IPv6) / relay-out (SS/VL/VM/TJ) → Landing

Aggregation :  agg_gen.sh → curl all sources → merge → dedup → base64 → /agg?token=xxx
```

## Client Compatibility

`v2rayN` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Clash Meta` · `V2Box` · `Karing`

## License

[MIT License](LICENSE).
