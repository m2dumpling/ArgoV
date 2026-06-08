#!/usr/bin/env bash
#==============================================================================
# ArgoV — Cloudflare Argo Tunnel 多协议交互式管理脚本
# VLESS + VMess (Argo)  |  Shadowsocks  |  VLESS Reality  |  Hysteria2
# 零公网暴露(Argo模式) · 无 Caddy/Nginx
#==============================================================================

# --- 颜色 ---
re="\033[0m"; red="\e[1;31m"; green="\e[1;32m"; yellow="\e[1;33m"
purple="\e[1;35m"; cyan="\e[1;36m"; white="\e[1;37m"
red_msg()    { echo -e "${red}$1${re}"; }
green_msg()  { echo -e "${green}$1${re}"; }
yellow_msg() { echo -e "${yellow}$1${re}"; }
purple_msg() { echo -e "${purple}$1${re}"; }
cyan_msg()   { echo -e "${cyan}$1${re}"; }

# --- 渐变色 DUMPLING Logo ---
logo() {
echo -e "\
${purple}  ██████╗ ██╗   ██╗███╗   ███╗██████╗ ██╗     ██╗███╗   ██╗ ██████╗ ${re}
${cyan}  ██╔══██╗██║   ██║████╗ ████║██╔══██╗██║     ██║████╗  ██║██╔════╝ ${re}
${blue}  ██║  ██║██║   ██║██╔████╔██║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗${re}
${green}  ██║  ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██║     ██║██║╚██╗██║██║   ██║${re}
${yellow}  ██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ███████╗██║██║ ╚████║╚██████╔╝${re}
${red}  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ${re}"
}

# --- 常量 ---
CONFIG_FILE="/etc/xray/config.json"
USER_CONF="/etc/xray/argov.conf"
TUNNEL_LOG="/etc/xray/argo.log"
WORK_DIR="/etc/xray"
ARGOV_USERS_FILE="/etc/xray/argov_users.json"
SCRIPT_PATH="/usr/bin/ag"
CDN_DEFAULT="cdn.31514926.xyz"

# --- 端口 ---
ARGO_PORT="${ARGO_PORT:-8080}"
VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
CDN_PORT="${CDN_PORT:-443}"
REALITY_PORT="${REALITY_PORT:-0}"
HY2_PORT="${HY2_PORT:-0}"
SS_PORT="${SS_PORT:-0}"
SUB_PORT="${SUB_PORT:-0}"
SUB_PATH="${SUB_PATH:-}"
SUB_DOMAIN="${SUB_DOMAIN:-}"
SUB_TOKEN="${SUB_TOKEN:-}"

# --- 节点名称 ---
NODE_NAME="${NODE_NAME:-ArgoV}"

# --- 可选协议 ---
ENABLE_VLESS_ARGO=1
ENABLE_VMESS_ARGO=1
ENABLE_REALITY=0
ENABLE_HY2=0
ENABLE_SS=0

# --- SS 加密 ---
SS_METHODS=("aes-128-gcm" "aes-256-gcm" "chacha20-ietf-poly1305" "xchacha20-ietf-poly1305"
            "2022-blake3-aes-128-gcm" "2022-blake3-aes-256-gcm" "2022-blake3-chacha20-poly1305")
SS_METHOD="${SS_METHOD:-aes-256-gcm}"

# --- Reality SNI ---
REALITY_SNIS=("www.amazon.com" "www.ebay.com" "www.paypal.com" "www.cloudflare.com"
              "dash.cloudflare.com" "aws.amazon.com" "addons.mozilla.org" "www.microsoft.com")
REALITY_SNI="${REALITY_SNI:-www.amazon.com}"
HY2_SNI="${HY2_SNI:-www.bing.com}"
HY2_CERT_FILE="${HY2_CERT_FILE:-/etc/xray/argov-hy2.crt}"
HY2_KEY_FILE="${HY2_KEY_FILE:-/etc/xray/argov-hy2.key}"

# --- CDN 池 ---
declare -A CDN_DOMAINS
CDN_DOMAINS[1]="cdn.31514926.xyz (三网通用)"
CDN_DOMAINS[2]="skk.moe (三网通用·泛用测速)"
CDN_DOMAINS[3]="ip.sb (三网通用·IP检测站)"
CDN_DOMAINS[4]="time.is (三网通用·时间站)"
CDN_DOMAINS[5]="bestcf.top (三网通用·优选站)"
CDN_DOMAINS[6]="cfip.xxxxxxxx.tk (三网通用)"
CDN_DOMAINS[7]="cf.090227.xyz (三网通用)"
CDN_DOMAINS[8]="yidong.19931101.xyz (移动专线)"
CDN_DOMAINS[9]="liantong.19931101.xyz (联通专线)"
CDN_DOMAINS[10]="dianxin.19931101.xyz (电信专线)"
CDN_DOMAINS[11]="cdn.2020111.xyz (综合优选)"
CDN_DOMAINS[12]="xn--b6gac.eu.org (综合优选·中东)"
CDN_DOMAINS[13]="cdns.doon.eu.org (综合优选·Doorn)"

#==============================================================================
# 工具
#==============================================================================
port_in_use() { netstat -tlnp 2>/dev/null | grep -q ":$1 " || ss -tlnp 2>/dev/null | grep -q ":$1 " || lsof -iTCP:"$1" -sTCP:LISTEN &>/dev/null; }
find_free_port() { local p="$1"; while port_in_use "$p" && [ "$p" -lt 65535 ]; do p=$((p+1)); done; echo "$p"; }
detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "64" ;; i686|i386) echo "32" ;;
        aarch64|arm64) echo "arm64-v8a" ;; armv7l) echo "arm32-v7a" ;; *) echo "" ;; esac
}
cf_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;; aarch64|arm64) echo "arm64" ;;
        armv7l) echo "arm" ;; i686|i386) echo "386" ;; *) echo "amd64" ;; esac
}

# Alpine / systemd 兼容层
[ -f /etc/alpine-release ] && IS_ALPINE=1 || IS_ALPINE=0
systemctl() {
    local cmd="$1"; shift
    if [ "$IS_ALPINE" = 1 ]; then
        case "$cmd" in
            start|stop|restart) for s in "$@"; do rc-service "$s" "$cmd" 2>/dev/null; done ;;
            enable)  for s in "$@"; do rc-update add "$s" default 2>/dev/null; done ;;
            disable) for s in "$@"; do rc-update del "$s" default 2>/dev/null; done ;;
            is-active) rc-service "$1" status 2>/dev/null | grep -q "started" ;;
            daemon-reload) true ;;  # Alpine 不需要
        esac
    else
        case "$cmd" in
            is-active) command systemctl is-active --quiet "$1" 2>/dev/null ;;
            daemon-reload) command systemctl daemon-reload 2>/dev/null ;;
            *) command systemctl "$cmd" "$@" 2>/dev/null ;;
        esac
    fi
}
get_argo_domain() {
    # 日志优先（始终是最新的隧道域名）
    local d; [ -f "$TUNNEL_LOG" ] && for i in {1..5}; do
        d=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' "$TUNNEL_LOG" | tail -n 1)
        [ -n "$d" ] && { echo "$d"; return; }; sleep 2
    done
    # 持久化兜底
    [ -n "$LAST_ARGO_DOMAIN" ] && { echo "$LAST_ARGO_DOMAIN"; return; }
    echo "$d"
}
get_uuid()   { jq -r '.inbounds[0].settings.clients[0].id // empty' "$CONFIG_FILE" 2>/dev/null; }
get_cdn() {
    local v=""
    [ -f "$CONFIG_FILE" ] && v=$(jq -r '.current_cdn // empty' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$v" ] && [ "$v" != "null" ] && echo "$v" || echo "$CDN_DOMAIN"
}
get_cdn_port() {
    local v=""
    [ -f "$CONFIG_FILE" ] && v=$(jq -r '.current_cdn_port // empty' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$v" ] && [ "$v" != "null" ] && echo "$v" || echo "$CDN_PORT"
}
get_ip() {
    local ip
    for s in ifconfig.me icanhazip.com checkip.amazonaws.com api.ipify.org ipinfo.io/ip; do
        ip=$(curl -s --max-time 3 "$s" 2>/dev/null || wget -qO- -T3 "$s" 2>/dev/null)
        [ -n "$ip" ] && echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' && { echo "$ip"; return; }
    done
    ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    [ -z "$ip" ] && ip=$(ip -4 addr show 2>/dev/null | awk '/inet / && !/127\./ {print $2}' | cut -d/ -f1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    echo "${ip:-NAT环境}"
}
is_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
save_var() { printf "%s=%q\n" "$1" "$2"; }
json_array_from_file() {
    local file="$1" py
    py=$(command -v python3 || command -v python || true)
    [ -z "$py" ] && { echo '[]'; return; }
    "$py" - "$file" << 'PYEOF'
import json, sys
items = []
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        item = line.strip()
        if item and item not in items:
            items.append(item)
print(json.dumps(items, ensure_ascii=False))
PYEOF
}
rand_token() { openssl rand -hex 16 2>/dev/null || printf '%08x%08x%08x%08x' $RANDOM $RANDOM $RANDOM $RANDOM; }
rand_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || printf '%08x-%04x-%04x-%04x-%012x\n' $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM; }
py_bin() { command -v python3 || command -v python || true; }
ensure_users_file() {
    local py uuid token
    py=$(py_bin); [ -z "$py" ] && return 1
    mkdir -p "$WORK_DIR" 2>/dev/null
    uuid=$(get_uuid); [ -z "$uuid" ] && uuid="${UUID_CUSTOM:-$(rand_uuid)}"
    [ -z "$SUB_TOKEN" ] && SUB_TOKEN=$(rand_token)
    token="$SUB_TOKEN"
    "$py" - "$ARGOV_USERS_FILE" "$uuid" "$token" << 'PYEOF'
import json, os, re, sys, time
path, uuid, token = sys.argv[1:4]

def clean_name(v):
    v = (v or "default").strip()
    return v or "default"

def email_for(name):
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", clean_name(name)).strip("-._").lower()
    return "argov-" + (safe or "user")

def norm_user(u, default_uuid, default_token):
    u = dict(u or {})
    u["name"] = clean_name(u.get("name"))
    u["uuid"] = u.get("uuid") or default_uuid
    u["token"] = u.get("token") or (default_token if u["name"] == "default" else "")
    u["enabled"] = bool(u.get("enabled", True))
    u["quota_bytes"] = int(u.get("quota_bytes") or 0)
    u["used_up"] = int(u.get("used_up") or 0)
    u["used_down"] = int(u.get("used_down") or 0)
    u["email"] = u.get("email") or email_for(u["name"])
    u["created_at"] = int(u.get("created_at") or time.time())
    return u

data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
users = data.get("users") if isinstance(data, dict) else None
if not isinstance(users, list):
    users = []

seen, out, has_default = set(), [], False
for u in users:
    nu = norm_user(u, uuid, token)
    if nu["name"] in seen:
        continue
    seen.add(nu["name"])
    if nu["name"] == "default":
        has_default = True
        if token:
            nu["token"] = token
        if uuid:
            nu["uuid"] = uuid
    out.append(nu)
if not has_default:
    out.insert(0, norm_user({"name": "default", "uuid": uuid, "token": token, "quota_bytes": 0}, uuid, token))

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"version": 1, "users": out}, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
PYEOF
}
parse_bytes() {
    local py; py=$(py_bin); [ -z "$py" ] && { echo 0; return; }
    "$py" - "$1" << 'PYEOF'
import re, sys
s=(sys.argv[1] if len(sys.argv)>1 else "0").strip().upper().replace(" ", "")
if s in ("", "0", "UNLIMITED", "NONE"):
    print(0); raise SystemExit
m=re.match(r"^([0-9]+(?:\.[0-9]+)?)(B|K|KB|M|MB|G|GB|T|TB)?$", s)
if not m:
    print(-1); raise SystemExit
unit=m.group(2) or "B"
mul={"B":1,"K":1024,"KB":1024,"M":1024**2,"MB":1024**2,"G":1024**3,"GB":1024**3,"T":1024**4,"TB":1024**4}[unit]
print(int(float(m.group(1))*mul))
PYEOF
}
format_bytes() {
    local py; py=$(py_bin); [ -z "$py" ] && { echo "$1 B"; return; }
    "$py" - "$1" << 'PYEOF'
import sys
n=int(float(sys.argv[1] or 0))
for u in ["B","KB","MB","GB","TB","PB"]:
    if n < 1024 or u == "PB":
        print(f"{n:.2f} {u}" if u != "B" else f"{n} B")
        break
    n /= 1024
PYEOF
}
sync_xray_users() {
    [ -f "$CONFIG_FILE" ] || return 0
    ensure_users_file || return 1
    local py; py=$(py_bin); [ -z "$py" ] && return 1
    "$py" - "$CONFIG_FILE" "$ARGOV_USERS_FILE" << 'PYEOF'
import json, os, re, sys
cfg_path, users_path = sys.argv[1:3]

def load(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def email_for(name):
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", (name or "user")).strip("-._").lower()
    return "argov-" + (safe or "user")

cfg = load(cfg_path, {})
udb = load(users_path, {"users": []})
users = []
for u in udb.get("users", []):
    if not u.get("enabled", True):
        continue
    uuid = u.get("uuid")
    if not uuid:
        continue
    name = u.get("name") or "user"
    email = u.get("email") or email_for(name)
    users.append({"name": name, "uuid": uuid, "email": email})
if not users:
    raise SystemExit("no enabled users")

def vless_clients(flow=False):
    out = []
    for u in users:
        c = {"id": u["uuid"], "email": u["email"]}
        if flow:
            c["flow"] = "xtls-rprx-vision"
        out.append(c)
    return out

def vmess_clients():
    return [{"id": u["uuid"], "alterId": 0, "email": u["email"]} for u in users]

def hy2_users():
    return [{"auth": u["uuid"], "level": 0, "email": u["email"]} for u in users]

for inbound in cfg.get("inbounds", []):
    tag = inbound.get("tag")
    if tag == "argo-in":
        inbound.setdefault("settings", {})["clients"] = vless_clients(True)
    elif tag == "vless-ws":
        inbound.setdefault("settings", {})["clients"] = vless_clients(False)
    elif tag == "vmess-ws":
        inbound.setdefault("settings", {})["clients"] = vmess_clients()
    elif tag == "reality":
        inbound.setdefault("settings", {})["clients"] = vless_clients(True)
    elif tag == "hy2":
        settings = inbound.setdefault("settings", {})
        settings["version"] = 2
        settings["users"] = hy2_users()

if not any(i.get("tag") == "api-in" for i in cfg.get("inbounds", [])):
    cfg.setdefault("inbounds", []).append({"listen":"127.0.0.1","port":10085,"protocol":"dokodemo-door","tag":"api-in","settings":{"address":"127.0.0.1"}})
cfg["api"] = {"tag":"api","services":["StatsService"]}
cfg["stats"] = {}
cfg["policy"] = {"levels":{"0":{"statsUserUplink":True,"statsUserDownlink":True}},"system":{"statsInboundUplink":True,"statsInboundDownlink":True,"statsOutboundUplink":True,"statsOutboundDownlink":True}}
routing = cfg.setdefault("routing", {})
rules = routing.setdefault("rules", [])
if not any(r.get("inboundTag") == ["api-in"] and r.get("outboundTag") == "api" for r in rules if isinstance(r, dict)):
    rules.insert(0, {"type":"field","inboundTag":["api-in"],"outboundTag":"api"})

tmp = cfg_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, separators=(",", ":"))
    f.write("\n")
os.replace(tmp, cfg_path)
PYEOF
}
get_user_sub_url() {
    local ip="$1" token="$2"
    [ -z "$token" ] && return 1
    if [ -n "$SUB_DOMAIN" ]; then
        echo "https://${SUB_DOMAIN}:${SUB_PORT}/sub?token=${token}"
    else
        [ -z "$ip" ] && ip=$(get_ip)
        echo "http://${ip}:${SUB_PORT}/sub?token=${token}"
    fi
}
restart_user_runtime() {
    sync_xray_users || return 1
    if [ "$IS_ALPINE" = 1 ]; then
        rc-service xray restart 2>/dev/null || true
    else
        systemctl restart xray 2>/dev/null || true
    fi
    start_sub_server >/dev/null 2>&1 || true
    start_stats_service >/dev/null 2>&1 || true
}
user_db_op() {
    local op="$1"; shift
    local py; py=$(py_bin); [ -z "$py" ] && return 1
    "$py" - "$ARGOV_USERS_FILE" "$op" "$@" << 'PYEOF'
import json, os, re, sys, time
path, op, args = sys.argv[1], sys.argv[2], sys.argv[3:]

def clean_name(v):
    v = (v or "").strip()
    v = re.sub(r"\s+", "-", v)
    v = re.sub(r"[^A-Za-z0-9_.-]+", "-", v).strip("-._")
    return v or "user"

def email_for(name):
    return "argov-" + clean_name(name).lower()

def load():
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {"version": 1, "users": []}
    if not isinstance(data, dict):
        data = {"version": 1, "users": []}
    data.setdefault("version", 1)
    data.setdefault("users", [])
    return data

def save(data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)

def find(data, name):
    for u in data.get("users", []):
        if u.get("name") == name:
            return u
    return None

def fmt_line(u):
    used = int(u.get("used_up") or 0) + int(u.get("used_down") or 0)
    quota = int(u.get("quota_bytes") or 0)
    enabled = "1" if u.get("enabled", True) else "0"
    print("\t".join([u.get("name",""), enabled, str(used), str(quota), u.get("token","")]))

data = load()
if op == "list":
    for u in data.get("users", []):
        fmt_line(u)
    raise SystemExit

if op == "show":
    u = find(data, args[0])
    if not u:
        raise SystemExit(2)
    fmt_line(u)
    raise SystemExit

if op == "add":
    name, quota, uuid, token = args[:4]
    name = clean_name(name)
    if name == "default" or find(data, name):
        raise SystemExit(2)
    data["users"].append({
        "name": name,
        "uuid": uuid,
        "token": token,
        "quota_bytes": int(quota),
        "used_up": 0,
        "used_down": 0,
        "enabled": True,
        "email": email_for(name),
        "created_at": int(time.time()),
    })
elif op == "set-enabled":
    name, enabled = args[:2]
    if name == "default":
        raise SystemExit(3)
    u = find(data, name)
    if not u:
        raise SystemExit(2)
    u["enabled"] = enabled == "1"
elif op == "set-quota":
    name, quota = args[:2]
    u = find(data, name)
    if not u:
        raise SystemExit(2)
    u["quota_bytes"] = int(quota)
    if int(quota) <= 0 or int(u.get("used_up") or 0) + int(u.get("used_down") or 0) < int(quota):
        u["enabled"] = True
elif op == "reset":
    u = find(data, args[0])
    if not u:
        raise SystemExit(2)
    u["used_up"] = 0
    u["used_down"] = 0
    u["enabled"] = True
elif op == "delete":
    name = args[0]
    if name == "default":
        raise SystemExit(3)
    old = len(data.get("users", []))
    data["users"] = [u for u in data.get("users", []) if u.get("name") != name]
    if len(data["users"]) == old:
        raise SystemExit(2)
else:
    raise SystemExit(1)
save(data)
PYEOF
}
gen_reality_keys() {
    local keys; keys=($("${WORK_DIR}/xray" x25519 2>/dev/null | sed 's/.*://'))
    REALITY_PRIV="${keys[0]}"
    REALITY_PUB="${keys[1]}"
    [ -z "$REALITY_PRIV" ] && { REALITY_PRIV="REPLACE_ME"; REALITY_PUB="REPLACE_ME"; }
}
gen_reality_shortid() {
    REALITY_SHORTID=$(openssl rand -hex 4 2>/dev/null || printf '%08x' $((RANDOM*RANDOM)))
}
gen_hy2_cert() {
    mkdir -p "$WORK_DIR" 2>/dev/null
    [ -s "$HY2_CERT_FILE" ] && [ -s "$HY2_KEY_FILE" ] && return 0
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj "/CN=${HY2_SNI:-ArgoV-Hy2}" \
        -keyout "$HY2_KEY_FILE" -out "$HY2_CERT_FILE" >/dev/null 2>&1
    chmod 600 "$HY2_KEY_FILE" 2>/dev/null || true
}
gen_ss2022_pass() {
    local method="$1"
    [[ "$method" =~ 128 ]] && openssl rand -base64 16 || openssl rand -base64 32
}

# --- 持久化 ---
load_conf() {
    [ -f "$USER_CONF" ] && . "$USER_CONF"
    NODE_NAME="${NODE_NAME:-ArgoV}"
    ARGO_PORT="${ARGO_PORT:-8080}"; VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
    VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
    CDN_PORT="${CDN_PORT:-443}"; CDN_DOMAIN="${CDN_DOMAIN:-$CDN_DEFAULT}"
    ARGO_MODE="${ARGO_MODE:-temp}"; ARGO_AUTH="${ARGO_AUTH:-}"
    ARGO_FIXED_DOMAIN="${ARGO_FIXED_DOMAIN:-}"; UUID_CUSTOM="${UUID_CUSTOM:-}"; LAST_ARGO_DOMAIN="${LAST_ARGO_DOMAIN:-}"
    REALITY_PORT="${REALITY_PORT:-0}"; HY2_PORT="${HY2_PORT:-0}"; SS_PORT="${SS_PORT:-0}"
    SUB_PORT="${SUB_PORT:-0}"; SUB_PATH="${SUB_PATH:-}"
    SUB_DOMAIN="${SUB_DOMAIN:-}"; SUB_TOKEN="${SUB_TOKEN:-}"
    REALITY_SNI="${REALITY_SNI:-www.amazon.com}"; HY2_SNI="${HY2_SNI:-www.bing.com}"; SS_METHOD="${SS_METHOD:-aes-256-gcm}"
    ENABLE_REALITY="${ENABLE_REALITY:-0}"; ENABLE_HY2="${ENABLE_HY2:-0}"; ENABLE_SS="${ENABLE_SS:-0}"
    HY2_CERT_FILE="${HY2_CERT_FILE:-/etc/xray/argov-hy2.crt}"; HY2_KEY_FILE="${HY2_KEY_FILE:-/etc/xray/argov-hy2.key}"
    REALITY_PRIV="${REALITY_PRIV:-}"; REALITY_PUB="${REALITY_PUB:-}"
    REALITY_SHORTID="${REALITY_SHORTID:-}"
    RELAY_ENABLED="${RELAY_ENABLED:-0}"; RELAY_LINK="${RELAY_LINK:-}"
    RELAY_MODE="${RELAY_MODE:-all}"
}
save_conf() {
    {
        echo "# ArgoV — $(date '+%Y-%m-%d %H:%M:%S')"
        save_var NODE_NAME "$NODE_NAME"
        save_var ARGO_PORT "$ARGO_PORT"; save_var VLESS_WS_PORT "$VLESS_WS_PORT"
        save_var VMESS_WS_PORT "$VMESS_WS_PORT"; save_var CDN_PORT "$CDN_PORT"
        save_var CDN_DOMAIN "$CDN_DOMAIN"; save_var ARGO_MODE "$ARGO_MODE"; save_var ARGO_AUTH "$ARGO_AUTH"
        save_var ARGO_FIXED_DOMAIN "$ARGO_FIXED_DOMAIN"; save_var UUID_CUSTOM "$UUID_CUSTOM"
        save_var REALITY_PORT "$REALITY_PORT"; save_var HY2_PORT "$HY2_PORT"; save_var SS_PORT "$SS_PORT"; save_var SUB_PORT "$SUB_PORT"; save_var SUB_PATH "$SUB_PATH"; save_var SUB_DOMAIN "$SUB_DOMAIN"; save_var SUB_TOKEN "$SUB_TOKEN"
        save_var REALITY_SNI "$REALITY_SNI"; save_var HY2_SNI "$HY2_SNI"; save_var SS_METHOD "$SS_METHOD"
        save_var ENABLE_REALITY "$ENABLE_REALITY"; save_var ENABLE_HY2 "$ENABLE_HY2"; save_var ENABLE_SS "$ENABLE_SS"
        save_var HY2_CERT_FILE "$HY2_CERT_FILE"; save_var HY2_KEY_FILE "$HY2_KEY_FILE"
        save_var REALITY_PRIV "$REALITY_PRIV"; save_var REALITY_PUB "$REALITY_PUB"
        save_var REALITY_SHORTID "$REALITY_SHORTID"; save_var LAST_ARGO_DOMAIN "$LAST_ARGO_DOMAIN"
        save_var RELAY_ENABLED "$RELAY_ENABLED"; save_var RELAY_LINK "$RELAY_LINK"; save_var RELAY_MODE "$RELAY_MODE"
    } > "$USER_CONF"
}

#==============================================================================
# 链接生成
#==============================================================================
gen_vmess_link() {
    local json; json="{\"v\":\"2\",\"ps\":\"${5:-${NODE_NAME}-VMess}\",\"add\":\"${3:-$(get_cdn)}\",\"port\":\"${4:-$(get_cdn_port)}\",\"id\":\"$1\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$2\",\"path\":\"/vmess-argo?ed=2560\",\"tls\":\"tls\",\"sni\":\"$2\",\"alpn\":\"\",\"fp\":\"\"}"
    printf '%s' "vmess://$(printf '%s' "$json" | base64 -w0 2>/dev/null || printf '%s' "$json" | base64 | tr -d '\n')"
}
gen_vless_link() {
    printf '%s' "vless://$1@${3:-$(get_cdn)}:${4:-$(get_cdn_port)}?encryption=none&security=tls&sni=$2&type=ws&host=$2&path=%2Fvless-argo%3Fed%3D2560#${5:-${NODE_NAME}-VLESS}"
}
gen_ss_link() {
    local b64; b64=$(printf '%s' "$1:$2" | base64 -w0 2>/dev/null || printf '%s' "$1:$2" | base64 | tr -d '\n')
    printf '%s' "ss://${b64}@$3:$4#${5:-${NODE_NAME}-SS}"
}
gen_reality_link() {
    local sid=""
    [ -n "$6" ] && sid="&sid=$6"
    local fp="$8"; [ -z "$fp" ] && fp="chrome"
    printf '%s' "vless://$1@$2:$3?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$4&pbk=$5&fp=${fp}${sid}#${7:-${NODE_NAME}-Reality}"
}
gen_hy2_link() {
    printf '%s' "hysteria2://$1@$2:$3?sni=$4&insecure=1&allowInsecure=1&alpn=h3#${5:-${NODE_NAME}-Hy2}"
}

show_qr() {
    local qr="${WORK_DIR}/qrencode"
    [ ! -f "$qr" ] && { yellow_msg "QR 工具未安装"; return 1; }
    chmod +x "$qr" 2>/dev/null; echo ""
    "$qr" -t ANSIUTF8 -m 1 -s 2 "$1" 2>/dev/null || yellow_msg "QR 生成失败"
}
install_qrencode() {
    local qr="${WORK_DIR}/qrencode"; [ -f "$qr" ] && return 0
    local a; case "$(uname -m)" in x86_64) a="amd64" ;; aarch64|arm64) a="arm64" ;; *) return 1 ;; esac
    curl -sLfo "$qr" "https://github.com/eooce/test/releases/download/${a}/qrencode-linux-${a}" 2>/dev/null; chmod +x "$qr" 2>/dev/null
}

