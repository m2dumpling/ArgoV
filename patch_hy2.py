import sys

content = open('E:\\Projects\\ClaudeCodeProjects\\ArgoX-Mini\\ArgoX-Mini\\argox_mini.sh', 'r', encoding='utf-8').read()

# 1. Variables
content = content.replace('ENABLE_SS=0\n', 'ENABLE_SS=0\nENABLE_HY2=0\n')
content = content.replace('REALITY_PORT="${REALITY_PORT:-0}"; SS_PORT="${SS_PORT:-0}"', 'REALITY_PORT="${REALITY_PORT:-0}"; SS_PORT="${SS_PORT:-0}"; HY2_PORT="${HY2_PORT:-0}"')
content = content.replace('ENABLE_REALITY="${ENABLE_REALITY:-0}"; ENABLE_SS="${ENABLE_SS:-0}"', 'ENABLE_REALITY="${ENABLE_REALITY:-0}"; ENABLE_SS="${ENABLE_SS:-0}"; ENABLE_HY2="${ENABLE_HY2:-0}"\n    HY2_PASS="${HY2_PASS:-}"; HY2_OBFS="${HY2_OBFS:-salamander}"; HY2_OBFS_PASS="${HY2_OBFS_PASS:-}"')

content = content.replace('save_var ENABLE_REALITY "$ENABLE_REALITY"; save_var ENABLE_SS "$ENABLE_SS"', 'save_var ENABLE_REALITY "$ENABLE_REALITY"; save_var ENABLE_SS "$ENABLE_SS"; save_var ENABLE_HY2 "$ENABLE_HY2"\n        save_var HY2_PORT "$HY2_PORT"; save_var HY2_PASS "$HY2_PASS"; save_var HY2_OBFS "$HY2_OBFS"; save_var HY2_OBFS_PASS "$HY2_OBFS_PASS"')

# 2. gen_ keys & link
keys_func = '''gen_ss2022_pass() {
    local method="$1"
    [[ "$method" =~ 128 ]] && openssl rand -base64 16 || openssl rand -base64 32
}
gen_hy2_keys() {
    local cert="${WORK_DIR}/hy2_cert.pem" key="${WORK_DIR}/hy2_key.pem"
    if [ ! -f "$cert" ] || [ ! -f "$key" ]; then
        openssl req -x509 -newkey rsa:2048 -keyout "$key" -out "$cert" -days 3650 -nodes -subj "/CN=bing.com" 2>/dev/null
    fi
}'''
content = content.replace('''gen_ss2022_pass() {
    local method="$1"
    [[ "$method" =~ 128 ]] && openssl rand -base64 16 || openssl rand -base64 32
}''', keys_func)

link_func = '''gen_reality_link() {
    local sid=""
    [ -n "$6" ] && sid="&sid=$6"
    local fp="$8"; [ -z "$fp" ] && fp="chrome"
    printf '%s' "vless://$1@$2:$3?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$4&pbk=$5&fp=${fp}${sid}#${7:-${NODE_NAME}-Reality}"
}
gen_hy2_link() {
    local op=""
    [ -n "$5" ] && op="&obfs=$4&obfs-password=$5"
    printf '%s' "hysteria2://$1@$2:$3/?insecure=1&sni=bing.com${op}#${6:-${NODE_NAME}-Hy2}"
}'''
content = content.replace('''gen_reality_link() {
    local sid=""
    [ -n "$6" ] && sid="&sid=$6"
    local fp="$8"; [ -z "$fp" ] && fp="chrome"
    printf '%s' "vless://$1@$2:$3?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$4&pbk=$5&fp=${fp}${sid}#${7:-${NODE_NAME}-Reality}"
}''', link_func)

# 3. select_protocols
content = content.replace('''        [ "$ENABLE_REALITY" = 1 ] && sum="$sum + Reality"
        [ "$ENABLE_SS" = 1 ] && sum="$sum + Shadowsocks"''', '''        [ "$ENABLE_REALITY" = 1 ] && sum="$sum + Reality"
        [ "$ENABLE_SS" = 1 ] && sum="$sum + Shadowsocks"
        [ "$ENABLE_HY2" = 1 ] && sum="$sum + Hysteria2"''')

content = content.replace('''        echo -e "  ${green}2${re}. Shadowsocks ${cyan}[$( [ "$ENABLE_SS" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     AEAD/2022 加密，需开放端口，轻量高速"
        echo ""''', '''        echo -e "  ${green}2${re}. Shadowsocks ${cyan}[$( [ "$ENABLE_SS" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     AEAD/2022 加密，需开放端口，轻量高速"
        echo ""
        echo -e "  ${green}3${re}. Hysteria2 ${cyan}[$( [ "$ENABLE_HY2" = 1 ] && echo "●● 已选" || echo "○○" )]${re}"
        echo -e "     UDP加速协议，原生支持，抗丢包"
        echo ""''')

