#!/bin/sh

# 同步所有配置好的应用源
sync_store_index() {
    local src_url="https://raw.githubusercontent.com/Zakkoree/mi-router-tool/HEAD/pkgs/apps.json"
    echo -e " 🔄 正在更新应用商店索引..."
    local final_url="${MIRROR}${src_url}"
#    local sources="$(mikit_db get "sources")"
#    sources="$src_url $sources"
#    for source in sources; do
#        local url="$(gh_to_raw "$source")"
#        case "$url" in
#            *raw.githubusercontent.com*)
#                url="${MIRROR}${url}"
#                ;;
#            *) : ;;
#        esac
#
#
#    done
#    echo -ne "   - 正在拉取源 [${C_YELLOW}${src_id}${C_RESET}] ... "

    rm -f "$MIKIT_DIR/data/store/*"

#    curl -sSL --connect-timeout 5 -m 10 "$final_url" -o "$MIKIT_TMP/apps.json"
    if curl -sSL --connect-timeout 5 -m 10 "$final_url" -o "$MIKIT_TMP/apps.json" 2>/dev/null && [ -s "$MIKIT_TMP/apps.json" ]; then
        local source_id="$(get_jsonfile_val "$MIKIT_TMP/apps.json" "source_id" 2>/dev/null)"
        mkdir -p "$MIKIT_DIR/data/store"
        mv "$MIKIT_TMP/apps.json" "$MIKIT_DIR/data/store/source_id.json"
        echo -e "\n ✅ 更新成功"
    else
        echo -e "\n ❌ 更新失败"
    fi
}

# 说明: 校验解压后的临时应用目录合法性
# 参数 $1: 临时解压路径 (/tmp/xxx)
# 返回: 0-通过, 1-校验失败
check_app_package() {
    local tmp_dir="$1"

    if [ ! -d "$tmp_dir" ]; then
        echo -e "\n ❌ 错误: 校验目录不存在！"
        return 1
    fi

    local manifest="$tmp_dir/manifest.json"

    local menu_script="$tmp_dir/menu"
    # 1. 结构检查
    if [ ! -f "$manifest" ]; then
        echo -e "\n ❌ 安装失败: 压缩包内缺少元数据文件 manifest.json！"
        return 1
    fi



    if [ ! -f "$menu_script" ]; then
        echo -e "\n ❌ 安装失败: 压缩包内缺少启动控制脚本 (menu)！"
        return 1
    fi


    parse_app_meta "$manifest"

    if [ -z "$PARSE_APP_ID" ] || [ -z "$PARSE_APP_NAME" ] || [ -z "$PARSE_APP_VERSION" ]; then
        echo -e "\n ❌ 安装失败: manifest.json 中字段缺失！"
        return 1
    fi

    if [ "$(basename "$tmp_dir")" != "$PARSE_APP_ID" ]; then
        echo -e "\n ❌ 安装失败: 目录和应用 ID 不匹配！"
        return 1
    fi
    local init_script="$tmp_dir/$PARSE_APP_ID"
    if [ ! -f "$init_script" ]; then
        echo -e "\n ❌ 安装失败: 压缩包内缺少启动控制脚本！"
        return 1
    fi

    ! check_valid_conf_name "$PARSE_APP_ID" "id" && return 1

    # 3. 架构兼容性检测
    if [ -n "$PARSE_APP_ARCH" ] && [ "$PARSE_APP_ARCH" != "all" ]; then
        case "|${PARSE_APP_ARCH}|" in
            *"|${SYSTEM_ARCH}|"*) : ;;
            *)
                echo " ❗ 架构不匹配警告: 插件支持 [$PARSE_APP_ARCH]，但当前架构为 [${SYSTEM_ARCH}]！"
                printf "是否仍要强行安装？(y/N): "
                read force_install
                if [ "$force_install" != "y" ] && [ "$force_install" != "Y" ]; then
                    echo -e "\n 🚫 已取消操作。"
                    return 1
                fi
                ;;
        esac
    fi

    return 0
}

