#!/usr/bin/env bash
#==============================================================================
# ArgoX-Mini — Cloudflare Argo Tunnel 多协议交互式管理脚本
# VLESS + VMess (Argo)  |  Shadowsocks  |  VLESS Reality
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
${purple}  ██████╗  ██╗   ██╗ ███╗   ███╗ ██████╗  ██╗      ██╗ ███╗   ██╗  ██████╗  ${re}
${cyan}  ██╔══██╗ ██║   ██║ ████╗ ████║ ██╔══██╗ ██║      ██║ ████╗  ██║ ██╔════╝  ${re}
${green}  ██║  ██║ ██║   ██║ ██╔████╔██║ ██████╔╝ ██║      ██║ ██╔██╗ ██║ ██║  ███╗ ${re}
${cyan}  ██║  ██║ ██║   ██║ ██║╚██╔╝██║ ██╔═══╝  ██║      ██║ ██║╚██╗██║ ██║   ██║ ${re}
${purple}  ██████╔╝ ╚██████╔╝ ██║ ╚═╝ ██║ ██║      ███████╗ ██║ ██║ ╚████║ ╚██████╔╝ ${re}
${re}  ╚═════╝   ╚═════╝  ╚═╝     ╚═╝ ╚═╝      ╚══════╝ ╚═╝ ╚═╝  ╚═══╝  ╚═════╝  "
}

# --- 常量 ---
CONFIG_FILE="/etc/xray/config.json"
USER_CONF="/etc/xray/argox.conf"
TUNNEL_LOG="/etc/xray/argo.log"
WORK_DIR="/etc/xray"
SCRIPT_PATH="/usr/bin/argov"
CDN_DEFAULT="cdn.31514926.xyz"

# --- 端口 ---
ARGO_PORT="${ARGO_PORT:-8080}"
VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
CDN_PORT="${CDN_PORT:-443}"
REALITY_PORT="${REALITY_PORT:-0}"
SS_PORT="${SS_PORT:-0}"
SUB_PORT="${SUB_PORT:-0}"
SUB_PATH="${SUB_PATH:-}"
SUB_DOMAIN="${SUB_DOMAIN:-}"
SUB_TOKEN="${SUB_TOKEN:-}"

# --- 节点名称 ---
NODE_NAME="${NODE_NAME:-ArgoX-Mini}"

# --- 可选协议 ---
ENABLE_VLESS_ARGO=1
ENABLE_VMESS_ARGO=1
ENABLE_REALITY=0
ENABLE_SS=0

# --- SS 加密 ---
SS_METHODS=("aes-128-gcm" "aes-256-gcm" "chacha20-ietf-poly1305" "xchacha20-ietf-poly1305"
            "2022-blake3-aes-128-gcm" "2022-blake3-aes-256-gcm" "2022-blake3-chacha20-poly1305")
SS_METHOD="${SS_METHOD:-aes-256-gcm}"

# --- Reality SNI ---
REALITY_SNIS=("www.amazon.com" "www.ebay.com" "www.paypal.com" "www.cloudflare.com"
              "dash.cloudflare.com" "aws.amazon.com" "addons.mozilla.org" "www.microsoft.com")
REALITY_SNI="${REALITY_SNI:-www.amazon.com}"

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
gen_reality_keys() {
    local keys; keys=($("${WORK_DIR}/xray" x25519 2>/dev/null | sed 's/.*://'))
    REALITY_PRIV="${keys[0]}"
    REALITY_PUB="${keys[1]}"
    [ -z "$REALITY_PRIV" ] && { REALITY_PRIV="REPLACE_ME"; REALITY_PUB="REPLACE_ME"; }
}
gen_reality_shortid() {
    REALITY_SHORTID=$(openssl rand -hex 4 2>/dev/null || printf '%08x' $((RANDOM*RANDOM)))
}
gen_ss2022_pass() {
    local method="$1"
    [[ "$method" =~ 128 ]] && openssl rand -base64 16 || openssl rand -base64 32
}

