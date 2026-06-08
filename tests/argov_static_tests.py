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
    r'HY2_PORT="\$\{HY2_PORT:-0\}"',
    "Hysteria2 must have a persisted editable port",
)
require(
    r'HY2_MPORT="\$\{HY2_MPORT:-\}"',
    "Hysteria2 port hopping range must be persisted separately from the listening port",
)
require(
    r"port_in_use_udp\(\)[\s\S]*ss -lunp",
    "Hysteria2 UDP ports must be checked with UDP listeners, not only TCP listeners",
)
require(
    r"port_in_use_any\(\)[\s\S]*port_in_use_tcp \"\$1\"[\s\S]*port_in_use_udp \"\$1\"",
    "public UDP protocols must reject ports occupied by either TCP or UDP listeners",
)
require(
    r"is_port_range\(\)[\s\S]*BASH_REMATCH",
    "Hysteria2 mport input must validate numeric port ranges before writing links or firewall rules",
)
require(
    r'ENABLE_HY2=0',
    "Hysteria2 must be selectable as a built-in optional protocol",
)
require(
    r'gen_hy2_link\(\)',
    "built-in Hysteria2 must generate hysteria2:// subscription links",
)
require(
    r'elif tag == "hy2":[\s\S]*"auth": u\["uuid"\][\s\S]*"email": u\["email"\]',
    "Hysteria2 user sync must use per-user auth and email for stats/quota",
)
require(
    r'build_hy2_inbound\(\)[\s\S]*"protocol":"hysteria","tag":"hy2"[\s\S]*"settings":\{"version":2,"users":\[\{"auth":"\'"\$\{auth\}"\'","level":0,"email":"\'"\$\{email\}"\'"\}\]\}',
    "initial Hysteria2 inbound must use Xray hysteria v2 users with email",
)
require(
    r'build_hy2_inbound\(\)[\s\S]*"streamSettings":\{"network":"hysteria","security":"tls"[\s\S]*"hysteriaSettings":\{"version":2',
    "initial Hysteria2 inbound must use the official hysteria transport with TLS",
)
require(
    r'"tlsSettings":\{"alpn":\["h3"\]',
    "built-in Hysteria2 must expose h3 ALPN for clients",
)
require(
    r'tag=="hy2"',
    "Hysteria2 must be managed by tag hy2",
)
require(
    r'hysteria2://\$\{uuid\}@\$\{ip\}:\$\{hport\}\?sni=\$\{hsni\}&insecure=1&allowInsecure=1&alpn=h3\$\{hmport_qs\}#\$\{NODE_NAME\}-Hy2',
    "subscription generator must include built-in Hysteria2 links with self-signed TLS compatibility for local controllable users",
)
require(
    r'local qs="sni=\$4&insecure=1&allowInsecure=1&alpn=h3"',
    "Hysteria2 share link helper must include both insecure and allowInsecure for self-signed certificates",
)
require(
    r'gen_hy2_link\(\)[\s\S]*local mport="\$6"[\s\S]*\[ -n "\$mport" \] && qs="\$\{qs\}&mport=\$\{mport\}"',
    "Hysteria2 share link helper must append mport only when port hopping is enabled",
)
require(
    r'links\+="hysteria2://\$\{uuid\}@\$\{ip\}:\$\{hport\}\?sni=\$\{hsni\}&insecure=1&allowInsecure=1&alpn=h3\$\{hmport_qs\}#\$\{NODE_NAME\}-Hy2"',
    "subscription generator must include built-in Hysteria2 mport when port hopping is enabled",
)
require(
    r'mport = qs\.get\("mport", qs\.get\("ports", \[""\]\)\)\[0\][\s\S]*p\["ports"\] = mport[\s\S]*p\["hop-interval"\] = 30',
    "Clash YAML conversion must preserve Hysteria2 port hopping as ports and hop-interval",
)
require(
    r'build_hy2_inbound\(\)[\s\S]*"finalmask":\{"quicParams":\{"udpHop":\{"ports":"\'"\$\{mport\}"\'","interval":30\}\}\}',
    "Hysteria2 inbound builder must write Xray Finalmask udpHop quicParams as a string range when port hopping is enabled",
)
require(
    r"apply_hy2_hop_rules\(\)[\s\S]*dport=\"\$\{mport//-/:\}\"[\s\S]*-p udp --dport \"\\\$dport\"[\s\S]*--to-ports \"\\\$listen_port\"",
    "Hysteria2 port hopping must install UDP REDIRECT rules to the single Xray listening port with iptables range syntax",
)
require(
    r"disable_hy2_hop_rules\(\)[\s\S]*argov-hy2-hop[\s\S]*iptables[\s\S]*-D PREROUTING",
    "Hysteria2 port hopping must have cleanup for persisted service and iptables rules",
)
require(
    r"clear_hy2_mport_config\(\)[\s\S]*HY2_MPORT=\"\"[\s\S]*del\(\.finalmask\.quicParams\.udpHop\)",
    "Hysteria2 mport must be removed from config if firewall rule installation fails",
)
require(
    r'select\(\.tag=="reality" or \.tag=="ss" or \.tag=="hy2"\)',
    "reinstall keep-data path must preserve built-in Hysteria2 inbounds",
)
require(
    r"add_hy2_protocol\(\)",
    "Hysteria2 add flow must have a dedicated implementation instead of falling through unknown protocol handling",
)
require(
    r'a2\)\s+\[ "\$has_hy2" = 0 \] && add_hy2_protocol',
    "manage node menu must call the built-in Hysteria2 add flow",
)
require(
    r'delete_protocol\(\)[\s\S]*tag=="hy2"[\s\S]*ENABLE_HY2=0',
    "delete flow must remove Hysteria2 inbounds and persist ENABLE_HY2=0",
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