content = content.replace('''        echo -e "  ${yellow}💡 输 1/2 切换勾选，输 0 进入端口配置${re}"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  (1/2=切换 / 0=下一步): " c
        case "$c" in
            1) ENABLE_REALITY=$((1-ENABLE_REALITY)); continue ;;
            2) ENABLE_SS=$((1-ENABLE_SS)); continue ;;
            0)
                echo ""
                [ "$ENABLE_REALITY" = 1 ] && { local rp; rp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Reality 端口 [随机 ${rp}]: ${re}"; read ri; REALITY_PORT="${ri:-$rp}"; echo -e "  → ${green}${REALITY_PORT}${re}"; }
                [ "$ENABLE_SS" = 1 ] && { local sp; sp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Shadowsocks 端口 [随机 ${sp}]: ${re}"; read si; SS_PORT="${si:-$sp}"; echo -e "  → ${green}${SS_PORT}${re}"; }''', '''        echo -e "  ${yellow}💡 输 1/2/3 切换勾选，输 0 进入端口配置${re}"
        echo -e " ${purple}────────────────────────────────────────${re}"
        read -p "  (1/2/3=切换 / 0=下一步): " c
        case "$c" in
            1) ENABLE_REALITY=$((1-ENABLE_REALITY)); continue ;;
            2) ENABLE_SS=$((1-ENABLE_SS)); continue ;;
            3) ENABLE_HY2=$((1-ENABLE_HY2)); continue ;;
            0)
                echo ""
                [ "$ENABLE_REALITY" = 1 ] && { local rp; rp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Reality 端口 [随机 ${rp}]: ${re}"; read ri; REALITY_PORT="${ri:-$rp}"; echo -e "  → ${green}${REALITY_PORT}${re}"; }
                [ "$ENABLE_SS" = 1 ] && { local sp; sp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Shadowsocks 端口 [随机 ${sp}]: ${re}"; read si; SS_PORT="${si:-$sp}"; echo -e "  → ${green}${SS_PORT}${re}"; }
                [ "$ENABLE_HY2" = 1 ] && { local hp; hp=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); echo -ne "  ${cyan}Hysteria2 端口 [随机 ${hp}]: ${re}"; read hi; HY2_PORT="${hi:-$hp}"; echo -e "  → ${green}${HY2_PORT}${re}"; }''')

content = content.replace('''                [ "$ENABLE_REALITY" = 1 ] && echo -e "  Reality: 端口 ${green}${REALITY_PORT}${re}  (UUID/SNI/密钥 自动生成)"
                [ "$ENABLE_SS" = 1 ] && echo -e "  Shadowsocks: 端口 ${green}${SS_PORT}${re}  (加密/密码 自动生成)"''', '''                [ "$ENABLE_REALITY" = 1 ] && echo -e "  Reality: 端口 ${green}${REALITY_PORT}${re}  (UUID/SNI/密钥 自动生成)"
                [ "$ENABLE_SS" = 1 ] && echo -e "  Shadowsocks: 端口 ${green}${SS_PORT}${re}  (加密/密码 自动生成)"
                [ "$ENABLE_HY2" = 1 ] && echo -e "  Hysteria2: 端口 ${green}${HY2_PORT}${re}  (密码/证书 自动生成)"''')

# 4. do_install
content = content.replace('''    if [ "$ENABLE_SS" = 1 ]; then [ "$SS_PORT" = "0" ] && SS_PORT=$(shuf -i 10000-60000 -n 1); port_in_use "$SS_PORT" && SS_PORT=$(find_free_port "$SS_PORT"); fi''', '''    if [ "$ENABLE_SS" = 1 ]; then [ "$SS_PORT" = "0" ] && SS_PORT=$(shuf -i 10000-60000 -n 1); port_in_use "$SS_PORT" && SS_PORT=$(find_free_port "$SS_PORT"); fi
    if [ "$ENABLE_HY2" = 1 ]; then
        [ "$HY2_PORT" = "0" ] && HY2_PORT=$(shuf -i 10000-60000 -n 1)
        port_in_use "$HY2_PORT" && HY2_PORT=$(find_free_port "$HY2_PORT")
        [ -z "$HY2_PASS" ] && HY2_PASS="$UUID_CUSTOM"
        [ -z "$HY2_PASS" ] && HY2_PASS="$(cat /proc/sys/kernel/random/uuid)"
        [ -z "$HY2_OBFS_PASS" ] && HY2_OBFS="salamander" && HY2_OBFS_PASS="$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)"
        gen_hy2_keys
    fi''')

content = content.replace('''        saved_inbounds=$(jq -c '[.inbounds[] | select(.tag=="reality" or .tag=="ss")]' "$CONFIG_FILE" 2>/dev/null)''', '''        saved_inbounds=$(jq -c '[.inbounds[] | select(.tag=="reality" or .tag=="ss" or .tag=="hy2")]' "$CONFIG_FILE" 2>/dev/null)''')

