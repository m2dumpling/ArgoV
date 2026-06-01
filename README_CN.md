# ArgoX-Mini 纯净版隧道管理面板

<p align="center">
  <a href="./README.md"><b>🌐 English</b></a>
</p>

---

一个极度精简、坚如磐石的 Cloudflare Argo 隧道一键管理脚本，**VLESS + VMess + Shadowsocks** 多协议支持，WebSocket + TLS 传输。

**ArgoX-Mini** 只装必需的组件：Xray-core + cloudflared。不装 Nginx、不装 Caddy。所有 Argo 协议入站严格绑定 `127.0.0.1`，VPS 公网上零代理端口暴露。可选 VLESS Reality 和 Shadowsocks 直连协议。

## ✨ 项目特点

- **多协议支持** — VLESS + VMess 双协议 Argo 隧道（默认安装），可选 Shadowsocks + Argo、VLESS Reality 直连、Shadowsocks 直连。
- **交互式安装向导** — 7 步引导：名称 → CDN → 端口 → UUID → 隧道类型 → 内部端口 → 可选协议。每步有默认值，回车即用。
- **一键导入链接** — 安装完成打印全部协议的导入链接 + QR 码。自定义节点名带协议后缀（`#东京-VLESS`、`#东京-Reality`）。
- **Shadowsocks 全加密** — 7 种加密方式：`aes-128-gcm` / `aes-256-gcm` / `chacha20-ietf-poly1305` / `xchacha20-ietf-poly1305` / `2022-blake3-aes-128-gcm` / `2022-blake3-aes-256-gcm` / `2022-blake3-chacha20-poly1305`。
- **VLESS Reality 直连** — XTLS Vision + Reality，8 个伪装域名可选，自动生成 x25519 密钥对。
- **零公网暴露（Argo 模式）** — Xray 仅监听 `127.0.0.1`，公网无代理端口，完美免疫防火墙主动探测。
- **固定 Argo 隧道** — 支持 CF Zero Trust Token 固定域名，与临时隧道随时切换。
- **持久化配置** — `/etc/xray/argox.conf` 保存所有设置，重装自动继承。
- **13 个优选域名** — 三网通用 / 移动 / 联通 / 电信分类覆盖。
- **端口冲突自动避让** — 安装时检测端口占用，自动向后寻找空闲端口。
- **环境变量覆盖** — `NODE_NAME=东京 SS_METHOD=2022-blake3-aes-256-gcm bash <(curl ...)` 非交互部署。

## 🚀 一键部署

Ubuntu / Debian / CentOS，root：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

首次运行自动进入安装向导。全程回车使用默认值：VLESS + VMess 双协议 Argo 隧道。

### 非交互部署

```bash
NODE_NAME=东京 CDN_DOMAIN=skk.moe CDN_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

## 🎛 安装流程

```
━━━ ① 节点名称 ━━━
  节点名称 [ArgoX-Mini]: 东京-Aria

━━━ ② CDN 优选地址 ━━━
  1. 默认 cdn.31514926.xyz   2. 从列表选   3. 自定义

━━━ ③ 客户端端口 ━━━
  端口 [443]: _

━━━ ④ UUID ━━━
  [自动生成]: _

━━━ ⑤ Argo 隧道类型 ━━━
  1. 临时隧道   2. 固定隧道

━━━ ⑥ 内部端口 ━━━
  起始端口 [8080]: _

━━━ ⑦ 额外协议（可选）━━━
  1. Shadowsocks + Argo  [○]    ← 走 Argo 隧道，无需开放端口
  2. VLESS Reality 直连 [○]    ← 需开放端口，XTLS Vision
  3. Shadowsocks 直连    [○]    ← 需开放端口，轻量高速
```

## 🛠️ 管理面板

```bash
argov
```

```
╔══════════════════════════════════════════════════╗
║     ArgoX-Mini  纯净版隧道管理面板              ║
║     VL-Argo VM-Argo SS-Argo Reality SS-Dir      ║
╚══════════════════════════════════════════════════╝

  名称 : 东京-Aria    Xray: ● 运行中    Argo: ● 运行中
  UUID : abcd1234-...
  域名 : xxx.trycloudflare.com
  CDN  : cdn.31514926.xyz:443

───────────────── 节点管理 ─────────────────
  1. 查看节点链接 (全部协议)
  2. 更换优选域名 / 线路
  3. 修改配置 (名称/UUID/隧道/加密/协议)

───────────────── 服务控制 ─────────────────
  4. 启动 服务    5. 停止 服务    6. 重启 服务

───────────────── 系统维护 ─────────────────
  7. 重新安装 (保留配置)    8. 更新    9. 卸载
```

**菜单 3 子菜单：** 改名称 · UUID · 隧道类型 · SS 加密 · Reality 伪装域名 · 增删协议（需重装）· 查看链接 · 刷新域名

## 🏗 架构

```
客户端 → CF边缘 (TLS:443) → Argo隧道 → localhost:8080 Xray fallback
                                           ├── /vless-argo → :8081 VLESS+WS
                                           ├── /vmess-argo → :8082 VMess+WS
                                           └── /ss-argo    → :8083 SS+WS    (可选)
直连 (可选):
  :<随机> VLESS+Reality  (0.0.0.0)
  :<随机> SS Direct      (0.0.0.0)
```

## 💻 客户端配置

复制终端输出的链接 → 客户端导入剪贴板即可。

| 协议 | 链接格式 |
|------|----------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#名称-VLESS` |
| VMess Argo | `vmess://base64(JSON)#名称-VMess` |
| SS Argo | `ss://base64(method:pass)@cdn:port#名称-SS-Argo` (WS+TLS 需手动配置) |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#名称-Reality` |
| SS Direct | `ss://base64(method:pass)@ip:port#名称-SS-Direct` |

支持客户端：v2rayN、Nekoray、Nekobox、Shadowrocket、Sing-box、V2Box、Karing、Clash Meta。

## 📄 开源协议

MIT License。
