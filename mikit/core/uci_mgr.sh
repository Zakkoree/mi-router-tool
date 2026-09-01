#!/bin/sh
# 1. 配置文件名称
_UCI_CONFIG_FILE="mikit_db"
_UCI_CONFIG_DIR="$MIKIT_DIR/data"

check_valid_conf_name() {
    if echo "$key" | grep -q '[^a-zA-Z0-9_]'; then
        echo "❌ [ERROR] 配置项 \"$key\" 包含非法字符，仅支持字母、数字和下划线！" >&2
        return 1
    fi
}

# 🛠️ APP 配置统一管理接口
# 语法: mikit_db [动作] <配置项/Section/路径> [值]
# 示例:
#   mikit_db "port"                # 简写读取: $APP_ID.port
#   mikit_db get "system.hostname" # 显式读取: system.hostname
#   mikit_db set "port" "8080"     # 设置 Option
#   mikit_db add "apps" "v2ray"    # 追加 List 项
#   mikit_db rmlist "apps" "v2ray" # 移除 List 项
#   mikit_db del "port"            # 删除指定 Option/Key
#   mikit_db del_sec "my_app"      # 删除整个 Section (节点)
mikit_db() {
    local action="$1"
    [ -z "$action" ] && return 1
    local config_file="$_UCI_CONFIG_DIR/$_UCI_CONFIG_FILE"
    if [ ! -f "$config_file" ]; then
        cat <<EOF > "$config_file"
config app 'mikit'
	option dnsmasq '1'
	option docker '0'
EOF
    fi

    case "$action" in
        get|set|add|rmlist|del|clean|del_sec|rmsec) shift ;;
        *) action="get" ;;
    esac

    local key="$1"
    local val="$2"
    local target="" section=""

    [ -z "$key" ] && return 1

    # 如果是直接删除 Section，无需拼接 $APP_ID 前缀
    if [ "$action" = "del_sec" ] || [ "$action" = "rmsec" ]; then
        local uci_cmd="uci -c \"$_UCI_CONFIG_DIR\""
        eval "$uci_cmd delete \"${_UCI_CONFIG_FILE}.${key}\"" 2>/dev/null
        eval "$uci_cmd commit \"$_UCI_CONFIG_FILE\"" 2>/dev/null
        return $?
    fi

    # 针对普通 Option/List 操作进行路径解析
    case "$key" in
        *.*)
            target="$key"
            section="${key%%.*}"
            ;;
        *)
            ! check_valid_conf_name && return 1
            target="${APP_ID}.${key}"
            section="$APP_ID"
            ;;
    esac

    local uci_cmd="uci -c \"$_UCI_CONFIG_DIR\""

    case "$action" in
        get)
            eval "$uci_cmd -q -d ' ' get \"${_UCI_CONFIG_FILE}.${target}\"" 2>/dev/null
            ;;
        set)
            eval "$uci_cmd -q get \"${_UCI_CONFIG_FILE}.${section}\"" >/dev/null 2>&1 || \
                eval "$uci_cmd set \"${_UCI_CONFIG_FILE}.${section}=app\"" 2>/dev/null

            eval "$uci_cmd set \"${_UCI_CONFIG_FILE}.${target}=${val}\"" 2>/dev/null
            eval "$uci_cmd commit \"$_UCI_CONFIG_FILE\"" 2>/dev/null
            ;;
        add)
            [ -z "$val" ] && return 1
            eval "$uci_cmd -q get \"${_UCI_CONFIG_FILE}.${section}\"" >/dev/null 2>&1 || \
                eval "$uci_cmd set \"${_UCI_CONFIG_FILE}.${section}=app\"" 2>/dev/null

            eval "$uci_cmd add_list \"${_UCI_CONFIG_FILE}.${target}=${val}\"" 2>/dev/null && \
                eval "$uci_cmd commit \"$_UCI_CONFIG_FILE\"" 2>/dev/null
            ;;
        rmlist)
            [ -z "$val" ] && return 1
            eval "$uci_cmd del_list \"${_UCI_CONFIG_FILE}.${target}=${val}\"" 2>/dev/null && \
                eval "$uci_cmd commit \"$_UCI_CONFIG_FILE\"" 2>/dev/null
            ;;
        del|clean)
            eval "$uci_cmd delete \"${_UCI_CONFIG_FILE}.${target}\"" 2>/dev/null
            eval "$uci_cmd commit \"$_UCI_CONFIG_FILE\"" 2>/dev/null
            ;;
    esac
}
