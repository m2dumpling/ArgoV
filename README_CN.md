# ArgoX-Mini 纯净版隧道管理面板

一个极度精简的 Cloudflare Argo 隧道管理脚本，**VLESS + VMess + Shadowsocks + VLESS Reality**，内置 **WARP 域名分流** 和 **订阅服务器**。

只装必需的：Xray-core + cloudflared。不装 Nginx、不装 Caddy。Argo 入站仅监听 `127.0.0.1`，公网零端口暴露。完整支持 Debian / Ubuntu / CentOS / Alpine。

## ✨ 功能

**核心**
- VLESS + VMess Argo 隧道（默认安装）。可选：Shadowsocks、VLESS Reality
- 8 步交互式安装向导，系统自动识别 + 端口自选
- `vless://` / `vmess://` / `ss://` 一键导入链接 + 订阅二维码

**订阅服务器** — 重启自动恢复，零 SSH
- 双模式：`https://你的域名:端口/sub?token=xxx` 或 `http://IP:端口/TOKEN`
- 自签证书支持 HTTPS（兼容 CF Full SSL），CF 端口自选（2096/8443/2053等）
- Random token 防偷，Python3 极简 HTTP server（15 行）
- 每次请求实时生成最新链接，改配置即时同步

**节点管理** — 菜单 `a`
- 添加、编辑、删除任意协议，不重装
- Argo VLESS/VMess：端口、路径可编辑，自动同步 fallback 路由
- Shadowsocks：7 种加密（AEAD + SS2022），加密/密码/端口可编辑
- Reality：8 个伪装域名，SNI/端口/shortId/指纹/密钥可编辑

**WARP 域名分流** — 菜单 `w`
- 一键安装 fscarmen WARP（SOCKS5 :40000 / IPv6 WireGuard）
- 自定义分流域名或注入 Google/YouTube 默认组
- 三种模式：全 SOCKS5 / 全 IPv6 / 智能分流（Google→IPv6 + YouTube→SOCKS5）
- Python3 安全改写 config.json，自动校验，写入失败自动回滚

**安全与兼容**
- 零公网暴露（Argo 模式），仅 `127.0.0.1`，免疫主动探测
- 固定 Argo 隧道 + 临时隧道，随时切换
- 持久化配置 `/etc/xray/argox.conf`，重装不丢
- 开机自启，tunnel 崩溃自动重试（Alpine 网络等待 30s）
- Alpine Linux 完整支持（openrc / apk / init.d）
- 服务名独立为 `argox-tunnel`，不与已有隧道冲突
- 13 个优选 CDN 域名，端口冲突自动避让
- 环境变量一键部署

## 🚀 安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
```

非交互：
```bash
NODE_NAME=东京 CDN_DOMAIN=skk.moe bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
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

  名称 : 东京    Xray: ● 运行中    Argo: ● 运行中

── 节点管理 ──
  1. 查看链接    2. 更换 CDN    3. 修改配置    a. 管理节点
── 服务控制 ──
  4. 启动    5. 停止    6. 重启/恢复
── 系统维护 ──
  7. 重装(保留)    8. 更新    9. 卸载    0. 退出    w. WARP分流
```

### 安装向导

```
━━━ ① 节点名称 ━━━  ② CDN 地址 ━━━  ③ 客户端端口 ━━━
④ UUID ━━━  ⑤ Argo 隧道类型 ━━━  ⑥ 内部端口 ━━━
⑦ 订阅域名（可选，CF 端口自选）━━━  ⑧ 额外协议 ━━━
```

## 💻 客户端

复制终端输出的链接 → 导入剪贴板，或填入订阅 URL 一键导入。

| 协议 | 链接格式 |
|------|----------|
| VLESS Argo | `vless://uuid@cdn:port?...&path=%2Fvless-argo#名称-VLESS` |
| VMess Argo | `vmess://base64(JSON)#名称-VMess` |
| SS | `ss://base64(method:pass)@ip:port#名称-SS` |
| Reality | `vless://uuid@ip:port?...&security=reality&pbk=xxx#名称-Reality` |

客户端：v2rayN · Nekoray · Shadowrocket · Sing-box · Clash Meta

## 📄 协议

MIT License
