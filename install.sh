#!/bin/sh
set -e
clear
C_CYAN='\033[36m'
C_DIM='\033[2m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_RESET='\033[0m'

info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${C_GREEN}[INFO]${C_RESET} $1"; }
warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${C_YELLOW}[WARN]${C_RESET} $1"; }
error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${C_RED}[ERROR]${C_RESET} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && error "请使用 root 用户运行此脚本！"

detect_usb_storage() {
    USB=""
    if [ -f /etc/config/disk ]; then
        USB="disk"
        return 0
    fi
    for mount_point in $(awk '$2 ~ /^\/extdisks\/|\/mnt\// {print $2}' /proc/mounts 2>/dev/null); do
        if [ -d "$mount_point" ] && [ "$mount_point" != "/data" ]; then
            if touch "$mount_point/.mikit_test" 2>/dev/null; then
                rm -f "$mount_point/.mikit_test"
                USB="$mount_point"
                break
            fi
        fi
    done
}

main() {
    detect_usb_storage
    local INSTALL_DIR="/data"

    local ROM_FREE_SPACE=$(df -h "/data" 2>/dev/null | awk 'NR==2 {print $4}')
    [ -z "$ROM_FREE_SPACE" ] && ROM_FREE_SPACE="未知"

    while true; do
        clear
        echo -e "${C_CYAN}====================================================${C_RESET}"
        echo -e "           ${C_BOLD}${C_GREEN}MIKIT • Mi-Toolkit 安装程序${C_RESET}"
        echo -e "${C_CYAN}====================================================${C_RESET}"

        if command -v mikit >/dev/null 2>&1; then
            info "检测到已安装 mikit 工具，您可以通过输入 'mikit' 来启动工具箱。"
            read -r -p "👉 按回车键 (Enter) 退出..." dummy
            exit 0
        fi

        echo -e " 📦 系统环境检测："
        if [ "$USB" = "disk" ]; then
            echo -e "    👉 ${C_GREEN}[ 检测到硬盘版 ]${C_RESET} 推荐使用: /userdisk/data"
        elif [ -z "$USB" ]; then
            echo -e "    👉 ${C_YELLOW}[ 检测到未挂载U盘 ]${C_RESET} 空间紧张，建议外挂U盘"
        else
            echo -e "    👉 ${C_GREEN}[ 检测到外置存储 ]${C_RESET} 路径: $USB"
        fi

        echo -e "    👉 系统 ROM (/data) 剩余空间: ${C_YELLOW}$ROM_FREE_SPACE${C_RESET}"
        echo -e " ${C_CYAN}----------------------------------------------------${C_RESET}"

#        echo -e " 请设置插件（Apps）的安装目录："
        case "$USB" in
            /mnt*)
                echo -e "   • USB版推荐: " /mnt/usb-*
                ;;
            /extdisks*)
                echo -e "   • USB版推荐: " /extdisks/sd*
                ;;
            *)
                echo -e "   • USB版推荐: " /mnt/usb-*  /extdisks/sd*
                ;;
                esac
        echo -e "   • 硬盘版推荐: "/userdisk/data
        echo ""
        read -r -p " 请设置插件（Apps）的安装目录: " user_input_apps_dir

        local APPS_DIR="$user_input_apps_dir"
        case "$APPS_DIR" in
            /*)
                ;;
            *)
                echo ""
                warn "路径格式错误！绝对路径必须以斜杠 '/' 开头"
                read -r -p "请按回车键重试..." dummy
                continue
                ;;
        esac
        if mkdir -p "$APPS_DIR" 2>/dev/null && touch "$APPS_DIR/.mikit_test" 2>/dev/null; then
            rm -f "$APPS_DIR/.mikit_test"
            break
        else
            echo ""
            warn "路径 [$APPS_DIR] 无法写入或无效！"
            read -r -p "👉 按回车键重试..." dummy
        fi
    done

    echo -e " ${C_CYAN}----------------------------------------------------${C_RESET}"
    local RAW_URL="https://github.com/Zakkoree/mi-router-tool/releases/latest/download/mikit.tar.gz"
    local TEMP_PKG="/tmp/mikit.tar.gz"
    local DOWNLOAD_SUCCESS=0

    local mirrors_def="
    ghproxy.net|https://ghproxy.net/
    mirror.mikus.ink|https://mirror.mikus.ink/
    gh.996986.xyz|https://gh.996986.xyz/
    wget.la|https://wget.la/
    "

    info "下载 Mikit 程序包..."

    # 1. 优先尝试 GitHub 官方直连地址
    info "正在尝试 GitHub 直连下载..."
    if curl -fsSL --connect-timeout 3 -m 5 "$RAW_URL" -o "$TEMP_PKG" >/dev/null 2>&1 && [ -s "$TEMP_PKG" ]; then
        DOWNLOAD_SUCCESS=1
        info "下载成功！"
    fi

    # 2. 如果直连失败，循环尝试镜像源
    if [ "$DOWNLOAD_SUCCESS" -ne 1 ]; then
        warn "⚠️ 直连失败，正在尝试代理加速镜像..."
        local DOWNLOAD_URL=""
        for item in $mirrors_def; do
            local name="${item%%|*}"
            local url="${item#*|}"

            [ -z "$name" ] || [ -z "$url" ] && continue

            DOWNLOAD_URL="${url}${RAW_URL}"
            info "尝试镜像: $name ..."

            if curl -fsSL --connect-timeout 3 -m 5 "$DOWNLOAD_URL" -o "$TEMP_PKG" >/dev/null 2>&1 && [ -s "$TEMP_PKG" ]; then
                DOWNLOAD_SUCCESS=1
                info "下载成功"
                break
            else
                warn "⚠️ 镜像 [$name] 连接失败，切换下一个..."
                rm -f "$TEMP_PKG"
            fi
        done
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ]; then
        error "❌ 所有下载通道均尝试失败，请检查网络连接！"
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"

    if ! tar -zxf "$TEMP_PKG" -C "$INSTALL_DIR"; then
        error "解压程序包失败！"
        rm -f "$TEMP_PKG"
        exit 1
    fi
    rm -f "$TEMP_PKG"

    info "程序包解压完成"

    mkdir -p "$INSTALL_DIR/mikit/data" "$INSTALL_DIR/mikit/apps" "$INSTALL_DIR/mikit/apps_data" "$APPS_DIR/.mikit_data/apps" "$APPS_DIR/.mikit_data/apps_data"

    sed -i "s|export MIKIT_DIR=.*|export MIKIT_DIR=$INSTALL_DIR/mikit|" "$INSTALL_DIR/mikit/core/init.sh"
    sed -i "s|export MIKIT_DATA_DIR=.*|export MIKIT_DATA_DIR=$APPS_DIR/.mikit_data|" "$INSTALL_DIR/mikit/core/init.sh"

    info "正在初始化配置文件..."
    local CUSTOM_FILE="$INSTALL_DIR/mikit/data/custom_script.sh"

    chmod -R +x "$INSTALL_DIR/mikit"

    local up_count=$(curl -fsSL --connect-timeout 3 -m 10 https://api.counterapi.dev/v2/zakkorees-team-5185/mikit/up -H "Authorization: Bearer ut_e8iyP5XCLm1wOuvRXqva24cmaXT6SwEcHWMbrk8P" 2>/dev/null | grep -o '"up_count":[0-9]*' | awk -F':' '{print $2}')

    local CONFIG_FILE="$INSTALL_DIR/mikit/data/mikit_db"

    cat <<EOF > "$CONFIG_FILE"
config app 'mikit'
  option dnsmasq '1'
  option docker '0'
  option up_count '${up_count:-1}'
EOF

    cat <<EOF > "$CUSTOM_FILE"
#!/bin/sh

# 自定义自启脚本
EOF
    touch "$INSTALL_DIR/mikit/data/mikit_cron_db"

    local MIKIT_HOSTS_FILE="$INSTALL_DIR/mikit/data/dnsmasq_db"
    cat <<EOF > "$MIKIT_HOSTS_FILE"
config dnsmasq
EOF

    "$INSTALL_DIR/mikit/core/init.sh"
    "$INSTALL_DIR/mikit/core/post_install.sh"

    [ -f /etc/profile ] && . /etc/profile >/dev/null 2>&1
    echo ""
    echo -e "${C_CYAN}====================================================${C_RESET}"
    echo -e " ${C_BOLD}${C_GREEN}🎉 MIKIT • Mi-Toolkit 安装成功！${C_RESET}"
    echo -e " ${C_DIM}感谢支持！您是第${C_RESET} ${C_BOLD}${C_YELLOW}${up_count:-1}${C_RESET} ${C_DIM}位使用的小伙伴 ~${C_RESET}"
    echo -e " ${C_CYAN}----------------------------------------------------${C_RESET}"
    echo -e " 📂 ${C_BOLD}工具目录:${C_RESET} ${C_DIM}$INSTALL_DIR/mikit${C_RESET}"
    echo -e " 🔌 ${C_BOLD}插件目录:${C_RESET} ${C_DIM}$APPS_DIR/.mikit_data${C_RESET}"
    echo -e " ${C_CYAN}----------------------------------------------------${C_RESET}"
    echo -e " 🚀 输入 ${C_BOLD}${C_GREEN}mikit${C_RESET} 即可随时启动工具箱"
    echo -e "${C_CYAN}====================================================${C_RESET}"
    echo ""
    read -r -p "👉 按回车键启动..." dummy

    mikit

    exec "${SHELL:-/bin/ash}" -l
}
main