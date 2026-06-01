#!/usr/bin/env bash
#==============================================================================
# ArgoX-Mini — Cloudflare Argo Tunnel 多协议交互式管理脚本
# VLESS + VMess + Shadowsocks  |  WS+TLS via Argo  |  VLESS Reality 直连
# 零公网暴露(Argo模式) · 无 Caddy/Nginx · 可选直连协议
#==============================================================================

# --- 颜色 ---
re="\033[0m"; red="\e[1;31m"; green="\e[1;32m"; yellow="\e[1;33m"
purple="\e[1;35m"; cyan="\e[1;36m"; white="\e[1;37m"
red_msg()    { echo -e "${red}$1${re}"; }
green_msg()  { echo -e "${green}$1${re}"; }
yellow_msg() { echo -e "${yellow}$1${re}"; }
purple_msg() { echo -e "${purple}$1${re}"; }
cyan_msg()   { echo -e "${cyan}$1${re}"; }

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
SS_WS_PORT="${SS_WS_PORT:-8083}"
CDN_PORT="${CDN_PORT:-443}"
REALITY_PORT="${REALITY_PORT:-0}"   # 0=自动分配
SS_DIRECT_PORT="${SS_DIRECT_PORT:-0}"

# --- 节点名称 ---
NODE_NAME="${NODE_NAME:-ArgoX-Mini}"

# --- 可选协议开关（安装向导中交互选择）---
ENABLE_VLESS_ARGO=1   # 始终启用
ENABLE_VMESS_ARGO=1   # 始终启用
ENABLE_SS_ARGO=0
ENABLE_REALITY=0
ENABLE_SS_DIRECT=0

# --- SS 加密方式 ---
SS_METHODS=(
    "aes-128-gcm"
    "aes-256-gcm"
    "chacha20-ietf-poly1305"
    "xchacha20-ietf-poly1305"
    "2022-blake3-aes-128-gcm"
    "2022-blake3-aes-256-gcm"
    "2022-blake3-chacha20-poly1305"
)
SS_METHOD="${SS_METHOD:-aes-256-gcm}"

# --- Reality 伪装域名 ---
REALITY_SNIS=(
    "www.amazon.com"
    "www.ebay.com"
    "www.paypal.com"
    "www.cloudflare.com"
    "dash.cloudflare.com"
    "aws.amazon.com"
    "addons.mozilla.org"
    "www.microsoft.com"
)
REALITY_SNI="${REALITY_SNI:-www.amazon.com}"

# --- 优选域名池 ---
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
# 工具函数
#==============================================================================
port_in_use() { lsof -iTCP:"$1" -sTCP:LISTEN &>/dev/null; }
find_free_port() { local p="$1"; while port_in_use "$p"; do p=$((p+1)); done; echo "$p"; }

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

get_argo_domain() {
    local d; [ -f "$TUNNEL_LOG" ] && for i in {1..5}; do
        d=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' "$TUNNEL_LOG" | tail -n 1)
        [ -n "$d" ] && break; sleep 2
    done; echo "$d"
}

