#!/usr/bin/env python3
import re
import sys
from pathlib import Path


script = Path(sys.argv[1])
text = script.read_text(encoding="utf-8")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def require(pattern: str, message: str, flags: int = 0) -> None:
    if not re.search(pattern, text, flags):
        fail(message)


def forbid(pattern: str, message: str, flags: int = 0) -> None:
    if re.search(pattern, text, flags):
        fail(message)


require(
    r'\*\)\s+command systemctl "\$cmd" "\$@"',
    "non-Alpine systemctl wrapper must call command systemctl to avoid recursion",
)
require(r"save_var\(\)", "save_conf must use a shell-escaping save_var helper")
require(
    r"save_var NODE_NAME \"\$NODE_NAME\"",
    "NODE_NAME must be persisted through save_var so quotes cannot break argov.conf",
)
require(
    r"get_cdn\(\)[\s\S]*\[\s+-n \"\$v\"\s+\].*\[\s+\"\$v\"\s+!= \"null\"\s+\]",
    "get_cdn must fall back when current_cdn is empty or null",
)
require(
    r"interactive_install\(\)[\s\S]*select_protocols[\s\S]*do_install",
    "interactive install must call select_protocols before do_install",
)
forbid(
    r'echo "https://\$\{SUB_DOMAIN\}:\$\{SUB_PORT\}/sub\?token=\$\{SUB_TOKEN\}#\$\{NODE_NAME\}"',
    "subscription URLs must not append raw NODE_NAME fragments because strict clients can reject non-ASCII or spaces before sending the request",
)
forbid(
    r'echo "http://\$\{1:-127\.0\.0\.1\}:\$\{SUB_PORT\}\$\{SUB_PATH\}#\$\{NODE_NAME\}"',
    "HTTP subscription URLs must not append raw NODE_NAME fragments because strict clients can reject non-ASCII or spaces before sending the request",
)
require(
    r"json\.dumps\(v,\s*ensure_ascii=False\)",
    "Clash YAML strings must preserve UTF-8 instead of emitting surrogate escapes such as \\ud83d\\ude80",
)
require(
    r"json\.dumps\(i,\s*ensure_ascii=False\)",
    "Clash YAML list strings must preserve UTF-8 instead of emitting surrogate escapes such as \\ud83d\\ude80",
)
forbid(
    r'Content-Disposition\',f\'inline; filename="\{safe_name\}\.yaml"',
    "Clash subscription profile names must not include a forced .yaml suffix",
)
require(
    r"safe_name = up\.quote\('\$\{NODE_NAME\}',\s*safe=''\)",
    "subscription profile names must percent-encode all unsafe filename characters",
)
require(
    r"Content-Disposition',f\"inline; filename\*=UTF-8''\{safe_name\}\"",
    "subscription responses must expose NODE_NAME through UTF-8 filename metadata",
)
require(
    r'"bind-address": "\*"',
    "Clash profile should expose bind-address like common airport templates",
)
require(
    r'"external-controller": "127\.0\.0\.1:9090"',
    "Clash profile should include a local external-controller for dashboard clients",
)
require(
    r'"default-nameserver": \["223\.5\.5\.5", "119\.29\.29\.29"\]',
    "Clash DNS should include bootstrap default-nameserver entries",
)
require(
    r'"use-hosts": True',
    "Clash DNS should honor hosts entries",
)
require(
    r'"fallback-filter": \{[\s\S]*"geoip-code": "CN"',
    "Clash DNS should explicitly configure fallback-filter geoip-code CN",
)
require(
    r'"name": "Proxy", "type": "select"',
    "Clash profile should include an airport-style Proxy group",
)
require(
    r'"name": "Fallback", "type": "fallback"',
    "Clash profile should include an airport-style Fallback group",
)
require(
    r'"name": "AIChat", "type": "select"',
    "Clash profile should include an AIChat group",
)
require(
    r'"MATCH,Final"',
    "Clash profile should route unmatched traffic through Final",
)
require(
    r'"encryption": "none"',
    "Generated VLESS proxies should include encryption none for Mihomo compatibility",
)
require(
    r'p\["flow"\] = qs\.get\("flow", \[""\]\)\[0\]',
    "VLESS Reality/Vision conversion should preserve flow",
)
require(
    r'elif l\.startswith\("hysteria2://"\):',
    "Custom hysteria2 links should be converted into Clash YAML",
)
require(
    r'"type": "hysteria2"',
    "Custom hysteria2 links should produce Mihomo hysteria2 proxies",
)
require(
    r'ARGOV_USERS_FILE="/etc/xray/argov_users\.json"',
    "multi-user quota state must be persisted in /etc/xray/argov_users.json",
)
require(
    r"ensure_users_file\(\)",
    "script must migrate/create the ArgoV users database",
)
require(
    r"manage_users\(\)",
    "main menu must expose user quota management",
)
require(
    r"sync_xray_users\(\)",
    "user changes must sync enabled users into Xray clients without reinstalling",
)
require(
    r"start_stats_service\(\)",
    "script must install a traffic quota watcher service",
)
require(
    r"argov-stats\.service",
    "systemd installs must include an argov-stats traffic watcher",
)
require(
    r'"api":\{"tag":"api","services":\["StatsService"\]\}',
    "Xray config must enable StatsService API",
)
require(
    r'"stats":\{\}',
    "Xray config must enable stats collection",
)
require(
    r'"statsUserUplink":true',
    "Xray policy must enable per-user uplink stats",
)
require(
    r'"statsUserDownlink":true',
    "Xray policy must enable per-user downlink stats",
)
require(
    r'"email":"argov-',
    "Xray clients must include stable email values for per-user stats",
)
require(
    r'USER_TOKEN="\$\{1:-\}"[\s\S]*USER_JSON=',
    "subscription generator must accept a per-user token and resolve user JSON",
)
require(
    r'INCLUDE_CUSTOM=0[\s\S]*if \[ "\$IS_DEFAULT_USER" = "1" \]; then[\s\S]*INCLUDE_CUSTOM=1',
    "only the default/global subscription may include external custom links",
)
require(
    r'quota_bytes[\s\S]*used_up[\s\S]*used_down[\s\S]*enabled',
    "user records must track quota, bidirectional usage, and enabled state",
)
require(
    r'xray api statsquery[\s\S]*traffic>>>uplink[\s\S]*traffic>>>downlink',
    "traffic watcher must query Xray per-user uplink and downlink counters",
)
require(
    r"ENABLE_REALITY[\s\S]*gen_reality_shortid",
    "Reality install path must generate REALITY_SHORTID",
)
require(
    r'"shortIds":\["\'"\$\{REALITY_SHORTID\}"\'"\]',
    "initial Reality inbound must write REALITY_SHORTID into shortIds",
)
require(
    r'"fingerprint":"chrome"',
    "initial Reality inbound must include a Reality fingerprint",
)
require(
    r"json_array_from_file\(\)",
    "WARP domain lists must be converted with json_array_from_file",
)
forbid(
    r"DOMAINS = \[\$\{domains_list\}\]",
    "WARP apply must not splice raw domain text into Python code",
)
forbid(
    r'domain":\[\$\{all_domains\}\]',
    "WARP mode switch must not splice raw domain text into Python code",
)
require(
    r"warp_auto_install_socks \|\| return",
    "WARP routing must stop when SOCKS installation fails",
)
require(
    r"核心功能.*进阶路由.*状态运维",
    "main menu must have three clearly separated groups: nodes, services, maintenance",
    flags=re.DOTALL,
)
require(
    r"节点配置修改",
    "change_config menu must exist with a clear purpose label",
)