#==============================================================================
#==============================================================================
# 订阅服务器（极简：Bash 生成内容 → 文件 → Python serve 文件）
#==============================================================================
get_sub_url() {
    if [ -n "$SUB_DOMAIN" ]; then
        echo "https://${SUB_DOMAIN}:${SUB_PORT}/sub?token=${SUB_TOKEN}"
    elif [ -n "$SUB_PORT" ] && [ "$SUB_PORT" != "0" ] && [ -n "$SUB_PATH" ]; then
        echo "http://${1:-127.0.0.1}:${SUB_PORT}${SUB_PATH}"
    fi
}

edit_subscription() {
    while true; do
        clear; load_conf
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}订阅配置编辑${re}                      ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        local cur_url; cur_url=$(get_sub_url 2>/dev/null || echo "未配置")
        echo -e "  ${yellow}当前:${re} ${cyan}${cur_url}${re}"
        echo ""
        if [ -n "$SUB_DOMAIN" ]; then
            echo -e "  ${green}1${re}. 修改域名 — ${cyan}${SUB_DOMAIN}${re}"
            echo -e "  ${green}2${re}. 修改端口 — ${cyan}${SUB_PORT}${re}"
            echo -e "  ${green}3${re}. 切换为 HTTP 模式"
        else
            echo -e "  ${green}1${re}. 添加域名 (HTTP → HTTPS)"
            echo -e "  ${green}2${re}. 修改端口 — ${cyan}${SUB_PORT}${re}"
        fi
        echo -e "  ${green}4${re}. 重新生成 Token"
        echo -e "  ${cyan}5${re}. 查看完整订阅链接"
        echo ""; echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            1)
                if [ -n "$SUB_DOMAIN" ]; then
                    local old_domain="$SUB_DOMAIN"
                    read -p "  新域名 [${SUB_DOMAIN}]: " nd
                    [ -n "$nd" ] && SUB_DOMAIN="$nd"
                else
                    echo -e "  ${yellow}输入已指向本机 IP 的域名，将切换到 HTTPS:${re}"
                    echo -e "  ${yellow}⚠ CF 代理仅支持以下端口:${re}"
                    echo -e "  ${cyan}  2096  8443  2053  2083  2087  443${re}"
                    read -p "  域名: " nd
                    [ -z "$nd" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                    SUB_DOMAIN="$nd"
                    if [ "$SUB_PORT" = "0" ]; then
                        echo ""; echo -e "  ${yellow}选择端口:${re}"
                        echo -e "  ${cyan}1${re}. 2096 (默认)  ${cyan}2${re}. 8443  ${cyan}3${re}. 2053  ${cyan}4${re}. 2083  ${cyan}5${re}. 2087  ${cyan}6${re}. 443"
                        read -p "  [1]: " pc
                        case "${pc:-1}" in
                            2) SUB_PORT=8443 ;; 3) SUB_PORT=2053 ;; 4) SUB_PORT=2083 ;;
                            5) SUB_PORT=2087 ;; 6) SUB_PORT=443 ;; *) SUB_PORT=2096 ;;
                        esac
                    fi
                fi
                # 域名变了 → 删旧证书让 start_sub_server 重新生成
                [ -n "$old_domain" ] && [ "$old_domain" != "$SUB_DOMAIN" ] && rm -f "${WORK_DIR}/sub_cert.pem" "${WORK_DIR}/sub_key.pem"
                save_conf; start_sub_server; green_msg "已更新。"; sleep 1
                ;;
            2)
                read -p "  新端口 [${SUB_PORT}]: " np
                [ -n "$np" ] && is_port "$np" && SUB_PORT="$np"
                save_conf; start_sub_server; green_msg "端口: ${SUB_PORT}"; sleep 1
                ;;
            3)
                if [ -n "$SUB_DOMAIN" ]; then
                    echo -ne "  ${yellow}确认切换为 HTTP? (y/n): ${re}"; read cf
                    [ "$cf" != "y" ] && [ "$cf" != "Y" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                    SUB_DOMAIN=""
                    # HTTPS 端口通常不是 HTTP 端口，自动分配一个
                    SUB_PORT=$(find_free_port "$(shuf -i 20000-50000 -n 1)")
                    # 删掉 TLS 证书，防止 Python 仍启用 HTTPS
                    rm -f "${WORK_DIR}/sub_cert.pem" "${WORK_DIR}/sub_key.pem"
                else
                    red_msg "已是 HTTP 模式"; sleep 1
                fi
                save_conf; start_sub_server; green_msg "已切换。"; sleep 1
                ;;
            4)
                SUB_TOKEN=$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)
                SUB_PATH="/${SUB_TOKEN}"; save_conf
                start_sub_server; green_msg "新 Token: ${SUB_TOKEN}"; sleep 1
                ;;
            5) echo ""; echo -e "  ${green}$(get_sub_url 2>/dev/null)${re}"; echo ""; read -p "  按回车继续..." -r ;;
            0) return ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

start_sub_server() {
    if [ "$SUB_PORT" = "0" ]; then
        [ -n "$SUB_DOMAIN" ] && SUB_PORT=2096 || SUB_PORT=$(find_free_port "$(shuf -i 20000-50000 -n 1)")
    fi
    # 先停旧服务再查端口（避免自己的旧进程被误判为占用）
    systemctl stop argov-sub 2>/dev/null; rc-service argov-sub stop 2>/dev/null; sleep 1
    port_in_use "$SUB_PORT" && SUB_PORT=$(find_free_port "$SUB_PORT")
    [ -z "$SUB_TOKEN" ] && SUB_TOKEN=$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)
    [ -z "$SUB_PATH" ] && SUB_PATH="/${SUB_TOKEN}"
    save_conf; ensure_users_file

    # 自签证书（CF Full 模式需要），域名变更时重新生成
    if [ -n "$SUB_DOMAIN" ]; then
        local cert_cn; cert_cn=$(openssl x509 -in "${WORK_DIR}/sub_cert.pem" -noout -subject 2>/dev/null | sed 's/.*CN\s*=\s*//')
        if [ "$cert_cn" != "$SUB_DOMAIN" ]; then
            openssl req -x509 -newkey rsa:2048 -keyout "${WORK_DIR}/sub_key.pem" -out "${WORK_DIR}/sub_cert.pem" -days 3650 -nodes -subj "/CN=${SUB_DOMAIN}" 2>/dev/null
        fi
    fi

    local py; py=$(command -v python3 || command -v python || true)
    [ -z "$py" ] && { yellow_msg "Python3 未安装，订阅跳过"; return 1; }

    cat > "${WORK_DIR}/sub.py" << PYEOF
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
import subprocess, os, socketserver, threading, time
import base64, json, urllib.parse

SUB_FILE='/etc/xray/sub.txt'; PORT=${SUB_PORT}
USERS_FILE='/etc/xray/argov_users.json'; GEN_SCRIPT='${WORK_DIR}/sub_gen.sh'
CACHE={}; CACHE_LOCK=threading.Lock()

def to_yaml(data, level=0):
    out = []
    ind = "  " * level
    if isinstance(data, dict):
        for k, v in data.items():
            if isinstance(v, (dict, list)):
                out.append(f"{ind}{k}:")
                out.append(to_yaml(v, level + 1))
            else:
                v_str = json.dumps(v, ensure_ascii=False) if isinstance(v, str) else str(v).lower() if isinstance(v, bool) else v
                out.append(f"{ind}{k}: {v_str}")
    elif isinstance(data, list):
        for i in data:
            if isinstance(i, dict):
                sub = to_yaml(i, level + 1).split("\\n")
                sub[0] = sub[0].replace("  " * (level + 1), ind + "- ", 1)
                out.extend(sub)
            else:
                v_str = json.dumps(i, ensure_ascii=False) if isinstance(i, str) else str(i).lower() if isinstance(i, bool) else i
                out.append(f"{ind}- {v_str}")
    return "\\n".join(out)

def build_clash(lines):
    proxies, names = [], []
    def split_host_port(server):
        host, port = server.rsplit(":", 1)
        return host.strip("[]"), int(port)

    def bool_qs(v):
        return str(v).lower() in ("1", "true", "yes")

    for l in lines:
        try:
            p = None
            if l.startswith("vless://"):
                link = l[8:]
                name = "VLESS"
                if "#" in link: link, name = link.split("#", 1)
                base, q = link.split("?", 1) if "?" in link else (link, "")
                qs = urllib.parse.parse_qs(q)
                uuid, server = base.split("@", 1)
                host, port = split_host_port(server)
                p = {"name": urllib.parse.unquote(name), "type": "vless", "server": host, "port": port, "uuid": uuid, "udp": True, "encryption": "none"}
                if qs.get("flow", [""])[0]:
                    p["flow"] = qs.get("flow", [""])[0]
                if qs.get("security", [""])[0] == "tls":
                    p.update({"tls": True, "servername": qs.get("sni", [""])[0]})
                elif qs.get("security", [""])[0] == "reality":
                    p.update({"tls": True, "servername": qs.get("sni", [""])[0], "client-fingerprint": qs.get("fp", ["chrome"])[0], "reality-opts": {"public-key": qs.get("pbk", [""])[0], "short-id": qs.get("sid", [""])[0]}})
                if qs.get("type", [""])[0] == "ws":
                    p.update({"network": "ws", "ws-opts": {"path": urllib.parse.unquote(qs.get("path", ["/"])[0]), "headers": {"Host": qs.get("host", [""])[0]}}})
            elif l.startswith("vmess://"):
                j = json.loads(base64.b64decode(l[8:] + "==").decode())
                p = {"name": j.get("ps", "VMess"), "type": "vmess", "server": j.get("add"), "port": int(j.get("port")), "uuid": j.get("id"), "alterId": int(j.get("aid", 0)), "cipher": j.get("scy", "auto"), "udp": True}
                if j.get("net") == "ws":
                    p.update({"network": "ws", "ws-opts": {"path": j.get("path", "/"), "headers": {"Host": j.get("host", "")}}})
                if str(j.get("tls")) == "tls":
                    p.update({"tls": True, "servername": j.get("sni", "")})
            elif l.startswith("ss://"):
                link = l[5:]
                name = "SS"
                if "#" in link: link, name = link.split("#", 1)
                if "@" in link:
                    b64, server = link.split("@", 1)
                    mp = base64.b64decode(b64 + "==").decode()
                else:
                    decoded = base64.b64decode(link + "==").decode()
                    mp, server = decoded.split("@", 1)
                host, port = split_host_port(server)
                method, pwd = mp.split(":", 1)
                p = {"name": urllib.parse.unquote(name), "type": "ss", "server": host, "port": port, "cipher": method, "password": pwd, "udp": True}
            elif l.startswith("trojan://"):
                link = l[9:]
                name = "Trojan"
                if "#" in link: link, name = link.split("#", 1)
                base, q = link.split("?", 1) if "?" in link else (link, "")
                qs = urllib.parse.parse_qs(q)
                pwd, server = base.split("@", 1)
                host, port = split_host_port(server)
                p = {"name": urllib.parse.unquote(name), "type": "trojan", "server": host, "port": port, "password": urllib.parse.unquote(pwd), "udp": True}
                if qs.get("sni", [""])[0]:
                    p["sni"] = qs.get("sni", [""])[0]
                if qs.get("allowInsecure", [""])[0] or qs.get("skip-cert-verify", [""])[0]:
                    p["skip-cert-verify"] = bool_qs(qs.get("allowInsecure", qs.get("skip-cert-verify", ["false"]))[0])
            elif l.startswith("hysteria2://"):
                link = l[12:]
                name = "Hysteria2"
                if "#" in link: link, name = link.split("#", 1)
                base, q = link.split("?", 1) if "?" in link else (link, "")
                qs = urllib.parse.parse_qs(q)
                pwd, server = base.split("@", 1)
                host, port = split_host_port(server)
                p = {"name": urllib.parse.unquote(name), "type": "hysteria2", "server": host, "port": port, "password": urllib.parse.unquote(pwd), "udp": True}
                if qs.get("sni", [""])[0]:
                    p["sni"] = qs.get("sni", [""])[0]
                if qs.get("insecure", [""])[0] or qs.get("skip-cert-verify", [""])[0]:
                    p["skip-cert-verify"] = bool_qs(qs.get("insecure", qs.get("skip-cert-verify", ["false"]))[0])
                if qs.get("obfs", [""])[0]:
                    p["obfs"] = qs.get("obfs", [""])[0]
                if qs.get("obfs-password", [""])[0]:
                    p["obfs-password"] = qs.get("obfs-password", [""])[0]
                if qs.get("alpn", [""])[0]:
                    p["alpn"] = [i for i in qs.get("alpn", [""])[0].split(",") if i]
            
            if p:
                proxies.append(p)
                names.append(p["name"])
        except: pass
    
    if not proxies: return ""
    proxy_names = ["Automatic", "Fallback"] + names
    direct_proxy_names = ["DIRECT", "Proxy", "Automatic"] + names
    cfg = {
        "mixed-port": 7890, "allow-lan": True, "bind-address": "*", "mode": "rule", "log-level": "info", "external-controller": "127.0.0.1:9090",
        "unified-delay": True, "tcp-concurrent": True,
        "dns": {
            "enable": True, "ipv6": False, "default-nameserver": ["223.5.5.5", "119.29.29.29"], "enhanced-mode": "fake-ip", "fake-ip-range": "198.18.0.1/16", "use-hosts": True,
            "nameserver": ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"],
            "fallback": ["https://public.dns.iij.jp/dns-query", "https://dns.twnic.tw/dns-query", "https://8.8.8.8/dns-query", "https://1.1.1.1/dns-query"],
            "fallback-filter": {"geoip": True, "geoip-code": "CN", "ipcidr": ["240.0.0.0/4", "0.0.0.0/32", "127.0.0.1/32"], "domain": ["+.google.com", "+.facebook.com", "+.twitter.com", "+.youtube.com", "+.googleapis.com", "+.googleapis.cn", "+.gvt1.com"]}
        },
        "proxies": proxies,
        "proxy-groups": [
            {"name": "Proxy", "type": "select", "proxies": proxy_names},
            {"name": "Automatic", "type": "url-test", "url": "http://www.gstatic.com/generate_204", "interval": 86400, "proxies": names},
            {"name": "Fallback", "type": "fallback", "url": "http://www.gstatic.com/generate_204", "interval": 7200, "proxies": names},
            {"name": "Apple", "type": "select", "proxies": direct_proxy_names},
            {"name": "MicroSoft", "type": "select", "proxies": direct_proxy_names},
            {"name": "Telegram", "type": "select", "proxies": ["Proxy", "Automatic"] + names},
            {"name": "Bilibili", "type": "select", "proxies": ["DIRECT", "Proxy", "Automatic"] + names},
            {"name": "Bahamut", "type": "select", "proxies": ["Proxy", "Automatic"] + names},
            {"name": "YouTube", "type": "select", "proxies": ["Proxy", "Automatic"] + names},
            {"name": "Netflix", "type": "select", "proxies": ["Proxy", "Automatic"] + names},
            {"name": "AIChat", "type": "select", "proxies": ["Proxy", "Automatic"] + names},
            {"name": "Game", "type": "select", "proxies": direct_proxy_names},
            {"name": "Final", "type": "select", "proxies": ["Proxy", "DIRECT", "Automatic"] + names}
        ],
        "rule-providers": {
            "reject": {"type": "http", "behavior": "domain", "url": "https://ghproxy.net/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt", "path": "./ruleset/reject.yaml", "interval": 86400},
            "proxy": {"type": "http", "behavior": "domain", "url": "https://ghproxy.net/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt", "path": "./ruleset/proxy.yaml", "interval": 86400},
            "direct": {"type": "http", "behavior": "domain", "url": "https://ghproxy.net/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt", "path": "./ruleset/direct.yaml", "interval": 86400},
            "gemini": {"type": "http", "behavior": "classical", "url": "https://ghproxy.net/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Gemini/Gemini.yaml", "path": "./ruleset/gemini.yaml", "interval": 86400},
            "Claude": {"type": "http", "behavior": "classical", "url": "https://ghproxy.net/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.yaml", "path": "./ruleset/Claude.yaml", "interval": 86400}
        },
        "rules": [
            "DOMAIN,services.googleapis.cn,DIRECT",
            "DOMAIN-KEYWORD,overleaf,DIRECT",
            "RULE-SET,reject,REJECT",
            "DOMAIN-SUFFIX,chatgpt.com,AIChat",
            "DOMAIN-SUFFIX,openai.com,AIChat",
            "DOMAIN-SUFFIX,pay.openai.com,AIChat",
            "DOMAIN-SUFFIX,chat.openai.com,AIChat",
            "DOMAIN-SUFFIX,auth0.openai.com,AIChat",
            "DOMAIN-SUFFIX,platform.openai.com,AIChat",
            "DOMAIN-SUFFIX,ai.com,AIChat",
            "DOMAIN-SUFFIX,oaistatic.com,AIChat",
            "DOMAIN-SUFFIX,oaiusercontent.com,AIChat",
            "DOMAIN-SUFFIX,bing.com,AIChat",
            "DOMAIN-SUFFIX,copilot.microsoft.com,AIChat",
            "DOMAIN-SUFFIX,poe.com,AIChat",
            "RULE-SET,Claude,AIChat",
            "RULE-SET,gemini,AIChat",
            "GEOSITE,openai,AIChat",
            "GEOSITE,youtube,YouTube",
            "GEOSITE,netflix,Netflix",
            "GEOSITE,telegram,Telegram",
            "GEOSITE,apple,Apple",
            "GEOSITE,microsoft,MicroSoft",
            "GEOSITE,bilibili,Bilibili",
            "GEOSITE,bahamut,Bahamut",
            "GEOSITE,category-games,Game",
            "PROCESS-NAME,aria2c.exe,DIRECT",
            "PROCESS-NAME,fdm.exe,DIRECT",
            "PROCESS-NAME,Thunder.exe,DIRECT",
            "PROCESS-NAME,Transmission.exe,DIRECT",
            "PROCESS-NAME,uTorrent.exe,DIRECT",
            "PROCESS-NAME,qbittorrent.exe,DIRECT",
            "RULE-SET,proxy,Proxy",
            "RULE-SET,direct,DIRECT",
            "GEOIP,LAN,DIRECT",
            "GEOIP,CN,DIRECT",
            "MATCH,Final"
        ]
    }
    return to_yaml(cfg)

def load_users():
    try:
        with open(USERS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f).get('users', [])
    except:
        return []

def resolve_token(path, qs):
    tok = qs.get('token', [None])[0]
    if path == '${SUB_PATH}' or tok == '${SUB_TOKEN}':
        return '${SUB_TOKEN}', True
    if not tok:
        return None, False
    for u in load_users():
        if u.get('token') == tok and u.get('enabled', True):
            return tok, False
    return None, False

def refresh_cache(token):
    try:
        raw = subprocess.check_output([GEN_SCRIPT, token], timeout=15)
        if not raw:
            return None
        raw_lines = base64.b64decode(raw).decode('utf-8', errors='ignore').splitlines()
        clash = build_clash(raw_lines).encode('utf-8')
        with CACHE_LOCK:
            CACHE[token] = (raw, clash)
        return CACHE[token]
    except:
        return None

def get_cache(token):
    with CACHE_LOCK:
        item = CACHE.get(token)
    return item or refresh_cache(token)

class ThreadedServer(ThreadingMixIn, HTTPServer):
    allow_reuse_address=True; daemon_threads=True

class H(BaseHTTPRequestHandler):
    def do_GET(s):
        import urllib.parse as up
        qs=up.parse_qs(up.urlparse(s.path).query)
        req_path=up.urlparse(s.path).path
        token,is_default=resolve_token(req_path, qs)
        item=get_cache(token) if token else None
        if item:
            try:
                s.send_response(200)
                cache_raw, cache_clash = item
                ua = s.headers.get('User-Agent', '').lower()
                is_clash = 'clash' in ua or 'mihomo' in ua or 'verge' in ua or qs.get('clash',[''])[0]=='1'
                safe_name = up.quote('${NODE_NAME}', safe='')
                if is_clash and cache_clash:
                    s.send_header('Content-Type','text/yaml; charset=utf-8')
                    s.send_header('Content-Length', str(len(cache_clash)))
                    s.send_header('Connection', 'close')
                    s.send_header('Profile-Update-Interval','24')
                    s.send_header('Profile-Title',safe_name)
                    s.send_header('Content-Disposition',f"inline; filename*=UTF-8''{safe_name}")
                    s.end_headers(); s.wfile.write(cache_clash)
                else:
                    s.send_header('Content-Type','text/plain; charset=utf-8')
                    s.send_header('Content-Length', str(len(cache_raw)))
                    s.send_header('Connection', 'close')
                    s.send_header('Profile-Update-Interval','24')
                    s.send_header('Profile-Title',safe_name)
                    s.send_header('Content-Disposition',f"inline; filename*=UTF-8''{safe_name}")
                    s.end_headers(); s.wfile.write(cache_raw)
            except: 
                s.send_response(500)
                s.send_header('Connection', 'close')
                s.end_headers()
        else: 
            s.send_response(404)
            s.send_header('Connection', 'close')
            s.end_headers()
    def log_message(s,*a): pass

