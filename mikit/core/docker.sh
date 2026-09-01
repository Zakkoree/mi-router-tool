#!/bin/sh

get_usb_path(){
  if [ -z "$USB_PATH" ]; then
    DEVICE_UUID=$(uci -q get mi_docker.settings.device_uuid)
    [ -n "$DEVICE_UUID" ] && USB_PATH=$(storage dump 2>/dev/null | grep -C3 "${DEVICE_UUID:-invalid-uuid}" | grep target: | awk '{print $2}')
  fi
}

# daemon.json 配置 对应文件 /etc/config/mi_docker
set_docker_config() {
  uci set mi_docker.globals.authorization_plugins=''
  # 镜像仓库
  while uci -q del mi_docker.globals.registry_mirrors; do :; done
  uci add_list mi_docker.globals.registry_mirrors='https://docker.1ms.run'
  uci add_list mi_docker.globals.registry_mirrors='https://docker.m.daocloud.io'
  uci add_list mi_docker.globals.registry_mirrors='https://registry-1.docker.io'

  while uci -q del mi_docker.globals.hosts; do :; done
  uci add_list mi_docker.globals.hosts='unix:///var/run/docker.sock'
  # 启用API管理端口
  uci add_list mi_docker.globals.hosts='tcp://0.0.0.0:2375'
  uci set mi_docker.globals.iptables='0'
  # 注意旧版固件缺失ipv6防火墙 （需固件版本 > 1.1.7）
  uci set mi_docker.globals.ipv6='1'
  uci set mi_docker.globals.fixed_cidr_v6='fd00:172:17::/64'
  uci set mi_docker.globals.ip6tables='1'
  uci set mi_docker.globals.experimental='1'

  uci set mi_docker.globals.proxy_server='' # 设置代理（要求 Docker 23.0+）

  uci commit mi_docker
  echo -e "\033[32mDocker config update succeed. \033[0m"
}

