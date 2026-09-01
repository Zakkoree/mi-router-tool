#!/bin/sh

# 通用日志函数 (-s: 静默控制台 | -t: 仅控制台)
log() {
    local level="$1"; shift
    local mode=""

    # 1. 解析开头选项 Flag (-s / -t)
    case "$1" in
        -s|-t) mode="$1"; shift ;;
    esac

    local msg="$*"

    # 2. 映射级别与颜色
    local color="32m"
    case "$level" in
        [eE]*|-[eE]*) level="ERROR"; color="31m" ;;
        [wW]*|-[wW]*) level="WARN";  color="33m" ;;
        *)            level="INFO";  color="32m" ;;
    esac

    # 3. 动态进程 tag
    local app=""
    [ -n "$APP_ID" ] && [ "$APP_ID" != "mikit" ] && app="-$APP_ID"

    # 4. 控制台高亮输出 (-s 时跳过)
    [ "$mode" != "-s" ] && echo -e "\033[${color}[${level}]\033[0m ${msg}"

    # 5. 写入 Syslog (-t 时跳过)
    [ "$mode" != "-t" ] && logger -p err -t "mikit${app}[$$]" "[${level}] ${msg}" 2>/dev/null

    return 0
}

# 快捷方式
loginfo() { log "INFO" "$@"; }
logwarn() { log "WARN" "$@"; }
logerr()  { log "ERROR" "$@"; }

# 🛠️ Mikit 通用按键暂停提示函数
# 语法: pause [模式/自定义提示词]
pause() {
    local prompt=""

    case "$1" in
        "") prompt="\n按任意键继续..." ;;
        *)    prompt="\n$1" ;;
    esac

    printf "%b" "$prompt"

    # 优先尝试使用 stty 禁用 echo 和 buffer 以实现真正的“按任意单键”
    if command -v stty >/dev/null 2>&1; then
        local old_tty_settings
        old_tty_settings="$(stty -g 2>/dev/null)"
        stty raw -echo 2>/dev/null
        eval "$({ dd bs=1 count=1 2>/dev/null; } | { cat; })"
        stty "$old_tty_settings" 2>/dev/null
        echo ""
    else
        # 降级备用逻辑：依次尝试 read -n1 / read -k1 (zsh) / 普通 read
        read -n 1 -s -r 2>/dev/null || read -k 1 -s -r 2>/dev/null || read -r _
        echo ""
    fi
}

# 检查 mikit_db "apps" 中是否包含指定的 app_id
# 参数: $1 - 待查找的 app_id
# 返回: 0 - 存在, 1 - 不存在
is_app_installed() {
    local appid="$1"
    [ -z "$appid" ] && return 1
    local apps
    apps=" $(mikit_db get "apps") "
    case "$apps" in
        *" $appid "*) return 0 ;;
        *)            return 1 ;;
    esac
}

detect_complete() {
    local raw_arch="$(uname -m)"
    case "$raw_arch" in
        arm*)
            # ARM 检测是否有 VFP/NEON 硬件浮点
            if ! grep -m 1 -i "Features" /proc/cpuinfo | grep -qE "vfp|vfpv3|vfpv4|neon"; then
                return 1
            fi
            ;;
        mips*)
            # MIPS 架构检测 FPU 或 DSP 指令集
            if ! grep -qiE "fpu|dsp|ase" /proc/cpuinfo; then
                return 1
            fi
            ;;
    esac

    return 0
}
detect_arch() {
    local raw_arch="$(uname -m)"

    case "$raw_arch" in
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7*)
            echo "armv7"
            ;;
        armv5*|armv6*|arm)
            echo "armv5"
            ;;
        x86_64|amd64)
            echo "amd64"
            ;;
        i386|i686|x86)
            echo "386"
            ;;
        mips*)
            local cpu_info=""
            [ -f /proc/cpuinfo ] && cpu_info="$(cat /proc/cpuinfo)"
            if [ "$raw_arch" = "mipsel" ] || [ "$raw_arch" = "mips64el" ] || \
               echo "$cpu_info" | grep -qE -i "MT7621|MediaTek|little endian"; then
                echo "mipsle"
            else
                echo "mips"
            fi
            ;;
        *)
            echo "$raw_arch"
            ;;
    esac

}

