#!/bin/sh
# /data/mi-toolkit/core/cron_engine.sh

_UCI_CRON_FILE="cron_db"
_UCI_CONFIG_DIR="$MIKIT_DIR/data"
CRON_TARGET="/etc/crontabs/root"

# 获取 UCI 动态路径参数
_get_uci_path_opt() {
    local config_dir="${CONFIG_DIR:-$_UCI_CONFIG_DIR}"
    [ -n "$config_dir" ] && echo "-c $config_dir" || echo ""
}

# 校验 Cron 表达式（标准 5 段语法）
_validate_cron_expr() {
    local expr="$1"
    local count=$(echo "$expr" | awk '{print NF}')
    if [ "$count" -ne 5 ]; then
        echo -e "\n ❌ Cron 表达式必须包含 5 个部分（分 时 日 月 周），当前有 $count 个"
        return 1
    fi
    return 0
}

# 重启/刷新系统 cron 服务
cron_reload() {
    if [ -x "/etc/init.d/cron" ]; then
        /etc/init.d/cron reload >/dev/null 2>&1 || /etc/init.d/cron restart >/dev/null 2>&1
    elif command -v crontab >/dev/null 2>&1; then
        crontab "$CRON_TARGET" >/dev/null 2>&1
    fi
}

# 单个任务增量写入 crontab
cron_sync_item() {
    local task_id="$1"
    local path_opt="$(_get_uci_path_opt)"

    [ -z "$task_id" ] && return 1

    mkdir -p "$(dirname "$CRON_TARGET")"
    [ -f "$CRON_TARGET" ] || touch "$CRON_TARGET"

    sed -i "/# MIKIT_CRON:${task_id}:/d" "$CRON_TARGET" 2>/dev/null

    local enabled=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${task_id}.enabled")
    local expr=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${task_id}.cron_expr")
    local cmd=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${task_id}.command")
    local tag=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${task_id}.tag")

    if [ "$enabled" = "1" ] && [ -n "$expr" ] && [ -n "$cmd" ]; then
        echo "${expr} ${cmd} # MIKIT_CRON:${task_id}:${tag}" >> "$CRON_TARGET"
    fi
}

# 单个任务删除
cron_unsync_item() {
    local task_id="$1"
    [ -z "$task_id" ] && return 1

    if [ -f "$CRON_TARGET" ]; then
        sed -i "/# MIKIT_CRON:${task_id}:/d" "$CRON_TARGET" 2>/dev/null
    fi
}

# 同步所有任务
cron_sync_all() {
    local path_opt="$(_get_uci_path_opt)"
    local global_enabled=$(uci $path_opt -q get "${_UCI_CRON_FILE}.global.enabled")

    mkdir -p "$(dirname "$CRON_TARGET")"
    [ -f "$CRON_TARGET" ] || touch "$CRON_TARGET"

    sed -i '/# MIKIT_CRON/d' "$CRON_TARGET" 2>/dev/null

    if [ "${global_enabled:-1}" = "1" ]; then
        for section in $(uci $path_opt -q show "$_UCI_CRON_FILE" | grep "=task" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}'); do
            local tag=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.tag")
            local enabled=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.enabled")
            local expr=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.cron_expr")
            local cmd=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.command")

            if [ "$enabled" = "1" ] && [ -n "$expr" ] && [ -n "$cmd" ]; then
                echo "${expr} ${cmd} # MIKIT_CRON:${section}:${tag}" >> "$CRON_TARGET"
            fi
        done
    fi
}

# 检查任务是否存在
cron_has_task() {
    local task_id="$1"
    local path_opt="$(_get_uci_path_opt)"
    [ -z "$task_id" ] && return 1
    uci $path_opt -q show "${_UCI_CRON_FILE}.${task_id}" >/dev/null 2>&1
    return $?
}

