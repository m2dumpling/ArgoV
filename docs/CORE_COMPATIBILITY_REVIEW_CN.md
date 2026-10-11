# ArgoV 内核特性与节点兼容性审视

核对日期：2026-10-11。核对对象是当前本地 `argov.sh`、订阅生成及转换代码、备用 Go 实现，包含本轮会话之前完成的 HY2 向导改动。服务器实际安装版本未读取。

结论：当前生成的整套服务端配置能通过 Xray 与 sing-box 稳定版校验。本轮已经修复 TLS 中继字段、证书指纹回填与导出、订阅参数传递，并补上内核升级预检和失败回滚。现有节点不自动迁移，WS、VMess、SS 继续保留。第 3 节记录修复前发现，第 6 节说明实际实施状态及兼容约束。

## 1. 官方版本与新增能力

| 内核 | 最新稳定版 | 最新预发布版 | 脚本当前选择方式 |
| --- | --- | --- | --- |
| Xray | [26.3.27](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)，2026-03-27 | [26.10.10](https://github.com/XTLS/Xray-core/releases/tag/v26.10.10)，2026-10-10 | 默认 GitHub `releases/latest/download`；可用 `XRAY_VERSION` 指定版本 |
| sing-box | [1.14.3](https://github.com/SagerNet/sing-box/releases/tag/v1.14.3)，2026-10-09 | [1.15.0-alpha.12](https://github.com/SagerNet/sing-box/releases/tag/v1.15.0-alpha.12)，2026-10-11 | 默认获取最新稳定版；可用 `SB_VERSION` 指定版本 |

Go 依赖 `github.com/xtls/xray-core v1.260327.0` 对应上述 Xray 稳定版；不能据此断言某台服务器上的独立二进制版本。Xray 版本号更大的近期发布均标记为预发布，默认下载逻辑不会主动切过去。

### Xray

| 能力 | 所处版本及影响 | 与 ArgoV 的关系 |
| --- | --- | --- |
| 原生 Hysteria2 入站及传输 | 26.3.27 加入完整 HY2 入站；QUIC 拥塞和带宽参数放进 Finalmask | 当前 HY2 实现已使用原生入站和 `finalmask.quicParams` |
| Finalmask 与 XHTTP 改进 | 26.3.27 增加流量外观选项，XHTTP/3 默认 BBR | 可以增加可选节点模板；现有 Argo 主链仍是 WS |
| REALITY、ECH 与 uTLS 改进 | 26.3.27 改进握手、目标探测、浏览器指纹及 ECH 行为；对非 443 监听和 Apple 类目标给出提示 | 脚本的 Reality 端口选择和目标检查需要跟进 |
| VLESS Encryption | 近几代已提供额外的协议层加密与前向保密；并非本次最新版本才出现 | 可作为新增模板；普通 VLESS + REALITY 仍可用 |
| MASQUE、XDRIVE、HY2 QUIC 扩展 | 26.10.10 预发布代码含 MASQUE、WARP 相关能力、XDRIVE，以及 BBR profile、Chrome QUIC 模拟等扩展 | 适合独立实验配置；不能把这些能力当作默认稳定版已有功能 |

稳定版更新依据：[26.3.27 发布说明](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)。VLESS 加密依据：[官方实现说明](https://github.com/XTLS/Xray-core/pull/5067)。预发布方向依据：[MASQUE 实现](https://github.com/XTLS/Xray-core/pull/6807)、[XDRIVE 实现](https://github.com/XTLS/Xray-core/pull/5645)、[26.10.10 QUIC 配置源码](https://github.com/XTLS/Xray-core/blob/v26.10.10/infra/conf/transport_finalmask.go)。

### sing-box

1.14.3 本身是修复版本；主要新功能来自 2026-08-31 发布的 1.14.0：

- HY2 增加 BBR 预设、Gecko 混淆、Realm/NAT 穿透和随机跳跃间隔；客户端默认模拟 Chrome 的 QUIC 握手。
- 新增 API 服务、Dashboard 与 `sing-box api` 命令，适合状态查看、日志与连接排障。
- 证书管理改为 certificate provider，支持 ACME 等提供者；HTTP/2、QUIC 参数也统一成共享配置。
- 增加 Snell、OpenVPN、OpenConnect、网络命名空间和内嵌 cloudflared 等能力。内嵌 cloudflared 入站的用途和当前 Argo WS 链路不同，不能直接用它替换现有连接方案。

依据：[1.14.0 发布说明](https://github.com/SagerNet/sing-box/releases/tag/v1.14.0)、[HY2 配置](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)、[cloudflared 入站](https://sing-box.sagernet.org/configuration/inbound/cloudflared/)。

1.15 目前仍是 alpha，新增 MASQUE、HTTP/2/3 与 CONNECT-UDP、完整证书 SHA256 固定以及新 TUN 栈。尤其 `certificate_sha256` 属于 1.15 的字段，不能写进 1.14.3 配置。依据：[1.15 更新记录](https://sing-box.sagernet.org/changelog/#1150-alpha7)、[TLS 字段版本说明](https://sing-box.sagernet.org/configuration/shared/tls/#certificate_sha256)。

## 2. 各节点现状

| 节点 | 当前判断 | 需要处理的细节 |
| --- | --- | --- |
| Argo VLESS + WS | 可用；WS 在 Xray 中已有弃用提示 | 增加可选 XHTTP；同步编辑后的路径；对新订阅参数进行完整转换 |
| Argo VMess + WS | 可用；协议与传输均有 Xray 弃用提示 | 作为兼容选项保留，新建时明确建议 VLESS；不要直接更改既有连接方式 |
| Xray VLESS + REALITY + Vision | 当前方案可用，`target` 字段已跟进 | 443 优先与冲突说明；对目标 TLS 能力进行检查；可选加密和签名扩展需客户端配合 |
| sing-box VLESS + REALITY | 当前配置可用 | 完善目标检查与端口编辑；不要直接套用 Xray 专属加密和签名字段 |
| Xray HY2 | 原生实现及 BBR/Brutal/Reno/协商模式均可加载 | TLS 证书模式、缺指纹处理、HTTP 伪装与混淆选项；为预发布字段变化准备版本适配 |
| sing-box HY2 | BBR/Brutal/协商与 1.14 BBR 预设已跟进 | 修正缺指纹时的证书回填来源；可选 Gecko/Salamander、HTTP 伪装、Realm；改善跳跃参数与恢复 |
| sing-box TUIC | 当前 UUID + 密码配置可用；BBR 本身没有过时 | 算法仍写死；自签证书链接只带 `insecure=1`，未输出证书固定信息 |
| sing-box AnyTLS + REALITY | 当前配置可用，协议没有过时 | 开放 padding 编辑与客户端兼容提示；`padding_scheme: []` 实际使用内核默认策略，并非关闭填充 |
| Xray / sing-box Shadowsocks | 当前 AEAD 及 SS2022 可用；Xray 对 SS 给出弃用提示 | 默认仍是 `aes-256-gcm`；明确 SS2022 的客户端条件，不把 SS2022 宣称为拥有前向保密的方案 |

弃用状态以实际 Xray 校验输出和对应版本源码为准：[WS 与传输解析](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go)、[VMess](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/vmess.go)、[Shadowsocks](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/shadowsocks.go)。这些是当前仍能加载的弃用功能，没有发现它们在本次测试的版本中已被删除。

AnyTLS 的空 padding 配置经源码确认会使用默认策略：[1.14.3 AnyTLS 实现](https://github.com/SagerNet/sing-box/blob/v1.14.3/protocol/anytls/inbound.go)。TUIC 可用算法按[官方 TUIC 配置](https://sing-box.sagernet.org/configuration/inbound/tuic/)处理。

## 3. 修复前发现的问题

本节保留审查依据与修复前代码位置；当前实施结果见第 6 节，不能将本节描述全部理解为仍未修复的问题。

### P1：中继 TLS 出站仍生成已失效选项

位置：`argov.sh:5184` 附近的 `relay_apply` / `apply_stream`。

导入带 `insecure=1` 或 `allowInsecure=1` 的 TLS 中继链接时，会生成 `tlsSettings.allowInsecure=true`。Xray 26.3.27 在 2026-06-01 之后拒绝此配置，26.10.10 也拒绝。这里影响的是 Xray 出站；不能据此认定 sing-box 的 `tls.insecure` 同时失效。

处理方向：有受信证书时正常校验；自签证书时完整传递证书指纹，生成 `pinnedPeerCertSha256`。当前解析器没有落实链接里的 `pcs` / `pinSHA256`。只有跳过验证、没有证书指纹的链接，需要给出可操作的提示，而不是继续生成被内核拒绝的配置。

依据：[26.3.27 TLS 解析源码](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go#L709)、[官方 TLS 配置](https://xtls.github.io/config/transports/tls.html)。本次已经用两个 Xray 二进制复现拒绝，并验证对应指纹字段可加载。

### P1：证书固定没有覆盖所有导出路径

位置：`gen_hy2_link`、`gen_sb_hy2_link`、`gen_sb_tuic_link`、独立订阅生成脚本，以及 `main_menu` 的指纹回填。

- HY2 链接已携带 `pinSHA256`，Mihomo 转换也携带指纹。但链接同时包含 `insecure=1`，其他客户端是否落实指纹取决于其导入实现，需要逐客户端验证。
- 没有指纹时，部分 HY2 导出仍退回 `allowInsecure=1`；新版 Xray 客户端一旦按这个参数生成出站就会遇到上述拒绝。
- TUIC 导出与转换只有跳过证书验证，没有对应证书固定。
- `main_menu` 回填 `SB_HY2_PIN_SHA256` 时读取的是共享 `SB_CERT_FILE`。HY2 已使用独立 `SB_HY2_CERT_FILE` 时，缺失指纹会被回填成其他证书的指纹。

证书指纹与公钥指纹不可混用：Xray 的 `pinnedPeerCertSha256` 是证书 DER 的 SHA256 十六进制；sing-box 稳定版的 `certificate_public_key_sha256` 是公钥指纹，1.15 新增的 `certificate_sha256` 才是完整证书指纹，使用 Base64。需要按内核、版本与客户端分开生成。依据：[Xray TLS](https://xtls.github.io/config/transports/tls.html#tlsobject)、[sing-box TLS](https://sing-box.sagernet.org/configuration/shared/tls/)。

### P1：订阅转换会丢掉新连接参数

位置：`argov.sh:2400` 附近的 `build_clash`，以及 `relay_apply` 的传输转换。

VLESS 转换固定写 `encryption: none`，传输主要只处理 WS。导入 XHTTP 或 VLESS Encryption 链接时，不能保留完整连接参数；其中部分链接会被输出成看似有效、实际无法按原方案连接的节点。当前 Mihomo 官方文档已经列出两种能力，因此不能再把问题归因于所有客户端均不支持。

处理方向：按协议、传输与客户端能力生成配置；对尚未支持的参数明确拒绝或展示原因。新增服务端模板必须同时更新普通 URI、Mihomo 订阅、中继解析和路径编辑。

依据：[Mihomo VLESS 文档](https://wiki.metacubex.one/config/proxies/vless/)。sing-box 1.14.3 的 VLESS 与传输配置没有对应的 XHTTP / VLESS Encryption 选项，仍需要提供它能使用的节点：[传输列表](https://sing-box.sagernet.org/configuration/shared/v2ray-transport/)、[1.14.3 VLESS 配置类型](https://github.com/SagerNet/sing-box/blob/v1.14.3/option/vless.go)。

### P1：Reality 安装默认随机高端口，缺少目标检查

位置：`argov.sh:4146` 附近的初次安装流程及两种内核的 Reality 编辑。

Xray Reality 端口为 0 时会随机选择 10000–60000。稳定版与本次测试的预发布版都对此给出提示。向导应优先提供空闲的 443，并在冲突时说明替代端口；目标域名应检查解析、连接及 TLS 1.3 能力。HY2 的自签证书域名和 Reality 的握手目标职责不同，不应复用同一套判断。

依据：[26.3.27 REALITY 更新说明](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)。这属于上游对连接环境的建议，不能承诺使用 443 或某个目标后一定不会受网络干扰。

### P2：HY2 的域名输入只设置证书与 SNI

首次安装已经允许用户输入域名和选择拥塞算法。当前域名用于自签证书与 TLS 握手，配置没有设置 HY2 的 HTTP `masquerade`。因此选择一个网站的域名，不会自动让服务端展示该网站的内容。

sing-box 可把 HTTP 伪装目标和证书域名单独配置；未配置伪装时返回默认 404。可以增加可编辑的伪装页面/目标、混淆方式与证书来源，并同步客户端配置。Gecko 等较新功能应标注版本和客户端条件，保留标准 HY2 作为兼容选择。依据：[HY2 入站的 masquerade 与 obfs](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)。

当前自签证书使用 RSA 2048，因此没有命中 sing-box 1.14 Chrome QUIC 模拟对 Ed25519 证书的兼容问题。不能将该上游变化误报成现有 HY2 节点必然握手失败。

### P2：跳跃参数需要区分内核版本和客户端

当前 sing-box 新向导把跳跃间隔重置为固定 30 秒，订阅转换也固定为 30；已有随机间隔字段没有完整进入导出。1.14 的 `hop_interval_max` 属于客户端出站能力，应完整传递或明确限制。

Xray 26.3.27 使用 `finalmask.quicParams.udpHop`，26.10.10 已把跳跃移到独立的 Finalmask UDP mask。预发布仍接受带旧字段的 JSON，但对应配置类型已没有旧字段；单靠“配置检查通过”不能证明该设置生效。当前服务端的端口范围转发主要依靠 iptables，所以不能把这个字段变化直接判定为现有服务端跳跃失效。

后续应按版本适配，同时检查客户端跳跃、服务端端口转发、重启后的规则恢复。依据：[上游跳跃迁移](https://github.com/XTLS/Xray-core/pull/6327)、[26.10.10 Finalmask 源码](https://github.com/XTLS/Xray-core/blob/v26.10.10/infra/conf/transport_finalmask.go)、[sing-box HY2 出站](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)。

### P2：升级与日志机制需要更强的兼容性检查

默认获取稳定版是合理选择，但内核替换应先校验现有配置，保留旧二进制，在服务无法启动时回滚。Xray 当前默认关闭日志，弃用提示也容易被安装/更新流程隐藏；菜单需要能查看核心版本和最近配置错误。

sing-box 的旧 DNS 格式已在 1.14 删除，旧入站 sniff 等字段已在 1.13 删除；当前模板及中继路由使用新规则动作和本地 DNS 类型，没有发现命中这些删除项。用户自行修改的配置和导入的完整配置仍需单独校验。新增证书管理时应使用 certificate provider，避免继续新增将被移除的内联 `tls.acme`。依据：[弃用清单](https://sing-box.sagernet.org/deprecated/)。

### P2：备用 Go 导出代码与 Bash 已不同步

`core/internal/sub/generator.go` 仍保留 `www.bing.com` 的缺省回退，HY2 链接也使用 `allowInsecure=1`，没有同步当前 Bash 的证书指纹与带宽导出。当前 Bash 安装/订阅流程没有调用该实现，因此它不是本次运行中的主链故障；启用 Go 实现前需要统一节点数据与导出规范。

## 4. 实测范围与结果

全部验证使用本机 WSL 的临时配置，不操作 VPS 服务或防火墙。

| 核验 | 结果 |
| --- | --- |
| Xray 26.3.27：Argo VLESS WS、VMess WS、Reality、HY2、SS、统计 API 完整生成配置 | 通过；输出 WS、VMess、SS、Reality 非 443 的提示 |
| sing-box 1.14.3：HY2、TUIC、AnyTLS Reality、VLESS Reality、SS 完整生成配置 | 通过 |
| Xray 26.10.10 预发布：同样的完整生成配置，含旧跳跃字段 | 通过加载；旧跳跃字段的实际作用需按源码和转发机制判断 |
| 两个 Xray 版本：TLS 出站使用 `allowInsecure=true` | 均拒绝，返回码 23 |
| 两个 Xray 版本：TLS 出站使用有效格式的 `pinnedPeerCertSha256` | 均通过配置校验；此处验证的是字段格式，未发起远端证书握手 |
| Xray 26.10.10：已有 HY2 算法测试，覆盖 BBR、Brutal、Reno、自动与旧 cubic 回退 | 通过 |

这里的“通过”表示配置可加载；实际 VPS 的 UDP 可达性、CDN 链路和各 GUI 客户端导入结果尚未验证。

## 5. 建议实施顺序

1. 修复 TLS 中继旧字段、指纹回填来源和 TUIC 证书验证；覆盖所有订阅出口。
2. 完善升级前检查与失败回滚、Reality 端口及目标检测、协议编辑后的订阅同步。
3. 增加可选 VLESS + XHTTP 和 VLESS Encryption，配套 URI、Mihomo 转换与客户端能力提示；保留既有连接方案。
4. 扩展 HY2 的证书来源、HTTP 伪装、混淆与跳跃编辑；用版本判断隔离预发布配置变化。
5. 再评估 API / Dashboard、Realm、Snell、MASQUE 等新增功能的实际需求，避免把每个上游功能都默认启用。

## 6. 已落实的修改与存量兼容约束

| 修改 | 当前实现 | 存量节点保护 |
| --- | --- | --- |
| TLS 中继 | 解析 `pcs`、`pinSHA256`、`pinnedPeerCertSha256`，输出新 Xray 证书固定字段；保留 ALPN、uTLS 指纹、gRPC、HTTPUpgrade、XHTTP 及 VLESS Encryption 参数 | 不自动重写现有出站；新导入缺指纹的跳过验证链接明确拒绝，原配置与服务保持原状 |
| 双核中继证书 | sing-box 1.14 使用独立的公钥 SHA256；支持完整证书固定的 1.15 版本才生成 `certificate_sha256` Base64 | 不把证书摘要冒充公钥摘要；无法准确表达时在写配置之前拒绝，提示使用双核兼容链接 |
| HY2 指纹回填 | 优先读取实际入站证书，独立 HY2 不再误读 TUIC 共享证书；订阅每次读取实际证书，缺文件时保留有效历史指纹 | 回填只更新指纹元数据，不换证书、密钥、域名、端口或用户身份 |
| TUIC 分享与订阅 | 普通链接、默认订阅、独立用户订阅均携带证书指纹；Mihomo 使用正确的 `congestion-controller` 字段 | 保留旧 URI 的 `insecure=1`；支持指纹的 Mihomo 使用固定证书验证，旧无指纹链接仍按原行为转换 |
| HY2 链接 | 不再导出失效的 `allowInsecure=1`，统一携带证书固定信息与 Brutal 带宽方向 | 保留旧 URI 客户端的 `insecure` 参数与两个 HY2 前缀，不改服务器连接身份 |
| 订阅转换 | 不再强制覆盖 VLESS Encryption；支持 XHTTP 常用 extra / XMUX、gRPC、HTTPUpgrade；路径只解码一次 | 普通 VLESS 仍缺省 `encryption=none`；复杂未支持参数给出注释，完全转换失败时保留已有缓存，原始 URI 保留 |
| WS 路径导出 | 普通分享、独立订阅读取实际入站路径；VMess JSON 使用安全编码 | 默认旧路径与早期数据参数保留；不会改写服务端路径 |
| 订阅程序生成 | 节点名、Token、路径通过 JSON 编码传入 Python，语法检查通过后替换程序 | 保留原 Token、路径和名称，支持引号、反斜杠与换行；生成失败保留旧程序 |
| Xray / sing-box 升级 | 候选二进制先验证现有配置，替换后检查服务，失败恢复旧二进制；保留 `.argov-previous` | 不停止服务后才发现不兼容；原本停止的服务不自动启动；配置缺失且服务正在运行时拒绝升级；升级不重建节点和证书 |
| 备用 Go HY2 导出 | 同步实际 SNI、证书指纹、带宽方向与 IPv6，去掉 Bing 回退和旧 TLS 选项 | 读取已有配置，不自动迁移节点；当前 Bash 主链仍不依赖此实现 |

未自动启用 XHTTP 服务端新模板、VLESS Encryption 服务端加密、Gecko、Realm、MASQUE、证书提供者或新的 padding；也未把旧 VMess / WS / SS 节点改成其他协议。Reality 443 优先和目标检查、TUIC 算法编辑、复杂 XHTTP 下载分离参数等仍是后续可选工作，不能用不完整转换替代客户端所需参数。后续灰度修订已补齐 Sing-box 跳跃的首次规则应用和 systemd / OpenRC 开机恢复；真实 VPS 重启后的规则与连通仍需验证。

### 旧 TLS 中继如何补充指纹

旧节点正在运行时，更新脚本不会自动重新配置中继。如果主动升级 Xray 时旧 TLS 配置被新内核拒绝，会保留旧内核；修正中继链接后再升级。完整证书指纹与公钥指纹应由落地服务端现有证书计算，不重新签发：

```bash
# pcs / pinSHA256：完整证书的 SHA256 十六进制，允许保留冒号
openssl x509 -in /path/to/cert.pem -noout -fingerprint -sha256

# certificate_public_key_sha256：公钥 SPKI 的 SHA256 Base64
openssl x509 -in /path/to/cert.pem -pubkey -noout |
  openssl pkey -pubin -outform DER |
  openssl dgst -sha256 -binary |
  openssl base64 -A
```

双核中继在 sing-box 1.14 上需要同时提供对应的公钥指纹。把 Base64 放进 URI 查询参数前应 URL 编码，避免 `+` 被解释为空格。受信证书则保留正常证书验证，无需上述固定参数。

### 新增验证

新增 23 项兼容测试，另保留原 23 项交互测试及已有静态、订阅、迁移、中继测试，备用 Go 导出测试通过。

- Xray 26.3.27 与 26.10.10、sing-box 1.14.3 校验实际生成的节点和中继配置。
- Xray TLS 中继使用本机自签证书真实握手：正确指纹传递原口令，错误指纹拒绝连接。
- Mihomo 1.19.32 真实校验 HY2、TUIC、VLESS Encryption + XHTTP 配置；通过 SOCKS 实际连接本机 sing-box TUIC 节点并回传数据，证书固定有效。
- TUIC 连通测试先等待双核启动与监听就绪，再发起连接，并使用收发确认后关闭回显连接；修正测试的启动时序竞争，连续重复 10 次通过。
- 预检拒绝不替换内核、不重启；启动失败回滚旧二进制；停止服务保持停止；运行中配置缺失拒绝升级。
- 服务检测直接调用原生 systemctl，避免脚本包装函数误读 `--quiet`；新增测试经过实际服务适配函数验证双核重启失败回滚，并覆盖 OpenRC 的 started / stopped / crashed 状态。
- 证书、私钥、入站配置保持字节不变；域名、端口、UUID、密码与订阅 Token 保留；包含特殊字符的订阅程序能正常解析。
- 既有 Xray 与 sing-box HY2 落地中继连通测试通过。

上述测试使用隔离的本机 WSL 临时目录和回环地址，未操作真实 VPS。未承诺所有历史 GUI 客户端与任意用户自定义配置都兼容；新内核遇到无法加载的现有配置会阻止升级，保留旧内核，避免把运行中的节点直接切到不兼容版本。sing-box 1.15 的摘要编码与版本门槛有单独测试，本轮没有运行该 alpha 的二进制。

### 2026-10-11 最终本地复核

| 检查 | 结果 |
| --- | --- |
| `bash tests/argov_static_tests.sh argov.sh`，PATH 提供 Xray 26.3.27、sing-box 1.14.3、Mihomo 1.19.32 | Bash 语法、全部七组 Python 测试通过；23 项交互和 23 项内核兼容测试均通过，没有跳过 |
| 同一完整测试入口，将 Xray 替换为 26.10.10 预发布二进制 | 同样通过，没有跳过；不据此默认安装预发布内核 |
| `tests/argov_relay_tests.py`，明确传入真实 Xray、openssl、sing-box 路径 | 真实 Xray / sing-box HY2 中继、Shadowsocks 中继和统计 API 验证通过 |
| `go test ./...` | 当前 Go 包全部通过编译及测试 |
| `git diff --check` | 通过 |

内核升级拒绝、重启失败回滚和停止状态保留采用模拟服务验证；证书握手、TUIC 与中继数据回传使用真实内核。尚未覆盖真实 VPS 的 systemd / OpenRC 服务生命周期、公网 UDP 与防火墙、开机恢复、Cloudflare / Argo 链路及全部旧 GUI 客户端。当前可推送开发分支供审查；正式发布前仍应在有备份的测试 VPS 上验证首次安装及存量升级。

### 灰度反馈后的默认值与跳跃修订

用户确认本次公网超时与原 VPS IP 有关，换机重测；没有根据该日志修改路由。按反馈将无已有值时的 Brutal 服务器下载默认值改为 200 Mbps，新建双核 HY2 默认启用跳跃，已部署节点保留原带宽和跳跃开关。两组默认范围避开彼此、其他已配置端口及实际 UDP 监听。

同时修复首次安装 Sing-box HY2 未应用跳跃规则的问题，补齐 systemd / OpenRC 开机恢复。规则安装失败时关闭跳跃后再生成配置；关闭仅清理项目所属规则和恢复服务。恢复脚本采用先检查再添加，重复启动不会叠加规则。

修订后使用稳定 Xray 26.3.27，以及预发布 Xray 26.10.10，分别配合 sing-box 1.14.3、Mihomo 1.19.32 运行完整七组 Python 测试：两轮均通过，30 项交互和 23 项兼容测试没有跳过。新增规则与服务测试使用模拟命令和临时路径；真实 VPS 的公网 UDP、系统服务及重启恢复仍需按 [灰度指南](VPS_CANARY_VALIDATION_CN.md) 验证。

### Sing-box 只装内核与残留进程修订

灰度日志和 `/proc/<MainPID>/exe` 确认：内核文件已被删除，原进程仍运行，同时配置和服务文件缺失。保留阻止升级的保护，改为明确提示安装文件丢失；预检拒绝不再误报为下载失败。卸载必须确认服务及对应 PID 已停止，否则取消删除文件。

首次安装只询问是否安装 Sing-box 内核，使用版本化 release 直接安装二进制并准备未启用的服务，不调用会自动启动服务的系统安装器。协议在 `s → s2` 后续增配；首个协议验证成功后启动并启用服务，已有节点配置及原有开机设置不因首次向导或追加编辑而重建。无可验证配置时，启动/重启会拒绝执行并给出增配或恢复提示。

运行中使用自定义配置路径时，升级预检读取真实进程的 `-c` / `-C` 参数与实际工作目录；不把这些路径自动迁入 ArgoV 的协议管理配置。仍无法确认配置时取消升级。正常停止、尚无节点的纯内核安装可以升级二进制，同时保持未启动且不创建空节点配置。

最终本地验证：稳定 Xray 26.3.27 和预发布 26.10.10，分别与 sing-box 1.14.3、Mihomo 1.19.32 运行完整七组 Python 测试，两轮均通过；37 项交互及 27 项兼容测试无跳过。真实内核覆盖归档安装、删除文件后的存活进程、配置目录与相对工作目录、预检失败保留原进程；服务创建、开机设置及停止失败采用模拟命令。尚未在用户 VPS 上执行修复或验证公网与真实系统服务。
