# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a>
</p>

---

An ultra-lightweight Cloudflare Argo Tunnel management script — **VLESS + VMess + Shadowsocks** multi-protocol, WebSocket + TLS.

**ArgoX-Mini** installs only the essentials: Xray-core + cloudflared. No Nginx, no Caddy. Argo inbounds listen on `127.0.0.1` only — zero public ports. Optional VLESS Reality and Shadowsocks direct protocols.

## ✨ Features

- **Multi-Protocol** — VLESS + VMess Argo (always). Optional: SS + Argo / VLESS Reality / SS Direct
- **Interactive Install Wizard** — 7 steps with sensible defaults, just press Enter
- **One-Click Import Links** — All protocol links + QR printed after install, with custom node name suffixes (`#Tokyo-VLESS`)
- **Node Management (Add/Edit/Delete)** — Menu `a`, incremental operations, no full reinstall
- **Edit Mode** — Change cipher, password, port, SNI, or regenerate Reality keys — press Enter to keep current value
- **SS Full Cipher Suite** — 7 methods: AEAD classics + SS2022 (`2022-blake3-aes-128/256-gcm`, `2022-blake3-chacha20-poly1305`)
- **VLESS Reality** — XTLS Vision + Reality, 8 destination SNIs, auto x25519 key pairs
- **Zero Public Exposure (Argo)** — `127.0.0.1` only, immune to active scans
- **Fixed Argo Tunnel** — CF Zero Trust Token, temp/fixed switch anytime
- **Persistent Config** — `/etc/xray/argox.conf`, survives reinstall
- **Auto-Start on Reboot** — `systemctl enable`, services survive VPS restart
- **13 CDN Domains** — Carrier-optimized
- **Port Conflict Auto-Resolution** — Finds free ports automatically
- **Env Var Overrides** — Non-interactive deployment

## 🚀 Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

Non-interactive:

```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe CDN_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🛠️ Management

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  Management Panel                ║
║     VL-Argo VM-Argo SS-Argo Reality SS-Dir      ║
╚══════════════════════════════════════════════════╝

  Name : Tokyo    Xray: ● up    Argo: ● up    CDN : cdn.xxx:443

── Nodes ──
  1. Show links    2. Change CDN    3. Config    a. Manage Nodes
── Services ──
  4. Start    5. Stop    6. Restart
── System ──
  7. Reinstall    8. Update    9. Uninstall    0. Exit
```

### Menu `a` — Node Management

```
╔══════════════════════════════════════════╗
║         Manage Nodes                    ║
╚══════════════════════════════════════════╝

  ── Installed · Editable ──
  e1. Shadowsocks + Argo  aes-256-gcm  port 8083

  ── Available ──
  a1. Shadowsocks Direct

  d. Delete    0. Back
```

- **`e1`** — Edit: step through cipher → password → port, show current value, Enter to keep. Reality: also SNI + key regeneration.
- **`a1`** — Add: choose cipher → set password → set port → confirm → auto-inject + restart → show link.
- **`d`** — Delete: pick node → confirm → remove inbound + cleanup fallback.

## 🏗 Architecture

```
Client → CF Edge (TLS:CDN_PORT) → Argo Tunnel → localhost:ARGO_PORT
                                                    Xray fallback
                                                 ├── /vless-argo → VLESS+WS
                                                 ├── /vmess-argo → VMess+WS
                                                 └── /ss-argo    → SS+WS (opt)
Direct (opt):
  :<rand> VLESS+Reality  (0.0.0.0, x25519)
  :<rand> SS Direct      (0.0.0.0)
```

## 💻 Client Config

Copy links from terminal → import to clipboard.

| Protocol | Format |
|----------|--------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#Name-VLESS` |
| VMess Argo | `vmess://base64(JSON)#Name-VMess` |
| SS Argo | `ss://base64(method:pass)@cdn:port#Name-SS-Argo` |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#Name-Reality` |
| SS Direct | `ss://base64(method:pass)@ip:port#Name-SS-Direct` |

Clients: v2rayN · Nekoray · Nekobox · Shadowrocket · Sing-box · V2Box · Karing · Clash Meta

## 📄 License

MIT License
