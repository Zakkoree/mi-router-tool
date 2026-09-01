#!/bin/sh

_NGINX_CONF_DIR="/etc/nginx/conf.d"
_NGINX_PATH="/etc/init.d/nginx"
_NGINX_CONF="/etc/nginx/nginx.conf"
if [ ! -f "$_NGINX_PATH" ]; then
    _NGINX_PATH="/etc/init.d/sysapihttpd"
    _NGINX_CONF="/etc/sysapihttpd/sysapihttpd.conf"
fi

_UCI_NGINX_FILE="nginx_db"
_UCI_CONFIG_DIR="$MIKIT_DIR/data"

_domain_to_section() {
    echo "$1" | tr '.' '_'
}

nginx_generate_all_conf() {
    local enabled=$(mikit_db get "mikit.nginx_status")
    [ ! -x "$_NGINX_PATH" ] || [ ! -f "$_NGINX_CONF" ] && return 1
    mkdir -p "$_NGINX_CONF_DIR"
    grep -q "include [[:space:]]*${_NGINX_CONF_DIR}/" "$_NGINX_CONF" || \
        sed -i '/^http {/,/^}/ s|^}$|    include '"${_NGINX_CONF_DIR}"'/*.conf;\n}|' "$_NGINX_CONF"
    rm -f "$_NGINX_CONF_DIR/mikit_vhosts_*.conf"
    if [ "$enabled" != "1" ]; then
        "$_NGINX_PATH" reload >/dev/null 2>&1
        return
    fi

    local sections=$(uci -c "$_UCI_CONFIG_DIR" show "$_UCI_NGINX_FILE" 2>/dev/null | grep "=domain$")

    for sec_line in $sections; do
        local sec=$(echo "$sec_line" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}')
        [ -z "$sec" ] && continue

        local domain=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.host" 2>/dev/null)
        local root_dir=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.path" 2>/dev/null)
        local api_prefix=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.api_prefix" 2>/dev/null)
        local proxy_url=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.proxy" 2>/dev/null)
        local port=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.port" 2>/dev/null)
        [ -z "$domain" ] || [ -z "$root_dir" ] && continue
        local proxy_block=""
        if [ -n "$api_prefix" ] && [ -n "$proxy_url" ]; then
            proxy_block="

    location ${api_prefix} {
        proxy_pass ${proxy_url};
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }"
        fi
        cat <<EOF > "$_NGINX_CONF_DIR/mikit_vhosts_${sec}.conf"
# ==========================================
# MIKIT Auto-generated Nginx Virtual Host
# Domain: $domain
# Generated at: $(date)
# ==========================================

server {
    listen $port;
    server_name ${domain} *.${domain};

    index index.html index.htm;

    set \$subdomain "main";

    if (\$host ~* ^([^.]+)\.${domain}$) {
        set \$subdomain \$1;
    }

    location / {
        root ${root_dir}/\$subdomain;
        try_files \$uri \$uri/ @fallback_404;
    }${proxy_block}

    location @fallback_404 {
        root ${root_dir};
        try_files /\$subdomain/404.html /main/404.html @global_404;
        internal;
    }

    location @global_404 {
        root $MIKIT_DIR/core;
        rewrite ^ /404.html break;
        internal;
    }
}
EOF
    done

    if [ "$_NGINX_PATH" = "/etc/init.d/sysapihttpd" ]; then
        "$_NGINX_PATH" reload >/dev/null 2>&1
        return
    fi


    nginx -t >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        "$_NGINX_PATH" reload >/dev/null 2>&1
    else
        echo -e "\n ${C_RED}❌ Nginx 语法检查失败，请检查配置！${C_RESET}"
        return 1
    fi
}

nginx_query_all() {
    local sections=$(uci -c "$_UCI_CONFIG_DIR" show "$_UCI_NGINX_FILE" 2>/dev/null | grep "=domain$")
    if [ -z "$sections" ]; then
        print_center "当前没有配置任何站点。" 10
        return 0
    fi

    print_center "=== 当前 Nginx 域名路由 ===" 6
    printf "%-18s %-25s %-25s\n" "Domain" "Root Directory" "Reverse Proxy"
    sub_line

    for sec_line in $sections; do
        local sec=$(echo "$sec_line" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}')
        local domain=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.host" 2>/dev/null)
        local root_dir=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.path" 2>/dev/null)
        local api_prefix=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.api_prefix" 2>/dev/null)
        local proxy_url=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.proxy" 2>/dev/null)
        local port=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.port" 2>/dev/null)
        local proxy_info="✖"
        if [ -n "$api_prefix" ] && [ -n "$proxy_url" ]; then
            proxy_info="${api_prefix} -> ${proxy_url}"
        fi

        [ -n "$domain" ] && printf "%-18s %-25s %-25s\n" "$domain:$port" "$root_dir" "$proxy_info"
    done
}