content = content.replace('''    # 重装时关掉可选协议（下面会从保存的 merge 回来，避免重复）
    [ -n "$saved_inbounds" ] && { ENABLE_REALITY=0; ENABLE_SS=0; }''', '''    # 重装时关掉可选协议（下面会从保存的 merge 回来，避免重复）
    [ -n "$saved_inbounds" ] && { ENABLE_REALITY=0; ENABLE_SS=0; ENABLE_HY2=0; }''')

content = content.replace('''        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="reality")' &>/dev/null && ENABLE_REALITY=1
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="ss")'       &>/dev/null && ENABLE_SS=1''', '''        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="reality")' &>/dev/null && ENABLE_REALITY=1
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="ss")'       &>/dev/null && ENABLE_SS=1
        echo "$saved_inbounds" | jq -e '.[] | select(.tag=="hy2")'      &>/dev/null && ENABLE_HY2=1''')

content = content.replace('''    if [ "$ENABLE_SS" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Shadowsocks (端口 ${SS_PORT}) ──${re}\\n"
        echo -e "  ${green}$(gen_ss_link "$SS_METHOD" "$SS_PASS" "$ip" "$SS_PORT" "${NODE_NAME}-SS")${re}\\n"
    fi''', '''    if [ "$ENABLE_SS" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Shadowsocks (端口 ${SS_PORT}) ──${re}\\n"
        echo -e "  ${green}$(gen_ss_link "$SS_METHOD" "$SS_PASS" "$ip" "$SS_PORT" "${NODE_NAME}-SS")${re}\\n"
    fi
    if [ "$ENABLE_HY2" = 1 ] && [ -n "$ip" ]; then
        echo -e "  ${white}── Hysteria2 (端口 ${HY2_PORT}) ──${re}\\n"
        echo -e "  ${green}$(gen_hy2_link "$HY2_PASS" "$ip" "$HY2_PORT" "$HY2_OBFS" "$HY2_OBFS_PASS" "${NODE_NAME}-Hy2")${re}\\n"
    fi''')

# 5. build_xray_config
content = content.replace('''    # 5. SS (opt)
    [ "$ENABLE_SS" = 1 ] && inbounds+=',{"port":'"${SS_PORT}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"}}'
    inbounds+=']' ''', '''    # 5. SS (opt)
    [ "$ENABLE_SS" = 1 ] && inbounds+=',{"port":'"${SS_PORT}"',"listen":"0.0.0.0","protocol":"shadowsocks","tag":"ss","settings":{"method":"'"${SS_METHOD}"'","password":"'"${ss_pass}"'","network":"tcp,udp"}}'
    
    # 6. Hysteria2 (opt)
    local hy2_settings='{"users":[{"password":"'"${HY2_PASS}"'"}]}'
    [ -n "$HY2_OBFS_PASS" ] && hy2_settings='{"obfuscation":"'"${HY2_OBFS_PASS}"'","users":[{"password":"'"${HY2_PASS}"'"}]}'
    [ "$ENABLE_HY2" = 1 ] && inbounds+=',{"port":'"${HY2_PORT}"',"listen":"0.0.0.0","protocol":"hysteria","tag":"hy2","settings":'"${hy2_settings}"',"streamSettings":{"network":"hysteria","hysteriaSettings":{"version":2},"tlsSettings":{"certificates":[{"certificateFile":"'"${WORK_DIR}"'/hy2_cert.pem","keyFile":"'"${WORK_DIR}"'/hy2_key.pem"}]}}}'
    inbounds+=']' ''')

# 6. manage_protocols
content = content.replace('''    local has_reality=0 has_ss=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1''', '''    local has_reality=0 has_ss=0 has_hy2=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
    grep -q '"hy2"' "$CONFIG_FILE" 2>/dev/null && has_hy2=1''')

content = content.replace('''        # 可选协议
        [ "$has_reality" = 1 ] || [ "$has_ss" = 1 ] && echo -e "  ${white}── 可选协议 · 可编辑 ──${re}" && echo ""''', '''        # 可选协议
        [ "$has_reality" = 1 ] || [ "$has_ss" = 1 ] || [ "$has_hy2" = 1 ] && echo -e "  ${white}── 可选协议 · 可编辑 ──${re}" && echo ""''')

content = content.replace('''        if [ "$has_ss" = 1 ]; then
            local sp sm; sp=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            sm=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
            local en; [ "$has_reality" = 1 ] && en="e4" || en="e3"
            echo -e "  ${green}${en}${re}. Shadowsocks       ${cyan}${sm}${re}  端口 ${cyan}${sp}${re}"
        fi''', '''        if [ "$has_ss" = 1 ]; then
            local sp sm; sp=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            sm=$(jq -r '.inbounds[]|select(.protocol=="shadowsocks")|.settings.method//empty' "$CONFIG_FILE" 2>/dev/null)
            local en; [ "$has_reality" = 1 ] && en="e4" || en="e3"
            echo -e "  ${green}${en}${re}. Shadowsocks       ${cyan}${sm}${re}  端口 ${cyan}${sp}${re}"
        fi
        if [ "$has_hy2" = 1 ]; then
            local hp ob; hp=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            ob=$(jq -r '.inbounds[]|select(.tag=="hy2")|.settings.obfuscation//empty' "$CONFIG_FILE" 2>/dev/null)
            local obm="无混淆"; [ -n "$ob" ] && [ "$ob" != "null" ] && obm="salamander"
            local en=$((3 + has_reality + has_ss))
            echo -e "  ${green}e${en}${re}. Hysteria2         ${cyan}${obm}${re}  端口 ${cyan}${hp}${re}"
        fi''')

