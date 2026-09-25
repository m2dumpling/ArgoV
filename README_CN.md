# ArgoV

<p align="center">
  <img src="docs/assets/argov-logo.svg?v=3" alt="ArgoV" width="420">
</p>

<p align="center">
  <strong>面向自托管服务器的 Xray + Sing-box 双核代理管理脚本</strong><br>
  一条命令部署、一个面板维护、一个订阅下发全部节点
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Runtime-Bash-121011?style=flat-square&logo=gnu-bash" alt="Bash">
  <img src="https://img.shields.io/badge/Cores-Xray%20%2B%20sing--box-0078D7?style=flat-square" alt="Dual core">
  <img src="https://img.shields.io/badge/Protocols-7-8B5CF6?style=flat-square" alt="Seven protocols">
  <img src="https://img.shields.io/badge/Linux-systemd%20%2B%20OpenRC-6E56CF?style=flat-square&logo=linux" alt="Linux init systems">
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#能力一览">能力一览</a> ·
  <a href="#协议与内核">协议与内核</a> ·
  <a href="#日常运维">日常运维</a> ·
  <a href="README.md">English</a>
</p>

---

ArgoV 把 Xray、Cloudflare Tunnel（Argo）和 Sing-box 组合为一个交互式运维脚本。它既可以部署完全不暴露公网端口的 Argo 节点，也可以只部署 Reality、Hysteria2、TUIC、AnyTLS、Shadowsocks 等直连节点；协议、用户、流量限额、订阅、WARP 和中继均可在安装后继续维护。

> 适合已拥有 Linux VPS，并希望在不维护多个配置文件的情况下管理多种入站协议的场景。请仅在你有权使用的网络与服务器上部署，并自行评估当地法律、服务商规则和网络政策。

## 快速开始

以 `root` 或具备 `sudo` 权限的用户登录 Linux 服务器后执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

安装向导会依次询问节点名称、是否启用 Argo、订阅方式、直连协议及可选 Sing-box 内核。完成后运行：

```bash
ag
```

即可进入管理面板。也可预设名称：

```bash
NODE_NAME=Tokyo bash <(curl -fsSL https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

### 部署前准备

| 项目 | 说明 |
| --- | --- |
| 系统 | Debian、Ubuntu、CentOS/RHEL 系、Alpine Linux；支持 systemd 与 OpenRC |
| 权限 | 建议 root；脚本会安装 `curl`、`jq`、`openssl`、`unzip` 等运行依赖 |
| 端口 | Argo 模式无需暴露 VLESS/VMess 内部端口；直连协议需在安全组和防火墙放行对应 TCP/UDP 端口 |
| 域名 | 临时 Argo 隧道不需要域名；固定隧道与 HTTPS 订阅需要你已配置的域名或 Token |
| 证书 | HY2、TUIC 可生成自签证书；订阅会携带可用的证书指纹 |

## 能力一览

| 模块 | 能力 |
| --- | --- |
| 双核管理 | Xray 负责 Argo、Reality、HY2、SS；可选 Sing-box 扩展 TUIC、AnyTLS 和独立直连节点 |
| Argo 隧道 | VLESS / VMess WebSocket over Cloudflare Tunnel；支持临时 `trycloudflare.com` 与固定 Token 隧道 |
| 直连协议 | VLESS Reality、Hysteria2、Shadowsocks；支持安装后新增、编辑、删除与链接展示 |
| Sing-box | Hysteria2、TUIC、AnyTLS Reality、VLESS Reality、Shadowsocks；支持安装、更新与协议管理 |
| 用户与配额 | 独立 UUID、订阅 Token、额度和重置日；超额自动禁用，月度自动恢复 |
| 动态订阅 | 一个 URL 下发当前用户可用节点；支持 Base64 原始订阅和 Clash/Mihomo YAML 输出 |
| 证书固定 | HY2 自动计算 `pinSHA256`，适用于自签证书固定校验 |
| 端口跳跃 | Xray HY2 与 Sing-box HY2 支持 UDP 端口跳跃，规则由 iptables 管理 |
| 落地中继 | 将 Xray 出站链式转发到 SS、VLESS、VMess 或 Trojan 落地节点 |
| WARP 分流 | 为指定域名注入 WARP SOCKS5、IPv6 或智能分流规则 |
| 聚合订阅 | 合并多个外部订阅源、去重并作为本地订阅的一部分提供 |
| 安全与恢复 | 下载校验、原子写入、状态锁以及旧 ArgoX 配置迁移 |

## 协议与内核

| 协议 | 内核 | 典型用途 | 备注 |
| --- | --- | --- | --- |
| VLESS + Argo | Xray | 零公网暴露的 Cloudflare Tunnel 节点 | WebSocket；Argo 可选 |
| VMess + Argo | Xray | 兼容既有 VMess 客户端 | WebSocket；最新 Xray 会给出弃用提示 |
| VLESS Reality | Xray / Sing-box | TLS 外观的直连节点 | Vision、SNI、Short ID、x25519 密钥 |
| Hysteria2 | Xray / Sing-box | UDP/QUIC 直连节点 | 证书固定、端口跳跃；Sing-box 支持 Brutal 带宽参数 |
| TUIC | Sing-box | QUIC 直连节点 | 启用 Sing-box 后可用 |
| AnyTLS Reality | Sing-box | Reality 直连节点 | 启用 Sing-box 后可用 |
| Shadowsocks | Xray / Sing-box | AEAD / SS2022 节点 | TCP/UDP；最新 Xray 会给出弃用提示 |

```text
                         ArgoV
                           │
          ┌────────────────┴────────────────┐
          │                                 │
       Xray                           Sing-box（可选）
          │                                 │
 Argo · Reality · HY2 · SS      HY2 · TUIC · AnyTLS · Reality · SS
          │                                 │
          └───────────────┬─────────────────┘
                          │
               用户、配额、订阅、路由与运维