get_uuid() { jq -r '.inbounds[0].settings.clients[0].id // empty' "$CONFIG_FILE" 2>/dev/null; }
get_cdn() { [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_DOMAIN"; }
get_cdn_port() { [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn_port // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_PORT"; }

# --- 获取本机 IP ---
get_ip() {
    local ip; ip=$(curl -s --max-time 2 ipv4.ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 2 ifconfig.me 2>/dev/null)
    echo "$ip"
}

# --- Reality 密钥生成 ---
gen_reality_keys() {
    local out; out=$("${WORK_DIR}/xray" x25519 2>/dev/null)
    REALITY_PRIV=$(echo "$out" | grep "Private" | awk '{print $3}')
    REALITY_PUB=$(echo "$out" | grep "Public"  | awk '{print $3}')
    [ -z "$REALITY_PRIV" ] && { REALITY_PRIV="REPLACE_ME"; REALITY_PUB="REPLACE_ME"; }
}

# --- SS2022 密码生成 ---
gen_ss2022_pass() {
    local method="$1"
    if [[ "$method" =~ 128 ]]; then openssl rand -base64 16
    else openssl rand -base64 32; fi
}

# --- 持久化配置 ---
load_conf() {
    [ -f "$USER_CONF" ] && . "$USER_CONF"
    NODE_NAME="${NODE_NAME:-ArgoX-Mini}"
    ARGO_PORT="${ARGO_PORT:-8080}"; VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
    VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"; SS_WS_PORT="${SS_WS_PORT:-8083}"
    CDN_PORT="${CDN_PORT:-443}"; CDN_DOMAIN="${CDN_DOMAIN:-$CDN_DEFAULT}"
    ARGO_MODE="${ARGO_MODE:-temp}"; ARGO_AUTH="${ARGO_AUTH:-}"
    ARGO_FIXED_DOMAIN="${ARGO_FIXED_DOMAIN:-}"; UUID_CUSTOM="${UUID_CUSTOM:-}"
    REALITY_PORT="${REALITY_PORT:-0}"; SS_DIRECT_PORT="${SS_DIRECT_PORT:-0}"
    REALITY_SNI="${REALITY_SNI:-www.amazon.com}"; SS_METHOD="${SS_METHOD:-aes-256-gcm}"
    ENABLE_SS_ARGO="${ENABLE_SS_ARGO:-0}"; ENABLE_REALITY="${ENABLE_REALITY:-0}"
    ENABLE_SS_DIRECT="${ENABLE_SS_DIRECT:-0}"
    REALITY_PRIV="${REALITY_PRIV:-}"; REALITY_PUB="${REALITY_PUB:-}"
}
save_conf() {
    cat > "$USER_CONF" << EOF
# ArgoX-Mini 配置 — $(date '+%Y-%m-%d %H:%M:%S')
NODE_NAME='${NODE_NAME}'
ARGO_PORT='${ARGO_PORT}'; VLESS_WS_PORT='${VLESS_WS_PORT}'
VMESS_WS_PORT='${VMESS_WS_PORT}'; SS_WS_PORT='${SS_WS_PORT}'
CDN_PORT='${CDN_PORT}'; CDN_DOMAIN='${CDN_DOMAIN}'
ARGO_MODE='${ARGO_MODE}'; ARGO_AUTH='${ARGO_AUTH}'
ARGO_FIXED_DOMAIN='${ARGO_FIXED_DOMAIN}'; UUID_CUSTOM='${UUID_CUSTOM}'
REALITY_PORT='${REALITY_PORT}'; SS_DIRECT_PORT='${SS_DIRECT_PORT}'
REALITY_SNI='${REALITY_SNI}'; SS_METHOD='${SS_METHOD}'
ENABLE_SS_ARGO='${ENABLE_SS_ARGO}'; ENABLE_REALITY='${ENABLE_REALITY}'
ENABLE_SS_DIRECT='${ENABLE_SS_DIRECT}'
REALITY_PRIV='${REALITY_PRIV}'; REALITY_PUB='${REALITY_PUB}'
EOF
}

#==============================================================================
# 链接生成
#==============================================================================
gen_vmess_link() {
    local uuid="$1" host="$2" addr="${3:-$(get_cdn)}" port="${4:-$(get_cdn_port)}" remark="${5:-${NODE_NAME}-VMess}"
    local json; json="{\"v\":\"2\",\"ps\":\"${remark}\",\"add\":\"${addr}\",\"port\":\"${port}\",\"id\":\"${uuid}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"/vmess-argo\",\"tls\":\"tls\",\"sni\":\"${host}\",\"alpn\":\"\",\"fp\":\"\"}"
    printf '%s' "vmess://$(printf '%s' "$json" | base64 -w0 2>/dev/null || printf '%s' "$json" | base64 | tr -d '\n')"
}
gen_vless_link() {
    local uuid="$1" host="$2" addr="${3:-$(get_cdn)}" port="${4:-$(get_cdn_port)}" remark="${5:-${NODE_NAME}-VLESS}"
    printf '%s' "vless://${uuid}@${addr}:${port}?encryption=none&security=tls&sni=${host}&type=ws&host=${host}&path=%2Fvless-argo%3Fed%3D2560#${remark// /%20}"
}
gen_ss_link() {
    local method="$1" pass="$2" host="$3" port="${4:-$(get_cdn_port)}" remark="${5:-${NODE_NAME}-SS}"
    local b64; b64=$(printf '%s' "${method}:${pass}" | base64 -w0 2>/dev/null || printf '%s' "${method}:${pass}" | base64 | tr -d '\n')
    printf '%s' "ss://${b64}@${host}:${port}#${remark// /%20}"
}
gen_reality_link() {
    local uuid="$1" addr="$2" port="$3" sni="$4" pub="$5" remark="${6:-${NODE_NAME}-Reality}"
    printf '%s' "vless://${uuid}@${addr}:${port}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${sni}&pbk=${pub}&fp=chrome#${remark// /%20}"
}

# --- QR ---
show_qr() {
    local qr="${WORK_DIR}/qrencode"
    [ ! -f "$qr" ] && { yellow_msg "QR 工具未安装，仅显示链接"; return 1; }
    chmod +x "$qr" 2>/dev/null
    echo ""; "$qr" -t ANSIUTF8 -m 1 -s 2 "$1" 2>/dev/null || yellow_msg "QR 生成失败"
}
install_qrencode() {
    local qr="${WORK_DIR}/qrencode"; [ -f "$qr" ] && return 0
    local a; case "$(uname -m)" in x86_64) a="amd64" ;; aarch64|arm64) a="arm64" ;; *) return 1 ;; esac
    curl -sLo "$qr" "https://github.com/eooce/test/releases/download/${a}/qrencode-linux-${a}" 2>/dev/null
    chmod +x "$qr" 2>/dev/null
}

#==============================================================================
# 服务状态
#==============================================================================
get_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"
    else XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"; fi
    if systemctl is-active --quiet tunnel 2>/dev/null; then
        TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"
    else TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"; fi
}

#==============================================================================
# 获取协议信息摘要（用于菜单显示）
#==============================================================================
get_proto_summary() {
    local s="VL-Argo VM-Argo"
    [ "$ENABLE_SS_ARGO" = 1 ] && s="$s SS-Argo"
    [ "$ENABLE_REALITY" = 1 ] && s="$s Reality"
    [ "$ENABLE_SS_DIRECT" = 1 ] && s="$s SS-Dir"
    echo "$s"
}

