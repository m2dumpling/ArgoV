#!/usr/bin/env bash
#==============================================================================
# ArgoX-Mini — 纯 Argo 隧道一键管理脚本
# 纯净 | 零公网暴露 | VMess + WebSocket + Cloudflare Tunnel
#==============================================================================

# --- 颜色定义 ---
re="\033[0m"
red="\e[1;31m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
cyan="\e[1;36m"
white_bold="\e[1;37m"

red_msg()    { echo -e "${red}$1${re}"; }
green_msg()  { echo -e "${green}$1${re}"; }
yellow_msg() { echo -e "${yellow}$1${re}"; }
purple_msg() { echo -e "${purple}$1${re}"; }
cyan_msg()   { echo -e "${cyan}$1${re}"; }

# --- 常量 ---
CONFIG_FILE="/etc/xray/config.json"
TUNNEL_LOG="/etc/xray/argo.log"
WORK_DIR="/etc/xray"
SCRIPT_PATH="/usr/bin/argo-v2"

# --- 内置优选域名 ---
declare -A CDN_DOMAINS
CDN_DOMAINS[1]="cdn.31514926.xyz (三网通用)"
CDN_DOMAINS[2]="yidong.19931101.xyz (移动专线)"
CDN_DOMAINS[3]="liantong.19931101.xyz (联通专线)"
CDN_DOMAINS[4]="dianxin.19931101.xyz (电信专线)"
CDN_DOMAINS[5]="skk.moe (泛用测速)"

#==============================================================================
# 工具函数
#==============================================================================

# 获取 Argo 临时域名
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

# 生成 VMess 链接 (base64)
gen_vmess_link() {
    local uuid="$1"
    local host="$2"
    local addr="${3:-cdn.31514926.xyz}"
    local port="${4:-443}"
    local remark="${5:-ArgoX-Mini}"

    local json
    json=$(cat << EOF
{"v":"2","ps":"${remark}","add":"${addr}","port":"${port}","id":"${uuid}","aid":"0","scy":"none","net":"ws","type":"none","host":"${host}","path":"/vmess-argo","tls":"tls","sni":"${host}","alpn":"","fp":""}
EOF
)
    echo "vmess://$(echo -n "$json" | base64 -w0 2>/dev/null || echo -n "$json" | base64 | tr -d '\n')"
}

# 在终端显示 QR 码 (ASCII)
show_qr() {
    local text="$1"
    local qrencode_bin="${WORK_DIR}/qrencode"

    if [ ! -f "$qrencode_bin" ]; then
        yellow_msg "提示: QR 码生成工具未安装，仅显示链接"
        return 1
    fi
    chmod +x "$qrencode_bin" 2>/dev/null
    echo ""
    "$qrencode_bin" -t ANSIUTF8 -m 1 -s 2 "$text" 2>/dev/null || {
        yellow_msg "QR 码生成失败，请检查终端兼容性"
        return 1
    }
}

# 下载 qrencode
install_qrencode() {
    local qrencode_bin="${WORK_DIR}/qrencode"
    [ -f "$qrencode_bin" ] && return 0

    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) yellow_msg "不支持的架构，跳过 QR 工具安装"; return 1 ;;
    esac

    curl -sLo "$qrencode_bin" \
        "https://github.com/eooce/test/releases/download/${arch}/qrencode-linux-${arch}" 2>/dev/null
    chmod +x "$qrencode_bin" 2>/dev/null
}

# 获取系统架构参数
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
# 服务状态获取
#==============================================================================
get_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        XRAY_ST="${green}● 运行中${re}"
        XRAY_RAW="running"
    else
        XRAY_ST="${red}○ 已停止${re}"
        XRAY_RAW="stopped"
    fi

    if systemctl is-active --quiet tunnel 2>/dev/null; then
        TUNNEL_ST="${green}● 运行中${re}"
        TUNNEL_RAW="running"
    else
        TUNNEL_ST="${red}○ 已停止${re}"
        TUNNEL_RAW="stopped"
    fi
}

