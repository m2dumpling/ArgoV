# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a> |
  <a href="#-features">Features</a> |
  <a href="#-one-click-installation">Installation</a> |
  <a href="#-setup-wizard">Wizard</a> |
  <a href="#-management-panel">Menu</a>
</p>

---

An ultra-lightweight Cloudflare Argo Tunnel management script — **VLESS + VMess + Shadowsocks** multi-protocol, WebSocket + TLS.

**ArgoX-Mini** installs only the essentials: Xray-core + cloudflared. No Nginx, no Caddy. All Argo inbounds bind strictly to `127.0.0.1` — zero proxy ports on the public internet. Optional VLESS Reality and Shadowsocks direct protocols.

## ✨ Features

- **Multi-Protocol** — VLESS + VMess Argo (always installed). Optional: Shadowsocks + Argo, VLESS Reality direct, Shadowsocks direct.
- **Interactive Setup Wizard** — 7 steps: name → CDN → port → UUID → tunnel type → internal ports → optional protocols. Sensible defaults throughout.
- **One-Click Import Links** — All protocol links + QR printed after install. Custom node names with protocol suffixes (`#Tokyo-VLESS`, `#Tokyo-Reality`).
- **Shadowsocks Full Cipher Suite** — 7 methods: AEAD classics + SS2022 (`2022-blake3-aes-128-gcm`, `2022-blake3-aes-256-gcm`, `2022-blake3-chacha20-poly1305`).
- **VLESS Reality Direct** — XTLS Vision + Reality with 8 destination SNIs, auto-generated x25519 key pairs.
- **Zero Public Exposure (Argo)** — Xray listens on `127.0.0.1` only. Immune to active scans.
- **Fixed Argo Tunnel** — CF Zero Trust Token support. Switch between temp/fixed anytime.
- **Persistent Config** — `/etc/xray/argox.conf` saves all settings. Reinstall preserves everything.
- **13 Pre-configured CDN Domains** — Carrier-optimized (China Mobile / Unicom / Telecom).
- **Auto Port Conflict Detection** — Finds free ports if defaults are in use.
- **Env Var Overrides** — `NODE_NAME=Tokyo SS_METHOD=2022-blake3-aes-256-gcm bash <(curl ...)`.

## 🚀 One-Click Installation

Ubuntu / Debian / CentOS, root:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

First run auto-launches setup wizard. Press Enter through each step for defaults.

### Non-interactive

```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe CDN_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🎛 Setup Wizard

```
━━━ ① Node Name ━━━
  [ArgoX-Mini]: Tokyo-Aria

━━━ ② CDN Address ━━━
  1. Default   2. From list   3. Custom

━━━ ③ Client Port ━━━
  [443]: _

━━━ ④ UUID ━━━
  [auto-generate]: _

━━━ ⑤ Argo Tunnel Type ━━━
  1. Temp   2. Fixed Token

━━━ ⑥ Internal Ports ━━━
  Base [8080]: _

━━━ ⑦ Extra Protocols (optional) ━━━
  1. SS + Argo [○]    2. Reality [○]    3. SS Direct [○]
```

## 🛠️ Management Panel

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  Management Panel                ║
║     VL-Argo VM-Argo SS-Argo Reality SS-Dir      ║
╚══════════════════════════════════════════════════╝

  Name : Tokyo-Aria    Xray: ● up    Argo: ● up
  UUID : abcd1234-...   CDN : cdn.xxx:443

── Node ──  1. Show links  2. Change CDN  3. Config
── Service ──  4. Start  5. Stop  6. Restart
── System ──  7. Reinstall  8. Update  9. Uninstall
```

**Config sub-menu:** name · UUID · tunnel type · SS cipher · Reality SNI · protocols (reinstall) · show links · refresh domain

## 🏗 Architecture

```
Client → CF Edge (TLS:443) → Argo Tunnel → localhost:8080 Xray fallback
                                              ├── /vless-argo → :8081 VLESS+WS
                                              ├── /vmess-argo → :8082 VMess+WS
                                              └── /ss-argo    → :8083 SS+WS    (opt)
Direct (opt):
  :<rand> VLESS+Reality  (0.0.0.0)
  :<rand> SS Direct      (0.0.0.0)
```

## 💻 Client Config

Copy links from terminal → import to clipboard.

| Protocol | Link Format |
|----------|-------------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#Name-VLESS` |
| VMess Argo | `vmess://base64(JSON)#Name-VMess` |
| SS Argo | `ss://base64(method:pass)@cdn:port#Name-SS-Argo` |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#Name-Reality` |
| SS Direct | `ss://base64(method:pass)@ip:port#Name-SS-Direct` |

Clients: v2rayN, Nekoray, Nekobox, Shadowrocket, Sing-box, V2Box, Karing, Clash Meta.

## 📄 License

MIT License.
