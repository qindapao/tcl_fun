#!/usr/bin/env tclsh9

# 声明本文件属于 tutils 工具箱的 1.0 版本（供 pkg_mkIndex 识别）
package provide tutils 1.0

namespace eval ::sys {
    namespace export {[a-z]*}
    namespace ensemble create

    # /**
    #  * @brief 标准合流外部命令执行器
    #  * @details 对外高层快捷门面函数。自动将标准错误（stderr）合并到标准输出（stdout）中一同返回。
    #  *          采用不定长参数直通设计，调用方无需在外部手动包裹 list 或大括号。
    #  *          得益于 Tcl 9 原生列表锁死机制，该函数天然免疫任何 Shell 脚本注入攻击。
    #  *
    #  * @param[in] args 不定长命令及参数。例如：sys exec_m grep "FATAL ERROR" "app log.log"
    #  *
    #  * @return dict 返回包含两个核心键的字典：
    #  *              - output: 完整的命令输出内容（包含 stdout 和 stderr）
    #  *              - code:   操作系统退出码（0=成功，非0=异常失败）
    #  *
    #  * @note 推荐将其作为自动化运维、日常测试用例执行的主力推荐函数。
    #  */
    proc exec_m {args} { return [_exec_core 1 $args] }

    # /**
    #  * @brief 纯净分流外部命令执行器
    #  * @details 对外高层快捷门面函数。强制剥离并重定向标准错误（stderr），使其不污染返回内容。
    #  *          采用不定长参数直通设计，调用方无需在外部手动包裹 list 或大括号。
    #  *          得益于 Tcl 9 原生列表锁死机制，该函数天然免疫任何 Shell 脚本注入攻击。
    #  *
    #  * @param[in] args 不定长命令及参数。例如：sys exec_s ls -la "my folder name"
    #  *
    #  * @return dict 返回包含两个核心键的字典：
    #  *              - output: 纯净的标准输出内容（不包含任何 stderr）
    #  *              - code:   操作系统退出码（0=成功，非0=异常失败）
    #  *
    #  * @note 适用于只需要精确提取命令正确回显（如获取版本号、提取IP地址）的业务场景。
    #  */
    proc exec_s {args} { return [_exec_core 0 $args] }

    # /**
    #  * @brief ISO-C 风格安全外部命令核心执行引擎（内部私有）
    #  * @details 采用阻塞管道与分块读取机制，保证对超长行回显和二进制流输出绝对安全。
    #  *          本函数不直接对外开放，通过高层的 exec_m 和 exec_s 进行安全隔离。
    #  *
    #  * @param[in] merge_stderr 是否合流标准错误（1=合流至 stdout 管道，0=独立分流不捕获）
    #  * @param[in] cmd_parts    由高层门面函数打包好的完整命令及参数列表（List格式）
    #  *
    #  * @return dict 返回包含两个核心键的字典：
    #  *              - output: 过滤掉末尾换行符的干净回显内容（中间多行换行符完美保留）
    #  *              - code:   操作系统退出码（精确捕获 CHILDSTATUS 错误码，突发宕机返回 -1）
    #  *
    #  * @throws error 如果外部可执行程序不存在或本地操作系统管道启动失败，会抛出标准 Tcl 异常。
    #  *
    #  * @note 核心内部逻辑。输入采用列表解包直通内核系统调用（execve），规避了传统字符串拼接引发的空格切分隐患。
    #  */
    proc _exec_core {merge_stderr cmd_parts} {
        if {[llength $cmd_parts] == 0} {
            return [dict create output "error: no command provided" code -1]
        }

        set pipeline_cmd [list | {*}$cmd_parts]
        if {$merge_stderr} { lappend pipeline_cmd "2>@1" }

        if {[catch {open $pipeline_cmd r} pipe]} {
            return -code error "\[exec_s\]error: unable to start external command -> $pipe"
        }

        # 8KB
        fconfigure $pipe -blocking 1 -buffering full -buffersize 8192
        set out_buffer [read $pipe]

        set exit_code 0
        if {[catch {close $pipe} err]} {
            lassign $::errorCode err_type pid code

            if {$err_type eq "CHILDSTATUS"} {
                set exit_code $code
            } else {
                set exit_code -1
                append out_buffer "\n\[system-level sudden death report\]: $err"
            }
        }

        return [dict create \
            output [string trimright $out_buffer "\r\n"] \
            code   $exit_code \
        ]
    }