# 说明: 从 JSON 字符串中提取指定 key 的值 (自动降级兼容)
# 格式: get_json_val '{"name":"mikit","port":80}' "port"
get_json_val() {
    local json_str="$1"
    local key="$2"
    local val=""

    [ -z "$json_str" ] || [ -z "$key" ] && return 1

    # 1. 优先使用 OpenWrt 高性能的 jsonfilter
    if command -v jsonfilter >/dev/null 2>&1; then
        val=$(echo "$json_str" | jsonfilter -e "@.${key}" 2>/dev/null)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
            echo "$val"
            return 0
        fi
    fi

    # 2. 次选 OpenWrt 内置的 jshn 解析
    if command -v jshn >/dev/null 2>&1; then
        eval "$(echo "$json_str" | jshn -r - 2>/dev/null)"
        eval "val=\"\$JSON_VAR_${key}\""
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi

    # 3. 终极兜底：纯 grep + cut 文本匹配（适合简单的单层 JSON）
    echo "$json_str" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4
}

# 说明: 从 JSON 文件中提取指定 key 的值
# 格式: get_jsonfile_val "/path/to/config.json" "port"
get_jsonfile_val() {
    local json_file="$1"
    local key="$2"

    [ ! -f "$json_file" ] && return 1

    local content=""
    content="$(tr -d '\r' < "$json_file")"

    [ -z "$content" ] && return 1

    get_json_val "$content" "$key"
}



# 说明: 比较两个版本号，如果 $1 > $2 则返回 0 (true)，否则返回 1 (false)
# 示例: version_gt "1.2.10" "1.2.2" -> 返回 0
# 判断 $1 是否大于 $2 ($1 > $2)
# 返回 0 (true) 表示大于，返回 1 (false) 表示不大于
version_gt() {
    [ "$1" = "$2" ] && return 1

    # 剥离版本号开头的 'v' 字符 (如 v1.2.0 -> 1.2.0)
    local v1="${1#v}."
    local v2="${2#v}."

    while [ -n "$v1" ] || [ -n "$v2" ]; do
        # 提取点号前的第一段数字
        local n1="${v1%%.*}"
        local n2="${v2%%.*}"

        # 为空时补 0
        n1="${n1:-0}"
        n2="${n2:-0}"

        if [ "$n1" -gt "$n2" ]; then
            return 0
        elif [ "$n1" -lt "$n2" ]; then
            return 1
        fi

        # 截掉已比较的第一段
        v1="${v1#*.}"
        v2="${v2#*.}"
    done

    return 1
}

# 将 GitHub 网页链接转换为 Raw 原始文件直链，并去除末尾多余的斜杠
# 参数: $1 - GitHub URL
# 返回: 转换后的 Raw URL (参数为空时返回 1)
gh_to_raw() {
    [ -z "$1" ] && return 1
    local url="$1"
    case "$url" in
        *github.com*)
            echo "$url" | sed -r \
                -e 's|https?://(www\.)?github\.com/|https://raw.githubusercontent.com/|g' \
                -e 's|/blob/|/|g'
            ;;
        *)
            echo "$url"
            ;;
    esac
}