set_mi_docker() {
  local TARGET_FILE="/etc/init.d/mi_docker"
  [ ! -f "$TARGET_FILE" ] && return 0

  local docker_conf=$(mikit_db get "docker")
  [ "$docker_conf" != "1" ] && return 0

  local PATCH_FLAG_BACK="/tmp/mi_docker_bak"
  if [ ! -f "$PATCH_FLAG_BACK" ]; then
    cp "$TARGET_FILE" "$PATCH_FLAG_BACK" 2>/dev/null
  fi

  local PATCH_FLAG="# __MI_DOCKER_PATCHED__"
  if grep -q "$PATCH_FLAG" "$TARGET_FILE" 2>/dev/null; then
    loginfo "$TARGET_FILE 已经包含修改标识，跳过重复执行！"
    return 0
  fi

  # 1. 取消掉挂载目录检测与完整性审查
  sed -i '/check_integrity()[[:space:]]*{/a \ \ \ \ \ \ \ \ return 0' "$TARGET_FILE"

  # 2. 去除 256M 内存和 0.5 核 CPU 的限制枷锁
  sed -i '/limit_resource()[[:space:]]*{/a \ \ \ \ \ \ \ \ return 0' "$TARGET_FILE"

  # 3. 将小米路由器定制的权限鉴权插件保镖进程的启动命令强行删除
  sed -i '/procd_open_instance/ {N; /\$PAUTHZ_BIN/ {N;N;N;d}}' "$TARGET_FILE"
  sed -i '/service_stop "$DOCKER_BIN\/$PAUTHZ_BIN"/d' "$TARGET_FILE"

  # 4. docker 日志配置
  sed -i 's/json_add_string "max-size" "50m"/json_add_string "max-size" "5m"\n\tjson_add_string "max-file" "3"/' "$TARGET_FILE"

  # 5. docker proxies 设置代理
  sed -i '/config_get_bool ipv6 globals ipv6 ""/a \ \ \ \ \ \ \ \ config_get proxy_server globals proxy_server ""' "$TARGET_FILE"
  sed -i '/json_add_boolean "iptables" "${iptables}"/a \        docker_ver_major=$("$DOCKER_BIN/dockerd" --version 2>/dev/null | awk '"'{print \$3}'"' | cut -d. -f1)\n        if [ -n "${proxy_server}" ] && [ "${docker_ver_major:-0}" -ge 23 ]; then\n                json_add_object "proxies"\n                json_add_string "http-proxy" "${proxy_server}"\n                json_add_string "https-proxy" "${proxy_server}"\n                json_add_string "no-proxy" "localhost,127.0.0.1"\n                json_close_object\n        fi' "$TARGET_FILE"

  # 6. 兼容新版 docker
  sed -i 's/pgrep containerd-shim/pgrep -f containerd-shim/g' "$TARGET_FILE"
  sed -i 's/xargs -r -n1 umount/xargs -r -n1 umount -f -l/g' "$TARGET_FILE"

  # 8. 删掉原脚本中自带的旧配置 避免重复
  sed -i '/config_get experimental globals experimental ""/d' "$TARGET_FILE"
  sed -i '/config_get ip6tables globals ip6tables ""/d' "$TARGET_FILE"
  sed -i '/\[ -z "${experimental}" \] || json_add_boolean "experimental" "${experimental}"/d' "$TARGET_FILE"
  sed -i '/\[ -z "${ip6tables}" \] || json_add_boolean "ip6tables" "${ip6tables}"/d' "$TARGET_FILE"
  sed -i '/\[ -z "${ipv6}" \] || json_add_boolean "ipv6" "${ipv6}"/d' "$TARGET_FILE"
  sed -i '/\[ -z "${fixed_cidr_v6}" \] || json_add_string "fixed-cidr-v6" "${fixed_cidr_v6}"/d' "$TARGET_FILE"

  # 9. 基础 UCI 配置注入
  sed -i '/config_get_bool ipv6 globals ipv6 ""/a \ \ \ \ \ \ \ \ config_get experimental globals experimental ""' "$TARGET_FILE"
  sed -i '/json_add_boolean "iptables" "${iptables}"/a \ \ \ \ \ \ \ \ [ -z "${experimental}" ] || json_add_boolean "experimental" "${experimental}"' "$TARGET_FILE"
  sed -i '/json_add_boolean "iptables" "${iptables}"/a \ \ \ \ \ \ \ \ [ -z "${fixed_cidr_v6}" ] || json_add_string "fixed-cidr-v6" "${fixed_cidr_v6}"' "$TARGET_FILE"
  sed -i '/json_add_boolean "iptables" "${iptables}"/a \ \ \ \ \ \ \ \ [ -z "${ipv6}" ] || json_add_boolean "ipv6" "${ipv6}"' "$TARGET_FILE"

  # ----------------------------------------------------
  # 判断是否具备有效的 IPv6 防火墙，按需注入 ip6tables 选项
  # ----------------------------------------------------
  local has_ip6tables=0
  if command -v ip6tables >/dev/null 2>&1; then
    local rule_count=$(ip6tables -S 2>/dev/null | wc -l)
    [ "$rule_count" -gt 3 ] && has_ip6tables=1
  fi

  if [ "$has_ip6tables" -eq 1 ]; then
    loginfo "检测到有效的 IPv6 防火墙环境，注入 ip6tables 参数支持"
    sed -i '/config_get_bool ipv6 globals ipv6 ""/a \ \ \ \ \ \ \ \ config_get ip6tables globals ip6tables ""' "$TARGET_FILE"
    sed -i '/json_add_boolean "iptables" "${iptables}"/a \ \ \ \ \ \ \ \ [ -z "${ip6tables}" ] || json_add_boolean "ip6tables" "${ip6tables}"' "$TARGET_FILE"
  else
    loginfo "未检测到有效的 IPv6 防火墙，跳过注入 ip6tables"
  fi

  # 10. 修改三方管理面板检测
  sed -i '/check_portainer()/,/}/ s:grep -sqw "$MANAGE_BIN":grep -sqE "$MANAGE_BIN|dpanel|portainer":' "$TARGET_FILE"

  # 写入修改标识
  echo -e "\n$PATCH_FLAG" >> "$TARGET_FILE"
  loginfo "Set mi_docker succeed."

  loginfo "设置成功需手动重启 Docker!" -t
}