# 说明: 渲染应用详情信息界面，并提示用户安装/重装
show_store_app_detail() {
    local app_id="$1"
    local app_name="$2"
    local app_ver="$3"
    local app_desc="$4"
    local app_url="$5"
    local app_author="$6"
    local app_arch="$7"
    local app_status="$8" # installed uninstalled upgradable
    local app_local_v="$9"

    clear
    main_line
    print_center "➕ ${C_BOLD}应用详情信息${C_RESET} ${C_DIM}($source_id)${C_RESET}" 8
    sub_line
    if [ "$app_status" = "upgradable" ]; then
        local ver_str="${C_YELLOW}(v${app_local_v} -> v${app_ver})${C_RESET}"
    else
        local ver_str="${C_DIM}(v${app_ver})${C_RESET}"
    fi
    local arch_pass=0
    local arch="${C_GREEN}✔${C_RESET} ${C_DIM}[$app_arch]${C_RESET}"
    if [ "$app_arch" = "all" ]; then
        arch_pass="all"
    else
        case "|${app_arch}|" in
            *"|${SYSTEM_ARCH}|"*)
                arch_pass=$SYSTEM_ARCH
                ;;
            *)
                arch="${C_RED}✖${C_RESET} ${C_DIM}[$app_arch]${C_RESET}"
                arch_pass=1
                ;;
        esac
    fi
    echo -e " 📦 名称: ${C_CYAN}${app_name}${C_RESET} ${C_DIM}[${app_id}]${C_RESET} ${ver_str}"
    echo -e " 👤 作者: ${app_author}"
    echo -e " 🔧 兼容: $arch"
    echo -e " 📝 简介: ${app_desc:-暂无描述}"
    [ -n "$app_url" ] && echo -e " 🔗 链接: ${app_url}"
    main_line

    if [ "$arch_pass" = "1" ]; then
        echo " ❗  警告: 不兼容 [ $SYSTEM_ARCH ] 系统架构！"
        return 0
    fi

    if [ "$app_status" = "uninstalled" ]; then
        read -r -p "应用可安装，是否安装？(y/N): " confirm
    elif [ "$app_status" = "upgradable" ]; then
        read -r -p "应用可更新，是否更新？(y/N): " confirm
    else
        read -r -p "应用已安装，是否重装？(y/N): " confirm
    fi
    local url="$(gh_to_raw "$source_url")"

    url="${MIRROR}${url}/HEAD/pkgs/${app_id}_${arch_pass}.tar.gz"
    case "$confirm" in
        y|Y)
            echo -e "\n 🚀 正在准备安装/更新 ${C_YELLOW}${app_name}${C_RESET}..."
            app_install_from_url "$url"
            ;;
        *)
            echo -e "\n 🚫 已取消操作。"
            ;;
    esac
}

