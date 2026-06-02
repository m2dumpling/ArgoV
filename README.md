# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a>
</p>

---

An ultra-lightweight Cloudflare Argo Tunnel management script — **VLESS + VMess + Shadowsocks + VLESS Reality**, with built-in **WARP SOCKS5 / IPv6 domain routing**.

**ArgoX-Mini** installs only the essentials: Xray-core + cloudflared. No Nginx, no Caddy. Argo inbounds listen on `127.0.0.1` only — zero public ports. Optional VLESS Reality and Shadowsocks direct protocols. Alpine Linux fully supported.

## ✨ Features

**Core**
- VLESS + VMess Argo tunnel (always installed). Optional: Shadowsocks, VLESS Reality
- Interactive 7-step install wizard with sensible defaults — just press Enter
- `vless://` / `vmess://` / `ss://` one-click import links + QR code
- Custom node names with protocol suffixes (`#Tokyo-VLESS`, `#Tokyo-Reality`)

**Node Management**
- Menu `a` — add, edit, or delete any protocol node without full reinstall
- Argo VLESS/VMess nodes editable (port, path, auto-sync fallback router)
- SS: 7 ciphers (AEAD + SS2022), editable method/password/port
- Reality: 8 destination SNIs, editable SNI/port/regenerate x25519 keys

**WARP Domain Routing** — Menu `w`
- One-click install fscarmen WARP (SOCKS5 on port 40000, or IPv6 WireGuard)
- Add custom domains (comma-separated), or inject Google/YouTube defaults
- Switch routing mode: SOCKS5 all / IPv6 all / Smart Split (Google→IPv6 + YouTube→SOCKS5)
- Python3 safe JSON rewrite with auto-validation and rollback on failure

**Security & Compatibility**
- Zero public exposure (Argo mode) — `127.0.0.1` only, immune to active scans
- Fixed Argo tunnel support (CF Zero Trust Token), temp/fixed switch anytime
- Persistent config (`/etc/xray/argox.conf`), survives reinstall
- Auto-start on reboot (`systemctl enable` / `rc-update add`)
- Alpine Linux support (openrc services, apk, netstat port detection)
- Service isolated as `argox-tunnel` — coexists with existing cloudflared tunnels
- 13 pre-configured CDN domains (carrier-optimized)
- Port conflict auto-resolution
- Env var overrides (`NODE_NAME=Tokyo CDN_PORT=8443 bash <(curl ...)`)

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
║     VL-Argo VM-Argo SS Reality                  ║
╚══════════════════════════════════════════════════╝

  Name : Tokyo    Xray: ● up    Argo: ● up    CDN : cdn.xxx:443

── Nodes ──
  1. Show links    2. Change CDN    3. Config    a. Manage Nodes
── Services ──
  4. Start    5. Stop    6. Restart
── System ──
  7. Reinstall    8. Update    9. Uninstall    0. Exit    w. WARP (SOCKS5 / IPv6)
```

### Menu `a` — Node Management

```
╔══════════════════════════════════════════╗
║         Manage Nodes                    ║
╚══════════════════════════════════════════╝

  ── Argo Tunnel ──
  e1. VLESS + Argo    port 8081   path /vless-argo
  e2. VMess + Argo    port 8082   path /vmess-argo

  ── Optional · Editable ──
  e3. VLESS Reality   www.amazon.com   port 43210
  e4. Shadowsocks      aes-256-gcm       port 8388

  ── Available ──
  a1. VLESS Reality    a2. Shadowsocks

  d. Delete    0. Back
```

- **`e1/e2`** — Edit Argo node: port, path (auto-updates fallback router)
- **`e3/e4`** — Edit optional node: cipher, password, port, SNI, regenerate keys
- **`a1/a2`** — Add new protocol (step-by-step interactive config)
- **`d`** — Delete with confirmation

### Menu `w` — WARP Routing

```
╔══════════════════════════════════════════╗
║     WARP SOCKS5 / IPv6 Config           ║
╚══════════════════════════════════════════╝

  1. Inject Google/YouTube default domains
  2. Add custom domains (comma-separated)
  3. Remove domains
  4. View / clear domain list
  5. Apply & restart Xray
  6. Switch routing mode (SOCKS5 ↔ IPv6 ↔ Smart)
```

Switch mode options:
- **SOCKS5** — all domains → WARP SOCKS5 (127.0.0.1:40000)
- **IPv6** — all domains → WARP IPv6 direct
- **Smart Split** — Google → IPv6 (no captcha) + YouTube → SOCKS5 (no popup)

## 🏗 Architecture

```
Client → CF Edge (TLS) → Argo Tunnel → localhost:8080 Xray fallback
                                           ├── /vless-argo → VLESS+WS
                                           └── /vmess-argo → VMess+WS

Direct (opt):
  VLESS+Reality (public port, x25519 keys)
  Shadowsocks (public port)

WARP Routing (opt):
  Xray routing rules → warp-out (SOCKS5 :40000) or v6-direct (IPv6)
  fscarmen WARP provides the transport layer
```

## 💻 Client Config

Copy links from terminal → import to clipboard.

| Protocol | Link Format |
|----------|-------------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#Name-VLESS` |
| VMess Argo | `vmess://base64(JSON)#Name-VMess` |
| SS | `ss://base64(method:pass)@ip:port#Name-SS` |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#Name-Reality` |

Clients: v2rayN · Nekoray · Nekobox · Shadowrocket · Sing-box · V2Box · Karing · Clash Meta

## 📄 License

MIT License