content = content.replace('''        # 可添加
        [ "$has_reality" = 0 ] || [ "$has_ss" = 0 ] && echo "" && echo -e "  ${white}── 可添加 ──${re}" && echo ""
        local aa=0
        if [ "$has_reality" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. VLESS Reality"; fi
        if [ "$has_ss" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. Shadowsocks"; fi''', '''        # 可添加
        [ "$has_reality" = 0 ] || [ "$has_ss" = 0 ] || [ "$has_hy2" = 0 ] && echo "" && echo -e "  ${white}── 可添加 ──${re}" && echo ""
        local aa=0
        if [ "$has_reality" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. VLESS Reality"; fi
        if [ "$has_ss" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. Shadowsocks"; fi
        if [ "$has_hy2" = 0 ]; then aa=$((aa+1)); echo -e "  ${cyan}a${aa}${re}. Hysteria2"; fi''')

content = content.replace('''        [ "$has_reality" = 1 ] || [ "$has_ss" = 1 ] && echo "" && echo -e "  ${red}d${re}. 删除可选节点"''', '''        [ "$has_reality" = 1 ] || [ "$has_ss" = 1 ] || [ "$has_hy2" = 1 ] && echo "" && echo -e "  ${red}d${re}. 删除可选节点"''')

content = content.replace('''            e3) if [ "$has_reality" = 1 ]; then edit_protocol "reality" "VLESS Reality"
                elif [ "$has_ss" = 1 ]; then edit_protocol "ss" "Shadowsocks"; fi ;;
            e4) [ "$has_ss" = 1 ] && [ "$has_reality" = 1 ] && edit_protocol "ss" "Shadowsocks" ;;
            a1) if [ "$has_reality" = 0 ]; then add_single_protocol "reality"
                elif [ "$has_ss" = 0 ]; then add_single_protocol "ss"; fi ;;
            a2) [ "$has_ss" = 0 ] && [ "$has_reality" = 0 ] && add_single_protocol "ss" ;;''', '''            e3) if [ "$has_reality" = 1 ]; then edit_protocol "reality" "VLESS Reality"
                elif [ "$has_ss" = 1 ]; then edit_protocol "ss" "Shadowsocks"
                elif [ "$has_hy2" = 1 ]; then edit_protocol "hy2" "Hysteria2"; fi ;;
            e4) if [ "$has_reality" = 1 ] && [ "$has_ss" = 1 ]; then edit_protocol "ss" "Shadowsocks"
                elif [ "$has_reality" = 1 ] && [ "$has_hy2" = 1 ]; then edit_protocol "hy2" "Hysteria2"
                elif [ "$has_ss" = 1 ] && [ "$has_hy2" = 1 ]; then edit_protocol "hy2" "Hysteria2"; fi ;;
            e5) edit_protocol "hy2" "Hysteria2" ;;
            a1) if [ "$has_reality" = 0 ]; then add_single_protocol "reality"
                elif [ "$has_ss" = 0 ]; then add_single_protocol "ss"
                elif [ "$has_hy2" = 0 ]; then add_single_protocol "hy2"; fi ;;
            a2) if [ "$has_reality" = 0 ] && [ "$has_ss" = 0 ]; then add_single_protocol "ss"
                elif [ "$has_reality" = 0 ] && [ "$has_hy2" = 0 ]; then add_single_protocol "hy2"
                elif [ "$has_ss" = 0 ] && [ "$has_hy2" = 0 ]; then add_single_protocol "hy2"; fi ;;
            a3) add_single_protocol "hy2" ;;''')

content = content.replace('''        has_reality=0; has_ss=0
        grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
        grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1''', '''        has_reality=0; has_ss=0; has_hy2=0
        grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
        grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
        grep -q '"hy2"' "$CONFIG_FILE" 2>/dev/null && has_hy2=1''')

# 7. edit_protocol
content = content.replace('''            SS_METHOD="$cur_method" ;;
    esac''', '''            SS_METHOD="$cur_method" ;;
        hy2)
            cur_port=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
            cur_pass=$(jq -r '.inbounds[]|select(.tag=="hy2")|.settings.users[0].password//empty' "$CONFIG_FILE" 2>/dev/null)
            local ob; ob=$(jq -r '.inbounds[]|select(.tag=="hy2")|.settings.obfuscation//empty' "$CONFIG_FILE" 2>/dev/null)
            if [ -n "$ob" ] && [ "$ob" != "null" ]; then cur_obfs="salamander"; cur_obfs_pass="$ob"; else cur_obfs="none"; cur_obfs_pass=""; fi ;;
    esac''')

