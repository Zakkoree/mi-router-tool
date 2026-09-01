#!/bin/bash
#$1：GID（任务内部 ID）
#$2：文件数量
#$3：下载完成后的文件或顶层文件夹路径
TARGET="$3"

if [ -n "$TARGET" ] && [ -e "$TARGET" ]; then
    # 赋予读写权限（根据需要调整，例如 664 给文件，775 给目录；或者直接 chmod -R 777）
    chmod -R 777 "$TARGET"
fi