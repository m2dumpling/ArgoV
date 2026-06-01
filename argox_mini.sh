#!/usr/bin/env bash
#==============================================================================
# ArgoX-Mini — 纯 Argo 隧道双协议交互式管理脚本
# VLESS + VMess  |  WebSocket + TLS  |  Cloudflare Argo Tunnel
# 零公网暴露 · 无 Caddy/Nginx · 无 Reality/XHTTP
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
USER_CONF="/etc/xray/argox.conf"   # 用户持久化配置
TUNNEL_LOG="/etc/xray/argo.log"
WORK_DIR="/etc/xray"
SCRIPT_PATH="/usr/bin/argov"
CDN_DEFAULT="cdn.31514926.xyz"

# --- 端口（支持环境变量覆盖）---
ARGO_PORT="${ARGO_PORT:-8080}"
VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
CDN_PORT="${CDN_PORT:-443}"

# --- 节点名称（支持环境变量）---
NODE_NAME="${NODE_NAME:-ArgoX-Mini}"

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

find_free_port() {
    local port="$1"
    while port_in_use "$port"; do port=$((port + 1)); done
    echo "$port"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)      echo "64" ;;
        i686|i386)   echo "32" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l)      echo "arm32-v7a" ;;
        *)           echo "" ;;
    esac
}

cloudflared_arch() {
    case "$(uname -m)" in
        x86_64)       echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l)       echo "arm" ;;
        i686|i386)    echo "386" ;;
        *)            echo "amd64" ;;
    esac
}

get_argo_domain() {
    local domain
    if [ -f "$TUNNEL_LOG" ]; then
        for i in {1..5}; do
            domain=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' "$TUNNEL_LOG" | tail -n 1)
            [ -n "$domain" ] && break
            sleep 2
        done
    fi
    echo "$domain"
}

# --- 持久化配置读写 ---
load_conf() {
    [ -f "$USER_CONF" ] && . "$USER_CONF"
    # 应用默认值（不覆盖环境变量，仅覆盖未设置的变量）
    NODE_NAME="${NODE_NAME:-ArgoX-Mini}"
    ARGO_PORT="${ARGO_PORT:-8080}"
    VLESS_WS_PORT="${VLESS_WS_PORT:-8081}"
    VMESS_WS_PORT="${VMESS_WS_PORT:-8082}"
    CDN_PORT="${CDN_PORT:-443}"
    CDN_DOMAIN="${CDN_DOMAIN:-$CDN_DEFAULT}"
    ARGO_MODE="${ARGO_MODE:-temp}"           # temp | fixed-token | fixed-json
    ARGO_AUTH="${ARGO_AUTH:-}"               # token 或 json 内容
    ARGO_FIXED_DOMAIN="${ARGO_FIXED_DOMAIN:-}" # 固定隧道域名
    UUID_CUSTOM="${UUID_CUSTOM:-}"           # 用户自定义 UUID（空=自动生成）
}

save_conf() {
    cat > "$USER_CONF" << EOF
# ArgoX-Mini 用户配置 — $(date '+%Y-%m-%d %H:%M:%S')
NODE_NAME='${NODE_NAME}'
ARGO_PORT='${ARGO_PORT}'
VLESS_WS_PORT='${VLESS_WS_PORT}'
VMESS_WS_PORT='${VMESS_WS_PORT}'
CDN_PORT='${CDN_PORT}'
CDN_DOMAIN='${CDN_DOMAIN}'
ARGO_MODE='${ARGO_MODE}'
ARGO_AUTH='${ARGO_AUTH}'
ARGO_FIXED_DOMAIN='${ARGO_FIXED_DOMAIN}'
UUID_CUSTOM='${UUID_CUSTOM}'
EOF
}