content = content.replace('''    local new_port="$cur_port" new_method="$cur_method" new_pass="$cur_pass" new_sni="$cur_sni" new_fp=""''', '''    local new_port="$cur_port" new_method="$cur_method" new_pass="$cur_pass" new_sni="$cur_sni" new_fp="" new_obfs="$cur_obfs" new_obfs_pass="$cur_obfs_pass"''')

content = content.replace('''            echo -e "  → ${green}${new_fp}${re}\\n"
            ;;
    esac''', '''            echo -e "  → ${green}${new_fp}${re}\\n"
            ;;
        hy2)
            echo -e " ${white}━━━ ① 密码 ━━━${re}"
            echo -e "  ${yellow}当前: ${cyan}$(echo "$cur_pass" | cut -c1-24)...${re}"
            echo -e "  ${yellow}回车保持。输入 new 自动生成。${re}"
            read -p "  新密码 [回车保持]: " np
            if [ "$np" = "new" ] || [ "$np" = "NEW" ]; then new_pass=$(cat /proc/sys/kernel/random/uuid)
            elif [ -n "$np" ]; then new_pass="$np"; fi
            echo -e "  → ${green}$(echo "$new_pass" | cut -c1-24)...${re}\\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"; echo -e "  ${yellow}当前: ${cyan}${cur_port}${re} 公网UDP端口"; read -p "  新端口 [回车保持]: " np2
            [ -n "$np2" ] && ! port_in_use "$np2" && new_port="$np2"; [ -n "$np2" ] && port_in_use "$np2" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${new_port}${re}\\n"

            echo -e " ${white}━━━ ③ 混淆 (Obfs) ━━━${re}"
            echo -e "  ${green}1${re}. salamander混淆  ${green}2${re}. 无混淆"
            echo -e "  ${yellow}当前: ${cyan}${cur_obfs}${re}"; read -p "  选择 [回车保持]: " nn
            case "${nn:-0}" in 1) new_obfs="salamander" ;; 2) new_obfs="none" ;; esac
            echo -e "  → ${green}${new_obfs}${re}\\n"
            
            if [ "$new_obfs" = "salamander" ]; then
                echo -e " ${white}━━━ ④ 混淆密码 ━━━${re}"
                echo -e "  ${yellow}当前: ${cyan}${cur_obfs_pass}${re}"
                read -p "  混淆密码 [回车保持]: " nop
                if [ "$nop" = "new" ] || [ "$nop" = "NEW" ]; then new_obfs_pass="$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)"
                elif [ -n "$nop" ]; then new_obfs_pass="$nop"
                elif [ -z "$new_obfs_pass" ]; then new_obfs_pass="$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)"; fi
                echo -e "  → ${green}${new_obfs_pass}${re}\\n"
            else
                new_obfs_pass=""
            fi
            ;;
    esac''')

content = content.replace('''    case "$tag" in
        ss) echo -e "  加密: ${cyan}${cur_method}${re} → ${green}${new_method}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$new_pass" != "$cur_pass" ] && echo -e "  密码: ${cyan}已更新${re}"; echo -e "  网络: ${green}${new_net}${re}" ;;
        reality) echo -e "  SNI: ${cyan}${cur_sni}${re} → ${green}${new_sni}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$nsid" = "new" ] || [ "$nsid" = "NEW" ] || [ -n "$nsid" ] && echo -e "  ShortId: ${cyan}已更新 → ${green}${REALITY_SHORTID}${re}"; echo -e "  指纹: ${green}${new_fp}${re}" ;;
    esac''', '''    case "$tag" in
        ss) echo -e "  加密: ${cyan}${cur_method}${re} → ${green}${new_method}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$new_pass" != "$cur_pass" ] && echo -e "  密码: ${cyan}已更新${re}"; echo -e "  网络: ${green}${new_net}${re}" ;;
        reality) echo -e "  SNI: ${cyan}${cur_sni}${re} → ${green}${new_sni}${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; [ "$nsid" = "new" ] || [ "$nsid" = "NEW" ] || [ -n "$nsid" ] && echo -e "  ShortId: ${cyan}已更新 → ${green}${REALITY_SHORTID}${re}"; echo -e "  指纹: ${green}${new_fp}${re}" ;;
        hy2) echo -e "  密码: ${cyan}已更新${re}"; echo -e "  端口: ${cyan}${cur_port}${re} → ${green}${new_port}${re}"; echo -e "  混淆: ${cyan}${cur_obfs}${re} → ${green}${new_obfs}${re}" ;;
    esac''')