# --- 持久化 ---
load_conf() {
    [ -f "$USER_CONF" ] && . "$USER_CONF"
    NODE_NAME="${NODE_NAME:-ArgoX-Mini}"
    ARGO_PORT="${ARGO_PORT:-8080}"; VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
    VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
    CDN_PORT="${CDN_PORT:-443}"; CDN_DOMAIN="${CDN_DOMAIN:-$CDN_DEFAULT}"
    ARGO_MODE="${ARGO_MODE:-temp}"; ARGO_AUTH="${ARGO_AUTH:-}"
    ARGO_FIXED_DOMAIN="${ARGO_FIXED_DOMAIN:-}"; UUID_CUSTOM="${UUID_CUSTOM:-}"; LAST_ARGO_DOMAIN="${LAST_ARGO_DOMAIN:-}"
    REALITY_PORT="${REALITY_PORT:-0}"; SS_PORT="${SS_PORT:-0}"
    SUB_PORT="${SUB_PORT:-0}"; SUB_PATH="${SUB_PATH:-}"
    SUB_DOMAIN="${SUB_DOMAIN:-}"; SUB_TOKEN="${SUB_TOKEN:-}"
    REALITY_SNI="${REALITY_SNI:-www.amazon.com}"; SS_METHOD="${SS_METHOD:-aes-256-gcm}"
    ENABLE_REALITY="${ENABLE_REALITY:-0}"; ENABLE_SS="${ENABLE_SS:-0}"
    REALITY_PRIV="${REALITY_PRIV:-}"; REALITY_PUB="${REALITY_PUB:-}"
    REALITY_SHORTID="${REALITY_SHORTID:-}"
}
save_conf() {
    {
        echo "# ArgoX-Mini — $(date '+%Y-%m-%d %H:%M:%S')"
        save_var NODE_NAME "$NODE_NAME"
        save_var ARGO_PORT "$ARGO_PORT"; save_var VLESS_WS_PORT "$VLESS_WS_PORT"
        save_var VMESS_WS_PORT "$VMESS_WS_PORT"; save_var CDN_PORT "$CDN_PORT"
        save_var CDN_DOMAIN "$CDN_DOMAIN"; save_var ARGO_MODE "$ARGO_MODE"; save_var ARGO_AUTH "$ARGO_AUTH"
        save_var ARGO_FIXED_DOMAIN "$ARGO_FIXED_DOMAIN"; save_var UUID_CUSTOM "$UUID_CUSTOM"
        save_var REALITY_PORT "$REALITY_PORT"; save_var SS_PORT "$SS_PORT"; save_var SUB_PORT "$SUB_PORT"; save_var SUB_PATH "$SUB_PATH"; save_var SUB_DOMAIN "$SUB_DOMAIN"; save_var SUB_TOKEN "$SUB_TOKEN"
        save_var REALITY_SNI "$REALITY_SNI"; save_var SS_METHOD "$SS_METHOD"
        save_var ENABLE_REALITY "$ENABLE_REALITY"; save_var ENABLE_SS "$ENABLE_SS"
        save_var REALITY_PRIV "$REALITY_PRIV"; save_var REALITY_PUB "$REALITY_PUB"
        save_var REALITY_SHORTID "$REALITY_SHORTID"; save_var LAST_ARGO_DOMAIN "$LAST_ARGO_DOMAIN"
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

show_qr() {
    local qr="${WORK_DIR}/qrencode"
    [ ! -f "$qr" ] && { yellow_msg "QR 工具未安装"; return 1; }
    chmod +x "$qr" 2>/dev/null; echo ""
    "$qr" -t ANSIUTF8 -m 1 -s 2 "$1" 2>/dev/null || yellow_msg "QR 生成失败"
}
install_qrencode() {
    local qr="${WORK_DIR}/qrencode"; [ -f "$qr" ] && return 0
    local a; case "$(uname -m)" in x86_64) a="amd64" ;; aarch64|arm64) a="arm64" ;; *) return 1 ;; esac
    curl -sLo "$qr" "https://github.com/eooce/test/releases/download/${a}/qrencode-linux-${a}" 2>/dev/null; chmod +x "$qr" 2>/dev/null
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