#==============================================================================
# 1. 查看节点信息（含 vmess 链接 + QR）
#==============================================================================
show_node() {
    clear
    if [ ! -f "$CONFIG_FILE" ]; then
        red_msg "错误: 未检测到安装，请先执行一键安装！"
        return
    fi

    local uuid host_domain vmess_link cdn_addr
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE" 2>/dev/null)
    host_domain=$(get_argo_domain)
    cdn_addr="cdn.31514926.xyz"

    # 标题区
    echo ""
    echo -e "${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e "${purple}║${re}        ${white_bold}ArgoX-Mini · 当前节点连接参数${re}        ${purple}║${re}"
    echo -e "${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""

    if [ -z "$host_domain" ]; then
        yellow_msg "  ⚠ 正在等待 Cloudflare 分配临时域名，请确保 Argo 隧道已启动..."
        sleep 2
        host_domain=$(get_argo_domain)
    fi

    echo -e "  ${cyan}协议${re}      : VMess + WebSocket + TLS"
    echo -e "  ${cyan}优选地址${re}  : ${green}${cdn_addr}${re}"
    echo -e "  ${cyan}端口${re}      : 443"
    echo -e "  ${cyan}用户 ID${re}   : ${purple}${uuid}${re}"
    echo -e "  ${cyan}传输协议${re}  : ws (WebSocket)"
    echo -e "  ${cyan}伪装域名${re}  : ${green}${host_domain}${re}"
    echo -e "  ${cyan}路径${re}      : /vmess-argo"
    echo -e "  ${cyan}TLS${re}       : tls (开启)"
    echo -e "  ${cyan}加密方式${re}  : none"
    echo ""

    # 生成并显示 vmess 链接
    if [ -n "$host_domain" ]; then
        vmess_link=$(gen_vmess_link "$uuid" "$host_domain" "$cdn_addr" "443" "ArgoX-Mini")
        echo -e "  ${yellow}━━━━━ 一键导入链接 (复制整行) ━━━━━${re}"
        echo ""
        echo -e "  ${green}${vmess_link}${re}"
        echo ""

        # QR 码
        show_qr "$vmess_link"
    fi

    echo ""
    echo -e "  ${yellow}💡 提示${re}: 在 v2rayN/Nekoray 中点击「导入剪贴板」即可一键添加"
    echo -e "  ${yellow}💡 提示${re}: 菜单 5 可切换三网优选线路"
}

#==============================================================================
# 2/3/4. 服务控制
#==============================================================================
start_services() {
    yellow_msg "正在启动服务..."
    systemctl start xray 2>/dev/null
    systemctl start tunnel 2>/dev/null
    sleep 2
    get_status
    echo -e "  Xray 内核: ${XRAY_ST}"
    echo -e "  Argo 隧道: ${TUNNEL_ST}"
    green_msg "服务启动完成！"
}

stop_services() {
    yellow_msg "正在停止服务..."
    systemctl stop xray 2>/dev/null
    systemctl stop tunnel 2>/dev/null
    sleep 1
    get_status
    echo -e "  Xray 内核: ${XRAY_ST}"
    echo -e "  Argo 隧道: ${TUNNEL_ST}"
    red_msg "服务已完全停止，端口与隧道均已关闭。"
}

restart_services() {
    yellow_msg "正在重启服务并重置隧道域名..."
    rm -f "$TUNNEL_LOG"
    systemctl restart xray 2>/dev/null
    systemctl restart tunnel 2>/dev/null
    sleep 3
    get_status
    local new_domain
    new_domain=$(get_argo_domain)
    echo -e "  Xray 内核: ${XRAY_ST}"
    echo -e "  Argo 隧道: ${TUNNEL_ST}"
    green_msg "重启成功！"
    [ -n "$new_domain" ] && echo -e "  新临时域名: ${purple}${new_domain}${re}"
}

#==============================================================================
# 5. 优选域名选择
#==============================================================================
edit_cdn() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}       ${white_bold}快捷更换优选域名 / 线路${re}         ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    for key in 1 2 3 4 5; do
        echo -e "  ${green}${key}${re}. ${CDN_DOMAINS[$key]}"
    done
    echo -e "  ${cyan}c${re}. 输入自定义优选域名或 IP"
    echo ""
    echo -e " ${purple}────────────────────────────────────────${re}"
    read -p "  请选择线路 (1-5 / c): " cdn_choice

    case "$cdn_choice" in
        1) SELECTED_CDN="cdn.31514926.xyz" ;;
        2) SELECTED_CDN="yidong.19931101.xyz" ;;
        3) SELECTED_CDN="liantong.19931101.xyz" ;;
        4) SELECTED_CDN="dianxin.19931101.xyz" ;;
        5) SELECTED_CDN="skk.moe" ;;
        c|C) read -p "  请输入自定义 Cloudflare 优选域名或 IP: " SELECTED_CDN ;;
        *) red_msg "无效输入，取消修改。"; return ;;
    esac

    if [ -n "$SELECTED_CDN" ]; then
        echo ""
        green_msg "线路切换成功！"
        echo -e "  新接入地址: ${purple}${SELECTED_CDN}${re}"
        echo -e "  ${yellow}💡 无需重启服务端，在客户端修改 Address 即可生效${re}"
    fi
}