#==============================================================================
# 查看节点
#==============================================================================
show_node() {
    clear; load_conf
    [ ! -f "$CONFIG_FILE" ] && { red_msg "未检测到安装！"; return; }
    local uuid cdn_addr cdn_port host_domain ip_addr
    uuid=$(get_uuid); cdn_addr=$(get_cdn); cdn_port=$(get_cdn_port)
    host_domain=$(get_argo_domain); ip_addr=$(get_ip)
    [ -z "$host_domain" ] && [ "$ARGO_MODE" != "fixed-token" ] && { yellow_msg "  ⚠ 正在获取 Argo 域名..."; sleep 3; host_domain=$(get_argo_domain); }
    [ "$ARGO_MODE" = "fixed-token" ] && host_domain="$ARGO_FIXED_DOMAIN"

    echo ""
    echo -e "${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e "${purple}║${re}       ${white}ArgoX-Mini · ${NODE_NAME}${re}"
    echo -e "${purple}║${re}       ${cyan}节点连接参数${re}"
    echo -e "${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  名称: ${white}${NODE_NAME}${re}    UUID: ${purple}$(echo "$uuid" | cut -c1-16)...${re}"
    [ -n "$ip_addr" ] && echo -e "  VPS IP: ${cyan}${ip_addr}${re}"
    echo ""

    # === Argo 协议 ===
    if [ -n "$host_domain" ]; then
        echo -e "  ${white}━━━ Argo 隧道协议 (无需开放端口) ━━━${re}"
        echo ""
        echo -e "  ${yellow}① VLESS + WS + Argo${re}"
        echo -e "  ${green}$(gen_vless_link "$uuid" "$host_domain" "$cdn_addr" "$cdn_port")${re}"
        echo ""
        echo -e "  ${yellow}② VMess + WS + Argo${re}"
        echo -e "  ${green}$(gen_vmess_link "$uuid" "$host_domain" "$cdn_addr" "$cdn_port")${re}"
        echo ""

        if [ "$ENABLE_SS_ARGO" = 1 ]; then
            echo -e "  ${yellow}③ Shadowsocks + WS + Argo${re}"
            local ss_pass; ss_pass=$(jq -r '.inbounds[] | select(.tag=="ss-ws") | .settings.password // empty' "$CONFIG_FILE" 2>/dev/null)
            [ -z "$ss_pass" ] && ss_pass="$uuid"
            echo -e "  ${green}$(gen_ss_link "$SS_METHOD" "$ss_pass" "$cdn_addr" "$cdn_port" "${NODE_NAME}-SS-Argo")${re}"
            echo -e "  ${cyan}加密${re}: ${SS_METHOD}  |  ${cyan}路径${re}: /ss-argo  |  ${cyan}传输${re}: ws  |  ${cyan}TLS${re}: tls"
            echo -e "  ${cyan}伪装域名${re}: ${green}${host_domain}${re}"
            echo ""
        fi
        show_qr "$(gen_vless_link "$uuid" "$host_domain" "$cdn_addr" "$cdn_port")"
    fi

    # === Reality 直连 ===
    if [ "$ENABLE_REALITY" = 1 ] && [ -n "$ip_addr" ]; then
        echo -e "  ${white}━━━ VLESS Reality 直连 (需开放端口 ${REALITY_PORT}) ━━━${re}"
        echo ""
        local r_pub; r_pub=$(jq -r '.inbounds[] | select(.tag=="reality") | .streamSettings.realitySettings.publicKey // empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${green}$(gen_reality_link "$uuid" "$ip_addr" "$REALITY_PORT" "$REALITY_SNI" "$r_pub")${re}"
        echo -e "  ${cyan}SNI${re}: ${REALITY_SNI}  |  ${cyan}Flow${re}: xtls-rprx-vision"
        echo ""
    fi

    # === SS 直连 ===
    if [ "$ENABLE_SS_DIRECT" = 1 ] && [ -n "$ip_addr" ]; then
        echo -e "  ${white}━━━ Shadowsocks 直连 (需开放端口 ${SS_DIRECT_PORT}) ━━━${re}"
        echo ""
        local ssd_pass; ssd_pass=$(jq -r '.inbounds[] | select(.tag=="ss-direct") | .settings.password // empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${green}$(gen_ss_link "$SS_METHOD" "$ssd_pass" "$ip_addr" "$SS_DIRECT_PORT" "${NODE_NAME}-SS-Direct")${re}"
        echo -e "  ${cyan}加密${re}: ${SS_METHOD}"
        echo ""
    fi

    echo -e "  ${yellow}💡${re} 复制链接 → 客户端导入剪贴板"
    echo -e "  ${yellow}💡${re} 菜单 2 切换优选线路 | 菜单 3 修改配置"
}

#==============================================================================
# 服务控制
#==============================================================================
start_services() {
    yellow_msg "启动服务..."; systemctl start xray tunnel 2>/dev/null; sleep 2
    get_status; echo -e "  Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"; green_msg "完成！"
}
stop_services() {
    yellow_msg "停止服务..."; systemctl stop xray tunnel 2>/dev/null; sleep 1
    get_status; echo -e "  Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"; red_msg "已停止。"
}
restart_services() {
    yellow_msg "重启服务..."; rm -f "$TUNNEL_LOG"
    systemctl restart xray tunnel 2>/dev/null; sleep 3; get_status
    local d; d=$(get_argo_domain)
    echo -e "  Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"; green_msg "完成！"
    [ -n "$d" ] && echo -e "  新域名: ${purple}${d}${re}"
}

#==============================================================================
# 优选域名
#==============================================================================
edit_cdn() {
    load_conf
    while true; do
        clear; local cur_cdn cur_port; cur_cdn=$(get_cdn); cur_port=$(get_cdn_port)
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}快捷更换优选域名 / 线路${re}             ${purple}║${re}"
        echo -e " ${purple}║${re}       ${yellow}当前: ${green}${cur_cdn}:${cur_port}${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${white}── 三网通用 ──${re}"
        for key in 1 2 3 4 5 6 7; do echo -e "  ${green}${key}${re}. ${CDN_DOMAINS[$key]}"; done
        echo ""
        echo -e "  ${white}── 运营商专线 ──${re}"
        for key in 8 9 10; do echo -e "  ${green}${key}${re}. ${CDN_DOMAINS[$key]}"; done
        echo ""
        echo -e "  ${white}── 其他优选 ──${re}"
        for key in 11 12 13; do echo -e "  ${green}${key}${re}. ${CDN_DOMAINS[$key]}"; done
        echo ""
        echo -e "  ${cyan}c${re}. 自定义地址 (host:port)"
        echo -e "  ${cyan}p${re}. 仅修改端口"
        echo -e "  ${red}0${re}. 返回"
        echo ""
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        local np="$cur_port"
        case "$c" in
            1) CDN_DOMAIN="cdn.31514926.xyz" ;; 2) CDN_DOMAIN="skk.moe" ;;
            3) CDN_DOMAIN="ip.sb" ;; 4) CDN_DOMAIN="time.is" ;; 5) CDN_DOMAIN="bestcf.top" ;;
            6) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;; 7) CDN_DOMAIN="cf.090227.xyz" ;;
            8) CDN_DOMAIN="yidong.19931101.xyz" ;; 9) CDN_DOMAIN="liantong.19931101.xyz" ;;
            10) CDN_DOMAIN="dianxin.19931101.xyz" ;; 11) CDN_DOMAIN="cdn.2020111.xyz" ;;
            12) CDN_DOMAIN="xn--b6gac.eu.org" ;; 13) CDN_DOMAIN="cdns.doon.eu.org" ;;
            c|C) read -p "  地址 (host:port): " raw
                 [[ "$raw" =~ ^(.+):([0-9]+)$ ]] && { CDN_DOMAIN="${BASH_REMATCH[1]}"; np="${BASH_REMATCH[2]}"; } || CDN_DOMAIN="$raw" ;;
            p|P) read -p "  端口: " np; CDN_DOMAIN="$cur_cdn" ;;
            0) return ;; *) red_msg "无效。"; sleep 1; continue ;;
        esac
        [ -n "$CDN_DOMAIN" ] && { CDN_PORT="$np"
            jq --arg cdn "$CDN_DOMAIN" --argjson p "$CDN_PORT" '.current_cdn=$cdn|.current_cdn_port=$p' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            save_conf; echo ""; green_msg "切换成功！${CDN_DOMAIN}:${CDN_PORT}"; yellow_msg "  💡 客户端修改 Address/Port 即可"; break; }
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
        echo -e "  ${green}1${re}. 修改节点名称 — ${cyan}${NODE_NAME}${re}"
        echo -e "  ${green}2${re}. 更换 UUID (所有协议同步)"
        echo -e "  ${green}3${re}. 切换 Argo 隧道 (临时↔固定)"
        echo -e "  ${green}4${re}. 修改 SS 加密方式 — ${cyan}${SS_METHOD}${re}"
        echo -e "  ${green}5${re}. 修改 Reality 伪装域名 — ${cyan}${REALITY_SNI}${re}"
        echo -e "  ${green}6${re}. 添加/移除可选协议 (需重装)"
        echo -e "  ${green}7${re}. 查看当前节点链接"
        echo -e "  ${green}8${re}. 刷新 Argo 临时域名"
        echo -e "  ${red}0${re}. 返回"
        echo ""; echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " c
        case "$c" in
            1) read -p "  新名称 [${NODE_NAME}]: " n; [ -n "$n" ] && NODE_NAME="$n"; save_conf; green_msg "已更新: ${NODE_NAME}" ;;
            2) local nu; read -p "  新 UUID (回车自动生成): " nu
               [ -z "$nu" ] && nu=$(cat /proc/sys/kernel/random/uuid)
               # 仅更新 clients[].id，不动 SS 的 password
               jq --arg u "$nu" '
                 (.inbounds[].settings.clients[]? | select(.id) | .id) |= $u
               ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
               UUID_CUSTOM="$nu"; save_conf; systemctl restart xray 2>/dev/null
               green_msg "UUID 已更新（全协议同步）！${nu}" ;;
            3) switch_argo_tunnel ;;
            4) echo ""; for i in "${!SS_METHODS[@]}"; do echo -e "  ${green}$((i+1))${re}. ${SS_METHODS[$i]}"; done; echo ""
               read -p "  选择加密方式 [默认: aes-256-gcm]: " sm
               [ -n "$sm" ] && SS_METHOD="${SS_METHODS[$((sm-1))]:-$SS_METHOD}"
               save_conf; green_msg "SS 加密: ${SS_METHOD}" ;;
            5) echo ""; for i in "${!REALITY_SNIS[@]}"; do echo -e "  ${green}$((i+1))${re}. ${REALITY_SNIS[$i]}"; done; echo ""
               read -p "  选择伪装域名 [默认: www.amazon.com]: " rs
               [ -n "$rs" ] && REALITY_SNI="${REALITY_SNIS[$((rs-1))]:-$REALITY_SNI}"
               save_conf; green_msg "Reality SNI: ${REALITY_SNI}" ;;
            6) select_protocols; do_install; break ;;
            7) show_node ;;
            8) restart_services ;;
            0) return ;; *) red_msg "无效选项" ;;
        esac
        read -p "  按回车键继续..." -r
    done
}