# 1. 创建/更新某个任务
cron_set_task() {
    local task_id="$1"
    local tag="$2"
    local enabled="$3"
    local cron_expr="$4"
    local command="$5"
    local remark="$6"
    local path_opt="$(_get_uci_path_opt)"
    local config_dir="${CONFIG_DIR:-$_UCI_CONFIG_DIR}"

    if [ -z "$task_id" ] || [ -z "$cron_expr" ] || [ -z "$command" ]; then
        echo -e "\n ❌ 参数缺失：任务 ID、表达式和命令不能为空！"
        return 1
    fi

    if ! _validate_cron_expr "$cron_expr"; then
        return 1
    fi

    if [ -n "$config_dir" ]; then
        mkdir -p "$config_dir"
        [ -f "${config_dir}/${_UCI_CRON_FILE}" ] || touch "${config_dir}/${_UCI_CRON_FILE}"
    fi

    if ! uci $path_opt -q show "${_UCI_CRON_FILE}.${task_id}" >/dev/null 2>&1; then
        uci $path_opt set "${_UCI_CRON_FILE}.${task_id}=task"
    fi

    uci $path_opt set "${_UCI_CRON_FILE}.${task_id}.tag=${tag}"
    uci $path_opt set "${_UCI_CRON_FILE}.${task_id}.enabled=${enabled:-0}"
    uci $path_opt set "${_UCI_CRON_FILE}.${task_id}.cron_expr=${cron_expr}"
    uci $path_opt set "${_UCI_CRON_FILE}.${task_id}.command=${command}"

    if [ -n "$remark" ]; then
        uci $path_opt set "${_UCI_CRON_FILE}.${task_id}.remark=${remark}"
    else
        uci $path_opt delete "${_UCI_CRON_FILE}.${task_id}.remark" 2>/dev/null
    fi

    uci $path_opt commit "$_UCI_CRON_FILE"
    cron_sync_item "$task_id"
    echo -e "\n ✅ 已成功保存定时任务 [${task_id}]"
}

# 2. 根据 task_id 删除指定任务
cron_del_by_id() {
    local task_id="$1"
    local path_opt="$(_get_uci_path_opt)"

    [ -z "$task_id" ] && return 1

    uci $path_opt delete "${_UCI_CRON_FILE}.${task_id}" 2>/dev/null
    uci $path_opt commit "$_UCI_CRON_FILE"
    cron_unsync_item "$task_id"
    echo -e "\n ✅ 已成功删除定时任务 [${task_id}]"
    return 0
}

# 3. 按照 Tag 批量删除任务
cron_del_by_tag() {
    local target_tag="$1"
    local path_opt="$(_get_uci_path_opt)"
    local deleted_count=0

    [ -z "$target_tag" ] && return 1

    for section in $(uci $path_opt -q show "$_UCI_CRON_FILE" | grep "=task" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}'); do
        local tag=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.tag")
        if [ "$tag" = "$target_tag" ]; then
            uci $path_opt delete "${_UCI_CRON_FILE}.${section}" 2>/dev/null
            deleted_count=$((deleted_count + 1))
        fi
    done

    if [ "$deleted_count" -gt 0 ]; then
        uci $path_opt commit "$_UCI_CRON_FILE"
        cron_sync_all
        echo -e "\n ${C_GREEN}✅ 已清除 TAG 为 [${target_tag}] 的 $deleted_count 个定时任务${C_RESET}"
        return 0
    else
        echo -e "\n ${C_YELLOW}❗ 未找到 TAG 为 [${target_tag}] 的任务${C_RESET}"
        return 1
    fi
}