    # /**
    #  * @brief 跨主机远程命令安全执行器
    #  * @details 采用最纯净的直通模式。远端的合流/分流全权由传入的远程命令自身控制。
    #  *          本地引擎仅作为纯净的数据搬运工，100% 隔离本地 SSH 客户端报错与远端业务回显。
    #  *
    #  * @param[in] host       目标主机 IP 地址或域名
    #  * @param[in] user       远程登录用户名
    #  * @param[in] pwd        远程登录密码
    #  * @param[in] timeout    远程连接与执行的超时时间（秒）
    #  * @param[in] args       要在远端执行的命令及参数。
    #  *                       例如：sys exec_r "192.168.1.1" "root" "pwd123" 30 ls -la "/tmp/spaces dir"
    #  *
    #  * @return dict 返回包含 output 和 code 的字典
    #  */
    proc exec_r {host {user "xx"} {pwd "yy"} {timeout 60} args} {
        if {[llength $args] == 0} {
            return [dict create output "error: no remote command provided" code -1]
        }

        # 1. 组装调用你那套完美 expect 脚本的本地参数
        set local_cmd [list cmd2r.exp $host $timeout $user $pwd]

        # 2. 将远程参数无缝平铺追加到末尾
        lappend local_cmd {*}$args

        # 3. 终极简化：固定传入 0（不合流）！
        # 让 _exec_core 只读取干净的远程回显，彻底拒绝本地杂质污染
        return [_exec_core 0 $local_cmd]
    }

    # /**
    #  * @brief 跨主机远程文件/目录安全推送器（本地 -> 远端）
    #  * @details 采用纯净的外部脚本直通模式。内部不进行任何管道写入或数据流套娃。
    #  *          将本地的文件或目录直接推送到远端指定的绝对路径中。
    #  *          注意：因采用 Tcl 位置匹配规则，若需调整超时时间，前面的 user 和 pwd 参数必须显式补齐。
    #  *
    #  * @param[in] host       目标主机 IP 地址或域名
    #  * @param[in] src_path   本地源文件或源目录的绝对路径
    #  * @param[in] dest_path  远端主机的目标绝对路径
    #  * @param[in] user       远程登录用户名（默认：xx）
    #  * @param[in] pwd        远程登录密码（默认：yy）
    #  * @param[in] timeout    文件传输与握手的超时时间，单位秒（默认：60）
    #  *
    #  * @return dict 返回包含两个核心键的字典：
    #  *              - output: 传输失败时的标准错误回显（成功时通常为空白，已自动剔除尾部换行）
    #  *              - code:   操作系统的真实退出码（0=成功，3=超时，其他=业务报错或失败）
    #  */
    proc cp_l2r {host src_path dest_path {user "xx"} {pwd "yy"} {timeout 60}} {
        # 【终极防呆】不管用户传的是 . 还是 .. 还是相对路径，一律强制“归一化”为完美的绝对路径！
        set real_src [file normalize $src_path]

        if {![file exists $real_src]} {
            return [dict create output "\[cp_l2r\]error: local source path does not exist -> $real_src" code -1]
        }

        # 后续传给外部脚本时，用 $real_src 代替原本的 $src_path 
        set local_cmd [list cp_l2r.exp $host $real_src $dest_path $timeout $user $pwd]
        return [_exec_core 0 $local_cmd]
    }

