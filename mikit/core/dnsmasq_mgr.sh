#!/bin/sh

_UCI_DNS_FILE="dnsmasq_db"
_UCI_CONFIG_DIR="$MIKIT_DIR/data"
_DATA_DNS_FILE="hosts.conf"
_GITHUB_HOSTS_FILE="$_UCI_CONFIG_DIR/github_hosts.conf"

# 域名转 UCI 安全 Section 名称 (如 dev.com -> dev_com)
_domain_to_section() {
    echo "$1" | tr '.' '_'
}

# 1A. 查询全部规则：按类型分类展示
dns_query_all() {
    print_center "=== 当前 DNSMASQ 规则 ===" 4
    local sections=$(uci -c "$_UCI_CONFIG_DIR" show "$_UCI_DNS_FILE" 2>/dev/null | grep "=rule$")

    if [ -z "$sections" ]; then
        print_center "（无自定义规则）" 6
    else
        printf "%-12s %-25s %-25s\n" "Type" "Domain" "Target"
        sub_line
        for sec_line in $sections; do
            local sec=$(echo "$sec_line" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}')
            local type=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.type" 2>/dev/null)
            local domain=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.domain" 2>/dev/null)
            local target=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.target" 2>/dev/null)

            [ -z "$type" ] && type="address"
            [ -n "$domain" ] && printf "%-12s %-25s %-25s\n" "$type" "$domain" "$target"
        done
    fi

    if [ -f "$_GITHUB_HOSTS_FILE" ]; then
        local count=$(wc -l < "$_GITHUB_HOSTS_FILE")
        echo -e "\n=== GitHub 规则状态 ==="
        echo "已加载 GitHub 规则条数: $count 条"
    fi
}

# 1B. 单个查询：极速定位
dns_query_one() {
    local target_domain="$1"
    [ -z "$target_domain" ] && return 0

    local sec=$(_domain_to_section "$target_domain")
    local type=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.type" 2>/dev/null)
    local target=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.target" 2>/dev/null)

    if [ -n "$target" ]; then
        echo "[$type] $target_domain -> $target"
    elif [ -f "$_GITHUB_HOSTS_FILE" ]; then
        grep -E "address=/${target_domain}/" "$_GITHUB_HOSTS_FILE" | head -n 1
    fi
}

# 2. 拼接全量配置并重载 dnsmasq
dns_generate_dnsmasq_file() {
    local status=$(mikit_db get "mikit.dnsmasq_status")
    local target_conf="/etc/dnsmasq.d/$_DATA_DNS_FILE"

    if [ "$status" != "1" ]; then
        rm -f "$target_conf" "$_UCI_CONFIG_DIR/$_DATA_DNS_FILE"
        [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq reload >/dev/null 2>&1
        return 0
    fi

    local sys_hosts="$_UCI_CONFIG_DIR/$_DATA_DNS_FILE"

    {
        echo "# =========================================="
        echo "# Auto-generated MIKIT DNS Rules"
        echo "# Generated at: $(date)"
        echo "# =========================================="

        local sections=$(uci -c "$_UCI_CONFIG_DIR" show "$_UCI_DNS_FILE" 2>/dev/null | grep "=rule$")
        for sec_line in $sections; do
            local sec=$(echo "$sec_line" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}')
            local type=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.type" 2>/dev/null)
            local domain=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.domain" 2>/dev/null)
            local target=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec.target" 2>/dev/null)

            [ -z "$domain" ] || [ -z "$target" ] && continue
            [ -z "$type" ] && type="address"

            case "$type" in
                address)
                    echo "address=/$domain/$target"
                    ;;
                server)
                    echo "server=/$domain/$target"
                    ;;
                host-record)
                    echo "host-record=$domain,$target"
                    ;;
            esac
        done
    } > "$sys_hosts"

    # 追加 GitHub Hosts
    [ -f "$_GITHUB_HOSTS_FILE" ] && cat "$_GITHUB_HOSTS_FILE" >> "$sys_hosts"

    ln -sf "$sys_hosts" "$target_conf"
    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq reload >/dev/null 2>&1
    fi
}

