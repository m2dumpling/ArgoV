# ArgoV

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="420">
</p>

<p align="center">
  <strong>A dual-core Xray + Sing-box management script for self-hosted servers</strong><br>
  One command to deploy, one panel to operate, one subscription to deliver every node
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Runtime-Bash-121011?style=flat-square&logo=gnu-bash" alt="Bash">
  <img src="https://img.shields.io/badge/Cores-Xray%20%2B%20sing--box-0078D7?style=flat-square" alt="Dual core">
  <img src="https://img.shields.io/badge/Protocols-7-8B5CF6?style=flat-square" alt="Seven protocols">
  <img src="https://img.shields.io/badge/Linux-systemd%20%2B%20OpenRC-6E56CF?style=flat-square&logo=linux" alt="Linux init systems">
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#at-a-glance">At a Glance</a> ·
  <a href="#protocols-and-cores">Protocols & Cores</a> ·
  <a href="#operations">Operations</a> ·
  <a href="README_CN.md">简体中文</a>
</p>

---

ArgoV combines Xray, Cloudflare Tunnel (Argo), and Sing-box behind one interactive operations script. It can run an Argo deployment with no public VLESS/VMess listening ports, or a direct-only server for Reality, Hysteria2, TUIC, AnyTLS, and Shadowsocks. Protocols, users, quotas, subscriptions, WARP, and relays remain manageable after the initial install.

> ArgoV is for Linux VPS owners who want to manage several inbound protocols without maintaining several configuration files. Deploy only on networks and servers you are authorized to use, and assess applicable laws, provider terms, and network policies yourself.

## Quick Start

Run this as `root`, or from an account with `sudo` access:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

The installer walks through node name, optional Argo, subscriptions, direct protocols, and the optional Sing-box core. When it finishes, open the panel with:

```bash
ag
```

You can also preset a node name:

```bash
NODE_NAME=Tokyo bash <(curl -fsSL https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

### Before You Start

| Item | Notes |
| --- | --- |
| OS | Debian, Ubuntu, CentOS/RHEL-family, and Alpine Linux; systemd and OpenRC are supported |
| Privilege | Root is recommended. The script installs runtime tools such as `curl`, `jq`, `openssl`, and `unzip` |
| Ports | Argo does not expose its internal VLESS/VMess ports. Direct protocols require matching TCP/UDP firewall and security-group rules |
| Domain | A temporary Argo tunnel needs no domain. A named tunnel and HTTPS subscription need your domain and/or Cloudflare token |
| Certificates | HY2 and TUIC can use generated self-signed certificates; subscription links include certificate pins where available |

## At a Glance

| Area | What ArgoV provides |
| --- | --- |
| Dual-core control | Xray handles Argo, Reality, HY2, and SS. Optional Sing-box adds TUIC, AnyTLS, and its own direct inbounds |
| Argo tunnel | VLESS / VMess WebSocket over Cloudflare Tunnel, using either temporary `trycloudflare.com` or a token-based named tunnel |
| Direct protocols | VLESS Reality, Hysteria2, and Shadowsocks, with post-install add/edit/delete/link actions |
| Sing-box | Hysteria2, TUIC, AnyTLS Reality, VLESS Reality, and Shadowsocks, plus install and update actions |
| Users and quotas | Per-user UUID, subscription token, quota, and reset day; over-quota users are automatically disabled and restored on their monthly reset |
| Dynamic subscriptions | One URL emits the current user's available nodes; Base64 links and Clash/Mihomo YAML are supported |
| Certificate pinning | HY2 links can carry `pinSHA256` for self-signed certificate pinning |
| Port hopping | Xray HY2 and Sing-box HY2 support UDP port hopping with iptables-managed rules |
| Landing relay | Chain Xray egress through SS, VLESS, VMess, or Trojan relay links |
| WARP routing | Send selected domains through WARP SOCKS5, IPv6 direct, or smart split routing |
| Subscription aggregation | Merge, de-duplicate, and serve external subscription sources alongside local nodes |
| Safe state handling | Checked downloads, atomic state writes, file locking, and migration from older ArgoX state |

## Protocols and Cores

| Protocol | Core | Typical use | Notes |
| --- | --- | --- | --- |
| VLESS + Argo | Xray | Cloudflare Tunnel with no public proxy port | WebSocket; Argo is optional |
| VMess + Argo | Xray | Compatibility with existing VMess clients | WebSocket; newer Xray builds warn that VMess is deprecated |
| VLESS Reality | Xray / Sing-box | Direct TLS-shaped endpoint | Vision, SNI, Short ID, and x25519 keys |
| Hysteria2 | Xray / Sing-box | UDP/QUIC direct endpoint | Certificate pinning and port hopping; Sing-box writes Brutal bandwidth values |
| TUIC | Sing-box | QUIC direct endpoint | Available after enabling Sing-box |
| AnyTLS Reality | Sing-box | Reality-based direct endpoint | Available after enabling Sing-box |
| Shadowsocks | Xray / Sing-box | Traditional AEAD / SS2022 endpoint | TCP/UDP; newer Xray builds warn that it is deprecated |

```text
                         ArgoV
                           │
          ┌────────────────┴────────────────┐
          │                                 │
       Xray                           Sing-box (optional)
          │                                 │
 Argo · Reality · HY2 · SS      HY2 · TUIC · AnyTLS · Reality · SS
          │                                 │
          └───────────────┬─────────────────┘
                          │
             Users, quotas, subscriptions, routing, operations
