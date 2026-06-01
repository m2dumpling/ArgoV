# ArgoX-Mini

<p align="center">
  <a href="./README_CN.md"><b>🇨🇳 中文版</b></a> |
  <a href="#-features">Features</a> |
  <a href="#-one-click-installation">Installation</a> |
  <a href="#-client-configuration">Configuration</a>
</p>

---

A lightweight, rock-solid, and ultra-pure one-click management script for Cloudflare Argo Tunnel (VMess + WebSocket).

Unlike other heavy injection scripts, **ArgoX-Mini** completely strips out unnecessary direct-connection protocols (like Reality, Hysteria2, XHTTP) and web server dependencies (such as Nginx or Caddy). It forces Xray to listen purely on localhost, ensuring your VPS leaves zero scanning footprint or exposed proxy ports to the public internet.

## ✨ Features

- **100% Pure Argo**: Zero bloat. No Caddy/Nginx dependency, no complex TLS certificates setup on your VPS.
- **Enhanced Stealth & Security**: Xray core binds strictly to `127.0.0.1`. No open ports exposed publicly, making it completely immune to active censorship scans.
- **Built-in Cloudflare IP Optimization**: Integrated with real-time optimized CDN domains categorized for China Mobile, China Unicom, and China Telecom routing.
- **Native CLI Management Control**: Automatically injects the `argo-v2` shortcut into your system environment for effortless dashboard wake-up.

## 🚀 One-Click Installation

Run the following command in your Linux VPS terminal (Supports root user on Ubuntu/Debian/CentOS):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🛠️ CLI Management Menu

Once installed, you can wake up the interactive colorful control panel at any time by simply typing:

```bash
argo-v2
```

**Menu Options:**

- **Show Connection Parameters**: Displays your real-time VMess credentials and dynamic Cloudflare Argo host info.
- **Start Services**: Bring Xray and Cloudflare Tunnel up.
- **Stop Services**: Completely freeze backend services and tear down the tunnel.
- **Restart Services**: Force restart and fetch a brand new random `.trycloudflare.com` domain.
- **Switch Optimized CDN Domains**: Instantly view or swap optimization domain endpoints.
- **Reinstall From Scratch**: Clean up residues and perform a fresh automated install.

## 💻 Client Configuration (e.g., v2rayN)

After deployment, select option **1** in the `argo-v2` menu to get your parameters. Open your client and create a new VMess server with the following settings:

| Parameter | Value | Note |
|---|---|---|
| **Address** | `cdn.31514926.xyz` | Or use the carrier-specific domains from Menu 5 |
| **Port** | `443` | Must be 443 for Cloudflare TLS edge |
| **User ID (UUID)** | `[Your Generated UUID]` | Copy from server terminal |
| **AlterId** | `0` | Default |
| **Security** | `none` | Inner encryption handled by outer TLS |
| **Network** | `ws` | WebSocket transport |
| **Host** | `xxxx.trycloudflare.com` | ⚠️ Crucial: Must match your terminal output |
| **Path** | `/vmess-argo` | Fixed routing path |
| **TLS** | `tls` | Enable transport security |
| **SNI** | `xxxx.trycloudflare.com` | Same as your Host domain |

## 📄 License

This project is licensed under the MIT License. Feel free to fork, modify, and share!
