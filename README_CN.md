# 🚇 ArgoX-Mini — Cloudflare Argo 隧道管理面板

<p align="center">
  <img src="docs/assets/argox-mini-logo.svg" alt="ArgoX-Mini" width="440">
</p>

<p align="center">
  <strong>一键部署 · 零公网端口 · VPS 重启自动恢复</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoX-Mini** 是基于 Cloudflare Argo 隧道的零公网端口代理管理面板。将 VLESS / VMess 流量封装在 CF 边缘网络内 — 无需开放防火墙端口，无需自有域名。可选 Reality 和 Shadowsocks 直连协议。内置订阅服务器，VPS 重启后自动获取新隧道域名、订阅链接无需更新。

[快速开始](#快速开始) · [功能](#功能特性) · [安装向导](#安装向导) · [订阅](#订阅服务器) · [WARP](#warp-域名分流) · [架构](#架构) · [客户端](#客户端配置) · [English](README.md)

---

## 快速开始

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

首次运行自动进入交互式安装向导，全程回车使用默认值。

安装完成后输入 `argov` 打开管理面板。

非交互模式（环境变量）：

```bash
NODE_NAME=东京 CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 功能特性

| 类别 | 详情 |
|------|------|
| **Argo 隧道** | VLESS + VMess 双协议，WS + TLS，仅监听 `127.0.0.1`，零公网暴露 |
| **直连协议** | VLESS Reality（XTLS Vision）+ Shadowsocks（7 种加密：AEAD + SS2022） |
| **安装向导** | 8 步交互式配置，合理默认值，自动系统检测 |
| **订阅服务器** | Python3 HTTP 服务器，ThreadingMixIn 多线程 + 10s 自动刷新，Token 认证，重启自动恢复 |
| **自定义链接** | 粘贴任意协议链接（Hysteria2、Trojan、TUIC 等），自动加入订阅，重启不丢失 |
| **WARP 分流** | 一键 fscarmen WARP，智能分流：Google → IPv6，YouTube → SOCKS5，其余直连 |
| **节点管理** | 增删改 Reality / Shadowsocks 节点，无需全量重装 |
| **系统兼容** | Debian / Ubuntu / CentOS / Alpine Linux，systemd + openrc 服务管理 |
| **服务隔离** | `argox-tunnel` 独立服务，不与已有隧道冲突 |

## 安装向导

```
━━━ ① 节点名称 ━━━
  ② CDN 优选地址（默认 / 列表选 / 自定义）
  ③ 客户端端口（CF 边缘，默认 443）
  ④ UUID（自动生成 / 自定义）
  ⑤ Argo 隧道类型（临时 / 固定 Token）
  ⑥ 内部端口（仅 127.0.0.1，自动分配）
  ⑦ 订阅域名（可选，CF 端口自选）
  ⑧ 额外协议（Reality / Shadowsocks，端口可输）
```

## 管理面板

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VL-Argo VM-Argo SS Reality                  ║
╚══════════════════════════════════════════════════╝

  名称 : 东京    Xray: ● 运行中    Argo: ● 运行中

── 节点管理 ──
  1. 查看链接    2. 更换 CDN    3. 修改配置    a. 管理节点

── 服务控制 ──
  4. 启动    5. 停止    6. 重启/恢复（仅 Argo）

── 系统维护 ──
  7. 重装    8. 更新    9. 卸载
  0. 退出    w. WARP 分流
```

## 订阅服务器

VPS 重启后 Argo 隧道自动获取新域名，订阅服务器每次请求返回最新链接 — **无需 SSH**。

| 模式 | URL | 所需配置 |
|------|-----|----------|
| 域名（HTTPS） | `https://sub.你的域名.com:2096/sub?token=xxx` | CF 小黄云开，DNS → VPS IP |
| IP（HTTP） | `http://VPS_IP:端口/TOKEN` | 无需配置 |

- 64 位随机 Token 认证
- 自签 TLS 证书（兼容 CF Full SSL 模式）
- CF 代理端口：2096 / 8443 / 2053 / 2083 / 2087 / 443 / 自定义
- 多线程 Python3 HTTP 服务器，systemd / openrc 管理

## 节点管理

按 `a` 管理全部节点，含自定义链接功能：

```
╔══════════════════════════════════════════╗
║         管理节点                         ║
╚══════════════════════════════════════════╝

  ── Argo 隧道 ──
  e1. VLESS + Argo    端口 8081    /vless-argo
  e2. VMess + Argo    端口 8082    /vmess-argo

  ── 可选协议 ──
  e3. VLESS Reality   amazon.com   :43210
  e4. Shadowsocks      aes-256-gcm  :8388

  a1. 添加 Reality    a2. 添加 SS    d. 删除

  ── 自定义节点 (自添加) ──
  已有 2 个自定义链接
  c1. 添加    c2. 查看/删除
```

通过 `c1` 粘贴任意协议链接（`hy2://`、`trojan://`、`tuic://` 等），自动加入订阅，重启不丢失。

| 协议 | 可编辑字段 |
|------|-----------|
| VLESS / VMess Argo | 端口、WS 路径（自动同步 fallback 路由） |
| Shadowsocks | 加密方式、密码、端口、网络（tcp/udp） |
| VLESS Reality | SNI、端口、shortId、指纹、重新生成 x25519 密钥 |

## WARP 域名分流

按 `w` 进入 WARP 管理。三种分流模式：

| 模式 | Google / 搜索 | YouTube | 其他 |
|------|--------------|---------|------|
| SOCKS5 | WARP IPv4 | WARP IPv4 | WARP IPv4 |
| IPv6 | WARP IPv6 | WARP IPv6 | WARP IPv6 |
| **智能分流**（推荐） | WARP IPv6 | WARP SOCKS5 | 直连 |

- fscarmen WARP 自动安装（SOCKS5 :40000 / IPv6 WireGuard）
- 自定义分流域名或注入 Google / YouTube 默认组
- Python3 安全改写 JSON，校验失败自动回滚

## 架构

```
客户端 → CF 边缘 (TLS) → Argo 隧道 → localhost:8080 Xray fallback
                                          ├── /vless-argo → VLESS+WS :8081
                                          └── /vmess-argo → VMess+WS :8082

直连（可选）：VLESS+Reality（公网端口） · Shadowsocks（公网端口）

WARP 分流：Xray 路由规则 → warp-out (SOCKS5 :40000) / v6-direct (IPv6)

订阅链路：sub_gen.sh → sub.txt → base64 → Python HTTP → 客户端
                                ↑
                  /etc/xray/custom_links.txt (用户自添加)
```

## Alpine 支持

| 功能 | Debian / Ubuntu | Alpine |
|------|----------------|--------|
| 服务控制 | `systemctl` | `rc-service` |
| 包管理 | `apt` | `apk` |
| 服务文件 | `/etc/systemd/system/` | `/etc/init.d/` |
| 隧道恢复 | `Restart=on-failure` | while 循环重试 + 30s 网络等待 |
| 端口检测 | `netstat` → `ss` → `lsof` | 同 |

## 客户端配置

复制终端输出的链接 → 导入剪贴板，或使用订阅 URL 一键导入。

| 协议 | 链接格式 |
|------|---------|
| VLESS Argo | `vless://UUID@CDN:443?encryption=none&security=tls&sni=...&type=ws&host=...&path=%2Fvless-argo#名称-VLESS` |
| VMess Argo | `vmess://base64(...)` |
| Shadowsocks | `ss://base64@IP:PORT#名称-SS` |
| VLESS Reality | `vless://UUID@IP:PORT?...&security=reality&pbk=KEY#名称-Reality` |
| 自定义 | 面板内粘贴任意 `protocol://` 链接 |

支持客户端：v2rayN · Nekoray · Shadowrocket · Sing-box · Clash Meta · V2Box · Karing

## 协议

MIT License。欢迎 Fork、修改、分享。