# 说明: 统一安装管道（解压校验 -> 覆盖安装 -> 注册 -> 执行钩子）
# 参数 $1: 待安装的 .tar.gz 文件路径
app_install_pipeline() {
    local pkg_file="$1"

    if [ ! -f "$pkg_file" ]; then
        echo -e " ❌ 安装失败: 未找到安装包文件 '$pkg_file'"
        return 1
    fi

    # 1. 创建带随机后缀的临时解压目录（防止残留/冲突）
    local random_id="$(${HEXDUMP:-hexdump} -n 4 -e '4/4 "%08x"' /dev/urandom 2>/dev/null || echo $$)"
    local tmp_extract="$MIKIT_TMP/mikit_pkg_${random_id}"
    mkdir -p "$tmp_extract"

    echo " 📦 正在解压并分析安装包..."

    tar -zxf "$pkg_file" -C "$tmp_extract" 2>/dev/null

    local real_dir=""
    for d in "$tmp_extract"/*/; do
        [ -d "$d" ] && real_dir="${d%/}" && break
    done
    [ -z "$real_dir" ] && real_dir="$tmp_extract"

    if ! check_app_package "$real_dir"; then
        rm -rf "$tmp_extract"
        return 1
    fi

    echo " 🔧 正在安装: ${PARSE_APP_NAME} (v${PARSE_APP_VERSION}) ..."

    local target_dir="$MIKIT_DATA_DIR/apps/$PARSE_APP_ID"
    local app_status=0

    if [ -d "$target_dir" ]; then
        echo " 🔄 正在进行覆盖/更新..."
        if [ -x "$target_dir/$PARSE_APP_ID" ]; then
            "$target_dir/$PARSE_APP_ID" status >/dev/null 2>&1 && app_status=1
            "$target_dir/$PARSE_APP_ID" stop >/dev/null 2>&1
        fi
    fi

    mkdir -p "$MIKIT_DATA_DIR/apps/$PARSE_APP_ID" "$MIKIT_DATA_DIR/apps_data/$PARSE_APP_ID"

    cp -rf "$real_dir"/* "$target_dir/" 2>/dev/null

    # 赋予可执行权限
    chmod -R +x "$target_dir" 2>/dev/null

    register_app "$PARSE_APP_ID"

    local initstatus=1
    if [ -x "$target_dir/$PARSE_APP_ID" ]; then
        ! "$target_dir/$PARSE_APP_ID" post_install && initstatus=0
        [ "$app_status" = "1" ] && "$target_dir/$PARSE_APP_ID" start
    fi

    rm -rf "$tmp_extract"

    [ "$initstatus" = "1" ] && echo -e "\n ✅ ${PARSE_APP_NAME} 安装成功！" || echo -e "\n 🚨 应用安装初始化发生异常！！！"
    return 0
}

# 说明: 从任意远程 URL 地址下载并安装插件
app_install_from_url() {
    local url="$1"
    [ -z "$url" ] && return 1

    local tmp_download="$MIKIT_TMP/mikit_remote_app.tar.gz"
    echo " ⬇️ 正在从远程地址下载插件包..."
    echo " 🔗 URL: $url"

    if ! curl -fsSL --progress-bar --connect-timeout 5 "$url" -o "$tmp_download" 2>/dev/null || [ ! -s "$tmp_download" ]; then
        echo -e "\n ❌ 下载失败: 无法访问远程文件或下载文件为空！"
        rm -f "$tmp_download" 2>/dev/null
        return 1
    fi

    # 交付管道处理
    app_install_pipeline "$tmp_download"
    local ret=$?

    rm -f "$tmp_download" 2>/dev/null
    return $ret
}

# 说明: 从本地路径 (如 /tmp/beszel.tar.gz 或 U盘路径) 安装
app_install_from_local() {
    local filepath="$1"

    if [ -z "$filepath" ]; then
        printf "请输入本地插件包的绝对路径 (.tar.gz): "
        read filepath
    fi

    if [ ! -f "$filepath" ]; then
        echo -e "\n ❌ 路径无效: 文件不存在！"
        pause
        return 1
    fi

    # 交付管道处理
    app_install_pipeline "$filepath"
    pause
}


# 说明: 一键生成适配 menu.common 的标准应用模板
create_new_app() {
    clear
    main_line
    print_center "Mi-Toolkit 开发模板" 4
    main_line
    printf "请输入应用 ID (纯字母/数字/下划线): "
    read t_id

    [ -z "$t_id" ] && { echo -e "\n ❌ 应用 ID 不能为空！"; return 1; }

    # ID 合法性校验
    ! check_valid_conf_name "$t_id" && return 1

    if is_app_installed "$t_id";then
        echo -e "\n ❌ 错误: 应用ID已存在！"
        return 1
    fi

    local target_dir="$MIKIT_DATA_DIR/apps/$t_id"
    echo -e " 💡 提示: 最好输入半角英文字符避免影响布局 (例如: ${C_BLUE}My custom app1${C_RESET})"
    printf "请输入应用显示名称 : "
    read t_name
    [ -z "$t_name" ] && t_name="$t_id"

    printf "请输入作者姓名昵称: "
    read t_author
    [ -z "$t_author" ] && t_author="Anonymous"

    printf "请输入应用简写描述: "
    read t_desc
    [ -z "$t_desc" ] && t_desc="基于 Mi-Toolkit 的自定义应用"

    echo ""
    echo " 🚀 正在生成应用工程目录..."
    # 1. 创建应用文件夹结构
    mkdir -p "$target_dir" "$MIKIT_DATA_DIR/apps_data/$t_id"


    PARSE_APP_ID="$t_id"
    PARSE_APP_NAME="$t_name"
    PARSE_APP_VERSION="1.0.0"
    PARSE_APP_AUTHOR="$t_author"
    PARSE_APP_DESC="$t_desc"
    PARSE_APP_ARCH="$SYSTEM_ARCH"
    PARSE_APP_URL=""
    # 2. 生成 manifest.json
    cat <<EOF > "$target_dir/manifest.json"
{
  "id": "${t_id}",
  "name": "${t_name}",
  "version": "1.0.0",
  "author": "${t_author}",
  "arch": "${SYSTEM_ARCH}",
  "desc": "${t_desc}",
  "href": ""
}
EOF

    cp "$MIKIT_DIR/core/app_script_template" "$target_dir/${t_id}"
    cp "$MIKIT_DIR/core/app_menu_template" "$target_dir/menu"
    cp "$MIKIT_DIR/core/public_function.md" "$target_dir/public_function.md"

    # 4. 赋予执行权限
    chmod +x "$target_dir/$t_id"
    chmod +x "$target_dir/menu"
    # 5. 注册 UCI
    register_app "$t_id"



    echo " ✅ 应用模板创建成功！"
    echo " 📂 工程路径: $target_dir"

    pause
}