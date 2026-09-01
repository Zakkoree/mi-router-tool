#!/bin/sh
. $MIKIT_DIR/core/uci_mgr.sh
. $MIKIT_DIR/core/cron_mgr.sh
. $MIKIT_DIR/core/dnsmasq_mgr.sh
. $MIKIT_DIR/core/utils.sh
. $MIKIT_DIR/core/docker.sh
. $MIKIT_DIR/core/nginx.sh
. $MIKIT_DIR/core/auto_start_mgr.sh

MIKIT_VER="1.0.0"

_PROJECT_URL="https://github.com/Zakkoree/mi-router-tool"

MIKIT_TMP=$(mktemp -d "/tmp/mikit_tmp.XXXXXX")
# 仅负责清理文件的函数（供 EXIT 触发）
cleanup() {
    [ -n "$MIKIT_TMP" ] && [ -d "$MIKIT_TMP" ] && rm -rf "$MIKIT_TMP"
}

# 仅负责响应 Ctrl+C 的函数（ SIGINT ）
on_ctrl_c() {
    # 立即解除所有 trap 捕获，防止死循环
    trap - INT TERM EXIT
    cleanup
    clear
    exit 130
}

# 绑定信号：EXIT 只做清理，INT 专门处理 Ctrl+C
trap cleanup EXIT
trap on_ctrl_c INT TERM
#MIKIT_DIR="/data/mikit"
#MIKIT_DATA_DIR="/data/mikit/apps"
detect_complete && HARDWARE_COMPLETE=1 || HARDWARE_COMPLETE=0
SYSTEM_ARCH=$(detect_arch)

# 3. 全局应用/插件ID (默认为 global)
APP_ID="mikit"
MIRROR="$(mikit_db get "mirror")"
wanip=$(ubus call network.interface.wan status 2> /dev/null | grep \"address\" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}') || wanip="127.0.0.1"
lanip=$(uci get network.lan.ipaddr 2> /dev/null) || lanip="127.0.0.1"
STORE_LIST="$(mikit_db get "store")"
# ==============================================================================
#  终端 ANSI 颜色与样式配置 (适配 ANSI / UTF-8 终端)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 基础控制与文本样式
# ------------------------------------------------------------------------------
C_RESET="\e[0m"          # 重置所有格式
C_BOLD="\e[1m"           # 加粗 / 高亮
C_DIM="\e[2m"            # 弱化 / 暗色
C_UNDERLINE="\e[4m"      # 下划线
C_BLINK="\e[5m"          # 闪烁

# ------------------------------------------------------------------------------
# 2. 标准颜色 (常规亮度，适合日常文本、低调提示)
# ------------------------------------------------------------------------------
C_BLACK="\e[0;30m"       # 黑色
C_NOR_RED="\e[0;31m"     # 暗红
C_NOR_GREEN="\e[0;32m"   # 暗绿
C_NOR_YELLOW="\e[0;33m"  # 暗黄
C_NOR_BLUE="\e[0;34m"    # 暗蓝
C_NOR_PURPLE="\e[0;35m"  # 紫色 / 品红
C_NOR_CYAN="\e[0;36m"    # 暗青 / 蓝绿
C_GRAY="\e[0;37m"        # 浅灰 / 标准白

# ------------------------------------------------------------------------------
# 3. 高亮颜色 (高对比度，适合重点突出、菜单选项与状态提示)
# ------------------------------------------------------------------------------
C_DARK_GRAY="\e[1;30m"   # 深灰 / 亮黑
C_RED="\e[1;31m"         # 亮红 (用于：错误、未设置、警告、退出选项)
C_GREEN="\e[1;32m"       # 亮绿 (用于：成功、在线状态、主菜单编号)
C_YELLOW="\e[1;33m"      # 亮黄 (用于：应用名称、提示信息、强调项)
C_BLUE="\e[1;34m"        # 亮蓝 (用于：链接、硬件参数、版本号)
C_PURPLE="\e[1;35m"      # 亮紫 (用于：作者标识、次要突出项)
C_CYAN="\e[1;36m"        # 亮青 (用于：主题标题、重要字段)
C_WHITE="\e[1;37m"       # 纯白 (用于：高亮纯白文本)

# ------------------------------------------------------------------------------
# 4. 背景颜色 (配合前景色使用，如 \e[41;37m)
# ------------------------------------------------------------------------------
BG_RED="\e[41m"          # 红底
BG_GREEN="\e[42m"        # 绿底
BG_YELLOW="\e[43m"       # 黄底
BG_BLUE="\e[44m"         # 蓝底

# ------------------------------------------------------------------------------
# 5. UI 框架专属分割线颜色与画线函数
# ------------------------------------------------------------------------------
C_MAIN_LINE="\e[1;34m"   # 主线颜色：亮蓝 (用于外框与重要主分割)
C_SUB_LINE="\e[2;36m"    # 次线颜色：弱化青 (用于内容次级分割，不抢眼)

main_line()    { echo -e "${C_MAIN_LINE}============================================================${C_RESET}"; }
sub_line()     { echo -e "${C_SUB_LINE}------------------------------------------------------------${C_RESET}"; }
dot_line()     { echo -e "${C_SUB_LINE}····························································${C_RESET}"; }
down_line()    { echo -e "${C_SUB_LINE}____________________________________________________________${C_RESET}"; }
cont_line()    { echo -e "${C_SUB_LINE}────────────────────────────────────────────────────────────${C_RESET}"; }
statr_line()   { echo -e "${C_SUB_LINE}************************************************************${C_RESET}"; }
back_line()    { echo -e "${C_SUB_LINE}\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`\`${C_RESET}"; }

