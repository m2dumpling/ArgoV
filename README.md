# 🚇 ArgoV — Cloudflare Argo Tunnel Manager

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>One-click deploy. Zero public ports. Auto-recovery after reboot.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** is a zero-public-port proxy management panel powered by Cloudflare Argo Tunnel. It wraps VLESS / VMess traffic inside Cloudflare's edge network — no open firewall ports, no domain required. Optional Reality and Shadowsocks for direct connections. Built-in subscription server with auto domain refresh after VPS reboot. Server-side landing relay for clean IP egress — transparent to all clients.

[Quick Start](#quick-start) · [Features](#features) · [Subscription](#subscription-server) · [Relay](#landing-relay) · [WARP](#warp-domain-routing) · [Architecture](#architecture) · [Clients](#client-config) · [中文版](README_CN.md)

---

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

First run auto-launches the interactive install wizard. Press Enter through each step for sensible defaults.

After install, type `argov` to open the management panel.

Non-interactive (env vars):

```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## Features

| Category | Details |
|----------|---------|
| **Argo Tunnel** | VLESS + VMess dual protocol over WebSocket + TLS. Listens on `127.0.0.1` only — zero public exposure |
| **Direct Protocols** | VLESS Reality (XTLS Vision) and Shadowsocks (7 ciphers: AEAD + SS2022) |
| **Install Wizard** | 8-step interactive setup with sensible defaults and auto system detection |
| **Subscription Server** | Python3 HTTP server with ThreadingMixIn + 10s auto-refresh. Token auth. Survives VPS reboot with fresh Argo domain |
| **Custom Links** | Paste any protocol link (Hysteria2, Trojan, TUIC, etc.) — auto-merged into the subscription for all clients |
| **Landing Relay** | Server-side proxy chaining to a clean-IP landing VPS. DNS resolved on landing (zero leak). Supports SS/VLESS/VMess/Trojan exit |
| **WARP Routing** | One-click fscarmen WARP with Smart Split: Google → IPv6, YouTube → SOCKS5, rest → direct |
| **Node Management** | Add / edit / delete Reality and Shadowsocks nodes without full reinstall |
| **System Support** | Debian / Ubuntu / CentOS / Alpine Linux. systemd + openrc service management |
| **Service Isolation** | `argov-tunnel` runs as an independent service — no conflict with existing tunnels |

## Install Wizard

```
━━━ ① Node Name ━━━
  ② CDN Preferred Address (default / list / custom)
  ③ Client Port (CF edge, default 443)
  ④ UUID (auto-generate or custom)
  ⑤ Argo Tunnel Type (temp / fixed token)
  ⑥ Internal Ports (127.0.0.1 only, auto)
  ⑦ Subscription Domain (optional, CF port picker)
  ⑧ Extra Protocols (Reality / Shadowsocks, port input)
```

## Management Panel

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoV  Management Panel                ║
║     VL-Argo VM-Argo SS Reality                  ║
╚══════════════════════════════════════════════════╝

  Name : Tokyo    Xray: ● up    Argo: ● up

── Nodes ──
  1. Show links    2. Change CDN    3. Config    a. Manage nodes

── Services ──
  4. Start    5. Stop    6. Restart (Argo only)

── System ──
  7. Reinstall    8. Update    9. Uninstall
  0. Exit    w. WARP routing
```

## Subscription Server

After reboot, the Argo tunnel auto-recovers with a new domain. The subscription server returns fresh links on every request — **no SSH needed**.

| Mode | URL | Setup |
|------|-----|-------|
| Domain (HTTPS) | `https://sub.yourdomain.com:2096/sub?token=xxx` | CF proxy ON, DNS → VPS IP |
| IP (HTTP) | `http://VPS_IP:PORT/TOKEN` | Zero config |

- 64-bit random token auth
- Self-signed TLS cert (CF Full SSL compatible)
- CF proxy ports: 2096 / 8443 / 2053 / 2083 / 2087 / 443 / custom
- Threaded Python3 HTTP server, systemd / openrc managed

## Node Management

Press `a` to manage nodes. Includes custom link support for external protocols:

```
╔══════════════════════════════════════════╗
║         Manage Nodes                    ║
╚══════════════════════════════════════════╝

  ── Argo Tunnel ──
  e1. VLESS + Argo    port 8081    /vless-argo
  e2. VMess + Argo    port 8082    /vmess-argo

  ── Optional ──
  e3. VLESS Reality   amazon.com   :43210
  e4. Shadowsocks      aes-256-gcm  :8388

  a1. Add Reality    a2. Add SS    d. Delete

  ── Custom Links (User-Added) ──
  2 custom links
  c1. Add    c2. View / delete
```

Paste any protocol link (`hy2://`, `trojan://`, `tuic://`, etc.) via `c1` — it appears in the subscription alongside Argo nodes, persistent across reboots.

| Protocol | Editable |
|----------|----------|
| VLESS / VMess Argo | Port, WS path (auto-sync fallback routes) |
| Shadowsocks | Cipher, password, port, network (tcp/udp) |
| VLESS Reality | SNI, port, shortId, fingerprint, regenerate x25519 keys |

## WARP Domain Routing

Press `w` for WARP management. Three routing modes:

| Mode | Google / Search | YouTube | Other |
|------|-----------------|---------|-------|
| SOCKS5 | WARP IPv4 | WARP IPv4 | WARP IPv4 |
| IPv6 | WARP IPv6 | WARP IPv6 | WARP IPv6 |
| **Smart Split** (recommended) | WARP IPv6 | WARP SOCKS5 | Direct |

- fscarmen WARP auto-install (SOCKS5 :40000 / IPv6 WireGuard)
- Custom domain routing or Google / YouTube defaults
- Python3 safe JSON rewrite with validation and auto-rollback

## Landing Relay

Press `r` to configure server-side proxy chaining. Route traffic through a **landing VPS** with a clean IP — all clients get the clean IP automatically, no client-side chain proxy configuration needed.

```
╔══════════════════════════════════════════╗
║       Landing Relay                      ║
╚══════════════════════════════════════════╝

  ● Enabled → ss → 1.2.3.4:28175  Mode: all

  r1. Set landing node    r2. Toggle mode    r3. Manage domains
  r4. Apply & restart     r5. Disable
```

| Mode | Behavior |
|------|----------|
| **All** (default) | All traffic exits through landing VPS |
| **Split** | Only specified domains relay; rest → direct or WARP |

- Paste any `ss://` / `vless://` / `vmess://` / `trojan://` link as the exit node
- **No DNS leak** — domains forwarded as-is to landing (`domainStrategy: AsIs`), landing resolves DNS
- Landing VPS only needs one SS server (SS-Rust: `chacha20-ietf-poly1305`, 1 command)
- Auto-prompt to apply after mode/domain changes — no forgotten `r4`
- Coexists with WARP — relay rules never touch `warp-out` / `v6-direct`
- Survives reboot and reinstall

## Architecture

```
Client → CF Edge (TLS) → Argo Tunnel → localhost:8080 Xray fallback
                                           ├── /vless-argo → VLESS+WS :8081
                                           └── /vmess-argo → VMess+WS :8082

Direct (optional):  VLESS+Reality (public port)  ·  Shadowsocks (public port)

WARP routing:  Xray rules → warp-out (SOCKS5 :40000) / v6-direct (IPv6)

Relay routing:  Xray rules → relay-out (SS/VLESS/VMess/Trojan) → Landing VPS → Internet

Subscription:  sub_gen.sh → sub.txt → base64 → Python HTTP → Client
                                  ↑
                    /etc/xray/custom_links.txt (user-added)
```

## Alpine Support

| Feature | Debian / Ubuntu | Alpine |
|---------|----------------|--------|
| Service control | `systemctl` | `rc-service` |
| Package manager | `apt` | `apk` |
| Service files | `/etc/systemd/system/` | `/etc/init.d/` |
| Tunnel recovery | `Restart=on-failure` | while-loop retry + 30s network wait |
| Port detection | `netstat` → `ss` → `lsof` | same |

## Client Config

Copy links from the terminal → import to clipboard, or use the subscription URL for one-click import.

| Protocol | Link Format |
|----------|-------------|
| VLESS Argo | `vless://UUID@CDN:443?encryption=none&security=tls&sni=...&type=ws&path=%2Fvless-argo#Name-VLESS` |
| VMess Argo | `vmess://base64(...)` |
| Shadowsocks | `ss://base64@IP:PORT#Name-SS` |
| VLESS Reality | `vless://UUID@IP:PORT?...&security=reality&pbk=KEY#Name-Reality` |
| Custom | Any `protocol://` link pasted via panel |

Supported clients: v2rayN · Nekoray · Shadowrocket · Sing-box · Clash Meta · V2Box · Karing

## License

MIT License. Fork, modify, share freely.