content = content.replace('''            if [ -n "$new_fp" ]; then
                jq --arg fp "$new_fp" \\
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.fingerprint)=$fp' \\
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi ;;
    esac''', '''            if [ -n "$new_fp" ]; then
                jq --arg fp "$new_fp" \\
                   '(.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.fingerprint)=$fp' \\
                   "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi ;;
        hy2)
            jq --arg p "$new_pass" --argjson pt "$new_port" \\
               '(.inbounds[]|select(.tag=="hy2")|.settings.users[0].password)=$p|(.inbounds[]|select(.tag=="hy2")|.port)=$pt' \\
               "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            if [ "$new_obfs" = "salamander" ]; then
                jq --arg ob "$new_obfs_pass" '(.inbounds[]|select(.tag=="hy2")|.settings.obfuscation)=$ob' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            else
                jq 'del(.inbounds[]|select(.tag=="hy2")|.settings.obfuscation)' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
            HY2_PASS="$new_pass"; HY2_PORT="$new_port"; HY2_OBFS="$new_obfs"; HY2_OBFS_PASS="$new_obfs_pass" ;;
    esac''')

content = content.replace('''        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$new_port" "$new_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;; 
    esac''', '''        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$new_port" "$new_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;; 
        hy2) [ -n "$ip" ] && echo -e "  ${green}$(gen_hy2_link "$new_pass" "$ip" "$new_port" "$new_obfs" "$new_obfs_pass" "${NODE_NAME}-Hy2")${re}" ;;
    esac''')


# 8. add_single_protocol
content = content.replace('''    [[ "$proto" != "ss" && "$proto" != "reality" ]] && { red_msg "未知协议"; return; }''', '''    [[ "$proto" != "ss" && "$proto" != "reality" && "$proto" != "hy2" ]] && { red_msg "未知协议"; return; }''')

content = content.replace('''            echo -e "  → ${green}xtls-rprx-vision${re}\\n"
            ;;
    esac''', '''            echo -e "  → ${green}xtls-rprx-vision${re}\\n"
            ;;
        hy2)
            echo ""; echo -e " ${purple}╔══════════════════════════════════════════╗${re}"
            echo -e " ${purple}║${re}     ${white}添加 Hysteria2${re}"
            echo -e " ${purple}╚══════════════════════════════════════════╝${re}"; echo ""

            echo -e " ${white}━━━ ① 密码 ━━━${re}"
            local dp="$uuid"
            local h_pass="$HY2_PASS"
            [ -z "$h_pass" ] && h_pass="$dp"
            echo -e "  ${yellow}当前: ${cyan}$(echo "$h_pass"|cut -c1-20)...${re}"
            echo -e "  ${yellow}回车保持。输入 new 自动生成。${re}"
            read -p "  密码 [回车保持]: " s
            if [ "$s" = "new" ] || [ "$s" = "NEW" ]; then
                h_pass=$(cat /proc/sys/kernel/random/uuid)
            elif [ -n "$s" ]; then h_pass="$s"; fi
            echo -e "  → ${green}$(echo "$h_pass"|cut -c1-24)...${re}\\n"

            echo -e " ${white}━━━ ② 端口 ━━━${re}"
            local h_port="$HY2_PORT"
            [ -z "$h_port" ] || [ "$h_port" = "0" ] && { local dpt; dpt=$(find_free_port "$(shuf -i 10000-60000 -n 1)"); h_port="$dpt"; }
            echo -e "  ${yellow}当前: ${cyan}${h_port}${re}"; read -p "  端口 [回车保持]: " s
            [ -n "$s" ] && ! port_in_use "$s" && h_port="$s"; [ -n "$s" ] && port_in_use "$s" && red_msg "端口占用，保持原端口"
            echo -e "  → ${green}${h_port}${re}\\n"

            echo -e " ${white}━━━ ③ 混淆 (Obfs) ━━━${re}"
            echo -e "  ${green}1${re}. salamander混淆  ${green}2${re}. 无混淆"
            local h_obfs="$HY2_OBFS"; [ -z "$h_obfs" ] && h_obfs="salamander"
            echo -e "  ${yellow}当前: ${cyan}${h_obfs}${re}"; read -p "  选择 [回车保持]: " nn
            case "${nn:-0}" in 1) h_obfs="salamander" ;; 2) h_obfs="none" ;; esac
            echo -e "  → ${green}${h_obfs}${re}\\n"
            
            local h_obfs_pass=""
            if [ "$h_obfs" = "salamander" ]; then
                echo -e " ${white}━━━ ④ 混淆密码 ━━━${re}"
                h_obfs_pass="$HY2_OBFS_PASS"
                [ -z "$h_obfs_pass" ] && h_obfs_pass="$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)"
                echo -e "  ${yellow}当前: ${cyan}${h_obfs_pass}${re}"
                read -p "  混淆密码 [回车保持]: " nop
                if [ "$nop" = "new" ] || [ "$nop" = "NEW" ]; then h_obfs_pass="$(openssl rand -hex 8 2>/dev/null || printf '%08x%08x' $RANDOM $RANDOM)"
                elif [ -n "$nop" ]; then h_obfs_pass="$nop"; fi
                echo -e "  → ${green}${h_obfs_pass}${re}\\n"
            fi
            ;;
    esac''')

