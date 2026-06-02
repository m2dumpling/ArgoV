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
get_uuid()   { jq -r '.inbounds[0].settings.clients[0].id // empty' "$CONFIG_FILE" 2>/dev/null; }
get_cdn()    { [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_DOMAIN"; }
get_cdn_port() { [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn_port // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_PORT"; }
get_ip() {
    local ip; ip=$(curl -s --max-time 2 ipv4.ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 2 ifconfig.me 2>/dev/null); echo "$ip"
}
gen_reality_keys() {
    local out; out=$("${WORK_DIR}/xray" x25519 2>/dev/null)
    REALITY_PRIV=$(echo "$out" | grep "Private" | awk '{print $3}')
    REALITY_PUB=$(echo "$out" | grep "Public"  | awk '{print $3}')
    [ -z "$REALITY_PRIV" ] && { REALITY_PRIV="REPLACE_ME"; REALITY_PUB="REPLACE_ME"; }
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
    ARGO_FIXED_DOMAIN="${ARGO_FIXED_DOMAIN:-}"; UUID_CUSTOM="${UUID_CUSTOM:-}"
    REALITY_PORT="${REALITY_PORT:-0}"; SS_PORT="${SS_PORT:-0}"
    REALITY_SNI="${REALITY_SNI:-www.amazon.com}"; SS_METHOD="${SS_METHOD:-aes-256-gcm}"
    ENABLE_REALITY="${ENABLE_REALITY:-0}"; ENABLE_SS="${ENABLE_SS:-0}"
    REALITY_PRIV="${REALITY_PRIV:-}"; REALITY_PUB="${REALITY_PUB:-}"
}
save_conf() {
    cat > "$USER_CONF" << EOF
# ArgoX-Mini — $(date '+%Y-%m-%d %H:%M:%S')
NODE_NAME='${NODE_NAME}'
ARGO_PORT='${ARGO_PORT}'; VLESS_WS_PORT='${VLESS_WS_PORT}'
VMESS_WS_PORT='${VMESS_WS_PORT}'; CDN_PORT='${CDN_PORT}'
CDN_DOMAIN='${CDN_DOMAIN}'; ARGO_MODE='${ARGO_MODE}'; ARGO_AUTH='${ARGO_AUTH}'
ARGO_FIXED_DOMAIN='${ARGO_FIXED_DOMAIN}'; UUID_CUSTOM='${UUID_CUSTOM}'
REALITY_PORT='${REALITY_PORT}'; SS_PORT='${SS_PORT}'
REALITY_SNI='${REALITY_SNI}'; SS_METHOD='${SS_METHOD}'
ENABLE_REALITY='${ENABLE_REALITY}'; ENABLE_SS='${ENABLE_SS}'
REALITY_PRIV='${REALITY_PRIV}'; REALITY_PUB='${REALITY_PUB}'
EOF
}

#==============================================================================
# 链接生成
#==============================================================================
gen_vmess_link() {
    local json; json="{\"v\":\"2\",\"ps\":\"${5:-${NODE_NAME}-VMess}\",\"add\":\"${3:-$(get_cdn)}\",\"port\":\"${4:-$(get_cdn_port)}\",\"id\":\"$1\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$2\",\"path\":\"/vmess-argo\",\"tls\":\"tls\",\"sni\":\"$2\",\"alpn\":\"\",\"fp\":\"\"}"
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
    printf '%s' "vless://$1@$2:$3?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$4&pbk=$5&fp=chrome#${6:-${NODE_NAME}-Reality}"
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
# 状态 & 摘要
#==============================================================================
get_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"
    else XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"; fi
    if argox-tunnel 2>/dev/null; then TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"
    else TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"; fi
}
get_proto_summary() {
    local s="VL-Argo VM-Argo"
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && s="$s SS"
    grep -q '"tag":"reality"' "$CONFIG_FILE" 2>/dev/null && s="$s Reality"
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
        show_qr "$(gen_vless_link "$uuid" "$hd" "$cd" "$cp")"
    fi

    if grep -q '"tag":"reality"' "$CONFIG_FILE" 2>/dev/null && [ -n "$ip" ]; then
        local rport rsni rp
        rport=$(jq -r '.inbounds[]|select(.tag=="reality")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        rsni=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]//empty' "$CONFIG_FILE" 2>/dev/null)
        rp=$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey//empty' "$CONFIG_FILE" 2>/dev/null)
        echo -e "  ${white}── VLESS Reality (端口 ${rport}) ──${re}"
        echo ""
        echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$rport" "$rsni" "$rp")${re}"
        echo -e "  ${cyan}SNI${re}: ${rsni}  Flow: xtls-rprx-vision\n"
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
}

#==============================================================================
# 服务控制
#==============================================================================
start_services() { yellow_msg "启动..."; systemctl start xray argox-tunnel 2>/dev/null; sleep 2; get_status; echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"; green_msg "完成"; }
stop_services()  { yellow_msg "停止..."; systemctl stop xray argox-tunnel 2>/dev/null; sleep 1; get_status; echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"; red_msg "已停止"; }
restart_services() { yellow_msg "重启..."; rm -f "$TUNNEL_LOG"; systemctl restart xray argox-tunnel 2>/dev/null; sleep 3; get_status; local d; d=$(get_argo_domain); echo -e "  Xray: ${XRAY_ST}  Argo: ${TUNNEL_ST}"; green_msg "完成"; [ -n "$d" ] && echo -e "  域名: ${purple}${d}${re}"; }

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
            6) select_protocols; do_install; break ;;
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
    if [ "$1" = "fixed-token" ]; then
        cat > /etc/systemd/system/argox-tunnel.service << EOF
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
        cat > /etc/systemd/system/argox-tunnel.service << EOF
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
    fi; systemctl daemon-reload
}

#==============================================================================
# 协议选择 (安装步骤⑦)
#==============================================================================
select_protocols() {
    while true; do
        clear
        echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}选择额外协议（可选）${re}                    ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${green}1${re}. VLESS Reality ${cyan}[$( [ "$ENABLE_REALITY" = 1 ] && echo "●" || echo "○" )]${re}"
        echo -e "     XTLS Vision + Reality，需开放端口"
        echo ""
        echo -e "  ${green}2${re}. Shadowsocks ${cyan}[$( [ "$ENABLE_SS" = 1 ] && echo "●" || echo "○" )]${re}"
        echo -e "     AEAD/2022 加密，需开放端口"
        echo ""
        echo -e "  ${white}始终安装：VLESS-Argo + VMess-Argo${re}"
        echo -e "  ${yellow}输序号切换，0 确认${re}"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  (1-2 / 0=确认): " c
        case "$c" in
            1) ENABLE_REALITY=$((1-ENABLE_REALITY)); continue ;;
            2) ENABLE_SS=$((1-ENABLE_SS)); continue ;;
            0) save_conf; return ;;
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
    read -p "  起始端口 [回车跳过]: " bp; [ -n "$bp" ] && { ARGO_PORT="$bp"; VLESS_WS_PORT=$((bp+1)); VMESS_WS_PORT=$((bp+2)); }; echo ""

    echo -e " ${white}━━━ ⑦ 额外协议 ━━━${re}"; select_protocols

    echo ""; echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e " ${white}确认：${re}  名称: ${green}${NODE_NAME}${re}  CDN: ${green}${CDN_DOMAIN}:${CDN_PORT}${re}"
    echo -e "  UUID: ${cyan}$([ -n "$UUID_CUSTOM" ] && echo "$UUID_CUSTOM" || echo "自动")${re}"
    echo -e "  隧道: ${cyan}$([ "$ARGO_MODE" = "fixed-token" ] && echo "固定 ${ARGO_FIXED_DOMAIN}" || echo "临时")${re}"
    echo -e "  协议: ${cyan}VLESS-Argo VMess-Argo$( [ "$ENABLE_REALITY" = 1 ] && echo " Reality" )$( [ "$ENABLE_SS" = 1 ] && echo " SS" )${re}"
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo ""; echo -ne "  ${yellow}确认安装? (y/n) [y]: ${re}"; read cf
    [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }
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
    systemctl stop xray argox-tunnel 2>/dev/null; pkill -9 nginx caddy 2>/dev/null; systemctl stop nginx caddy 2>/dev/null; systemctl disable nginx caddy 2>/dev/null; green_msg "  完成"

    yellow_msg "[2/6] 依赖..."
    if command -v apt &>/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof openssl
    elif command -v yum &>/dev/null; then yum install -y -q jq unzip curl lsof openssl
    elif command -v dnf &>/dev/null; then dnf install -y -q jq unzip curl lsof openssl; fi; green_msg "  完成"

    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG CF_ARCH; ARCH_ARG=$(detect_arch); CF_ARCH=$(cf_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/6] 下载..."
    curl -sLo "${WORK_DIR}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${WORK_DIR}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR">/dev/null 2>&1; chmod +x "${WORK_DIR}/xray" "${WORK_DIR}/argo"; rm -f "${WORK_DIR}/xray.zip"
    install_qrencode; green_msg "  完成"

    yellow_msg "[4/6] 端口检测..."
    port_in_use "$ARGO_PORT" && ARGO_PORT=$(find_free_port "$ARGO_PORT")
    port_in_use "$VLESS_WS_PORT" && VLESS_WS_PORT=$(find_free_port "$VLESS_WS_PORT")
    port_in_use "$VMESS_WS_PORT" && VMESS_WS_PORT=$(find_free_port "$VMESS_WS_PORT")
    if [ "$ENABLE_REALITY" = 1 ]; then [ "$REALITY_PORT" = "0" ] && REALITY_PORT=$(shuf -i 10000-60000 -n 1); port_in_use "$REALITY_PORT" && REALITY_PORT=$(find_free_port "$REALITY_PORT"); gen_reality_keys; fi
    if [ "$ENABLE_SS" = 1 ]; then [ "$SS_PORT" = "0" ] && SS_PORT=$(shuf -i 10000-60000 -n 1); port_in_use "$SS_PORT" && SS_PORT=$(find_free_port "$SS_PORT"); fi

    local UUID; UUID="${UUID_CUSTOM:-$(cat /proc/sys/kernel/random/uuid)}"
    local SS_PASS
    [[ "$SS_METHOD" =~ 2022 ]] && SS_PASS=$(gen_ss2022_pass "$SS_METHOD") || SS_PASS="$UUID"
    [ -z "$SS_PASS" ] && SS_PASS="$UUID"
    green_msg "  完成"

    yellow_msg "[5/6] 生成配置..."
    build_xray_config "$UUID" "$SS_PASS"; green_msg "  完成"

    yellow_msg "[6/6] 启动..."
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
    rebuild_tunnel "$ARGO_MODE"; rm -f "$TUNNEL_LOG"; systemctl daemon-reload
    systemctl enable xray argox-tunnel 2>/dev/null; systemctl restart xray argox-tunnel; sleep 5; green_msg "  完成"

    cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
ARGOWRAP
    chmod +x "$SCRIPT_PATH"; save_conf

    local hd ip; [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN" || hd=$(get_argo_domain)
    [ -z "$hd" ] && [ "$ARGO_MODE" != "fixed-token" ] && { sleep 3; hd=$(get_argo_domain); }; ip=$(get_ip)

    echo ""; echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}🎉 部署成功 · ${NODE_NAME}${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""; echo -e "  ${cyan}管理${re}: ${green}argov${re}    ${cyan}名称${re}: ${white}${NODE_NAME}${re}    ${cyan}UUID${re}: ${purple}${UUID}${re}"; echo ""

    if [ -n "$hd" ]; then
        echo -e "  ${white}── Argo (无需开放端口) ──${re}\n"
        echo -e "  ${yellow}VLESS${re} ${green}$(gen_vless_link "$UUID" "$hd" "$CDN_DOMAIN" "$CDN_PORT")${re}\n"
        echo -e "  ${yellow}VMess${re} ${green}$(gen_vmess_link "$UUID" "$hd" "$CDN_DOMAIN" "$CDN_PORT")${re}\n"
        show_qr "$(gen_vless_link "$UUID" "$hd" "$CDN_DOMAIN" "$CDN_PORT")"
    fi
    if [ "$ENABLE_REALITY" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Reality (端口 ${REALITY_PORT}) ──${re}\n"
        echo -e "  ${green}$(gen_reality_link "$UUID" "$ip" "$REALITY_PORT" "$REALITY_SNI" "$REALITY_PUB")${re}\n"
    fi
    if [ "$ENABLE_SS" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Shadowsocks (端口 ${SS_PORT}) ──${re}\n"
        echo -e "  ${green}$(gen_ss_link "$SS_METHOD" "$SS_PASS" "$ip" "$SS_PORT" "${NODE_NAME}-SS")${re}\n"
    fi
    echo -e "  ${yellow}📋${re} argov    ${yellow}💡${re} 复制链接 → 客户端导入"
}

#==============================================================================
# 构建 config.json
#==============================================================================
build_xray_config() {
    local uuid="$1" ss_pass="$2" inbounds fallbacks
    inbounds='['
    fallbacks='{"path":"/vmess-argo","dest":'"${VMESS_WS_PORT}"'},{"path":"/vless-argo","dest":'"${VLESS_WS_PORT}"'}'

    # 1. Argo 路由入口
    inbounds+='{"port":'"${ARGO_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"argo-in","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none","fallbacks":['"${fallbacks}"']},"streamSettings":{"network":"tcp"}}'
    # 2. VLESS WS
    inbounds+=',{"port":'"${VLESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vless","tag":"vless-ws","settings":{"clients":[{"id":"'"${uuid}"'"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}}}'
    # 3. VMess WS
    inbounds+=',{"port":'"${VMESS_WS_PORT}"',"listen":"127.0.0.1","protocol":"vmess","tag":"vmess-ws","settings":{"clients":[{"id":"'"${uuid}"'","alterId":0}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-argo"}}}'
    # 4. Reality (opt)
    [ "$ENABLE_REALITY" = 1 ] && inbounds+=',{"port":'"${REALITY_PORT}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${REALITY_SNI}"':443","serverNames":["'"${REALITY_SNI}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":[""]}},"sniffing":{"enabled":true,"destOverride":["http","tls"],"routeOnly":true}}'
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
    grep -q '"tag":"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
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
            a2) [ "$has_ss" = 0 ] && [ "$has_reality" = 1 ] && add_single_protocol "ss" ;;
            d|D) delete_protocol ;;
            *) red_msg "无效"; sleep 1; continue ;;
        esac

        load_conf
        has_reality=0; has_ss=0
        grep -q '"tag":"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
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

    local new_port="$cur_port" new_method="$cur_method" new_pass="$cur_pass" new_sni="$cur_sni"

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
            ;;
        reality)
            echo -e " ${white}━━━ ① 伪装域名 ━━━${re}"
            for i in "${!REALITY_SNIS[@]}"; do local mk=" "; [ "${REALITY_SNIS[$i]}" = "$new_sni" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${REALITY_SNIS[$i]}"; done
            echo ""; echo -e "  ${yellow}当前: ${cyan}${new_sni}${re}"; read -p "  新 SNI [回车保持]: " rs
            if [ -n "$rs" ]; then local ri=$((rs-1)); [ "$ri" -ge 0 ] 2>/dev/null && [ "$ri" -lt "${#REALITY_SNIS[@]}" ] && new_sni="${REALITY_SNIS[$ri]}"; fi
            echo -e "  → ${green}${new_sni}${re}\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"; echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网端口"; read -p "  新端口 [回车保持]: " np2
            [ -n "$np2" ] && ! port_in_use "$np2" && new_port="$np2"; [ -n "$np2" ] && port_in_use "$np2" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${new_port}${re}\n"

            echo -e " ${white}━━━ ③ x25519 密钥 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}$(jq -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.privateKey//empty' "$CONFIG_FILE" 2>/dev/null | cut -c1-24)...${re}"
            echo -e "  ${yellow}输入 new 重新生成。${re}"; read -p "  [回车保持]: " rk
            [ "$rk" = "new" ] || [ "$rk" = "NEW" ] && { gen_reality_keys; echo -e "  → ${green}新密钥已生成${re}"; }; echo ""
            ;;
    esac

    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"; echo -e " ${white}确认修改：${re}"
    case "$tag" in
        ss) echo -e "  加密: ${cyan}${cur_method}${re} → ${green}${new_method}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$new_pass" != "$cur_pass" ] && echo -e "  密码: ${cyan}已更新${re}" ;;
        reality) echo -e "  SNI: ${cyan}${cur_sni}${re} → ${green}${new_sni}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}" ;;
    esac
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"; echo ""
    echo -ne "  ${yellow}确认? (y/n) [y]: ${re}"; read cf; [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }

    case "$tag" in
        ss)
            jq --arg m "$new_method" --arg p "$new_pass" --argjson pt "$new_port" \
               '(.inbounds[]|select(.protocol=="shadowsocks")|.settings.method)=$m|(.inbounds[]|select(.protocol=="shadowsocks")|.settings.password)=$p|(.inbounds[]|select(.protocol=="shadowsocks")|.port)=$pt|(.inbounds[]|select(.protocol=="shadowsocks")|.tag)="ss"' \
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
            fi ;;
    esac
    save_conf; yellow_msg "重启 Xray..."; systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "完成"

    echo ""; echo -e " ${white}━━━ 更新后链接 ━━━${re}"; echo ""
    local ip hd cd cp; ip=$(get_ip); hd=$(get_argo_domain); cd=$(get_cdn); cp=$(get_cdn_port)
    [ "$ARGO_MODE" = "fixed-token" ] && hd="$ARGO_FIXED_DOMAIN"
    case "$tag" in
        ss) [ -n "$ip" ] && echo -e "  ${green}$(gen_ss_link "$new_method" "$new_pass" "$ip" "$new_port" "${NODE_NAME}-SS")${re}" ;;
        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$new_port" "$new_sni" "$REALITY_PUB")${re}" ;;
    esac
    echo ""; read -p "  按回车继续..." -r
}

