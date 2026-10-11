#!/usr/bin/env bash
#==============================================================================
# ArgoV — Xray + Sing-box 双核代理管理脚本
# VLESS + VMess (Argo)  |  Shadowsocks  |  VLESS Reality  |  Hysteria2
# 零公网暴露(Argo模式) · 无 Caddy/Nginx
#==============================================================================

# --- 颜色 ---
re="\033[0m"; red="\e[1;31m"; green="\e[1;32m"; yellow="\e[1;33m"
purple="\e[1;35m"; cyan="\e[1;36m"; blue="\e[1;34m"; white="\e[1;37m"
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
CDN_DEFAULT="xx.cloudflare.182682.xyz"

# --- Sing-box 常量 ---
SB_WORK_DIR="/etc/sing-box"
SB_CONFIG_FILE="${SB_WORK_DIR}/config.json"

# --- 端口 ---
ARGO_PORT="${ARGO_PORT:-8080}"
VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
CDN_PORT="${CDN_PORT:-443}"
REALITY_PORT="${REALITY_PORT:-0}"
HY2_PORT="${HY2_PORT:-0}"
HY2_MPORT="${HY2_MPORT:-}"
HY2_CONGESTION="${HY2_CONGESTION:-}"
HY2_UP_MBPS="${HY2_UP_MBPS:-}"
HY2_DOWN_MBPS="${HY2_DOWN_MBPS:-}"
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
REALITY_SNIS=("www.tesla.com" "www.nvidia.com" "www.amazon.com" "www.ebay.com"
              "www.paypal.com" "aws.amazon.com" "addons.mozilla.org" "www.microsoft.com")
REALITY_SNI="${REALITY_SNI:-www.tesla.com}"
REALITY_FP="${REALITY_FP:-chrome}"
HY2_SNI="${HY2_SNI:-}"
HY2_CERT_FILE="${HY2_CERT_FILE:-/etc/xray/argov-hy2.crt}"
HY2_KEY_FILE="${HY2_KEY_FILE:-/etc/xray/argov-hy2.key}"

# --- CDN 池 ---
declare -A CDN_DOMAINS
CDN_DOMAINS[1]="xx.cloudflare.182682.xyz (三网通用·默认)"
CDN_DOMAINS[2]="bestcf.top (三网通用·优选站)"
CDN_DOMAINS[3]="cdn.31514926.xyz (三网通用)"
CDN_DOMAINS[4]="skk.moe (三网通用·泛用测速)"
CDN_DOMAINS[5]="ip.sb (三网通用·IP检测站)"
CDN_DOMAINS[6]="time.is (三网通用·时间站)"
CDN_DOMAINS[7]="cfip.xxxxxxxx.tk (三网通用)"
CDN_DOMAINS[8]="cf.090227.xyz (三网通用)"
CDN_DOMAINS[9]="yidong.19931101.xyz (移动专线)"
CDN_DOMAINS[10]="liantong.19931101.xyz (联通专线)"
CDN_DOMAINS[11]="dianxin.19931101.xyz (电信专线)"
CDN_DOMAINS[12]="cdn.2020111.xyz (综合优选)"
CDN_DOMAINS[13]="xn--b6gac.eu.org (综合优选·中东)"
CDN_DOMAINS[14]="cdns.doon.eu.org (综合优选·Doorn)"

#==============================================================================
# 工具
#==============================================================================
# MODULE: platform and filesystem helpers
# 零内存端口检测: /proc/net/* 无需外部进程
port_in_use_tcp() {
    local p; p=$(printf '%04X' "$1" 2>/dev/null) || return 1
    grep -qE "^[[:space:]]*[0-9]+:[[:space:]]*[0-9A-F]+:${p}[[:space:]]+[0-9A-F]+:0000[[:space:]]+0A" /proc/net/tcp /proc/net/tcp6 2>/dev/null
}
port_in_use_udp() {
    local p; p=$(printf '%04X' "$1" 2>/dev/null) || return 1
    grep -qE "^[[:space:]]*[0-9]+:[[:space:]]*[0-9A-F]+:${p}[[:space:]]+[0-9A-F]+:0000[[:space:]]+07" /proc/net/udp /proc/net/udp6 2>/dev/null
}
port_in_use() { port_in_use_tcp "$1"; }
port_in_use_any() { port_in_use_tcp "$1" || port_in_use_udp "$1"; }
find_free_port() { local p="$1"; while is_port "$p"; do port_in_use "$p" || { echo "$p"; return 0; }; p=$((10#$p+1)); done; return 1; }
find_free_any_port() { local p="$1"; while is_port "$p"; do port_in_use_any "$p" || { echo "$p"; return 0; }; p=$((10#$p+1)); done; return 1; }
detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "64" ;; i686|i386) echo "32" ;;
        aarch64|arm64) echo "arm64-v8a" ;; armv7l) echo "arm32-v7a" ;; *) echo "" ;; esac
}
detect_sb_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;; aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;; i686|i386) echo "386" ;; *) echo "amd64" ;; esac
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
get_uuid()   { jq -r 'first(.inbounds[]? | (.settings.clients // .settings.users // [])[]? | .id // .auth // empty) // empty' "$CONFIG_FILE" 2>/dev/null; }
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
normalize_xray_reality_config() {
    [ -f "$CONFIG_FILE" ] || return 0
    command -v jq >/dev/null 2>&1 || return 1
    local legacy_pub
    legacy_pub=$(jq -r '.inbounds[]?|select(.tag=="reality")|.streamSettings.realitySettings.publicKey//empty' "$CONFIG_FILE" 2>/dev/null | head -n 1)
    [ -z "${REALITY_PUB:-}" ] && [ -n "$legacy_pub" ] && REALITY_PUB="$legacy_pub"
    jq '(.inbounds // []) |= map(
        if .tag == "reality" and (.streamSettings.realitySettings? != null) then
            .streamSettings.realitySettings |= (
                if ((has("target") | not) and has("dest")) then .target = .dest else . end
                | del(.dest, .publicKey, .fingerprint)
            )
        else . end
    )' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv -f "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}
is_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
is_port_range() {
    [[ "$1" =~ ^([0-9]+)-([0-9]+)$ ]] || return 1
    local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
    is_port "$start" && is_port "$end" && [ "$start" -le "$end" ]
}

# Shared forms keep first installation, adding and editing consistent. EOF/cancel
# returns to the caller; invalid input is never silently replaced by a random value.
normalize_domain() {
    local value="$1" label
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value,,}"
    value="${value#https://}"; value="${value#http://}"; value="${value%/}"
    [[ "$value" == *.* && "$value" != *..* && "$value" != .* && "$value" != *. ]] || return 1
    [ "${#value}" -le 253 ] || return 1
    local -a labels
    IFS=. read -r -a labels <<< "$value"
    for label in "${labels[@]}"; do
        [ "${#label}" -le 63 ] && [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
    done
    [[ "${labels[${#labels[@]}-1]}" =~ [a-z] ]] || return 1
    printf '%s' "$value"
}
prompt_domain() {
    local _pd_target="$1" _pd_default="$2" _pd_label="$3" _pd_input _pd_value
    while true; do
        printf '  %s [%s，0 返回]: ' "$_pd_label" "${_pd_default:-必填}"
        IFS= read -r _pd_input || return 1
        [[ "${_pd_input,,}" == "cancel" || "$_pd_input" == "0" ]] && return 1
        _pd_value=$(normalize_domain "${_pd_input:-$_pd_default}") || {
            red_msg "请输入有效域名，如 example.com；可粘贴 https://example.com/，不要带路径或端口。"
            continue
        }
        printf -v "$_pd_target" '%s' "$_pd_value"
        return 0
    done
}
configured_port_conflict() {
    local candidate="$1" owner="$2" last="${3:-$1}" key value range start end
    for key in ARGO_PORT VLESS_WS_PORT VMESS_WS_PORT SUB_PORT REALITY_PORT HY2_PORT SS_PORT \
        SB_HY2_PORT SB_TUIC_PORT SB_ANYTLS_PORT SB_REALITY_PORT SB_SS_PORT; do
        [ "$key" = "$owner" ] && continue
        case "$key" in
            # The Xray template reserves these internal listeners even when
            # the Cloudflare tunnel is skipped.
            ARGO_PORT|VLESS_WS_PORT|VMESS_WS_PORT) : ;;
            REALITY_PORT) [ "${ENABLE_REALITY:-0}" != 1 ] && continue ;;
            HY2_PORT) [ "${ENABLE_HY2:-0}" != 1 ] && continue ;;
            SS_PORT) [ "${ENABLE_SS:-0}" != 1 ] && continue ;;
            SB_*_PORT) local enabled="${key%_PORT}_ENABLE"; [ "${!enabled}" != true ] && continue ;;
        esac
        value="${!key}"
        is_port "$value" && (( 10#$candidate <= 10#$value && 10#$last >= 10#$value )) && return 0
    done
    for key in HY2_PORT SB_HY2_PORT; do
        [ "$key" = "$owner" ] && continue
        range=""
        if [ "$key" = HY2_PORT ] && [ "${ENABLE_HY2:-0}" = 1 ]; then range="${HY2_MPORT:-}"; fi
        if [ "$key" = SB_HY2_PORT ] && [ "${SB_HY2_ENABLE:-false}" = true ] && [ "${SB_HY2_HOP_ENABLE:-false}" = true ]; then
            range="${SB_HY2_HOP_START}-${SB_HY2_HOP_END}"
        fi
        is_port_range "$range" || continue
        start="${range%-*}"; end="${range#*-}"
        (( 10#$candidate <= 10#$end && 10#$last >= 10#$start )) && return 0
    done
    return 1
}
prompt_port() {
    local _pp_target="$1" _pp_default="$2" _pp_label="$3" _pp_owner="${4:-$1}"
    local _pp_current="${5:-}" _pp_input _pp_value
    while true; do
        printf '  %s [%s，0 返回]: ' "$_pp_label" "$_pp_default"
        IFS= read -r _pp_input || return 1
        [[ "$_pp_input" == 0 || "${_pp_input,,}" == cancel ]] && return 1
        _pp_value="${_pp_input:-$_pp_default}"
        is_port "$_pp_value" || { red_msg "端口必须为 1–65535 的整数，请重新输入。"; continue; }
        _pp_value=$((10#$_pp_value))
        configured_port_conflict "$_pp_value" "$_pp_owner" && { red_msg "端口已被其他已选协议或订阅使用，请重新输入。"; continue; }
        if [ "$_pp_value" != "$_pp_current" ] && port_in_use_any "$_pp_value"; then
            red_msg "端口已被其他服务占用，请重新输入。"; continue
        fi
        printf -v "$_pp_target" '%s' "$_pp_value"
        return 0
    done
}
prompt_positive_integer() {
    local _pi_target="$1" _pi_default="$2" _pi_label="$3" _pi_input _pi_value
    while true; do
        printf '  %s [%s，cancel 返回]: ' "$_pi_label" "$_pi_default"
        IFS= read -r _pi_input || return 1
        [ "${_pi_input,,}" = cancel ] && return 1
        _pi_value="${_pi_input:-$_pi_default}"
        [[ "$_pi_value" =~ ^[0-9]{1,7}$ ]] && (( 10#$_pi_value >= 1 && 10#$_pi_value <= 1000000 )) || {
            red_msg "请输入 1–1000000 的整数（单位 Mbps）。"; continue
        }
        printf -v "$_pi_target" '%s' "$((10#$_pi_value))"
        return 0
    done
}
prompt_hy2_congestion() {
    local _hc_mode_var="$1" _hc_up_var="$2" _hc_down_var="$3" _hc_core="$4"
    local _hc_mode="${5:-bbr}" _hc_up="${6:-}" _hc_down="${7:-}" _hc_input
    echo "  拥塞控制（服务端配置）："
    echo "    1. BBR：自动估计带宽（默认）"
    echo "    2. Brutal：按带宽协商，请填写实际可用带宽"
    if [ "$_hc_core" = xray ]; then
        echo "    3. Reno：较保守的拥塞控制"
        echo "    4. 内核默认：由客户端协商带宽"
        [ "$_hc_mode" = cubic ] && _hc_mode=auto
    else
        echo "    3. 客户端协商：允许客户端选择 BBR / Brutal"
        [ "$_hc_mode" = reno ] && { yellow_msg "旧 Reno 选项没有写入 Sing-box 配置；请重新选择有效模式。"; _hc_mode=bbr; }
    fi
    while true; do
        printf '  算法 [%s，0 返回，可输入编号或名称]: ' "$_hc_mode"
        IFS= read -r _hc_input || return 1
        case "${_hc_input:-$_hc_mode}" in
            0|cancel|CANCEL) return 1 ;;
            1|bbr|BBR) _hc_mode=bbr; _hc_up=""; _hc_down=""; break ;;
            2|brutal|Brutal|BRUTAL) _hc_mode=brutal; break ;;
            3)
                if [ "$_hc_core" = xray ]; then _hc_mode=reno; else _hc_mode=auto; fi
                _hc_up=""; _hc_down=""; break ;;
            reno|Reno|RENO)
                [ "$_hc_core" = xray ] || { red_msg "当前 Sing-box HY2 不支持 Reno，请重新选择。"; continue; }
                _hc_mode=reno; _hc_up=""; _hc_down=""; break ;;
            4)
                [ "$_hc_core" = xray ] || { red_msg "无效选择。"; continue; }
                _hc_mode=auto; _hc_up=""; _hc_down=""; break ;;
            auto|AUTO) _hc_mode=auto; _hc_up=""; _hc_down=""; break ;;
            *) red_msg "无效选择，请输入已显示的编号或算法名称。" ;;
        esac
    done
    if [ "$_hc_mode" = brutal ]; then
        prompt_positive_integer _hc_up "${_hc_up:-100}" "服务器上传 Mbps（客户端的下载）" || return 1
        prompt_positive_integer _hc_down "${_hc_down:-200}" "服务器下载 Mbps（客户端的上传）" || return 1
        yellow_msg "Brutal 仍需客户端设置带宽；通用分享链接不能替客户端选择算法。"
    fi
    printf -v "$_hc_mode_var" '%s' "$_hc_mode"
    printf -v "$_hc_up_var" '%s' "$_hc_up"
    printf -v "$_hc_down_var" '%s' "$_hc_down"
}
udp_range_in_use() {
    local start="$1" end="$2" ignore="${3:-0}" file slot address rest port
    is_port "$ignore" && ignore=$((10#$ignore)) || ignore=0
    for file in /proc/net/udp /proc/net/udp6; do
        [ -r "$file" ] || continue
        while read -r slot address rest; do
            port="${address##*:}"
            [[ "$port" =~ ^[[:xdigit:]]{4}$ ]] || continue
            port=$((16#$port))
            [ "$port" = "$ignore" ] && continue
            (( port >= 10#$start && port <= 10#$end )) && return 0
        done < "$file"
    done
    return 1
}
default_hy2_hop_range() {
    local owner="$1" preferred=47000 start end
    [ "$owner" = SB_HY2_PORT ] && preferred=49000
    for start in "$preferred" {10000..64000..1000}; do
        end=$((start+1000))
        if ! configured_port_conflict "$start" "$owner" "$end" && ! udp_range_in_use "$start" "$end" "${!owner}"; then
            printf '%s-%s' "$start" "$end"
            return 0
        fi
    done
    red_msg "没有可用的默认跳跃范围，请先调整已选协议端口。" >&2
    return 1
}
prompt_hy2_hopping() {
    local _hh_target="$1" _hh_current="$2" _hh_owner="${3:-HY2_PORT}" _hh_input _hh_start _hh_end
    echo "  端口跳跃需放行整个 UDP 范围；跳跃间隔由客户端控制，Mihomo 订阅使用 30 秒。"
    while true; do
        printf '  跳跃范围 [%s，off 关闭，0 返回]: ' "${_hh_current:-关闭；如 47000-48000}"
        IFS= read -r _hh_input || return 1
        [ "$_hh_input" = 0 ] && return 1
        _hh_input="${_hh_input:-$_hh_current}"
        case "${_hh_input,,}" in off|"") printf -v "$_hh_target" '%s' ""; return 0 ;; cancel) return 1 ;; esac
        is_port_range "$_hh_input" || { red_msg "范围无效，应为 起始端口-结束端口，且起始不大于结束。"; continue; }
        _hh_start="${_hh_input%-*}"; _hh_end="${_hh_input#*-}"
        configured_port_conflict "$_hh_start" "$_hh_owner" "$_hh_end" && {
            red_msg "跳跃范围与其他协议、订阅端口或另一组 HY2 跳跃范围冲突，请重新输入。"; continue
        }
        udp_range_in_use "$_hh_start" "$_hh_end" "${!_hh_owner}" && {
            red_msg "跳跃范围内已有其他 UDP 监听，请更换范围，避免影响已有节点。"; continue
        }
        _hh_input="$((10#$_hh_start))-$((10#$_hh_end))"
        printf -v "$_hh_target" '%s' "$_hh_input"
        return 0
    done
}
prompt_choice() {
    local _pc_target="$1" _pc_default="$2" _pc_label="$3" _pc_input _pc_option _pc_index
    shift 3
    while true; do
        _pc_index=1
        for _pc_option in "$@"; do printf '    %s. %s\n' "$_pc_index" "$_pc_option"; _pc_index=$((_pc_index+1)); done
        printf '  %s [%s，0 返回]: ' "$_pc_label" "$_pc_default"
        IFS= read -r _pc_input || return 1
        [[ "$_pc_input" = 0 || "${_pc_input,,}" = cancel ]] && return 1
        _pc_input="${_pc_input:-$_pc_default}"; _pc_index=1
        for _pc_option in "$@"; do
            if [ "$_pc_input" = "$_pc_index" ] || [ "$_pc_input" = "$_pc_option" ]; then
                printf -v "$_pc_target" '%s' "$_pc_option"; return 0
            fi
            _pc_index=$((_pc_index+1))
        done
        red_msg "无效选择，请重新输入。"
    done
}
confirm_changes() {
    local answer
    while true; do
        printf '  %s [Y/n]: ' "$1"
        IFS= read -r answer || return 1
        case "${answer,,}" in ""|y|yes) return 0 ;; n|no|0|cancel) yellow_msg "已取消。"; return 1 ;; *) red_msg "请输入 y 或 n。" ;; esac
    done
}
replace_json_placeholder() {
    local file="$1" placeholder="$2" encoded
    encoded=$(jq -rn --arg value "$3" '$value | tojson') || return 1
    encoded="${encoded//\\/\\\\}"; encoded="${encoded//&/\\&}"; encoded="${encoded//|/\\|}"
    sed -i "s|\"$placeholder\"|$encoded|g" "$file"
}
build_hy2_inbound() {
    local listen_port="$1" sni="$2" auth="$3" email="${4:-argov-default}" mport="$5"
    local congestion="${6:-}" up_bw="${7:-}" down_bw="${8:-}"
    # 拼装 quicParams
    local qp=""
    [[ "$congestion" = auto || "$congestion" = cubic ]] && congestion=""
    [ -n "$congestion" ] && qp="${qp}\"congestion\":\"${congestion}\","
    [ "$congestion" = brutal ] && [ -n "$up_bw" ] && [ "$up_bw" != "0" ] && qp="${qp}\"brutalUp\":\"${up_bw} mbps\","
    [ "$congestion" = brutal ] && [ -n "$down_bw" ] && [ "$down_bw" != "0" ] && qp="${qp}\"brutalDown\":\"${down_bw} mbps\","
    [ -n "$mport" ] && qp="${qp}\"udpHop\":{\"ports\":\"${mport}\",\"interval\":30},"
    qp="${qp%,}"
    local fm=""
    [ -n "$qp" ] && fm=",\"finalmask\":{\"quicParams\":{${qp}}}"
    printf '%s' '{"port":'"${listen_port}"',"listen":"0.0.0.0","protocol":"hysteria","tag":"hy2","settings":{"version":2,"users":[{"auth":"'"${auth}"'","level":0,"email":"'"${email}"'"}],"clients":[{"auth":"'"${auth}"'","level":0,"email":"'"${email}"'"}]},"streamSettings":{"network":"hysteria","security":"tls","tlsSettings":{"alpn":["h3"],"serverName":"'"${sni}"'","certificates":[{"certificateFile":"'"${HY2_CERT_FILE}"'","keyFile":"'"${HY2_KEY_FILE}"'"}]},"hysteriaSettings":{"version":2,"udpIdleTimeout":60}'"$fm"'},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
}
disable_hy2_hop_rules() {
    local listen_port="${1:-$HY2_PORT}" mport dport
    if [ "$#" -ge 2 ]; then mport="$2"; else mport="$HY2_MPORT"; fi
    dport="${mport//-/:}"
    systemctl stop argov-hy2-hop 2>/dev/null || true
    systemctl disable argov-hy2-hop 2>/dev/null || true
    rc-service argov-hy2-hop stop 2>/dev/null || true
    rc-update del argov-hy2-hop default 2>/dev/null || true
    if [ -n "$listen_port" ] && [ -n "$mport" ] && command -v iptables >/dev/null 2>&1; then
        while iptables -t nat -C PREROUTING -p udp --dport "$dport" -j REDIRECT --to-ports "$listen_port" 2>/dev/null; do
            iptables -t nat -D PREROUTING -p udp --dport "$dport" -j REDIRECT --to-ports "$listen_port" 2>/dev/null || break
        done
    fi
    rm -f "${WORK_DIR}/hy2-hop.sh" /etc/systemd/system/argov-hy2-hop.service /etc/init.d/argov-hy2-hop 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}
clear_hy2_mport_config() {
    HY2_MPORT=""
    [ -f "$CONFIG_FILE" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq '(.inbounds[]|select(.tag=="hy2")|.streamSettings) |= (del(.finalmask.quicParams.udpHop) | if (.finalmask.quicParams == {}) then del(.finalmask.quicParams) else . end | if (.finalmask == {}) then del(.finalmask) else . end | del(.hysteriaSettings.quicParams))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}
apply_hy2_hop_rules() {
    local listen_port="$1" mport="$2" dport
    [ -z "$mport" ] && { disable_hy2_hop_rules "$listen_port" ""; return 0; }
    is_port "$listen_port" && is_port_range "$mport" || { red_msg "Invalid Hysteria2 port hopping range."; return 1; }
    dport="${mport//-/:}"
    command -v iptables >/dev/null 2>&1 || { yellow_msg "iptables not found; Hysteria2 port hopping rule was not installed."; return 1; }
    mkdir -p "$WORK_DIR" 2>/dev/null
    cat > "${WORK_DIR}/hy2-hop.sh" << EOF
#!/usr/bin/env bash
set -e
listen_port="${listen_port}"
dport="${dport}"
while iptables -t nat -C PREROUTING -p udp --dport "\$dport" -j REDIRECT --to-ports "\$listen_port" 2>/dev/null; do
    iptables -t nat -D PREROUTING -p udp --dport "\$dport" -j REDIRECT --to-ports "\$listen_port" 2>/dev/null || break
done
iptables -t nat -A PREROUTING -p udp --dport "\$dport" -j REDIRECT --to-ports "\$listen_port"
EOF
    chmod +x "${WORK_DIR}/hy2-hop.sh"
    "${WORK_DIR}/hy2-hop.sh" || return 1
    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/argov-hy2-hop << EOF
#!/sbin/openrc-run
name=argov-hy2-hop
command=${WORK_DIR}/hy2-hop.sh
command_background=false
EOF
        chmod +x /etc/init.d/argov-hy2-hop
        rc-update add argov-hy2-hop default 2>/dev/null || true
    else
        cat > /etc/systemd/system/argov-hy2-hop.service << EOF
[Unit]
Description=ArgoV Hysteria2 Port Hopping Rules
After=network.target firewalld.service ufw.service
[Service]
Type=oneshot
ExecStart=${WORK_DIR}/hy2-hop.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable argov-hy2-hop 2>/dev/null || true
    fi
}
build_singbox_config() {
    (
    mkdir -p "$SB_WORK_DIR" || return 1
    local relay_snapshot=""
    local sb_output="" TEMP_INBOUNDS=""
    trap '[ -z "$relay_snapshot" ] || rm -f "$relay_snapshot"; [ -z "$sb_output" ] || rm -f "$sb_output" "${sb_output}.cc" "${sb_output}.tmp"; [ -z "$TEMP_INBOUNDS" ] || rm -f "$TEMP_INBOUNDS"' EXIT
    if [ "${RELAY_ENABLED:-0}" = "1" ] && [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ]; then
        relay_snapshot=$(mktemp -t argov-sb-relay.XXXXXX) || return 1
        cp "$SB_CONFIG_FILE" "$relay_snapshot" || { red_msg "无法备份中继配置，已取消修改。"; return 1; }
    fi
    sb_sync_users || { red_msg "无法同步 Sing-box 用户配置，已取消修改。"; return 1; }

    sb_output=$(mktemp "${SB_CONFIG_FILE}.tmp.XXXXXX") || return 1
    TEMP_INBOUNDS=$(mktemp -t sbin.XXXXXX) || return 1
    > "$TEMP_INBOUNDS"
    local need_comma=false

    # === HY2 (singbox-deploy 同款模板) ===
    if [ "${SB_HY2_ENABLE:-false}" = "true" ] && [ -n "${SB_HY2_PORT:-}" ]; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_HY2'
    {
      "type": "hysteria2",
      "tag": "sb-hy2",
      "listen": "::",
      "listen_port": __SB_HY2_PORT__,
      "users": [ { "password": "__SB_HY2_PSK__" } ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "__SB_CERT_FILE__",
        "key_path": "__SB_KEY_FILE__"
      }
    }
INBOUND_HY2
        sed -i "s|__SB_HY2_PORT__|${SB_HY2_PORT}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_HY2_PSK__" "${SB_HY2_PSK:-}" || return 1
        sed -i "s|__SB_CERT_FILE__|${SB_HY2_CERT_FILE:-$SB_CERT_FILE}|g" "$TEMP_INBOUNDS"
        sed -i "s|__SB_KEY_FILE__|${SB_HY2_KEY_FILE:-$SB_KEY_FILE}|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi

    # === TUIC (singbox-deploy 同款模板) ===
    if [ "${SB_TUIC_ENABLE:-false}" = "true" ] && [ -n "${SB_TUIC_PORT:-}" ]; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_TUIC'
    {
      "type": "tuic",
      "tag": "sb-tuic",
      "listen": "::",
      "listen_port": __SB_TUIC_PORT__,
      "users": [ { "uuid": "__SB_TUIC_UUID__", "password": "__SB_TUIC_PSK__" } ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "__SB_CERT_FILE__",
        "key_path": "__SB_KEY_FILE__"
      }
    }
INBOUND_TUIC
        sed -i "s|__SB_TUIC_PORT__|${SB_TUIC_PORT}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_TUIC_UUID__" "${SB_TUIC_UUID:-}" || return 1
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_TUIC_PSK__" "${SB_TUIC_PSK:-}" || return 1
        sed -i "s|__SB_CERT_FILE__|${SB_CERT_FILE}|g" "$TEMP_INBOUNDS"
        sed -i "s|__SB_KEY_FILE__|${SB_KEY_FILE}|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi

    # === AnyTLS Reality (singbox-deploy 1:1 复刻) ===
    if [ "${SB_ANYTLS_ENABLE:-false}" = "true" ] && [ -n "${SB_ANYTLS_PORT:-}" ]; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_ANYTLS'
    {
      "type": "anytls",
      "tag": "sb-anytls",
      "listen": "::",
      "listen_port": __SB_ANYTLS_PORT__,
      "users": [ { "name": "__SB_ANYTLS_USER__", "password": "__SB_ANYTLS_PSK__" } ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "__SB_SNI__",
        "reality": {
          "enabled": true,
          "handshake": { "server": "__SB_SNI__", "server_port": 443 },
          "private_key": "__SB_REALITY_PRIV__",
          "short_id": ["__SB_REALITY_SID__"]
        }
      }
    }
INBOUND_ANYTLS
        sed -i "s|__SB_ANYTLS_PORT__|${SB_ANYTLS_PORT}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_ANYTLS_USER__" "${SB_ANYTLS_USER:-argov}" || return 1
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_ANYTLS_PSK__" "${SB_ANYTLS_PSK:-}" || return 1
        sed -i "s|__SB_SNI__|${SB_ANYTLS_SNI:-${SB_SNI:-addons.mozilla.org}}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_REALITY_PRIV__" "${SB_REALITY_PRIV:-}" || return 1
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_REALITY_SID__" "${SB_REALITY_SID:-}" || return 1
        need_comma=true
    fi

    # === VLESS Reality (singbox-deploy 1:1 复刻) ===
    if [ "${SB_REALITY_ENABLE:-false}" = "true" ] && [ -n "${SB_REALITY_PORT:-}" ]; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_VLESS'
    {
      "type": "vless",
      "tag": "sb-reality",
      "listen": "::",
      "listen_port": __SB_REALITY_PORT__,
      "users": [ { "uuid": "__SB_REALITY_UUID__", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "__SB_SNI__",
        "reality": {
          "enabled": true,
          "handshake": { "server": "__SB_SNI__", "server_port": 443 },
          "private_key": "__SB_REALITY_PRIV__",
          "short_id": ["__SB_REALITY_SID__"]
        }
      }
    }
INBOUND_VLESS
        sed -i "s|__SB_REALITY_PORT__|${SB_REALITY_PORT}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_REALITY_UUID__" "${UUID_CUSTOM:-$(get_uuid)}" || return 1
        sed -i "s|__SB_SNI__|${SB_REALITY_SNI:-${SB_SNI:-addons.mozilla.org}}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_REALITY_PRIV__" "${SB_REALITY_PRIV:-}" || return 1
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_REALITY_SID__" "${SB_REALITY_SID:-}" || return 1
        need_comma=true
    fi

    # === Shadowsocks (singbox-deploy 同款模板) ===
    if [ "${SB_SS_ENABLE:-false}" = "true" ] && [ -n "${SB_SS_PORT:-}" ]; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_SS'
    {
      "type": "shadowsocks",
      "tag": "sb-ss",
      "listen": "::",
      "listen_port": __SB_SS_PORT__,
      "method": "__SB_SS_METHOD__",
      "password": "__SB_SS_PSK__"
    }
INBOUND_SS
        sed -i "s|__SB_SS_PORT__|${SB_SS_PORT}|g" "$TEMP_INBOUNDS"
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_SS_METHOD__" "${SB_SS_METHOD:-${SS_METHOD:-aes-256-gcm}}" || return 1
        replace_json_placeholder "$TEMP_INBOUNDS" "__SB_SS_PSK__" "${SB_SS_PSK:-}" || return 1
        need_comma=true
    fi

    # 每用户独立 inbound (v2 流量配额)
    local per_user_need_comma; per_user_need_comma=$(sb_build_per_user_inbounds "$TEMP_INBOUNDS" "$need_comma")
    [ "$per_user_need_comma" = "true" ] && need_comma=true

    # 拼接最终 config.json
    cat > "$sb_output" <<'SBCONFIGHEAD'
{
  "log": { "level": "info", "timestamp": true },
  "ntp": { "enabled": true, "server": "time.apple.com", "server_port": 123, "interval": "30m" },
  "inbounds": [
SBCONFIGHEAD
    cat "$TEMP_INBOUNDS" >> "$sb_output"
    cat >> "$sb_output" <<'SBCONFIGTAIL'
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct-out" }
  ]
}
SBCONFIGTAIL


    # Both BBR and Brutal must reach the actual inbound, not only argov.conf.
    local sb_mode="${SB_HY2_CONGESTION:-bbr}" sb_up="${SB_HY2_UP_MBPS:-0}" sb_down="${SB_HY2_DOWN_MBPS:-0}"
    if [ "${SB_HY2_ENABLE:-false}" = true ]; then
        case "$sb_mode" in
            bbr|auto) sb_up=0; sb_down=0 ;;
            reno)
                sb_mode=auto; sb_up=0; sb_down=0
                yellow_msg "旧 Sing-box Reno 选项未实际生效，保留客户端协商模式；可在 HY2 编辑中重新选择。"
                ;;
            brutal) [[ "$sb_up" =~ ^[0-9]{1,7}$ && "$sb_down" =~ ^[0-9]{1,7}$ ]] && ((10#$sb_up > 0 && 10#$sb_down > 0)) || {
                red_msg "Hysteria2 Brutal 带宽无效，原配置未替换。"; rm -f "$sb_output" "$TEMP_INBOUNDS"; return 1;
            } ;;
            *) red_msg "Sing-box HY2 不支持该拥塞选项，请选择 BBR、Brutal 或客户端协商。"; rm -f "$sb_output" "$TEMP_INBOUNDS"; return 1 ;;
        esac
        jq --arg mode "$sb_mode" --argjson up "$((10#$sb_up))" --argjson down "$((10#$sb_down))" '
            .inbounds |= map(if .type=="hysteria2" then
                del(.up_mbps,.down_mbps,.ignore_client_bandwidth) |
                if $mode=="brutal" then .up_mbps=$up | .down_mbps=$down | .ignore_client_bandwidth=false
                elif $mode=="bbr" then .ignore_client_bandwidth=true else . end
            else . end)' "$sb_output" > "${sb_output}.cc" && mv "${sb_output}.cc" "$sb_output" || {
                rm -f "$sb_output" "${sb_output}.cc" "$TEMP_INBOUNDS"; return 1;
            }
        if [ "$sb_mode" = bbr ] && singbox_supports_bbr_profile; then
            jq --arg profile "${SB_HY2_BBR_PROFILE:-standard}" '(.inbounds[]|select(.type=="hysteria2")|.bbr_profile)=$profile' \
                "$sb_output" > "${sb_output}.cc" && mv "${sb_output}.cc" "$sb_output" || return 1
        fi
    fi

    # Protocol/user edits rebuild the generated Sing-box config. Carry the active
    # relay outbound and route across that rebuild so HY2 does not silently go direct.
    if [ -n "$relay_snapshot" ] && [ -s "$relay_snapshot" ]; then
        local sb_py; sb_py=$(py_bin)
        if [ -n "$sb_py" ]; then
            "$sb_py" - "$sb_output" "$relay_snapshot" << 'PYSBRELAYMERGE'
import json, os, sys

current_path, previous_path = sys.argv[1:3]
with open(current_path, "r", encoding="utf-8") as f:
    current = json.load(f)
with open(previous_path, "r", encoding="utf-8") as f:
    previous = json.load(f)

relay_outbounds = [o for o in previous.get("outbounds", [])
                   if o.get("tag") == "argov-relay"]
if relay_outbounds:
    current.setdefault("outbounds", [])
    current["outbounds"] = [o for o in current["outbounds"]
                            if o.get("tag") != "argov-relay"] + relay_outbounds
    old_route = previous.get("route", {})
    route = current.setdefault("route", {})
    relay_rules = [r for r in old_route.get("rules", [])
                   if r.get("outbound") == "argov-relay"]
    if any(r.get("domain") for r in relay_rules) and not any(
        r.get("action") == "sniff" for r in route.get("rules", [])
    ):
        route.setdefault("rules", []).insert(0, {"action": "sniff"})
    route["rules"] = relay_rules + [
        r for r in route.get("rules", []) if r.get("outbound") != "argov-relay"
    ]
    if old_route.get("final") == "argov-relay":
        route["final"] = "argov-relay"
    old_dns = previous.get("dns", {})
    old_servers = [s for s in old_dns.get("servers", [])
                   if s.get("tag") == "argov-relay-dns"]
    if old_servers:
        dns = current.setdefault("dns", {})
        dns.setdefault("servers", [])
        dns["servers"] = [s for s in dns["servers"]
                          if s.get("tag") != "argov-relay-dns"] + old_servers
    if old_route.get("default_domain_resolver") == "argov-relay-dns":
        current.setdefault("route", {})["default_domain_resolver"] = "argov-relay-dns"

tmp = current_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(current, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, current_path)
PYSBRELAYMERGE
            [ "$?" -ne 0 ] && { red_msg "无法保留 Sing-box 落地中继，原配置未替换。"; return 1; }
        else
            red_msg "保留中继配置需要 Python，原配置未替换。"; return 1
        fi
        rm -f "$relay_snapshot" 2>/dev/null || true
    fi
    rm -f "$TEMP_INBOUNDS" 2>/dev/null


    if ! jq empty "$sb_output" >/dev/null 2>&1; then
        red_msg "Sing-box 配置不是有效 JSON，原配置未替换。"; rm -f "$sb_output"; return 1
    fi
    if sb_is_installed; then
        local check_result
        check_result=$(sing-box check -c "$sb_output" 2>&1) || {
            red_msg "Sing-box 配置验证失败，原配置未替换："
            printf '%s\n' "$check_result"; rm -f "$sb_output"; return 1
        }
    fi
    chmod 600 "$sb_output"
    mv -f "$sb_output" "$SB_CONFIG_FILE"
    )
}