#==============================================================================
# 6. 修改节点配置
#==============================================================================
change_config() {
    clear
    if [ ! -f "$CONFIG_FILE" ]; then
        red_msg "请先安装后再修改配置！"
        return
    fi

    local uuid host_domain
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE" 2>/dev/null)
    host_domain=$(get_argo_domain)

    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}          ${white_bold}节点配置修改${re}                    ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""
    echo -e "  ${green}1${re}. 更换 UUID"
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
               '.inbounds[0].settings.clients[0].id = $u' \
               "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            systemctl restart xray 2>/dev/null
            green_msg "UUID 已更新！"
            echo -e "  新 UUID: ${purple}${new_uuid}${re}"
            echo -e "  ${yellow}⚠ 请同步更新客户端的 UUID${re}"
            ;;
        2)
            show_node
            ;;
        3)
            restart_services
            ;;
        0) return ;;
        *) red_msg "无效选项" ;;
    esac
}

#==============================================================================
# 7. 一键全自动安装
#==============================================================================
install_core() {
    clear
    echo ""
    echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}   ${white_bold}ArgoX-Mini · 一键全自动部署${re}            ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════╝${re}"
    echo ""

    # --- 清理旧环境 ---
    yellow_msg "[1/6] 清理冲突组件..."
    pkill -9 nginx caddy xray argo 2>/dev/null
    systemctl stop nginx caddy xray tunnel 2>/dev/null
    systemctl disable nginx caddy 2>/dev/null
    green_msg "  清理完成"

    # --- 安装依赖 ---
    yellow_msg "[2/6] 安装基础依赖..."
    if command -v apt &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y -qq && apt-get install -y -qq jq unzip curl lsof
    elif command -v yum &>/dev/null; then
        yum install -y -q jq unzip curl lsof
    elif command -v dnf &>/dev/null; then
        dnf install -y -q jq unzip curl lsof
    fi
    green_msg "  依赖安装完成"

    # --- 创建工作目录 ---
    mkdir -p "$WORK_DIR" && chmod 777 "$WORK_DIR"
    local ARCH_ARG
    ARCH_ARG=$(detect_arch)
    [ -z "$ARCH_ARG" ] && red_msg "不支持的 CPU 架构: $(uname -m)" && exit 1

    # --- 下载核心 ---
    yellow_msg "[3/6] 下载 Xray 核心 & Cloudflare Tunnel..."
    curl -sLo "${WORK_DIR}/xray.zip" \
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${WORK_DIR}/argo" \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    unzip -o "${WORK_DIR}/xray.zip" -d "$WORK_DIR" > /dev/null 2>&1
    chmod +x "${WORK_DIR}/xray" "${WORK_DIR}/argo"
    rm -f "${WORK_DIR}/xray.zip"
    green_msg "  核心下载完成"

    # --- 下载 QR 工具 ---
    install_qrencode

    # --- 生成配置 ---
    yellow_msg "[4/6] 生成 Xray 配置 & 系统服务..."
    UUID=$(cat /proc/sys/kernel/random/uuid)

    cat > "$CONFIG_FILE" << XRAYCONF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    {
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "$UUID", "alterId": 0 }] },
      "streamSettings": {
        "network": "ws",
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
ExecStart=${WORK_DIR}/argo tunnel --url http://localhost:8080 --no-autoupdate --edge-ip-version auto --protocol http2
StandardOutput=append:${TUNNEL_LOG}
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
SERVICETUN

    # --- 启动服务 ---
    yellow_msg "[5/6] 启动后台服务..."
    rm -f "$TUNNEL_LOG"
    systemctl daemon-reload
    systemctl enable xray tunnel 2>/dev/null
    systemctl restart xray tunnel
    green_msg "  服务启动完成"

    # --- 等待握手 & 输出结果 ---
    yellow_msg "[6/6] 等待与 Cloudflare 握手连接..."
    sleep 5

    # 安装快捷指令
    cp "$0" "$SCRIPT_PATH" 2>/dev/null
    chmod +x "$SCRIPT_PATH"

    green_msg "一键安装完成！"
    echo ""

    # --- 输出节点链接 ---
    local host_domain vmess_link
    host_domain=$(get_argo_domain)

    echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
    echo -e " ${purple}║${re}           ${white_bold}🎉 安装成功 · 节点参数如下${re}            ${purple}║${re}"
    echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
    echo ""

    echo -e "  ${cyan}快捷管理${re}  : 终端输入 ${green}argo-v2${re} 唤醒面板"
    echo ""

    if [ -n "$host_domain" ]; then
        vmess_link=$(gen_vmess_link "$UUID" "$host_domain")

        echo -e "  ${cyan}优选地址${re}  : cdn.31514926.xyz"
        echo -e "  ${cyan}端口${re}      : 443"
        echo -e "  ${cyan}用户 ID${re}   : ${purple}${UUID}${re}"
        echo -e "  ${cyan}伪装域名${re}  : ${green}${host_domain}${re}"
        echo -e "  ${cyan}路径${re}      : /vmess-argo"
        echo ""
        echo -e "  ${yellow}━━━━━ 一键导入链接 ━━━━━${re}"
        echo ""
        echo -e "  ${green}${vmess_link}${re}"
        echo ""

        show_qr "$vmess_link"
    else
        host_domain=$(get_argo_domain)
        [ -n "$host_domain" ] && {
            vmess_link=$(gen_vmess_link "$UUID" "$host_domain")
            echo -e "  ${green}${vmess_link}${re}"
            echo ""
            show_qr "$vmess_link"
        }
    fi

    echo ""
    echo -e "  ${yellow}📋 管理指令:${re} ${green}argo-v2${re}"
    echo -e "  ${yellow}💡 客户端导入:${re} 复制上方 vmess 链接 → v2rayN → 导入剪贴板"
}