# 后台定时刷新（首次+每60秒）
refresh_cache('${SUB_TOKEN}')
def bg_refresh():
    while True:
        time.sleep(10)
        with CACHE_LOCK:
            toks=list(CACHE.keys())
        for tok in toks:
            refresh_cache(tok)
threading.Thread(target=bg_refresh,daemon=True).start()

import ssl, os
CERT='${WORK_DIR}/sub_cert.pem'; KEY='${WORK_DIR}/sub_key.pem'
socketserver.TCPServer.allow_reuse_address=True
if os.path.exists(CERT) and os.path.exists(KEY):
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT,KEY)
    httpd=ThreadedServer(('0.0.0.0',PORT),H)
    httpd.socket=ctx.wrap_socket(httpd.socket,server_side=True)
else:
    httpd=ThreadedServer(('0.0.0.0',PORT),H)
httpd.serve_forever()
PYEOF

    # 刷新脚本：供 Python 调用，每次请求前更新订阅文件
    cat > "${WORK_DIR}/sub_gen.sh" << 'SUBEOF'
#!/usr/bin/env bash
JQ=/usr/bin/jq
CFG=/etc/xray/config.json; LOG=/etc/xray/argo.log; CONF=/etc/xray/argov.conf; USERS=/etc/xray/argov_users.json
USER_TOKEN="${1:-}"
[ -f "$CONF" ] && . "$CONF"
NODE_NAME="${NODE_NAME:-ArgoV}"; MODE="${ARGO_MODE:-temp}"; FIXED="${ARGO_FIXED_DOMAIN:-}"
CDN_PORT="${CDN_PORT:-443}"
get_domain() {
    local d
    [ -f "$LOG" ] && for i in 1 2 3; do
        d=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' "$LOG" | tail -1)
        [ -n "$d" ] && echo "$d" && return; sleep 1
    done
    echo "$LAST_ARGO_DOMAIN"
}
b64() { printf '%s' "$1" | base64 -w0 2>/dev/null || printf '%s' "$1" | base64 | tr -d '\n'; }
[ -f "$USERS" ] || exit 1
USER_JSON=$($JQ -c --arg tok "$USER_TOKEN" --arg def "${SUB_TOKEN:-}" 'if ($tok == "" or $tok == $def) then (.users[]|select(.name=="default" and (.enabled//true))) else (.users[]|select(.token==$tok and (.enabled//true))) end' "$USERS" 2>/dev/null | head -n 1)
[ -z "$USER_JSON" ] && exit 1
uuid=$(printf '%s' "$USER_JSON" | $JQ -r '.uuid//empty')
user_name=$(printf '%s' "$USER_JSON" | $JQ -r '.name//"user"')
[ -z "$uuid" ] && exit 1
IS_DEFAULT_USER=0
[ "$user_name" = "default" ] && IS_DEFAULT_USER=1
INCLUDE_CUSTOM=0
if [ "$IS_DEFAULT_USER" = "1" ]; then
    INCLUDE_CUSTOM=1
fi
cdn=$($JQ -r '.current_cdn//"cdn.31514926.xyz"' "$CFG")
cp=$($JQ -r '.current_cdn_port//443' "$CFG")
hd=$(get_domain)
ip=""; for s in ifconfig.me icanhazip.com checkip.amazonaws.com api.ipify.org; do
    ip=$(curl -s --max-time 3 "$s" 2>/dev/null || wget -qO- -T3 "$s" 2>/dev/null)
    echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' && break || ip=""
done
[ "$MODE" = "fixed-token" ] && hd="$FIXED"
links=""
if [ -n "$hd" ]; then
    links+="vless://${uuid}@${cdn}:${cp}?encryption=none&security=tls&sni=${hd}&type=ws&host=${hd}&path=%2Fvless-argo%3Fed%3D2560#${NODE_NAME}-VLESS"$'\n'
    j='{"v":"2","ps":"'"${NODE_NAME}"'-VMess","add":"'"${cdn}"'","port":"'"${cp}"'","id":"'"${uuid}"'","aid":"0","scy":"none","net":"ws","type":"none","host":"'"${hd}"'","path":"/vmess-argo?ed=2560","tls":"tls","sni":"'"${hd}"'","alpn":"","fp":""}'
    links+="vmess://$(b64 "$j")"$'\n'
fi
if $JQ -e '.inbounds[]|select(.tag=="reality")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    rport=$($JQ -r '.inbounds[]|select(.tag=="reality")|.port' "$CFG")
    rs=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]' "$CFG")
    rpub=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey' "$CFG")
    rsid=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds[0]//empty' "$CFG")
    [ -n "$rsid" ] && rsid="&sid=${rsid}" || rsid=""
    [ -n "$rport" ] && links+="vless://${uuid}@${ip}:${rport}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${rs}&pbk=${rpub}&fp=chrome${rsid}#${NODE_NAME}-Reality"$'\n'
fi
# 自定义链接（用户自添加）
if [ "$INCLUDE_CUSTOM" = "1" ] && [ -f /etc/xray/custom_links.txt ]; then
    while IFS= read -r cl; do
        [ -n "$cl" ] && links+="${cl}"$'\n'
    done < /etc/xray/custom_links.txt
fi
if $JQ -e '.inbounds[]|select(.tag=="hy2")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    hport=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.port' "$CFG")
    hsni=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CFG")
    [ -n "$hport" ] && links+="hysteria2://${uuid}@${ip}:${hport}?sni=${hsni}&insecure=1&allowInsecure=1&alpn=h3#${NODE_NAME}-Hy2"$'\n'
fi
out=$(printf '%s' "$links" | base64 -w0 2>/dev/null || printf '%s' "$links" | base64 | tr -d '\n')
[ "$IS_DEFAULT_USER" = "1" ] && printf '%s' "$out" > /etc/xray/sub.txt
printf '%s' "$out"
SUBEOF
    chmod +x "${WORK_DIR}/sub_gen.sh"
    bash "${WORK_DIR}/sub_gen.sh" "$SUB_TOKEN" >/dev/null 2>&1 || true

    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/argov-sub << EOF
#!/sbin/openrc-run
name=argov-sub
command=$py
command_args="${WORK_DIR}/sub.py"
command_background=true
pidfile=/var/run/argov-sub.pid
EOF
        chmod +x /etc/init.d/argov-sub
        rc-update add argov-sub default 2>/dev/null || true
        rc-service argov-sub restart 2>/dev/null || true
    else
        cat > /etc/systemd/system/argov-sub.service << EOF
[Unit]
Description=ArgoV Subscription Server
After=network.target
[Service]
Type=simple
ExecStart=$py ${WORK_DIR}/sub.py
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable argov-sub 2>/dev/null || true
        systemctl restart argov-sub 2>/dev/null || true
    fi
}

stop_sub_server() {
    if [ "$IS_ALPINE" = 1 ]; then
        rc-service argov-sub stop 2>/dev/null
        rc-update del argov-sub default 2>/dev/null
        rm -f /etc/init.d/argov-sub
    else
        systemctl stop argov-sub 2>/dev/null; systemctl disable argov-sub 2>/dev/null
        rm -f /etc/systemd/system/argov-sub.service
    fi
    rm -f "${WORK_DIR}/sub.py" "${WORK_DIR}/sub_gen.sh" "${WORK_DIR}/sub.txt"
    systemctl daemon-reload 2>/dev/null || true
}

start_stats_service() {
    ensure_users_file || return 1
    sync_xray_users || true
    local py; py=$(py_bin)
    [ -z "$py" ] && return 1

    cat > "${WORK_DIR}/stats.py" << 'PYEOF'
import json, os, re, subprocess, time

USERS_FILE = "/etc/xray/argov_users.json"
CONFIG_FILE = "/etc/xray/config.json"
XRAY_BIN = "/etc/xray/xray"
API_SERVER = "127.0.0.1:10085"
INTERVAL = 60

# xray api statsquery --server=127.0.0.1:10085 --pattern user>>>argov-user>>>traffic>>>uplink --reset
# xray api statsquery --server=127.0.0.1:10085 --pattern user>>>argov-user>>>traffic>>>downlink --reset

def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        if path == USERS_FILE:
            json.dump(data, f, ensure_ascii=False, indent=2)
        else:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    os.replace(tmp, path)

def email_for(name):
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", (name or "user")).strip("-._").lower()
    return "argov-" + (safe or "user")

def query_stat(email, direction):
    pattern = f"user>>>{email}>>>traffic>>>{direction}"
    cmd = [XRAY_BIN, "api", "statsquery", f"--server={API_SERVER}", "--pattern", pattern, "--reset"]
    try:
        raw = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, timeout=10).decode("utf-8", "ignore")
    except Exception:
        return 0
    total = 0
    try:
        data = json.loads(raw)
        for item in data.get("stat") or data.get("stats") or []:
            total += int(item.get("value") or 0)
    except Exception:
        for n in re.findall(r'"value"\s*:\s*([0-9]+)', raw):
            total += int(n)
    return total

def sync_config(users):
    cfg = load_json(CONFIG_FILE, {})
    enabled = []
    for u in users:
        if not u.get("enabled", True) or not u.get("uuid"):
            continue
        enabled.append({"uuid": u["uuid"], "email": u.get("email") or email_for(u.get("name"))})
    if not enabled:
        return False

    def vless(flow=False):
        out = []
        for u in enabled:
            c = {"id": u["uuid"], "email": u["email"]}
            if flow:
                c["flow"] = "xtls-rprx-vision"
            out.append(c)
        return out

    for inbound in cfg.get("inbounds", []):
        tag = inbound.get("tag")
        if tag == "argo-in":
            inbound.setdefault("settings", {})["clients"] = vless(True)
        elif tag == "vless-ws":
            inbound.setdefault("settings", {})["clients"] = vless(False)
        elif tag == "vmess-ws":
            inbound.setdefault("settings", {})["clients"] = [{"id": u["uuid"], "alterId": 0, "email": u["email"]} for u in enabled]
        elif tag == "reality":
            inbound.setdefault("settings", {})["clients"] = vless(True)
        elif tag == "hy2":
            settings = inbound.setdefault("settings", {})
            settings["version"] = 2
            settings["users"] = [{"auth": u["uuid"], "level": 0, "email": u["email"]} for u in enabled]

    if not any(i.get("tag") == "api-in" for i in cfg.get("inbounds", [])):
        cfg.setdefault("inbounds", []).append({"listen":"127.0.0.1","port":10085,"protocol":"dokodemo-door","tag":"api-in","settings":{"address":"127.0.0.1"}})
    cfg["api"] = {"tag":"api","services":["StatsService"]}
    cfg["stats"] = {}
    cfg["policy"] = {"levels":{"0":{"statsUserUplink":True,"statsUserDownlink":True}},"system":{"statsInboundUplink":True,"statsInboundDownlink":True,"statsOutboundUplink":True,"statsOutboundDownlink":True}}
    routing = cfg.setdefault("routing", {})
    rules = routing.setdefault("rules", [])
    if not any(isinstance(r, dict) and r.get("inboundTag") == ["api-in"] and r.get("outboundTag") == "api" for r in rules):
        rules.insert(0, {"type":"field","inboundTag":["api-in"],"outboundTag":"api"})
    save_json(CONFIG_FILE, cfg)
    return True

def restart_xray():
    if os.path.exists("/etc/alpine-release"):
        subprocess.call(["rc-service", "xray", "restart"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.call(["systemctl", "restart", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def poll_once():
    data = load_json(USERS_FILE, {"version": 1, "users": []})
    changed = False
    disabled = False
    for u in data.get("users", []):
        if not u.get("enabled", True):
            continue
        email = u.get("email") or email_for(u.get("name"))
        u["email"] = email
        up = query_stat(email, "uplink")
        down = query_stat(email, "downlink")
        if up or down:
            u["used_up"] = int(u.get("used_up") or 0) + up
            u["used_down"] = int(u.get("used_down") or 0) + down
            changed = True
        quota = int(u.get("quota_bytes") or 0)
        used = int(u.get("used_up") or 0) + int(u.get("used_down") or 0)
        if u.get("name") != "default" and quota > 0 and used >= quota:
            u["enabled"] = False
            changed = True
            disabled = True
    if changed:
        save_json(USERS_FILE, data)
    if disabled and sync_config(data.get("users", [])):
        restart_xray()

def main():
    while True:
        poll_once()
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
PYEOF

    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/argov-stats << EOF
#!/sbin/openrc-run
name=argov-stats
command=$py
command_args="${WORK_DIR}/stats.py"
command_background=true
pidfile=/var/run/argov-stats.pid
EOF
        chmod +x /etc/init.d/argov-stats
        rc-update add argov-stats default 2>/dev/null || true
        rc-service argov-stats restart 2>/dev/null || true
    else
        cat > /etc/systemd/system/argov-stats.service << EOF
[Unit]
Description=ArgoV User Traffic Quota Watcher
After=network.target xray.service

[Service]
Type=simple
ExecStart=$py ${WORK_DIR}/stats.py
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable argov-stats 2>/dev/null || true
        systemctl restart argov-stats 2>/dev/null || true
    fi
}

stop_stats_service() {
    if [ "$IS_ALPINE" = 1 ]; then
        rc-service argov-stats stop 2>/dev/null || true
        rc-update del argov-stats default 2>/dev/null || true
        rm -f /etc/init.d/argov-stats
    else
        systemctl stop argov-stats 2>/dev/null || true
        systemctl disable argov-stats 2>/dev/null || true
        rm -f /etc/systemd/system/argov-stats.service
        systemctl daemon-reload 2>/dev/null || true
    fi
    rm -f "${WORK_DIR}/stats.py"
}

#==============================================================================
# 状态 & 摘要
#==============================================================================
get_status() {
    if [ "$IS_ALPINE" = 1 ]; then
        (rc-service xray status 2>/dev/null | grep -qE "started|crashed" || pgrep -x xray &>/dev/null) && { XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"; } || { XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"; }
        (rc-service argov-tunnel status 2>/dev/null | grep -qE "started|crashed" || pgrep -f 'argo.*tunnel' &>/dev/null) && { TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"; } || { TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"; }
    else
        systemctl is-active xray 2>/dev/null && { XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"; } || { XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"; }
        systemctl is-active argov-tunnel 2>/dev/null && { TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"; } || { TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"; }
    fi
}
get_proto_summary() {
    local s="VL-Argo VM-Argo"
    jq -e '.inbounds[]|select(.protocol=="shadowsocks")' "$CONFIG_FILE" >/dev/null 2>&1 && s="$s SS"
    jq -e '.inbounds[]|select(.tag=="reality")' "$CONFIG_FILE" >/dev/null 2>&1 && s="$s Reality"
    jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1 && s="$s Hy2"
    echo "$s"
}

#==============================================================================
# 查看节点
#==============================================================================
show_node() {
    clear; load_conf
    [ ! -f "$CONFIG_FILE" ] && { red_msg "未检测到安装！"; return; }
    local uuid hd cd cp ip
    uuid=$(get_uuid); hd=$(get_argo_domain); cd=$(get_cdn); cp=$(get_cdn_port); ip=$(get_ip)
    [ -z "$hd" ] && [ "$ARGO_MODE" != "fixed-token" ] && { yellow_msg "  ⚠ 正在获取 Argo 域名..."; sleep 3; hd=$(get_argo_domain); }
    [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"

    echo ""
    echo -e "${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e "${purple}║${re}       ${white}ArgoV · ${NODE_NAME}${re}"
    echo -e "${purple}║${re}       ${cyan}节点连接参数${re}"
    echo -e "${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  名称: ${white}${NODE_NAME}${re}    UUID: ${purple}$(echo "$uuid" | cut -c1-16)...${re}"
    [ -n "$ip" ] && echo -e "  VPS IP: ${cyan}${ip}${re}"
    echo ""

    if [ -n "$hd" ]; then
        echo -e "  ${white}── Argo 隧道 (无需开放端口) ──${re}"
        echo ""
        echo -e "  ${yellow}① VLESS${re}  ${green}$(gen_vless_link "$uuid" "$hd" "$cd" "$cp")${re}\n"
        echo -e "  ${yellow}② VMess${re}  ${green}$(gen_vmess_link "$uuid" "$hd" "$cd" "$cp")${re}\n"
        load_conf 2>/dev/null; local su; su=$(get_sub_url "$ip" 2>/dev/null)
        show_qr "${su:-$(gen_vless_link "$uuid" "$hd" "$cd" "$cp")}"
    fi

    if jq -e '.inbounds[]|select(.tag=="reality")' "$CONFIG_FILE" >/dev/null 2>&1 && [ -n "$ip" ]; then
        local rport rsni rp
        rport=$(jq -r '.inbounds[]|select(.tag=="reality")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        rsni=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]//empty' "$CONFIG_FILE" 2>/dev/null)
        rp=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey//empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── VLESS Reality (端口 ${rport}) ──${re}"
        echo ""
        echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$rport" "$rsni" "$rp" "$REALITY_SHORTID")${re}"
        echo -e "  ${cyan}SNI${re}: ${rsni}  Flow: xtls-rprx-vision"
        [ -n "$REALITY_SHORTID" ] && echo -e "  ${cyan}ShortId${re}: ${REALITY_SHORTID}"
        echo ""
    fi

    if jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1 && [ -n "$ip" ]; then
        local hport hsni
        hport=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        hsni=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── Hysteria2 (端口 ${hport}) ──${re}"
        echo ""
        echo -e "  ${green}$(gen_hy2_link "$uuid" "$ip" "$hport" "$hsni" "${NODE_NAME}-Hy2")${re}"
        echo -e "  ${cyan}SNI${re}: ${hsni}  ALPN: h3  TLS: self-signed/insecure"
        echo ""
    fi

    if jq -e '.inbounds[]|select(.protocol=="shadowsocks")' "$CONFIG_FILE" >/dev/null 2>&1 && [ -n "$ip" ]; then
        local sport sm sp
        sport=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        sm=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
        sp=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.password//empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── Shadowsocks (端口 ${sport}) ──${re}"
        echo ""
        echo -e "  ${green}$(gen_ss_link "$sm" "$sp" "$ip" "$sport" "${NODE_NAME}-SS")${re}"
        echo -e "  ${cyan}加密${re}: ${sm}\n"
    fi

    echo -e "  ${yellow}💡${re} 复制链接 → 客户端导入    菜单 2 换线路 | 菜单 3 改配置"
    local su; su=$(get_sub_url "$ip" 2>/dev/null)
    [ -n "$su" ] && { echo ""; echo -e "  ${purple}━━━ 📡 订阅链接 ━━━${re}"; echo -e "  ${white}${su}${re}"; echo -e "  ${yellow}💡 V2rayN / Shadowrocket / Clash 系全平台智能适配，一键导入${re}"; }
}

#==============================================================================
# 服务控制
#==============================================================================
start_services() {
    yellow_msg "Starting..."
    systemctl start xray argov-tunnel argov-stats 2>/dev/null || true
    rc-service xray start 2>/dev/null || true
    rc-service argov-tunnel start 2>/dev/null || true
    rc-service argov-stats start 2>/dev/null || true
    sleep 2; get_status
    echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"
    green_msg "Done"
}
stop_services()  {
    yellow_msg "Stopping..."
    systemctl stop xray argov-tunnel argov-stats 2>/dev/null || true
    rc-service xray stop 2>/dev/null || true
    rc-service argov-tunnel stop 2>/dev/null || true
    rc-service argov-stats stop 2>/dev/null || true
    sleep 1; get_status
    echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"
    red_msg "Stopped"
}
restart_services() {
    yellow_msg "Restarting..."
    rm -f "$TUNNEL_LOG"
    systemctl restart xray argov-tunnel argov-stats 2>/dev/null || true
    rc-service xray restart 2>/dev/null || true
    rc-service argov-tunnel restart 2>/dev/null || true
    rc-service argov-stats restart 2>/dev/null || true
    sleep 3; get_status
    local d; d=$(get_argo_domain)
    echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"
    green_msg "Done"
    [ -n "$d" ] && { echo -e "  Domain: ${purple}${d}${re}"; LAST_ARGO_DOMAIN="$d"; save_conf; }
}

#==============================================================================
# 优选域名
#==============================================================================
edit_cdn() {
    load_conf
    while true; do
        clear; local cc cp; cc=$(get_cdn); cp=$(get_cdn_port)
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}更换优选域名 / 线路${re}                 ${purple}║${re}"
        echo -e " ${purple}║${re}       ${yellow}当前: ${green}${cc}:${cp}${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${white}── 三网通用 ──${re}"
        for k in 1 2 3 4 5 6 7; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done
        echo ""; echo -e "  ${white}── 运营商专线 ──${re}"
        for k in 8 9 10; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done
        echo ""; echo -e "  ${white}── 其他 ──${re}"
        for k in 11 12 13; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done
        echo ""
        echo -e "  ${cyan}c${re}. 自定义 (host:port)    ${cyan}p${re}. 仅改端口    ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c; local np="$cp"
        case "$c" in
            1) CDN_DOMAIN="cdn.31514926.xyz" ;; 2) CDN_DOMAIN="skk.moe" ;; 3) CDN_DOMAIN="ip.sb" ;;
            4) CDN_DOMAIN="time.is" ;; 5) CDN_DOMAIN="bestcf.top" ;; 6) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;;
            7) CDN_DOMAIN="cf.090227.xyz" ;; 8) CDN_DOMAIN="yidong.19931101.xyz" ;;
            9) CDN_DOMAIN="liantong.19931101.xyz" ;; 10) CDN_DOMAIN="dianxin.19931101.xyz" ;;
            11) CDN_DOMAIN="cdn.2020111.xyz" ;; 12) CDN_DOMAIN="xn--b6gac.eu.org" ;; 13) CDN_DOMAIN="cdns.doon.eu.org" ;;
            c|C) read -p "  host:port: " raw; [[ "$raw" =~ ^(.+):([0-9]+)$ ]] && { CDN_DOMAIN="${BASH_REMATCH[1]}"; np="${BASH_REMATCH[2]}"; } || CDN_DOMAIN="$raw" ;;
            p|P) read -p "  端口: " np; CDN_DOMAIN="$cc" ;;
            0) return ;; *) red_msg "无效"; sleep 1; continue ;;
        esac
        [ -n "$CDN_DOMAIN" ] && { CDN_PORT="$np"
            jq --arg cdn "$CDN_DOMAIN" --argjson p "$CDN_PORT" '.current_cdn=$cdn|.current_cdn_port=$p' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            save_conf; echo ""; green_msg "切换成功！${CDN_DOMAIN}:${CDN_PORT}"; yellow_msg "  💡 客户端改 Address/Port 即可"; break; }
    done
}

