# 🌐 ArgoV — Dual-Core Proxy

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>One-click · Xray + Sing-box · Optional Argo</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray_v1.8+_|_Sing--box_v1.10+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-7_Protocols-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** is a dual-core zero-trust proxy panel. Xray-core powers the Argo tunnel (optional), Sing-box extends to TUIC & AnyTLS Reality. Supports 7 protocols: VLESS / VMess / Reality / Hysteria2 / TUIC / AnyTLS / SS. Built-in per-user quotas, certificate pinning, port hopping, landing relay, aggregated subscriptions, and WARP routing. Single Bash script.

[Quick Start](#quick-start) · [Panel](#management-panel) · [Install Flow](#install-flow) · [Dual-Core](#dual-core) · [Quotas](#multi-user-traffic-quotas) · [中文版](README_CN.md)

---

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

After install, type `ag` for the panel.

```bash
NODE_NAME=Tokyo bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## Install Flow

```text
 ① Node name      → LAX
 ② Argo tunnel?   → 1. Enable (VLESS/VMess over CF)  /  2. Skip
    ├─ Enable: ③ CDN → ④ Port → ⑤ UUID → ⑥ Mode → ⑦ Internal ports
    └─ Skip: straight to ⑧ Sub domain → ⑨ Extra protocols → ⑩ Sing-box
```

**Argo is optional** — skip it to deploy Reality/HY2/SS directly. Enable later via `a → a0`.

## Management Panel

```text
 Name: Tokyo    Xray: ● running    Sing-box: ● running    Argo: ● running
 UUID: 45c7acf6...    Domain: xxx.trycloudflare.com    Traffic: ↓12 GB ↑156 GB

 ──────────────── ✦ Core ✦ ────────────────
  1. 🔗 View links        2. ☁️  Switch CDN
  3. ⚙️  Edit config        a. 🧩 Manage protocols
  u. 👥 Users & quotas

 ──────────────── ✦ Routing ✦ ────────────────
  w. 🌐 WARP routing      r. 🔀 Landing relay
  g. 📡 Aggregated sub     s. 🔧 Sing-box manage

 ──────────────── ✦ Ops ✦ ────────────────
  4. ▶️  Start  5. ⏹️  Stop  6. 🔁 Restart Argo
  7. 🔄 Reinstall  8. 🆙 Update  9. 🗑️  Uninstall  x. 🚀 Update Xray
```

## Core Features

| Category | Details |
|----------|---------|
| **Argo Tunnel** (optional) | VLESS + VMess over CF. `127.0.0.1` only. Skip during install, enable later via `a → a0` |
| **Dual-Core** | Xray for Argo; Sing-box for TUIC, AnyTLS Reality. Unified panel + merged subscription |
| **VLESS Reality** | XTLS Vision + Reality. Custom SNI / shortId / fingerprint / x25519 keys |
| **Hysteria2** | BBR / Brutal congestion. Port hopping (custom range, fixed/random interval). Certificate pinning (pinSHA256) |
| **TUIC / AnyTLS** | Sing-box native. TUIC QUIC + BBR; AnyTLS Reality stealth |
| **Shadowsocks** | AEAD + SS2022, TCP/UDP |
| **Subscription Server** | Python3 HTTP threaded, 10s refresh, self-signed TLS. base64 / Clash YAML output |
| **User Quotas** | Per-user UUID+Token. Xray via gRPC, Sing-box via iptables per-port. Monthly auto-reset |
| **Certificate Pinning** | Auto SHA256 fingerprint on HY2 creation. `pinSHA256=` in subscription links |
| **Aggregated Sub** | Merge all VPS/airport subs. ≤10s sync, `sort -u` dedup |
| **Landing Relay** | SS / VLESS / VMess / Trojan exit. AsIs DNS, zero leak |
| **WARP Routing** | SOCKS5 :40000 + IPv6. Smart split |
| **System** | Debian / Ubuntu / CentOS / Alpine. systemd + OpenRC |

## Dual-Core

```
Xray-core (always)               Sing-box (optional: s → s1)
├ VLESS Argo  :8080              ├ Hysteria2   :8443 (hopping + pinSHA256)
├ VMess Argo  :8081              ├ TUIC        :8444
├ Reality     :443               ├ AnyTLS      :8445
├ Hysteria2   :23333             ├ VLESS Reality :8446
└ Shadowsocks :8388              └ Shadowsocks :8447
└ gRPC stats                     └ iptables per-port stats
```

## Dynamic Subscription Server

| Mode | URL |
|------|-----|
| HTTPS | `https://sub.domain:2096/sub?token=xxx` |
| HTTP | `http://IP:PORT/TOKEN` |

## Multi-User Traffic Quotas

Press `u`:

```text
  name     state  reset   used        quota       token
  default  on     -       1.96 GB     unlimited   67e66c...
  f1       on     ↑10     987 MB      200 GB      e87385...
```

- **Xray**: gRPC StatsService per UUID
- **Sing-box** (TUIC/AnyTLS/Reality/SS): iptables dedicated port + daemon (60s delta tracking)
- HY2 excluded (port hopping compatibility)
- Monthly reset (days 1–28), auto-disable on quota breach

## Certificate Pinning

Auto SHA256 fingerprint on HY2 create/edit. Subscription link: `&pinSHA256=BA:88:45:...&allowInsecure=0`. No domain required.

## Aggregated Subscription

Press `g` to merge all sources. `sort -u` dedup, ≤10s sync.

## Client Compatibility

`v2rayN v7+` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Karing`

## License

[MIT](LICENSE)
