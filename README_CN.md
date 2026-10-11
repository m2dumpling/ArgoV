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

安装向导会依次询问节点名称、是否启用 Argo、订阅方式、直连协议及可选 Sing-box 内核。

Sing-box 在首次安装中只询问是否安装内核；选择安装后准备内核和服务定义，暂不创建节点、证书或启动空服务。安装完成后，从 `s → s2` 添加 HY2、TUIC 等协议，配置验证通过后才启动节点并设置开机运行。已有 Sing-box 节点继续保留原配置。

完成后运行：

```bash
ag
```

即可进入管理面板。也可预设名称：

```bash
NODE_NAME=Tokyo bash <(curl -fsSL https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh)
```

首次选择 HY2 时必须输入 SNI/TLS 域名，随后选择端口、拥塞控制和端口跳跃。Xray 提供 BBR、Brutal、Reno 和自动协商；Sing-box 提供 BBR、Brutal 和客户端协商。选择 Brutal 后，向导会分别询问服务器上传、下载带宽（Mbps），没有已有值时默认上传 100、下载 200；服务器下载对应客户端上传。域名用于自签证书和握手，不要求你拥有该域名，也不会将代理流量转发到该网站。

新建 HY2 默认开启端口跳跃，Xray 优先使用 UDP `47000-48000`，Sing-box 优先使用 `49000-50000`；冲突时向导会选择其他空闲范围，输入 `off` 可关闭。云安全组与主机防火墙须放行最终显示的整个 UDP 范围。双核都提供开机恢复规则；仅更新脚本不会改变旧节点的带宽、跳跃开关和范围。

安装后可用 `ag → a → e4` 编辑 Xray HY2；Sing-box 的五种协议均可在 `ag → s → s2` 中编辑，HY2 对应 `e1`。编辑时回车保留现值，输入错误会重新询问，可输入 `0` 或 `cancel` 返回。确认后会验证配置；HY2/Sing-box 协议编辑失败时恢复原配置、用户数据和证书。更换域名或证书后请刷新客户端订阅。

完整的易用性审视、已修复项目及待改进项目见 [易用性与可编辑性审视](docs/USABILITY_REVIEW_CN.md)。

开发分支的真实服务器测试步骤见 [VPS 灰度验证指南](docs/VPS_CANARY_VALIDATION_CN.md)，包含干净安装、旧部署升级、检查命令和验收标准。

更新脚本会保留存量节点的协议、域名、端口、凭据和证书。主动更新 Xray 或 Sing-box 内核时，先用新内核校验现有配置；不兼容则取消升级，启动失败则恢复旧二进制。原本停止的服务保持停止，成功升级后旧内核保存在当前二进制旁的 `.argov-previous` 文件中。

若 Sing-box 进程仍运行但内核文件已删除，面板会显示“进程仍运行，安装文件丢失”，并阻止安装/更新；缺失的配置需要从备份恢复，脚本不会强行重启。卸载时若服务仍运行，也会取消删除文件。运行中使用自定义 `-c` / `-C` 配置路径的服务，会按实际进程参数和工作目录进行升级预检。

HY2/TUIC 订阅会从正在使用的证书读取指纹，保留旧 URI 客户端的兼容参数；Mihomo 订阅使用证书指纹验证。TLS 中继会传递 `pcs` / `pinSHA256`，缺少指纹的旧跳过验证链接不会自动改写现有中继。完整修复状态、版本限制和剩余可选功能见 [内核兼容性审视](docs/CORE_COMPATIBILITY_REVIEW_CN.md)。

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
| Hysteria2 | Xray / Sing-box | UDP/QUIC 直连节点 | 自选域名和拥塞控制、证书固定、端口跳跃；双核均支持 Brutal 带宽参数 |
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

