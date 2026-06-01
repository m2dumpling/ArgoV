# ArgoX-Mini 纯净版隧道管理面板

<p align="center">
  <a href="./README.md"><b>🌐 English</b></a>
</p>

---

一个极度精简、坚如磐石的 Cloudflare Argo 穿透隧道一键管理脚本 —— **VLESS + VMess 双协议**，WebSocket + TLS 传输。

**ArgoX-Mini** 只装 Argo 必需的组件：Xray-core + cloudflared。不装 Nginx、不装 Caddy、不要 Reality、不要 Hysteria2、不要 XHTTP。所有 Xray 入站严格绑定 `127.0.0.1`，VPS 公网上零代理端口暴露。

## ✨ 项目特点

- **VLESS + VMess 双协议** — 单条 Argo 隧道通过 Xray fallback 机制同时支持两种协议，无需额外组件。
- **交互式安装向导** — 6 步引导配置：节点名称 → CDN 地址 → 端口 → UUID → 隧道类型 → 内部端口。每步都有合理默认值，全程回车即用。
- **`vless://` + `vmess://` 一键导入** — 安装完成打印双协议链接 + QR 码。自定义节点名直接显示在链接中（如 `#东京-VLESS`）。
- **持久化配置** — 设置保存到 `/etc/xray/argox.conf`。重装不丢配置，菜单 7 一键重装自动继承。
- **零公网暴露** — Xray 仅监听 `127.0.0.1`。公网无任何代理端口，完美免疫防火墙主动探测。
- **固定 Argo 隧道** — 支持从临时 `.trycloudflare.com` 域名切换到 CF Zero Trust Token 固定域名，菜单随时切换。
- **配置灵活修改** — 菜单 3 可改名称、UUID、CDN、端口、隧道类型，无需重装。
- **无 Caddy / 无 Nginx** — TLS 由 Cloudflare 边缘节点处理。VPS 无需证书，无需 web 服务器。
- **内置 13 个优选域名** — 三网通用 / 移动 / 联通 / 电信分类覆盖。
- **端口冲突自动避让** — 安装时检测默认端口是否被占用，自动向后寻找空闲端口。
- **环境变量覆盖** — 支持 `NODE_NAME=东京 ARGO_PORT=9090 CDN_PORT=8443 bash <(curl ...)` 非交互部署。

## 🚀 一键部署安装

Ubuntu / Debian / CentOS，root 用户：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

首次运行自动进入安装向导，全程回车 = 使用默认值。

### 非交互部署（环境变量）

```bash
NODE_NAME=东京 CDN_DOMAIN=skk.moe CDN_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🎛 交互式安装流程

```
━━━ ① 节点名称 ━━━
  此名称显示在客户端的节点列表里，方便区分多台 VPS。
  节点名称 [ArgoX-Mini]: 东京-Aria

━━━ ② CDN 优选地址 ━━━
  1. 默认 cdn.31514926.xyz (三网通用)
  2. 从 13 个优选域名中选择
  3. 自定义

━━━ ③ 客户端端口 ━━━
  Cloudflare 支持的 HTTPS 端口: 443, 8443, 2053, 2083, 2087, 2096
  端口 [443]: _

━━━ ④ 用户 ID (UUID) ━━━
  UUID [自动生成]: _

━━━ ⑤ Argo 隧道类型 ━━━
  1. 临时隧道 (随机 .trycloudflare.com，推荐)
  2. 固定隧道 (需先在 CF Zero Trust 创建 Token)

━━━ ⑥ 内部端口 ━━━
  仅 127.0.0.1 监听。输入起始端口或回车跳过。
```

## 🛠️ 日常管理

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VLESS + VMess 双协议  |  WS + TLS + Argo    ║
╚══════════════════════════════════════════════════╝

  节点名称 : 东京-Aria
  Xray     : ● 运行中     Argo : ● 运行中
  UUID     : abcd1234-...
  域名     : xxx.trycloudflare.com
  CDN      : cdn.31514926.xyz:443

───────────────── 节点管理 ─────────────────
  1. 查看节点链接 (VLESS + VMess)
  2. 更换优选域名 / 线路
  3. 修改配置 (名称 / UUID / 隧道 / 端口)

───────────────── 服务控制 ─────────────────
  4. 启动 服务
  5. 停止 服务
  6. 重启 服务 (刷新域名)

───────────────── 系统维护 ─────────────────
  7. 重新安装 (保留配置)
  8. 完全卸载
```

**菜单 3 子菜单：**

```
  1. 修改节点名称
  2. 更换 UUID（双协议同步）
  3. 查看/修改内部端口
  4. 查看当前节点链接
  5. 切换 Argo 隧道类型（临时 ↔ 固定 Token）
  6. 刷新临时域名
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
                                                            │  fallback 路由   │
                                                            │  /vless-argo→8081│
                                                            │  /vmess-argo→8082│
                                                            └──┬───────────┬───┘
                                                               │           │
                                                         VLESS+WS    VMess+WS
                                                         :8081       :8082
                                                        (仅 127.0.0.1)
```

## 💻 客户端配置

**推荐：** 复制终端输出的 `vless://` 或 `vmess://` 链接 → 客户端 → 导入剪贴板。

| 配置项 | VLESS | VMess |
|---|---|---|
| 地址 | `cdn.31514926.xyz`（或你选的 CDN） | 同左 |
| 端口 | `443`（或你选的端口） | 同左 |
| UUID | 从终端复制 | 同左 |
| 传输协议 | `ws` | `ws` |
| 路径 | `/vless-argo` | `/vmess-argo` |
| TLS | `tls` | `tls` |
| SNI / 伪装域名 | `xxxx.trycloudflare.com` | 同左 |
| alterId | — | `0` |
| 加密 | `none` | `none` |

支持客户端：v2rayN、Nekoray、Nekobox、Shadowrocket (小火箭)、Sing-box、V2Box、Karing、Clash Meta。

## 📄 开源协议

MIT License。欢迎自由 Fork、二次改造和分享！
