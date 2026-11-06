# Xray 配置校验与版本兼容性复核

日期：2026-11-06。复核 `argov.sh` 的全部 Xray 配置校验入口，并使用多个真实内核运行隔离回归。版本清单取自 [Xray 官方发布记录](https://github.com/XTLS/Xray-core/releases)。

## 调用点审计

修复前，直接执行 `xray run -test` 的位置共有四处：

| 入口 | 校验对象 | 审计结果与处理 |
| --- | --- | --- |
| `commit_xray_candidate` | Argo、HY2、WARP 的随机后缀候选文件 | 上次修复已补 `.json` 后缀；本次接入统一校验入口 |
| `activate_core_binary` | 已有配置，使用待升级的新内核 | 默认文件为 `config.json`，没有同类后缀问题；继续使用候选内核预检，并保留已安装资源目录 |
| `relay_apply` | 添加中继后生成的 `config.json` | 原路径有合法后缀；接入统一入口，保留原有失败回滚 |
| `relay_clear` | 移除中继后的 `config.json` | 原路径有合法后缀；接入统一入口，保留原有失败回滚 |

当前只有 `validate_xray_config` 直接调用 `run -test`。它显式指定 JSON 格式，普通 `.json` 文件按原路径检查；其他后缀通过官方支持的 `stdin:` 读取同一个文件，不改变文件内容、位置或当前工作目录。两代实现均支持该入口：[26.7.28](https://github.com/XTLS/Xray-core/blob/v26.7.28/main/confloader/external/external.go#L18)、[26.10.31](https://github.com/XTLS/Xray-core/blob/v26.10.31/main/confloader/external/external.go#L20)。

候选配置提交仍保留上次发布的 `.json` 重命名与原子替换；统一入口同时覆盖未来可能传入的特殊文件名。没有新增运行依赖，仍以单个 `argov.sh` 部署。

## 补齐的预检与回滚

Reality、Shadowsocks 的旧增改流程直接覆盖配置后重启，普通协议删除也缺少内核预检。本次改为：

1. 确认操作后，备份配置、用户及证书。
2. 生成候选配置，交给当前安装的 Xray 校验。
3. 校验通过后替换配置、保存元数据并重启；配置或服务失败时恢复快照。

Reality 的域名、密钥和 Short ID 修改合并为一次候选 JSON 写入，保留其他用户、入站和路由。操作在函数的独立 Shell 环境中执行，取消或失败时不会把中途修改的变量留给面板。原 `edit_protocol hy2` 入口转交已有 HY2 编辑流程。

HY2 删除会在配置校验与重启成功后再移除原跳跃规则，避免校验失败时先拆掉仍在使用的规则。安装流程在用户同步之后、创建和启动服务之前增加内核校验；不兼容时报告失败并停止后续启动。这一检查不代表安装全流程已经具备事务回滚。

## 验证版本与范围

| Xray 版本 | 官方发布类型 | 本次内核来源 |
| --- | --- | --- |
| 26.10.31 | 稳定版，当前 latest | 官方 Linux amd64 发布包，核对 SHA256 |
| 26.10.21 | 稳定版 | 官方 Linux amd64 发布包，核对 SHA256 |
| 26.9.30 | 预发布版 | 官方 Linux amd64 发布包，核对 SHA256 |
| 26.9.9 | 预发布版 | 官方 Linux amd64 发布包，核对 SHA256 |
| 26.7.28 | 预发布版 | 官方 Linux amd64 发布包，核对 SHA256 |
| 26.3.27 | 历史稳定版基线 | 从项目固定依赖 `v1.260327.0` 构建的测试内核 |

上述六个版本均完成 **115 项回归，全部通过、零跳过**，合计 690 项执行。每版还运行同一组静态、历史配置、订阅、迁移和中继检查。测试环境同时提供 Sing-box 1.14.3、Mihomo 1.19.33；实际版本、主脚本与二进制摘要及耗时记录在 [验证清单](validation/xray-matrix-20261106.json)。

额外逐版本运行了真实 `relay_apply` / `relay_clear` 函数，配置使用带空格的非标准后缀路径，均通过内核校验；另启动本地 StatsService，验证现有 `api statsquery --server ... --pattern ... --reset` 命令能够查询并返回有效 JSON。服务与中继目标仍在隔离测试环境中。

每个版本运行同一套检查，覆盖：

- 完整安装配置模板：两种 Argo、Reality、7 种 SS 加密方式、HY2 的 auto/BBR/Brutal/Reno，包含跳跃和多用户同步。SS 与 HY2 参数组合共 28 组。
- Argo 独立增删改、最后一种协议的隧道启停、重装选择保留，以及三种 Argo 组合的实际回环 WebSocket/SOCKS/HTTP 流量。
- Reality、SS2022、HY2 的实际增删改路径；其他入站、用户和路由保持一致。
- 无效 SS2022 密钥、无效 Reality Short ID、候选配置拒绝、重启失败，以及原配置与元数据恢复。
- 标准路径、带空格或单引号的特殊后缀文件、无效 JSON、缺少内核或配置，以及使用新内核校验后再替换二进制。
- 三种 WARP 模式、TLS 中继、分享链接、订阅、证书、用户迁移、统计采集和 Sing-box 配套回归。

服务管理器与防火墙命令使用隔离替身，不操作宿主系统。真实网络测试在本机回环执行，不能代替每台 VPS 的公网、Cloudflare 隧道及客户端互通验证；ARM、32 位及其他操作系统未实测。26.3.27 之前的版本和未来版本不在本次验证清单内。

## 重复验证

在 Linux 或 WSL 的仓库根目录准备 Bash、Python、jq、openssl，以及放入 PATH 的 Sing-box、Mihomo。Xray 二进制须事先取得并校验；测试工具不会下载或安装内核。

```bash
python3 tests/run_xray_matrix.py \
  --xray /path/to/xray-26.10.31 \
  --xray /path/to/xray-26.10.21 \
  --xray /path/to/xray-26.9.30 \
  --report /tmp/argov-xray-matrix.json
```

可重复指定更多 `--xray`。工具逐版本隔离 PATH，运行 `tests/argov_static_tests.sh`，保存实际版本、二进制与主脚本 SHA256、检查数量、耗时和完整日志。失败或存在跳过项均返回失败。

## 已部署 VPS 更新

退出旧面板，在 SSH 重新执行 `ag` 即可获取脚本修复。无需重装或为了这次脚本更新替换 Xray；已有节点与核心版本保留。再次添加、编辑或删除节点时才执行相应预检与重启。内核升级仍从菜单 `x` 主动执行，并先用候选新内核校验当前配置。