#==============================================================================
# Argo 隧道切换
#==============================================================================
switch_argo_tunnel() {
    load_conf; clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}切换 Argo 隧道类型${re}                   ${purple}║${re}"
    echo -e " ${purple}║${re}       ${yellow}当前: $([ "$ARGO_MODE" = "temp" ] && echo "临时隧道" || echo "固定隧道")${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${green}1${re}. 临时隧道 (.trycloudflare.com)"
    echo -e "  ${green}2${re}. 固定隧道 (CF Zero Trust Token)"
    echo -e "  ${red}0${re}. 返回"
    echo ""; read -p "  请选择: " c
    case "$c" in
        1) ARGO_MODE="temp"; ARGO_AUTH=""; ARGO_FIXED_DOMAIN=""; save_conf; rebuild_tunnel "temp"; restart_services ;;
        2) read -p "  固定域名: " ARGO_FIXED_DOMAIN; read -p "  Token: " ARGO_AUTH
           [ -z "$ARGO_FIXED_DOMAIN" ] || [ -z "$ARGO_AUTH" ] && { red_msg "不能为空"; return; }
           ARGO_MODE="fixed-token"; save_conf; rebuild_tunnel "fixed-token"; restart_services
           green_msg "已切换固定隧道: ${ARGO_FIXED_DOMAIN}" ;;
        0) return ;; *) red_msg "无效" ;;
    esac
}