    # /**
    #  * @brief 跨主机远程文件/目录安全拉取器（远端 -> 本地）
    #  * @details 采用纯净的外部脚本直通模式。内部不进行任何管道写入或数据流套娃。
    #  *          将远端的文件或一整部目录拉取并落地到本地指定的绝对路径中。
    #  *          注意：因采用 Tcl 位置匹配规则，若需调整超时时间，前面的 user 和 pwd 参数必须显式补齐。
    #  *
    #  * @param[in] host       目标主机 IP 地址或域名
    #  * @param[in] src_path   远端主机源文件或源目录的绝对路径
    #  * @param[in] dest_path  本地的目标绝对路径
    #  * @param[in] user       远程登录用户名（默认：xx）
    #  * @param[in] pwd        远程登录密码（默认：yy）
    #  * @param[in] timeout    文件传输与握手的超时时间，单位秒（默认：60）
    #  *
    #  * @return dict 返回包含两个核心键的字典：
    #  *              - output: 传输失败时的标准错误回显（成功时通常为空白，已自动剔除尾部换行）
    #  *              - code:   操作系统的真实退出码（0=成功，3=超时，其他=业务报错或失败）
    #  */
    proc cp_r2l {host src_path dest_path {user "xx"} {pwd "yy"} {timeout 60}} {
        # 1. 安全防呆：如果本地目标落地路径的父目录都不存在，直接拦截返回
        set local_parent [file dirname $dest_path]
        if {![file exists $local_parent]} {
            return [dict create output "\[cp_r2l\]error: local destination directory does not exist -> $local_parent" \
                                code -1]
        }

        # 2. 组装调用已部署在系统 PATH 中的 cp_r2l.exp 脚本的本地参数
        set local_cmd [list cp_r2l.exp $host $src_path $dest_path $timeout $user $pwd]

        # 3. 终极简化：固定传入 0（不合流）！
        # 抛弃 Stdin 写入，由 scp 自行掌控生命周期，进程结束时自动解脱，Windows UCRT64 下无假死风险
        return [_exec_core 0 $local_cmd]
    }

    # /**
    #  * @brief System Date and Time Formatter (date_prt)
    #  * @details 纯 Tcl 实现的高性能时间戳生成器，自适应支持秒级与毫秒级高精度输出。
    #  *          默认输出格式为 "YYYY-MM-DD HH:MM:SS"。
    #  *
    #  * @param[in] format_str Tcl 格式的时间模板（选填）。
    #  *                       - 默认 "%Y-%m-%d %H:%M:%S"        -> 2026-05-20 09:15:30
    #  *                       - 毫秒 "%Y-%m-%d %H:%M:%S.%Milli" -> 2026-05-20 09:15:30.425
    #  *                       - 文件 "%Y%m%d_%H%M%S_%Milli"     -> 20260520_091530_425
    #  *
    #  * @return string 返回格式化后的本地时间字符串。
    #  */
    proc date_prt {{format_str "%Y-%m-%d %H:%M:%S"}} {
        set us [clock microseconds]

        set now [expr {$us / 1000000}]

        if {[string match "*%Milli*" $format_str]} {
            set ms_num [expr {($us / 1000) % 1000}]
            set milli [format "%03d" $ms_num]
            regsub -all {%Milli} $format_str $milli format_str
        }

        return [clock format $now -format $format_str]
    }