start_sub_server() {
    if [ "$SUB_PORT" = "0" ]; then
        [ -n "$SUB_DOMAIN" ] && SUB_PORT=2096 || SUB_PORT=$(find_free_port "$(shuf -i 20000-50000 -n 1)")
    fi
    # 先停旧服务再查端口（避免自己的旧进程被误判为占用）
    systemctl stop argox-sub 2>/dev/null; rc-service argox-sub stop 2>/dev/null; sleep 1
    port_in_use "$SUB_PORT" && SUB_PORT=$(find_free_port "$SUB_PORT")
    [ -z "$SUB_TOKEN" ] && SUB_TOKEN=$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)
    [ -z "$SUB_PATH" ] && SUB_PATH="/${SUB_TOKEN}"
    save_conf; bash "${WORK_DIR}/sub_gen.sh" 2>/dev/null

    # 自签证书（CF Full 模式需要）
    if [ -n "$SUB_DOMAIN" ] && [ ! -f "${WORK_DIR}/sub_cert.pem" ]; then
        openssl req -x509 -newkey rsa:2048 -keyout "${WORK_DIR}/sub_key.pem" -out "${WORK_DIR}/sub_cert.pem" -days 3650 -nodes -subj "/CN=${SUB_DOMAIN}" 2>/dev/null
    fi

    local py; py=$(command -v python3 || command -v python || true)
    [ -z "$py" ] && { yellow_msg "Python3 未安装，订阅跳过"; return 1; }

    cat > "${WORK_DIR}/sub.py" << PYEOF
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
import subprocess, os, socketserver, threading, time
SUB_FILE='/etc/xray/sub.txt'; PORT=${SUB_PORT}
CACHE=b''; CACHE_LOCK=threading.Lock()

def refresh_cache():
    global CACHE
    try:
        subprocess.run(['${WORK_DIR}/sub_gen.sh'],timeout=15)
        with open(SUB_FILE,'rb') as f: CACHE=f.read()
    except: pass

class ThreadedServer(ThreadingMixIn, HTTPServer):
    allow_reuse_address=True; daemon_threads=True

class H(BaseHTTPRequestHandler):
    def do_GET(s):
        import urllib.parse as up
        qs=up.parse_qs(up.urlparse(s.path).query)
        tok=qs.get('token',[None])[0]
        ok=(s.path=='${SUB_PATH}' or tok=='${SUB_TOKEN}')
        if ok:
            try:
                with CACHE_LOCK:
                    s.send_response(200); s.send_header('Content-Type','text/plain'); s.end_headers(); s.wfile.write(CACHE)
            except: s.send_response(500); s.end_headers()
        else: s.send_response(404); s.end_headers()
    def log_message(s,*a): pass

# 后台定时刷新（首次+每60秒）
refresh_cache()
def bg_refresh():
    while True:
        time.sleep(10); refresh_cache()
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
CFG=/etc/xray/config.json; LOG=/etc/xray/argo.log; CONF=/etc/xray/argox.conf
[ -f "$CONF" ] && . "$CONF"
NODE_NAME="${NODE_NAME:-ArgoX-Mini}"; MODE="${ARGO_MODE:-temp}"; FIXED="${ARGO_FIXED_DOMAIN:-}"
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
uuid=$($JQ -r '.inbounds[0].settings.clients[0].id//empty' "$CFG")
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
if [ -f /etc/xray/custom_links.txt ]; then
    while IFS= read -r cl; do
        [ -n "$cl" ] && links+="${cl}"$'\n'
    done < /etc/xray/custom_links.txt
fi
{ printf '%s' "$links" | base64 -w0 2>/dev/null || printf '%s' "$links" | base64 | tr -d '\n'; } > /etc/xray/sub.txt
SUBEOF
    chmod +x "${WORK_DIR}/sub_gen.sh"

    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/argox-sub << EOF
#!/sbin/openrc-run
name=argox-sub
command=$py
command_args="${WORK_DIR}/sub.py"
command_background=true
pidfile=/var/run/argox-sub.pid
EOF
        chmod +x /etc/init.d/argox-sub
        rc-update add argox-sub default 2>/dev/null || true
        rc-service argox-sub restart 2>/dev/null || true
    else
        cat > /etc/systemd/system/argox-sub.service << EOF
[Unit]
Description=ArgoX Subscription Server
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
        systemctl enable argox-sub 2>/dev/null || true
        systemctl restart argox-sub 2>/dev/null || true
    fi
}

stop_sub_server() {
    if [ "$IS_ALPINE" = 1 ]; then
        rc-service argox-sub stop 2>/dev/null
        rc-update del argox-sub default 2>/dev/null
        rm -f /etc/init.d/argox-sub
    else
        systemctl stop argox-sub 2>/dev/null; systemctl disable argox-sub 2>/dev/null
        rm -f /etc/systemd/system/argox-sub.service
    fi
    rm -f "${WORK_DIR}/sub.py" "${WORK_DIR}/sub_gen.sh" "${WORK_DIR}/sub.txt"
    systemctl daemon-reload 2>/dev/null || true
}