get_uuid()  { jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE" 2>/dev/null; }
get_cdn()   { [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_DOMAIN"; }
get_cdn_port() { [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn_port // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_PORT"; }

# --- 链接生成 ---
gen_vmess_link() {
    local uuid="$1" host="$2" addr="${3:-$(get_cdn)}" port="${4:-$(get_cdn_port)}" remark="${5:-${NODE_NAME}-VMess}"
    local json b64
    json="{\"v\":\"2\",\"ps\":\"${remark}\",\"add\":\"${addr}\",\"port\":\"${port}\",\"id\":\"${uuid}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"/vmess-argo\",\"tls\":\"tls\",\"sni\":\"${host}\",\"alpn\":\"\",\"fp\":\"\"}"
    b64=$(printf '%s' "$json" | base64 -w0 2>/dev/null || printf '%s' "$json" | base64 | tr -d '\n')
    printf '%s' "vmess://${b64}"
}

gen_vless_link() {
    local uuid="$1" host="$2" addr="${3:-$(get_cdn)}" port="${4:-$(get_cdn_port)}" remark="${5:-${NODE_NAME}-VLESS}"
    printf '%s' "vless://${uuid}@${addr}:${port}?encryption=none&security=tls&sni=${host}&type=ws&host=${host}&path=%2Fvless-argo%3Fed%3D2560#${remark// /%20}"
}

show_qr() {
    local text="$1" qr="${WORK_DIR}/qrencode"
    if [ ! -f "$qr" ]; then yellow_msg "QR 工具未安装，仅显示链接"; return 1; fi
    chmod +x "$qr" 2>/dev/null
    echo ""
    "$qr" -t ANSIUTF8 -m 1 -s 2 "$text" 2>/dev/null || yellow_msg "QR 生成失败"
}

install_qrencode() {
    local qr="${WORK_DIR}/qrencode"; [ -f "$qr" ] && return 0
    local arch
    case "$(uname -m)" in x86_64) arch="amd64" ;; aarch64|arm64) arch="arm64" ;; *) return 1 ;; esac
    curl -sLo "$qr" "https://github.com/eooce/test/releases/download/${arch}/qrencode-linux-${arch}" 2>/dev/null
    chmod +x "$qr" 2>/dev/null
}

#==============================================================================
# 服务状态
#==============================================================================
get_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        XRAY_ST="${green}● 运行中${re}"; XRAY_RAW="running"
    else
        XRAY_ST="${red}○ 已停止${re}"; XRAY_RAW="stopped"
    fi
    if systemctl is-active --quiet tunnel 2>/dev/null; then
        TUNNEL_ST="${green}● 运行中${re}"; TUNNEL_RAW="running"
    else
        TUNNEL_ST="${red}○ 已停止${re}"; TUNNEL_RAW="stopped"
    fi
}

#==============================================================================
# 查看节点
#==============================================================================
show_node() {
    clear
    [ ! -f "$CONFIG_FILE" ] && { red_msg "未检测到安装，请先执行一键安装！"; return; }

    load_conf
    local uuid host_domain cdn_addr cdn_port
    uuid=$(get_uuid)
    host_domain=$(get_argo_domain)
    cdn_addr=$(get_cdn)
    cdn_port=$(get_cdn_port)
    [ -z "$host_domain" ] && { yellow_msg "  ⚠ Argo 隧道未运行，正尝试获取域名..."; sleep 3; host_domain=$(get_argo_domain); }

    echo ""
    echo -e "${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e "${purple}║${re}       ${white}ArgoX-Mini · ${NODE_NAME}${re}"
    echo -e "${purple}║${re}       ${cyan}节点连接参数${re}"
    echo -e "${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${cyan}节点名称${re}  : ${white}${NODE_NAME}${re}"
    echo -e "  ${cyan}优选地址${re}  : ${green}${cdn_addr}${re}"
    echo -e "  ${cyan}端口${re}      : ${green}${cdn_port}${re}  ${yellow}(Cloudflare 边缘)${re}"
    echo -e "  ${cyan}用户 ID${re}   : ${purple}${uuid}${re}"
    [ -n "$host_domain" ] && echo -e "  ${cyan}伪装域名${re}  : ${green}${host_domain}${re}"
    [ "$ARGO_MODE" != "temp" ] && echo -e "  ${cyan}隧道类型${re}  : ${yellow}固定隧道${re}"
    echo ""

    if [ -n "$host_domain" ]; then
        local vless_link vmess_link
        vless_link=$(gen_vless_link "$uuid" "$host_domain" "$cdn_addr" "$cdn_port")
        vmess_link=$(gen_vmess_link "$uuid" "$host_domain" "$cdn_addr" "$cdn_port")

        echo -e "  ${yellow}━━━ ① VLESS + WS + Argo ━━━${re}"
        echo -e "  ${green}${vless_link}${re}"
        echo ""
        echo -e "  ${yellow}━━━ ② VMess + WS + Argo ━━━${re}"
        echo -e "  ${green}${vmess_link}${re}"
        echo ""
        show_qr "$vless_link"
    fi
    echo ""
    echo -e "  ${yellow}💡${re} 复制链接 → v2rayN/Nekoray/小火箭 → 导入剪贴板"
    echo -e "  ${yellow}💡${re} 菜单 2 切换优选线路 | 菜单 3 修改配置"
}

#==============================================================================
# 服务控制
#==============================================================================
start_services() {
    yellow_msg "正在启动服务..."
    systemctl start xray 2>/dev/null; systemctl start tunnel 2>/dev/null; sleep 2
    get_status
    echo -e "  Xray : ${XRAY_ST}    Argo : ${TUNNEL_ST}"
    green_msg "服务启动完成！"
}
stop_services() {
    yellow_msg "正在停止服务..."
    systemctl stop xray 2>/dev/null; systemctl stop tunnel 2>/dev/null; sleep 1
    get_status
    echo -e "  Xray : ${XRAY_ST}    Argo : ${TUNNEL_ST}"
    red_msg "服务已完全停止。"
}
restart_services() {
    yellow_msg "正在重启服务并刷新隧道..."
    rm -f "$TUNNEL_LOG"
    systemctl restart xray 2>/dev/null; systemctl restart tunnel 2>/dev/null; sleep 3
    get_status
    local new_domain; new_domain=$(get_argo_domain)
    echo -e "  Xray : ${XRAY_ST}    Argo : ${TUNNEL_ST}"
    green_msg "重启成功！"
    [ -n "$new_domain" ] && echo -e "  新域名: ${purple}${new_domain}${re}"
}

#==============================================================================
# 优选域名菜单
#==============================================================================
edit_cdn() {
    load_conf
    while true; do
        clear
        local cur_cdn cur_port
        cur_cdn=$(get_cdn); cur_port=$(get_cdn_port)
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
        echo -e "  ${cyan}c${re}. 自定义地址（支持 host:port）"
        echo -e "  ${cyan}p${re}. 仅修改端口"
        echo -e "  ${red}0${re}. 返回"
        echo ""
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择: " cdn_choice
        local new_port="$cur_port"
        case "$cdn_choice" in
            1)  CDN_DOMAIN="cdn.31514926.xyz" ;;
            2)  CDN_DOMAIN="skk.moe" ;;
            3)  CDN_DOMAIN="ip.sb" ;;
            4)  CDN_DOMAIN="time.is" ;;
            5)  CDN_DOMAIN="bestcf.top" ;;
            6)  CDN_DOMAIN="cfip.xxxxxxxx.tk" ;;
            7)  CDN_DOMAIN="cf.090227.xyz" ;;
            8)  CDN_DOMAIN="yidong.19931101.xyz" ;;
            9)  CDN_DOMAIN="liantong.19931101.xyz" ;;
            10) CDN_DOMAIN="dianxin.19931101.xyz" ;;
            11) CDN_DOMAIN="cdn.2020111.xyz" ;;
            12) CDN_DOMAIN="xn--b6gac.eu.org" ;;
            13) CDN_DOMAIN="cdns.doon.eu.org" ;;
            c|C)
                read -p "  输入地址 (host:port): " raw
                if [[ "$raw" =~ ^(.+):([0-9]+)$ ]]; then
                    CDN_DOMAIN="${BASH_REMATCH[1]}"; new_port="${BASH_REMATCH[2]}"
                else
                    CDN_DOMAIN="$raw"
                fi ;;
            p|P) read -p "  输入新端口: " new_port; CDN_DOMAIN="$cur_cdn" ;;
            0) return ;;
            *) red_msg "无效输入。"; sleep 1; continue ;;
        esac
        if [ -n "$CDN_DOMAIN" ]; then
            CDN_PORT="$new_port"
            jq --arg cdn "$CDN_DOMAIN" --argjson port "$CDN_PORT" \
               '.current_cdn = $cdn | .current_cdn_port = $port' \
               "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            save_conf
            echo ""; green_msg "切换成功！"
            echo -e "  ${purple}${CDN_DOMAIN}:${CDN_PORT}${re}"
            yellow_msg "  💡 客户端修改 Address/Port 即可，无需重启服务端"
            break
        fi
    done
}

