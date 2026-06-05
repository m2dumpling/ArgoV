# ArgoX-Mini

> Cloudflare Argo Tunnel one-click deployment script  
> VLESS + VMess + Shadowsocks + VLESS Reality | WARP SOCKS5/IPv6 smart routing | Built-in subscription server

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/Platform-Debian_Ubuntu_CentOS_Alpine-lightgrey)

[中文版](README_CN.md)

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Install Wizard](#install-wizard)
- [Management Panel](#management-panel)
- [Subscription Server](#subscription-server)
- [WARP Domain Routing](#warp-domain-routing)
- [Node Management](#node-management)
- [Architecture](#architecture)
- [Alpine Support](#alpine-support)
- [Client Config](#client-config)
- [License](#license)

---

## Features

| Category | Details |
|----------|---------|
| **Argo Tunnel** | VLESS + VMess dual protocol, WS+TLS, zero public ports, `127.0.0.1` only |
| **Direct Protocols** | VLESS Reality (XTLS Vision), Shadowsocks (7 ciphers: AEAD + SS2022) |
| **Install Wizard** | 8-step interactive with sensible defaults, auto system detection |
| **Subscription Server** | Auto-recovery after reboot, dual-mode (domain HTTPS / IP HTTP), token auth, QR code |
| **WARP Routing** | One-click fscarmen WARP, Smart Split (Google→IPv6 + YouTube→SOCKS5) |
| **Node Management** | Add/edit/delete any protocol, no full reinstall |
| **Compatibility** | Debian / Ubuntu / CentOS / Alpine Linux, openrc + systemd |
| **Service Isolation** | `argox-tunnel` service, no conflict with existing tunnels |

---

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

First run auto-launches the install wizard. Press Enter through each step for defaults.

Non-interactive (env vars):

```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

---

## Install Wizard

```
━━━ ① Node Name ━━━
  ② CDN Address (default / list / custom)
  ③ Client Port (CF edge, default 443)
  ④ UUID (auto-generate or custom)
  ⑤ Argo Tunnel Type (temp / fixed token)
  ⑥ Internal Ports (127.0.0.1 only, auto)
  ⑦ Subscription Domain (optional, CF port picker)
  ⑧ Extra Protocols (Reality / Shadowsocks, port input)
```

---

## Management Panel

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  Management Panel                ║
║     VL-Argo VM-Argo SS Reality                  ║
╚══════════════════════════════════════════════════╝

  Name : Tokyo    Xray: ● up    Argo: ● up    CDN : cdn.xxx:443

── Nodes ──
  1. Show links    2. Change CDN    3. Config    a. Manage nodes

── Services ──
  4. Start    5. Stop    6. Restart/Recover (Argo only)

── System ──
  7. Reinstall (preserve)    8. Update    9. Uninstall
  0. Exit    w. WARP routing
```

---

## Subscription Server

After reboot, the Argo tunnel auto-recovers with a new domain. The subscription server returns fresh links on every request — **zero SSH needed**.

### URLs

| Mode | URL | Setup |
|------|-----|-------|
| Domain (HTTPS) | `https://sub.yourdomain.com:2096/sub?token=xxx` | CF proxy ON, DNS → VPS IP |
| IP (HTTP) | `http://VPS_IP:PORT/TOKEN` | No setup needed |

### Features

- Token auth via random 64-bit hex string
- Self-signed TLS certificate (CF Full SSL mode compatible)
- CF-supported port picker: 2096, 8443, 2053, 2083, 2087, 443, or custom
- 15-line Python3 HTTP server, `systemd` / `openrc` managed
- QR code encodes subscription URL for mobile import

---

## WARP Domain Routing

Press `w` to access WARP management. Three routing modes:

| Mode | Google / Search | YouTube | Other |
|------|-----------------|---------|-------|
| SOCKS5 | WARP IPv4 | WARP IPv4 | WARP IPv4 |
| IPv6 | WARP IPv6 | WARP IPv6 | WARP IPv6 |
| **Smart Split** (recommended) | WARP IPv6 | WARP SOCKS5 | Direct |

- fscarmen WARP auto-install (SOCKS5 :40000, IPv6 WireGuard)
- Custom domain lists or Google/YouTube defaults
- Python3 safe JSON rewrite with validation and auto-rollback

---

## Node Management

Press `a` to manage all protocol nodes:

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
```

Editable fields per protocol:

| Protocol | Editable |
|----------|----------|
| VLESS/VMess Argo | Port, WS path (auto-sync fallback) |
| Shadowsocks | Cipher, password, port |
| VLESS Reality | SNI, port, shortId, fingerprint, regenerate x25519 keys |

---

## Architecture

```
Client → CF Edge (TLS) → Argo Tunnel → localhost:8080 Xray fallback
                                           ├── /vless-argo → VLESS+WS :8081
                                           └── /vmess-argo → VMess+WS :8082

Optional direct:  VLESS+Reality (public port)  ·  Shadowsocks (public port)

WARP routing:  Xray rules → warp-out (SOCKS5 :40000) or v6-direct (IPv6)
```

---

## Alpine Support

| Feature | Debian/Ubuntu | Alpine |
|---------|--------------|--------|
| Service control | `systemctl` | `rc-service` |
| Package manager | `apt` | `apk` |
| Service files | `/etc/systemd/system/` | `/etc/init.d/` |
| Tunnel recovery | `Restart=on-failure` | while-loop retry + 30s network wait |
| Port detection | `netstat` → `ss` → `lsof` | same |

---

## Client Config

Copy links from terminal → import to clipboard, or use subscription URL.

| Protocol | Example |
|----------|---------|
| VLESS Argo | `vless://UUID@CDN:443?...&path=%2Fvless-argo#Name-VLESS` |
| VMess Argo | `vmess://base64(#Name-VMess)` |
| SS | `ss://base64@IP:PORT#Name-SS` |
| Reality | `vless://UUID@IP:PORT?...&security=reality&pbk=KEY#Name-Reality` |

Clients: v2rayN · Nekoray · Shadowrocket · Sing-box · Clash Meta

---

## License

MIT License. Fork, modify, share freely.
