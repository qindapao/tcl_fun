#!/usr/bin/env bash

# 1. 定义安装路径优先级数组
source ./tcl9_linux_common.sh

if which sudo ; then
    TAR_CMD=("sudo" "tar")
    LN_CMD=("sudo" "ln")
else
    TAR_CMD=("tar")
    LN_CMD=("ln")
fi

DEST_FILE="tcl9.tar.gz"
TARGET_DIR=""

# 检查压缩包是否存在
if [[ ! -f "$DEST_FILE" ]] ; then
    printf '错误: 找不到安装包 %s\n' "$DEST_FILE"
    exit 1
fi

# 2. 遍历数组，寻找第一个有权操作的“落脚点”
for path in "${TCL_INSTALL_PATHS[@]}" ; do
    # 如果目录不存在先创建
    if [[ ! -d "$path" ]] ; then
        mkdir -p "$path" 2>/dev/null
    fi

    # 检查该目录是否可写
    if [[ -w "$path/" ]] ; then
        TARGET_DIR="$path/"
        break
    fi
done

# 3. 结果判断
if [[ -z "$TARGET_DIR" ]]  ; then
    printf '错误: 权限不足，无法在预设的路径数组中创建安装目录！\n'
    exit 1
fi

# 4. 执行解压（不带多余逻辑，只管搬运）
printf '>>> 选定目标路径: %s\n' "$TARGET_DIR"
printf '>>> 正在安装...\n'

# -x: 解压, -z: gzip, -f: 文件, -C: 切换到目标目录再解压
"${TAR_CMD[@]}" -xzvf "$DEST_FILE" -C "$TARGET_DIR"
if [[ $? -eq 0 ]] ; then
    printf '>>> 安装完成！位置: %s\n' "$TARGET_DIR"
    
    # 这里要创建一个软链接 -f 作用是强制覆盖，防止第二次执行报错
    "${LN_CMD[@]}" -sf "${TARGET_DIR}/bin/tclsh9.0" "${TARGET_DIR}/bin/tclsh9"
    "${LN_CMD[@]}" -sf "${TARGET_DIR}/bin/wish9.0" "${TARGET_DIR}/bin/wish9"
else
    printf '>>> 安装过程中出现错误！\n'
    exit 1
fi

