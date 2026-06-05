# ArgoX-Mini 纯净版隧道管理面板

> Cloudflare Argo 隧道一键部署脚本  
> VLESS + VMess + Shadowsocks + VLESS Reality | WARP SOCKS5/IPv6 智能分流 | 内置订阅服务器

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/Platform-Debian_Ubuntu_CentOS_Alpine-lightgrey)

[English](README.md)

---

## 目录

- [功能特性](#功能特性)
- [快速开始](#快速开始)
- [安装向导](#安装向导)
- [管理面板](#管理面板)
- [订阅服务器](#订阅服务器)
- [WARP 域名分流](#warp-域名分流)
- [节点管理](#节点管理)
- [架构](#架构)
- [Alpine 支持](#alpine-支持)
- [客户端配置](#客户端配置)
- [协议](#协议)

---

## 功能特性

| 类别 | 详情 |
|------|------|
| **Argo 隧道** | VLESS + VMess 双协议，WS+TLS，零公网端口，仅 `127.0.0.1` 监听 |
| **直连协议** | VLESS Reality（XTLS Vision），Shadowsocks（7 种加密：AEAD + SS2022） |
| **安装向导** | 8 步交互式安装，合理默认值，自动系统检测 |
| **订阅服务器** | 重启自动恢复，双模式（域名 HTTPS / IP HTTP），Token 认证，二维码 |
| **WARP 分流** | 一键 fscarmen WARP，智能分流（Google→IPv6 + YouTube→SOCKS5） |
| **节点管理** | 增删改任意协议，无需全量重装 |
| **系统兼容** | Debian / Ubuntu / CentOS / Alpine Linux，openrc + systemd |
| **服务隔离** | `argox-tunnel` 独立服务，不与已有隧道冲突 |

---

## 快速开始

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

首次运行自动进入安装向导，全程回车使用默认值。

非交互（环境变量）：

```bash
NODE_NAME=东京 CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

---

## 安装向导

```
━━━ ① 节点名称 ━━━
  ② CDN 优选地址（默认 / 列表选 / 自定义）
  ③ 客户端端口（CF 边缘，默认 443）
  ④ UUID（自动生成 / 自定义）
  ⑤ Argo 隧道类型（临时 / 固定 Token）
  ⑥ 内部端口（仅 127.0.0.1，自动分配）
  ⑦ 订阅域名（可选，CF 端口自选：2096/8443/2053 等）
  ⑧ 额外协议（Reality / Shadowsocks，端口可输）
```

---

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
  7. 重装（保留配置）    8. 更新    9. 卸载
  0. 退出    w. WARP 分流
```

---

## 订阅服务器

VPS 重启后 Argo 隧道自动获取新域名，订阅服务器每次请求返回最新链接——**无需 SSH**。

### 链接格式

| 模式 | URL | 所需配置 |
|------|-----|----------|
| 域名（HTTPS） | `https://sub.yourdomain.com:2096/sub?token=xxx` | CF 小黄云开，DNS → VPS IP |
| IP（HTTP） | `http://VPS_IP:端口/TOKEN` | 无需配置 |

### 特点

- 64 位随机 Token 认证防偷
- 自签 TLS 证书（兼容 CF Full SSL 模式）
- CF 代理端口自选：2096 / 8443 / 2053 / 2083 / 2087 / 443 / 自定义
- 15 行 Python3 HTTP 服务器，systemd / openrc 管理
- 二维码扫码 = 订阅 URL

---

## WARP 域名分流

按 `w` 进入 WARP 管理。三种分流模式：

| 模式 | Google / 搜索 | YouTube | 其他 |
|------|--------------|---------|------|
| SOCKS5 | WARP IPv4 | WARP IPv4 | WARP IPv4 |
| IPv6 | WARP IPv6 | WARP IPv6 | WARP IPv6 |
| **智能分流**（推荐） | WARP IPv6 | WARP SOCKS5 | 直连 |

- fscarmen WARP 自动安装（SOCKS5 :40000 / IPv6 WireGuard）
- 自定义分流域名或注入 Google/YouTube 默认组
- Python3 安全改写 JSON，校验失败自动回滚

---

## 节点管理

按 `a` 管理全部协议节点：

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
```

各协议可编辑字段：

| 协议 | 可编辑 |
|------|--------|
| VLESS/VMess Argo | 端口、WS 路径（自动同步 fallback 路由） |
| Shadowsocks | 加密方式、密码、端口 |
| VLESS Reality | SNI、端口、shortId、指纹、重新生成 x25519 密钥 |

---

## 架构

```
客户端 → CF 边缘 (TLS) → Argo 隧道 → localhost:8080 Xray fallback
                                          ├── /vless-argo → VLESS+WS :8081
                                          └── /vmess-argo → VMess+WS :8082

直连（可选）：VLESS+Reality（公网端口） · Shadowsocks（公网端口）

WARP 分流：Xray 路由规则 → warp-out (SOCKS5 :40000) 或 v6-direct (IPv6)
```

---

## Alpine 支持

| 功能 | Debian/Ubuntu | Alpine |
|------|--------------|--------|
| 服务控制 | `systemctl` | `rc-service` |
| 包管理 | `apt` | `apk` |
| 服务文件 | `/etc/systemd/system/` | `/etc/init.d/` |
| Tunnel 恢复 | `Restart=on-failure` | while 循环重试 + 30s 网络等待 |
| 端口检测 | `netstat` → `ss` → `lsof` | 同 |

---

## 客户端配置

复制终端输出的链接 → 导入剪贴板，或使用订阅 URL 一键导入。

| 协议 | 示例 |
|------|------|
| VLESS Argo | `vless://UUID@CDN:443?...&path=%2Fvless-argo#名称-VLESS` |
| VMess Argo | `vmess://base64(#名称-VMess)` |
| SS | `ss://base64@IP:PORT#名称-SS` |
| Reality | `vless://UUID@IP:PORT?...&security=reality&pbk=KEY#名称-Reality` |

客户端：v2rayN · Nekoray · Shadowrocket · Sing-box · Clash Meta

---

## 协议

MIT License。欢迎 Fork、修改、分享。