#==============================================================================
# v2: Sing-box 每用户端口分配 + 流量配额
#==============================================================================
sb_sync_users() {
    # 为所有非 default 用户分配独立 Sing-box 端口和凭证
    local py; py=$(py_bin); [ -z "$py" ] && return
    [ ! -f "$ARGOV_USERS_FILE" ] && return

    local hy2_base="${SB_HY2_PORT:-0}" tuic_base="${SB_TUIC_PORT:-0}"
    local anytls_base="${SB_ANYTLS_PORT:-0}" reality_base="${SB_REALITY_PORT:-0}" ss_base="${SB_SS_PORT:-0}"

    begin_argov_lock
    "$py" - "$ARGOV_USERS_FILE" "$hy2_base" "$tuic_base" "$anytls_base" "$reality_base" "$ss_base" "${SB_SS_METHOD:-${SS_METHOD:-aes-256-gcm}}" << 'PYEOF'
import base64, binascii, json, os, sys

users_file = sys.argv[1]
hy2_base  = int(sys.argv[2] or 0)
tuic_base = int(sys.argv[3] or 0)
anytls_base = int(sys.argv[4] or 0)
reality_base = int(sys.argv[5] or 0)
ss_base   = int(sys.argv[6] or 0)
ss_method = sys.argv[7]

with open(users_file, 'r') as f:
    data = json.load(f)

idx = 0
for u in data.get('users', []):
    if u.get('name') == 'default':
        continue
    idx += 1
    u.setdefault('sb_ports', {})
    u.setdefault('sb_creds', {})

    # HY2 每用户端口不分配 — 跳变兼容性, 仅共享端口可用
    if tuic_base > 0 and 'tuic' not in u['sb_ports']:
        u['sb_ports']['tuic'] = tuic_base + 10 + idx
        u['sb_creds'].setdefault('tuic_uuid', __import__('uuid').uuid4().hex)
        u['sb_creds'].setdefault('tuic_pass', os.urandom(16).hex())

    if anytls_base > 0 and 'anytls' not in u['sb_ports']:
        u['sb_ports']['anytls'] = anytls_base + 10 + idx
        u['sb_creds'].setdefault('anytls_pass', os.urandom(16).hex())

    if reality_base > 0 and 'reality' not in u['sb_ports']:
        u['sb_ports']['reality'] = reality_base + 10 + idx

    if ss_base > 0 and 'ss' not in u['sb_ports']:
        u['sb_ports']['ss'] = ss_base + 10 + idx
    if ss_base > 0:
        password = u['sb_creds'].get('ss_pass', '')
        if ss_method.startswith('2022-'):
            key_size = 16 if '128' in ss_method else 32
            try:
                valid_key = len(base64.b64decode(password, validate=True)) == key_size
            except (ValueError, binascii.Error):
                valid_key = False
            if not valid_key:
                u['sb_creds']['ss_pass'] = base64.b64encode(os.urandom(key_size)).decode()
        elif not password:
            u['sb_creds']['ss_pass'] = os.urandom(16).hex()

with open(users_file + '.tmp', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
os.replace(users_file + '.tmp', users_file)
PYEOF
    local rc=$?
    end_argov_lock
    return $rc
}

sb_build_per_user_inbounds() {
    local tmp_file="$1" need_comma="$2"
    [ ! -f "$ARGOV_USERS_FILE" ] && { echo "$need_comma"; return; }
    local py; py=$(py_bin); [ -z "$py" ] && { echo "$need_comma"; return; }

    # Python 生成每用户 inbound JSON (避免 heredoc 展开问题)
    local per_user_json; per_user_json=$("$py" - "$ARGOV_USERS_FILE" "$need_comma" \
        "${SB_HY2_ENABLE:-false}" "${SB_HY2_HOP_ENABLE:-false}" "${SB_HY2_HOP_START:-}" "${SB_HY2_HOP_END:-}" \
        "${SB_HY2_HOP_MODE:-fixed}" "${SB_HY2_HOP_INTERVAL:-30}" "${SB_HY2_HOP_MIN:-10}" "${SB_HY2_HOP_MAX:-30}" \
        "${SB_TUIC_ENABLE:-false}" "${SB_ANYTLS_ENABLE:-false}" "${SB_REALITY_ENABLE:-false}" "${SB_SS_ENABLE:-false}" \
        "${SB_CERT_FILE}" "${SB_KEY_FILE}" "${SB_SNI:-addons.mozilla.org}" "${SB_REALITY_PRIV:-}" "${SB_REALITY_SID:-}" \
        "${SB_SS_METHOD:-${SS_METHOD:-aes-256-gcm}}" "${SB_ANYTLS_SNI:-$SB_SNI}" "${SB_REALITY_SNI:-$SB_SNI}" << 'PYPERUSER'
import json, sys
users_file = sys.argv[1]
prev_comma  = sys.argv[2] == 'true'
hy2_enable    = sys.argv[3] == 'true'
hy2_hop_en    = sys.argv[4] == 'true'
hy2_hop_start = sys.argv[5]
hy2_hop_end   = sys.argv[6]
hy2_hop_mode  = sys.argv[7]
hy2_hop_intv  = sys.argv[8]
hy2_hop_min   = sys.argv[9]
hy2_hop_max   = sys.argv[10]
tuic_enable   = sys.argv[11] == 'true'
anytls_enable = sys.argv[12] == 'true'
reality_enable= sys.argv[13] == 'true'
ss_enable     = sys.argv[14] == 'true'
cert_file     = sys.argv[15]
key_file      = sys.argv[16]
sb_sni        = sys.argv[17]
reality_priv  = sys.argv[18]
reality_sid   = sys.argv[19]
ss_method     = sys.argv[20]
anytls_sni    = sys.argv[21]
reality_sni   = sys.argv[22]

with open(users_file) as f:
    data = json.load(f)

inbounds = []
for u in data.get('users', []):
    name = u.get('name', 'default')
    if name == 'default':
        continue
    ports = u.get('sb_ports', {})
    creds = u.get('sb_creds', {})

    # HY2 每用户 inbound 已移除 — 跳变兼容性, 仅共享端口
    # TUIC per-user
    if tuic_enable:
        p = ports.get('tuic') or 0
        if p > 0:
            inbounds.append({"type":"tuic","tag":f"sb-tuic-{name}","listen":"::","listen_port":p,
                "users":[{"uuid":creds.get('tuic_uuid',''),"password":creds.get('tuic_pass','')}],
                "congestion_control":"bbr",
                "tls":{"enabled":True,"alpn":["h3"],"certificate_path":cert_file,"key_path":key_file}})

    # AnyTLS per-user
    if anytls_enable:
        p = ports.get('anytls') or 0
        if p > 0:
            inbounds.append({"type":"anytls","tag":f"sb-anytls-{name}","listen":"::","listen_port":p,
                "users":[{"name":name,"password":creds.get('anytls_pass','')}],
                "padding_scheme":[],
                "tls":{"enabled":True,"server_name":anytls_sni,
                    "reality":{"enabled":True,"handshake":{"server":anytls_sni,"server_port":443},
                    "private_key":reality_priv,"short_id":[reality_sid]}}})

    # Reality per-user
    if reality_enable:
        p = ports.get('reality') or 0
        if p > 0:
            inbounds.append({"type":"vless","tag":f"sb-reality-{name}","listen":"::","listen_port":p,
                "users":[{"uuid":u.get('uuid',''),"flow":"xtls-rprx-vision"}],
                "tls":{"enabled":True,"server_name":reality_sni,
                    "reality":{"enabled":True,"handshake":{"server":reality_sni,"server_port":443},
                    "private_key":reality_priv,"short_id":[reality_sid]}}})

    # SS per-user
    if ss_enable:
        p = ports.get('ss') or 0
        if p > 0:
            inbounds.append({"type":"shadowsocks","tag":f"sb-ss-{name}","listen":"::","listen_port":p,
                "method":ss_method,"password":creds.get('ss_pass','')})

for i, obj in enumerate(inbounds):
    if i > 0 or prev_comma:
        print(",", end="")
    print(json.dumps(obj, indent=2, ensure_ascii=False))
PYPERUSER
    )

    if [ -n "$per_user_json" ]; then
        printf '%s' "$per_user_json" >> "$tmp_file"
        echo "true"
    else
        echo "$need_comma"
    fi
}

sb_collect_user_traffic() {
    # 读取每用户端口的 iptables 计数器, 更新 argov_users.json
    local py; py=$(py_bin); [ -z "$py" ] && return
    [ ! -f "$ARGOV_USERS_FILE" ] && return

    # 收集所有用户端口
    local port_map=""
    local users_json; users_json=$(jq -c '.users[] | select(.name != "default")' "$ARGOV_USERS_FILE" 2>/dev/null)
    while IFS= read -r user; do
        [ -z "$user" ] && continue
        local uname; uname=$(echo "$user" | jq -r '.name')
        local sb_ports; sb_ports=$(echo "$user" | jq -c '.sb_ports // {}')

        for proto in hy2 tuic anytls reality ss; do
            local up; up=$(echo "$sb_ports" | jq -r ".${proto} // 0")
            if [ "$up" -gt 0 ]; then
                # 读取该端口的 iptables INPUT 计数器 (入站=用户的 uplink, 即服务器 downlink)
                local tin; tin=$(iptables -L INPUT -v -n -x 2>/dev/null | awk -v p="$up" '$NF ~ p {sum+=$2} END {print sum+0}')
                local tout; tout=$(iptables -L OUTPUT -v -n -x 2>/dev/null | awk -v p="$up" '$NF ~ p {sum+=$2} END {print sum+0}')
                port_map="${port_map}${uname} ${proto} ${tin} ${tout}\n"
            fi
        done
    done <<< "$users_json"

    [ -z "$port_map" ] && return

    begin_argov_lock
    printf '%b' "$port_map" | "$py" - "$ARGOV_USERS_FILE" << 'PYEOF'
import json, sys

users_file = sys.argv[1]
with open(users_file, 'r') as f:
    data = json.load(f)

# 读取端口流量映射: name proto in_bytes out_bytes
user_traffic = {}
for line in sys.stdin:
    parts = line.strip().split()
    if len(parts) != 4:
        continue
    name, proto, tin, tout = parts[0], parts[1], int(parts[2]), int(parts[3])
    user_traffic.setdefault(name, {'up': 0, 'down': 0})
    user_traffic[name]['up'] += tout   # 服务器出站 = 用户下行(uplink)
    user_traffic[name]['down'] += tin  # 服务器入站 = 用户上行(downlink)

for u in data.get('users', []):
    name = u.get('name', '')
    if name in user_traffic:
        u['used_up'] = u.get('used_up', 0) + user_traffic[name]['up']
        u['used_down'] = u.get('used_down', 0) + user_traffic[name]['down']

with open(users_file + '.tmp', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
import os; os.replace(users_file + '.tmp', users_file)
PYEOF
    end_argov_lock
}

start_sb_stats_service() {
    # 安装 argov-sb-stats 守护进程 (每60s采集 Sing-box 用户流量)
    cat > "${WORK_DIR}/sb_stats.sh" << 'SBSTATSEOF'
#!/usr/bin/env bash
WORK_DIR="/etc/xray"
ARGOV_USERS_FILE="/etc/xray/argov_users.json"
ARGOV_CONF="/etc/xray/argov.conf"
# 加载配置 (SB_ENABLE 等在这)
[ -f "$ARGOV_CONF" ] && . "$ARGOV_CONF"
while true; do
    sleep 60
    [ "${SB_ENABLE:-false}" != "true" ] && continue
    [ ! -f "$ARGOV_USERS_FILE" ] && continue
    # 调用 argov.sh 中的采集函数 (通过 source 加载)
    if [ -f "${WORK_DIR}/sb_collect.sh" ]; then
        bash "${WORK_DIR}/sb_collect.sh" 2>/dev/null || true
    fi
done
SBSTATSEOF

    # 独立采集脚本 (避免 source 整个 argov.sh)
    cat > "${WORK_DIR}/sb_collect.sh" << 'SBCOLLECTEOF'
#!/usr/bin/env bash
ARGOV_USERS_FILE="/etc/xray/argov_users.json"
py=$(command -v python3 || command -v python || true)
[ -z "$py" ] && exit 0
[ ! -f "$ARGOV_USERS_FILE" ] && exit 0

port_map=""
users_json=$(jq -c '.users[] | select(.name != "default")' "$ARGOV_USERS_FILE" 2>/dev/null)
while IFS= read -r user; do
    [ -z "$user" ] && continue
    uname=$(echo "$user" | jq -r '.name')
    sb_ports=$(echo "$user" | jq -c '.sb_ports // {}')
    for proto in hy2 tuic anytls reality ss; do
        up=$(echo "$sb_ports" | jq -r ".${proto} // 0")
        [ "$up" = "0" ] && continue
        tin=$(iptables -L INPUT -v -n -x 2>/dev/null | awk -v p="$up" '/argov-traffic-in/ && $0 ~ "dpt:"p {sum+=$2} END {print sum+0}')
        tout=$(iptables -L OUTPUT -v -n -x 2>/dev/null | awk -v p="$up" '/argov-traffic-out/ && $0 ~ "spt:"p {sum+=$2} END {print sum+0}')
        port_map="${port_map}${uname} ${proto} ${tin} ${tout}\n"
    done
done <<< "$users_json"

[ -z "$port_map" ] && exit 0

# 写 Python 脚本到临时文件 (避免 pipe+heredoc 争抢 stdin)
cat > /tmp/.sb_collect.py << 'PYEOF'
import json, sys, os
users_file = sys.argv[1]
with open(users_file, 'r') as f:
    data = json.load(f)
user_traffic = {}
for line in sys.stdin:
    parts = line.strip().split()
    if len(parts) != 4: continue
    name, proto, tin, tout = parts[0], parts[1], int(parts[2]), int(parts[3])
    user_traffic.setdefault(name, {'up': 0, 'down': 0})
    user_traffic[name]['up'] += tout
    user_traffic[name]['down'] += tin
for u in data.get('users', []):
    name = u.get('name', '')
    if name in user_traffic:
        # delta 模式: iptables 计数器是累积值, 只加增量
        prev_in = u.get('sb_prev_in') or 0
        prev_out = u.get('sb_prev_out') or 0
        cur_in = user_traffic[name]['up']
        cur_out = user_traffic[name]['down']
        delta_up = cur_out - prev_out
        delta_down = cur_in - prev_in
        if delta_up > 0:
            u['used_up'] = u.get('used_up', 0) + delta_up
        if delta_down > 0:
            u['used_down'] = u.get('used_down', 0) + delta_down
        u['sb_prev_in'] = cur_in
        u['sb_prev_out'] = cur_out
        # 检查配额
        quota = u.get('quota_bytes', 0)
        if quota > 0:
            total = u['used_up'] + u['used_down']
            if total >= quota:
                u['enabled'] = False
with open(users_file + '.tmp', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
os.replace(users_file + '.tmp', users_file)
PYEOF
# 管道喂数据给 Python 脚本 (heredoc 和 pipe 分两步, 不抢 stdin)
exec 9>"/etc/xray/.argov.lock" 2>/dev/null
flock -x 9 2>/dev/null || true
printf '%b' "$port_map" | "$py" /tmp/.sb_collect.py "$ARGOV_USERS_FILE"
rm -f /tmp/.sb_collect.py
exec 9>&- 2>/dev/null || true
SBCOLLECTEOF
    chmod +x "${WORK_DIR}/sb_stats.sh" "${WORK_DIR}/sb_collect.sh"

    # 安装系统服务
    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/argov-sb-stats << 'SBOPENRC'
#!/sbin/openrc-run
name=argov-sb-stats
description="ArgoV Sing-box Per-User Stats Daemon"
supervisor=supervise-daemon
command=/etc/xray/sb_stats.sh
command_background=true
pidfile=/run/argov-sb-stats.pid
depend() { need net; }
SBOPENRC
        chmod +x /etc/init.d/argov-sb-stats
        rc-update add argov-sb-stats default 2>/dev/null || true
        rc-service argov-sb-stats restart 2>/dev/null || true
    else
        cat > /etc/systemd/system/argov-sb-stats.service << 'SBSYSTEMD'
[Unit]
Description=ArgoV Sing-box Per-User Stats Daemon
After=network.target
[Service]
Type=simple
ExecStart=/etc/xray/sb_stats.sh
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
SBSYSTEMD
        systemctl daemon-reload
        systemctl enable argov-sb-stats 2>/dev/null || true
        systemctl restart argov-sb-stats 2>/dev/null || true
    fi
}

stop_sb_stats_service() {
    systemctl stop argov-sb-stats 2>/dev/null || true
    systemctl disable argov-sb-stats 2>/dev/null || true
    rc-service argov-sb-stats stop 2>/dev/null || true
    rc-update del argov-sb-stats default 2>/dev/null || true
    rm -f /etc/systemd/system/argov-sb-stats.service /etc/init.d/argov-sb-stats "${WORK_DIR}/sb_stats.sh" "${WORK_DIR}/sb_collect.sh" 2>/dev/null
}
save_var() { printf "%s=%q\n" "$1" "$2"; }
secure_work_dir_permissions() {
    [ -d "$WORK_DIR" ] || return 0
    chmod 755 "$WORK_DIR" 2>/dev/null || true
    chmod 600 "$USER_CONF" "$ARGOV_USERS_FILE" "$CONFIG_FILE" "$TUNNEL_LOG" "$HY2_KEY_FILE" "${WORK_DIR}/custom_links.txt" "${WORK_DIR}/sub.txt" 2>/dev/null || true
    chmod 644 "${WORK_DIR}/relay_domains.txt" "${WORK_DIR}/warp_domains.txt" "$HY2_CERT_FILE" 2>/dev/null || true
    chmod 700 "${WORK_DIR}/xray" "${WORK_DIR}/argo" "${WORK_DIR}/qrencode" "${WORK_DIR}/argov-tunnel.sh" "${WORK_DIR}/hy2-hop.sh" "${WORK_DIR}/sub_gen.sh" 2>/dev/null || true
    chmod 600 "${WORK_DIR}/sub.py" "${WORK_DIR}/stats.py" 2>/dev/null || true
}
install_ag_wrapper() {
    local mode="${1:-}"
    if [ "$mode" = "forward_args" ]; then
        cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
T="/tmp/argov.sh"
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$T" "https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh?r=$RANDOM$RANDOM" || curl -fsSL --retry 3 -o "$T" "https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh"
[ -s "$T" ] && bash -n "$T" && bash "$T" "$@"
ARGOWRAP
    else
        cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
T=$(mktemp /tmp/argov.XXXXXX)
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$T" "https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh?r=$RANDOM$RANDOM" || curl -fsSL --retry 3 -o "$T" "https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh"
[ -s "$T" ] && bash -n "$T" && bash "$T"
rm -f "$T"
ARGOWRAP
    fi
    chmod +x "$SCRIPT_PATH"
}

#==============================================================================
# Sing-box 内核管理
#==============================================================================
singbox_runtime_config_ready() {
    [ -f "$SB_CONFIG_FILE" ] && return 0
    local binary
    if sb_status && binary=$(singbox_binary_path) && singbox_preflight_current_config "$binary" "$SB_CONFIG_FILE" >/dev/null 2>&1; then
        return 0
    fi
    yellow_msg "Sing-box 没有可验证的节点配置，已取消启动/重启；请从 s → s2 增配节点，或先恢复丢失的配置。"
    return 1
}
sb_start() {
    singbox_runtime_config_ready || return 1
    if [ "$IS_ALPINE" = 1 ]; then rc-service sing-box start; else systemctl start sing-box; fi
}
sb_stop() {
    if [ "$IS_ALPINE" = 1 ]; then rc-service sing-box stop; else systemctl stop sing-box; fi
}
sb_restart() {
    singbox_runtime_config_ready || return 1
    if [ "$IS_ALPINE" = 1 ]; then rc-service sing-box restart; else systemctl restart sing-box; fi
}
stop_singbox_for_uninstall() {
    sb_stop
    if sb_status || singbox_service_pid >/dev/null 2>&1; then
        red_msg "Sing-box 进程仍在运行，已取消卸载；内核、配置与证书未删除。请先检查服务停止失败的原因。"
        return 1
    fi
    return 0
}
sb_status() {
    core_service_active sing-box
}
singbox_service_pid() {
    local pid
    if [ "${IS_ALPINE:-0}" = 1 ]; then
        IFS= read -r pid < /run/sing-box.pid 2>/dev/null || return 1
    else
        pid=$(command systemctl show sing-box -p MainPID --value 2>/dev/null) || return 1
    fi
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [ -r "/proc/$pid/cmdline" ] || return 1
    printf '%s' "$pid"
}
singbox_running_binary() {
    local pid binary version
    pid=$(singbox_service_pid) || return 1
    binary=$(readlink "/proc/$pid/exe") || return 1
    [ -x "$binary" ] || return 1
    version=$("$binary" version 2>/dev/null) || return 1
    [[ "$version" == 'sing-box version '* ]] || return 1
    printf '%s' "$binary"
}
singbox_binary_path() {
    local binary
    binary=$(singbox_running_binary) && { printf '%s' "$binary"; return 0; }
    binary=$(type -P sing-box)
    [ -n "$binary" ] && [ -x "$binary" ] && { printf '%s' "$binary"; return 0; }
    for binary in /usr/local/bin/sing-box /usr/bin/sing-box "${SB_WORK_DIR}/sing-box"; do
        [ -x "$binary" ] && { printf '%s' "$binary"; return 0; }
    done
    return 1
}
sing-box() {
    local binary
    binary=$(singbox_binary_path) || { red_msg "未找到 Sing-box 可执行文件。" >&2; return 127; }
    "$binary" "$@"
}
sb_is_installed() { singbox_binary_path >/dev/null 2>&1; }
sb_has_protocols() {
    local key
    for key in SB_HY2_ENABLE SB_TUIC_ENABLE SB_ANYTLS_ENABLE SB_REALITY_ENABLE SB_SS_ENABLE; do
        [ "${!key}" = true ] && return 0
    done
    return 1
}

singbox_version_string() {
    local binary pid
    binary=$(singbox_binary_path) || {
        pid=$(singbox_service_pid) || return 1
        binary="/proc/$pid/exe"
    }
    "$binary" version 2>/dev/null \
        | sed -n 's/^sing-box version[[:space:]]*\([^[:space:]]*\).*/\1/p' \
        | head -n 1
}

singbox_libc() {
    if [ "${IS_ALPINE:-0}" = 1 ]; then
        echo "musl"
        return 0
    fi
    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        echo "musl"
    else
        echo "glibc"
    fi
}

singbox_latest_version() {
    local requested="${SB_VERSION:-}" tag response
    if [ -n "$requested" ] && [ "$requested" != "latest" ]; then
        printf '%s\n' "${requested#v}"
        return 0
    fi
    command -v jq >/dev/null 2>&1 || { red_msg "获取 Sing-box 版本需要 jq，请先安装 jq。" >&2; return 1; }
    if ! response=$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: ArgoV' \
        'https://api.github.com/repos/SagerNet/sing-box/releases/latest'); then
        red_msg "获取 Sing-box 版本失败：GitHub API 请求失败，请检查网络、TLS 或 HTTP 限流提示。" >&2
        return 1
    fi
    tag=$(printf '%s' "$response" | jq -er '.tag_name | select(type == "string")' 2>/dev/null) || {
        red_msg "获取 Sing-box 版本失败：GitHub API 未返回有效的版本 JSON。" >&2
        return 1
    }
    tag="${tag#v}"
    [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || {
        red_msg "获取 Sing-box 版本失败：GitHub API 返回了无效的版本号。" >&2
        return 1
    }
    printf '%s\n' "$tag"
}

singbox_archive_url() {
    local version="${1#v}" arch="$2" libc suffix=""
    libc=$(singbox_libc)
    [ "$libc" = "musl" ] && suffix="-musl"
    printf 'https://github.com/SagerNet/sing-box/releases/download/v%s/sing-box-%s-linux-%s%s.tar.gz\n' \
        "$version" "$version" "$arch" "$suffix"
}

core_service_active() {
    if [ "${IS_ALPINE:-0}" = 1 ]; then
        rc-service "$1" status 2>/dev/null | grep -q 'started'
    else
        command systemctl is-active --quiet "$1" 2>/dev/null
    fi
}

singbox_preflight_current_config() {
    local candidate="$1" fallback="$2" pid cwd arg i has_config=0
    local -a args=() check_args=()
    if core_service_active sing-box && pid=$(singbox_service_pid) && singbox_running_binary >/dev/null; then
        while IFS= read -r -d '' arg; do args+=("$arg"); done < "/proc/$pid/cmdline"
        for ((i=1; i<${#args[@]}; i++)); do
            case "${args[$i]}" in
                -c|--config|-C|--config-directory)
                    arg="${args[$i]}"; ((i++))
                    [ "$i" -lt "${#args[@]}" ] || return 1
                    check_args+=("$arg" "${args[$i]}")
                    has_config=1
                    ;;
                --config=*|--config-directory=*) check_args+=("${args[$i]}"); has_config=1 ;;
                -D|--directory) ((i++)) ;;
            esac
        done
        if [ "$has_config" = 1 ]; then
            cwd=$(readlink "/proc/$pid/cwd") || return 1
            (cd "$cwd" && "$candidate" check -D "$cwd" "${check_args[@]}")
            return $?
        fi
    fi
    if [ -f "$fallback" ]; then "$candidate" check -c "$fallback"; return $?; fi
    if core_service_active sing-box; then
        red_msg "运行中的 Sing-box 配置路径无法确认，且 $fallback 不存在；已取消升级，原服务保持运行。"
        return 1
    fi
    return 0
}

# 升级只替换二进制；用现有配置预检，不迁移协议、用户或证书。
activate_core_binary() {
    local core="$1" candidate="$2" target="$3" config="$4" check_result stage backup="" was_running=0 i healthy=1
    [ -x "$candidate" ] || { red_msg "候选内核不可执行，原内核未修改。"; return 1; }
    "$candidate" version >/dev/null 2>&1 || { red_msg "候选内核无法运行，原内核未修改。"; return 1; }
    if [ "$core" != sing-box ] && [ ! -f "$config" ] && core_service_active "$core"; then
        red_msg "运行中的服务缺少现有配置文件，无法安全预检，已取消升级。"
        return 1
    fi
    if [ "$core" = sing-box ] || [ -f "$config" ]; then
        if [ "$core" = xray ]; then
            check_result=$(XRAY_LOCATION_ASSET="$(dirname "$target")" "$candidate" run -test -config "$config" 2>&1)
        else
            check_result=$(singbox_preflight_current_config "$candidate" "$config" 2>&1)
        fi
        if [ "$?" -ne 0 ]; then
            red_msg "新内核不兼容现有配置，已取消升级，原服务继续使用原内核。"
            printf '%s\n' "$check_result"
            return 1
        fi
    fi
    if [ -f "$target" ]; then
        backup=$(mktemp "${target}.argov-backup.XXXXXX") || return 1
        cp -p "$target" "$backup" || { rm -f "$backup"; return 1; }
    fi
    stage=$(mktemp "${target}.argov-new.XXXXXX") || { [ -n "$backup" ] && rm -f "$backup"; return 1; }
    if ! cp "$candidate" "$stage" || ! chmod 0755 "$stage"; then
        rm -f "$stage"; [ -n "$backup" ] && rm -f "$backup"; return 1
    fi
    core_service_active "$core" && was_running=1
    if ! mv -f "$stage" "$target"; then
        rm -f "$stage"; [ -n "$backup" ] && rm -f "$backup"; return 1
    fi
    if [ "$was_running" = 1 ]; then
        healthy=0
        if restart_protocol_runtime "$core"; then
            healthy=1
            for i in 1 2 3; do
                sleep 1
                core_service_active "$core" || { healthy=0; break; }
            done
        fi
    fi
    if [ "$healthy" != 1 ]; then
        if [ -n "$backup" ] && mv -f "$backup" "$target"; then
            red_msg "新内核启动失败，已恢复旧内核和原配置。"
            restart_protocol_runtime "$core" >/dev/null 2>&1 && core_service_active "$core" || yellow_msg "旧内核服务未恢复，请查看服务日志。"
        else
            red_msg "回滚未完成，旧内核备份位于 ${backup:-未生成}，请检查磁盘与权限。"
        fi
        return 1
    fi
    if [ -n "$backup" ]; then
        mv -f "$backup" "${target}.argov-previous" || yellow_msg "旧内核备份保留在 $backup"
    fi
    return 0
}

install_singbox_archive() {
    local version="$1" arch="$2" url tmp extract binary target
    [ -n "$version" ] || return 1
    url=$(singbox_archive_url "$version" "$arch")
    tmp=$(mktemp -t singbox.XXXXXX) || return 1
    extract=$(mktemp -d -t singbox-extract.XXXXXX) || { rm -f "$tmp" 2>/dev/null || true; return 1; }
    if ! download_file "$url" "$tmp"; then
        red_msg "Sing-box 内核下载失败: $version ($arch/$(singbox_libc))"
        rm -f "$tmp" 2>/dev/null || true
        rm -rf "$extract" 2>/dev/null || true
        return 1
    fi
    if ! tar xzf "$tmp" -C "$extract" 2>/dev/null; then
        red_msg "Sing-box 下载的压缩包无法解压: $version"
        rm -f "$tmp" 2>/dev/null || true
        rm -rf "$extract" 2>/dev/null || true
        return 1
    fi
    binary=$(find "$extract" -type f -name sing-box -print -quit 2>/dev/null)
    if [ -z "$binary" ]; then
        red_msg "Sing-box 压缩包中没有内核文件: $version"
        rm -f "$tmp" 2>/dev/null || true
        rm -rf "$extract" 2>/dev/null || true
        return 1
    fi
    target="/usr/bin/sing-box"
    if sb_is_installed; then
        target=$(singbox_binary_path) || { rm -f "$tmp"; rm -rf "$extract"; return 1; }
    fi
    if ! activate_core_binary sing-box "$binary" "$target" "$SB_CONFIG_FILE"; then
        rm -f "$tmp"; rm -rf "$extract"; return 1
    fi
    rm -f "$tmp" 2>/dev/null || true
    rm -rf "$extract" 2>/dev/null || true
    return 0
}

# SHA256 证书指纹 (证书固定 pinSHA256)
cert_pin_sha256() {
    # Hysteria2 URL 格式: 大写十六进制+冒号 (BA:88:45:17:A1:...)
    local cert="$1"
    [ -f "$cert" ] || return 1
    openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//' | tr '[:lower:]' '[:upper:]'
}
cert_pin_sha256_b64() {
    # 完整证书 DER 的 SHA256，Base64 格式；不是公钥指纹。
    local cert="$1"
    [ -f "$cert" ] || return 1
    openssl x509 -in "$cert" -outform DER -sha256 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | base64 -w0 2>/dev/null || \
    openssl x509 -in "$cert" -outform DER 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | base64 | tr -d '\n'
}

# 只读取正在使用的证书，不重新签发或更换存量节点的身份。
refresh_certificate_pins() {
    local xray_cert="$HY2_CERT_FILE" sb_hy2_cert="${SB_HY2_CERT_FILE:-$SB_CERT_FILE}" tuic_cert="$SB_CERT_FILE"
    local path pin changed=1
    if command -v jq >/dev/null 2>&1; then
        path=$(jq -r '.inbounds[]?|select(.tag=="hy2")|.streamSettings.tlsSettings.certificates[0].certificateFile//empty' "$CONFIG_FILE" 2>/dev/null | head -n 1)
        [ -n "$path" ] && xray_cert="$path"
        path=$(jq -r '.inbounds[]?|select(.tag=="sb-hy2")|.tls.certificate_path//empty' "$SB_CONFIG_FILE" 2>/dev/null | head -n 1)
        [ -n "$path" ] && sb_hy2_cert="$path"
        path=$(jq -r '.inbounds[]?|select(.tag=="sb-tuic")|.tls.certificate_path//empty' "$SB_CONFIG_FILE" 2>/dev/null | head -n 1)
        [ -n "$path" ] && tuic_cert="$path"
    fi
    pin=$(cert_pin_sha256 "$xray_cert")
    if [ -n "$pin" ] && [ "$pin" != "${HY2_PIN_SHA256:-}" ]; then HY2_PIN_SHA256="$pin"; changed=0; fi
    pin=$(cert_pin_sha256 "$sb_hy2_cert")
    if [ -n "$pin" ] && [ "$pin" != "${SB_HY2_PIN_SHA256:-}" ]; then SB_HY2_PIN_SHA256="$pin"; changed=0; fi
    pin=$(cert_pin_sha256 "$tuic_cert")
    if [ -n "$pin" ] && [ "$pin" != "${SB_TUIC_PIN_SHA256:-}" ]; then SB_TUIC_PIN_SHA256="$pin"; changed=0; fi
    return "$changed"
}

certificate_uri_options() {
    # insecure 保留旧 URI 客户端兼容；支持指纹的客户端必须固定证书。
    # 不再导出新版 Xray 已删除的 allowInsecure=1。
    local pin="${1//:/}"
    printf '&insecure=1&allowInsecure=0'
    [[ "$pin" =~ ^[[:xdigit:]]{64}$ ]] && printf '&pinSHA256=%s' "$pin"
    return 0
}

# Sing-box HY2 端口跳跃
apply_sb_hy2_hop_rules() {
    [ "${SB_HY2_HOP_ENABLE:-false}" != "true" ] && return 0
    local port="${SB_HY2_PORT:-}" hop_candidate
    local shared_start="${SB_HY2_HOP_START:-47000}" shared_end="${SB_HY2_HOP_END:-48000}"
    is_port "$port" && is_port_range "${shared_start}-${shared_end}" || return 1
    command -v iptables >/dev/null 2>&1 || { yellow_msg "未找到 iptables，无法启用 HY2 跳跃。"; return 1; }
    mkdir -p "$SB_WORK_DIR" || return 1
    hop_candidate=$(mktemp "${SB_WORK_DIR}/hy2-hop.sh.new.XXXXXX") || return 1
    cat > "$hop_candidate" << EOF
#!/usr/bin/env bash
set -e
iptables -t nat -C PREROUTING -p udp --dport "${shared_start}:${shared_end}" -j REDIRECT --to-ports "$port" -m comment --comment "argov-sb-hy2-hop" 2>/dev/null || \\
iptables -t nat -A PREROUTING -p udp --dport "${shared_start}:${shared_end}" -j REDIRECT --to-ports "$port" -m comment --comment "argov-sb-hy2-hop"
EOF
    [ "$?" = 0 ] || { rm -f "$hop_candidate"; return 1; }
    chmod 700 "$hop_candidate" || { rm -f "$hop_candidate"; return 1; }
    disable_sb_hy2_hop_rules
    mv -f "$hop_candidate" "${SB_WORK_DIR}/hy2-hop.sh" || { rm -f "$hop_candidate"; return 1; }
    "${SB_WORK_DIR}/hy2-hop.sh" || return 1
    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/argov-sb-hy2-hop << EOF
#!/sbin/openrc-run
name=argov-sb-hy2-hop
command="${SB_WORK_DIR}/hy2-hop.sh"
command_background=false
depend() { need net; after firewall; }
EOF
        [ "$?" = 0 ] || return 1
        chmod +x /etc/init.d/argov-sb-hy2-hop || return 1
        rc-update add argov-sb-hy2-hop default && rc-service argov-sb-hy2-hop start
    else
        cat > /etc/systemd/system/argov-sb-hy2-hop.service << EOF
[Unit]
Description=ArgoV Sing-box Hysteria2 Port Hopping Rules
After=network.target firewalld.service ufw.service
[Service]
Type=oneshot
ExecStart=${SB_WORK_DIR}/hy2-hop.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
        [ "$?" = 0 ] || return 1
        systemctl daemon-reload && systemctl enable argov-sb-hy2-hop && systemctl start argov-sb-hy2-hop
    fi
}
disable_sb_hy2_hop_rules() {
    systemctl stop argov-sb-hy2-hop 2>/dev/null || true
    systemctl disable argov-sb-hy2-hop 2>/dev/null || true
    rc-service argov-sb-hy2-hop stop 2>/dev/null || true
    rc-update del argov-sb-hy2-hop default 2>/dev/null || true
    while iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep -q "argov-sb-hy2-hop"; do
        local ln; ln=$(iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep "argov-sb-hy2-hop" | head -1 | awk '{print $1}')
        [ -n "$ln" ] && iptables -t nat -D PREROUTING "$ln" 2>/dev/null || break
    done
    rm -f "${SB_WORK_DIR}/hy2-hop.sh" /etc/systemd/system/argov-sb-hy2-hop.service /etc/init.d/argov-sb-hy2-hop
    systemctl daemon-reload 2>/dev/null || true
}

install_singbox() {
    local action="${1:-install}" force_update=0 cur_ver sb_arch latest
    [ "$action" = "update" ] && force_update=1
    yellow_msg "$([ "$force_update" = 1 ] && echo '更新' || echo '安装') Sing-box..."

    if core_service_active sing-box && ! singbox_running_binary >/dev/null; then
        red_msg "Sing-box 服务仍在运行，但运行内核的安装路径不可用；已取消安装/更新，避免重启后旧节点失效。"
        yellow_msg "请先恢复原内核、配置和服务文件；无需保留节点的测试机应先清理残留服务，再安装。"
        return 1
    fi

    if sb_is_installed && [ "$force_update" != 1 ]; then
        cur_ver=$(singbox_version_string)
        green_msg "Sing-box 已安装: ${cur_ver:-unknown}"
        return 0
    fi

    sb_arch=$(detect_sb_arch)
    mkdir -p "$SB_WORK_DIR" "$SB_WORK_DIR/certs" 2>/dev/null || true
    # 首次也只安装 release 内核，避免发行版安装器自动启动尚无节点配置的服务。
    latest=$(singbox_latest_version) || { red_msg "无法获取 Sing-box 目标版本，已取消安装/更新；现有节点未修改。"; return 1; }
    [ -n "$latest" ] || { red_msg "无法获取 Sing-box 目标版本，已取消安装/更新；现有节点未修改。"; return 1; }
    install_singbox_archive "$latest" "$sb_arch" || return 1
    if ! sb_is_installed; then
        red_msg "Sing-box 安装后未找到可执行文件"
        return 1
    fi
    configure_singbox_service || return 1
    SB_ENABLE=true
    save_conf || return 1
    green_msg "Sing-box 内核安装/更新成功: $(singbox_version_string)"
    if ! sb_has_protocols && [ ! -f "$SB_CONFIG_FILE" ]; then
        yellow_msg "内核已就绪，尚未配置节点；稍后从 s → s2 添加协议。"
    fi
}

configure_singbox_service() {
    local sb_bin
    sb_bin=$(singbox_binary_path) || return 1
    # 已有定义（包括发行版单元和用户自定义路径）继续保留。
    if [ "$IS_ALPINE" = 1 ]; then
        [ -f /etc/init.d/sing-box ] && return 0
    else
        [ -n "$(command systemctl show sing-box -p FragmentPath --value 2>/dev/null)" ] && return 0
        [ -f /etc/systemd/system/sing-box.service ] && return 0
    fi

    # 首次仅创建未启用的服务，增配首个协议成功后再设置开机启动。
    if [ "$IS_ALPINE" = 1 ]; then
        cat > /etc/init.d/sing-box << SBOPENRC
#!/sbin/openrc-run
name="sing-box"
description="Sing-box Service"
supervisor="supervise-daemon"
command="${sb_bin}"
command_args="run -c ${SB_CONFIG_FILE}"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background="yes"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.err"
depend() { need net; after firewall; }
start_pre() { checkpath --directory --mode 0755 /var/log /run; }
SBOPENRC
        [ "$?" = 0 ] && chmod +x /etc/init.d/sing-box || return 1
    else
        cat > /etc/systemd/system/sing-box.service << SBSYSTEMD
[Unit]
Description=Sing-box Service
After=network.target
[Service]
Type=simple
ExecStart=${sb_bin} run -c ${SB_CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
SBSYSTEMD
        [ "$?" = 0 ] && systemctl daemon-reload || return 1
    fi
}
enable_singbox_service() {
    if [ "$IS_ALPINE" = 1 ]; then rc-update add sing-box default; else systemctl enable sing-box; fi
}

generate_singbox_cert() {
    ensure_self_signed_cert "${1:-${SB_TUIC_SNI:-$SB_SNI}}" "$SB_CERT_FILE" "$SB_KEY_FILE" || return 1
    SB_TUIC_PIN_SHA256=$(cert_pin_sha256 "$SB_CERT_FILE")
}
generate_singbox_hy2_cert() {
    ensure_self_signed_cert "$SB_HY2_SNI" "$SB_HY2_CERT_FILE" "$SB_HY2_KEY_FILE" || return 1
    SB_HY2_PIN_SHA256=$(cert_pin_sha256 "$SB_HY2_CERT_FILE")
}
ensure_self_signed_cert() {
    local sni="$1" cert="$2" key="$3" cert_tmp key_tmp cert_pub key_pub
    normalize_domain "$sni" >/dev/null || { red_msg "证书域名无效，请先配置 SNI。"; return 1; }
    if [ -s "$cert" ] && [ -s "$key" ] && openssl x509 -in "$cert" -checkend 86400 -noout >/dev/null 2>&1 && \
        openssl x509 -in "$cert" -noout -checkhost "$sni" 2>/dev/null | grep -q 'does match certificate'; then
        cert_pub=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null)
        key_pub=$(openssl pkey -in "$key" -pubout 2>/dev/null)
        [ -n "$cert_pub" ] && [ "$cert_pub" = "$key_pub" ] && return 0
    fi
    mkdir -p "${cert%/*}" "${key%/*}" || return 1
    cert_tmp=$(mktemp "${cert}.tmp.XXXXXX") || return 1
    key_tmp=$(mktemp "${key}.tmp.XXXXXX") || { rm -f "$cert_tmp"; return 1; }
    if ! openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj "/CN=${sni}" -addext "subjectAltName=DNS:${sni}" -keyout "$key_tmp" -out "$cert_tmp" >/dev/null 2>&1; then
        rm -f "$cert_tmp" "$key_tmp"; red_msg "自签证书生成失败。"; return 1
    fi
    chmod 600 "$key_tmp"
    mv -f "$key_tmp" "$key" && mv -f "$cert_tmp" "$cert"
}
singbox_supports_bbr_profile() {
    local version major minor
    version=$(singbox_version_string)
    [ -z "$version" ] && version="${SB_VERSION:-}"
    version="${version#v}"
    [[ "$version" =~ ^([0-9]+)\.([0-9]+) ]] || return 1
    major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"
    (( major > 1 || (major == 1 && minor >= 14) ))
}

#==============================================================================
# iptables 统一流量统计 (内核无关)
#==============================================================================
setup_traffic_counters() {
    # 收集所有监听端口
    local ports=""
    [ -n "${ARGO_PORT:-}" ] && [ "${ARGO_PORT:-}" != "0" ] && ports="$ports $ARGO_PORT"
    [ -n "${VLESS_WS_PORT:-}" ] && [ "${VLESS_WS_PORT:-}" != "0" ] && ports="$ports $VLESS_WS_PORT"
    [ -n "${VMESS_WS_PORT:-}" ] && [ "${VMESS_WS_PORT:-}" != "0" ] && ports="$ports $VMESS_WS_PORT"
    [ -n "${REALITY_PORT:-}" ] && [ "${REALITY_PORT:-}" != "0" ] && ports="$ports $REALITY_PORT"
    [ -n "${HY2_PORT:-}" ] && [ "${HY2_PORT:-}" != "0" ] && ports="$ports $HY2_PORT"
    [ -n "${SS_PORT:-}" ] && [ "${SS_PORT:-}" != "0" ] && ports="$ports $SS_PORT"
    [ -n "${SB_HY2_PORT:-}" ] && [ "${SB_HY2_PORT:-}" != "0" ] && ports="$ports $SB_HY2_PORT"
    [ -n "${SB_TUIC_PORT:-}" ] && [ "${SB_TUIC_PORT:-}" != "0" ] && ports="$ports $SB_TUIC_PORT"
    [ -n "${SB_ANYTLS_PORT:-}" ] && [ "${SB_ANYTLS_PORT:-}" != "0" ] && ports="$ports $SB_ANYTLS_PORT"
    [ -n "${SB_REALITY_PORT:-}" ] && [ "${SB_REALITY_PORT:-}" != "0" ] && ports="$ports $SB_REALITY_PORT"
    [ -n "${SB_SS_PORT:-}" ] && [ "${SB_SS_PORT:-}" != "0" ] && ports="$ports $SB_SS_PORT"

    # v2: 每用户端口
    if [ -f "$ARGOV_USERS_FILE" ]; then
        local per_user_ports; per_user_ports=$(jq -r '.users[] | select(.name!="default") | .sb_ports // {} | .[]' "$ARGOV_USERS_FILE" 2>/dev/null)
        for pp in $per_user_ports; do
            [ "$pp" != "0" ] && [ -n "$pp" ] && ports="$ports $pp"
        done
    fi

    # 对每个端口挂 INPUT/OUTPUT 计数规则 (grep 检查 > iptables -C, 避免重复叠加)
    for p in $ports; do
        # INPUT tcp
        iptables -L INPUT -n 2>/dev/null | grep -q "dpt:$p.*argov-traffic-in" || \
            iptables -I INPUT -p tcp --dport "$p" -m comment --comment "argov-traffic-in" 2>/dev/null || true
        # INPUT udp
        iptables -L INPUT -n 2>/dev/null | grep -q "dpt:$p.*argov-traffic-in" || \
            iptables -I INPUT -p udp --dport "$p" -m comment --comment "argov-traffic-in" 2>/dev/null || true
        # OUTPUT tcp
        iptables -L OUTPUT -n 2>/dev/null | grep -q "spt:$p.*argov-traffic-out" || \
            iptables -I OUTPUT -p tcp --sport "$p" -m comment --comment "argov-traffic-out" 2>/dev/null || true
        # OUTPUT udp
        iptables -L OUTPUT -n 2>/dev/null | grep -q "spt:$p.*argov-traffic-out" || \
            iptables -I OUTPUT -p udp --sport "$p" -m comment --comment "argov-traffic-out" 2>/dev/null || true
    done
}

collect_traffic() {
    local tin=0 tout=0
    tin=$(iptables -L INPUT -v -n -x 2>/dev/null | awk '/argov-traffic-in/{sum+=$2}END{print sum+0}')
    tout=$(iptables -L OUTPUT -v -n -x 2>/dev/null | awk '/argov-traffic-out/{sum+=$2}END{print sum+0}')
    TRAFFIC_IN="$tin"; TRAFFIC_OUT="$tout"
    echo "TRAFFIC_IN=$tin" > "${WORK_DIR}/.traffic_counters"
    echo "TRAFFIC_OUT=$tout" >> "${WORK_DIR}/.traffic_counters"
}

reset_traffic_counters() {
    while iptables -L INPUT -n --line-numbers 2>/dev/null | grep -q "argov-traffic"; do
        local ln; ln=$(iptables -L INPUT -n --line-numbers 2>/dev/null | grep "argov-traffic" | head -1 | awk '{print $1}')
        [ -n "$ln" ] && iptables -D INPUT "$ln" 2>/dev/null || break
    done
    setup_traffic_counters
    TRAFFIC_IN=0; TRAFFIC_OUT=0
    save_conf
}

# MODULE: download and supply-chain helpers
begin_argov_lock() {
    mkdir -p "$WORK_DIR" 2>/dev/null || true
    { exec 9>"${WORK_DIR}/.argov.lock"; } 2>/dev/null || return 0
    command -v flock >/dev/null 2>&1 && flock -x 9 2>/dev/null || true
}
end_argov_lock() {
    command -v flock >/dev/null 2>&1 && flock -u 9 2>/dev/null || true
    { exec 9>&-; } 2>/dev/null || true
}
download_file() {
    local url="$1" dest="$2" tmp
    tmp=$(mktemp "${dest}.tmp.XXXXXX") || return 1
    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$tmp" "$url" && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dest"
        return $?
    fi
    rm -f "$tmp" 2>/dev/null || true
    return 1
}
sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r "$file" | awk '{print $1}'
    else
        return 1
    fi
}
verify_sha256_file() {
    local file="$1" expected="$2" actual
    expected=$(printf '%s' "$expected" | tr -d '[:space:]' | tr 'A-F' 'a-f')
    [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || return 1
    actual=$(sha256_file "$file" | tr 'A-F' 'a-f') || return 1
    [ "$actual" = "$expected" ]
}
xray_release_base() {
    if [ -n "${XRAY_VERSION:-}" ] && [ "$XRAY_VERSION" != "latest" ]; then
        echo "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"
    else
        echo "https://github.com/XTLS/Xray-core/releases/latest/download"
    fi
}
xray_download_url() {
    local arch="$1" base
    base=$(xray_release_base)
    echo "${base}/Xray-linux-${arch}.zip"
}
xray_checksum_url() {
    local arch="$1" base
    base=$(xray_release_base)
    echo "${base}/Xray-linux-${arch}.zip.dgst"
}
cloudflared_release_base() {
    if [ -n "${CLOUDFLARED_VERSION:-}" ] && [ "$CLOUDFLARED_VERSION" != "latest" ]; then
        echo "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}"
    else
        echo "https://github.com/cloudflare/cloudflared/releases/latest/download"
    fi
}
cloudflared_download_url() {
    local arch="$1" base
    base=$(cloudflared_release_base)
    echo "${base}/cloudflared-linux-${arch}"
}
extract_sha256_from_dgst() {
    grep -Eoi '[a-f0-9]{64}' "$1" 2>/dev/null | head -n 1 | tr 'A-F' 'a-f'
}
download_xray_zip_checked() {
    local arch="$1" dest="$2" url dgst expected
    url=$(xray_download_url "$arch")
    download_file "$url" "$dest" || return 1
    if [ -n "${XRAY_SHA256:-}" ]; then
        verify_sha256_file "$dest" "$XRAY_SHA256" || { rm -f "$dest" 2>/dev/null || true; return 1; }
        return 0
    fi
    dgst="${dest}.dgst"
    if download_file "$(xray_checksum_url "$arch")" "$dgst"; then
        expected=$(extract_sha256_from_dgst "$dgst")
        rm -f "$dgst" 2>/dev/null || true
        [ -n "$expected" ] || { rm -f "$dest" 2>/dev/null || true; return 1; }
        verify_sha256_file "$dest" "$expected" || { rm -f "$dest" 2>/dev/null || true; return 1; }
    else
        rm -f "$dgst" 2>/dev/null || true
        yellow_msg "WARNING: Xray checksum sidecar unavailable; set XRAY_SHA256 for strict verification."
    fi
    return 0
}
download_cloudflared_checked() {
    local arch="$1" dest="$2" url
    url=$(cloudflared_download_url "$arch")
    download_file "$url" "$dest" || return 1
    if [ -n "${CLOUDFLARED_SHA256:-}" ]; then
        verify_sha256_file "$dest" "$CLOUDFLARED_SHA256" || { rm -f "$dest" 2>/dev/null || true; return 1; }
    fi
}
download_script_checked() {
    local url="$1" dest="$2"
    download_file "$url" "$dest" || return 1
    bash -n "$dest" >/dev/null 2>&1 || { rm -f "$dest" 2>/dev/null || true; return 1; }
}
run_warp_menu() {
    local mode="$1" script="/tmp/warp_menu.sh"
    download_script_checked "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" "$script" || return 1
    chmod +x "$script" 2>/dev/null || true
    bash "$script" "$mode"
    local rc=$?
    rm -f "$script" 2>/dev/null || true
    return "$rc"
}
is_safe_conf_value() {
    local value="$1" quote="" ch next i=0
    while [ "$i" -lt "${#value}" ]; do
        ch="${value:i:1}"
        case "$quote" in
            single)
                [ "$ch" = "'" ] && quote=""
                ;;
            double)
                if [ "$ch" = "\\" ]; then
                    i=$((i+1))
                elif [ "$ch" = '"' ]; then
                    quote=""
                elif [ "$ch" = '$' ] || [ "$ch" = '`' ]; then
                    return 1
                fi
                ;;
            ansi)
                if [ "$ch" = "\\" ]; then
                    i=$((i+1))
                elif [ "$ch" = "'" ]; then
                    quote=""
                fi
                ;;
            *)
                case "$ch" in
                    "\\") i=$((i+1)) ;;
                    "'") quote="single" ;;
                    '"') quote="double" ;;
                    '$')
                        next="${value:i+1:1}"
                        [ "$next" = "'" ] || return 1
                        quote="ansi"; i=$((i+1))
                        ;;
                    '`'|';'|'|'|'&'|'<'|'>'|'('|')'|'{'|'}') return 1 ;;
                    [[:space:]]) return 1 ;;
                esac
                ;;
        esac
        i=$((i+1))
    done
    [ -z "$quote" ]
}
is_safe_conf_file() {
    local file="$1" line key
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || return 1
        key="${line%%=*}"
        case "$key" in
            NODE_NAME|ARGO_PORT|VLESS_WS_PORT|VMESS_WS_PORT|CDN_PORT|CDN_DOMAIN|ARGO_MODE|ARGO_AUTH|ARGO_FIXED_DOMAIN|UUID_CUSTOM|REALITY_PORT|HY2_PORT|HY2_MPORT|HY2_CONGESTION|HY2_UP_MBPS|HY2_DOWN_MBPS|SS_PORT|SUB_PORT|SUB_PATH|SUB_DOMAIN|SUB_TOKEN|REALITY_SNI|REALITY_FP|HY2_SNI|SS_METHOD|ENABLE_REALITY|ENABLE_HY2|ENABLE_SS|HY2_CERT_FILE|HY2_KEY_FILE|REALITY_PRIV|REALITY_PUB|REALITY_SHORTID|LAST_ARGO_DOMAIN|RELAY_ENABLED|RELAY_LINK|RELAY_MODE|XRAY_VERSION|XRAY_SHA256|CLOUDFLARED_VERSION|CLOUDFLARED_SHA256|AGG_TOKEN|SB_ENABLE|SB_VERSION|SB_HY2_ENABLE|SB_HY2_CONGESTION|SB_HY2_UP_MBPS|SB_HY2_DOWN_MBPS|SB_HY2_BBR_PROFILE|SB_TUIC_ENABLE|SB_ANYTLS_ENABLE|SB_REALITY_ENABLE|SB_SS_ENABLE|SB_HY2_PORT|SB_TUIC_PORT|SB_ANYTLS_PORT|SB_REALITY_PORT|SB_SS_PORT|SB_REALITY_PRIV|SB_REALITY_PUB|SB_REALITY_SID|SB_ANYTLS_PSK|SB_TUIC_UUID|SB_TUIC_PSK|SB_HY2_PSK|SB_SS_PSK|SB_ANYTLS_USER|SB_SNI|SB_CERT_FILE|SB_KEY_FILE|TRAFFIC_IN|TRAFFIC_OUT|SB_HY2_HOP_ENABLE|SB_HY2_HOP_START|SB_HY2_HOP_END|SB_HY2_HOP_MODE|SB_HY2_HOP_INTERVAL|SB_HY2_HOP_MIN|SB_HY2_HOP_MAX|HY2_PIN_SHA256|SB_HY2_PIN_SHA256|SB_TUIC_PIN_SHA256|SB_HY2_SNI|SB_TUIC_SNI|SB_ANYTLS_SNI|SB_REALITY_SNI|SB_SS_METHOD|SB_HY2_CERT_FILE|SB_HY2_KEY_FILE) ;;
            *) return 1 ;;
        esac
        case "$line" in
            *'$('*|*'${'*) return 1 ;;
        esac
        is_safe_conf_value "${line#*=}" || return 1
    done < "$file"
    return 0
}
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
# MODULE: user quota state
ensure_users_file() {
    local py uuid token
    py=$(py_bin); [ -z "$py" ] && return 1
    mkdir -p "$WORK_DIR" 2>/dev/null
    secure_work_dir_permissions
    uuid=$(get_uuid); [ -z "$uuid" ] && uuid="${UUID_CUSTOM:-$(rand_uuid)}"
    [ -z "$SUB_TOKEN" ] && SUB_TOKEN=$(rand_token)
    token="$SUB_TOKEN"
    begin_argov_lock
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
    u["reset_day"] = int(u.get("reset_day") or 0)
    u["last_reset_month"] = int(u.get("last_reset_month") or 0)
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
    local rc=$?
    end_argov_lock
    secure_work_dir_permissions
    return "$rc"
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
    normalize_xray_reality_config 2>/dev/null || true
    local py; py=$(py_bin); [ -z "$py" ] && return 1
    begin_argov_lock
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

ROUTE_SNIFFING = {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}
ROUTE_SNIFF_TAGS = {"argo-in", "vless-ws", "vmess-ws", "reality", "hy2", "ss"}

for inbound in cfg.get("inbounds", []):
    tag = inbound.get("tag")
    if tag in ROUTE_SNIFF_TAGS:
        inbound["sniffing"] = dict(ROUTE_SNIFFING)
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
        inbound_users = hy2_users()
        settings["users"] = inbound_users
        settings["clients"] = inbound_users

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
    local rc=$?
    end_argov_lock
    secure_work_dir_permissions
    return "$rc"
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
    # v2: 同步 Sing-box 每用户端口 + 重建设置 + 启动流量守护进程
    if [ "${SB_ENABLE:-false}" = "true" ] && sb_has_protocols && sb_is_installed 2>/dev/null; then
        sb_sync_users 2>/dev/null || true
        build_singbox_config 2>/dev/null || true
        sb_restart 2>/dev/null || true
        setup_traffic_counters 2>/dev/null || true
        start_sb_stats_service 2>/dev/null || true
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
    reset_day = str(u.get("reset_day") or 0)
    print("\t".join([u.get("name",""), enabled, str(used), str(quota), u.get("token",""), reset_day]))

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
elif op == "set-reset-day":
    name, day = args[:2]
    u = find(data, name)
    if not u:
        raise SystemExit(2)
    d = int(day)
    if d < 0 or d > 28:
        raise SystemExit(4)
    u["reset_day"] = d
    if d == 0:
        u.pop("last_reset_month", None)
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
    ensure_self_signed_cert "$HY2_SNI" "$HY2_CERT_FILE" "$HY2_KEY_FILE" || return 1
    HY2_PIN_SHA256=$(cert_pin_sha256 "$HY2_CERT_FILE")
}
gen_ss2022_pass() {
    local method="$1"
    [[ "$method" =~ 128 ]] && openssl rand -base64 16 || openssl rand -base64 32
}

