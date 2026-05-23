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
# 构建完成后需要手动将
# /opt/tcl9/bin/ 加入到系统的 PATH 中，在启动的 .bashrc 中加入
# export PATH=${PATH}:/opt/tcl9/bin/

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
    mingw32-make
    mingw32-make install

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
    mingw32-make
    mingw32-make install
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
    # mingw32-make install
    mingw32-make install-libraries
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
    mingw32-make install-libraries
}

# windows 系统最好是把 tk 装上
# 这样我们可以开发GUI程序
clean &&
build_tcl9 &&
install_tcllib &&
build_tk9 &&
install_tklib

