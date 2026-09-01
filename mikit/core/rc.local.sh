#!/bin/sh
. /etc/profile
. $MIKIT_DIR/core/env.sh

set_dnsmasq() {
  local status=$(mikit_db get "dnsmasq_status")
  [ "$status" != "1" ] && return 0
  dns_generate_dnsmasq_file
  loginfo "dnsmasq 初始化完成"
}

set_nginx() {
  local status=$(mikit_db get "nginx_status")
  [ "$status" != "1" ] && return 0
  nginx_generate_all_conf
  loginfo "nginx 初始化完成"
}

start_app() {
    local app_list
    app_list="$(mikit_db get "apps")"
    [ -z "$app_list" ] && return 0

    loginfo "正在检查并启动自启应用..."

    local sorted_apps=""
    local enable priority

    for app_id in $app_list; do
        enable="$(mikit_db get "${app_id}.start")"
        [ "$enable" != "1" ] && continue

        priority="$(mikit_db get "${app_id}.priority")"
        case "$priority" in
            ''|*[!0-9]*) priority="99" ;;
        esac

        sorted_apps="${sorted_apps}${priority}:${app_id}
"
    done

    [ -z "$sorted_apps" ] && return 0

    local item cur_priority cur_app_id app_bin
    for item in $(echo "$sorted_apps" | sort -n); do
        [ -z "$item" ] && continue
        cur_priority="${item%%:*}"
        cur_app_id="${item#*:}"
        [ -z "$cur_app_id" ] && continue

        loginfo "[$cur_app_id] 正在启动 (优先级: $cur_priority)..."

        app_bin="$MIKIT_DATA_DIR/apps/$cur_app_id/$cur_app_id"
        if [ -x "$app_bin" ]; then
            if "$app_bin" restart >/dev/null 2>&1; then
                loginfo "[$cur_app_id] 启动成功"
            else
                logwarn "[$cur_app_id] 启动失败，请检查日志"
            fi
        else
            logwarn "[$cur_app_id] 可执行文件不存在或无执行权限: $app_bin"
        fi
    done

    loginfo "自启 App 启动加载完成"
}

set_docker_profile_path() {
  [ ! -f /etc/init.d/mi_docker ] && return 0
  local docker_conf=$(mikit_db get "docker")
  [ "$docker_conf" != "1" ] && return 0

  HOTPLUG_FILE="/etc/hotplug.d/mount/30-mikit_docker"
  ln -sf "$MIKIT_DIR/core/hotplug_docker" $HOTPLUG_FILE

  DEVICE_UUID=$(uci -q get mi_docker.settings.device_uuid)
  [ -n "$DEVICE_UUID" ] && USB_PATH=$(storage dump 2>/dev/null | grep -C3 "${DEVICE_UUID:-invalid-uuid}" | grep target: | awk '{print $2}')
  if [ -z "$USB_PATH" ]; then
    logwarn "set_docker_profile_path 未检测到可用的 USB 设备"
    return 1
  fi
  # 检测并创建/更新“/data/usb”链接
  CURRENT_LINK=$(readlink /data/usb)
  if [ "$CURRENT_LINK" != "$USB_PATH" ]; then
    loginfo "updating symlink: /data/usb -> $USB_PATH"
    rm -f /data/usb && ln -sf "$USB_PATH" /data/usb
  fi
}

BOOT_LOCK="/tmp/lock/mi_toolkit_startup.locked"
[ -f  "$BOOT_LOCK" ] && return 0
touch "$BOOT_LOCK"
set_docker_profile_path

start_app
set_dnsmasq
set_nginx

# 3. 执行用户自定义脚本
loginfo "运行用户自定义脚本"
[ -f $MIKIT_DIR/data/custom_script.sh ] && $MIKIT_DIR/data/custom_script.sh >/dev/null 2>&1