# --- 持久化 ---
# MODULE: config persistence
load_conf() {
    if [ -f "$USER_CONF" ]; then
        if is_safe_conf_file "$USER_CONF"; then
            . "$USER_CONF"
        else
            red_msg "检测到异常配置，已跳过加载: $USER_CONF"
        fi
    fi
    NODE_NAME="${NODE_NAME:-ArgoV}"
    ARGO_PORT="${ARGO_PORT:-8080}"; VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
    VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
    CDN_PORT="${CDN_PORT:-443}"; CDN_DOMAIN="${CDN_DOMAIN:-$CDN_DEFAULT}"
    ARGO_MODE="${ARGO_MODE:-temp}"; [ "$ARGO_MODE" = "skip" ] && SKIP_ARGO=1 || SKIP_ARGO=0; ARGO_AUTH="${ARGO_AUTH:-}"
    ARGO_FIXED_DOMAIN="${ARGO_FIXED_DOMAIN:-}"; UUID_CUSTOM="${UUID_CUSTOM:-}"; LAST_ARGO_DOMAIN="${LAST_ARGO_DOMAIN:-}"
    REALITY_PORT="${REALITY_PORT:-0}"; HY2_PORT="${HY2_PORT:-0}"; HY2_MPORT="${HY2_MPORT:-}"
    HY2_CONGESTION="${HY2_CONGESTION:-bbr}"; HY2_UP_MBPS="${HY2_UP_MBPS:-}"; HY2_DOWN_MBPS="${HY2_DOWN_MBPS:-}"; SS_PORT="${SS_PORT:-0}"
    SUB_PORT="${SUB_PORT:-0}"; SUB_PATH="${SUB_PATH:-}"
    SUB_DOMAIN="${SUB_DOMAIN:-}"; SUB_TOKEN="${SUB_TOKEN:-}"; AGG_TOKEN="${AGG_TOKEN:-}"
    REALITY_SNI="${REALITY_SNI:-www.tesla.com}"; REALITY_FP="${REALITY_FP:-chrome}"; HY2_SNI="${HY2_SNI:-}"; SS_METHOD="${SS_METHOD:-aes-256-gcm}"
    ENABLE_REALITY="${ENABLE_REALITY:-0}"; ENABLE_HY2="${ENABLE_HY2:-0}"; ENABLE_SS="${ENABLE_SS:-0}"
    HY2_CERT_FILE="${HY2_CERT_FILE:-/etc/xray/argov-hy2.crt}"; HY2_KEY_FILE="${HY2_KEY_FILE:-/etc/xray/argov-hy2.key}"
    REALITY_PRIV="${REALITY_PRIV:-}"; REALITY_PUB="${REALITY_PUB:-}"
    if [ -z "$REALITY_PUB" ] && [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        REALITY_PUB=$(jq -r '.inbounds[]?|select(.tag=="reality")|.streamSettings.realitySettings.publicKey//empty' "$CONFIG_FILE" 2>/dev/null | head -n 1)
    fi

    if [ -z "$HY2_SNI" ] && [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        HY2_SNI=$(jq -r '.inbounds[]?|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//empty' "$CONFIG_FILE" 2>/dev/null | head -n 1)
    fi
    REALITY_SHORTID="${REALITY_SHORTID:-}"
    RELAY_ENABLED="${RELAY_ENABLED:-0}"; RELAY_LINK="${RELAY_LINK:-}"
    RELAY_MODE="${RELAY_MODE:-all}"
    XRAY_VERSION="${XRAY_VERSION:-latest}"; XRAY_SHA256="${XRAY_SHA256:-}"
    CLOUDFLARED_VERSION="${CLOUDFLARED_VERSION:-latest}"; CLOUDFLARED_SHA256="${CLOUDFLARED_SHA256:-}"
    # Sing-box defaults
    SB_ENABLE="${SB_ENABLE:-false}"; SB_VERSION="${SB_VERSION:-}"
    SB_HY2_ENABLE="${SB_HY2_ENABLE:-false}"; SB_HY2_CONGESTION="${SB_HY2_CONGESTION:-bbr}"; SB_HY2_UP_MBPS="${SB_HY2_UP_MBPS:-}"; SB_HY2_DOWN_MBPS="${SB_HY2_DOWN_MBPS:-}"; SB_HY2_BBR_PROFILE="${SB_HY2_BBR_PROFILE:-standard}"
    SB_TUIC_ENABLE="${SB_TUIC_ENABLE:-false}"; SB_ANYTLS_ENABLE="${SB_ANYTLS_ENABLE:-false}"
    SB_REALITY_ENABLE="${SB_REALITY_ENABLE:-false}"; SB_SS_ENABLE="${SB_SS_ENABLE:-false}"
    SB_HY2_PORT="${SB_HY2_PORT:-}"; SB_TUIC_PORT="${SB_TUIC_PORT:-}"; SB_ANYTLS_PORT="${SB_ANYTLS_PORT:-}"
    SB_REALITY_PORT="${SB_REALITY_PORT:-}"; SB_SS_PORT="${SB_SS_PORT:-}"
    SB_REALITY_PRIV="${SB_REALITY_PRIV:-}"; SB_REALITY_PUB="${SB_REALITY_PUB:-}"; SB_REALITY_SID="${SB_REALITY_SID:-}"
    SB_ANYTLS_PSK="${SB_ANYTLS_PSK:-}"; SB_TUIC_UUID="${SB_TUIC_UUID:-}"; SB_TUIC_PSK="${SB_TUIC_PSK:-}"
    SB_HY2_PSK="${SB_HY2_PSK:-}"; SB_SS_PSK="${SB_SS_PSK:-}"; SB_ANYTLS_USER="${SB_ANYTLS_USER:-argov}"
    SB_HY2_HOP_ENABLE="${SB_HY2_HOP_ENABLE:-false}"; SB_HY2_HOP_START="${SB_HY2_HOP_START:-}"; SB_HY2_HOP_END="${SB_HY2_HOP_END:-}"
    SB_HY2_HOP_MODE="${SB_HY2_HOP_MODE:-}"; SB_HY2_HOP_INTERVAL="${SB_HY2_HOP_INTERVAL:-}"; SB_HY2_HOP_MIN="${SB_HY2_HOP_MIN:-}"; SB_HY2_HOP_MAX="${SB_HY2_HOP_MAX:-}"
    HY2_PIN_SHA256="${HY2_PIN_SHA256:-}"; SB_HY2_PIN_SHA256="${SB_HY2_PIN_SHA256:-}"; SB_TUIC_PIN_SHA256="${SB_TUIC_PIN_SHA256:-}"

    SB_SNI="${SB_SNI:-addons.mozilla.org}"
    # Legacy installs inherit the original values until the user edits a protocol.
    if [ "${SB_HY2_ENABLE:-false}" = true ]; then SB_HY2_SNI="${SB_HY2_SNI:-$SB_SNI}"; else SB_HY2_SNI="${SB_HY2_SNI:-}"; fi
    SB_TUIC_SNI="${SB_TUIC_SNI:-$SB_SNI}"; SB_ANYTLS_SNI="${SB_ANYTLS_SNI:-$SB_SNI}"; SB_REALITY_SNI="${SB_REALITY_SNI:-$SB_SNI}"
    SB_SS_METHOD="${SB_SS_METHOD:-$SS_METHOD}"
    SB_CERT_FILE="${SB_CERT_FILE:-/etc/sing-box/certs/fullchain.pem}"; SB_KEY_FILE="${SB_KEY_FILE:-/etc/sing-box/certs/privkey.pem}"

    if [ "${SB_HY2_ENABLE:-false}" = true ]; then
        SB_HY2_CERT_FILE="${SB_HY2_CERT_FILE:-$SB_CERT_FILE}"; SB_HY2_KEY_FILE="${SB_HY2_KEY_FILE:-$SB_KEY_FILE}"
    else
        SB_HY2_CERT_FILE="${SB_HY2_CERT_FILE:-${SB_WORK_DIR}/certs/hy2.pem}"; SB_HY2_KEY_FILE="${SB_HY2_KEY_FILE:-${SB_WORK_DIR}/certs/hy2.key}"
    fi
    TRAFFIC_IN="${TRAFFIC_IN:-0}"; TRAFFIC_OUT="${TRAFFIC_OUT:-0}"
    [ -n "$HY2_MPORT" ] && ! is_port_range "$HY2_MPORT" && HY2_MPORT=""
}
save_conf() {
    mkdir -p "$WORK_DIR" 2>/dev/null
    local tmp
    tmp=$(mktemp "${USER_CONF}.tmp.XXXXXX") || return 1
    begin_argov_lock
    {
        echo "# ArgoV — $(date '+%Y-%m-%d %H:%M:%S')"
        save_var NODE_NAME "$NODE_NAME"
        save_var ARGO_PORT "$ARGO_PORT"; save_var VLESS_WS_PORT "$VLESS_WS_PORT"
        save_var VMESS_WS_PORT "$VMESS_WS_PORT"; save_var CDN_PORT "$CDN_PORT"
        save_var CDN_DOMAIN "$CDN_DOMAIN"; save_var ARGO_MODE "$ARGO_MODE"; save_var ARGO_AUTH "$ARGO_AUTH"
        save_var ARGO_FIXED_DOMAIN "$ARGO_FIXED_DOMAIN"; save_var UUID_CUSTOM "$UUID_CUSTOM"
        save_var REALITY_PORT "$REALITY_PORT"; save_var HY2_PORT "$HY2_PORT"; save_var HY2_MPORT "$HY2_MPORT"
        save_var HY2_CONGESTION "$HY2_CONGESTION"; save_var HY2_UP_MBPS "$HY2_UP_MBPS"; save_var HY2_DOWN_MBPS "$HY2_DOWN_MBPS"
        save_var SS_PORT "$SS_PORT"; save_var SUB_PORT "$SUB_PORT"; save_var SUB_PATH "$SUB_PATH"; save_var SUB_DOMAIN "$SUB_DOMAIN"; save_var SUB_TOKEN "$SUB_TOKEN"; save_var AGG_TOKEN "$AGG_TOKEN"
        save_var REALITY_SNI "$REALITY_SNI"; save_var REALITY_FP "$REALITY_FP"; save_var HY2_SNI "$HY2_SNI"; save_var SS_METHOD "$SS_METHOD"
        save_var ENABLE_REALITY "$ENABLE_REALITY"; save_var ENABLE_HY2 "$ENABLE_HY2"; save_var ENABLE_SS "$ENABLE_SS"
        save_var HY2_CERT_FILE "$HY2_CERT_FILE"; save_var HY2_KEY_FILE "$HY2_KEY_FILE"
        save_var REALITY_PRIV "$REALITY_PRIV"; save_var REALITY_PUB "$REALITY_PUB"
        save_var REALITY_SHORTID "$REALITY_SHORTID"; save_var LAST_ARGO_DOMAIN "$LAST_ARGO_DOMAIN"
        save_var RELAY_ENABLED "$RELAY_ENABLED"; save_var RELAY_LINK "$RELAY_LINK"; save_var RELAY_MODE "$RELAY_MODE"
        save_var XRAY_VERSION "$XRAY_VERSION"; save_var XRAY_SHA256 "$XRAY_SHA256"
        save_var CLOUDFLARED_VERSION "$CLOUDFLARED_VERSION"; save_var CLOUDFLARED_SHA256 "$CLOUDFLARED_SHA256"
        # Sing-box
        save_var SB_ENABLE "$SB_ENABLE"; save_var SB_VERSION "$SB_VERSION"
        save_var SB_HY2_ENABLE "$SB_HY2_ENABLE"; save_var SB_HY2_CONGESTION "$SB_HY2_CONGESTION"; save_var SB_HY2_UP_MBPS "$SB_HY2_UP_MBPS"; save_var SB_HY2_DOWN_MBPS "$SB_HY2_DOWN_MBPS"; save_var SB_HY2_BBR_PROFILE "$SB_HY2_BBR_PROFILE"
        save_var SB_TUIC_ENABLE "$SB_TUIC_ENABLE"; save_var SB_ANYTLS_ENABLE "$SB_ANYTLS_ENABLE"
        save_var SB_REALITY_ENABLE "$SB_REALITY_ENABLE"; save_var SB_SS_ENABLE "$SB_SS_ENABLE"
        save_var SB_HY2_PORT "$SB_HY2_PORT"; save_var SB_TUIC_PORT "$SB_TUIC_PORT"; save_var SB_ANYTLS_PORT "$SB_ANYTLS_PORT"
        save_var SB_REALITY_PORT "$SB_REALITY_PORT"; save_var SB_SS_PORT "$SB_SS_PORT"
        save_var SB_REALITY_PRIV "$SB_REALITY_PRIV"; save_var SB_REALITY_PUB "$SB_REALITY_PUB"; save_var SB_REALITY_SID "$SB_REALITY_SID"
        save_var SB_ANYTLS_PSK "$SB_ANYTLS_PSK"; save_var SB_TUIC_UUID "$SB_TUIC_UUID"; save_var SB_TUIC_PSK "$SB_TUIC_PSK"
        save_var SB_HY2_PSK "$SB_HY2_PSK"; save_var SB_SS_PSK "$SB_SS_PSK"; save_var SB_ANYTLS_USER "$SB_ANYTLS_USER"
        save_var SB_HY2_HOP_ENABLE "$SB_HY2_HOP_ENABLE"; save_var SB_HY2_HOP_START "$SB_HY2_HOP_START"; save_var SB_HY2_HOP_END "$SB_HY2_HOP_END"
        save_var SB_HY2_HOP_MODE "$SB_HY2_HOP_MODE"; save_var SB_HY2_HOP_INTERVAL "$SB_HY2_HOP_INTERVAL"; save_var SB_HY2_HOP_MIN "$SB_HY2_HOP_MIN"; save_var SB_HY2_HOP_MAX "$SB_HY2_HOP_MAX"
        save_var HY2_PIN_SHA256 "$HY2_PIN_SHA256"; save_var SB_HY2_PIN_SHA256 "$SB_HY2_PIN_SHA256"; save_var SB_TUIC_PIN_SHA256 "$SB_TUIC_PIN_SHA256"

        save_var SB_SNI "$SB_SNI"; save_var SB_CERT_FILE "$SB_CERT_FILE"; save_var SB_KEY_FILE "$SB_KEY_FILE"
        save_var SB_HY2_SNI "$SB_HY2_SNI"; save_var SB_TUIC_SNI "$SB_TUIC_SNI"
        save_var SB_ANYTLS_SNI "$SB_ANYTLS_SNI"; save_var SB_REALITY_SNI "$SB_REALITY_SNI"
        save_var SB_SS_METHOD "$SB_SS_METHOD"
        save_var SB_HY2_CERT_FILE "$SB_HY2_CERT_FILE"; save_var SB_HY2_KEY_FILE "$SB_HY2_KEY_FILE"
        save_var TRAFFIC_IN "$TRAFFIC_IN"; save_var TRAFFIC_OUT "$TRAFFIC_OUT"
    } > "$tmp" && mv -f "$tmp" "$USER_CONF"
    local rc=$?
    [ "$rc" -ne 0 ] && rm -f "$tmp" 2>/dev/null || true
    end_argov_lock
    secure_work_dir_permissions
    return "$rc"
}

#==============================================================================
# 链接生成
#==============================================================================
# MODULE: subscription generation and serving
ws_client_path() {
    local tag="$1" path
    path=$(jq -r --arg tag "$tag" '.inbounds[]?|select(.tag==$tag)|.streamSettings.wsSettings.path//empty' "$CONFIG_FILE" 2>/dev/null | head -n 1)
    path="${path:-$2}"
    case "$path" in
        *\?ed=*|*\&ed=*) ;;
        *\?*) path="${path}&ed=2560" ;;
        *) path="${path}?ed=2560" ;;
    esac
    printf '%s' "$path"
}
gen_vmess_link() {
    local json; json=$(jq -nc --arg name "${5:-${NODE_NAME}-VMess}" --arg cdn "${3:-$(get_cdn)}" --arg port "${4:-$(get_cdn_port)}" --arg uuid "$1" --arg host "$2" --arg path "$(ws_client_path vmess-ws /vmess-argo)" \
        '{v:"2",ps:$name,add:$cdn,port:$port,id:$uuid,aid:"0",scy:"none",net:"ws",type:"none",host:$host,path:$path,tls:"tls",sni:$host,alpn:"",fp:""}')
    printf '%s' "vmess://$(printf '%s' "$json" | base64 -w0 2>/dev/null || printf '%s' "$json" | base64 | tr -d '\n')"
}
gen_vless_link() {
    printf '%s' "vless://$1@${3:-$(get_cdn)}:${4:-$(get_cdn_port)}?encryption=none&security=tls&sni=$2&type=ws&host=$2&path=$(uri_encode "$(ws_client_path vless-ws /vless-argo)")#$(uri_encode "${5:-${NODE_NAME}-VLESS}")"
}
gen_ss_link() {
    local b64; b64=$(printf '%s' "$1:$2" | base64 -w0 2>/dev/null || printf '%s' "$1:$2" | base64 | tr -d '\n')
    printf '%s' "ss://${b64}@$3:$4#${5:-${NODE_NAME}-SS}"
}
gen_reality_link() {
    local sid=""
    [ -n "$6" ] && sid="&sid=$6"
    local fp="$8"; [ -z "$fp" ] && fp="${REALITY_FP:-chrome}"
    printf '%s' "vless://$1@$2:$3?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$4&pbk=$5&fp=${fp}${sid}#${7:-${NODE_NAME}-Reality}"
}
uri_encode() { jq -rn --arg value "$1" '$value | @uri'; }
uri_host() {
    case "$1" in \[*\]) printf '%s' "$1" ;; *:*) printf '[%s]' "$1" ;; *) printf '%s' "$1" ;; esac
}
client_hy2_bandwidth() {
    local mode_key="${1}_CONGESTION" up_key="${1}_UP_MBPS" down_key="${1}_DOWN_MBPS"
    local up="${!up_key}" down="${!down_key}"
    # ArgoV subscription hints for Mihomo; portable URI clients may ignore them.
    # Server upload is client download, and server download is client upload.
    if [ "${!mode_key}" = brutal ] && [[ "$up" =~ ^[0-9]{1,7}$ && "$down" =~ ^[0-9]{1,7}$ ]] && ((10#$up > 0 && 10#$down > 0)); then
        printf '&up=%smbps&down=%smbps' "$down" "$up"
    fi
    return 0
}
gen_hy2_link() {
    local mport="$6"
    local qs="sni=$4&alpn=h3"
    qs+="$(certificate_uri_options "${HY2_PIN_SHA256:-}")"
    [ -n "$mport" ] && qs="${qs}&mport=${mport}"
    qs+="$(client_hy2_bandwidth HY2)"
    printf '%s' "hysteria2://$1@$(uri_host "$2"):$3?${qs}#$(uri_encode "${5:-${NODE_NAME}-Hy2}")"
}

# Sing-box 链接生成
gen_sb_hy2_link() {
    # $1=pass $2=host $3=port $4=sni $5=name $6=hop_range (optional)
    local name="${5:-${NODE_NAME}-HY2}"
    local extra=""
    [ -n "$6" ] && extra="&mport=$6"
    extra+="$(certificate_uri_options "${SB_HY2_PIN_SHA256:-}")"
    extra+="$(client_hy2_bandwidth SB_HY2)"
    printf '%s' "hy2://$(uri_encode "$1")@$(uri_host "$2"):$3?sni=${4}&alpn=h3${extra}#$(uri_encode "$name")"
}
gen_sb_tuic_link() {
    # $1=uuid $2=pass $3=host $4=port $5=sni $6=name
    local name="${6:-${NODE_NAME}-TUIC}"
    printf '%s' "tuic://$1:$(uri_encode "$2")@$(uri_host "$3"):$4?congestion_control=bbr&alpn=h3&sni=${5}$(certificate_uri_options "${SB_TUIC_PIN_SHA256:-}")#$(uri_encode "$name")"
}
gen_sb_anytls_link() {
    # $1=pass $2=host $3=port $4=sni $5=pbk $6=sid $7=name
    local name="${7:-${NODE_NAME}-AnyTLS}"
    printf '%s' "anytls://$(uri_encode "$1")@$(uri_host "$2"):$3?security=reality&sni=${4}&fp=chrome&pbk=${5}&sid=${6}#$(uri_encode "$name")"
}
gen_sb_reality_link() {
    # $1=uuid $2=host $3=port $4=sni $5=pbk $6=sid $7=name
    local name="${7:-${NODE_NAME}-Reality}"
    printf '%s' "vless://$1@$(uri_host "$2"):$3?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${4}&pbk=${5}&fp=chrome&sid=${6}#$(uri_encode "$name")"
}
gen_sb_ss_link() {
    # $1=method $2=pass $3=host $4=port $5=name
    local b64; b64=$(printf '%s' "$1:$2" | base64 -w0 2>/dev/null || printf '%s' "$1:$2" | base64 | tr -d '\n')
    local name="${5:-${NODE_NAME}-SS}"
    printf '%s' "ss://${b64}@$(uri_host "$3"):$4#$(uri_encode "$name")"
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
    download_file "https://github.com/eooce/test/releases/download/${a}/qrencode-linux-${a}" "$qr" >/dev/null 2>&1 && chmod +x "$qr" 2>/dev/null
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
            echo -e "  ${green}1${re}. 添加域名 (HTTP → HTTPS, 自动选端口)"
            echo -e "  ${green}2${re}. 修改端口 — ${cyan}${SUB_PORT}${re}"
        fi
        echo -e "  ${green}4${re}. 随机生成 Token"
        echo -e "  ${purple}5${re}. 自定义 Token (手动输入)"
        echo -e "  ${cyan}6${re}. 查看完整订阅链接"
        echo ""; echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  请选择: "; read c 
        case "$c" in
            1)
                if [ -n "$SUB_DOMAIN" ]; then
                    local old_domain="$SUB_DOMAIN"
                    echo -ne "  新域名 [${SUB_DOMAIN}]: "; read nd 
                    [ -n "$nd" ] && SUB_DOMAIN="$nd"
                else
                    echo -e "  ${yellow}输入已指向本机 IP 的域名，将切换到 HTTPS:${re}"
                    echo -e "  ${yellow}⚠ CF 代理仅支持以下端口，请选择:${re}"
                    echo -ne "  域名: "; read nd
                    [ -z "$nd" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                    SUB_DOMAIN="$nd"
                    echo ""; echo -e "  ${yellow}选择 CF HTTPS 端口:${re}"
                    echo -e "  ${cyan}1${re}. 2096 (默认)  ${cyan}2${re}. 8443  ${cyan}3${re}. 2053  ${cyan}4${re}. 2083  ${cyan}5${re}. 2087  ${cyan}6${re}. 443"
                    echo -ne "  [1]: "; read pc
                    case "${pc:-1}" in
                        2) SUB_PORT=8443 ;; 3) SUB_PORT=2053 ;; 4) SUB_PORT=2083 ;;
                        5) SUB_PORT=2087 ;; 6) SUB_PORT=443 ;; *) SUB_PORT=2096 ;;
                    esac
                fi
                # 域名变了 → 删旧证书让 start_sub_server 重新生成
                [ -n "$old_domain" ] && [ "$old_domain" != "$SUB_DOMAIN" ] && rm -f "${WORK_DIR}/sub_cert.pem" "${WORK_DIR}/sub_key.pem"
                save_conf; start_sub_server; green_msg "已更新。"; sleep 1
                ;;
            2)
                echo -ne "  新端口 [${SUB_PORT}]: "; read np 
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
            5)
                echo -ne "  ${yellow}输入自定义 Token (留空取消):${re} "; read ct
                [ -z "$ct" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                SUB_TOKEN="$ct"; SUB_PATH="/${SUB_TOKEN}"; save_conf
                start_sub_server; green_msg "Token: ${SUB_TOKEN}"; sleep 1
                ;;
            6) echo ""; echo -e "  ${green}$(get_sub_url 2>/dev/null)${re}"; echo ""; echo -ne "  按回车继续..."; read -r ;;
            0) return ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