rebuild_tunnel() {
    if [ "$1" = "fixed-token" ]; then
        cat > /etc/systemd/system/tunnel.service << EOF
[Unit]
Description=Cloudflare Argo Tunnel (Fixed)
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=${WORK_DIR}/argo tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    else
        cat > /etc/systemd/system/tunnel.service << EOF
[Unit]
Description=Cloudflare Argo Tunnel (Temp)
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=${WORK_DIR}/argo tunnel --url http://localhost:${ARGO_PORT} --no-autoupdate --edge-ip-version auto --protocol http2
StandardOutput=append:${TUNNEL_LOG}
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl daemon-reload
}

#==============================================================================
# 协议选择（步骤 ⑦）
#==============================================================================
select_protocols() {
    while true; do
        clear
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}选择额外协议（可选）${re}                    ${purple}║${re}"
        echo -e " ${purple}║${re}     ${yellow}以下协议默认不安装，按需勾选${re}            ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${white}Argo 隧道协议（无需开放端口）：${re}"
        echo ""
        echo -e "  ${green}1${re}. Shadowsocks + Argo ${cyan}[$( [ "$ENABLE_SS_ARGO" = 1 ] && echo "●" || echo "○" )]${re}"
        echo -e "     SS AEAD/2022 → WS → Argo，7 种加密可选"
        echo ""
        echo -e "  ${white}直连协议（需开放 VPS 端口）：${re}"
        echo ""
        echo -e "  ${green}2${re}. VLESS Reality ${cyan}[$( [ "$ENABLE_REALITY" = 1 ] && echo "●" || echo "○" )]${re}"
        echo -e "     XTLS Vision + Reality，抗封锁"
        echo ""
        echo -e "  ${green}3${re}. Shadowsocks 直连 ${cyan}[$( [ "$ENABLE_SS_DIRECT" = 1 ] && echo "●" || echo "○" )]${re}"
        echo -e "     SS AEAD/2022 直连 TCP"
        echo ""
        echo -e "  ${white}始终安装：VLESS-Argo + VMess-Argo${re}"
        echo ""
        echo -e "  ${yellow}输序号切换勾选，0 确认${re}"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  (1-3 / 0=确认): " c
        case "$c" in
            1) ENABLE_SS_ARGO=$((1 - ENABLE_SS_ARGO)); continue ;;
            2) ENABLE_REALITY=$((1 - ENABLE_REALITY)); continue ;;
            3) ENABLE_SS_DIRECT=$((1 - ENABLE_SS_DIRECT)); continue ;;
            0) save_conf; return ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac
    done
}