#==============================================================================
# 修改配置
#==============================================================================
change_config() {
    load_conf
    while true; do
        clear; [ ! -f "$CONFIG_FILE" ] && { red_msg "请先安装！"; return; }
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}          ${white}节点配置修改${re}                    ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${green}1${re}. 节点名称 — ${cyan}${NODE_NAME}${re}"
        echo -e "  ${green}2${re}. 更换 UUID"
        echo -e "  ${green}3${re}. 切换 Argo 隧道 (临时↔固定)"
        echo -e "  ${green}4${re}. SS 加密 — ${cyan}${SS_METHOD}${re}"
        echo -e "  ${green}5${re}. Reality 伪装域名 — ${cyan}${REALITY_SNI}${re}"
        echo -e "  ${green}6${re}. 管理协议节点 (添加/删除)"
        echo -e "  ${green}7${re}. 查看节点链接"
        echo -e "  ${green}8${re}. 刷新 Argo 域名"
        echo -e "  ${green}9${re}. 订阅配置"
        echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            1) read -p "  新名称 [${NODE_NAME}]: " n; [ -n "$n" ] && NODE_NAME="$n"; save_conf; green_msg "已更新: ${NODE_NAME}" ;;
            2) local nu; read -p "  新 UUID (回车生成): " nu; [ -z "$nu" ] && nu=$(cat /proc/sys/kernel/random/uuid)
               jq --arg u "$nu" '(.inbounds[].settings.clients[]?|select(.id)|.id)|=$u' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
               UUID_CUSTOM="$nu"; save_conf; ensure_users_file; sync_xray_users; systemctl restart xray 2>/dev/null; rc-service xray restart 2>/dev/null || true; green_msg "UUID 已更新！${nu}" ;;
            3) switch_argo_tunnel ;;
            4) echo ""; for i in "${!SS_METHODS[@]}"; do echo -e "  ${green}$((i+1))${re}. ${SS_METHODS[$i]}"; done; echo ""
               read -p "  选择 [默认 aes-256-gcm]: " sm; [ -n "$sm" ] && SS_METHOD="${SS_METHODS[$((sm-1))]:-$SS_METHOD}"
               save_conf; green_msg "SS: ${SS_METHOD}" ;;
            5) echo ""; for i in "${!REALITY_SNIS[@]}"; do echo -e "  ${green}$((i+1))${re}. ${REALITY_SNIS[$i]}"; done; echo ""
               read -p "  选择 [默认 www.amazon.com]: " rs; [ -n "$rs" ] && REALITY_SNI="${REALITY_SNIS[$((rs-1))]:-$REALITY_SNI}"
               save_conf; green_msg "Reality SNI: ${REALITY_SNI}" ;;
            6) manage_protocols ;;
            7) show_node ;; 8) restart_services ;; 9) edit_subscription ;; 0) return ;; *) red_msg "无效" ;;
        esac; read -p "  按回车继续..." -r
    done
}

#==============================================================================
# Argo 隧道切换
#==============================================================================
manage_users() {
    load_conf
    [ ! -f "$CONFIG_FILE" ] && { red_msg "Please install first."; return; }
    ensure_users_file || { red_msg "Cannot create users database."; return; }

    while true; do
        clear
        echo ""
        echo -e "  ${white}ArgoV users and traffic quota${re}"
        echo ""
        printf "  %-16s %-8s %-14s %-14s %s\n" "name" "state" "used" "quota" "token"
        printf "  %-16s %-8s %-14s %-14s %s\n" "----" "-----" "----" "-----" "-----"
        while IFS=$'\t' read -r name enabled used quota token; do
            [ -z "$name" ] && continue
            local state="off"
            [ "$enabled" = "1" ] && state="on"
            printf "  %-16s %-8s %-14s %-14s %s\n" "$name" "$state" "$(format_bytes "$used")" "$([ "$quota" = "0" ] && echo unlimited || format_bytes "$quota")" "$token"
        done < <(user_db_op list 2>/dev/null)
        echo ""
        echo -e "  ${green}1${re}. Add limited user"
        echo -e "  ${green}2${re}. Enable user"
        echo -e "  ${yellow}3${re}. Disable user"
        echo -e "  ${green}4${re}. Set quota"
        echo -e "  ${green}5${re}. Reset usage"
        echo -e "  ${cyan}6${re}. Show subscription URL"
        echo -e "  ${red}7${re}. Delete user"
        echo -e "  ${red}0${re}. Back"
        echo ""
        read -p "  Select: " c
        case "$c" in
            1)
                local name quota quota_bytes uuid token ip
                read -p "  User name (letters/numbers, e.g. friend): " name
                [ -z "$name" ] && { red_msg "Empty name."; sleep 1; continue; }
                read -p "  Quota, e.g. 200G (0 = unlimited): " quota
                quota_bytes=$(parse_bytes "${quota:-0}")
                [ "$quota_bytes" -lt 0 ] && { red_msg "Invalid quota."; sleep 1; continue; }
                uuid=$(rand_uuid)
                token=$(rand_token)
                if user_db_op add "$name" "$quota_bytes" "$uuid" "$token"; then
                    restart_user_runtime
                    ip=$(get_ip)
                    echo ""
                    green_msg "User added."
                    echo -e "  URL: ${green}$(get_user_sub_url "$ip" "$token")${re}"
                    echo -e "  Limited users receive only: VLESS Argo, VMess Argo, Reality, Hysteria2."
                else
                    red_msg "User already exists or cannot be added."
                fi
                read -p "  Press Enter..." -r
                ;;
            2|3|4|5|6|7)
                local name quota quota_bytes token ip line enabled used quota_cur
                read -p "  User name: " name
                [ -z "$name" ] && { red_msg "Empty name."; sleep 1; continue; }
                case "$c" in
                    2)
                        user_db_op set-enabled "$name" 1 && restart_user_runtime && green_msg "Enabled." || red_msg "Cannot enable user."
                        ;;
                    3)
                        user_db_op set-enabled "$name" 0 && restart_user_runtime && green_msg "Disabled." || red_msg "Cannot disable user."
                        ;;
                    4)
                        read -p "  New quota, e.g. 200G (0 = unlimited): " quota
                        quota_bytes=$(parse_bytes "${quota:-0}")
                        [ "$quota_bytes" -lt 0 ] && { red_msg "Invalid quota."; sleep 1; continue; }
                        user_db_op set-quota "$name" "$quota_bytes" && restart_user_runtime && green_msg "Quota updated." || red_msg "Cannot update quota."
                        ;;
                    5)
                        user_db_op reset "$name" && restart_user_runtime && green_msg "Usage reset." || red_msg "Cannot reset user."
                        ;;
                    6)
                        line=$(user_db_op show "$name" 2>/dev/null) || { red_msg "User not found."; sleep 1; continue; }
                        IFS=$'\t' read -r name enabled used quota_cur token << EOF
$line
EOF
                        ip=$(get_ip)
                        echo ""
                        echo -e "  ${green}$(get_user_sub_url "$ip" "$token")${re}"
                        read -p "  Press Enter..." -r
                        ;;
                    7)
                        echo -ne "  Delete ${name}? (y/n): "; read cf
                        if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                            user_db_op delete "$name" && restart_user_runtime && green_msg "Deleted." || red_msg "Cannot delete user."
                        fi
                        ;;
                esac
                sleep 1
                ;;
            0) return ;;
            *) red_msg "Invalid."; sleep 1 ;;
        esac
    done
}

switch_argo_tunnel() {
    load_conf; clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}切换 Argo 隧道${re}                       ${purple}║${re}"
    echo -e " ${purple}║${re}       ${yellow}当前: $([ "$ARGO_MODE" = "temp" ] && echo "临时" || echo "固定")${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""; echo -e "  ${green}1${re}. 临时隧道     ${green}2${re}. 固定 Token    ${red}0${re}. 返回"
    read -p "  请选择: " c
    case "$c" in
        1) ARGO_MODE="temp"; ARGO_AUTH=""; ARGO_FIXED_DOMAIN=""; save_conf; rebuild_tunnel "temp"; restart_services ;;
        2) read -p "  域名: " ARGO_FIXED_DOMAIN; read -p "  Token: " ARGO_AUTH
           [ -z "$ARGO_FIXED_DOMAIN" ] || [ -z "$ARGO_AUTH" ] && { red_msg "不能为空"; return; }
           ARGO_MODE="fixed-token"; save_conf; rebuild_tunnel "fixed-token"; restart_services; green_msg "已切换: ${ARGO_FIXED_DOMAIN}" ;;
        0) return ;; *) red_msg "无效" ;;
    esac
}
rebuild_tunnel() {
    if [ "$IS_ALPINE" = 1 ]; then
        if [ "$1" = "fixed-token" ]; then
            cat > /etc/init.d/argov-tunnel << EOF
#!/sbin/openrc-run
name=argov-tunnel
command=${WORK_DIR}/argo
command_args="tunnel --edge-ip-version auto --no-autoupdate run --token ${ARGO_AUTH}"
command_background=true
pidfile=/var/run/argov-tunnel.pid
EOF
        else
            cat > "${WORK_DIR}/argov-tunnel.sh" << EOF
#!/bin/sh
# 等待网络就绪
for i in 1 2 3 4 5 6 7 8 9 10; do
    ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && break
    sleep 3
done
# 重试循环（崩溃自动恢复）
while true; do
    ${WORK_DIR}/argo tunnel --url http://localhost:${ARGO_PORT} --no-autoupdate --edge-ip-version auto >> ${TUNNEL_LOG} 2>&1
    sleep 10
done
EOF
            chmod +x "${WORK_DIR}/argov-tunnel.sh"
            cat > /etc/init.d/argov-tunnel << EOF
#!/sbin/openrc-run
name=argov-tunnel
command=${WORK_DIR}/argov-tunnel.sh
command_background=true
pidfile=/var/run/argov-tunnel.pid
EOF
        fi
        chmod +x /etc/init.d/argov-tunnel
        return
    fi
    if [ "$1" = "fixed-token" ]; then
        cat > /etc/systemd/system/argov-tunnel.service << EOF
[Unit]
Description=Cloudflare Argo Tunnel (Fixed)
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=${WORK_DIR}/argo tunnel --edge-ip-version auto --no-autoupdate run --token ${ARGO_AUTH}
Restart=on-failure
RestartSec=30s
[Install]
WantedBy=multi-user.target
EOF
    else
        cat > /etc/systemd/system/argov-tunnel.service << EOF
[Unit]
Description=Cloudflare Argo Tunnel (Temp)
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=${WORK_DIR}/argo tunnel --url http://localhost:${ARGO_PORT} --no-autoupdate --edge-ip-version auto
StandardOutput=append:${TUNNEL_LOG}
StandardError=append:${TUNNEL_LOG}
Restart=on-failure
RestartSec=30s
[Install]
WantedBy=multi-user.target
EOF
    fi; systemctl daemon-reload
}

#==============================================================================
# 协议选择 (安装步骤⑦)
#==============================================================================
select_protocols() {
    while true; do
        clear
        local sum="VLESS-Argo + VMess-Argo"
        [ "$ENABLE_REALITY" = 1 ] && sum="$sum + Reality"
        [ "$ENABLE_HY2" = 1 ] && sum="$sum + Hysteria2"
        [ "$ENABLE_SS" = 1 ] && sum="$sum + Shadowsocks"
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}选择额外协议（可选）${re}                    ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${white}始终安装：VLESS-Argo + VMess-Argo${re}"
        echo ""
        echo -e "  ${green}1${re}. VLESS Reality ${cyan}[$( [ "$ENABLE_REALITY" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     XTLS Vision + Reality，需开放端口，抗封锁"
        echo ""
        echo -e "  ${green}2${re}. Hysteria2 ${cyan}[$( [ "$ENABLE_HY2" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     Xray 原生 Hy2，UDP/QUIC，高速，进入用户统计和限额"
        echo ""
        echo -e "  ${green}3${re}. Shadowsocks ${cyan}[$( [ "$ENABLE_SS" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     AEAD/2022 加密，需开放端口，轻量高速"
        echo ""
        echo -e "  ${yellow}📋 当前: ${green}${sum}${re}"
        echo -e "  ${yellow}💡 输 1/2/3 切换勾选，输 0 进入端口配置${re}"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  (1/2/3=切换 / 0=下一步): " c
        case "$c" in
            1) ENABLE_REALITY=$((1-ENABLE_REALITY)); continue ;;
            2) ENABLE_HY2=$((1-ENABLE_HY2)); continue ;;
            3) ENABLE_SS=$((1-ENABLE_SS)); continue ;;
            0)
                echo ""
                [ "$ENABLE_REALITY" = 1 ] && { local rp; rp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Reality 端口 [随机 ${rp}]: ${re}"; read ri; REALITY_PORT="${ri:-$rp}"; echo -e "  → ${green}${REALITY_PORT}${re}"; }
                [ "$ENABLE_HY2" = 1 ] && { local hp; hp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Hysteria2 端口 [随机 ${hp}]: ${re}"; read hi; HY2_PORT="${hi:-$hp}"; echo -e "  → ${green}${HY2_PORT}${re}"; }
                [ "$ENABLE_SS" = 1 ] && { local sp; sp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Shadowsocks 端口 [随机 ${sp}]: ${re}"; read si; SS_PORT="${si:-$sp}"; echo -e "  → ${green}${SS_PORT}${re}"; }
                echo ""
                echo -e "  ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo -e "  ${white}即将安装:${re}  Argo: VLESS+VMess"
                [ "$ENABLE_REALITY" = 1 ] && echo -e "  Reality: 端口 ${green}${REALITY_PORT}${re}  (UUID/SNI/密钥 自动生成)"
                [ "$ENABLE_HY2" = 1 ] && echo -e "  Hysteria2: 端口 ${green}${HY2_PORT}${re}  (UUID/证书 自动生成)"
                [ "$ENABLE_SS" = 1 ] && echo -e "  Shadowsocks: 端口 ${green}${SS_PORT}${re}  (加密/密码 自动生成)"
                echo -e "  ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo ""
                echo -ne "  ${yellow}开始安装? (y/n/0=返回) [y]: ${re}"
                read cf
                [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return 1; }
                [ "$cf" = "0" ] && continue
                mkdir -p /etc/xray 2>/dev/null; save_conf; return
                ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac
    done
}

#==============================================================================
# 交互式安装
#==============================================================================
interactive_install() {
    load_conf; clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}  ${white}ArgoV · 交互式安装向导${re}              ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""; yellow_msg "按提示配置，回车使用默认值。"; echo ""
    # 系统检测展示
    local sys_type; [ "$IS_ALPINE" = 1 ] && sys_type="Alpine Linux (OpenRC)" || sys_type="Debian/Ubuntu (systemd)"
    echo -e "  ${cyan}🖥 检测到系统: ${green}${sys_type}${re}\n"

    echo -e " ${white}━━━ ① 节点名称 ━━━${re}"; read -p "  [${NODE_NAME}]: " n; [ -n "$n" ] && NODE_NAME="$n"; echo -e "  → ${green}${NODE_NAME}${re}\n"
    echo -e " ${white}━━━ ② CDN 地址 ━━━${re}"; echo -e "  ${green}1${re}. 默认 ${green}2${re}. 列表选 ${green}3${re}. 自定义"; read -p "  [1]: " ct
    case "${ct:-1}" in
        2) for k in {1..13}; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done; read -p "  序号 [1]: " ci
           case "${ci:-1}" in
               1) CDN_DOMAIN="cdn.31514926.xyz" ;; 2) CDN_DOMAIN="skk.moe" ;; 3) CDN_DOMAIN="ip.sb" ;;
               4) CDN_DOMAIN="time.is" ;; 5) CDN_DOMAIN="bestcf.top" ;; 6) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;;
               7) CDN_DOMAIN="cf.090227.xyz" ;; 8) CDN_DOMAIN="yidong.19931101.xyz" ;; 9) CDN_DOMAIN="liantong.19931101.xyz" ;;
               10) CDN_DOMAIN="dianxin.19931101.xyz" ;; 11) CDN_DOMAIN="cdn.2020111.xyz" ;; 12) CDN_DOMAIN="xn--b6gac.eu.org" ;;
               13) CDN_DOMAIN="cdns.doon.eu.org" ;; esac ;;
        3) read -p "  地址: " CDN_DOMAIN; [ -z "$CDN_DOMAIN" ] && CDN_DOMAIN="$CDN_DEFAULT" ;;
    esac; echo -e "  → ${green}${CDN_DOMAIN}${re}\n"

    echo -e " ${white}━━━ ③ 客户端端口 ━━━${re}"; echo -e "  ${yellow}CF: 443 8443 2053 2083 2087 2096${re}"; read -p "  [${CDN_PORT}]: " n; [ -n "$n" ] && CDN_PORT="$n"; echo -e "  → ${green}${CDN_PORT}${re}\n"
    echo -e " ${white}━━━ ④ UUID ━━━${re}"; read -p "  [自动生成]: " n; [ -n "$n" ] && UUID_CUSTOM="$n"; echo ""
    echo -e " ${white}━━━ ⑤ Argo 隧道 ━━━${re}"; echo -e "  ${green}1${re}. 临时     ${green}2${re}. 固定 Token"; read -p "  [1]: " tt
    case "${tt:-1}" in 2) read -p "  域名: " ARGO_FIXED_DOMAIN; read -p "  Token: " ARGO_AUTH
           [ -n "$ARGO_FIXED_DOMAIN" ] && [ -n "$ARGO_AUTH" ] && ARGO_MODE="fixed-token" ;; esac; echo ""

    echo -e " ${white}━━━ ⑥ 内部端口 ━━━${re}"; echo -e "  ${cyan}Argo:${ARGO_PORT}  VLESS:${VLESS_WS_PORT}  VMess:${VMESS_WS_PORT}${re}"
    read -p "  起始端口 [回车跳过]: " bp
    if [ -n "$bp" ] && is_port "$bp"; then ARGO_PORT="$bp"; VLESS_WS_PORT=$((bp+1)); VMESS_WS_PORT=$((bp+2)); fi
    echo ""
    echo -e " ${white}━━━ ⑦ 订阅域名（可选）━━━${re}"
    echo -e "  ${yellow}输入已指向本机IP的域名，订阅URL变为 https://域名:端口/sub?token=xxx${re}"
    echo -e "  ${yellow}使用CF代理端口 2096，DNS开小黄云即可，无需Origin Rules${re}"
    echo -e "  ${yellow}回车跳过则使用 http://IP:端口 格式${re}"
    [ -n "$SUB_DOMAIN" ] && echo -e "  ${cyan}当前: ${SUB_DOMAIN}${re}"
    read -p "  域名 [回车跳过]: " sd
    [ -n "$sd" ] && SUB_DOMAIN="$sd"
    if [ -n "$SUB_DOMAIN" ]; then
        echo ""
        echo -e "  ${yellow}选择 CF 支持的 HTTPS 端口:${re}"
        echo -e "  ${cyan}1${re}. 2096 (默认)  ${cyan}2${re}. 8443  ${cyan}3${re}. 2053  ${cyan}4${re}. 2083  ${cyan}5${re}. 2087  ${cyan}6${re}. 443  ${cyan}c${re}. 自定义"
        read -p "  [1]: " pc
        case "${pc:-1}" in
            2) SUB_PORT=8443 ;; 3) SUB_PORT=2053 ;; 4) SUB_PORT=2083 ;;
            5) SUB_PORT=2087 ;; 6) SUB_PORT=443 ;;
            c|C) read -p "  端口: " SUB_PORT ;;
            *) SUB_PORT=2096 ;;
        esac
        if port_in_use "$SUB_PORT"; then
            red_msg "端口 ${SUB_PORT} 被占用！"
            SUB_PORT=$(find_free_port 2096)
            yellow_msg "  自动切换为 ${SUB_PORT}"
        fi
        echo -e "  → ${green}https://${SUB_DOMAIN}:${SUB_PORT}/sub?token=(自动生成)${re}"
    else
        local sp_def; sp_def=$(find_free_port "$(shuf -i 20000-50000 -n 1)")
        [ "$SUB_PORT" != "0" ] && sp_def="$SUB_PORT"
        echo -ne "  ${cyan}HTTP 端口 [${sp_def}]: ${re}"; read sp_in
        [ -n "$sp_in" ] && is_port "$sp_in" && SUB_PORT="$sp_in" || SUB_PORT="${sp_def}"
        echo -e "  → ${green}http://IP:${SUB_PORT}/TOKEN${re}"
    fi
    echo ""

    echo -e " ${white}━━━ ⑧ 额外协议（可选）━━━${re}"
    select_protocols || { yellow_msg "安装已取消。"; return; }
    save_conf; do_install
}

#==============================================================================
# 安装
#==============================================================================
do_install() {
    load_conf; clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}   ${white}ArgoV · 部署中...${re}                    ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

    yellow_msg "[1/6] 清理..."
    systemctl stop xray argov-tunnel 2>/dev/null; pkill -9 nginx 2>/dev/null; systemctl stop nginx 2>/dev/null; systemctl disable nginx 2>/dev/null; green_msg "  完成"

    yellow_msg "[2/6] 依赖..."
    if command -v apt &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof openssl
    elif command -v yum &>/dev/null; then yum install -y -q jq unzip curl lsof openssl
    elif command -v dnf &>/dev/null; then dnf install -y -q jq unzip curl lsof openssl
    elif command -v apk &>/dev/null; then apk update -q && apk add -q jq unzip curl lsof openssl; fi; green_msg "  完成"

    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG CF_ARCH; ARCH_ARG=$(detect_arch); CF_ARCH=$(cf_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/6] 下载..."
    curl -sLfo "${WORK_DIR}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLfo "${WORK_DIR}/argo.tmp" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    [ -s "${WORK_DIR}/argo.tmp" ] && mv -f "${WORK_DIR}/argo.tmp" "${WORK_DIR}/argo"
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR">/dev/null 2>&1; chmod +x "${WORK_DIR}/xray" "${WORK_DIR}/argo"; rm -f "${WORK_DIR}/xray.zip"
    install_qrencode; green_msg "  完成"

    yellow_msg "[4/6] 端口检测..."
    # 防御：确保 Argo 三端口不同
    is_port "$ARGO_PORT" || ARGO_PORT=8080
    is_port "$VLESS_WS_PORT" || VLESS_WS_PORT=8081
    is_port "$VMESS_WS_PORT" || VMESS_WS_PORT=8082
    [ "$VLESS_WS_PORT" -eq "$ARGO_PORT" ] && VLESS_WS_PORT=$((ARGO_PORT+1))
    [ "$VMESS_WS_PORT" -eq "$ARGO_PORT" ] || [ "$VMESS_WS_PORT" -eq "$VLESS_WS_PORT" ] && VMESS_WS_PORT=$((ARGO_PORT+2))
    port_in_use "$ARGO_PORT" && ARGO_PORT=$(find_free_port "$ARGO_PORT")
    port_in_use "$VLESS_WS_PORT" && VLESS_WS_PORT=$(find_free_port "$VLESS_WS_PORT")
    port_in_use "$VMESS_WS_PORT" && VMESS_WS_PORT=$(find_free_port "$VMESS_WS_PORT")
    if [ "$ENABLE_REALITY" = 1 ]; then
        [ "$REALITY_PORT" = "0" ] && REALITY_PORT=$(shuf -i 10000-60000 -n 1)
        port_in_use "$REALITY_PORT" && REALITY_PORT=$(find_free_port "$REALITY_PORT")
        { [ -z "$REALITY_PRIV" ] || [ "$REALITY_PRIV" = "REPLACE_ME" ]; } && gen_reality_keys
        [ -z "$REALITY_SHORTID" ] && gen_reality_shortid
    fi
    if [ "$ENABLE_HY2" = 1 ]; then
        [ "$HY2_PORT" = "0" ] && HY2_PORT=$(shuf -i 10000-60000 -n 1)
        port_in_use "$HY2_PORT" && HY2_PORT=$(find_free_port "$HY2_PORT")
        gen_hy2_cert || { red_msg "Hy2 证书生成失败，请确认 openssl 可用。"; exit 1; }
    fi
    if [ "$ENABLE_SS" = 1 ]; then [ "$SS_PORT" = "0" ] && SS_PORT=$(shuf -i 10000-60000 -n 1); port_in_use "$SS_PORT" && SS_PORT=$(find_free_port "$SS_PORT"); fi

    local UUID
    if [ -f "$CONFIG_FILE" ]; then
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id//empty' "$CONFIG_FILE" 2>/dev/null)
    fi
    [ -z "$UUID" ] && UUID="${UUID_CUSTOM:-$(cat /proc/sys/kernel/random/uuid)}"
    UUID_CUSTOM="$UUID"
    ensure_users_file
    local SS_PASS
    [[ "$SS_METHOD" =~ 2022 ]] && SS_PASS=$(gen_ss2022_pass "$SS_METHOD") || SS_PASS="$UUID"
    [ -z "$SS_PASS" ] && SS_PASS="$UUID"
    green_msg "  完成"

    yellow_msg "[5/6] 生成配置..."
    # 重装时保留已有 SS/Reality inbound（解耦 Argo 和可选协议）
    local saved_inbounds=""
    if [ -f "$CONFIG_FILE" ]; then
        saved_inbounds=$(jq -c '[.inbounds[] | select(.tag=="reality" or .tag=="ss" or .tag=="hy2")]' "$CONFIG_FILE" 2>/dev/null)
        [ "$saved_inbounds" = "[]" ] && saved_inbounds=""
    fi
    # 重装时关掉可选协议（下面会从保存的 merge 回来，避免重复）
    [ -n "$saved_inbounds" ] && { ENABLE_REALITY=0; ENABLE_HY2=0; ENABLE_SS=0; }
    build_xray_config "$UUID" "$SS_PASS"
    # 合并回已保存的 inbound
    if [ -n "$saved_inbounds" ]; then
        jq --argjson saved "$saved_inbounds" '.inbounds += $saved' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        # 强制同步 UUID 和升级老旧配置（如补齐 quic 嗅探），彻底修复老版本遗留的脱节问题
        jq --arg u "$UUID" --arg sp "$SS_PASS" \
           '(try (.inbounds[] | select(.tag=="reality") | .settings.clients[0].id) catch empty) = $u | 
            (try (.inbounds[] | select(.tag=="ss") | .settings.password) catch empty) = $sp | 
            (try (.inbounds[] | select(.tag=="reality") | .sniffing.destOverride) catch empty) = ["http","tls","quic"]' \
           "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="reality")' &>/dev/null && ENABLE_REALITY=1
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="hy2")'      &>/dev/null && ENABLE_HY2=1
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="ss")'       &>/dev/null && ENABLE_SS=1
    fi
    sync_xray_users
    green_msg "  完成"

    yellow_msg "[6/6] 启动..."
    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/xray << EOF