upgrade_docker() {
    get_usb_path
    if [ -z "$USB_PATH" ]; then
        echo "未找到 USB 存储设备。"
        return 1
    fi

    # 定义关键目录路径
    MI_DOCKER_DIR="$USB_PATH/mi_docker"
    BIN_DIR="$MI_DOCKER_DIR/docker-binaries"
    BACKUP_DIR="$MI_DOCKER_DIR/docker-binaries_bak"

    if [ ! -d "$MI_DOCKER_DIR" ] || [ ! -f "$BIN_DIR/dockerd" ]; then
        echo "未找到本地 Docker 环境！请先通过路由器 WebUI 安装 mi_docker。"
        return 1
    fi

    local CURRENT_VER="Unknown"
    if "$BIN_DIR/docker" version >/dev/null 2>&1; then
        CURRENT_VER=$("$BIN_DIR/docker" version --format '{{.Server.Version}}')
    fi

    # ==========================================
    # 交互选择目标版本号
    # ==========================================
    clear
    main_line
    print_center "${C_BOLD}${C_GREEN}🔝 升级 Docker 版本${C_RESET}" 4
    sub_line
    echo -e "  当前运行版本: ${C_YELLOW}${CURRENT_VER:-未知}${C_RESET}"
    sub_line
    echo -e " 请选择需要升级/安装的 Docker 版本："
    echo -e "  ${C_GREEN}1)${C_RESET} 🌐 自动获取官方最新版本 ${C_DIM}(Latest Stable)${C_RESET}"
    echo -e "  ${C_GREEN}2)${C_RESET} 📝 手动输入指定版本号   ${C_DIM}(例如: 26.1.4)${C_RESET}"
    echo -e "  ${C_GREEN}3)${C_RESET} ⭐ 推荐安装补丁版       ${C_DIM}(29.7.1)${C_RESET}"
    sub_line
    echo -e "  ${C_GRAY}0)${C_RESET} 🔙 退出 / 暂不升级"
    main_line
    printf " 👉 请选择选项 [${C_BOLD}0-3${C_RESET}] (默认: 0): "
    read VER_OPT
    VER_OPT=${VER_OPT:-0}

    local TARGET_VER=""
    ARCH=$(uname -m)
    MATCH=""

    case "$ARCH" in
        aarch64|arm64)       MATCH="aarch64" ;;
        x86_64|amd64)        MATCH="x86_64";;
        armv7*|armv8l|armhf) MATCH="armhf" ;;
        armv5*|armv6*|armel) MATCH="armel" ;;
        ppc64le|ppc64el)     MATCH="ppc64le" ;;
        s390x)               MATCH="s390x" ;;
        *)
            echo "CPU 架构 '$ARCH' 不支持"
            return 1
            ;;
    esac

    case "$VER_OPT" in
        1)
            echo "正在从镜像中获取最新稳定版本..."
            TARGET_VER=$(curl -sSL "https://mirrors.nju.edu.cn/docker-ce/linux/static/stable/$MATCH/" | grep -oE 'docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz' | sed 's/docker-//;s/\.tgz//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
            if [ -z "$TARGET_VER" ]; then
                echo "获取最新版本失败，回退使用默认版本 29.7.1"
                TARGET_VER="29.7.1"
            fi
            ;;
        2)
            echo ""
            printf " 🔗 请输入目标版本号 (如 26.1.4 或 29.7.1): "
            read INPUT_VER
            TARGET_VER=$(echo "$INPUT_VER" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
            if [ -z "$TARGET_VER" ]; then
                echo "输入版本格式错误，回退使用默认版本: 29.7.1"
                TARGET_VER="29.7.1"
            fi
            ;;
        3)
            TARGET_VER="29.7.1"
            ;;
        *)
            return 0
            ;;
    esac

    CLEAN_VER="${CURRENT_VER%-xiaomi*}"
    if [ "$CLEAN_VER" = "$TARGET_VER" ]; then
        echo "当前 Docker 已是目标版本 v$CURRENT_VER，无需升级。"
        return 0
    fi

    echo ""
    printf " 👉 确定目标升级版本为: v${TARGET_VER} ？[y/N]: "
    read CHOICE
    case "$CHOICE" in
        [yY]) ;;
        *)
            echo -e "\n${C_YELLOW}❗ 用户已取消操作。${C_RESET}"
            return 0
            ;;
    esac

    # 死守初始状态：只在第一次升级前备份一次
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "正在备份原始程序..."
        cp -r "$BIN_DIR" "$BACKUP_DIR"
        if [ $? -ne 0 ]; then
            echo "备份失败，为了系统安全停止升级。"
            return 1
        fi
        echo "初始备份已封存至 $BACKUP_DIR"
    fi

    TMP_FILE="${SCRIPT_TMP:-/tmp}/docker.tgz"
    DOWNLOAD_URL="https://mirrors.nju.edu.cn/docker-ce/linux/static/stable/$MATCH/docker-${TARGET_VER}.tgz"

    echo "正在下载: $DOWNLOAD_URL ..."
    if ! curl -fsSL --progress-bar --connect-timeout 15 -m 60 "$DOWNLOAD_URL" -o "$TMP_FILE" || [ ! -s "$TMP_FILE" ]; then
        echo "下载失败，请检查网络连通性。"
        return 1
    fi

    echo "解压并校验文件结构..."
    # 确保临时解压工作区存在
    cd "${SCRIPT_TMP:-/tmp}"
    tar -zxf "$TMP_FILE"
    if [ ! -d "./docker" ] || [ ! -f "./docker/dockerd" ]; then
        echo "解压文件异常或损坏！"
        rm -f "$TMP_FILE"
        return 1
    fi

    echo "替换二进制程序并设置执行权限..."
    cp -f ./docker/* "$BIN_DIR/"
    chmod +x "$BIN_DIR"/*
    rm -rf ./docker "$TMP_FILE"

    echo "重新启动 Docker 服务..."
    /etc/init.d/mi_docker restart

    echo -e "\n${C_GREEN}✅ Docker 升级成功！(v$CURRENT_VER -> v$TARGET_VER)${C_RESET}"
}

install_docker_patch() {
    get_usb_path
    if [ -z "$USB_PATH" ]; then
        echo "未找到 USB 存储设备。"
        return 1
    fi

    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64) : ;;
        *)
            echo "CPU 架构 '$ARCH' 不支持，本补丁只支持 aarch64|arm64"
            return 1
            ;;
    esac

    BIN_DIR="$USB_PATH/mi_docker/docker-binaries"
    if [ ! -d "$BIN_DIR" ]; then
        echo "未找到本地 Docker 环境！请先确认是否已安装 Docker。"
        return 1
    fi

    clear
    main_line
    print_center "${C_BOLD}${C_GREEN}🔨 安装 Docker 补丁${C_RESET}" 4
    sub_line
    echo "完美解决 Docker `stats` 及第三方监控工具（如 Portainer、Beszel、Dpanel 等）失灵问题（CPU、内存、网络流量统计全部显示为 0 的问题）"
    echo "正在检测当前 Docker 版本..."
    CURRENT_VER=$("$BIN_DIR/docker" version --format '{{.Server.Version}}' 2>/dev/null)

    case "$CURRENT_VER" in
        "29.7.1")
            echo "当前版本为 29.7.1，符合补丁适配要求。"
            ;;
        *xiaomi*)
            echo -e "  ${C_GREEN}👉 当前 Docker 已打过补丁！${C_RESET}"
            sub_line
            return 1
            ;;
        "")
            echo "Docker 环境异常，无法获取版本号。"
            sub_line
            return 1
            ;;
        *)
            echo "Docker 版本不兼容 ($CURRENT_VER)，本补丁仅针对 29.7.1 编译适配！"
            sub_line
            return 1
            ;;
    esac

    echo ""
    echo -e "  🚨  即将下载适配的 ${C_BOLD}dockerd${C_RESET} 补丁并重启 Docker 服务"
    sub_line
    printf " 👉 确认继续执行吗？ [y/N]: "
    read SURE

    case "$SURE" in
        [yY])
            echo ""
            echo "正在备份原文件到 $BIN_DIR/dockerd_bak ..."
            cp "$BIN_DIR/dockerd" "$BIN_DIR/dockerd_bak"

            echo "开始下载 dockerd 替换文件..."
            TMP_FILE="$MIKIT_TMP/dockerd.tar.gz"
            local DOWNLOAD_URL="${MIRROR}https://raw.githubusercontent.com/Zakkoree/mi-router-tool/main/dockerd/dockerd.tar.gz"

            echo "下载地址: $DOWNLOAD_URL"
            if ! curl -fsSL --progress-bar --connect-timeout 15 -m 60 "$DOWNLOAD_URL" -o "$TMP_FILE" || [ ! -s "$TMP_FILE" ]; then
                echo "下载失败，请检查网络连接或 GitHub 连通性。"
                rm -f "$TMP_FILE"
                return 1
            fi

            echo "下载完成，正在替换二进制文件..."
            if tar -zxf "$TMP_FILE" -C "$BIN_DIR"; then
                chmod +x "$BIN_DIR/dockerd"
                rm -f "$TMP_FILE"
                echo "替换完成，正在重启 Docker 服务..."
                /etc/init.d/mi_docker restart
                echo -e "\n${C_GREEN}✅ dockerd 补丁安装并生效完毕！${C_RESET}"
            else
                echo "解压失败，下载的文件可能已损坏。"
                rm -f "$TMP_FILE"
                return 1
            fi
            ;;
        *)
            echo -e "\n${C_YELLOW}用户已取消操作。${C_RESET}"
            ;;
    esac
}

install_docker_compose() {
    get_usb_path
    if [ -z "$USB_PATH" ]; then
        echo "未找到 USB 存储设备。"
        return 1
    fi

    ARCH=$(uname -m)
    MATCH=""

    case "$ARCH" in
        aarch64|arm64)   MATCH="aarch64" ;;
        armv6*)          MATCH="armv6" ;;
        armv7*|armhf)    MATCH="armv7" ;;
        ppc64le|ppc64el) MATCH="ppc64le" ;;
        riscv64)         MATCH="riscv64" ;;
        s390x)           MATCH="s390x" ;;
        x86_64|amd64)    MATCH="x86_64" ;;
        *)
            echo "CPU 架构 '$ARCH' 不支持"
            return 1
            ;;
    esac

    DOCKER_CFG_DIR="$USB_PATH/mi_docker/config"
    COMPOSE_BIN="$DOCKER_CFG_DIR/cli-plugins/docker-compose"

    mkdir -p "$DOCKER_CFG_DIR/cli-plugins"

    clear
    main_line
    print_center "${C_BOLD}${C_GREEN}📦 安装 / 更新 Docker Compose${C_RESET}" 4
    sub_line

    echo "正在获取 Docker Compose 最新版本信息..."
    RELEASE_JSON=$(curl -sSL --connect-timeout 5 -m 10 "https://api.github.com/repos/docker/compose/releases/latest")
    LATEST_TAG=$(echo "$RELEASE_JSON" | grep -oE '"tag_name": *"[^"]+"' | head -n1 | cut -d'"' -f4)

    if [ -z "$LATEST_TAG" ]; then
        echo "无法从 GitHub 获取到最新版本号！请检查网络或代理设置。"
        return 1
    fi

    local CURR_VERSION=""
    if [ -f "$COMPOSE_BIN" ] && "$COMPOSE_BIN" version >/dev/null 2>&1; then
        CURR_VERSION=$("$COMPOSE_BIN" version --short 2>/dev/null)
        LATEST_NUM=$(echo "$LATEST_TAG" | sed 's/^v//')
        CURR_NUM=$(echo "$CURR_VERSION" | sed 's/^v//')
        if [ "$LATEST_NUM" = "$CURR_NUM" ]; then
            echo "当前版本 ($CURR_VERSION) 与最新版一致，无需更新。"
            sub_line
            return 0
        fi
    fi

    if [ -n "$CURR_VERSION" ]; then
        echo -e "  检测到新版本: ${C_YELLOW}$CURR_VERSION${C_RESET} -> ${C_GREEN}$LATEST_TAG${C_RESET}"
    else
        echo -e "  准备安装 Docker Compose 版本: ${C_GREEN}$LATEST_TAG${C_RESET}"
    fi

    sub_line
    printf " 👉 是否确认开始下载并安装？ [y/N]: "
    read CHOICE
    case "$CHOICE" in
        [yY]) ;;
        *)
            echo -e "\n${C_YELLOW}❗ 用户已取消下载，操作终止。${C_RESET}"
            return 0
            ;;
    esac

    # 自动应用全局下载源 (适配你全局的 MIRROR 变量)
    local raw_github_url="${MIRROR}https://github.com/docker/compose/releases/download/${LATEST_TAG}/docker-compose-linux-${MATCH}"

    echo "正在下载: $LATEST_TAG ..."
    TMP_FILE="${SCRIPT_TMP:-/tmp}/docker-compose"

    if ! curl -SL --connect-timeout 15 -m 300 "$raw_github_url" -o "$TMP_FILE" || [ ! -s "$TMP_FILE" ]; then
        echo "下载失败！请检查网络连接或镜像源设置。"
        return 1
    fi

    echo "正在安装与配置二进制文件..."
    mv "$TMP_FILE" "${COMPOSE_BIN}"
    chmod +x "$COMPOSE_BIN"

    if ! grep -q "DOCKER_CONFIG=" /etc/profile 2>/dev/null; then
        echo "export DOCKER_CONFIG=\"$DOCKER_CFG_DIR\"" >> /etc/profile
        export DOCKER_CONFIG="$DOCKER_CFG_DIR"
        echo "已将 DOCKER_CONFIG 写入 /etc/profile"
    fi

    echo -e "\n${C_GREEN}✅ Docker Compose ($LATEST_TAG) 安装成功！${C_RESET}"
}

manage_docker_mirrors() {
    while true; do
        clear
        main_line
        print_center "🌐 Docker 镜像源管理" 6
        echo -e " 当前已配置的镜像加速源:"
        local mirrors=$(uci -q get mi_docker.globals.registry_mirrors)
        if [ -z "$mirrors" ]; then
            echo -e "   ${C_DIM}(无，将使用 Docker Hub 官方默认源)${C_RESET}"
        else
            for m in $mirrors; do
                echo -e "   🔹 ${C_BLUE}${m}${C_RESET}"
            done
        fi
        sub_line

        echo -e "  ${C_GREEN}1)${C_RESET} ➕ 添加自定义镜像源"
        echo -e "  ${C_GREEN}2)${C_RESET} 🔄 恢复默认国内加速源 (1ms.run / DaoCloud)"
        echo -e "  ${C_GREEN}3)${C_RESET} 💥 清空所有镜像源"
        sub_line
        echo -e "  ${C_GRAY}0)${C_RESET} 🔙 返回"
        main_line
        printf " 👉 请选择 [${C_BOLD}0-3${C_RESET}]: "
        read m_choice

        case "$m_choice" in
            1)
                printf " 🔗 请输入完整的镜像源 URL (例如 https://docker.1ms.run): "
                read custom_m
                if [ -n "$custom_m" ]; then
                    uci add_list mi_docker.globals.registry_mirrors="$custom_m"
                    uci commit mi_docker
                    echo -e "\n ${C_GREEN}✅ 已添加镜像源: ${custom_m}${C_RESET}"
                else
                    echo -e "\n ${C_YELLOW}❌ 输入为空，操作已取消！${C_RESET}"
                fi
                pause
                ;;
            2)
                while uci -q del mi_docker.globals.registry_mirrors; do :; done
                uci add_list mi_docker.globals.registry_mirrors='https://docker.1ms.run'
                uci add_list mi_docker.globals.registry_mirrors='https://docker.m.daocloud.io'
                uci add_list mi_docker.globals.registry_mirrors='https://registry-1.docker.io'
                uci commit mi_docker
                echo -e "\n ${C_GREEN}✅ 已恢复推荐加速源！${C_RESET}"
                pause
                ;;
            3)
                while uci -q del mi_docker.globals.registry_mirrors; do :; done
                uci commit mi_docker
                echo -e "\n ${C_YELLOW}💥 已清空所有镜像源配置！${C_RESET}"
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

set_docker_config_menu() {
    while true; do
        clear
        main_line
        print_center "🐳 Docker 全局参数设置" 7
        echo -e "${C_DIM}修改后需要重启 Docker 服务后生效 (部分设置要先解除docker限制)${C_RESET}"
        # 读取当前 UCI 实时状态
        local cur_hosts="$(uci -q get mi_docker.globals.hosts)"
        local cur_api_status="${C_RED}✖"
        echo "$cur_hosts" | grep -q "tcp://" && cur_api_status="${C_GREEN}✔ (2375)"

        local cur_ipv6="$(uci -q get mi_docker.globals.ipv6)"
        [ "$cur_ipv6" = "1" ] && cur_ipv6_txt="${C_GREEN}✔" || cur_ipv6_txt="${C_RED}✖"

        local cur_iptables="$(uci -q get mi_docker.globals.iptables)"
        [ "$cur_iptables" = "1" ] && cur_iptables_txt="${C_GREEN}✔" || cur_iptables_txt="${C_RED}✖"

        local cur_ip6tables="$(uci -q get mi_docker.globals.ip6tables)"
        [ "$cur_ip6tables" = "1" ] && cur_ip6tables_txt="${C_GREEN}✔" || cur_ip6tables_txt="${C_RED}✖"

        local cur_proxy="$(uci -q get mi_docker.globals.proxy_server)"
        [ -z "$cur_proxy" ] && cur_proxy_txt="${C_RED}✖" || cur_proxy_txt="${C_GREEN}$cur_proxy"

        echo -e "   🔹 Remote API Port  : ${cur_api_status}${C_RESET}"
        echo -e "   🔹 Docker IPv6 Net  : ${cur_ipv6_txt}${C_RESET}"
        echo -e "   🔹 iptables  (IPv4) : ${cur_iptables_txt}${C_RESET}"
        echo -e "   🔹 ip6tables (IPv6) : ${cur_ip6tables_txt}${C_RESET}"
        echo -e "   🔹 HTTP/HTTPS Proxy : ${cur_proxy_txt}${C_RESET}"
        sub_line

        echo -e "  ${C_GREEN}1)${C_RESET} ⭐ 一键加载优化推荐配置 (推荐)"
        echo -e "  ${C_GREEN}2)${C_RESET} 🔌 开关 API 远程管理端口"
        echo -e "  ${C_GREEN}3)${C_RESET} 🌐 开关 IPv6 网络支持"
        echo -e "  ${C_GREEN}4)${C_RESET} 🧱 开关 IPv4 防火墙 (iptables)"
        echo -e "  ${C_GREEN}5)${C_RESET} 🧱 开关 IPv6 防火墙 (ip6tables)"
        echo -e "  ${C_GREEN}6)${C_RESET} 🚀 设置 Docker Daemon HTTP/HTTPS 代理"
        echo -e "  ${C_GREEN}7)${C_RESET} 🌐 管理 Docker 镜像加速源"
        sub_line
        echo -e "  ${C_GRAY}0)${C_RESET} 🔙 返回"
        main_line
        printf " 👉 请选择 [${C_BOLD}0-7${C_RESET}]: "
        read dk_choice

        case "$dk_choice" in
            1)
                set_docker_config
                echo -e "\n ${C_GREEN}✅ 已成功加载优化推荐配置！${C_RESET}"
                pause
                ;;
            2)
                # 开关 API 2375
                if echo "$cur_hosts" | grep -q "tcp://"; then
                    while uci -q del mi_docker.globals.hosts; do :; done
                    uci add_list mi_docker.globals.hosts='unix:///var/run/docker.sock'
                    echo -e "\n ${C_GREEN}✅ 已关闭 2375 远程 API 端口！${C_RESET}"
                else
                    while uci -q del mi_docker.globals.hosts; do :; done
                    uci add_list mi_docker.globals.hosts='unix:///var/run/docker.sock'
                    uci add_list mi_docker.globals.hosts='tcp://0.0.0.0:2375'
                    echo -e "\n ${C_GREEN}✅ 已开启 2375 远程 API 端口！${C_RESET}"
                fi
                uci commit mi_docker
                pause
                ;;
            3)
                # Toggle IPv6
                if [ "$cur_ipv6" = "1" ]; then
                    uci set mi_docker.globals.ipv6='0'
                    echo -e "\n ${C_YELLOW}❌ 已关闭 IPv6 支持！${C_RESET}"
                else
                    uci set mi_docker.globals.ipv6='1'
                    uci set mi_docker.globals.fixed_cidr_v6='fd00:172:17::/64'
                    echo -e "\n ${C_GREEN}✅ 已开启 IPv6 支持！${C_RESET}"
                fi
                uci commit mi_docker
                pause
                ;;
            4)
                # Toggle iptables (IPv4)
                if [ "$cur_iptables" = "1" ]; then
                    uci set mi_docker.globals.iptables='0'
                    echo -e "\n ${C_GREEN}🛡️ 已禁用 iptables 修改！${C_RESET}"
                else
                    if ! command -v iptables >/dev/null 2>&1; then
                        echo -e "\n ${C_YELLOW}❗ 系统缺少 iptables 工具，强行开启可能导致 Docker 启动失败！${C_RESET}"
                    fi
                    uci set mi_docker.globals.iptables='1'
                    echo -e "\n ${C_YELLOW}❗ 已允许 Docker 修改宿主机 IPv4 防火墙 (iptables)！${C_RESET}"
                fi
                uci commit mi_docker
                pause
                ;;
            5)
                # Toggle ip6tables (IPv6)
                if [ "$cur_ip6tables" = "1" ]; then
                    uci set mi_docker.globals.ip6tables='0'
                    echo -e "\n ${C_GREEN}🛡️ 已禁用 ip6tables 修改！${C_RESET}"
                else
                    if ! command -v ip6tables >/dev/null 2>&1; then
                        echo -e "\n ${C_YELLOW}❗ 系统缺少 ip6tables 工具，强行开启可能导致 Docker 启动失败！${C_RESET}"
                    fi
                    uci set mi_docker.globals.ip6tables='1'
                    echo -e "\n ${C_GREEN}✅ 已开启 ip6tables 支持！${C_RESET}"
                fi
                uci commit mi_docker
                pause
                ;;
            6)
                # 设置代理
                echo ""
                echo -e " 💡 提示: 输入 HTTP/HTTPS 代理地址 (要求 Docker 23.0+)"
                echo -e "${C_DIM}如: [http://192.168.31.2:7890]，留空回车则置空${C_RESET}"
                printf "请输入代理地址: "
                read user_proxy

                uci set mi_docker.globals.proxy_server="$user_proxy"
                uci commit mi_docker
                echo -e "\n ${C_GREEN}✅ 代理设置更新成功！${C_RESET}"
                pause
                ;;
            7)
                # 子菜单：管理 Docker 镜像源
                manage_docker_mirrors
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

docker_menu() {
    while true; do
        local start=$(mikit_db get "docker")
        local start_str="${C_RED}✖${C_RESET}"
        [ "$start" = "1" ] && start_str="${C_GREEN}✔${C_RESET}"
        clear
        local status="🔴"
        /etc/init.d/mi_docker is_running && status="🟢"
        main_line
        print_center "${C_BOLD}${C_GREEN}🐳 Docker 管理与设置${C_RESET}" 5

        print_center "运行状态: $status    解除限制: $start_str" 9
        print_center "${C_NOR_YELLOW}优先执行(6)解除限制和(2)设置配置，再进行其他操作${C_RESET}" 20
        sub_line
        echo -e "  ${C_GREEN}1)${C_RESET} 🔄 重启 Docker 服务"
        echo -e "  ${C_GREEN}2)${C_RESET} 🔧 设置 Docker 配置"
        echo -e "  ${C_GREEN}3)${C_RESET} 🔝 升级 Docker 版本"
        echo -e "  ${C_GREEN}4)${C_RESET} 🔨 安装 Docker 补丁"
        echo -e "  ${C_GREEN}5)${C_RESET} 📦 安装 Docker Compose"
        echo -e "  ${C_GREEN}6)${C_RESET} 🚀 解除 Docker 限制并加入开机自启"
        sub_line
        echo -e "  ${C_GRAY}0)${C_RESET} 🔙 返回"
        main_line
        printf " 👉 请选择 [${C_BOLD}0-6${C_RESET}]: "
        read docker_choice

        case "$docker_choice" in
            1)
                echo -e "正在重启 Docker..."
                /etc/init.d/mi_docker restart
                echo -e "\n ✅ 重启完成！Docker 服务加载需要点时间"
                pause
                ;;
            2)
                set_docker_config_menu
                ;;
            3)
                upgrade_docker
                pause
                ;;
            4)
                install_docker_patch
                pause
                ;;
            5)
                install_docker_compose
                pause
                ;;
            6)
                read -r -p "是否启用？ (y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    mikit_db set "docker" "1"
                    set_mi_docker
                    echo -e "\n ✅ 已启用"
                else
                    mikit_db set "docker" "0"
                    [ -f /tmp/mi_docker_bak ] && cp /tmp/mi_docker_bak /etc/init.d/mi_docker && chmod +x /etc/init.d/mi_docker
                    echo -e "\n ❌ 已禁用"
                fi
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