# 功能描述: 在指定宽度的终端边框内将文本格式化并居中输出
# 参数说明:
#   $1 - text          : [必须] 要输出的文本（支持含 ANSI 颜色代码及 Emoji/中文）
#   $2 - manual_offset : [可选] 宽字符（Emoji/中文）的补偿个数，默认 0
#                        说明：1 个 Emoji 或 1 个中文在 Shell 字符数算 1，但终端显示占 2 宽，
#                        因此每有 1 个 Emoji 或 1 个中文，此值需 +1（例如 2 个 Emoji + 2 个中文 = 4）
#   $3 - total_width   : [可选] 目标对齐的总边框宽度，默认 54
print_center() {
    local text="${1:-0}"
    local manual_offset="${2:-0}" # 手动补重：1个Emoji或1个汉字算 1
    local total_width="${3:-60}"
    local esc=$(printf '\033')
    local plain_text=$(printf '%b' "$text" | sed "s/${esc}\[[0-9;]*[a-zA-Z]//g")
    local real_width=$(( ${#plain_text} - manual_offset ))
    if [ "$real_width" -ge "$total_width" ]; then
        printf "%b\n" "$text"
        return
    fi
    local pad_left=$(( (total_width - real_width) / 2 ))
    printf "%*s%b\n" "$pad_left" "" "$text"
}

# 说明: 读取指定 app_id 的元数据信息
# 参数 $1: app_id
# 输出环境变量: META_NAME, META_VER, META_AUTHOR, META_DESC, META_ARCH
parse_app_meta() {
    local manifest="$1"
    [ -z "$manifest" ] && return 1
    PARSE_APP_ID=""
    PARSE_APP_NAME=""
    PARSE_APP_VERSION="0.0.0"
    PARSE_APP_AUTHOR="匿名"
    PARSE_APP_DESC="暂无描述"
    PARSE_APP_ARCH="all"
    PARSE_APP_URL=""
    if [ -f "$manifest" ]; then
        local id="$(get_jsonfile_val "$manifest" "id" 2>/dev/null)"
        local name="$(get_jsonfile_val "$manifest" "name" 2>/dev/null)"
        local ver="$(get_jsonfile_val "$manifest" "version" 2>/dev/null)"
        local author="$(get_jsonfile_val "$manifest" "author" 2>/dev/null)"
        local desc="$(get_jsonfile_val "$manifest" "desc" 2>/dev/null)"
        local arch="$(get_jsonfile_val "$manifest" "arch" 2>/dev/null)"
        local url="$(get_jsonfile_val "$manifest" "url" 2>/dev/null)"
        [ -n "$id" ] && PARSE_APP_ID="$id"
        [ -n "$name" ] && PARSE_APP_NAME="$name"
        [ -n "$ver" ] && PARSE_APP_VERSION="$ver"
        [ -n "$author" ] && PARSE_APP_AUTHOR="$author"
        [ -n "$desc" ] && PARSE_APP_DESC="$desc"
        [ -n "$arch" ] && PARSE_APP_ARCH="$arch"
        [ -n "$url" ] && PARSE_APP_URL="$url"
    fi
}

register_app() {
    local app_id="$1"
    [ -z "$app_id" ] && return 1

    mikit_db rmlist "apps" "$app_id"
    mikit_db add "apps" "$app_id"
    mikit_db set "$app_id.source_id" "$source_id"
    mikit_db set "$app_id.version" "$PARSE_APP_VERSION"
    mikit_db set "$app_id.name" "$PARSE_APP_NAME"
    mikit_db set "$app_id.author" "$PARSE_APP_AUTHOR"
    mikit_db set "$app_id.arch" "$PARSE_APP_ARCH"
    mikit_db set "$app_id.desc" "$PARSE_APP_DESC"
    mikit_db set "$app_id.url" "$PARSE_APP_URL"
}

uninstall_app() {
    local appid="$1"
    [ -z "$appid" ] && return 1
    read -r -p "🚨  警告: 确定要删除/卸载 [ $appid ] 吗 (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        read -r -p "是否删除 [ $appid ] 用户数据目录及配置？ (Y/n 默认Y): " confirm
        if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
            echo "--> 将删除用户目录和应用配置"
        else
            echo "--> 将保留用户目录 ($MIKIT_DATA_DIR/apps_data/$appid) 和应用配置"
        fi
        "$MIKIT_DATA_DIR/apps/$appid/init" stop 2>/dev/null
        echo " 💥  正在卸载插件..."
        "$MIKIT_DATA_DIR/apps/$appid/init" pre_uninstall 2>/dev/null
        rm -rf "$MIKIT_DATA_DIR/apps/$appid"

        mikit_db rmlist "mikit.apps" "$appid" 2>/dev/null

        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -rf "$MIKIT_DATA_DIR/apps_data/$appid"
            mikit_db del_sec "$appid"
        fi
        echo -e "\n ✅ 卸载完成！"
    else
        echo -e "\n ❌ 已取消删除操作。"
        return 1
    fi
}

inspect_entware() { [ ! -x /opt/bin/opkg ] || [ ! -f /opt/etc/init.d/rc.unslung ] && return 1 || return 0; }

extract_domain() {
    local url="$1"
    [ -z "$url" ] && return 1
    local domain="${url#*://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain="${domain%%\?*}"
    echo "$domain"
}

get_device_temp() {
  if [ -f /sys/devices/virtual/thermal/thermal_zone0/temp ];then
    echo "$(cat /sys/devices/virtual/thermal/thermal_zone0/temp 2> /dev/null)°C"
  elif [ -f /proc/dmu/temperature ];then
    echo "`cat /proc/dmu/temperature | awk '{printf$4}' | cut -b 1-2`°C"
  else
    echo "N/A"
  fi
}