start_sub_server() {
    [ -z "$AGG_TOKEN" ] && AGG_TOKEN=$(rand_token) && save_conf
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

    local sub_settings sub_settings_literal sub_candidate
    sub_settings=$(jq -nc --arg work "$WORK_DIR" --arg name "$NODE_NAME" --arg token "$SUB_TOKEN" --arg path "$SUB_PATH" --arg agg "$AGG_TOKEN" --arg port "$SUB_PORT" \
        '{work:$work,name:$name,token:$token,path:$path,agg:$agg,port:$port}') || return 1
    sub_settings_literal=$(jq -rn --arg value "$sub_settings" '$value | @json') || return 1
    sub_candidate=$(mktemp "${WORK_DIR}/sub.py.new.XXXXXX") || return 1
    cat > "$sub_candidate" << PYEOF
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
import subprocess, os, socketserver, threading, time
import base64, json, urllib.parse

SETTINGS=json.loads(${sub_settings_literal})
WORK_DIR=SETTINGS['work']; NODE_NAME=SETTINGS['name']; SUB_TOKEN=SETTINGS['token']; SUB_PATH=SETTINGS['path']; AGG_TOKEN=SETTINGS['agg']
SUB_FILE='/etc/xray/sub.txt'; PORT=int(SETTINGS['port'])
USERS_FILE='/etc/xray/argov_users.json'; GEN_SCRIPT=os.path.join(WORK_DIR, 'sub_gen.sh')
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

def share_cert_pin(qs):
    pin = next((qs[k][0] for k in ("pinSHA256", "pcs", "pinnedPeerCertSha256") if qs.get(k)), "")
    if not pin:
        return ""
    pin = pin.replace(":", "")
    if len(pin) != 64 or any(c not in "0123456789abcdefABCDEF" for c in pin):
        raise ValueError("证书 SHA256 指纹格式无效，请检查原始链接")
    return pin

def clash_tls_options(p, qs):
    if qs.get("fp", [""])[0]:
        p["client-fingerprint"] = qs["fp"][0]
    if qs.get("alpn", [""])[0]:
        p["alpn"] = [v for v in qs["alpn"][0].split(",") if v]
    pin = share_cert_pin(qs)
    if pin:
        p["fingerprint"] = pin
        p["skip-cert-verify"] = False
    else:
        value = next((qs[k][0] for k in ("allowInsecure", "insecure", "skip-cert-verify") if qs.get(k)), "")
        if value:
            p["skip-cert-verify"] = value.lower() in ("1", "true", "yes")

def clash_xhttp_options(qs):
    opts = {"path": qs.get("path", ["/"])[0] or "/", "host": qs.get("host", [""])[0], "mode": qs.get("mode", ["auto"])[0]}
    extra = json.loads(qs.get("extra", ["{}"]) [0])
    if not isinstance(extra, dict):
        raise ValueError("XHTTP extra 必须是 JSON 对象，请使用原始链接")
    # 显式映射，避免把未知字段丢掉后输出无法连接的节点。
    mapping = {
        "headers": "headers", "noGRPCHeader": "no-grpc-header", "xPaddingBytes": "x-padding-bytes",
        "xPaddingObfsMode": "x-padding-obfs-mode", "xPaddingKey": "x-padding-key", "xPaddingHeader": "x-padding-header",
        "xPaddingPlacement": "x-padding-placement", "xPaddingMethod": "x-padding-method", "uplinkHTTPMethod": "uplink-http-method",
        "sessionPlacement": "session-placement", "sessionKey": "session-key", "sessionTable": "session-table", "sessionLength": "session-length",
        "seqPlacement": "seq-placement", "seqKey": "seq-key", "uplinkDataPlacement": "uplink-data-placement", "uplinkDataKey": "uplink-data-key",
        "uplinkChunkSize": "uplink-chunk-size", "scMaxEachPostBytes": "sc-max-each-post-bytes", "scMinPostsIntervalMs": "sc-min-posts-interval-ms",
    }
    ranges = {"xPaddingBytes", "sessionLength", "uplinkChunkSize", "scMaxEachPostBytes", "scMinPostsIntervalMs"}
    for key, value in extra.items():
        if key in mapping:
            opts[mapping[key]] = str(value) if key in ranges else value
        elif key == "xmux":
            xmux_map = {"maxConcurrency": "max-concurrency", "maxConnections": "max-connections", "cMaxReuseTimes": "c-max-reuse-times",
                        "hMaxRequestTimes": "h-max-request-times", "hMaxReusableSecs": "h-max-reusable-secs", "hKeepAlivePeriod": "h-keep-alive-period"}
            if not isinstance(value, dict) or any(k not in xmux_map for k in value):
                raise ValueError("XHTTP xmux 包含尚未支持的参数，请使用原始链接")
            opts["reuse-settings"] = {xmux_map[k]: int(v) if k == "hKeepAlivePeriod" else str(v) for k, v in value.items()}
        else:
            raise ValueError("XHTTP 参数 " + key + " 尚未支持转换，请使用原始链接")
    return opts

def clash_transport_options(p, qs):
    network = qs.get("type", qs.get("network", ["tcp"]))[0] or "tcp"
    path, host = qs.get("path", ["/"])[0] or "/", qs.get("host", [""])[0]
    if network in ("tcp", "raw"):
        return
    if network == "ws":
        p.update({"network": "ws", "ws-opts": {"path": path, "headers": {"Host": host}}})
    elif network == "httpupgrade":
        p.update({"network": "ws", "ws-opts": {"path": path, "headers": {"Host": host}, "v2ray-http-upgrade": True}})
    elif network == "grpc":
        p.update({"network": "grpc", "grpc-opts": {"grpc-service-name": qs.get("serviceName", [""])[0]}})
    elif network in ("xhttp", "splithttp") and p["type"] == "vless":
        p.update({"network": "xhttp", "xhttp-opts": clash_xhttp_options(qs)})
    elif network == "h2":
        p.update({"network": "h2", "h2-opts": {"path": path, "host": [host] if host else []}})
    else:
        raise ValueError("传输 " + network + " 尚未支持转换，请使用原始链接")

def build_clash(lines):
    proxies, names, errors = [], [], []
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
                p = {"name": urllib.parse.unquote(name), "type": "vless", "server": host, "port": port, "uuid": uuid, "udp": True, "encryption": qs.get("encryption", ["none"])[0]}
                if qs.get("flow", [""])[0]:
                    p["flow"] = qs.get("flow", [""])[0]
                if qs.get("security", [""])[0] == "tls":
                    p.update({"tls": True, "servername": qs.get("sni", [""])[0]})
                elif qs.get("security", [""])[0] == "reality":
                    p.update({"tls": True, "servername": qs.get("sni", [""])[0], "client-fingerprint": qs.get("fp", ["chrome"])[0], "reality-opts": {"public-key": qs.get("pbk", [""])[0], "short-id": qs.get("sid", [""])[0]}})
                clash_tls_options(p, qs)
                clash_transport_options(p, qs)
            elif l.startswith("vmess://"):
                j = json.loads(base64.b64decode(l[8:] + "==").decode())
                p = {"name": j.get("ps", "VMess"), "type": "vmess", "server": j.get("add"), "port": int(j.get("port")), "uuid": j.get("id"), "alterId": int(j.get("aid", 0)), "cipher": j.get("scy", "auto"), "udp": True}
                if j.get("net") == "ws":
                    p.update({"network": "ws", "ws-opts": {"path": j.get("path", "/"), "headers": {"Host": j.get("host", "")}}})
                if str(j.get("tls")) == "tls":
                    p.update({"tls": True, "servername": j.get("sni", "")})
                    clash_tls_options(p, {k: [str(v)] for k, v in j.items() if v is not None})
                clash_transport_options(p, {"type": [j.get("net", "tcp")], "path": [j.get("path", "/")], "host": [j.get("host", "")], "serviceName": [j.get("path", "")]})
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
                clash_tls_options(p, qs)
                clash_transport_options(p, qs)
            elif l.startswith(("hysteria2://", "hy2://")):
                link = l.split("://", 1)[1]
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
                clash_tls_options(p, qs)
                for field in ("up", "down"):
                    bandwidth = qs.get(field, [""])[0]
                    numeric = bandwidth.lower().replace(" ", "")
                    for suffix in ("mbps", "kbps", "gbps"):
                        if numeric.endswith(suffix):
                            numeric = numeric[:-len(suffix)]
                            break
                    if numeric.replace(".", "", 1).isdigit() and float(numeric) > 0:
                        p[field] = bandwidth
                mport = qs.get("mport", qs.get("ports", [""]))[0]
                if mport:
                    p["ports"] = mport
                    p["hop-interval"] = 30
            elif l.startswith("tuic://"):
                link = l[7:]
                name = "TUIC"
                if "#" in link: link, name = link.split("#", 1)
                base, q = link.split("?", 1) if "?" in link else (link, "")
                qs = urllib.parse.parse_qs(q)
                userinfo, server = base.split("@", 1)
                uid, pwd = userinfo.split(":", 1) if ":" in userinfo else (userinfo, "")
                host, port = split_host_port(server)
                p = {"name": urllib.parse.unquote(name), "type": "tuic", "server": host, "port": port, "uuid": urllib.parse.unquote(uid), "password": urllib.parse.unquote(pwd), "udp": True}
                if qs.get("sni", [""])[0]: p["sni"] = qs.get("sni", [""])[0]
                if qs.get("alpn", [""])[0]: p["alpn"] = [i for i in qs.get("alpn", [""])[0].split(",") if i]
                if qs.get("insecure", [""])[0] or qs.get("skip-cert-verify", [""])[0]:
                    p["skip-cert-verify"] = bool_qs(qs.get("insecure", qs.get("skip-cert-verify", ["false"]))[0])
                if qs.get("congestion_control", [""])[0]: p["congestion-controller"] = qs["congestion_control"][0]
                if qs.get("udp_relay_mode", [""])[0]: p["udp-relay-mode"] = qs["udp_relay_mode"][0]
                clash_tls_options(p, qs)
            elif l.startswith("anytls://"):
                link = l[9:]
                name = "AnyTLS"
                if "#" in link: link, name = link.split("#", 1)
                base, q = link.split("?", 1) if "?" in link else (link, "")
                qs = urllib.parse.parse_qs(q)
                pwd, server = base.split("@", 1)
                host, port = split_host_port(server)
                p = {"name": urllib.parse.unquote(name), "type": "anytls", "server": host, "port": port, "password": urllib.parse.unquote(pwd), "udp": True}
                if qs.get("sni", [""])[0]: p["sni"] = qs.get("sni", [""])[0]
                if qs.get("fp", [""])[0]: p["client-fingerprint"] = qs.get("fp", [""])[0]
                if qs.get("pbk", [""])[0]: p["reality-opts"] = {"public-key": qs.get("pbk", [""])[0], "short-id": qs.get("sid", [""])[0]}
                clash_tls_options(p, qs)

            if p:
                proxies.append(p)
                names.append(p["name"])
        except Exception as exc:
            # 不输出链接、密码或 UUID；转换错误保留在订阅注释中。
            errors.append("ArgoV: " + l.split(":", 1)[0] + " 转换失败: " + str(exc))
    
    if not proxies:
        if errors:
            raise ValueError("; ".join(errors))
        return ""
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
    result = to_yaml(cfg)
    if errors:
        result = "\\n".join("# " + e.replace("\\n", " ").replace("\\r", " ") for e in errors) + "\\n" + result
    return result

def load_users():
    try:
        with open(USERS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f).get('users', [])
    except:
        return []

def resolve_token(path, qs):
    tok = qs.get('token', [None])[0]
    if path == SUB_PATH or tok == SUB_TOKEN:
        return SUB_TOKEN, True
    if not tok:
        return None, False
    for u in load_users():
        if u.get('token') == tok and u.get('enabled', True):
            return tok, False
    return None, False

def refresh_cache(token):
    try:
        raw = b''
        for attempt in (1, 2):
            result = subprocess.run([GEN_SCRIPT, token], capture_output=True, timeout=15)
            raw = result.stdout
            if raw:
                break
            time.sleep(2)
        if not raw:
            with CACHE_LOCK:
                return CACHE.get(token)  # 失败保留旧缓存
        raw_lines = base64.b64decode(raw).decode('utf-8', errors='ignore').splitlines()
        clash = build_clash(raw_lines).encode('utf-8')
        with CACHE_LOCK:
            CACHE[token] = (raw, clash)
        return CACHE[token]
    except:
        with CACHE_LOCK:
            return CACHE.get(token)  # 异常保留旧缓存

def get_cache(token):
    with CACHE_LOCK:
        item = CACHE.get(token)
    if item:
        return item
    # 缓存未命中 → 不阻塞请求，后台异步刷新；临时返回默认用户缓存
    if token:
        threading.Thread(target=lambda: refresh_cache(token), daemon=True).start()
    with CACHE_LOCK:
        return CACHE.get(token)  # 不 fallback 到 default, 避免限额用户拿到共享节点

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
                safe_name = up.quote(NODE_NAME, safe='')
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
        elif req_path == '/agg':
            tok = qs.get('token', [None])[0]
            if tok == AGG_TOKEN:
                try:
                    if not os.path.exists(os.path.join(WORK_DIR, 'agg_raw.txt')):
                        s.send_response(503)
                        s.send_header('Content-Type','text/plain; charset=utf-8')
                        s.send_header('Connection', 'close')
                        s.end_headers(); s.wfile.write(b'waiting for first sync...')
                    else:
                        with open(os.path.join(WORK_DIR, 'agg_raw.txt'), 'rb') as f:
                            agg = f.read()
                        s.send_response(200)
                        s.send_header('Content-Type','text/plain; charset=utf-8')
                        s.send_header('Content-Length', str(len(agg)))
                        s.send_header('Connection', 'close')
                        s.end_headers(); s.wfile.write(agg)
                except:
                    s.send_response(500)
                    s.send_header('Connection', 'close')
                    s.end_headers()
            else:
                s.send_response(404)
                s.send_header('Connection', 'close')
                s.end_headers()
        else:
            s.send_response(404)
            s.send_header('Connection', 'close')
            s.end_headers()
    def log_message(s,*a): pass

# 后台定时刷新（首次+每60秒）
refresh_cache(SUB_TOKEN)
def bg_refresh():
    while True:
        time.sleep(10)
        # 聚合订阅刷新（先跑，不阻塞 token 刷新）
        if os.path.exists(os.path.join(WORK_DIR, 'agg_gen.sh')):
            try:
                subprocess.run([os.path.join(WORK_DIR, 'agg_gen.sh')], timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except: pass
        with CACHE_LOCK:
            toks=list(CACHE.keys())
        for tok in toks:
            refresh_cache(tok)
threading.Thread(target=bg_refresh,daemon=True).start()

import ssl, os
CERT=os.path.join(WORK_DIR, 'sub_cert.pem'); KEY=os.path.join(WORK_DIR, 'sub_key.pem')
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

    if ! "$py" -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$sub_candidate"; then
        rm -f "$sub_candidate"
        red_msg "订阅程序语法检查失败，已保留旧程序。"
        restart_protocol_runtime argov-sub >/dev/null 2>&1 || true
        return 1
    fi
    mv -f "$sub_candidate" "${WORK_DIR}/sub.py" || return 1

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
    [ -f "$LOG" ] && for i in 1 2 3 4 5; do
        d=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' "$LOG" | tail -1)
        [ -n "$d" ] && echo "$d" && return; sleep 2
    done
    echo "$LAST_ARGO_DOMAIN"
}
b64() { printf '%s' "$1" | base64 -w0 2>/dev/null || printf '%s' "$1" | base64 | tr -d '\n'; }
cert_pin_sha256() {
    [ -f "$1" ] || return 1
    openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//' | tr '[:lower:]' '[:upper:]'
}
certificate_uri_options() {
    local pin="${1//:/}"
    printf '&insecure=1&allowInsecure=0'
    [[ "$pin" =~ ^[[:xdigit:]]{64}$ ]] && printf '&pinSHA256=%s' "$pin"
    return 0
}
[ -f "$USERS" ] || exit 1
# 默认用户永远有效（即使被误禁用）；其他用户需 enabled=true
UQ='if ($tok == "" or $tok == $dtok) then (.users[]|select(.name=="default")) else (.users[]|select(.token==$tok and (.enabled//true))) end'
USER_JSON=$($JQ -c --arg tok "$USER_TOKEN" --arg dtok "${SUB_TOKEN:-}" "$UQ" "$USERS" 2>/dev/null | head -n 1)
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
cdn=$($JQ -r '.current_cdn//"xx.cloudflare.182682.xyz"' "$CFG")
cp=$($JQ -r '.current_cdn_port//443' "$CFG")
hd=$(get_domain)
ip=""; for s in ifconfig.me icanhazip.com checkip.amazonaws.com api.ipify.org; do
    ip=$(curl -s --max-time 3 "$s" 2>/dev/null || wget -qO- -T3 "$s" 2>/dev/null)
    echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' && break || ip=""
done
[ "$MODE" = "fixed-token" ] && hd="$FIXED"
[ "$MODE" = "skip" ] && hd=""
uri_encode() { "$JQ" -rn --arg value "$1" '$value | @uri'; }
uri_host() { if [[ "$1" == *:* && "$1" != \[*\] ]]; then printf '[%s]' "$1"; else printf '%s' "$1"; fi; }
ip_host=$(uri_host "$ip")
links=""
if [ -n "$hd" ]; then
    ws_client_path() {
        local tag="$1" path
        path=$("$JQ" -r --arg tag "$tag" '.inbounds[]?|select(.tag==$tag)|.streamSettings.wsSettings.path//empty' "$CFG" | head -n 1)
        path="${path:-$2}"
        case "$path" in
            *\?ed=*|*\&ed=*) ;;
            *\?*) path="${path}&ed=2560" ;;
            *) path="${path}?ed=2560" ;;
        esac
        printf '%s' "$path"
    }
    links+="vless://${uuid}@${cdn}:${cp}?encryption=none&security=tls&sni=${hd}&type=ws&host=${hd}&path=$(uri_encode "$(ws_client_path vless-ws /vless-argo)")#$(uri_encode "${NODE_NAME}-VLESS")"$'\n'
    j=$("$JQ" -nc --arg name "${NODE_NAME}-VMess" --arg cdn "$cdn" --arg port "$cp" --arg uuid "$uuid" --arg host "$hd" --arg path "$(ws_client_path vmess-ws /vmess-argo)" \
        '{v:"2",ps:$name,add:$cdn,port:$port,id:$uuid,aid:"0",scy:"none",net:"ws",type:"none",host:$host,path:$path,tls:"tls",sni:$host,alpn:"",fp:""}')
    links+="vmess://$(b64 "$j")"$'\n'
fi
client_hy2_bandwidth() {
    local mode_key="${1}_CONGESTION" up_key="${1}_UP_MBPS" down_key="${1}_DOWN_MBPS"
    local up="${!up_key}" down="${!down_key}"
    # ArgoV subscription hints for Mihomo; portable URI clients may ignore them.
    # Server upload is client download, and server download is client upload.
    if [ "${!mode_key}" = brutal ] && [[ "$up" =~ ^[0-9]{1,7}$ && "$down" =~ ^[0-9]{1,7}$ ]] && ((10#$up > 0 && 10#$down > 0)); then
        printf '&up=%smbps&down=%smbps' "$down" "$up"
    fi
    return 0
}
if $JQ -e '.inbounds[]|select(.tag=="reality")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    rport=$($JQ -r '.inbounds[]|select(.tag=="reality")|.port' "$CFG")
    rs=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]' "$CFG")
    rpub="${REALITY_PUB:-}"
    [ -n "$rpub" ] || rpub=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey//empty' "$CFG")
    rsid=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds[0]//empty' "$CFG")
    [ -n "$rsid" ] && rsid="&sid=${rsid}" || rsid=""
    [ -n "$rport" ] && links+="vless://${uuid}@${ip_host}:${rport}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${rs}&pbk=${rpub}&fp=${REALITY_FP:-chrome}${rsid}#$(uri_encode "${NODE_NAME}-Reality")"$'\n'
fi
# 自定义链接（用户自添加）
if [ "$INCLUDE_CUSTOM" = "1" ] && [ -f /etc/xray/custom_links.txt ]; then
    while IFS= read -r cl; do
        [ -n "$cl" ] && links+="${cl}"$'\n'
    done < /etc/xray/custom_links.txt
fi
if $JQ -e '.inbounds[]|select(.tag=="hy2")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    hport=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.port' "$CFG")
    hsni=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//empty' "$CFG")
    hmport=$($JQ -r '.inbounds[]|select(.tag=="hy2")|(.streamSettings.finalmask.quicParams.udpHop.ports//.streamSettings.hysteriaSettings.quicParams.udpHop.ports[0]//empty)' "$CFG")
    hmport_qs=""; [ -n "$hmport" ] && hmport_qs="&mport=${hmport}"
    hcert=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.certificates[0].certificateFile//empty' "$CFG")
    hpin=$(cert_pin_sha256 "${hcert:-${HY2_CERT_FILE:-}}")
    hy2_extra=$(certificate_uri_options "${hpin:-${HY2_PIN_SHA256:-}}")
    hy2_extra+="$(client_hy2_bandwidth HY2)"
    [ -n "$hport" ] && links+="hysteria2://${uuid}@${ip_host}:${hport}?sni=${hsni:-${HY2_SNI:-}}&alpn=h3${hmport_qs}${hy2_extra}#$(uri_encode "${NODE_NAME}-HY2")"$'\n'
