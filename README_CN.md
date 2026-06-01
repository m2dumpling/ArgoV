# ArgoX-Mini 纯净版隧道管理面板

<p align="center">
  <a href="./README.md"><b>🌐 English</b></a>
</p>

---

一个极度精简、坚如磐石的 Cloudflare Argo 穿透隧道一键管理脚本 —— **VLESS + VMess 双协议**，WebSocket + TLS 传输。

与市面上全家桶脚本对比：xray-2go 打包 4 协议配 Caddy；ArgoX 打包 11 协议配 Nginx。**ArgoX-Mini** 只装 Argo 必需的组件：Xray-core + cloudflared。不装 Nginx、不装 Caddy、不要 Reality、不要 Hysteria2、不要 XHTTP。Xray 严格绑定 `127.0.0.1`，VPS 公网零代理端口暴露。

## ✨ 项目特点

- **VLESS + VMess 双协议** — 两种协议均可走 WS+TLS+Argo。VLESS 适合新客户端（v2rayN、小火箭、Sing-box），VMess 保证最大兼容性。
- **Xray Fallback 分流** — 单条 Argo 隧道入口（8080 端口）通过 Xray 内置 fallback 机制按路径 `/vless-argo` / `/vmess-argo` 自动分流，无需 Nginx/Caddy。
- **`vmess://` + `vless://` 一键导入** — 安装完成直接打印双协议链接 + QR 二维码。复制粘贴进客户端即完成配置，告别手填。
- **零公网暴露** — 所有 Xray inbound 仅监听 `127.0.0.1`。公网无任何代理端口，完美免疫防火墙主动探测和端口扫描。
- **无 Caddy / 无 Nginx** — TLS 由 Cloudflare 边缘节点处理。VPS 无需申请证书，无需装 web 服务器，无需开放端口。
- **内置三网优选分流** — 预配置移动/联通/电信/通用优选域名。
- **彩色交互面板** — 安装后注入 `argov` 快捷指令。分类菜单，实时状态着色。
- **配置灵活修改** — 更换 UUID（双协议同步）、刷新 Argo 临时域名、切换 CDN 优选线路，无需重装。

## 🚀 一键部署安装

Ubuntu / Debian / CentOS，root 用户：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

安装完成后终端直接输出 VLESS 和 VMess 链接 + QR 码，复制即用。

## 🛠️ 日常管理

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VLESS + VMess 双协议  |  WS + TLS + Argo    ║
╚══════════════════════════════════════════════════╝

  Xray 内核 : ● 运行中     UUID : abcd1234-...
  Argo 隧道 : ● 运行中

───────────────── 节点管理 ─────────────────
  1. 查看节点链接 (VLESS + VMess 双协议)
  2. 更换/选择分流优选域名
  3. 修改节点配置 (UUID / 刷新域名)

───────────────── 服务控制 ─────────────────
  4. 启动 服务
  5. 停止 服务
  6. 重启 服务 (获取新临时域名)

───────────────── 系统维护 ─────────────────
  7. 重新一键全自动安装
  8. 完全卸载 ArgoX-Mini
```

## 🏗 架构图

```
┌──────────┐     TLS:443      ┌─────────────┐     HTTP     ┌──────────────────┐
│  客户端   │ ────────────────→ │  Cloudflare │ ───────────→ │  cloudflared     │
│ v2rayN   │ ←──────────────── │  边缘节点   │ ←─────────── │  (Argo 隧道)     │
│ 小火箭   │     WebSocket     └─────────────┘   localhost  └───────┬──────────┘
└──────────┘                                                        │
                                                            localhost:8080
                                                                    │
                                                            ┌───────▼──────────┐
                                                            │  Xray Inbound    │
                                                            │  VLESS TCP       │
                                                            │  端口 8080       │
                                                            │  ┌─ fallback ─┐  │
                                                            │  │ /vless-argo │  │
                                                            │  │ /vmess-argo │  │
                                                            │  └─────────────┘  │
                                                            └──┬───────────┬───┘
                                                               │           │
                                                      localhost:8081  localhost:8082
                                                      VLESS + WS      VMess + WS
```

## 💻 客户端配置指南

### VLESS（推荐新客户端使用）

| 配置项 | 填写内容 |
|---|---|
| 地址 | `cdn.31514926.xyz`（或分流域名） |
| 端口 | `443` |
| UUID | 从终端复制 |
| 传输协议 | `ws` (WebSocket) |
| 路径 | `/vless-argo` |
| TLS | `tls` 开启 |
| SNI | `xxxx.trycloudflare.com` |

### VMess

| 配置项 | 填写内容 |
|---|---|
| 地址 | `cdn.31514926.xyz` |
| 端口 | `443` |
| UUID | 从终端复制 |
| alterId | `0` |
| 加密 | `none` |
| 传输协议 | `ws` |
| 路径 | `/vmess-argo` |
| TLS | `tls` 开启 |
| SNI | `xxxx.trycloudflare.com` |

**支持客户端：** v2rayN、Nekoray、Nekobox、Shadowrocket (小火箭)、Sing-box、V2Box、Karing、Clash Meta，以及任何支持 VLESS/VMess + WS + TLS 的客户端。

## 📄 开源协议

MIT License。欢迎自由 Fork、二次改造和分享！