#!/sbin/openrc-run
name=xray
command=${WORK_DIR}/xray
command_args="-c ${CONFIG_FILE}"
command_background=true
pidfile=/var/run/xray.pid
EOF
        chmod +x /etc/init.d/xray
    else
        cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
Type=simple
ExecStart=${WORK_DIR}/xray -c ${CONFIG_FILE}
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    fi
    rebuild_tunnel "$ARGO_MODE"; rm -f "$TUNNEL_LOG"; systemctl daemon-reload
    systemctl enable xray argov-tunnel 2>/dev/null; systemctl restart xray argov-tunnel; sleep 5; green_msg "  完成"

    cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
T=$(mktemp /tmp/argov.XXXXXX)
curl -sLfo "$T" https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh
bash "$T"; rm -f "$T"
ARGOWRAP
    chmod +x "$SCRIPT_PATH"; save_conf

    local hd ip; [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN" || hd=$(get_argo_domain)
    [ -z "$hd" ] && [ "$ARGO_MODE" != "fixed-token" ] && { sleep 3; hd=$(get_argo_domain); }
    [ -n "$hd" ] && LAST_ARGO_DOMAIN="$hd" && save_conf; ip=$(get_ip)
    # 恢复 relay / WARP (重装后重建 outbound + routing)
    [ "$RELAY_ENABLED" = "1" ] && relay_apply "restore"
    [ -f "$WARP_DOMAIN_FILE" ] && [ -s "$WARP_DOMAIN_FILE" ] && warp_apply_routing "restore"

    start_sub_server
    start_stats_service

    echo ""; echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}🎉 部署成功 · ${NODE_NAME}${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""; echo -e "  ${cyan}管理${re}: ${green}ag${re}    ${cyan}名称${re}: ${white}${NODE_NAME}${re}    ${cyan}UUID${re}: ${purple}${UUID}${re}"; echo ""

    if [ -n "$hd" ]; then
        echo -e "  ${white}── Argo (无需开放端口) ──${re}\n"
        echo -e "  ${yellow}VLESS${re} ${green}$(gen_vless_link "$UUID" "$hd" "$CDN_DOMAIN" "$CDN_PORT")${re}\n"
        echo -e "  ${yellow}VMess${re} ${green}$(gen_vmess_link "$UUID" "$hd" "$CDN_DOMAIN" "$CDN_PORT")${re}\n"
        local su=""; [ -n "$SUB_PORT" ] && [ "$SUB_PORT" != "0" ] && [ -n "$ip" ] && su="$(get_sub_url "$ip")"
        show_qr "${su:-$(gen_vless_link "$UUID" "$hd" "$CDN_DOMAIN" "$CDN_PORT")}"
    fi
    if [ "$ENABLE_REALITY" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Reality (端口 ${REALITY_PORT}) ──${re}\n"
        echo -e "  ${green}$(gen_reality_link "$UUID" "$ip" "$REALITY_PORT" "$REALITY_SNI" "$REALITY_PUB" "$REALITY_SHORTID")${re}\n"
    fi
    if [ "$ENABLE_SS" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Shadowsocks (端口 ${SS_PORT}) ──${re}\n"
        echo -e "  ${green}$(gen_ss_link "$SS_METHOD" "$SS_PASS" "$ip" "$SS_PORT" "${NODE_NAME}-SS")${re}\n"
    fi
    if [ -n "$ip" ] && [ "$SUB_PORT" != "0" ] && [ -n "$SUB_PATH" ]; then
        echo -e "  ${cyan}📡 订阅${re}: ${green}$(get_sub_url "$ip")${re}"
        echo -e "  ${yellow}💡${re} 客户端填入订阅URL → 更新 → 所有协议自动导入"
    fi
    echo -e "  ${yellow}📋${re} ag       ${yellow}💡${re} 复制链接 → 客户端导入"
}

#==============================================================================
# 构建 config.json
#==============================================================================
build_xray_config() {
    local uuid="$1" ss_pass="$2" inbounds fallbacks
    inbounds='['
    fallbacks='{"path":"/vmess-argo","dest":'"${VMESS_WS_PORT}"'},{"path":"/vless-argo","dest":'"${VLESS_WS_PORT}"'},{"dest":'"${VLESS_WS_PORT}"'}'

    # 1. Argo 路由入口
    inbounds+='{"port":'"${ARGO_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"argo-in","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision","email":"argov-default"}],"decryption":"none","fallbacks":['"${fallbacks}"']},"streamSettings":{"network":"tcp"}}'
    # 2. VLESS WS
    inbounds+=',{"port":'"${VLESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"vless-ws","settings":{"clients":[{"id":"'"${uuid}"'","email":"argov-default"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}}}'
    # 3. VMess WS
    inbounds+=',{"port":'"${VMESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vmess","tag":"vmess-ws","settings":{"clients":[{"id":"'"${uuid}"'","alterId":0,"email":"argov-default"}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-argo"}}}'
    # 4. Reality (opt)
    [ "$ENABLE_REALITY" = 1 ] && inbounds+=',{"port":'"${REALITY_PORT}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision","email":"argov-default"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${REALITY_SNI}"':443","serverNames":["'"${REALITY_SNI}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":["'"${REALITY_SHORTID}"'"],"fingerprint":"chrome"}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
    # 5. Hysteria2 (opt)
    [ "$ENABLE_HY2" = 1 ] && inbounds+=',{"port":'"${HY2_PORT}"',"listen":"0.0.0.0","protocol":"hysteria","tag":"hy2","settings":{"version":2,"users":[{"auth":"'"${uuid}"'","level":0,"email":"argov-default"}]},"streamSettings":{"network":"hysteria","security":"tls","tlsSettings":{"alpn":["h3"],"serverName":"'"${HY2_SNI}"'","certificates":[{"certificateFile":"'"${HY2_CERT_FILE}"'","keyFile":"'"${HY2_KEY_FILE}"'"}]},"hysteriaSettings":{"version":2,"udpIdleTimeout":"60s"}}}'
    # 6. SS (opt)
    [ "$ENABLE_SS" = 1 ] && inbounds+=',{"port":'"${SS_PORT}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"}}'
    inbounds+=']'

    cat > "$CONFIG_FILE" << XRAYCONF
{
  "current_cdn": "${CDN_DOMAIN}",
  "current_cdn_port": ${CDN_PORT},
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": ${inbounds},
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }],
  "api":{"tag":"api","services":["StatsService"]},
  "stats":{},
  "policy":{"levels":{"0":{"statsUserUplink":true,"statsUserDownlink":true}},"system":{"statsInboundUplink":true,"statsInboundDownlink":true,"statsOutboundUplink":true,"statsOutboundDownlink":true}},
  "routing":{"rules":[{"type":"field","inboundTag":["api-in"],"outboundTag":"api"}]}
}
XRAYCONF
    jq '.inbounds += [{"listen":"127.0.0.1","port":10085,"protocol":"dokodemo-door","tag":"api-in","settings":{"address":"127.0.0.1"}}]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

#==============================================================================
# 管理节点 (添加/编辑/删除)
#==============================================================================
edit_hy2_protocol() {
    local uuid ip cur_port cur_sni new_port new_sni
    uuid=$(get_uuid)
    ip=$(get_ip)
    cur_port=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
    cur_sni=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CONFIG_FILE" 2>/dev/null)
    new_port="$cur_port"
    new_sni="$cur_sni"

    clear
    echo ""; echo -e " ${purple}┌────────────────────────────────────────┐${re}"
    echo -e " ${purple}│${re}     ${white}编辑 Hysteria2${re}"
    echo -e " ${purple}└────────────────────────────────────────┘${re}"
    echo ""
    echo -e " ${white}── SNI ──${re}"
    echo -e "  ${yellow}当前: ${cyan}${cur_sni}${re}"
    read -p "  新 SNI [回车保持]: " hs
    [ -n "$hs" ] && new_sni="$hs"
    echo -e "  → ${green}${new_sni}${re}\n"

    echo -e " ${white}── 端口 ──${re}"
    echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网端口"
    read -p "  新端口 [回车保持]: " hp
    if [ -n "$hp" ]; then
        if is_port "$hp" && ! port_in_use "$hp"; then
            new_port="$hp"
        else
            red_msg "端口无效或已占用，保持原端口"
        fi
    fi
    echo -e "  → ${green}${new_port}${re}\n"

    echo -e " ${white}确认修改:${re}"
    echo -e "  SNI: ${cyan}${cur_sni}${re} → ${green}${new_sni}${re}"
    echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"
    echo ""
    echo -ne "  ${yellow}确认? (y/n) [y]: ${re}"
    read cf
    [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }

    jq --arg sni "$new_sni" --argjson pt "$new_port" \
       '(.inbounds[]|select(.tag=="hy2")|.port)=$pt|(.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName)=$sni' \
       "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    HY2_PORT="$new_port"
    HY2_SNI="$new_sni"
    save_conf
    yellow_msg "重启 Xray..."
    systemctl restart xray 2>/dev/null
    rc-service xray restart 2>/dev/null || true
    sleep 2
    get_status
    green_msg "完成"
    [ -n "$ip" ] && echo -e "  ${green}$(gen_hy2_link "$uuid" "$ip" "$new_port" "$new_sni" "${NODE_NAME}-Hy2")${re}"
    echo ""; read -p "  按回车继续..." -r
}

manage_protocols() {
    load_conf
    [ ! -f "$CONFIG_FILE" ] && { red_msg "请先安装！"; return; }

    local has_reality=0 has_ss=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1

    while true; do
        clear
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}         ${white}管理节点${re}                          ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""

        # Argo 隧道节点（始终存在）
        local vl_port vm_port ar_port
        vl_port=$(jq -r '.inbounds[]|select(.tag=="vless-ws")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        vm_port=$(jq -r '.inbounds[]|select(.tag=="vmess-ws")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        ar_port=$(jq -r '.inbounds[]|select(.tag=="argo-in")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── Argo 隧道 ──${re}"
        echo ""
        echo -e "  ${green}e1${re}. VLESS + Argo    端口 ${cyan}${vl_port}${re}  路径 ${cyan}/vless-argo${re}"
        echo -e "  ${green}e2${re}. VMess + Argo    端口 ${cyan}${vm_port}${re}  路径 ${cyan}/vmess-argo${re}"
        echo ""

        # 可选协议
        [ "$has_reality" = 1 ] || [ "$has_ss" = 1 ] && echo -e "  ${white}── 可选协议 · 可编辑 ──${re}" && echo ""
        local er=1 es=1  # e1/e2 are taken by Argo, start at e3
        if [ "$has_reality" = 1 ]; then
            local rp rs; rp=$(jq -r '.inbounds[]|select(.tag=="reality")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            rs=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]//empty' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}e3${re}. VLESS Reality    ${cyan}${rs}${re}  端口 ${cyan}${rp}${re}"
        fi
        if [ "$has_ss" = 1 ]; then
            local sp sm; sp=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            sm=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
            local en; [ "$has_reality" = 1 ] && en="e4" || en="e3"
            echo -e "  ${green}${en}${re}. Shadowsocks       ${cyan}${sm}${re}  端口 ${cyan}${sp}${re}"
        fi

        # 可添加
        [ "$has_reality" = 0 ] || [ "$has_ss" = 0 ] && echo "" && echo -e "  ${white}── 可添加 ──${re}" && echo ""
        local aa=0
        if [ "$has_reality" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. VLESS Reality"; fi
        if [ "$has_ss" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. Shadowsocks"; fi

        # 自定义节点
        echo ""; echo -e "  ${white}── 自定义节点 (自添加) ──${re}"; echo ""
        local custom_count=0
        [ -f "${WORK_DIR}/custom_links.txt" ] && custom_count=$(grep -c '[^[:space:]]' "${WORK_DIR}/custom_links.txt" 2>/dev/null || echo 0)
        [ -z "$custom_count" ] && custom_count=0
        echo -e "  已有 ${cyan}${custom_count}${re} 个自定义链接"
        echo ""
        echo -e "  ${cyan}c1${re}. 添加自定义链接    ${cyan}c2${re}. 查看/删除自定义链接"
        echo ""
        echo -e "  ${purple}💡 Hysteria2 节点搭建建议${re}"
        echo -e "  鉴于 Xray 内核对 Hy2 支持尚不完善 (sing-box 适配更佳)，推荐使用以下专属脚本搭建。"
        echo -e "  搭建后，将节点链接使用上方 ${cyan}c1${re} 选项贴入，即可实现订阅聚合下发！"
        echo -e "  ${white}安装命令: ${green}bash <(curl -fsSL https://git.io/hysteria.sh)${re}"

        [ "$has_reality" = 1 ] || [ "$has_ss" = 1 ] && echo "" && echo -e "  ${red}d${re}. 删除可选节点"
        echo ""; echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请输入: " ac; [ "$ac" = "0" ] && return

        case "$ac" in
            e1) edit_protocol "vless-ws" "VLESS + Argo" ;;
            e2) edit_protocol "vmess-ws" "VMess + Argo" ;;
            e3) if [ "$has_reality" = 1 ]; then edit_protocol "reality" "VLESS Reality"
                elif [ "$has_ss" = 1 ]; then edit_protocol "ss" "Shadowsocks"; fi ;;
            e4) [ "$has_ss" = 1 ] && [ "$has_reality" = 1 ] && edit_protocol "ss" "Shadowsocks" ;;
            a1) if [ "$has_reality" = 0 ]; then add_single_protocol "reality"
                elif [ "$has_ss" = 0 ]; then add_single_protocol "ss"; fi ;;
            a2) [ "$has_ss" = 0 ] && [ "$has_reality" = 0 ] && add_single_protocol "ss" ;;
            c1) add_custom_link ;;
            c2) view_delete_custom_links ;;
            d|D) delete_protocol ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac

        load_conf
        has_reality=0; has_ss=0
        grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
        grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
    done
}

edit_protocol() {
    local tag="$1" label="$2" uuid; uuid=$(get_uuid)
    local cur_port cur_method cur_pass cur_sni cur_path rk=""

    case "$tag" in
        vless-ws|vmess-ws)
            cur_port=$(jq -r '.inbounds[]|select(.tag=="'"${tag}"'")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            cur_path=$(jq -r '.inbounds[]|select(.tag=="'"${tag}"'")|.streamSettings.wsSettings.path//empty' "$CONFIG_FILE" 2>/dev/null)
            clear
            echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
            echo -e " ${purple}║${re}     ${white}编辑 ${label}${re}"
            echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

            echo -e " ${white}━━━ ① 内部端口 ━━━${re}"
            echo -e "  ${yellow}仅 127.0.0.1，通过 Argo 隧道。当前: ${cyan}${cur_port}${re}"
            read -p "  新端口 [回车保持]: " np; local new_port="${np:-$cur_port}"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ② WS 路径 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}${cur_path}${re}"
            read -p "  新路径 [回车保持]: " npt; local new_path="${npt:-$cur_path}"
            echo -e "  → ${green}${new_path}${re}\n"

            echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
            echo -e " ${white}确认：${re}  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"
            echo -e "  路径: ${cyan}${cur_path}${re} → ${green}${new_path}${re}"
            echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"; echo ""
            echo -ne "  ${yellow}确认? (y/n) [y]: ${re}"; read cf
            [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }

            jq --argjson pt "$new_port" --arg p "$new_path" \
               '(.inbounds[]|select(.tag=="'"${tag}"'")|.port)=$pt|(.inbounds[]|select(.tag=="'"${tag}"'")|.streamSettings.wsSettings.path)=$p' \
               "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            # 同步更新 fallback 路由中的 dest 和 path
            local fb_path_old fb_path_new fb_tag
            [ "$tag" = "vless-ws" ] && fb_tag="vless-argo" || fb_tag="vmess-argo"
            fb_path_old="/${fb_tag}"; fb_path_new="$new_path"
            jq --arg oldp "$fb_path_old" --arg newp "$fb_path_new" --argjson d "$new_port" \
               '(.inbounds[]|select(.tag=="argo-in")|.settings.fallbacks)|=map(if .path==$oldp then {path:$newp,dest:$d} else . end)' \
               "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            [ "$tag" = "vless-ws" ] && VLESS_WS_PORT="$new_port" || VMESS_WS_PORT="$new_port"
            save_conf; yellow_msg "重启 Xray..."; systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "完成"
            echo ""; read -p "  按回车继续..." -r
            return ;;
        reality)
            cur_port=$(jq -r '.inbounds[]|select(.tag=="reality")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            cur_sni=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]//empty' "$CONFIG_FILE" 2>/dev/null)
            REALITY_SNI="$cur_sni" ;;
        hy2)
            cur_port=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            cur_sni=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CONFIG_FILE" 2>/dev/null)
            HY2_SNI="$cur_sni" ;;
        ss)
            cur_port=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            cur_method=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
            cur_pass=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.password//empty' "$CONFIG_FILE" 2>/dev/null)
            SS_METHOD="$cur_method" ;;
    esac

    clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}     ${white}编辑 ${label}${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

    local new_port="$cur_port" new_method="$cur_method" new_pass="$cur_pass" new_sni="$cur_sni" new_fp=""

    case "$tag" in
        ss)
            echo -e " ${white}━━━ ① 加密 ━━━${re}"
            for i in "${!SS_METHODS[@]}"; do local mk=" "; [ "${SS_METHODS[$i]}" = "$new_method" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${SS_METHODS[$i]}"; done
            echo ""; echo -e "  ${yellow}当前: ${cyan}${new_method}${re}"; read -p "  新加密 [回车保持]: " sm
            if [ -n "$sm" ]; then local si=$((sm-1)); [ "$si" -ge 0 ] 2>/dev/null && [ "$si" -lt "${#SS_METHODS[@]}" ] && new_method="${SS_METHODS[$si]}"; fi
            echo -e "  → ${green}${new_method}${re}\n"

            echo -e " ${white}━━━ ② 密码 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}$(echo "$cur_pass" | cut -c1-24)...${re}"; echo -e "  ${yellow}回车保持。输入 new 自动生成。${re}"
            read -p "  新密码 [回车保持]: " np
            if [ "$np" = "new" ] || [ "$np" = "NEW" ]; then
                [[ "$new_method" =~ 2022 ]] && new_pass=$(gen_ss2022_pass "$new_method") || new_pass=$(cat /proc/sys/kernel/random/uuid)
            elif [ -n "$np" ]; then new_pass="$np"; fi
            echo -e "  → ${green}$(echo "$new_pass" | cut -c1-24)...${re}\n"

            echo -e " ${white}━━━ ③ 端口 ━━━${re}"; echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网端口"; read -p "  新端口 [回车保持]: " np2
            [ -n "$np2" ] && ! port_in_use "$np2" && new_port="$np2"; [ -n "$np2" ] && port_in_use "$np2" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ④ 网络 ━━━${re}"
            local cur_net; cur_net=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.network//"tcp,udp"' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}1${re}. tcp,udp  ${green}2${re}. tcp  ${green}3${re}. udp"
            echo -e "  ${yellow}当前: ${cyan}${cur_net}${re}"; read -p "  选择 [回车保持]: " nn
            case "${nn:-0}" in 1) cur_net="tcp,udp" ;; 2) cur_net="tcp" ;; 3) cur_net="udp" ;; esac
            local new_net="$cur_net"
            echo -e "  → ${green}${new_net}${re}\n"
            ;;
        reality)
            echo -e " ${white}━━━ ① 伪装域名 ━━━${re}"
            for i in "${!REALITY_SNIS[@]}"; do local mk=" "; [ "${REALITY_SNIS[$i]}" = "$new_sni" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${REALITY_SNIS[$i]}"; done
            echo -e "  ${cyan}c${re}. 自定义"
            echo ""; echo -e "  ${yellow}当前: ${cyan}${new_sni}${re}"; read -p "  新 SNI [回车保持]: " rs
            if [ "$rs" = "c" ] || [ "$rs" = "C" ]; then
                read -p "  输入 SNI: " new_sni; [ -z "$new_sni" ] && new_sni="$cur_sni"
            elif [ -n "$rs" ]; then local ri=$((rs-1)); [ "$ri" -ge 0 ] 2>/dev/null && [ "$ri" -lt "${#REALITY_SNIS[@]}" ] && new_sni="${REALITY_SNIS[$ri]}"; fi
            echo -e "  → ${green}${new_sni}${re}\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"; echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网端口"; read -p "  新端口 [回车保持]: " np2
            [ -n "$np2" ] && ! port_in_use "$np2" && new_port="$np2"; [ -n "$np2" ] && port_in_use "$np2" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ③ x25519 密钥 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.privateKey//empty' "$CONFIG_FILE" 2>/dev/null | cut -c1-24)...${re}"
            echo -e "  ${yellow}输入 new 重新生成。${re}"; read -p "  [回车保持]: " rk
            [ "$rk" = "new" ] || [ "$rk" = "NEW" ] && { gen_reality_keys; echo -e "  → ${green}新密钥已生成${re}"; }; echo ""

            echo -e " ${white}━━━ ④ ShortId ━━━${re}"
            local cur_sid; cur_sid=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds[0]//empty' "$CONFIG_FILE" 2>/dev/null)
            [ -z "$cur_sid" ] && cur_sid="(空)"
            echo -e "  ${yellow}当前: ${cyan}${cur_sid}${re}"
            echo -e "  ${yellow}回车保持。输入 new 随机生成。${re}"
            read -p "  新 ShortId [回车保持]: " nsid
            if [ "$nsid" = "new" ] || [ "$nsid" = "NEW" ]; then
                gen_reality_shortid
                echo -e "  → ${green}${REALITY_SHORTID}${re}"
            elif [ -n "$nsid" ]; then
                REALITY_SHORTID="$nsid"
                echo -e "  → ${green}${REALITY_SHORTID}${re}"
            fi; echo ""

            echo -e " ${white}━━━ ⑤ 指纹 (Fingerprint) ━━━${re}"
            local cur_fp; cur_fp=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.fingerprint//"chrome"' "$CONFIG_FILE" 2>/dev/null)
            local fps=("chrome" "firefox" "safari" "edge" "random")
            for i in "${!fps[@]}"; do local mk=" "; [ "${fps[$i]}" = "$cur_fp" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${fps[$i]}"; done
            echo ""; echo -e "  ${yellow}当前: ${cyan}${cur_fp}${re}"; read -p "  新指纹 [回车保持]: " fp
            [ -n "$fp" ] && { local fi=$((fp-1)); [ "$fi" -ge 0 ] 2>/dev/null && [ "$fi" -lt "${#fps[@]}" ] && cur_fp="${fps[$fi]}"; }; new_fp="$cur_fp"
            echo -e "  → ${green}${new_fp}${re}\n"
            ;;
    esac

    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"; echo -e " ${white}确认修改：${re}"
    case "$tag" in
        ss) echo -e "  加密: ${cyan}${cur_method}${re} → ${green}${new_method}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$new_pass" != "$cur_pass" ] && echo -e "  密码: ${cyan}已更新${re}"; echo -e "  网络: ${green}${new_net}${re}" ;;
        reality) echo -e "  SNI: ${cyan}${cur_sni}${re} → ${green}${new_sni}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$nsid" = "new" ] || [ "$nsid" = "NEW" ] || [ -n "$nsid" ] && echo -e "  ShortId: ${cyan}已更新 → ${green}${REALITY_SHORTID}${re}"; echo -e "  指纹: ${green}${new_fp}${re}" ;;
    esac
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"; echo ""
    echo -ne "  ${yellow}确认? (y/n) [y]: ${re}"; read cf; [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }

    case "$tag" in
        ss)
            jq --arg m "$new_method" --arg p "$new_pass" --argjson pt "$new_port" --arg n "$new_net" \
               '(.inbounds[]|select(.protocol=="shadowsocks")|.settings.method)=$m|(.inbounds[]|select(.protocol=="shadowsocks")|.settings.password)=$p|(.inbounds[]|select(.protocol=="shadowsocks")|.port)=$pt|(.inbounds[]|select(.protocol=="shadowsocks")|.settings.network)=$n|(.inbounds[]|select(.protocol=="shadowsocks")|.tag)="ss"' \
               "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            SS_METHOD="$new_method"; SS_PORT="$new_port" ;;
        reality)
            jq --arg sni "$new_sni" --argjson pt "$new_port" \
               '(.inbounds[]|select(.tag=="reality")|.port)=$pt|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.dest)=($sni+":443")|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames)=[$sni,""]' \
               "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            REALITY_PORT="$new_port"; REALITY_SNI="$new_sni"
            if [ "$rk" = "new" ] || [ "$rk" = "NEW" ]; then
                jq --arg priv "$REALITY_PRIV" --arg pub "$REALITY_PUB" \
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.privateKey)=$priv|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey)=$pub' \
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
            if [ "$nsid" = "new" ] || [ "$nsid" = "NEW" ] || [ -n "$nsid" ]; then
                local sid_val; [ -n "$REALITY_SHORTID" ] && sid_val="\"$REALITY_SHORTID\"" || sid_val="\"\""
                jq --argjson s "[${sid_val}]" \
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds)=$s' \
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
            if [ -n "$new_fp" ]; then
                jq --arg fp "$new_fp" \
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.fingerprint)=$fp' \
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi ;;
    esac
    save_conf; yellow_msg "重启 Xray..."; systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "完成"

    echo ""; echo -e " ${white}━━━ 更新后链接 ━━━${re}"; echo ""
    local ip hd cd cp; ip=$(get_ip); hd=$(get_argo_domain); cd=$(get_cdn); cp=$(get_cdn_port)
    [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"
    case "$tag" in
        ss) [ -n "$ip" ] && echo -e "  ${green}$(gen_ss_link "$new_method" "$new_pass" "$ip" "$new_port" "${NODE_NAME}-SS")${re}" ;;
        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$new_port" "$new_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;; 
    esac
    echo ""; read -p "  按回车继续..." -r
}