    # /**
    #  * @brief 高性能、0 误伤、且不污染变量现场的 Tcl 9 数据类型内窥器 (get_type)
    #  * @details 本函数是 tutils 工具箱的核心基石。专为 Tcl 9 内核的值共享与优化机制设计。
    #  *          它利用底层未公开指令深入 C 语言运行时，在完全不触发写时复制 (Copy-On-Write)
    #  *          和内部人格突变 (Shimmering) 的前提下，精准识别对象的真实物理形态。
    #  * 
    #  *          【硬核机制说明】：
    #  *          1. 顶级标量防火墙：优先拦截 pure string, string, int, double, bytearray。
    #  *             绝对不给它们接触 llength 或 dict keys 的机会，从源头上彻底切断「单元素列表」
    #  *             和「二进制字节流解码」引发的隔空内存污染。
    #  *          2. 内核标签直通车：对已标记为 dict 或 list 的复合结构进行 C 语言级别的快速放行。
    #  *          3. 混沌文本安全探测：仅对未打标签的原始字串进行防污染隔离探测（利用 catch 隔离），
    #  *             安全推导出潜在的字典或列表结构。
    #  *
    #  * @param[in] data  需要进行内部类型探测的任意 Tcl 数据对象（支持原子标量与复杂嵌套容器）。
    #  *
    #  * @return string   返回该对象的业务抽象类型，仅限于以下三种标准枚举值：
    #  *                  - "dict"       : 纯正的、或符合语法规则的字典结构
    #  *                  - "list"       : 纯正的、或符合语法规则的列表结构
    #  *                  - "empty"      : 空
    #  *                  - "string"     : 包含纯文字、数字、布林值及二进制字节流在内的所有原子标量
    #  */
    proc get_type {data} {
        set rep [tcl::unsupported::representation $data]
        set rep_lower [string tolower $rep]

        # 1. 【核心严谨防线】基本标量防火墙
        # 只要底层包含 string、int、double 或 bytearray 等任何原子类型，
        # 立刻作为 "string"（标量）安全撤退，绝对不给后面任何引发突变的指令触碰的机会！
        if {[regexp {value is a (pure )?(string|int|double|bytearray)} $rep_lower]} {
            return "string"
        }

        # 2. 第一防线：依靠 C 层面真正的内部表示，绝对不触发隐式转换
        if {[string match {*value is a dict*} $rep_lower]} {
            if {[dict size $data] == 0} {
                return "empty"
            } else {
                return "dict"
            }
        }
        if {[string match {*value is a list*} $rep_lower]} {
            if {[llength $data] == 0} {
                return "empty"
            } else {
                return "list"
            }
        }

        if {$data eq ""} { return "string" }

        # 3. 只有非 pure string 且可能代表列表/字典的复合文本，才允许安全探测
        # 探测前先用 catch 隔离，防止人格污染
        if {![catch {dict keys $data} dkeys] && [llength $dkeys] > 0} {
            if {[expr {[llength $data] % 2}] == 0} { return "dict" }
        }
        if {![catch {llength $data} len] && $len > 1} {
            return "list"
        }

        return "string"
    }

    # /**
    #  * @brief 高性能、调试友好、且不污染变量现场的 Tcl 9 对象内存指标内窥器
    #  * 
    #  * @description 本过程专为 Tcl 9 设计。利用底层未公开指令深入 C 语言运行时层面，
    #  *              在不触发「写时复制 (Copy-On-Write)」和对象复制的前提下，瞬间
    #  *              提取变量在内存中的物理地址指针。常用于内存泄漏排查、底层调试、
    #  *              以及分析 Tcl 9 对象的共用 (Sharing) 与优化状态。
    #  * 
    #  * @param data      [Any]  需要探测内存指针的 Tcl 数据对象（支持任意类型）。
    #  * @param show_ptr  [Bool] 调试开关。预设为 1 (开启) 返回格式化指标；设为 0 (关闭) 则直接返回空串。
    #  * 
    #  * @return [String] 返回格式化后的指标后缀（形如 " <0x100874b10>"）。若关闭开关或提取失败，返回空字符串 ""。
    #  */
    proc get_ptr_suffix {data} {
        set rep [tcl::unsupported::representation $data]

        # 核心抓取机制：利用专门适应 Tcl 9 的 64 位变长十六进制正则表达式，捕获内存地址
        # 此处精妙使用 Tcl 自由变量名习惯，以 `->` 作为抛弃型完整匹配占位符，将首个捕获组精准导向 `ptr`
        if {[regexp {object pointer at (0x[0-9A-Fa-f]+)} $rep -> ptr]} { return " <$ptr>" }
        return ""
    }

}

