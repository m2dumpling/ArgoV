#!/usr/bin/env bash

# 定义颜色
re="\033[0m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red="\e[1;31m"

CONFIG_FILE="/etc/xray/config.json"
TUNNEL_LOG="/etc/xray/argo.log"
SCRIPT_PATH="/usr/bin/argo-v2"

# 内置优质优选域名选项
declare -A CDN_DOMAINS
CDN_DOMAINS[1]="cdn.31514926.xyz (三网通用)"
CDN_DOMAINS[2]="yidong.19931101.xyz (移动专线)"
CDN_DOMAINS[3]="liantong.19931101.xyz (联通专线)"
CDN_DOMAINS[4]="dianxin.19931101.xyz (电信专线)"
CDN_DOMAINS[5]="skk.moe (泛用测速)"

# 检查运行状态
get_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        XRAY_ST="${green}运行中${re}"
    else
        XRAY_ST="${red}已停止${re}"
    fi

    if systemctl is-active --quiet tunnel 2>/dev/null; then
        TUNNEL_ST="${green}运行中${re}"
    else
        TUNNEL_ST="${red}已停止${re}"
    fi
}

# 1. 查看节点信息
show_node() {
    clear
    if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$TUNNEL_LOG" ]; then
        echo -e "${red}错误: 未检测到安装服务，请先选择选项 6 进行安装！${re}"
        return
    fi
    
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE 2>/dev/null)
    HOST_DOMAIN=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' $TUNNEL_LOG | tail -n 1)
    
    echo -e "=================================================="
    echo -e "          ${green}当前纯 Argo 隧道节点配置参数${re}"
    echo -e "=================================================="
    if [ -z "$HOST_DOMAIN" ]; then
        echo -e "${yellow}提示: 正在获取 Cloudflare 临时伪装域名，请确保隧道已启动...${re}"
        sleep 2
        HOST_DOMAIN=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' $TUNNEL_LOG | tail -n 1)
    fi
    echo -e "协议类型: VMess"
    echo -e "优选地址 (Address): cdn.31514926.xyz (可搭配分流菜单查看更多)"
    echo -e "端口 (Port): 443"
    echo -e "用户 UUID: ${purple}${UUID}${re}"
    echo -e "传输协议 (Network): ws"
    echo -e "伪装域名 (Host / SNI): ${green}${HOST_DOMAIN}${re}"
    echo -e "路径 (Path): /vmess-argo"
    echo -e "传输层安全 (TLS): tls"
    echo -e "加密方式: none"
    echo -e "=================================================="
    echo -e "${yellow}提示: 请直接在 v2rayN 中新建或修改节点，并严格对照填入上方参数。${re}"
}

# 2. 启动服务
start_services() {
    echo -e "${yellow}正在启动服务...${re}"
    systemctl start xray
    systemctl start tunnel
    echo -e "${green}服务已启动！${re}"
}

# 3. 停止服务
stop_services() {
    echo -e "${yellow}正在停止服务...${re}"
    systemctl stop xray
    systemctl stop tunnel
    echo -e "${red}服务已停止，VPS 端口与隧道已完全关闭。${re}"
}

# 4. 重启服务
restart_services() {
    echo -e "${yellow}正在重启服务并重置隧道...${re}"
    rm -f $TUNNEL_LOG
    systemctl restart xray
    systemctl restart tunnel
    sleep 3
    echo -e "${green}服务重启成功！已向 Cloudflare 申请全新临时域名。${re}"
}

# 5. 更换/选择优选域名描述
edit_cdn() {
    clear
    echo -e "=================================================="
    echo -e "         ${green}快捷更换优选域名 / 线路菜单${re}"
    echo -e "=================================================="
    for key in 1 2 3 4 5; do
        echo -e "  $key. ${CDN_DOMAINS[$key]}"
    done
    echo -e "  c. 输入自定义优选域名或IP"
    echo -e "=================================================="
    read -p "请选择优选线路: " cdn_choice
    
    case "$cdn_choice" in
        1) SELECTED_CDN="cdn.31514926.xyz" ;;
        2) SELECTED_CDN="yidong.19931101.xyz" ;;
        3) SELECTED_CDN="liantong.19931101.xyz" ;;
        4) SELECTED_CDN="dianxin.19931101.xyz" ;;
        5) SELECTED_CDN="skk.moe" ;;
        c|C) read -p "请输入您自定义的 Cloudflare 优选域名或IP: " SELECTED_CDN ;;
        *) echo -e "${red}无效输入，取消修改。${re}"; return ;;
    esac

    if [ -n "$SELECTED_CDN" ]; then
        echo -e "\n${green}线路选择成功！您的客户端 [地址 (Address)] 请更换为: ${purple}${SELECTED_CDN}${re}"
        echo -e "${yellow}注意: 纯净直连模式下，服务端无需重启，只需在电脑客户端修改地址即可。${re}"
    fi
}