dns_clear_github() {
    rm -f "$_GITHUB_HOSTS_FILE"
    dns_generate_dnsmasq_file
}

dns_clear_all() {
    > "$_UCI_CONFIG_DIR/$_UCI_DNS_FILE"
    rm -f "$_GITHUB_HOSTS_FILE"
    dns_generate_dnsmasq_file
}

# 3. 删除指定规则
dns_delete_one() {
    local target_domain="$1"
    if [ -z "$target_domain" ]; then
        echo -e "\n ❌ 必须提供要删除的域名！"
        return 1
    fi

    local sec=$(_domain_to_section "$target_domain")

    local exist=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_DNS_FILE.$sec" 2>/dev/null)
    if [ -z "$exist" ]; then
        echo -e "\n ❗ 未找到关于域名 [$target_domain] 的规则记录。"
        return 0
    fi

    uci -c "$_UCI_CONFIG_DIR" delete "$_UCI_DNS_FILE.$sec"
    uci -c "$_UCI_CONFIG_DIR" commit "$_UCI_DNS_FILE" >/dev/null 2>&1

    dns_generate_dnsmasq_file
    echo -e "\n ✅ 成功删除域名规则: $target_domain"
}

# 4. 统一设置规则 (支持类型切换)
dns_set_rule() {
    local type="$1"     # address / server / host-record
    local domain="$2"
    local target="$3"

    if [ -z "$domain" ] || [ -z "$target" ]; then
        echo -e "\n ❌ 域名和目标值不能为空！"
        return 1
    fi

    local sec=$(_domain_to_section "$domain")

    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_DNS_FILE.$sec=rule"
    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_DNS_FILE.$sec.type=$type"
    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_DNS_FILE.$sec.domain=$domain"
    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_DNS_FILE.$sec.target=$target"
    uci -c "$_UCI_CONFIG_DIR" commit "$_UCI_DNS_FILE" >/dev/null 2>&1
    dns_generate_dnsmasq_file

    echo -e "\n ✅ [$type] 规则设置成功: $domain -> $target"
    echo -e "   💡 提示事项 : 若不生效，可尝试清空本地 DNS 缓存 (ipconfig /flushdns)"
}

# 5. 更新 GitHub 规则
github_dns_update() {
    local url="https://raw.githubusercontent.com/maxiaof/github-hosts/HEAD/hosts"
    echo "开始下载最新规则..."
    LOCAL_TMP="$MIKIT_TMP/github_hosts.txt"
    curl -sSL --connect-timeout 5 -m 10 "${MIRROR}${url}" -o "$LOCAL_TMP"
    if [ $? -ne 0 ] || [ ! -s "$LOCAL_TMP" ]; then
        echo -e "\n ❌ 下载失败或文件为空！"
        return 1
    fi

    echo "正在极速转换规则格式..."
    awk '
    /^#/ || /^$/ { next }
    $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
        ip = $1
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^#/) break
            print "address=/" $i "/" ip
        }
    }' "$LOCAL_TMP" > "$_GITHUB_HOSTS_FILE"

    rm -f "$LOCAL_TMP"
    dns_generate_dnsmasq_file
    echo -e "\n ✅ GitHub Hosts 更新完成！"
    echo -e "   📦 规则来源 : $url (每日自动更新)"
    echo -e "   💡 提示事项 : 若不生效，可尝试清空本地 DNS 缓存 (ipconfig /flushdns)"
}