fi
# ===== Sing-box 节点 (仅 default 用户获取共享端口; 限额用户用专属端口) =====
SB_CFG="/etc/sing-box/config.json"
if [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CFG" ] && [ -n "$ip" ]; then
    SB_SNI="${SB_SNI:-addons.mozilla.org}"
    sb_hcert=$($JQ -r '.inbounds[]?|select(.tag=="sb-hy2")|.tls.certificate_path//empty' "$SB_CFG" | head -n 1)
    sb_hpin=$(cert_pin_sha256 "${sb_hcert:-${SB_HY2_CERT_FILE:-${SB_CERT_FILE:-}}}")
    sb_hy2_tls=$(certificate_uri_options "${sb_hpin:-${SB_HY2_PIN_SHA256:-}}")
    sb_tcert=$($JQ -r '.inbounds[]?|select(.tag=="sb-tuic")|.tls.certificate_path//empty' "$SB_CFG" | head -n 1)
    sb_tpin=$(cert_pin_sha256 "${sb_tcert:-${SB_CERT_FILE:-}}")
    sb_tuic_tls=$(certificate_uri_options "${sb_tpin:-${SB_TUIC_PIN_SHA256:-}}")
    sb_hy2_name="${NODE_NAME}-HY2"
    sb_reality_name="${NODE_NAME}-Reality"
    sb_ss_name="${NODE_NAME}-SS"
    $JQ -e '.inbounds[]|select(.tag=="hy2")' "$CFG" >/dev/null 2>&1 && sb_hy2_name="${NODE_NAME}-SingBox-HY2"
    $JQ -e '.inbounds[]|select(.tag=="reality")' "$CFG" >/dev/null 2>&1 && sb_reality_name="${NODE_NAME}-SingBox-Reality"
    $JQ -e '.inbounds[]|select(.tag=="ss")' "$CFG" >/dev/null 2>&1 && sb_ss_name="${NODE_NAME}-SingBox-SS"
    if [ "$IS_DEFAULT_USER" = "1" ]; then
        # 共享节点 — 仅 default 用户. 直接读 conf 变量, 不 jq 查 config.json
        sb_hy2_hop=""
        [ "${SB_HY2_HOP_ENABLE:-false}" = "true" ] && sb_hy2_hop="&mport=${SB_HY2_HOP_START}-${SB_HY2_HOP_END}"
        if [ "${SB_HY2_ENABLE:-false}" = "true" ] && [ -n "${SB_HY2_PORT:-}" ] && [ -n "${SB_HY2_PSK:-}" ]; then
            sb_hy2_pin="$sb_hy2_tls"
            sb_hy2_pin+="$(client_hy2_bandwidth SB_HY2)"
            links+="hy2://$(uri_encode "$SB_HY2_PSK")@${ip_host}:${SB_HY2_PORT}?sni=${SB_HY2_SNI:-$SB_SNI}&alpn=h3${sb_hy2_hop}${sb_hy2_pin}#$(uri_encode "$sb_hy2_name")"$'\n'
        fi
        if [ "${SB_TUIC_ENABLE:-false}" = "true" ] && [ -n "${SB_TUIC_PORT:-}" ] && [ -n "${SB_TUIC_UUID:-}" ]; then
            links+="tuic://${SB_TUIC_UUID}:$(uri_encode "$SB_TUIC_PSK")@${ip_host}:${SB_TUIC_PORT}?congestion_control=bbr&alpn=h3&sni=${SB_TUIC_SNI:-$SB_SNI}${sb_tuic_tls}#$(uri_encode "${NODE_NAME}-TUIC")"$'\n'
        fi
        if [ "${SB_ANYTLS_ENABLE:-false}" = "true" ] && [ -n "${SB_ANYTLS_PORT:-}" ] && [ -n "${SB_ANYTLS_PSK:-}" ]; then
            links+="anytls://$(uri_encode "$SB_ANYTLS_PSK")@${ip_host}:${SB_ANYTLS_PORT}?security=reality&sni=${SB_ANYTLS_SNI:-$SB_SNI}&fp=chrome&pbk=${SB_REALITY_PUB:-}&sid=${SB_REALITY_SID:-}#$(uri_encode "${NODE_NAME}-AnyTLS")"$'\n'
        fi
        if [ "${SB_REALITY_ENABLE:-false}" = "true" ] && [ -n "${SB_REALITY_PORT:-}" ]; then
            links+="vless://${uuid}@${ip_host}:${SB_REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SB_REALITY_SNI:-$SB_SNI}&pbk=${SB_REALITY_PUB:-}&fp=chrome&sid=${SB_REALITY_SID:-}#$(uri_encode "$sb_reality_name")"$'\n'
        fi
        if [ "${SB_SS_ENABLE:-false}" = "true" ] && [ -n "${SB_SS_PORT:-}" ] && [ -n "${SB_SS_PSK:-}" ]; then
            sb_ss_b64=$(printf '%s' "${SB_SS_METHOD:-${SS_METHOD:-aes-256-gcm}}:${SB_SS_PSK}" | base64 -w0 2>/dev/null || printf '%s' "${SB_SS_METHOD:-${SS_METHOD:-aes-256-gcm}}:${SB_SS_PSK}" | base64 | tr -d '\n')
            links+="ss://${sb_ss_b64}@${ip_host}:${SB_SS_PORT}#$(uri_encode "$sb_ss_name")"$'\n'
        fi
    else
    # v2: 限额用户获取自己专属的 Sing-box 节点 (独立端口+密码, 可追踪流量)
        sb_ports=$(printf '%s' "$USER_JSON" | $JQ -c '.sb_ports // {}' 2>/dev/null)
        sb_creds=$(printf '%s' "$USER_JSON" | $JQ -c '.sb_creds // {}' 2>/dev/null)
        # HY2 不走限额用户 — 跳变兼容性问题
        # TUIC per-user
        tuic_up=$(echo "$sb_ports" | $JQ -r '.tuic // 0')
        if [ "${SB_TUIC_ENABLE:-false}" = true ] && [ "$tuic_up" -gt 0 ]; then
            t_uuid=$(echo "$sb_creds" | $JQ -r '.tuic_uuid // ""')
            t_pass=$(echo "$sb_creds" | $JQ -r '.tuic_pass // ""')
            [ -n "$t_uuid" ] && links+="tuic://${t_uuid}:$(uri_encode "$t_pass")@${ip_host}:${tuic_up}?congestion_control=bbr&alpn=h3&sni=${SB_TUIC_SNI:-$SB_SNI}${sb_tuic_tls}#$(uri_encode "${NODE_NAME}-TUIC")"$'\n'
        fi
        # AnyTLS per-user
        anytls_up=$(echo "$sb_ports" | $JQ -r '.anytls // 0')
        if [ "${SB_ANYTLS_ENABLE:-false}" = true ] && [ "$anytls_up" -gt 0 ]; then
            a_pass=$(echo "$sb_creds" | $JQ -r '.anytls_pass // ""')
            [ -n "$a_pass" ] && links+="anytls://$(uri_encode "$a_pass")@${ip_host}:${anytls_up}?security=reality&sni=${SB_ANYTLS_SNI:-$SB_SNI}&fp=chrome&pbk=${SB_REALITY_PUB:-}&sid=${SB_REALITY_SID:-}#$(uri_encode "${NODE_NAME}-AnyTLS")"$'\n'
        fi
        # Reality per-user
        reality_up=$(echo "$sb_ports" | $JQ -r '.reality // 0')
        if [ "${SB_REALITY_ENABLE:-false}" = true ] && [ "$reality_up" -gt 0 ]; then
            links+="vless://${uuid}@${ip_host}:${reality_up}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SB_REALITY_SNI:-$SB_SNI}&pbk=${SB_REALITY_PUB:-}&fp=chrome&sid=${SB_REALITY_SID:-}#$(uri_encode "$sb_reality_name")"$'\n'
        fi
        # SS per-user
        ss_up=$(echo "$sb_ports" | $JQ -r '.ss // 0')
        if [ "${SB_SS_ENABLE:-false}" = true ] && [ "$ss_up" -gt 0 ]; then
            ss_pass=$(echo "$sb_creds" | $JQ -r '.ss_pass // ""')
            ss_m="${SB_SS_METHOD:-${SS_METHOD:-aes-256-gcm}}"
            [ -n "$ss_pass" ] && { ss_b64=$(printf '%s' "${ss_m}:${ss_pass}" | base64 -w0 2>/dev/null || printf '%s' "${ss_m}:${ss_pass}" | base64 | tr -d '\n'); links+="ss://${ss_b64}@${ip_host}:${ss_up}#$(uri_encode "$sb_ss_name")"$'\n'; }
        fi
    fi   # close else (IS_DEFAULT_USER != 1)
fi   # close SB_ENABLE check
out=$(printf '%s' "$links" | base64 -w0 2>/dev/null || printf '%s' "$links" | base64 | tr -d '\n')
[ "$IS_DEFAULT_USER" = "1" ] && printf '%s' "$out" > /etc/xray/sub.txt

if [ "$IS_DEFAULT_USER" != "1" ]; then
    quota=$(printf '%s' "$USER_JSON" | $JQ -r '.quota_bytes//0')
    used_up=$(printf '%s' "$USER_JSON" | $JQ -r '.used_up//0')
    used_down=$(printf '%s' "$USER_JSON" | $JQ -r '.used_down//0')
    reset_day=$(printf '%s' "$USER_JSON" | $JQ -r '.reset_day//0')
    
    used_total=$((used_up + used_down))
    
    format_bytes() {
        local b=$1
        if [ -z "$b" ] || [ "$b" -eq 0 ]; then echo "0 B"; return; fi
        if [ "$b" -ge 1073741824 ]; then awk "BEGIN {printf \"%.2f GB\", $b/1073741824}"; return; fi
        if [ "$b" -ge 1048576 ]; then awk "BEGIN {printf \"%.2f MB\", $b/1048576}"; return; fi
        if [ "$b" -ge 1024 ]; then awk "BEGIN {printf \"%.2f KB\", $b/1024}"; return; fi
        echo "${b} B"
    }
    
    if [ "$quota" -gt 0 ]; then
        rem=$((quota - used_total))
        [ "$rem" -lt 0 ] && rem=0
        rem_str=$(format_bytes "$rem")
    else
        rem_str="无限"
    fi
    
    fake_nodes="vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?encryption=none&security=tls&type=ws#🎯剩余流量: ${rem_str}"$'\n'
    
    if [ "$reset_day" -gt 0 ]; then
        d=$(date +%d | sed 's/^0*//')
        if [ "$d" -le "$reset_day" ]; then
            days=$((reset_day - d))
        else
            days=$((30 - d + reset_day))
        fi
        fake_nodes+="vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?encryption=none&security=tls&type=ws#距离下次重置剩余: ${days} 天"$'\n'
    fi
    
    links="${fake_nodes}${links}"
    out=$(printf '%s' "$links" | base64 -w0 2>/dev/null || printf '%s' "$links" | base64 | tr -d '\n')
fi

printf '%s' "$out"
SUBEOF
    chmod +x "${WORK_DIR}/sub_gen.sh"
    bash "${WORK_DIR}/sub_gen.sh" "$SUB_TOKEN" >/dev/null 2>&1 || true

    # 聚合订阅脚本
    cat > "${WORK_DIR}/agg_gen.sh" << 'AGGEOF'
#!/usr/bin/env bash
SOURCES=/etc/xray/agg_sources.txt
OUTPUT=/etc/xray/agg_raw.txt
TIMEOUT=12
all=""
# 本地节点
if [ -f /etc/xray/sub.txt ]; then
    local_decoded=$(base64 -d /etc/xray/sub.txt 2>/dev/null || true)
    [ -n "$local_decoded" ] && all+="$local_decoded"$'\n'
fi
# 拉取源订阅
if [ -f "$SOURCES" ]; then
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        raw=$(curl -skL --max-time "$TIMEOUT" "$u" 2>/dev/null)
        [ -z "$raw" ] && continue
        d=$(echo "$raw" | base64 -d 2>/dev/null || true)
        [ -n "$d" ] && all+="$d"$'\n'
    done < "$SOURCES"
fi
# 去重编码
echo "$all" | grep -v '^$' | sort -u | base64 -w0 2>/dev/null > "$OUTPUT" || {
    echo "$all" | grep -v '^$' | sort -u | base64 | tr -d '\n' > "$OUTPUT"
}
AGGEOF
    chmod +x "${WORK_DIR}/agg_gen.sh"
    [ -z "$AGG_TOKEN" ] && AGG_TOKEN=$(rand_token) && save_conf

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
            users = [{"auth": u["uuid"], "level": 0, "email": u["email"]} for u in enabled]
            settings["users"] = users
            settings["clients"] = users

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

def bj_now():
    return time.localtime(time.time() + 8 * 3600)

def poll_once():
    data = load_json(USERS_FILE, {"version": 1, "users": []})
    changed = False
    disabled = False

    # --- 月度流量重置 (北京时区) ---
    bj = bj_now()
    current_month = int(time.strftime("%Y%m", bj))
    current_day = int(time.strftime("%d", bj))
    for u in data.get("users", []):
        reset_day = int(u.get("reset_day") or 0)
        if reset_day < 1:
            continue
        last_reset = int(u.get("last_reset_month") or 0)
        if current_month > last_reset and current_day >= reset_day:
            u["used_up"] = 0
            u["used_down"] = 0
            u["last_reset_month"] = current_month
            if not u.get("enabled", True):
                u["enabled"] = True
            changed = True

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
    # Sing-box 状态
    if [ "${SB_ENABLE:-false}" = "true" ]; then
        sb_status && { SB_ST="${green}● 运行中${re}"; SB_RAW="running"; } || { SB_ST="${red}○ 已停止${re}"; SB_RAW="stopped"; }
    else
        SB_ST=""; SB_RAW=""
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
        rp="${REALITY_PUB:-}"
        [ -n "$rp" ] || rp=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey//empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── VLESS Reality (端口 ${rport}) ──${re}"
        echo ""
        echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$rport" "$rsni" "$rp" "$REALITY_SHORTID")${re}"
        echo -e "  ${cyan}SNI${re}: ${rsni}  Flow: xtls-rprx-vision"
        [ -n "$REALITY_SHORTID" ] && echo -e "  ${cyan}ShortId${re}: ${REALITY_SHORTID}"
        echo ""
    fi

    if jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1 && [ -n "$ip" ]; then
        local hport hsni hmport
        hport=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        hsni=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CONFIG_FILE" 2>/dev/null)
        hmport=$(jq -r '.inbounds[]|select(.tag=="hy2")|(.streamSettings.finalmask.quicParams.udpHop.ports//.streamSettings.hysteriaSettings.quicParams.udpHop.ports[0]//empty)' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── Hysteria2 (端口 ${hport}) ──${re}"
        echo ""
        echo -e "  ${green}$(gen_hy2_link "$uuid" "$ip" "$hport" "$hsni" "${NODE_NAME}-Hy2" "$hmport")${re}"
        echo -e "  ${cyan}SNI${re}: ${hsni}  ALPN: h3  TLS: self-signed/insecure"
        [ -n "$hmport" ] && echo -e "  ${cyan}MPort${re}: ${hmport}"
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

    # Sing-box 节点
    if [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ] && [ -n "$ip" ]; then
        local sb_hy2_name="${NODE_NAME}-HY2" sb_reality_name="${NODE_NAME}-Reality" sb_ss_name="${NODE_NAME}-SS"
        jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1 && sb_hy2_name="${NODE_NAME}-SingBox-HY2"
        jq -e '.inbounds[]|select(.tag=="reality")' "$CONFIG_FILE" >/dev/null 2>&1 && sb_reality_name="${NODE_NAME}-SingBox-Reality"
        jq -e '.inbounds[]|select(.tag=="ss")' "$CONFIG_FILE" >/dev/null 2>&1 && sb_ss_name="${NODE_NAME}-SingBox-SS"
        echo ""
        echo -e "  ${white}── Sing-box 节点 ──${re}"
        echo ""
        if [ "${SB_HY2_ENABLE:-false}" = "true" ] && [ -n "${SB_HY2_PORT:-}" ]; then
            local sbhy2_pass sbhy2_port
            sbhy2_port="$SB_HY2_PORT"
            sbhy2_pass=$(jq -r '.inbounds[]|select(.type=="hysteria2").users[0].password//empty' "$SB_CONFIG_FILE" 2>/dev/null)
            local sb_hy2_hop_range=""
            [ "${SB_HY2_HOP_ENABLE:-false}" = "true" ] && sb_hy2_hop_range="${SB_HY2_HOP_START}-${SB_HY2_HOP_END}"
            [ -n "$sbhy2_pass" ] && echo -e "  ${yellow}HY2${re}  ${green}$(gen_sb_hy2_link "$sbhy2_pass" "$ip" "$sbhy2_port" "${SB_HY2_SNI:-$SB_SNI}" "$sb_hy2_name" "$sb_hy2_hop_range")${re}\n"
            [ -n "$sb_hy2_hop_range" ] && echo -e "  ${cyan}跳变${re}: ${sb_hy2_hop_range}  mode: ${SB_HY2_HOP_MODE:-fixed}"
        fi
        if [ "${SB_TUIC_ENABLE:-false}" = "true" ] && [ -n "${SB_TUIC_PORT:-}" ]; then
            local sbtuic_uuid sbtuic_pass
            sbtuic_uuid="${SB_TUIC_UUID}"; sbtuic_pass="${SB_TUIC_PSK}"
            [ -n "$sbtuic_uuid" ] && echo -e "  ${yellow}TUIC${re}  ${green}$(gen_sb_tuic_link "$sbtuic_uuid" "$sbtuic_pass" "$ip" "$SB_TUIC_PORT" "${SB_TUIC_SNI:-$SB_SNI}" "${NODE_NAME}-TUIC")${re}\n"
        fi
        if [ "${SB_ANYTLS_ENABLE:-false}" = "true" ] && [ -n "${SB_ANYTLS_PORT:-}" ]; then
            local sbany_pass
            sbany_pass="${SB_ANYTLS_PSK}"
            [ -n "$sbany_pass" ] && echo -e "  ${yellow}AnyTLS${re}  ${green}$(gen_sb_anytls_link "$sbany_pass" "$ip" "$SB_ANYTLS_PORT" "${SB_ANYTLS_SNI:-$SB_SNI}" "${SB_REALITY_PUB}" "${SB_REALITY_SID}" "${NODE_NAME}-AnyTLS")${re}\n"
        fi
        if [ "${SB_REALITY_ENABLE:-false}" = "true" ] && [ -n "${SB_REALITY_PORT:-}" ]; then
            local sbreal_uuid; sbreal_uuid=$(get_uuid)
            echo -e "  ${yellow}Reality${re}  ${green}$(gen_sb_reality_link "$sbreal_uuid" "$ip" "$SB_REALITY_PORT" "${SB_REALITY_SNI:-$SB_SNI}" "${SB_REALITY_PUB}" "${SB_REALITY_SID}" "$sb_reality_name")${re}\n"
        fi
        if [ "${SB_SS_ENABLE:-false}" = "true" ] && [ -n "${SB_SS_PORT:-}" ]; then
            local sbss_pass; sbss_pass=$(jq -r '.inbounds[]|select(.type=="shadowsocks").password//empty' "$SB_CONFIG_FILE" 2>/dev/null)
            [ -n "$sbss_pass" ] && echo -e "  ${yellow}SS${re}  ${green}$(gen_sb_ss_link "${SB_SS_METHOD:-$SS_METHOD}" "$sbss_pass" "$ip" "$SB_SS_PORT" "$sb_ss_name")${re}\n"
        fi
    fi

    echo -e "  ${yellow}💡${re} 复制链接 → 客户端导入    菜单 2 换线路 | 菜单 3 改配置"
    local su; su=$(get_sub_url "$ip" 2>/dev/null)
    [ -n "$su" ] && { echo ""; echo -e "  ${purple}━━━ 📡 订阅链接 ━━━${re}"; echo -e "  ${white}${su}${re}"; echo -e "  ${yellow}💡 V2rayN / Shadowrocket / Clash 系全平台智能适配，一键导入${re}"; }

    # 流量统计显示
    if [ -f "${WORK_DIR}/.traffic_counters" ]; then
        . "${WORK_DIR}/.traffic_counters" 2>/dev/null || true
        local tin="${TRAFFIC_IN:-0}" tout="${TRAFFIC_OUT:-0}"
        local tin_f tout_f
        tin_f=$(numfmt --to=iec "$tin" 2>/dev/null || echo "$tin B")
        tout_f=$(numfmt --to=iec "$tout" 2>/dev/null || echo "$tout B")
        echo -e "  ${purple}流量${re}: ${green}↓ ${tin_f}${re}  ${cyan}↑ ${tout_f}${re}"
    fi
}

#==============================================================================
# 服务控制
#==============================================================================
# MODULE: service lifecycle
start_services() {
    yellow_msg "Starting..."
    systemctl start xray argov-stats argov-sb-stats 2>/dev/null || true
    [ "$SKIP_ARGO" != "1" ] && systemctl start argov-tunnel 2>/dev/null || true
    rc-service xray start 2>/dev/null || true
    [ "$SKIP_ARGO" != "1" ] && rc-service argov-tunnel start 2>/dev/null || true
    rc-service argov-stats start 2>/dev/null || true
    rc-service argov-sb-stats start 2>/dev/null || true
    [ "${SB_ENABLE:-false}" = "true" ] && { sb_start; }
    setup_traffic_counters 2>/dev/null || true
    sleep 2; get_status
    echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"
    [ -n "$SB_ST" ] && echo -e "  Sing-box: ${SB_ST}"
    green_msg "Done"
}
stop_services()  {
    yellow_msg "Stopping..."
    systemctl stop xray argov-stats argov-sb-stats 2>/dev/null || true
    [ "$SKIP_ARGO" != "1" ] && systemctl stop argov-tunnel 2>/dev/null || true
    rc-service xray stop 2>/dev/null || true
    [ "$SKIP_ARGO" != "1" ] && rc-service argov-tunnel stop 2>/dev/null || true
    rc-service argov-stats stop 2>/dev/null || true
    rc-service argov-sb-stats stop 2>/dev/null || true
    [ "${SB_ENABLE:-false}" = "true" ] && { sb_stop; }
    sleep 1; get_status
    echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"
    [ -n "$SB_ST" ] && echo -e "  Sing-box: ${SB_ST}"
    red_msg "Stopped"
}
restart_services() {
    yellow_msg "Restarting..."
    rm -f "$TUNNEL_LOG"
    systemctl restart xray argov-stats argov-sb-stats 2>/dev/null || true
    [ "$SKIP_ARGO" != "1" ] && systemctl restart argov-tunnel 2>/dev/null || true
    rc-service xray restart 2>/dev/null || true
    [ "$SKIP_ARGO" != "1" ] && rc-service argov-tunnel restart 2>/dev/null || true
    rc-service argov-stats restart 2>/dev/null || true
    rc-service argov-sb-stats restart 2>/dev/null || true
    [ "${SB_ENABLE:-false}" = "true" ] && { sb_restart; }
    sleep 3; get_status
    local d; d=$(get_argo_domain)
    echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"
    [ -n "$SB_ST" ] && echo -e "  Sing-box: ${SB_ST}"
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
        for k in 1 2 3 4 5 6 7 8; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done
        echo ""; echo -e "  ${white}── 运营商专线 ──${re}"
        for k in 9 10 11; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done
        echo ""; echo -e "  ${white}── 其他 ──${re}"
        for k in 12 13 14; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done
        echo ""
        echo -e "  ${cyan}c${re}. 自定义 (host:port)    ${cyan}p${re}. 仅改端口    ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  请选择: "; read c ; local np="$cp"
        case "$c" in
            1) CDN_DOMAIN="xx.cloudflare.182682.xyz" ;; 2) CDN_DOMAIN="bestcf.top" ;; 3) CDN_DOMAIN="cdn.31514926.xyz" ;;
            4) CDN_DOMAIN="skk.moe" ;; 5) CDN_DOMAIN="ip.sb" ;; 6) CDN_DOMAIN="time.is" ;;
            7) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;; 8) CDN_DOMAIN="cf.090227.xyz" ;;
            9) CDN_DOMAIN="yidong.19931101.xyz" ;; 10) CDN_DOMAIN="liantong.19931101.xyz" ;;
            11) CDN_DOMAIN="dianxin.19931101.xyz" ;; 12) CDN_DOMAIN="cdn.2020111.xyz" ;; 13) CDN_DOMAIN="xn--b6gac.eu.org" ;; 14) CDN_DOMAIN="cdns.doon.eu.org" ;;
            c|C) echo -ne "  host:port: "; read raw ; [[ "$raw" =~ ^(.+):([0-9]+)$ ]] && { CDN_DOMAIN="${BASH_REMATCH[1]}"; np="${BASH_REMATCH[2]}"; } || CDN_DOMAIN="$raw" ;;
            p|P) echo -ne "  端口: "; read np ; CDN_DOMAIN="$cc" ;;
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
        echo -e "  ${green}3${re}. $([ "$ARGO_MODE" = "skip" ] && echo "启用 Argo 隧道" || echo "切换 Argo 隧道 (临时↔固定)")"
        echo -e "  ${green}4${re}. SS 加密 — ${cyan}${SS_METHOD}${re}"
        echo -e "  ${green}5${re}. Reality 伪装域名 — ${cyan}${REALITY_SNI}${re}"
        echo -e "  ${green}6${re}. 管理协议节点 (添加/删除)"
        echo -e "  ${green}7${re}. 查看节点链接"
        echo -e "  ${green}8${re}. 刷新 Argo 域名"
        echo -e "  ${green}9${re}. 订阅配置"
        echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  请选择: "; read c 
        case "$c" in
            1) echo -ne "  新名称 [${NODE_NAME}]: "; read n ; [ -n "$n" ] && NODE_NAME="$n"; save_conf; green_msg "已更新: ${NODE_NAME}" ;;
            2) local nu; echo -ne "  新 UUID (回车生成): "; read nu ; [ -z "$nu" ] && nu=$(cat /proc/sys/kernel/random/uuid)
               jq --arg u "$nu" '(.inbounds[].settings.clients[]?|select(.id)|.id)|=$u' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
               UUID_CUSTOM="$nu"; save_conf; ensure_users_file; sync_xray_users; systemctl restart xray 2>/dev/null; rc-service xray restart 2>/dev/null || true; green_msg "UUID 已更新！${nu}" ;;
            3) switch_argo_tunnel ;;
            4) edit_protocol ss "Shadowsocks" ;;
            5) edit_protocol reality "VLESS Reality" ;;
            6) manage_protocols ;;
            7) show_node ;; 8) restart_services ;; 9) edit_subscription ;; 0) return ;; *) red_msg "无效" ;;
        esac; echo -ne "  按回车继续..."; read -r
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
        printf "  %-16s %-8s %-8s %-14s %-14s %s\n" "name" "state" "reset" "used" "quota" "token"
        printf "  %-16s %-8s %-8s %-14s %-14s %s\n" "----" "-----" "-----" "----" "-----" "-----"
        while IFS=$'\t' read -r name enabled used quota token reset_day; do
            [ -z "$name" ] && continue
            local state="off"
            [ "$enabled" = "1" ] && state="on"
            local reset_label="-"
            [ "${reset_day:-0}" != "0" ] && [ -n "$reset_day" ] && reset_label="↑${reset_day}"
            printf "  %-16s %-8s %-8s %-14s %-14s %s\n" "$name" "$state" "$reset_label" "$(format_bytes "$used")" "$([ "$quota" = "0" ] && echo unlimited || format_bytes "$quota")" "$token"
        done < <(user_db_op list 2>/dev/null)
        echo ""
        echo -e "  ${green}1${re}. Add limited user"
        echo -e "  ${green}2${re}. Enable user"
        echo -e "  ${yellow}3${re}. Disable user"
        echo -e "  ${green}4${re}. Set quota"
        echo -e "  ${green}5${re}. Reset usage"
        echo -e "  ${cyan}6${re}. Show subscription URL"
        echo -e "  ${purple}8${re}. Set reset day"
        echo -e "  ${red}7${re}. Delete user"
        echo -e "  ${red}0${re}. Back"
        echo ""
        echo -ne "  Select: "; read c
        case "$c" in
            1)
                local name quota quota_bytes uuid token ip
                echo -ne "  User name (letters/numbers, e.g. friend): "; read name 
                [ -z "$name" ] && { red_msg "Empty name."; sleep 1; continue; }
                echo -ne "  Quota, e.g. 200G (0 = unlimited): "; read quota 
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
                    echo -e "  Limited users receive only: VLESS Argo, VMess Argo, Reality, Hysteria2, Sing-box (dedicated port)."
                else
                    red_msg "User already exists or cannot be added."
                fi
                echo -ne "  Press Enter..."; read -r
                ;;
            2|3|4|5|6|7|8)
                local name quota quota_bytes token ip line enabled used quota_cur
                echo -ne "  User name: "; read name 
                [ -z "$name" ] && { red_msg "Empty name."; sleep 1; continue; }
                case "$c" in
                    2)
                        user_db_op set-enabled "$name" 1 && restart_user_runtime && green_msg "Enabled." || red_msg "Cannot enable user."
                        ;;
                    3)
                        user_db_op set-enabled "$name" 0 && restart_user_runtime && green_msg "Disabled." || red_msg "Cannot disable user."
                        ;;
                    4)
                        echo -ne "  New quota, e.g. 200G (0 = unlimited): "; read quota 
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
                        echo -ne "  Press Enter..."; read -r
                        ;;
                    8)
                        local cur_day
                        cur_day=$(user_db_op show "$name" 2>/dev/null | awk -F'\t' '{print $6}' || echo 0)
                        cur_day="${cur_day:-0}"
                        echo -e "  ${yellow}每月该日重置流量 (北京时区)${re}"
                        echo -e "  ${yellow}当前: ${cyan}$([ "$cur_day" = "0" ] && echo "未设置" || echo "每月 ${cur_day} 号")${re}"
                        echo -ne "  输入 1-28 (0=关闭): "; read rday 
                        [ -z "$rday" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                        if [ "$rday" = "0" ]; then
                            user_db_op set-reset-day "$name" 0 && green_msg "已关闭自动重置。" || red_msg "Failed."
                        elif [[ "$rday" =~ ^[0-9]+$ ]] && [ "$rday" -ge 1 ] && [ "$rday" -le 28 ]; then
                            user_db_op set-reset-day "$name" "$rday" && green_msg "已设置: 每月 ${rday} 号重置。" || red_msg "Failed."
                        else
                            red_msg "无效，输入 1-28 或 0 关闭。"
                        fi
                        sleep 1
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

    # 如果之前跳过了 Argo, 先下载 cloudflared
    if [ "$ARGO_MODE" = "skip" ]; then
        echo -e "  ${yellow}Argo 隧道未安装, 正在下载 cloudflared...${re}"
        local cf_arch; cf_arch=$(cf_arch)
        download_cloudflared_checked "$cf_arch" "${WORK_DIR}/argo" || { red_msg "cloudflared 下载失败"; return; }
        chmod +x "${WORK_DIR}/argo"
        ARGO_MODE="temp"
        SKIP_ARGO=0
    fi

    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}切换 Argo 隧道${re}                       ${purple}║${re}"
    echo -e " ${purple}║${re}       ${yellow}当前: $([ "$ARGO_MODE" = "temp" ] && echo "临时" || echo "固定")${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""; echo -e "  ${green}1${re}. 临时隧道     ${green}2${re}. 固定 Token    ${red}0${re}. 返回"
    echo -ne "  请选择: "; read c
    case "$c" in
        1) ARGO_MODE="temp"; ARGO_AUTH=""; ARGO_FIXED_DOMAIN=""; save_conf; rebuild_tunnel "temp"; restart_services ;;
        2) echo -ne "  域名: "; read ARGO_FIXED_DOMAIN; echo -ne "  Token: "; read ARGO_AUTH
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
restart_protocol_runtime() {
    local service="$1"
    [ "$service" = singbox ] && service=sing-box
    if [ "${IS_ALPINE:-0}" = 1 ]; then rc-service "$service" restart; else systemctl restart "$service"; fi
}
begin_protocol_edit() {
    EDIT_CORE="$1"; EDIT_COMMITTED=0
    EDIT_SNAPSHOT_DIR=$(mktemp -d -t argov-edit.XXXXXX) || return 1
    EDIT_FILES=("$USER_CONF" "$CONFIG_FILE" "$SB_CONFIG_FILE" "$ARGOV_USERS_FILE" \
        "$HY2_CERT_FILE" "$HY2_KEY_FILE" "$SB_CERT_FILE" "$SB_KEY_FILE" "$SB_HY2_CERT_FILE" "$SB_HY2_KEY_FILE")
    local i
    for i in "${!EDIT_FILES[@]}"; do
        if [ -f "${EDIT_FILES[$i]}" ]; then
            cp -p "${EDIT_FILES[$i]}" "$EDIT_SNAPSHOT_DIR/$i" || {
                rm -f "$EDIT_SNAPSHOT_DIR"/*; rmdir "$EDIT_SNAPSHOT_DIR"; red_msg "无法备份原配置，已取消修改。"; return 1
            }
        fi
    done
    trap finish_protocol_edit EXIT
}
finish_protocol_edit() {
    local i restore_failed=0
    if [ "$EDIT_COMMITTED" != 1 ]; then
        for i in "${!EDIT_FILES[@]}"; do
            if [ -f "$EDIT_SNAPSHOT_DIR/$i" ]; then
                cp -p "$EDIT_SNAPSHOT_DIR/$i" "${EDIT_FILES[$i]}" || restore_failed=1
            else
                rm -f "${EDIT_FILES[$i]}" || restore_failed=1
            fi
        done
        if [ "$restore_failed" = 1 ]; then
            red_msg "自动恢复未完成，备份保留在 ${EDIT_SNAPSHOT_DIR}，请检查磁盘和文件权限。"
            return 1
        fi
        red_msg "修改未完成，已恢复原配置、用户数据和证书。"
        restart_protocol_runtime "$EDIT_CORE" >/dev/null 2>&1 || yellow_msg "原服务未能重新启动，请检查服务日志。"
    fi
    rm -f "$EDIT_SNAPSHOT_DIR"/*
    rmdir "$EDIT_SNAPSHOT_DIR" 2>/dev/null || true
}
commit_xray_candidate() {
    local candidate="$1" check_result
    jq empty "$candidate" >/dev/null 2>&1 || { rm -f "$candidate"; red_msg "配置 JSON 无效，未替换原文件。"; return 1; }
    if [ -x "${WORK_DIR}/xray" ]; then
        check_result=$("${WORK_DIR}/xray" run -test -config "$candidate" 2>&1) || {
            printf '%s\n' "$check_result"; rm -f "$candidate"; red_msg "Xray 配置验证失败。"; return 1
        }
    fi
    chmod 600 "$candidate"
    mv -f "$candidate" "$CONFIG_FILE"
}
add_sb_protocol() {
    (
        load_conf
        sb_is_installed || { red_msg "请先安装 Sing-box 内核。"; return 1; }
        local proto="$1" sb_keys first_protocol=0
        [ -f "$SB_CONFIG_FILE" ] || first_protocol=1
        configure_sb_protocol "$proto" || return 1
        confirm_changes "应用以上设置？连接参数变化后客户端需刷新订阅" || return 1
        begin_protocol_edit singbox || return 1
        case "$proto" in
            HY2) generate_singbox_hy2_cert || return 1 ;;
            TUIC) generate_singbox_cert || return 1 ;;
            ANYTLS|REALITY)
                if [ -z "$SB_REALITY_PRIV" ]; then
                    sb_keys=$(sing-box generate reality-keypair 2>/dev/null) || return 1
                    SB_REALITY_PRIV=$(printf '%s\n' "$sb_keys" | awk '/PrivateKey/{print $2}')
                    SB_REALITY_PUB=$(printf '%s\n' "$sb_keys" | awk '/PublicKey/{print $2}')
                fi
                [ -n "$SB_REALITY_SID" ] || SB_REALITY_SID=$(sing-box generate rand 8 --hex 2>/dev/null)
                [ -n "$SB_REALITY_PRIV" ] && [ -n "$SB_REALITY_PUB" ] && [ -n "$SB_REALITY_SID" ] || {
                    red_msg "Reality 密钥生成失败。"; return 1;
                }
                ;;
        esac
        build_singbox_config || return 1
        save_conf || return 1
        configure_singbox_service || return 1
        restart_protocol_runtime singbox || { red_msg "Sing-box 重启失败。"; return 1; }
        if [ "$proto" = HY2 ]; then
            disable_sb_hy2_hop_rules
            if [ "$SB_HY2_HOP_ENABLE" = true ] && ! apply_sb_hy2_hop_rules; then
                SB_HY2_HOP_ENABLE=false; save_conf
                yellow_msg "跳跃规则安装失败，已关闭跳跃；监听端口保持可用。"
            fi
        fi
        if [ "$first_protocol" = 1 ]; then
            enable_singbox_service || yellow_msg "节点已启动，但开机启动设置失败，请检查 Sing-box 服务。"
        fi
        EDIT_COMMITTED=1
        start_sub_server >/dev/null 2>&1 &
        green_msg "Sing-box ${proto} 设置已应用，请刷新客户端订阅。"
    )
}
prompt_xray_hy2() {
    local def_port="$HY2_PORT" current="" hop_default="$HY2_MPORT" sni_default="$HY2_SNI"
    is_port "$def_port" || def_port=$(find_free_any_port "$(shuf -i 10000-60000 -n 1)")
    [ -f "$CONFIG_FILE" ] && [ "${ENABLE_HY2:-0}" = 1 ] && current="$HY2_PORT"
    if [ -z "$sni_default" ] && ! jq -e '.inbounds[]?|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1; then
        sni_default="www.tesla.com"
    fi
    echo "  HY2 使用自签证书；SNI 是握手域名，不会将流量转发到该网站。"
    prompt_domain HY2_SNI "$sni_default" "HY2 SNI/TLS 域名" || return 1
    prompt_port HY2_PORT "$def_port" "HY2 UDP 端口" HY2_PORT "$current" || return 1
    prompt_hy2_congestion HY2_CONGESTION HY2_UP_MBPS HY2_DOWN_MBPS xray \
        "${HY2_CONGESTION:-bbr}" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS" || return 1
    if [ -z "$hop_default" ] && ! jq -e '.inbounds[]?|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1; then
        hop_default=$(default_hy2_hop_range HY2_PORT) || return 1
    fi
    prompt_hy2_hopping HY2_MPORT "$hop_default" || return 1
    echo "  HY2: ${HY2_SNI}:${HY2_PORT}，算法 ${HY2_CONGESTION}，跳跃 ${HY2_MPORT:-关闭}"
    [ "$HY2_CONGESTION" = brutal ] && echo "  服务端带宽: 上传 ${HY2_UP_MBPS} Mbps / 下载 ${HY2_DOWN_MBPS} Mbps"
    return 0
}
prompt_password() {
    local _pw_target="$1" _pw_default="$2" _pw_label="$3" _pw_method="${4:-}" _pw_input
    [ -n "$_pw_default" ] || {
        if [[ "$_pw_method" == 2022-* ]]; then _pw_default=$(gen_ss2022_pass "$_pw_method"); else _pw_default=$(rand_token); fi
    }
    while true; do
        printf '  %s [回车保留/自动生成，new 换新，cancel 返回]: ' "$_pw_label"
        IFS= read -rs _pw_input || { echo; return 1; }; echo
        [ "${_pw_input,,}" = cancel ] && return 1
        if [ "${_pw_input,,}" = new ]; then
            if [[ "$_pw_method" == 2022-* ]]; then _pw_input=$(gen_ss2022_pass "$_pw_method"); else _pw_input=$(rand_token); fi
        fi
        _pw_input="${_pw_input:-$_pw_default}"
        if [[ "$_pw_method" == 2022-* ]] && ! valid_ss2022_password "$_pw_method" "$_pw_input"; then
            red_msg "SS2022 密码必须是正确长度的 Base64 密钥，可输入 new 自动生成。"; continue
        fi
        printf -v "$_pw_target" '%s' "$_pw_input"; return 0
    done
}
valid_ss2022_password() {
    local method="$1" password="$2" size expected=32
    [[ "$method" == *128* ]] && expected=16
    [[ "$password" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
    size=$(printf '%s' "$password" | openssl base64 -d -A 2>/dev/null | wc -c)
    [ "$size" -eq "$expected" ]
}
configure_sb_protocol() {
    local proto="$1" port_key="SB_${1}_PORT" enabled_key="SB_${1}_ENABLE" sni_key="SB_${1}_SNI"
    local current="${!port_key}" def_port="${!port_key}" pass_key="SB_${1}_PSK" hop_range=""
    [ "${!enabled_key}" = true ] || current=""
    is_port "$def_port" || def_port=$(find_free_any_port "$(shuf -i 10000-60000 -n 1)")
    echo; cyan_msg "配置 Sing-box ${proto}（回车保留当前值，0/cancel 返回）"
    prompt_port "$port_key" "$def_port" "${proto} 端口" "$port_key" "$current" || return 1
    if [ "$proto" != SS ]; then
        prompt_domain "$sni_key" "${!sni_key}" "${proto} SNI/TLS 域名" || return 1
    fi
    case "$proto" in
        HY2)
            if [ "${!enabled_key}" != true ] || { [ "$SB_HY2_CERT_FILE" = "$SB_CERT_FILE" ] && [ "$SB_HY2_SNI" != "$SB_SNI" ]; }; then
                SB_HY2_CERT_FILE="${SB_WORK_DIR}/certs/hy2.pem"; SB_HY2_KEY_FILE="${SB_WORK_DIR}/certs/hy2.key"
            fi
            prompt_hy2_congestion SB_HY2_CONGESTION SB_HY2_UP_MBPS SB_HY2_DOWN_MBPS singbox \
                "$SB_HY2_CONGESTION" "$SB_HY2_UP_MBPS" "$SB_HY2_DOWN_MBPS" || return 1
            if [ "$SB_HY2_CONGESTION" = bbr ] && singbox_supports_bbr_profile; then
                prompt_choice SB_HY2_BBR_PROFILE "$SB_HY2_BBR_PROFILE" "BBR 预设" standard conservative aggressive || return 1
            fi
            [ "$SB_HY2_HOP_ENABLE" = true ] && hop_range="${SB_HY2_HOP_START}-${SB_HY2_HOP_END}"
            if [ "${!enabled_key}" != true ] && [ -z "$hop_range" ] &&
                ! jq -e '.inbounds[]?|select(.tag=="sb-hy2")' "$SB_CONFIG_FILE" >/dev/null 2>&1; then
                hop_range=$(default_hy2_hop_range SB_HY2_PORT) || return 1
            fi
            prompt_hy2_hopping hop_range "$hop_range" SB_HY2_PORT || return 1
            if [ -n "$hop_range" ]; then
                SB_HY2_HOP_ENABLE=true; SB_HY2_HOP_START="${hop_range%-*}"; SB_HY2_HOP_END="${hop_range#*-}"
            else SB_HY2_HOP_ENABLE=false; SB_HY2_HOP_START=""; SB_HY2_HOP_END=""; fi
            SB_HY2_HOP_MODE=fixed; SB_HY2_HOP_INTERVAL=30
            ;;
        TUIC) SB_TUIC_UUID="${SB_TUIC_UUID:-$(rand_uuid)}" ;;
        SS)
            prompt_choice SB_SS_METHOD "$SB_SS_METHOD" "SS 加密方法" "${SS_METHODS[@]}" || return 1
            if [[ "$SB_SS_METHOD" == 2022-* ]] && ! valid_ss2022_password "$SB_SS_METHOD" "$SB_SS_PSK"; then SB_SS_PSK=""; fi
            ;;
    esac
    if [ "$proto" != REALITY ]; then
        prompt_password "$pass_key" "${!pass_key}" "${proto} 认证密码" "$([ "$proto" = SS ] && echo "$SB_SS_METHOD")" || return 1
    fi
    printf -v "$enabled_key" '%s' true
    SB_ENABLE=true
    echo "  ${proto}: 端口 ${!port_key}$([ "$proto" != SS ] && echo "，域名 ${!sni_key}")"
    [ "$proto" = HY2 ] && echo "  算法: ${SB_HY2_CONGESTION}，跳跃: ${hop_range:-关闭}"
    return 0
}
select_protocols() {
    while true; do
        clear
        local sum=""; [ "$ARGO_MODE" != skip ] && sum="VLESS-Argo + VMess-Argo"
        [ "$ENABLE_REALITY" = 1 ] && sum="$sum + Reality"
        [ "$ENABLE_HY2" = 1 ] && sum="$sum + Hysteria2"
        [ "$ENABLE_SS" = 1 ] && sum="$sum + Shadowsocks"
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}选择额外协议（可选）${re}                    ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        [ "$ARGO_MODE" != skip ] && echo -e "  ${white}已启用：VLESS-Argo + VMess-Argo${re}" || echo "  Argo 已跳过，请选择 Xray 直连协议；Sing-box 节点可在安装后增配。"
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
        echo -ne "  (1/2/3=切换 / 0=下一步 / cancel=取消): "; IFS= read -r c || return 1
        case "$c" in
            cancel|CANCEL) return 1 ;;
            1) ENABLE_REALITY=$((1-ENABLE_REALITY)); continue ;;
            2) ENABLE_HY2=$((1-ENABLE_HY2)); continue ;;
            3) ENABLE_SS=$((1-ENABLE_SS)); continue ;;
            0)
                echo ""

                if [ "$ENABLE_REALITY" = 1 ]; then
                    local rp; rp=$(find_free_any_port "$(shuf -i 10000-60000 -n 1)")
                    prompt_port REALITY_PORT "$rp" "Reality 端口" || return 1
                    prompt_domain REALITY_SNI "$REALITY_SNI" "Reality 伪装域名" || return 1
                fi
                [ "$ENABLE_HY2" = 1 ] && { prompt_xray_hy2 || return 1; }
                if [ "$ENABLE_SS" = 1 ]; then
                    local sp; sp=$(find_free_any_port "$(shuf -i 10000-60000 -n 1)")
                    prompt_port SS_PORT "$sp" "Shadowsocks 端口" || return 1
                    prompt_choice SS_METHOD "$SS_METHOD" "Shadowsocks 加密" "${SS_METHODS[@]}" || return 1
                fi
                echo ""
                echo -e "  ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo -e "  ${white}即将安装:${re}$([ "$ARGO_MODE" != "skip" ] && echo "  Argo: VLESS+VMess")"
                [ "$ENABLE_REALITY" = 1 ] && echo -e "  Reality: 端口 ${green}${REALITY_PORT}${re}  (SNI ${REALITY_SNI}；UUID/密钥 自动生成)"
                [ "$ENABLE_HY2" = 1 ] && echo -e "  Hysteria2: 端口 ${green}${HY2_PORT}${re}  (SNI ${HY2_SNI}；算法 ${HY2_CONGESTION}；证书 自动生成)"
                [ "$ENABLE_HY2" = 1 ] && [ -n "$HY2_MPORT" ] && echo -e "  Hysteria2 跳跃: ${green}${HY2_MPORT}${re}  (UDP 转发到 ${HY2_PORT})"
                [ "$ENABLE_SS" = 1 ] && echo -e "  Shadowsocks: 端口 ${green}${SS_PORT}${re}  (加密 ${SS_METHOD}；密码 自动生成)"
                echo -e "  ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
                echo ""
                while true; do
                    echo -ne "  ${yellow}继续安装向导? (y/n/0=返回) [y]: ${re}"
                    IFS= read -r cf || return 1
                    case "${cf,,}" in
                        ""|y|yes|0) break ;;
                        n|no|cancel) yellow_msg "已取消。"; return 1 ;;
                        *) red_msg "请输入 y、n 或 0。" ;;
                    esac
                done
                [ "$cf" = "0" ] && continue
                return 0
                ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac
    done
}

#==============================================================================
# 交互式安装
#==============================================================================
# MODULE: install and update
interactive_install() {
    local install_sb_core=false
    load_conf; clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}  ${white}ArgoV · 交互式安装向导${re}              ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""; yellow_msg "按提示配置，回车使用默认值。"; echo ""
    # 系统检测展示
    local sys_type; [ "$IS_ALPINE" = 1 ] && sys_type="Alpine Linux (OpenRC)" || sys_type="Debian/Ubuntu (systemd)"
    echo -e "  ${cyan}🖥 检测到系统: ${green}${sys_type}${re}\n"

    echo -e " ${white}━━━ ① 节点名称 ━━━${re}"; echo -ne "  [${NODE_NAME}]: "; read n ; [ -n "$n" ] && NODE_NAME="$n"; echo -e "  → ${green}${NODE_NAME}${re}\n"

    echo -e " ${white}━━━ ② Argo 隧道 ━━━${re}"
    echo -e "  ${green}1${re}. 启用 (VLESS/VMess over Cloudflare, 无需公网端口)"
    echo -e "  ${red}2${re}. 跳过 — 仅部署 Reality / HY2 / SS 等直连协议"
    echo -ne "  [1]: "; read tt
    case "${tt:-1}" in
        1) [ "$ARGO_MODE" = skip ] && ARGO_MODE=temp ;;
        2) ARGO_MODE="skip"; echo -e "  → ${red}跳过 Argo, 仅部署直连协议${re}\n" ;;
    esac

    if [ "$ARGO_MODE" != "skip" ]; then
        echo -e " ${white}━━━ ③ CDN 地址 ━━━${re}"; echo -e "  ${green}1${re}. 默认 ${green}2${re}. 列表选 ${green}3${re}. 自定义"; echo -ne "  [1]: "; read ct
        case "${ct:-1}" in
            2) for k in {1..14}; do echo -e "  ${green}${k}${re}. ${CDN_DOMAINS[$k]}"; done; echo -ne "  序号 [14]: "; read ci
               case "${ci:-14}" in
                   1) CDN_DOMAIN="xx.cloudflare.182682.xyz" ;; 2) CDN_DOMAIN="bestcf.top" ;; 3) CDN_DOMAIN="cdn.31514926.xyz" ;;
                   4) CDN_DOMAIN="skk.moe" ;; 5) CDN_DOMAIN="ip.sb" ;; 6) CDN_DOMAIN="time.is" ;;
                   7) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;; 8) CDN_DOMAIN="cf.090227.xyz" ;; 9) CDN_DOMAIN="yidong.19931101.xyz" ;;
                   10) CDN_DOMAIN="liantong.19931101.xyz" ;; 11) CDN_DOMAIN="dianxin.19931101.xyz" ;; 12) CDN_DOMAIN="cdn.2020111.xyz" ;; 13) CDN_DOMAIN="xn--b6gac.eu.org" ;;
                   14) CDN_DOMAIN="cdns.doon.eu.org" ;; esac ;;
            3) echo -ne "  地址: "; read CDN_DOMAIN; [ -z "$CDN_DOMAIN" ] && CDN_DOMAIN="$CDN_DEFAULT" ;;
        esac; echo -e "  → ${green}${CDN_DOMAIN}${re}\n"

        echo -e " ${white}━━━ ④ 客户端端口 ━━━${re}"; echo -e "  ${yellow}CF: 443 8443 2053 2083 2087 2096${re}"; echo -ne "  [${CDN_PORT}]: "; read n ; [ -n "$n" ] && CDN_PORT="$n"; echo -e "  → ${green}${CDN_PORT}${re}\n"
        echo -e " ${white}━━━ ⑤ UUID ━━━${re}"; echo -ne "  [自动生成]: "; read n ; [ -n "$n" ] && UUID_CUSTOM="$n"; echo ""

        echo -e " ${white}━━━ ⑥ 隧道模式 ━━━${re}"
        echo -e "  ${green}1${re}. 临时域名 (trycloudflare.com)    ${green}2${re}. 固定 Token"
        echo -ne "  [1]: "; read argo_type
        case "${argo_type:-1}" in
            2) echo -ne "  域名: "; read ARGO_FIXED_DOMAIN; echo -ne "  Token: "; read ARGO_AUTH
               [ -n "$ARGO_FIXED_DOMAIN" ] && [ -n "$ARGO_AUTH" ] && ARGO_MODE="fixed-token" ;;
        esac; echo ""

        echo -e " ${white}━━━ ⑦ 内部端口 ━━━${re}"; echo -e "  ${cyan}Argo:${ARGO_PORT}  VLESS:${VLESS_WS_PORT}  VMess:${VMESS_WS_PORT}${re}"
        echo -ne "  起始端口 [回车跳过]: "; read bp
        if [ -n "$bp" ] && is_port "$bp"; then ARGO_PORT="$bp"; VLESS_WS_PORT=$((bp+1)); VMESS_WS_PORT=$((bp+2)); fi
        echo ""
    fi
    echo -e " ${white}━━━ ⑧ 订阅域名（可选）━━━${re}"
    echo -e "  ${yellow}输入已指向本机IP的域名，订阅URL变为 https://域名:端口/sub?token=xxx${re}"
    echo -e "  ${yellow}使用CF代理端口 2096，DNS开小黄云即可，无需Origin Rules${re}"
    echo -e "  ${yellow}回车跳过则使用 http://IP:端口 格式${re}"
    [ -n "$SUB_DOMAIN" ] && echo -e "  ${cyan}当前: ${SUB_DOMAIN}${re}"
    echo -ne "  域名 [回车跳过]: "; read sd 
    [ -n "$sd" ] && SUB_DOMAIN="$sd"
    if [ -n "$SUB_DOMAIN" ]; then
        echo ""
        echo -e "  ${yellow}选择 CF 支持的 HTTPS 端口:${re}"
        echo -e "  ${cyan}1${re}. 2096 (默认)  ${cyan}2${re}. 8443  ${cyan}3${re}. 2053  ${cyan}4${re}. 2083  ${cyan}5${re}. 2087  ${cyan}6${re}. 443  ${cyan}c${re}. 自定义"
        echo -ne "  [1]: "; read pc 
        case "${pc:-1}" in
            2) SUB_PORT=8443 ;; 3) SUB_PORT=2053 ;; 4) SUB_PORT=2083 ;;
            5) SUB_PORT=2087 ;; 6) SUB_PORT=443 ;;
            c|C) echo -ne "  端口: "; read SUB_PORT ;;
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

    echo -e " ${white}━━━ ⑨ 额外协议（可选）━━━${re}"
    select_protocols || { yellow_msg "安装已取消。"; return 1; }

    echo -e " ${white}━━━ ⑩ Sing-box 内核（可选）━━━${re}"
    echo -e "  ${yellow}此处只安装内核；节点协议可在安装后从 s → s2 增配。${re}"
    echo -ne "  是否安装 Sing-box？[y/N]: "; read sb_yn
    if [ "$sb_yn" = "y" ] || [ "$sb_yn" = "Y" ]; then
        SB_ENABLE=true
        install_sb_core=true
        echo -e "  → ${green}将安装 Sing-box 内核${re}"
    else
        echo "  → 跳过本次 Sing-box 内核安装，已有节点设置保留。"
    fi


    if [ "$ARGO_MODE" = skip ] && [ "$ENABLE_REALITY" = 0 ] && [ "$ENABLE_HY2" = 0 ] && [ "$ENABLE_SS" = 0 ] &&
        { [ "$SB_ENABLE" != true ] || [ "${SB_HY2_ENABLE:-false}${SB_TUIC_ENABLE:-false}${SB_ANYTLS_ENABLE:-false}${SB_REALITY_ENABLE:-false}${SB_SS_ENABLE:-false}" = falsefalsefalsefalsefalse ]; }; then
        red_msg "尚未选择节点协议，请重新运行安装向导。"; return 1
    fi
    confirm_changes "保存全部设置并开始安装？" || return 1
    save_conf || return 1
    do_install "$install_sb_core"
}

#==============================================================================
# 安装
#==============================================================================
do_install() {
    local install_sb_core="${1:-${SB_ENABLE:-false}}"
    load_conf; clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}   ${white}ArgoV · 部署中...${re}                    ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

    yellow_msg "[1/6] 清理..."
    if [ "$IS_ALPINE" = 1 ]; then
        rc-service xray stop 2>/dev/null; rc-service argov-tunnel stop 2>/dev/null
    else
        systemctl stop xray argov-tunnel 2>/dev/null
    fi
    green_msg "  完成"

    yellow_msg "[2/6] 依赖..."
    if command -v apt &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof openssl iptables
    elif command -v yum &>/dev/null; then yum install -y -q jq unzip curl lsof openssl iptables
    elif command -v dnf &>/dev/null; then dnf install -y -q jq unzip curl lsof openssl iptables
    elif command -v apk &>/dev/null; then apk update -q && apk add -q jq unzip curl lsof openssl iproute2 iptables; fi; green_msg "  完成"

    mkdir -p "$WORK_DIR" && secure_work_dir_permissions
    local ARCH_ARG CF_ARCH; ARCH_ARG=$(detect_arch); CF_ARCH=$(cf_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/6] 下载..."
    download_xray_zip_checked "$ARCH_ARG" "${WORK_DIR}/xray.zip" || { red_msg "Xray 下载失败，请检查网络或校验配置！"; exit 1; }
    if [ "$ARGO_MODE" != "skip" ]; then
        download_cloudflared_checked "$CF_ARCH" "${WORK_DIR}/argo" || { red_msg "cloudflared 下载失败，请检查网络或校验配置！"; exit 1; }
    fi
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR">/dev/null 2>&1; chmod +x "${WORK_DIR}/xray"; rm -f "${WORK_DIR}/xray.zip"
    [ "$ARGO_MODE" != "skip" ] && chmod +x "${WORK_DIR}/argo"
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
        port_in_use_any "$HY2_PORT" && HY2_PORT=$(find_free_any_port "$HY2_PORT")
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
        if echo "$saved_inbounds" | jq -e '.[] | select(.tag=="hy2")' &>/dev/null; then
            ENABLE_HY2=1
            HY2_MPORT=$(jq -r '.inbounds[]|select(.tag=="hy2")|(.streamSettings.finalmask.quicParams.udpHop.ports//.streamSettings.hysteriaSettings.quicParams.udpHop.ports[0]//empty)' "$CONFIG_FILE" 2>/dev/null)
        fi
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="ss")'       &>/dev/null && ENABLE_SS=1
        normalize_xray_reality_config 2>/dev/null || true
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
    if [ "$ARGO_MODE" != "skip" ]; then
        rebuild_tunnel "$ARGO_MODE"; rm -f "$TUNNEL_LOG"
        systemctl enable argov-tunnel 2>/dev/null
    fi
    systemctl daemon-reload
    systemctl enable xray 2>/dev/null
    if [ "$ARGO_MODE" != "skip" ]; then
        systemctl restart xray argov-tunnel
    else
        systemctl restart xray
    fi
    sleep 5
    if [ "$ENABLE_HY2" = 1 ] && [ -n "$HY2_MPORT" ]; then
        if ! apply_hy2_hop_rules "$HY2_PORT" "$HY2_MPORT"; then
            clear_hy2_mport_config
            save_conf
            yellow_msg "  Hysteria2 端口跳跃规则安装失败，已关闭 mport。"
        fi
    fi
    green_msg "  完成"

    install_ag_wrapper

    # Sing-box 安装 (如果启用)
    if [ "$install_sb_core" = true ]; then
        install_singbox || yellow_msg "Sing-box 安装失败，可稍后重试"
    fi
    save_conf

    local hd ip; [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN" || hd=$(get_argo_domain)
    [ -z "$hd" ] && [ "$ARGO_MODE" != "fixed-token" ] && { sleep 3; hd=$(get_argo_domain); }
    [ -n "$hd" ] && LAST_ARGO_DOMAIN="$hd" && save_conf; ip=$(get_ip)
    # 恢复 relay / WARP (重装后重建 outbound + routing)
    [ "$RELAY_ENABLED" = "1" ] && relay_apply "restore"
    [ -f "$WARP_DOMAIN_FILE" ] && [ -s "$WARP_DOMAIN_FILE" ] && warp_apply_routing "restore"

    start_sub_server
    start_stats_service
    if sb_has_protocols; then
        sb_sync_users 2>/dev/null || true
        start_sb_stats_service 2>/dev/null || true
    fi
    setup_traffic_counters 2>/dev/null || true

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
    inbounds+='{"port":'"${ARGO_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"argo-in","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision","email":"argov-default"}],"decryption":"none","fallbacks":['"${fallbacks}"']},"streamSettings":{"network":"tcp"},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
    # 2. VLESS WS
    inbounds+=',{"port":'"${VLESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"vless-ws","settings":{"clients":[{"id":"'"${uuid}"'","email":"argov-default"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
    # 3. VMess WS
    inbounds+=',{"port":'"${VMESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vmess","tag":"vmess-ws","settings":{"clients":[{"id":"'"${uuid}"'","alterId":0,"email":"argov-default"}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-argo"}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
    # 4. Reality (opt)
    [ "$ENABLE_REALITY" = 1 ] && inbounds+=',{"port":'"${REALITY_PORT}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision","email":"argov-default"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"target":"'"${REALITY_SNI}"':443","serverNames":["'"${REALITY_SNI}"'",""],"privateKey":"'"${REALITY_PRIV}"'","shortIds":["'"${REALITY_SHORTID}"'"]}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
    # 5. Hysteria2 (opt)
    if [ "$ENABLE_HY2" = 1 ]; then
        local hy2_inbound
        hy2_inbound=$(build_hy2_inbound "$HY2_PORT" "$HY2_SNI" "$uuid" "argov-default" "$HY2_MPORT" "$HY2_CONGESTION" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS")
        inbounds+=",${hy2_inbound}"
    fi
    # 6. SS (opt)
    [ "$ENABLE_SS" = 1 ] && inbounds+=',{"port":'"${SS_PORT}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
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
    (
        load_conf
        jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1 || { red_msg "尚未添加 Xray HY2。"; return 1; }
        local old_port old_mport uuid ip new_inbound candidate
        old_port=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port' "$CONFIG_FILE")
        old_mport=$(jq -r '.inbounds[]|select(.tag=="hy2")|(.streamSettings.finalmask.quicParams.udpHop.ports//.streamSettings.hysteriaSettings.quicParams.udpHop.ports[0]//empty)' "$CONFIG_FILE")
        HY2_PORT="$old_port"; HY2_MPORT="$old_mport"
        HY2_SNI=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//empty' "$CONFIG_FILE")
        HY2_CONGESTION=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.finalmask.quicParams.congestion//"auto"' "$CONFIG_FILE")
        cyan_msg "编辑 Xray Hysteria2"
        prompt_xray_hy2 || return 1
        confirm_changes "应用以上 HY2 设置？域名变化时会更新证书指纹，客户端需刷新订阅" || return 1
        begin_protocol_edit xray || return 1
        gen_hy2_cert || return 1
        uuid=$(get_uuid)
        new_inbound=$(build_hy2_inbound "$HY2_PORT" "$HY2_SNI" "$uuid" argov-default "$HY2_MPORT" "$HY2_CONGESTION" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS")
        candidate=$(mktemp "${CONFIG_FILE}.edit.XXXXXX") || return 1
        jq --argjson i "$new_inbound" '(.inbounds[]|select(.tag=="hy2"))=$i' "$CONFIG_FILE" > "$candidate" || { rm -f "$candidate"; return 1; }
        commit_xray_candidate "$candidate" || return 1
        sync_xray_users || return 1
        save_conf || return 1
        restart_protocol_runtime xray || { red_msg "Xray 重启失败。"; return 1; }
        disable_hy2_hop_rules "$old_port" "$old_mport"
        if ! apply_hy2_hop_rules "$HY2_PORT" "$HY2_MPORT"; then
            clear_hy2_mport_config; save_conf
            yellow_msg "跳跃规则安装失败，已关闭跳跃；监听端口保持可用。"
        fi
        EDIT_COMMITTED=1
        start_sub_server >/dev/null 2>&1 &
        green_msg "HY2 设置已应用，请刷新客户端订阅。"
        ip=$(get_ip); [ -n "$ip" ] && gen_hy2_link "$uuid" "$ip" "$HY2_PORT" "$HY2_SNI" "${NODE_NAME}-Hy2" "$HY2_MPORT"
        echo
    )
}

legacy_manage_protocols_unused() {
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
        echo -ne "  请输入: "; read ac; [ "$ac" = "0" ] && return

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
            echo -ne "  新端口 [回车保持]: "; read np ; local new_port="${np:-$cur_port}"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ② WS 路径 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}${cur_path}${re}"
            echo -ne "  新路径 [回车保持]: "; read npt ; local new_path="${npt:-$cur_path}"
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
            echo ""; echo -ne "  按回车继续..."; read -r
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
            echo ""; echo -e "  ${yellow}当前: ${cyan}${new_method}${re}"; echo -ne "  新加密 [回车保持]: "; read sm 
            if [ -n "$sm" ]; then local si=$((sm-1)); [ "$si" -ge 0 ] 2>/dev/null && [ "$si" -lt "${#SS_METHODS[@]}" ] && new_method="${SS_METHODS[$si]}"; fi
            echo -e "  → ${green}${new_method}${re}\n"

            echo -e " ${white}━━━ ② 密码 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}$(echo "$cur_pass" | cut -c1-24)...${re}"; echo -e "  ${yellow}回车保持。输入 new 自动生成。${re}"
            echo -ne "  新密码 [回车保持]: "; read np 
            if [ "$np" = "new" ] || [ "$np" = "NEW" ]; then
                [[ "$new_method" =~ 2022 ]] && new_pass=$(gen_ss2022_pass "$new_method") || new_pass=$(cat /proc/sys/kernel/random/uuid)
            elif [ -n "$np" ]; then new_pass="$np"; fi
            echo -e "  → ${green}$(echo "$new_pass" | cut -c1-24)...${re}\n"

            echo -e " ${white}━━━ ③ 端口 ━━━${re}"; echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网端口"; echo -ne "  新端口 [回车保持]: "; read np2
            [ -n "$np2" ] && ! port_in_use "$np2" && new_port="$np2"; [ -n "$np2" ] && port_in_use "$np2" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ④ 网络 ━━━${re}"
            local cur_net; cur_net=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.network//"tcp,udp"' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}1${re}. tcp,udp  ${green}2${re}. tcp  ${green}3${re}. udp"
            echo -e "  ${yellow}当前: ${cyan}${cur_net}${re}"; echo -ne "  选择 [回车保持]: "; read nn 
            case "${nn:-0}" in 1) cur_net="tcp,udp" ;; 2) cur_net="tcp" ;; 3) cur_net="udp" ;; esac
            local new_net="$cur_net"
            echo -e "  → ${green}${new_net}${re}\n"
            ;;
        reality)
            echo -e " ${white}━━━ ① 伪装域名 ━━━${re}"
            for i in "${!REALITY_SNIS[@]}"; do local mk=" "; [ "${REALITY_SNIS[$i]}" = "$new_sni" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${REALITY_SNIS[$i]}"; done
            echo -e "  ${cyan}c${re}. 自定义"
            echo ""; echo -e "  ${yellow}当前: ${cyan}${new_sni}${re}"; echo -ne "  新 SNI [回车保持]: "; read rs 
            if [ "$rs" = "c" ] || [ "$rs" = "C" ]; then
                echo -ne "  输入 SNI: "; read new_sni ; [ -z "$new_sni" ] && new_sni="$cur_sni"
            elif [ -n "$rs" ]; then local ri=$((rs-1)); [ "$ri" -ge 0 ] 2>/dev/null && [ "$ri" -lt "${#REALITY_SNIS[@]}" ] && new_sni="${REALITY_SNIS[$ri]}"; fi
            echo -e "  → ${green}${new_sni}${re}\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"; echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网端口"; echo -ne "  新端口 [回车保持]: "; read np2
            [ -n "$np2" ] && ! port_in_use "$np2" && new_port="$np2"; [ -n "$np2" ] && port_in_use "$np2" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ③ x25519 密钥 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.privateKey//empty' "$CONFIG_FILE" 2>/dev/null | cut -c1-24)...${re}"
            echo -e "  ${yellow}输入 new 重新生成。${re}"; echo -ne "  [回车保持]: "; read rk 
            [ "$rk" = "new" ] || [ "$rk" = "NEW" ] && { gen_reality_keys; echo -e "  → ${green}新密钥已生成${re}"; }; echo ""

            echo -e " ${white}━━━ ④ ShortId ━━━${re}"
            local cur_sid; cur_sid=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds[0]//empty' "$CONFIG_FILE" 2>/dev/null)
            [ -z "$cur_sid" ] && cur_sid="(空)"
            echo -e "  ${yellow}当前: ${cyan}${cur_sid}${re}"
            echo -e "  ${yellow}回车保持。输入 new 随机生成。${re}"
            echo -ne "  新 ShortId [回车保持]: "; read nsid 
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
            echo ""; echo -e "  ${yellow}当前: ${cyan}${cur_fp}${re}"; echo -ne "  新指纹 [回车保持]: "; read fp 
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
               '(.inbounds[]|select(.tag=="reality")|.port)=$pt|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.target)=($sni+":443")|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings|=del(.dest,.publicKey,.fingerprint))|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames)=[$sni,""]' \
               "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            REALITY_PORT="$new_port"; REALITY_SNI="$new_sni"
            if [ "$rk" = "new" ] || [ "$rk" = "NEW" ]; then
                jq --arg priv "$REALITY_PRIV" \
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.privateKey)=$priv|(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings|=del(.dest,.publicKey,.fingerprint))' \
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
            if [ "$nsid" = "new" ] || [ "$nsid" = "NEW" ] || [ -n "$nsid" ]; then
                local sid_val; [ -n "$REALITY_SHORTID" ] && sid_val="\"$REALITY_SHORTID\"" || sid_val="\"\""
                jq --argjson s "[${sid_val}]" \
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds)=$s' \
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
            [ -n "$new_fp" ] && REALITY_FP="$new_fp"
            ;;
    esac
    save_conf; yellow_msg "重启 Xray..."; systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "完成"

    echo ""; echo -e " ${white}━━━ 更新后链接 ━━━${re}"; echo ""
    local ip hd cd cp; ip=$(get_ip); hd=$(get_argo_domain); cd=$(get_cdn); cp=$(get_cdn_port)
    [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"
    case "$tag" in
        ss) [ -n "$ip" ] && echo -e "  ${green}$(gen_ss_link "$new_method" "$new_pass" "$ip" "$new_port" "${NODE_NAME}-SS")${re}" ;;
        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$new_port" "$new_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;; 
    esac
    echo ""; echo -ne "  按回车继续..."; read -r
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
            echo ""; echo -e "  ${yellow}当前: ${cyan}${sm}${re}"; echo -ne "  选择 [回车保持]: "; read s 
            local si=$(( ${s:-0} -1 ))
            [ "$si" -ge 0 ] 2>/dev/null && [ "$si" -lt "${#SS_METHODS[@]}" ] && sm="${SS_METHODS[$si]}"
            echo -e "  → ${green}${sm}${re}\n"

            echo -e " ${white}━━━ ② 密码 ━━━${re}"
            local dp; [[ "$sm" =~ 2022 ]] && dp=$(gen_ss2022_pass "$sm") || dp="$uuid"
            [ -z "$sp" ] && sp="$dp"
            echo -e "  ${yellow}当前: ${cyan}$(echo "$sp"|cut -c1-20)...${re}"
            echo -e "  ${yellow}回车保持。输入 new 自动生成。${re}"
            echo -ne "  密码 [回车保持]: "; read s 
            if [ "$s" = "new" ] || [ "$s" = "NEW" ]; then
                [[ "$sm" =~ 2022 ]] && sp=$(gen_ss2022_pass "$sm") || sp=$(cat /proc/sys/kernel/random/uuid)
            elif [ -n "$s" ]; then sp="$s"; fi
            echo -e "  → ${green}$(echo "$sp"|cut -c1-24)...${re}\n"

            echo -e " ${white}━━━ ③ 端口 ━━━${re}"
            [ -z "$s_port" ] && { local dpt; dpt=$(find_free_port "${SS_PORT:-0}"); [ "$dpt" = "0" ] && dpt=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); s_port="$dpt"; }
            echo -e "  ${yellow}当前: ${cyan}${s_port}${re}"; echo -ne "  端口 [回车保持]: "; read s 
            [ -n "$s" ] && ! port_in_use "$s" && s_port="$s"; [ -n "$s" ] && port_in_use "$s" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${s_port}${re}\n"

            echo -e " ${white}━━━ ④ 网络 ━━━${re}"
            echo -e "  ${green}1${re}. tcp,udp  ${green}2${re}. tcp  ${green}3${re}. udp"
            echo -e "  ${yellow}当前: ${cyan}${s_net}${re}"; echo -ne "  选择 [回车保持]: "; read s 
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
            echo -e "  ${yellow}当前: ${cyan}${r_sni}${re}"; echo -ne "  选择 [回车保持]: "; read rs 
            local ri=$(( ${rs:-0} -1 ))
            if [ "$rs" = "c" ] || [ "$rs" = "C" ]; then
                echo -ne "  输入 SNI: "; read r_sni ; [ -z "$r_sni" ] && r_sni="www.tesla.com"
            elif [ "$ri" -ge 0 ] 2>/dev/null && [ "$ri" -lt "${#REALITY_SNIS[@]}" ]; then
                r_sni="${REALITY_SNIS[$ri]}"
            fi
            echo -e "  → ${green}${r_sni}${re}\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"
            [ -z "$r_port" ] && { r_port=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); }
            echo -e "  ${yellow}当前: ${cyan}${r_port}${re}"; echo -ne "  端口 [回车保持]: "; read s 
            [ -n "$s" ] && ! port_in_use "$s" && r_port="$s"; [ -n "$s" ] && port_in_use "$s" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${r_port}${re}\n"

            echo -e " ${white}━━━ ③ ShortId ━━━${re}"
            [ -z "$r_sid" ] && { r_sid=$(openssl rand -hex 4 2>/dev/null || printf '%08x' $((RANDOM*RANDOM))); }
            echo -e "  ${yellow}8位十六进制，客户端需匹配。${re}"
            echo -e "  ${yellow}当前: ${cyan}${r_sid}${re}"; echo -ne "  ShortId [回车保持]: "; read s 
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
            echo -ne "  [回车保持]: "; read s 
            [ "$s" = "new" ] || [ "$s" = "NEW" ] && { gen_reality_keys; echo -e "  → ${green}新密钥已生成${re}"; }
            echo -e "  → ${green}$(echo "${REALITY_PUB}"|cut -c1-24)...${re}\n"

            echo -e " ${white}━━━ ⑤ 指纹 (Fingerprint) ━━━${re}"
            local fps=("chrome" "firefox" "safari" "edge" "random")
            for i in "${!fps[@]}"; do local mk=" "; [ "${fps[$i]}" = "$r_fp" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${fps[$i]}"; done
            echo ""; echo -e "  ${yellow}当前: ${cyan}${r_fp}${re}"; echo -ne "  选择 [回车保持]: "; read s 
            local fi=$(( ${s:-0} -1 ))
            [ "$fi" -ge 0 ] 2>/dev/null && [ "$fi" -lt "${#fps[@]}" ] && r_fp="${fps[$fi]}"
            echo -e "  → ${green}${r_fp}${re}\n"

            echo -e " ${white}━━━ ⑥ 流控 (Flow) ━━━${re}"
            echo -e "  ${green}1${re}. xtls-rprx-vision"
            echo ""; echo -e "  ${yellow}当前: ${cyan}xtls-rprx-vision${re}"; echo -ne "  [回车保持]: "; read s 
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
            new_inbound='{"port":'"${r_port}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision","email":"argov-default"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"target":"'"${r_sni}"':443","serverNames":["'"${r_sni}"'",""],"privateKey":"'"${REALITY_PRIV}"'","shortIds":['"${sid_val}"']}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}'
            REALITY_PORT="$r_port"; REALITY_SNI="$r_sni"; REALITY_FP="$r_fp"; ENABLE_REALITY=1 ;;
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
    echo ""; echo -ne "  按回车返回..."; read -r
}

legacy_delete_protocol_unused() {
    clear
    local has_reality=0 has_ss=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
    [ $((has_reality+has_ss)) = 0 ] && { echo ""; green_msg "无可删除。"; echo ""; echo -ne "  按回车返回..."; read -r; return; }

    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}         ${red}删除节点${re}                          ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""
    local dd=0
    [ "$has_reality" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. VLESS Reality"
    [ "$has_ss" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. Shadowsocks"
    echo -e "  ${cyan}0${re}. 返回"; echo -e " ${purple}────────────────────────────────────────${re}"
    echo -ne "  选择: "; read dc ; [ "$dc" = "0" ] && return

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
    echo ""; echo -ne "  按回车返回..."; read -r
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
    echo -ne "  链接: "; read link 
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
        echo -ne "  请选择: "; read c 
        case "$c" in
            0) return ;;
            d|D)
                echo -ne "  删除序号 (多个用逗号分隔，如 1,3): "; read nums 
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

# MODULE: relay routing
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
        echo -ne "  请选择: "; read c 
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
                echo -ne "  粘贴链接: "; read link 
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
                    [ "$cf" != "n" ] && [ "$cf" != "N" ] && { RELAY_ENABLED=1; relay_apply; echo ""; echo -ne "  按回车返回..."; read -r; } || yellow_msg "已保存，别忘了按 r4 应用！"
                fi
                ;;
            r3|R3)
                if [ "$RELAY_MODE" != "split" ]; then red_msg "请先切换到分流模式"; sleep 1; continue; fi
                relay_manage_domains
                if [ "$RELAY_ENABLED" = "1" ] && [ -n "$RELAY_LINK" ]; then
                    echo -ne "  ${yellow}域名已更新，立即应用路由规则? (y/n) [y]: ${re}"; read cf
                    [ "$cf" != "n" ] && [ "$cf" != "N" ] && { RELAY_ENABLED=1; relay_apply; echo ""; echo -ne "  按回车返回..."; read -r; }
                fi
                ;;
            r4|R4)
                if [ -z "$RELAY_LINK" ]; then red_msg "请先设置落地节点 (r1)"; sleep 1; continue; fi
                relay_apply; echo ""; echo -ne "  按回车返回..."; read -r
                ;;
            r5|R5)
                [ "$RELAY_ENABLED" != "1" ] && { yellow_msg "中继未启用。"; sleep 1; continue; }
                echo -ne "  ${red}确认关闭? (y/n): ${re}"; read cf
                [ "$cf" != "y" ] && [ "$cf" != "Y" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                relay_clear; echo ""; echo -ne "  按回车返回..."; read -r
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
        echo -ne "  请选择: "; read c 
        case "$c" in
            1) echo ""; echo -e "  ${yellow}多个用逗号分隔:${re}"; echo -ne "  > "; read input 
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
               echo -ne "  > "; read input 
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
    [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ] && cp "$SB_CONFIG_FILE" "${SB_CONFIG_FILE}.bak"

    local py_err; py_err=$(mktemp /tmp/relay_err.XXXXXX)
    RELAY_LINK_ENV="$RELAY_LINK" RELAY_MODE_ENV="$RELAY_MODE" SB_CONFIG_ENV="$SB_CONFIG_FILE" SB_ENABLED_ENV="${SB_ENABLE:-false}" SB_VERSION_ENV="$(singbox_version_string)" python3 2>"$py_err" << PYEOF
import json, base64, os, re, sys
from urllib.parse import parse_qs, unquote, urlsplit

CONFIG = '${CONFIG_FILE}'
SB_CONFIG = os.environ.get('SB_CONFIG_ENV', '/etc/sing-box/config.json')
SB_ENABLED = os.environ.get('SB_ENABLED_ENV', 'false') == 'true'
SB_VERSION = os.environ.get('SB_VERSION_ENV', '')
RELAY_LINK = os.environ.get('RELAY_LINK_ENV', '')
RELAY_MODE = os.environ.get('RELAY_MODE_ENV', 'all')
DOMAINS = ${domains_json}

def decode_b64(s):
    """安全 base64 解码，补齐 padding"""
    s = s + '=' * (-len(s) % 4)
    s = s.replace('-', '+').replace('_', '/')
    return base64.b64decode(s).decode('utf-8', errors='replace')

def split_host_port(server, default_port=443):
    server = server.split('?', 1)[0].split('#', 1)[0]
    if server.startswith('['):
        host, _, rest = server[1:].partition(']')
        port = int(rest[1:]) if rest.startswith(':') and rest[1:] else default_port
        return host, port
    if server.count(':') > 1:
        return server, default_port
    host, sep, raw_port = server.rpartition(':')
    if sep and raw_port.isdigit():
        return host, int(raw_port)
    return server, default_port

def parse_url(link):
    u = urlsplit(link)
    host = u.hostname or ''
    port = u.port or 443
    return u, host, port, parse_qs(u.query)

def cert_pins(qs):
    raw = next((qs[k][0] for k in ('pcs', 'pinSHA256', 'pinnedPeerCertSha256') if qs.get(k)), '')
    if not raw:
        return []
    pins = [p.strip().replace(':', '') for p in raw.split(',')]
    if any(not re.fullmatch('[0-9a-fA-F]{64}', p) for p in pins):
        raise ValueError('证书指纹应为 64 位 SHA256 十六进制，支持冒号分隔')
    return pins

def tls_options(sni, qs):
    tls = {'serverName': sni} if sni else {}
    pins = cert_pins(qs)
    skip = qs.get('allowInsecure', qs.get('insecure', ['']))[0].lower() in ('1', 'true', 'yes')
    if pins:
        tls['pinnedPeerCertSha256'] = ','.join(pins)
    elif skip:
        raise ValueError('新版 Xray 不支持 allowInsecure=1。请在链接中提供 pcs 或 pinSHA256 证书指纹，或使用受信证书；原配置未修改')
    if qs.get('alpn', [''])[0]:
        tls['alpn'] = [v for v in qs['alpn'][0].split(',') if v]
    if qs.get('fp', [''])[0]:
        tls['fingerprint'] = qs['fp'][0]
    return tls

def sb_tls_options(security, sni, qs):
    if security not in ('tls', 'reality'):
        return None
    tls = {'enabled': True}
    if sni:
        tls['server_name'] = sni
    if qs.get('alpn', [''])[0]:
        tls['alpn'] = [v for v in qs['alpn'][0].split(',') if v]
    if qs.get('fp', [''])[0]:
        tls['utls'] = {'enabled': True, 'fingerprint': qs['fp'][0]}
    if security == 'reality':
        tls['reality'] = {'enabled': True, 'public_key': qs.get('pbk', [''])[0], 'short_id': qs.get('sid', [''])[0]}
        return tls
    pins = cert_pins(qs)
    spki = qs.get('certificate_public_key_sha256', [''])[0]
    if spki:
        values = spki.split(',')
        if any(len(base64.b64decode(v, validate=True)) != 32 for v in values):
            raise ValueError('Sing-box 公钥 SHA256 应为 32 字节摘要的 Base64，不能填入证书十六进制指纹')
        tls['certificate_public_key_sha256'] = values
    elif pins and SB_ENABLED:
        version = re.match(r'^v?(\d+)\.(\d+)\.(\d+)(.*)$', SB_VERSION)
        supported = False
        if version:
            release = tuple(int(v) for v in version.groups()[:3])
            suffix = version.group(4)
            alpha = re.fullmatch(r'-alpha\.(\d+)', suffix)
            supported = release > (1, 15, 0) or (release == (1, 15, 0) and (not suffix or (alpha and int(alpha.group(1)) >= 7)))
        if not supported:
            raise ValueError('当前 Sing-box 不支持完整证书 SHA256 固定。双核中继链接还需提供 certificate_public_key_sha256 公钥指纹，或使用受信证书；原配置未修改')
        tls['certificate_sha256'] = [base64.b64encode(bytes.fromhex(p)).decode() for p in pins]
    return tls

def sb_transport_options(network, qs):
    if not SB_ENABLED or network in ('tcp', 'raw', ''):
        return None
    path, host = qs.get('path', ['/'])[0] or '/', qs.get('host', [''])[0]
    if network in ('ws', 'httpupgrade'):
        transport = {'type': network, 'path': path}
        if host:
            if network == 'ws': transport['headers'] = {'Host': host}
            else: transport['host'] = host
        return transport
    if network == 'grpc':
        return {'type': 'grpc', 'service_name': qs.get('serviceName', [''])[0]}
    raise ValueError('当前 Sing-box 不支持该中继传输 ' + network + '，请提供双核均支持的节点；原配置未修改')

def apply_stream(out, network='tcp', security='none', sni='', qs=None):
    qs = qs or {}
    stream = {"network": network or "tcp"}
    if security == 'reality':
        stream["security"] = "reality"
        stream["realitySettings"] = {
            "serverName": sni,
            "publicKey": qs.get('pbk', [''])[0],
            "shortId": qs.get('sid', [''])[0],
            "fingerprint": qs.get('fp', ['chrome'])[0]
        }
    elif security == 'tls':
        stream["security"] = "tls"
        stream["tlsSettings"] = tls_options(sni, qs)
    elif security and security != 'none':
        stream["security"] = security

    if stream["network"] == "ws":
        path = qs.get('path', ['/'])[0] or '/'
        host = qs.get('host', [''])[0]
        ws = {"path": path}
        if host:
            ws["headers"] = {"Host": host}
        stream["wsSettings"] = ws
    elif stream['network'] in ('xhttp', 'splithttp'):
        stream['network'] = 'xhttp'
        settings = {'path': qs.get('path', ['/'])[0] or '/', 'host': qs.get('host', [''])[0], 'mode': qs.get('mode', ['auto'])[0]}
        if qs.get('extra', [''])[0]:
            settings['extra'] = json.loads(qs['extra'][0])
            if not isinstance(settings['extra'], dict):
                raise ValueError('XHTTP extra 必须是 JSON 对象')
        stream['xhttpSettings'] = settings
    elif stream['network'] == 'grpc':
        stream['grpcSettings'] = {'serviceName': qs.get('serviceName', [''])[0], 'multiMode': qs.get('mode', [''])[0] == 'multi'}
    elif stream['network'] == 'httpupgrade':
        stream['httpupgradeSettings'] = {'path': qs.get('path', ['/'])[0] or '/', 'host': qs.get('host', [''])[0]}
    elif stream['network'] not in ('tcp', 'raw'):
        raise ValueError('当前 Xray 不支持该中继传输 ' + stream['network'] + '；原配置未修改')

    if stream["network"] != "tcp" or stream.get("security") not in (None, "none"):
        out["streamSettings"] = stream

ROUTE_SNIFFING = {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}
ROUTE_SNIFF_TAGS = {"argo-in", "vless-ws", "vmess-ws", "reality", "hy2", "ss"}
DOMAIN_PREFIXES = ("domain:", "full:", "regexp:", "keyword:", "geosite:", "ext:", "dotless:")

def enable_route_sniffing(config):
    for inbound in config.get("inbounds", []):
        if inbound.get("tag") in ROUTE_SNIFF_TAGS:
            inbound["sniffing"] = dict(ROUTE_SNIFFING)

# --- 解析链接 ---
def normalize_relay_domains(items):
    out = []
    seen = set()
    for raw in items:
        d = str(raw).strip()
        if not d:
            continue
        if d.startswith(("http://", "https://")):
            d = urlsplit(d).hostname or ""
        if d.startswith("*."):
            d = d[2:]
        d = d.strip().strip("/")
        if not d:
            continue
        if not d.startswith(DOMAIN_PREFIXES):
            d = "domain:" + d.lstrip(".")
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out

proto = addr = port = ''
out = {}  # Xray outbound
sb_out = {}  # Sing-box outbound, when Sing-box is installed

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
        addr, port = split_host_port(addr_part)
        raw = decode_b64(userinfo)
        parts = raw.split(':', 1)
        method = parts[0] if parts[0] else method
        password = parts[1] if len(parts) > 1 else ''
    else:
        # Legacy: 整个字符串是一个 base64
        raw = decode_b64(rest)
        if '@' not in raw:
            raise ValueError(f'Cannot parse SS link format: {rest[:40]}...')
        mp, addr_part = raw.rsplit('@', 1)
        addr, port = split_host_port(addr_part)
        parts = mp.split(':', 1)
        method = parts[0] if parts[0] else method
        password = parts[1] if len(parts) > 1 else ''
    out = {
        "tag": "relay-out",
        "protocol": "shadowsocks",
        "domainStrategy": "AsIs",
        "settings": {"servers": [{"address": addr, "port": port, "method": method, "password": password}]}
    }
    sb_out = {"type": "shadowsocks", "tag": "argov-relay", "server": addr,
              "server_port": port, "method": method, "password": password}

elif RELAY_LINK.startswith('vless://'):
    proto = 'vless'
    u, addr, port, qs = parse_url(RELAY_LINK)
    uuid = unquote(u.username or '')
    if not uuid or not addr:
        raise ValueError('Invalid vless link')
    flow = qs.get('flow', [''])[0]
    encryption = qs.get('encryption', ['none'])[0] or 'none'
    if SB_ENABLED and encryption != 'none':
        raise ValueError('当前 Sing-box 不支持 VLESS Encryption 双核中继，请提供兼容节点；原配置未修改')
    user = {"id": uuid, "encryption": encryption}
    if flow:
        user["flow"] = flow
    out = {
        "tag": "relay-out",
        "protocol": "vless",
        "domainStrategy": "AsIs",
        "settings": {"vnext": [{"address": addr, "port": port, "users": [user]}]}
    }
    network = qs.get('type', qs.get('network', ['tcp']))[0] or 'tcp'
    security = qs.get('security', ['none'])[0]
    sni = qs.get('sni', qs.get('servername', ['']))[0]
    apply_stream(out, network, security, sni, qs)
    sb_out = {"type": "vless", "tag": "argov-relay", "server": addr,
              "server_port": port, "uuid": uuid}
    if flow:
        sb_out["flow"] = flow
    if security == 'reality':
        reality = {"enabled": True, "public_key": qs.get('pbk', [''])[0],
                   "short_id": qs.get('sid', [''])[0]}
        tls = {"enabled": True, "server_name": sni, "reality": reality}
        if qs.get('fp', [''])[0]:
            tls["utls"] = {"enabled": True, "fingerprint": qs['fp'][0]}
        sb_out["tls"] = tls
    elif security == 'tls':
        tls = {"enabled": True}
        if sni:
            tls["server_name"] = sni
        if qs.get('allowInsecure', qs.get('insecure', ['']))[0].lower() in ('1', 'true', 'yes'):
            tls["insecure"] = True
        sb_out["tls"] = tls
    if network == 'ws':
        transport = {"type": "ws", "path": unquote(qs.get('path', ['/'])[0] or '/')}
        host = qs.get('host', [''])[0]
        if host:
            transport["headers"] = {"Host": host}
        sb_out["transport"] = transport

elif RELAY_LINK.startswith('vmess://'):
    proto = 'vmess'
    b64 = RELAY_LINK[8:]
    raw = decode_b64(b64)
    vm = json.loads(raw)
    addr = vm.get('add', '')
    port = int(vm.get('port', 443))
    uuid = vm.get('id', '')
    sni = vm.get('sni', addr)
    network = vm.get('net', 'tcp') or 'tcp'
    method = vm.get('scy', 'auto') or 'auto'
    alter_id = int(vm.get('aid', 0))
    out = {
        "tag": "relay-out",
        "protocol": "vmess",
        "domainStrategy": "AsIs",
        "settings": {"vnext": [{"address": addr, "port": port, "users": [{"id": uuid, "alterId": 0}]}]}
    }
    qs = {"path": [vm.get('path', '/')], "host": [vm.get('host', '')], "serviceName": [vm.get('path', '')]}
    for key in ('allowInsecure', 'insecure', 'pcs', 'pinSHA256', 'pinnedPeerCertSha256', 'certificate_public_key_sha256', 'fp', 'alpn'):
        if vm.get(key) is not None:
            qs[key] = [str(vm[key])]
    security = 'tls' if vm.get('tls') == 'tls' else 'none'
    apply_stream(out, network, security, sni, qs)
    sb_out = {"type": "vmess", "tag": "argov-relay", "server": addr,
              "server_port": port, "uuid": uuid, "security": method,
              "alter_id": alter_id}
    if vm.get('tls') == 'tls':
        sb_out["tls"] = {"enabled": True, "server_name": sni or addr}
    if network == 'ws':
        transport = {"type": "ws", "path": unquote(vm.get('path', '/') or '/')}
        host = vm.get('host', '')
        if host:
            transport["headers"] = {"Host": host}
        sb_out["transport"] = transport

elif RELAY_LINK.startswith('trojan://'):
    proto = 'trojan'
    u, addr, port, qs = parse_url(RELAY_LINK)
    password = unquote(u.username or '')
    if not password or not addr:
        raise ValueError('Invalid trojan link')
    out = {
        "tag": "relay-out",
        "protocol": "trojan",
        "domainStrategy": "AsIs",
        "settings": {"servers": [{"address": addr, "port": port, "password": password}]}
    }
    network = qs.get('type', qs.get('network', ['tcp']))[0] or 'tcp'
    sni = qs.get('sni', qs.get('peer', ['']))[0]
    security = qs.get('security', ['tls'])[0]
    apply_stream(out, network, security, sni, qs)
    sb_out = {"type": "trojan", "tag": "argov-relay", "server": addr,
              "server_port": port, "password": password}
    if security in ('tls', 'reality'):
        tls = {"enabled": True}
        if sni:
            tls["server_name"] = sni
        if security == 'reality':
            tls["reality"] = {"enabled": True, "public_key": qs.get('pbk', [''])[0],
                               "short_id": qs.get('sid', [''])[0]}
        elif qs.get('allowInsecure', qs.get('insecure', ['']))[0].lower() in ('1', 'true', 'yes'):
            tls["insecure"] = True
        sb_out["tls"] = tls
    if network == 'ws':
        transport = {"type": "ws", "path": unquote(qs.get('path', ['/'])[0] or '/')}
        host = qs.get('host', [''])[0]
        if host:
            transport["headers"] = {"Host": host}
        sb_out["transport"] = transport

else:
    raise ValueError(f'Unsupported protocol: {proto}')

if SB_ENABLED and proto in ('vless', 'vmess', 'trojan'):
    tls = sb_tls_options(security, sni, qs)
    sb_out.pop('tls', None)
    if tls:
        sb_out['tls'] = tls
    transport = sb_transport_options(network, qs)
    sb_out.pop('transport', None)
    if transport:
        sb_out['transport'] = transport

# 防御校验：addr/port 不能为空
if not addr or not port or port <= 0:
    raise ValueError(f'Parsed invalid address: "{addr}:{port}". Check the link format.')

# --- 注入 config.json ---
with open(CONFIG, 'r') as f:
    config = json.load(f)

enable_route_sniffing(config)

# 清理旧 relay-out (只清 relay，不动 warp)
config['outbounds'] = [o for o in config['outbounds'] if o.get('tag') != 'relay-out']
config.setdefault('routing', {}).setdefault('rules', [])
config['routing']['rules'] = [r for r in config['routing']['rules'] if r.get('outboundTag') != 'relay-out']

# In all mode the first outbound is the fallback when no routing rule matches.
# Keep relay first so a missed rule cannot silently use the local direct exit.
if RELAY_MODE == 'all':
    config['outbounds'].insert(0, out)
else:
    config['outbounds'].append(out)

# 构造 routing rule
if RELAY_MODE == 'all':
    relay_rule = {"type": "field", "network": "tcp,udp", "outboundTag": "relay-out"}
else:
    relay_domains = normalize_relay_domains(DOMAINS)
    if not relay_domains:
        raise ValueError('分流模式但无分流域名')
    relay_rule = {"type": "field", "domain": relay_domains, "outboundTag": "relay-out"}

# API traffic must retain its own outbound. A catch-all relay rule ahead of it
# breaks StatsService and can make the panel report misleading traffic data.
api_rules = [r for r in config['routing']['rules'] if r.get('outboundTag') == 'api']
other_rules = [r for r in config['routing']['rules'] if r.get('outboundTag') != 'api']
config['routing']['rules'] = api_rules + [relay_rule] + other_rules

# 写回
with open(CONFIG, 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

# Apply the same relay to Sing-box. Its Hysteria2 listeners are separate from
# Xray's router, so updating config.json alone leaves Sing-box traffic direct.
if SB_ENABLED and os.path.isfile(SB_CONFIG):
    with open(SB_CONFIG, 'r', encoding='utf-8') as f:
        sb_config = json.load(f)
    sb_config['outbounds'] = [o for o in sb_config.get('outbounds', [])
                              if o.get('tag') != 'argov-relay']
    sb_config['outbounds'].append(sb_out)
    route = sb_config.setdefault('route', {})
    rules = [r for r in route.get('rules', []) if r.get('outbound') != 'argov-relay']
    if RELAY_MODE == 'all':
        rules.insert(0, {"action": "route", "outbound": "argov-relay"})
        route['final'] = 'argov-relay'
    else:
        relay_domains = normalize_relay_domains(DOMAINS)
        if not relay_domains:
            raise ValueError('分流模式但无分流域名')
        rules = [r for r in rules if r.get('action') != 'sniff']
        rules.insert(0, {"action": "sniff"})
        rules.insert(1, {"domain": relay_domains, "action": "route", "outbound": "argov-relay"})
        route.setdefault('final', 'direct-out')
    route['rules'] = rules

    if not re.match(r'^\d{1,3}(?:\.\d{1,3}){3}$', addr) and ':' not in addr:
        dns = sb_config.setdefault('dns', {})
        servers = dns.setdefault('servers', [])
        if not any(s.get('tag') == 'argov-relay-dns' for s in servers):
            servers.append({"type": "local", "tag": "argov-relay-dns"})
        route['default_domain_resolver'] = 'argov-relay-dns'

    with open(SB_CONFIG, 'w', encoding='utf-8') as f:
        json.dump(sb_config, f, indent=2, ensure_ascii=False)

print(f'RELAY_OK|{proto}|{addr}:{port}')
PYEOF

    local result=$?
    # Validate all configured cores before restarting services.
    local config_ok=1
    if [ "$result" -ne 0 ] || ! python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>"$py_err" || \
       [ ! -x "${WORK_DIR}/xray" ] || ! "${WORK_DIR}/xray" run -test -config "$CONFIG_FILE" >"$py_err" 2>&1; then
        config_ok=0
    fi
    if [ "$config_ok" = 1 ] && [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ]; then
        if ! sb_is_installed || ! sing-box check -c "$SB_CONFIG_FILE" >"$py_err" 2>&1; then
            config_ok=0
        fi
    fi

    if [ "$config_ok" = 1 ]; then
        systemctl restart xray 2>/dev/null
        [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ] && sb_restart 2>/dev/null
        sleep 2
        if systemctl is-active xray 2>/dev/null && { [ "${SB_ENABLE:-false}" != "true" ] || [ ! -f "$SB_CONFIG_FILE" ] || sb_status; }; then
            RELAY_ENABLED=1; save_conf
            [ "$mode" != "restore" ] && green_msg "落地中继已生效！"
            rm -f "$py_err"
            return 0
        else
            red_msg "代理内核启动失败！自动回滚中继配置。"
            cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            systemctl restart xray 2>/dev/null; sleep 2
            if [ "${SB_ENABLE:-false}" = "true" ] && [ -f "${SB_CONFIG_FILE}.bak" ]; then
                cp "${SB_CONFIG_FILE}.bak" "$SB_CONFIG_FILE"
                sb_restart 2>/dev/null || true
            fi
        fi
    else
        red_msg "中继配置失败！"
        local emsg; emsg=$(tail -n 1 "$py_err" 2>/dev/null)
        [ -n "$emsg" ] && echo -e "  ${yellow}${emsg}${re}"
        cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        [ "${SB_ENABLE:-false}" = "true" ] && [ -f "${SB_CONFIG_FILE}.bak" ] && cp "${SB_CONFIG_FILE}.bak" "$SB_CONFIG_FILE"
    fi
    rm -f "$py_err"
    return 1
}

relay_clear() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        [ -f "$SB_CONFIG_FILE" ] && cp "$SB_CONFIG_FILE" "${SB_CONFIG_FILE}.bak"
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

        if [ -f "$SB_CONFIG_FILE" ]; then
            python3 - "$SB_CONFIG_FILE" << 'PYCLEARSBRELAY'
import json, os, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    config = json.load(f)
config["outbounds"] = [o for o in config.get("outbounds", [])
                       if o.get("tag") != "argov-relay"]
route = config.setdefault("route", {})
route["rules"] = [r for r in route.get("rules", [])
                  if r.get("outbound") != "argov-relay"]
if route.get("final") == "argov-relay":
    route["final"] = "direct-out"
if route.get("default_domain_resolver") == "argov-relay-dns":
    route.pop("default_domain_resolver", None)
dns = config.get("dns", {})
dns["servers"] = [s for s in dns.get("servers", [])
                  if s.get("tag") != "argov-relay-dns"]
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(config, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
PYCLEARSBRELAY
        fi

        local clear_ok=1
        python3 -c "import json; json.load(open('${CONFIG_FILE}'))" 2>/dev/null || clear_ok=0
        [ "$clear_ok" = 1 ] && [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ] && \
            { ! sb_is_installed || ! sing-box check -c "$SB_CONFIG_FILE" >/dev/null 2>&1; } && clear_ok=0
        [ "$clear_ok" = 1 ] && [ -x "${WORK_DIR}/xray" ] && \
            "${WORK_DIR}/xray" run -test -config "$CONFIG_FILE" >/dev/null 2>&1 || clear_ok=0

        if [ "$clear_ok" = 1 ]; then
            systemctl restart xray 2>/dev/null
            [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ] && sb_restart 2>/dev/null
            sleep 2
            if systemctl is-active xray 2>/dev/null && { [ "${SB_ENABLE:-false}" != "true" ] || [ ! -f "$SB_CONFIG_FILE" ] || sb_status; }; then
                RELAY_ENABLED=0; save_conf
                get_status; green_msg "中继已关闭。"
                return 0
            fi
            clear_ok=0
        fi

        if [ "$clear_ok" != 1 ]; then
            cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            if [ "${SB_ENABLE:-false}" = "true" ] && [ -f "${SB_CONFIG_FILE}.bak" ]; then
                cp "${SB_CONFIG_FILE}.bak" "$SB_CONFIG_FILE"
            fi
            systemctl restart xray 2>/dev/null
            [ "${SB_ENABLE:-false}" = "true" ] && [ -f "$SB_CONFIG_FILE" ] && sb_restart 2>/dev/null
            red_msg "关闭中继失败，已恢复原配置。"
        else
            red_msg "关闭中继失败。"
        fi
    fi
}

#==============================================================================
# WARP SOCKS/IPv6 域名分流模块（基于 fscarmen/warp + Python3 JSON 安全改写）
#==============================================================================
WARP_DOMAIN_FILE="/etc/xray/warp_domains.txt"
WARP_DEFAULT_DOMAINS="google.com googleapis.com googleusercontent.com gstatic.com youtube.com ytimg.com googlevideo.com ggpht.com google-analytics.com googleadservices.com"

# === WARP 主入口 ===
# MODULE: WARP routing
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
        echo -ne "  请选择: "; read wc 

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
    local warp_rc=0
    if run_warp_menu w; then
        warp_rc=0
    else
        warp_rc=$?
        red_msg "下载 fscarmen WARP 脚本失败，请检查网络"
        echo ""; echo -ne "  按回车继续..."; read -r; return 1
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
        echo ""; echo -ne "  按回车继续..."; read -r
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
    # 模式 w = WireProxy/Socks5 模式，默认端口 40000
    if ! run_warp_menu w; then
        red_msg "下载失败，请检查网络连接。"
        echo ""; echo -ne "  按回车返回..."; read -r; return
    fi

    # 验证安装
    sleep 3
    if (ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':40000 '; then
        green_msg "WARP Socks5 安装成功！(127.0.0.1:40000)"
    else
        yellow_msg "安装完成，但未检测到 40000 端口。请手动检查 warp 服务状态。"
    fi
    echo ""; echo -ne "  按回车继续..."; read -r
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
    echo ""; echo -ne "  按回车继续..."; read -r
}

# === 手动添加自定义域名 ===
warp_add_custom() {
    echo ""
    echo -e "  ${yellow}请输入要分流的域名，多个用逗号或空格分隔:${re}"
    echo -e "  ${cyan}示例: twitter.com, instagram.com, openai.com${re}"
    echo ""
    echo -ne "  > "; read input 
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
    echo ""; echo -ne "  按回车继续..."; read -r
}

# === 删除指定域名 ===
warp_remove_domain() {
    [ ! -f "$WARP_DOMAIN_FILE" ] || [ ! -s "$WARP_DOMAIN_FILE" ] && { yellow_msg "分流域名列表为空。"; echo ""; echo -ne "  按回车返回..."; read -r; return; }

    echo ""
    echo -e "  ${white}当前分流域名:${re}"
    nl -w2 -s'. ' "$WARP_DOMAIN_FILE"
    echo ""
    echo -e "  ${yellow}输入要删除的序号 (多个用逗号分隔)，或输入域名本身:${re}"
    echo -ne "  > "; read input 
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
    echo ""; echo -ne "  按回车继续..."; read -r
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
        echo -ne "  请选择: "; read vc 
        case "$vc" in
            c|C) echo ""; echo -ne "  ${red}确认清空? (y/n): ${re}"; read cf
                 [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { > "$WARP_DOMAIN_FILE"; green_msg "已清空。"; } ;;
            0) return ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac
        echo -ne "  按回车返回..."; read -r
    done
}

# === 核心：使用 Python3 安全改写 config.json，应用 WARP 分流 ===
warp_apply_routing() {
    [ ! -f "$WARP_DOMAIN_FILE" ] || [ ! -s "$WARP_DOMAIN_FILE" ] && { yellow_msg "分流域名列表为空，请先添加域名。"; echo ""; echo -ne "  按回车返回..."; read -r; return; }
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
        echo ""; echo -ne "  按回车返回..."; read -r; return
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
    echo ""; echo -ne "  按回车返回..."; read -r
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
    echo -ne "  请选择: "; read mc ; [ "$mc" = "0" ] && return

    # 检查 Python3
    if ! command -v python3 &>/dev/null; then
        red_msg "未检测到 Python3，请先安装: apt install python3"
        echo ""; echo -ne "  按回车返回..."; read -r; return
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
                    run_warp_menu w || return 1
                else green_msg "WARP SOCKS5 已就绪"; fi
            fi
            if [ "$mc" = "2" ] || [ "$mc" = "3" ]; then
                if ! ip -6 addr show 2>/dev/null | grep -q 'wgcf\|Warp'; then
                    yellow_msg "安装 WARP IPv6 模式..."
                    run_warp_menu 6 || return 1
                else green_msg "WARP IPv6 已就绪"; fi
            fi
            ;;&
        1) warp_py_apply "socks5" ;;
        2) warp_py_apply "ipv6" ;;
        3) warp_py_apply "smart" ;;
        *) red_msg "无效"; return ;;
    esac

    echo ""; echo -ne "  按回车返回..."; read -r
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
    
    local update_dir utmp rc=1
    update_dir=$(mktemp -d -t argov-xray-update.XXXXXX) || return 1
    utmp="${update_dir}/xray.zip"
    if download_xray_zip_checked "$ARCH_ARG" "$utmp" && unzip -q "$utmp" -d "$update_dir"; then
        chmod +x "${update_dir}/xray"
        if activate_core_binary xray "${update_dir}/xray" "${WORK_DIR}/xray" "$CONFIG_FILE"; then
            green_msg "Xray 内核更新完成；原配置、证书和数据文件已保留。"
            rc=0
        fi
    else
        red_msg "下载或解压 Xray 内核失败，原内核未修改。"
    fi
    rm -rf "$update_dir"
    return "$rc"
}

#==============================================================================
# 主菜单
#==============================================================================
add_argo_protocol() {
    load_conf; clear
    echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}    ${white}启用 Argo 隧道 (VLESS/VMess over CF)${re}       ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    # 1. 下载 cloudflared
    yellow_msg "下载 cloudflared..."
    local cf_arch; cf_arch=$(cf_arch)
    download_cloudflared_checked "$cf_arch" "${WORK_DIR}/argo" || { red_msg "下载失败"; return; }
    chmod +x "${WORK_DIR}/argo"
    green_msg "cloudflared 就绪"

    # 2. 选择隧道模式
    echo ""
    echo -e "  ${yellow}隧道模式:${re}"
    echo -e "  ${green}1${re}. 临时 (trycloudflare.com)    ${green}2${re}. 固定 Token"
    echo -ne "  → [1]: "; read tt
    case "${tt:-1}" in
        2) echo -ne "  域名: "; read ARGO_FIXED_DOMAIN; echo -ne "  Token: "; read ARGO_AUTH
           [ -n "$ARGO_FIXED_DOMAIN" ] && [ -n "$ARGO_AUTH" ] && ARGO_MODE="fixed-token" || ARGO_MODE="temp" ;;
        *) ARGO_MODE="temp"; ARGO_AUTH="" ;;
    esac
    SKIP_ARGO=0

    # 3. 确保默认端口
    is_port "$ARGO_PORT" || ARGO_PORT=8080
    is_port "$VLESS_WS_PORT" || VLESS_WS_PORT=8081
    is_port "$VMESS_WS_PORT" || VMESS_WS_PORT=8082

    # 4. 构建 Argo inbound (插入现有 Xray config)
    local uuid; uuid=$(get_uuid)
    [ -z "$uuid" ] && uuid="${UUID_CUSTOM:-$(rand_uuid)}" && UUID_CUSTOM="$uuid"
    local argo_inbound json_saved
    # 检查是否已有 Argo inbound
    if jq -e '.inbounds[]|select(.tag=="argo-in")' "$CONFIG_FILE" >/dev/null 2>&1; then
        yellow_msg "Argo 隧道已存在, 跳过 inbound 构建"
        json_saved="[]"
    else
        # 保存现有可选协议
        json_saved=$(jq -c '[.inbounds[] | select(.tag=="reality" or .tag=="hy2" or .tag=="ss")]' "$CONFIG_FILE" 2>/dev/null)
        [ -z "$json_saved" ] && json_saved="[]"

        # 用 jq 临时移除可选协议, 调用 build_xray_config 只生成 Argo 部分
        local tmp_cfg; tmp_cfg=$(mktemp)
        jq 'del(.inbounds[] | select(.tag=="reality" or .tag=="hy2" or .tag=="ss"))' "$CONFIG_FILE" > "$tmp_cfg" 2>/dev/null || cp "$CONFIG_FILE" "$tmp_cfg"
        # 强制重置, 让 build_xray_config 生成完整 Argo 部分
        ENABLE_REALITY=0; ENABLE_HY2=0; ENABLE_SS=0
        REALITY_PORT=0; HY2_PORT=0; SS_PORT=0
        cp "$tmp_cfg" "$CONFIG_FILE"
        build_xray_config "$uuid" ""
        rm -f "$tmp_cfg"
    fi

    # 5. 合并回已保存的协议
    if [ "$json_saved" != "[]" ]; then
        jq --argjson saved "$json_saved" '.inbounds += $saved' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    normalize_xray_reality_config 2>/dev/null || true

    # 6. 重建隧道 + 启动
    rebuild_tunnel "$ARGO_MODE"
    save_conf
    systemctl daemon-reload
    systemctl enable xray argov-tunnel 2>/dev/null
    systemctl restart xray argov-tunnel
    sleep 3

    green_msg "Argo 隧道已启用！"
    echo -ne "  按回车..."; read -r
}

add_hy2_protocol() {
    (
        load_conf
        if jq -e '.inbounds[]|select(.tag=="hy2")' "$CONFIG_FILE" >/dev/null 2>&1; then
            edit_hy2_protocol; return $?
        fi
        local uuid ip new_inbound candidate
        cyan_msg "添加 Xray Hysteria2"
        prompt_xray_hy2 || return 1
        confirm_changes "添加以上 HY2 节点？" || return 1
        begin_protocol_edit xray || return 1
        gen_hy2_cert || return 1
        uuid=$(get_uuid)
        new_inbound=$(build_hy2_inbound "$HY2_PORT" "$HY2_SNI" "$uuid" argov-default "$HY2_MPORT" "$HY2_CONGESTION" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS")
        candidate=$(mktemp "${CONFIG_FILE}.edit.XXXXXX") || return 1
        jq --argjson i "$new_inbound" '.inbounds += [$i]' "$CONFIG_FILE" > "$candidate" || { rm -f "$candidate"; return 1; }
        commit_xray_candidate "$candidate" || return 1
        ENABLE_HY2=1
        sync_xray_users || return 1
        save_conf || return 1
        restart_protocol_runtime xray || { red_msg "Xray 重启失败。"; return 1; }
        if ! apply_hy2_hop_rules "$HY2_PORT" "$HY2_MPORT"; then
            clear_hy2_mport_config; save_conf
            yellow_msg "跳跃规则安装失败，已关闭跳跃；监听端口保持可用。"
        fi
        EDIT_COMMITTED=1
        start_sub_server >/dev/null 2>&1 &
        green_msg "Hysteria2 已添加，请刷新客户端订阅。"
        ip=$(get_ip); [ -n "$ip" ] && gen_hy2_link "$uuid" "$ip" "$HY2_PORT" "$HY2_SNI" "${NODE_NAME}-Hy2" "$HY2_MPORT"
        echo
    )
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
    echo -ne "  Select: "; read choice

    case "$choice" in
        1) [ "$has_reality" = 1 ] || return; tag="reality"; label="Reality"; ENABLE_REALITY=0; REALITY_PORT=0 ;;
        2) [ "$has_hy2" = 1 ] || return; tag="hy2"; label="Hysteria2"; ENABLE_HY2=0; HY2_PORT=0; HY2_MPORT="" ;;
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
        hy2)
            local old_hy2_port old_hy2_mport
            old_hy2_port=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            old_hy2_mport=$(jq -r '.inbounds[]|select(.tag=="hy2")|(.streamSettings.finalmask.quicParams.udpHop.ports//.streamSettings.hysteriaSettings.quicParams.udpHop.ports[0]//empty)' "$CONFIG_FILE" 2>/dev/null)
            disable_hy2_hop_rules "$old_hy2_port" "$old_hy2_mport"
            jq --arg tag "$tag" 'del(.inbounds[] | select(.tag==$tag))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
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

        local vl_port vm_port has_argo=0
        vl_port=$(jq -r '.inbounds[]|select(.tag=="vless-ws")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        vm_port=$(jq -r '.inbounds[]|select(.tag=="vmess-ws")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        [ -n "$vl_port" ] || [ -n "$vm_port" ] && has_argo=1

        if [ "$has_argo" = 1 ]; then
            echo -e "  ${white}── Argo 隧道 ──${re}"
            echo ""
            echo -e "  ${green}e1${re}. VLESS + Argo    端口 ${cyan}${vl_port}${re}  路径 ${cyan}/vless-argo${re}"
            echo -e "  ${green}e2${re}. VMess + Argo    端口 ${cyan}${vm_port}${re}  路径 ${cyan}/vmess-argo${re}"
            echo ""
        fi

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
            local hp hs hm
            hp=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            hs=$(jq -r '.inbounds[]|select(.tag=="hy2")|.streamSettings.tlsSettings.serverName//"www.bing.com"' "$CONFIG_FILE" 2>/dev/null)
            hm=$(jq -r '.inbounds[]|select(.tag=="hy2")|(.streamSettings.finalmask.quicParams.udpHop.ports//.streamSettings.hysteriaSettings.quicParams.udpHop.ports[0]//empty)' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}e4${re}. Hysteria2       ${cyan}${hs}${re}  端口 ${cyan}${hp}${re}$( [ -n "$hm" ] && echo "  跳跃 ${cyan}${hm}${re}" )"
        fi
        if [ "$has_ss" = 1 ]; then
            local sp sm
            sp=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            sm=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
            echo -e "  ${green}e5${re}. Shadowsocks       ${cyan}${sm}${re}  端口 ${cyan}${sp}${re}"
        fi

        if [ "$has_argo" = 0 ] || [ "$has_reality" = 0 ] || [ "$has_hy2" = 0 ] || [ "$has_ss" = 0 ]; then
            echo ""; echo -e "  ${white}── 可添加 ──${re}"; echo ""
        fi
        [ "$has_argo" = 0 ] && echo -e "  ${cyan}a0${re}. VLESS/VMess Argo (Cloudflare 隧道)"
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
        echo -e "  ${purple}提示${re}: 内置 Hysteria2 会进入用户统计与限额；端口跳跃会用 UDP 转发到单监听端口。"

        [ "$has_reality" = 1 ] || [ "$has_hy2" = 1 ] || [ "$has_ss" = 1 ] && echo "" && echo -e "  ${red}d${re}. 删除可选节点"
        echo ""; echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  请输入: "; read ac; [ "$ac" = "0" ] && return

        case "$ac" in
            e1|e2) [ "$has_argo" = 1 ] && { [ "$ac" = "e1" ] && edit_protocol "vless-ws" "VLESS + Argo" || edit_protocol "vmess-ws" "VMess + Argo"; } ;;
            e3) [ "$has_reality" = 1 ] && edit_protocol "reality" "VLESS Reality" ;;
            e4) [ "$has_hy2" = 1 ] && edit_hy2_protocol ;;
            e5) [ "$has_ss" = 1 ] && edit_protocol "ss" "Shadowsocks" ;;
            a0) [ "$has_argo" = 0 ] && add_argo_protocol ;;
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

#==============================================================================
# 聚合订阅
#==============================================================================
agg_menu() {
    load_conf
    [ -z "$AGG_TOKEN" ] && AGG_TOKEN=$(rand_token) && save_conf
    [ ! -f "${WORK_DIR}/agg_gen.sh" ] && start_sub_server >/dev/null 2>&1 &

    while true; do
        clear
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}      ${white}聚合订阅 (Aggregated Sub)${re}           ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""

        local agg_url
        [ -n "$SUB_DOMAIN" ] && agg_url="https://${SUB_DOMAIN}:${SUB_PORT}/agg?token=${AGG_TOKEN}" || agg_url="http://$(get_ip 2>/dev/null):${SUB_PORT}/agg?token=${AGG_TOKEN}"
        echo -e " ${purple}── 📡 总订阅 (导入客户端) ──${re}"
        echo -e "  ${green}${agg_url}${re}"
        echo ""

        local count=0
        [ -f "${WORK_DIR}/agg_sources.txt" ] && count=$(grep -c '[^[:space:]]' "${WORK_DIR}/agg_sources.txt" 2>/dev/null || echo 0)
        [ -z "$count" ] && count=0
        echo -e " ${purple}── 📥 子订阅 (其他 VPS/机场) ──${re}"
        if [ "$count" -eq 0 ]; then
            echo -e "  ${yellow}(空, 通过 g1 添加)${re}"
        else
            nl -w2 -s'. ' "${WORK_DIR}/agg_sources.txt" 2>/dev/null
            echo ""
        fi
        echo -e "  ${yellow}共 ${cyan}${count}${re} 个子订阅 + 本机 = 聚合后客户端总节点"
        echo ""
        echo -e "  ${green}g1${re}. 添加子订阅 (粘贴其他 VPS 的 /sub?token=xxx)"
        [ "$count" -gt 0 ] && echo -e "  ${red}g2${re}. 删除子订阅"
        echo -e "  ${cyan}g3${re}. 查看总订阅链接"
        echo ""; echo -e "  ${red}0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  Select: "; read c
        case "$c" in
            g1|G1)
                echo ""; echo -e "  ${yellow}粘贴其他 VPS 的订阅 URL:${re}"
                echo -ne "  URL: "; read url 
                [ -z "$url" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                if ! echo "$url" | grep -qE '^https?://'; then
                    red_msg "无效 URL"; sleep 1; continue
                fi
                touch "${WORK_DIR}/agg_sources.txt"
                echo "$url" >> "${WORK_DIR}/agg_sources.txt"
                green_msg "已添加。"; bash "${WORK_DIR}/agg_gen.sh" 2>/dev/null &
                sleep 1
                ;;
            g2|G2)
                [ "$count" = 0 ] && { yellow_msg "无源可删。"; sleep 1; continue; }
                echo ""; echo -ne "  输入序号删除 (多选空格分隔): "; read nums 
                [ -z "$nums" ] && { yellow_msg "已取消。"; sleep 1; continue; }
                local idx=0 new=()
                while IFS= read -r line; do
                    [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue
                    idx=$((idx+1))
                    local keep=1
                    for n in $nums; do
                        [ "$n" = "$idx" ] && { keep=0; break; }
                    done
                    [ "$keep" = 1 ] && new+=("$line")
                done < "${WORK_DIR}/agg_sources.txt"
                printf '%s\n' "${new[@]}" > "${WORK_DIR}/agg_sources.txt"
                green_msg "已删除。"; bash "${WORK_DIR}/agg_gen.sh" 2>/dev/null &
                sleep 1
                ;;
            g3|G3)
                echo ""; echo -e "  ${green}${agg_url}${re}"; echo ""
                echo -ne "  按回车返回..."; read -r
                ;;
            0) return ;;
            *) red_msg "无效"; sleep 1 ;;
        esac
    done
}

#==============================================================================
# Sing-box 管理面板
#==============================================================================
sb_menu() {
    while true; do
        load_conf
        get_status
        clear
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}Sing-box 内核管理${re}                   ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""

        # 状态
        local sb_ver="—"
        if sb_is_installed; then
            sb_ver="$(singbox_version_string)"
            sb_ver="${sb_ver:-版本未知}"
        fi
        local sb_st_display="未安装"
        if sb_status; then
            if sb_is_installed; then
                sb_st_display="${green}● 运行中${re}"
            else
                sb_st_display="${yellow}● 进程仍运行，安装文件丢失${re}"
                sb_ver="版本未知"
                local running_ver; running_ver=$(singbox_version_string)
                [ -n "$running_ver" ] && sb_ver="$running_ver"
            fi
        elif sb_is_installed; then
            [ -f "$SB_CONFIG_FILE" ] && sb_st_display="${red}○ 已停止${re}" || sb_st_display="${cyan}○ 内核已安装，待增配节点${re}"
        fi
        echo -e "  Sing-box: ${sb_st_display}    版本: ${cyan}${sb_ver}${re}"

        # 启用的协议
        local proto_list=""
        [ "${SB_HY2_ENABLE:-false}" = "true" ] && proto_list="$proto_list HY2"
        [ "${SB_TUIC_ENABLE:-false}" = "true" ] && proto_list="$proto_list TUIC"
        [ "${SB_ANYTLS_ENABLE:-false}" = "true" ] && proto_list="$proto_list AnyTLS"
        [ "${SB_REALITY_ENABLE:-false}" = "true" ] && proto_list="$proto_list Reality"
        [ "${SB_SS_ENABLE:-false}" = "true" ] && proto_list="$proto_list SS"
        [ -n "$proto_list" ] && echo -e "  协议: ${green}${proto_list}${re}"
        echo ""

        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -e "  ${green}s1${re}. 安装/更新 Sing-box 内核"
        echo -e "  ${green}s2${re}. 管理 Sing-box 协议 (添加/编辑/删除)"
        echo -e "  ${green}s3${re}. 查看 Sing-box 节点链接"
        echo -e "  ${green}s4${re}. 启动 / 停止 / 重启 Sing-box"
        echo -e "  ${red}s5${re}. 卸载 Sing-box"
        echo -e "  ${cyan}s0${re}. 返回主菜单"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  请选择: "; read c

        case "$c" in
            s1|S1|1)
                local sb_action=install
                if sb_is_installed || sb_status; then sb_action=update; fi
                if install_singbox "$sb_action"; then
                    SB_ENABLE=true; save_conf; start_sub_server >/dev/null 2>&1 &
                    green_msg "Sing-box 安装/更新成功！"
                else
                    echo -ne "  按回车返回..."; read -r
                fi
                ;;
            s2|S2|2) manage_sb_protocols ;;
            s3|S3|3) show_node; echo -ne "  按回车返回..."; read -r ;;
            s4|S4|4)
                echo ""
                echo -e "  ${green}1${re}. 启动    ${red}2${re}. 停止    ${yellow}3${re}. 重启"
                echo -ne "  选择: "; read sc
                case "${sc:-1}" in
                    1) sb_start && green_msg "Sing-box 已启动" || red_msg "Sing-box 未启动，请检查上述提示。" ;;
                    2) sb_stop && green_msg "Sing-box 已停止" || red_msg "Sing-box 停止失败，请检查服务日志。" ;;
                    3) sb_restart && green_msg "Sing-box 已重启" || red_msg "Sing-box 未重启，请检查上述提示。" ;;
                esac
                sleep 1
                ;;
            s5|S5|5)
                echo -ne "  ${red}⚠ 确定卸载 Sing-box? (y/N): ${re}"; read cf
                if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                    stop_singbox_for_uninstall || { echo -ne "  按回车返回..."; read -r; continue; }
                    stop_sb_stats_service 2>/dev/null
                    disable_sb_hy2_hop_rules 2>/dev/null
                    systemctl disable sing-box 2>/dev/null; rc-update del sing-box default 2>/dev/null
                    rm -rf "$SB_WORK_DIR" /etc/systemd/system/sing-box.service /etc/init.d/sing-box /var/log/sing-box.log /var/log/sing-box.err /usr/bin/sing-box /usr/local/bin/sing-box 2>/dev/null
                    systemctl daemon-reload 2>/dev/null || true
                    SB_ENABLE=false
                    SB_HY2_ENABLE=false; SB_TUIC_ENABLE=false; SB_ANYTLS_ENABLE=false; SB_REALITY_ENABLE=false; SB_SS_ENABLE=false
                    save_conf; start_sub_server >/dev/null 2>&1 &
                    red_msg "Sing-box 已卸载"
                fi
                ;;
            s0|S0|0) return ;;
            *) red_msg "无效选择"; sleep 1 ;;
        esac
    done
}

manage_sb_protocols() {
    if ! sb_is_installed; then
        red_msg "请先安装 Sing-box 内核！"
        echo -ne "  按回车返回..."; read -r
        return
    fi

    while true; do
        load_conf
        clear
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}Sing-box 协议管理${re}                     ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""

        # 列出已启用协议
        echo -e "  ${white}── 已启用 ──${re}"
        local has_any=false
        if [ "${SB_HY2_ENABLE:-false}" = "true" ] && [ -n "${SB_HY2_PORT:-}" ]; then
            has_any=true
            echo -e "  ${yellow}HY2${re}    port: ${green}${SB_HY2_PORT}${re}  SNI: ${cyan}${SB_HY2_SNI:-$SB_SNI}${re}"
        fi
        if [ "${SB_TUIC_ENABLE:-false}" = "true" ] && [ -n "${SB_TUIC_PORT:-}" ]; then
            has_any=true
            echo -e "  ${yellow}TUIC${re}   port: ${green}${SB_TUIC_PORT}${re}  SNI: ${cyan}${SB_TUIC_SNI:-$SB_SNI}${re}"
        fi
        if [ "${SB_ANYTLS_ENABLE:-false}" = "true" ] && [ -n "${SB_ANYTLS_PORT:-}" ]; then
            has_any=true
            echo -e "  ${yellow}AnyTLS${re} port: ${green}${SB_ANYTLS_PORT}${re}  SNI: ${cyan}${SB_ANYTLS_SNI:-$SB_SNI}${re}"
        fi
        if [ "${SB_REALITY_ENABLE:-false}" = "true" ] && [ -n "${SB_REALITY_PORT:-}" ]; then
            has_any=true
            echo -e "  ${yellow}Reality${re} port: ${green}${SB_REALITY_PORT}${re}  SNI: ${cyan}${SB_REALITY_SNI:-$SB_SNI}${re}"
        fi
        if [ "${SB_SS_ENABLE:-false}" = "true" ] && [ -n "${SB_SS_PORT:-}" ]; then
            has_any=true
            echo -e "  ${yellow}SS${re}      port: ${green}${SB_SS_PORT}${re}  method: ${cyan}${SB_SS_METHOD:-$SS_METHOD}${re}"
        fi
        $has_any || echo -e "  ${cyan}(无)${re}"

        echo ""
        echo -e "  ${white}── 可选协议 ──${re}"
        [ "${SB_HY2_ENABLE:-false}" != "true" ]    && echo -e "  ${green}b1${re}. 添加 Hysteria2"
        [ "${SB_TUIC_ENABLE:-false}" != "true" ]   && echo -e "  ${green}b2${re}. 添加 TUIC"
        [ "${SB_ANYTLS_ENABLE:-false}" != "true" ] && echo -e "  ${green}b3${re}. 添加 AnyTLS Reality"
        [ "${SB_REALITY_ENABLE:-false}" != "true" ] && echo -e "  ${green}b4${re}. 添加 VLESS Reality"
        [ "${SB_SS_ENABLE:-false}" != "true" ]     && echo -e "  ${green}b5${re}. 添加 Shadowsocks"

        [ "${SB_HY2_ENABLE:-false}" = true ] && echo "  e1. 编辑 Hysteria2"
        [ "${SB_TUIC_ENABLE:-false}" = true ] && echo "  e2. 编辑 TUIC"
        [ "${SB_ANYTLS_ENABLE:-false}" = true ] && echo "  e3. 编辑 AnyTLS Reality"
        [ "${SB_REALITY_ENABLE:-false}" = true ] && echo "  e4. 编辑 VLESS Reality"
        [ "${SB_SS_ENABLE:-false}" = true ] && echo "  e5. 编辑 Shadowsocks"
        echo -e "  ${red}d${re}. 删除协议    ${cyan}b0${re}. 返回"
        echo -e " ${purple}────────────────────────────────────────${re}"
        echo -ne "  请选择: "; read c

        case "$c" in
            b1|B1|e1|E1) add_sb_hy2 ;;
            b2|B2|e2|E2) add_sb_tuic ;;
            b3|B3|e3|E3) add_sb_anytls ;;
            b4|B4|e4|E4) add_sb_reality ;;
            b5|B5|e5|E5) add_sb_ss ;;
            d|D) delete_sb_protocol ;;
            b0|B0|0) return ;;
            *) red_msg "无效选择"; sleep 1 ;;
        esac
    done
}

# Sing-box 协议添加函数
add_sb_hy2() { add_sb_protocol HY2; }

add_sb_anytls() { add_sb_protocol ANYTLS; }

add_sb_tuic() { add_sb_protocol TUIC; }

add_sb_reality() { add_sb_protocol REALITY; }

add_sb_ss() { add_sb_protocol SS; }

delete_sb_protocol() {
    load_conf
    echo ""
    echo -e "  ${white}选择要删除的 Sing-box 协议:${re}"
    # 构建动态映射：显示编号 → 协议 key
    local -a proto_list=()
    [ "${SB_HY2_ENABLE:-false}"   = "true" ] && proto_list+=("HY2")
    [ "${SB_TUIC_ENABLE:-false}"  = "true" ] && proto_list+=("TUIC")
    [ "${SB_ANYTLS_ENABLE:-false}" = "true" ] && proto_list+=("ANYTLS")
    [ "${SB_REALITY_ENABLE:-false}" = "true" ] && proto_list+=("REALITY")
    [ "${SB_SS_ENABLE:-false}"    = "true" ] && proto_list+=("SS")
    if [ ${#proto_list[@]} -eq 0 ]; then
        yellow_msg "无协议可删除"; sleep 1; return
    fi
    local i=1
    for p in "${proto_list[@]}"; do
        echo -e "  ${green}${i}${re}. ${p}"
        i=$((i+1))
    done
    echo -ne "  输入序号(空格分隔): "; read nums
    for n in $nums; do
        [ "$n" -lt 1 ] || [ "$n" -gt "${#proto_list[@]}" ] && { echo "  → 序号 $n 无效，跳过"; continue; }
        local key="${proto_list[$((n-1))]}"
        case "$key" in
            HY2)    disable_sb_hy2_hop_rules 2>/dev/null; SB_HY2_ENABLE=false; SB_HY2_PORT=; SB_HY2_PSK=; SB_HY2_HOP_ENABLE=false; echo "  → HY2 已删除" ;;
            TUIC)   SB_TUIC_ENABLE=false; SB_TUIC_PORT=; echo "  → TUIC 已删除" ;;
            ANYTLS) SB_ANYTLS_ENABLE=false; SB_ANYTLS_PORT=; echo "  → AnyTLS 已删除" ;;
            REALITY) SB_REALITY_ENABLE=false; SB_REALITY_PORT=; echo "  → Reality 已删除" ;;
            SS)     SB_SS_ENABLE=false; SB_SS_PORT=; SB_SS_PSK=; echo "  → SS 已删除" ;;
        esac
    done
    # 如果没有任何协议了，禁用 Sing-box
    if [ "${SB_HY2_ENABLE:-false}" != "true" ] && [ "${SB_TUIC_ENABLE:-false}" != "true" ] && \
       [ "${SB_ANYTLS_ENABLE:-false}" != "true" ] && [ "${SB_REALITY_ENABLE:-false}" != "true" ] && \
       [ "${SB_SS_ENABLE:-false}" != "true" ]; then
        SB_ENABLE=false
        sb_stop 2>/dev/null
        yellow_msg "所有协议已删除，Sing-box 已停止"
    else
        build_singbox_config; sb_restart
    fi
    save_conf; start_sub_server >/dev/null 2>&1 &
    sleep 1
}

# MODULE: menus and entrypoint
main_menu() {
    load_conf
    secure_work_dir_permissions
    # 确保流量计数器已挂载（升级/重启后首次进入 ag 时补装）
    setup_traffic_counters 2>/dev/null || true
    collect_traffic 2>/dev/null || true
    # 从实际入站证书回填，保留域名、端口、凭据和证书本身。
    if refresh_certificate_pins; then save_conf; fi
    # 无感升级：旧版 stats.py 无配额阻断逻辑 → 静默重新生成
    if [ -f "${WORK_DIR}/stats.py" ] && ! grep -qF 'disabled and sync_config' "${WORK_DIR}/stats.py" 2>/dev/null; then
        start_stats_service >/dev/null 2>&1 &
    fi
    while true; do
        get_status
        collect_traffic 2>/dev/null
        clear
        local uuid_short="未安装" hd=""
        [ -f "$CONFIG_FILE" ] && uuid_short="$(get_uuid | cut -c1-12)..."
        [ "$TUNNEL_RAW" = "running" ] && hd=$(get_argo_domain)
        [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"

        logo
        echo -e "  ${yellow}▶${re} 命令行输入 ${green}ag${re} 可随时启动本面板"
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}ArgoV  双核代理${re}              ${purple}║${re}"
        echo -e " ${purple}║${re}     ${cyan}$(get_proto_summary)${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  名称 : ${white}${NODE_NAME}${re}    Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"
        echo -e "  UUID : ${cyan}${uuid_short}${re}"
        [ -n "$hd" ] && echo -e "  域名 : ${green}${hd}${re}"
        echo -e "  CDN  : ${green}$(get_cdn):$(get_cdn_port)${re}"
        [ -n "$SB_ST" ] && echo -e "  Sing-box: ${SB_ST}"
        # 流量统计
        if [ -f "${WORK_DIR}/.traffic_counters" ]; then
            . "${WORK_DIR}/.traffic_counters" 2>/dev/null || true
            local tin_f tout_f
            tin_f=$(numfmt --to=iec "${TRAFFIC_IN:-0}" 2>/dev/null || echo "${TRAFFIC_IN:-0} B")
            tout_f=$(numfmt --to=iec "${TRAFFIC_OUT:-0}" 2>/dev/null || echo "${TRAFFIC_OUT:-0} B")
            echo -e "  流量 : ${green}↓ ${tin_f}${re}  ${cyan}↑ ${tout_f}${re}"
        fi
        echo ""
        echo -e " ${purple}──────────────── ✦ 核心功能 ✦ ────────────────${re}"
        echo -e "  ${green}1${re}. 🔗 查看节点链接       ${green}2${re}. ☁️  更换优选线路"
        echo -e "  ${green}3${re}. ⚙️  修改基础配置       ${cyan}a${re}. 🧩 管理代理节点 (添加/编辑/删除)"
        echo -e "  ${cyan}u${re}. 👥 用户/流量限额       ${yellow}配额用户仅下发本机节点"
        echo ""
        echo -e " ${purple}──────────────── ✦ 进阶路由 ✦ ────────────────${re}"
        echo -e "  ${purple}w${re}. 🌐 独立 WARP 分流     ${purple}r${re}. 🔀 落地节点中继"
        echo -e "  ${purple}g${re}. 📡 聚合订阅            ${purple}s${re}. 🔧 Sing-box 管理"
        echo ""
        echo -e " ${purple}──────────────── ✦ 状态运维 ✦ ────────────────${re}"
        echo -e "  ${green}4${re}. ▶️  启动系统         ${red}5${re}. ⏹️  停止系统"
        echo -e "  ${yellow}6${re}. 🔁 重启 Argo 隧道    ${yellow}7${re}. 🔄 重新安装 (保留数据)"
        echo -e "  ${cyan}8${re}. 🆙 更新管理脚本      ${red}9${re}. 🗑️  彻底卸载系统"
        echo -e "  ${purple}x${re}. 🚀 更新 Xray 内核    ${cyan}0${re}. 🚪 安全退出"
        echo -e " ${purple}───────────────────────────────────────────────${re}"
        echo -ne "  请输入 (0-9 / a / u / x / w / r / g / s): "; read c
        case "$c" in
            1) show_node; echo -ne "  按回车返回..."; read -r ;;
            2) edit_cdn; echo -ne "  按回车返回..."; read -r ;;
            3) change_config ;;
            a|A) manage_protocols ;;
            u|U) manage_users ;;
            4) start_services; sleep 1 ;; 5) stop_services; sleep 1 ;; 6) restart_services; sleep 1 ;;
            7) echo -ne "  ${yellow}重新安装? (y/n): ${re}"; read cf
               [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { load_conf; do_install; }; echo -ne "  按回车返回..."; read -r ;;
            8) yellow_msg "拉取最新版..."
               local utmp; utmp=$(mktemp /tmp/argov.XXXXXX)
               download_script_checked "https://raw.githubusercontent.com/m2dumpling/ArgoV/main/argov.sh?r=$RANDOM$RANDOM" "$utmp" && bash "$utmp"; rm -f "$utmp"
               start_sub_server >/dev/null 2>&1 &
               start_sb_stats_service >/dev/null 2>&1 &
               clear; continue ;;
            x|X) update_xray_core ;;
            9) echo -ne "  ${red}⚠ 确定卸载? (y/n): ${re}"; read cf
               if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                   stop_sub_server 2>/dev/null
                   stop_stats_service 2>/dev/null
                   systemctl stop xray argov-tunnel argov-stats argov-sb-stats 2>/dev/null; systemctl disable xray argov-tunnel argov-stats argov-sb-stats 2>/dev/null
                   # Sing-box 清理
                   [ "${SB_ENABLE:-false}" = "true" ] && { sb_stop; systemctl disable sing-box 2>/dev/null; rc-update del sing-box default 2>/dev/null; }
                    rm -rf "$WORK_DIR" "$SB_WORK_DIR"; rm -f /usr/bin/sing-box /usr/local/bin/sing-box /etc/systemd/system/xray.service /etc/systemd/system/argov-tunnel.service /etc/systemd/system/argov-sub.service /etc/systemd/system/argov-stats.service /etc/systemd/system/argov-sb-stats.service /etc/systemd/system/sing-box.service /etc/init.d/xray /etc/init.d/argov-tunnel /etc/init.d/argov-stats /etc/init.d/argov-sb-stats /etc/init.d/sing-box "$SCRIPT_PATH" "${WORK_DIR}/argov-tunnel.sh"
                   systemctl daemon-reload; green_msg "卸载完成。"; fi ;;
            w|W) warp_menu ;;
            r|R) relay_menu ;;
            g|G) agg_menu ;;
            s|S) sb_menu ;;
            0) clear; break ;;
            *) red_msg "无效 (0-9 / a / u / x / w / r / g / s)"; sleep 1 ;;
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
        
        install_ag_wrapper forward_args
        green_msg "迁移完成！输入 ag 即可使用全新面板。"
        sleep 2
    fi
}

migrate_argox_to_argov
load_conf
[ ! -f "$CONFIG_FILE" ] && interactive_install
main_menu
