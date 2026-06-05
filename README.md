# ArgoX-Mini

An ultra-lightweight Cloudflare Argo Tunnel management script — **VLESS + VMess + Shadowsocks + VLESS Reality**, with built-in **WARP domain routing** and **subscription server**.

Installs only the essentials: Xray-core + cloudflared. No Nginx, no Caddy. Argo inbounds listen on `127.0.0.1` only — zero public ports. Full Debian / Ubuntu / CentOS / Alpine support.

## ✨ Features

**Core**
- VLESS + VMess Argo tunnel (always installed). Optional: Shadowsocks, VLESS Reality
- 8-step interactive install wizard with automatic system detection
- `vless://` / `vmess://` / `ss://` one-click import links + subscription QR code

**Subscription Server** — auto-recovery after reboot, zero SSH
- Dual mode: `https://yourdomain:port/sub?token=xxx` or `http://IP:port/TOKEN`
- Self-signed cert for HTTPS (CF Full SSL compatible), CF port picker (2096/8443/2053 etc.)
- Random token auth, Python3 15-line HTTP server
- Fresh links generated on every request — config changes sync instantly

**Node Management** — Menu `a`
- Add, edit, delete any protocol without full reinstall
- Argo VLESS/VMess: editable port, path, auto-sync fallback router
- Shadowsocks: 7 ciphers (AEAD + SS2022), editable method/password/port
- Reality: 8 destination SNIs, editable SNI/port/shortId/fingerprint/keys

**WARP Domain Routing** — Menu `w`
- One-click fscarmen WARP (SOCKS5 :40000 / IPv6 WireGuard)
- Custom domain lists or inject Google/YouTube defaults
- Three modes: All SOCKS5 / All IPv6 / Smart Split (Google→IPv6 + YouTube→SOCKS5)
- Python3 safe JSON rewrite with auto-rollback on failure

**Security & Compatibility**
- Zero public exposure (Argo mode), `127.0.0.1` only, immune to active scans
- Fixed Argo tunnel + temporary tunnel, switch anytime
- Persistent config `/etc/xray/argox.conf`, survives reinstall
- Auto-start on boot, tunnel crash auto-retry (Alpine 30s network wait)
- Full Alpine Linux support (openrc / apk / init.d)
- Service isolated as `argox-tunnel` — coexists with existing tunnels
- 13 pre-configured CDN domains, auto port conflict resolution
- Env var deployment

## 🚀 Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

Non-interactive:
```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
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

  Name : Tokyo    Xray: ● up    Argo: ● up

── Nodes ──
  1. Show links    2. Change CDN    3. Config    a. Manage Nodes
── Services ──
  4. Start    5. Stop    6. Restart/Recover
── System ──
  7. Reinstall    8. Update    9. Uninstall    0. Exit    w. WARP

─── Install Wizard ───
① Node name → ② CDN → ③ Client port → ④ UUID → ⑤ Tunnel type
→ ⑥ Internal ports → ⑦ Sub domain (optional, CF port picker) → ⑧ Extra protocols
```

## 💻 Client Config

Copy links from terminal → import to clipboard, or use subscription URL for one-click import.

| Protocol | Format |
|----------|--------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#Name-VLESS` |
| VMess Argo | `vmess://base64(JSON)#Name-VMess` |
| SS | `ss://base64(method:pass)@ip:port#Name-SS` |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#Name-Reality` |

Clients: v2rayN · Nekoray · Shadowrocket · Sing-box · Clash Meta

## 📄 License

MIT License