add_single_protocol() {
    local proto="$1" uuid; uuid=$(get_uuid)
    local sm="$SS_METHOD" sp="" s_port="" s_net="tcp,udp"
    local r_sni="$REALITY_SNI" r_port="" r_sid="" r_fp="chrome"

    [[ "$proto" != "ss" && "$proto" != "reality" ]] && { red_msg "未知协议"; return; }

    while true; do
    clear
    case "$proto" in
        ss)
            echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
            echo -e " ${purple}║${re}     ${white}添加 Shadowsocks${re}"
            echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

            echo -e " ${white}━━━ ① 加密方式 ━━━${re}"
            for i in "${!SS_METHODS[@]}"; do local mk=" "; [ "${SS_METHODS[$i]}" = "$sm" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${SS_METHODS[$i]}"; done
            echo ""; echo -e "  ${yellow}当前: ${cyan}${sm}${re}"; read -p "  选择 [回车保持]: " s
            local si=$(( ${s:-0} -1 ))
            [ "$si" -ge 0 ] 2>/dev/null && [ "$si" -lt "${#SS_METHODS[@]}" ] && sm="${SS_METHODS[$si]}"
            echo -e "  → ${green}${sm}${re}\n"

            echo -e " ${white}━━━ ② 密码 ━━━${re}"
            local dp; [[ "$sm" =~ 2022 ]] && dp=$(gen_ss2022_pass "$sm") || dp="$uuid"
            [ -z "$sp" ] && sp="$dp"
            echo -e "  ${yellow}当前: ${cyan}$(echo "$sp"|cut -c1-20)...${re}"
            echo -e "  ${yellow}回车保持。输入 new 自动生成。${re}"
            read -p "  密码 [回车保持]: " s
            if [ "$s" = "new" ] || [ "$s" = "NEW" ]; then
                [[ "$sm" =~ 2022 ]] && sp=$(gen_ss2022_pass "$sm") || sp=$(cat /proc/sys/kernel/random/uuid)
            elif [ -n "$s" ]; then sp="$s"; fi
            echo -e "  → ${green}$(echo "$sp"|cut -c1-24)...${re}\n"

            echo -e " ${white}━━━ ③ 端口 ━━━${re}"
            [ -z "$s_port" ] && { local dpt; dpt=$(find_free_port "${SS_PORT:-0}"); [ "$dpt" = "0" ] && dpt=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); s_port="$dpt"; }
            echo -e "  ${yellow}当前: ${cyan}${s_port}${re}"; read -p "  端口 [回车保持]: " s
            [ -n "$s" ] && ! port_in_use "$s" && s_port="$s"; [ -n "$s" ] && port_in_use "$s" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${s_port}${re}\n"

            echo -e " ${white}━━━ ④ 网络 ━━━${re}"
            echo -e "  ${green}1${re}. tcp,udp  ${green}2${re}. tcp  ${green}3${re}. udp"
            echo -e "  ${yellow}当前: ${cyan}${s_net}${re}"; read -p "  选择 [回车保持]: " s
            case "${s:-0}" in 1) s_net="tcp,udp" ;; 2) s_net="tcp" ;; 3) s_net="udp" ;; esac
            echo -e "  → ${green}${s_net}${re}\n"
            ;;

        reality)
            echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
            echo -e " ${purple}║${re}     ${white}添加 VLESS Reality${re}"
            echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

            echo -e " ${white}━━━ ① 伪装域名 (SNI) ━━━${re}"
            for i in "${!REALITY_SNIS[@]}"; do local mk=" "; [ "${REALITY_SNIS[$i]}" = "$r_sni" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${REALITY_SNIS[$i]}"; done
            echo -e "  ${cyan}c${re}. 自定义"; echo ""
            echo -e "  ${yellow}当前: ${cyan}${r_sni}${re}"; read -p "  选择 [回车保持]: " rs
            local ri=$(( ${rs:-0} -1 ))
            if [ "$rs" = "c" ] || [ "$rs" = "C" ]; then
                read -p "  输入 SNI: " r_sni; [ -z "$r_sni" ] && r_sni="www.amazon.com"
            elif [ "$ri" -ge 0 ] 2>/dev/null && [ "$ri" -lt "${#REALITY_SNIS[@]}" ]; then
                r_sni="${REALITY_SNIS[$ri]}"
            fi
            echo -e "  → ${green}${r_sni}${re}\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"
            [ -z "$r_port" ] && { r_port=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); }
            echo -e "  ${yellow}当前: ${cyan}${r_port}${re}"; read -p "  端口 [回车保持]: " s
            [ -n "$s" ] && ! port_in_use "$s" && r_port="$s"; [ -n "$s" ] && port_in_use "$s" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${r_port}${re}\n"

            echo -e " ${white}━━━ ③ ShortId ━━━${re}"
            [ -z "$r_sid" ] && { r_sid=$(openssl rand -hex 4 2>/dev/null || printf '%08x' $((RANDOM*RANDOM))); }
            echo -e "  ${yellow}8位十六进制，客户端需匹配。${re}"
            echo -e "  ${yellow}当前: ${cyan}${r_sid}${re}"; read -p "  ShortId [回车保持]: " s
            if [ "$s" = "new" ] || [ "$s" = "NEW" ]; then
                r_sid=$(openssl rand -hex 4 2>/dev/null || printf '%08x' $((RANDOM*RANDOM)))
            elif [ -n "$s" ]; then r_sid="$s"; fi
            echo -e "  → ${green}${r_sid}${re}\n"

            echo -e " ${white}━━━ ④ x25519 密钥对 ━━━${re}"
            if [ -z "$REALITY_PRIV" ] || [ "$REALITY_PRIV" = "REPLACE_ME" ]; then
                gen_reality_keys
            fi
            echo -e "  ${yellow}私钥: ${cyan}$(echo "${REALITY_PRIV}"|cut -c1-24)...${re}"
            echo -e "  ${yellow}公钥: ${cyan}$(echo "${REALITY_PUB}"|cut -c1-24)...${re}"
            echo -e "  ${yellow}回车保持。输入 new 重新生成。${re}"
            read -p "  [回车保持]: " s
            [ "$s" = "new" ] || [ "$s" = "NEW" ] && { gen_reality_keys; echo -e "  → ${green}新密钥已生成${re}"; }
            echo -e "  → ${green}$(echo "${REALITY_PUB}"|cut -c1-24)...${re}\n"

            echo -e " ${white}━━━ ⑤ 指纹 (Fingerprint) ━━━${re}"
            local fps=("chrome" "firefox" "safari" "edge" "random")
            for i in "${!fps[@]}"; do local mk=" "; [ "${fps[$i]}" = "$r_fp" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${fps[$i]}"; done
            echo ""; echo -e "  ${yellow}当前: ${cyan}${r_fp}${re}"; read -p "  选择 [回车保持]: " s
            local fi=$(( ${s:-0} -1 ))
            [ "$fi" -ge 0 ] 2>/dev/null && [ "$fi" -lt "${#fps[@]}" ] && r_fp="${fps[$fi]}"
            echo -e "  → ${green}${r_fp}${re}\n"

            echo -e " ${white}━━━ ⑥ 流控 (Flow) ━━━${re}"
            echo -e "  ${green}1${re}. xtls-rprx-vision"
            echo ""; echo -e "  ${yellow}当前: ${cyan}xtls-rprx-vision${re}"; read -p "  [回车保持]: " s
            echo -e "  → ${green}xtls-rprx-vision${re}\n"
            ;;
    esac

    # === 确认 ===
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e " ${white}确认配置：${re}"
    case "$proto" in
        ss)
            echo -e "  加密: ${green}${sm}${re}  端口: ${green}${s_port}${re}"
            echo -e "  网络: ${green}${s_net}${re}"
            ;;
        reality)
            echo -e "  SNI: ${green}${r_sni}${re}  端口: ${green}${r_port}${re}"
            echo -e "  ShortId: ${green}${r_sid}${re}"
            echo -e "  公钥: ${purple}$(echo "${REALITY_PUB}"|cut -c1-32)...${re}"
            echo -e "  指纹: ${green}${r_fp}${re}  Flow: ${green}xtls-rprx-vision${re}"
            ;;
    esac
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo ""; echo -ne "  ${yellow}确认添加? (y=确认 n=重新配置 q=取消) [y]: ${re}"; read cf
    case "${cf:-y}" in
        y|Y) break ;;
        n|N) continue ;;  # 重新配置
        *) yellow_msg "已取消。"; return ;;
    esac
    done

    # === 写入 JSON ===
    local new_inbound=""
    case "$proto" in
        ss)
            new_inbound='{"port":'"${s_port}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${sm}"'","password":"'"${sp}"'","network":"'"${s_net}"'"}}'
            SS_PORT="$s_port"; SS_METHOD="$sm"; ENABLE_SS=1 ;;
        reality)
            [ -z "$REALITY_PRIV" ] || [ "$REALITY_PRIV" = "REPLACE_ME" ] && gen_reality_keys
            REALITY_SHORTID="$r_sid"
            local sid_val="\"$REALITY_SHORTID\""
            new_inbound='{"port":'"${r_port}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision","email":"argov-default"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${r_sni}"':443","serverNames":["'"${r_sni}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":['"${sid_val}"'],"fingerprint":"'"${r_fp}"'"}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
            REALITY_PORT="$r_port"; REALITY_SNI="$r_sni"; ENABLE_REALITY=1 ;;
    esac
    jq --argjson i "$new_inbound" '.inbounds+=[$i]' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    sync_xray_users
    save_conf; yellow_msg "重启 Xray..."; systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "完成"

    echo ""; echo -e " ${white}━━━ 链接 ━━━${re}"; echo ""
    local ip; ip=$(get_ip)
    case "$proto" in
        ss) [ -n "$ip" ] && echo -e "  ${green}$(gen_ss_link "$sm" "$sp" "$ip" "$s_port" "${NODE_NAME}-SS")${re}" ;;
        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$r_port" "$r_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;;
    esac
    echo ""; read -p "  按回车返回..." -r
}

delete_protocol() {
    clear
    local has_reality=0 has_ss=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
    [ $((has_reality+has_ss)) = 0 ] && { echo ""; green_msg "无可删除。"; echo ""; read -p "  按回车返回..." -r; return; }

    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}         ${red}删除节点${re}                          ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""
    local dd=0
    [ "$has_reality" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. VLESS Reality"
    [ "$has_ss" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. Shadowsocks"
    echo -e "  ${cyan}0${re}. 返回"; echo -e " ${purple}────────────────────────────────────────${re}"
    read -p "  选择: " dc; [ "$dc" = "0" ] && return

    local del_tag=""
    [ "$dc" = "1" ] && [ "$has_reality" = 1 ] && del_tag="reality"
    [ "$dc" = "1" ] && [ "$has_reality" = 0 ] && [ "$has_ss" = 1 ] && del_tag="ss"
    [ "$dc" = "2" ] && [ "$has_ss" = 1 ] && del_tag="ss"
    [ -z "$del_tag" ] && { red_msg "无效。"; return; }

    echo ""; echo -ne "  ${red}⚠ 确认删除? (y/n): ${re}"; read cf; [ "$cf" != "y" ] && [ "$cf" != "Y" ] && { yellow_msg "已取消。"; return; }
    jq 'del(.inbounds[]|select(.tag=="'"${del_tag}"'"))' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    [ "$del_tag" = "reality" ] && ENABLE_REALITY=0
    [ "$del_tag" = "ss" ] && ENABLE_SS=0
    save_conf; systemctl restart xray 2>/dev/null; sleep 1; green_msg "已删除。"
    echo ""; read -p "  按回车返回..." -r
}

#==============================================================================
#==============================================================================
# 自定义节点链接（用户自行粘贴任意协议链接，加入订阅输出）
#==============================================================================
add_custom_link() {
    clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}     ${white}添加自定义节点链接${re}                  ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${yellow}粘贴任意协议节点链接，如 Hysteria2、Trojan、TUIC 等${re}"
    echo -e "  ${yellow}支持格式: hy2://, trojan://, vless://, vmess://, ss://, tuic:// 等${re}"
    echo -e "  ${yellow}链接会自动加入订阅 base64，每次更新订阅都能获取${re}"
    echo ""
    echo -e "  ${cyan}示例: hy2://password@1.2.3.4:443?sni=xxx.com&insecure=0#Name${re}"
    echo ""
    read -p "  链接: " link
    [ -z "$link" ] && { yellow_msg "已取消。"; sleep 1; return; }
    # 防粘连：每次只能粘贴一个链接
    local url_count; url_count=$(echo "$link" | grep -o '://' | wc -l)
    if [ "$url_count" -gt 1 ]; then
        red_msg "每次只能粘贴一个链接！检测到 ${url_count} 个链接，请分开粘贴。"
        sleep 2; return
    fi
    # 基础校验：必须以 protocol:// 开头
    if ! echo "$link" | grep -qE '^[a-z][a-z0-9+.-]*://'; then
        red_msg "无效链接格式，必须以 protocol:// 开头（如 hy2://, trojan:// 等）"
        sleep 2; return
    fi
    mkdir -p "$WORK_DIR" 2>/dev/null
    # 一次性迁移：旧版 sub_gen.sh 不含 custom_links 支持，调用 start_sub_server 更新
    if ! grep -qF 'custom_links.txt' "${WORK_DIR}/sub_gen.sh" 2>/dev/null; then
        yellow_msg "正在更新订阅脚本以支持自定义节点..."
        start_sub_server
    fi
    echo "$link" >> "${WORK_DIR}/custom_links.txt"
    green_msg "已添加！订阅将包含此节点。"
    bash "${WORK_DIR}/sub_gen.sh" 2>/dev/null &
    sleep 1
}

view_delete_custom_links() {
    while true; do
        [ ! -f "${WORK_DIR}/custom_links.txt" ] || [ ! -s "${WORK_DIR}/custom_links.txt" ] && { yellow_msg "暂无自定义链接。"; sleep 1; return; }
        clear
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}查看/删除自定义链接${re}                  ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""

        # 读取并显示
        local count=0
        local links=()
        while IFS= read -r line; do
            [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
            count=$((count+1))
            links+=("$line")
            local display="$line"
            [ ${#display} -gt 78 ] && display="${display:0:75}..."
            echo -e "  ${green}${count}${re}. ${cyan}${display}${re}"
        done < "${WORK_DIR}/custom_links.txt"

        [ "$count" = 0 ] && { yellow_msg "暂无有效链接。"; sleep 1; return; }

        echo ""
        echo -e "  ${red}d${re}. 删除指定序号    ${red}da${re}. 清空全部    ${cyan}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            0) return ;;
            d|D)
                read -p "  删除序号 (多个用逗号分隔，如 1,3): " nums
                [ -z "$nums" ] && { yellow_msg "已取消。"; continue; }
                IFS=',' read -ra indices <<< "$nums"
                # 重建文件
                local new_links=() idx=0
                while IFS= read -r line; do
                    [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
                    idx=$((idx+1))
                    local keep=1
                    for n in "${indices[@]}"; do
                        n=$(echo "$n" | xargs)
                        [ "$n" = "$idx" ] && { keep=0; break; }
                    done
                    [ "$keep" = 1 ] && new_links+=("$line")
                done < "${WORK_DIR}/custom_links.txt"
                printf '%s\n' "${new_links[@]}" > "${WORK_DIR}/custom_links.txt"
                green_msg "已删除。"; bash "${WORK_DIR}/sub_gen.sh" 2>/dev/null &
                sleep 1
                ;;
            da|DA)
                echo -ne "  ${red}⚠ 确认清空全部 ${count} 个链接? (y/n): ${re}"; read cf
                [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { > "${WORK_DIR}/custom_links.txt"; green_msg "已清空。"; bash "${WORK_DIR}/sub_gen.sh" 2>/dev/null & sleep 1; }
                ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

#==============================================================================
# 落地中继 (Relay) — Xray outbound 链式代理到干净落地 VPS
#==============================================================================
RELAY_DOMAIN_FILE="/etc/xray/relay_domains.txt"

echo_relay_status() {
    if [ "$RELAY_ENABLED" = "1" ] && [ -n "$RELAY_LINK" ]; then
        local proto addr; proto=$(echo "$RELAY_LINK" | sed -n 's|^\([a-z0-9+.-]*\)://.*|\1|p')
        addr=$(echo "$RELAY_LINK" | sed -n 's|.*://[^@]*@\([^:/?#]*\).*|\1|p')
        [ -z "$addr" ] && addr=$(echo "$RELAY_LINK" | sed -n 's|.*://\([^:/?#]*\).*|\1|p')
        echo -e "  ${green}● 已启用${re} → ${purple}${proto}${re} → ${cyan}${addr}${re}  模式: ${yellow}$([ "$RELAY_MODE" = "all" ] && echo "全部" || echo "分流")${re}"
    else
        echo -e "  ${yellow}○ 未启用${re}"
    fi
}

relay_menu() {
    load_conf
    while true; do
        clear
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}落地中继 (Landing Relay)${re}            ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo_relay_status
        if [ "$RELAY_MODE" = "split" ] && [ -f "$RELAY_DOMAIN_FILE" ]; then
            local dc; dc=$(grep -c '[^[:space:]]' "$RELAY_DOMAIN_FILE" 2>/dev/null || echo 0)
            echo -e "  ${cyan}分流域名: ${dc} 个${re}"
        fi
        echo ""
        echo -e "  ${green}r1${re}. 设置落地节点 (粘贴 ss:// / vless:// / trojan:// 链接)"
        echo -e "  ${green}r2${re}. 切换模式 (当前: $([ "$RELAY_MODE" = "all" ] && echo "全部" || echo "分流"))"
        if [ "$RELAY_MODE" = "split" ]; then
            echo -e "  ${green}r3${re}. 管理分流域名"
        fi
        echo -e "  ${green}r4${re}. 应用并重启 Xray"
        if [ "$RELAY_ENABLED" = "1" ]; then
            echo -e "  ${red}r5${re}. 关闭中继"
        fi
        echo ""; echo -e "  ${cyan}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            r1|R1)
                echo ""; echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo -e " ${white}📌 落地 VPS 部署指南${re}"
                echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo ""
                echo -e "  ${yellow}在落地 VPS 上运行以下命令，然后粘贴生成的链接:${re}"
                echo ""
                echo -e "  ${green}bash <(curl -Ls https://raw.githubusercontent.com/xOS/Shadowsocks-Rust/master/ss-rust.sh)${re}"
                echo ""
                echo -e "  ${yellow}⚠ 加密务必选: ${cyan}chacha20-ietf-poly1305${re}"
                echo -e "  ${yellow}⚠ 不要选 2022 系列 (Xray 不支持)${re}"
                echo ""
                echo -e "  ${cyan}也支持: vless://  vmess://  trojan://${re}"
                echo -e " ${purple}────────────────────────────────────────${re}"
                echo ""
                read -p "  粘贴链接: " link
                [ -z "$link" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                # 基础校验
                if ! echo "$link" | grep -qE '^(ss|vless|vmess|trojan)://'; then
                    red_msg "不支持的协议，仅支持 ss:// vless:// vmess:// trojan://"
                    sleep 2; continue
                fi
                RELAY_LINK="$link"; RELAY_ENABLED=0; save_conf
                green_msg "落地节点已保存！按 r4 应用生效。"
                sleep 1
                ;;
            r2|R2)
                if [ "$RELAY_MODE" = "all" ]; then
                    RELAY_MODE="split"; touch "$RELAY_DOMAIN_FILE" 2>/dev/null
                else
                    RELAY_MODE="all"
                fi
                save_conf; green_msg "模式: $([ "$RELAY_MODE" = "all" ] && echo "全部流量中继" || echo "分流模式")"
                if [ "$RELAY_ENABLED" = "1" ] && [ -n "$RELAY_LINK" ]; then
                    echo -ne "  ${yellow}立即应用新路由规则? (y/n) [y]: ${re}"; read cf
                    [ "$cf" != "n" ] && [ "$cf" != "N" ] && { RELAY_ENABLED=1; relay_apply; echo ""; read -p "  按回车返回..." -r; } || yellow_msg "已保存，别忘了按 r4 应用！"
                fi
                ;;
            r3|R3)
                if [ "$RELAY_MODE" != "split" ]; then red_msg "请先切换到分流模式"; sleep 1; continue; fi
                relay_manage_domains
                if [ "$RELAY_ENABLED" = "1" ] && [ -n "$RELAY_LINK" ]; then
                    echo -ne "  ${yellow}域名已更新，立即应用路由规则? (y/n) [y]: ${re}"; read cf
                    [ "$cf" != "n" ] && [ "$cf" != "N" ] && { RELAY_ENABLED=1; relay_apply; echo ""; read -p "  按回车返回..." -r; }
                fi
                ;;
            r4|R4)
                if [ -z "$RELAY_LINK" ]; then red_msg "请先设置落地节点 (r1)"; sleep 1; continue; fi
                RELAY_ENABLED=1; save_conf; relay_apply; echo ""; read -p "  按回车返回..." -r
                ;;
            r5|R5)
                [ "$RELAY_ENABLED" != "1" ] && { yellow_msg "中继未启用。"; sleep 1; continue; }
                echo -ne "  ${red}确认关闭? (y/n): ${re}"; read cf
                [ "$cf" != "y" ] && [ "$cf" != "Y" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                relay_clear; echo ""; read -p "  按回车返回..." -r
                ;;
            0) return ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

