# 开发分支 VPS 灰度验证

适用分支：`hy2-compatibility-update`。以下命令按 Debian / Ubuntu、root、systemd 编写。干净 VPS 可以验证首次安装；保护旧用户还需要第二轮“旧版先部署，再运行新版”的升级验证。

灰度期间始终运行检出的 `argov.sh`。现有 `ag` 快捷命令与主菜单 `8` 都下载 `main`，会切回旧管理脚本。菜单 `7` 是重装，不能当作仅更新脚本的测试入口。测试版本固定 Xray `v26.3.27`、sing-box `1.14.3`，与本地已验证的稳定版一致。

## 一、准备与固定版本

先在云平台保存干净系统快照，方便第二轮恢复。同一台测试 VPS 的公网 IP 保持不变。

```bash
sudo -i
apt-get update
apt-get install -y ca-certificates curl git jq openssl unzip python3 iproute2 iptables
git clone --branch hy2-compatibility-update --single-branch \
  https://github.com/m2dumpling/ArgoV.git /root/argov-canary
cd /root/argov-canary
git rev-parse HEAD
bash -n argov.sh
```

核对提交号与推送时给出的提交号相同。分支之后继续更新时，可用 `git checkout <本次提交号>` 固定测试内容。

如果已有检出目录（包括固定在旧提交的情况），获取修订后再固定到本次提供的提交号：

```bash
git -C /root/argov-canary fetch origin hy2-compatibility-update
git -C /root/argov-canary checkout <本次提交号>
```

## 二、干净安装

```bash
cd /root/argov-canary
XRAY_VERSION=v26.3.27 SB_VERSION=1.14.3 bash ./argov.sh
```

第一轮先验证直连，建议按下表填写；带宽应填写 VPS 实际可用值。

| 向导项 | 本轮选择 |
| --- | --- |
| 名称 | `canary-vps` |
| Argo 隧道 | 先选择跳过；直连通过后单独验证 Argo |
| 订阅域名 | 回车跳过，HTTP 端口选择 `18080` |
| Xray 协议 | 选择 HY2，端口 `32443`；输入自己想用的 SNI 域名，算法选 BBR，回车接受跳跃范围（通常 `47000-48000`） |
| Sing-box | 安装；选择 HY2、TUIC，端口分别为 `33443`、`34443`；使用两个不同 SNI 域名，HY2 选 Brutal；无已有值时服务器上传默认 100、下载默认 200 Mbps，可改为实际可用值；回车接受跳跃范围（通常 `49000-50000`） |
| 确认 | 核对摘要后确认安装 |

HY2 / TUIC 的域名用于自签证书与 TLS 握手，连接地址仍为 VPS IP；不要求这些域名指向 VPS。订阅 HTTPS 域名则是另外一种配置，后续验证时需要实际 DNS 与证书设置。

在云安全组和 VPS 防火墙放行本轮选择的 TCP `18080`，以及 UDP `32443`、`33443`、`34443` 和两个完整跳跃范围（通常是 `47000-48000`、`49000-50000`）。冲突时默认范围会调整，以最终摘要为准；SSH 端口保持开放。跳跃由 NAT 转发到单个监听端口，`ss` 不会显示整个范围都有监听。

安装结束后，在另一个 SSH 会话检查：

```bash
/etc/xray/xray version
sing-box version
XRAY_LOCATION_ASSET=/etc/xray /etc/xray/xray run -test -config /etc/xray/config.json
sing-box check -c /etc/sing-box/config.json
systemctl is-active xray sing-box argov-sub
systemctl is-enabled argov-hy2-hop argov-sb-hy2-hop
iptables -t nat -S PREROUTING
ss -lntup
journalctl -u xray -u sing-box -u argov-sub -n 80 --no-pager
```

应当看到两个内核及订阅服务为 active，配置检查成功，选定端口有监听，日志没有持续崩溃或反复重启。上游对 WS、VMess、SS 的弃用提示与致命启动错误应分开判断。

## 三、客户端与编辑验证

从 VPS 外部网络导入面板 `1` 显示的订阅，至少使用一个 Mihomo 客户端；再用已有用户实际使用的客户端验证普通分享链接。订阅是访问凭据，测试产物留在自己设备上。

| 检查 | 通过标准 |
| --- | --- |
| Xray HY2、Sing-box HY2、TUIC | 每个节点分别能访问网页并传输文件；外部网络成功，不能只看 VPS 自身 curl 成功 |
| 订阅 | 更新返回成功，包含实际启用的三个节点；域名、端口、指纹正确 |
| Brutal | 客户端收到带宽值；服务器上传对应客户端下行，服务器下载对应客户端上行 |
| 证书隔离 | 修改 Sing-box HY2 域名后，刷新订阅使 HY2 恢复连接；原 TUIC 分享链接仍能连接 |
| 固定证书 | 在一个临时 Mihomo 配置副本中改错指纹后，该节点连接失败；恢复正确指纹后成功 |
| 输入与取消 | 错误域名 / 端口重试；输入 cancel 返回；取消不改变原节点连接参数 |
| 算法切换 | Xray HY2 逐次验证 BBR、Brutal、Reno、协商；Sing-box HY2 验证 BBR、Brutal、客户端协商；每次检查配置并重新连通 |
| 重启 | 在 SSH 中运行 `reboot`，重新登录后重复服务状态、订阅及三节点连通检查 |

编辑入口必须从本次脚本打开：

```bash
bash /root/argov-canary/argov.sh
```

Xray HY2 使用 `a → e4`；Sing-box 使用 `s → s2 → e1` 编辑 HY2，其余编号按菜单显示。测试改变跳跃范围和输入 `off` 关闭，再启用：每次放行最终完整 UDP 范围，刷新客户端订阅，核查 NAT 规则与开机恢复服务。双核均应在重启后恢复规则并继续连接。若需要区分基础连接和跳跃问题，主动输入 `off`，先用三个监听端口验证，再逐核开启跳跃。

