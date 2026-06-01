#!/usr/bin/env bash
#==============================================================================
# ArgoX-Mini — 纯 Argo 隧道双协议一键管理脚本
# VLESS + VMess  |  WebSocket + TLS  |  Cloudflare Argo Tunnel
# 纯净 · 零公网暴露 · 无 Caddy/Nginx · 无 Reality/XHTTP
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
TUNNEL_LOG="/etc/xray/argo.log"
WORK_DIR="/etc/xray"
SCRIPT_PATH="/usr/bin/argov"
ARGO_PORT="8080"        # Argo 隧道入口端口
VLESS_WS_PORT="8081"    # VLESS + WS 内部端口
VMESS_WS_PORT="8082"    # VMess + WS 内部端口
CDN_DEFAULT="cdn.31514926.xyz"

# --- 优选域名池（合并自 ArgoX + xray-2go 参考项目） ---
# 格式: 序号=域名 (分类|说明)
declare -A CDN_DOMAINS
# ---- 三网通用 ----
CDN_DOMAINS[1]="cdn.31514926.xyz (三网通用)"
CDN_DOMAINS[2]="skk.moe (三网通用·泛用测速)"
CDN_DOMAINS[3]="ip.sb (三网通用·IP检测站)"
CDN_DOMAINS[4]="time.is (三网通用·时间站)"
CDN_DOMAINS[5]="bestcf.top (三网通用·优选站)"
CDN_DOMAINS[6]="cfip.xxxxxxxx.tk (三网通用)"
CDN_DOMAINS[7]="cf.090227.xyz (三网通用)"
# ---- 运营商专线 ----
CDN_DOMAINS[8]="yidong.19931101.xyz (移动专线)"
CDN_DOMAINS[9]="liantong.19931101.xyz (联通专线)"
CDN_DOMAINS[10]="dianxin.19931101.xyz (电信专线)"
# ---- 其他优选 ----
CDN_DOMAINS[11]="cdn.2020111.xyz (综合优选)"
CDN_DOMAINS[12]="xn--b6gac.eu.org (综合优选·中东)"
CDN_DOMAINS[13]="cdns.doon.eu.org (综合优选·Doorn)"

#==============================================================================
# 工具函数
#==============================================================================

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

# 获取 UUID
get_uuid() {
    jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE" 2>/dev/null
}

# 获取当前 CDN 地址
get_cdn() {
    [ -f "$CONFIG_FILE" ] && jq -r '.current_cdn // empty' "$CONFIG_FILE" 2>/dev/null || echo "$CDN_DEFAULT"
}

# VMess 链接 (base64 JSON)
gen_vmess_link() {
    local uuid="$1" host="$2" addr="${3:-$CDN_DEFAULT}" port="${4:-443}" remark="${5:-ArgoX-Mini-VMess}"
    local json b64
    json="{\"v\":\"2\",\"ps\":\"${remark}\",\"add\":\"${addr}\",\"port\":\"${port}\",\"id\":\"${uuid}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"/vmess-argo\",\"tls\":\"tls\",\"sni\":\"${host}\",\"alpn\":\"\",\"fp\":\"\"}"
    b64=$(printf '%s' "$json" | base64 -w0 2>/dev/null || printf '%s' "$json" | base64 | tr -d '\n')
    printf '%s' "vmess://${b64}"
}

# VLESS 链接
gen_vless_link() {
    local uuid="$1" host="$2" addr="${3:-$CDN_DEFAULT}" port="${4:-443}" remark="${5:-ArgoX-Mini-VLESS}"
    printf '%s' "vless://${uuid}@${addr}:${port}?encryption=none&security=tls&sni=${host}&type=ws&host=${host}&path=%2Fvless-argo%3Fed%3D2560#${remark// /%20}"
}

# QR 码
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

