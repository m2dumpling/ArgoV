# 🌐 ArgoV — 次世代代理管理面板

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>一键部署 · 双内核 · 零公网端口 · 动态链路路由</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray+v1.8_|_Sing--box_v1.10+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-VLESS|VMess|SS|Reality|HY2|TUIC|AnyTLS-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** 是双内核零信任代理面板。Xray-core 驱动 Argo 隧道（VLESS/VMess WebSocket），Sing-box 扩展 TUIC、AnyTLS Reality 等次世代协议。内置多用户流量配额、证书固定（pinSHA256）、端口跳跃、落地中继、聚合订阅、WARP 分流。全部在一个 Bash 脚本中。

[快速开始](#快速开始) · [面板](#管理面板) · [特性](#核心特性) · [双内核](#双内核) · [订阅](#动态订阅服务器) · [配额](#多用户流量限额) · [聚合](#聚合订阅) · [English](README.md)

---

## 快速开始

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

安装后输入 `ag` 打开面板。非交互模式：

```bash
NODE_NAME=东京 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## 管理面板

```text
 名称 : Tokyo    Xray: ● 运行中    Sing-box: ● 运行中    Argo: ● 运行中
 UUID : 45c7acf6-1fb...
 域名 : xxx.trycloudflare.com
 CDN  : xx.cloudflare.182682.xyz:443
 流量 : ↓ 12.3 GB  ↑ 156.7 GB

 ──────────────── ✦ 核心功能 ✦ ────────────────
  1. 🔗 查看节点链接       2. ☁️  更换优选线路
  3. ⚙️  修改基础配置       a. 🧩 管理代理节点 (添加/编辑/删除)
  u. 👥 用户/流量限额       配额用户仅下发本机节点

 ──────────────── ✦ 进阶路由 ✦ ────────────────
  w. 🌐 独立 WARP 分流     r. 🔀 落地节点中继
  g. 📡 聚合订阅            s. 🔧 Sing-box 管理

 ──────────────── ✦ 状态运维 ✦ ────────────────
  4. ▶️  启动系统        5. ⏹️  停止系统
  6. 🔁 重启 Argo 隧道   7. 🔄 重新安装 (保留数据)
  8. 🆙 更新管理脚本     9. 🗑️  彻底卸载系统
  x. 🚀 更新 Xray 内核   0. 🚪 安全退出
```

## 核心特性

| 类别 | 详情 |
|------|------|
| **Argo 隧道** | VLESS + VMess，WS + TLS over CF。仅 `127.0.0.1`，零公网暴露，重启自动恢复域名 |
| **双内核** | Xray-core 驱动 Argo 隧道；Sing-box 扩展 TUIC、AnyTLS Reality。统一面板管理，订阅合并输出 |
| **VLESS Reality** | XTLS Vision + Reality。防主动探测，自定义 SNI / shortId / 指纹 / x25519 密钥 |
| **Hysteria2** | BBR / Brutal 拥塞控制，端口跳跃（UDP REDIRECT + 自定义范围/固定或随机间隔），证书固定（pinSHA256） |
| **TUIC** | Sing-box 原生 QUIC 协议，BBR 拥塞控制，多用户认证 |
| **AnyTLS Reality** | Sing-box 独占协议，Reality 隐匿 + 自定义 SNI / 密钥 / shortId |
| **Shadowsocks** | AEAD + SS2022，TCP / UDP 双栈 |
| **订阅服务器** | Python3 HTTP 多线程，10s 自动刷新，自签 TLS。输出 base64 / Clash YAML / sing-box 格式 |
| **用户配额** | 独立 UUID + Token，双向流量限额。Xray 走 gRPC，Sing-box 走 iptables 端口级追踪。月度自动重置 |
| **聚合订阅** | 跨 VPS + 机场合并一个 URL。源变更 ≤10s 同步，自签 TLS 兼容 |
| **落地中继** | SS / VLESS / VMess / Trojan 出口。`AsIs` DNS 零泄露。全局 / 分流双模式 |
| **WARP 分流** | SOCKS5 :40000 + IPv6 WireGuard。智能分流：Google → IPv6，YouTube → SOCKS5 |
| **系统** | Debian / Ubuntu / CentOS / Alpine。systemd + OpenRC。服务隔离 |

## 双内核

```
                 Xray-core (常驻)              Sing-box (可选)
                 ├ VLESS Argo  :8080           ├ Hysteria2   :8443
                 ├ VMess Argo  :8081           ├ TUIC        :8444
                 ├ Reality     :443            ├ AnyTLS      :8445
                 ├ Hysteria2   :8443           ├ VLESS Reality :8446
                 ├ Shadowsocks :8388           └ Shadowsocks :8447
                 └  Argo 隧道 + gRPC 统计        iptables 端口级统计
```

- **Xray 不可移除**：Argo 隧道依赖其 VLESS fallback 机制
- **Sing-box 按需安装**：`s → s1` 一键部署，支持 HY2 端口跳跃（自定义范围 + 固定/随机间隔）
- **订阅统一输出**：两份 config.json 合并为一个订阅链接，客户端无感

## 动态订阅服务器

| 模式 | URL | 配置 |
|------|-----|------|
| 域名 (HTTPS) | `https://sub.你的域名.com:2096/sub?token=xxx` | CF 小黄云开，DNS → VPS IP |
| IP (HTTP) | `http://IP:PORT/TOKEN` | 无需配置 |

- 64 位随机 Token，`3 → 9` 自定义
- 自签 TLS，域名变更自动重新生成
- CF 代理端口：2096 / 8443 / 2053 / 2083 / 2087 / 443

## 多用户流量限额

按 `u` 管理用户：

```text
  name     state  reset   used        quota       token
  default  on     -       1.96 GB     unlimited   67e66c...
  f1       on     ↑10     987.51 MB   200.00 GB   e87385...
```

- 独立 UUID、Token、启停、配额
- **Xray 节点**：gRPC StatsService 按 UUID 追踪
- **Sing-box 节点**（TUIC/AnyTLS/Reality/SS）：iptables 每用户独立端口 + `argov-sb-stats` 守护进程 60s 采集，delta 模式累加
- HY2 限额用户暂不分配（跳变兼容性）
- 月度自动重置（1–28 号，北京时区），超额自动禁用

## 证书固定 (pinSHA256)

Xray 将于 2026.8.1 移除 `allowInsecure`。ArgoV 已内置证书固定：创建/编辑 HY2 时自动计算 SHA256 证书指纹，订阅链接格式：

```
hysteria2://pass@ip:8443?sni=...&insecure=1&pinSHA256=BA:88:45:...&allowInsecure=0
                                       ↑ sing-box CA跳过   ↑ 指纹锁定    ↑ Xray 兼容
```

**无需域名**。自签证书 + 指纹验证 = CA 签名安全等级。

## 聚合订阅

按 `g` 合并所有 VPS 订阅：

```text
 总订阅:  https://sub.example.com:2096/agg?token=xxx
 子订阅:
   1. https://vps2.example.com:2096/sub?token=abc
   2. https://vps3.example.com:8443/sub?token=def
```

源变更 ≤10s 同步，`curl -skL` 兼容自签 TLS，`sort -u` 去重。

## 落地中继

按 `r` 透明路由到干净 IP VPS：

```text
 ● 已启用 → ss → 1.2.3.4:28175  模式: 全部
```

粘贴 `ss://` / `vless://` / `vmess://` / `trojan://` 链接，`domainStrategy: AsIs` 零 DNS 泄露。

## WARP 智能分流

按 `w` 一键挂载 fscarmen WARP：

| 模式 | Google | YouTube | 其他 |
|------|--------|---------|------|
| 智能分流 | WARP IPv6 | WARP SOCKS5 | 直连 |

## 架构

```text
客户端 → CF Edge (TLS) → Argo Tunnel → :8080 Xray fallback → VLESS-WS / VMess-WS

直连:   Reality · Hysteria2 (QUIC, BBR/Brutal, 端口跳跃) · TUIC · AnyTLS · SS

路由:   Xray rules → warp-out / v6-direct / relay-out (SS/VL/VM/TJ)

双核:   Xray (Argo+gRPC统计) ｜ Sing-box (HY2/TUIC/AnyTLS+iptables统计)

订阅:   sub_gen.sh → 读两份 config.json → 合并 → base64 → /sub?token=xxx

聚合:   agg_gen.sh → curl 全源 → 合并去重 → /agg?token=xxx
```

## 客户端兼容

`v2rayN v7+` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Karing`

## License

[MIT](LICENSE)