#==============================================================================
# 交互式安装
#==============================================================================
interactive_install() {
    load_conf
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}  ${white}ArgoX-Mini · 交互式安装向导${re}              ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    yellow_msg "按提示一步步配置，回车使用默认值即可。"
    echo ""

    # ①
    echo -e " ${white}━━━ ① 节点名称 ━━━${re}"
    echo -e "  ${yellow}显示在客户端节点列表中。${re}"
    read -p "  [${NODE_NAME}]: " n; [ -n "$n" ] && NODE_NAME="$n"
    echo -e "  → ${green}${NODE_NAME}${re}\n"

    # ②
    echo -e " ${white}━━━ ② CDN 优选地址 ━━━${re}"
    echo -e "  ${green}1${re}. 默认 ${CDN_DEFAULT}    ${green}2${re}. 从列表选    ${green}3${re}. 自定义"
    read -p "  [1]: " ct
    case "${ct:-1}" in
        2) for key in {1..13}; do echo -e "  ${green}${key}${re}. ${CDN_DOMAINS[$key]}"; done
           read -p "  序号 [1]: " ci
           case "${ci:-1}" in
               1) CDN_DOMAIN="cdn.31514926.xyz" ;; 2) CDN_DOMAIN="skk.moe" ;;
               3) CDN_DOMAIN="ip.sb" ;; 4) CDN_DOMAIN="time.is" ;; 5) CDN_DOMAIN="bestcf.top" ;;
               6) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;; 7) CDN_DOMAIN="cf.090227.xyz" ;;
               8) CDN_DOMAIN="yidong.19931101.xyz" ;; 9) CDN_DOMAIN="liantong.19931101.xyz" ;;
               10) CDN_DOMAIN="dianxin.19931101.xyz" ;; 11) CDN_DOMAIN="cdn.2020111.xyz" ;;
               12) CDN_DOMAIN="xn--b6gac.eu.org" ;; 13) CDN_DOMAIN="cdns.doon.eu.org" ;;
           esac ;;
        3) read -p "  地址: " CDN_DOMAIN; [ -z "$CDN_DOMAIN" ] && CDN_DOMAIN="$CDN_DEFAULT" ;;
    esac
    echo -e "  → ${green}${CDN_DOMAIN}${re}\n"

    # ③
    echo -e " ${white}━━━ ③ 客户端端口 ━━━${re}"
    echo -e "  ${yellow}CF 支持: 443, 8443, 2053, 2083, 2087, 2096${re}"
    read -p "  [${CDN_PORT}]: " n; [ -n "$n" ] && CDN_PORT="$n"
    echo -e "  → ${green}${CDN_PORT}${re}\n"

    # ④
    echo -e " ${white}━━━ ④ UUID ━━━${re}"
    read -p "  [自动生成]: " n; [ -n "$n" ] && UUID_CUSTOM="$n"
    echo ""

    # ⑤
    echo -e " ${white}━━━ ⑤ Argo 隧道类型 ━━━${re}"
    echo -e "  ${green}1${re}. 临时隧道      ${green}2${re}. 固定隧道"
    read -p "  [1]: " tt
    case "${tt:-1}" in
        2) read -p "  固定域名: " ARGO_FIXED_DOMAIN; read -p "  Token: " ARGO_AUTH
           [ -n "$ARGO_FIXED_DOMAIN" ] && [ -n "$ARGO_AUTH" ] && ARGO_MODE="fixed-token" ;;
    esac
    echo ""

    # ⑥
    echo -e " ${white}━━━ ⑥ 内部端口 ━━━${re}"
    echo -e "  ${yellow}仅 127.0.0.1，不对外暴露。${re}"
    echo -e "  ${cyan}Argo:${ARGO_PORT}  VLESS:${VLESS_WS_PORT}  VMess:${VMESS_WS_PORT}  SS:${SS_WS_PORT}${re}"
    read -p "  修改起始端口? 输入或回车跳过: " bp
    [ -n "$bp" ] && { ARGO_PORT="$bp"; VLESS_WS_PORT=$((bp+1)); VMESS_WS_PORT=$((bp+2)); SS_WS_PORT=$((bp+3)); }
    echo ""

    # ⑦ 可选协议
    echo -e " ${white}━━━ ⑦ 额外协议（可选）━━━${re}"
    select_protocols

    # 确认
    echo ""
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e " ${white}配置确认：${re}"
    echo -e "  名称     : ${green}${NODE_NAME}${re}"
    echo -e "  CDN      : ${green}${CDN_DOMAIN}:${CDN_PORT}${re}"
    echo -e "  UUID     : ${cyan}$([ -n "$UUID_CUSTOM" ] && echo "$UUID_CUSTOM" || echo "自动生成")${re}"
    echo -e "  隧道     : ${cyan}$([ "$ARGO_MODE" = "fixed-token" ] && echo "固定 ${ARGO_FIXED_DOMAIN}" || echo "临时")${re}"
    echo -e "  协议     : ${cyan}VLESS-Argo VMess-Argo$( [ "$ENABLE_SS_ARGO" = 1 ] && echo " SS-Argo" )$( [ "$ENABLE_REALITY" = 1 ] && echo " Reality" )$( [ "$ENABLE_SS_DIRECT" = 1 ] && echo " SS-Direct" )${re}"
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo ""
    echo -ne "  ${yellow}确认安装? (y/n) [y]: ${re}"
    read cf
    [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }
    save_conf; do_install
}