detect_arch() {
    case "$(uname -m)" in
        x86_64)      echo "64" ;;
        i686|i386)   echo "32" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l)      echo "arm32-v7a" ;;
        *)           echo "" ;;
    esac
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
# 1. 查看节点信息（双协议 + 链接 + QR）
#==============================================================================
show_node() {
    clear
    [ ! -f "$CONFIG_FILE" ] && { red_msg "未检测到安装，请先执行一键安装！"; return; }

    local uuid host_domain cdn_addr
    uuid=$(get_uuid)
    host_domain=$(get_argo_domain)
    cdn_addr=$(get_cdn)

    echo ""
    echo -e "${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e "${purple}║${re}          ${white}ArgoX-Mini · 节点连接参数${re}               ${purple}║${re}"
    echo -e "${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    [ -z "$host_domain" ] && { yellow_msg "  ⚠ 正在获取 Cloudflare 临时域名..."; sleep 2; host_domain=$(get_argo_domain); }

    echo -e "  ${cyan}优选地址${re}  : ${green}${cdn_addr}${re}"
    echo -e "  ${cyan}端口${re}      : 443"
    echo -e "  ${cyan}用户 ID${re}   : ${purple}${uuid}${re}"
    echo -e "  ${cyan}伪装域名${re}  : ${green}${host_domain}${re}"
    echo ""

    if [ -n "$host_domain" ]; then
        local vless_link vmess_link
        vless_link=$(gen_vless_link "$uuid" "$host_domain" "$cdn_addr")
        vmess_link=$(gen_vmess_link "$uuid" "$host_domain" "$cdn_addr")

        # VLESS
        echo -e "  ${yellow}━━━━━ ① VLESS + WS + Argo 链接 ━━━━━${re}"
        echo ""
        echo -e "  ${green}${vless_link}${re}"
        echo ""
        echo -e "  ${cyan}传输${re}: ws  |  ${cyan}路径${re}: /vless-argo  |  ${cyan}TLS${re}: tls  |  ${cyan}加密${re}: none"
        echo ""

        # VMess
        echo -e "  ${yellow}━━━━━ ② VMess + WS + Argo 链接 ━━━━━${re}"
        echo ""
        echo -e "  ${green}${vmess_link}${re}"
        echo ""
        echo -e "  ${cyan}传输${re}: ws  |  ${cyan}路径${re}: /vmess-argo  |  ${cyan}TLS${re}: tls  |  ${cyan}加密${re}: none  |  ${cyan}alterId${re}: 0"
        echo ""

        # QR
        show_qr "$vless_link"
    fi

    echo ""
    echo -e "  ${yellow}💡 提示${re}: 复制 VLESS 或 VMess 链接 → v2rayN/Nekoray/小火箭 → 导入剪贴板"
    echo -e "  ${yellow}💡 提示${re}: 菜单 2 可切换三网优选线路"
}

#==============================================================================
# 2/3/4. 服务控制
#==============================================================================
start_services() {
    yellow_msg "正在启动服务..."
    systemctl start xray 2>/dev/null; systemctl start tunnel 2>/dev/null; sleep 2
    get_status
    echo -e "  Xray 内核: ${XRAY_ST}"; echo -e "  Argo 隧道: ${TUNNEL_ST}"
    green_msg "服务启动完成！"
}
stop_services() {
    yellow_msg "正在停止服务..."
    systemctl stop xray 2>/dev/null; systemctl stop tunnel 2>/dev/null; sleep 1
    get_status
    echo -e "  Xray 内核: ${XRAY_ST}"; echo -e "  Argo 隧道: ${TUNNEL_ST}"
    red_msg "服务已完全停止。"
}
restart_services() {
    yellow_msg "正在重启服务并刷新隧道域名..."
    rm -f "$TUNNEL_LOG"
    systemctl restart xray 2>/dev/null; systemctl restart tunnel 2>/dev/null; sleep 3
    get_status
    local new_domain
    new_domain=$(get_argo_domain)
    echo -e "  Xray 内核: ${XRAY_ST}"; echo -e "  Argo 隧道: ${TUNNEL_ST}"
    green_msg "重启成功！"
    [ -n "$new_domain" ] && echo -e "  新临时域名: ${purple}${new_domain}${re}"
}

