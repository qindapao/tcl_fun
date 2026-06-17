#!/usr/bin/env bash

# Tcl/Tk 下载链接
#   https://www.tcl-lang.org/software/tcltk/download.html
#
# Tcllib 2.0
#   https://www.tcl-lang.org/software/tcllib/
#   tcllib-2.0.tar.gz
#
# Tklib 0.9
#   https://www.tcl-lang.org/software/tklib/
#
# Tcl最强的JSON扩展 rl_json
#   https://github.com/RubyLane/rl_json

BASE_DIR=$(pwd)
TCL_VERSION="tcl9.0.3"
TK_VERSION="tk9.0.3"
PREFIX="/opt/tcl9"

clean ()
{
    rm -rf "$PREFIX"
}

build_tcl9 ()
{
    cd "$BASE_DIR"
    tar xzvf "${TCL_VERSION}-src.tar.gz"
    cd "${TCL_VERSION}/"
    cd win/
    ./configure --prefix="$PREFIX" --enable-64bit
    make
    make install

    cd "$BASE_DIR"
    mkdir -p "${PREFIX}/lib/tcl9.0"
    cp -rf ${TCL_VERSION}/library/* "${PREFIX}/lib/tcl9.0/"
}

build_tk9 ()
{
    cd "$BASE_DIR"
    tar xzvf "${TK_VERSION}-src.tar.gz"
    cd "$TK_VERSION/"
    cd win/
    ./configure --prefix="$PREFIX" \
                --with-tcl=../../${TCL_VERSION}/win \
                --enable-64bit \
                --enable-threads
    make
    make install
}

install_tcllib ()
{
    cd "$BASE_DIR"
    tar xzvf tcllib-2.0.tar.gz
    cd tcllib-2.0/
    rm -rf config.cache

    # 明确告诉它使用哪个 tclsh，这样它会自动识别所有路径
    ./configure --prefix="$PREFIX" --with-tclsh="$PREFIX/bin/tclsh90.exe"

    # 执行安装
    # 这一步会调用它内部的 sak.tcl（Tcllib 的专属管家），能正确处理路径
    # 暂时先不用这个，因为 critcl 对于 Tcl9.0 的适配还不够稳定
    # 虽然 critcl 把库编译成C语言，速度更快，但是还是等下吧
    # make install
    make install-libraries
}

install_tklib ()
{
    cd "$BASE_DIR"
    tar xzvf tklib-0.9.tgz
    cd tklib-0.9/

    # 同样通过 configure 指定路径
    ./configure --prefix="$PREFIX" \
                --with-tclsh="$PREFIX/bin/tclsh90.exe"

    # 因为 Tklib 绝大多数是纯 Tcl/Tk 代码，直接装 library 即可
    make install-libraries
}

install_rl_json ()
{
    # 1. 进入你的源码存放目录并解压
    cd "$BASE_DIR"
    local rl_json_file_name
    rl_json_file_name=$(ls -l | grep "rl_json" | grep "tar.gz" | awk '{print $NF}' | awk -F ".tar.gz" '{print $1}')
    tar xzvf "${rl_json_file_name}.tar.gz"

    # 2. 核心：必须进入解压后的【根目录】，千万不要进 win/ 目录
    cd "${rl_json_file_name}/"

    # 3. 配置环境
    ./configure --prefix="$PREFIX" \
                --with-tcl=../${TCL_VERSION}/win \
                --enable-64bit \
                --enable-threads

    # 配置完成后需要給代码打上 ucrt64专用的补丁才行
    #   teabase/names.c 开头加上下面这样的宏定义
    #   #ifdef _WIN32
    #   #define srandom(x) srand(x)
    #   #define random()   rand()
    #   #endif
    # 并且编译依赖 pandoc
    sed -i '1i\
#ifdef _WIN32\
#define srandom(x) srand(x)\
#define random()   rand()\
#endif
' teabase/names.c

    # 4. 编译与安装
    # 由于 ucrt64 环境中没有 pandoc ,所以我们的安装会失败
    make

    # 我们手动拷贝库和引导文件
    mkdir -p /opt/tcl9/lib/rl_json
    cp -f ./pkgIndex.tcl /opt/tcl9/lib/rl_json/
    cp -f ./tcl9rl_json*.dll /opt/tcl9/lib/rl_json/

    # :TODO: 目前发现只有下面这样的安装是不对的，不清楚原因
    # 下面的只会安装头文件不会安装dll和tcl文件
    make install-libraries
}

mklink_ucrt64 ()
{
    # 编译完成后建立软连接
    ln -sf /opt/tcl9/bin/tclsh90.exe /opt/tcl9/bin/tclsh9
    ln -sf /opt/tcl9/bin/wish90.exe /opt/tcl9/bin/wish9
}

# windows 系统最好是把 tk 装上
# 这样我们可以开发GUI程序
clean &&
build_tcl9 &&
install_tcllib &&
build_tk9 &&
install_tklib &&
install_rl_json &&
mklink_ucrt64