#==============================================================================
# 修改配置菜单
#==============================================================================
change_config() {
    load_conf
    while true; do
        clear
        [ ! -f "$CONFIG_FILE" ] && { red_msg "请先安装！"; return; }
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}          ${white}节点配置修改${re}                    ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  ${green}1${re}. 修改节点名称 — ${cyan}${NODE_NAME}${re}"
        echo -e "  ${green}2${re}. 更换 UUID"
        echo -e "  ${green}3${re}. 修改内部端口 (当前 ${cyan}${ARGO_PORT}/${VLESS_WS_PORT}/${VMESS_WS_PORT}${re})"
        echo -e "  ${green}4${re}. 查看当前节点链接"
        echo -e "  ${green}5${re}. 切换 Argo 隧道类型 — ${cyan}$([ "$ARGO_MODE" = "temp" ] && echo "临时隧道" || echo "固定隧道")${re}"
        echo -e "  ${green}6${re}. 刷新临时域名"
        echo -e "  ${red}0${re}. 返回主菜单"
        echo ""
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择 (0-6): " cfg_choice
        case "$cfg_choice" in
            1)
                local old_name="$NODE_NAME"
                read -p "  新节点名称 (回车保持「${NODE_NAME}」): " new_name
                [ -n "$new_name" ] && NODE_NAME="$new_name"
                save_conf
                green_msg "节点名称已更新: ${old_name} → ${NODE_NAME}"
                ;;
            2)
                local new_uuid
                read -p "  新 UUID (回车自动生成): " new_uuid
                [ -z "$new_uuid" ] && new_uuid=$(cat /proc/sys/kernel/random/uuid)
                jq --arg u "$new_uuid" \
                   '.inbounds[0].settings.clients[0].id = $u | .inbounds[1].settings.clients[0].id = $u | .inbounds[2].settings.clients[0].id = $u' \
                   "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                UUID_CUSTOM="$new_uuid"; save_conf
                systemctl restart xray 2>/dev/null
                green_msg "UUID 已更新（双协议同步）！"
                echo -e "  ${purple}${new_uuid}${re}"
                ;;
            3)
                echo ""
                yellow_msg "当前内部端口（仅 127.0.0.1 监听，不对外暴露）："
                echo -e "  Argo 入口 : ${cyan}${ARGO_PORT}${re}"
                echo -e "  VLESS WS  : ${cyan}${VLESS_WS_PORT}${re}"
                echo -e "  VMess WS  : ${cyan}${VMESS_WS_PORT}${re}"
                echo ""
                echo -ne "  ${yellow}修改? 需重装生效。按回车返回...${re}"
                read -r
                ;;
            4) show_node ;;
            5) switch_argo_tunnel ;;
            6) restart_services ;;
            0) return ;;
            *) red_msg "无效选项" ;;
        esac
        read -p "  按回车键继续..." -r
    done
}

