# ArgoX-Mini 纯净版隧道管理面板

<p align="center">
  <a href="./README.md"><b>🌐 English</b></a>
</p>

---

一个极度精简的 Cloudflare Argo 隧道一键管理脚本，**VLESS + VMess + Shadowsocks** 多协议，WebSocket + TLS。

**ArgoX-Mini** 只装必需的：Xray-core + cloudflared。不装 Nginx / Caddy。Argo 协议入站仅监听 `127.0.0.1`，公网零端口暴露。可选 VLESS Reality 和 Shadowsocks 直连。

## ✨ 功能

- **多协议** — VLESS + VMess Argo（默认），可选 SS + Argo / VLESS Reality / SS 直连
- **交互式安装向导** — 7 步引导，每步有默认值，回车即用
- **一键导入链接** — 安装完打印所有协议链接 + QR，自定义节点名带后缀（`#东京-VLESS`）
- **节点管理（添加/编辑/删除）** — 菜单 `a`，增量操作不重装，每个参数可交互修改
- **编辑模式** — 修改加密方式、密码、端口、SNI、密钥对，回车保持当前值
- **SS 全部加密** — 7 种：`aes-128/256-gcm` / `chacha20/xchacha20-ietf-poly1305` / `2022-blake3-aes-128/256-gcm` / `2022-blake3-chacha20-poly1305`
- **VLESS Reality** — XTLS Vision + Reality，8 个伪装域名，自动 x25519 密钥对
- **零公网暴露（Argo 模式）** — 仅 `127.0.0.1`，免疫主动探测
- **固定隧道** — CF Zero Trust Token，临时/固定随时切换
- **持久化配置** — `/etc/xray/argox.conf`，重装自动继承
- **VPS 重启自启** — `systemctl enable`，开机自动拉起
- **13 个优选域名** — 三网通用 / 移动 / 联通 / 电信
- **端口冲突自动避让** — 安装/添加时自动找空闲端口
- **环境变量覆盖** — 非交互部署

## 🚀 安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

首次运行自动进入向导。非交互：

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
║     VL-Argo VM-Argo SS-Argo Reality SS-Dir      ║
╚══════════════════════════════════════════════════╝

  名称 : 东京-Aria    Xray: ● 运行中    Argo: ● 运行中
  UUID : abcd1234-...    域名 : xxx.trycloudflare.com

── 节点管理 ──
  1. 查看节点链接 (全部协议)
  2. 更换优选域名 / 线路
  3. 修改配置 (名称/UUID/隧道/加密/协议)
  a. 管理节点 (添加 / 编辑 / 删除)

── 服务控制 ──
  4. 启动    5. 停止    6. 重启 (刷新域名)

── 系统维护 ──
  7. 重新安装 (保留配置)    8. 更新    9. 卸载    0. 退出
```

### 菜单 3 子菜单

改名称 · 换 UUID · 切隧道 · SS 加密 · Reality SNI · 协议增删（需重装）· 查看链接 · 刷新域名

### 菜单 a 管理面板

```
╔══════════════════════════════════════════╗
║         管理节点                         ║
╚══════════════════════════════════════════╝

  ── 已安装 · 可编辑 ──
  e1. Shadowsocks + Argo  aes-256-gcm  端口 8083

  ── 可添加 ──
  a1. Shadowsocks 直连

  d. 删除节点    0. 返回
```

**编辑模式** (`e1`)：逐步修改加密 → 密码 → 端口，每步显示当前值，回车保持。Reality 额外支持换 SNI、重新生成密钥对。

**添加模式** (`a1`)：选加密 → 设密码 → 设端口 → 确认 → 自动写入配置 + 重启 Xray → 输出链接。

**删除模式** (`d`)：选节点 → 二次确认 → 删 inbound + 清理 fallback。

## 🏗 架构

```
客户端 → CF 边缘 (TLS:CDN_PORT) → Argo 隧道 → localhost:ARGO_PORT
                                                 Xray fallback
                                              ├── /vless-argo → VLESS+WS
                                              ├── /vmess-argo → VMess+WS
                                              └── /ss-argo    → SS+WS (可选)
直连 (可选):
  :<随机> VLESS+Reality  (0.0.0.0, x25519 密钥)
  :<随机> SS Direct      (0.0.0.0)
```

## 💻 客户端

复制终端输出的链接 → 客户端导入剪贴板。

| 协议 | 链接格式 |
|------|----------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#名称-VLESS` |
| VMess Argo | `vmess://base64(JSON)#名称-VMess` |
| SS Argo | `ss://base64(method:pass)@cdn:port#名称-SS-Argo` (WS+TLS) |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#名称-Reality` |
| SS Direct | `ss://base64(method:pass)@ip:port#名称-SS-Direct` |

客户端：v2rayN · Nekoray · Nekobox · Shadowrocket · Sing-box · V2Box · Karing · Clash Meta

## 📄 协议

MIT License
