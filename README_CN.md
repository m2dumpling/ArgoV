# 🌐 ArgoV — 次世代代理管理面板

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>一键部署 · 零公网端口 · 动态链路路由 · 极客首选</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray_v1.8+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality|Hysteria2-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** 是基于 Cloudflare Argo 隧道的零信任代理管理面板。VLESS / VMess 流量封装在 CF 边缘网络内——零公网端口，无需域名。原生支持 VLESS Reality、Xray 内置 Hysteria2（BBR / Brutal 拥塞控制 + 端口跳跃）、Shadowsocks。内置多用户流量配额 + 月度自动重置、服务端落地中继、跨 VPS 聚合订阅、WARP 智能分流。全部在一个 Bash 脚本中。

[快速开始](#快速开始) · [面板](#管理面板) · [特性](#核心特性) · [订阅](#动态订阅服务器) · [用户配额](#多用户流量限额) · [聚合](#聚合订阅) · [中继](#落地中继) · [WARP](#warp-智能分流) · [English](README.md)

---

## 快速开始

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

首次运行自动进入交互安装向导，全程回车使用默认值。

安装后输入 `ag` 打开面板。

非交互模式：
```bash
NODE_NAME=东京 CDN_DOMAIN=xx.cloudflare.182682.xyz bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## 管理面板

```text
 ╔══════════════════════════════════════════════════╗
 ║     ArgoV  纯净版隧道管理面板                    ║
 ║     VL-Argo VM-Argo SS Reality Hysteria2         ║
 ╚══════════════════════════════════════════════════╝

  名称 : Tokyo    Xray: ● 运行中    Argo: ● 运行中
  UUID : 45c7acf6-1fb...
  域名 : xxx.trycloudflare.com
  CDN  : xx.cloudflare.182682.xyz:443

 ──────────────── ✦ 核心功能 ✦ ────────────────
  1. 🔗 查看节点链接       2. ☁️  更换优选线路
  3. ⚙️  修改基础配置       a. 🧩 管理代理节点 (添加/编辑/删除)
  u. 👥 用户/流量限额       配额用户仅下发本机节点

 ──────────────── ✦ 进阶路由 ✦ ────────────────
  w. 🌐 独立 WARP 分流     r. 🔀 落地节点中继
  g. 📡 聚合订阅 (Aggregation)

 ──────────────── ✦ 状态运维 ✦ ────────────────
  4. ▶️  启动系统        5. ⏹️  停止系统
  6. 🔁 重启 Argo 隧道   7. 🔄 重新安装 (保留数据)
  8. 🆙 更新管理脚本     9. 🗑️  彻底卸载系统
  x. 🚀 更新 Xray 内核   0. 🚪 安全退出
 ───────────────────────────────────────────────
```

## 核心特性

| 类别 | 详情 |
|------|------|
| **Argo 隧道** | VLESS + VMess 双协议，WS + TLS 走 Cloudflare。仅监听 `127.0.0.1`，零公网暴露。重启自动恢复域名 |
| **VLESS Reality** | XTLS Vision + Reality 隐匿。防主动探测，自定义 SNI / shortId / 指纹 / x25519 密钥 |
| **Hysteria2** | Xray 原生 QUIC 协议。BBR / Brutal 拥塞控制，端口跳跃（UDP 重定向），用户级认证 |
| **Shadowsocks** | 7 种加密：AEAD + SS2022。TCP / UDP / TCP+UDP 三种网络模式 |
| **订阅服务器** | Python3 HTTP 多线程 + 10s 自动刷新，自签 TLS（CF Full SSL 兼容）。v2rayN 输出 base64，Mihomo 输出 Clash YAML |
| **用户配额** | 独立用户账号，UUID + Token 隔离，双向流量限额（如 200G）。按用户粒度下发订阅。月度自动重置（北京时区） |
| **聚合订阅** | 一台 VPS 聚合所有其他 VPS + 机场的订阅 → 一个 URL。任何源变更 ≤10s 同步。兼容自签 TLS |
| **落地中继** | 服务端链式代理到干净 IP VPS。SS / VLESS / VMess / Trojan 出口。`AsIs` DNS 零泄露。全局 / 分流双模式 |
| **WARP 分流** | SOCKS5 :40000 + IPv6 WireGuard。智能分流：Google → IPv6，YouTube → SOCKS5，其余直连。自定义域名 |
| **节点管理** | 各协议独立增删改。自定义链接粘贴。HY2 端口跳跃配置 |
| **系统兼容** | Debian / Ubuntu / CentOS / Alpine。`systemd` + `openrc`。服务隔离（`argov-tunnel`、`argov-sub`、`argov-stats`） |

## 动态订阅服务器

VPS 重启 → Argo 隧道自动获取新域名 → 订阅服务器返回最新链接。**无需 SSH。**

| 模式 | URL | 配置 |
|------|-----|------|
| 域名（HTTPS） | `https://sub.你的域名.com:2096/sub?token=xxx` | CF 小黄云开，DNS → VPS IP |
| IP（HTTP） | `http://IP:PORT/TOKEN` | 无需配置 |

- 64 位随机 Token 认证，支持手动自定义（`3. 修改配置 → 9. 订阅配置`）
- 自签 TLS 证书，域名变更自动重新生成
- CF 代理端口：2096 / 8443 / 2053 / 2083 / 2087 / 443
- Shadowrocket 分组命名 + v2rayN `Profile-Title` HTTP 头
- 订阅配置编辑器：HTTP ↔ HTTPS、域名、端口、自定义 Token

## 多用户流量限额

按 `u` 管理独立用户：

```text
  name             state    reset    used           quota          token
  ----             -----    -----    ----           -----          -----
  default          on       -        1.96 GB        unlimited      67e66c...
  f1               on       ↑10      987.51 MB      200.00 GB      e87385...
```

- 每个用户：独立 UUID、订阅 Token、启停开关、流量配额
- 限额用户下发：VLESS Argo、VMess Argo、Reality、Hysteria2（不含自定义链接）
- 配额阻断：`argov-stats` 守护进程每 60s 查询 Xray StatsService；超额自动禁用，用户保留在列表
- **月度自动重置**：用户可设重置日（1–28 号，北京时区），流量清零 + 自动重新启用。用户管理选 `8`

## 聚合订阅

按 `g` 将所有 VPS 的订阅合并为一个 URL：

```text
 ── 📡 总订阅 (导入客户端) ──
   https://sub.example.com:2096/agg?token=xxx

 ── 📥 子订阅 (其他 VPS/机场) ──
   1. https://vps2.example.com:2096/sub?token=abc
   2. https://vps3.example.com:8443/sub?token=def

   共 2 个子订阅 + 本机 = 聚合后客户端总节点
```

- 一个总订阅 URL → 全部 VPS + 机场的所有节点
- 任何源变更 ≤10s 同步（`agg_gen.sh` 后台抓取）
- 兼容自签 TLS 源（`curl -skL`）
- 按链接去重（`sort -u`）
- 客户端只导入一个 URL 即可看到所有节点

## 落地中继

按 `r` 将流量透明路由到干净 IP VPS：

```text
 ● 已启用 → ss → 1.2.3.4:28175  模式: 全部
```

- 粘贴 `ss://` / `vless://` / `vmess://` / `trojan://` 链接作为出口
- **零 DNS 泄露**：`domainStrategy: AsIs` — 域名经代理协议原样透传至落地解析
- 模式：**全部**（所有流量走落地）或 **分流**（仅指定域名）
- 落地 VPS 只需 SS-Rust：一行命令，5 MB 内存
- 与 WARP 共存；重启 / 重装自动恢复

## WARP 智能分流

按 `w` 一键挂载 fscarmen WARP，域名级分流：

| 模式 | Google | YouTube | 其他 |
|------|--------|---------|------|
| SOCKS5 | WARP | WARP | WARP |
| IPv6 | WARP | WARP | WARP |
| 智能分流 | WARP IPv6 | WARP SOCKS5 | 直连 |

## 架构拓扑

```text
客户端 → CF 边缘 (TLS) → Argo 隧道 → localhost:8080 Xray fallback
                                          ├── /vless-argo → VLESS+WS :8081
                                          └── /vmess-argo → VMess+WS :8082

直连 :  VLESS+Reality  ·  Hysteria2 (QUIC, BBR/Brutal)  ·  Shadowsocks

路由 :  Xray 规则 → warp-out (Socks5 :40000) / v6-direct (IPv6) / relay-out (SS/VL/VM/TJ) → 落地

聚合 :  agg_gen.sh → curl 所有源 → 合并 → 去重 → base64 → /agg?token=xxx
```

## 客户端兼容

`v2rayN` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Clash Meta` · `V2Box` · `Karing`

## License

[MIT License](LICENSE).