#==============================================================================
# 状态 & 摘要
#==============================================================================
get_status() {
    if [ "$IS_ALPINE" = 1 ]; then
        (rc-service xray status 2>/dev/null | grep -qE "started|crashed" || pgrep -x xray &>/dev/null) && { XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"; } || { XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"; }
        (rc-service argox-tunnel status 2>/dev/null | grep -qE "started|crashed" || pgrep -f 'argo.*tunnel' &>/dev/null) && { TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"; } || { TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"; }
    else
        systemctl is-active xray 2>/dev/null && { XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"; } || { XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"; }
        systemctl is-active argox-tunnel 2>/dev/null && { TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"; } || { TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"; }
    fi
}
get_proto_summary() {
    local s="VL-Argo VM-Argo"
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && s="$s SS"
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && s="$s Reality"
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
    echo -e "${purple}║${re}       ${white}ArgoX-Mini · ${NODE_NAME}${re}"
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

    if grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && [ -n "$ip" ]; then
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

    if grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && [ -n "$ip" ]; then
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
    [ -n "$su" ] && { echo ""; echo -e "  ${purple}━━━ 📡 订阅链接 ━━━${re}"; echo -e "  ${white}${su}${re}"; echo -e "  ${yellow}💡 客户端填入 → 更新订阅 → 全部节点一键导入，重启自动刷新域名${re}"; }
}

#==============================================================================
# 服务控制
#==============================================================================
start_services() { yellow_msg "启动..."; systemctl start xray argox-tunnel 2>/dev/null; sleep 2; get_status; echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"; green_msg "完成"; }
stop_services()  { yellow_msg "停止..."; systemctl stop xray argox-tunnel 2>/dev/null; sleep 1; get_status; echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"; red_msg "已停止"; }
restart_services() { yellow_msg "重启..."; rm -f "$TUNNEL_LOG"; systemctl restart xray argox-tunnel 2>/dev/null; sleep 3; get_status; local d; d=$(get_argo_domain); echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"; green_msg "完成"; [ -n "$d" ] && { echo -e "  域名: ${purple}${d}${re}"; LAST_ARGO_DOMAIN="$d"; save_conf; }; }

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
        echo -e "  ${green}6${re}. 增删协议 (需重装)"
        echo -e "  ${green}7${re}. 查看节点链接"
        echo -e "  ${green}8${re}. 刷新 Argo 域名"
        echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            1) read -p "  新名称 [${NODE_NAME}]: " n; [ -n "$n" ] && NODE_NAME="$n"; save_conf; green_msg "已更新: ${NODE_NAME}" ;;
            2) local nu; read -p "  新 UUID (回车生成): " nu; [ -z "$nu" ] && nu=$(cat /proc/sys/kernel/random/uuid)
               jq --arg u "$nu" '(.inbounds[].settings.clients[]?|select(.id)|.id)|=$u' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
               UUID_CUSTOM="$nu"; save_conf; systemctl restart xray 2>/dev/null; green_msg "UUID 已更新！${nu}" ;;
            3) switch_argo_tunnel ;;
            4) echo ""; for i in "${!SS_METHODS[@]}"; do echo -e "  ${green}$((i+1))${re}. ${SS_METHODS[$i]}"; done; echo ""
               read -p "  选择 [默认 aes-256-gcm]: " sm; [ -n "$sm" ] && SS_METHOD="${SS_METHODS[$((sm-1))]:-$SS_METHOD}"
               save_conf; green_msg "SS: ${SS_METHOD}" ;;
            5) echo ""; for i in "${!REALITY_SNIS[@]}"; do echo -e "  ${green}$((i+1))${re}. ${REALITY_SNIS[$i]}"; done; echo ""
               read -p "  选择 [默认 www.amazon.com]: " rs; [ -n "$rs" ] && REALITY_SNI="${REALITY_SNIS[$((rs-1))]:-$REALITY_SNI}"
               save_conf; green_msg "Reality SNI: ${REALITY_SNI}" ;;
            6) do_install; break ;;
            7) show_node ;; 8) restart_services ;; 0) return ;; *) red_msg "无效" ;;
        esac; read -p "  按回车继续..." -r
    done
}