#==============================================================================
# 5. 优选域名
#==============================================================================
edit_cdn() {
    while true; do
        clear
        local current_cdn; current_cdn=$(get_cdn)
        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}       ${white}快捷更换优选域名 / 线路${re}             ${purple}║${re}"
        echo -e " ${purple}║${re}       ${yellow}当前: ${green}${current_cdn}${re}"
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
        echo -e "  ${cyan}c${re}. 输入自定义优选域名或 IP"
        echo -e "  ${red}0${re}. 返回主菜单"
        echo ""
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  请选择 (1-13 / c / 0): " cdn_choice

        case "$cdn_choice" in
            1) SELECTED_CDN="cdn.31514926.xyz" ;;
            2) SELECTED_CDN="skk.moe" ;;
            3) SELECTED_CDN="ip.sb" ;;
            4) SELECTED_CDN="time.is" ;;
            5) SELECTED_CDN="bestcf.top" ;;
            6) SELECTED_CDN="cfip.xxxxxxxx.tk" ;;
            7) SELECTED_CDN="cf.090227.xyz" ;;
            8) SELECTED_CDN="yidong.19931101.xyz" ;;
            9) SELECTED_CDN="liantong.19931101.xyz" ;;
            10) SELECTED_CDN="dianxin.19931101.xyz" ;;
            11) SELECTED_CDN="cdn.2020111.xyz" ;;
            12) SELECTED_CDN="xn--b6gac.eu.org" ;;
            13) SELECTED_CDN="cdns.doon.eu.org" ;;
            c|C) read -p "  请输入自定义 Cloudflare 优选域名或 IP: " SELECTED_CDN ;;
            0) return ;;
            *) red_msg "无效输入。"; sleep 1; continue ;;
        esac

        if [ -n "$SELECTED_CDN" ]; then
            jq --arg cdn "$SELECTED_CDN" '.current_cdn = $cdn' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            echo ""
            green_msg "线路切换成功！"
            echo -e "  新接入地址: ${purple}${SELECTED_CDN}${re}"
            yellow_msg "  💡 无需重启服务端，在客户端修改 Address 即可生效"
            break
        fi
    done
}

#==============================================================================
# 6. 修改配置
#==============================================================================
change_config() {
    clear
    [ ! -f "$CONFIG_FILE" ] && { red_msg "请先安装！"; return; }
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}          ${white}节点配置修改${re}                    ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${green}1${re}. 更换 UUID（双协议同步更新）"
    echo -e "  ${green}2${re}. 查看当前节点链接"
    echo -e "  ${green}3${re}. 刷新 Argo 临时域名"
    echo -e "  ${red}0${re}. 返回主菜单"
    echo ""
    echo -e " ${purple}────────────────────────────────────────${re}"
    read -p "  请选择 (0-3): " cfg_choice
    case "$cfg_choice" in
        1)
            local new_uuid
            read -p "  输入新 UUID (回车随机生成): " new_uuid
            [ -z "$new_uuid" ] && new_uuid=$(cat /proc/sys/kernel/random/uuid)
            jq --arg u "$new_uuid" \
               '.inbounds[0].settings.clients[0].id = $u | .inbounds[1].settings.clients[0].id = $u | .inbounds[2].settings.clients[0].id = $u' \
               "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            systemctl restart xray 2>/dev/null
            green_msg "UUID 已更新（VLESS + VMess 同步生效）！"
            echo -e "  新 UUID: ${purple}${new_uuid}${re}"
            ;;
        2) show_node ;;
        3) restart_services ;;
        0) return ;;
        *) red_msg "无效选项" ;;
    esac
}