relay_manage_domains() {
    while true; do
        clear
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}管理中继分流域名${re}                  ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        if [ -f "$RELAY_DOMAIN_FILE" ] && [ -s "$RELAY_DOMAIN_FILE" ]; then
            nl -w2 -s'. ' "$RELAY_DOMAIN_FILE"
            echo ""; echo -e "  ${green}共 $(wc -l < "$RELAY_DOMAIN_FILE") 个域名${re}"
        else
            echo -e "  ${yellow}列表为空${re}"
        fi
        echo ""
        echo -e "  ${green}1${re}. 添加域名    ${red}2${re}. 删除序号    ${red}da${re}. 清空全部    ${cyan}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            1) echo ""; echo -e "  ${yellow}多个用逗号分隔:${re}"; read -p "  > " input
               [ -z "$input" ] && continue
               touch "$RELAY_DOMAIN_FILE"
               IFS=',' read -ra DOMS <<< "$input"
               for d in "${DOMS[@]}"; do
                   d=$(echo "$d" | xargs); [ -z "$d" ] && continue
                   grep -qxF "$d" "$RELAY_DOMAIN_FILE" || echo "$d" >> "$RELAY_DOMAIN_FILE"
               done
               green_msg "已更新。"; sleep 1
               ;;
            2) echo ""; echo -e "  ${yellow}输入要删除的序号，空格分隔 (如 5 6 8):${re}"
               read -p "  > " input
               [ -z "$input" ] && { yellow_msg "已取消。"; sleep 1; continue; }
               # 重建文件
               local new_doms=() idx=0
               while IFS= read -r line; do
                   [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
                   idx=$((idx+1))
                   local keep=1
                   for n in $input; do
                       [ "$n" = "$idx" ] && { keep=0; break; }
                   done
                   [ "$keep" = 1 ] && new_doms+=("$line")
               done < "$RELAY_DOMAIN_FILE"
               printf '%s\n' "${new_doms[@]}" > "$RELAY_DOMAIN_FILE"
               green_msg "已删除。"; sleep 1
               ;;
            da|DA) echo ""; echo -ne "  ${red}⚠ 清空全部? (y/n): ${re}"; read cf
               [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { > "$RELAY_DOMAIN_FILE"; green_msg "已清空。"; sleep 1; } ;;
            0) return ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

relay_apply() {
    local mode="${1:-apply}"  # apply | restore
    load_conf
    [ -z "$RELAY_LINK" ] && { red_msg "未设置落地节点。"; return 1; }

    # Python3 依赖检查
    if ! command -v python3 &>/dev/null; then
        yellow_msg "安装 Python3..."
        if [ "$IS_ALPINE" = 1 ]; then apk add --no-cache python3 2>/dev/null
        elif command -v apt &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 2>/dev/null
        elif command -v yum &>/dev/null; then yum install -y -q python3 2>/dev/null; fi
    fi
    ! command -v python3 &>/dev/null && { red_msg "Python3 不可用。"; return 1; }

    local domains_json='[]'
    if [ "$RELAY_MODE" = "split" ] && [ -f "$RELAY_DOMAIN_FILE" ] && [ -s "$RELAY_DOMAIN_FILE" ]; then
        domains_json=$(json_array_from_file "$RELAY_DOMAIN_FILE")
    fi

    [ "$mode" != "restore" ] && yellow_msg "正在应用落地中继..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    local py_err; py_err=$(mktemp /tmp/relay_err.XXXXXX)
    python3 2>"$py_err" << PYEOF
import json, base64, re, sys
from urllib.parse import parse_qs, unquote

CONFIG = '${CONFIG_FILE}'
RELAY_LINK = '${RELAY_LINK}'
RELAY_MODE = '${RELAY_MODE}'
DOMAINS = ${domains_json}

def decode_b64(s):
    """安全 base64 解码，补齐 padding"""
    s = s + '=' * (-len(s) % 4)
    s = s.replace('-', '+').replace('_', '/')
    return base64.b64decode(s).decode('utf-8', errors='replace')

# --- 解析链接 ---
proto = addr = port = ''
out = {}  # Xray outbound

if RELAY_LINK.startswith('ss://'):
    # 支持两种格式:
    #   SIP002: ss://base64(method:pass)@IP:PORT#Name
    #   Legacy:  ss://base64(method:pass@IP:PORT)#Name
    proto = 'shadowsocks'
    rest = RELAY_LINK[5:]
    # 去掉 fragment / query
    if '#' in rest:
        rest = rest.split('#')[0]
    if '?' in rest and '@' not in rest.split('?')[0]:
        rest = rest.split('?')[0]
    method = 'aes-256-gcm'; password = ''; addr = ''; port = 0
    if '@' in rest:
        # SIP002: userinfo@addr:port
        userinfo, addr_part = rest.split('@', 1)
        addr = addr_part.split(':')[0]
        p = re.search(r':(\d+)', addr_part)
        port = int(p.group(1)) if p else 443
        raw = decode_b64(userinfo)
        parts = raw.split(':', 1)
        method = parts[0] if parts[0] else method
        password = parts[1] if len(parts) > 1 else ''
    else:
        # Legacy: 整个字符串是一个 base64
        raw = decode_b64(rest)
        m2 = re.search(r'^([^:]+):(.+?)@([^:]+):(\d+)', raw)
        if m2:
            method, password, addr, port = m2.group(1), m2.group(2), m2.group(3), int(m2.group(4))
        else:
            raise ValueError(f'Cannot parse SS link format: {rest[:40]}...')
    out = {
        "tag": "relay-out",
        "protocol": "shadowsocks",
        "domainStrategy": "AsIs",
        "settings": {"servers": [{"address": addr, "port": port, "method": method, "password": password}]}
    }

elif RELAY_LINK.startswith('vless://'):
    proto = 'vless'
    # vless://UUID@IP:PORT?params#name
    m = re.search(r'vless://([^@]+)@([^:]+):(\d+)(\?.*?)?(#.*)?$', RELAY_LINK)
    if m:
        uuid = m.group(1)
        addr = m.group(2)
        port = int(m.group(3))
        qs = parse_qs(unquote(m.group(4) or ''))
        flow = qs.get('flow', [''])[0]
        security = qs.get('security', ['none'])[0]
        sni = qs.get('sni', [''])[0]
        pbk = qs.get('pbk', [''])[0]
        sid = qs.get('sid', [''])[0]
        fp = qs.get('fp', ['chrome'])[0]
        out = {
            "tag": "relay-out",
            "protocol": "vless",
            "domainStrategy": "AsIs",
            "settings": {
                "vnext": [{"address": addr, "port": port, "users": [{"id": uuid, "encryption": "none", "flow": flow}]}]
            }
        }
        if security == 'reality':
            out["streamSettings"] = {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "serverName": sni,
                    "publicKey": pbk,
                    "shortId": sid,
                    "fingerprint": fp
                }
            }
        elif security == 'tls' and sni:
            out["streamSettings"] = {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {"serverName": sni}
            }
    else:
        raise ValueError(f'Invalid vless link')

elif RELAY_LINK.startswith('vmess://'):
    proto = 'vmess'
    b64 = RELAY_LINK[8:]
    raw = decode_b64(b64)
    vm = json.loads(raw)
    addr = vm.get('add', '')
    port = int(vm.get('port', 443))
    uuid = vm.get('id', '')
    sni = vm.get('sni', addr)
    out = {
        "tag": "relay-out",
        "protocol": "vmess",
        "domainStrategy": "AsIs",
        "settings": {"vnext": [{"address": addr, "port": port, "users": [{"id": uuid, "alterId": 0}]}]}
    }
    if vm.get('tls') == 'tls':
        out["streamSettings"] = {"network": "ws", "security": "tls", "tlsSettings": {"serverName": sni}}

elif RELAY_LINK.startswith('trojan://'):
    proto = 'trojan'
    # trojan://PASSWORD@IP:PORT?params#name
    m = re.search(r'trojan://([^@]+)@([^:]+):(\d+)(\?.*?)?(#.*)?$', RELAY_LINK)
    if m:
        password = m.group(1)
        addr = m.group(2)
        port = int(m.group(3))
        qs = parse_qs(unquote(m.group(4) or ''))
        sni = qs.get('sni', [''])[0]
        out = {
            "tag": "relay-out",
            "protocol": "trojan",
            "domainStrategy": "AsIs",
            "settings": {"servers": [{"address": addr, "port": port, "password": password}]}
        }
        if sni:
            out["streamSettings"] = {"network": "tcp", "security": "tls", "tlsSettings": {"serverName": sni}}
    else:
        raise ValueError(f'Invalid trojan link')

else:
    raise ValueError(f'Unsupported protocol: {proto}')

# 防御校验：addr/port 不能为空
if not addr or not port or port <= 0:
    raise ValueError(f'Parsed invalid address: "{addr}:{port}". Check the link format.')

# --- 注入 config.json ---
with open(CONFIG, 'r') as f:
    config = json.load(f)

# 清理旧 relay-out (只清 relay，不动 warp)
config['outbounds'] = [o for o in config['outbounds'] if o.get('tag') != 'relay-out']
config.setdefault('routing', {}).setdefault('rules', [])
config['routing']['rules'] = [r for r in config['routing']['rules'] if r.get('outboundTag') != 'relay-out']

# 注入 relay-out
config['outbounds'].append(out)

# 构造 routing rule
if RELAY_MODE == 'all':
    relay_rule = {"type": "field", "network": "tcp,udp", "outboundTag": "relay-out"}
else:
    if not DOMAINS:
        raise ValueError('分流模式但无分流域名')
    relay_rule = {"type": "field", "domain": DOMAINS, "outboundTag": "relay-out"}

config['routing']['rules'].insert(0, relay_rule)

# 写回
with open(CONFIG, 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f'RELAY_OK|{proto}|{addr}:{port}')
PYEOF

    local result=$?
    # 校验 JSON + 重启
    if python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>/dev/null && [ "$result" = 0 ]; then
        systemctl restart xray 2>/dev/null; sleep 2
        if systemctl is-active xray 2>/dev/null; then
            [ "$mode" != "restore" ] && green_msg "落地中继已生效！"
        else
            red_msg "Xray 启动失败！自动回滚备份。"
            cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            systemctl restart xray 2>/dev/null; sleep 2
        fi
    else
        red_msg "中继配置失败！"
        local emsg; emsg=$(head -3 "$py_err" 2>/dev/null)
        [ -n "$emsg" ] && echo -e "  ${yellow}${emsg}${re}"
        cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    fi
    rm -f "$py_err"
}

relay_clear() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        python3 << PYEOF
import json
with open('${CONFIG_FILE}', 'r') as f:
    config = json.load(f)
config['outbounds'] = [o for o in config['outbounds'] if o.get('tag') != 'relay-out']
config.setdefault('routing', {}).setdefault('rules', [])
config['routing']['rules'] = [r for r in config['routing']['rules'] if r.get('outboundTag') != 'relay-out']
with open('${CONFIG_FILE}', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        if python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>/dev/null; then
            RELAY_ENABLED=0; save_conf
            systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "中继已关闭。"
        else
            cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"; red_msg "回滚失败。"
        fi
    fi
}

#==============================================================================
# WARP SOCKS/IPv6 域名分流模块（基于 fscarmen/warp + Python3 JSON 安全改写）
#==============================================================================
WARP_DOMAIN_FILE="/etc/xray/warp_domains.txt"
WARP_DEFAULT_DOMAINS="google.com googleapis.com googleusercontent.com gstatic.com youtube.com ytimg.com googlevideo.com ggpht.com google-analytics.com googleadservices.com"

# === WARP 主入口 ===
warp_menu() {
    load_conf
    while true; do
        clear
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}WARP SOCKS5 / IPv6 分流配置${re}            ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""

        # 检测 WARP 状态
        local warp_socks_ok=0 warp_v6_ok=0
        (ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':40000 ' && warp_socks_ok=1
        ip -6 addr show 2>/dev/null | grep -q 'wgcf\|Warp' && warp_v6_ok=1

        # 状态栏
            if [ "$warp_socks_ok" = 0 ] && [ "$warp_v6_ok" = 0 ]; then
                echo -e "  ${yellow}WARP 待安装 — 选择 1 一键部署或 6 切换模式${re}"
            else
            [ "$warp_socks_ok" = 1 ] && echo -e "  ${green}WARP SOCKS5 就绪 (127.0.0.1:40000)${re}"
            [ "$warp_v6_ok" = 1 ]    && echo -e "  ${green}WARP IPv6 就绪${re}"
        fi
        echo -e "  ${yellow}选项 6 可切换分流模式，按需安装对应 WARP 组件${re}"
        echo ""
        if [ -f "$WARP_DOMAIN_FILE" ] && [ -s "$WARP_DOMAIN_FILE" ]; then
            local count; count=$(wc -l < "$WARP_DOMAIN_FILE")
            echo -e "  ${cyan}当前分流域名: ${count} 个${re}"
            echo -e "  ${cyan}$(tr '\n' ' ' < "$WARP_DOMAIN_FILE" | head -c 60)...${re}"
        else
            echo -e "  ${yellow}当前无分流域名${re}"
        fi
        echo ""
        echo -e "  ${green}1${re}. 一键部署 (注入默认域名 + 安装 WARP SOCKS5)"
        echo -e "  ${green}2${re}. 手动添加自定义域名 (逗号分隔)"
        echo -e "  ${green}3${re}. 删除指定域名"
        echo -e "  ${green}4${re}. 查看/清空分流域名列表"
        echo -e "  ${green}5${re}. 应用配置并重启 Xray"
        echo -e "  ${purple}6${re}. 切换分流模式 (SOCKS5 ↔ IPv6 直连)"
        echo -e "  ${red}0${re}. 返回主菜单"
        echo ""
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " wc

        case "$wc" in
            1) warp_auto_install_socks || continue; warp_add_defaults
               [ "$(wc -l < "$WARP_DOMAIN_FILE" 2>/dev/null)" -gt 0 ] && warp_apply_routing ;;
            2) warp_add_custom ;;
            3) warp_remove_domain ;;
            4) warp_view_clear ;;
            5) warp_auto_install_socks || continue; warp_apply_routing ;;
            6) warp_switch_mode ;;
            0) return ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

# === 自动安装 WARP SOCKS5（如未安装）===
warp_auto_install_socks() {
    (ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':40000 ' && return 0
    yellow_msg "WARP SOCKS5 未安装，正在自动部署..."
    echo ""
    wget -N --no-check-certificate https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh -O /tmp/warp_menu.sh 2>/dev/null
    if [ -f /tmp/warp_menu.sh ]; then
        chmod +x /tmp/warp_menu.sh
        bash /tmp/warp_menu.sh w; local warp_rc=$?
        rm -f /tmp/warp_menu.sh
    else
        red_msg "下载 fscarmen WARP 脚本失败，请检查网络"
        echo ""; read -p "  按回车继续..." -r; return 1
    fi
    echo ""; sleep 3
    if (ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':40000 '; then
        green_msg "WARP SOCKS5 安装成功！(127.0.0.1:40000)"
        return 0
    else
        red_msg "WARP 安装失败 — 40000 端口未监听 (exit: $warp_rc)"
        echo -e "  ${yellow}排查步骤:${re}"
        if [ "$IS_ALPINE" = 1 ]; then
            echo -e "  ${cyan}1${re}. 检查 WireGuard 接口: ${green}ip link show wgcf${re}"
            echo -e "  ${cyan}2${re}. 检查服务: ${green}rc-service -l | grep -i warp${re}"
            echo -e "  ${cyan}3${re}. 安装依赖: ${green}apk add wireguard-tools${re}"
            echo -e "  ${cyan}4${re}. 查看日志: ${green}tail -30 /var/log/messages | grep -i warp${re}"
        else
            echo -e "  ${cyan}1${re}. 服务状态: ${green}systemctl status wireproxy${re}"
            echo -e "  ${cyan}2${re}. 查看日志: ${green}journalctl -u wireproxy -n 10${re}"
            echo -e "  ${cyan}3${re}. 检查端口: ${green}ss -tlnp | grep 40000${re}"
        fi
        echo ""; read -p "  按回车继续..." -r
        return 1
    fi
}

# === 安装 fscarmen WARP ===
warp_install() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}     ${white}安装 fscarmen WARP (Socks5 模式)${re}       ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    yellow_msg "正在拉取并运行 fscarmen/warp 官方安装脚本..."
    echo ""
    # 下载并运行 warp 菜单脚本，选择模式 w (WireProxy/Socks5)
    wget -N -q --no-check-certificate https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh -O /tmp/warp_menu.sh 2>/dev/null
    if [ -f /tmp/warp_menu.sh ]; then
        chmod +x /tmp/warp_menu.sh
        # 模式 w = WireProxy/Socks5 模式，默认端口 40000
        bash /tmp/warp_menu.sh w
        rm -f /tmp/warp_menu.sh
    else
        red_msg "下载失败，请检查网络连接。"
        echo ""; read -p "  按回车返回..." -r; return
    fi

    # 验证安装
    sleep 3
    if (ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':40000 '; then
        green_msg "WARP Socks5 安装成功！(127.0.0.1:40000)"
    else
        yellow_msg "安装完成，但未检测到 40000 端口。请手动检查 warp 服务状态。"
    fi
    echo ""; read -p "  按回车继续..." -r
}

# === 注入默认 Google/YouTube 域名组 ===
warp_add_defaults() {
    touch "$WARP_DOMAIN_FILE"
    local added=0
    for d in $WARP_DEFAULT_DOMAINS; do
        if ! grep -qxF "$d" "$WARP_DOMAIN_FILE"; then
            echo "$d" >> "$WARP_DOMAIN_FILE"
            added=$((added+1))
        fi
    done
    green_msg "已注入 ${added} 个默认域名 (Google/YouTube 系列)"
    echo ""; read -p "  按回车继续..." -r
}

# === 手动添加自定义域名 ===
warp_add_custom() {
    echo ""
    echo -e "  ${yellow}请输入要分流的域名，多个用逗号或空格分隔:${re}"
    echo -e "  ${cyan}示例: twitter.com, instagram.com, openai.com${re}"
    echo ""
    read -p "  > " input
    [ -z "$input" ] && { yellow_msg "已取消。"; sleep 1; return; }

    # 分割逗号或空格
    local added=0
    touch "$WARP_DOMAIN_FILE"
    IFS=', ' read -ra DOMAINS <<< "$input"
    for d in "${DOMAINS[@]}"; do
        d=$(echo "$d" | xargs)  # 去前后空格
        [ -z "$d" ] && continue
        if ! grep -qxF "$d" "$WARP_DOMAIN_FILE"; then
            echo "$d" >> "$WARP_DOMAIN_FILE"
            echo -e "  ${green}  + ${d}${re}"
            added=$((added+1))
        else
            echo -e "  ${yellow}  = ${d} (已存在)${re}"
        fi
    done
    green_msg "共添加 ${added} 个域名"
    echo ""; read -p "  按回车继续..." -r
}

# === 删除指定域名 ===
warp_remove_domain() {
    [ ! -f "$WARP_DOMAIN_FILE" ] || [ ! -s "$WARP_DOMAIN_FILE" ] && { yellow_msg "分流域名列表为空。"; echo ""; read -p "  按回车返回..." -r; return; }

    echo ""
    echo -e "  ${white}当前分流域名:${re}"
    nl -w2 -s'. ' "$WARP_DOMAIN_FILE"
    echo ""
    echo -e "  ${yellow}输入要删除的序号 (多个用逗号分隔)，或输入域名本身:${re}"
    read -p "  > " input
    [ -z "$input" ] && { yellow_msg "已取消。"; sleep 1; return; }

    # 读取域名到数组
    mapfile -t lines < "$WARP_DOMAIN_FILE" 2>/dev/null || { IFS=$'\n' read -d '' -ra lines < "$WARP_DOMAIN_FILE"; }
    local to_remove=()

    # 解析输入：数字序号或域名文本
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part=$(echo "$part" | xargs)
        if [[ "$part" =~ ^[0-9]+$ ]]; then
            # 数字序号
            local idx=$((part-1))
            [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "${#lines[@]}" ] && to_remove+=("${lines[$idx]}")
        else
            # 域名文本
            to_remove+=("$part")
        fi
    done

    # 重建文件
    local removed=0
    > "$WARP_DOMAIN_FILE"
    for line in "${lines[@]}"; do
        local keep=1
        for rm_d in "${to_remove[@]}"; do
            [ "$line" = "$rm_d" ] && { keep=0; echo -e "  ${red}  - ${line}${re}"; removed=$((removed+1)); break; }
        done
        [ "$keep" = 1 ] && echo "$line" >> "$WARP_DOMAIN_FILE"
    done
    green_msg "已删除 ${removed} 个域名"
    echo ""; read -p "  按回车继续..." -r
}

# === 查看/清空列表 ===
warp_view_clear() {
    while true; do
        clear
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}WARP 分流域名列表${re}                     ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        if [ -f "$WARP_DOMAIN_FILE" ] && [ -s "$WARP_DOMAIN_FILE" ]; then
            nl -w2 -s'. ' "$WARP_DOMAIN_FILE"
            echo ""
            echo -e "  ${green}共 $(wc -l < "$WARP_DOMAIN_FILE") 个域名${re}"
        else
            echo -e "  ${yellow}列表为空${re}"
        fi
        echo ""
        echo -e "  ${red}c${re}. 清空全部    ${cyan}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " vc
        case "$vc" in
            c|C) echo ""; echo -ne "  ${red}确认清空? (y/n): ${re}"; read cf
                 [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { > "$WARP_DOMAIN_FILE"; green_msg "已清空。"; } ;;
            0) return ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac
        read -p "  按回车返回..." -r
    done
}

# === 核心：使用 Python3 安全改写 config.json，应用 WARP 分流 ===
warp_apply_routing() {
    [ ! -f "$WARP_DOMAIN_FILE" ] || [ ! -s "$WARP_DOMAIN_FILE" ] && { yellow_msg "分流域名列表为空，请先添加域名。"; echo ""; read -p "  按回车返回..." -r; return; }
    # 自动安装 WARP（如未安装）
    warp_auto_install_socks || return

    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}     ${white}应用 WARP 分流规则${re}                     ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    # 检查 Python3 可用性
    if ! command -v python3 &>/dev/null; then
        red_msg "未检测到 Python3，请先安装: apt install python3"
        echo ""; read -p "  按回车返回..." -r; return
    fi

    # 读取域名列表
    local domains_json; domains_json=$(json_array_from_file "$WARP_DOMAIN_FILE")
    [ "$domains_json" = "[]" ] && { yellow_msg "域名列表解析失败。"; return; }

    # 备份 config.json
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    green_msg "已备份: ${CONFIG_FILE}.bak"

    # 使用 Python3 安全改写 JSON
    yellow_msg "正在注入 WARP 出站与路由规则..."
    python3 << PYEOF
import json, sys

CONFIG = '${CONFIG_FILE}'
DOMAINS = ${domains_json}

# 读取配置
with open(CONFIG, 'r') as f:
    config = json.load(f)

# 1. 清理已有 warp-out 出站，重新注入
config['outbounds'] = [o for o in config['outbounds'] if o.get('tag') != 'warp-out']
warp_out = {
    "tag": "warp-out",
    "protocol": "socks",
    "settings": {"servers": [{"address": "127.0.0.1", "port": 40000}]}
}
config['outbounds'].append(warp_out)

# 2. 确保 routing 存在
if 'routing' not in config:
    config['routing'] = {'rules': []}
if 'rules' not in config['routing']:
    config['routing']['rules'] = []

# 3. 移除已有 WARP 分流规则
config['routing']['rules'] = [r for r in config['routing']['rules'] if r.get('outboundTag') != 'warp-out']

# 4. 构造新分流规则并插入最顶部（最高优先级）
warp_rule = {
    "type": "field",
    "outboundTag": "warp-out",
    "domain": DOMAINS
}
config['routing']['rules'].insert(0, warp_rule)