#==============================================================================
# 实际安装
#==============================================================================
do_install() {
    load_conf
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}   ${white}ArgoX-Mini · 正在部署...${re}                  ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    yellow_msg "[1/7] 清理冲突组件..."
    pkill -9 nginx caddy xray argo 2>/dev/null
    systemctl stop nginx caddy xray tunnel 2>/dev/null
    systemctl disable nginx caddy 2>/dev/null
    green_msg "  完成"

    yellow_msg "[2/7] 安装依赖..."
    if command -v apt &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof openssl
    elif command -v yum &>/dev/null; then yum install -y -q jq unzip curl lsof openssl
    elif command -v dnf &>/dev/null; then dnf install -y -q jq unzip curl lsof openssl; fi
    green_msg "  完成"

    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG CF_ARCH; ARCH_ARG=$(detect_arch); CF_ARCH=$(cf_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/7] 下载 Xray + cloudflared..."
    curl -sLo "${WORK_DIR}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${WORK_DIR}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR" > /dev/null 2>&1
    chmod +x "${WORK_DIR}/xray" "${WORK_DIR}/argo"; rm -f "${WORK_DIR}/xray.zip"
    install_qrencode; green_msg "  完成"

    yellow_msg "[4/7] 检测端口并生成密钥..."
    port_in_use "$ARGO_PORT" && ARGO_PORT=$(find_free_port "$ARGO_PORT")
    port_in_use "$VLESS_WS_PORT" && VLESS_WS_PORT=$(find_free_port "$VLESS_WS_PORT")
    port_in_use "$VMESS_WS_PORT" && VMESS_WS_PORT=$(find_free_port "$VMESS_WS_PORT")
    [ "$ENABLE_SS_ARGO" = 1 ] && port_in_use "$SS_WS_PORT" && SS_WS_PORT=$(find_free_port "$SS_WS_PORT")

    # Reality 直连端口
    if [ "$ENABLE_REALITY" = 1 ]; then
        [ "$REALITY_PORT" = "0" ] && REALITY_PORT=$(shuf -i 10000-60000 -n 1)
        port_in_use "$REALITY_PORT" && REALITY_PORT=$(find_free_port "$REALITY_PORT")
        gen_reality_keys
    fi
    # SS 直连端口
    if [ "$ENABLE_SS_DIRECT" = 1 ]; then
        [ "$SS_DIRECT_PORT" = "0" ] && SS_DIRECT_PORT=$(shuf -i 10000-60000 -n 1)
        port_in_use "$SS_DIRECT_PORT" && SS_DIRECT_PORT=$(find_free_port "$SS_DIRECT_PORT")
    fi

    local UUID; UUID="${UUID_CUSTOM:-$(cat /proc/sys/kernel/random/uuid)}"
    # SS 密码
    local SS_PASS
    if [[ "$SS_METHOD" =~ 2022 ]]; then SS_PASS=$(gen_ss2022_pass "$SS_METHOD")
    else SS_PASS="$UUID"; fi
    [ -z "$SS_PASS" ] && SS_PASS="$UUID"

    green_msg "  完成"

    yellow_msg "[5/7] 生成 Xray 配置..."
    build_xray_config "$UUID" "$SS_PASS"
    green_msg "  完成"

    yellow_msg "[6/7] 创建系统服务..."
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
    rebuild_tunnel "$ARGO_MODE"
    green_msg "  完成"

    yellow_msg "[7/7] 启动服务..."
    rm -f "$TUNNEL_LOG"; systemctl daemon-reload
    systemctl enable xray tunnel 2>/dev/null
    systemctl restart xray tunnel; sleep 5
    green_msg "  完成"

    # 快捷指令
    cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
ARGOWRAP
    chmod +x "$SCRIPT_PATH"; save_conf

    # --- 输出结果 ---
    local host_domain ip_addr
    [ "$ARGO_MODE" = "fixed-token" ] && host_domain="$ARGO_FIXED_DOMAIN" || host_domain=$(get_argo_domain)
    [ -z "$host_domain" ] && [ "$ARGO_MODE" != "fixed-token" ] && { sleep 3; host_domain=$(get_argo_domain); }
    ip_addr=$(get_ip)

    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}🎉 部署成功 · ${NODE_NAME}${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${cyan}快捷管理${re}: ${green}argov${re}"
    echo -e "  ${cyan}节点名称${re}: ${white}${NODE_NAME}${re}"
    echo -e "  ${cyan}UUID${re}    : ${purple}${UUID}${re}"
    echo ""

    # Argo 协议输出
    if [ -n "$host_domain" ]; then
        echo -e "  ${white}── Argo 隧道协议 (无需开放端口) ──${re}"
        echo ""
        local vl vm; vl=$(gen_vless_link "$UUID" "$host_domain" "$CDN_DOMAIN" "$CDN_PORT")
        vm=$(gen_vmess_link "$UUID" "$host_domain" "$CDN_DOMAIN" "$CDN_PORT")
        echo -e "  ${yellow}VLESS:${re}  ${green}${vl}${re}\n"
        echo -e "  ${yellow}VMess:${re}  ${green}${vm}${re}\n"
        if [ "$ENABLE_SS_ARGO" = 1 ]; then
            local ss_l; ss_l=$(gen_ss_link "$SS_METHOD" "$SS_PASS" "$CDN_DOMAIN" "$CDN_PORT" "${NODE_NAME}-SS-Argo")
            echo -e "  ${yellow}SS:${re}     ${green}${ss_l}${re}"
            echo -e "          加密:${SS_METHOD}  路径:/ss-argo  WS+TLS  伪装:${host_domain}\n"
        fi
        show_qr "$vl"
    fi

    # Reality
    if [ "$ENABLE_REALITY" = 1 ] && [ -n "$ip_addr" ]; then
        echo -e "  ${white}── VLESS Reality 直连 (端口 ${REALITY_PORT}) ──${re}"
        local rl; rl=$(gen_reality_link "$UUID" "$ip_addr" "$REALITY_PORT" "$REALITY_SNI" "$REALITY_PUB")
        echo -e "  ${yellow}Reality:${re} ${green}${rl}${re}\n"
    fi

    # SS 直连
    if [ "$ENABLE_SS_DIRECT" = 1 ] && [ -n "$ip_addr" ]; then
        echo -e "  ${white}── Shadowsocks 直连 (端口 ${SS_DIRECT_PORT}) ──${re}"
        local sl; sl=$(gen_ss_link "$SS_METHOD" "$SS_PASS" "$ip_addr" "$SS_DIRECT_PORT" "${NODE_NAME}-SS-Direct")
        echo -e "  ${yellow}SS:${re}     ${green}${sl}${re}\n"
    fi

    echo -e "  ${yellow}📋${re} 管理: ${green}argov${re}    ${yellow}💡${re} 复制链接 → 客户端导入"
}