add_single_protocol() {
    local proto="$1" uuid; uuid=$(get_uuid)
    local sm="$SS_METHOD" sp="" s_port="" r_sni="$REALITY_SNI" r_port=""
    clear
    case "$proto" in
        ss)
            echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
            echo -e " ${purple}║${re}     ${white}添加 Shadowsocks${re}"
            echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""
            echo -e " ${white}━━━ ① 加密 ━━━${re}"
            for i in "${!SS_METHODS[@]}"; do local mk=" "; [ "${SS_METHODS[$i]}" = "$sm" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${SS_METHODS[$i]}"; done
            echo ""; read -p "  选择 [默认 ${sm}]: " s; local si=$(( ${s:-0} -1 ))
            [ "$si" -ge 0 ] 2>/dev/null && [ "$si" -lt "${#SS_METHODS[@]}" ] && sm="${SS_METHODS[$si]}"
            echo -e "  → ${green}${sm}${re}\n"
            echo -e " ${white}━━━ ② 密码 ━━━${re}"; local dp; [[ "$sm" =~ 2022 ]] && dp=$(gen_ss2022_pass "$sm") || dp="$uuid"
            read -p "  密码 [自动]: " sp; [ -z "$sp" ] && sp="$dp"; echo -e "  → ${green}$(echo "$sp"|cut -c1-20)...${re}\n"
            echo -e " ${white}━━━ ③ 端口 ━━━${re}"; local dpt; dpt=$(find_free_port "${SS_PORT:-0}"); [ "$dpt" = "0" ] && dpt=$(find_free_port "$(shuf -i 10000-60000 -n 1)")
            read -p "  端口 [${dpt}]: " s_port; s_port="${s_port:-$dpt}"; echo -e "  → ${green}${s_port}${re}\n"
            ;;
        reality)
            echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
            echo -e " ${purple}║${re}     ${white}添加 VLESS Reality${re}"
            echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""
            echo -e " ${white}━━━ ① SNI ━━━${re}"
            for i in "${!REALITY_SNIS[@]}"; do local mk=" "; [ "${REALITY_SNIS[$i]}" = "$r_sni" ] && mk="★"; echo -e "  ${green}$((i+1))${re}.${mk} ${REALITY_SNIS[$i]}"; done
            echo ""; read -p "  选择 [默认 ${r_sni}]: " rs; local ri=$(( ${rs:-0} -1 ))
            [ "$ri" -ge 0 ] 2>/dev/null && [ "$ri" -lt "${#REALITY_SNIS[@]}" ] && r_sni="${REALITY_SNIS[$ri]}"
            echo -e "  → ${green}${r_sni}${re}\n"
            echo -e " ${white}━━━ ② 端口 ━━━${re}"; local rd; rd=$(find_free_port "$(shuf -i 10000-60000 -n 1)")
            read -p "  端口 [${rd}]: " r_port; r_port="${r_port:-$rd}"; echo -e "  → ${green}${r_port}${re}\n"
            ;;
    esac

    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -ne "  ${yellow}确认添加? (y/n) [y]: ${re}"; read cf; [ "$cf" = "n" ] || [ "$cf" = "N" ] && { yellow_msg "已取消。"; return; }

    local new_inbound=""
    case "$proto" in
        ss)
            new_inbound='{"port":'"${s_port}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${sm}"'","password":"'"${sp}"'","network":"tcp,udp"}}'
            SS_PORT="$s_port"; SS_METHOD="$sm"; ENABLE_SS=1 ;;
        reality)
            gen_reality_keys
            new_inbound='{"port":'"${r_port}"',"listen":"0.0.0.0","protocol":"vless","tag":"reality","settings":{"clients":[{"id":"'"${uuid}"'","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"'"${r_sni}"':443","serverNames":["'"${r_sni}"'",""],"privateKey":"'"${REALITY_PRIV}"'","publicKey":"'"${REALITY_PUB}"'","shortIds":[""]}},"sniffing":{"enabled":true,"destOverride":["http","tls"],"routeOnly":true}}'
            REALITY_PORT="$r_port"; REALITY_SNI="$r_sni"; ENABLE_REALITY=1 ;;
    esac
    jq --argjson i "$new_inbound" '.inbounds+=[$i]' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    save_conf; yellow_msg "重启 Xray..."; systemctl restart xray 2>/dev/null; sleep 2; get_status; green_msg "完成"

    echo ""; echo -e " ${white}━━━ 链接 ━━━${re}"; echo ""
    local ip; ip=$(get_ip)
    case "$proto" in
        ss) [ -n "$ip" ] && echo -e "  ${green}$(gen_ss_link "$sm" "$sp" "$ip" "$s_port" "${NODE_NAME}-SS")${re}" ;;
        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$r_port" "$r_sni" "$REALITY_PUB")${re}" ;;
    esac
    echo ""; read -p "  按回车返回..." -r
}