# ==========================================
# 交互菜单主逻辑
# ==========================================
cron_menu() {
    while true; do
        clear
        main_line
        print_center "⏰ ${C_BOLD}${C_GREEN}定时任务管理${C_RESET}" 7
        sub_line

        local path_opt="$(_get_uci_path_opt)"
        local count=0
        local id_list=""

        for section in $(uci $path_opt -q show "$_UCI_CRON_FILE" | grep "=task" | awk -F'.' '{print $2}' | awk -F'=' '{print $1}'); do
            count=$((count + 1))
            local enabled=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.enabled")
            local remark=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.remark")
            local tag=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${section}.tag")

            local status_icon="🔴"
            [ "$enabled" = "1" ] && status_icon="🟢"

            local desc="${remark:-${tag:-$section}}"
            local formatted_count="$(printf '%02d' "$count")"

            echo -e "  ${C_GREEN}${formatted_count})${C_RESET} ${status_icon} ${C_BOLD}${section}${C_RESET} ${C_DIM}(${desc})${C_RESET}"
            id_list="${id_list}${count}:${section} "
        done

        if [ "$count" -eq 0 ]; then
            print_center "${C_NOR_YELLOW}🤹 当前暂无任何定时任务${C_RESET}" 11
        fi

        sub_line
        echo -e "  ${C_BLUE}AA)${C_RESET} ➕ 添加"
        echo -e "  ${C_GRAY}00)${C_RESET} 🔙 返回"
        main_line

        if [ "$count" -gt 0 ]; then
            printf " 👉 请选择 [${C_BOLD}0-$count/A${C_RESET}]: "
        else
            printf " 👉 请选择 [${C_BOLD}0/A${C_RESET}]: "
        fi
        read -r choice

        case "$choice" in
            [aA]|[aA][aA]) # 修复：同时支持 a、A、aa、AA
                _cron_menu_add
                pause
                continue
                ;;
            0|00)
                break
                ;;
            *)
                # 修复：安全去除前导 0，避免 08 和 09 的八进制报错
                local clean_choice="$choice"
                clean_choice="${clean_choice#0}" # 去掉开头的第一个 0 (比如 05 -> 5)

                local target_id=""
                for item in $id_list; do
                    local idx="${item%%:*}"
                    local tid="${item#*:}"
                    if [ "$clean_choice" = "$idx" ]; then
                        target_id="$tid"
                        break
                    fi
                done

                if [ -n "$target_id" ]; then
                    _cron_menu_detail "$target_id"
                else
                    echo -e "\n ❌ 无效选项，请重新输入！"
                    pause
                fi
                ;;
        esac
    done
}

# 用法示例:
#   1. 设置/更新:   cron set <task_id> <tag> <enabled> <expr> <cmd> [remark]
#   2. 获取详情:   cron get <task_id>
#   3. 获取Tag组:  cron get_tag <tag_name>
#   4. 删除任务:   cron del <task_id> (或 del_tag <tag_name>)
#   5. 全量同步:   cron sync
cron() {
    local action="$1"
    shift # 移位，剩下的参数传给具体函数

    case "$action" in
        set)
            # 传参: task_id tag enabled expr cmd remark
            cron_set_task "$@"
            ;;
        get)
            # 传参: task_id
            cron_get_by_id "$@"
            ;;
        get_tag)
            # 传参: tag_name
            cron_get_by_tag "$@"
            ;;
        del)
            # 传参: task_id
            cron_del_by_id "$@"
            ;;
        del_tag)
            # 传参: tag_name
            cron_del_by_tag "$@"
            ;;
        sync)
            # 全量同步
            cron_sync_all
            echo -e "\n ✅ 定时任务已全部同步至系统 crontab"
            ;;
        *)
            echo -e "\n ❌ 未知操作指令: '${action}'"
            echo -e "  支持的指令: ${C_YELLOW}set | get | get_tag | del | del_tag | sync${C_RESET}"
            return 1
            ;;
    esac
}