content = content.replace('''            echo -e "  指纹: ${green}${r_fp}${re}  Flow: ${green}xtls-rprx-vision${re}"
            ;;
    esac''', '''            echo -e "  指纹: ${green}${r_fp}${re}  Flow: ${green}xtls-rprx-vision${re}"
            ;;
        hy2)
            echo -e "  端口: ${green}${h_port}${re} (UDP)  混淆: ${green}${h_obfs}${re}"
            ;;
    esac''')

content = content.replace('''            REALITY_PORT="$r_port"; REALITY_SNI="$r_sni"; ENABLE_REALITY=1 ;;
    esac''', '''            REALITY_PORT="$r_port"; REALITY_SNI="$r_sni"; ENABLE_REALITY=1 ;;
        hy2)
            gen_hy2_keys
            local hy2_settings='{"users":[{"password":"'"${h_pass}\"'"}]}'
            [ -n "$h_obfs_pass" ] && hy2_settings='{"obfuscation":"'"${h_obfs_pass}\"'","users":[{"password":"'"${h_pass}\"'"}]}'
            new_inbound='{"port":'"${h_port}"',"listen":"0.0.0.0","protocol":"hysteria","tag":"hy2","settings":'"${hy2_settings}"',"streamSettings":{"network":"hysteria","hysteriaSettings":{"version":2},"tlsSettings":{"certificates":[{"certificateFile":"'"${WORK_DIR}"'/hy2_cert.pem","keyFile":"'"${WORK_DIR}"'/hy2_key.pem"}]}}}'
            HY2_PORT="$h_port"; HY2_PASS="$h_pass"; HY2_OBFS="$h_obfs"; HY2_OBFS_PASS="$h_obfs_pass"; ENABLE_HY2=1 ;;
    esac''')

content = content.replace('''        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$r_port" "$r_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;;
    esac''', '''        reality) [ -n "$ip" ] && echo -e "  ${green}$(gen_reality_link "$uuid" "$ip" "$r_port" "$r_sni" "$REALITY_PUB" "$REALITY_SHORTID")${re}" ;;
        hy2) [ -n "$ip" ] && echo -e "  ${green}$(gen_hy2_link "$h_pass" "$ip" "$h_port" "$h_obfs" "$h_obfs_pass" "${NODE_NAME}-Hy2")${re}" ;;
    esac''')

# 9. delete_protocol
content = content.replace('''    local has_reality=0 has_ss=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
    [ $((has_reality+has_ss)) = 0 ] && { echo ""; green_msg "无可删除。"; echo ""; read -p "  按回车返回..." -r; return; }''', '''    local has_reality=0 has_ss=0 has_hy2=0
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && has_reality=1
    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && has_ss=1
    grep -q '"hy2"' "$CONFIG_FILE" 2>/dev/null && has_hy2=1
    [ $((has_reality+has_ss+has_hy2)) = 0 ] && { echo ""; green_msg "无可删除。"; echo ""; read -p "  按回车返回..." -r; return; }''')

content = content.replace('''    local dd=0
    [ "$has_reality" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. VLESS Reality"
    [ "$has_ss" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. Shadowsocks"
    echo -e "  ${cyan}0${re}. 返回"; echo -e " ${purple}────────────────────────────────────────${re}"''', '''    local dd=0
    [ "$has_reality" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. VLESS Reality"
    [ "$has_ss" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. Shadowsocks"
    [ "$has_hy2" = 1 ] && dd=$((dd+1)) && echo -e "  ${red}${dd}${re}. Hysteria2"
    echo -e "  ${cyan}0${re}. 返回"; echo -e " ${purple}────────────────────────────────────────${re}"''')

content = content.replace('''    local del_tag=""
    [ "$dc" = "1" ] && [ "$has_reality" = 1 ] && del_tag="reality"
    [ "$dc" = "1" ] && [ "$has_reality" = 0 ] && [ "$has_ss" = 1 ] && del_tag="ss"
    [ "$dc" = "2" ] && [ "$has_ss" = 1 ] && del_tag="ss"''', '''    local del_tag=""
    local idx=0
    if [ "$has_reality" = 1 ]; then idx=$((idx+1)); [ "$dc" = "$idx" ] && del_tag="reality"; fi
    if [ "$has_ss" = 1 ]; then idx=$((idx+1)); [ "$dc" = "$idx" ] && del_tag="ss"; fi
    if [ "$has_hy2" = 1 ]; then idx=$((idx+1)); [ "$dc" = "$idx" ] && del_tag="hy2"; fi''')