#==============================================================================
# Argo 隧道切换（临时 ↔ 固定 token）
#==============================================================================
switch_argo_tunnel() {
    load_conf
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}切换 Argo 隧道类型${re}                   ${purple}║${re}"
    echo -e " ${purple}║${re}       ${yellow}当前: $([ "$ARGO_MODE" = "temp" ] && echo "临时隧道" || echo "固定隧道")${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${green}1${re}. 临时隧道（随机 .trycloudflare.com 域名）"
    echo -e "  ${green}2${re}. 固定隧道（Token 方式，需先在 CF 后台创建）"
    echo -e "  ${red}0${re}. 返回"
    echo ""
    read -p "  请选择: " argo_choice
    case "$argo_choice" in
        1)
            ARGO_MODE="temp"; ARGO_AUTH=""; ARGO_FIXED_DOMAIN=""
            save_conf
            # 重建 tunnel 服务为临时模式
            rebuild_tunnel_service "temp"
            restart_services
            ;;
        2)
            read -p "  输入 Argo 固定域名 (如 mynode.example.com): " ARGO_FIXED_DOMAIN
            read -p "  输入 Argo Token (从 CF Zero Trust 获取): " ARGO_AUTH
            [ -z "$ARGO_FIXED_DOMAIN" ] || [ -z "$ARGO_AUTH" ] && { red_msg "域名和 Token 不能为空"; return; }
            ARGO_MODE="fixed-token"
            save_conf
            rebuild_tunnel_service "fixed-token"
            restart_services
            green_msg "已切换到固定隧道模式！域名: ${ARGO_FIXED_DOMAIN}"
            ;;
        0) return ;;
        *) red_msg "无效选项" ;;
    esac
}