# 任务详情子菜单
_cron_menu_detail() {
    local t_id="$1"
    local path_opt="$(_get_uci_path_opt)"

    while true; do
        clear
        main_line
        print_center "${C_BOLD}${C_GREEN}📌 任务详情: [${t_id}]${C_RESET}" 4
        sub_line

        local tag=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${t_id}.tag")
        local enabled=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${t_id}.enabled")
        local expr=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${t_id}.cron_expr")
        local cmd=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${t_id}.command")
        local remark=$(uci $path_opt -q get "${_UCI_CRON_FILE}.${t_id}.remark")
        # ❌ / ✖️ ➖ / 🚫 💣
        echo -e "  🔖 Tag     : ${tag:-N/A}"
        echo -e "  🚀 Enabled : $([ "$enabled" = "1" ] && echo -e "${C_GREEN}已启用${C_RESET}" || echo -e "${C_RED}已禁用${C_RESET}")"
        echo -e "  ⏰ Cron    : ${C_YELLOW}${expr}${C_RESET}"
        echo -e "  🔧 Cmd     : ${C_BLUE}${cmd}${C_RESET}"
        echo -e "  📝 Remark  : ${remark:-无}"

        sub_line
        echo -e "  ${C_GREEN}1)${C_RESET} 📝 修改任务"
        echo -e "  ${C_GREEN}2)${C_RESET} ➖ 删除任务"
        sub_line
        echo -e "  ${C_GRAY}0)${C_RESET} 🔙 返回"
        main_line
        printf " 👉 请选择操作 [${C_BOLD}0-2${C_RESET}]: "
        read -r sub_choice

        case "$sub_choice" in
            1)
                echo ""
                printf "  🔹 标识 Tag [%s]: " "${tag:-无}"
                read -r new_tag
                printf "  🔹 是否启用 [1:启用 / 0:禁用] [%s]: " "${enabled}"
                read -r new_enabled
                printf "  🔹 Cron 表达式 [%s]: " "${expr}"
                read -r new_expr
                printf "  🔹 执行命令 [%s]: " "${cmd}"
                read -r new_cmd
                printf "  🔹 备注说明 [%s]: " "${remark:-无}"
                read -r new_remark

                cron_set_task "$t_id" \
                              "${new_tag:-$tag}" \
                              "${new_enabled:-$enabled}" \
                              "${new_expr:-$expr}" \
                              "${new_cmd:-$cmd}" \
                              "${new_remark:-$remark}"
                pause
                ;;
            2)
                echo ""
                printf "  🚨 确定要删除任务 [${C_BOLD}%s${C_RESET}] 吗？ [y/N]: " "$t_id"
                read -r confirm
                case "$confirm" in
                    [yY])
                        cron_del_by_id "$t_id"
                        pause
                        return 0
                        ;;
                    *)
                        echo -e "\n 🚫 已取消操作"
                        pause
                        ;;
                esac
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "\n ❌ 无效选项！"
                pause
                ;;
        esac
    done
}

# 添加新任务界面
_cron_menu_add() {
    clear
    main_line
    print_center "${C_BOLD}${C_GREEN}➕ 添加定时任务${C_RESET}" 4
    sub_line

    printf "  🔹 任务 ID (纯字母/数字/下划线): "
    read -r t_id
    [ -z "$t_id" ] && { echo -e "\n ❌ 任务 ID 不能为空！"; return 1; }

    # 简单的格式防呆校验
    case "$t_id" in
        *[!a-zA-Z0-9_]*)
            echo -e "\n ❌ 任务 ID 只能包含字母、数字和下划线！"
            return 1
            ;;
    esac

    if cron_has_task "$t_id"; then
        echo -e "\n ❌ 该任务 ID 已存在，请更换！"
        return 1
    fi

    printf "  🔹 标识 Tag (可选): "
    read -r t_tag
    printf "  🔹 是否启用 [1:启用 / 0:禁用] (默认 1): "
    read -r t_enabled
    t_enabled="${t_enabled:-1}"

    printf "  🔹 Cron 表达式 (如 0 3 * * *): "
    read -r t_expr
    printf "  🔹 执行命令: "
    read -r t_cmd
    printf "  🔹 备注说明 (可选): "
    read -r t_remark

    sub_line
    cron_set_task "$t_id" "$t_tag" "$t_enabled" "$t_expr" "$t_cmd" "$t_remark"
}