#==============================================================================
# Argo 隧道切换
#==============================================================================
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
            cat > /etc/init.d/argox-tunnel << EOF
#!/sbin/openrc-run
name=argox-tunnel
command=${WORK_DIR}/argo
command_args="tunnel --edge-ip-version auto --no-autoupdate run --token ${ARGO_AUTH}"
command_background=true
pidfile=/var/run/argox-tunnel.pid
EOF
        else
            cat > "${WORK_DIR}/argox-tunnel.sh" << EOF
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
            chmod +x "${WORK_DIR}/argox-tunnel.sh"
            cat > /etc/init.d/argox-tunnel << EOF
#!/sbin/openrc-run
name=argox-tunnel
command=${WORK_DIR}/argox-tunnel.sh
command_background=true
pidfile=/var/run/argox-tunnel.pid
EOF
        fi
        chmod +x /etc/init.d/argox-tunnel
        return
    fi
    if [ "$1" = "fixed-token" ]; then
        cat > /etc/systemd/system/argox-tunnel.service << EOF
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
        cat > /etc/systemd/system/argox-tunnel.service << EOF
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
        echo -e "  ${green}2${re}. Shadowsocks ${cyan}[$( [ "$ENABLE_SS" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     AEAD/2022 加密，需开放端口，轻量高速"
        echo ""
        echo -e "  ${yellow}📋 当前: ${green}${sum}${re}"
        echo -e "  ${yellow}💡 输 1/2 切换勾选，输 0 进入端口配置${re}"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  (1/2=切换 / 0=下一步): " c
        case "$c" in
            1) ENABLE_REALITY=$((1-ENABLE_REALITY)); continue ;;
            2) ENABLE_SS=$((1-ENABLE_SS)); continue ;;
            0)
                echo ""
                [ "$ENABLE_REALITY" = 1 ] && { local rp; rp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Reality 端口 [随机 ${rp}]: ${re}"; read ri; REALITY_PORT="${ri:-$rp}"; echo -e "  → ${green}${REALITY_PORT}${re}"; }
                [ "$ENABLE_SS" = 1 ] && { local sp; sp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Shadowsocks 端口 [随机 ${sp}]: ${re}"; read si; SS_PORT="${si:-$sp}"; echo -e "  → ${green}${SS_PORT}${re}"; }
                echo ""
                echo -e "  ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo -e "  ${white}即将安装:${re}  Argo: VLESS+VMess"
                [ "$ENABLE_REALITY" = 1 ] && echo -e "  Reality: 端口 ${green}${REALITY_PORT}${re}  (UUID/SNI/密钥 自动生成)"
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
    echo -e " ${purple}║${re}  ${white}ArgoX-Mini · 交互式安装向导${re}              ${purple}║${re}"
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
    echo -e " ${purple}║${re}   ${white}ArgoX-Mini · 部署中...${re}                    ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

    yellow_msg "[1/6] 清理..."
    systemctl stop xray argox-tunnel 2>/dev/null; pkill -9 nginx 2>/dev/null; systemctl stop nginx 2>/dev/null; systemctl disable nginx 2>/dev/null; green_msg "  完成"

    yellow_msg "[2/6] 依赖..."
    if command -v apt &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof openssl
    elif command -v yum &>/dev/null; then yum install -y -q jq unzip curl lsof openssl
    elif command -v dnf &>/dev/null; then dnf install -y -q jq unzip curl lsof openssl
    elif command -v apk &>/dev/null; then apk update -q && apk add -q jq unzip curl lsof openssl; fi; green_msg "  完成"

    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG CF_ARCH; ARCH_ARG=$(detect_arch); CF_ARCH=$(cf_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/6] 下载..."
    curl -sLo "${WORK_DIR}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${WORK_DIR}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
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
    if [ "$ENABLE_SS" = 1 ]; then [ "$SS_PORT" = "0" ] && SS_PORT=$(shuf -i 10000-60000 -n 1); port_in_use "$SS_PORT" && SS_PORT=$(find_free_port "$SS_PORT"); fi

    local UUID; UUID="${UUID_CUSTOM:-$(cat /proc/sys/kernel/random/uuid)}"
    local SS_PASS
    [[ "$SS_METHOD" =~ 2022 ]] && SS_PASS=$(gen_ss2022_pass "$SS_METHOD") || SS_PASS="$UUID"
    [ -z "$SS_PASS" ] && SS_PASS="$UUID"
    green_msg "  完成"

    yellow_msg "[5/6] 生成配置..."
    # 重装时保留已有 SS/Reality inbound（解耦 Argo 和可选协议）
    local saved_inbounds=""
    if [ -f "$CONFIG_FILE" ]; then
        saved_inbounds=$(jq -c '[.inbounds[] | select(.tag=="reality" or .tag=="ss")]' "$CONFIG_FILE" 2>/dev/null)
        [ "$saved_inbounds" = "[]" ] && saved_inbounds=""
    fi
    # 重装时关掉可选协议（下面会从保存的 merge 回来，避免重复）
    [ -n "$saved_inbounds" ] && { ENABLE_REALITY=0; ENABLE_SS=0; }
    build_xray_config "$UUID" "$SS_PASS"
    # 合并回已保存的 inbound
    if [ -n "$saved_inbounds" ]; then
        jq --argjson saved "$saved_inbounds" '.inbounds += $saved' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="reality")' &>/dev/null && ENABLE_REALITY=1
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="ss")'       &>/dev/null && ENABLE_SS=1
    fi
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
    systemctl enable xray argox-tunnel 2>/dev/null; systemctl restart xray argox-tunnel; sleep 5; green_msg "  完成"

    cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
