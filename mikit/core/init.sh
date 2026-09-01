#!/bin/sh
export MIKIT_DIR=__MIKIT_DIR__
export MIKIT_DATA_DIR=__MIKIT_DATA_DIR__

. $MIKIT_DIR/core/env.sh

loginfo "初始化脚本启动..."

set_profile() {
    if ! grep -q "# MIKIT_PROFILE" /etc/profile; then
        local profile_content="
# MIKIT_PROFILE
export MIKIT_DIR=\"$MIKIT_DIR\"
export MIKIT_DATA_DIR=\"$MIKIT_DATA_DIR\"
export PATH=\$MIKIT_DIR:\$PATH"

        if [ -f /etc/init.d/mi_docker ]; then
            profile_content="$profile_content
export PATH=\$PATH:/data/usb/mi_docker/docker-binaries
export DOCKER_CONFIG=/data/usb/mi_docker/config/cli-plugins"
        fi

        profile_content="$profile_content
[ -f \$MIKIT_DIR/core/profile ] && . \$MIKIT_DIR/core/profile
# MIKIT_PROFILE_END"
        echo "$profile_content" >> /etc/profile
        loginfo  -s "环境变量加载完成"
    fi
}

lock_ssh_fingerprint() {
    local PERSIST_KEYS_DIR="$MIKIT_DIR/ssh_keys"
    local SYSTEM_KEYS_DIR="/etc/dropbear"

    mkdir -p "$PERSIST_KEYS_DIR"
    mkdir -p "$SYSTEM_KEYS_DIR"

    local found_key=0

    # 持久化目录存在 key，全部恢复/复制到系统目录
    for key in "$PERSIST_KEYS_DIR"/dropbear_*_host_key; do
        [ -f "$key" ] || continue
        local key_name="$(basename "$key")"

        if dropbearkey -y -f "$key" >/dev/null 2>&1; then
            cp -f "$key" "$SYSTEM_KEYS_DIR/$key_name" 2>/dev/null
            chmod 600 "$SYSTEM_KEYS_DIR/$key_name" 2>/dev/null
            found_key=1
        else
            logerr  -s "持久化 SSH 指纹文件损坏: $key_name"
        fi
    done

    if [ "$found_key" -eq 1 ]; then
        loginfo  -s "已从备份恢复 SSH 指纹并完成锁定"
        return 0
    fi

    # 持久化目录无 key，备份系统当前所有的 key 到持久化目录
    for key in "$SYSTEM_KEYS_DIR"/dropbear_*_host_key; do
        [ -f "$key" ] || continue
        local key_name="$(basename "$key")"
        if dropbearkey -y -f "$key" >/dev/null 2>&1; then
            cp -f "$key" "$PERSIST_KEYS_DIR/$key_name" 2>/dev/null
            found_key=1
        fi
    done

    if [ "$found_key" -eq 1 ]; then
        loginfo  -s "已备份当前系统 SSH 指纹到持久化目录"
        return 0
    fi

    logerr  -s "未找到任何有效的 SSH 指纹文件，忽略锁定"
    return 1
}

set_profile

# lock_ssh_fingerprint

loginfo  -s "创建程序核心软链接"
ln -sf "$MIKIT_DIR/core/rc.common" /etc/mk.rc.common
ln -sf "$MIKIT_DIR/core/menu.common" /etc/mk.menu.common

auto_start_check

set_mi_docker

if ! grep -q "# MIKIT_PROFILE" /etc/rc.local; then
  sed -i "1i [ -f $MIKIT_DIR/core/rc.local.sh ] && sh $MIKIT_DIR/core/rc.local.sh start >/dev/null 2>&1 & # MIKIT_PROFILE" /etc/rc.local
  loginfo  -s "已成功将自启钩子写入 /etc/rc.local"
fi
