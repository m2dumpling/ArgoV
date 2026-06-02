# ArgoX-Mini 纯净版隧道管理面板

<p align="center">
  <a href="./README.md"><b>🌐 English</b></a>
</p>

---

一个极度精简的 Cloudflare Argo 隧道管理脚本，**VLESS + VMess + Shadowsocks + VLESS Reality**，内置 **WARP SOCKS5 / IPv6 域名分流**。

**ArgoX-Mini** 只装必需的：Xray-core + cloudflared。不装 Nginx、不装 Caddy。Argo 入站仅监听 `127.0.0.1`，公网零端口暴露。可选 VLESS Reality 和 Shadowsocks 直连。完整支持 Alpine Linux。

## ✨ 功能

**核心**
- VLESS + VMess Argo 隧道（默认安装）。可选：Shadowsocks、VLESS Reality
- 7 步交互式安装向导，每步有默认值，回车即用
- `vless://` / `vmess://` / `ss://` 一键导入链接 + QR 码
- 自定义节点名带协议后缀（`#东京-VLESS`、`#东京-Reality`）

**节点管理** — 菜单 `a`
- 添加、编辑、删除任意协议节点，不重装
- Argo VLESS/VMess 节点可编辑（端口、路径，自动同步 fallback 路由）
- SS：7 种加密（AEAD + SS2022），可编辑加密/密码/端口
- Reality：8 个伪装域名，可编辑 SNI/端口/重新生成 x25519 密钥对

**WARP 域名分流** — 菜单 `w`
- 一键安装 fscarmen WARP（SOCKS5 :40000 或 IPv6 WireGuard）
- 添加自定义域名（逗号分隔），或一键注入 Google/YouTube 默认组
- 切换分流模式：全 SOCKS5 / 全 IPv6 / 智能分流（Google→IPv6 + YouTube→SOCKS5）
- Python3 安全改写 JSON，自动校验，写入失败自动回滚

**安全与兼容**
- 零公网暴露（Argo 模式），仅 `127.0.0.1`，免疫主动探测
- 固定 Argo 隧道（CF Zero Trust Token），临时/固定随时切换
- 持久化配置（`/etc/xray/argox.conf`），重装自动继承
- 开机自启（`systemctl enable` / `rc-update add`）
- Alpine Linux 完整支持（openrc 服务、apk 包管理、netstat 端口检测）
- 服务名独立为 `argox-tunnel`，不与已有 cloudflared 隧道冲突
- 13 个优选 CDN 域名（三网/移动/联通/电信分类）
- 端口冲突自动避让
- 环境变量一键部署（`NODE_NAME=东京 bash <(curl ...)`）

## 🚀 安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

非交互：
```bash
NODE_NAME=东京 CDN_DOMAIN=skk.moe CDN_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🛠️ 管理

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VL-Argo VM-Argo SS Reality                  ║
╚══════════════════════════════════════════════════╝

  名称 : 东京    Xray: ● 运行中    Argo: ● 运行中    CDN : cdn.xxx:443

── 节点管理 ──
  1. 查看链接    2. 更换 CDN    3. 修改配置    a. 管理节点
── 服务控制 ──
  4. 启动    5. 停止    6. 重启
── 系统维护 ──
  7. 重装    8. 更新    9. 卸载    0. 退出    w. WARP分流(SOCKS5/IPv6)
```

### 菜单 `a` — 管理节点

```
╔══════════════════════════════════════════╗
║         管理节点                         ║
╚══════════════════════════════════════════╝

  ── Argo 隧道 ──
  e1. VLESS + Argo    端口 8081  路径 /vless-argo
  e2. VMess + Argo    端口 8082  路径 /vmess-argo

  ── 可选协议 · 可编辑 ──
  e3. VLESS Reality   www.amazon.com  端口 43210
  e4. Shadowsocks      aes-256-gcm     端口 8388

  ── 可添加 ──
  a1. VLESS Reality    a2. Shadowsocks

  d. 删除    0. 返回
```

- **`e1/e2`** — 编辑 Argo 节点：端口、路径（自动同步 fallback 路由）
- **`e3/e4`** — 编辑可选节点：加密、密码、端口、SNI、重新生成密钥
- **`a1/a2`** — 添加新协议（逐步交互配置）
- **`d`** — 删除节点，二次确认

### 菜单 `w` — WARP 分流

```
╔══════════════════════════════════════════╗
║     WARP SOCKS5 / IPv6 分流配置          ║
╚══════════════════════════════════════════╝

  1. 一键注入 Google/YouTube 默认域名组
  2. 手动添加自定义域名 (逗号分隔)
  3. 删除指定域名
  4. 查看 / 清空分流域名列表
  5. 应用配置并重启 Xray
  6. 切换分流模式 (SOCKS5 ↔ IPv6 ↔ 智能)
```

切换模式选项：
- **SOCKS5** — 全部域名走 WARP SOCKS5 (127.0.0.1:40000)
- **IPv6** — 全部域名走 WARP IPv6 直连
- **智能分流** — Google → IPv6（免验证码）+ YouTube → SOCKS5（防弹窗）

## 🏗 架构

```
客户端 → CF 边缘 (TLS) → Argo 隧道 → localhost:8080 Xray fallback
                                          ├── /vless-argo → VLESS+WS
                                          └── /vmess-argo → VMess+WS

直连 (可选):
  VLESS+Reality (公网端口, x25519 密钥)
  Shadowsocks (公网端口)

WARP 分流 (可选):
  Xray routing rules → warp-out (SOCKS5 :40000) 或 v6-direct (IPv6)
  fscarmen WARP 提供底层传输
```

## 💻 客户端配置

复制终端输出的链接 → 导入剪贴板。

| 协议 | 链接格式 |
|------|----------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#名称-VLESS` |
| VMess Argo | `vmess://base64(JSON)#名称-VMess` |
| SS | `ss://base64(method:pass)@ip:port#名称-SS` |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#名称-Reality` |

客户端：v2rayN · Nekoray · Nekobox · Shadowrocket · Sing-box · V2Box · Karing · Clash Meta

## 📄 协议

MIT License