# 6. 一键全自动安装流程
install_core() {
    clear
    echo -e "${yellow}开始一键全自动部署纯净 Argo + Xray 环境...${re}"
    pkill -9 nginx caddy xray argo 2>/dev/null
    systemctl stop nginx caddy xray tunnel 2>/dev/null
    systemctl disable nginx caddy 2>/dev/null
    
    # 自动安装基础系统组件
    if command -v apt &>/dev/null; then
        apt-get update -y && apt-get install -y jq unzip curl lsof
    elif command -v yum &>/dev/null; then
        yum install -y jq unzip curl lsof
    fi

    mkdir -p /etc/xray && chmod 777 /etc/xray
    ARCH_RAW=$(uname -m)
    [ "$ARCH_RAW" = "x86_64" ] && ARCH_ARG="64" || ARCH_ARG="arm64-v8a"

    echo -e "${yellow}正在下载官方核心组件...${re}"
    curl -sLo "/etc/xray/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "/etc/xray/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    unzip -o "/etc/xray/xray.zip" -d "/etc/xray/" > /dev/null 2>&1
    chmod +x /etc/xray/xray /etc/xray/argo
    rm -f /etc/xray/xray.zip

    UUID=$(cat /proc/sys/kernel/random/uuid)
    cat > /etc/xray/config.json << EOF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    {
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "$UUID", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess-argo" } }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF

    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=/etc/xray/xray -c /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/tunnel.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/etc/xray/argo tunnel --url http://localhost:8080 --no-autoupdate --edge-ip-version auto --protocol http2
StandardOutput=append:/etc/xray/argo.log
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    rm -f $TUNNEL_LOG
    systemctl daemon-reload
    systemctl enable xray tunnel
    systemctl restart xray tunnel
    
    echo -e "${yellow}正在等待与 Cloudflare 大网端握手连接...${re}"
    sleep 5
    echo -e "${green}安装成功！已成功创建本地快捷管理指令：argo-v2${re}"
    
    # 建立本地常驻指令副本
    cp "$0" "$SCRIPT_PATH" 2>/dev/null
    chmod +x "$SCRIPT_PATH"
    show_node
}

# 自动判断：如果尚未安装，直接进入安装流程
if [ ! -f "$CONFIG_FILE" ]; then
    install_core
    exit 0
fi

# 主菜单循环
while true; do
    get_status
    clear
    echo -e "=================================================="
    echo -e "       ${purple}ArgoX-Mini 纯净版隧道一键管理面板${re}"
    echo -e "=================================================="
    echo -e "  Xray内核状态: ${XRAY_ST}"
    echo -e "  Argo隧道状态: ${TUNNEL_ST}"
    echo -e "--------------------------------------------------"
    echo -e "  1. 查看节点连接参数"
    echo -e "  2. 启动 服务"
    echo -e "  3. 停止 服务 (临时关闭后端)"
    echo -e "  4. 重举 服务 (刷新并获取新域名)"
    echo -e "  5. 更换/选择分流优选域名"
    echo -e "  6. 重新一键全自动安装"
    echo -e "  0. 退出面板"
    echo -e "=================================================="
    read -p "请输入选项 (0-6): " menu_input
    
    case "$menu_input" in
        1) show_node; read -p "按任意键返回主菜单..." -n 1 -s -r ;;
        2) start_services; sleep 2 ;;
        3) stop_services; sleep 2 ;;
        4) restart_services; sleep 2 ;;
        5) edit_cdn; read -p "按任意键返回主菜单..." -n 1 -s -r ;;
        6) install_core; read -p "按任意键返回主菜单..." -n 1 -s -r ;;
        0) clear; exit 0 ;;
        *) echo -e "${red}无效选项${re}"; sleep 1 ;;
    esac
done