T=$(mktemp /tmp/argox.XXXXXX)
curl -sLo "$T" https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh
bash "$T"; rm -f "$T"
ARGOWRAP
    chmod +x "$SCRIPT_PATH"; save_conf

    local hd ip; [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN" || hd=$(get_argo_domain)
    [ -z "$hd" ] && [ "$ARGO_MODE" != "fixed-token" ] && { sleep 3; hd=$(get_argo_domain); }
    [ -n "$hd" ] && LAST_ARGO_DOMAIN="$hd" && save_conf; ip=$(get_ip)
    start_sub_server

    echo ""; echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}🎉 部署成功 · ${NODE_NAME}${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""; echo -e "  ${cyan}管理${re}: ${green}argov${re}    ${cyan}名称${re}: ${white}${NODE_NAME}${re}    ${cyan}UUID${re}: ${purple}${UUID}${re}"; echo ""

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
    echo -e "  ${yellow}📋${re} argov    ${yellow}💡${re} 复制链接 → 客户端导入"
}

#==============================================================================
# 构建 config.json
#==============================================================================
build_xray_config() {
    local uuid="$1" ss_pass="$2" inbounds fallbacks
    inbounds='['
    fallbacks='{"path":"/vmess-argo","dest":'"${VMESS_WS_PORT}"'},{"path":"/vless-argo","dest":'"${VLESS_WS_PORT}"'},{"dest":'"${VLESS_WS_PORT}"'}'

    # 1. Argo 路由入口
    inbounds+='{"port":'"${ARGO_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"argo-in","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none","fallbacks":['"${fallbacks}"']},"streamSettings":{"network":"tcp"}}'
    # 2. VLESS WS
    inbounds+=',{"port":'"${VLESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"vless-ws","settings":{"clients":[{"id":"'"${uuid}"'"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}}}'
    # 3. VMess WS
    inbounds+=',{"port":'"${VMESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vmess","tag":"vmess-ws","settings":{"clients":[{"id":"'"${uuid}"'","alterId":0}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-argo"}}}'
    # 4. Reality (opt)
    [ "$ENABLE_REALITY" = 1 ] && inbounds+=',{"port":'"${REALITY_PORT}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${REALITY_SNI}"':443","serverNames":["'"${REALITY_SNI}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":["'"${REALITY_SHORTID}"'"],"fingerprint":"chrome"}},"sniffing":{"enabled":true,"destOverride":["http","tls"],"routeOnly":true}}'
    # 5. SS (opt)
    [ "$ENABLE_SS" = 1 ] && inbounds+=',{"port":'"${SS_PORT}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"}}'
    inbounds+=']'

    cat > "$CONFIG_FILE" << XRAYCONF
{
  "current_cdn": "${CDN_DOMAIN}",
  "current_cdn_port": ${CDN_PORT},
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": ${inbounds},
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
XRAYCONF
}