content = content.replace('''    jq 'del(.inbounds[]|select(.tag=="'"${del_tag}"'"))' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    [ "$del_tag" = "reality" ] && ENABLE_REALITY=0
    [ "$del_tag" = "ss" ] && ENABLE_SS=0''', '''    jq 'del(.inbounds[]|select(.tag=="'"${del_tag}"'"))' "$CONFIG_FILE">"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    [ "$del_tag" = "reality" ] && ENABLE_REALITY=0
    [ "$del_tag" = "ss" ] && ENABLE_SS=0
    [ "$del_tag" = "hy2" ] && ENABLE_HY2=0''')

# 10. get_proto_summary and show_node
content = content.replace('''    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && s="$s SS"
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && s="$s Reality"
    echo "$s"''', '''    grep -q '"shadowsocks"' "$CONFIG_FILE" 2>/dev/null && s="$s SS"
    grep -qE '"tag"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null && s="$s Reality"
    grep -q '"hy2"' "$CONFIG_FILE" 2>/dev/null && s="$s Hy2"
    echo "$s"''')

content = content.replace('''        echo -e "  ${cyan}加密${re}: ${sm}\\n"
    fi

    echo -e "  ${yellow}💡${re} 复制链接 → 客户端导入    菜单 2 换线路 | 菜单 3 改配置"''', '''        echo -e "  ${cyan}加密${re}: ${sm}\\n"
    fi

    if grep -q '"hy2"' "$CONFIG_FILE" 2>/dev/null && [ -n "$ip" ]; then
        local hp hpass ob obm
        hp=$(jq -r '.inbounds[]|select(.tag=="hy2")|.port//empty' "$CONFIG_FILE" 2>/dev/null)
        hpass=$(jq -r '.inbounds[]|select(.tag=="hy2")|.settings.users[0].password//empty' "$CONFIG_FILE" 2>/dev/null)
        ob=$(jq -r '.inbounds[]|select(.tag=="hy2")|.settings.obfuscation//empty' "$CONFIG_FILE" 2>/dev/null)
        local curr_ob="none"; local curr_obp=""
        if [ -n "$ob" ] && [ "$ob" != "null" ]; then curr_ob="salamander"; curr_obp="$ob"; obm="salamander"; else obm="无混淆"; fi
        echo -e "  ${white}── Hysteria2 (端口 ${hp}) ──${re}\\n"
        echo -e "  ${green}$(gen_hy2_link "$hpass" "$ip" "$hp" "$curr_ob" "$curr_obp" "${NODE_NAME}-Hy2")${re}\\n"
        echo -e "  ${cyan}混淆${re}: ${obm}\\n"
    fi

    echo -e "  ${yellow}💡${re} 复制链接 → 客户端导入    菜单 2 换线路 | 菜单 3 改配置"''')

# 11. sub_gen.sh modification
content = content.replace('''if $JQ -e '.inbounds[]|select(.tag=="reality")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    rport=$($JQ -r '.inbounds[]|select(.tag=="reality")|.port' "$CFG")
    rs=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]' "$CFG")
    rpub=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey' "$CFG")
    rsid=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds[0]//empty' "$CFG")
    [ -n "$rsid" ] && rsid="&sid=${rsid}" || rsid=""
    [ -n "$rport" ] && links+="vless://${uuid}@${ip}:${rport}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${rs}&pbk=${rpub}&fp=chrome${rsid}#${NODE_NAME}-Reality"$'\n'
fi
# 自定义链接（用户自添加）''', '''if $JQ -e '.inbounds[]|select(.tag=="reality")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    rport=$($JQ -r '.inbounds[]|select(.tag=="reality")|.port' "$CFG")
    rs=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.serverNames[0]' "$CFG")
    rpub=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.publicKey' "$CFG")
    rsid=$($JQ -r '.inbounds[]|select(.tag=="reality")|.streamSettings.realitySettings.shortIds[0]//empty' "$CFG")
    [ -n "$rsid" ] && rsid="&sid=${rsid}" || rsid=""
    [ -n "$rport" ] && links+="vless://${uuid}@${ip}:${rport}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${rs}&pbk=${rpub}&fp=chrome${rsid}#${NODE_NAME}-Reality"$'\n'
fi
if $JQ -e '.inbounds[]|select(.tag=="hy2")' "$CFG" >/dev/null 2>&1 && [ -n "$ip" ]; then
    hport=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.port' "$CFG")
    hpass=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.settings.users[0].password' "$CFG")
    hobfs=$($JQ -r '.inbounds[]|select(.tag=="hy2")|.settings.obfuscation//empty' "$CFG")
    local op=""
    if [ -n "$hobfs" ] && [ "$hobfs" != "null" ]; then op="&obfs=salamander&obfs-password=${hobfs}"; fi
    [ -n "$hport" ] && links+="hysteria2://${hpass}@${ip}:${hport}/?insecure=1&sni=bing.com${op}#${NODE_NAME}-Hy2"$'\n'
fi
# 自定义链接（用户自添加）''')


with open('E:\\Projects\\ClaudeCodeProjects\\ArgoX-Mini\\ArgoX-Mini\\argox_mini_patched.sh', 'w', encoding='utf-8') as f:
    f.write(content)
