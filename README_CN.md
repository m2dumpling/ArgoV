# 🌐 ArgoV — 双核代理

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="440">
</p>

<p align="center">
  <strong>一键部署 · Xray + Sing-box · Argo 可选</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT"></a>
  <img src="https://img.shields.io/badge/Platform-Debian|Ubuntu|CentOS|Alpine-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Core-Xray_v1.8+_|_Sing--box_v1.10+-0078D7?style=flat-square" alt="Core">
  <img src="https://img.shields.io/badge/Protocol-7种协议-8B5CF6?style=flat-square" alt="Protocols">
</p>

---

**ArgoV** 是双内核零信任代理面板。Xray-core 驱动 Argo 隧道（可选），Sing-box 扩展 TUIC、AnyTLS Reality。支持 VLESS / VMess / Reality / Hysteria2 / TUIC / AnyTLS / Shadowsocks 七种协议。内置多用户流量配额、证书固定、端口跳跃、落地中继、聚合订阅、WARP 分流。单 Bash 脚本。

[快速开始](#快速开始) · [面板](#管理面板) · [特性](#核心特性) · [安装流程](#安装流程) · [双内核](#双内核) · [配额](#多用户流量限额) · [English](README.md)

---

## 快速开始

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

安装后输入 `ag` 打开面板。

```bash
# 非交互
NODE_NAME=东京 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

## 安装流程

```text
 ① 节点名称        → LAX
 ② Argo 隧道?      → 1. 启用 (VLESS/VMess over CF)  /  2. 跳过
    ├─ 启用: ③ CDN → ④ 端口 → ⑤ UUID → ⑥ 临时/固定 → ⑦ 内部端口
    └─ 跳过: 直接到 ⑧ 订阅域名 → ⑨ 额外协议 → ⑩ Sing-box
```

**Argo 非必选**——跳过可直接部署 Reality / HY2 / SS 等直连协议。后续可通过 `a → a0` 随时启用。

## 管理面板

```text
 名称: Tokyo    Xray: ● 运行中    Sing-box: ● 运行中    Argo: ● 运行中
 UUID: 45c7acf6-1fb...    域名: xxx.trycloudflare.com
 CDN: xx.cloudflare.182682.xyz:443    流量: ↓ 12.3 GB  ↑ 156.7 GB

 ──────────────── ✦ 核心 ✦ ────────────────
  1. 🔗 查看节点         2. ☁️  换 CDN
  3. ⚙️  修改配置          a. 🧩 管理节点 (增删改)
  u. 👥 用户/流量限额

 ──────────────── ✦ 路由 ✦ ────────────────
  w. 🌐 WARP 分流        r. 🔀 落地中继
  g. 📡 聚合订阅          s. 🔧 Sing-box 管理

 ──────────────── ✦ 运维 ✦ ────────────────
  4. ▶️  启动  5. ⏹️  停止  6. 🔁 重启 Argo
  7. 🔄 重装  8. 🆙 更新  9. 🗑️  卸载  x. 🚀 更新 Xray
```

## 核心特性

| 类别 | 详情 |
|------|------|
| **Argo 隧道** (可选) | VLESS + VMess over CF。`127.0.0.1` 仅本地，零公网暴露。安装时可跳过，后续 `a → a0` 启用 |
| **双内核** | Xray-core 驱动 Argo；Sing-box 扩展 TUIC、AnyTLS Reality。统一面板 + 合并订阅 |
| **VLESS Reality** | XTLS Vision + Reality 隐匿。自定义 SNI / shortId / 指纹 / x25519 密钥 |
| **Hysteria2** | BBR / Brutal 拥塞。端口跳跃（自定义范围 + 固定/随机间隔，Hi_Hysteria 同款交互）。证书固定 pinSHA256 |
| **TUIC / AnyTLS** | Sing-box 原生。TUIC QUIC + BBR；AnyTLS Reality 隐匿 |
| **Shadowsocks** | AEAD + SS2022，TCP/UDP |
| **订阅服务器** | Python3 HTTP 多线程，10s 自动刷新，自签 TLS。base64 / Clash YAML |
| **用户配额** | 独立 UUID + Token，双向限额。Xray 走 gRPC，Sing-box 走 iptables 端口级追踪。月度自动重置 |
| **证书固定** | 创建/编辑 HY2 自动计算 SHA256 指纹，订阅链接 `pinSHA256=` |
| **聚合订阅** | 跨 VPS 合并一个 URL。源变更 ≤10s 同步 |
| **落地中继** | SS / VLESS / VMess / Trojan 出口。AsIs DNS，零泄露 |
| **WARP 分流** | SOCKS5 :40000 + IPv6。智能分流 |
| **系统兼容** | Debian / Ubuntu / CentOS / Alpine。systemd + OpenRC |

## 双内核

```
Xray-core (常驻)                Sing-box (可选: s → s1)
├ VLESS Argo  :8080             ├ Hysteria2   :8443 (跳变 + pinSHA256)
├ VMess Argo  :8081             ├ TUIC        :8444
├ Reality     :443              ├ AnyTLS      :8445
├ Hysteria2   :23333            ├ VLESS Reality :8446
└ Shadowsocks :8388             └ Shadowsocks :8447
└ gRPC 统计                     └ iptables 端口级统计
```

## 动态订阅服务器

| 模式 | URL |
|------|-----|
| HTTPS | `https://sub.域名:2096/sub?token=xxx` |
| HTTP | `http://IP:PORT/TOKEN` |

## 多用户流量限额

按 `u` 管理：

```text
  name     state  reset   used        quota       token
  default  on     -       1.96 GB     unlimited   67e66c...
  f1       on     ↑10     987 MB      200 GB      e87385...
```

- **Xray 节点**: gRPC StatsService 按 UUID 追踪
- **Sing-box 节点** (TUIC/AnyTLS/Reality/SS): iptables 每用户独立端口 + 守护进程 60s delta 累加
- HY2 暂不分配每用户（跳变兼容）
- 月度自动重置，超额自动禁用

## 证书固定 (pinSHA256)

创建/编辑 HY2 自动计算 SHA256 指纹。订阅链接：`&pinSHA256=BA:88:45:...&allowInsecure=0`。无需域名。

## 聚合订阅

按 `g` 合并所有 VPS/机场。`sort -u` 去重，≤10s 同步。

## 客户端兼容

`v2rayN v7+` · `Nekoray` · `Shadowrocket` · `Sing-box` · `Mihomo` · `Clash Verge` · `Karing`

## License

[MIT](LICENSE)