nginx_set_domain() {
    local domain="$1"
    local root_dir="$2"
    local api_prefix="$3"
    local proxy_url="$4"
    local port="${5:-80}"

    if [ -z "$domain" ] || [ -z "$root_dir" ]; then
        echo -e "\n ❌ 域名和静态根目录不能为空！"
        return 1
    fi

    case "$port" in
        *[!0-9]*|"")
            echo "❌ 错误: 端口号必须是纯数字！"
            return 1
            ;;
        *)
            if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                echo "❌ 错误: 端口号 [$port] 超出范围 (1-65535)！"
                return 1
            fi
            ;;
    esac

    root_dir="${root_dir%/}"
    [ -z "$root_dir" ] && { echo -e "\n ❌ 无效的静态路径！"; return 1; }

    ! dns_set_rule "address" "$domain" "$lanip" && return 1

    local sec=$(_domain_to_section "$domain")

    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_NGINX_FILE.$sec=domain"
    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_NGINX_FILE.$sec.host=$domain"
    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_NGINX_FILE.$sec.path=$root_dir"
    uci -c "$_UCI_CONFIG_DIR" set "$_UCI_NGINX_FILE.$sec.port=$port"

    # 可选配置 API 代理
    if [ -n "$api_prefix" ] && [ -n "$proxy_url" ]; then
        case "$api_prefix" in
            /*) ;;
            *) api_prefix="/${api_prefix}" ;;
        esac
        case "$api_prefix" in
            */) ;;
            *) api_prefix="${api_prefix}/" ;;
        esac

        case "$proxy_url" in
            http://*|https://*) ;;
            *) proxy_url="http://${proxy_url}" ;;
        esac

        uci -c "$_UCI_CONFIG_DIR" set "$_UCI_NGINX_FILE.$sec.api_prefix=$api_prefix"
        uci -c "$_UCI_CONFIG_DIR" set "$_UCI_NGINX_FILE.$sec.proxy=$proxy_url"
    else
        uci -c "$_UCI_CONFIG_DIR" del "$_UCI_NGINX_FILE.$sec.api_prefix" 2>/dev/null
        uci -c "$_UCI_CONFIG_DIR" del "$_UCI_NGINX_FILE.$sec.proxy" 2>/dev/null
    fi

    uci -c "$_UCI_CONFIG_DIR" commit "$_UCI_NGINX_FILE" >/dev/null 2>&1

    mkdir -p "${root_dir}/main"

    nginx_generate_all_conf

    echo -e "\n ✅ Nginx 站点设置成功！"
    echo -e "   🔹 🌐 站点域名 : http://${domain}"
    echo -e "   🔹 📁 站点目录 : ${root_dir}"
    echo -e "   🔹 🏠 默认路径 : ${root_dir}/main  (访问 http://${domain})"
    echo -e "   🔹 🌿 子域路径 : ${root_dir}/[sub] (访问 http://[sub].${domain})"
    if [ -n "$api_prefix" ] && [ -n "$proxy_url" ]; then
        echo -e "   🔹 🔄 反向代理 : ${api_prefix} -> ${proxy_url}"
    fi
}

nginx_delete_one() {
    local target_domain="$1"
    if [ -z "$target_domain" ]; then
        echo -e "\n ❌ 必须提供要删除的域名！"
        return 1
    fi

    local sec=$(_domain_to_section "$target_domain")

    local exist=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec" 2>/dev/null)
    if [ -z "$exist" ]; then
        echo -e "\n ❗ 未找到域名 [$target_domain] 的配置记录。"
        return 0
    fi

    # 在删除记录前提前获取映射目录路径
    local root_dir=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.path" 2>/dev/null)

    # 清理 DNS 记录与 Nginx 规则
    dns_delete_one "$target_domain" >/dev/null 2>&1
    uci -c "$_UCI_CONFIG_DIR" delete "$_UCI_NGINX_FILE.$sec"
    uci -c "$_UCI_CONFIG_DIR" commit "$_UCI_NGINX_FILE" >/dev/null 2>&1

    rm -f "$_NGINX_CONF_DIR/mikit_vhosts_${sec}.conf"
    nginx_generate_all_conf

    echo -e "\n ✅ 成功删除域名站点: $target_domain"
    [ -n "$root_dir" ] && echo -e " 💡 如需彻底清理网页文件，可手动删除目录: ${root_dir}"
}