# 5. 格式化写回
with open(CONFIG, 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print('CONFIG_OK')
PYEOF

    if python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>/dev/null; then
        green_msg "规则注入成功，重启 Xray..."
        systemctl restart xray 2>/dev/null; sleep 2
        if systemctl is-active xray; then
            get_status; green_msg "WARP 分流已生效"
            echo ""; echo -e "  ${cyan}分流域名:${re} ${white}$(tr '\n' ' ' < "$WARP_DOMAIN_FILE")${re}"
        else
            red_msg "Xray 启动失败！自动回滚备份。"
            cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            systemctl restart xray 2>/dev/null; sleep 2; get_status
        fi
    else
        red_msg "JSON 写入不合法！自动回滚备份。"
        cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    fi
    echo ""; read -p "  按回车返回..." -r
}

# === 切换分流模式：SOCKS5 ↔ IPv6 直连（二选一）===
warp_switch_mode() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}     ${white}切换 WARP 分流模式${re}                     ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    # 检测当前模式
    local has_w=0 has_v6=0
    jq -e '.outbounds[] | select(.tag=="warp-out")'  "$CONFIG_FILE" &>/dev/null && has_w=1
    jq -e '.outbounds[] | select(.tag=="v6-direct")' "$CONFIG_FILE" &>/dev/null && has_v6=1
    local cur_mode="无"
    [ "$has_w" = 1 ] && [ "$has_v6" = 1 ] && cur_mode="智能分流 (Google→IPv6 + YouTube→SOCKS5)"
    [ "$has_w" = 1 ] && [ "$has_v6" = 0 ] && cur_mode="SOCKS5 (40000端口)"
    [ "$has_w" = 0 ] && [ "$has_v6" = 1 ] && cur_mode="IPv6 直连"
    echo -e "  ${yellow}当前模式: ${cyan}${cur_mode}${re}"
    echo ""

    echo -e "  ${green}1${re}. SOCKS5 模式 — 全部域名走 WARP Socks5 (127.0.0.1:40000)"
    echo -e "  ${green}2${re}. IPv6 模式 — 全部域名走 IPv6 直连"
    echo -e "  ${purple}3${re}. 智能分流 — Google 走 IPv6 + YouTube 走 SOCKS5 (推荐)"
    echo -e "  ${red}0${re}. 返回"
    echo ""
    echo -e " ${purple}────────────────────────────────────────${re}"
    read -p "  请选择: " mc; [ "$mc" = "0" ] && return

    # 检查 Python3
    if ! command -v python3 &>/dev/null; then
        red_msg "未检测到 Python3，请先安装: apt install python3"
        echo ""; read -p "  按回车返回..." -r; return
    fi

    # 确保有域名列表
    [ ! -f "$WARP_DOMAIN_FILE" ] || [ ! -s "$WARP_DOMAIN_FILE" ] && { warp_add_defaults; }

    # 备份
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    case "${mc:-1}" in
        1|2|3)
            # 安装所需 WARP 组件
            if [ "$mc" = "1" ] || [ "$mc" = "3" ]; then
                if ! (ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':40000 '; then
                    yellow_msg "安装 WARP SOCKS5 模式..."
                    wget -N -q --no-check-certificate https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh -O /tmp/warp_menu.sh 2>/dev/null
                    [ -f /tmp/warp_menu.sh ] && { chmod +x /tmp/warp_menu.sh; bash /tmp/warp_menu.sh w; rm -f /tmp/warp_menu.sh; }
                else green_msg "WARP SOCKS5 已就绪"; fi
            fi
            if [ "$mc" = "2" ] || [ "$mc" = "3" ]; then
                if ! ip -6 addr show 2>/dev/null | grep -q 'wgcf\|Warp'; then
                    yellow_msg "安装 WARP IPv6 模式..."
                    wget -N -q --no-check-certificate https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh -O /tmp/warp_menu.sh 2>/dev/null
                    [ -f /tmp/warp_menu.sh ] && { chmod +x /tmp/warp_menu.sh; bash /tmp/warp_menu.sh 6; rm -f /tmp/warp_menu.sh; }
                else green_msg "WARP IPv6 已就绪"; fi
            fi
            ;;&
        1) warp_py_apply "socks5" ;;
        2) warp_py_apply "ipv6" ;;
        3) warp_py_apply "smart" ;;
        *) red_msg "无效"; return ;;
    esac

    echo ""; read -p "  按回车返回..." -r
}

# === Python3 分流写入（统一入口）===
warp_py_apply() {
    local mode="$1"

    # 构建域名列表 (JSON-safe via json_array_from_file)
    local all_domains; all_domains=$(json_array_from_file "$WARP_DOMAIN_FILE")
    local google_list yt_list
    google_list='["google.com","googleapis.com","googleusercontent.com","gstatic.com","ggpht.com","google-analytics.com","googletagmanager.com","googleadservices.com","googlesyndication.com","google.com.hk","google.cn"]'
    yt_list='["youtube.com","ytimg.com","googlevideo.com"]'

    local label
    case "$mode" in
        socks5) label="SOCKS5 (全部域名 → warp-out)" ;;
        ipv6)   label="IPv6 (全部域名 → v6-direct)" ;;
        smart)  label="智能分流 (Google→IPv6, YouTube→SOCKS5)" ;;
    esac
    yellow_msg "应用: ${label}..."

    python3 << PYEOF
import json

with open('${CONFIG_FILE}', 'r') as f:
    config = json.load(f)

# 清理旧出站和规则
config['outbounds'] = [o for o in config['outbounds'] if o.get('tag') not in ('warp-out', 'v6-direct')]
config.setdefault('routing', {}).setdefault('rules', [])
config['routing']['rules'] = [r for r in config['routing']['rules']
                              if r.get('outboundTag') not in ('warp-out', 'v6-direct')]

mode = '${mode}'

if mode == 'socks5':
    # SOCKS5 — 全部走 warp-out
    config['outbounds'].append({"tag":"warp-out","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":40000}]}})
    config['routing']['rules'].insert(0, {"type":"field","outboundTag":"warp-out","domain":${all_domains}})

elif mode == 'ipv6':
    # IPv6 — 全部走 v6-direct
    config['outbounds'].append({"tag":"v6-direct","protocol":"freedom","settings":{"domainStrategy":"UseIPv6"}})
    config['routing']['rules'].insert(0, {"type":"field","outboundTag":"v6-direct","domain":${all_domains}})

elif mode == 'smart':
    # 智能分流：Google → IPv6, YouTube → SOCKS5
    config['outbounds'].append({"tag":"v6-direct","protocol":"freedom","settings":{"domainStrategy":"UseIPv6"}})
    config['outbounds'].append({"tag":"warp-out","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":40000}]}})
    # Google → v6-direct (最高优先级)
    config['routing']['rules'].insert(0, {"type":"field","outboundTag":"v6-direct","domain":${google_list}})
    # YouTube → warp-out
    config['routing']['rules'].insert(1, {"type":"field","outboundTag":"warp-out","domain":${yt_list}})

with open('${CONFIG_FILE}', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print('APPLY_OK')
PYEOF

    # 校验 JSON 合法性
    if python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>/dev/null; then
        green_msg "规则注入成功，重启 Xray..."
        systemctl restart xray 2>/dev/null; sleep 2
        if systemctl is-active xray; then
            get_status; green_msg "Xray 运行正常！"
            echo ""
            case "$mode" in
                socks5) echo -e "  ${cyan}全部域名${re} → ${green}WARP SOCKS5${re}" ;;
                ipv6)   echo -e "  ${cyan}全部域名${re} → ${green}WARP IPv6 直连${re}" ;;
                smart)  echo -e "  ${cyan}Google${re}  → ${green}IPv6 直连${re} (免验证码)"
                        echo -e "  ${cyan}YouTube${re} → ${purple}WARP SOCKS5${re} (防弹窗)" ;;
            esac
        else
            red_msg "Xray 启动失败！JSON 虽然合法但配置有误，自动回滚备份。"
            cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            systemctl restart xray 2>/dev/null; sleep 2
            get_status
        fi
    else
        red_msg "JSON 写入不合法！自动回滚备份。"
        cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    fi
}

update_xray_core() {
    yellow_msg "正在检测 Xray 内核版本并更新..."
    local ARCH_ARG; ARCH_ARG=$(detect_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; sleep 2; return; }
    
    local utmp="/tmp/xray_update.zip"
    curl -sLfo "$utmp" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    if [ -s "$utmp" ]; then
        systemctl stop xray 2>/dev/null
        unzip -o "$utmp" -d "$WORK_DIR" >/dev/null 2>&1
        chmod +x "${WORK_DIR}/xray"
        rm -f "$utmp"
        systemctl start xray 2>/dev/null
        green_msg "Xray 内核更新完成！"
    else
        red_msg "下载 Xray 内核失败，请检查网络！"
    fi
    sleep 2
}

#==============================================================================
# 主菜单
#==============================================================================
add_hy2_protocol() {
    local uuid ip h_port h_sni new_inbound
    uuid=$(get_uuid)
    ip=$(get_ip)
    h_port=$(find_free_port "$(shuf -i 10000-60000 -n 1)")
    h_sni="${HY2_SNI:-www.bing.com}"

    clear
    echo ""
    echo -e " ${purple}Add Hysteria2${re}"
    echo ""
    echo -e "  Default SNI: ${cyan}${h_sni}${re}"
    read -p "  SNI [enter keep]: " hs
    [ -n "$hs" ] && h_sni="$hs"

    echo -e "  Random port: ${cyan}${h_port}${re}"
    read -p "  Port [enter keep]: " hp
    if [ -n "$hp" ]; then
        if is_port "$hp" && ! port_in_use "$hp"; then
            h_port="$hp"
        else
            red_msg "Invalid or occupied port, keep random port."
        fi
    fi

    echo ""
    echo -e "  Hysteria2 SNI: ${green}${h_sni}${re}"
    echo -e "  Hysteria2 port: ${green}${h_port}${re}"
    echo -ne "  Confirm add? (y/n) [y]: "
    read cf
    [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "Canceled."; return; }

    HY2_PORT="$h_port"
    HY2_SNI="$h_sni"
    gen_hy2_cert || { red_msg "Failed to generate Hysteria2 self-signed certificate."; return; }

    new_inbound='{"port":'"${HY2_PORT}"',"listen":"0.0.0.0","protocol":"hysteria","tag":"hy2","settings":{"version":2,"users":[{"auth":"'"${uuid}"'","level":0,"email":"argov-default"}]},"streamSettings":{"network":"hysteria","security":"tls","tlsSettings":{"alpn":["h3"],"serverName":"'"${HY2_SNI}"'","certificates":[{"certificateFile":"'"${HY2_CERT_FILE}"'","keyFile":"'"${HY2_KEY_FILE}"'"}]},"hysteriaSettings":{"version":2,"udpIdleTimeout":"60s"}}}'
    jq --argjson i "$new_inbound" '.inbounds += [$i]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    ENABLE_HY2=1
    sync_xray_users || return
    save_conf
    yellow_msg "Restarting Xray..."
    systemctl restart xray 2>/dev/null || true
    rc-service xray restart 2>/dev/null || true
    sleep 2
    get_status
    green_msg "Hysteria2 added."
    [ -n "$ip" ] && echo -e "  ${green}$(gen_hy2_link "$uuid" "$ip" "$HY2_PORT" "$HY2_SNI" "${NODE_NAME}-Hy2")${re}"
    echo ""
    read -p "  Press Enter to continue..." -r
}

delete_protocol() {
    local has_reality=0 has_hy2=0 has_ss=0 choice tag label
    jq -e '.inbounds[]|select(.tag=="reality")' "$CONFIG_FILE" >/dev/null 2>&1 && has_reality=1
    jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1 && has_hy2=1
    jq -e '.inbounds[]|select(.tag=="ss" or .protocol=="shadowsocks")' "$CONFIG_FILE" >/dev/null 2>&1 && has_ss=1

    clear
    echo ""
    echo -e " ${purple}Delete optional node${re}"
    echo ""
    [ "$has_reality" = 1 ] && echo -e "  ${green}1${re}. Reality"
    [ "$has_hy2" = 1 ] && echo -e "  ${green}2${re}. Hysteria2"
    [ "$has_ss" = 1 ] && echo -e "  ${green}3${re}. Shadowsocks"
    echo -e "  ${red}0${re}. Back"
    read -p "  Select: " choice

    case "$choice" in
        1) [ "$has_reality" = 1 ] || return; tag="reality"; label="Reality"; ENABLE_REALITY=0; REALITY_PORT=0 ;;
        2) [ "$has_hy2" = 1 ] || return; tag="hy2"; label="Hysteria2"; ENABLE_HY2=0; HY2_PORT=0 ;;
        3) [ "$has_ss" = 1 ] || return; tag="ss"; label="Shadowsocks"; ENABLE_SS=0; SS_PORT=0 ;;
        0) return ;;
        *) red_msg "Invalid."; sleep 1; return ;;
    esac

    echo -ne "  Delete ${label}? (y/n): "
    read cf
    [ "$cf" = "y" ] || [ "$cf" = "Y" ] || { yellow_msg "Canceled."; return; }

    case "$tag" in
        ss)
            jq 'del(.inbounds[] | select(.tag=="ss" or .protocol=="shadowsocks"))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            ;;
        *)
            jq --arg tag "$tag" 'del(.inbounds[] | select(.tag==$tag))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            ;;
    esac
    save_conf
    systemctl restart xray 2>/dev/null || true
    rc-service xray restart 2>/dev/null || true
    sleep 1
    green_msg "Deleted."
}

manage_protocols() {
    load_conf
    [ ! -f "$CONFIG_FILE" ] && { red_msg "请先安装。"; return; }

    while true; do
        local has_reality=0 has_hy2=0 has_ss=0
        grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
        grep -qE '"tag"[[:space:]]*:[[:space:]]*"hy2"' "$CONFIG_FILE" 2>/dev/null && has_hy2=1
        grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1

        clear
        echo ""; echo -e " ${purple}┌────────────────────────────────────────┐${re}"
        echo -e " ${purple}│${re}         ${white}管理节点${re}                          ${purple}│${re}"
        echo -e " ${purple}└────────────────────────────────────────┘${re}"
        echo ""

        local vl_port vm_port
        vl_port=$(jq -r '.inbounds[]|select(.tag=="vless-ws")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        vm_port=$(jq -r '.inbounds[]|select(.tag=="vmess-ws")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── Argo 隧道 ──${re}"
        echo ""
        echo -e "  ${green}e1${re}. VLESS + Argo    端口 ${cyan}${vl_port}${re}  路径 ${cyan}/vless-argo${re}"
        echo -e "  ${green}e2${re}. VMess + Argo    端口 ${cyan}${vm_port}${re}  路径 ${cyan}/vmess-argo${re}"
        echo ""

        if [ "$has_reality" = 1 ] || [ "$has_hy2" = 1 ] || [ "$has_ss" = 1 ]; then
            echo -e "  ${white}── 可选协议 · 可编辑 ──${re}"
            echo ""
        fi
        if [ "$has_reality" = 1 ]; then
            local rp rs
            rp=$(jq -r '.inbounds[]|select(.tag=="reality")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            rs=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]//empty' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}e3${re}. VLESS Reality    ${cyan}${rs}${re}  端口 ${cyan}${rp}${re}"
        fi
        if [ "$has_hy2" = 1 ]; then
            local hp hs
            hp=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            hs=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}e4${re}. Hysteria2       ${cyan}${hs}${re}  端口 ${cyan}${hp}${re}"
        fi
        if [ "$has_ss" = 1 ]; then
            local sp sm
            sp=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            sm=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}e5${re}. Shadowsocks       ${cyan}${sm}${re}  端口 ${cyan}${sp}${re}"
        fi

        if [ "$has_reality" = 0 ] || [ "$has_hy2" = 0 ] || [ "$has_ss" = 0 ]; then
            echo ""; echo -e "  ${white}── 可添加 ──${re}"; echo ""
        fi
        [ "$has_reality" = 0 ] && echo -e "  ${cyan}a1${re}. VLESS Reality"
        [ "$has_hy2" = 0 ] && echo -e "  ${cyan}a2${re}. Hysteria2"
        [ "$has_ss" = 0 ] && echo -e "  ${cyan}a3${re}. Shadowsocks"

        echo ""; echo -e "  ${white}── 自定义节点(自添加) ──${re}"; echo ""
        local custom_count=0
        [ -f "${WORK_DIR}/custom_links.txt" ] && custom_count=$(grep -c '[^[:space:]]' "${WORK_DIR}/custom_links.txt" 2>/dev/null || echo 0)
        [ -z "$custom_count" ] && custom_count=0
        echo -e "  已有 ${cyan}${custom_count}${re} 个自定义链接"
        echo ""
        echo -e "  ${cyan}c1${re}. 添加自定义链接   ${cyan}c2${re}. 查看/删除自定义链接"
        echo ""
        echo -e "  ${purple}提示${re}: 内置 Hysteria2 会进入用户统计与限额；端口跳跃暂未自动配置。"

        [ "$has_reality" = 1 ] || [ "$has_hy2" = 1 ] || [ "$has_ss" = 1 ] && echo "" && echo -e "  ${red}d${re}. 删除可选节点"
        echo ""; echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请输入: " ac; [ "$ac" = "0" ] && return

        case "$ac" in
            e1) edit_protocol "vless-ws" "VLESS + Argo" ;;
            e2) edit_protocol "vmess-ws" "VMess + Argo" ;;
            e3) [ "$has_reality" = 1 ] && edit_protocol "reality" "VLESS Reality" ;;
            e4) [ "$has_hy2" = 1 ] && edit_hy2_protocol ;;
            e5) [ "$has_ss" = 1 ] && edit_protocol "ss" "Shadowsocks" ;;
            a1) [ "$has_reality" = 0 ] && add_single_protocol "reality" ;;
            a2) [ "$has_hy2" = 0 ] && add_hy2_protocol ;;
            a3) [ "$has_ss" = 0 ] && add_single_protocol "ss" ;;
            c1) add_custom_link ;;
            c2) view_delete_custom_links ;;
            d|D) delete_protocol ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac
        load_conf
    done
}

main_menu() {
    load_conf
    while true; do
        get_status; clear
        local uuid_short="未安装" hd=""
        [ -f "$CONFIG_FILE" ] && uuid_short="$(get_uuid | cut -c1-12)..."
        [ "$TUNNEL_RAW" = "running" ] && hd=$(get_argo_domain)
        [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"

        logo
        echo -e "  ${yellow}▶${re} 命令行输入 ${green}ag${re} 可随时启动本面板"
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}ArgoV  纯净版隧道管理面板${re}              ${purple}║${re}"
        echo -e " ${purple}║${re}     ${cyan}$(get_proto_summary)${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  名称 : ${white}${NODE_NAME}${re}    Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"
        echo -e "  UUID : ${cyan}${uuid_short}${re}"
        [ -n "$hd" ] && echo -e "  域名 : ${green}${hd}${re}"
        echo -e "  CDN  : ${green}$(get_cdn):$(get_cdn_port)${re}"
        echo ""
        echo -e " ${purple}──────────────── ✦ 核心功能 ✦ ────────────────${re}"
        echo -e "  ${green}1${re}. 🔗 查看节点链接       ${green}2${re}. ☁️  更换优选线路"
        echo -e "  ${green}3${re}. ⚙️  修改基础配置       ${cyan}a${re}. 🧩 管理代理节点 (添加/编辑/删除)"
        echo -e "  ${cyan}u${re}. 👥 用户/流量限额       ${yellow}配额用户仅下发本机节点"
        echo ""
        echo -e " ${purple}──────────────── ✦ 进阶路由 ✦ ────────────────${re}"
        echo -e "  ${purple}w${re}. 🌐 独立 WARP 分流     ${purple}r${re}. 🔀 落地节点中继"
        echo ""
        echo -e " ${purple}──────────────── ✦ 状态运维 ✦ ────────────────${re}"
        echo -e "  ${green}4${re}. ▶️  启动系统         ${red}5${re}. ⏹️  停止系统"
        echo -e "  ${yellow}6${re}. 🔁 重启 Argo 隧道    ${yellow}7${re}. 🔄 重新安装 (保留数据)"
        echo -e "  ${cyan}8${re}. 🆙 更新管理脚本      ${red}9${re}. 🗑️  彻底卸载系统"
        echo -e "  ${purple}x${re}. 🚀 更新 Xray 内核    ${cyan}0${re}. 🚪 安全退出"
        echo -e " ${purple}───────────────────────────────────────────────${re}"
        read -p "  请输入 (0-9 / a / u / x / w / r): " c
        case "$c" in
            1) show_node; read -p "  按回车返回..." -r ;;
            2) edit_cdn; read -p "  按回车返回..." -r ;;
            3) change_config ;;
            a|A) manage_protocols ;;
            u|U) manage_users ;;
            4) start_services; sleep 1 ;; 5) stop_services; sleep 1 ;; 6) restart_services; sleep 1 ;;
            7) echo -ne "  ${yellow}重新安装? (y/n): ${re}"; read cf
               [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { load_conf; do_install; }; read -p "  按回车返回..." -r ;;
            8) yellow_msg "拉取最新版..."
               local utmp; utmp=$(mktemp /tmp/argov.XXXXXX)
               curl -sLfo "$utmp" https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh && bash "$utmp" && rm -f "$utmp"
               clear; continue ;;
            x|X) update_xray_core ;;
            9) echo -ne "  ${red}⚠ 确定卸载? (y/n): ${re}"; read cf
               if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                   stop_sub_server 2>/dev/null
                   stop_stats_service 2>/dev/null
                   systemctl stop xray argov-tunnel argov-stats 2>/dev/null; systemctl disable xray argov-tunnel argov-stats 2>/dev/null
                    rm -rf "$WORK_DIR"; rm -f /etc/systemd/system/xray.service /etc/systemd/system/argov-tunnel.service /etc/systemd/system/argov-sub.service /etc/systemd/system/argov-stats.service /etc/init.d/xray /etc/init.d/argov-tunnel /etc/init.d/argov-stats "$SCRIPT_PATH" "${WORK_DIR}/argov-tunnel.sh"
                   systemctl daemon-reload; green_msg "卸载完成。"; fi ;;
            w|W) warp_menu ;;
            r|R) relay_menu ;;
            0) clear; break ;;
            *) red_msg "无效 (0-9 / a / u / x / w / r)"; sleep 1 ;;
        esac
    done
}

migrate_argox_to_argov() {
    if [ -f "/etc/xray/argox.conf" ] && [ ! -f "/etc/xray/argov.conf" ]; then
        yellow_msg "检测到旧版 ArgoX 配置，正在无缝迁移至 ArgoV..."
        mv /etc/xray/argox.conf /etc/xray/argov.conf 2>/dev/null
        systemctl stop argox-tunnel argox-sub 2>/dev/null
        systemctl disable argox-tunnel argox-sub 2>/dev/null
        rm -f /etc/systemd/system/argox-tunnel.service /etc/systemd/system/argox-sub.service
        rc-service argox-tunnel stop 2>/dev/null; rc-service argox-sub stop 2>/dev/null
        rc-update del argox-tunnel default 2>/dev/null; rc-update del argox-sub default 2>/dev/null
        rm -f /etc/init.d/argox-tunnel /etc/init.d/argox-sub
        systemctl daemon-reload 2>/dev/null || true
        mv /etc/xray/argox-tunnel.sh /etc/xray/argov-tunnel.sh 2>/dev/null
        rm -f /usr/bin/argov 2>/dev/null
        
        load_conf
        rebuild_tunnel "$ARGO_MODE"
        start_sub_server
        start_stats_service
        systemctl start xray argov-tunnel 2>/dev/null
        
        cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
T="/tmp/argov.sh"
curl -sLfo "$T" https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh
[ -s "$T" ] && bash "$T" "$@"
ARGOWRAP
        chmod +x "$SCRIPT_PATH"
        green_msg "迁移完成！输入 ag 即可使用全新面板。"
        sleep 2
    fi
}

migrate_argox_to_argov
load_conf
[ ! -f "$CONFIG_FILE" ] && interactive_install
main_menu
