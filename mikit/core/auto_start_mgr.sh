#!/bin/sh

auto_start_install() {
  uci set firewall.startup_script=include
  uci set firewall.startup_script.type='script'
  uci set firewall.startup_script.path="$MIKIT_DIR/core/init.sh"
  uci set firewall.startup_script.enabled='1'
  uci commit firewall
  loginfo "设置开机自启成功"
}

auto_start_check(){
  if uci -q get firewall.startup_script >/dev/null 2>&1; then
    # 如果已经存在，直接更新其路径和状态，避免重复创建
    uci set firewall.startup_script.path="$MIKIT_DIR/core/init.sh"
    uci set firewall.startup_script.enabled='1'
    loginfo "开机自启规则已存在，已更新配置路径"
  else
    # 如果不存在，则全新添加
    uci set firewall.startup_script=include
    uci set firewall.startup_script.type='script'
    uci set firewall.startup_script.path="$MIKIT_DIR/core/init.sh"
    uci set firewall.startup_script.enabled='1'
    loginfo "设置开机自启成功"
  fi
  uci commit firewall
}

auto_start_uninstall() {
  uci delete firewall.startup_script 2>/dev/null
  uci commit firewall
  loginfo "开机自启已关闭"
}