#==============================================================================
# 7. 一键安装（VLESS + VMess 双协议）
#==============================================================================
install_core() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}   ${white}ArgoX-Mini · VLESS + VMess 双协议部署${re}      ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    yellow_msg "[1/6] 清理冲突组件..."
    pkill -9 nginx caddy xray argo 2>/dev/null
    systemctl stop nginx caddy xray tunnel 2>/dev/null
    systemctl disable nginx caddy 2>/dev/null
    green_msg "  清理完成"

    yellow_msg "[2/6] 安装基础依赖..."
    if command -v apt &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof
    elif command -v yum &>/dev/null; then
        yum install -y -q jq unzip curl lsof
    elif command -v dnf &>/dev/null; then
        dnf install -y -q jq unzip curl lsof
    fi
    green_msg "  依赖安装完成"

    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG CLOUDFLARED_ARCH
    ARCH_ARG=$(detect_arch)
    case "$(uname -m)" in
        x86_64)       CLOUDFLARED_ARCH="amd64" ;;
        aarch64|arm64) CLOUDFLARED_ARCH="arm64" ;;
        armv7l)       CLOUDFLARED_ARCH="arm" ;;
        i686|i386)    CLOUDFLARED_ARCH="386" ;;
        *)            CLOUDFLARED_ARCH="amd64" ;;  # fallback
    esac
    [ -z "$ARCH_ARG" ] && { red_msg "不支持 CPU: $(uname -m)"; exit 1; }

    yellow_msg "[3/6] 下载 Xray 核心 & Cloudflare Tunnel..."
    curl -sLo "${WORK_DIR}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${WORK_DIR}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR" > /dev/null 2>&1
    chmod +x "${WORK_DIR}/xray" "${WORK_DIR}/argo"
    rm -f "${WORK_DIR}/xray.zip"
    install_qrencode
    green_msg "  核心下载完成"

    yellow_msg "[4/6] 生成双协议 Xray 配置 & 系统服务..."
    UUID=$(cat /proc/sys/kernel/random/uuid)

    # Xray 配置：入口 8080 VLESS TCP + fallback 分流 → 8081 VLESS WS / 8082 VMess WS
    cat > "$CONFIG_FILE" << XRAYCONF
{
  "current_cdn": "${CDN_DEFAULT}",
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
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vless-argo" }
      }
    },
    {
      "port": ${VMESS_WS_PORT},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "tag": "vmess-ws",
      "settings": {
        "clients": [{ "id": "$UUID", "alterId": 0 }]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
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

    cat > /etc/systemd/system/tunnel.service << SERVICETUN
[Unit]
Description=Cloudflare Argo Tunnel
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

    yellow_msg "[5/6] 启动后台服务..."
    rm -f "$TUNNEL_LOG"
    systemctl daemon-reload
    systemctl enable xray tunnel 2>/dev/null
    systemctl restart xray tunnel
    green_msg "  服务启动完成"

    yellow_msg "[6/6] 等待 Cloudflare 握手..."
    sleep 5

    # 写 argov wrapper（不能 cp $0，因为管道执行时 $0 是 bash）
    cat > "$SCRIPT_PATH" << 'ARGOWRAP'
#!/usr/bin/env bash
bash <(curl -Ls https://raw.githubusercontent.com/m2dumpling/ArgoX-Mini/main/argox_mini.sh)
ARGOWRAP
    chmod +x "$SCRIPT_PATH"
    green_msg "一键安装完成！"
    echo ""

    # --- 输出双协议链接 ---
    local host_domain; host_domain=$(get_argo_domain)
    [ -z "$host_domain" ] && { sleep 3; host_domain=$(get_argo_domain); }

    echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white}🎉 安装成功 · 双协议节点链接${re}               ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${cyan}快捷管理${re}: ${green}argov${re}"
    echo -e "  ${cyan}优选地址${re}: ${green}${CDN_DEFAULT}${re}"
    echo -e "  ${cyan}端口${re}    : 443"
    echo -e "  ${cyan}用户 ID${re} : ${purple}${UUID}${re}"
    echo -e "  ${cyan}伪装域名${re}: ${green}${host_domain}${re}"
    echo ""

    if [ -n "$host_domain" ]; then
        local vless_link vmess_link
        vless_link=$(gen_vless_link "$UUID" "$host_domain")
        vmess_link=$(gen_vmess_link "$UUID" "$host_domain")

        echo -e "  ${yellow}━━━ ① VLESS + WS + Argo ━━━${re}"
        echo -e "  ${green}${vless_link}${re}"
        echo ""
        echo -e "  ${yellow}━━━ ② VMess + WS + Argo ━━━${re}"
        echo -e "  ${green}${vmess_link}${re}"
        echo ""

        show_qr "$vless_link"
    fi

    echo ""
    echo -e "  ${yellow}📋 管理:${re} ${green}argov${re}"
    echo -e "  ${yellow}💡 导入:${re} 复制 VLESS 或 VMess 链接 → 客户端 → 导入剪贴板"
    echo -e "  ${yellow}💡 任何支持 VLESS/VMess + WS + TLS 的客户端均可使用${re}"
}

#==============================================================================
# 主菜单
#==============================================================================
main_menu() {
    while true; do
        get_status; clear

        local uuid_short="未安装" argo_domain=""
        [ -f "$CONFIG_FILE" ] && uuid_short="$(get_uuid | cut -c1-12)..."
        [ "$TUNNEL_RAW" = "running" ] && argo_domain=$(get_argo_domain)

        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white}ArgoX-Mini  纯净版隧道管理面板${re}              ${purple}║${re}"
        echo -e " ${purple}║${re}     ${cyan}VLESS + VMess 双协议  |  WS + TLS + Argo${re}     ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  Xray 内核 : ${XRAY_ST}     UUID : ${cyan}${uuid_short}${re}"
        echo -e "  Argo 隧道 : ${TUNNEL_ST}"
        [ -n "$argo_domain" ] && echo -e "  当前域名  : ${green}${argo_domain}${re}"
        echo ""
        echo -e " ${purple}───────────────── 节点管理 ─────────────────${re}"
        echo -e "  ${green}1${re}. 查看节点链接 (VLESS + VMess 双协议)"
        echo -e "  ${green}2${re}. 更换/选择分流优选域名"
        echo -e "  ${green}3${re}. 修改节点配置 (UUID / 刷新域名)"
        echo ""
        echo -e " ${purple}───────────────── 服务控制 ─────────────────${re}"
        echo -e "  ${green}4${re}. 启动 服务"
        echo -e "  ${red}5${re}. 停止 服务"
        echo -e "  ${yellow}6${re}. 重启 服务 (获取新临时域名)"
        echo ""
        echo -e " ${purple}───────────────── 系统维护 ─────────────────${re}"
        echo -e "  ${yellow}7${re}. 重新一键全自动安装"
        echo -e "  ${red}8${re}. 完全卸载 ArgoX-Mini"
        echo ""
        echo -e "  ${cyan}0${re}. 退出面板"
        echo ""
        echo -e " ${purple}────────────────────────────────────────────${re}"
        read -p "  请输入选项 (0-8): " menu_input

        case "$menu_input" in
            1) show_node; read -p "  按回车键返回..." -r ;;
            2) edit_cdn; read -p "  按回车键返回..." -r ;;
            3) change_config; read -p "  按回车键返回..." -r ;;
            4) start_services; sleep 1 ;;
            5) stop_services; sleep 1 ;;
            6) restart_services; sleep 1 ;;
            7)
                echo -ne "  ${yellow}确认重新安装? (y/n): ${re}"
                read confirm
                [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && install_core
                read -p "  按回车键返回..." -r ;;
            8)
                echo -ne "  ${red}⚠ 确认完全卸载? (y/n): ${re}"
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
[ ! -f "$CONFIG_FILE" ] && { install_core; exit 0; }
main_menu