delete_protocol() {
    clear
    local has_reality=0 has_ss=0
    grep -q '"tag":"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
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
        echo -e "  ${green}4${re}. 启动    ${red}5${re}. 停止    ${yellow}6${re}. 重启 (刷新域名)"
        echo ""
        echo -e " ${purple}───────────────── 系统维护 ─────────────────${re}"
        echo -e "  ${yellow}7${re}. 重新安装 (保留配置)    ${cyan}8${re}. 更新    ${red}9${re}. 卸载"
        echo ""
        echo -e "  ${cyan}0${re}. 退出"
        echo -e " ${purple}────────────────────────────────────────────${re}"
        read -p "  请输入 (0-9 / a): " c
        case "$c" in
            1) show_node; read -p "  按回车返回..." -r ;;
            2) edit_cdn; read -p "  按回车返回..." -r ;;
            3) change_config ;;
            a|A) manage_protocols ;;
            4) start_services; sleep 1 ;; 5) stop_services; sleep 1 ;; 6) restart_services; sleep 1 ;;
            7) echo -ne "  ${yellow}重新安装? (y/n): ${re}"; read cf
               [ "$cf" = "y" ] || [ "$cf" = "Y" ] && { load_conf; do_install; }; read -p "  按回车返回..." -r ;;
            8) yellow_msg "拉取最新版..."; bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh); exit 0 ;;
            9) echo -ne "  ${red}⚠ 确定卸载? (y/n): ${re}"; read cf
               if [ "$cf" = "y" ] || [ "$cf" = "Y" ]; then
                   systemctl stop xray argox-tunnel 2>/dev/null; systemctl disable xray argox-tunnel 2>/dev/null
                   rm -rf "$WORK_DIR"; rm -f /etc/systemd/system/xray.service /etc/systemd/system/argox-tunnel.service "$SCRIPT_PATH"
                   systemctl daemon-reload; green_msg "卸载完成。"; exit 0; fi ;;
            0) clear; exit 0 ;;
            *) red_msg "无效 (0-9 / a)"; sleep 1 ;;
        esac
    done
}

load_conf
[ ! -f "$CONFIG_FILE" ] && { interactive_install; exit 0; }
main_menu
