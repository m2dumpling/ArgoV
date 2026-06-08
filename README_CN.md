# 🌐 ArgoV — Next-Gen Proxy Management Panel

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>一键部署 · 零公网暴露 · 动态链路路由 · 极客首选面板</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray_v1.8+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality|Hysteria2-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** 是一款极简、硬核且高度专业化的零公网端口代理管理面板。基于 Cloudflare Argo 隧道，它将 VLESS 和 VMess 流量深度伪装在 Cloudflare 的边缘网络内，无需任何域名，无需开放任何防火墙端口。

除了隧道基础能力，ArgoV 还内建了原生 **VLESS Reality** 和 **Shadowsocks** 协议支持，并提供了前所未有的灵活路由策略：包括强大的**落地中继 (Chain Proxy)**、**WARP 智能分流**、**订阅动态下发**，以及对第三方节点的**无缝订阅聚合**。一切均由高度优化的 Bash 架构驱动，轻量级、无依赖、秒级响应。

[快速开始](#快速开始) · [核心特性](#核心特性) · [动态订阅](#动态订阅服务器) · [落地中继](#落地中继-server-side-relay) · [面板展示](#极客化管理面板) · [English](README.md)

---

## 快速开始

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

> **🔥 效率提示**：安装完成后，随时在终端输入 `ag` 或 `argov` 即可极速呼出管理面板。

非交互模式（适用于自动化流水线）：
```bash
NODE_NAME=Tokyo CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## 核心特性

| 特性维度 | 深度解析 |
|----------|---------|
| **零公网暴露 (Argo)** | VLESS / VMess 流量封装于 WS + TLS 隧道内，Xray 仅监听 `127.0.0.1`，彻底隐匿服务器真实 IP，免疫所有主动探测。 |
| **极致直连 (Reality)**| 原生支持 `VLESS-Reality` (XTLS Vision) 及 `Shadowsocks` (涵盖 SS2022 与 AEAD 加密)。支持 QUIC/TLS 深度嗅探。 |
| **一键订阅 (Sub)** | 内置轻量 Python3 HTTP 订阅服务器，VPS 重启后自动更新隧道节点域名并实时下发客户端；v2rayN 类客户端获取 base64 节点订阅，Clash/Mihomo/Clash Verge 获取完整 YAML 配置。 |
| **协议聚合 (Custom)**| 支持一键导入第三方节点链接（`vless://`、`vmess://`、`ss://`、`trojan://`、`hysteria2://`），通过 ArgoV 的订阅服务实现**跨生态节点聚合**。 |
| **链式代理 (Relay)** | **落地中继**引擎。服务端直接将流量加密路由至海外原生 IP (解锁 VPS)，客户端零配置即享原生纯净出口 IP。 |
| **智能分流 (WARP)** | 一键挂载 WARP IPv6 / SOCKS5。精准的 DNS 级出站路由：Google 走 IPv6，YouTube 走 SOCKS5，规避封控与限流。 |
| **轻量级守护** | 兼容 Debian / Ubuntu / CentOS / Alpine。完美适配 `systemd` 与 `openrc`，服务绝对隔离，轻如鸿毛。 |

## 极客化管理面板

只需输入 `ag`，掌控全局网络拓扑：

```text
 ╔══════════════════════════════════════════════════╗
 ║     ArgoV  纯净版隧道管理面板                    ║
 ║     VL-Argo VM-Argo SS Reality                   ║
 ╚══════════════════════════════════════════════════╝

  名称 : Tokyo    Xray: ● 运行中    Argo: ● 运行中
  UUID : 45c7acf6-1fb...
  域名 : xxx.trycloudflare.com
  CDN  : skk.moe:443

 ──────────────── ✦ 核心功能 ✦ ────────────────
  1. 🔗 查看节点链接       2. ☁️  更换优选线路
  3. ⚙️  修改基础配置       a. 🧩 管理代理节点 (添加/编辑/删除)

 ──────────────── ✦ 进阶路由 ✦ ────────────────
  w. 🌐 独立 WARP 分流     r. 🔀 落地节点中继

 ──────────────── ✦ 状态运维 ✦ ────────────────
  4. ▶️  启动系统         5. ⏹️  停止系统
  6. 🔁 重启 Argo 隧道    7. 🔄 重新安装 (保留数据)
  8. 🆙 更新管理脚本      9. 🗑️  彻底卸载系统
  x. 🚀 更新 Xray 内核    0. 🚪 安全退出
 ───────────────────────────────────────────────
```

## 动态订阅服务器

无论是重启 VPS 还是 Cloudflare 重置了 Argo 域名，客户端永远不会断连。
**无需 SSH 登录服务器获取新链接**，订阅服务器会实时将最新的 Argo 隧道信息动态下发。

- **高安全性**：64 位随机 Token 硬件级认证。
- **高兼容性**：支持自签 TLS（完美兼容 Cloudflare Full SSL）或纯 HTTP 下发。
- **端口自由**：支持 Cloudflare 全部代理端口（2096, 8443, 2053, 443 等）。
- **客户端智能适配**：v2rayN 类客户端返回标准 base64 节点订阅；Clash/Mihomo/Clash Verge 返回完整 YAML，包含 DNS、策略组、规则集，以及 Reality/Hysteria2 所需字段。

已安装用户可通过面板更新脚本并重新生成服务：

```text
ag
8. 更新管理脚本
7. 重新安装 (保留数据)
```

## 高级协议管理

按 `a` 键进入**协议管理矩阵**。不仅仅局限于管理 ArgoV 本身的节点，你甚至可以将其作为整个 VPS 的“网关订阅中心”。

```text
  ── Argo 隧道 ──
  e1. VLESS + Argo    端口 8081    /vless-argo
  e2. VMess + Argo    端口 8082    /vmess-argo

  ── 可选直连协议 ──
  e3. VLESS Reality   amazon.com   :43210
  e4. Shadowsocks     aes-256-gcm  :8388

  ── 自定义节点 (聚合下发) ──
  已有 2 个自定义链接
  c1. 添加    c2. 查看/删除
```

> 💡 **Hysteria2 最佳实践**：鉴于内核适配策略，对于需要极致 UDP 性能的 Hysteria2，我们建议使用专用脚本搭建后，将 `hysteria2://` 分享链接通过 `c1` 粘贴至此。ArgoV 会自动将其与现有隧道整合，并在 Clash 客户端请求订阅时转换为 Mihomo 兼容 YAML。

## 落地中继 (Server-Side Relay)

告别客户端繁琐的链式代理配置。ArgoV 提供服务端层面的**透明中继**。

*通过在面板按 `r` 进入。*

- 粘贴任何有效的 `ss://`, `vless://`, `vmess://`, `trojan://` 链接作为落地出口。
- **零 DNS 泄露**：启用 `domainStrategy: AsIs`，所有 DNS 查询直接打包发送至落地节点解析。
- **策略路由**：支持“全局中继”或“分流中继”（仅指定流媒体域名走落地）。
- 与 WARP 双路由引擎完美共存。

## 架构拓扑

```text
Client → CF Edge (TLS) → Argo Tunnel → localhost:8080 Xray fallback
                                           ├── /vless-argo → VLESS+WS :8081
                                           └── /vmess-argo → VMess+WS :8082

Direct (可选) : VLESS+Reality (端口隐匿)  ·  Shadowsocks (流加密)

WARP 分流栈 : Xray 路由规则 → warp-out (SOCKS5 :40000) / v6-direct (IPv6)

Relay 代理链: Xray 路由规则 → relay-out (SS/VL/VM/TJ) → 落地 VPS (原生 IP) → Internet
```

## 客户端适配

ArgoV 完美兼容目前所有的主流 Xray-core / Sing-box 内核客户端：
`v2rayN` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Clash Meta` · `V2Box` · `Karing`

当前 Clash YAML 转换支持 `vless`、`vmess`、`ss`、`trojan`、`hysteria2` 分享链接。其他自定义协议可以保存在原始订阅列表中，但不会自动转换成 Clash YAML，除非后续显式增加转换支持。

## License
[MIT License](LICENSE).