生成配置已对齐当前 Xray 与 sing-box 格式：Xray Reality 服务端使用 `target` 字段，Xray HY2 Brutal 使用 `brutalUp` / `brutalDown`，Sing-box 使用 `up_mbps` / `down_mbps`。Sing-box HY2 的 BBR 模式会忽略客户端带宽声明；BBR 预设仅在支持该字段的 1.14+ 版本显示和写入。Argo WebSocket、VMess 和 Shadowsocks 为保护既有客户端兼容性仍被保留；较新的 Xray 会显示弃用警告。迁移到 XHTTP 或 VLESS Encryption 会改变客户端连接方式，因此不会在更新时强制执行。

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

### 服务故障排查

节点或订阅无法使用时，先检查已启用功能对应的服务。使用 systemd 的系统可以查看 Xray 状态和最近的日志：

```bash
systemctl status xray
journalctl -u xray -n 50 --no-pager
```

如果启用了 Argo，再检查隧道服务和域名日志：

```bash
systemctl status argov-tunnel
journalctl -u argov-tunnel -n 50 --no-pager
tail -n 50 /etc/xray/argo.log
```

在 Alpine / OpenRC 上，用以下命令查看服务状态：

```bash
rc-service xray status
rc-service argov-tunnel status
```

未启用 Argo 时不会有 argov-tunnel 服务；Sing-box 和订阅服务也只在启用相应功能后出现。公开日志前请遮盖 Token、UUID 和域名。

### 订阅故障排查

节点可以连接，但订阅无法更新时，需要单独检查订阅服务，而不只是 Xray 或 Argo。systemd 系统执行：

```bash
systemctl status argov-sub
journalctl -u argov-sub -n 50 --no-pager
```

Alpine / OpenRC 系统执行：

```bash
rc-service argov-sub status
```

只有启用订阅功能后才会有 `argov-sub` 服务。请使用面板显示的最新订阅地址；独立用户的订阅地址应从 `u` 菜单获取。

| 现象 | 检查方向 |
| --- | --- |
| 连接被拒绝或超时 | 检查服务是否运行、订阅地址的端口是否正确，以及服务器防火墙和云安全组是否放行该 TCP 端口。Argo 不会自动代理订阅服务。 |
| HTTPS 证书错误 | 单独检查订阅域名和订阅服务证书，不要与代理节点的证书混淆。 |
| HTTP 404 | 检查地址和 Token，并确认用户已启用、未因配额被禁用。有效用户的订阅也可能在缓存生成期间短暂返回 404，可稍后重试，不必立即重装。 |

订阅地址包含访问凭据。公开提问时，不要上传完整订阅地址、用户数据库或配置文件；请只提供错误信息和已脱敏的排查结果。

## 客户端与注意事项

常见链接格式可用于 `v2rayN`、Nekoray、Shadowrocket、sing-box、Mihomo / Clash Verge、Karing 等客户端；实际可用性取决于客户端内核版本和协议支持。

- 直连 Reality、HY2、TUIC、AnyTLS、SS 需要在 VPS 防火墙和云安全组开放端口。
- 自签 HY2/TUIC 证书要求客户端允许不受信任证书；优先使用订阅中的 `pinSHA256` 固定证书指纹。
- 内置 Mihomo 订阅会携带 HY2 的证书指纹和 Brutal 带宽。上传、下载相对于客户端，和向导中的服务器方向相反；其他通用 URI 客户端可能忽略带宽提示，需在客户端设置对应值。
- Sing-box HY2、TUIC、AnyTLS 依赖官方发布包的构建标签；建议通过面板更新，不要随意替换为精简构建。
- 项目当前未提供 `LICENSE` 文件；复用、分发或部署前请确认授权与合规要求。

## 贡献

欢迎提交 Issue 或 Pull Request。提交前请在仓库根目录运行完整检查（需要 Bash 和 Python）：

```bash
bash tests/argov_static_tests.sh argov.sh
```

该脚本检查 Bash 语法、全部七组 Python 测试（包括交互、配置生成、订阅、迁移、中继和内核兼容性），以及隧道服务的日志设置。交互测试需要 `jq` 和 `openssl`；若 PATH 中提供 Xray、Sing-box 和 Mihomo，还会用真实内核校验配置并运行本机连通测试。