rebuild_tunnel_service() {
    local mode="$1"
    if [ "$mode" = "fixed-token" ]; then
        cat > /etc/systemd/system/tunnel.service << SERVICETUN
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
SERVICETUN
    else
        cat > /etc/systemd/system/tunnel.service << SERVICETUN
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
SERVICETUN
    fi
    systemctl daemon-reload
}

#==============================================================================
# 交互式安装流程
#==============================================================================
interactive_install() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}  ${white}ArgoX-Mini · 交互式安装向导${re}              ${purple}║${re}"
    echo -e " ${purple}║${re}  ${cyan}VLESS + VMess 双协议  |  WS + TLS + Argo${re}  ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    yellow_msg "按提示一步步配置，回车使用默认值即可快速安装。"
    echo ""

    # --- 1. 节点名称 ---
    echo -e " ${white}━━━ ① 节点名称 ━━━${re}"
    echo -e "  ${yellow}此名称显示在客户端的节点列表里，方便区分多台 VPS。${re}"
    echo ""
    read -p "  节点名称 [${NODE_NAME}]: " input
    [ -n "$input" ] && NODE_NAME="$input"
    echo -e "  → ${green}${NODE_NAME}${re}"
    echo ""

    # --- 2. CDN 优选地址 ---
    echo -e " ${white}━━━ ② CDN 优选地址 ━━━${re}"
    echo -e "  ${yellow}选择客户端连接的 CF 边缘 IP/域名。${re}"
    echo ""
    echo -e "  ${green}1${re}. 默认 ${CDN_DEFAULT} (三网通用)"
    echo -e "  ${green}2${re}. 从优选列表中选择"
    echo -e "  ${green}3${re}. 自定义"
    echo ""
    read -p "  请选择 [1]: " cdn_type
    case "${cdn_type:-1}" in
        2)
            echo ""
            for key in 1 2 3 4 5 6 7 8 9 10 11 12 13; do echo -e "  ${green}${key}${re}. ${CDN_DOMAINS[$key]}"; done
            echo ""
            read -p "  选择序号 [1]: " cdn_idx
            case "${cdn_idx:-1}" in
                1)  CDN_DOMAIN="cdn.31514926.xyz" ;; 2) CDN_DOMAIN="skk.moe" ;;
                3)  CDN_DOMAIN="ip.sb" ;;           4) CDN_DOMAIN="time.is" ;;
                5)  CDN_DOMAIN="bestcf.top" ;;      6) CDN_DOMAIN="cfip.xxxxxxxx.tk" ;;
                7)  CDN_DOMAIN="cf.090227.xyz" ;;   8) CDN_DOMAIN="yidong.19931101.xyz" ;;
                9)  CDN_DOMAIN="liantong.19931101.xyz" ;; 10) CDN_DOMAIN="dianxin.19931101.xyz" ;;
                11) CDN_DOMAIN="cdn.2020111.xyz" ;; 12) CDN_DOMAIN="xn--b6gac.eu.org" ;;
                13) CDN_DOMAIN="cdns.doon.eu.org" ;; *) CDN_DOMAIN="$CDN_DEFAULT" ;;
            esac ;;
        3) read -p "  输入自定义地址: " CDN_DOMAIN; [ -z "$CDN_DOMAIN" ] && CDN_DOMAIN="$CDN_DEFAULT" ;;
    esac
    echo -e "  → ${green}${CDN_DOMAIN}${re}"
    echo ""

    # --- 3. CDN 端口 ---
    echo -e " ${white}━━━ ③ 客户端端口 ━━━${re}"
    echo -e "  ${yellow}Cloudflare 支持的 HTTPS 端口: 443, 8443, 2053, 2083, 2087, 2096${re}"
    echo ""
    read -p "  端口 [${CDN_PORT}]: " input
    [ -n "$input" ] && CDN_PORT="$input"
    echo -e "  → ${green}${CDN_PORT}${re}"
    echo ""

    # --- 4. UUID ---
    echo -e " ${white}━━━ ④ 用户 ID (UUID) ━━━${re}"
    echo -e "  ${yellow}留空自动生成随机 UUID。${re}"
    echo ""
    read -p "  UUID [自动生成]: " input
    [ -n "$input" ] && UUID_CUSTOM="$input"
    echo ""

    # --- 5. Argo 隧道类型 ---
    echo -e " ${white}━━━ ⑤ Argo 隧道类型 ━━━${re}"
    echo -e "  ${green}1${re}. 临时隧道 (随机 .trycloudflare.com 域名，推荐)"
    echo -e "  ${green}2${re}. 固定隧道 (需先在 CF Zero Trust 创建 Token)"
    echo ""
    read -p "  请选择 [1]: " tunnel_type
    case "${tunnel_type:-1}" in
        2)
            read -p "  输入固定域名: " ARGO_FIXED_DOMAIN
            read -p "  输入 Argo Token: " ARGO_AUTH
            [ -n "$ARGO_FIXED_DOMAIN" ] && [ -n "$ARGO_AUTH" ] && ARGO_MODE="fixed-token" ;;
    esac
    echo ""

    # --- 6. 内部端口 ---
    echo -e " ${white}━━━ ⑥ 内部端口 ━━━${re}"
    echo -e "  ${yellow}仅 127.0.0.1 监听，不对外暴露。一般无需修改。${re}"
    echo -e "  ${cyan}Argo入口:${ARGO_PORT}  VLESS:${VLESS_WS_PORT}  VMess:${VMESS_WS_PORT}${re}"
    echo ""
    read -p "  修改? 输入新起始端口 (如 9000) 或回车跳过: " base_port
    if [ -n "$base_port" ]; then
        ARGO_PORT="$base_port"
        VLESS_WS_PORT=$((base_port + 1))
        VMESS_WS_PORT=$((base_port + 2))
        echo -e "  → Argo:${ARGO_PORT}  VLESS:${VLESS_WS_PORT}  VMess:${VMESS_WS_PORT}"
    fi
    echo ""

    # --- 确认 ---
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo -e " ${white}配置确认：${re}"
    echo -e "  节点名称 : ${green}${NODE_NAME}${re}"
    echo -e "  CDN 地址 : ${green}${CDN_DOMAIN}:${CDN_PORT}${re}"
    echo -e "  UUID     : ${cyan}$([ -n "$UUID_CUSTOM" ] && echo "$UUID_CUSTOM" || echo "自动生成")${re}"
    echo -e "  隧道类型 : ${cyan}$([ "$ARGO_MODE" = "fixed-token" ] && echo "固定隧道 ${ARGO_FIXED_DOMAIN}" || echo "临时隧道")${re}"
    echo -e "  内部端口 : ${cyan}${ARGO_PORT}/${VLESS_WS_PORT}/${VMESS_WS_PORT}${re}"
    echo -e " ${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${re}"
    echo ""
    read -p "  ${yellow}确认开始安装? (y/n) [y]: ${re}" confirm
    [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && { yellow_msg "已取消。"; return; }

    save_conf
    do_install
}