#==============================================================================
# 构建 Xray config.json
#==============================================================================
build_xray_config() {
    local uuid="$1" ss_pass="$2"
    local inbounds fallbacks
    inbounds='['; fallbacks=''

    # --- 1. Argo 路由入口 ---
    fallbacks='{"path":"/vmess-argo","dest":'"${VMESS_WS_PORT}"'},{"path":"/vless-argo","dest":'"${VLESS_WS_PORT}"'}'
    [ "$ENABLE_SS_ARGO" = 1 ] && fallbacks+=',{"path":"/ss-argo","dest":'"${SS_WS_PORT}"'}'

    inbounds+='{"port":'"${ARGO_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"argo-in","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none","fallbacks":['"${fallbacks}"']},"streamSettings":{"network":"tcp"}}'

    # --- 2. VLESS WS Argo ---
    inbounds+=',{"port":'"${VLESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"vless-ws","settings":{"clients":[{"id":"'"${uuid}"'"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}}}'

    # --- 3. VMess WS Argo ---
    inbounds+=',{"port":'"${VMESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vmess","tag":"vmess-ws","settings":{"clients":[{"id":"'"${uuid}"'","alterId":0}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-argo"}}}'

    # --- 4. SS WS Argo (optional) ---
    if [ "$ENABLE_SS_ARGO" = 1 ]; then
        inbounds+=',{"port":'"${SS_WS_PORT}"',"listen":"127.0.0.1","protocol":"shadowsocks","tag":"ss-ws","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/ss-argo"}}}'
    fi

    # --- 5. VLESS Reality (optional, public) ---
    if [ "$ENABLE_REALITY" = 1 ]; then
        inbounds+=',{"port":'"${REALITY_PORT}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${REALITY_SNI}"':443","serverNames":["'"${REALITY_SNI}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":[""]}},"sniffing":{"enabled":true,"destOverride":["http","tls"],"routeOnly":true}}'
    fi

    # --- 6. SS Direct (optional, public) ---
    if [ "$ENABLE_SS_DIRECT" = 1 ]; then
        inbounds+=',{"port":'"${SS_DIRECT_PORT}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss-direct","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"}}'
    fi

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
# 主菜单
#==============================================================================
main_menu() {
    load_conf
    while true; do
        get_status; clear
        local uuid_short="未安装" argo_domain=""
        [ -f "$CONFIG_FILE" ] && uuid_short="$(get_uuid | cut -c1-12)..."
        [ "$TUNNEL_RAW" = "running" ] && argo_domain=$(get_argo_domain)
        [ "$ARGO_MODE" = "fixed-token" ] && argo_domain="$ARGO_FIXED_DOMAIN"

        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}ArgoX-Mini  纯净版隧道管理面板${re}              ${purple}║${re}"
        echo -e " ${purple}║${re}     ${cyan}$(get_proto_summary)${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  名称 : ${white}${NODE_NAME}${re}    Xray: ${XRAY_ST}    Argo: ${TUNNEL_ST}"
        echo -e "  UUID : ${cyan}${uuid_short}${re}"
        [ -n "$argo_domain" ] && echo -e "  域名 : ${green}${argo_domain}${re}"
        echo -e "  CDN  : ${green}$(get_cdn):$(get_cdn_port)${re}"
        echo ""
        echo -e " ${purple}───────────────── 节点管理 ─────────────────${re}"
        echo -e "  ${green}1${re}. 查看节点链接 (全部协议)"
        echo -e "  ${green}2${re}. 更换优选域名 / 线路"
        echo -e "  ${green}3${re}. 修改配置 (名称/UUID/隧道/加密/协议)"
        echo ""
        echo -e " ${purple}───────────────── 服务控制 ─────────────────${re}"
        echo -e "  ${green}4${re}. 启动 服务"
        echo -e "  ${red}5${re}. 停止 服务"
        echo -e "  ${yellow}6${re}. 重启 服务 (刷新域名)"
        echo ""
        echo -e " ${purple}───────────────── 系统维护 ─────────────────${re}"
        echo -e "  ${yellow}7${re}. 重新安装 (保留配置)"
        echo -e "  ${cyan}8${re}. 更新 ArgoX-Mini"
        echo -e "  ${red}9${re}. 完全卸载"
        echo ""
        echo -e "  ${cyan}0${re}. 退出"
        echo ""
        echo -e " ${purple}────────────────────────────────────────────${re}"
        read -p "  请输入 (0-9): " c
        case "$c" in
            1) show_node; read -p "  按回车键返回..." -r ;;
            2) edit_cdn; read -p "  按回车键返回..." -r ;;
            3) change_config ;;
            4) start_services; sleep 1 ;; 5) stop_services; sleep 1 ;; 6) restart_services; sleep 1 ;;
            7) echo -ne "  ${yellow}重新安装? 保留配置 (y/n): ${re}"; read cf
               [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { load_conf; do_install; }
               read -p "  按回车键返回..." -r ;;
            8) yellow_msg "拉取最新版本..."; bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh); exit 0 ;;
            9) echo -ne "  ${red}⚠ 确定完全卸载? (y/n): ${re}"; read cf
               if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                   systemctl stop xray tunnel 2>/dev/null; systemctl disable xray tunnel 2>/dev/null
                   rm -rf "$WORK_DIR"; rm -f /etc/systemd/system/xray.service /etc/systemd/system/tunnel.service "$SCRIPT_PATH"
                   systemctl daemon-reload; green_msg "卸载完成。"; exit 0
               fi ;;
            0) clear; exit 0 ;;
            *) red_msg "无效 (0-9)"; sleep 1 ;;
        esac
    done
}

#==============================================================================
# 入口
#==============================================================================
load_conf
[ ! -f "$CONFIG_FILE" ] && { interactive_install; exit 0; }
main_menu