仅运行新版脚本不自动改变已有节点的跳跃开关、范围或带宽；旧节点需要主动进入上述编辑入口才会应用新的规则恢复流程。

直连通过后，再测试 Reality / SS、Argo 的 VLESS / VMess、HTTPS 订阅、普通与限额用户，以及已有生产环境实际使用的中继 / WARP / 聚合功能。每次新增一种能力，先核查配置和服务，再使用外部客户端连接；Argo 临时域名变化需要刷新订阅。

## 四、旧部署升级兼容性

保存第一轮测试记录与快照，再恢复之前的干净系统快照，重新执行准备命令。此轮先部署旧脚本，模拟已有用户；不要在已经新装的配置上假装进行了旧版升级。

```bash
cd /root/argov-canary
git show 85864b33511de529cc1aaa0dae10e34878e48b33:argov.sh > /root/argov-legacy.sh
XRAY_VERSION=v26.3.27 SB_VERSION=1.14.3 bash /root/argov-legacy.sh
```

旧版安装选择实际要保留的节点，至少包含 Xray HY2、Sing-box HY2 和 TUIC；若老用户使用 WS / VMess / Reality / SS，也一并覆盖。先确认这些旧节点均能从外部连接，保存原分享链接和订阅地址。在云平台保存“旧版已正常运行”的快照。

记录身份与备份，以下操作在测试 VPS 上执行：

```bash
install -d -m 700 /root/argov-before-update
tar -C / -czf /root/argov-before-update/xray.tgz etc/xray
if [ -d /etc/sing-box ]; then
  tar -C / -czf /root/argov-before-update/singbox.tgz etc/sing-box
fi
if command -v sing-box >/dev/null; then
  cp -p "$(command -v sing-box)" /root/argov-before-update/sing-box
fi
sha256sum /etc/xray/config.json /etc/sing-box/config.json \
  /etc/xray/xray "$(command -v sing-box)" > /root/argov-before-update/config-core.sha256
find /etc/xray /etc/sing-box -type f \
  \( -name '*.crt' -o -name '*.pem' -o -name '*.key' \) -print0 |
  sort -z | xargs -0 -r sha256sum > /root/argov-before-update/certs.sha256
jq -S '[.users[] | {name,uuid,token,sb_ports,sb_creds}]' \
  /etc/xray/argov_users.json > /root/argov-before-update/user-identity.json
systemctl show xray sing-box -p Id -p MainPID -p ActiveState \
  > /root/argov-before-update/services.txt
```

以上摘要命令按本轮已安装双核编写。保留备份目录权限；其中包含凭据和私钥。若自定义证书位于其他目录，也应备份实际配置引用的文件。

现在只打开新版管理脚本，查看面板并退出，不选择重装、编辑、启动停止或内核升级：

```bash
bash /root/argov-canary/argov.sh
sha256sum -c /root/argov-before-update/config-core.sha256
sha256sum -c /root/argov-before-update/certs.sha256
jq -S '[.users[] | {name,uuid,token,sb_ports,sb_creds}]' \
  /etc/xray/argov_users.json > /root/argov-before-update/user-identity-after.json
diff -u /root/argov-before-update/user-identity.json \
  /root/argov-before-update/user-identity-after.json
systemctl show xray sing-box -p Id -p MainPID -p ActiveState
```

通过标准：配置、内核、证书摘要均匹配，用户身份没有差异，两个内核的 PID 未改变；原客户端无需重新导入仍能连接，原订阅 URL 仍有效。`argov.conf` 可能回填证书指纹等元数据，流量计数也会增长，这些变化不能直接视为节点身份改变。

## 五、主动升级内核与恢复

存量兼容检查通过后，从新版脚本选择 `x` 更新 Xray、`s → s1` 更新 Sing-box。持久化配置已固定到本轮稳定版，因此可能是同版本重新安装，仍能验证替换与服务重启路径；验证跨版本时需要单独选定已测试的候选版本，不应同时改协议、域名和凭据。

- 正常升级后：配置和证书摘要仍匹配；只比较 `config-core.sha256` 中配置两行，内核摘要可能变化。旧二进制旁出现 `.argov-previous`，两个服务正常，旧客户端仍连通。
- 停止状态：先在测试 VPS 停止一个内核，再更新该内核；更新结束后仍应为 inactive。随后手动启动并重新连接。
- 不兼容预检与故障回滚：先在云平台再保存快照，再单独设计故障注入；检查候选配置被拒绝时旧服务 PID 和二进制不变，重启失败时旧二进制和服务被恢复。首次灰度不需要直接破坏正在测试的配置；本地已有对应自动回归，真实故障注入可作为第二轮专项测试。

发生故障时保留服务日志，停止继续叠加修改。恢复“旧版已正常运行”的 VPS 快照，可以同时恢复配置、证书、二进制和服务定义。仅运行旧管理脚本不能代替恢复已经改变的运行环境。

Alpine VPS 的服务检查改用 `rc-service xray status`、`rc-service sing-box status`、`rc-service argov-sub status`；依赖安装使用 apk。systemd 灰度通过不等于 OpenRC 已验证。

## 六、发布验收

记录 OS / 架构、脚本提交、实际内核版本、客户端版本、测试节点、结果及脱敏日志。首次安装、旧版升级、原订阅与节点身份、编辑、内核更新、重启和生产实际使用的链路均通过后，连续观察至少 24 小时；没有反复重启、订阅失败或 UDP 间歇中断，再考虑合并 main。未完成的功能测试应明确列出，不能标为全环境验证通过。