#==============================================================================
# 实际安装
#==============================================================================
do_install() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}   ${white}ArgoX-Mini · 正在部署...${re}                  ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    yellow_msg "[1/6] 清理冲突组件..."
    pkill -9 nginx caddy xray argo 2>/dev/null
    systemctl stop nginx caddy xray tunnel 2>/dev/null
    systemctl disable nginx caddy 2>/dev/null
    green_msg "  完成"

    yellow_msg "[2/6] 安装依赖..."
    if command -v apt &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof
    elif command -v yum &>/dev/null; then
        yum install -y -q jq unzip curl lsof
    elif command -v dnf &>/dev/null; then
        dnf install -y -q jq unzip curl lsof
    fi
    green_msg "  完成"

    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG CLOUDFLARED_ARCH
    ARCH_ARG=$(detect_arch); CLOUDFLARED_ARCH=$(cloudflared_arch)
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/6] 下载 Xray + cloudflared..."
    curl -sLo "${WORK_DIR}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${WORK_DIR}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR" > /dev/null 2>&1
    chmod +x "${WORK_DIR}/xray" "${WORK_DIR}/argo"
    rm -f "${WORK_DIR}/xray.zip"
    install_qrencode
    green_msg "  完成"

    yellow_msg "[4/6] 检测端口并生成配置..."
    # 端口冲突检测
    port_in_use "$ARGO_PORT" && ARGO_PORT=$(find_free_port "$ARGO_PORT")
    port_in_use "$VLESS_WS_PORT" && VLESS_WS_PORT=$(find_free_port "$VLESS_WS_PORT")
    port_in_use "$VMESS_WS_PORT" && VMESS_WS_PORT=$(find_free_port "$VMESS_WS_PORT")

    local UUID; UUID="${UUID_CUSTOM:-$(cat /proc/sys/kernel/random/uuid)}"

    cat > "$CONFIG_FILE" << XRAYCONF
{
  "current_cdn": "${CDN_DOMAIN}",
  "current_cdn_port": ${CDN_PORT},
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    {
      "port": ${ARGO_PORT},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "tag": "argo-in",
      "settings": {
        "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
        "decryption": "none",
        "fallbacks": [
          { "path": "/vmess-argo", "dest": ${VMESS_WS_PORT} },
          { "path": "/vless-argo", "dest": ${VLESS_WS_PORT} }
        ]
      },
      "streamSettings": { "network": "tcp" }
    },
    {
      "port": ${VLESS_WS_PORT},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "tag": "vless-ws",
      "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" },
      "streamSettings": {
        "network": "ws", "security": "none",
        "wsSettings": { "path": "/vless-argo" }
      }
    },
    {
      "port": ${VMESS_WS_PORT},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "tag": "vmess-ws",
      "settings": { "clients": [{ "id": "$UUID", "alterId": 0 }] },
      "streamSettings": {
        "network": "ws", "security": "none",
        "wsSettings": { "path": "/vmess-argo" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
XRAYCONF

    cat > /etc/systemd/system/xray.service << SERVICEXRAY
[Unit]
Description=Xray Service
After=network.target
[Service]
Type=simple
ExecStart=${WORK_DIR}/xray -c ${CONFIG_FILE}
Restart=on-failure
[Install]
WantedBy=multi-user.target
SERVICEXRAY

    rebuild_tunnel_service "$ARGO_MODE"

    yellow_msg "[5/6] 启动服务..."
    rm -f "$TUNNEL_LOG"
    systemctl daemon-reload
    systemctl enable xray tunnel 2>/dev/null
    systemctl restart xray tunnel
    green_msg "  完成"

    yellow_msg "[6/6] 等待 Cloudflare 握手..."
    sleep 5

    # 快捷指令
    cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
ARGOWRAP
    chmod +x "$SCRIPT_PATH"
    save_conf   # 确保最新状态写入

    # --- 输出结果 ---
    local host_domain; host_domain=$(get_argo_domain)
    [ "$ARGO_MODE" = "fixed-token" ] && host_domain="$ARGO_FIXED_DOMAIN"
    [ -z "$host_domain" ] && [ "$ARGO_MODE" != "fixed-token" ] && { sleep 3; host_domain=$(get_argo_domain); }

    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}🎉 部署成功 · ${NODE_NAME}${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${cyan}节点名称${re}: ${white}${NODE_NAME}${re}"
    echo -e "  ${cyan}快捷管理${re}: ${green}argov${re}"
    echo -e "  ${cyan}优选地址${re}: ${green}${CDN_DOMAIN}:${CDN_PORT}${re}"
    echo -e "  ${cyan}用户 ID${re}: ${purple}${UUID}${re}"
    [ -n "$host_domain" ] && echo -e "  ${cyan}伪装域名${re}: ${green}${host_domain}${re}"
    echo ""

    if [ -n "$host_domain" ]; then
        local vless_link vmess_link
        vless_link=$(gen_vless_link "$UUID" "$host_domain" "$CDN_DOMAIN" "$CDN_PORT")
        vmess_link=$(gen_vmess_link "$UUID" "$host_domain" "$CDN_DOMAIN" "$CDN_PORT")

        echo -e "  ${yellow}━━━ VLESS + WS + Argo ━━━${re}"
        echo -e "  ${green}${vless_link}${re}"
        echo ""
        echo -e "  ${yellow}━━━ VMess + WS + Argo ━━━${re}"
        echo -e "  ${green}${vmess_link}${re}"
        echo ""
        show_qr "$vless_link"
    fi

    echo ""
    echo -e "  ${yellow}📋${re} 管理面板: ${green}argov${re}"
    echo -e "  ${yellow}💡${re} 复制链接 → 客户端 → 导入剪贴板"
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
        echo -e " ${purple}║${re}     ${cyan}VLESS + VMess 双协议  |  WS + TLS + Argo${re}     ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  节点名称 : ${white}${NODE_NAME}${re}"
        echo -e "  Xray     : ${XRAY_ST}     Argo : ${TUNNEL_ST}"
        echo -e "  UUID     : ${cyan}${uuid_short}${re}"
        [ -n "$argo_domain" ] && echo -e "  域名     : ${green}${argo_domain}${re}"
        echo -e "  CDN      : ${green}$(get_cdn):$(get_cdn_port)${re}"
        echo ""
        echo -e " ${purple}───────────────── 节点管理 ─────────────────${re}"
        echo -e "  ${green}1${re}. 查看节点链接 (VLESS + VMess)"
        echo -e "  ${green}2${re}. 更换优选域名 / 线路"
        echo -e "  ${green}3${re}. 修改配置 (名称 / UUID / 隧道 / 端口)"
        echo ""
        echo -e " ${purple}───────────────── 服务控制 ─────────────────${re}"
        echo -e "  ${green}4${re}. 启动 服务"
        echo -e "  ${red}5${re}. 停止 服务"
        echo -e "  ${yellow}6${re}. 重启 服务 (刷新域名)"
        echo ""
        echo -e " ${purple}───────────────── 系统维护 ─────────────────${re}"
        echo -e "  ${yellow}7${re}. 重新安装 (保留配置)"
        echo -e "  ${red}8${re}. 完全卸载"
        echo ""
        echo -e "  ${cyan}0${re}. 退出"
        echo ""
        echo -e " ${purple}────────────────────────────────────────────${re}"
        read -p "  请输入选项 (0-8): " menu_input

        case "$menu_input" in
            1) show_node; read -p "  按回车键返回..." -r ;;
            2) edit_cdn; read -p "  按回车键返回..." -r ;;
            3) change_config ;;
            4) start_services; sleep 1 ;;
            5) stop_services; sleep 1 ;;
            6) restart_services; sleep 1 ;;
            7)
                echo -ne "  ${yellow}重新安装? 将保留当前配置 (y/n): ${re}"
                read confirm
                [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && { load_conf; do_install; }
                read -p "  按回车键返回..." -r ;;
            8)
                echo -ne "  ${red}⚠ 确定完全卸载? (y/n): ${re}"
                read confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    systemctl stop xray tunnel 2>/dev/null
                    systemctl disable xray tunnel 2>/dev/null
                    rm -rf "$WORK_DIR"
                    rm -f /etc/systemd/system/xray.service /etc/systemd/system/tunnel.service "$SCRIPT_PATH"
                    systemctl daemon-reload
                    green_msg "卸载完成。再见！"
                    exit 0
                fi ;;
            0) clear; exit 0 ;;
            *) red_msg "无效选项 (0-8)"; sleep 1 ;;
        esac
    done
}

#==============================================================================
# 入口
#==============================================================================
load_conf
[ ! -f "$CONFIG_FILE" ] && { interactive_install; exit 0; }
main_menu