nginx_clear_all() {
    local sections=$(uci -c "$_UCI_CONFIG_DIR" show "$_UCI_NGINX_FILE" 2>/dev/null | grep "=domain$")
    local dirs_to_clean=""

    for sec_line in $sections; do
        local sec=$(echo "$sec_line" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}')
        local domain=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.host" 2>/dev/null)
        local root_dir=$(uci -c "$_UCI_CONFIG_DIR" get "$_UCI_NGINX_FILE.$sec.path" 2>/dev/null)

        [ -n "$domain" ] && dns_delete_one "$domain" >/dev/null 2>&1
        rm -f "$_NGINX_CONF_DIR/mikit_vhosts_${sec}.conf"

        [ -n "$root_dir" ] && dirs_to_clean="${dirs_to_clean}\n    - ${root_dir}"
    done

    # 清空配置文件
    > "$_UCI_CONFIG_DIR/$_UCI_NGINX_FILE"
    nginx_generate_all_conf

    echo -e "\n ✅ 所有 Nginx 站点配置已清空！"
    if [ -n "$dirs_to_clean" ]; then
        echo -e " 💡 如需彻底清理网页文件，可手动删除以下站点目录:${dirs_to_clean}"
    fi
}

nginx_menu() {
    while true; do
        clear
        local status=$(mikit_db get "nginx_status")
        local status_str="🛑"
        [ "$status" = "1" ] && status_str="🟢"

        main_line
        print_center "${C_BOLD}${C_GREEN}🌐 NGINX 域名路由管理${C_RESET} ${status_str}" 8
        print_center "${C_DIM}Static Web Hosting & Subdomain Mapping${C_RESET}"
        sub_line
        echo -e "  ${C_GREEN}1)${C_RESET} 🔄 启用/禁用 Nginx 路由配置"
        echo -e "  ${C_GREEN}2)${C_RESET} 📜 查看全部站点配置"
        echo -e "  ${C_GREEN}3)${C_RESET} ➕ 添加/修改 域名映射/反向代理"
        sub_line
        echo -e "  ${C_RED}8)${C_RESET} 💥 移除单条域名站点"
        echo -e "  ${C_RED}9)${C_RESET} 🚨 清空所有站点配置"
        echo -e "  ${C_GRAY}0)${C_RESET} 🔙 返回"
        main_line
        printf " 👉 请选择 [${C_BOLD}0-9${C_RESET}]: "
        read ng_choice
        echo ""

        case "$ng_choice" in
            1)
                echo -e " 当前状态：$status_str"
                read -r -p "是否启用 Nginx 路由规则？ (y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    mikit_db set "nginx_status" "1"
                    nginx_generate_all_conf
                    echo -e "\n ✅ 已启用并应用 Nginx 规则"
                else
                    mikit_db set "nginx_status" "0"
                    nginx_generate_all_conf
                    echo -e "\n ❌ 已禁用 Nginx 路由规则"
                fi
                pause
                ;;
            2)
                nginx_query_all
                pause
                ;;
            3)
                echo -e " 💡 注：如 80 8080 443 等常用端口被小米服务占用只能使用域名访问 "
                printf "1️⃣ 请输入 [域名 目录 端口(默认80)] (例如: dev.com /data/usb/www/dev.com 80): "
                read set_d set_dir set_port

                if [ -z "$set_d" ] || [ -z "$set_dir" ]; then
                    echo -e "\n ❌ 域名和静态目录不能为空！"
                    pause
                    continue
                fi

                echo ""
                printf "2️⃣ 请输入反代 [匹配前缀 后端代理地址] (例如: /api/ http://127.0.0.1 ，直接回车跳过): "
                read set_api_prefix set_proxy

                nginx_set_domain "$set_d" "$set_dir" "$set_api_prefix" "$set_proxy" "$set_port"
                pause
                ;;
            8)
                printf "请输入要删除的主域名: "
                read del_d
                if [ -n "$del_d" ]; then
                    nginx_delete_one "$del_d"
                fi
                pause
                ;;
            9)
                printf " 🚨 确定要彻底清空【所有】Nginx 站点配置吗？[y/N]: "
                read confirm
                case "$confirm" in
                    y|Y)
                        echo "正在清除所有 Nginx 站点规则..."
                        nginx_clear_all
                        ;;
                    *) echo -e "\n已取消清空。" ;;
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