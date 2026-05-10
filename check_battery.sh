#!/usr/bin/env bash

TCL_ROOT=
TCL_CMD=

source ./tcl9_linux_common.sh

for path in "${TCL_INSTALL_PATHS[@]}" ; do
    if  [[ -x "$path/bin/tclsh9.0" ]] ; then
        TCL_ROOT="$path"
        TCL_CMD="tclsh9.0"
        break
    fi

    if [[ -x "$path/bin/tclsh90.exe" ]] ; then
        TCL_ROOT="$path"
        TCL_CMD="tclsh90.exe"
        break
    fi
done

if [[ -z "$TCL_ROOT" ]]; then
    printf '错误: 未找到 tcl9.0 运行环境，请先运行 tcl9_linux_install.sh\n'
    exit 1
fi

TCL_BIN_ROOT="${TCL_ROOT}/bin"
TCL_LIB_ROOT="${TCL_ROOT}/lib"
TCL_LD_LIBRARY_PATH="${TCL_ROOT}/lib"

if [[ ":$PATH:" != *":$TCL_BIN_ROOT:"* ]] ; then
    export PATH="$TCL_BIN_ROOT:$PATH"
fi

# 这个结构式一个TCL列表，必须是这种格式
if [[ " $TCLLIBPATH " != *" $TCL_LIB_ROOT "* ]] ; then
    # 如果 TCLLIBPATH 为空，直接赋值；如果不为空，加个空格再拼接
    export TCLLIBPATH="$TCL_LIB_ROOT${TCLLIBPATH:+ $TCLLIBPATH}"
fi

# 只有当 LD_LIBRARY_PATH 里还没这个路径时，我们才在“启动命令时”加上它
if [[ ":$LD_LIBRARY_PATH:" != *":$TCL_LD_LIBRARY_PATH:"* ]] ; then
    export LD_LIBRARY_PATH="$TCL_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

"$TCL_CMD" check_battery.tcl

