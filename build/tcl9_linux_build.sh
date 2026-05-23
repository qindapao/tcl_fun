#!/usr/bin/env bash

# 环境准备：Linux 下需要 gcc, make 和 libx11-dev (给 Tk 用的)
# Ubuntu/Debian: sudo apt install build-essential libx11-dev
# CentOS/RHEL: sudo yum groupinstall "Development Tools" && yum install libX11-devel
# 编译前确认下编译机中的GLIBC的版本，建议使用 ：`GentOS7/RHEL 7` 的 `2.17`，
#   这样编译出来的兼容性才最好。

BUILD_VERSION=1.000
BASE_DIR=$(pwd)
TCL_VERSION="tcl9.0.3"
TK_VERSION="tk9.0.3"
PREFIX="/opt/tcl9"
TOOL_TCL="/opt/tmptcl9"
TOOL_TCL_BIN="${TOOL_TCL}/bin/tclsh9.0"
CROSS_CC="aarch64-linux-gnu-gcc"

build_tcl9 ()
{
    cd "$BASE_DIR"
    rm -rf "$PREFIX"
    rm -rf "$TCL_VERSION"
    tar xzvf "${TCL_VERSION}-src.tar.gz"
    cd "${TCL_VERSION}/unix"
    # 1. 必须指定 --host=aarch64-linux-gnu
    # 2. 显式传 CC 和 CFLAGS 给 configure，确保它生成的 Makefile 是纯 aarch64 的
    #
    # LDFLAGS="-Wl,-rpath=$PREFIX/lib"
    #   上面这行配置会导致 $PREFIX/lib 的路径被刻进二进制，不太好 
    export TCLSH_PROG="${TOOL_TCL_BIN}"
    ./configure --prefix=$PREFIX \
                --host=aarch64-linux-gnu \
                --enable-64bit \
                --enable-shared \
                TCLSH_PROG=${TOOL_TCL_BIN} \
                CC="$CROSS_CC" \
                CFLAGS="-O2"


    # compile@dggpcompi00001:~/xx/tcl$ diff Makefile Makefile_bak 
    # 2085c2085
    # <                   ( cd $(PKG8_DIR)/$$pkg; $(MAKE); ) || exit $$?; \
    # ---
    # >                   ( cd $(PKG8_DIR)/$$pkg; $(MAKE) "TCLSH_PROG=/opt/tmptcl9/bin/tclsh9.0"; ) || exit $$?; \
    # 2089c2089
    # <                   ( cd $(PKG_DIR)/$$pkg; $(MAKE); ) || exit $$?; \
    # ---
    # >                   ( cd $(PKG_DIR)/$$pkg; $(MAKE) "TCLSH_PROG=/opt/tmptcl9/bin/tclsh9.0"; ) || exit $$?; \
    # 2101c2101
    # <                         "DESTDIR=$(INSTALL_ROOT)"; ) || exit $$?; \
    # ---
    # >                         "DESTDIR=$(INSTALL_ROOT)" "TCLSH_PROG=/opt/tmptcl9/bin/tclsh9.0"; ) || exit $$?; \
    # 2106c2106
    # <                         "DESTDIR=$(INSTALL_ROOT)"; ) || exit $$?; \
    # ---
    # >                         "DESTDIR=$(INSTALL_ROOT)" "TCLSH_PROG=/opt/tmptcl9/bin/tclsh9.0"; ) || exit $$?; \
    # compile@dggpcompi00001:~/xx/tcl$ 

    # 1. 处理 packages 区间
    sed -i '/^packages:/,/^$/ {
        s#\(\$(MAKE)\)\(; ) || exit\)#\1 "TCLSH_PROG='"$TOOL_TCL_BIN"'"\2#g
    }' Makefile

    # 2. 处理 install-packages 区间
    sed -i '/^install-packages:/,/^$/ {
        s#"DESTDIR=\$(INSTALL_ROOT)"#"DESTDIR=$(INSTALL_ROOT)" "TCLSH_PROG='"$TOOL_TCL_BIN"'"#g
    }' Makefile

    make -j$(nproc)
    make install

    # 手动拷贝库目录
    cd "$BASE_DIR"
    mkdir -p "${PREFIX}/lib/tcl9.0"
    cp -rf ${TCL_VERSION}/library/* "${PREFIX}/lib/tcl9.0/"
}

# 必须要先在编译机上面安装一个X86的工具tcl
# 不然后面在编译机上无法安装Tcl的核心也无法安装标准库
build_tcl9_x86 ()
{
    cd "$BASE_DIR"
    rm -rf "$TOOL_TCL"
    rm -rf "$TCL_VERSION"
    tar xzvf "${TCL_VERSION}-src.tar.gz"
    cd "${TCL_VERSION}/unix"
    # Linux 下建议加上 --enable-shared
    ./configure --prefix=$TOOL_TCL --enable-64bit --enable-threads --enable-shared
    make -j$(nproc)
    make install
}

install_tcllib ()
{
    cd "$BASE_DIR"
    # 建议加上清理逻辑，防止多次运行残留
    rm -rf tcllib-2.0
    tar xzvf tcllib-2.0.tar.gz
    cd tcllib-2.0/

    # 重点改进：加上 --with-tcl 指向你刚编好的 ARM 版库目录
    # 这样工具人 tclsh 运行安装程序时，知道要把索引写到哪
    ./configure --prefix="$PREFIX" \
                --with-tclsh="${TOOL_TCL}/bin/tclsh9.0" \
                --with-tcl="$PREFIX/lib"
    
    # 执行安装
    make install-libraries
}

# :TODO: 未调试和验证
build_tk9 ()
{
    cd "$BASE_DIR"
    tar xzvf "${TK_VERSION}-src.tar.gz"
    cd "${TK_VERSION}/unix"

    # 1. 同样必须加 --host
    # 2. 显式指定 CC
    # 3. --with-tcl 最好指向 Tcl 的安装目录(PREFIX/lib)，而不是源码目录，这样更稳
    ./configure --prefix=$PREFIX \
                --host=aarch64-linux-gnu \
                --with-tcl="$PREFIX/lib" \
                --enable-64bit \
                --enable-threads \
                --enable-shared \
                CC="$CROSS_CC" \
                CFLAGS="-O2"

    make -j$(nproc)
    make install
}

# :TODO: 未调试和验证
install_tklib ()
{
    cd "$BASE_DIR"
    tar xzvf tklib-0.9.tar.gz
    cd tklib-0.9/
    # 增加 --with-tk 路径，防止它去系统路径乱找
    ./configure --prefix=$PREFIX \
                --with-tclsh="${TOOL_TCL}/bin/tclsh9.0" \
                --with-tcl="$PREFIX/lib" \
                --with-tk="$PREFIX/lib"
    make install-libraries
}

install_rl_json ()
{
    cd "$BASE_DIR"
    if [ -d "rl_json-v0.17.4" ]; then rm -rf rl_json-v0.17.4; fi
    tar xzvf rl_json-v0.17.4.tar.gz
    cd rl_json-v0.17.4/

    # 因为交叉编译下检测必错，所以直接用 sed 无脑改为 0
    sed -i 's/GETBYTES_SHIM=1/GETBYTES_SHIM=0/g' configure
    sed -i 's/have_getbytes=no/have_getbytes=yes/g' configure

    # 传入 --host 参数和交叉编译器，拦截本机的 gcc
    # 同时使用已经编译好的 ARM64 的 tclConfig.sh ($PREFIX/lib/tclConfig.sh)
    ./configure --prefix="$PREFIX" \
                --with-tcl="$PREFIX/lib" \
                --host=aarch64-linux-gnu \
                --enable-64bit \
                --enable-threads \
                CC="$CROSS_CC" \
                CFLAGS="-O2 -fPIC"

    # 利用编好的 Host 工具 (TOOL_TCL_BIN) 来跑可能需要的脚本
    # 强制让 make 阶段调用 x86 的 tclsh，而编译代码用交叉编译器
    # 加上 "binaries" 参数，让 make 只编译代码，不碰任何文档！
    # 因为我们的环境上没有 pandoc 工具
    make CC="$CROSS_CC" TCLSH_PROG="$TOOL_TCL_BIN" -j$(nproc) binaries

    # 4. 规范化安装（只安装二进制和库，免除 pandoc 文档编译带来的次生灾害）
    make install-binaries
}

clean ()
{
    cd "$BASE_DIR"
    find . -name "*.o" -delete
    find . -name "*.a" -delete
    find . -name "*.so" -delete
    rm -f config.cache tclConfig.sh Makefile
}

after_build ()
{
    cd "$BASE_DIR"
    # -C 后面跟着要进入的目录
    # 最后的 . 代表打包该目录下的所有内容
    aarch64-linux-gnu-strip $PREFIX/bin/tclsh9.0
    aarch64-linux-gnu-strip $PREFIX/lib/libtcl9.0.so
    tar -czvf "$BASE_DIR/tcl9.tar.gz" -C "$PREFIX" .
    sync
    sleep 1
    rm -rf "$PREFIX"
    rm -rf "$TOOL_TCL"

    echo "all work done! please check ${BASE_DIR}/tcl9.tar.gz"
}

# 执行安装
clean &&
build_tcl9_x86 &&
clean &&
build_tcl9 &&
install_tcllib &&
install_rl_json &&
# 因为我们是命令行编程，不需要安装TK
# build_tk9 &&
# install_tklib &&
after_build