```

### Current Core Compatibility

Generated configurations follow current Xray and sing-box conventions: Xray Reality server inbounds use `target`, and Sing-box HY2 Brutal writes `up_mbps` / `down_mbps`. Argo WebSocket, VMess, and Shadowsocks remain available to avoid breaking existing clients; newer Xray releases may warn about their deprecation. Moving to XHTTP or VLESS Encryption changes client connection details, so it is not forced during an update.

## Installation Flow

```text
Node name
  │
  ├─ Enable Argo ── CDN / UUID / temporary or named tunnel / internal ports
  │
  └─ Skip Argo ─── Deploy direct Reality / HY2 / SS endpoints
                         │
                         ├─ Subscription server (HTTP or HTTPS)
                         └─ Optional Sing-box (HY2 / TUIC / AnyTLS / Reality / SS)
```

Argo is not required. If you skip it at install time, enable it later from `a → a0`. Reinstalling preserves user state and configured optional inbounds.

## Management Panel

Run `ag` to enter the panel.

| Entry | Action |
| --- | --- |
| `1` | View links, subscription address, and QR code |
| `2` / `3` | Switch CDN; edit basic settings and subscription settings |
| `a` | Manage Xray protocols, enable Argo, and add custom links |
| `u` | Add/enable/disable users; set quotas, reset days, and subscription tokens |
| `s` | Install or update Sing-box; manage its protocols and links |
| `w` | Configure WARP SOCKS5 / IPv6 domain routing |
| `r` | Configure or clear a landing relay |
| `g` | Manage external subscription sources |
| `4` / `5` / `6` | Start, stop, or restart services |
| `7` / `8` / `x` | Reinstall while keeping data; update the script; update Xray |

## Users, Quotas, and Subscriptions

User state is stored in `/etc/xray/argov_users.json`. Each user can have an independent UUID, subscription token, quota, consumption counters, and monthly reset day.

| Path | Accounting method | Quota behavior |
| --- | --- | --- |
| Xray inbounds | Xray StatsService gRPC, per-user email and both traffic directions | Over-quota users are removed from Xray client lists |
| Sing-box dedicated-port inbounds | iptables port counters, periodically accumulated | Over-quota users no longer receive active per-user inbounds |
| HY2 hopping ports | No individual HY2 inbound for non-default users | Current limitation of shared port-hopping mode |

| Mode | Example |
| --- | --- |
| HTTPS domain | `https://sub.example.com:2096/sub?token=...` |
| HTTP IP | `http://SERVER_IP:PORT/sub?token=...` |

The default user receives shared nodes and custom links. Quota users receive only their available nodes and dedicated Sing-box ports.

## Routing

### WARP Domain Routing

- **SOCKS5**: list traffic is sent through local WARP SOCKS5, normally `127.0.0.1:40000`.
- **IPv6**: list traffic is sent through the IPv6 direct egress.
- **Smart**: Google-family domains use IPv6 while YouTube-family domains use WARP SOCKS5.

### Landing Relay and Subscription Aggregation

Landing relay sends traffic received by both Xray and Sing-box proxy inbounds to another SS, VLESS, VMess, or Trojan node. “All” covers client traffic received by either proxy core, not traffic initiated by the server itself. When both cores offer the same protocol, Sing-box subscription names include a core label to make the endpoints distinguishable. Subscription aggregation merges multiple VPS or external feeds, removes duplicates, and serves the result through the local subscription endpoint.

## Operations

```bash
# Open the panel
ag

# Check services on systemd systems
systemctl status xray sing-box

# Or on Alpine / OpenRC
rc-service xray status
```

Important files:

| File | Purpose |
| --- | --- |
| `/etc/xray/argov.conf` | Persisted ArgoV options and secret references |
| `/etc/xray/config.json` | Xray runtime configuration |
| `/etc/xray/argov_users.json` | Users, tokens, quotas, and traffic state |
| `/etc/sing-box/config.json` | Sing-box runtime configuration |
| `/etc/xray/argo.log` | Temporary Argo tunnel URL log |

### Troubleshooting services

If a node or subscription stops working, check the service for the feature you enabled before reinstalling. On systemd systems, inspect the Xray service and recent logs:

```bash
systemctl status xray
journalctl -u xray -n 50 --no-pager
```

For Argo tunnel issues, check `argov-tunnel` and the tunnel URL log. On Alpine / OpenRC, use `rc-service` for service status:

```bash
systemctl status argov-tunnel
journalctl -u argov-tunnel -n 50 --no-pager
tail -n 50 /etc/xray/argo.log

# Alpine / OpenRC equivalents for service status
rc-service xray status
rc-service argov-tunnel status
```

`argov-tunnel` is absent when Argo is disabled. The `sing-box` and `argov-sub` services are present only when those optional features are enabled. Redact tokens, UUIDs, and domains before sharing logs in an issue.

## Clients and Notes

Common link formats work with `v2rayN`, Nekoray, Shadowrocket, sing-box, Mihomo / Clash Verge, Karing, and similar applications, subject to each client's core version and protocol support.

- Open matching cloud security-group and host firewall ports for direct Reality, HY2, TUIC, AnyTLS, and SS endpoints.
- Self-signed HY2/TUIC certificates require client-side insecure acceptance; prefer the `pinSHA256` value in subscription links for certificate pinning.
- Sing-box HY2, TUIC, and AnyTLS rely on features included in official release builds. Prefer updating through the panel rather than replacing the binary with a minimal build.
- The repository currently does not include a `LICENSE` file. Confirm authorization and compliance requirements before reuse, distribution, or deployment.

## Contributing

Issues and pull requests are welcome. From the repository root, run the complete check before submitting a change (Bash and Python are required):

```bash
bash tests/argov_static_tests.sh argov.sh
```

This checks Bash syntax, all five Python suites (including relay configuration), and the tunnel service log settings.
