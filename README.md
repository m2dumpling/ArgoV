# 🌐 ArgoV — Next-Gen Proxy Management Panel

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>One-click · Dual-Core · Zero Public Ports · Dynamic Routing</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray_1.8+_|_Sing--box_1.10+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality|HY2|TUIC|AnyTLS-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** is a dual-core zero-trust proxy panel. Xray-core powers the Argo tunnel (VLESS/VMess WebSocket), Sing-box extends coverage to TUIC, AnyTLS Reality. Built-in per-user quotas, certificate pinning, port hopping, landing relay, aggregated subscriptions, and WARP routing. All in one Bash script.

[Quick Start](#quick-start) · [Panel](#management-panel) · [Features](#core-features) · [Dual-Core](#dual-core) · [Subs](#dynamic-subscription-server) · [Quotas](#multi-user-traffic-quotas) · [Aggregation](#aggregated-subscription) · [中文版](README_CN.md)

---

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

After install, type `ag` for the panel.

```bash
NODE_NAME=Tokyo bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## Management Panel

```text
 Name: Tokyo    Xray: ● running    Sing-box: ● running    Argo: ● running
 UUID: 45c7acf6-1fb...
 Domain: xxx.trycloudflare.com  CDN: xx.cloudflare.182682.xyz:443
 Traffic: ↓ 12.3 GB  ↑ 156.7 GB

 ──────────────── ✦ Core ✦ ────────────────
  1. 🔗 View links         2. ☁️  Switch CDN
  3. ⚙️  Edit config        a. 🧩 Manage protocols
  u. 👥 Users & quotas     

 ──────────────── ✦ Routing ✦ ────────────────
  w. 🌐 WARP routing       r. 🔀 Landing relay
  g. 📡 Aggregated sub      s. 🔧 Sing-box manage

 ──────────────── ✦ Ops ✦ ────────────────
  4. ▶️  Start  5. ⏹️  Stop  6. 🔁 Restart Argo
  7. 🔄 Reinstall  8. 🆙 Update  9. 🗑️  Uninstall
  x. 🚀 Update Xray    0. 🚪 Exit
```

## Core Features

| Category | Details |
|----------|---------|
| **Argo Tunnel** | VLESS + VMess via WS + TLS over CF. `127.0.0.1` only, zero public exposure. Auto domain recovery |
| **Dual-Core** | Xray-core for Argo; Sing-box for TUIC, AnyTLS. Unified panel, merged subscription |
| **VLESS Reality** | XTLS Vision + Reality. Custom SNI / shortId / fingerprint / x25519 keys |
| **Hysteria2** | BBR / Brutal congestion, port hopping (UDP REDIRECT, custom range, fixed/random interval), pinSHA256 |
| **TUIC / AnyTLS** | Sing-box native protocols. TUIC QUIC + BBR; AnyTLS Reality stealth |
| **Shadowsocks** | AEAD + SS2022, TCP/UDP |
| **Subscription Server** | Python3 HTTP, 10s refresh, self-signed TLS. base64 / Clash YAML / sing-box output |
| **User Quotas** | Per-user UUID+Token, bidirectional limits. Xray via gRPC, Sing-box via iptables per-port. Monthly reset |
| **Aggregated Sub** | Merge all VPS + airport subs into one URL. ≤10s sync |
| **Landing Relay** | SS / VLESS / VMess / Trojan exit. `AsIs` DNS, zero leak |
| **WARP Routing** | SOCKS5 :40000 + IPv6. Smart split: Google→IPv6, YouTube→SOCKS5 |
| **System** | Debian / Ubuntu / CentOS / Alpine. systemd + OpenRC |

## Dual-Core

```
                 Xray-core (always)             Sing-box (optional)
                 ├ VLESS Argo  :8080            ├ Hysteria2   :8443
                 ├ VMess Argo  :8081            ├ TUIC        :8444
                 ├ Reality     :443             ├ AnyTLS      :8445
                 ├ Hysteria2   :8443            ├ VLESS Reality :8446
                 └ Shadowsocks :8388            └ Shadowsocks :8447
                 └  Argo + gRPC stats            iptables per-port stats
```

- **Xray required** for Argo tunnel fallback; **Sing-box optional** (`s → s1`)
- Unified subscription merges both config sources transparently

## Dynamic Subscription Server

| Mode | URL |
|------|-----|
| HTTPS | `https://sub.yourdomain.com:2096/sub?token=xxx` |
| HTTP | `http://IP:PORT/TOKEN` |

64-bit random token, self-signed TLS, CF proxy ports: 2096/8443/2053/2083/2087/443.

## Multi-User Traffic Quotas

Press `u`:

```text
  name     state  reset   used        quota       token
  default  on     -       1.96 GB     unlimited   67e66c...
  f1       on     ↑10     987.51 MB   200.00 GB   e87385...
```

- **Xray**: gRPC StatsService per UUID
- **Sing-box** (TUIC/AnyTLS/Reality/SS): iptables dedicated port + `argov-sb-stats` daemon (60s delta tracking)
- HY2 excluded from per-user (port hopping compatibility)
- Monthly reset (days 1–28), auto-disable on quota breach

## Certificate Pinning (pinSHA256)

Auto-calculated on HY2 creation. No domain needed.

```
hysteria2://pass@ip:8443?sni=...&insecure=1&pinSHA256=BA:88:45:...&allowInsecure=0
```

Self-signed cert + SHA256 fingerprint = CA-level security.

## Aggregated Subscription

Press `g` → merge all VPS/airport sources into one URL. ≤10s sync, `sort -u` dedup.

## Landing Relay / WARP Routing

`r` → route through clean-IP VPS (SS/VL/VM/TJ exit). `w` → one-click fscarmen WARP with domain-aware split.

## Architecture

```
Client → CF Edge → Argo Tunnel → :8080 Xray fallback → VLESS-WS / VMess-WS
Direct:  Reality · Hysteria2 (BBR/Brutal, port hopping) · TUIC · AnyTLS · SS
Routing: warp-out / v6-direct / relay-out
Dual:    Xray (Argo+gRPC) ｜ Sing-box (iptables per-user stats)
Sub/Agg: sub_gen.sh / agg_gen.sh → merge → base64 → URL
```

## Client Compatibility

`v2rayN v7+` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Karing`

## License

[MIT](LICENSE)
