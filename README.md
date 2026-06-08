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
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** is a sleek, hardcore, and highly professional zero-trust proxy management panel. Built on top of Cloudflare Argo Tunnel, it encapsulates VLESS and VMess traffic deep inside Cloudflare's edge network—requiring absolutely no domains and keeping your server's firewall completely locked down.

Beyond basic tunneling, ArgoV is supercharged with native **VLESS Reality** and **Shadowsocks** protocols, alongside unprecedented routing capabilities: **Server-Side Landing Relay**, **Smart WARP Split-routing**, **Dynamic Subscriptions**, and **Seamless Protocol Aggregation** for external nodes. All powered by a highly-optimized, dependency-free Bash architecture.

[Quick Start](#🚀-quick-start) · [Features](#💎-core-features) · [Dynamic Subscriptions](#📡-dynamic-subscription-server) · [Landing Relay](#⛓️-landing-relay-server-side-proxy-chaining) · [Panel UI](#💻-management-panel) · [中文版](README_CN.md)

---

## 🚀 Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

> **🔥 Pro Tip**: After installation, simply type `ag` or `argov` in your terminal to instantly launch the management panel.

Non-interactive installation (for CI/CD pipelines):
```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## 💎 Core Features

| Dimension | Technical Detail |
|-----------|------------------|
| **Zero Public Exposure** | VLESS/VMess traffic is isolated inside WS + TLS tunnels. Xray listens solely on `127.0.0.1`, completely hiding the server's real IP and immunizing it against active probing. |
| **Direct Protocols** | Native support for `VLESS-Reality` (XTLS Vision) and `Shadowsocks` (SS2022 & AEAD). Equipped with advanced QUIC/TLS deep sniffing. |
| **Dynamic Sub** | Built-in lightweight Python3 HTTP server. Automatically updates and dispatches fresh tunnel domains to clients upon VPS reboot. |
| **Node Aggregation** | Import external node links (e.g., Hysteria2, Trojan, TUIC). ArgoV acts as a centralized gateway to push all nodes seamlessly into a unified client subscription. |
| **Chain Proxy (Relay)** | **Landing Relay Engine**. Transparently encrypts and routes server traffic to an overseas residential/clean VPS. Clients enjoy native IPs with zero configuration. |
| **Smart WARP Routing** | One-click WARP IPv6 / SOCKS5 mount. DNS-level outbound splitting: e.g., Google via IPv6, YouTube via SOCKS5, avoiding captchas and throttles. |
| **Lightweight Daemon** | Full compatibility with Debian, Ubuntu, CentOS, and Alpine. Native support for both `systemd` and `openrc`. Extremely lightweight process isolation. |

## 💻 Management Panel

Just type `ag` to take full control of your network topology:

```text
╔══════════════════════════════════════════════════╗
║     ArgoV  Management Panel                      ║
║     VL-Argo VM-Argo SS Reality                   ║
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

## 📡 Dynamic Subscription Server

Never lose connection, even if Cloudflare resets your Argo domain or your VPS reboots.
**No SSH required** to retrieve new links. The subscription server pushes the latest tunnel configurations in real-time.

- **Hardware-Level Security**: 64-bit random cryptographically secure token auth.
- **High Compatibility**: Supports Self-signed TLS (Cloudflare Full SSL compatible) or raw HTTP dispatch.
- **Port Freedom**: Integrates with any Cloudflare proxy port (2096, 8443, 2053, 443, etc.).

## 🔗 Advanced Node Matrix

Press `a` to enter the **Protocol Matrix**. ArgoV can serve as the ultimate "Gateway Subscription Center" for your entire node ecosystem.

```text
  ── Argo Tunnel ──
  e1. VLESS + Argo    port 8081    /vless-argo
  e2. VMess + Argo    port 8082    /vmess-argo

  ── Optional Direct ──
  e3. VLESS Reality   amazon.com   :43210
  e4. Shadowsocks     aes-256-gcm  :8388

  ── Custom Nodes (Aggregated) ──
  2 custom links
  c1. Add    c2. View / delete
```

> 💡 **Hysteria2 Best Practice**: For bleeding-edge UDP performance, we recommend deploying Hysteria2 via a dedicated script, then pasting its share link into ArgoV via `c1`. ArgoV will seamlessly merge it into your unified subscription.

## ⛓️ Landing Relay (Server-Side Proxy Chaining)

Say goodbye to convoluted client-side chain configurations. ArgoV provides **Transparent Server-Side Relays**.

*Press `r` in the panel to configure.*

- Paste any valid `ss://`, `vless://`, `vmess://`, or `trojan://` link to act as your exit node.
- **Zero DNS Leak**: Uses `domainStrategy: AsIs`. DNS queries are securely encapsulated and resolved strictly on the landing node.
- **Policy Routing**: Choose between "Global Relay" or "Split Relay" (routing only specific streaming domains through the landing node).
- Coexists flawlessly with the WARP dual-routing engine.

## 🗺️ Architecture Topology

```text
Client → CF Edge (TLS) → Argo Tunnel → localhost:8080 Xray fallback
                                           ├── /vless-argo → VLESS+WS :8081
                                           └── /vmess-argo → VMess+WS :8082

Direct (Optional) : VLESS+Reality (Stealth)  ·  Shadowsocks (Stream Cipher)

WARP Stack : Xray routing rules → warp-out (SOCKS5 :40000) / v6-direct (IPv6)

Relay Chain: Xray routing rules → relay-out (SS/VL/VM/TJ) → Landing VPS (Clean IP) → Internet
```

## 📝 Client Compatibility

ArgoV perfectly supports all modern Xray-core / Sing-box based clients:
`v2rayN` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Clash Meta` · `V2Box` · `Karing`

## ⚖️ License
[MIT License](LICENSE).