#==============================================================================
# 主菜单
#==============================================================================
main_menu() {
    while true; do
        get_status
        clear

        local uuid_short="未安装"
        [ -f "$CONFIG_FILE" ] && uuid_short=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE" 2>/dev/null | cut -c1-12)...""

        local argo_domain=""
        [ "$TUNNEL_RAW" = "running" ] && argo_domain=$(get_argo_domain)

        echo ""
        echo -e " ${purple}╔══════════════════════════════════════════════════╗${re}"
        echo -e " ${purple}║${re}     ${white_bold}ArgoX-Mini  纯净版隧道管理面板${re}              ${purple}║${re}"
        echo -e " ${purple}╚══════════════════════════════════════════════════╝${re}"
        echo ""
        echo -e "  Xray 内核 : ${XRAY_ST}     UUID : ${cyan}${uuid_short}${re}"
        echo -e "  Argo 隧道 : ${TUNNEL_ST}"
        [ -n "$argo_domain" ] && echo -e "  当前域名  : ${green}${argo_domain}${re}"
        echo ""
        echo -e " ${purple}───────────────── 节点管理 ─────────────────${re}"
        echo -e "  ${green}1${re}. 查看节点连接参数 & 一键导入链接"
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
            1) show_node; read -p "  按回车键返回主菜单..." -r ;;
            2) edit_cdn; read -p "  按回车键返回主菜单..." -r ;;
            3) change_config; read -p "  按回车键返回主菜单..." -r ;;
            4) start_services; sleep 1 ;;
            5) stop_services; sleep 1 ;;
            6) restart_services; sleep 1 ;;
            7)
                read -p "  ${yellow}确认重新安装? 将覆盖现有配置 (y/n): ${re}" confirm
                [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && install_core
                read -p "  按回车键返回主菜单..." -r
                ;;
            8)
                read -p "  ${red}⚠ 确认完全卸载 ArgoX-Mini? (y/n): ${re}" confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    systemctl stop xray tunnel 2>/dev/null
                    systemctl disable xray tunnel 2>/dev/null
                    rm -rf "$WORK_DIR"
                    rm -f /etc/systemd/system/xray.service /etc/systemd/system/tunnel.service
                    rm -f "$SCRIPT_PATH"
                    systemctl daemon-reload
                    green_msg "卸载完成。再见！"
                    exit 0
                fi
                ;;
            0) clear; exit 0 ;;
            *) red_msg "无效选项，请输入 0-8"; sleep 1 ;;
        esac
    done
}

#==============================================================================
# 入口：未安装则自动进入安装流程
#==============================================================================
if [ ! -f "$CONFIG_FILE" ]; then
    install_core
    exit 0
fi

main_menu