#==============================================================================
# 管理节点 (添加/编辑/删除)
#==============================================================================
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
            a1) [ "$has_reality" = 0 ] && add_single_protocol "reality" ;;
            a2) [ "$has_ss" = 0 ] && add_single_protocol "ss" ;;
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
            new_inbound='{"port":'"${r_port}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${r_sni}"':443","serverNames":["'"${r_sni}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":['"${sid_val}"'],"fingerprint":"'"${r_fp}"'"}},"sniffing":{"enabled":true,"destOverride":["http","tls"],"routeOnly":true}}'
            REALITY_PORT="$r_port"; REALITY_SNI="$r_sni"; ENABLE_REALITY=1 ;;
    esac
    jq --argjson i "$new_inbound" '.inbounds+=[$i]' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
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

#==============================================================================
# 主菜单
#==============================================================================
main_menu() {
    load_conf
    while true; do
        get_status; clear
        local uuid_short="未安装" hd=""
        [ -f "$CONFIG_FILE" ] && uuid_short="$(get_uuid | cut -c1-12)..."
        [ "$TUNNEL_RAW" = "running" ] && hd=$(get_argo_domain)
        [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"

        logo
        echo -e "  ${yellow}▶${re} 命令行输入 ${green}argov${re} 可随时启动本面板"
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}ArgoX-Mini  纯净版隧道管理面板${re}              ${purple}║${re}"
        echo -e " ${purple}║${re}     ${cyan}$(get_proto_summary)${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  名称 : ${white}${NODE_NAME}${re}    Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"
        echo -e "  UUID : ${cyan}${uuid_short}${re}"
        [ -n "$hd" ] && echo -e "  域名 : ${green}${hd}${re}"
        echo -e "  CDN  : ${green}$(get_cdn):$(get_cdn_port)${re}"
        echo ""
        echo -e " ${purple}───────────────── 节点管理 ─────────────────${re}"
        echo -e "  ${green}1${re}. 查看节点链接     ${green}2${re}. 更换优选域名/线路"
        echo -e "  ${green}3${re}. 修改配置         ${cyan}a${re}. 管理节点 (添加/编辑/删除)"
        echo ""
        echo -e " ${purple}───────────────── 服务控制 ─────────────────${re}"
        echo -e "  ${green}4${re}. 启动    ${red}5${re}. 停止    ${yellow}6${re}. 重启/恢复 (仅Argo,不动SS/Reality)"
        echo ""
        echo -e " ${purple}───────────────── 系统维护 ─────────────────${re}"
        echo -e "  ${yellow}7${re}. 重新安装 (保留配置)    ${cyan}8${re}. 更新    ${red}9${re}. 卸载"
        echo ""
        echo -e "  ${cyan}0${re}. 退出   ${purple}w${re}. WARP分流 (SOCKS5 / IPv6 切换)"
        echo -e " ${purple}────────────────────────────────────────────${re}"
        read -p "  请输入 (0-9 / a / w): " c
        case "$c" in
            1) show_node; read -p "  按回车返回..." -r ;;
            2) edit_cdn; read -p "  按回车返回..." -r ;;
            3) change_config ;;
            a|A) manage_protocols ;;
            4) start_services; sleep 1 ;; 5) stop_services; sleep 1 ;; 6) restart_services; sleep 1 ;;
            7) echo -ne "  ${yellow}重新安装? (y/n): ${re}"; read cf
               [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { load_conf; do_install; }; read -p "  按回车返回..." -r ;;
            8) yellow_msg "拉取最新版..."
               local utmp; utmp=$(mktemp /tmp/argox.XXXXXX)
               curl -sLo "$utmp" https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh && bash "$utmp" && rm -f "$utmp"
               clear; continue ;;
            9) echo -ne "  ${red}⚠ 确定卸载? (y/n): ${re}"; read cf
               if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                   stop_sub_server 2>/dev/null
                   systemctl stop xray argox-tunnel 2>/dev/null; systemctl disable xray argox-tunnel 2>/dev/null
                   rm -rf "$WORK_DIR"; rm -f /etc/systemd/system/xray.service /etc/systemd/system/argox-tunnel.service /etc/systemd/system/argox-sub.service /etc/init.d/xray /etc/init.d/argox-tunnel "$SCRIPT_PATH" "${WORK_DIR}/argox-tunnel.sh"
                   systemctl daemon-reload; green_msg "卸载完成。"; fi ;;
            w|W) warp_menu ;;
            0) clear; break ;;
            *) red_msg "无效 (0-9 / a / w)"; sleep 1 ;;
        esac
    done
}

load_conf
[ ! -f "$CONFIG_FILE" ] && interactive_install
main_menu