# 控制台主菜单
show_domain_menu() {
    while true; do
        clear
        local status=$(mikit_db get "mikit.dnsmasq_status")
        local status_str="🛑"
        [ "$status" = "1" ] && status_str="🟢"
        main_line
        print_center "${C_BOLD}${C_GREEN}🧭 DNSMASQ 域名路由管理${C_RESET} ${status_str}" 8
        print_center "${C_DIM}DNS & Hosts Toolkit${C_RESET}"

        sub_line
        echo -e "  ${C_GREEN}1)${C_RESET} 🔄 启用/禁用"
        echo -e "  ${C_GREEN}2)${C_RESET} 📜 查看全部规则"
        echo -e "  ${C_GREEN}3)${C_RESET} 📝 添加/修改 Address 规则 (特定 IP)"
        echo -e "  ${C_GREEN}4)${C_RESET} 🎯 添加/修改 Server 规则 (指定 DNS)"
        echo -e "  ${C_GREEN}5)${C_RESET} 📌 添加/修改 Host-Record 规则"
        echo -e "  ${C_GREEN}6)${C_RESET} 🐙 更新 GitHub 规则"

        sub_line
        echo -e "  ${C_RED}7)${C_RESET} 🧹 清理 GitHub 规则"
        echo -e "  ${C_RED}8)${C_RESET} ➖ 移除单条规则"
        echo -e "  ${C_RED}9)${C_RESET} 🚨 清空所有规则"
        echo -e "  ${C_GRAY}0)${C_RESET} 🔙 返回"
        main_line
        printf " 👉 请选择 [${C_BOLD}0-9${C_RESET}]: "
        read gh_choice
        echo ""
        case "$gh_choice" in
            1)
                read -r -p "是否启用规则？ (y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    mikit_db set "dnsmasq_status" "1"
                    dns_generate_dnsmasq_file
                    echo -e "\n ✅ 已启用"
                else
                    mikit_db set "dnsmasq_status" "0"
                    dns_generate_dnsmasq_file
                    echo -e "\n ❌ 已禁用"
                fi
                pause
                ;;
            2)
                dns_query_all
                pause
                ;;
            3)
                printf "请输入格式 [域名 目标IP] (例如: dev.com 192.168.31.1): "
                read set_d set_ip
                if [ -n "$set_d" ] && [ -n "$set_ip" ]; then
                    dns_set_rule "address" "$set_d" "$set_ip"
                else
                    echo -e "\n ❌ 输入不能为空！"
                fi
                pause
                ;;
            4)
                printf "请输入格式 [域名 DNS服务器] (例如: baidu.com 223.5.5.5): "
                read set_d set_dns
                if [ -n "$set_d" ] && [ -n "$set_dns" ]; then
                    dns_set_rule "server" "$set_d" "$set_dns"
                else
                    echo -e "\n ❌ 输入不能为空！"
                fi
                pause
                ;;
            5)
                printf "请输入格式 [域名 绑定IP] (例如: dev.local 192.168.31.1): "
                read set_d set_ip
                if [ -n "$set_d" ] && [ -n "$set_ip" ]; then
                    dns_set_rule "host-record" "$set_d" "$set_ip"
                else
                    echo -e "\n ❌ 输入不能为空！"
                fi
                pause
                ;;
            6)
                github_dns_update
                pause
                ;;
            7)
                printf " 🚨 确定要清理 GitHub 规则吗？[y/N]: "
                read confirm
                case "$confirm" in
                    y|Y)
                        echo " 正在清除 GitHub 规则..."
                        dns_clear_github
                        echo -e "\n ✅ 清理 GitHub 规则完成！"
                        ;;
                    *) echo "\n 🚫 已取消操作" ;;
                esac
                pause
                ;;
            8)
                printf "请输入要删除的域名: "
                read del_d
                [ -n "$del_d" ] && dns_delete_one "$del_d"
                pause
                ;;
            9)
                printf " 🚨 确定要彻底清空【所有】规则吗？[y/N]: "
                read confirm
                case "$confirm" in
                    y|Y)
                        echo "正在清除所有规则..."
                        dns_clear_all
                        echo -e "\n ✅ 所有规则已清空！"
                        ;;
                    *) echo -e "\n 🚫 已取消操作" ;;
                esac
                pause
                ;;
            0)
                break
                ;;
            *)
                echo -e "\n ❌ 无效选项，请重新输入！"
                pause
                ;;
        esac
    done
}