```

### 当前内核兼容性

生成配置已对齐当前 Xray 与 sing-box 格式：Xray Reality 服务端使用 `target` 字段，Sing-box HY2 Brutal 会写入 `up_mbps` / `down_mbps`。Argo WebSocket、VMess 和 Shadowsocks 为保护既有客户端兼容性仍被保留；较新的 Xray 会显示弃用警告。迁移到 XHTTP 或 VLESS Encryption 会改变客户端连接方式，因此不会在更新时强制执行。

## 安装流程

```text
节点名称
  │
  ├─ 启用 Argo ── CDN / UUID / 临时或固定隧道 / 内部端口
  │
  └─ 跳过 Argo ── 直接部署 Reality / HY2 / SS
                         │
                         ├─ 订阅服务器（HTTP 或 HTTPS）
                         └─ 可选 Sing-box（HY2 / TUIC / AnyTLS / Reality / SS）
```

Argo 不是必选项。安装时跳过后，仍可在主面板中通过 `a → a0` 启用。重装会保留已有用户数据和已配置的可选入站。

## 管理面板

运行 `ag` 后，可从以下分组进入功能：

| 入口 | 用途 |
| --- | --- |
| `1` | 查看节点链接、订阅地址与二维码 |
| `2` / `3` | 更换 CDN、修改基础参数与订阅配置 |
| `a` | 管理 Xray 协议、启用 Argo、添加自定义链接 |
| `u` | 添加/启用/禁用用户，设置配额、重置日与订阅 Token |
| `s` | 安装或更新 Sing-box，管理其协议及节点链接 |
| `w` | 配置 WARP SOCKS5 / IPv6 域名分流 |
| `r` | 配置或清理落地中继 |
| `g` | 管理外部聚合订阅源 |
| `4` / `5` / `6` | 启动、停止、重启服务 |
| `7` / `8` / `x` | 保留数据重装、更新管理脚本、更新 Xray 内核 |

## 多用户、配额与订阅

用户数据存储在 `/etc/xray/argov_users.json`。每位用户可拥有独立 UUID、订阅 Token、额度、已用流量与月度重置日。

| 路径 | 计量方式 | 限额行为 |
| --- | --- | --- |
| Xray 入站 | Xray StatsService gRPC，按用户 email 统计双向流量 | 超额后从 Xray 客户端列表移除 |
| Sing-box 独立端口入站 | iptables 端口计数，定时累加 | 超额后停止向该用户分配有效入口 |
| HY2 跳跃端口 | 非默认用户不分配独立 HY2 入口 | 当前共享端口跳跃模式限制 |

| 模式 | 订阅示例 |
| --- | --- |
| HTTPS 域名 | `https://sub.example.com:2096/sub?token=...` |
| HTTP IP | `http://SERVER_IP:PORT/sub?token=...` |

默认用户可获得共享节点及自定义链接；限额用户只会收到自己的可用节点和独立 Sing-box 端口。

## 路由能力

### WARP 域名分流

- **SOCKS5**：清单内流量经本机 WARP SOCKS5（默认 `127.0.0.1:40000`）转发。
- **IPv6**：清单内流量走 IPv6 直连出口。
- **智能**：Google 类域名走 IPv6，YouTube 类域名走 WARP SOCKS5。

### 落地中继与聚合订阅

落地中继可将 Xray 与 Sing-box 代理入站的出站交给另一台 SS、VLESS、VMess 或 Trojan 节点；“全部”表示两套代理内核接收的客户端流量，不包括服务器系统自身发起的流量。若同时启用两个内核的同名协议，订阅会为 Sing-box 节点追加内核标识，方便区分。聚合订阅可合并多台 VPS 或外部订阅源，去重后统一下发。

## 日常运维

```bash
# 进入面板
ag

# systemd 系统
systemctl status xray sing-box

# Alpine / OpenRC
rc-service xray status
```

| 文件 | 用途 |
| --- | --- |
| `/etc/xray/argov.conf` | ArgoV 持久化参数与密钥引用 |
| `/etc/xray/config.json` | Xray 运行配置 |
| `/etc/xray/argov_users.json` | 用户、Token、额度与流量状态 |
| `/etc/sing-box/config.json` | Sing-box 运行配置 |
| `/etc/xray/argo.log` | 临时 Argo 隧道域名日志 |

## 客户端与注意事项

常见链接格式可用于 `v2rayN`、Nekoray、Shadowrocket、sing-box、Mihomo / Clash Verge、Karing 等客户端；实际可用性取决于客户端内核版本和协议支持。

- 直连 Reality、HY2、TUIC、AnyTLS、SS 需要在 VPS 防火墙和云安全组开放端口。
- 自签 HY2/TUIC 证书要求客户端允许不受信任证书；优先使用订阅中的 `pinSHA256` 固定证书指纹。
- Sing-box HY2、TUIC、AnyTLS 依赖官方发布包的构建标签；建议通过面板更新，不要随意替换为精简构建。
- 项目当前未提供 `LICENSE` 文件；复用、分发或部署前请确认授权与合规要求。

## 贡献

欢迎提交 Issue 或 Pull Request。提交前请在仓库根目录运行完整检查（需要 Bash 和 Python）：

```bash
bash tests/argov_static_tests.sh argov.sh
```

该脚本检查 Bash 语法、全部五组 Python 测试（包括中继配置），以及隧道服务的日志设置。
